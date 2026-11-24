// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {RunFloors} from "./RunFloors.sol";

contract RunFloorsProbe {
    function check(string memory name, bool met) external {
        RunFloors.check(name, met, "vacuous: probe floor");
    }

    function checkIf(string memory name, bool applies, bool met) external {
        RunFloors.checkIf(name, applies, met, "vacuous: probe floor");
    }
}

/// @dev Same calls, different code: a separate contract keeps a separate tally.
contract RunFloorsOtherProbe {
    function check(string memory name, bool met) external {
        RunFloors.check(name, met, "vacuous: other probe floor");
    }

    function marker() external pure returns (uint256) {
        return 1;
    }
}

contract RunFloorsTest is Test {
    RunFloorsProbe internal probe;
    RunFloorsOtherProbe internal other;

    function setUp() public {
        probe = new RunFloorsProbe();
        other = new RunFloorsOtherProbe();
    }

    /// @dev Tallies live in the process environment, so every test names its own floor.
    function _key(string memory test) internal pure returns (string memory) {
        return string.concat("RunFloorsTest_", test);
    }

    function test_FloorNeverMetFailsOnceJudged() public {
        string memory name = _key("never");
        for (uint256 i = 1; i < RunFloors.MIN_RUNS; ++i) probe.check(name, false);
        vm.expectRevert(bytes("vacuous: probe floor: met in 0 of 16 runs"));
        probe.check(name, false);
    }

    function test_FloorMetInHalfTheRunsPasses() public {
        string memory name = _key("half");
        for (uint256 i; i < 32; ++i) probe.check(name, i % 2 == 0);
    }

    function test_FloorMetInFewerThanHalfFails() public {
        string memory name = _key("few");
        for (uint256 i; i < 15; ++i) probe.check(name, i < 7);
        vm.expectRevert(bytes("vacuous: probe floor: met in 7 of 16 runs"));
        probe.check(name, false);
    }

    function test_OneIdleRunDoesNotFail() public {
        string memory name = _key("idle");
        probe.check(name, false);
        for (uint256 i; i < 63; ++i) probe.check(name, true);
    }

    function test_InapplicableRunsAreNotCounted() public {
        string memory name = _key("applies");
        for (uint256 i; i < 40; ++i) probe.checkIf(name, false, false);
        for (uint256 i = 1; i < RunFloors.MIN_RUNS; ++i) probe.checkIf(name, true, false);
        vm.expectRevert(bytes("vacuous: probe floor: met in 0 of 16 runs"));
        probe.checkIf(name, true, false);
    }

    function test_ContractsKeepSeparateTallies() public {
        string memory name = _key("separate");
        for (uint256 i; i < 32; ++i) other.check(name, true);
        for (uint256 i = 1; i < RunFloors.MIN_RUNS; ++i) probe.check(name, false);
        vm.expectRevert(bytes("vacuous: probe floor: met in 0 of 16 runs"));
        probe.check(name, false);
    }
}
