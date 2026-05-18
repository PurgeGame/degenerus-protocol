// SPDX-License-Identifier: AGPL-3.0-only
//
// randTraitTicketRef.mjs — Reference implementation of (a) `_randTraitTicket`
// (contracts/modules/DegenerusGameJackpotModule.sol L1707-L1763, ETH-path
// 25-winner trait-ticket draw) and (b) the per-pull inline gold-tier block
// within `_awardDailyCoinToTraitWinners` (same file L1860-L1894, BURNIE-path
// 1-winner-per-pull draw). Drives the 1,000-iteration TST-DPNERF-04 EV
// regression per D-295-EV-METHODOLOGY-01 and the 16-iter cross-attestation
// per D-295-INVOKE-01.
//
// Audit subject anchors:
//   - Phase 294 commit `47936e0c` — locks the ETH `_randTraitTicket` gold
//     tier flat-1 `virtualCount` branch at L1732-L1737 inside the existing
//     `if (deity != address(0))` block (D-42N-GOLD-FLOOR-01 + D-42N-DEITY-EV-01).
//   - Phase 294 BURNIE gap-closure commit `38319463` — extends the same
//     gold-tier branch logic to the inline-duplicate site at L1867-L1874
//     inside `_awardDailyCoinToTraitWinners` (D-294-BURNIE-INLINE-01). The
//     BURNIE path is NOT a caller of `_randTraitTicket`; it is a structurally
//     independent multi-bucket / 1-winner-per-iteration sampler whose
//     architectural shape is incompatible with the single-bucket / N-winner
//     signature of `_randTraitTicket`, so the gold-tier branch is inlined
//     in-place rather than reached through a function call. The two surfaces
//     carry the same locked branch shape `if (((trait >> 3) & 7) == 7)` at
//     ETH L1732 + BURNIE L1868 per `feedback_verify_call_graph_against_source.md`.
//
// Exports:
//   - goldTierVirtualCount(trait, len, deityPresent) — shared primitive
//     mirroring the L1729-L1738 (ETH) and L1864-L1874 (BURNIE) branch logic.
//   - randTraitTicketRef({ holders, randomWord, trait, numWinners, salt, deity })
//     — full ETH-path 25-winner draw mirror (L1707-L1763).
//   - awardDailyCoinPullRef({ holders, randomWord, trait_i, lvlPrime, pullIdx, deity })
//     — per-pull BURNIE-path 1-winner draw mirror (L1860-L1894).
//   - RAND_TRAIT_TICKET_CONSTANTS — frozen constants object exposing the
//     U256_MASK + DEITY_SENTINEL_TICKET_IDX values used in test assertions.
//
// Trait byte layout (per L1724-L1726):
//   trait[7:6] = quadrant
//   trait[5:3] = color (gold = 7)
//   trait[2:0] = symIdx
//   fullSymId  = quadrant * 8 + symIdx (range 0..31 has a deity slot)
//
// Numeric integrity:
//   - `len` and `virtualCount` are uint256 in Solidity; mirrored via BigInt
//     with no masking needed (BigInt arithmetic is unbounded; the `% effectiveLen`
//     operation produces values < effectiveLen < 2^256 by construction).
//   - keccak inputs use `abi.encode` (NOT `abi.encodePacked`) per L1750 + L1884
//     — each value is left-padded to a 32-byte word. ethers `AbiCoder.defaultAbiCoder()`
//     produces the identical byte layout.
//   - DEITY_SENTINEL_TICKET_IDX = type(uint256).max = (1n << 256n) - 1n
//     mirrors the L1757 (ETH) + L1893 (BURNIE) sentinel marker assigned to
//     `ticketIndexes[i]` (ETH) / `ticketIdx` (BURNIE) when the sampled `idx`
//     falls into the virtual-deity slot (`idx >= len`).
//
// Symmetric file separation:
//   - Sister helpers `rollHeroSymbolRef.mjs` (HRROLL audit subject) and
//     `raritySymbolBatchRef.mjs` (MINTCLN audit subject) cover their own
//     audit-subject scopes; this file is a NEW sibling for the DPNERF audit
//     subject per the Phase 282/291/293 file-separation pattern. Do NOT merge.

import { AbiCoder, keccak256 } from "ethers";

const U256_MASK = (1n << 256n) - 1n;
const U64_MASK = (1n << 64n) - 1n;
const U32_MASK = (1n << 32n) - 1n;
const DEITY_SENTINEL_TICKET_IDX = U256_MASK; // type(uint256).max
const ZERO_ADDRESS = "0x" + "0".repeat(40);

const abiCoder = AbiCoder.defaultAbiCoder();

/// @notice Lowercase test for whether a given `deity` address is non-zero.
///         Accepts the canonical mixed-case zero, the lowercase zero, and
///         the uppercase zero forms; any other 20-byte address counts as
///         deity-present.
function isDeityPresent(deity) {
  if (deity === undefined || deity === null) return false;
  const lower = String(deity).toLowerCase();
  return lower !== ZERO_ADDRESS && lower !== "0x0";
}

/// @notice Shared primitive: JS bit-mirror of the gold-tier-vs-common-tier
///         virtual-count branch logic that appears at TWO surfaces:
///           ETH:    contracts/modules/DegenerusGameJackpotModule.sol L1726-L1738
///           BURNIE: contracts/modules/DegenerusGameJackpotModule.sol L1863-L1874
///         Both surfaces carry the identical branch shape per D-294-BURNIE-INLINE-01.
///
/// Body trace (lines from the ETH surface; BURNIE inlines the SAME shape
/// without the surrounding `fullSymId < 32` guard since the BURNIE path
/// already short-circuits via `deityCache[traitIdx]` which only loads
/// `deityBySymbol[fullSymId]` when `fullSymId < 32` — L1842-L1845):
///   L1726     fullSymId = (trait >> 6) * 8 + (trait & 0x07)
///   L1729     if (fullSymId < 32) {
///   L1730       deity = deityBySymbol[fullSymId]
///   L1731       if (deity != address(0)) {
///   L1732         if (((trait >> 3) & 7) == 7) {        // GOLD-TIER BRANCH
///   L1733           virtualCount = 1
///   L1734         } else {
///   L1735           virtualCount = len / 50
///   L1736           if (virtualCount < 2) virtualCount = 2
///   L1737         }
///   L1738       }
///   L1739     }
///
/// @param trait uint8 (Number) — the trait byte
/// @param len BigInt — the holder-bucket length (`holders.length`)
/// @param deityPresent boolean — whether `deityBySymbol[fullSymId]` is non-zero
/// @return BigInt — `virtualCount` (0 / 1 / max(len/50, 2))
export function goldTierVirtualCount(trait, len, deityPresent) {
  const traitNum = Number(trait) & 0xff;
  const fullSymId = ((traitNum >> 6) & 0x03) * 8 + (traitNum & 0x07);
  if (fullSymId >= 32) return 0n;
  if (!deityPresent) return 0n;
  // Gold tier: color = (trait >> 3) & 7 == 7
  if (((traitNum >> 3) & 7) === 7) {
    return 1n;
  }
  // Common tier: floor(len/50), minimum 2
  const lenBn = typeof len === "bigint" ? len : BigInt(len);
  const vc = lenBn / 50n;
  return vc < 2n ? 2n : vc;
}

/// @notice JS bit-mirror of `_randTraitTicket` (contracts/modules/DegenerusGameJackpotModule.sol
///         L1707-L1763). ETH-path 25-winner draw against a single
///         `traitBurnTicket[lvl][trait]` bucket with the gold-tier flat-1
///         virtual-count branch + common-tier `max(len/50, 2)` preserved.
///
/// Body trace vs the live contract:
///   L1718     address[] storage holders = traitBurnTicket_[trait]
///                                            → caller passes the bucket
///                                              array directly as `holders`
///   L1719     uint256 len = holders.length          → BigInt(holders.length)
///   L1726-L1738 fullSymId / deity / virtualCount branch  → goldTierVirtualCount(...)
///   L1741     effectiveLen = len + virtualCount
///   L1742-L1744 if (effectiveLen == 0 || numWinners == 0) return empty
///   L1746-L1747 winners + ticketIndexes allocation
///   L1748-L1762 sampling loop:
///     L1749-L1751 idx = uint256(keccak256(abi.encode(randomWord, trait, salt, i))) % effectiveLen
///     L1752-L1754 if (idx < len) winners[i] = holders[idx]; ticketIndexes[i] = idx
///     L1755-L1758 else            winners[i] = deity;       ticketIndexes[i] = type(uint256).max
///
/// @param holders string[] — the `traitBurnTicket[lvl][trait]` bucket (the
///                           storage-mapping reference parameter is replaced
///                           by a direct array of holder addresses)
/// @param randomWord BigInt uint256 — VRF entropy plumbed through `_processDailyEth`
/// @param trait Number uint8 — the trait byte
/// @param numWinners Number uint8 — 25 in production at L1296 callsite per `_processDailyEth`
/// @param salt Number uint8 — caller-supplied salt to disambiguate concurrent draws
/// @param deity string address — the deity address (zero if no deity for the symbol)
/// @return { winners, ticketIndexes, deitySentinelMask, virtualCount }
///   winners[i]          — the holder at sampled idx, OR deity if sentinel
///   ticketIndexes[i]    — the sampled idx, OR type(uint256).max if sentinel
///   deitySentinelMask[i]— true iff position i landed on the virtual deity slot
///   virtualCount        — the BigInt computed via goldTierVirtualCount
export function randTraitTicketRef({
  holders,
  randomWord,
  trait,
  numWinners,
  salt,
  deity,
}) {
  const traitNum = Number(trait) & 0xff;
  const numWinnersNum = Number(numWinners) & 0xff;
  const saltNum = Number(salt) & 0xff;
  const randomWordBn = (
    typeof randomWord === "bigint" ? randomWord : BigInt(randomWord)
  ) & U256_MASK;

  const len = BigInt(holders.length);
  const deityPresent = isDeityPresent(deity);
  const virtualCount = goldTierVirtualCount(traitNum, len, deityPresent);
  const effectiveLen = len + virtualCount;

  if (effectiveLen === 0n || numWinnersNum === 0) {
    return {
      winners: [],
      ticketIndexes: [],
      deitySentinelMask: [],
      virtualCount,
    };
  }

  const winners = new Array(numWinnersNum);
  const ticketIndexes = new Array(numWinnersNum);
  const deitySentinelMask = new Array(numWinnersNum);

  for (let i = 0; i < numWinnersNum; ++i) {
    // L1749-L1751: idx = uint256(keccak256(abi.encode(randomWord, trait, salt, i))) % effectiveLen
    const encoded = abiCoder.encode(
      ["uint256", "uint8", "uint8", "uint8"],
      [randomWordBn, traitNum, saltNum, i]
    );
    const idx = BigInt(keccak256(encoded)) % effectiveLen;

    if (idx < len) {
      winners[i] = holders[Number(idx)];
      ticketIndexes[i] = idx;
      deitySentinelMask[i] = false;
    } else {
      // L1755-L1758: virtual deity slot
      winners[i] = deity;
      ticketIndexes[i] = DEITY_SENTINEL_TICKET_IDX;
      deitySentinelMask[i] = true;
    }
  }

  return { winners, ticketIndexes, deitySentinelMask, virtualCount };
}

/// @notice JS bit-mirror of the per-pull body of `_awardDailyCoinToTraitWinners`
///         (contracts/modules/DegenerusGameJackpotModule.sol L1852-L1911,
///         single iteration of the `for (uint256 i; i < cap; )` loop). BURNIE
///         path 1-winner-per-pull draw with the inline-duplicate gold-tier
///         branch at L1868 per D-294-BURNIE-INLINE-01.
///
/// Body trace vs the live contract (one iteration of the cap loop):
///   L1853     uint8 traitIdx = uint8(i % 4)             → caller supplies trait_i directly
///   L1854     uint8 trait_i = traitIds[traitIdx]        → caller supplies trait_i directly
///   L1856-L1858 uint24 lvlPrime = minLevel + uint24(keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i)) % range)
///                                            → caller supplies lvlPrime directly (computed upstream)
///   L1860     address[] storage holders = traitBurnTicket[lvlPrime][trait_i]
///                                            → caller passes `holders` directly
///   L1861     uint256 len = holders.length             → BigInt(holders.length)
///   L1862     address deity = deityCache[traitIdx]     → caller supplies `deity` directly
///   L1863-L1874 virtualCount branch                    → goldTierVirtualCount(trait_i, len, deity != 0)
///   L1875     uint256 effectiveLen = len + virtualCount
///   L1876-L1881 if (effectiveLen == 0) skip pull       → return isDeitySentinel=false, idx=0
///   L1883-L1885 idx = uint256(keccak256(abi.encode(randomWord, trait_i, lvlPrime, i))) % effectiveLen
///   L1888-L1893 winner / ticketIdx assignment (sentinel iff idx >= len)
///
/// @param holders string[] — the `traitBurnTicket[lvlPrime][trait_i]` bucket
/// @param randomWord BigInt uint256 — VRF entropy plumbed through `payDailyCoinJackpot`
/// @param trait_i Number uint8 — the per-iteration trait byte
/// @param lvlPrime Number uint24 — the sampled level for this pull
/// @param pullIdx BigInt or Number uint256 — the loop index `i`
/// @param deity string address — the cached deity for trait_i (zero if no deity)
/// @return { winner, ticketIdx, isDeitySentinel, virtualCount, idx, effectiveLen }
export function awardDailyCoinPullRef({
  holders,
  randomWord,
  trait_i,
  lvlPrime,
  pullIdx,
  deity,
}) {
  const traitNum = Number(trait_i) & 0xff;
  const lvlPrimeNum = Number(lvlPrime) & 0xffffff; // uint24
  const pullIdxBn =
    typeof pullIdx === "bigint" ? pullIdx : BigInt(pullIdx);
  const randomWordBn = (
    typeof randomWord === "bigint" ? randomWord : BigInt(randomWord)
  ) & U256_MASK;

  const len = BigInt(holders.length);
  const deityPresent = isDeityPresent(deity);
  const virtualCount = goldTierVirtualCount(traitNum, len, deityPresent);
  const effectiveLen = len + virtualCount;

  if (effectiveLen === 0n) {
    // L1876-L1881: empty bucket — pull is silently skipped (no winner; no
    // event emission in the contract). Mirror as a non-sentinel zero-output.
    return {
      winner: ZERO_ADDRESS,
      ticketIdx: 0n,
      isDeitySentinel: false,
      virtualCount,
      idx: 0n,
      effectiveLen,
    };
  }

  // L1883-L1885: idx = keccak256(abi.encode(randomWord, trait_i, lvlPrime, i)) % effectiveLen
  // Type list mirrors the Solidity argument list: (uint256, uint8, uint24, uint256).
  const encoded = abiCoder.encode(
    ["uint256", "uint8", "uint24", "uint256"],
    [randomWordBn, traitNum, lvlPrimeNum, pullIdxBn]
  );
  const idx = BigInt(keccak256(encoded)) % effectiveLen;

  if (idx < len) {
    return {
      winner: holders[Number(idx)],
      ticketIdx: idx,
      isDeitySentinel: false,
      virtualCount,
      idx,
      effectiveLen,
    };
  }

  // L1891-L1893: virtual deity slot
  return {
    winner: deity,
    ticketIdx: DEITY_SENTINEL_TICKET_IDX,
    isDeitySentinel: true,
    virtualCount,
    idx,
    effectiveLen,
  };
}

/// @notice Frozen constants exposed for cross-validation in test assertions
///         (e.g., the DEITY_SENTINEL_TICKET_IDX marker mirrors L1757 + L1893
///         and the U256_MASK preserves keccak-input width parity).
export const RAND_TRAIT_TICKET_CONSTANTS = Object.freeze({
  U256_MASK,
  U64_MASK,
  U32_MASK,
  DEITY_SENTINEL_TICKET_IDX,
  ZERO_ADDRESS,
});
