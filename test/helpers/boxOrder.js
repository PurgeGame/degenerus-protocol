// Test-side encoders for the box purchase input that purchase()'s third parameter carries:
// [small:8][med:8][large:8][customCount:8][customSize:56 gwei], every bit at or above 88 zero.
// Decoders read the stored queue entry (LB_* layout in DegenerusGameStorage). Each purchase is
// its own entry.
//
// Migration rule: an old test that passed X wei of lootbox spend buys the SAME wei as ONE
// custom box of size X — boCustom(X).
"use strict";

const SCALE = 10n ** 9n; // LB_SIZE_UNIT (1 gwei)

function boCustom(wei) {
  const w = BigInt(wei);
  if (w === 0n || w % SCALE !== 0n) throw new Error(`boCustom: bad wei ${w}`);
  return (1n << 24n) | ((w / SCALE) << 32n);
}

function boCustomFloor(wei) {
  const units = BigInt(wei) / SCALE;
  return units === 0n ? 0n : (1n << 24n) | (units << 32n);
}

function boCustoms(n, wei) {
  const w = BigInt(wei);
  const c = BigInt(n);
  if (w === 0n || w % SCALE !== 0n || c === 0n || c > 100n) throw new Error("boCustoms: args");
  return (c << 24n) | ((w / SCALE) << 32n);
}

function boSmalls(n) {
  const c = BigInt(n);
  if (c === 0n || c > 100n) throw new Error("boSmalls: count");
  return c;
}

function boOrder({ small = 0n, med = 0n, large = 0n, customCount = 0n, customSizeWei = 0n }) {
  const w = BigInt(customSizeWei);
  if (w % SCALE !== 0n) throw new Error("boOrder: granularity");
  return (
    BigInt(small) |
    (BigInt(med) << 8n) |
    (BigInt(large) << 16n) |
    (BigInt(customCount) << 24n) |
    ((w / SCALE) << 32n)
  );
}

// ---- stored entry decoders (LB_* layout in DegenerusGameStorage) ----

function boDecode(word) {
  const x = BigInt(word);
  return {
    walletId: x & 0xffffffffn,
    level: (x >> 32n) & 0xffffffn,
    score: (x >> 56n) & 0x7fffn,
    boostBps: (x >> 71n) & 0x3fffn,
    evBps: (x >> 85n) & 0x3fffn,
    distress: ((x >> 99n) & 1n) === 1n,
    small: (x >> 100n) & 0x7fn,
    med: (x >> 107n) & 0x7fn,
    large: (x >> 114n) & 0x7fn,
    customCount: (x >> 121n) & 0x7fn,
    sizeWei: ((x >> 128n) & 0xffffffffffffffn) * SCALE,
    cover: ((x >> 184n) & 1n) === 1n,
    presaleWei: (x >> 185n) & 0x3ffffffffffffffffn,
    presaleTier: (x >> 251n) & 7n,
    presaleClosing: ((x >> 254n) & 1n) === 1n,
  };
}

function boCount(word) {
  const d = boDecode(word);
  return d.small + d.med + d.large + d.customCount + (d.cover ? 1n : 0n);
}

// Nominal wei a stored entry's ordinary leg represents at its own level's ticket price.
function boNominal(word, levelPriceWei) {
  const d = boDecode(word);
  if (d.cover) return d.sizeWei;
  return (d.small + 5n * d.med + 25n * d.large) * BigInt(levelPriceWei) + d.customCount * d.sizeWei;
}

// ESM named export — this file lives under the project's "type": "module" scope,
// so `module.exports` (CommonJS) throws ReferenceError here.
export { SCALE, boCustom, boCustomFloor, boCustoms, boSmalls, boOrder, boDecode, boCount, boNominal };
