// SPDX-License-Identifier: AGPL-3.0-only
//
// rollHeroSymbolRef.mjs — Reference implementation of `_rollHeroSymbol`
// (contracts/modules/DegenerusGameJackpotModule.sol L1639-L1700) at the v42.0
// HRROLL audit-subject commit `a0218952`. Verbatim port of the pass-1 packed
// `dailyHeroWagers[day][q]` decode + leader tracking + pass-2 keccak-derived
// `pick` cursor walk with `leaderBonus` add at `idx == leaderIdx`. Drives the
// 10K-iteration TST-HRROLL-01 + TST-HRROLL-02 JS-replay oracle and the
// small-N TST-HRROLL-04 + TST-HRROLL-05 edge-case fixtures per the Phase 293
// D-293-INVOKE-01 default disposition (ALGORITHM_VERIFIED via JS-replay; the
// function is `private view` so an inheritance harness cannot reach it).
//
// Algorithm lock (D-42N-DETERMINISM-01, locked at Phase 292):
//   - Pass-2 keccak input is `abi.encode(uint256 entropy, uint32 day)` —
//     each value left-padded to a 32-byte word (uint256 + uint32 → 64 bytes).
//   - Pass-2 cursor walks flat idx ascending `0..31`; `leaderBonus` is added
//     at `idx == leaderIdx` (NOT a separate `idx == 32` bucket).
//   - Pass-1 strict-`>` first-seen tie-break: a later equal-amount slot does
//     NOT displace the leader.
//
// Cache shape lock (D-42N-CACHE-01, locked at Phase 292 §3.b):
//   - Flat `uint32[32]` indexed `(q << 3) | s`; pass-1 SLOADs 4 packed slots
//     once and unrolls 32 fields into the flat cache. Mirror via `Uint32Array(32)`.
//
// Entropy domain (D-42N-COLOR-ENTROPY-01, locked at Phase 292 §3.e):
//   - Symbol-roll path consumes `keccak256(abi.encode(randomWord, day))`.
//   - Color path (separate, lives in `_applyHeroOverride` L1620) consumes
//     bits of the post-keccak word `r` and is orthogonal to this helper.
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
//   - Sister helper `raritySymbolBatchRef.mjs` covers the v41/v42 mint-batch
//     audit subject; this file is a NEW sibling for the HRROLL audit subject
//     per the Phase 282/291 file-separation pattern. Do NOT merge.

import { AbiCoder, keccak256 } from "ethers";

const U64_MASK = (1n << 64n) - 1n;
const U32_MASK = (1n << 32n) - 1n;
const U256_MASK = (1n << 256n) - 1n;
const abiCoder = AbiCoder.defaultAbiCoder();

/// @notice JS bit-mirror of `_rollHeroSymbol` (contracts/modules/DegenerusGameJackpotModule.sol L1639-L1700).
///
/// Body trace vs the live contract:
///   L1647     uint32[32] memory weights        → const weights = new Uint32Array(32)
///   L1648     uint64 total                     → let total = 0n
///   L1649     uint32 maxAmount                 → let maxAmount = 0
///   L1650     uint8 leaderIdx                  → let leaderIdx = 0
///   L1652-L1675 pass-1 nested loop (q,s) decode 32 uint32 amounts, accumulate
///             total, track strict-> first-seen leader. Mirrored verbatim.
///   L1677-L1679 if (total == 0) return (false, 0, 0)
///   L1681     uint64 leaderBonus = uint64(maxAmount) / 2
///                                            → BigInt(maxAmount) >> 1n
///   L1682     uint64 effectiveTotal = total + leaderBonus
///   L1683-L1685 uint64 pick = uint64(uint256(keccak256(abi.encode(entropy, day))) % effectiveTotal)
///   L1687-L1699 pass-2 cursor walk; leaderBonus add at idx == leaderIdx;
///             return (true, idx >> 3, idx & 7) on first cumulative > pick.
///   L1700     implicit fall-through returns named-return defaults (false, 0, 0)
///             — unreachable by invariant `pick < effectiveTotal = sum(weights) + leaderBonus`
///             but mirrored here for byte equivalence per `feedback_no_dead_guards.md`
///             carry-forward from Phase 292.
///
/// @param day uint32 day key (accepts number or BigInt; coerced via Number(day) >>> 0
///            for the flat-uint32 mask, then BigInt for the keccak input).
/// @param entropy uint256 BigInt — the raw `randomWord` plumbed through
///                `_applyHeroOverride` per the D-42N-BONUS-ENTROPY-01 carry; the
///                keccak hash with `day` produces the symbol-path entropy domain.
/// @param dailyHeroWagers BigInt[4] — the four packed uint256 slots for
///                `dailyHeroWagers[day]`, indexed by quadrant 0..3 ascending. Each
///                BigInt packs 8 × uint32 amounts at 32-bit offsets (symbol s at
///                bits `s*32 .. s*32+31`).
/// @return { hasWinner: boolean, winQuadrant: 0..3, winSymbol: 0..7 } — when
///                hasWinner is false, winQuadrant and winSymbol are 0 to mirror
///                the Solidity named-return tuple (false, 0, 0).
export function rollHeroSymbolRef({ day, entropy, dailyHeroWagers }) {
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
      const amount = Number((packed >> BigInt(s * 32)) & U32_MASK);
      const idx = (q << 3) | s;
      weights[idx] = amount;
      total = (total + BigInt(amount)) & U64_MASK;
      if (amount > maxAmount) {
        maxAmount = amount;
        leaderIdx = idx;
      }
    }
  }

  // Early-bail — HRROLL-01 zero-wager invariant.
  if (total === 0n) {
    return { hasWinner: false, winQuadrant: 0, winSymbol: 0 };
  }

  // Pass 2 — leaderBonus, effectiveTotal, keccak-derived pick, cursor walk.
  const leaderBonus = BigInt(maxAmount) >> 1n; // uint64(maxAmount) / 2
  const effectiveTotal = (total + leaderBonus) & U64_MASK;

  // Solidity `abi.encode(uint256 entropy, uint32 day)` packs each value into a
  // 32-byte word; ethers AbiCoder produces the identical byte layout (verified
  // at the v41 mint-batch oracle via Phase 282 W2 invariant pass).
  const encoded = abiCoder.encode(
    ["uint256", "uint32"],
    [entropyBn, dayBn]
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
  // named-return default per D-42N-DETERMINISM-01 + 292-02 key-decision
  // "Implicit (false,0,0) named-return for the (proven-unreachable) loop-exit path".
  return { hasWinner: false, winQuadrant: 0, winSymbol: 0 };
}

/// @notice Pack a flat 32-length uint32 array (idx layout `(q << 3) | s`) into
///         four packed BigInts mirroring the `dailyHeroWagers[day]` storage
///         layout (contracts/storage/DegenerusGameStorage.sol L1470-L1475). Each
///         per-symbol amount is capped at `0xFFFFFFFF` (uint32 max) to mirror
///         the `placeDegeneretteBet` saturation at
///         contracts/modules/DegenerusGameDegeneretteModule.sol L495.
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
