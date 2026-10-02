// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {CrapsPins, MockCoinflip} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {Craps} from "../../contracts/Craps.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

interface ICohortTableFixture {
    function rngCohortComplete(uint48 index) external view returns (bool);
    function keepRngCohort(uint48 index, uint64 budget) external returns (bool moved, bool settled);
}

contract CustomCohortRecyclingTest is CrapsPins {
    CrapsViews table;
    ICohortTableFixture cohort;
    address alice;
    function setUp() public {
        _installPins();
        table = new CrapsViews();
        cohort = ICohortTableFixture(address(table));
        alice = makeAddr("cohort-alice");
        vm.prank(vaultOwner);
        table.setBattleCreator(address(this), true);
        _setIndex(0);
    }
    function _create() private returns (uint64) {
        return table.createBattle(300, 2, 5, 0, uint40(vm.getBlockTimestamp() + 60), true, 0);
    }
    function _enter(uint64 slot) private {
        vm.prank(alice);
        table.enterBattle(slot, uint32(0), 1);
    }
    function test_CustomCloseHorizonBoundsFundedCapacityOccupancy() public {
        uint40 latest = uint40(vm.getBlockTimestamp() + 7 days);
        vm.expectRevert(CrapsBattleStorage.BadBattleTerms.selector);
        table.createBattle(300, 2, 5, 0, latest + 1, true, 0);
        uint64 slot = table.createBattle(300, 2, 5, 0, latest, true, 0);
        _enter(slot);
        vm.warp(latest);
        uint48 index = table.closeBattle(slot);
        _setWord(index, 0xB0B5);
        cohort.keepRngCohort(index, 20_000);
        assertTrue(cohort.rngCohortComplete(index), "permissionless completion releases the admitted field");
    }
    function test_CustomArmRegistersHashedFieldAndKeeperFinishesIt() public {
        uint64 slot = _create();
        _enter(slot);
        vm.warp(block.timestamp + 60);
        uint48 index = table.closeBattle(slot);
        (bytes32 key,,) = table.customBattleOf(slot);
        assertTrue(key != bytes32(uint256(slot)), "fixture must use the custom hash key");
        assertFalse(cohort.rngCohortComplete(index), "custom field is a read consumer");
        _setWord(index, uint256(keccak256("custom read word")) | 1);
        (bool moved, bool settled) = cohort.keepRngCohort(index, 20_000);
        assertTrue(moved);
        assertTrue(settled);
        assertTrue(table.battleOf(key).finalized, "all payout effects finished");
        assertTrue(cohort.rngCohortComplete(index));
        table.resolveSlot(slot, 20_000); // spent check succeeds without discharging twice
        assertTrue(cohort.rngCohortComplete(index));
    }
    function _pendingBit(uint48 index) private view returns (bool) {
        return uint256(game.slots(bytes32(uint256(33)))) & (uint256(1) << (250 + (index & 1))) != 0;
    }
    function test_GameMirrorClearsOnlyAfterEveryFieldAtIndexSettles() public {
        uint64 a = _create(); uint64 b = _create();
        _enter(a); _enter(b);
        vm.warp(block.timestamp + 60);
        uint48 index = table.closeBattle(a);
        assertTrue(_pendingBit(index));
        // Both fields were committed before the same request, as when the real request
        // is ineligible until the previous read cohort drains.
        _setIndex(index);
        assertEq(table.closeBattle(b), index);
        _setWord(index, 0xB0B5);
        table.resolveSlot(a, 20_000);
        assertFalse(cohort.rngCohortComplete(index));
        assertTrue(_pendingBit(index), "first completed field cannot release the shared Game gate");
        table.resolveSlot(b, 20_000);
        assertTrue(cohort.rngCohortComplete(index));
        assertFalse(_pendingBit(index));
    }
    function test_FailedSettlementPreservesFieldCapacityAndGameFlag() public {
        uint64 slot = _create(); _enter(slot);
        vm.warp(block.timestamp + 60);
        uint48 index = table.closeBattle(slot);
        _setWord(index, 0xB0B5);
        Craps.SlipResult memory win; win.bankrollIn = 1 ether; win.bankrollOut = 1 ether;
        vm.mockCall(ContractAddresses.CRAPS_ENGINE, abi.encodeWithSelector(CrapsEngine.settleBattle.selector), abi.encode(win));
        vm.mockCallRevert(ContractAddresses.COINFLIP, abi.encodeWithSelector(MockCoinflip.creditFlipBatch.selector), "payout failure");
        vm.expectRevert(); cohort.keepRngCohort(index, 20_000);
        assertFalse(cohort.rngCohortComplete(index));
        assertTrue(_pendingBit(index));
        (bytes32 key,,) = table.customBattleOf(slot);
        assertFalse(table.battleOf(key).finalized);
        vm.clearMockedCalls();
        cohort.keepRngCohort(index, 20_000);
        assertTrue(cohort.rngCohortComplete(index));
        assertFalse(_pendingBit(index));
    }
    function test_TerminalRequestKillsUnfinishedCrapsWithoutUsingTerminalEntropy() public {
        uint64 slot = _create();
        _enter(slot);
        vm.warp(block.timestamp + 60);
        uint48 index = table.closeBattle(slot);
        _setWord(index, 0xB0B5);
        // A delivered old read cannot settle once the terminal latch is set.
        uint256 state = uint256(game.slots(bytes32(0)));
        game.set(bytes32(0), bytes32(state | (uint256(1) << 253)));
        (bool moved, bool settled) = cohort.keepRngCohort(index, 20_000);
        assertFalse(moved || settled);
        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        table.resolveSlot(slot, 20_000);
        // Neither the retained payload nor a new terminal fulfillment resurrects it.
        _setIndex(index ^ 1);
        assertFalse(cohort.rngCohortComplete(index));
        (moved, settled) = cohort.keepRngCohort(index, 20_000);
        assertFalse(moved || settled);
        game.set(bytes32(uint256(3)), bytes32(uint256(0xCAFE)));
        _setWord(index ^ 1, 0xCAFE);
        (moved, settled) = cohort.keepRngCohort(index, 20_000);
        assertFalse(moved || settled);
        (bytes32 key,,) = table.customBattleOf(slot);
        assertFalse(table.battleOf(key).finalized);
    }
    function test_SpentBattleCannotDischargeNewPendingFieldWhenItsBufferIsReused() public {
        uint64 old;
        uint48 first;
        for (uint256 cycle; cycle < 3; ++cycle) {
            uint64 slot = _create(); _enter(slot);
            vm.warp(vm.getBlockTimestamp() + 60);
            uint48 buffer = table.closeBattle(slot);
            _setWord(buffer, cycle + 42);
            assertTrue(_pendingBit(buffer));
            if (cycle == 0) { old = slot; first = buffer; }
            if (cycle == 2) {
                assertEq(buffer, first, "fixture has reused the old physical buffer");
                table.resolveSlot(old, 20_000);
                assertTrue(_pendingBit(buffer), "spent battle cannot clear the new field's pending bit");
                assertFalse(cohort.rngCohortComplete(buffer));
            }
            cohort.keepRngCohort(buffer, 20_000);
            assertTrue(cohort.rngCohortComplete(buffer));
            assertFalse(_pendingBit(buffer));
        }
    }
    function test_FifthFundedFieldRejectedBeforeBurnAndCompleteFieldReleasesCapacity() public {
        uint64[5] memory slots;
        for (uint256 i; i < 5; ++i) slots[i] = _create();
        for (uint256 i; i < 4; ++i) _enter(slots[i]);
        uint256 burned = flip.totalBurned();
        vm.expectRevert(JackpotBattle.BadJackpotField.selector);
        _enter(slots[4]);
        assertEq(flip.totalBurned(), burned, "capacity rejection took no funds");
        vm.warp(block.timestamp + 60);
        uint48 index = table.closeBattle(slots[0]);
        _setWord(index, uint256(keccak256("release capacity")) | 1);
        table.resolveSlot(slots[0], 20_000);
        // New admission is a future write field, so use a newly-created open battle.
        uint64 next = _create();
        _enter(next);
        assertGt(flip.totalBurned(), burned);
    }
    function test_MoreThan64RepeatEntriesAllowedAndPartialSettlementKeepsGateClosed() public {
        uint64 slot = _create();
        for (uint256 i; i < 65; ++i) _enter(slot);
        vm.warp(block.timestamp + 60);
        uint48 index = table.closeBattle(slot);
        _setWord(index, uint256(keccak256("large custom field")) | 1);
        table.resolveSeats(slot, 1);
        assertFalse(cohort.rngCohortComplete(index), "one settled seat cannot complete the field");
        for (uint256 i; i < 65 && !cohort.rngCohortComplete(index); ++i) cohort.keepRngCohort(index, 20_000);
        assertTrue(cohort.rngCohortComplete(index));
    }
}
