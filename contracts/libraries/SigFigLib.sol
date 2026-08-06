// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title SigFigLib
 * @notice Collapses an award onto its leading three significant figures.
 * @dev The DGNRS counterpart to `FlipRoundLib`'s 100-FLIP granule. A fixed granule does
 *      not work for DGNRS: the box legs price against a live pool balance, so the award
 *      spans orders of magnitude across a game and any constant step is either the whole
 *      prize at the small end or invisible at the large end. Three significant figures is
 *      scale-free — it reads as a round number at every magnitude and never costs a full
 *      1% of the award: the discarded tail is under one unit in the third figure, so the
 *      relative cost is under 1/mantissa, i.e. worst case 1/100 and best case 1/999.
 *
 *      The collapse is a pure floor, so it truncates toward the protocol and needs no
 *      entropy. That also keeps it off the RNG-window ledger entirely.
 */
library SigFigLib {
    /**
     * @notice Floor `amount` to its leading three significant figures.
     * @dev Amounts under 1,000 already carry three or fewer figures and pass through
     *      untouched, so zero maps to zero. The loop runs once per decimal digit past the
     *      third — about 16-22 iterations at the 1e18-scaled magnitudes these awards
     *      reach, and bounded at 74 by uint256 itself.
     * @param amount Raw award, wei-scaled.
     * @return The award with every digit past the third zeroed.
     */
    function floorToThreeSigFigs(uint256 amount) internal pure returns (uint256) {
        uint256 scale = 1;
        uint256 mantissa = amount;
        while (mantissa >= 1000) {
            mantissa /= 10;
            scale *= 10;
        }
        return mantissa * scale;
    }
}
