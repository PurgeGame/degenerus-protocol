// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract HeroWagerBufferHarness is DegenerusGameStorage {
    function record(uint8 q, uint8 s, uint256 units) external {
        lootboxRngPacked = _recordHeroWager(q, s, units, lootboxRngPacked);
    }
    function seal(uint24 day) external { _sealHeroWagers(day); }
    function read(uint24 day, uint8 q) external view returns (uint256) { return _dailyHeroWagerWord(day, q); }
    function raw(uint256 key, uint8 q) external view returns (uint256) { return dailyHeroWagers[key][q]; }
    function setMetadata(uint256 word) external { lootboxRngPacked = word; }
    function metadata() external view returns (uint256) { return lootboxRngPacked; }
    function today() external view returns (uint24) { return _simulatedDayIndex(); }
}

contract HeroWagerBufferTest is Test {
    HeroWagerBufferHarness private h;
    uint256 private constant HERO_MASK = ((uint256(1) << 30) - 1) | (uint256(1) << 38);
    function setUp() public {
        h = new HeroWagerBufferHarness();
        vm.warp((uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 100) * 1 days);
    }

    function test_StallAccumulatesWithoutChangingFrozenDraw() public {
        h.record(1, 5, 100);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint24 sealedDay = h.today() - 1;
        h.seal(h.today());
        for (uint256 i; i < 5; ++i) {
            vm.warp(vm.getBlockTimestamp() + 1 days);
            h.record(1, 7, 10);
            assertEq(h.read(sealedDay, 1), uint256(100) << 160);
            assertEq(h.read(h.today(), 1), uint256((i + 1) * 10) << 224);
        }
        h.seal(h.today());
        assertEq(h.read(h.today() - 1, 1), uint256(50) << 224, "all stalled wagers enter the next draw");
        assertEq(h.read(h.today(), 1), 0, "fresh write buffer starts empty");
        assertEq(h.read(sealedDay, 1), 0, "retired pool is inaccessible");
    }

    function test_ClockAloneDoesNotRotateOrDiscardWeights() public {
        h.record(0, 0, 100);
        uint24 oldDay = h.today();
        uint256 beforeMeta = h.metadata();
        vm.warp(vm.getBlockTimestamp() + 7 days);
        assertEq(h.metadata(), beforeMeta);
        assertEq(h.read(h.today(), 0), 100);
        assertEq(h.read(oldDay, 0), 0, "views do not pretend to retain calendar history");
        h.record(0, 0, 200);
        assertEq(h.read(h.today(), 0), 300);
    }

    function test_RecyclingInvalidatesAllQuadrantsWithoutClearingWords() public {
        h.record(0, 0, 100); h.record(1, 0, 110); h.record(2, 0, 120);
        h.seal(h.today());
        h.record(1, 0, 210);
        vm.warp(vm.getBlockTimestamp() + 1 days); h.seal(h.today());
        assertEq(h.raw(0, 1), 110, "retired physical data is retained");
        assertEq(h.read(h.today(), 0), 0); assertEq(h.read(h.today(), 1), 0);
        h.record(0, 1, 9);
        assertEq(h.read(h.today(), 0), uint256(9) << 32, "first write removes every stale lane");
        assertEq(h.read(h.today(), 1), 0);
        assertEq(h.read(h.today() - 1, 1), 210, "read buffer remains independent");
        assertEq(h.read(h.today(), 3), 0); assertEq(h.read(h.today(), 255), 0);
    }

    function test_EmptyCommitmentCannotResurrectOldWeights() public {
        h.record(0, 0, 100); h.seal(h.today());
        vm.warp(vm.getBlockTimestamp() + 1 days); h.seal(h.today());
        assertEq(h.read(h.today() - 1, 0), 0);
        vm.warp(vm.getBlockTimestamp() + 1 days); h.seal(h.today());
        assertEq(h.read(h.today() - 1, 0), 0);
        assertEq(h.raw(0, 0), 100);
    }

    function test_AllEightLanesSaturateIndependently() public {
        uint256 expected;
        for (uint8 s; s < 8; ++s) {
            uint256 units = type(uint32).max - s;
            h.record(2, s, units); expected |= units << (uint256(s) * 32);
            assertEq(h.read(h.today(), 2), expected);
        }
        for (uint8 s; s < 8; ++s) {
            h.record(2, s, uint256(s) + 99);
            expected |= uint256(type(uint32).max) << (uint256(s) * 32);
            assertEq(h.read(h.today(), 2), expected);
        }
        h.record(2, 7, type(uint64).max);
        assertEq(h.read(h.today(), 2), type(uint256).max);
    }

    function testFuzz_MetadataPreservesNeighboringFields(uint256 bits) public {
        uint256 preserved = bits & ~HERO_MASK;
        h.setMetadata(preserved);
        h.record(0, 0, 10); assertEq(h.metadata() & ~HERO_MASK, preserved);
        h.seal(h.today()); assertEq(h.metadata() & ~HERO_MASK, preserved);
        h.record(2, 7, 20); assertEq(h.metadata() & ~HERO_MASK, preserved);
        h.seal(h.today() + 1); assertEq(h.metadata() & ~HERO_MASK, preserved);
    }

    function testFuzz_SequenceMatchesIndependentCohortModel(bytes32 seed) public {
        uint256[3] memory writing;
        uint256[3] memory frozen;
        uint24 stamp;
        for (uint256 step; step < 32; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step)));
            vm.warp(vm.getBlockTimestamp() + ((r >> 8) % 4) * 1 days);
            if (r & 3 == 0) {
                // A fresh request needs a later day than the preceding request.
                if (h.today() <= stamp) vm.warp(vm.getBlockTimestamp() + 1 days);
                stamp = h.today();
                for (uint256 q; q < 3; ++q) { frozen[q] = writing[q]; writing[q] = 0; }
                h.seal(stamp);
            } else {
                uint8 q = uint8((r >> 24) % 3); uint8 s = uint8((r >> 32) % 8);
                uint256 units = uint32(r >> 64); uint256 shift = uint256(s) * 32;
                uint256 total = uint32(writing[q] >> shift) + units;
                if (total > type(uint32).max) total = type(uint32).max;
                writing[q] = (writing[q] & ~(uint256(type(uint32).max) << shift)) | (total << shift);
                h.record(q, s, units);
            }
            for (uint8 q; q < 3; ++q) {
                assertEq(h.read(h.today(), q), writing[q]);
                if (stamp != 0) assertEq(h.read(stamp - 1, q), frozen[q]);
                assertEq(h.read(h.today() + 1, q), 0);
            }
        }
    }
}
