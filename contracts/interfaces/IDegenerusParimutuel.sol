// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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
