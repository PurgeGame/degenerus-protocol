// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title FlipRoundLib
 * @notice Collapses FLIP award amounts onto whole 100-FLIP multiples.
 * @dev The 0-99 whole-FLIP remainder rounds up with probability rem/100 against a
 *      committed VRF word, so the expectation of the rounded award equals the raw
 *      award less the sub-1-FLIP dust the whole-FLIP floor already discarded.
 *
 *      Two rules keep the collapse EV-neutral, and both are properties of the
 *      caller, not of this library:
 *
 *      1. Key the entropy on immutable per-award data — a bet id, a box index, a
 *         pull index — never on a value the caller chose.
 *      2. Never round a caller-composed aggregate. Rounding a batch total lets the
 *         caller enumerate batch partitions against the already-committed word and
 *         pick the split that maximises round-ups.
 */
library FlipRoundLib {
    /// @dev The award granule: 100 FLIP, where 1 FLIP = 1 ether.
    uint256 internal constant FLIP_ROUND_UNIT = 100 ether;

    /// @dev Awards at or below this keep the whole-FLIP floor instead. A flat 100-FLIP
    ///      granule on a sub-1,000-FLIP award is a haircut of 10% or worse, and the
    ///      small-award sites bottom out near 18 FLIP at the milestone price.
    uint256 internal constant FLIP_ROUND_THRESHOLD = 1_000 ether;

    /**
     * @notice Collapse `amount` onto a whole 100-FLIP multiple, preserving expectation.
     * @dev Reduces the remainder to whole FLIP (0..99) before the roll, so a 32-bit
     *      entropy window covers the domain with ~2e-8 modulo bias — the same window
     *      width and bias as the ticket collapse. Comparing against the wei remainder
     *      instead would need ~67 bits to hold the bias down, which no seed here has
     *      spare. Sub-1-FLIP dust evaporates, exactly as the whole-FLIP floor did.
     * @param amount Raw award, wei-scaled (1 FLIP = 1 ether).
     * @param entropy Word derived from a committed VRF word and immutable award data.
     * @return The award rounded to a multiple of `FLIP_ROUND_UNIT`.
     */
    function roundFlipToHundreds(
        uint256 amount,
        uint256 entropy
    ) internal pure returns (uint256) {
        uint256 hundreds = amount / FLIP_ROUND_UNIT;
        uint256 remFlip = (amount % FLIP_ROUND_UNIT) / 1 ether; // 0..99
        if (remFlip != 0 && uint32(entropy) % 100 < remFlip) {
            unchecked {
                ++hundreds;
            }
        }
        return hundreds * FLIP_ROUND_UNIT;
    }

    /**
     * @notice Floor `amount` to a whole FLIP, discarding the wei-scale residue.
     * @dev The sub-threshold half of the award policy. Awards too small for the
     *      100-FLIP granule still land on a round FLIP figure, and the residue
     *      truncates in the protocol's favour exactly as it always has.
     * @param amount Raw award, wei-scaled (1 FLIP = 1 ether).
     * @return The award floored to a multiple of 1 FLIP.
     */
    function floorWholeFlip(uint256 amount) internal pure returns (uint256) {
        return (amount / 1 ether) * 1 ether;
    }
}
