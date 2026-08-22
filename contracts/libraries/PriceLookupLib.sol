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

/// @title PriceLookupLib
/// @notice Shared price tier calculations for level-based pricing
/// @dev Implements an intro tier followed by a 100-level cycle used across game modules
library PriceLookupLib {
    /// @notice Get price for a specific level
    /// @dev Price tiers follow a 100-level cycle with discounted intro prices:
    ///      Cycle (repeating every 100 levels):
    ///      - Levels x00 (100, 200, etc.): 0.24 ETH (milestone)
    ///      - Levels x01-x29: 0.04 ETH
    ///      - Levels x30-x59: 0.08 ETH
    ///      - Levels x60-x89: 0.12 ETH
    ///      - Levels x90-x99: 0.16 ETH
    ///      First cycle overrides (levels 0-9 use intro pricing):
    ///      - Levels 0-4: 0.01 ETH (instead of 0.04 ETH)
    ///      - Levels 5-9: 0.02 ETH (instead of 0.04 ETH)
    /// @param targetLevel Level to query price for
    /// @return Price in wei
    function priceForLevel(uint24 targetLevel) internal pure returns (uint256) {
        // Intro tiers (levels 0-9)
        if (targetLevel < 5) return 0.01 ether;
        if (targetLevel < 10) return 0.02 ether;

        // Levels 10-99 share the repeating-cycle tiers: their cycleOffset equals
        // the level itself and is never 0 in that range, so one chain serves all
        // levels >= 10.
        uint256 cycleOffset = targetLevel % 100;

        if (cycleOffset == 0) {
            return 0.24 ether; // Milestone levels: 100, 200, 300...
        }
        // Non-milestone cycle prices are 0.04 ether multiples keyed by decade
        // (the tier table above): offsets 1-29 -> 1x, 30-59 -> 2x, 60-89 -> 3x,
        // 90-99 -> 4x. Nibble table indexed by cycleOffset / 10; max product
        // 0.04 ether * 15 cannot overflow.
        unchecked {
            return 0.04 ether * ((0x4333222111 >> ((cycleOffset / 10) * 4)) & 0xF);
        }
    }
}
