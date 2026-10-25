// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {LogicalDaysFixture} from "../fuzz/helpers/LogicalDaysFixture.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

contract LogicalCrapsDaysTest is LogicalDaysFixture {
    function test_CommittedCustomTableEndsAtHardEnding() public {
        vm.mockCall(ContractAddresses.VAULT, abi.encodeWithSignature("isVaultOwner(address)", address(this)), abi.encode(true));
        uint64 slot = crapsBattle.createBattle(100, 5, 10, 1, uint40(vm.getBlockTimestamp() + 1 hours), true, 0);
        address player = address(0xA11CE);
        uint32 id = _giveWalletId(player);
        vm.prank(ContractAddresses.GAME); coin.mintForGame(player, 1_000_000);
        vm.prank(player); crapsBattle.enterBattle(id, slot, 0, 1);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        crapsBattle.closeBattle(slot);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 request = _requestLogical();
        mockVRF.fulfillRandomWords(request, 0xC0FFEE);
        (,,uint48 completed) = game.dailySessionState();
        vm.warp(uint256(completed) + 14 days);
        for (uint256 i; i < 100 && !game.gameOver(); ++i) game.mineFlip(0);
        assertTrue(game.gameOver());
        assertEq(crapsBattle.bonusCursorOf(slot), 0, "terminal Game never executes the battle");
        // No terminal settlement door remains, and normal work never resumes the table.
        for (uint256 i; i < 30; ++i) {
            (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            ok; // Completed terminal work may report NoWork; no call may resume the table.
        }
        assertEq(crapsBattle.bonusCursorOf(slot), 0);
    }
    function test_UnservedResetPausesScheduledAdmissions() public {
        _nextLogical(777);
        _nextLogical(779);
        assertTrue(game.dailyScheduleOpen_g214());
        uint24 logical = crapsBattle.currentDayIndex();
        vm.warp(vm.getBlockTimestamp() + 3 days);
        assertEq(crapsBattle.currentDayIndex(), logical);
        assertFalse(game.dailyScheduleOpen_g214());
        (uint24 before,) = crapsBattle.bonusDayOf();
        vm.prank(ContractAddresses.GAME); crapsBattle.openBonusDay();
        (uint24 afterDay,) = crapsBattle.bonusDayOf();
        assertEq(afterDay, before);
    }
    function test_LateOpeningAnnouncesOnlyRemainingPeriods() public {
        _nextLogical(777);
        vm.warp(vm.getBlockTimestamp() + 1 days + 8 hours);
        uint256 request = _requestLogical();
        mockVRF.fulfillRandomWords(request, 779);
        vm.recordLogs();
        _finishLogical();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("CrapsBonusOpened(bytes32,uint48,uint256,uint128,uint128,uint256,uint256)");
        uint256 opened;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(crapsBattle) || logs[i].topics[0] != topic) continue;
            uint256 slot = uint256(logs[i].topics[2]);
            assertGe(slot % crapsBattle.BONUS_SLOTS_PER_DAY(), 3, "elapsed opener and first routine never reopen");
            ++opened;
        }
        assertGt(opened, 0);
    }
}
