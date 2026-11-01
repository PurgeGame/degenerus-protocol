// SPDX-License-Identifier: AGPL-3.0-only
//
// rollHeroSymbolRef.mjs — Reference implementation of `_rollHeroSymbol`
// (contracts/modules/DegenerusGameJackpotModule.sol).
// Port of the pass-1 packed
// `dailyHeroWagers[day][q]` decode + leader tracking + pass-2 keccak-derived
// `pick` cursor walk with `leaderBonus` add at `idx == leaderIdx`. Drives the
// 10K-iteration JS-replay oracle and the small-N edge-case fixtures (the
// function is `private view` so an inheritance harness cannot reach it).
//
// Algorithm:
//   - Pass-2 keccak input is `abi.encode(uint256 HERO_SYMBOL_TAG, uint256 entropy)` —
//     each value left-padded to a 32-byte word (64 bytes, as EntropyLib.hash2 hashes them).
//   - Pass-2 cursor walks flat idx ascending `0..31`; `leaderBonus` is added
//     at `idx == leaderIdx` (NOT a separate `idx == 32` bucket).
//   - Pass-1 strict-`>` first-seen tie-break: a later equal-amount slot does
//     NOT displace the leader.
//
// Cache shape:
//   - Flat `uint32[32]` indexed `(q << 3) | s`; quadrant 3 (Dice) is forced to 0, so the
//     weights match the 24 eligible slots production caches. Mirror via `Uint32Array(32)`.
//
// Entropy domain:
//   - Symbol-roll path consumes `keccak256(abi.encode(HERO_SYMBOL_TAG, randomWord))`.
//   - The hero replaces only the winning quadrant's symbol bits (`_rollBoard`); the quadrant
//     keeps its base-rolled color, so colors are orthogonal to this helper.
//
// Numeric integrity:
//   - `total` and `cumulative` are uint64 in Solidity; masked with `U64_MASK`
//     after every BigInt arithmetic op to preserve byte equivalence.
//   - Per-slot `amount` is uint32; extracted via `(packed >> (s*32)) & U32_MASK`.
//   - `leaderBonus = uint64(maxAmount) / 2` matched as `BigInt(maxAmount) >> 1n`
//     — exactly equivalent to integer-divide-by-2 for non-negative BigInts and
//     avoids any floating-point coercion.
//
// Symmetric file separation:
//   - Sister helper `ticketTraitsRef.mjs` replays the ticket trait generation
//     (`_generateTraitRun`); this file is a separate sibling for the hero-symbol roll. Do not merge.

import { AbiCoder, keccak256 } from "ethers";

const U64_MASK = (1n << 64n) - 1n;
const U32_MASK = (1n << 32n) - 1n;
const U256_MASK = (1n << 256n) - 1n;
const HERO_SYMBOL_TAG = 74n; // RngTags.JACKPOT_HERO
const abiCoder = AbiCoder.defaultAbiCoder();

/// @notice JS bit-mirror of `_rollHeroSymbol` (contracts/modules/DegenerusGameJackpotModule.sol).
///
/// Body trace vs the live contract:
///   uint32[24] memory weights        → const weights = new Uint32Array(32) (quadrant 3 stays 0)
///   uint64 total                     → let total = 0n
///   uint32 maxAmount                 → let maxAmount = 0
///   uint8 leaderIdx                  → let leaderIdx = 0
///   pass-1 nested loop (q,s) decode uint32 amounts, accumulate
///             total, track strict-> first-seen leader. Mirrored.
///   if (total == 0) return (false, 0, 0)
///   uint64 leaderBonus = uint64(maxAmount) / 2
///                                            → BigInt(maxAmount) >> 1n
///   uint64 effectiveTotal = total + leaderBonus
///   uint64 pick = uint64(uint256(EntropyLib.hash2(RngTags.JACKPOT_HERO, entropy)) % effectiveTotal)
///   pass-2 cursor walk; leaderBonus add at idx == leaderIdx;
///             return (true, idx >> 3, idx & 7) on first cumulative > pick.
///   implicit fall-through returns named-return defaults (false, 0, 0)
///             — unreachable by invariant `pick < effectiveTotal = sum(weights) + leaderBonus`
///             but mirrored here for byte equivalence.
///
/// @param day uint32 day key the wager words were read for (accepts number or BigInt); it is
///            not part of the hash — the caller supplies that day's `dailyHeroWagers` words.
/// @param entropy uint256 BigInt — the raw `randomWord` plumbed through
///                `_rollBoard`; hashed with RngTags.JACKPOT_HERO (74) it produces
///                the symbol-path entropy domain.
/// @param dailyHeroWagers BigInt[4] — the four packed uint256 slots for
///                `dailyHeroWagers[day]`, indexed by quadrant 0..3 ascending. Each
///                BigInt packs 8 × uint32 amounts at 32-bit offsets (symbol s at
///                bits `s*32 .. s*32+31`).
/// @param banQuadrant quadrant excluded from the roll (0xFF = none), as `_rollHeroSymbol`'s third argument.
/// @return { hasWinner: boolean, winQuadrant: 0..3, winSymbol: 0..7 } — when
///                hasWinner is false, winQuadrant and winSymbol are 0 to mirror
///                the Solidity named-return tuple (false, 0, 0).
export function rollHeroSymbolRef({ day, entropy, dailyHeroWagers, banQuadrant = 0xff }) {
  // `banQuadrant` mirrors production (0xFF = _NO_QUADRANT_BAN): a banned quadrant adds no
  // weight and cannot hold the leader. Quadrant 3 carries no hero wagers
  // (DEGENERETTE_HERO_COUNT = 24).
  const ban = Number(banQuadrant) & 0xff;
  const dayU32 = Number(day) >>> 0;
  const dayBn = BigInt(dayU32);
  // Mask entropy to uint256 to mirror the Solidity `uint256 entropy` parameter:
  // VRF-delivered words are uint256 by construction, but test-harness-constructed
  // BigInt values (e.g., synthetic 33-byte hex literals) can overflow. The mask
  // is a no-op for in-spec inputs and prevents ethers AbiCoder uint256 overflow
  // rejection for over-wide test inputs (mirrors the Solidity ABI-decode that
  // would reject the same call externally — internal callsites only ever pass
  // `randWord` from VRF which is uint256 by construction).
  const entropyRaw =
    typeof entropy === "bigint" ? entropy : BigInt(entropy);
  const entropyBn = entropyRaw & U256_MASK;

  // Pass 1 — decode 32 × uint32 amounts, accumulate uint64 total, track
  // strict-> first-seen leader.
  const weights = new Uint32Array(32);
  let total = 0n;
  let maxAmount = 0;
  let leaderIdx = 0;

  for (let q = 0; q < 4; ++q) {
    const packed = BigInt(dailyHeroWagers[q]);
    for (let s = 0; s < 8; ++s) {
      const idx = (q << 3) | s;
      const amount =
        q === ban || q === 3 ? 0 : Number((packed >> BigInt(s * 32)) & U32_MASK);
      weights[idx] = amount;
      total = (total + BigInt(amount)) & U64_MASK;
      if (amount > maxAmount) {
        maxAmount = amount;
        leaderIdx = idx;
      }
    }
  }

  // Early-bail — zero-wager invariant.
  if (total === 0n) {
    return { hasWinner: false, winQuadrant: 0, winSymbol: 0 };
  }

  // Pass 2 — leaderBonus, effectiveTotal, keccak-derived pick, cursor walk.
  const leaderBonus = BigInt(maxAmount) >> 1n; // uint64(maxAmount) / 2
  const effectiveTotal = (total + leaderBonus) & U64_MASK;

  // Solidity `abi.encode(uint256 HERO_SYMBOL_TAG, uint256 entropy)` packs each value into a
  // 32-byte word; ethers AbiCoder produces the identical byte layout (also relied on by the
  // mint-batch oracle).
  const encoded = abiCoder.encode(
    ["uint256", "uint256"],
    [HERO_SYMBOL_TAG, entropyBn]
  );
  const pick = BigInt(keccak256(encoded)) % effectiveTotal;

  let cumulative = 0n;
  for (let idx = 0; idx < 32; ++idx) {
    cumulative = (cumulative + BigInt(weights[idx])) & U64_MASK;
    if (idx === leaderIdx) {
      cumulative = (cumulative + leaderBonus) & U64_MASK;
    }
    if (cumulative > pick) {
      return { hasWinner: true, winQuadrant: idx >> 3, winSymbol: idx & 7 };
    }
  }

  // Unreachable by invariant `pick < effectiveTotal`; mirror the Solidity
  // named-return default for the (proven-unreachable) loop-exit path.
  return { hasWinner: false, winQuadrant: 0, winSymbol: 0 };
}

/// @notice Pack a flat 32-length uint32 array (idx layout `(q << 3) | s`) into
///         four packed BigInts mirroring the `dailyHeroWagers[day]` storage
///         layout (contracts/storage/DegenerusGameStorage.sol). Each
///         per-symbol amount is capped at `0xFFFFFFFF` (uint32 max) to mirror
///         the `betDegenerette` saturation in
///         contracts/modules/DegenerusGameDegeneretteModule.sol.
///
/// @param rawAmounts number[32] — flat amounts indexed by `(q << 3) | s`.
/// @return BigInt[4] — `out[q] = sum over s of (BigInt(amount[(q<<3)|s]) << (s*32))`.
export function packDailyHeroWagers(rawAmounts) {
  if (!rawAmounts || rawAmounts.length !== 32) {
    throw new Error(
      `packDailyHeroWagers: expected length-32 array, got length ${
        rawAmounts ? rawAmounts.length : "undefined"
      }`
    );
  }
  const out = [0n, 0n, 0n, 0n];
  for (let q = 0; q < 4; ++q) {
    let packed = 0n;
    for (let s = 0; s < 8; ++s) {
      const raw = rawAmounts[(q << 3) | s];
      const capped = BigInt(raw) & U32_MASK; // saturate at uint32 max
      packed |= capped << BigInt(s * 32);
    }
    out[q] = packed;
  }
  return out;
}

/// @notice Exposes the masks used by `rollHeroSymbolRef` for cross-validation
///         in test assertions (e.g., enforcing the uint32 amount upper bound).
export const ROLL_HERO_SYMBOL_CONSTANTS = Object.freeze({
  U64_MASK,
  U32_MASK,
  U256_MASK,
});
