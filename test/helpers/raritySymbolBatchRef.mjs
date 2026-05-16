// SPDX-License-Identifier: AGPL-3.0-only
//
// raritySymbolBatchRef.mjs — Reference implementation of
// `_raritySymbolBatch` (contracts/modules/DegenerusGameMintModule.sol L544-L643)
// at HEAD `221afcf7`. Verbatim port of the per-group-of-16 keccak seed + LCG
// step + per-trait offset extraction body, intended as the off-chain
// indexer-replay oracle for the W2 invariant.
//
// Exports:
//   - TICKET_LCG_MULT — uint64 LCG multiplier (matches Mint module L92).
//   - computeBaseKey(lvl, queueIdx, player) — bit-for-bit equivalent of the
//     baseKey layout at L423-L425 (future-pool path) and L800 (current-level
//     path).
//   - raritySymbolBatchRef({baseKey, entropyWord, ownedSalt, startIndex, count})
//     — returns a Uint8Array of length `count` carrying the trait IDs the
//     post-fix `_raritySymbolBatch` credits for a single batched call.
//
// Trait ID shape (matches DegenerusTraitUtils.traitFromWord L143-L147 +
// the quadrant addition at L585-L586):
//   trait[7:6] = quadrant = i & 3
//   trait[5:3] = color tier (DegenerusTraitUtils.weightedColorBucket)
//   trait[2:0] = symbol = (s >> 32) & 7
//
// Numeric integrity:
//   - Solidity uint64 multiplication is mod 2^64. The JS port masks every
//     LCG step with U64_MASK = (1n << 64n) - 1n to preserve byte equivalence.
//   - Solidity `abi.encode(uint256 baseKey, uint256 entropyWord, uint32
//     groupIdx, uint32 ownedSalt)` packs each value into a 32-byte word
//     (uint32 left-padded to 32 bytes); ethers `AbiCoder.defaultAbiCoder()`
//     produces the identical byte layout.

import { AbiCoder, keccak256, getBytes } from "ethers";

const U64_MASK = (1n << 64n) - 1n;
const U32_MASK = (1n << 32n) - 1n;

/// @notice uint64 LCG multiplier shared with contracts/modules/DegenerusGameMintModule.sol L92.
export const TICKET_LCG_MULT = 6364136223846793005n;

/// @notice Encode baseKey identically to DegenerusGameMintModule.sol L423-L425 (future-pool)
///         and L800 (current-level): `(uint256(lvl) << 224) | (idx << 192) |
///         (uint256(uint160(player)) << 32)`.
/// @param lvl uint24 level; accepts number or bigint
/// @param queueIdx uint64-ish queue index; accepts number or bigint
/// @param player 0x-prefixed 20-byte address string or bigint
/// @return 256-bit baseKey as a BigInt
export function computeBaseKey(lvl, queueIdx, player) {
  const lvlBn = BigInt(lvl);
  const idxBn = BigInt(queueIdx);
  let playerBn;
  if (typeof player === "bigint") {
    playerBn = player;
  } else if (typeof player === "string") {
    playerBn = BigInt(player);
  } else {
    throw new Error("computeBaseKey: player must be hex string or bigint");
  }
  // uint160 truncation matches `uint256(uint160(player))`.
  const playerU160 = playerBn & ((1n << 160n) - 1n);
  return (lvlBn << 224n) | (idxBn << 192n) | (playerU160 << 32n);
}

/// @notice 256-bit -> 32-bit color bucket per DegenerusTraitUtils.weightedColorBucket L115-L127.
function weightedColorBucket(rnd32) {
  // rnd32 is uint32 (bigint in 0..2^32-1).
  // scaled = uint32((uint64(rnd) * 256) >> 32)
  const scaled = Number((rnd32 * 256n) >> 32n);
  if (scaled < 64) return 0;
  if (scaled < 128) return 1;
  if (scaled < 192) return 2;
  if (scaled < 224) return 3;
  if (scaled < 240) return 4;
  if (scaled < 248) return 5;
  if (scaled < 254) return 6;
  return 7;
}

/// @notice 64-bit -> 6-bit trait ID per DegenerusTraitUtils.traitFromWord L143-L147.
function traitFromWord(s) {
  // s is uint64 bigint. Low 32 bits → weighted color; bits 32..39 → symbol (& 7).
  const low32 = s & U32_MASK;
  const color = weightedColorBucket(low32);
  const symbol = Number((s >> 32n) & 7n);
  return (color << 3) | symbol;
}

const abiCoder = AbiCoder.defaultAbiCoder();

/// @notice Reference port of `_raritySymbolBatch` (DegenerusGameMintModule.sol
///         L544-L643). Returns the sequence of trait IDs the contract would
///         credit for a single batched call.
///
/// Body trace vs the live contract (line-anchored against HEAD 221afcf7):
///   L557-L560 endIndex = startIndex + count (unchecked → unbounded wrap acceptable
///             for the iteration domain; mirrored as plain BigInt add here).
///   L561      i = startIndex.
///   L564-L596 outer while (i < endIndex):
///     L565      groupIdx = i >> 4.
///     L571-L573 seed = uint256(keccak256(abi.encode(baseKey, entropyWord,
///                       groupIdx, ownedSalt)))  (types: u256, u256, u32, u32).
///     L574      s = uint64(seed) | 1.
///     L575      offset = uint8(i & 15).
///     L577      s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset)
///                   (unchecked uint64).
///     L580-L594 inner for j = offset .. 15 while i < endIndex:
///       L582    s = s * TICKET_LCG_MULT + 1                     (unchecked uint64).
///       L585    traitId = traitFromWord(s) + (uint8(i & 3) << 6) (quadrant add).
///       L589    record traitId (the contract increments counts[] + touchedTraits[];
///                this oracle returns the sequence directly).
///       L592    ++i.
///       L593    ++j.
///
/// @param baseKey uint256 BigInt (computed via computeBaseKey or extracted from
///                a captured TraitsGenerated event's emit-time inputs)
/// @param entropyWord uint256 BigInt (the daily VRF word)
/// @param ownedSalt uint32 number/BigInt (= owed_at_call_entry per the patched
///                  callsites at L469 + L803; emitted as the 4th positional
///                  field of TraitsGenerated)
/// @param startIndex uint32 number/BigInt (= `processed` per the patched
///                   callsites; emitted as TraitsGenerated.startIndex's
///                   sister-3rd-position `queueIdx` is unrelated — this is
///                   the `startIndex` LOCAL passed to _raritySymbolBatch)
/// @param count uint32 number/BigInt (= `take` per the patched callsites;
///              emitted as TraitsGenerated.count's 5th positional field)
/// @return Uint8Array length `count` of trait IDs
export function raritySymbolBatchRef({
  baseKey,
  entropyWord,
  ownedSalt,
  startIndex,
  count,
}) {
  const baseKeyBn = typeof baseKey === "bigint" ? baseKey : BigInt(baseKey);
  const entropyBn =
    typeof entropyWord === "bigint" ? entropyWord : BigInt(entropyWord);
  const ownedSaltBn =
    typeof ownedSalt === "bigint" ? ownedSalt : BigInt(ownedSalt);
  const startIndexNum =
    typeof startIndex === "bigint" ? Number(startIndex) : Number(startIndex);
  const countNum = typeof count === "bigint" ? Number(count) : Number(count);

  const out = new Uint8Array(countNum);
  let written = 0;

  const endIndex = startIndexNum + countNum;
  let i = startIndexNum;

  while (i < endIndex) {
    const groupIdx = BigInt(i >> 4);

    // Solidity `abi.encode(uint256, uint256, uint32, uint32)` packs each
    // value into a 32-byte word. ethers AbiCoder produces the identical
    // byte layout; keccak256 over those 128 bytes matches the EVM.
    const encoded = abiCoder.encode(
      ["uint256", "uint256", "uint32", "uint32"],
      [baseKeyBn, entropyBn, groupIdx, ownedSaltBn]
    );
    const seed = BigInt(keccak256(getBytes(encoded)));

    // s = uint64(seed) | 1
    let s = (seed & U64_MASK) | 1n;
    const offset = i & 15;
    const offsetBn = BigInt(offset);

    // s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset)
    // All arithmetic is uint64 mod 2^64.
    s = (s * ((TICKET_LCG_MULT + offsetBn) & U64_MASK) + offsetBn) & U64_MASK;

    for (let j = offset; j < 16 && i < endIndex; ) {
      // s = s * TICKET_LCG_MULT + 1
      s = (s * TICKET_LCG_MULT + 1n) & U64_MASK;

      const quadrant = i & 3;
      const trait = (traitFromWord(s) + (quadrant << 6)) & 0xff;
      out[written++] = trait;

      ++i;
      ++j;
    }
  }

  return out;
}
