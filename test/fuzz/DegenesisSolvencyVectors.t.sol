// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {SolvencyObligations} from "./helpers/SolvencyObligations.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title DegenesisSolvencyVectors -- packed amounts, the realized sDGNRS schedule and the whale
///        quote, each tied to ETH and token conservation
/// @notice 1. Orders at the encoding extremes (the 0.01 ETH minimum, the 2^38 - 1 unit bound, any
///            second of the day) across slot boundaries: every lane and slot word is exact, the
///            header carries exactly the units and count, claimablePool holds exactly the ETH,
///            the split is exact in wei, and each order settles once at its stored amount.
///         2. A full sale of many small orders: Q follows min(2.5T, R * 2 / 3) on the realized
///            inventory, each day pays near its 0.4Q expectation, the week distributes about
///            86.6B and burns the rest, inventory is conserved exactly, and every sDGNRS award
///            lies on the 5,000-15,000 bps size roll with both ends reached.
///         3. Whale passes at any quantity up to 1,000: the charge is the flat level-0 price per
///            pass, the pools take exactly the charge, the overpay is AFKing, credit is a quarter
///            of the charge, one bonus pass rides on every five, the box entry folds to at most
///            100 boxes of the floored tenth, and backing minus obligations does not move.
contract DegenesisSolvencyVectors is DegenesisHarness {
    address[8] internal buyers;
    bytes32 internal constant SIG_AFKING_FUNDED = keccak256("AfkingFunded(uint32,uint256)");

    function setUp() public override {
        super.setUp();
        _drive(0);
        for (uint256 i; i < 8; ++i) buyers[i] = _player(string.concat("sv-", vm.toString(i)));
        _driveDay(2, 0);
    }

    function _claimablePool() internal view returns (uint256) {
        return game.claimablePoolView();
    }

    function _surplus() internal view returns (int256) {
        return int256(SolvencyObligations.backing(game)) - int256(SolvencyObligations.obligations(game));
    }

    // =====================================================================
    // 1. Encoding extremes across slot boundaries
    // =====================================================================

    /// @notice Seven orders (three slots, the last partly filled) at random extreme amounts and
    ///         times of day.
    function testFuzz_ExtremeLanesConserveAndSettleOnce(uint256 seed) public {
        uint256 n = 7;
        uint256[] memory units = new uint256[](n);
        uint256[] memory secs = new uint256[](n);
        uint32[] memory ids = new uint32[](n);
        uint256 total;
        uint256 pool0 = _claimablePool();
        uint256 dayStart = _dayStart(2);
        for (uint256 i; i < n; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            uint256 mode = r % 4;
            units[i] = mode == 0 ? 100 : mode == 1 ? MAX_UNITS : mode == 2 ? bound(r >> 8, 100, MAX_UNITS)
                : bound(r >> 8, 100, 1_000_000);
            // Strictly later each order, from the open to past the bonus window.
            uint256 t = dayStart + i * 3 hours + (r >> 200) % 3 hours;
            vm.warp(t);
            secs[i] = t - dayStart > BONUS_WINDOW ? BONUS_WINDOW : t - dayStart;
            address p = buyers[i % 3];
            uint256 amount = units[i] * UNIT;
            _seedCredit(p, amount);
            ids[i] = game.walletIdOf(p);
            int256 s0 = _surplus();
            _buy(p, amount);
            assertEq(_surplus(), s0, "a buy moves backing and obligations together");
            total += amount;
        }
        assertEq(_claimablePool() - pool0, total, "claimablePool holds exactly the ETH");
        assertEq(_volumeUnits(1), total / UNIT, "header volume is the units");
        assertEq(_count(1), n, "header count");
        assertFalse(_split(1), "unsplit until the next request");
        for (uint256 i; i < n; ++i) {
            uint256 want = uint256(ids[i]) | (units[i] << 32) | (secs[i] << 70);
            assertEq(_lane(1, i), want, "lane is id | units | seconds");
        }
        for (uint256 w; w < 3; ++w) {
            uint256 word = _orderSlot(1, w * 3);
            uint256 expect;
            for (uint256 k; k < 3 && w * 3 + k < n; ++k) expect |= _lane(1, w * 3 + k) << (85 * k);
            assertEq(word, expect, "slot word is exactly its lanes");
            assertEq(word >> 255, 0, "bit 255 clear");
        }

        uint256 budget0 = _vaultBudget();
        uint256 word_ = uint256(keccak256(abi.encode("extreme-lanes", seed)));
        uint256 q = _refQ(1, _degPool());
        uint256 degPool0 = _degPool();
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word_);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        assertTrue(_split(1), "split at the day-3 request");
        assertEq(_vaultBudget() - budget0, total / 4, "Vault quarter exact");
        // The split's sDGNRS funding event is the first AfkingFunded for sDGNRS after the split.
        uint256 funded;
        bool afterSplit;
        for (uint256 i; i < logs.length && funded == 0; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == SIG_SPLIT) afterSplit = true;
            else if (afterSplit && logs[i].topics[0] == SIG_AFKING_FUNDED && uint32(uint256(logs[i].topics[1])) == SDGNRS_ID) {
                funded = abi.decode(logs[i].data, (uint256));
            }
        }
        assertEq(funded, total / 4, "sDGNRS AFKing quarter exact");
        assertEq(got.length, n, "every order resolved once");
        Res[] memory want_ = _refCohort(1, word_, q);
        uint256 paid;
        for (uint256 i; i < n; ++i) {
            assertEq(got[i].index, i, "in index order");
            assertEq(got[i].amount, units[i] * UNIT, "resolved at its stored amount");
            _assertRes(got[i], want_[i], string.concat("order ", vm.toString(i)));
            paid += got[i].dgnrs;
        }
        assertLe(paid, q * 3 / 2, "within L");
        assertEq(degPool0 - _degPool(), paid, "inventory fell by exactly the paid sDGNRS");
        assertEq(_closed(), 1, "closed");
    }

    // =====================================================================
    // 2. The realized schedule over a full sale
    // =====================================================================

    struct Week {
        uint256[8] q;
        uint256[8] paid;
        uint256[8] v;
        uint256 burned;
        uint256 minMult;
        uint256 maxMult;
        uint256 winners;
        uint256 flipSide;
        uint256 wwxrp;
        uint256 orders;
    }

    /// @notice 200 orders a day for seven days.
    function test_RealizedScheduleAndSizeRoll() public {
        for (uint256 i; i < 8; ++i) _earnCredit(buyers[i], 60 ether);
        Week memory wk;
        wk.minMult = type(uint256).max;
        vm.recordLogs();
        for (uint256 c = 1; c <= 7; ++c) {
            uint24 d = _dayOf(c);
            if (c > 1) _driveDay(d, 0);
            uint256 start = _dayStart(d) + 2 hours;
            for (uint256 i; i < 200; ++i) {
                vm.warp(start + i * 6 minutes);
                _buy(buyers[i % 8], 0.01 ether + (i % 9) * 0.0037 ether + (i % 4) * 0.01 ether);
            }
            wk.v[c] = _volumeUnits(c);
        }
        _driveToClose(_dayOf(7) + 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 inventory = 100_000_000_000 * 1e12;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 t = logs[i].topics[0];
            if (t == SIG_PRICED) {
                uint256 c = uint256(logs[i].topics[1]);
                (uint256 volume, uint256 qBudget,) = abi.decode(logs[i].data, (uint256, uint256, uint24));
                assertEq(volume, wk.v[c] * UNIT, "priced at the sealed V");
                assertEq(qBudget, _refQ(c, inventory), "Q = min(2.5T, R*2/3) on the realized inventory");
                wk.q[c] = qBudget;
            } else if (t == SIG_RESOLVED) {
                (uint8 day,, uint256 amount, uint256 flip, uint256 dgnrs, uint256 wwxrp, uint32 np, uint32 hp) =
                    abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256, uint256, uint32, uint32));
                ++wk.orders;
                inventory -= dgnrs;
                wk.paid[day] += dgnrs;
                if (wwxrp != 0) ++wk.wwxrp;
                if (flip != 0 || np != 0 || hp != 0) ++wk.flipSide;
                if (dgnrs != 0) {
                    ++wk.winners;
                    // floor(x Q m / (V 1e4)) = dgnrs  =>  m in [dgnrs V 1e4 / (x Q), (dgnrs + 1) V 1e4 / (x Q))
                    uint256 xq = (amount / UNIT) * wk.q[day];
                    uint256 lo = dgnrs * wk.v[day] * 10_000 / xq;
                    uint256 hi = ((dgnrs + 1) * wk.v[day] * 10_000 - 1) / xq;
                    assertLe(lo, 15_000, "size roll above 15,000 bps");
                    assertGe(hi, 5000, "size roll below 5,000 bps");
                    if (lo < wk.minMult) wk.minMult = lo;
                    if (hi > wk.maxMult) wk.maxMult = hi;
                }
            } else if (t == SIG_BURNED) {
                wk.burned += abi.decode(logs[i].data, (uint256));
                inventory -= abi.decode(logs[i].data, (uint256));
            }
        }
        assertEq(wk.orders, 1400, "every order resolved once");
        assertEq(inventory, 0, "nothing left after the burn");
        assertEq(_degPool(), 0, "pool empty");
        uint256 sum;
        for (uint256 c = 1; c <= 7; ++c) {
            sum += wk.paid[c];
            assertLe(wk.paid[c], wk.q[c] * 3 / 2, "within L");
            // 200 orders: the day's paid sits within 30% of 0.4Q (about 3.3 standard deviations).
            assertApproxEqRel(wk.paid[c], wk.q[c] * 2 / 5, 0.3e18, "day paid near 0.4Q");
        }
        assertEq(sum + wk.burned, 100_000_000_000 * 1e12, "paid + burned is the whole 100B inventory");
        assertApproxEqRel(sum, 86_600_000_000 * 1e12, 0.08e18, "about 86.6B distributed");
        assertApproxEqRel(wk.burned, 13_400_000_000 * 1e12, 0.5e18, "about 13.4B burned");
        assertLt(wk.minMult, 5300, "low end of the size roll reached");
        assertGt(wk.maxMult, 14_700, "high end of the size roll reached");
        // 40% sDGNRS; the other 60% pay FLIP value or, for a sub-pass or sub-FLIP result and the
        // 10% WWXRP category, the WWXRP consolation. Small orders on the pass side often round
        // to zero passes (Bernoulli, EV-preserving) and console, so FLIP value alone is under 50%.
        assertApproxEqRel(wk.winners, 560, 0.15e18, "about 40% sDGNRS");
        assertEq(wk.winners + wk.flipSide + wk.wwxrp, 1400, "exactly one outcome per order");
        assertGe(wk.wwxrp, 140 * 85 / 100, "at least the WWXRP category consoles");
        emit log_named_uint("FLIP-valued outcomes", wk.flipSide);
        emit log_named_uint("WWXRP outcomes", wk.wwxrp);
        emit log_named_uint("week paid (whole sDGNRS)", sum / 1e12);
        emit log_named_uint("week burned (whole sDGNRS)", wk.burned / 1e12);
        for (uint256 c = 1; c <= 7; ++c) emit log_named_uint(string.concat("day ", vm.toString(c), " paid"), wk.paid[c] / 1e12);
    }

    // =====================================================================
    // 3. Whale quote up to 1,000 passes
    // =====================================================================

    uint256 internal constant WHALE_EARLY = 2.4 ether;

    function _pools() internal view returns (uint256) {
        (uint256 pn, uint256 pf) = SolvencyObligations.pendingPools(game);
        return game.nextPrizePoolView() + game.futurePrizePoolView() + game.currentPrizePoolView() + pn + pf;
    }

    function testFuzz_WhaleQuoteChargedExactly(uint256 q) public {
        q = bound(q, 1, 1000);
        address w = _player(string.concat("whale-", vm.toString(q)));
        uint256 value = q * 4 ether;
        vm.deal(w, value);
        uint256 pools0 = _pools();
        uint256 claimable0 = _claimablePool();
        int256 s0 = _surplus();
        vm.prank(w);
        game.purchaseWhalePass{value: value}(0, q, bytes32(0));
        uint256 charged = value - game.afkingFundingOf(w);
        assertEq(charged, q * WHALE_EARLY, "flat level-0 price per pass");
        assertEq(_pools() - pools0, charged, "the pools take exactly the charge");
        assertEq(_claimablePool() - claimable0, value - charged, "the overpay is AFKing inside claimablePool");
        assertEq(game.degenesisCreditOf(w), charged / 4, "credit is a quarter of the charge");
        assertEq(_surplus(), s0, "backing minus obligations unchanged");
        assertEq(game.entriesOwedView(5, w), 20 * (q + q / 5), "one bonus pass per five, 20 entries a level");
        uint48 b = RecyclingState.writeBuffer(address(game));
        uint256 e = RecyclingState.boxEntry(address(game), b, RecyclingState.boxCount(address(game), b) - 1);
        uint256 boxes = q > 100 ? 100 : q;
        assertEq(BoxOrderLib.boId(e), game.walletIdOf(w), "box entry is the buyer's");
        assertEq(BoxOrderLib.boCount(e), boxes, "folds to at most 100 boxes");
        assertEq(BoxOrderLib.boUnits(e), charged / 10 / boxes / 0.001 ether, "floored tenth per box");
    }

    function test_WhaleQuantityAboveThousandReverts() public {
        address w = _player("whale-1001");
        vm.deal(w, 5000 ether);
        vm.prank(w);
        vm.expectRevert();
        game.purchaseWhalePass{value: 5000 ether}(0, 1001, bytes32(0));
        vm.prank(w);
        game.purchaseWhalePass{value: 2400 ether}(0, 1000, bytes32(0));
        assertEq(game.afkingFundingOf(w), 0, "1,000 passes at exactly the quote");
        assertEq(game.entriesOwedView(5, w), 20 * 1200, "1,000 passes carry 200 bonus passes");
    }
}
