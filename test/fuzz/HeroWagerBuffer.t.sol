// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract HeroWagerBufferHarness is DegenerusGameStorage {
    function record(uint24 day, uint8 quadrant, uint8 symbol, uint256 units) external {
        lootboxRngPacked = _recordDailyHeroWager(day, quadrant, symbol, units, lootboxRngPacked);
    }

    function setDailyIdx(uint24 day) external {
        dailyIdx = day;
    }

    function read(uint24 day, uint8 quadrant) external view returns (uint256) {
        return _dailyHeroWagerWord(day, quadrant);
    }

    function rawWord(uint24 key, uint8 quadrant) external view returns (uint256) {
        return dailyHeroWagers[key][quadrant];
    }

    function setMetadata(uint256 word) external {
        lootboxRngPacked = word;
    }

    function metadata() external view returns (uint256) {
        return lootboxRngPacked;
    }
}

/// @dev Tests the retained-day API against original day-keyed totals, including
///      stalls and catch-up. Raw-word assertions independently prove that retiring
///      a day invalidates it logically without clearing its storage words.
contract HeroWagerBufferTest is Test {
    HeroWagerBufferHarness private h;
    uint256 private constant META_MASK = (uint256(1) << 30) - 1;

    function setUp() public {
        h = new HeroWagerBufferHarness();
    }

    function test_TwoDayReusePreservesPreviousAndHidesExpired() public {
        h.setDailyIdx(9);
        h.record(10, 0, 0, 100);
        h.setDailyIdx(10);
        h.record(11, 0, 0, 200);
        assertEq(h.read(10, 0), 100);
        assertEq(h.read(11, 0), 200);
        assertEq(h.rawWord(0, 0), 100);
        assertEq(h.rawWord(1, 0), 200);

        h.setDailyIdx(11);
        h.record(12, 0, 0, 300);
        assertEq(h.read(10, 0), 0, "expired day must not alias the new day");
        assertEq(h.read(11, 0), 200, "previous day's jackpot pool survives");
        assertEq(h.read(12, 0), 300);
        assertEq(h.rawWord(0, 0), 300, "same physical word reused");
        assertEq(h.rawWord(10, 0), 0, "normal day needs no full-day slot");
        assertEq(h.rawWord(12, 0), 0, "normal day needs no full-day slot");
    }

    function test_AllEightLanesSaturateIndependently() public {
        h.setDailyIdx(20);
        uint256 expected;
        for (uint8 symbol; symbol < 8; ++symbol) {
            uint256 units = type(uint32).max - symbol;
            h.record(21, 2, symbol, units);
            expected |= units << (uint256(symbol) * 32);
            assertEq(h.read(21, 2), expected, "adding one lane preserves siblings");
        }
        for (uint8 symbol; symbol < 8; ++symbol) {
            h.record(21, 2, symbol, uint256(symbol) + 99);
            uint256 mask = uint256(type(uint32).max) << (uint256(symbol) * 32);
            expected |= mask;
            assertEq(h.read(21, 2), expected, "saturation must not carry into next lane");
        }
        assertEq(expected, type(uint256).max);
        h.record(21, 2, 7, type(uint64).max);
        assertEq(h.read(21, 2), type(uint256).max);
    }

    function test_RolloverInvalidatesQuadrantsWithoutClearingSiblingWords() public {
        h.setDailyIdx(9);
        h.record(10, 0, 0, 100);
        h.record(10, 1, 0, 110);
        h.record(10, 2, 0, 120);
        h.setDailyIdx(10);
        h.record(11, 1, 0, 210);
        h.setDailyIdx(11);
        h.record(12, 0, 0, 300);

        assertEq(h.rawWord(0, 1), 110, "old q1 word is not deleted");
        assertEq(h.rawWord(0, 2), 120, "old q2 word is not deleted");
        assertEq(h.read(12, 1), 0, "stale q1 is logically empty");
        assertEq(h.read(12, 2), 0, "stale q2 is logically empty");
        assertEq(h.read(11, 1), 210, "opposite buffer remains live");
        h.record(12, 1, 0, 9);
        assertEq(h.read(12, 1), 9, "first wager overwrites retired counts");
        assertEq(h.read(12, 0), 300, "already imported sibling is retained");
        assertEq(h.rawWord(0, 2), 120, "untouched stale sibling remains physical");
        assertEq(h.read(12, 3), 0, "fourth quadrant is ineligible");
        assertEq(h.read(12, type(uint8).max), 0, "invalid quadrant is empty");
    }

    function test_SkippedDaysInvalidateBothBuffersWithoutClearing() public {
        h.setDailyIdx(9);
        h.record(10, 1, 0, 100);
        h.setDailyIdx(10);
        h.record(11, 2, 0, 200);
        h.setDailyIdx(14);
        h.record(15, 0, 0, 300);

        assertEq(h.read(10, 1), 0);
        assertEq(h.read(11, 2), 0);
        assertEq(h.read(14, 1), 0, "no-bet day must not expose an old parity slot");
        assertEq(h.read(15, 2), 0, "skipped days invalidate both quadrant masks");
        assertEq(h.read(15, 0), 300);
        assertEq(h.rawWord(0, 1), 100, "skipped old even word is not deleted");
        assertEq(h.rawWord(1, 2), 200, "skipped old odd word is not deleted");
    }

    function test_MultiDayStallPreservesFrozenJackpotDay() public {
        h.setDailyIdx(9);
        h.record(10, 1, 0, 100);
        h.setDailyIdx(10);
        h.record(11, 1, 0, 110);
        for (uint24 day = 12; day <= 16; ++day) {
            h.record(day, 1, 0, day * 10);
            assertEq(h.read(10, 1), 100, "wall clock cannot evict frozen jackpot day");
            assertEq(h.read(11, 1), 110, "next pending day also survives");
            assertEq(h.rawWord(day, 1), day * 10, "stalled day uses spill key");
        }
        assertEq(uint24(h.metadata()), 11, "spill writes cannot advance ring metadata");
        for (uint24 day = 12; day <= 16; ++day) {
            assertEq(h.read(day, 1), day * 10);
        }
    }

    function test_CatchupImportsOneQuadrantAndRetiresSpillsWithoutDeleting() public {
        h.setDailyIdx(9);
        h.record(10, 0, 0, 100);
        h.setDailyIdx(10);
        h.record(11, 0, 0, 110);
        h.record(14, 0, 0, 140);
        h.record(14, 1, 0, 141);
        assertEq(h.rawWord(14, 0), 140);
        assertEq(h.rawWord(14, 1), 141);

        h.setDailyIdx(13);
        h.record(14, 0, 0, 7);
        assertEq(h.read(14, 0), 147, "imported quadrant combines paid spill and new wager");
        assertEq(h.read(14, 1), 141, "unimported quadrant falls back to spill");
        assertEq(h.rawWord(0, 0), 147);
        assertEq(h.rawWord(14, 0), 140, "import never deletes the spill prefix");
        assertEq(h.rawWord(14, 1), 141, "unimported spill also remains untouched");

        h.setDailyIdx(14);
        h.record(15, 2, 0, 150);
        assertEq(h.read(14, 0), 147);
        assertEq(h.read(14, 1), 141);
        h.setDailyIdx(15);
        h.record(16, 2, 0, 160);
        assertEq(h.read(14, 0), 0, "expired imported prefix cannot reappear");
        assertEq(h.read(14, 1), 0, "expired unimported prefix cannot reappear");
        assertEq(h.rawWord(14, 0), 140, "retiring a spill is logical only");
        assertEq(h.rawWord(14, 1), 141, "retiring a spill is logical only");
        assertEq(h.rawWord(0, 0), 147, "untouched expired ring word is not deleted");
        assertEq(h.read(15, 2), 150);
        assertEq(h.read(16, 2), 160);
    }

    function test_DaysZeroAndOneDoNotConfuseRingAndSpillKeys() public {
        h.record(0, 0, 0, 10);
        assertEq(h.read(0, 0), 10);
        assertEq(h.read(1, 0), 0);
        h.record(1, 0, 0, 20);
        assertEq(h.read(0, 0), 10);
        assertEq(h.read(1, 0), 20);
        h.setDailyIdx(1);
        h.record(2, 0, 0, 30);
        assertEq(h.read(0, 0), 0);
        assertEq(h.read(1, 0), 20);
        assertEq(h.read(2, 0), 30);
    }

    function testFuzz_MetadataPreservesEveryOtherBit(uint256 otherBits) public {
        uint256 preserved = otherBits & ~META_MASK;
        h.setMetadata(preserved);
        h.record(0, 0, 0, 10);
        assertEq(h.metadata() & ~META_MASK, preserved);
        h.record(1, 1, 0, 20);
        assertEq(h.metadata() & ~META_MASK, preserved);
        uint256 beforeSpill = h.metadata();
        h.record(5, 2, 0, 30);
        assertEq(h.metadata(), beforeSpill, "spill write does not touch metadata");
        h.setDailyIdx(4);
        h.record(5, 2, 0, 40);
        assertEq(h.metadata() & ~META_MASK, preserved);
        assertEq(h.read(5, 2), 70);
        h.setDailyIdx(5);
        h.record(6, 0, 0, 50);
        assertEq(h.metadata() & ~META_MASK, preserved);
    }

    function testFuzz_MonotonicSequenceMatchesDayKeyedModel(bytes32 seed) public {
        // This oracle has no parity keys, validity masks, or spill/import logic.
        // Totals are accumulated independently by their original day and symbol.
        uint256[3][128] memory expected;
        uint24 day;
        uint24 frozenDay;
        uint24 latestRetainedDay;
        for (uint256 step; step < 40; ++step) {
            uint256 choices = uint256(keccak256(abi.encode(seed, step)));
            day += uint24(choices % 4);
            if ((choices >> 8) & 3 != 0) {
                uint24 advanceBy = uint24((choices >> 16) % 8);
                frozenDay = frozenDay + advanceBy > day ? day : frozenDay + advanceBy;
            }
            h.setDailyIdx(frozenDay);
            uint8 quadrant = uint8((choices >> 24) % 3);
            uint8 symbol = uint8((choices >> 32) % 8);
            uint256 units =
                ((choices >> 200) & 7) == 0 ? uint64(choices >> 64) : uint256(uint32(choices >> 64)) % 10_000;
            uint256 shift = uint256(symbol) * 32;
            uint256 total = uint32(expected[day][quadrant] >> shift) + units;
            if (total > type(uint32).max) total = type(uint32).max;
            expected[day][quadrant] =
                (expected[day][quadrant] & ~(uint256(type(uint32).max) << shift)) | (total << shift);
            if (uint256(day) <= uint256(frozenDay) + 1) latestRetainedDay = day;
            h.record(day, quadrant, symbol, units);

            _assertDay(expected, day, latestRetainedDay);
            _assertDay(expected, day == 0 ? 0 : day - 1, latestRetainedDay);
            _assertDay(expected, frozenDay, latestRetainedDay);
            _assertDay(expected, uint24((choices >> 128) % (uint256(day) + 1)), latestRetainedDay);
            assertEq(h.read(day + 1, quadrant), 0, "future day cannot expose a live parity word");
        }
    }

    function _assertDay(uint256[3][128] memory expected, uint24 day, uint24 latest) private view {
        for (uint8 quadrant; quadrant < 3; ++quadrant) {
            uint256 retained = uint256(day) + 1 < latest ? 0 : expected[day][quadrant];
            assertEq(h.read(day, quadrant), retained, "retained pool differs from original day totals");
        }
    }
}
