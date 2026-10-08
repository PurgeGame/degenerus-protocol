// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {BafBoardSeed} from "./BafBoardSeed.sol";
import {IDegenerusJackpots} from "../../contracts/interfaces/IDegenerusJackpots.sol";

/// @notice Per-round reads of `DegenerusJackpots.bafPairWinners` on the current state.
library BafViews {
    /// @dev Round `r`'s best and second of `rounds` (wallet IDs): its half of the pair view. The award stage
    ///      draws both rounds of a pair at the pair's first position, so this matches the paid
    ///      winners when read on that state; a far-future pair read after ticket legs added lanes
    ///      in its band can differ.
    function round(address jackpots, uint24 lvl, uint256 word, uint256 r, uint256 rounds)
        internal
        view
        returns (uint32 best, uint32 second)
    {
        uint32[4] memory w = pair(jackpots, lvl, word, r >> 1, rounds);
        uint256 o = (r & 1) << 1;
        return (w[o], w[o + 1]);
    }
    function pair(address jackpots, uint24 lvl, uint256 word, uint256 p, uint256 rounds)
        internal view returns (uint32[4] memory winners)
    {
        uint256 board = BafBoardSeed.context(lvl, word, rounds);
        uint8[3] memory traits;
        for (uint256 i; i < 3; ++i) traits[i] = BafBoardSeed.trait(i, rounds, board);
        (winners,) = IDegenerusJackpots(jackpots).bafPairWinners(lvl, word, p, rounds, traits);
    }
}
