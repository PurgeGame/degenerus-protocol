// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @dev The production jackpot module in its own storage, plus seeders and the two Game reads the
///      real CrapsBattle makes back into the GAME address (extsload, playerActivityScore). NO
///      production logic is overridden.
contract CoinDrawHarness is DegenerusGameJackpotModule, BucketSeed {
    /// @dev Mirror of `_calcDailyCoinBudget` solved for the pool at storage level 0 (0.01 ETH):
    ///      budget = pool * 1000 / (0.01 * 400) = pool * 250.
    function seedBudgetFor(uint24 lvl, uint256 coinBudget) external {
        levelPrizePool[lvl - 1] = (coinBudget * PriceLookupLib.priceForLevel(level) * 400) / PRICE_COIN_UNIT;
    }

    function coinBudgetOf(uint24 lvl) external view returns (uint256) {
        return (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (PriceLookupLib.priceForLevel(level) * 400);
    }

    /// @dev Every trait byte gets `count` distinct holders, so every pull resolves a winner.
    function seedAllTraits(uint24 lvl, uint256 count) external {
        for (uint256 t; t < 256; ++t) {
            for (uint256 i; i < count; ++i) {
                _seedBucket(lvl, uint8(t), address(uint160((t << 32) | (i + 1))), 1);
            }
        }
    }

    /// @dev Only quadrant `q`'s 64 trait bytes get holders: pulls on the other quadrants miss.
    function seedQuadrant(uint24 lvl, uint256 q, uint256 count) external {
        for (uint256 t = q * 64; t < q * 64 + 64; ++t) {
            for (uint256 i; i < count; ++i) {
                _seedBucket(lvl, uint8(t), address(uint160((t << 32) | (i + 1))), 1);
            }
        }
    }

    /// @dev Every trait byte held by `who` alone.
    function seedAllTraitsTo(uint24 lvl, address who) external {
        for (uint256 t; t < 256; ++t) _seedBucket(lvl, uint8(t), who, 1);
    }

    function seedFarQueue(uint24 lvl, uint256 count, uint160 base) external {
        for (uint256 i; i < count; ++i) {
            _tqAppend(
                _tqFarFutureKey(lvl),
                uint32(_registerEntryOwner(address(base + uint160(i + 1)), lvl) >> OWNER_IDX_SHIFT)
            );
        }
    }

    function passValue() external pure returns (uint256) {
        return NORMAL_DAY_PASS_VALUE;
    }

    function today() external view returns (uint24) {
        return _simulatedDayIndex();
    }

    /// @dev The real CrapsBattle reads the Game's storage (daily words) through this.
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    function playerActivityScore(address) external pure returns (uint256) {
        return 0;
    }
}

/// @dev Records every FLIP credit that crosses the boundary.
contract SeatCoinflipDouble {
    address[] public players;
    uint256[] public amounts;
    uint256 public batches;
    uint256 public total;

    function creditFlipBatch(address[] calldata p, uint256[] calldata a) external {
        for (uint256 i; i < p.length; ++i) {
            if (p[i] != address(0) && a[i] != 0) {
                players.push(p[i]);
                amounts.push(a[i]);
                total += a[i];
            }
        }
        ++batches;
    }

    function count() external view returns (uint256) {
        return players.length;
    }

    function amountOf(address who) external view returns (uint256 sum) {
        for (uint256 i; i < players.length; ++i) {
            if (players[i] == who) sum += amounts[i];
        }
    }
}

/// @dev The table's double: a raw slot store the Game vets claims against, and the two seat
///      doors, each recording a code (deliverPasses as kind 2, count one).
contract SeatCrapsDouble {
    mapping(bytes32 => bytes32) public slots;
    uint256[] public codes;

    function setSlot(bytes32 k, bytes32 v) external {
        slots[k] = v;
    }

    function extsload(bytes32 k) external view returns (bytes32) {
        return slots[k];
    }

    mapping(address => bool) public claimed;

    function setClaimed(address p) external {
        claimed[p] = true;
    }

    /// @dev A whole-day gift is always one banked normal pass.
    function creditPasses(address p, uint32 normal, uint32 high) external returns (uint32) {
        require(normal == 1 && high == 0, "a day gift is one normal pass");
        passes[p] += normal;
        ++passCalls;
        return normal;
    }

    uint256 public passCalls;

    function vaultComp(uint256 code) external returns (uint256) {
        codes.push(code);
        return 1;
    }

    mapping(address => uint256) public passes;

    function codeCount() external view returns (uint256) {
        return codes.length;
    }
}

/// @title CoinDrawCrapsSeats — every coin draw's craps half, proven on the live module
/// @notice Half the budget seats up to 25 winners on TOMORROW (2,400 FLIP an opener seat, and
///         whatever is left upgrades seats to the whole day at 20,400 each); the rest plus the
///         craps half's leftover pays up to 25 equal whole-100-FLIP coin shares. A winner Craps
///         refuses is paid its seat's value in FLIP.
contract CoinDrawCrapsSeatsTest is Test {
    CoinDrawHarness internal h;
    SeatCoinflipDouble internal coinflip;
    SeatCrapsDouble internal craps;

    uint24 internal constant LVL = 1;
    uint256 internal constant WORD = uint256(keccak256("coin-draw-seat-word"));
    uint256 internal constant UNIT = 100 ether;
    uint256 internal constant SEAT = 2_400 ether;
    uint256 internal P; // NORMAL_DAY_PASS_VALUE
    uint256 internal UPGRADE;

    bytes32 internal constant FLIP_WIN_SIG = keccak256("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
    bytes32 internal constant FAR_WIN_SIG = keccak256("FarFutureFlipJackpotWinner(address,uint24,uint24,uint256)");
    bytes32 internal constant CRAPS_WIN_SIG = keccak256("CoinDrawCrapsWin(address,uint24,bool,bool)");

    function setUp() public {
        vm.warp((uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 5) * 1 days + 82_620 + 1 hours);
        h = new CoinDrawHarness();
        P = h.passValue();
        UPGRADE = P - SEAT;
        vm.etch(ContractAddresses.COINFLIP, address(new SeatCoinflipDouble()).code);
        vm.etch(ContractAddresses.CRAPS, address(new SeatCrapsDouble()).code);
        coinflip = SeatCoinflipDouble(ContractAddresses.COINFLIP);
        craps = SeatCrapsDouble(ContractAddresses.CRAPS);
    }

    // ── Mirror of the plan ─────────────────────────────────────────────────

    function _pulls(uint256 b) internal pure returns (uint256 p) {
        p = (b / 2) / SEAT;
        if (p > 25) p = 25;
    }

    function _plan(uint256 b, uint256 n) internal view returns (uint256 days_, uint256 amount, uint256 cap) {
        uint256 left = b / 2 - n * SEAT;
        days_ = left / UPGRADE;
        if (days_ > n) days_ = n;
        uint256 units = (b - n * SEAT - days_ * UPGRADE) / UNIT;
        cap = units < 25 ? units : 25;
        if (cap != 0) amount = (units / cap) * UNIT;
    }

    /// @dev Give `who` a claim on tomorrow in the double, at the slot the Game reads.
    function _claim(address who) internal {
        bytes32 dayClaims = keccak256(abi.encode((uint256(h.today()) + 1) * 8, uint256(8)));
        craps.setSlot(keccak256(abi.encode(who, dayClaims)), bytes32(uint256(1)));
        craps.setClaimed(who);
    }

    /// @dev The `i`th craps winner the Game logged (emitter-filtered).
    function _crapsWinner(Vm.Log[] memory logs, uint256 i) internal pure returns (bytes32) {
        uint256 k;
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].topics[0] != CRAPS_WIN_SIG || logs[j].emitter != ContractAddresses.GAME) continue;
            if (k++ == i) return logs[j].topics[1];
        }
        revert("no such craps winner");
    }

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) ++n;
        }
    }

    function _runTrait() internal returns (Vm.Log[] memory logs) {
        vm.recordLogs();
        h.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        logs = vm.getRecordedLogs();
    }

    // ── The split ──────────────────────────────────────────────────────────

    /// @dev The worked table: seat count, full-day count, coin share and coin winner count at
    ///      every budget tier, with every pull resolving a winner.
    function test_theSplitMatchesTheWorkedTable() public {
        uint256[7] memory budgets = [
            uint256(3_125 ether), 12_500 ether, 31_250 ether, 62_500 ether, 125_000 ether, 250_000 ether, 625_000 ether
        ];
        uint256[7] memory seats = [uint256(0), 2, 6, 13, 25, 25, 25];
        uint256[7] memory fullDays = [uint256(0), 0, 0, 0, 0, 3, 12];
        uint256[7] memory shares = [
            uint256(100 ether), 300 ether, 600 ether, 1_200 ether, 2_600 ether, 5_100 ether, 12_800 ether
        ];
        h.seedAllTraits(LVL, 8);
        uint256 snap = vm.snapshotState();
        for (uint256 c; c < budgets.length; ++c) {
            vm.revertToState(snap);
            snap = vm.snapshotState();
            h.seedBudgetFor(LVL, budgets[c]);
            assertEq(h.coinBudgetOf(LVL), budgets[c], "budget seed did not round-trip");
            Vm.Log[] memory logs = _runTrait();

            assertEq(craps.passCalls(), fullDays[c], "full-day gifts = banked passes");
            assertEq(craps.codeCount(), seats[c] - fullDays[c], "opener seats");
            assertEq(_countSig(logs, CRAPS_WIN_SIG), seats[c], "one craps event per seat");
            assertEq(_countSig(logs, FLIP_WIN_SIG), 25, "25 coin winners");
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != FLIP_WIN_SIG) continue;
                (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(amount, shares[c], "equal coin share");
            }
            // Nothing refused: the FLIP credited is exactly the 25 coin shares.
            assertEq(coinflip.total(), 25 * shares[c], "FLIP credited beyond the coin shares");
            assertLe(
                seats[c] * SEAT + fullDays[c] * UPGRADE + coinflip.total(), budgets[c], "the draw overspent its budget"
            );
        }
    }

    /// @dev Every code targets TOMORROW, count one, normal lane; the first `fullDays` codes are
    ///      kind 2 (whole day) and the rest kind 5 period 0 (the opener).
    function test_everySeatTargetsTomorrowWithTheRightKind() public {
        h.seedAllTraits(LVL, 8);
        h.seedBudgetFor(LVL, 250_000 ether);
        _runTrait();
        (uint256 days_,,) = _plan(250_000 ether, 25);
        assertEq(craps.passCalls(), days_, "the first days_ winners bank a pass");
        uint256 n = craps.codeCount();
        assertEq(n, 25 - days_, "the rest take tomorrow's opener");
        uint24 tomorrow = h.today() + 1;
        for (uint256 i; i < n; ++i) {
            uint256 code = craps.codes(i);
            assertEq((code >> 160) & 0xFF, 5, "window ahead");
            assertEq(code & (uint256(1) << 168), 0, "never the high lane");
            assertEq(uint8(code >> 200), 1, "count one");
            assertEq(uint24(code >> 176), tomorrow, "tomorrow");
            assertEq(uint8(code >> 208), 0, "period 0 = the opener");
        }
    }

    /// @dev A whole day always banks one normal craps pass (creditPasses), claim or not; a
    ///      refused opener is paid its 2,400 in FLIP in the same batch — coin shares unchanged.
    function test_aDayBanksAPassAndARefusedOpenerPaysFlip() public {
        h.seedAllTraitsTo(LVL, address(0xABCD));
        _claim(address(0xABCD));
        h.seedBudgetFor(LVL, 250_000 ether);
        Vm.Log[] memory logs = _runTrait();
        (uint256 days_, uint256 amount,) = _plan(250_000 ether, 25);
        assertGt(days_, 0, "the fixture must refuse at least one whole day");
        assertEq(craps.codeCount(), 0, "a refused winner is never seated");
        assertEq(craps.passes(address(0xABCD)), days_, "each refused day banked one pass");
        assertEq(coinflip.batches(), 1, "one batch");
        assertEq(coinflip.total(), (25 - days_) * SEAT + 25 * amount, "refused openers plus coin shares");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != CRAPS_WIN_SIG) continue;
            (bool fullDay, bool refused) = abi.decode(logs[i].data, (bool, bool));
            assertEq(refused, !fullDay, "only an opener is ever refused");
        }
    }

    /// @dev Below one seat (craps half < 2,400) the whole budget is the coin half.
    function test_belowOneSeatTheWholeBudgetIsCoin() public {
        h.seedAllTraits(LVL, 8);
        h.seedBudgetFor(LVL, 4_700 ether);
        Vm.Log[] memory logs = _runTrait();
        assertEq(craps.codeCount(), 0, "no seat under 4,800");
        assertEq(_countSig(logs, FLIP_WIN_SIG), 25);
        assertEq(coinflip.total(), 25 * 100 ether, "47 units split 25 ways = 100 each");
    }

    /// @dev Empty craps pulls leave their seat money in the craps half, which upgrades found
    ///      winners and then flows to coin — the draw never pays for a seat nobody took.
    function test_emptyCrapsPullsFlowOnward(uint256 seed) public {
        uint256 b = bound(seed, 1, 200) * 5_000 ether;
        // Quadrant 0 only: three pulls in four miss.
        h.seedQuadrant(LVL, 0, 4);
        h.seedBudgetFor(LVL, b);
        _runTrait();
        uint256 n = craps.codeCount() + craps.passCalls();
        assertLe(n, _pulls(b), "more seats than pulls");
        (uint256 days_, uint256 amount, uint256 cap) = _plan(b, n);
        assertLe(n * SEAT + days_ * UPGRADE + coinflip.total(), b, "overspent");
        assertLe(coinflip.total(), cap * amount, "coin beyond its shares");
    }

    /// @dev Conservation across fuzzed budgets with full buckets.
    function test_fuzz_theDrawNeverOverspends(uint256 seed) public {
        uint256 b = bound(seed, 1, 5_000) * 250 ether;
        h.seedAllTraits(LVL, 4);
        h.seedBudgetFor(LVL, b);
        _runTrait();
        uint256 n = craps.codeCount() + craps.passCalls();
        assertEq(n, _pulls(b), "every craps pull resolved");
        (uint256 days_, uint256 amount, uint256 cap) = _plan(b, n);
        assertEq(coinflip.total(), cap * amount, "every coin share paid, equal");
        assertLe(n * SEAT + days_ * UPGRADE + coinflip.total(), b, "overspent");
    }

    // ── The purchase fill draw ─────────────────────────────────────────────

    /// @dev Fill draw: the first wallets walked are the craps half, the next the coin half.
    function test_theFillDrawSeatsItsFirstWallets() public {
        for (uint24 d = 2; d <= 100; ++d) h.seedFarQueue(d, 64, uint160(uint256(d) << 32));
        h.seedBudgetFor(LVL, 125_000 ether);
        vm.recordLogs();
        h.payDailyFutureFlipJackpot(LVL, WORD);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(craps.codeCount(), 25, "25 seats");
        assertEq(_countSig(logs, FAR_WIN_SIG), 25, "25 coin winners");
        (, uint256 amount,) = _plan(125_000 ether, 25);
        assertEq(coinflip.total(), 25 * amount);
        // No wallet is both a seat and a coin winner.
        for (uint256 i; i < 25; ++i) {
            address seated = address(uint160(craps.codes(i)));
            assertEq(coinflip.amountOf(seated), 0, "a seat also took a coin share");
        }
    }

    /// @dev A thin future (two wallets on every level) fills the craps half first.
    function test_aThinFillDrawSeatsBeforeItPaysCoin() public {
        for (uint24 d = 2; d <= 100; ++d) h.seedFarQueue(d, 2, uint160(uint256(d) << 32));
        h.seedBudgetFor(LVL, 125_000 ether);
        h.payDailyFutureFlipJackpot(LVL, WORD);
        uint256 n = craps.codeCount() + craps.passCalls();
        assertGt(n, 0);
        assertLe(n, 25);
        (uint256 days_, uint256 amount, uint256 cap) = _plan(125_000 ether, n);
        assertLe(n * SEAT + days_ * UPGRADE + coinflip.total(), 125_000 ether, "overspent");
        assertLe(coinflip.total(), cap * amount);
    }

    // ── The real CrapsBattle ───────────────────────────────────────────────

    function _real() internal returns (CoinDrawHarness g, CrapsViews c) {
        vm.etch(ContractAddresses.CRAPS, address(new CrapsViews()).code);
        vm.etch(ContractAddresses.GAME, address(new CoinDrawHarness()).code);
        g = CoinDrawHarness(ContractAddresses.GAME);
        c = CrapsViews(ContractAddresses.CRAPS);
    }

    /// @dev THE REAL DOOR: day winners hold tomorrow's whole day, opener winners hold tomorrow's
    ///      opener, nothing is burned, and a second identical draw (every winner now holding
    ///      tomorrow) is refused seat by seat and paid in FLIP.
    function test_theRealCrapsBattleSeatsAndRefuses() public {
        (CoinDrawHarness g, CrapsViews c) = _real();
        g.seedAllTraits(LVL, 192);
        g.seedBudgetFor(LVL, 250_000 ether);
        uint24 tomorrow = g.today() + 1;
        uint64 opener = uint64(uint256(tomorrow) * 8 + 1);

        vm.recordLogs();
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 days_,,) = _plan(250_000 ether, 25);
        uint256 k;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != CRAPS_WIN_SIG || logs[i].emitter != address(g)) continue;
            address w = address(uint160(uint256(logs[i].topics[1])));
            (bool fullDay, bool paidAsFlip) = abi.decode(logs[i].data, (bool, bool));
            assertEq(fullDay, k < days_, "day by position");
            if (fullDay) {
                // A whole-day gift is a banked pass, never a seat.
                assertFalse(paidAsFlip, "a day gift is never refused");
                (uint256 held,) = c.passCreditsOf(w);
                assertGe(held, 1, "no banked pass");
            } else if (!paidAsFlip) {
                assertEq(c.dayStateOf(tomorrow, w), 1, "no claim on tomorrow");
                assertTrue(c.seatedIn(opener, w), "no opener seat");
            }
            ++k;
        }
        assertEq(k, 25, "25 craps winners");
        uint256 flipBefore = coinflip.total();

        // Same draw again: days bank another real pass; every opener winner now holds tomorrow
        // and is paid in FLIP.
        uint256 passesBefore;
        for (uint256 i; i < days_; ++i) {
            (uint256 held,) = c.passCreditsOf(address(uint160(uint256(_crapsWinner(logs, i)))));
            passesBefore += held;
        }
        vm.recordLogs();
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        (, uint256 amount,) = _plan(250_000 ether, 25);
        assertEq(coinflip.total() - flipBefore, (25 - days_) * SEAT + 25 * amount, "refused openers not paid in FLIP");
        uint256 passesAfter;
        for (uint256 i; i < days_; ++i) {
            (uint256 held,) = c.passCreditsOf(address(uint160(uint256(_crapsWinner(logs, i)))));
            passesAfter += held;
        }
        assertEq(passesAfter - passesBefore, days_, "day gifts did not bank real passes");
    }

    /// @dev The vault and sDGNRS are always refused and paid in FLIP; their automatic day seat is
    ///      left for `openBonusDay`.
    function test_theRealDoorRefusesTheProtocolBodies() public {
        (CoinDrawHarness g, CrapsViews c) = _real();
        g.seedAllTraitsTo(LVL, ContractAddresses.VAULT);
        g.seedBudgetFor(LVL, 125_000 ether);
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        uint24 tomorrow = g.today() + 1;
        assertEq(c.dayStateOf(tomorrow, ContractAddresses.VAULT), 0, "the vault was seated ahead of its day seat");
        (, uint256 amount,) = _plan(125_000 ether, 25);
        // B 125,000 seats 25 openers and no days: every refused opener is 2,400 FLIP.
        assertEq(coinflip.amountOf(ContractAddresses.VAULT), 25 * SEAT + 25 * amount, "vault not paid in FLIP");
    }

    /// @dev A saturated pass bank cannot silently consume a full-day award.
    function test_aSaturatedDayPassPaysItsValueInFlip() public {
        (CoinDrawHarness g, CrapsViews c) = _real();
        address winner = address(0xABCD);
        g.seedAllTraitsTo(LVL, winner);
        c.setPassCredits(winner, type(uint32).max, 0);
        g.seedBudgetFor(LVL, 250_000 ether);

        vm.recordLogs();
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 days_, uint256 amount,) = _plan(250_000 ether, 25);
        assertGt(days_, 0, "fixture needs full-day awards");
        assertEq(_countSig(logs, CRAPS_WIN_SIG), 25);
        uint256 refusedDays;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != CRAPS_WIN_SIG) continue;
            (bool fullDay, bool refused) = abi.decode(logs[i].data, (bool, bool));
            if (fullDay && refused) ++refusedDays;
        }
        assertEq(refusedDays, days_, "saturated days were not marked as FLIP payouts");
        (uint256 held,) = c.passCreditsOf(winner);
        assertEq(held, type(uint32).max, "saturated bank changed");
        // The first opener is seated; the remaining openers are refused for holding that day.
        assertEq(coinflip.total(), days_ * P + (25 - days_ - 1) * SEAT + 25 * amount);
    }

    /// @dev Anyone but the vault or the Game is still refused by the door.
    function test_theDoorStillGatesItsCallers() public {
        (, CrapsViews c) = _real();
        vm.expectRevert(CrapsBattle.NotVaultOwner.selector);
        vm.prank(address(0xBEEF));
        c.vaultComp(uint256(uint160(address(1))) | (uint256(5) << 160));
    }

    /// @dev WORST-CASE GAS on the real door: 25 distinct cold wallets seated (12 whole days),
    ///      plus the 25-share coin batch, against the 10M soft target — beside an all-coin draw.
    function test_gas_theWorstCaseSeatDraw() public {
        (CoinDrawHarness g,) = _real();
        g.seedAllTraits(LVL, 192);
        uint256 snap = vm.snapshotState();
        g.seedBudgetFor(LVL, 625_000 ether);
        uint256 before = gasleft();
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        uint256 seatGas = before - gasleft();

        vm.revertToState(snap);
        g.seedBudgetFor(LVL, 4_700 ether);
        before = gasleft();
        g.payDailyFlipJackpot(LVL, WORD, LVL, LVL);
        uint256 coinGas = before - gasleft();

        emit log_named_uint("coin draw, 25 seats (12 days) + 25 shares", seatGas);
        emit log_named_uint("coin draw, 25 shares only", coinGas);
        assertLt(seatGas, 10_000_000, "the seat draw broke the 10M soft target on its own");
    }
}
