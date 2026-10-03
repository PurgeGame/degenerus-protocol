// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {PackedTicketShuffle} from "../../contracts/libraries/PackedTicketShuffle.sol";

contract DirectShuffleHarness is DegenerusGameTicketModule, BucketSeed {
    function seed(bool tails) external {
        _setTicketBufferLevel(42);
        _registerEntryOwner(address(1), 42);
        for (uint256 i; i < 32; ++i) _registerEntryOwner(address(uint160(0x1000 + i)), 42);
        if (tails) {
            for (uint256 t; t < 256; ++t) _seedBucket(42, uint8(t), address(0xCAFE), t == 253 ? 1 : 7);
        }
    }
    function round(uint256 seed, uint256 count) external {
        uint256[4] memory lanes;
        for (uint256 i; i < count; ++i) lanes[i >> 3] |= (i + 1) << (32 * (i & 7));
        _materializeJackpotRound(42, lanes, count, seed);
    }
    function shuffleGas(uint256[4] memory words, uint256 positions, uint256 entropy)
        external view returns (uint256 used, uint256[4] memory result, uint256 order)
    {
        uint256 before = gasleft();
        order = PackedTicketShuffle.shuffle(words, positions, entropy);
        used = before - gasleft();
        result = words;
    }
    function ownerDataSlot() external pure returns (uint256 slot) {
        assembly ("memory-safe") { mstore(0, ticketOwners.slot) slot := keccak256(0, 32) }
    }
    function inventory() external view returns (uint32[32] memory traits, uint8[32] memory masks) {
        for (uint256 t; t < 256; ++t) {
            uint256 count = _bucketLength(42, t);
            for (uint256 i; i < count; ++i) {
                address owner = _bucketOwnerAtUnchecked(42, uint8(t), i);
                if (owner == address(0xCAFE)) continue;
                uint256 idx = uint160(owner) - 0x1000;
                uint8 bit = uint8(1 << (t >> 6));
                require((masks[idx] & bit) == 0, "duplicate quadrant");
                masks[idx] |= bit;
                traits[idx] |= uint32(t << (8 * (t >> 6)));
            }
        }
    }
    function goldSix() external view returns (uint256) { return _bucketLength(42, GoldSixLib.TRAIT); }
}

contract DirectJackpotShuffleTest is Test {
    DirectShuffleHarness private h;
    function setUp() public { h = new DirectShuffleHarness(); }
    function _commonDistinct(uint256 seed) private pure returns (bool) {
        for (uint256 q; q < 4; ++q) {
            uint256 seen;
            for (uint256 group; group < 4; ++group) {
                uint8 trait = DegenerusTraitUtils.traitFromWord(uint64(EntropyLib.hash2(seed, group) >> (64 * q)));
                if (trait >= 48 || (seen & (uint256(1) << trait)) != 0) return false;
                seen |= uint256(1) << trait;
            }
        }
        return true;
    }
    function test_ShufflingBreaksUpIdenticalTickets() public {
        h.seed(false);
        uint256 seed = 1;
        while (!_commonDistinct(seed)) ++seed;
        h.round(seed, 32);
        (uint32[32] memory tickets, uint8[32] memory masks) = h.inventory();
        uint256 distinct;
        for (uint256 i; i < 32; ++i) {
            assertEq(masks[i], 15, "each player gets all four quadrants");
            assertEq(uint8(tickets[i]), uint8(tickets[(i / 8) * 8]), "first quadrant copies each group");
            bool fresh = true;
            for (uint256 j; j < i; ++j) if (tickets[i] == tickets[j]) fresh = false;
            if (fresh) ++distinct;
        }
        emit log_named_uint("distinct complete tickets after quadrant shuffles", distinct);
        emit log_named_uint("distinct complete tickets with unchanged groups", 4);
        assertGt(distinct, 16, "shuffling must separate the original groups");
    }
    function testFuzz_PackedAndPartialShufflesArePermutations(uint256 seed, uint8 countSeed, bool tails) public {
        uint256 count = uint256(countSeed) % 32 + 1;
        h.seed(tails);
        vm.cool(address(h));
        uint256 before = gasleft();
        h.round(seed, count);
        uint256 used = before - gasleft();
        assertLt(used, 4_000_000, "complete 32-ticket round fits declared bound");
        (,uint8[32] memory masks) = h.inventory();
        for (uint256 i; i < 32; ++i) assertEq(masks[i], i < count ? 15 : 0, "no missing, duplicated or padded owner");
        assertLe(h.goldSix(), 1);
    }
    function test_ShuffleCostIsMemoryOnly() public {
        uint256[4] memory words;
        uint256 positions;
        for (uint256 i; i < 32; ++i) {
            words[i >> 3] |= (i + 1) << (32 * (i & 7));
            positions |= i << (8 * i);
        }
        vm.record();
        (uint256 used,uint256[4] memory result,uint256 order) = h.shuffleGas(words, positions, 0xE4B139);
        (bytes32[] memory reads,bytes32[] memory writes) = vm.accesses(address(h));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
        uint256 seen;
        for (uint256 i; i < 32; ++i) {
            uint256 pos = uint8(order >> (8 * i));
            assertEq((seen >> pos) & 1, 0);
            seen |= uint256(1) << pos;
            assertEq(uint32(result[i >> 3] >> (32 * (i & 7))), pos + 1);
        }
        assertEq(seen, type(uint32).max);
        assertLt(used, 20_000);
        emit log_named_uint("one four-word memory shuffle gas", used);
        emit log_named_uint("three shuffles per 32-ticket round gas", used * 3);
    }
    function test_RoundDoesNotReadPlayerAddresses() public {
        h.seed(false);
        uint256 ownerData = h.ownerDataSlot();
        vm.record();
        h.round(1234, 32);
        (bytes32[] memory reads,) = vm.accesses(address(h));
        for (uint256 i; i < reads.length; ++i) {
            uint256 slot = uint256(reads[i]);
            assertTrue(slot < ownerData || slot >= ownerData + 33, "no owner address resolution");
        }
    }

    function testFuzz_MemoryShuffleMatchesIndependentRotation(uint256 entropy) public {
        uint256[4] memory words;
        uint256 positions;
        for (uint256 i; i < 32; ++i) {
            words[i >> 3] |= (i + 1) << (32 * (i & 7));
            positions |= i << (8 * i);
        }
        (,uint256[4] memory result,uint256 order) = h.shuffleGas(words, positions, entropy);
        for (uint256 g; g < 4; ++g) for (uint256 lane; lane < 8; ++lane) {
            uint256 source = ((g + ((entropy >> (lane * 2)) & 3)) % 4) * 8 + lane;
            assertEq(uint32(result[g] >> (32 * lane)), source + 1);
            assertEq(uint8(order >> (8 * (g * 8 + lane))), source);
        }
    }

}
