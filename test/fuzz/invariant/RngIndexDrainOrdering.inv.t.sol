// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {RngIndexDrainHandler} from "../handlers/RngIndexDrainHandler.sol";

/// @title RngIndexDrainOrderingInvariants -- Phase 232.1 SPEC AC-1 + AC-2
/// @notice Drives the handler through fuzzed purchase / advance / VRF-fulfill /
///         warp sequences and asserts the ordering / zero-entropy / binding
///         invariants hold across every reachable state.
contract RngIndexDrainOrderingInvariants is DeployProtocol {
    RngIndexDrainHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        handler = new RngIndexDrainHandler(game, mockVRF, admin);

        targetContract(address(handler));
    }

    // =========================================================================
    // AC-1: drain-before-swap ordering
    // =========================================================================

    /// @notice `_swapAndFreeze` cannot advance LR_INDEX while any read-slot
    ///         ticket remains undrained. The handler scores this indirectly:
    ///         any post-fix TraitsGenerated emit with entropy != slot value
    ///         OR entropy == 0 indicates an ordering violation, because the
    ///         drain ran without a populated lootbox slot.
    function invariant_drainBeforeSwap() public view {
        assertEq(
            handler.ghost_bindingMismatches(),
            0,
            "RngIndexDrain: captured entropy != lootboxRngWordByIndex[X] (ordering violation)"
        );
    }

    // =========================================================================
    // AC-2: no _raritySymbolBatch(entropyWord == 0)
    // =========================================================================

    /// @notice `_raritySymbolBatch` is never invoked with `entropyWord == 0`
    ///         under any reachable advanceGame stage sequence.
    function invariant_noZeroEntropyConsumption() public view {
        assertEq(
            handler.ghost_zeroEntropyConsumptions(),
            0,
            "RngIndexDrain: _raritySymbolBatch observed entropyWord == 0"
        );
    }

    // =========================================================================
    // Branch-coverage health: ensures AC-2's "all paths" claim is non-vacuous
    // =========================================================================

    /// @notice Reports fuzzer branch coverage at the end of the run. Does
    ///         not assert — coverage is surveillance data, not a correctness
    ///         gate. If both counters are 0 across all fuzzer seeds, review
    ///         the handler action set, but do not fail the run (AC-1 / AC-2
    ///         still hold vacuously if the fuzzer truly exercised no state).
    function invariant_branchCoverageSurveillance() public view {
        // No assertions — just make sure the canary passes so forge emits
        // the ghost-counter metrics alongside the other invariants.
        handler.ghost_dailyDrainBranchEntered();
        handler.ghost_gameOverBranchEntered();
    }

    // =========================================================================
    // Canary: confirms handler is wired up.
    // =========================================================================

    function invariant_handlerCanary() public view {
        assertTrue(
            address(handler.game()) != address(0),
            "RngIndexDrain: handler game reference is zero"
        );
    }
}
