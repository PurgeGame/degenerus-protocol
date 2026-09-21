// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PackedTicketSampleLib} from "../../contracts/libraries/PackedTicketSampleLib.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract WordJackpotHarness is DegenerusGameJackpotModule, BucketSeed {
    function seed(uint8 trait, uint256 len, address deity, uint256 awards) external {
        level = 41;
        dailyTicketBudgetsPacked = (awards * 4) << 144;
        _seedBucketDistinct(42, trait, len, 0x10000);
        deityBySymbol[(trait >> 6) * 8 + (trait & 7)] = deity;
    }

    function owed(address player) external view returns (uint32) {
        return uint32(_entriesOwed(_tqWriteKey(42), player) >> 8);
    }
}

contract WordScatterHarness is DegenerusGame, BucketSeed {
    function seed(uint256 len) external {
        _seedBucketDistinct(42, 7, len, 0x10000);
    }
}

contract JackpotWordSamplingTest is Test {
    bytes32 private constant WIN = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 private constant BONUS = keccak256("BONUS_TRAITS");
    WordJackpotHarness private h;
    WordScatterHarness private scatter;

    function setUp() public {
        h = new WordJackpotHarness();
        scatter = new WordScatterHarness();
    }

    /// @dev Scalar oracle: no packed storage and no production sampling helper.
    function _index(uint256 seed, uint256 len, uint256 lane) private pure returns (uint256 idx) {
        if (len <= 8) return (seed % len + lane) % len;
        uint256 selected = seed % (((len + 7) / 8) * 8);
        idx = (selected / 8) * 8 + ((selected % 8 + lane) % 8);
        if (idx >= len) idx = uint256(keccak256(abi.encode(seed, lane))) % len;
    }

    struct ExpectedDraw {
        uint256 length;
        uint256 effectiveLength;
        uint256 entriesEach;
        uint256 entropy;
        uint8 trait;
        address deity;
    }

    function _checkWin(Vm.Log memory entry, ExpectedDraw memory expected, uint256 paid)
        private pure returns (uint256 ownerIndex)
    {
        assertGt(expected.effectiveLength, 0, "empty bucket must never pay");
        uint256 seed = uint256(keccak256(abi.encode(expected.entropy, expected.trait, uint8(239), (paid / 8) * 8)));
        uint256 idx = _index(seed, expected.effectiveLength, paid % 8);
        address winner = address(uint160(uint256(entry.topics[1])));
        (uint32 entries, uint24 source, uint256 ticketIndex, bool rounded) =
            abi.decode(entry.data, (uint32, uint24, uint256, bool));
        assertEq(entries, expected.entriesEach, "every award remains a whole ticket");
        assertEq(source, 42);
        assertFalse(rounded);
        if (idx < expected.length) {
            assertEq(winner, address(uint160(0x10001 + idx)), "packed owner decoding");
            assertEq(ticketIndex, idx, "event names the actual source lane");
            return idx;
        }
        assertEq(winner, expected.deity);
        assertEq(ticketIndex, type(uint256).max, "deity sentinel");
        return expected.length;
    }

    function _checkJackpot(uint256 word, uint256 len, uint256 awards, bool withDeity) private {
        ExpectedDraw memory expected;
        expected.length = len;
        expected.trait = JackpotBucketLib.getRandomTraits(uint256(keccak256(abi.encode(word, BONUS))))[0];
        expected.deity = withDeity ? address(0xD00D) : address(0);
        expected.effectiveLength = len;
        if (withDeity) {
            uint8 color = (expected.trait >> 3) & 7;
            // Gold: one virtual entry. Colors 5/6: floor(1%), minimum 1. Colors 0..4: floor(2%), minimum 2.
            expected.effectiveLength += color == 7 ? 1 : (color >= 5 ? (len / 100 < 1 ? 1 : len / 100) : (len / 50 < 2 ? 2 : len / 50));
        }
        uint256 cap = awards < 128 ? awards : 128;
        if (cap >= 8) cap = (cap / 8) * 8;
        expected.entriesEach = cap == 0 ? 0 : (awards / cap) * 4;
        expected.entropy = uint256(keccak256(abi.encode(
            uint256(keccak256(abi.encode(word, uint24(42)))), uint8(0)
        )));
        h.seed(expected.trait, len, expected.deity, awards);
        vm.recordLogs();
        h.payEarlyBirdTickets(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256[] memory wins = new uint256[](len + 1);
        uint256 paid;
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].topics[0] != WIN) continue;
            ++wins[_checkWin(logs[j], expected, paid)];
            ++paid;
        }
        assertEq(paid, expected.effectiveLength == 0 ? 0 : cap, "padding must not drop or add funded draw slots");
        for (uint256 j; j < len; ++j) {
            assertEq(h.owed(address(uint160(0x10001 + j))), wins[j] * expected.entriesEach, "queued ownership and payout conservation");
        }
        if (withDeity) assertEq(h.owed(expected.deity), wins[len] * expected.entriesEach);
    }

    function testFuzz_RealJackpotMatchesWordOracle(uint256 word, uint16 length, uint8 count, bool deity) public {
        _checkJackpot(word, uint256(length) % 513, uint256(count), deity);
    }

    function test_EmptyBucket() public { _checkJackpot(1, 0, 128, false); }
    function test_DeityOnly() public { _checkJackpot(2, 0, 128, true); }
    function test_OneRealEntry() public { _checkJackpot(3, 1, 128, false); }
    function test_RealVirtualBoundaryInsideWord() public { _checkJackpot(4, 51, 128, true); }
    function test_FullWordsAndShortFinalGroup() public { _checkJackpot(5, 64, 25, false); }
    function test_OneEntryTail() public { _checkJackpot(6, 65, 128, false); }

    function test_AboveCapLeavesRemainderUnqueued() public { _checkJackpot(7, 65, 129, false); }
    function test_AboveCapPaysEqualWholeTickets() public { _checkJackpot(8, 65, 513, true); }

    function testFuzz_ScatterUsesSameWordRules(uint256 entropy, uint8 length) public {
        uint256 len = uint256(length) % 65;
        scatter.seed(len);
        entropy = (entropy & ~uint256(0xffffffffff)) | (uint256(7) << 24);
        (uint8 trait, address[] memory players) = scatter.sampleTraitEntriesAtLevel(42, entropy);
        assertEq(trait, 7);
        uint256 take = len < 4 ? len : 4;
        assertEq(players.length, take);
        for (uint256 i; i < take; ++i) {
            assertEq(players[i], address(uint160(0x10001 + _index(entropy >> 40, len, i))));
        }
    }

    /// @dev Every output position is exactly uniform over all word/rotation combinations.
    ///      This also proves that final groups of 1..7 do not favour low lanes.
    function test_AllPositionsUniformForFullWords() public pure {
        uint256 len = 64;
        uint256[512] memory counts;
        for (uint256 seed; seed < len; ++seed) {
            PackedTicketSampleLib.Cursor memory c;
            uint256 base = PackedTicketSampleLib.begin(c, len, seed);
            for (uint256 i; i < 8; ++i) {
                (uint256 idx, bool redrawn) = PackedTicketSampleLib.next(c, len);
                assertEq(idx / 8, base / 8, "one word supplies the full group");
                assertFalse(redrawn);
                ++counts[i * len + idx];
            }
            assertEq(c.used, 0, "next group must request new entropy");
        }
        for (uint256 i; i < counts.length; ++i) assertEq(counts[i], 1);
    }

    /// @dev Deterministic distribution test against padding bias, independently for each
    ///      output position. Lengths cover a one-entry tail and different short-tail sizes.
    function test_PartialWordDoesNotBiasTailOrFirstEntries() public pure {
        uint256[3] memory lengths = [uint256(9), 17, 51];
        for (uint256 t; t < lengths.length; ++t) {
            uint256 len = lengths[t];
            uint256[] memory counts = new uint256[](len * 8);
            for (uint256 seed; seed < 8192; ++seed) {
                PackedTicketSampleLib.Cursor memory c;
                PackedTicketSampleLib.begin(c, len, uint256(keccak256(abi.encode(seed, len))));
                for (uint256 i; i < 8; ++i) {
                    (uint256 idx,) = PackedTicketSampleLib.next(c, len);
                    assertLt(idx, len);
                    ++counts[i * len + idx];
                }
            }
            uint256 expected = 8192 / len;
            for (uint256 i; i < counts.length; ++i) {
                assertGt(counts[i], expected * 60 / 100);
                assertLt(counts[i], expected * 140 / 100);
            }
        }
    }
}
