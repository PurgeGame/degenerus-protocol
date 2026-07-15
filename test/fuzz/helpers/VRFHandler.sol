// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";

/// @title VRFHandler -- Handler contract wrapping VRF mock for invariant tests
/// @notice Designed for reuse in Phase 15+ invariant tests. The fuzzer calls
///         fulfillVrf with random words, driving the game through VRF-gated
///         state transitions.
contract VRFHandler is Test {
    MockVRFCoordinator public vrf;
    DegenerusGame public game;

    /// @notice Ghost variable tracking successful VRF fulfillments
    uint256 public ghost_vrfFulfillments;

    constructor(MockVRFCoordinator vrf_, DegenerusGame game_) {
        vrf = vrf_;
        game = game_;
    }

    /// @notice Attempt to fulfill the latest pending VRF request
    /// @param randomWord The random word to fulfill with (fuzz input)
    function fulfillVrf(uint256 randomWord) external {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return; // no requests ever made

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return; // already fulfilled

        try vrf.fulfillRandomWords(reqId, randomWord) {
            ghost_vrfFulfillments++;
        } catch {
            // Ignore errors (e.g., callback reverts)
        }
    }

    /// @notice Warp past the VRF retry timeout (18 hours + 1 second)
    function warpPastVrfTimeout() external {
        vm.warp(block.timestamp + 18 hours + 1);
    }

    /// @notice Warp time by a bounded delta
    /// @param delta Raw delta, bounded to [1 minute, 30 days]
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 30 days);
        vm.warp(block.timestamp + delta);
    }
}
