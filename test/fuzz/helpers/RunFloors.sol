// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";

/// @title RunFloors
/// @notice Campaign-level progress floors for invariant suites.
/// @dev A progress floor (entries made, fields settled, words delivered) shows that a campaign exercised
///      the state its properties read. One run of random calls can legitimately miss a floor while every
///      property holds, so a floor is never asserted on a single run. Each floor is tallied over the forge
///      process instead (vm.setEnv): once `MIN_RUNS` runs it applies to have completed, at least half of
///      them must have met it. The key includes the test contract's code hash, so a suite and a subclass
///      variant in the same process keep separate tallies.
library RunFloors {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Runs a floor must apply to before it is judged.
    uint256 internal constant MIN_RUNS = 16;

    /// @notice Tally this run against floor `name` and judge the floor once it has `MIN_RUNS` runs.
    function check(string memory name, bool met, string memory reason) internal {
        checkIf(name, true, met, reason);
    }

    /// @notice As `check`, for a floor that only applies to some runs: a run where `applies` is false is
    ///         neither counted nor judged.
    function checkIf(string memory name, bool applies, bool met, string memory reason) internal {
        if (!applies) return;
        string memory key = string.concat("RF_", vm.toString(uint256(address(this).codehash) >> 224), "_", name);
        uint256 runs = _bump(string.concat(key, "_RUNS"), 1);
        uint256 hits = _bump(string.concat(key, "_MET"), met ? 1 : 0);
        if (runs >= MIN_RUNS && hits * 2 < runs) {
            revert(string.concat(reason, ": met in ", vm.toString(hits), " of ", vm.toString(runs), " runs"));
        }
    }

    function _bump(string memory key, uint256 v) private returns (uint256 total) {
        total = vm.envOr(key, uint256(0)) + v;
        vm.setEnv(key, vm.toString(total));
    }
}
