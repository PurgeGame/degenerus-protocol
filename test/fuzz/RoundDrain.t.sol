// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @dev Extends the production mint module so the live `processTicketBatch` runs the seated
///      round drain in THIS contract's storage; adds queue seeders and bucket decoders only.
contract RoundDrainHarness is DegenerusGameMintModule, BucketSeed {
    function seedQueue(uint24 lvl, address[] calldata players, uint32[] calldata owed, uint8[] calldata rem, uint256 entropy)
        external
    {
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        lootboxRngWordByIndex[0] = entropy | 1;
        uint24 rk = _tqReadKey(lvl);
        for (uint256 i; i < players.length; ++i) {
            _seedQueued(rk, lvl, players[i], (uint80(owed[i]) << 8) | uint80(rem[i]));
        }
        ticketCursor = 0;
        ticketLevel = 0;
    }

    /// @dev Queue through the production purchase sink and register at buy time, then flip
    ///      the double buffer so the entries sit on the read key the drain walks.
    function seedViaPurchase(uint24 lvl, address[] calldata players, uint32[] calldata entriesScaled, uint256 entropy)
        external
    {
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        lootboxRngWordByIndex[0] = entropy | 1;
        for (uint256 i; i < players.length; ++i) {
            _queueEntriesScaled(players[i], lvl, entriesScaled[i], false);
        }
        ticketWriteSlot = !ticketWriteSlot;
        ticketCursor = 0;
        ticketLevel = 0;
    }

    function ownerIdxBitsOf(uint24 lvl, address p) external view returns (uint256) {
        return uint256(entriesOwedPacked[_tqReadKey(lvl)][p] >> OWNER_IDX_SHIFT);
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

    function owedOf(uint24 lvl, address p) external view returns (uint80) {
        return entriesOwedPacked[_tqReadKey(lvl)][p];
    }

    function roundCounter() external view returns (uint32) {
        return ticketRound;
    }

    function cursorView() external view returns (uint256) {
        return ticketCursor;
    }

    function seatsView() external view returns (uint256) {
        return ticketSeats;
    }
}

/// @title RoundDrain — the seated round drain conserves entries, keeps quadrant shape, and
///        hands the tail to the per-entry path
contract RoundDrain is Test {
    RoundDrainHarness internal h;
    uint24 internal constant LVL = 9;
    bytes32 internal constant ROUND_SIG = keccak256("RoundTraitsGenerated(uint24,uint32,uint256,uint32,uint256)");
    bytes32 internal constant ENTRY_SIG = keccak256("TraitsGenerated(address,uint256,uint32)");

    function setUp() public {
        h = new RoundDrainHarness();
        vm.etch(
            ContractAddresses.GAME_FOILPACK_MODULE,
            address(new DegenerusGameFoilPackModule()).code
        );
    }

    function _drain() internal returns (uint256 calls) {
        bool finished;
        while (!finished) {
            (finished, ) = h.processTicketBatch(LVL + 1);
            ++calls;
            assertLt(calls, 200, "drain did not finish");
        }
    }

    /// @dev Per-player, per-quadrant occurrence counts decoded from the level's buckets.
    function _counts(address[] memory players) internal view returns (uint256[4][] memory c, uint256 total) {
        c = new uint256[4][](players.length);
        for (uint256 t; t < 256; ++t) {
            uint256 len = h.bucketLen(LVL, uint8(t));
            total += len;
            for (uint256 k; k < len; ++k) {
                address o = h.ownerAt(LVL, uint8(t), k);
                bool found;
                for (uint256 p; p < players.length; ++p) {
                    if (players[p] == o) {
                        ++c[p][t >> 6];
                        found = true;
                        break;
                    }
                }
                assertTrue(found, "lane resolves to a seeded player");
            }
        }
    }

    function _players(uint256 n) internal pure returns (address[] memory ps) {
        ps = new address[](n);
        for (uint256 i; i < n; ++i) ps[i] = address(uint160(0x5EA7000 + i));
    }

    /// @dev Twelve buyers with mixed owed counts: every entry is materialized exactly once,
    ///      quadrants follow the per-entry shape (entry i lands in quadrant i mod 4), one
    ///      registry position per buyer, and both drain paths ran.
    function test_Conservation_MixedOwed() public {
        uint256 n = 12;
        address[] memory ps = _players(n);
        uint32[] memory owed = new uint32[](n);
        uint8[] memory rem = new uint8[](n);
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            owed[i] = uint32([4, 1, 9, 40, 4, 2, 7, 4, 16, 3, 4, 100][i]);
            sum += owed[i];
        }
        h.seedQueue(LVL, ps, owed, rem, uint256(keccak256("round-drain-1")));

        vm.recordLogs();
        _drain();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 rounds;
        uint256 entryEmits;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == ROUND_SIG) ++rounds;
            if (logs[i].topics[0] == ENTRY_SIG) ++entryEmits;
        }
        assertGt(rounds, 0, "rounds ran");
        assertGt(entryEmits, 0, "the tail ran on the per-entry path");
        assertEq(h.roundCounter(), rounds);

        (uint256[4][] memory c, uint256 total) = _counts(ps);
        assertEq(total, sum);
        for (uint256 p; p < n; ++p) {
            uint256 got = c[p][0] + c[p][1] + c[p][2] + c[p][3];
            assertEq(got, owed[p], "per-player entries conserved");
            // Quadrant shape: whole tickets fill all four evenly; the partial ticket fills
            // the leading quadrants.
            uint256 whole = owed[p] / 4;
            uint256 part = owed[p] % 4;
            for (uint256 q; q < 4; ++q) {
                assertEq(c[p][q], whole + (q < part ? 1 : 0), "quadrant shape");
            }
            assertEq(h.owedOf(LVL, ps[p]), 0, "owed cleared");
        }
        // One registry position per buyer on the round path; the per-entry tail may re-register
        // a survivor, never more than the seat floor allows.
        assertGe(h.ownerCount(LVL), n);
        assertLe(h.ownerCount(LVL), n + 3);
    }

    /// @dev Entries registered at purchase carry their registry position in the owed word:
    ///      the drain (rounds and the per-entry tail) pushes nothing and every lane resolves
    ///      to its buyer; fractional purchases keep the position through the remainder roll.
    function test_PurchaseRegistered_NoDrainPushes() public {
        uint24 lvl = 3; // <= level + 5 with level == 0, so the write key, not far-future
        uint256 n = 11;
        address[] memory ps = _players(n);
        uint32[] memory q = new uint32[](n);
        for (uint256 i; i < n; ++i) q[i] = uint32(100 * (1 + i % 4) + (i % 3) * 50); // 1..4 entries + 0/50/100 frac
        h.seedViaPurchase(lvl, ps, q, uint256(keccak256("round-drain-5")));
        for (uint256 i; i < n; ++i) assertEq(h.ownerIdxBitsOf(lvl, ps[i]), i + 1, "stamped at buy");
        assertEq(h.ownerCount(lvl), n);
        bool finished;
        uint256 calls;
        while (!finished) {
            (finished, ) = h.processTicketBatch(lvl + 1);
            assertLt(++calls, 200);
        }
        assertEq(h.ownerCount(lvl), n, "the drain registered nobody");
        uint256 total;
        for (uint256 t; t < 256; ++t) {
            uint256 len = h.bucketLen(lvl, uint8(t));
            total += len;
            for (uint256 k; k < len; ++k) {
                address o = h.ownerAt(lvl, uint8(t), k);
                bool found;
                for (uint256 i; i < n; ++i) if (ps[i] == o) found = true;
                assertTrue(found, "lane resolves to a buyer");
            }
        }
        uint256 minTotal;
        for (uint256 i; i < n; ++i) minTotal += q[i] / 100;
        assertGe(total, minTotal);
        assertLe(total, minTotal + n);
    }

    /// @dev A whale at the front of a long queue of single-ticket buyers: the whale stays
    ///      seated for hundreds of rounds while thousands of later entries exhaust into holes.
    ///      Every chunk must make progress (the frontier or the whale's balance moves), the
    ///      drain must finish in a bounded number of calls, and every entry is conserved.
    function test_WhaleAtFront_ThousandsBehind_NoLivelock() public {
        uint256 n = 3001;
        address[] memory ps = _players(n);
        uint32[] memory owed = new uint32[](n);
        uint8[] memory rem = new uint8[](n);
        owed[0] = 40000; // 10k tickets at index 0
        uint256 sum = 40000;
        for (uint256 i = 1; i < n; ++i) {
            owed[i] = 4;
            sum += 4;
        }
        h.seedQueue(LVL, ps, owed, rem, uint256(keccak256("round-drain-6")));

        bool finished;
        uint256 calls;
        uint256 lastCursor;
        uint256 lastWhaleOwed = 40000;
        while (!finished) {
            (finished, ) = h.processTicketBatch(LVL + 1);
            ++calls;
            uint256 cursor = h.cursorView();
            uint256 whaleOwed = uint32(h.owedOf(LVL, ps[0]) >> 8);
            assertTrue(
                finished || cursor > lastCursor || whaleOwed < lastWhaleOwed,
                "a chunk made no progress"
            );
            lastCursor = cursor;
            lastWhaleOwed = whaleOwed;
            assertLt(calls, 480, "drain did not finish in a bounded number of chunks");
        }
        // 52k entries at >= ~300 per chunk at the worst-case unit prices (the whale drains
        // ~330 occurrences per call on the per-entry price, the crowd ~700 per round chunk).
        assertLe(calls, 400, "too many chunks for 52k entries");

        uint256 total;
        uint256 whaleCount;
        for (uint256 t; t < 256; ++t) {
            uint256 len = h.bucketLen(LVL, uint8(t));
            total += len;
            for (uint256 k; k < len; ++k) {
                if (h.ownerAt(LVL, uint8(t), k) == ps[0]) ++whaleCount;
            }
        }
        assertEq(total, sum, "every entry materialized exactly once");
        assertEq(whaleCount, 40000, "the whale's entries all landed");
        assertEq(h.seatsView(), 0, "no seat left behind");
    }

    /// @dev Survivors below the seat floor with a dry queue drain by index: three whales
    ///      behind a crowd finish without any hole rescan and nothing is released early.
    function test_Survivors_DrainByIndex_AfterCrowd() public {
        uint256 n = 203;
        address[] memory ps = _players(n);
        uint32[] memory owed = new uint32[](n);
        uint8[] memory rem = new uint8[](n);
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            owed[i] = i < 3 ? 3000 : 4;
            sum += owed[i];
        }
        h.seedQueue(LVL, ps, owed, rem, uint256(keccak256("round-drain-7")));
        uint256 calls = _drain();
        assertLt(calls, 110);
        (, uint256 total) = _counts(ps);
        assertEq(total, sum);
        assertEq(h.seatsView(), 0);
        for (uint256 i; i < 3; ++i) assertEq(h.owedOf(LVL, ps[i]), 0, "whale drained");
    }

    /// @dev Fewer entries than the seat floor: no round runs, the per-entry path does it all.
    function test_BelowSeatFloor_PerEntryOnly() public {
        address[] memory ps = _players(3);
        uint32[] memory owed = new uint32[](3);
        uint8[] memory rem = new uint8[](3);
        owed[0] = 8; owed[1] = 4; owed[2] = 12;
        h.seedQueue(LVL, ps, owed, rem, uint256(keccak256("round-drain-2")));
        vm.recordLogs();
        _drain();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != ROUND_SIG, "no round below the seat floor");
        }
        (, uint256 total) = _counts(ps);
        assertEq(total, 24);
        assertEq(h.roundCounter(), 0);
    }

    /// @dev Fractional remainders on exhausted seats: the total lands at sum(owed) plus the
    ///      number of remainder wins, each win being exactly one extra entry in quadrant 0.
    function test_Remainders_AtMostOneExtraEach() public {
        uint256 n = 8;
        address[] memory ps = _players(n);
        uint32[] memory owed = new uint32[](n);
        uint8[] memory rem = new uint8[](n);
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            owed[i] = 4;
            rem[i] = 50;
            sum += 4;
        }
        h.seedQueue(LVL, ps, owed, rem, uint256(keccak256("round-drain-3")));
        _drain();
        (uint256[4][] memory c, uint256 total) = _counts(ps);
        assertGe(total, sum);
        assertLe(total, sum + n);
        for (uint256 p; p < n; ++p) {
            uint256 extra = c[p][0] + c[p][1] + c[p][2] + c[p][3] - 4;
            assertLe(extra, 1);
            assertEq(c[p][0], 1 + extra, "a remainder win is one entry in quadrant 0");
        }
    }

    /// @dev Big drain spanning many budget chunks: conservation survives every resume.
    function test_MultiChunk_Conservation() public {
        uint256 n = 40;
        address[] memory ps = _players(n);
        uint32[] memory owed = new uint32[](n);
        uint8[] memory rem = new uint8[](n);
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            owed[i] = uint32(12 * (1 + (i * 7) % 23));
            sum += owed[i];
        }
        h.seedQueue(LVL, ps, owed, rem, uint256(keccak256("round-drain-4")));
        uint256 calls = _drain();
        assertGt(calls, 2, "must span chunks");
        (uint256[4][] memory c, uint256 total) = _counts(ps);
        assertEq(total, sum);
        for (uint256 p; p < n; ++p) {
            assertEq(c[p][0] + c[p][1] + c[p][2] + c[p][3], owed[p]);
        }
    }

    /// @dev A rare-color quadrant spreads its seats over distinct symbols. Search entropies
    ///      until a round rolls color >= 6 in some quadrant, then check that quadrant's
    ///      seat traits share the color and carry pairwise-distinct symbols.
    function test_RareColorSplit_DistinctSymbols() public {
        address[] memory ps = _players(8);
        uint32[] memory owed = new uint32[](8);
        uint8[] memory rem = new uint8[](8);
        for (uint256 i; i < 8; ++i) owed[i] = 4;
        bool seen;
        for (uint256 e = 1; e < 400 && !seen; ++e) {
            uint256 snap = vm.snapshotState();
            h.seedQueue(LVL, ps, owed, rem, uint256(keccak256(abi.encode("split", e))));
            vm.recordLogs();
            _drain();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length && !seen; ++i) {
                if (logs[i].topics[0] != ROUND_SIG) continue;
                (, uint256 seatTraits, , uint256 seatOwners) =
                    abi.decode(logs[i].data, (uint32, uint256, uint32, uint256));
                uint256 seated;
                while (seated < 8 && (seatOwners >> (32 * seated)) & 0xffffffff != 0) ++seated;
                for (uint256 q; q < 4 && !seen; ++q) {
                    uint8 t0 = uint8(seatTraits >> (8 * q));
                    if (((t0 >> 3) & 7) < 6) continue;
                    seen = true;
                    uint256 symbolMask;
                    for (uint256 j; j < seated; ++j) {
                        uint8 tj = uint8(seatTraits >> (32 * j + 8 * q));
                        assertEq(tj & 0xF8, t0 & 0xF8, "same quadrant and color");
                        uint256 bit = 1 << (tj & 7);
                        assertEq(symbolMask & bit, 0, "symbols pairwise distinct");
                        symbolMask |= bit;
                    }
                }
            }
            vm.revertToState(snap);
        }
        assertTrue(seen, "no rare-color round found in 400 entropies");
    }
}
