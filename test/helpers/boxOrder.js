// Test-side encoders for the box purchase input that purchase()'s third parameter carries:
// [quantity:7][kind:2][customUnits:21], every bit at or above 30 zero; kind 0 small, 1 medium,
// 2 large, 3 custom; custom units in 0.001 ETH (10..2,000,000). Decoders read the stored 85-bit
// queue entry (LB_* layout in DegenerusGameStorage), three entries per storage word: logical
// position p sits in word p / 3 at bit (p % 3) * 85. One box type per purchase; each purchase
// is its own entry.
//
// Migration rule: an old test that passed X wei of lootbox spend buys the SAME wei as ONE
// custom box of size X — boCustom(X) — when X is a whole number of 0.001 ETH.
"use strict";

const SCALE = 10n ** 15n; // LB_VALUE_UNIT (0.001 ETH)
const UNITS_MIN = 10n;
const UNITS_MAX = 2_000_000n;
const KIND = { small: 0n, med: 1n, large: 2n, custom: 3n };
const ENTRY_BITS = 85n;
const ENTRY_MASK = (1n << 85n) - 1n;
const SCORE_CODE_EXACT = 2042n;
const SCORE_CODE_STEP = 14n;
const SCORE_CAP = 30_000n;

function boInput(kind, qty, units = 0n) {
  return BigInt(qty) | (BigInt(kind) << 7n) | (BigInt(units) << 9n);
}

function _count(n, label) {
  const c = BigInt(n);
  if (c === 0n || c > 100n) throw new Error(`${label}: count ${c}`);
  return c;
}

function boCustoms(n, wei) {
  const w = BigInt(wei);
  if (w % SCALE !== 0n || w / SCALE < UNITS_MIN || w / SCALE > UNITS_MAX) {
    throw new Error(`boCustoms: size ${w} is not a whole 0.001 ETH in 0.01..2,000 ETH`);
  }
  return boInput(KIND.custom, _count(n, "boCustoms"), w / SCALE);
}

function boCustom(wei) {
  return boCustoms(1n, wei);
}

// Floors to 0.001 ETH; 0 (no box) below one unit. The contract rejects customs below 10 units.
function boCustomFloor(wei) {
  const units = BigInt(wei) / SCALE;
  return units === 0n ? 0n : boInput(KIND.custom, 1n, units);
}

function boSmalls(n) {
  return boInput(KIND.small, _count(n, "boSmalls"));
}

function boMeds(n) {
  return boInput(KIND.med, _count(n, "boMeds"));
}

function boLarges(n) {
  return boInput(KIND.large, _count(n, "boLarges"));
}

// Count-shaped encoder for ONE box type: exactly one count is nonzero.
function boOrder({ small = 0n, med = 0n, large = 0n, customCount = 0n, customSizeWei = 0n }) {
  const counts = [small, med, large, customCount].map(BigInt);
  if (counts.filter((c) => c !== 0n).length !== 1) throw new Error("boOrder: one box type per purchase");
  if (BigInt(customCount) !== 0n) return boCustoms(customCount, customSizeWei);
  if (BigInt(customSizeWei) !== 0n) throw new Error("boOrder: preset with size");
  if (BigInt(small) !== 0n) return boSmalls(small);
  if (BigInt(med) !== 0n) return boMeds(med);
  return boLarges(large);
}

// ---- activity score code (mirrors the Lootbox module) ----

function scoreCode(score) {
  let s = BigInt(score);
  if (s > SCORE_CAP) s = SCORE_CAP;
  return s <= SCORE_CODE_EXACT ? s : SCORE_CODE_EXACT + (s - SCORE_CODE_EXACT) / SCORE_CODE_STEP;
}

function scoreFromCode(code) {
  const c = BigInt(code);
  return c <= SCORE_CODE_EXACT ? c : SCORE_CODE_EXACT + (c - SCORE_CODE_EXACT) * SCORE_CODE_STEP;
}

// ---- stored entry decoders (LB_* layout in DegenerusGameStorage) ----

function boDecode(entry) {
  const x = BigInt(entry);
  const units = (x >> 32n) & 0x1fffffn;
  const code = (x >> 53n) & 0xfffn;
  return {
    walletId: x & 0xffffffffn,
    units,
    sizeWei: units * SCALE,
    scoreCode: code,
    score: scoreFromCode(code),
    boostBps: (x >> 65n) & 0xfffn,
    count: (x >> 77n) & 0x7fn,
    distress: ((x >> 84n) & 1n) === 1n,
    highBits: x >> 85n, // always zero in a decoded entry
  };
}

function boCount(entry) {
  return boDecode(entry).count;
}

// Nominal wei a stored entry represents (quantity x per-box value).
function boNominal(entry) {
  const d = boDecode(entry);
  return d.count * d.sizeWei;
}

// ---- queue addressing ----

function boWordIndex(position) {
  return BigInt(position) / 3n;
}

function boLane(physicalWord, position) {
  return (BigInt(physicalWord) >> ((BigInt(position) % 3n) * ENTRY_BITS)) & ENTRY_MASK;
}

// ESM named export — this file lives under the project's "type": "module" scope,
// so `module.exports` (CommonJS) throws ReferenceError here.
export {
  SCALE,
  UNITS_MIN,
  UNITS_MAX,
  KIND,
  boInput,
  boCustom,
  boCustomFloor,
  boCustoms,
  boSmalls,
  boMeds,
  boLarges,
  boOrder,
  scoreCode,
  scoreFromCode,
  boDecode,
  boCount,
  boNominal,
  boWordIndex,
  boLane,
};
