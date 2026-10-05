// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";

/// @title RedemptionRollSymbolicTest -- Halmos symbolic verification of redemption roll bounds
/// @notice Proves that uint16((word >> 8) % 155 + 21) always produces [21, 175]
///         for any uint256 input word. This is an arithmetic model of sDGNRS._rollFromWord;
///         production equivalence is exercised by RedemptionForwardBatches.
/// @dev Run with: halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000
contract RedemptionRollSymbolicTest is Test {
    // =========================================================================
    // Property 1: Redemption roll bounds [21, 175]
    // =========================================================================

    /// @notice Redemption roll is always in [21, 175] for any uint256 word
    function check_redemption_roll_bounds(uint256 word) public pure {
        uint16 roll = uint16((word >> 8) % 155 + 21);
        assert(roll >= 21);
        assert(roll <= 175);
    }

    // =========================================================================
    // Property 2: Determinism
    // =========================================================================

    /// @notice Redemption roll is deterministic -- same input produces same output
    function check_redemption_roll_deterministic(uint256 word) public pure {
        uint16 roll1 = uint16((word >> 8) % 155 + 21);
        uint16 roll2 = uint16((word >> 8) % 155 + 21);
        assert(roll1 == roll2);
    }

    // =========================================================================
    // Property 3: Intermediate modulo range [0, 154]
    // =========================================================================

    /// @notice Intermediate value (word >> 8) % 155 is always in [0, 154]
    function check_redemption_roll_modulo_range(uint256 word) public pure {
        uint256 intermediate = (word >> 8) % 155;
        assert(intermediate <= 154);
        // Adding 21 gives [21, 175], which fits in uint16 (max 65535)
        assert(intermediate + 21 <= type(uint16).max);
    }

    // =========================================================================
    // Property 4: Safe uint16 cast -- no truncation
    // =========================================================================

    /// @notice uint16 cast is safe -- no information lost in downcast
    function check_redemption_roll_no_truncation(uint256 word) public pure {
        uint256 fullResult = (word >> 8) % 155 + 21;
        uint16 castResult = uint16(fullResult);
        assert(uint256(castResult) == fullResult);
    }
}
