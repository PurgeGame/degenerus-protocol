// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusJackpots} from "../../contracts/interfaces/IDegenerusJackpots.sol";

/// @notice Per-round reads of `DegenerusJackpots.bafPairWinners` on the current state.
library BafViews {
    /// @dev Round `r`'s best and second of `rounds`: its half of the pair view. The award stage
    ///      draws both rounds of a pair at the pair's first position, so this matches the paid
    ///      winners when read on that state; a far-future pair read after ticket legs added lanes
    ///      in its band can differ.
    function round(address jackpots, uint24 lvl, uint256 word, uint256 r, uint256 rounds)
        internal
        view
        returns (address best, address second)
    {
        address[4] memory w = IDegenerusJackpots(jackpots).bafPairWinners(lvl, word, r >> 1, rounds);
        uint256 o = (r & 1) << 1;
        return (w[o], w[o + 1]);
    }
}
