// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @dev Extends the production mint module so the live `processTicketBatch` drains into THIS
///      contract's packed buckets; adds lane-level seeders and decoders only.
contract BucketLaneHarness is DegenerusGameMintModule, BucketSeed {
    function append(uint24 lvl, uint8 trait, address player, uint256 n) external {
        _seedBucket(lvl, trait, player, n);
    }

    function ownerAt(uint24 lvl, uint8 trait, uint256 k) external view returns (address) {
        return _bucketOwnerAt(lvl, trait, k);
    }

    function bucketLen(uint24 lvl, uint8 trait) external view returns (uint256) {
        return lvlTraitEntry[lvl][trait].length;
    }

    function ownerCount(uint24 lvl) external view returns (uint256) {
        return lvlEntryOwner[lvl].length;
    }

    function laneWord(uint24 lvl, uint8 trait, uint256 w) external view returns (uint256 word) {
        uint256[] storage lanes = lvlTraitEntry[lvl][trait];
        assembly ("memory-safe") {
            mstore(0x00, lanes.slot)
            word := sload(add(keccak256(0x00, 0x20), w))
        }
    }

    /// @dev One player owing `owed` entries in the read-slot queue for `lvl`, cursor reset.
    function seedQueue(uint24 lvl, address p, uint32 owed) external {
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        lootboxRngWordByIndex[0] = uint256(keccak256("lane-packing-entropy")) | 1;
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

    /// @dev The same owner appended twice in a row reuses one registry position; a different
    ///      owner in between forces a new one.
    function test_RegistryReuse() public {
        h.append(1, 9, address(0x1), 3);
        h.append(1, 9, address(0x1), 3);
        assertEq(h.ownerCount(1), 1);
        h.append(1, 9, address(0x2), 1);
        h.append(1, 9, address(0x1), 1);
        assertEq(h.ownerCount(1), 3);
        assertEq(h.ownerAt(1, 9, 6), address(0x2));
        assertEq(h.ownerAt(1, 9, 7), address(0x1));
    }

    /// @dev A live drain split across budget chunks registers the owner once and materializes
    ///      exactly `owed` occurrences across the level's buckets.
    function test_LiveDrain_SplitResume_OneRegistryEntry() public {
        uint24 lvl = 5;
        address p = address(0xD00D);
        uint32 owed = 1200; // several WRITES_BUDGET_SAFE chunks
        h.seedQueue(lvl, p, owed);
        uint256 calls;
        bool finished;
        while (!finished) {
            (finished, ) = h.processTicketBatch(lvl + 1);
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
