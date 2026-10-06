// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {WalletSeed} from "./WalletSeed.sol";

/// @title BucketSeed — test-side seeding and decoding of the packed trait buckets
/// @notice Harnesses that extend a production module mix this in to seed
///         `lvlTraitEntry[lvl][trait]` the way the drains do: register the owner in
///         the wallet table, then append packed lanes naming its wallet ID.
/// @dev Test-only. No contracts/*.sol is mutated.
abstract contract BucketSeed is WalletSeed {
    /// @dev Seed a queue owner's locator and positional owed field without weakening owner identity.
    function _seedOwedAt(uint24 key, address player, uint80 packed) internal {
        uint32 id = _walletIdOf(player);
        require(id != 0 && (uint32(packed >> OWNER_IDX_SHIFT) == 0 || uint32(packed >> OWNER_IDX_SHIFT) == id), "owner ID mismatch");
        _setEntryOwed(key, id, packed);
    }

    /// @dev Register `player` (idempotent; admission bypassed) and return its wallet ID, the
    ///      value a bucket lane holds.
    function _ownerIdxFor(uint24, address player) internal returns (uint256) {
        return _seedWallet(player);
    }

    /// @dev Append `n` occurrences of `player` to lvlTraitEntry[lvl][trait].
    function _seedBucket(uint24 lvl, uint8 trait, address player, uint256 n) internal {
        _setTicketBufferLevel(lvl);
        _bucketAppendRun(_traitBufferBase(lvl), trait, _ownerIdxFor(lvl, player), n, lvl);
    }

    /// @dev Queue `player` on key `rk` for level `lvl` owing `packedOwedRem` (owed << 8 | rem),
    ///      registered the way every production sink registers.
    function _seedQueued(uint24 rk, uint24 lvl, address player, uint80 packedOwedRem) internal {
        uint32 id = uint32(_ownerIdxFor(lvl, player));
        _tqAppend(rk, id);
        _seedOwedAt(rk, player, (uint80(id) << OWNER_IDX_SHIFT) | packedOwedRem);
    }

    /// @dev Append `count` distinct, non-zero holders `base+1 .. base+count`, one occurrence each.
    function _seedBucketDistinct(uint24 lvl, uint8 trait, uint256 count, uint160 base) internal {
        for (uint256 i; i < count; ++i) {
            _seedBucket(lvl, trait, address(base + uint160(i + 1)), 1);
        }
    }

    /// @dev Occurrence count of the bucket.
    function _seedBucketLen(uint24 lvl, uint8 trait) internal view returns (uint256) {
        return _bucketLength(lvl, trait);
    }

    /// @dev Reset the bucket to empty (the length word alone gates every read).
    function _seedBucketClear(uint24 lvl, uint8 trait) internal {
        uint256 lanesSlot = _traitBufferBase(lvl) + trait;
        assembly ("memory-safe") {
            sstore(lanesSlot, 0)
        }
    }
}
