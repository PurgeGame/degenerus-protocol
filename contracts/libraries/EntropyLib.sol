// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

/**
 * @title EntropyLib
 * @notice Shared PRNG utilities for deterministic entropy derivation
 * @dev XOR-shift algorithm seeded from VRF for ultimate security
 */
library EntropyLib {
    /**
     * @notice XOR-shift PRNG step for deterministic entropy derivation.
     * @dev Standard xorshift64 algorithm. Seeded from VRF, so ultimately secure.
     * @param state Current PRNG state.
     * @return Next PRNG state.
     */
    function entropyStep(uint256 state) internal pure returns (uint256) {
        unchecked {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
        }
        return state;
    }
}
