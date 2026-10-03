// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";

/// @title Differential reference model — spec-conformance of pure economic math
/// @notice Implementation-INDEPENDENT re-derivation of the *documented intended rules*, diffed
///         against the production libraries. The production code encodes these rules in compressed
///         forms (a packed nibble table for prices; packed-byte rotation + doubling loop for
///         buckets). The references below are written straight from the prose spec in the library
///         NatSpec — deliberately NOT copying the production encoding — so a shared misreading of the
///         intended rule (e.g. a wrong tier boundary) shows up as a diff instead of passing silently.
///
///         This is stronger than the existing property tests, which only check weak properties
///         (bounded / deterministic / member-of-set) and would not catch a level mapped to the
///         wrong tier.
contract ReferenceModelDiffTest is Test {
    // =====================================================================
    // Reference 1 — ticket price curve (from PriceLookupLib NatSpec)
    // =====================================================================
    // Intro (first cycle only): 0-4 -> 0.01, 5-9 -> 0.02.
    // Repeating 100-level cycle: x00 -> 0.24; x01-x29 -> 0.04; x30-x59 -> 0.08;
    //                            x60-x89 -> 0.12; x90-x99 -> 0.16.
    function _refPrice(uint24 level) internal pure returns (uint256) {
        if (level <= 4) return 0.01 ether;
        if (level <= 9) return 0.02 ether;
        uint256 off = uint256(level) % 100;
        if (off == 0) return 0.24 ether; // milestone x00
        if (off <= 29) return 0.04 ether; // x01-x29
        if (off <= 59) return 0.08 ether; // x30-x59
        if (off <= 89) return 0.12 ether; // x60-x89
        return 0.16 ether; // x90-x99
    }

    /// @notice Exhaustive: the packed-nibble price table must equal the prose spec for every
    ///         distinct behaviour (intro overrides + all 100 cycle offsets, over 21 cycles).
    function test_price_matchesSpec_exhaustive() public pure {
        for (uint24 level = 0; level <= 2100; level++) {
            assertEq(
                PriceLookupLib.priceForLevel(level),
                _refPrice(level),
                "price table diverges from documented tier spec"
            );
        }
    }

    /// @notice Fuzz across the full uint24 domain (catches any far-out-of-range divergence).
    function testFuzz_price_matchesSpec(uint24 level) public pure {
        assertEq(PriceLookupLib.priceForLevel(level), _refPrice(level));
    }

    // =====================================================================
    // Reference 2 — terminal winner counts (from JackpotBucketLib NatSpec)
    // =====================================================================
    // "[152, 104, 48, 1] rotated" — rotation offset is the bottom 2 bits of entropy, and the solo
    // lands on soloBucketIndex. The reference re-derives the rotation independently and also asserts
    // the multiset invariant (output is always a permutation of the base set).
    function _refRotate(uint16[4] memory base, uint256 entropy) internal pure returns (uint16[4] memory out) {
        uint256 offset = entropy & 3;
        for (uint256 i = 0; i < 4; i++) {
            out[i] = base[(i + offset) % 4];
        }
    }

    function testFuzz_terminalCounts_matchSpec(uint256 entropy) public pure {
        uint16[4] memory got = JackpotBucketLib.terminalWinnerCounts(entropy);
        uint16[4] memory want = _refRotate([uint16(152), 104, 48, 1], entropy);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(got[i], want[i], "terminal rotation diverges from spec");
        }
        uint256 sum;
        uint256 prod = 1;
        for (uint256 i = 0; i < 4; i++) {
            sum += got[i];
            prod *= got[i];
        }
        assertEq(sum, 305, "terminal counts must sum to the base total (permutation)");
        assertEq(prod, uint256(152) * 104 * 48 * 1, "terminal counts must be a permutation of the base set");
        assertEq(got[JackpotBucketLib.soloBucketIndex(entropy)], 1, "the solo bucket holds the single winner");
    }

    // =====================================================================
    // Reference 3 — live ETH winner targets (from JackpotBucketLib NatSpec)
    // =====================================================================
    // "Base [32, 16, 4, 1] rotated; non-solo bases scale by 1, doubled at 40 / 160 / 640 / 2,560 /
    // 10,240 ETH (at most 32); zeroes for an empty pool." Written as an explicit tier table.
    function _refMultiplier(uint256 pool) internal pure returns (uint256) {
        if (pool >= 10_240 ether) return 32;
        if (pool >= 2_560 ether) return 16;
        if (pool >= 640 ether) return 8;
        if (pool >= 160 ether) return 4;
        if (pool >= 40 ether) return 2;
        return 1;
    }

    function testFuzz_ethTargets_matchSpec(uint256 pool, uint256 entropy) public pure {
        pool = bound(pool, 0, 100_000 ether);
        uint16[4] memory got = JackpotBucketLib.ethWinnerTargets(pool, entropy);
        if (pool == 0) {
            for (uint256 i = 0; i < 4; i++) assertEq(got[i], 0, "an empty pool has no targets");
            return;
        }
        uint16[4] memory base = _refRotate([uint16(32), 16, 4, 1], entropy);
        uint256 m = _refMultiplier(pool);
        for (uint256 i = 0; i < 4; i++) {
            uint256 want = base[i] == 1 ? 1 : base[i] * m;
            assertEq(uint256(got[i]), want, "ETH target diverges from the documented tier spec");
        }
        assertEq(got[JackpotBucketLib.soloBucketIndex(entropy)], 1, "the solo target is never scaled");
    }
}
