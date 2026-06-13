// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

/// @dev Round-7 byte-identity gates.
///
///      1. PriceLookupLib.priceForLevel restructure (LIBS-01/02): the reference body
///         below is the PRE-round-7 implementation copied verbatim — the live library
///         must agree on the full uint24 domain (dense low range + cycle boundaries +
///         fuzz; both bodies depend only on `< 5` / `< 10` and `targetLevel % 100`,
///         so these cover every equivalence class).
///
///      2. EntropyLib.hash1/hash2 (LIBS-03/04): each migrated call-site shape must
///         hash the byte-identical preimage as the abi.encode/encodePacked idiom it
///         replaces — any divergence would change RNG-derived values.
contract R7LibEquivalence is Test {
    /// @dev PRE-round-7 priceForLevel body, verbatim.
    function _priceForLevelRef(uint24 targetLevel) internal pure returns (uint256) {
        if (targetLevel < 5) return 0.01 ether;
        if (targetLevel < 10) return 0.02 ether;

        if (targetLevel < 30) return 0.04 ether;
        if (targetLevel < 60) return 0.08 ether;
        if (targetLevel < 90) return 0.12 ether;
        if (targetLevel < 100) return 0.16 ether;

        uint256 cycleOffset = targetLevel % 100;

        if (cycleOffset == 0) {
            return 0.24 ether;
        } else if (cycleOffset < 30) {
            return 0.04 ether;
        } else if (cycleOffset < 60) {
            return 0.08 ether;
        } else if (cycleOffset < 90) {
            return 0.12 ether;
        } else {
            return 0.16 ether;
        }
    }

    function test_priceForLevel_denseLowRange() public pure {
        for (uint256 l; l <= 10_000; ++l) {
            assertEq(
                PriceLookupLib.priceForLevel(uint24(l)),
                _priceForLevelRef(uint24(l)),
                "price divergence in dense low range"
            );
        }
    }

    function test_priceForLevel_cycleBoundaryStrides() public pure {
        // Tier edges at 100-boundaries across magnitudes up to the uint24 ceiling.
        // (Both bodies depend only on `< 5` / `< 10` and `% 100`, so the dense range
        // plus these high-magnitude bases cover every equivalence class; the fuzz
        // test sweeps the rest of the domain.)
        uint24[9] memory offsets = [uint24(0), 1, 9, 29, 30, 59, 60, 89, 99];
        uint256[8] memory bases = [
            uint256(100),
            1_000,
            10_000,
            100_000,
            1_000_000,
            8_388_600,
            16_777_000,
            16_777_100
        ];
        for (uint256 b; b < 8; ++b) {
            for (uint256 j; j < 9; ++j) {
                uint24 l = uint24(bases[b]) + offsets[j];
                assertEq(
                    PriceLookupLib.priceForLevel(l),
                    _priceForLevelRef(l),
                    "price divergence at cycle boundary"
                );
            }
        }
        assertEq(
            PriceLookupLib.priceForLevel(type(uint24).max),
            _priceForLevelRef(type(uint24).max),
            "price divergence at uint24 max"
        );
    }

    function testFuzz_priceForLevel(uint24 l) public pure {
        assertEq(PriceLookupLib.priceForLevel(l), _priceForLevelRef(l));
    }

    // --- EntropyLib byte-identity per migrated call-site shape ---

    /// @dev Shape [1]/[3]: abi.encode(uint256, address)
    function testFuzz_hash2_wordAddress(uint256 a, address p) public pure {
        assertEq(
            EntropyLib.hash2(a, uint256(uint160(p))),
            uint256(keccak256(abi.encode(a, p)))
        );
    }

    /// @dev Shape [2]: abi.encode(uint256, uint64) — uint64 zero-extends to a full word.
    function testFuzz_hash2_wordUint64(uint256 a, uint64 b) public pure {
        assertEq(EntropyLib.hash2(a, b), uint256(keccak256(abi.encode(a, b))));
    }

    /// @dev Shapes [4]/[5]: abi.encodePacked(uint256, bytes32 tag) — two raw words.
    function testFuzz_hash2_wordTag(uint256 a, bytes32 tag) public pure {
        assertEq(
            EntropyLib.hash2(a, uint256(tag)),
            uint256(keccak256(abi.encodePacked(a, tag)))
        );
    }

    /// @dev Shape [6] and the Jackpots salt chain: abi.encodePacked(uint256, uint256).
    function testFuzz_hash2_wordWord(uint256 a, uint256 b) public pure {
        assertEq(EntropyLib.hash2(a, b), uint256(keccak256(abi.encodePacked(a, b))));
    }

    /// @dev LIBS-04 reseed shape: abi.encode of a single uint256 is one raw word.
    function testFuzz_hash1_singleWord(uint256 x) public pure {
        assertEq(EntropyLib.hash1(x), uint256(keccak256(abi.encode(x))));
    }
}
