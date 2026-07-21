// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title EntropyLib
 * @notice Shared PRNG utility: keccak scratch-slot hashing of one or two words
 * @dev Full-diffusion keccak256 over the EVM scratch space, suited to
 *      consumers that read low bits of a word derived from structured
 *      (high-bit) input.
 */
library EntropyLib {
    /**
     * @notice Keccak mix of two uint256 inputs using EVM scratch slots.
     * @dev Equivalent to `uint256(keccak256(abi.encode(a, b)))` but cheaper because
     *      it writes directly to the scratch space (0x00-0x3F) instead of allocating
     *      a bytes-memory buffer. Use in preference to XOR-based
     *      mixing whenever low-bit diffusion of structured (high-bit) input is
     *      required.
     * @param a First input word.
     * @param b Second input word.
     * @return r 256-bit Keccak digest of the two inputs.
     */
    function hash2(uint256 a, uint256 b) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            r := keccak256(0x00, 0x40)
        }
    }

    /**
     * @notice Keccak of a single uint256 input using the EVM scratch slot.
     * @dev Equivalent to `uint256(keccak256(abi.encode(a)))` without the
     *      bytes-memory allocation — byte-identical preimage (one raw word).
     * @param a Input word.
     * @return r 256-bit Keccak digest of the two inputs.
     */
    function hash1(uint256 a) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            r := keccak256(0x00, 0x20)
        }
    }
}
