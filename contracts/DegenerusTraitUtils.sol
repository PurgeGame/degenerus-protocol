// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*+==============================================================================+
  |                                                                              |
  |                      DEGENERUS TRAIT UTILS LIBRARY                           |
  |                                                                              |
  |  Pure utility library for deterministic trait generation from random seeds.  |
  |  Used by ticket and trait sampling flows to derive deterministic traits.     |
  |                                                                              |
  +==============================================================================+
  |                           TRAIT SYSTEM OVERVIEW                              |
  +==============================================================================+
  |                                                                              |
  |  TRAIT ID STRUCTURE (8 bits per trait):                                      |
  |  +------------------------------------------------------------------------+  |
  |  |  Bits 7-6: Quadrant identifier (0-3)                                   |  |
  |  |  Bits 5-3: Color tier (0-7)                                            |  |
  |  |  Bits 2-0: Symbol (0-7)                                                |  |
  |  |                                                                        |  |
  |  |  Format: [QQ][CCC][SSS] = 8 bits                                       |  |
  |  |                                                                        |  |
  |  |  - Quadrant: Which of 4 trait slots (A=0, B=1, C=2, D=3)               |  |
  |  |  - Color: Rarity tier (8 tiers, heavy-tail distribution)               |  |
  |  |  - Symbol: Variant within color (8 options, uniform distribution)      |  |
  |  +------------------------------------------------------------------------+  |
  |                                                                              |
  |  PACKED TRAITS (32 bits total):                                              |
  |  +------------------------------------------------------------------------+  |
  |  |  Bits 31-24: Trait D (quadrant 3)                                      |  |
  |  |  Bits 23-16: Trait C (quadrant 2)                                      |  |
  |  |  Bits 15-8:  Trait B (quadrant 1)                                      |  |
  |  |  Bits 7-0:   Trait A (quadrant 0)                                      |  |
  |  |                                                                        |  |
  |  |  [DDDDDDDD][CCCCCCCC][BBBBBBBB][AAAAAAAA] = 32 bits                    |  |
  |  |  Each trait byte: [QQ][CCC][SSS] (quadrant, color, symbol)             |  |
  |  +------------------------------------------------------------------------+  |
  |                                                                              |
  |  WEIGHTED DISTRIBUTION (color tier):                                         |
  |  +------------------------------------------------------------------------+  |
  |  |  Color | Range        | Width | Probability                            |  |
  |  |  ------+--------------+-------+------------                            |  |
  |  |    0   | [0, 64)      |  64   | 25.000%                                |  |
  |  |    1   | [64, 128)    |  64   | 25.000%                                |  |
  |  |    2   | [128, 192)   |  64   | 25.000%                                |  |
  |  |    3   | [192, 224)   |  32   | 12.500%                                |  |
  |  |    4   | [224, 240)   |  16   |  6.250%                                |  |
  |  |    5   | [240, 248)   |   8   |  3.125%                                |  |
  |  |    6   | [248, 254)   |   6   |  2.344%                                |  |
  |  |    7   | [254, 256)   |   2   |  0.781%   <- gold tier (1-in-128)      |  |
  |  |  ------+--------------+-------+------------                            |  |
  |  |  Total: 256 (rarity ratio 32x between color 7 and colors 0/1/2)        |  |
  |  +------------------------------------------------------------------------+  |
  |                                                                              |
  |  RANDOM SEED USAGE:                                                          |
  |  +------------------------------------------------------------------------+  |
  |  |  256-bit seed divided into 4 x 64-bit words:                           |  |
  |  |                                                                        |  |
  |  |  [bits 255-192] -> Trait D (color from low 32, symbol from high 32)    |  |
  |  |  [bits 191-128] -> Trait C (color from low 32, symbol from high 32)    |  |
  |  |  [bits 127-64]  -> Trait B (color from low 32, symbol from high 32)    |  |
  |  |  [bits 63-0]    -> Trait A (color from low 32, symbol from high 32)    |  |
  |  +------------------------------------------------------------------------+  |
  |                                                                              |
  +==============================================================================+
  |                         SECURITY CONSIDERATIONS                              |
  +==============================================================================+
  |                                                                              |
  |  1. PURE FUNCTIONS:                                                          |
  |     - No state reads/writes - purely computational                           |
  |     - No external calls - no reentrancy risk                                 |
  |     - Deterministic outputs from inputs                                      |
  |                                                                              |
  |  2. ARITHMETIC SAFETY:                                                       |
  |     - Uses unchecked blocks for gas efficiency                               |
  |     - Safety rests on documented per-function preconditions, not on the       |
  |       operations being unconditionally overflow-free (foilCuts requires        |
  |       multBps in [20000, 60000])                                              |
  |     - Scaling uses uint64 intermediate to prevent truncation                 |
  |                                                                              |
  |  3. DETERMINISM:                                                             |
  |     - Same input seed/word always yields the same traits (pure functions)    |
  |     - Critical for on-chain trait verification                               |
  |                                                                              |
  +==============================================================================+*/

/// @title DegenerusTraitUtils
/// @author Burnie Degenerus
/// @notice Pure library for deterministic trait generation from random seeds
/// @dev Used by game ticket and trait utilities for deterministic trait derivation.
///      All functions are internal pure - no state, no external calls.
/// @custom:security-contact burnie@degener.us
library DegenerusTraitUtils {
    /*+======================================================================+
      |                      COLOR TIER DISTRIBUTION                         |
      +======================================================================+
      |  Maps a 32-bit random input to a 0-7 color tier with the heavy-tail  |
      |  distribution: 25% / 25% / 25% / 12.5% / 6.25% / 3.125% / 2.344% /   |
      |  0.781%. Rarity ratio 32x between color 7 (gold) and colors 0/1/2.   |
      +======================================================================+*/

    /// @notice Maps a 32-bit random input to a color tier 0-7 with heavy-tail probability
    /// @dev Scales uint32 (0 to 2^32-1) into [0, 256) by taking the top 8 bits (rnd >> 24),
    ///      then maps to a color tier via descending-probability thresholds.
    ///
    ///      Color tier thresholds (256-resolution):
    ///      - Color 0: scaled <  64  (25.000%)
    ///      - Color 1: scaled < 128  (25.000%)
    ///      - Color 2: scaled < 192  (25.000%)
    ///      - Color 3: scaled < 224  (12.500%)
    ///      - Color 4: scaled < 240  ( 6.250%)
    ///      - Color 5: scaled < 248  ( 3.125%)
    ///      - Color 6: scaled < 254  ( 2.344%)
    ///      - Color 7: scaled >= 254 ( 0.781%, gold tier - 1-in-128)
    /// @param rnd 32-bit random input value
    /// @return Color tier 0-7 with heavy-tail distribution
    function weightedColorBucket(uint32 rnd) internal pure returns (uint8) {
        unchecked {
            uint32 scaled = rnd >> 24;
            if (scaled < 64) return 0;
            if (scaled < 128) return 1;
            if (scaled < 192) return 2;
            if (scaled < 224) return 3;
            if (scaled < 240) return 4;
            if (scaled < 248) return 5;
            if (scaled < 254) return 6;
            return 7;
        }
    }

    /*+======================================================================+
      |                      TRAIT GENERATION                                |
      +======================================================================+
      |  Derives a 6-bit trait from a 64-bit random word.                    |
      |  Combines color tier (3 bits) and symbol (3 bits).                   |
      +======================================================================+*/

    /// @notice Produces a 6-bit trait ID from a 64-bit random value
    /// @dev Color tier comes from the low 32 bits via `weightedColorBucket` (heavy-tail).
    ///      Symbol comes from the high 32 bits as a uniform 3-bit slice (& 7).
    ///      Output format: [CCC][SSS] where C = color tier (bits 5-3), S = symbol (bits 2-0).
    ///      Quadrant bits (bits 7-6) are added by the caller.
    /// @param rnd 64-bit random input value
    /// @return 6-bit trait ID (0-63, quadrant bits not included)
    function traitFromWord(uint64 rnd) internal pure returns (uint8) {
        uint8 color = weightedColorBucket(uint32(rnd));
        uint8 symbol = uint8(rnd >> 32) & 7;
        return (color << 3) | symbol;
    }

    /*+======================================================================+
      |                      TRAIT PACKING                                   |
      +======================================================================+
      |  Packs 4 traits into 32-bit value for efficient storage.             |
      +======================================================================+*/

    /// @notice Packs 4 quadrant traits derived from a 256-bit random seed into 32 bits
    /// @dev Splits 256-bit seed into 4 x 64-bit words, generates 6-bit trait from each,
    ///      adds quadrant identifier, and packs into 32-bit value.
    ///
    ///      Seed usage:
    ///      - bits [63:0]    -> Trait A (quadrant 0)
    ///      - bits [127:64]  -> Trait B (quadrant 1)
    ///      - bits [191:128] -> Trait C (quadrant 2)
    ///      - bits [255:192] -> Trait D (quadrant 3)
    ///
    ///      Output format: [traitD:8][traitC:8][traitB:8][traitA:8]
    ///      Each trait byte: [QQ][CCC][SSS] (quadrant, color, symbol)
    /// @param rand 256-bit random seed (typically from keccak256)
    /// @return 32-bit packed traits value
    function packedTraitsFromSeed(uint256 rand) internal pure returns (uint32) {
        // Extract 6-bit trait from each 64-bit word, add quadrant identifier
        uint8 traitA = traitFromWord(uint64(rand)); // Quadrant 0: bits 7-6 = 00
        uint8 traitB = traitFromWord(uint64(rand >> 64)) | 64; // Quadrant 1: bits 7-6 = 01
        uint8 traitC = traitFromWord(uint64(rand >> 128)) | 128; // Quadrant 2: bits 7-6 = 10
        uint8 traitD = traitFromWord(uint64(rand >> 192)) | 192; // Quadrant 3: bits 7-6 = 11

        // Pack into 32 bits: [D:24-31][C:16-23][B:8-15][A:0-7]
        return uint32(traitA) | (uint32(traitB) << 8) | (uint32(traitC) << 16) | (uint32(traitD) << 24);
    }

    /*+======================================================================+
      |                  DEGENERETTE TRAIT PACKING (NEAR-UNIFORM)            |
      +======================================================================+
      |  Sibling helper to packedTraitsFromSeed using a per-quadrant         |
      |  near-uniform color distribution: 7 commons at 2/15 each (13.333%),  |
      |  gold at 1/15 (6.667%). Symbol uniform 1/8 from the high 32 bits of  |
      |  each 64-bit lane. Output format mirrors packedTraitsFromSeed:       |
      |  [QQ][CCC][SSS] per byte, 4 bytes packed into uint32. This producer  |
      |  feeds the Degenerette quickPlay payout schedule (5 per-N tables);   |
      |  packedTraitsFromSeed (heavy-tail color) is the reference packer.    |
      +======================================================================+*/

    /// @notice Packs 4 quadrant traits using the Degenerette near-uniform color
    ///         distribution: 7 commons at 2/15 each (13.333%), gold at 1/15 (6.667%).
    /// @dev Per-quadrant: color via base-15 scaling (gold = scaled==14, common =
    ///      scaled >> 1), symbol uniform 1/8 from the high 32 bits of each lane.
    ///      Output format mirrors packedTraitsFromSeed: [QQ][CCC][SSS] per byte,
    ///      4 bytes packed into uint32. The library `internal pure` declaration
    ///      inlines into the consumer at compile time — no new public-ABI selector.
    /// @param rand 256-bit random seed (typically from per-spin keccak256)
    /// @return 32-bit packed traits value with near-uniform color + uniform symbol
    function packedTraitsDegenerette(uint256 rand) internal pure returns (uint32) {
        uint8 traitA = _degTrait(uint64(rand));               // Quadrant 0: bits 7-6 = 00
        uint8 traitB = _degTrait(uint64(rand >> 64))  | 64;   // Quadrant 1: bits 7-6 = 01
        uint8 traitC = _degTrait(uint64(rand >> 128)) | 128;  // Quadrant 2: bits 7-6 = 10
        uint8 traitD = _degTrait(uint64(rand >> 192)) | 192;  // Quadrant 3: bits 7-6 = 11
        return uint32(traitA)
             | (uint32(traitB) << 8)
             | (uint32(traitC) << 16)
             | (uint32(traitD) << 24);
    }

    /// @dev Per-quadrant Degenerette trait derivation. Color via base-15 scaling
    ///      with bias < 2.3e-10 per slot; symbol uniform 1/8 from high 32 bits.
    ///      Color mapping: scaled ∈ [0..14]; scaled == 14 → gold (color 7),
    ///      otherwise color = scaled >> 1 (yields 0..6, two scaled values per common).
    /// @param rnd 64-bit per-quadrant random word
    /// @return 6-bit trait ID [CCC][SSS] (quadrant bits added by caller)
    function _degTrait(uint64 rnd) private pure returns (uint8) {
        uint32 scaled = uint32((uint64(uint32(rnd)) * 15) >> 32);
        uint8 color = scaled == 14 ? 7 : uint8(scaled >> 1);
        uint8 symbol = uint8(rnd >> 32) & 7;
        return (color << 3) | symbol;
    }

    /*+======================================================================+
      |                  FOIL TRAIT GENERATION (ACTIVITY-BOOSTED)            |
      +======================================================================+
      |  Sibling producers to traitFromWord / packedTraitsFromSeed that      |
      |  lift the rare color tiers by an activity-frozen multiplier M =      |
      |  multBps / 10000 (10000 = 1x). The boost is tapered by rare-rank:    |
      |  gold takes the full M, each less-rare tier tapers toward 1x, and    |
      |  the three 25% commons (colors 0/1/2) are the sole shrink sink.      |
      |  Color cutoffs are computed in a /15360 super-ladder (15360 = 256 x  |
      |  60; x60 clears the /5 taper denominator and the 3-way common split) |
      |  so the taper resolves exactly. Symbol stays uniform 1/8 from the    |
      |  high word and the pack layout is identical to packedTraitsFromSeed. |
      +======================================================================+*/

    /// @notice Builds the /15360 tapered color-cutoff ladder for an activity
    ///         multiplier. The ladder depends ONLY on `multBps`, so a buyer/pack
    ///         (one frozen multiplier) computes it once and reuses it across every
    ///         lane and entry via `foilTrait`.
    /// @dev Per boosted tier c in {4,5,6,7} with rank weight w5 = {4:2,5:3,6:4,7:5}
    ///      (color 3 is unboosted, w5=0, held at baseline):
    ///      width15360[c] = base[c]*60 * (50000 + (multBps-10000)*w5[c]) / 50000
    ///      over baseline widths base = {0:64,1:64,2:64,3:32,4:16,5:8,6:6,7:2}
    ///      (the weightedColorBucket /256 ladder). The remainder rem = 15360 - sum of
    ///      the rare widths is split evenly across the three commons, with color 0
    ///      additionally absorbing rem mod 3 so the ladder always sums to exactly 15360.
    ///      Gold (color 7) lands on width15360[7] = 120*M. The returned `cut` holds
    ///      the seven running-sum cutoffs (cut[0] = color-0 bound .. cut[6] = color-6
    ///      bound); a draw at or above cut[6] is gold (color 7).
    /// @param multBps frozen activity multiplier in bps (10000 = 1x; range 20000..60000)
    /// @return cut Seven cumulative /15360 color cutoffs for `foilTrait`
    function foilCuts(uint16 multBps) internal pure returns (uint256[7] memory cut) {
        unchecked {
            // /15360 tapered rare widths: base[c]*60 * (50000 + boost*w5[c]) / 50000.
            uint256 boost = uint256(multBps) - 10000;
            uint256 w3 = uint256(32) * 60; // color 3 unboosted (w5=0): held at baseline 1920
            uint256 w4 = (uint256(16) * 60 * (50000 + boost * 2)) / 50000;
            uint256 w5 = (uint256(8) * 60 * (50000 + boost * 3)) / 50000;
            uint256 w6 = (uint256(6) * 60 * (50000 + boost * 4)) / 50000;
            uint256 w7 = (uint256(2) * 60 * (50000 + boost * 5)) / 50000;
            uint256 rem = 15360 - (w3 + w4 + w5 + w6 + w7);
            uint256 common = rem / 3;
            uint256 c0 = common + (rem - common * 3); // color 0 absorbs rem mod 3

            // Seven running-sum cutoffs in fixed color order (commons first), the
            // /15360 analogue of the weightedColorBucket /256 ladder.
            cut[0] = c0;
            cut[1] = c0 + common;
            cut[2] = cut[1] + common;
            cut[3] = cut[2] + w3;
            cut[4] = cut[3] + w4;
            cut[5] = cut[4] + w5;
            cut[6] = cut[5] + w6;
        }
    }

    /// @notice Produces a 6-bit boosted trait ID from a 64-bit word and a prebuilt
    ///         cutoff ladder.
    /// @dev Walks the running-sum cutoff chain in fixed color order (commons first),
    ///      identical control flow to weightedColorBucket but in /15360 resolution.
    ///      Symbol comes from the high 32 bits as a uniform 3-bit slice (& 7),
    ///      byte-identical to traitFromWord. Output format: [CCC][SSS]; quadrant bits
    ///      (7-6) are added by the caller.
    /// @param s 64-bit random input value
    /// @param cut Seven cumulative /15360 color cutoffs from `foilCuts`
    /// @return 6-bit boosted trait ID (0-63, quadrant bits not included)
    function foilTrait(uint64 s, uint256[7] memory cut) internal pure returns (uint8) {
        unchecked {
            uint256 scaled = (uint64(uint32(s)) * 15360) >> 32; // draw in [0, 15360)
            uint8 color;
            if (scaled < cut[0]) color = 0;
            else if (scaled < cut[1]) color = 1;
            else if (scaled < cut[2]) color = 2;
            else if (scaled < cut[3]) color = 3;
            else if (scaled < cut[4]) color = 4;
            else if (scaled < cut[5]) color = 5;
            else if (scaled < cut[6]) color = 6;
            else color = 7;

            uint8 symbol = uint8(s >> 32) & 7;
            return (color << 3) | symbol;
        }
    }
}
