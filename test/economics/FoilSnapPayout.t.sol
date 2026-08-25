// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title FoilSnapPayout — the foil match payout ignores the level's snap exponent
/// @notice A thanos declaration multiplies the foil pack's PRICE by 2^s and stops there:
///         no foil payout scales with the exponent, so on a thanos level the pack is
///         simply bad value. That is the ruling, and this pins both halves of it — the
///         price doubles, the match bonus does not.
/// @dev Differential, not absolute. One scenario is driven to the point where real foil
///      matches are claimable, then the SAME claims are settled twice from one snapshot —
///      once at snapShift = 0 and once at snapShift = 1. Everything the payout reads (the
///      frozen boost / activity score / derived lines / sealed draws / tier / ROI) is
///      bit-identical across the two settlements, so if the exponent leaked into any lane
///      it would be the only term that moved. Every lane must come out equal.
///
///      Settling across a shift is the exact shape the ruling exists to defuse: a claim
///      can land arbitrarily later than its buy, and a live `_snapShiftFor` read hands
///      every past level whatever exponent the newest declaration committed — so a claim
///      parked across a commit would have paid 2^(new - old) times its face. The test
///      constructs that straddle deliberately and asserts nothing moves.
contract FoilSnapPayout is DeployProtocol {
    uint256 private _lastFulfilledReqId;

    uint256 private constant FOIL_BUYERS = 6;
    uint256 private constant TICKET_BUYERS = 6;

    /// @dev Driving parameters cloned from FoilPackEV's test_foilEV_N30 — same buyer
    ///      addresses, same cohort sizes and order, same whale cadence, same VRF word
    ///      sequence, same day count. RNG here is a pure function of that trajectory, so
    ///      reusing it inherits a fixture already known to surface real foil matches
    ///      (13 at that seed). A bespoke seed produced zero and the guard below caught it.
    uint256 private constant PURCHASE_DAYS = 30;
    uint256 private constant RUN_DAYS = PURCHASE_DAYS + 50;

    /// @dev snapShift is a uint8 at slot 14, byte 7 — packed with ticketCursor (bytes 0-3)
    ///      and ticketLevel (bytes 4-6). Read from scripts/layout/golden/DegenerusGame.json.
    ///      The poke is read-modify-write so it cannot clobber its slot-mates, the storage
    ///      layout oracle fails the build if the field moves, and the price test below
    ///      proves the poke still lands. That proof is load-bearing: the payout property
    ///      is now an EQUALITY, which a poke that quietly stopped writing would satisfy
    ///      vacuously. The price test is what keeps the pair honest.
    uint256 private constant SNAP_SLOT = 14;
    uint256 private constant SNAP_BYTE = 7;

    address[FOIL_BUYERS] private _fb;
    uint24 private _buyDay;
    uint24 private _endDay;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Cycle driving (mirrors FoilPackEV: a benign "nothing to do" tick is tolerated)
    // ──────────────────────────────────────────────────────────────────────

    function _advance() internal {
        try game.advanceGame() {} catch {}
    }

    function _completeDay(uint256 vrfWord) internal {
        _advance();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            try mockVRF.fulfillRandomWords(reqId, vrfWord == 0 ? 1 : vrfWord) {} catch {}
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            _advance();
        }
    }

    function _seed(uint256 a, uint256 b) internal pure returns (uint256 w) {
        w = uint256(keccak256(abi.encode("foilEV", a, b)));
        if (w == 0) w = 1;
    }

    /// @dev Read-modify-write so ticketCursor / ticketLevel in the same slot survive.
    function _forceSnapShift(uint8 s) internal {
        bytes32 slot = bytes32(SNAP_SLOT);
        uint256 v = uint256(vm.load(address(game), slot));
        v &= ~(uint256(0xff) << (SNAP_BYTE * 8));
        v |= uint256(s) << (SNAP_BYTE * 8);
        vm.store(address(game), slot, bytes32(v));
    }

    // ──────────────────────────────────────────────────────────────────────
    // Fixture: buy foil packs at shift 0, then drive the cycle so draws seal
    // ──────────────────────────────────────────────────────────────────────

    function _buyAndDrive() internal {
        uint24 lvl = game.level();
        uint256 priceWei = PriceLookupLib.priceForLevel(lvl + 1);
        uint256 foilCost = 10 * priceWei; // FOIL_PACK_TICKETS = 10
        uint256 ticketQty = (foilCost * 4 * 100) / priceWei;

        uint256 bought;
        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            _fb[i] = makeAddr(string(abi.encodePacked("foil", vm.toString(i))));
            vm.deal(_fb[i], 1_000 ether);
            vm.prank(_fb[i]);
            try game.purchase{value: foilCost}(
                _fb[i], 0, 0, bytes32(0), MintPaymentKind.DirectEth, true
            ) {
                bought++;
            } catch {}
        }
        emit log_named_uint("foil packs bought", bought);
        // The ticket cohort is part of the cloned trajectory: it moves the pools and the
        // entry population, so dropping it would change every downstream draw.
        for (uint256 i = 0; i < TICKET_BUYERS; i++) {
            address t = makeAddr(string(abi.encodePacked("tkt", vm.toString(i))));
            vm.deal(t, 1_000 ether);
            vm.prank(t);
            try game.purchase{value: foilCost}(
                t, ticketQty, 0, bytes32(0), MintPaymentKind.DirectEth, false
            ) {} catch {}
        }

        _buyDay = game.currentDayView();

        address whale = makeAddr("whale");
        vm.deal(whale, 1_000_000 ether);
        // Warp arithmetic MUST read vm.getBlockTimestamp(), not block.timestamp: under this
        // repo's via-IR build the optimizer treats TIMESTAMP as tx-invariant and CSEs it, so
        // chained `vm.warp(block.timestamp + 1 days)` calls all land on the SAME timestamp —
        // 80 iterations advanced the clock by one day and the fixture silently produced zero
        // claimable matches. The cheatcode read is a staticcall and is never folded.
        for (uint256 d = 0; d < RUN_DAYS; d++) {
            if (!game.jackpotPhase()) {
                uint256 pw = PriceLookupLib.priceForLevel(game.level() + 1);
                vm.prank(whale);
                try game.purchase{value: 50 * pw}(
                    whale, 50 * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false
                ) {} catch {}
            }
            _completeDay(_seed(PURCHASE_DAYS, d));
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        _endDay = game.currentDayView();

        uint256 worded;
        for (uint24 day = _buyDay + 1; day <= _endDay; day++) {
            if (game.rngWordForDay(day) != 0) worded++;
        }
        emit log_named_uint("buyDay", _buyDay);
        emit log_named_uint("endDay", _endDay);
        emit log_named_uint("days with a sealed word in window", worded);
        emit log_named_uint("end level", game.level());
    }

    function _tally() internal view returns (uint256 eth, uint256 flip, uint256 wx) {
        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            eth += game.claimableWinningsOf(_fb[i]);
            // The FLIP lane is COINFLIP STAKE, not wallet FLIP: every foil FLIP award ships
            // through `coinflip.creditFlip` (DegenerusGameFoilPackModule:601/858/1179), and this
            // protocol never wallet-mints an award. Reading `coin.balanceOf` here measured a lane
            // the payout does not use, so it was pinned at zero and the non-vacuity guard below
            // fired ("re-seed the run") no matter which draw was replayed — 30 foil buyers still
            // produced zero. Re-seeding was never the remedy; reading the right lane is.
            flip += coinflip.coinflipAmount(_fb[i]);
            wx += wwxrp.balanceOf(_fb[i]);
        }
    }

    /// @dev Settle every claimable (buyer, day, ticketIndex, drawKind) tuple and return the
    ///      value each lane produced as a DELTA over the pre-claim tally. Deltas matter: a
    ///      foil buyer's 16 jackpot entries can win a daily jackpot and the purchase itself
    ///      can complete a quest, so the standing balances carry a non-match baseline that
    ///      would otherwise swamp the comparison. The baseline is identical across both
    ///      settlements (they share one snapshot), so differencing it out is exact.
    function _claimAll()
        internal
        returns (uint256 ethOut, uint256 flipOut, uint256 wwxrpOut, uint256 claims)
    {
        (uint256 eth0, uint256 flip0, uint256 wx0) = _tally();

        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            for (uint24 day = _buyDay + 1; day <= _endDay; day++) {
                if (game.rngWordForDay(day) == 0) continue;
                for (uint256 ti = 0; ti < 4; ti++) {
                    for (uint8 dk = 0; dk < 2; dk++) {
                        try game.claimFoilMatch(_fb[i], day, ti, dk) {
                            claims++;
                        } catch {}
                    }
                }
            }
        }

        (uint256 eth1, uint256 flip1, uint256 wx1) = _tally();
        ethOut = eth1 - eth0;
        flipOut = flip1 - flip0;
        wwxrpOut = wx1 - wx0;
    }

    // ──────────────────────────────────────────────────────────────────────
    // The property
    // ──────────────────────────────────────────────────────────────────────

    function test_matchPayoutIgnoresSnapExponent() public {
        _buyAndDrive();

        uint256 snap = vm.snapshotState();

        (uint256 eth0, uint256 flip0, uint256 wx0, uint256 claims0) = _claimAll();
        assertGt(claims0, 0, "fixture produced no claimable foil match - re-seed the run");
        assertGt(flip0, 0, "fixture produced no FLIP-lane match - re-seed the run");

        vm.revertToState(snap);
        _forceSnapShift(1);

        (uint256 eth1, uint256 flip1, uint256 wx1, uint256 claims1) = _claimAll();

        emit log_named_uint("claims settled (each run)", claims0);
        emit log_named_uint("FLIP payout at shift 0", flip0);
        emit log_named_uint("FLIP payout at shift 1", flip1);
        emit log_named_uint("ETH payout at shift 0", eth0);
        emit log_named_uint("ETH payout at shift 1", eth1);

        // Identical matches settle either way: the shift touches neither eligibility nor
        // magnitude.
        assertEq(claims1, claims0, "shift changed which tuples are claimable");

        // Every lane is bit-equal, not approximately so. The two settlements replay one
        // snapshot through the same code with the same inputs, so a difference of a single
        // wei anywhere means an exponent leaked back into a face amount.
        assertEq(flip1, flip0, "FLIP match payout moved with 2^s");
        assertEq(wx1, wx0, "WWXRP match payout moved with 2^s");
        assertEq(eth1, eth0, "ETH match payout moved with 2^s");
    }

    /// @dev The other half of the ruling, and the guard that keeps the equality above from
    ///      passing vacuously: the poke reaches the SAME `_snapShiftFor` the buy path reads,
    ///      proven through production code rather than by re-reading storage. At shift 1 a
    ///      pack costs 2x, so the unshifted price must no longer cover a DirectEth buy.
    function test_snapShiftDoublesFoilPrice() public {
        uint24 lvl = game.level();
        uint256 baseCost = 10 * PriceLookupLib.priceForLevel(lvl + 1);

        _forceSnapShift(1);

        address a = makeAddr("fsnapPriceA");
        vm.deal(a, 1_000 ether);
        vm.prank(a);
        // Insolvent: 1x no longer covers the shifted quote, DirectEth forbids the claimable
        // tier, and this fresh actor has no prepaid afking for the waterfall's last tier to
        // draw. Selector-pinned so an unrelated revert cannot make this pass by accident.
        vm.expectRevert(bytes4(keccak256("Insolvent()")));
        game.purchase{value: baseCost}(a, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);

        address b = makeAddr("fsnapPriceB");
        vm.deal(b, 1_000 ether);
        vm.prank(b);
        game.purchase{value: 2 * baseCost}(b, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
    }
}
