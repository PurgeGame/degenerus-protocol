// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {Craps} from "../../contracts/Craps.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipBudget} from "../../contracts/libraries/MineFlipBudget.sol";

contract CrapsGlobalWorkOrderTest is CrapsPins {
    CrapsViews private table;
    JackpotBattle private cohort;
    uint64 private first;
    uint64 private second;
    uint48 private index;

    function setUp() public {
        _installPins();
        table = new CrapsViews();
        cohort = JackpotBattle(address(table));
        vm.prank(vaultOwner);
        table.setBattleCreator(address(this), true);
        first = table.createBattle(300, 2, 5, 0, uint40(block.timestamp + 60), true, 0);
        second = table.createBattle(300, 2, 5, 0, uint40(block.timestamp + 60), true, 0);
        table.enterBattle(first, 0, 1);
        table.enterBattle(second, 0, 1);
        vm.warp(block.timestamp + 60);
        index = table.closeBattle(first);
        _setIndex(index);
        assertEq(table.closeBattle(second), index);
        _setWord(index, 0xC0FFEE);
    }

    function test_EarlierCategoriesBlockEveryManualReadSettlementDoor() public {
        for (uint8 stage; stage < 5; ++stage) {
            game.setRngConsumerStage(stage);
            (bool moved, bool settled, uint64 charged) = cohort.keepRngCohortBudgeted(index, 1_824);
            assertFalse(moved);
            assertFalse(settled);
            assertEq(charged, 0);
            vm.expectRevert(LootboxCraps.RngNotReady.selector);
            table.resolveSlot(first, 1_824);
            table.keepScheduled(1_824);
            assertEq(table.bonusCursorOf(first), 0);
        }
        game.setRngConsumerStage(5);
        table.resolveSlot(first, 1_824);
        assertEq(table.bonusCursorOf(first), 1);
    }

    function test_CustomCallerCannotChooseLaterCommittedField() public {
        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        table.resolveSlot(second, 1_824);
        table.resolveSlot(first, 1_824);
        assertEq(table.bonusCursorOf(second), 0);
        table.resolveSlot(second, 1_824);
        assertTrue(table.rngCohortComplete(index));
        table.resolveSlot(first, 1_824); // Paid historical fields cannot discharge twice.
        assertTrue(table.rngCohortComplete(index));
    }

    function test_ReservesMaximumRollAndFinalizationCostBeforeSeat() public {
        Craps.SlipResult memory r;
        r.bankrollIn = 1 ether;
        r.bankrollOut = 1 ether;
        r.peakBankroll = 2 ether;
        r.totalRolls = 1_111;
        r.unitsPlayed = (uint256(1) << 104) | 100;
        r.stop = Craps.SlipStop.Goal;
        vm.mockCall(ContractAddresses.CRAPS_ENGINE,
            abi.encodeWithSelector(CrapsEngine.settleBattle.selector), abi.encode(r));
        // 4 cohort + 12 batch + 7 seat + 185 rolls + 6 credit + 6 final + 64 tail.
        (bool moved, bool settled, uint64 charged) = cohort.keepRngCohortBudgeted(index, 283);
        assertFalse(moved);
        assertFalse(settled);
        assertLe(charged, 283);
        assertEq(table.bonusCursorOf(first), 0);
        (moved, settled, charged) = cohort.keepRngCohortBudgeted(index, 284);
        assertTrue(moved);
        assertTrue(settled);
        assertEq(charged, 284);
        assertEq(table.bonusCursorOf(first), 1);
        assertEq(table.bonusCursorOf(second), 0);
    }

    function testFuzz_ChargedWorkNeverExceedsClampedAllowance(uint64 allowance) public {
        (,, uint64 charged) = cohort.keepRngCohortBudgeted(index, allowance);
        assertLe(charged, MineFlipBudget.clamp(allowance));
    }

    function test_ZeroBudgetLeavesSettlementAndLifecycleUntouched() public {
        uint64 keeper = table.keeperSlot();
        (bool moved, bool settled, uint64 charged) = cohort.keepRngCohortBudgeted(index, 0);
        assertFalse(moved);
        assertFalse(settled);
        assertEq(charged, 0);
        (bool progressed, uint64 afterKeeper, uint64 used) = table.keepScheduledBudgeted(0);
        assertFalse(progressed);
        assertEq(afterKeeper, keeper);
        assertEq(used, 0);
        assertEq(table.bonusCursorOf(first), 0);
    }
}
