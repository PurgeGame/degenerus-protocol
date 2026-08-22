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

/// @title IDegenerusParimutuel
/// @author Burnie Degenerus
/// @notice The game's view of the parimutuel markets: the settlement pushes it receives.
interface IDegenerusParimutuel {
    /// @notice Close the ticket-volume round that ends at this RNG request.
    /// @dev Called by GAME at the freeze, the round's definitional crossover: buys route to
    ///      the pending accumulator from that instant, so `total` is final and nothing can
    ///      move it afterwards. The market holds the prior round's total, scores
    ///      `total > prev`, records the side, and keeps `total` as the next benchmark — so
    ///      the game stores no volume history of its own.
    /// @param round The round closing at this crossover.
    /// @param total The round's manual ETH-paid ticket volume, in raw purchase units
    ///        (400 = 1 whole ticket; FLIP-paid, afking, pass, box, foil and award tickets
    ///        are not counted).
    function recordVolume(uint24 round, uint48 total) external;

    /// @notice Record the settled side of a growth round.
    /// @dev Called by GAME at the level transition that banks the successor ratchet entry —
    ///      the moment round `round`'s three terms are all final. Must run after every
    ///      ratchet write the transition performs, so a century entry reads its pushed
    ///      achieved pool rather than zero.
    /// @param round The growth round being settled.
    /// @param over True if the round resolved OVER, false for UNDER.
    function recordGrowth(uint24 round, bool over) external;
}
