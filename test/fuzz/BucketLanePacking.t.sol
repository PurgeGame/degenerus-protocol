// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Extends the production ticket module so the live `runTicketWork` drains into THIS
///      contract's packed buckets; adds lane-level seeders and decoders only.
contract BucketLaneHarness is DegenerusGameTicketModule {
    /// @dev The ticket module answers the liveness tail through the Game's view; this harness is
    ///      not deployed at the Game's address, so it evaluates the tail in place.
    function _pastDeadlineTriggered(uint24 today, uint24 idx)
        internal
        view
        override
        returns (bool)
    {
        return DegenerusGameStorage._pastDeadlineTriggered(today, idx);
    }

    /// @dev Seed a queue owner's locator and positional owed field without weakening owner identity.
    function _seedOwedAt(uint24 key, address player, uint80 packed) internal {
        uint32 pos = uint32(packed >> OWNER_IDX_SHIFT);
        if (pos != 0) ticketOwnerId[player] = pos;
        else pos = ticketOwnerId[player];
        require(pos != 0, "queue owner must be registered");
        _setEntryOwed(key, pos, packed);
    }

    /// @dev Registry position for `player` at `lvl`: the last position when it is already
    ///      this player, otherwise a fresh push (test-side lookup-or-push).
    function _ownerIdxFor(uint24 lvl, address player) internal returns(uint256) {
        return uint256(_registerEntryOwner(player,lvl)>>OWNER_IDX_SHIFT)-1;
    }

    /// @dev Append `n` occurrences of `player` to lvlTraitEntry[lvl][trait].
    function _seedBucket(uint24 lvl, uint8 trait, address player, uint256 n) internal {
        _setTicketBufferLevel(lvl);
        _bucketAppendRun(_traitBufferBase(lvl), trait, _ownerIdxFor(lvl, player), n, lvl);
    }

    /// @dev Queue `player` on key `rk` for level `lvl` owing `packedOwedRem` (owed << 8 | rem),
    ///      registered the way every production sink registers.
    function _seedQueued(uint24 rk, uint24 lvl, address player, uint80 packedOwedRem) internal {
        // Keep position zero out of the seeded set: a zero lane index makes every word store a
        // no-op and understates gas.
        if (ticketOwners.length == 0) _registerEntryOwner(address(1), lvl);
        uint80 ownerBits = _registerEntryOwner(player, lvl);
        _tqAppend(rk, uint32(ownerBits >> OWNER_IDX_SHIFT));
        _seedOwedAt(rk, player, ownerBits | packedOwedRem);
    }

    function append(uint24 lvl, uint8 trait, address player, uint256 n) external {
        _seedBucket(lvl, trait, player, n);
    }

    function ownerAt(uint24 lvl, uint8 trait, uint256 k) external view returns (address) {
        return _bucketOwnerAtUnchecked(lvl, trait, k);
    }

    function bucketLen(uint24 lvl, uint8 trait) external view returns (uint256) {
        return _bucketLength(lvl, trait);
    }

    function ownerCount(uint24 lvl) external view returns (uint256) {
        return ticketOwners.length;
    }

    function laneWord(uint24 lvl, uint8 trait, uint256 w) external view returns (uint256 word) {
        return _bucketWordAtUnchecked(lvl, trait, w * 8);
    }

    /// @dev One player owing `owed` entries in the read-slot queue for `lvl`, cursor reset.
    function seedQueue(uint24 lvl, address p, uint32 owed) external {
        // The live mint window ends at game level + 1. Put this queue at its
        // edge so runTicketWork(lvl + 1, ...) exercises the real sweep.
        level = lvl - 1;
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(0) + 1) & 1) << 12);
        rngWordCurrent = uint256(keccak256("lane-packing-entropy")) | 1; _setRngSessionPublished(true); _setRngComplete(false);
        uint24 rk = _tqReadKey(lvl);
        _seedQueued(rk, lvl, p, uint80(owed) << 8);
        ticketCursor = 0;
        ticketLevel = 0;
    }
}

/// @title BucketLanePacking — the packed trait buckets decode to the addresses that were appended
contract BucketLanePacking is Test {
    BucketLaneHarness internal h;

    function setUp() public {
        h = new BucketLaneHarness();
        vm.etch(
            ContractAddresses.GAME_FOILPACK_MODULE,
            address(new DegenerusGameFoilPackModule()).code
        );
    }

    /// @dev Appends across word boundaries in every alignment decode back in order.
    function test_RoundTrip_WordBoundaries() public {
        uint24 lvl = 7;
        uint8 trait = 200;
        uint256[5] memory runs = [uint256(7), 1, 9, 17, 8];
        address[] memory model = new address[](42);
        uint256 pos;
        for (uint256 r; r < runs.length; ++r) {
            address p = address(uint160(0xBEEF00 + r));
            h.append(lvl, trait, p, runs[r]);
            for (uint256 i; i < runs[r]; ++i) model[pos++] = p;
        }
        assertEq(pos, 42);
        assertEq(h.bucketLen(lvl, trait), 42);
        assertEq(h.ownerCount(lvl), 5);
        for (uint256 k; k < 42; ++k) {
            assertEq(h.ownerAt(lvl, trait, k), model[k]);
        }
        // Lanes past the length are zero (the final word is only partially written).
        assertEq(h.laneWord(lvl, trait, 5) >> 64, 0);
    }

    /// @dev Fuzz: any sequence of (player, run) appends decodes to the in-memory model, the
    ///      length is the occurrence count, and every in-length lane names a registered,
    ///      nonzero owner.
    function testFuzz_RoundTrip(uint8[16] calldata runsRaw, uint8[16] calldata who) public {
        uint24 lvl = 3;
        uint8 trait = 65;
        address[] memory model = new address[](16 * 32);
        uint256 pos;
        for (uint256 r; r < 16; ++r) {
            uint256 n = uint256(runsRaw[r]) % 33;
            if (n == 0) continue;
            address p = address(uint160(0xA11CE00 + (uint256(who[r]) % 5)));
            h.append(lvl, trait, p, n);
            for (uint256 i; i < n; ++i) model[pos++] = p;
        }
        assertEq(h.bucketLen(lvl, trait), pos);
        uint256 owners = h.ownerCount(lvl);
        for (uint256 k; k < pos; ++k) {
            address got = h.ownerAt(lvl, trait, k);
            assertEq(got, model[k]);
            assertTrue(got != address(0));
            uint256 lane = (h.laneWord(lvl, trait, k >> 3) >> (32 * (k & 7))) & 0xffffffff;
            assertLt(lane, owners);
        }
    }

    /// @dev A wallet retains its global registry position even with another owner in between.
    function test_RegistryReuse() public {
        h.append(1, 9, address(0x1), 3);
        h.append(1, 9, address(0x1), 3);
        assertEq(h.ownerCount(1), 1);
        h.append(1, 9, address(0x2), 1);
        h.append(1, 9, address(0x1), 1);
        assertEq(h.ownerCount(1), 2);
        assertEq(h.ownerAt(1, 9, 6), address(0x2));
        assertEq(h.ownerAt(1, 9, 7), address(0x1));
    }

    /// @dev A live drain split across budget chunks registers the owner once and materializes
    ///      exactly `owed` occurrences across the level's buckets.
    function test_LiveDrain_SplitResume_OneRegistryEntry() public {
        uint24 lvl = 5;
        address p = address(0xD00D);
        uint32 owed = 1200; // enough work for several physically gas-limited calls
        h.seedQueue(lvl, p, owed);
        uint256 calls;
        bool finished;
        while (!finished) {
            finished = h.runTicketWork{gas: 2_000_000}(lvl + 1, 2_000_000).done;
            ++calls;
            assertLt(calls, 64, "drain did not finish");
        }
        assertGt(calls, 1, "the drain must span more than one chunk to test the resume");
        // the seeder's position-zero sentinel plus the drained player
        assertEq(h.ownerCount(lvl), 2);
        assertEq(h.ownerAt(lvl, 0, 0) == p || h.bucketLen(lvl, 0) == 0, true);
        uint256 total;
        for (uint256 t; t < 256; ++t) {
            uint256 len = h.bucketLen(lvl, uint8(t));
            for (uint256 k; k < len; ++k) {
                assertEq(h.ownerAt(lvl, uint8(t), k), p);
            }
            total += len;
        }
        assertEq(total, owed);
    }
}
