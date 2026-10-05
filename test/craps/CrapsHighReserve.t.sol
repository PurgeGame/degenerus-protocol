// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsPins} from "./CrapsPins.sol";
import {JackpotTableHarness} from "./JackpotBattle.t.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

contract CrapsHighReserveTest is CrapsPins {
    JackpotTableHarness internal table;
    JackpotBattle internal cold;
    IJackpotBattle internal api;
    uint24 internal day;
    uint64 internal slot;
    uint256 internal dayStart;
    uint16 internal multiple;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    bytes32 internal constant DRAW_EVENT = keccak256("HighRollerReserveDrawn(uint64,uint32,address,uint256,uint256)");
    uint256 internal constant DRAW_TAG = uint256(keccak256("CrapsHighReserveDraw"));

    function setUp() public {
        _installPins();
        table = new JackpotTableHarness();
        cold = JackpotBattle(address(table));
        api = IJackpotBattle(address(table));
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        dayStart = vm.getBlockTimestamp() + 1 days - elapsed;
        _openDay(10);
        // Busts isolate the new reserve from engine returns and unrelated progressive awards.
        Craps.SlipResult memory bust;
        vm.mockCall(ContractAddresses.CRAPS_ENGINE, abi.encodeWithSelector(CrapsEngine.settleBattle.selector), abi.encode(bust));
    }

    function _openDay(uint16 h) internal { _openDay(h, false); }

    function _openDay(uint16 h, bool preserveReservations) internal {
        vm.warp(dayStart);
        day = table.currentDayIndex();
        slot = uint64(uint256(day) * 8 + 6);
        game.setRngLocked(false);
        multiple = h;
        uint256 word = 1;
        while (table.highMultOfWord(word) != h
            || uint256(keccak256(abi.encode(word, uint256(0x43726170735363686564756c65), uint256(5)))) & 3 == 0
            || uint256(keccak256(abi.encode(word, uint256(0x43726170735363686564756c65), uint256(5)))) & 3 == 3) ++word;
        _setDailyWord(day, word);
        vm.prank(ContractAddresses.GAME);
        table.openBonusDay();
        if (!preserveReservations) table.clearDayBodies(day);
    }

    function _enter(address who, bool high, bool daySeat) internal {
        vm.prank(who);
        if (daySeat) table.enterBonusDay(0, high ? multiple : 1);
        else table.enterBonusBattle(5, 0, high ? multiple : 1);
    }

    function _lock(uint256 added) internal {
        vm.warp(dayStart + 1 days);
        game.setRngLocked(true);
        vm.prank(ContractAddresses.GAME);
        api.lockJackpotBattle(day + 1, added * 1 ether / 500, 2);
    }

    function _start(uint256 word, uint256 awards) internal {
        uint256[] memory field = new uint256[](awards);
        // Repeated awards to an existing high entrant must never buy more raffle tickets.
        for (uint256 i; i < awards; ++i) field[i] = uint160(ALICE) | (uint256(1) << 180);
        vm.startPrank(ContractAddresses.GAME);
        api.prepareJackpotBattle(2, word);
        api.appendJackpotBattle(field, 0, true);
        vm.stopPrank();
    }

    /// @dev Settle the jackpot field to completion: whole batches for `WHOLE_FIELD`, otherwise
    ///      `budget` seats per call, so a chunked run really crosses seat boundaries. Both paths
    ///      run the reserve draw.
    function _finish(uint64 budget) internal {
        for (uint256 i; i < 500; ++i) {
            (,,, bool complete) = api.jackpotProgress();
            if (complete) return;
            if (budget == WHOLE_FIELD) table.settleSlot(slot, budget);
            else table.resolveSeats(slot, budget);
        }
        revert("settlement stalled");
    }

    function _word(bool win) internal view returns (uint256 word) {
        for (word = 1; ; ++word) {
            if ((uint256(keccak256(abi.encode(word, DRAW_TAG, uint256(slot)))) % 10 == 0) == win) return word;
        }
    }

    function _assertDrawLog(Vm.Log[] memory logs, uint32 n, address winner, uint256 amount, uint256 balance) internal view {
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(table) || logs[i].topics[0] != DRAW_EVENT) continue;
            assertEq(uint256(logs[i].topics[1]), slot);
            assertEq(address(uint160(uint256(logs[i].topics[2]))), winner);
            (uint32 count, uint256 paid, uint256 held) = abi.decode(logs[i].data, (uint32, uint256, uint256));
            assertEq(count, n); assertEq(paid, amount); assertEq(held, balance);
            ++seen;
        }
        assertEq(seen, 1, "expected exactly one event-wide decision");
    }

    function test_fivePercentIsFundedOnceBeforeTheMultiplierAndAwardsUseGrossAdded() public {
        _enter(ALICE, true, false);
        _lock(150_000);
        assertEq(cold.highRollerReserve(), 7_500);
        vm.prank(ContractAddresses.GAME);
        api.lockJackpotBattle(day + 1, 1_000 ether, 2);
        assertEq(cold.highRollerReserve(), 7_500, "lock retry funded twice");
        uint256 snap = vm.snapshotState();
        uint256[4] memory wanted = [uint256(5_000), 30_000, 200_000, 1_000_000];
        for (uint256 j; j < wanted.length; ++j) {
            if (j != 0) { vm.revertToState(snap); snap = vm.snapshotState(); }
            uint256 word;
            for (word = 1; ; ++word) {
                uint256 roll = uint256(keccak256(abi.encode(word, uint256(0x436f696e447261774d756c7469706c696572)))) % 1000;
                if ((roll < 900 ? 5000 : roll < 990 ? 30000 : roll < 999 ? 200000 : 1000000) == wanted[j]) break;
            }
            _start(word, 15);
            (CrapsBattleStorage.JackpotRound memory r,,) = cold.jackpotBattleOf(slot);
            assertEq(r.awardTarget, 15);
            assertEq(r.totalPool, (80_000 + 142_500 * uint256(r.subsidyMultiplierBps) / 10_000) * wanted[j] / 10_000);
            assertEq(cold.highRollerReserve(), 7_500, "pool multiplier reached reserve");
            vm.prank(ContractAddresses.GAME);
            api.prepareJackpotBattle(2, word + 1);
            assertEq(cold.highRollerReserve(), 7_500, "prepare retry funded twice");
        }
    }

    function test_emptyEventsAccumulateWithoutAnAttempt() public {
        for (uint256 i; i < 3; ++i) {
            if (i != 0) { dayStart += 1 days; _openDay(10); }
            _lock(50_000);
            vm.recordLogs();
            _start(_word(true), 0);
            _assertDrawLog(vm.getRecordedLogs(), 0, address(0), 0, (i + 1) * 2_500);
            CrapsBattleStorage.HighRollerDraw memory d = cold.highRollerDrawOf(slot);
            assertTrue(d.resolved); assertFalse(d.won);
        }
        assertEq(cold.highRollerReserve(), 7_500);
    }

    function test_sdgnrsAndNormalOrAwardedSeatsCannotTriggerTheReserve() public {
        _enter(ContractAddresses.SDGNRS, true, true);
        _enter(ALICE, false, false);
        _lock(50_000); _start(_word(true), 5);
        vm.recordLogs(); _finish(1);
        _assertDrawLog(vm.getRecordedLogs(), 0, address(0), 0, 2_500);
        assertEq(cold.highRollerDrawOf(slot).eligible, 0);
        assertEq(cold.highRollerReserve(), 2_500);
    }

    /// @dev The cold delegate must pay the reserve through creditFlip in the table context.
    function test_vaultCanTriggerAndWinAloneEvenWhenSdgnrsIsHighToo() public {
        _enter(ContractAddresses.SDGNRS, true, true);
        _enter(ContractAddresses.VAULT, true, false);
        _lock(50_000); _start(_word(true), 5);
        uint256 comps = flip.compLane();
        uint256 action = table.dayStaked(day);
        vm.recordLogs(); _finish(1);
        _assertDrawLog(vm.getRecordedLogs(), 1, ContractAddresses.VAULT, 2_500, 0);
        assertEq(cold.highRollerDrawOf(slot).nominee, ContractAddresses.VAULT);
        assertEq(cold.highRollerReserve(), 0);
        assertGe(coinflip.staked(ContractAddresses.VAULT), 2_500);
        assertEq(flip.compLane(), comps, "reserve award generated comps");
        assertEq(table.dayStaked(day), action, "reserve award generated action");
    }

    function test_newcomerPaysItsPremiumAndCanWinTheEntireReserve() public {
        game.setMintHistory(ALICE, 0);
        game.setScore(ALICE, 0);
        _enter(ALICE, true, false);
        assertEq(flip.burned(ALICE), 84_000);
        _lock(50_000); _start(_word(true), 0);
        vm.recordLogs(); _finish(WHOLE_FIELD);
        _assertDrawLog(vm.getRecordedLogs(), 1, ALICE, 2_500, 0);
        assertEq(cold.highRollerDrawOf(slot).nominee, ALICE);
    }

    function test_missAndEmptyDayCarryIntoTheNextWinner() public {
        _enter(ALICE, true, false);
        _lock(50_000); _start(_word(false), 0);
        vm.recordLogs(); _finish(1);
        _assertDrawLog(vm.getRecordedLogs(), 1, address(0), 0, 2_500);
        dayStart += 1 days; _openDay(10);
        _lock(50_000); _start(_word(true), 0);
        assertEq(cold.highRollerReserve(), 5_000);
        dayStart += 1 days; _openDay(100);
        _enter(BOB, true, false);
        _lock(50_000); _start(_word(true), 0);
        vm.recordLogs(); _finish(WHOLE_FIELD);
        _assertDrawLog(vm.getRecordedLogs(), 1, BOB, 7_500, 0);
    }

    function test_upgradesAndCompedHighEntriesQualifyAtTheirAcceptedTerms() public {
        _enter(ALICE, false, true);
        vm.prank(ALICE); table.upgradeDayWindows(day, 1 << 5);
        uint256 code = uint160(BOB) | (uint256(1) << 168) | (uint256(5) << 176);
        flip.setCompLane(1_000_000);
        vm.prank(ContractAddresses.VAULT); table.vaultComp(code);
        assertEq(flip.burned(BOB), 0);
        _lock(50_000); _start(_word(true), 5); _finish(1);
        assertEq(cold.highRollerDrawOf(slot).eligible, 2);
        assertTrue(cold.highRollerDrawOf(slot).won);
    }

    function test_consumedHighPassQualifiesWithoutAnotherPayment() public {
        table.setPassCredits(ALICE, 0, 1);
        vm.prank(ALICE); table.applyCrapsPasses(day + 1, 1, true, 0);
        table.setPassCredits(ContractAddresses.SDGNRS, 1, 0);
        table.setPassCredits(ContractAddresses.VAULT, 1, 0);
        dayStart += 1 days; _openDay(10, true);
        assertEq(flip.burned(ALICE), 0);
        _lock(50_000); _start(_word(true), 0); _finish(1);
        assertEq(cold.highRollerDrawOf(slot).eligible, 1);
        assertEq(cold.highRollerDrawOf(slot).nominee, ALICE);
    }

    function test_lateEntryUpgradeAndDirectHookCannotChangeEligibility() public {
        _enter(ALICE, false, true);
        _lock(50_000);
        vm.prank(ALICE); vm.expectRevert(); table.upgradeDayWindows(day, 1 << 5);
        vm.prank(BOB); vm.expectRevert(); table.enterBonusBattle(5, 0, multiple);
        vm.expectRevert(JackpotBattle.OnlyTableSelf.selector); cold.settleHighRollerReserve(slot);
        _start(_word(true), 0); _finish(1);
        assertEq(cold.highRollerDrawOf(slot).eligible, 0);
    }

    function testFuzz_chunkingAndRetriesCannotChangeTheDraw(uint256 seed, uint8 rawHeads, bool tail) public {
        if (tail) {
            // Accepted window terms are frozen when the day opens.
            dayStart += 1 days;
            _openDay(100);
        }
        uint256 heads = 1 + uint256(rawHeads) % 7;
        for (uint160 i; i < heads; ++i) _enter(address(0x1000 + i), true, i % 2 == 0);
        _enter(ContractAddresses.SDGNRS, true, false);
        _enter(ALICE, false, false);
        _lock(50_000); _start(seed == 0 ? 1 : seed, 5);
        uint256 snap = vm.snapshotState();
        _finish(WHOLE_FIELD);
        CrapsBattleStorage.HighRollerDraw memory one = cold.highRollerDrawOf(slot);
        uint256 credited = coinflip.totalCredited();
        uint256 reserve = cold.highRollerReserve();
        assertEq(one.eligible, heads);
        assertTrue(one.resolved);
        assertGe(uint160(one.nominee), 0x1000); assertLt(uint160(one.nominee), 0x1000 + heads);
        assertEq(one.won, uint256(keccak256(abi.encode(seed == 0 ? 1 : seed, DRAW_TAG, uint256(slot)))) % 10 == 0);
        vm.revertToState(snap);
        _finish(1);
        assertEq(keccak256(abi.encode(cold.highRollerDrawOf(slot))), keccak256(abi.encode(one)));
        assertEq(coinflip.totalCredited(), credited); assertEq(cold.highRollerReserve(), reserve);
        vm.recordLogs();
        table.settleSlot(slot, WHOLE_FIELD);
        vm.prank(ContractAddresses.GAME); cold.runDailyBattleWork(gasleft());
        assertEq(vm.getRecordedLogs().length, 0, "retry attempted another draw");
        assertEq(coinflip.totalCredited(), credited); assertEq(cold.highRollerReserve(), reserve);
    }

    function test_paidFieldLargerThanOneBatchIsBoundedAndPaysOnce() public {
        for (uint160 i; i < 270; ++i) _enter(address(0x1000 + i), true, false);
        _lock(50_000); _start(_word(true), 0);
        vm.recordLogs();
        table.settleSlot(slot, WHOLE_FIELD);
        assertEq(cold.highRollerDrawOf(slot).eligible, 96);
        assertFalse(cold.highRollerDrawOf(slot).resolved);
        assertEq(cold.highRollerReserve(), 2_500);
        _finish(1);
        CrapsBattleStorage.HighRollerDraw memory d = cold.highRollerDrawOf(slot);
        assertEq(d.eligible, 270);
        _assertDrawLog(vm.getRecordedLogs(), 270, d.nominee, 2_500, 0);
    }
}
