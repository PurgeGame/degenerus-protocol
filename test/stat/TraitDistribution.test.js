// SPDX-License-Identifier: AGPL-3.0-only
// Phase 261 STAT-01/02/03 + D-03 boundary cross-validation harness.
// Heavy Monte Carlo — runs ONLY under `npm run test:stat` (NOT default `npm test`).
// Deterministic seeded keccak-counter PRNG; reproducibility = exact replay on failure.
//
// ---------------------------------------------------------------------------
// Architecture (D-03 hybrid oracle):
//
//   - The 1M-sample loops use `jsWeightedColorBucket`, a JS replica of
//     `DegenerusTraitUtils.weightedColorBucket(uint32)`. A JS replica is
//     necessary because per-sample EVM tester calls take milliseconds while
//     a JS function takes microseconds — 1M tester calls would push the
//     suite from minutes into hours.
//
//   - The drift guard against the JS replica getting out of sync with the
//     production thresholds is the D-03 boundary cross-validation harness:
//     16 `it` blocks at every threshold edge in the production library
//     (scaled ∈ {0, 63, 64, 127, 128, 191, 192, 223, 224, 239, 240, 247,
//     248, 253, 254, 255}) assert `js == onChain == expected`. JS-replica
//     drift is structurally impossible without the boundary harness
//     failing first; a bulk-loop assertion cannot be silently wrong unless
//     a boundary assertion is also wrong.
// ---------------------------------------------------------------------------

import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";

async function deployTester() {
  const Tester = await hre.ethers.getContractFactory("TraitUtilsTester");
  const tester = await Tester.deploy();
  await tester.waitForDeployment();
  return { tester };
}

// Reverse-map a `scaled` value (0..255) to a `rnd` uint32 such that
//   uint32((uint64(rnd) * 256) >> 32) === scaled
// The clean inverse is `rnd = scaled << 24` because
//   (scaled * 2^24 * 256) >> 32 = (scaled * 2^32) >> 32 = scaled.
function rndForScaled(scaled) {
  return BigInt(scaled) << 24n;
}

// Deterministic 256-bit PRNG: keccak256(seed || counter). Cryptographic
// uniformity (suitable for chi-squared bucketing) AND reproducible — the
// fixed seed makes any future failure exactly replayable. Bound to ethers'
// built-in keccak256 so the test has no extra dependency.
function makeRng(seed) {
  const seedHex = "0x" + BigInt.asUintN(256, BigInt(seed)).toString(16).padStart(64, "0");
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

// JS replica of DegenerusTraitUtils.weightedColorBucket(uint32 rnd).
// Drift guard: D-03 boundary harness asserts equality with the production tester
// at every threshold value scaled ∈ {0, 63, 64, ..., 254, 255}. If this replica
// drifts from the production thresholds, the boundary harness FAILS FIRST
// — the bulk MC loops downstream cannot be wrong without the boundary harness
// also being wrong.
function jsWeightedColorBucket(rnd) {
  // rnd is a BigInt in [0, 2^32). scaled = uint32((uint64(rnd) * 256) >> 32).
  const scaled = (rnd * 256n) >> 32n; // BigInt math; result fits in 9 bits.
  if (scaled < 64n) return 0;
  if (scaled < 128n) return 1;
  if (scaled < 192n) return 2;
  if (scaled < 224n) return 3;
  if (scaled < 240n) return 4;
  if (scaled < 248n) return 5;
  if (scaled < 254n) return 6;
  return 7;
}

// Extract symbol via the same composition as traitFromWord:
//   symbol = uint8(rnd64 >> 32) & 7
function jsSymbol(rnd64) {
  return Number((rnd64 >> 32n) & 7n);
}

// Chi-squared critical values at alpha = 0.05, extended from
// test/unit/JackpotSoloPicker.test.js (which only covered df 1..3).
// STAT-01 / STAT-03 use df=7 (8 buckets - 1).
// STAT-02 (color × symbol joint independence) uses df=49 — see jointChi2 below.
const CHI2_CRIT_05 = {
  1: 3.841,  2: 5.991,  3: 7.815,  4: 9.488,
  5: 11.070, 6: 12.592, 7: 14.067,
};

// Wilson-Hilferty approximation: for X ~ chi²(df), Z = ((X/df)^(1/3) - (1 - 2/(9*df)))
// / sqrt(2/(9*df)) is approximately N(0, 1). One-sided right-tail at alpha=0.05
// is Z > 1.645. Used for df=49 where listing the literal critical value
// (66.339) inline would lose audit trail; the closed-form approximation is
// transparent and self-evident.
function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}

// ===========================================================================
// STAT-01 — color frequency over 1M samples.
// Empirical chi-squared + per-bucket 3-sigma binomial bounds + ±0.1% absolute
// tolerance against analytical heavy-tail spec
// [25.000%, 25.000%, 25.000%, 12.500%, 6.250%, 3.125%, 2.344%, 0.781%].
// ===========================================================================

describe("STAT-01 — color frequency over 1M samples", function () {
  this.timeout(180000);

  it("color buckets fall within 3-sigma binomial bounds at N=1_000_000", function () {
    const N = 1_000_000;
    // Seed 0xC010_0001 — distinct per-test seed (D-03 reproducibility note).
    const rng = makeRng(0xC010_0001);
    const counts = new Array(8).fill(0);

    for (let i = 0; i < N; i++) {
      const rnd256 = rng();
      const rnd32 = rnd256 & 0xFFFFFFFFn;
      counts[jsWeightedColorBucket(rnd32)]++;
    }

    // Analytical color tier probabilities (256-resolution heavy tail).
    const P = [0.25000, 0.25000, 0.25000, 0.12500, 0.06250, 0.03125, 0.02344, 0.00781];

    for (let i = 0; i < 8; i++) {
      const expected = N * P[i];
      const sigma = Math.sqrt(N * P[i] * (1 - P[i]));
      const absDeviation = Math.abs(counts[i] - expected);
      const relDeviation = Math.abs(counts[i] / N - P[i]);
      expect(
        absDeviation <= 3 * sigma,
        `color ${i}: |${counts[i]} - ${expected}| = ${absDeviation.toFixed(1)} > 3σ = ${(3 * sigma).toFixed(1)} (counts=[${counts.join(",")}])`,
      ).to.be.true;
      expect(
        relDeviation <= 0.001,
        `color ${i}: |${(counts[i] / N).toFixed(6)} - ${P[i]}| = ${relDeviation.toFixed(6)} > 0.001 (counts=[${counts.join(",")}])`,
      ).to.be.true;
    }

    // Chi-squared goodness-of-fit at df=7.
    let chi2 = 0;
    for (let i = 0; i < 8; i++) {
      const expected = N * P[i];
      const diff = counts[i] - expected;
      chi2 += (diff * diff) / expected;
    }
    expect(
      chi2 < CHI2_CRIT_05[7],
      `STAT-01 chi² = ${chi2.toFixed(3)} >= ${CHI2_CRIT_05[7]} (df=7) (counts=[${counts.join(",")}])`,
    ).to.be.true;
  });
});

// ===========================================================================
// STAT-02 — color × symbol joint independence over 1M samples.
// Asserts that the color tier (low-32-bit-derived) and the symbol (high-32-bit
// 3-bit slice) are statistically independent at alpha=0.05 via chi-squared
// test of independence. df = (8-1)*(8-1) = 49 → Wilson-Hilferty Z one-sided.
// ===========================================================================

describe("STAT-02 — color × symbol joint independence over 1M samples", function () {
  this.timeout(240000);

  it("joint (color, symbol) chi² does not reject independence at alpha=0.05 (Wilson-Hilferty Z < 1.645)", function () {
    const N = 1_000_000;
    // Seed 0xC010_0002 — distinct from STAT-01 to avoid sequence reuse.
    const rng = makeRng(0xC010_0002);

    const joint = Array.from({ length: 8 }, () => new Array(8).fill(0));
    const colorMarg = new Array(8).fill(0);
    const symMarg = new Array(8).fill(0);

    for (let i = 0; i < N; i++) {
      const rnd64 = rng() & 0xFFFFFFFFFFFFFFFFn;
      const color = jsWeightedColorBucket(rnd64 & 0xFFFFFFFFn);
      const symbol = jsSymbol(rnd64);
      joint[color][symbol]++;
      colorMarg[color]++;
      symMarg[symbol]++;
    }

    // Chi-squared test of independence: E[c][s] = (rowSum * colSum) / N.
    let chi2 = 0;
    for (let c = 0; c < 8; c++) {
      for (let s = 0; s < 8; s++) {
        const expected = (colorMarg[c] * symMarg[s]) / N;
        if (expected > 0) {
          const diff = joint[c][s] - expected;
          chi2 += (diff * diff) / expected;
        }
      }
    }

    const z = wilsonHilfertyZ(chi2, 49);
    expect(
      z < 1.645,
      `STAT-02 chi² = ${chi2.toFixed(3)}, Wilson-Hilferty Z = ${z.toFixed(3)} >= 1.645 (df=49)`,
    ).to.be.true;
  });
});

// ===========================================================================
// STAT-03 — symbol uniformity over 1M samples.
// Asserts that the symbol bits (uint8(rnd >> 32) & 7) are uniformly
// distributed across the 8 symbol values via chi-squared at df=7.
// ===========================================================================

describe("STAT-03 — symbol uniformity over 1M samples", function () {
  this.timeout(180000);

  it("symbol distribution is uniform across 8 values (chi² < 14.067 at df=7)", function () {
    const N = 1_000_000;
    // Seed 0xC010_0003 — distinct from STAT-01 / STAT-02.
    const rng = makeRng(0xC010_0003);
    const symCounts = new Array(8).fill(0);

    for (let i = 0; i < N; i++) {
      const rnd64 = rng() & 0xFFFFFFFFFFFFFFFFn;
      symCounts[jsSymbol(rnd64)]++;
    }

    // Uniform expected = N / 8 = 125_000 per bucket.
    const expected = N / 8;
    let chi2 = 0;
    for (let i = 0; i < 8; i++) {
      const diff = symCounts[i] - expected;
      chi2 += (diff * diff) / expected;
    }

    expect(
      chi2 < CHI2_CRIT_05[7],
      `STAT-03 chi² = ${chi2.toFixed(3)} >= ${CHI2_CRIT_05[7]} (df=7) (counts=[${symCounts.join(",")}])`,
    ).to.be.true;
  });
});

// ===========================================================================
// D-03 — boundary cross-validation: JS-replica vs production tester.
// 16 `it` blocks (one per boundary edge) assert that `jsWeightedColorBucket`
// and `TraitUtilsTester.weightedColorBucket` both return the analytically-
// expected color tier at every threshold value. This is the structural drift
// guard for the bulk Monte Carlo loops above — if the JS replica drifts from
// the production thresholds, every affected boundary `it` fails first.
// ===========================================================================

describe("D-03 — boundary cross-validation: JS-replica vs production tester", function () {
  const BOUNDARIES = [
    [0, 0], [63, 0], [64, 1], [127, 1], [128, 2], [191, 2],
    [192, 3], [223, 3], [224, 4], [239, 4], [240, 5], [247, 5],
    [248, 6], [253, 6], [254, 7], [255, 7],
  ];

  for (const [scaled, expectedColor] of BOUNDARIES) {
    it(`scaled=${scaled} → JS replica == production tester == ${expectedColor}`, async function () {
      const { tester } = await loadFixture(deployTester);
      const rnd = rndForScaled(scaled);
      const onChain = await tester.weightedColorBucket(rnd);
      const js = jsWeightedColorBucket(rnd);
      expect(Number(onChain)).to.equal(expectedColor);
      expect(js).to.equal(expectedColor);
      expect(Number(onChain)).to.equal(js);
    });
  }
});
