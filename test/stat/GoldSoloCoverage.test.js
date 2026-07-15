// SPDX-License-Identifier: AGPL-3.0-only
// Phase 261 STAT-04 (gold coverage 100% on >=1-gold draws) + STAT-05 (multi-gold tie-break uniformity).
// Tester-driven loops — production bytes invoked per sample (D-03 oracle for SOLO-1 helper).
// Heavy MC — runs ONLY under `npm run test:stat`. Mirrors test/unit/JackpotSoloPicker.test.js
// SOLO-08(c) shape, scaled to 100K samples per goldCount + adds the explicit >=1-gold
// coverage record over a randomly-distributed goldCount sweep.
//
// ---------------------------------------------------------------------------
// Architecture:
//
//   STAT-04 uses jsWeightedColorBucket (replicated inline, drift-guarded by
//   Plan 01 D-03 boundary harness) to draw heavy-tail color bytes for each
//   of the 4 quadrants. The draw is conditioned on >=1 gold (color==7) by
//   resampling the entire colors[4] array on no-gold draws — this matches
//   the STAT-04 wording ("over 100K draws with >=1 gold ... returns a gold
//   quadrant in 100% of cases"). Each sample then calls the production
//   pickSoloQuadrant(traits, entropy) via JackpotSoloTester and asserts the
//   chosen quadrant carries color 7.
//
//   STAT-05 fixes goldCount ∈ {2, 3, 4} per case and asserts uniform
//   distribution over the gold quadrants via chi-squared at df = goldCount-1.
//   Same shape as test/unit/JackpotSoloPicker.test.js SOLO-08(c) but
//   PROMOTED to a STAT record with distinct seeds (`0xC010_0050 ^ goldCount`)
//   and 100K samples per goldCount.
// ---------------------------------------------------------------------------

import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";

async function deployTester() {
  const Tester = await hre.ethers.getContractFactory("JackpotSoloTester");
  const tester = await Tester.deploy();
  await tester.waitForDeployment();
  return { tester };
}

// Trait byte helpers — [QQ][CCC][SSS] format. Quadrant 2 bits, color 3 bits,
// symbol 3 bits. The helper inspects (traits[i] >> 3) & 7 for color tier.
function trait(quadrant, color, symbol) {
  return (BigInt(quadrant & 3) << 6n) | (BigInt(color & 7) << 3n) | BigInt(symbol & 7);
}

function traitsByColors(colors) {
  return [trait(0, colors[0], 0), trait(1, colors[1], 0), trait(2, colors[2], 0), trait(3, colors[3], 0)];
}

// Deterministic 256-bit PRNG: keccak256(seed || counter). Cryptographically
// uniform AND reproducible — fixed seed makes any failure exactly replayable.
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
// Drift guard: Plan 01 D-03 boundary harness asserts equality with the
// production tester at every threshold edge (scaled ∈ {0, 63, 64, ..., 254,
// 255}). If this replica drifts from the production thresholds, the boundary
// harness FAILS FIRST.
function jsWeightedColorBucket(rnd) {
  const scaled = (rnd * 256n) >> 32n;
  if (scaled < 64n) return 0;
  if (scaled < 128n) return 1;
  if (scaled < 192n) return 2;
  if (scaled < 224n) return 3;
  if (scaled < 240n) return 4;
  if (scaled < 248n) return 5;
  if (scaled < 254n) return 6;
  return 7;
}

// Critical chi-squared values at alpha = 0.05 keyed by df.
// STAT-05 uses df = goldCount - 1 ∈ {1, 2, 3} → {3.841, 5.991, 7.815}.
const CHI2_CRIT_05 = { 1: 3.841, 2: 5.991, 3: 7.815, 4: 9.488, 5: 11.070, 6: 12.592, 7: 14.067 };

// ===========================================================================
// STAT-04 — 100% gold coverage on >=1-gold draws.
// Over 100K random colors[4] arrays (heavy-tail sampled, conditioned on
// >=1 gold) and random entropies, pickSoloQuadrant always returns a
// quadrant whose trait carries color==7.
// ===========================================================================

describe("STAT-04 — 100% gold coverage on >=1-gold draws", function () {
  this.timeout(300000); // 5 min budget — 100K tester calls

  it("over 100K random >=1-gold trait arrays + random entropies, pickSoloQuadrant always returns a gold (color==7) quadrant", async function () {
    const { tester } = await loadFixture(deployTester);
    const SAMPLES = 100_000;
    // Distinct per-test seed (D-13 reproducibility). Hex literal 0xC010_0004.
    const rng = makeRng(0xC010_0004);

    let goldDraws = 0;
    let goldCountHistogram = [0, 0, 0, 0, 0]; // index = goldCount ∈ {1,2,3,4}; slot 0 unused

    for (let i = 0; i < SAMPLES; i++) {
      // One rng() call yields the entropy; 4 fresh rng() calls yield colors.
      // Bits used are non-overlapping across the same 256-bit word for color
      // and entropy (we pull separate words), so there is no cross-coupling.
      const entropy = rng();

      // Sample 4 colors via heavy-tail. Resample the whole array if zero gold —
      // the STAT-04 wording conditions on >=1 gold, not on a Bernoulli(1/128)
      // marginal hit per quadrant, so resampling preserves the conditional
      // distribution unbiased.
      let colors;
      while (true) {
        const w = rng();
        colors = [
          jsWeightedColorBucket(w & 0xFFFFFFFFn),
          jsWeightedColorBucket((w >> 32n) & 0xFFFFFFFFn),
          jsWeightedColorBucket((w >> 64n) & 0xFFFFFFFFn),
          jsWeightedColorBucket((w >> 96n) & 0xFFFFFFFFn),
        ];
        if (colors.includes(7)) break;
      }
      const goldCount = colors.filter((c) => c === 7).length;
      goldCountHistogram[goldCount]++;
      goldDraws++;

      const traits = traitsByColors(colors);
      const result = await tester.pickSoloQuadrant(traits, entropy);
      const chosenQuadrant = Number(result);
      const chosenColor = Number((traits[chosenQuadrant] >> 3n) & 7n);

      if (chosenColor !== 7) {
        throw new Error(
          `STAT-04 failure at i=${i}: colors=[${colors.join(",")}] ` +
          `entropy=0x${entropy.toString(16)} chosenQuadrant=${chosenQuadrant} ` +
          `chosenColor=${chosenColor}`
        );
      }
    }

    // Pass criterion is binary: 100% of >=1-gold draws return a gold quadrant.
    // The loop throws on the first failure, so reaching this assertion means
    // all SAMPLES draws hit a gold quadrant.
    expect(goldDraws).to.equal(SAMPLES);
    console.log(
      `  STAT-04: ${SAMPLES} >=1-gold draws, gold-quadrant hit rate 100% ` +
      `(goldCount histogram: 1→${goldCountHistogram[1]} 2→${goldCountHistogram[2]} ` +
      `3→${goldCountHistogram[3]} 4→${goldCountHistogram[4]})`
    );
  });
});

// ===========================================================================
// STAT-05 — tie-break uniformity over 100K samples per goldCount ∈ {2, 3, 4}.
// For each goldCount, fix a colors[4] array placing gold in known positions
// and sample 100K random entropies. Bucket the returned quadrant indices
// by their position in goldQuads. Chi-squared at df = goldCount - 1 vs
// uniform expected = SAMPLES / goldCount.
// ===========================================================================

describe("STAT-05 — tie-break uniformity over 100K samples per goldCount ∈ {2, 3, 4}", function () {
  this.timeout(300000); // 5 min budget for the 3 sweeps in series

  // Fixtures — colors[4] with the listed quadrants carrying color 7.
  const cases = [
    { goldCount: 2, colors: [7, 0, 7, 0], goldQuads: [0, 2] },
    { goldCount: 3, colors: [7, 7, 0, 7], goldQuads: [0, 1, 3] },
    { goldCount: 4, colors: [7, 7, 7, 7], goldQuads: [0, 1, 2, 3] },
  ];

  for (const { goldCount, colors, goldQuads } of cases) {
    it(`distributes uniformly across ${goldCount} gold quadrants over 100K samples`, async function () {
      const { tester } = await loadFixture(deployTester);
      const traits = traitsByColors(colors);
      const SAMPLES = 100_000;
      const counts = new Array(goldCount).fill(0);
      // Distinct per-goldCount seed (D-13 reproducibility).
      const rng = makeRng(0xC010_0050 ^ goldCount);

      for (let i = 0; i < SAMPLES; i++) {
        const entropy = rng();
        const result = await tester.pickSoloQuadrant(traits, entropy);
        const idx = goldQuads.indexOf(Number(result));
        if (idx < 0) {
          throw new Error(
            `STAT-05 (goldCount=${goldCount}) returned non-gold quadrant ${result} ` +
            `for entropy=0x${entropy.toString(16)} colors=[${colors.join(",")}]`
          );
        }
        counts[idx]++;
      }

      // Chi-squared vs uniform.
      const expected = SAMPLES / goldCount;
      let chi2 = 0;
      for (const c of counts) {
        chi2 += ((c - expected) ** 2) / expected;
      }
      const df = goldCount - 1;
      const crit = CHI2_CRIT_05[df];
      console.log(
        `  STAT-05 goldCount=${goldCount}: chi²=${chi2.toFixed(3)} (crit=${crit} df=${df}) ` +
        `counts=[${counts.join(",")}]`
      );
      expect(
        chi2,
        `STAT-05 chi²=${chi2.toFixed(3)} >= ${crit} (df=${df}, goldCount=${goldCount}, counts=[${counts.join(",")}])`,
      ).to.be.lessThan(crit);
    });
  }
});
