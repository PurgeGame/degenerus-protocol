// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

contract MinerRewardScheduleHarness is DegenerusGameMinerModule {
    function terms(uint256 elapsed) external pure returns (uint256 capWei, uint256 multiplierBps) {
        return _minerRewardTerms(elapsed);
    }

    function dueAt() external view returns (uint256) {
        return _minerRewardDueAt();
    }

    function holdsPass(address miner) external view returns (bool) {
        return _minerHoldsActivePass(miner);
    }

    function seedPass(address miner, uint256 packed, uint24 currentLevel) external {
        mintPacked_[miner] = packed;
        level = currentLevel;
    }

    function seed(uint24 processedDay, uint24 preparationDay, uint48 requestTime) external {
        dailyIdx = processedDay;
        _afkingResetDay = preparationDay;
        rngRequestTime = requestTime;
        _rearmRngRetry();
    }

    function markRetrySpent() external {
        _spendRngRetry();
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
        _assertTerms(0, 0.5 gwei, 3000);
        _assertTerms(1799, 0.5 gwei, 3000);
        _assertTerms(1800, 1 gwei, 7500);
        _assertTerms(3599, 1 gwei, 7500);
        _assertTerms(3600, 2 gwei, 12000);
        _assertTerms(5399, 2 gwei, 12000);
        _assertTerms(5400, 4 gwei, 16500);
        _assertTerms(7199, 4 gwei, 16500);
        _assertTerms(7200, 8 gwei, 21000);
        _assertTerms(7201, 8 gwei, 21000);
        _assertTerms(type(uint256).max, 8 gwei, 21000);
    }

    function testFuzz_SaturatedTermsDoNotOverflow(uint256 elapsed) public view {
        elapsed = bound(elapsed, 2 hours, type(uint256).max);
        _assertTerms(elapsed, 8 gwei, 21000);
    }

    function _packedPass(uint256 passType, uint256 frozenUntil) private pure returns (uint256) {
        return (passType << BitPackingLib.WHALE_PASS_TYPE_SHIFT)
            | (frozenUntil << BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT);
    }

    function _holds(uint256 packed, uint24 currentLevel) private returns (bool) {
        address miner = makeAddr("pass-miner");
        harness.seedPass(miner, packed, currentLevel);
        return harness.holdsPass(miner);
    }

    function test_ActivePassWindowMatchesTheActivityScore() public {
        assertFalse(_holds(0, 7), "no pass");
        assertTrue(_holds(uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT, 900), "deity pass never expires");
        assertTrue(_holds(_packedPass(1, 12), 3), "lazy pass inside its window");
        assertTrue(_holds(_packedPass(1, 12), 12), "lazy pass on its last level");
        assertFalse(_holds(_packedPass(1, 12), 13), "lazy pass after its window");
        assertTrue(_holds(_packedPass(3, 110), 50), "whale pass inside its window");
        assertFalse(_holds(_packedPass(3, 110), 111), "whale pass after its window");
        assertFalse(_holds(_packedPass(2, 500), 3), "type 2 is not a pass");
        assertFalse(_holds(_packedPass(0, 500), 3), "a frozen level alone is not a pass");
    }

    function _reset() private view returns (uint256) {
        return block.timestamp - (block.timestamp - 82_620) % 1 days;
    }

    function test_LaterRequestIsTheClockForEveryAction() public {
        vm.warp(30 days + 5 hours);
        uint48 request = uint48(_reset() + 2 hours);
        harness.seed(27, 28, request);
        assertEq(harness.dueAt(), request, "work waits from the request");
        harness.markRetrySpent();
        assertEq(harness.dueAt(), request, "a retry keeps the request's origin");
        vm.warp(block.timestamp + 6 hours);
        assertEq(harness.dueAt(), request, "a late miner cannot restart the clock");
    }

    function test_ResetIsTheClockWhenTheLastRequestIsOlder() public {
        vm.warp(30 days + 5 hours);
        harness.seed(27, 28, uint48(_reset() - 20 hours));
        assertEq(harness.dueAt(), _reset(), "reset-time work starts at the base rate");
        harness.seed(27, 31, 1);
        assertEq(harness.dueAt(), _reset(), "no request yet still uses the reset");
    }

    function test_ClockIgnoresCallerProgress() public {
        vm.warp(30 days + 5 hours);
        uint48 request = uint48(_reset() + 1 hours);
        harness.seed(27, 27, request);
        uint256 due = harness.dueAt();
        harness.seed(28, 31, request);
        assertEq(harness.dueAt(), due, "daily progress never moves the clock");
    }
}
