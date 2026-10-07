// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {CrapsPreferenceStore} from "./CrapsPreferenceStore.sol";

import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";
import {CrapsPriceLib} from "../../contracts/libraries/CrapsPriceLib.sol";
import {LegacyCrapsEngine} from "../helpers/LegacyCrapsEngine.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";

/// @dev An independent recomputation of one battle run: the same engine entry, driven with the
///      terms the battle's spec names, so the battle's orchestration (dedupe, units, the bust
///      rule, the pot) is graded against runs it did not compute itself.
contract BattleRef is Craps {
    uint256 internal constant DICE_TAG = 0x436f696e4472617744696365; // "CoinDrawDice"
    uint256 internal constant COIN_DRAW_SCATTER_TAG = 0x436f696e4472617753636174746572; // "CoinDrawScatter"

    /// @dev The scheduled row for a board the dice threw whole: 15% of shooters, +32% profit.
    uint256 internal constant BOOST_ROW = 12 | (30 << 8);

    /// @dev One run at 0-based seat `j` of an `n`-wallet field, its turn in CrapsBattle's form.
    function run(uint256 word, address p, uint256 chipFlip, uint256 j, uint256 n)
        external
        pure
        returns (SlipResult memory r)
    {
        uint256 bankroll = chipFlip * 50;
        Bets memory b;
        _scatterInto(b, uint256(keccak256(abi.encode(word, COIN_DRAW_SCATTER_TAG, uint256(uint160(p))))), chipFlip, 10);
        bytes32 seed = keccak256(abi.encode(word, DICE_TAG));
        uint256 start = uint256(keccak256(abi.encode(ROTATING_SHOOTER_TAG, seed))) % n;
        uint256 offset = ((j + 1) + n - 1 - start) % n;
        r = _settleSlip(b, seed, bankroll, bankroll * 5, 22, 200, uint256(uint160(p)), BOOST_ROW | ((offset + 1) << 16));
    }

    /// @dev Independent canonical decoder and boost lookup, with no production codec use.
    function runBoard(uint256 word, address p, uint256 chipFlip, uint256 j, uint256 n, uint32 chips)
        external pure returns (SlipResult memory r)
    {
        uint256 placed;
        for (uint256 i; i < 10; ++i) placed += (chips >> (i * 3)) & 7;
        uint16[8] memory rows = [uint16(0x200f), 0x1d0e, 0x1d0c, 0x1d0b, 0x1d09, 0x1808, 0x1706, 0x1205];
        Bets memory b = _boardFrom(chips, chipFlip);
        _scatterInto(b, uint256(keccak256(abi.encode(word, COIN_DRAW_SCATTER_TAG, uint256(uint160(p))))), chipFlip, 10 - placed);
        bytes32 seed = keccak256(abi.encode(word, DICE_TAG));
        uint256 start = uint256(keccak256(abi.encode(ROTATING_SHOOTER_TAG, seed))) % n;
        uint256 turn = (j + n - start) % n + 1;
        uint256 bankroll = chipFlip * 50;
        return _settleSlip(b, seed, bankroll, bankroll * 5, 22, 200, uint256(uint160(p)), rows[placed] | (turn << 16));
    }

    /// @dev A raw slip with a caller-chosen hand cap, returning its shape for the gas envelope.
    function capped(uint256 packed, bytes32 seed, uint256 hands, uint256 budget, uint256 turn)
        external
        pure
        returns (uint256 h, uint256 rolls)
    {
        Bets memory b = _boardFrom(packed, 1);
        SlipResult memory r = _settleSlip(b, seed, 1e30, 0, hands, budget, 0xBEEF, BOOST_ROW | (turn << 16));
        return (r.handsPlayed, r.totalRolls);
    }

    /// @dev A raw slip at a caller-chosen roll budget, for the exact-cap property.
    function slip(uint256 packed, uint256 chipFlip, bytes32 seed, uint256 bankroll, uint256 goal, uint256 budget)
        external
        pure
        returns (SlipResult memory r)
    {
        Bets memory b = _boardFrom(packed, chipFlip);
        r = _settleSlip(b, seed, bankroll, goal, _MAX_SLIP_HANDS, budget, 0xBEEF, 0);
    }

    /// @dev Sum of the board's stakes, for the cut-hand accounting check.
    function stake(uint256 packed, uint256 chipFlip) external pure returns (uint256) {
        return _stakeFor(_boardFrom(packed, chipFlip));
    }
}

contract JackpotTableHarness is CrapsViews {
    function clearDayBodies(uint24 day) external {
        uint256 d = uint256(day) * 8;
        _dayTickets[d] = 0;
        _storeDaySeat(d, 2, 0);
        _storeDaySeat(d, 1, 0);
    }
    function jackpotTerms(uint64 slot) external view returns (Window memory) { return _slotWindow(slot); }
    /// @dev Unopen a day, so the next lock detaches its battle to remainder seven of that day.
    function clearBoostBudget(uint24 day) external { _boostBudget[day] = 0; }
}

contract JackpotBattleTest is CrapsPins {
    JackpotTableHarness internal table;
    IJackpotBattle internal api;
    JackpotBattle internal cold;
    uint24 internal day;
    uint64 internal slot;
    uint256 internal dayStart;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    LegacyCrapsEngine private legacyEngine;

    function setUp() public {
        _installPins();
        legacyEngine = new LegacyCrapsEngine();
        // Deployed from the artifact: embedding its creation code here overflows solc's tag width.
        table = JackpotTableHarness(deployCode("JackpotBattle.t.sol:JackpotTableHarness"));
        api = IJackpotBattle(address(table));
        cold = JackpotBattle(address(table));
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        dayStart = vm.getBlockTimestamp() + 1 days - elapsed;
        vm.warp(dayStart);
        day = table.currentDayIndex();
        slot = uint64(uint256(day) * 8 + 6);
        _setIndex(1);
        _setDailyWord(day, 123456);
        vm.prank(ContractAddresses.GAME);
        table.openBonusDay();
        table.clearDayBodies(day);
        game.setScore(alice, 100);
        game.setScore(bob, 100);
    }

    function _enter(address player, bool wholeDay) internal returns (uint256 id) {
        game.setScore(player, 100);
        vm.prank(player);
        if (wholeDay) {
            table.enterBonusDay(0, 1);
            return (uint256(day) * 8 << 64) | table.daySeatNumberOf(day, player);
        }
        return table.enterBonusBattle(5, 0, 1);
    }
    function _lock(uint256 added) internal {
        vm.warp(dayStart + 1 days);
        game.setRngLocked(true);
        // Level 2 prices at 0.01 ETH, so a pool of `added * 1 ether / 500` locks exactly `added` (floor 50,000).
        vm.prank(ContractAddresses.GAME);
        api.lockJackpotBattle(day + 1, added * 1 ether / 500, 2);
    }
    function _start(uint256 word, uint256 n, address base) internal {
        uint256[] memory field = new uint256[](n);
        for (uint256 i; i < n; ++i) field[i] = uint160(base) + i | (uint256(1) << 180);
        vm.startPrank(ContractAddresses.GAME);
        api.prepareJackpotBattle(7, word);
        api.appendJackpotBattle(field, 0, true);
        vm.stopPrank();
    }
    /// @dev A tight per-call allowance: enough to admit one atomic seat and its tails, so a
    ///      chunked run settles the field a seat or two per call.
    uint256 internal constant TIGHT_CHUNK = 2_500_000;

    /// @dev Drive the daily battle worker — mineFlip's jackpot-battle stage, called as the Game —
    ///      until the field completes, `allowance` gas per call (zero means all available gas).
    function _finish(uint256 allowance) internal returns (uint256 calls) {
        for (; calls < 200; ++calls) {
            (,,, bool done) = api.jackpotProgress();
            if (done) return calls;
            vm.prank(ContractAddresses.GAME);
            cold.runDailyBattleWork(allowance == 0 ? gasleft() : allowance);
        }
        revert("no progress");
    }

    function _finish() internal returns (uint256) {
        return _finish(0);
    }
    function _round() internal view returns (CrapsBattleStorage.JackpotRound memory r) {
        (r,,) = cold.jackpotBattleOf(slot);
    }

    function test_RunDailyBattleWorkUsesParentAllowanceAndFinishesLockedDailyField() public {
        _enter(alice, false);
        _enter(bob, false);
        _lock(50_000);
        _start(0xD4117, 5, address(0xD1000));
        vm.expectRevert();
        table.runDailyBattleWork(9_000_000);
        vm.prank(ContractAddresses.GAME);
        MineFlipGas.Result memory result = table.runDailyBattleWork(1_000_000);
        assertFalse(result.progressed);
        assertEq(table.bonusCursorOf(slot), 0);
        uint256 iterations;
        while (!result.done && iterations++ < 20) {
            vm.prank(ContractAddresses.GAME);
            uint256 before = gasleft();
            result = table.runDailyBattleWork(3_000_000);
            assertLt(before - gasleft(), 3_000_000, "full native call respects parent remainder");
            assertTrue(result.progressed, "funded daily continuation must move while game remains locked");
        }
        assertTrue(result.done);
        assertTrue(table.battleOf(table.keyOfSlot(slot)).finalized);
        assertTrue(game.rngLocked());
    }

    function test_EarlyFloorAwardsOnePerTenThousandAdded() public {
        _lock(CrapsPriceLib.jackpotAdded(25_000, 0));
        vm.prank(ContractAddresses.GAME);
        (,, uint256 remaining) = api.prepareJackpotBattle(7, 123);
        assertEq(remaining, 15);
        assertEq(_round().added, 150_000);
        _start(123, 15, alice);
        CrapsBattleStorage.JackpotRound memory r = _round();
        assertEq(r.drawnCount, 15);
        assertGe(r.bankroll, 300);
    }

    function test_AwardCountIgnoresPaidVolumeAndPoolRoll() public {
        _enter(alice, false);
        _lock(259_999);
        uint256 snap = vm.snapshotState();
        vm.prank(ContractAddresses.GAME);
        (,, uint256 a) = api.prepareJackpotBattle(7, 123);
        assertEq(a, 25);
        assertTrue(vm.revertToState(snap));
        vm.prank(ContractAddresses.GAME);
        (,, uint256 b) = api.prepareJackpotBattle(7, 999);
        assertEq(b, a);
        assertEq(_round().paidUnits, 1);
    }

    function test_AwardTargetRetainsSafetyCap() public {
        _lock(100_000_000);
        vm.prank(ContractAddresses.GAME);
        (,, uint256 remaining) = api.prepareJackpotBattle(7, 123);
        assertEq(remaining, 500);
    }

    function test_AppendRejectsMoreThanOneCheckpoint() public {
        _lock(1_000_000);
        vm.startPrank(ContractAddresses.GAME);
        api.prepareJackpotBattle(7, 123);
        uint256[] memory field = new uint256[](JackpotBattleFieldLib.MAX_CHUNK + 1);
        for (uint256 i; i < field.length; ++i) field[i] = uint160(bob) | (uint256(1) << 180);
        vm.expectRevert(JackpotBattle.BadJackpotField.selector);
        api.appendJackpotBattle(field, field.length, false);
        vm.stopPrank();
        assertEq(_round().drawnCount, 0);
        assertEq(_round().drawCursor, 0);
    }

    function test_LargeAwardFieldCollectsBeforeAnyPaidSettlement() public {
        _enter(alice, false);
        _lock(1_000_000);
        vm.prank(ContractAddresses.GAME);
        (,, uint256 remaining) = api.prepareJackpotBattle(7, 123);
        assertEq(remaining, 100);
        uint256[] memory field = new uint256[](50);
        for (uint256 i; i < field.length; ++i) field[i] = uint160(bob) | (uint256(1) << 180);
        vm.prank(ContractAddresses.GAME);
        api.appendJackpotBattle(field, 50, false);
        assertEq(_round().drawnCount, 50);
        assertEq(_round().word, 0);
        vm.prank(ContractAddresses.GAME);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        cold.runDailyBattleWork(gasleft());
        assertEq(table.bonusCursorOf(slot), 0);
        vm.prank(ContractAddresses.GAME);
        api.appendJackpotBattle(field, 100, true);
        assertEq(_round().drawnCount, 100);
        assertEq(_round().word, 123);
        assertGe(_round().bankroll, 300);
        _finish();
    }

    function test_NewHighDrawAgreesWithJackpotPaidUnits() public {
        _highDay(true);
        vm.prank(alice);
        table.enterBonusBattle(5, 0, 100);
        assertEq(flip.burned(alice), 800_000);
        _lock(150_000);
        assertEq(_round().paidUnits, 100);
        _start(123, 5, bob);
        CrapsBattleStorage.JackpotRound memory r = _round();
        assertEq(r.totalPool, _expectedPool(r));
    }

    function test_DrawnFeeVariableStakeAndExactPoolConservation() public {
        _enter(alice, false); _enter(bob, true);
        assertEq(flip.burned(alice), 8_000);
        _lock(400_000); _start(123, 50, address(0x1000));
        CrapsBattleStorage.JackpotRound memory r = _round();
        assertEq(r.paidCount, 2); assertEq(r.paidUnits, 2);
        uint256 n = r.paidUnits + r.drawnUnits;
        assertEq(r.drawnUnits, 40);
        assertEq(r.totalPool, _expectedPool(r));
        assertEq(uint256(r.bankroll) % 300, 0);
        assertEq(n * (uint256(r.bankroll) + uint256(r.bountyUnits) * 100) + r.potRemainder, r.totalPool);
        assertLe(uint256(r.bankroll) * n, r.totalPool / 2);
        assertLt(r.totalPool / 2 - uint256(r.bankroll) * n, n * 300);
        _finish();
    }

    function test_AwardedEntryThrowsTheFieldDiceUnderItsOwnKey() public view {
        CrapsEngine engine = CrapsEngine(ContractAddresses.CRAPS_ENGINE);
        uint256 word = 424_242;
        uint256 betId = (uint256(slot) << 64) | 9;
        uint256 chips = 1 | (1 << 9) | (1 << 12);
        uint256 field = (uint256(20) << 64) | 9;
        // The award's own key replaces its wallet for scatter, survival coin and boost; the dice
        // seed is the field's. So it is exactly a paid seat played by that key on the same word.
        uint256 key = uint160(uint256(keccak256(abi.encode(word, uint256(0x4a61636b706f7441776172646564), betId))));
        Craps.SlipResult memory awarded = engine.settleBattle(
            betId, uint32(uint160(bob)) | (chips << 32) | (uint256(1) << 72), 30, 1_500, 7_500, uint48(slot), field, word);
        Craps.SlipResult memory paid = legacyEngine.settleBattle(
            betId, key | (chips << 160), 30, 1_500, 7_500, uint48(slot), field, word);
        assertEq(keccak256(abi.encode(awarded)), keccak256(abi.encode(paid)));
    }

    /// @dev A bankroll no escalated round can drain: only a hard bound stops the run.
    function _endlessRun(uint256 bound, uint256 goal, uint256 word) internal view returns (Craps.SlipResult memory) {
        return CrapsEngine(ContractAddresses.CRAPS_ENGINE).settleBattle(
            (bound << 64) | 1, uint160(alice), 1, 1e40, goal, uint48(bound), (uint256(1) << 64) | 1, word);
    }

    function testFuzz_JackpotRunStopsInsideItsRollCeiling(uint256 word, bool detached, bool latched) public view {
        uint256 bound = uint256(day) * 8 + (detached ? 7 : 6);
        Craps.SlipResult memory r = _endlessRun(bound, latched ? 5e39 : 5e40, word);
        assertGe(r.totalRolls, 600, "stopped short of the budget");
        assertLe(r.totalRolls, 1_111, "passed the budget plus one full hand");
        if (latched) {
            assertEq(uint8(r.stop), uint8(Craps.SlipStop.Goal), "latched run must keep its Goal");
            assertGe(r.bankrollOut, 5e39, "reserve breached");
            assertGt(r.bankrollIn, 0, "Goal pays what it holds");
        } else {
            assertEq(uint8(r.stop), uint8(Craps.SlipStop.Bust), "pre-goal bound is a bust");
            assertEq(r.bankrollIn, 0, "a bust pays nothing");
        }
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzz_OrdinaryAndCustomRunsUseSharedRollCeiling(
        uint256 word, uint8 period, bool custom, bool latched
    ) public view {
        uint256 bound = custom ? (uint256(1) << 40) + word % 1000 : uint256(day) * 8 + 1 + period % 5;
        Craps.SlipResult memory r = _endlessRun(bound, latched ? 5e39 : 5e40, word);
        assertGe(r.totalRolls, 600, "stopped short of the shared budget");
        assertLe(r.totalRolls, 1_111, "passed the shared ceiling");
        assertEq(uint8(r.stop), uint8(latched ? Craps.SlipStop.Goal : Craps.SlipStop.Bust));
        if (latched) assertGe(r.bankrollIn, 5e39, "latched goal lost its reserve");
        else assertEq(r.bankrollIn, 0, "a pre-goal bound paid a bust");
    }

    /// @dev A detached battle sits at remainder seven of a day that never opened, which is exactly
    ///      the day the keeper's lapse sweep refunds. The sweep must leave the battle's settle
    ///      cursor alone and refund nothing for its awards, or the field could never complete.
    function test_LapseSweepLeavesADetachedBattleToSettle() public {
        table.clearBoostBudget(day);
        _lock(400_000);
        uint64 detached = uint64(uint256(day) * 8 + 7);
        (uint64 active,,,) = api.jackpotProgress();
        assertEq(active, detached, "the lock did not detach");
        _start(123, 40, address(0x1000));
        table.resolveSeats(detached, 1);
        assertEq(table.bonusCursorOf(detached), 1);
        uint64 daySlot = uint64(uint256(day) * 8);
        _crank(table);
        assertEq(table.keeperSlot(), daySlot, "daily lock prevents maintenance interleaving");
        assertEq(table.bonusCursorOf(detached), 1);
        _finish();
        uint256 settledLane = flip.compLane();
        game.setRngLocked(false);
        game.setRngConsumerStage(7);
        for (uint256 i; i < 20 && table.keeperSlot() <= daySlot; ++i) _crank(table);
        assertGt(table.keeperSlot(), daySlot, "the keeper never swept the lapsed day");
        assertEq(table.bonusCursorOf(detached), 40, "the sweep moved the completed battle cursor");
        assertEq(flip.compLane(), settledLane, "the sweep refunded awards as reservations");
        assertEq(table.battleOf(bytes32(uint256(detached))).resolved, 40);
    }

    function test_OnlyPaidFeesAreBookedAsActionAndComped() public {
        _enter(alice, false); _enter(bob, true);
        uint256 before = table.dayStaked(day);
        uint256 lane = flip.compLane();
        _lock(400_000); _start(123, 50, address(0x1000));
        CrapsBattleStorage.JackpotRound memory r = _round();
        uint256 n = r.paidUnits + r.drawnUnits;
        uint256 bps = r.multiplierBps < 10_000 ? r.multiplierBps : 10_000;
        uint256 staked = uint256(r.paidUnits) * 8_000 * bps / 10_000 * (n * r.bankroll) / r.totalPool;
        assertGt(staked, 0);
        assertLe(staked, uint256(r.paidUnits) * 4_000, "more than the fees' bankroll half");
        assertEq(table.dayStaked(day) - before, staked);
        assertEq(flip.compLane() - lane, staked / 50, "creditCrapsComps paid other than the fee share");
        _finish();
        assertEq(table.dayStaked(day) - before, staked, "settlement booked the jackpot again");
        assertEq(flip.compLane() - lane, staked / 50, "finalization comped the jackpot again");
    }

    function test_BadDrawsAreSkippedAndResumeKeepsFrozenDraw() public {
        _enter(alice, false);
        _lock(150_000);
        vm.prank(ContractAddresses.GAME);
        (uint256 frozen,,) = api.prepareJackpotBattle(7, 123);
        vm.prank(ContractAddresses.GAME);
        (uint256 resumed,,) = api.prepareJackpotBattle(8, 456);
        assertEq(resumed, frozen);
        assertEq(_round().level, 7);
        uint256[] memory f = new uint256[](3);
        f[0] = uint160(bob) | (uint256(1) << 180);
        f[1] = uint256(1) << 180;
        f[2] = uint160(bob);
        vm.prank(ContractAddresses.GAME);
        api.appendJackpotBattle(f, 3, true);
        assertEq(_round().drawnCount, 1);
        assertEq(_round().word, 123);
        _finish();
    }

    function test_AwardOnlyFieldBooksNothing() public {
        uint256 before = table.dayStaked(day);
        uint256 lane = flip.compLane();
        _lock(150_000); _start(123, 15, alice); _finish();
        assertEq(table.dayStaked(day), before);
        assertEq(flip.compLane(), lane);
    }

    function test_PaidOwnThenDayThenAwarded_OneWalkFinalizesOnce() public {
        _enter(alice, false); _enter(bob, true);
        _lock(1_000_000); _start(17, 2, alice);
        table.resolveSeats(slot, 1);
        assertFalse(table.battleOf(bytes32(uint256(slot))).finalized);
        assertEq(table.bonusCursorOf(slot), 1);
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME); assertTrue(cold.runDailyBattleWork(gasleft()).done);
        assertEq(table.bonusCursorOf(slot), 4, "the walk stopped at the paid boundary");
        assertEq(table.battleOf(bytes32(uint256(slot))).resolved, 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 finals;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == CrapsBattleStorage.CrapsBattleFinalized.selector) ++finals;
        }
        assertEq(finals, 1, "one finalization, at the last awarded seat");
        uint256 credited = coinflip.totalCredited();
        vm.prank(ContractAddresses.GAME); assertTrue(cold.runDailyBattleWork(gasleft()).done);
        assertEq(coinflip.totalCredited(), credited, "paid twice");
    }

    function test_DifferentBudgetsProduceSameWinnerAndPayments() public {
        _enter(alice, false); _enter(bob, true);
        for (uint160 i = 0x2000; i < 0x2008; ++i) _enter(address(i), false);
        _lock(1_000_000); _start(578, 12, address(0x3000));
        uint256 snap = vm.snapshotState();
        assertGt(_finish(TIGHT_CHUNK), 1, "the tight allowance did not split the field");
        uint256 credited = coinflip.totalCredited();
        bytes32 digest = keccak256(abi.encode(table.battleOf(bytes32(uint256(slot)))));
        assertTrue(vm.revertToState(snap));
        _finish();
        assertEq(coinflip.totalCredited(), credited);
        assertEq(keccak256(abi.encode(table.battleOf(bytes32(uint256(slot))))), digest);
    }

    function test_LockPreventsEntryUpgradeAmendmentAndPreferenceChange() public {
        uint256 id = _enter(alice, false); _enter(bob, true);
        _lock(200_000);
        vm.prank(address(0x123)); vm.expectRevert(); table.enterBonusBattle(5, 0, 1);
        vm.prank(alice); vm.expectRevert(); table.amendSlip(id, 1);
        vm.prank(bob); vm.expectRevert(); table.upgradeDayWindows(0, day, 0x20);
        _start(831, 1, alice); _finish();
    }

    function test_RetryCannotReplaceAllocationOrField() public {
        _enter(alice, false); _lock(200_000);
        vm.prank(ContractAddresses.GAME); api.lockJackpotBattle(day + 1, 999_000 ether / 500, 2);
        assertEq(_round().added, 200_000);
        _start(99, 1, alice);
        uint256[] memory f = new uint256[](3);
        for (uint256 i; i < f.length; ++i) f[i] = uint160(bob) + i | (uint256(1) << 180);
        vm.startPrank(ContractAddresses.GAME);
        api.prepareJackpotBattle(7, 777);
        vm.expectRevert(JackpotBattle.BadJackpotField.selector);
        api.appendJackpotBattle(f, 0, true);
        vm.stopPrank();
        assertEq(_round().word, 99); assertEq(_round().drawnCount, 1);
        _finish();
    }

    function test_EmptyAwardFieldStillClosesPaidBattle() public {
        _enter(alice, false); _lock(123_000); _start(44, 0, bob);
        assertEq(_finish(), 1);
        assertEq(table.battleOf(bytes32(uint256(slot))).winnerId, 1);
    }
    function test_NoEntrantsCompletesWithoutDivisionOrPayout() public {
        _lock(123_000); _start(44, 0, bob);
        (,,, bool complete) = api.jackpotProgress(); assertTrue(complete);
        assertEq(coinflip.totalCredited(), 0);
    }
    function test_LateAndNextDayProcessingDoesNotChangeFrozenTerms() public {
        _enter(alice, false); _lock(500_000);
        vm.warp(dayStart + 5 days);
        _setDailyWord(table.currentDayIndex(), 999);
        vm.prank(ContractAddresses.GAME); table.openBonusDay();
        _start(987, 3, bob); _finish();
        assertEq(_round().paidCount, 1); assertEq(_round().added, 500_000);
    }
    function test_HighCopiesAndRepeatedAwardsCountAsUnits() public {
        uint16 h = uint16(table.highMultOfWord(123456));
        vm.prank(alice); table.enterBonusBattle(5, 0, h);
        _lock(500_000);
        uint256[] memory f = new uint256[](3);
        for (uint256 i; i < f.length; ++i) f[i] = uint160(bob) | (uint256(1) << 180);
        vm.startPrank(ContractAddresses.GAME);
        api.prepareJackpotBattle(7, 999);
        api.appendJackpotBattle(f, 0, true);
        vm.stopPrank();
        CrapsBattleStorage.JackpotRound memory r = _round();
        assertEq(r.paidUnits, h); assertEq(r.drawnUnits, 3); assertEq(r.drawnCount, 3);
        assertEq(r.totalPool, _expectedPool(r));
        _finish();
    }
    function test_OnlyGameCanLockOrSupplyField() public {
        vm.expectRevert(); api.lockJackpotBattle(day + 1, 123 ether, 2);
        uint256[] memory f = new uint256[](0);
        vm.expectRevert(); api.prepareJackpotBattle(7, 123);
        vm.expectRevert(); api.appendJackpotBattle(f, 0, true);
    }
    function test_SixDeadlinesAndUnusedSlot() public {
        uint256[6] memory elapsed = [uint256(0),20 minutes,6 hours + 3 minutes,12 hours + 3 minutes,18 hours + 3 minutes,1 days - 20 minutes];
        for (uint256 i; i < elapsed.length; ++i) {
            vm.warp(dayStart + elapsed[i]);
            (,uint256 period,) = table.currentBonusSlot(); assertEq(period, i);
        }
        vm.expectRevert(); table.jackpotTerms(uint64(uint256(day) * 8 + 7));
    }
    function test_DayPriceUsesNewPresetsAndDrawnJackpotFee() public {
        uint256 total;
        for (uint256 p; p < 6; ++p) {
            (uint128 bank,,,uint256 bounty,,) = table.bonusTermsFor(day,p);
            total += bank + bounty;
            if (p == 5) assertEq(uint256(bank) + bounty, 8_000);
        }
        _enter(alice, true); assertEq(flip.burned(alice), total);
        assertEq(table.BONUS_PERIODS_PER_DAY(), 6);
        assertEq(table.daySeatHighMaskOf(day,alice),0);
    }
    function testFuzz_PoolSplitNeverOverallocates(uint96 added, uint16 rawPaid, uint8 rawDraw, uint256 word) public {
        added = uint96(bound(added, 1, 1e7));
        uint256 paid = bound(rawPaid, 1, 12);
        uint256 drawn = bound(rawDraw, 0, 50);
        for (uint160 i; i < paid; ++i) _enter(address(0xA000 + i), false);
        _lock(added); _start(word == 0 ? 1 : word, drawn, address(0xB000));
        CrapsBattleStorage.JackpotRound memory r = _round();
        uint256 n = r.paidUnits + r.drawnUnits;
        assertGe(r.bankroll, 300);
        assertEq(n * (uint256(r.bankroll) + uint256(r.bountyUnits) * 100) + r.potRemainder, r.totalPool);
    }

    function _highDay(bool tail) private returns (uint16 multiple) {
        if (!tail) {
            assertEq(table.jackpotTerms(slot).highMult, 10, "default day already accepted 10x terms");
            return 10;
        }
        // Window terms freeze at openBonusDay. Choose the word before opening a
        // fresh day; replacing the already-open day's mock word cannot reprice it.
        dayStart += 1 days;
        vm.warp(dayStart);
        day = table.currentDayIndex();
        slot = uint64(uint256(day) * 8 + 6);
        multiple = tail ? 100 : 10;
        for (uint256 word = 1; ; ++word) {
            if (table.highMultOfWord(word) == multiple
                && CrapsPriceLib.jackpotPrice(uint256(keccak256(abi.encode(word, uint256(0x43726170735363686564756c65), uint256(5))))) == 8_000) {
                _setDailyWord(day, word);
                vm.prank(ContractAddresses.GAME);
                table.openBonusDay();
                table.clearDayBodies(day);
                return multiple;
            }
        }
    }

    function _enterHigh(address player, uint16 multiple) private {
        game.setScore(player, 100);
        vm.prank(player);
        table.enterBonusBattle(5, 0, multiple);
    }

    function _wordForMultiplier(uint256 bps) private pure returns (uint256 word) {
        for (word = 1; ; ++word) {
            uint256 roll = uint256(keccak256(abi.encode(word, uint256(0x436f696e447261774d756c7469706c696572)))) % 1000;
            uint256 got = roll < 900 ? 5000 : roll < 990 ? 30000 : roll < 999 ? 200000 : 1000000;
            if (got == bps) return word;
        }
    }

    /// @dev Isolate payout accounting from dice luck. A qualified run returns exactly 5x, so it
    ///      earns no progressive or record award; a bust returns zero and still ranks normally.
    function _mockRun(bool qualified) private {
        uint256 bank = _round().bankroll;
        Craps.SlipResult memory result;
        if (qualified) {
            result.bankrollIn = bank * 5; // settleBattle returns the rounded payment here
            result.bankrollOut = bank * 5;
            result.peakBankroll = bank * 5;
            result.unitsPlayed = (uint256(1) << 104) | ((bank * 5 / 1) << 60)
                | ((bank * 5 / 1) << 16);
            result.stop = Craps.SlipStop.Goal;
        }
        vm.mockCall(ContractAddresses.CRAPS_ENGINE, abi.encodeWithSelector(CrapsEngine.settleBattle.selector), abi.encode(result));
    }

    function _expectedPool(CrapsBattleStorage.JackpotRound memory r) private pure returns (uint256) {
        uint256 subsidy = (r.added - r.added / 20) * r.subsidyMultiplierBps / 10_000;
        return (uint256(r.paidUnits) * r.entryPrice + subsidy) * r.multiplierBps / 10_000;
    }

    function _mainPot(CrapsBattleStorage.JackpotRound memory r) private pure returns (uint256) {
        return (uint256(r.paidCount) + r.drawnCount) * r.bountyUnits * 100 + r.potRemainder;
    }

    function test_HighUpgradeCannotDiluteTheMainSeatAllocation() public {
        uint16 h = _highDay(true);
        uint256 snap = vm.snapshotState();
        _enter(alice, false); _enter(bob, false);
        _lock(150_000); _start(123, 15, address(0x1000));
        CrapsBattleStorage.JackpotRound memory normal = _round();
        assertTrue(vm.revertToState(snap));
        _enterHigh(alice, h); _enter(bob, false);
        _lock(150_000); _start(123, 15, address(0x1000));
        CrapsBattleStorage.JackpotRound memory high = _round();
        assertEq(high.bankroll, normal.bankroll, "high copies diluted base bankrolls");
        assertEq(high.bountyUnits, normal.bountyUnits, "high copies diluted main bounties");
        assertEq(high.potRemainder, normal.potRemainder, "high allocation took main remainder");
        assertEq(high.totalPool - normal.totalPool, 2 * table.jackpotTerms(slot).highExtra);
    }

    function test_AddedCannotIncreaseHighExtraCapital() public {
        uint16 h = _highDay(true);
        _enterHigh(alice, h); _enterHigh(bob, h);
        uint256 snap = vm.snapshotState();
        _lock(50_000); _start(123, 0, address(0));
        uint256 extra = table.jackpotTerms(slot).highExtra;
        uint256 bank = _round().bankroll;
        assertTrue(vm.revertToState(snap));
        _lock(5_000_000); _start(123, 0, address(0));
        assertGt(_round().bankroll, bank);
        assertEq(table.jackpotTerms(slot).highExtra, extra, "Added leaked into high capital");
        assertEq(table.highBaseOf(slot), 0, "jackpot high field acquired a protocol boost");
    }

    function testFuzz_HighPoolConservesAndCompsOnlyExpectedFeeLoss(
        bool tail, uint8 rawHeads, uint8 rawOrdinary, uint8 rawDrawn, uint96 rawAdded, uint256 word
    ) public {
        uint16 h = _highDay(tail);
        uint256 heads = 1 + uint256(rawHeads) % 5;
        uint256 ordinary = uint256(rawOrdinary) % 5;
        for (uint160 i; i < heads; ++i) _enterHigh(address(0xA000 + i), h);
        for (uint160 i; i < ordinary; ++i) _enter(address(0xB000 + i), false);
        uint256 before = flip.compLane();
        uint256 booked = table.dayStaked(day);
        uint256 added = bound(rawAdded, 50_000, 5_000_000);
        _lock(added); _start(word == 0 ? 1 : word, uint256(rawDrawn) % 16, address(0xC000));
        CrapsBattleStorage.JackpotRound memory r = _round();
        uint256 highFees = heads * (h - 1) * 8_000;
        uint256 highPool = highFees * r.multiplierBps / 10_000;
        uint256 mainPool = r.totalPool - highPool;
        uint256 baseUnits = uint256(r.paidCount) + r.drawnUnits;
        assertEq(2 * heads * table.jackpotTerms(slot).highExtra, highPool, "high pool must contain fees only");
        assertEq(baseUnits * (uint256(r.bankroll) + uint256(r.bountyUnits) * 100) + r.potRemainder, mainPool);
        uint256 retainedBps = r.multiplierBps < 10_000 ? r.multiplierBps : 10_000;
        uint256 baseAction = uint256(r.paidCount) * 8_000 * retainedBps / 10_000
            * (baseUnits * r.bankroll) / mainPool;
        uint256 atRisk = heads == 1 ? highFees : highFees / 2;
        uint256 highComps = atRisk * 12 / 100 * 80 / 100;
        assertEq(flip.compLane() - before, baseAction / 50 + highComps);
        assertEq(table.dayStaked(day) - booked, baseAction, "extra high loss was recycled into future boosts");
    }

    function test_HighCompBudgetUsesPreRollEVAndOnlyAccruesOnce() public {
        uint16 h = _highDay(true);
        _enterHigh(alice, h); _enterHigh(bob, h);
        uint256[4] memory bps = [uint256(5000), 30000, 200000, 1000000];
        uint256 snap = vm.snapshotState();
        bytes32 eventSig = keccak256("JackpotHighCompsAccrued(uint64,uint256,uint256,uint256,uint256)");
        for (uint256 i; i < bps.length; ++i) {
            if (i != 0) { assertTrue(vm.revertToState(snap)); snap = vm.snapshotState(); }
            _lock(150_000);
            vm.recordLogs();
            _start(_wordForMultiplier(bps[i]), 15, address(0x1000));
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 found;
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].topics[0] != eventSig) continue;
                (uint256 fees, uint256 atRisk, uint256 loss, uint256 comps) = abi.decode(logs[j].data, (uint256,uint256,uint256,uint256));
                assertEq(fees, 1_584_000);
                assertEq(atRisk, 792_000);
                assertEq(loss, 95_040);
                assertEq(comps, 76_032);
                ++found;
            }
            assertEq(found, 1);
            uint256 lane = flip.compLane();
            _mockRun(false);
            _finish(TIGHT_CHUNK);
            vm.prank(ContractAddresses.GAME); cold.runDailyBattleWork(gasleft());
            assertEq(flip.compLane(), lane, "settlement or retry credited comps twice");
            vm.clearMockedCalls();
        }
    }

    function test_ContestedHighPotPaysItsRolledFeesEvenWhenAllBust() public {
        uint16 h = _highDay(true);
        _enterHigh(alice, h); _enterHigh(bob, h);
        _lock(150_000); _start(_wordForMultiplier(30000), 0, address(0));
        CrapsBattleStorage.JackpotRound memory r = _round();
        uint256 extra = table.jackpotTerms(slot).highExtra;
        assertEq(extra, 1_188_000);
        _mockRun(false);
        _finish();
        assertEq(coinflip.totalCredited(), _mainPot(r) + 2 * extra, "contested high bounty was scaled by Added or lost on busts");
    }

    function test_SoleHighBountyRidesAndItsWholeExtraFeeEarnsLossComps() public {
        uint16 h = _highDay(false);
        _enterHigh(alice, h);
        uint256 before = flip.compLane();
        _lock(50_000); _start(_wordForMultiplier(5000), 0, address(0));
        CrapsBattleStorage.JackpotRound memory r = _round();
        uint256 extra = table.jackpotTerms(slot).highExtra;
        uint256 mainPool = r.totalPool - 2 * extra;
        uint256 baseAction = 4_000 * uint256(r.bankroll) / mainPool;
        assertEq(extra, 18_000);
        assertEq(flip.compLane() - before, baseAction / 50 + 6_912, "sole bounty risk omitted or comped twice");
        _mockRun(true);
        _finish();
        assertEq(coinflip.staked(alice), _mainPot(r) + 5 * (uint256(r.bankroll) + 2 * extra));
    }

    function test_HighExtraReceivesNoMultipliedProtocolBoon() public {
        uint16 h = _highDay(false);
        flip.setNextBoonMask(4);
        _enterHigh(alice, h); _enterHigh(bob, h);
        _lock(50_000); _start(_wordForMultiplier(5000), 0, address(0));
        CrapsBattleStorage.JackpotRound memory r = _round();
        uint256 extra = table.jackpotTerms(slot).highExtra;
        _mockRun(true);
        _finish();
        uint256 baseBoon = uint256(r.bankroll) * 5 * 15 / 100;
        assertLt(baseBoon, 9_000, "fixture must distinguish base boon from the high cap");
        assertEq(coinflip.totalCredited(), _mainPot(r) + 2 * extra + 10 * (uint256(r.bankroll) + extra) + baseBoon);
    }

    function test_HighDayTicketUsesTheSameFeeOnlyAllocation() public {
        uint16 h = _highDay(true);
        vm.prank(alice); table.enterBonusDay(0, h);
        _lock(150_000); _start(_wordForMultiplier(5000), 15, address(0x1000));
        assertEq(_round().paidUnits, 100);
        assertEq(table.jackpotTerms(slot).highExtra, 198_000);
        _finish();
    }
}
