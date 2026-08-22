// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended, not a
 * malfunction and not a defect. Do not commit funds you are not prepared to lose
 * entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/**
 * @title EntropyLib
 * @notice Shared PRNG utility: allocation-free keccak hashing of fixed-width words
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
     * @notice Keccak mix of four ABI words without allocating an encoded bytes buffer.
     * @dev Byte-identical to `uint256(keccak256(abi.encode(a, b, c, d)))`. Four words do not
     *      fit in Solidity's 64-byte scratch region, so the preimage temporarily uses memory at
     *      the free-memory pointer without advancing it; the block makes no calls and leaves the
     *      pointer itself untouched.
     */
    function hash4(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            let p := mload(0x40)
            mstore(p, a)
            mstore(add(p, 0x20), b)
            mstore(add(p, 0x40), c)
            mstore(add(p, 0x60), d)
            r := keccak256(p, 0x80)
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
