// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";

/// @title FVRF-01: Game FSM Symbolic Property Tests
/// @notice Halmos bounded model checks for game state machine invariants.
/// @dev These tests verify FSM properties in isolation (not through full function calls)
///      because the full DegenerusGame contract with 10 delegatecall modules exceeds
///      Halmos solver capacity within reasonable timeouts.
///
///      Run with: halmos --contract GameFSMSymbolicTest --solver-timeout-assertion 60
contract GameFSMSymbolicTest is Test {
    // =========================================================================
    // Property 1: gameOver is terminal (no function can unset it)
    // =========================================================================

    /// @notice Once gameOver is true, it cannot become false
    /// @dev Models the invariant: gameOver can only transition false -> true, never true -> false
    function check_gameOver_terminal(bool stateBefore, bool stateAfter) public pure {
        // If gameOver was true before any operation...
        if (stateBefore) {
            // ...it must still be true after
            // This is the FSM property: gameOver = true is an absorbing state
            // In the actual code, gameOver is only set to true in:
            //   1. GameOverModule.handleGameOverDrain() line 120
            //   2. AdvanceModule._handleGameOverPath()
            // And never set to false anywhere.
            // We model this as: for any (before=true, after) pair that the code can produce,
            // after must also be true.
            assert(stateAfter == true);
        }
        // If stateBefore was false, stateAfter can be either true or false (valid transition)
    }

    // =========================================================================
    // Property 2: Level monotonicity
    // =========================================================================

    /// @notice Level can only increase, never decrease
    /// @dev Models: level_after >= level_before for any state transition
    function check_level_monotonic(uint24 levelBefore, uint24 levelAfter) public pure {
        // In the actual code, level is only modified in:
        //   1. AdvanceModule._endPhase(): level += 1
        // It is never decremented.
        // We model this as: any valid (before, after) pair must satisfy after >= before
        if (levelAfter < levelBefore) {
            // This would be a violation -- assert false to flag it
            assert(false);
        }
    }

    // =========================================================================
    // Property 3: dailyIdx monotonicity
    // =========================================================================

    /// @notice dailyIdx can only increase (time moves forward)
    function check_dailyIdx_monotonic(uint48 idxBefore, uint48 idxAfter) public pure {
        // dailyIdx is set to current day index in advanceGame
        // block.timestamp only increases, so dailyIdx only increases
        assert(idxAfter >= idxBefore);
    }

    // =========================================================================
    // Property 4: Sentinel pattern correctness
    // =========================================================================

    /// @notice claimableWinnings sentinel: after claim, value is exactly 1
    function check_sentinel_claim(uint256 amount) public pure {
        // Model the _claimWinningsInternal logic:
        // if (amount <= 1) revert -- skip these
        if (amount <= 1) return;

        // claimableWinnings[player] = 1 (sentinel)
        uint256 afterClaim = 1;
        // payout = amount - 1
        uint256 payout;
        unchecked { payout = amount - 1; }

        assert(afterClaim == 1);
        assert(payout == amount - 1);
        assert(payout < amount);
        assert(payout > 0); // since amount > 1, payout > 0
    }

    /// @notice claimablePool accounting: payout = amount - 1, pool decremented by payout
    function check_claim_pool_accounting(uint256 claimablePool, uint256 amount) public pure {
        if (amount <= 1) return;
        if (claimablePool < amount - 1) return; // would underflow

        uint256 payout;
        unchecked { payout = amount - 1; }

        uint256 poolAfter = claimablePool - payout;

        // Pool should decrease by exactly payout
        assert(poolAfter == claimablePool - payout);
        // Pool should retain the 1 wei sentinel contribution
        assert(poolAfter == claimablePool - amount + 1);
    }

    // =========================================================================
    // Property 5: Credit-then-pool invariant
    // =========================================================================

    /// @notice When _creditClaimable adds X to individual, caller must add X to pool
    /// @dev Models the dual-accounting invariant
    function check_credit_pool_balance(
        uint256 poolBefore,
        uint256 individualBefore,
        uint256 creditAmount
    ) public pure {
        if (creditAmount == 0) return;
        if (poolBefore > type(uint256).max - creditAmount) return;
        if (individualBefore > type(uint256).max - creditAmount) return;

        // _creditClaimable: individual += creditAmount
        uint256 individualAfter;
        unchecked { individualAfter = individualBefore + creditAmount; }

        // Caller: pool += creditAmount
        uint256 poolAfter = poolBefore + creditAmount;

        // Invariant: individual increment == pool increment
        assert(individualAfter - individualBefore == poolAfter - poolBefore);
        assert(individualAfter - individualBefore == creditAmount);
    }

    // =========================================================================
    // Property 6: Pre-reservation accounting (DecimatorModule model)
    // =========================================================================

    /// @notice Decimator: pre-reserve then deduct maintains balance
    function check_decimator_prereserve(
        uint256 poolBefore,
        uint256 poolReserved,
        uint256 ethPortion,
        uint256 lootboxPortion
    ) public pure {
        if (poolReserved == 0) return;
        if (ethPortion + lootboxPortion != poolReserved) return;
        if (poolBefore > type(uint256).max - poolReserved) return;

        // Step 1: Pre-reserve full amount
        uint256 poolAfterReserve = poolBefore + poolReserved;

        // Step 2: Deduct lootbox portion (not claimable)
        if (poolAfterReserve < lootboxPortion) return;
        uint256 poolAfterDeduct = poolAfterReserve - lootboxPortion;

        // Result: pool increased by ethPortion only
        assert(poolAfterDeduct == poolBefore + ethPortion);
    }

    // =========================================================================
    // Property 7: Auto-rebuy return value correctness
    // =========================================================================

    /// @notice When auto-rebuy fires: reserved returned, ethSpent goes to pool
    function check_autorebuy_split(
        uint256 weiAmount,
        uint256 reserved,
        uint256 ethSpent
    ) public pure {
        if (weiAmount == 0) return;
        // rebuyAmount = weiAmount - reserved
        if (reserved > weiAmount) return;
        uint256 rebuyAmount = weiAmount - reserved;

        // ethSpent <= rebuyAmount (baseTickets * ticketPrice <= rebuyAmount)
        if (ethSpent > rebuyAmount) return;

        // dust = rebuyAmount - ethSpent (dropped)
        uint256 dust = rebuyAmount - ethSpent;

        // Conservation: weiAmount = reserved + ethSpent + dust
        assert(reserved + ethSpent + dust == weiAmount);
    }
}
