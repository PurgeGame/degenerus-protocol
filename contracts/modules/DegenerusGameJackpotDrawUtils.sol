// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PackedTicketSampleLib} from "../libraries/PackedTicketSampleLib.sol";

/// @dev Shared frozen-bucket sampling for ETH, ticket and FLIP jackpot draws.
abstract contract DegenerusGameJackpotDrawUtils is DegenerusGameStorage {
    /// @dev A cursor belongs to exactly one (level, trait) bucket. It caches a packed word
    ///      for eight outputs even when other buckets' draws are interleaved. Callers gate
    ///      empty pools; no storage writer can change these buckets during a draw.
    function _drawBucketEntry(
        uint24 lvl,
        uint8 trait,
        uint256 len,
        uint256 effectiveLen,
        uint32 deity,
        uint256 randomWord,
        uint256 salt,
        uint256 pull,
        PackedTicketSampleLib.Cursor memory cursor
    ) internal view returns (uint32 winner, uint256 index) {
        if (cursor.used == 0) {
            uint256 base = PackedTicketSampleLib.begin(
                cursor, effectiveLen, EntropyLib.hash4(randomWord, trait, salt, pull)
            );
            if (base < len) cursor.word = _bucketWordAtUnchecked(lvl, trait, base);
        }
        bool redrawn;
        (index, redrawn) = PackedTicketSampleLib.next(cursor, effectiveLen);
        if (index >= len) return (deity, type(uint256).max);
        uint256 word = redrawn ? _bucketWordAtUnchecked(lvl, trait, index) : cursor.word;
        winner = _bucketIdFromWord(word, index);
    }

}
