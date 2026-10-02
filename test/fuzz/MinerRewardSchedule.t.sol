// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract MinerRewardScheduleHarness is DegenerusGameMinerModule {
    function terms(uint256 elapsed) external pure returns (uint256 capWei, uint256 multiplierBps) {
        return _minerRewardTerms(elapsed);
    }

    function dueAt(MinerAction action) external view returns (uint256) {
        return _minerRewardDueAt(action);
    }

    function seed(uint24 processedDay, uint24 preparationDay, uint48 requestTime, uint48 readyAt) external {
        dailyIdx = processedDay;
        _afkingResetDay = preparationDay;
        rngRequestTime = requestTime;
        _lrWrite(LR_WORK_READY_SHIFT, LR_WORK_READY_MASK, readyAt);
    }
}

/// @notice The approved economic table and every category's independent age source.
contract MinerRewardScheduleTest is Test {
    MinerRewardScheduleHarness private harness;

    function setUp() public { harness = new MinerRewardScheduleHarness(); }

    function _assertTerms(uint256 elapsed, uint256 cap, uint256 multiplier) private view {
        (uint256 actualCap, uint256 actualMultiplier) = harness.terms(elapsed);
        assertEq(actualCap, cap, "base fee cap differs from the approved schedule");
        assertEq(actualMultiplier, multiplier, "FLIP multiplier differs from the approved schedule");
    }

    function test_ExactHalfHourBoundariesAndTwoHourSaturation() public view {
        _assertTerms(0, 0.5 gwei, 7500);
        _assertTerms(1799, 0.5 gwei, 7500);
        _assertTerms(1800, 1 gwei, 12500);
        _assertTerms(3599, 1 gwei, 12500);
        _assertTerms(3600, 2 gwei, 17500);
        _assertTerms(5399, 2 gwei, 17500);
        _assertTerms(5400, 4 gwei, 22500);
        _assertTerms(7199, 4 gwei, 22500);
        _assertTerms(7200, 8 gwei, 27500);
        _assertTerms(7201, 8 gwei, 27500);
        _assertTerms(type(uint256).max, 8 gwei, 27500);
    }

    function testFuzz_SaturatedTermsDoNotOverflow(uint256 elapsed) public view {
        elapsed = bound(elapsed, 2 hours, type(uint256).max);
        _assertTerms(elapsed, 8 gwei, 27500);
    }

    function test_EveryReadConsumerUsesTheAcceptedCallbackAnchor() public {
        harness.seed(27, 28, 100_000, 200_000);
        for (uint8 action = uint8(DegenerusGameStorage.MinerAction.Publish);
            action <= uint8(DegenerusGameStorage.MinerAction.CertifyRead); ++action) {
            assertEq(harness.dueAt(DegenerusGameStorage.MinerAction(action)), 200_000);
        }
        harness.seed(28, 29, 300_000, 200_000);
        for (uint8 action = uint8(DegenerusGameStorage.MinerAction.Publish);
            action <= uint8(DegenerusGameStorage.MinerAction.CertifyRead); ++action) {
            assertEq(harness.dueAt(DegenerusGameStorage.MinerAction(action)), 200_000);
        }
    }

    function test_DailyAgeStartsAtEarliestOwedResetAndIgnoresPreparationProgress() public {
        harness.seed(27, 27, 100_000, 1);
        uint256 expected = (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 27) * 1 days + 82_620;
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.PrepareSubscriptions), expected);
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.RequestDaily), expected);
        harness.seed(27, 31, 300_000, 200_000);
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.PrepareSubscriptions), expected, "late first miner cannot start a new reward clock");
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.RequestDaily), expected, "partially completed preparation cannot reset age");
        harness.seed(28, 31, 300_000, 200_000);
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.RequestDaily), expected + 1 days, "completed daily obligation advances the clock");
    }

    function test_MaintenanceUsesItsActionableHeadDeadline() public {
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenanceDueAt()"), abi.encode(123_456));
        harness.seed(27, 28, 100_000, 200_000);
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.Maintenance), 123_456);
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenanceDueAt()"), abi.encode(0));
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.Maintenance), 0, "empty bookkeeping has no invented old deadline");
    }

    function test_OptionalRequestCannotInheritAnOldReadClock() public {
        harness.seed(27, 28, 100_000, 1);
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.RequestMidday), 0);
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.Idle), 0);
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.Terminal), 0);
        assertEq(harness.dueAt(DegenerusGameStorage.MinerAction.Wait), 0);
    }
}
