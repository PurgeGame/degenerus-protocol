// SPDX-License-Identifier: AGPL-3.0-only
//
// ticketTraitsRef.mjs — Independent replay of `_generateTraitRun`
// (contracts/modules/DegenerusGameTicketModule.sol) for indexers and tests.
//
// Each aligned group of sixteen entries is seeded by
// keccak256(abi.encode(RngTags.TICKET_TRAITS, entropyWord, identity without the wallet ID,
// groupIdx)); the low 64 bits (| 1) start an LCG that yields one trait per entry:
//   trait[7:6] = quadrant = i & 3
//   trait[5:3] = color tier (DegenerusTraitUtils.weightedColorBucket on the low 32 bits)
//   trait[2:0] = symbol = (s >> 32) & 7
// The first natural gold six (trait 253) of a level is kept; later ones take
// GoldSixLib.replacement.
//
// Solidity uint64 multiplication wraps mod 2^64, so every LCG step is masked with U64_MASK.

import { AbiCoder, keccak256 } from "ethers";

const U64_MASK = (1n << 64n) - 1n;
const U32_MASK = (1n << 32n) - 1n;

/// @notice uint64 LCG multiplier, TICKET_LCG_MULT in DegenerusGameTicketModule.sol.
export const TICKET_LCG_MULT = 6364136223846793005n;

/// @notice 32-bit input -> color tier, DegenerusTraitUtils.weightedColorBucket.
function weightedColorBucket(rnd32) {
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

/// @notice 64-bit input -> 6-bit trait ID, DegenerusTraitUtils.traitFromWord.
function traitFromWord(s) {
  const color = weightedColorBucket(s & U32_MASK);
  const symbol = Number((s >> 32n) & 7n);
  return (color << 3) | symbol;
}

const abiCoder = AbiCoder.defaultAbiCoder();

export const CHECKPOINT_DOMAINS = Object.freeze({ half0: 0x20, half1: 0x21, future: 0x22, foil: 0x23 });

export function checkpointIdentity({ level, queueIndex, walletId, domain = CHECKPOINT_DOMAINS.half0 }) {
  const lvl = BigInt(level), index = BigInt(queueIndex), who = BigInt(walletId);
  if (lvl < 0n || lvl > 0xffffffn || index < 0n || index > U32_MASK || who < 0n || who > U32_MASK) {
    throw new RangeError("ticket identity exceeds its packed field");
  }
  if (!Object.values(CHECKPOINT_DOMAINS).includes(domain)) throw new RangeError("unknown ticket domain");
  return (BigInt(domain) << 248n) | (lvl << 224n) | (index << 192n) | (who << 32n);
}

export function decodeCheckpointKey(baseKey) {
  const goldSixTaken = (BigInt(baseKey) >> 255n) !== 0n;
  const key = BigInt(baseKey) & ~(1n << 255n);
  const domain = Number(key >> 248n);
  if (!Object.values(CHECKPOINT_DOMAINS).includes(domain)) throw new RangeError("unknown ticket generator version/domain");
  return {
    domain,
    goldSixTaken,
    level: Number((key >> 224n) & 0xffffffn),
    queueIndex: Number((key >> 192n) & U32_MASK),
    walletId: Number((key >> 32n) & U32_MASK),
    startIndex: Number(key & U32_MASK),
    identity: key & ~U32_MASK,
  };
}

/// Replay one event independently: low32 is its absolute solo offset, never owed.
/// Foil keeps its separate boosted four-line algorithm and must not enter this decoder.
export function ticketCheckpointTraits({ baseKey, entropyWord, count }) {
  const decoded = decodeCheckpointKey(baseKey);
  if (decoded.domain === CHECKPOINT_DOMAINS.foil) throw new RangeError("foil requires its frozen boost and foil replay");
  const start = BigInt(decoded.startIndex), n = BigInt(count), end = start + n;
  if ((start & 15n) !== 0n || n < 0n || n > U32_MASK || end > (1n << 32n)) {
    throw new RangeError("invalid checkpoint range");
  }
  const out = new Uint8Array(Number(n));
  let written = 0;
  let goldSixTaken = decoded.goldSixTaken;
  for (let i = start; i < end;) {
    const seed = BigInt(keccak256(abiCoder.encode(
      ["uint256", "uint256", "uint256", "uint256"], [105n, BigInt(entropyWord), decoded.identity & ~(U32_MASK << 32n), i / 16n]
    )));
    let s = ((seed & U64_MASK) | 1n) * TICKET_LCG_MULT & U64_MASK;
    for (let j = 0; j < 16 && i < end; ++j, ++i) {
      s = (s * TICKET_LCG_MULT + 1n) & U64_MASK;
      let trait = traitFromWord(s) | (Number(i & 3n) << 6);
      if (trait === 253) {
        if (goldSixTaken) {
          const tag = 70n;
          const pick = Number(BigInt(keccak256(abiCoder.encode(["uint256", "uint256"], [tag, s]))) % 7n);
          trait = 248 + pick + (pick >= 5 ? 1 : 0);
        } else goldSixTaken = true;
      }
      out[written++] = trait;
    }
  }
  return out;
}

/// Decode the anonymous EntryTraitsRevealed event's four packed seat topics, (level << 160) | walletId.
export function seatedTicketReveals(log) {
  if (log.topics.length !== 4 || log.data.length !== 66) return [];
  const topics = log.topics.map(BigInt);
  if (topics.some((v) => v >> 184n !== 0n)) return [];
  const word = BigInt(log.data), mask = word >> 128n, out = [];
  for (let seat = 0; seat < 4; ++seat) {
    if (topics[seat] === 0n) continue;
    for (let quadrant = 0; quadrant < 4; ++quadrant) {
      if ((mask >> BigInt(seat * 4 + quadrant) & 1n) === 0n) continue;
      out.push({
        lvl: Number(topics[seat] >> 160n),
        walletId: Number(topics[seat] & U32_MASK),
        trait: Number(word >> BigInt(seat * 32 + quadrant * 8) & 255n),
      });
    }
  }
  return out;
}
