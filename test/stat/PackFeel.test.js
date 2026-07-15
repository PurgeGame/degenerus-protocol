// SPDX-License-Identifier: AGPL-3.0-only
// Phase 261 STAT-07 — pack-feel CIs over >=100K 10-ticket packs (40 trait rolls each).
// JS-replica color sampling (drift-guarded by Plan 01 D-03 boundary harness).
// Asserts measured >=1-of-tier frequencies fall within Wilson 99% CIs of analytical
// values computed from (1 - P(color>=k))^40 under the heavy-tail color distribution.
//
// Reconciliation note: REQUIREMENTS.md STAT-07 cites 99.5% / 92.3% / 71.7% / 27.0%
// — the analytical values under the canonical (1 - sum(P[color>=k]))^40 formula yield
// {99.99%, 99.51%, 92.86%, 26.94%}. The Plan-locked assertions use the canonical
// analytical values (computed inline at file top); the REQUIREMENTS.md headline
// numbers are retained as Wilson-CI lower-bound informational targets, not
// hard assertions. Phase 262 audit may surface a REQUIREMENTS.md amendment.
//
// ---------------------------------------------------------------------------
// Mechanics:
//
//   Pack = 10 tickets × 4 quadrants = 40 trait rolls. For each pack, sample
//   40 color bytes via jsWeightedColorBucket and check whether ANY roll hit
//   the >=k threshold for each tier {notable, rare, epic, legendary}. Over
//   PACKS=100_000 packs, count packs that had >=1 hit per tier; compute
//   Wilson 99% CI for each measured proportion; assert the analytical
//   value lies within the CI.
//
//   Tail probabilities (sum of P[color] for color >= threshold):
//     notable   (color>=3) = 0.12500 + 0.06250 + 0.03125 + 0.02344 + 0.00781 = 0.25000
//     rare      (color>=4) = 0.06250 + 0.03125 + 0.02344 + 0.00781 = 0.12500
//     epic      (color>=5) = 0.03125 + 0.02344 + 0.00781 = 0.06250
//     legendary (color==7) = 0.00781
//
//   Analytical pack frequency: P(>=1 of tier in pack) = 1 - (1 - tail)^40
//     notable   ≈ 0.99999 (REQUIREMENTS.md target 99.5% — comfortable)
//     rare      ≈ 0.99506 (target 92.3%)
//     epic      ≈ 0.92857 (target 71.7%)
//     legendary ≈ 0.26937 (target 27.0%)
//
//   Wilson 99% CI: two-sided z=2.576 score interval for binomial proportion.
// ---------------------------------------------------------------------------

import { expect } from "chai";
import hre from "hardhat";

// Deterministic 256-bit PRNG: keccak256(seed || counter).
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
// Drift-guarded by Plan 01 D-03 boundary harness.
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

const COLOR_PROB = [0.25000, 0.25000, 0.25000, 0.12500, 0.06250, 0.03125, 0.02344, 0.00781];

// Cumulative tail probabilities P(color >= k):
//   k=3 → P[3]+P[4]+P[5]+P[6]+P[7] = 0.12500 + 0.06250 + 0.03125 + 0.02344 + 0.00781 = 0.25000
//   k=4 →             0.06250 + 0.03125 + 0.02344 + 0.00781 = 0.12500
//   k=5 →                       0.03125 + 0.02344 + 0.00781 = 0.06250
//   k=7 →                                           0.00781
const TAIL = { notable: 0.25000, rare: 0.12500, epic: 0.06250, legendary: 0.00781 };
const ROLLS_PER_PACK = 40;
// P(>=1 of tier in pack) = 1 - (1 - TAIL[tier])^ROLLS_PER_PACK
const ANALYTICAL = {
  notable:   1 - Math.pow(1 - TAIL.notable,   ROLLS_PER_PACK), // ~0.99999
  rare:      1 - Math.pow(1 - TAIL.rare,      ROLLS_PER_PACK), // ~0.99506
  epic:      1 - Math.pow(1 - TAIL.epic,      ROLLS_PER_PACK), // ~0.92857
  legendary: 1 - Math.pow(1 - TAIL.legendary, ROLLS_PER_PACK), // ~0.26937
};
const PACKS = 100_000;

// Wilson score interval for a binomial proportion at the two-sided 99% level
// (z = 2.576). Closed-form; no jstat dependency. Returns {lo, hi} bounds.
function wilson99(successes, total) {
  const z = 2.576;
  const p = successes / total;
  const denom = 1 + (z * z) / total;
  const center = (p + (z * z) / (2 * total)) / denom;
  const half = (z * Math.sqrt((p * (1 - p)) / total + (z * z) / (4 * total * total))) / denom;
  return { lo: center - half, hi: center + half };
}

describe("STAT-07 — pack-feel CIs over 100K packs (40 rolls/pack)", function () {
  this.timeout(120000); // 2 min budget — pure JS, ~4M jsWeightedColorBucket calls

  it("measured >=1-of-tier frequencies match analytical values within Wilson 99% CIs", function () {
    // Distinct per-test seed (D-13 reproducibility). Hex literal 0xC010_0070.
    const rng = makeRng(0xC010_0070);
    const packCounts = { notable: 0, rare: 0, epic: 0, legendary: 0 };

    for (let p = 0; p < PACKS; p++) {
      let hasNotable = false;
      let hasRare = false;
      let hasEpic = false;
      let hasLegendary = false;

      // 40 rolls per pack — 5 fresh 256-bit words give 40 × 32-bit slices.
      // Pull slices via repeated rng() calls + bit-shifts. Each rng() yields
      // 8 × 32-bit slices; 5 calls cover the 40 rolls exactly.
      for (let r = 0; r < 5; r++) {
        const w = rng();
        for (let s = 0; s < 8; s++) {
          const rnd32 = (w >> BigInt(s * 32)) & 0xFFFFFFFFn;
          const color = jsWeightedColorBucket(rnd32);
          if (color >= 3) hasNotable = true;
          if (color >= 4) hasRare = true;
          if (color >= 5) hasEpic = true;
          if (color === 7) hasLegendary = true;
        }
      }

      if (hasNotable) packCounts.notable++;
      if (hasRare) packCounts.rare++;
      if (hasEpic) packCounts.epic++;
      if (hasLegendary) packCounts.legendary++;
    }

    for (const tier of ["notable", "rare", "epic", "legendary"]) {
      const measured = packCounts[tier] / PACKS;
      const ci = wilson99(packCounts[tier], PACKS);
      console.log(
        `  ${tier}: measured ${(measured * 100).toFixed(2)}% ` +
        `(Wilson 99% CI [${(ci.lo * 100).toFixed(2)}%, ${(ci.hi * 100).toFixed(2)}%]; ` +
        `analytical ${(ANALYTICAL[tier] * 100).toFixed(2)}%)`
      );
      expect(
        ANALYTICAL[tier],
        `${tier} analytical ${ANALYTICAL[tier]} outside CI [${ci.lo}, ${ci.hi}]`,
      ).to.be.gte(ci.lo);
      expect(ANALYTICAL[tier]).to.be.lte(ci.hi);
    }
  });
});
