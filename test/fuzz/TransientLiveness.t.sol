// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract TransientLivenessHarness is DegenerusGameStorage {
    function seed(uint24 lvl, uint24 daysComplete, bool complete, uint48 completedAt) external {
        level = lvl;
        purchaseStartDay = 9;
        dailyIdx = 9 + daysComplete;
        dailyComplete = complete;
        lastDailyCompletedAt = completedAt;
        lastDailyRequestWallDay = _wallDayAt(completedAt);
        _setLevelPrizePool(lvl, 10 ether);
        _setPrizePools(9 ether, 0);
    }
    function pool(uint128 amount) external { _setPrizePools(amount, 0); }
    function phase(uint8 which) external { lastPurchaseDay = which == 1; jackpotPhaseFlag = which == 2; }
    function latch() external { _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1); _setRngTerminal(); }
    function commitment(uint48 time, bool published) external {
        rngRequestTime = time; rngRequestDay = dailyIdx;
        _setRngRequestActive(true); _setRngSessionPublished(published);
        rngWordCurrent = published ? 777 : 1;
    }
    function liveness() external view returns (bool) { return _livenessTriggered(); }
    function reason() external view returns (EndingReason) { return _endingReason(); }
    function distress() external view returns (bool) { return _isDistressMode(); }
}

contract TransientLivenessUnitTest is Test {
    TransientLivenessHarness private h;
    function setUp() public { vm.warp(1000 days + 12 hours); h = new TransientLivenessHarness(); }
    function test_UnattendedDeadlineCannotThawAtLaterReset() public {
        h.seed(5, 30, true, uint48(vm.getBlockTimestamp() - 1 days));
        assertTrue(h.liveness());
        vm.warp(vm.getBlockTimestamp() + 3 days);
        assertTrue(h.liveness());
    }
    function test_TargetRescueOnlyBeforeLatch() public {
        h.seed(5, 30, true, uint48(vm.getBlockTimestamp() - 1 days));
        assertTrue(h.liveness());
        h.pool(11 ether); assertFalse(h.liveness());
        h.latch(); assertTrue(h.liveness());
    }
    function test_HardStallIgnoresTargetRescueAndPhase() public {
        for (uint8 phase; phase < 3; ++phase) {
            h.seed(5, 0, false, uint48(vm.getBlockTimestamp() - 14 days));
            h.pool(100 ether); h.phase(phase);
            assertEq(uint8(h.reason()), uint8(DegenerusGameStorage.EndingReason.HardStall));
        }
    }
    function test_PendingThirtiethDayFinishesBeforePurchaseEnding() public {
        h.seed(5, 30, false, uint48(vm.getBlockTimestamp() - 1 days));
        h.commitment(uint48(vm.getBlockTimestamp()), true);
        assertFalse(h.liveness());
    }
    function test_PublishedWordCannotExtendHardDeadline() public {
        h.seed(5, 3, false, uint48(vm.getBlockTimestamp() - 14 days));
        h.commitment(uint48(vm.getBlockTimestamp()), true);
        assertTrue(h.liveness());
    }
    function test_RequestRetryCannotExtendHardDeadline() public {
        h.seed(5, 3, false, uint48(vm.getBlockTimestamp() - 14 days));
        h.commitment(uint48(vm.getBlockTimestamp()), false);
        assertTrue(h.liveness());
    }
}
