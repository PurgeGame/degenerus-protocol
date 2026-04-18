// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title EntropyLib
 * @notice Shared PRNG utilities for deterministic entropy derivation
 * @dev XOR-shift algorithm seeded from VRF for ultimate security
 */
library EntropyLib {
    /**
     * @notice XOR-shift PRNG step for deterministic entropy derivation.
     * @dev Xorshift on uint256. Seeded from VRF, so ultimately secure.
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

    /**
     * @notice Keccak mix of two uint256 inputs using EVM scratch slots.
     * @dev Equivalent to `uint256(keccak256(abi.encode(a, b)))` but ~10× cheaper
     *      because it writes directly to the scratch space (0x00-0x3F) instead
     *      of allocating a bytes-memory buffer. Use in preference to XOR-based
     *      mixing whenever low-bit diffusion of structured (high-bit) input is
     *      required.
     * @param a First input word.
     * @param b Second input word.
     * @return r Full-entropy 256-bit hash.
     */
    function hash2(uint256 a, uint256 b) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            r := keccak256(0x00, 0x40)
        }
    }
}
