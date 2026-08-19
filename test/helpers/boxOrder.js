// Test-side encoders for the packed box order that purchase()'s third parameter now
// carries: [small:8][med:8][large:8][customCount:8][customSize:48 @1e12].
//
// Migration rule: an old test that passed X wei of lootbox spend buys the SAME wei as ONE
// custom box of size X — boCustom(X) — the closest semantic match to the old accumulated
// single box (same spend, same pool contribution; one roll at full size instead of the old
// 0.5-ETH auto-split pair).
"use strict";

const SCALE = 10n ** 12n; // LB_CUSTOM_SCALE

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

// ---- storage-word decoders (LB_* layout in DegenerusGameStorage) ----

function boDecode(word) {
  const x = BigInt(word);
  return {
    level: x & 0xffffffn,
    score: (x >> 24n) & 0x7fffn,
    boostBps: (x >> 39n) & 0x3fffn,
    distressBps: (x >> 53n) & 0x3fffn,
    adjBps: (x >> 67n) & 0x3fffn,
    small: (x >> 81n) & 0xffn,
    med: (x >> 89n) & 0xffn,
    large: (x >> 97n) & 0xffn,
    customCount: (x >> 105n) & 0xffn,
    customSizeWei: ((x >> 113n) & 0xffffffffffffn) * SCALE,
    coverWei: ((x >> 161n) & 0xffffffffffffn) * SCALE,
  };
}

function boCount(word) {
  const d = boDecode(word);
  return d.small + d.med + d.large + d.customCount + (d.coverWei === 0n ? 0n : 1n);
}

// Nominal wei a stored order represents — replacement for the old lootboxEth word's
// low-128-bit amount. NOTE: excludes the boon boost the old amount included.
function boNominal(word, levelPriceWei) {
  const d = boDecode(word);
  return (
    (d.small + 5n * d.med + 25n * d.large) * BigInt(levelPriceWei) +
    d.customCount * d.customSizeWei +
    d.coverWei
  );
}

// ESM named export — this file lives under the project's "type": "module" scope,
// so `module.exports` (CommonJS) throws ReferenceError here.
export { SCALE, boCustom, boCustomFloor, boCustoms, boSmalls, boOrder, boDecode, boCount, boNominal };
