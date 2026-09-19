// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {EntropyLib} from "./EntropyLib.sol";

/// @dev Samples a uniformly chosen packed word with a random lane rotation, eight draws at a time.
///      Each output has the same marginal weight as a uniform entry draw. Real entries and
///      virtual deity entries share one logical range; only real entries require storage.
library PackedTicketSampleLib {
    struct Cursor {
        uint256 used;
        uint256 start;
        uint256 word;
        uint256 entropy;
    }

    /// @dev Caller supplies nonzero length and fresh domain-separated entropy every eight draws.
    ///      Choosing one position in the padded range chooses both word and lane rotation
    ///      uniformly, including when the caller consumes fewer than eight outputs.
    function begin(Cursor memory c, uint256 length, uint256 entropy) internal pure returns (uint256 base) {
        c.entropy = entropy;
        c.start = entropy % (length <= 8 ? length : (length + 7) & ~uint256(7));
        base = c.start & ~uint256(7);
    }

    /// @dev Padding is redrawn across the ENTIRE valid range, not wrapped onto its first
    ///      entries. For padded length P and real+virtual length N, each output selects
    ///      every valid entry with probability 1/P + (P-N)/(P*N) = 1/N.
    ///      A pool fitting in one word instead rotates directly through its valid entries.
    /// @return index Logical real/virtual entry index.
    /// @return redrawn True when the caller must resolve a new source word for a padding draw.
    function next(Cursor memory c, uint256 length) internal pure returns (uint256 index, bool redrawn) {
        uint256 used = c.used;
        c.used = (used + 1) & 7;
        if (length <= 8) return ((c.start + used) % length, false);
        index = (c.start & ~uint256(7)) | ((c.start + used) & 7);
        if (index >= length) {
            index = EntropyLib.hash2(c.entropy, used) % length;
            redrawn = true;
        }
    }
}
