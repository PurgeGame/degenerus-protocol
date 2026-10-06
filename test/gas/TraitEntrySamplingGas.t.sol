// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {PackedTicketSampleLib} from "../../contracts/libraries/PackedTicketSampleLib.sol";

contract TraitEntrySamplingHarness is DegenerusGame, BucketSeed {
    function seed(uint24 current, bool next, uint8 trait, uint256 length) external {
        level = current;
        uint24 target = current + (next ? 1 : 0);
        _seedBucketDistinct(target, trait, length, 0x10000);
    }

    function retire(uint24 target) external { _setTicketBufferLevel(target + 2); }

    /// @dev Pre-optimization sampler, kept only as a behavior and gas reference.
    function referenceSample(bool nextLevel, uint256 entropy)
        external view returns (uint8 traitSel, address[] memory entries)
    {
        uint24 targetLvl = level + (nextLevel ? 1 : 0);
        traitSel = uint8(entropy >> 24);
        if (_ticketLevelRetired(targetLvl)) return (traitSel, new address[](0));
        uint256 len = _bucketLength(targetLvl, traitSel);
        if (len == 0) return (traitSel, new address[](0));
        uint256 take = len > 4 ? 4 : len;
        entries = new address[](take);
        PackedTicketSampleLib.Cursor memory cursor;
        uint256 base = PackedTicketSampleLib.begin(cursor, len, entropy >> 40);
        cursor.word = _bucketWordAtUnchecked(targetLvl, traitSel, base);
        for (uint256 i; i < take;) {
            (uint256 index, bool redrawn) = PackedTicketSampleLib.next(cursor, len);
            uint256 word = redrawn ? _bucketWordAtUnchecked(targetLvl, traitSel, index) : cursor.word;
            entries[i] = _walletKey(_bucketIdFromWord(word, index));
            unchecked { ++i; }
        }
    }
}

contract TraitEntrySamplingGasTest is Test {
    TraitEntrySamplingHarness private h;

    function setUp() public { h = new TraitEntrySamplingHarness(); }

    function _entropy(uint256 seed, uint8 trait) private pure returns (uint256) {
        return (seed << 40) | (uint256(trait) << 24);
    }

    function testFuzz_CachedSamplerPreservesEntries(uint256 seed, uint16 length, uint8 trait, bool next) public {
        h.seed(42, next, trait, uint256(length) % 513);
        uint256 entropy = _entropy(seed, trait);
        (uint8 beforeTrait, address[] memory beforeEntries) = h.referenceSample(next, entropy);
        (uint8 afterTrait, address[] memory afterEntries) = h.sampleTraitEntries(next, entropy);
        assertEq(afterTrait, beforeTrait);
        assertEq(afterEntries, beforeEntries, "sampling order and padding redraws must stay identical");
    }

    function test_RetiredBucketRemainsHidden() public {
        h.seed(42, false, 7, 17);
        h.retire(42);
        (uint8 trait, address[] memory entries) = h.sampleTraitEntries(false, _entropy(16, 7));
        assertEq(trait, 7);
        assertEq(entries.length, 0);
    }

    function _measure(uint256 length, uint256 seed) private {
        h.seed(42, false, 7, length);
        uint256 entropy = _entropy(seed, 7);
        vm.cool(address(h));
        (, address[] memory beforeEntries) = h.referenceSample(false, entropy);
        uint256 beforeGas = vm.snapshotGasLastCall("reference-sample");
        vm.cool(address(h));
        (, address[] memory afterEntries) = h.sampleTraitEntries(false, entropy);
        uint256 afterGas = vm.snapshotGasLastCall("cached-sample");
        assertEq(afterEntries, beforeEntries);
        emit log_named_uint("reference cold sample gas", beforeGas);
        emit log_named_uint("cached cold sample gas", afterGas);
        assertLt(afterGas, beforeGas, "storage-root caching must save gas");
    }

    function test_ColdFullWordGas() public { _measure(64, 23); }
    function test_ColdSingleEntryGas() public { _measure(1, 0); }
    function test_ColdPartialTailGas() public { _measure(17, 22); }
    function test_ColdOneEntryTailGas() public { _measure(9, 14); }
    function test_ColdEmptyBucketGas() public { _measure(0, 0); }
}
