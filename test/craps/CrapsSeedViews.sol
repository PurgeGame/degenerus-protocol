// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {LootboxCraps} from "../../contracts/LootboxCraps.sol";

/// @dev Test-only seed derivation. Production derives the same seed inline in the engine and the
///      hottest-shooter payout; the suite recomputes it here to replay a table's dice.
abstract contract CrapsSeedViews is LootboxCraps {
    /// @notice The seed for the table at `index`.
    /// @dev Takes nothing but the index on purpose: the shooter belongs to the table, not to a
    ///      player. Reverts until the word lands.
    function _seedFor(uint48 index) internal view returns (bytes32) {
        uint256 word = _wordAt(index);
        if (word == 0) revert RngNotReady();
        return _crapsSeed(word, index);
    }

    /// @dev The seed derivation alone, for a caller that already fetched the word.
    function _crapsSeed(uint256 word, uint48 index) internal pure returns (bytes32) {
        return bytes32(_hash3(uint256(_CRAPS_SEED_DOMAIN), word, index));
    }
}
