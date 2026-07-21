// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";

/// @title Differential reference model — spec-conformance of pure economic math
/// @notice Implementation-INDEPENDENT re-derivation of the *documented intended rules*, diffed
///         against the production libraries. The production code encodes these rules in compressed
///         forms (a packed nibble table for prices; index-rotation + piecewise-linear scaling for
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
    // Reference 2 — trait bucket base counts (from JackpotBucketLib NatSpec)
    // =====================================================================
    // "Base counts [25, 15, 8, 1] are rotated by entropy for fairness" — rotation offset is the
    // bottom 2 bits of entropy. The reference re-derives the rotation independently and also asserts
    // the multiset invariant (output is always a permutation of the base set).
    function _refTraitCounts(uint256 entropy) internal pure returns (uint16[4] memory out) {
        uint16[4] memory base = [uint16(25), 15, 8, 1];
        uint256 offset = entropy & 3;
        for (uint256 i = 0; i < 4; i++) {
            out[i] = base[(i + offset) % 4];
        }
    }

    function testFuzz_traitCounts_matchSpec(uint256 entropy) public pure {
        uint16[4] memory got = JackpotBucketLib.traitBucketCounts(entropy);
        uint16[4] memory want = _refTraitCounts(entropy);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(got[i], want[i], "trait bucket rotation diverges from spec");
        }
        // Independent multiset invariant: the result is always a permutation of {25,15,8,1}.
        uint256 sum;
        uint256 prod = 1;
        for (uint256 i = 0; i < 4; i++) {
            sum += got[i];
            prod *= got[i];
        }
        assertEq(sum, 25 + 15 + 8 + 1, "trait counts must sum to the base total (permutation)");
        assertEq(prod, uint256(25) * 15 * 8 * 1, "trait counts must be a permutation of the base set");
    }

    // =====================================================================
    // Reference 3 — pool-size scale multiplier (from JackpotBucketLib NatSpec)
    // =====================================================================
    // "1x under 10 ETH, linearly to 2x by 50 ETH, linearly to maxScaleBps by 200 ETH, then capped."
    function _refScaleBps(uint256 ethPool, uint32 maxScaleBps) internal pure returns (uint256) {
        uint256 MIN = 10 ether;
        uint256 FIRST = 50 ether;
        uint256 SECOND = 200 ether;
        uint256 BASE = 10_000;
        uint256 TWO = 20_000;
        if (ethPool < MIN) return BASE;
        if (ethPool < FIRST) return BASE + ((ethPool - MIN) * (TWO - BASE)) / (FIRST - MIN);
        if (ethPool < SECOND) return TWO + ((ethPool - FIRST) * (uint256(maxScaleBps) - TWO)) / (SECOND - FIRST);
        return maxScaleBps;
    }

    /// @notice Drives the production scaler so the observed large-bucket count isolates the
    ///         piecewise-linear scale multiplier. Compares against the reference scale applied
    ///         to the largest base bucket (25).
    function testFuzz_scale_matchesSpec(uint256 ethPool, uint32 maxScaleBps) public pure {
        ethPool = bound(ethPool, 0, 10_000 ether);
        maxScaleBps = uint32(bound(maxScaleBps, 20_000, 40_000)); // >= 2x per the spec's monotonic curve

        uint16[4] memory base = [uint16(25), 15, 8, 1];
        uint16[4] memory got =
            JackpotBucketLib.scaleTraitBucketCounts(base, ethPool, maxScaleBps);

        uint256 scaleBps = _refScaleBps(ethPool, maxScaleBps);
        // Largest bucket (25) — spec: scaled = base * scaleBps / 10_000, floored at base.
        uint256 wantLarge = (uint256(25) * scaleBps) / 10_000;
        if (wantLarge < 25) wantLarge = 25;
        assertEq(uint256(got[0]), wantLarge, "bucket scaling diverges from documented piecewise-linear spec");

        // Solo bucket (base 1) is never scaled.
        assertEq(uint256(got[3]), 1, "solo bucket must stay 1 (unscaled) per spec");
    }
}
