// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title BucketSeed — test-side seeding and decoding of the packed trait buckets
/// @notice Harnesses that extend a production module mix this in to seed
///         `lvlTraitEntry[lvl][trait]` the way the drains do: register the owner in
///         `lvlEntryOwner[lvl]`, then append packed lanes naming that position.
/// @dev Test-only. No contracts/*.sol is mutated.
abstract contract BucketSeed is DegenerusGameStorage {
    /// @dev Seed a queue owner's locator and positional owed field without weakening owner identity.
    function _seedOwedAt(uint24 key, address player, uint80 packed) internal {
        uint32 pos = uint32(packed >> OWNER_IDX_SHIFT);
        if (pos != 0) entryOwnerPosition[key][player] = pos;
        else pos = entryOwnerPosition[key][player];
        require(pos != 0, "queue owner must be registered");
        _setEntryOwed(key & ~(TICKET_SLOT_BIT | TICKET_FAR_FUTURE_BIT), pos, packed);
    }

    /// @dev Registry position for `player` at `lvl`: the last position when it is already
    ///      this player, otherwise a fresh push (test-side lookup-or-push).
    function _ownerIdxFor(uint24 lvl, address player) internal returns (uint256) {
        EntryOwner[] storage owners = lvlEntryOwner[lvl];
        uint256 len = owners.length;
        if (len != 0 && owners[len - 1].owner == player) return len - 1;
        owners.push(EntryOwner(player, 0));
        return len;
    }

    /// @dev Append `n` occurrences of `player` to lvlTraitEntry[lvl][trait].
    function _seedBucket(uint24 lvl, uint8 trait, address player, uint256 n) internal {
        uint256 levelSlot;
        assembly ("memory-safe") {
            mstore(0x00, lvl)
            mstore(0x20, lvlTraitEntry.slot)
            levelSlot := keccak256(0x00, 0x40)
        }
        _bucketAppendRun(levelSlot, trait, _ownerIdxFor(lvl, player), n);
    }

    /// @dev Queue `player` on key `rk` for level `lvl` owing `packedOwedRem` (owed << 8 | rem),
    ///      registered the way every production sink registers.
    function _seedQueued(uint24 rk, uint24 lvl, address player, uint80 packedOwedRem) internal {
        // Keep position zero out of the seeded set: a zero lane index makes every word store a
        // no-op and understates gas.
        if (lvlEntryOwner[lvl].length == 0) lvlEntryOwner[lvl].push(EntryOwner(address(1), 0));
        uint80 ownerBits = _registerEntryOwner(player, lvl);
        _tqAppend(rk, uint32(ownerBits >> OWNER_IDX_SHIFT));
        _seedOwedAt(rk, player, ownerBits | packedOwedRem);
    }

    /// @dev Append `count` distinct, non-zero holders `base+1 .. base+count`, one occurrence each.
    function _seedBucketDistinct(uint24 lvl, uint8 trait, uint256 count, uint160 base) internal {
        for (uint256 i; i < count; ++i) {
            _seedBucket(lvl, trait, address(base + uint160(i + 1)), 1);
        }
    }

    /// @dev Occurrence count of the bucket.
    function _seedBucketLen(uint24 lvl, uint8 trait) internal view returns (uint256) {
        return lvlTraitEntry[lvl][trait].length;
    }

    /// @dev Reset the bucket to empty (the length word alone gates every read).
    function _seedBucketClear(uint24 lvl, uint8 trait) internal {
        uint256[] storage lanes = lvlTraitEntry[lvl][trait];
        assembly ("memory-safe") {
            sstore(lanes.slot, 0)
        }
    }
}
