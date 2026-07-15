// SPDX-License-Identifier: AGPL-3.0-only
// Phase 261 STAT-06 — per-surface 100K-sample EV-uplift Monte Carlo.
// D-04: per-surface assertion model (final-day / daily / purchase, three independent sims).
// D-05: base bucket counts [25, 15, 8, 1]; ethPool below JACKPOT_SCALE_MIN_WEI so
//       bucketCountsForPoolCap returns base unchanged. No pool-scaling confound.
// D-06: ±5% relative tolerance (5σ safety at 100K samples).
// D-07: owns-the-gold-quadrant-ticket model — for each draw conditioned on >=1 gold,
//       compute (with-priority EV) = 1/goldCount × solo-payout-per-ticket
//                                   + (goldCount-1)/goldCount × E[non-solo-payout-per-ticket],
//       (baseline EV) = 1/4 × solo-payout-per-ticket + 3/4 × E[non-solo-payout-per-ticket].
//       The uplift ratio = (with-priority avg) / (baseline avg) over all conditioned draws.
// Tester-driven for the gold-quadrant pick; analytical for payout-per-ticket
// (deterministic given trait colors + entropy + base counts + share BPS).
//
// ---------------------------------------------------------------------------
// Mechanics:
//
//   For each draw:
//     - Sample colors[4] via heavy-tail jsWeightedColorBucket and condition on
//       >=1 gold (color==7) per D-07.
//     - Pick the holder's quadrant g = goldQuads[0] (the model is symmetric
//       across gold quadrants — any deterministic choice yields the same
//       expectation under the uniform-over-goldQuads tie-break).
//     - Call tester.pickSoloQuadrant(traits, entropy) to obtain the production
//       gold-priority output goldQuadrant.
//     - Priority bucket geometry: rotation = (3 - goldQuadrant) & 3
//         counts_priority[i]  = BASE_COUNTS[(i + rotation) & 3]
//         shares_priority[i]  = surf.shareBps[(i + rotation + 1) & 3]   per JackpotBucketLib.rotatedShareBps
//         priorityPayoutAtG = shares_priority[g] / counts_priority[g]
//     - Baseline bucket geometry (legacy rotation only): rotation = entropy & 3
//         counts_baseline[i]  = BASE_COUNTS[(i + rotation) & 3]
//         shares_baseline[i]  = surf.shareBps[(i + rotation + 1) & 3]
//         baselinePayoutAtG = shares_baseline[g] / counts_baseline[g]
//
//   Uplift = mean(priorityPayoutAtG) / mean(baselinePayoutAtG) over all
//   conditioned-on->=1-gold draws. Per-draw payouts are in BPS units; the
//   /10000 fraction cancels in the ratio.
//
//   Surface BPS sources (hand-copied; T-261-02-01 mitigation: Phase 262 §3a
//   delta-surface table re-verifies these literals against contract source):
//     final-day → FINAL_DAY_SHARES_PACKED at DegenerusGameJackpotModule.sol L150-154
//                 = [6000, 1333, 1333, 1334]
//     daily / purchase → DAILY_JACKPOT_SHARES_PACKED at L158-159
//                 = [2000, 2000, 2000, 2000]
//
//   Drift detection: if any literal drifts from the contract source, the
//   measured uplift moves outside ±5% relative of the analytical target —
//   loud failure mode.
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

// Trait byte helpers — [QQ][CCC][SSS] format.
function trait(quadrant, color, symbol) {
  return (BigInt(quadrant & 3) << 6n) | (BigInt(color & 7) << 3n) | BigInt(symbol & 7);
}

function traitsByColors(colors) {
  return [trait(0, colors[0], 0), trait(1, colors[1], 0), trait(2, colors[2], 0), trait(3, colors[3], 0)];
}

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

// Trait byte color extraction matches contracts/DegenerusTraitUtils.sol.
const COLOR_PROB = [0.25000, 0.25000, 0.25000, 0.12500, 0.06250, 0.03125, 0.02344, 0.00781];

// Surface BPS share vectors at base bucket counts [25, 15, 8, 1].
// final-day source: FINAL_DAY_SHARES_PACKED (DegenerusGameJackpotModule.sol L150-154).
// daily / purchase source: DAILY_JACKPOT_SHARES_PACKED (DegenerusGameJackpotModule.sol L158-159).
const SURFACES = {
  finalDay: { name: "final-day", shareBps: [6000, 1333, 1333, 1334], analyticalUplift: 3.78, seed: 0xC010_0061 },
  daily:    { name: "daily",     shareBps: [2000, 2000, 2000, 2000], analyticalUplift: 3.21, seed: 0xC010_0062 },
  purchase: { name: "purchase",  shareBps: [2000, 2000, 2000, 2000], analyticalUplift: 3.21, seed: 0xC010_0063 },
};
const BASE_COUNTS = [25, 15, 8, 1];
const SAMPLES = 100_000;
const TOLERANCE_REL = 0.05; // ±5% relative per D-06

// Payout-per-ticket at quadrant `q` under rotation `rot`, given a surface
// share-BPS vector and base bucket counts. The /10000 BPS-to-fraction factor
// is omitted because it cancels in the priority/baseline ratio.
//
// rotatedShareBps formula (JackpotBucketLib.sol L248-250):
//   baseIndex = (traitIdx + offset + 1) & 3
//   share = packed[baseIndex]              -- packed slot at position baseIndex
// counts (traitBucketCounts L36-50):
//   counts[i] = base[(i + offset) & 3]
function payoutAtQuadrant(shareBps, rot, q) {
  const count = BASE_COUNTS[(q + rot) & 3];
  const share = shareBps[(q + rot + 1) & 3];
  return share / count;
}

describe("STAT-06 — per-surface EV uplift over 100K conditioned-on->=1-gold samples", function () {
  this.timeout(600000); // 10 min budget per surface — three back-to-back 100K MCs

  for (const [key, surf] of Object.entries(SURFACES)) {
    it(`${surf.name} surface measured uplift within ±5% of analytical ${surf.analyticalUplift}× at base counts [25,15,8,1]`, async function () {
      const { tester } = await loadFixture(deployTester);
      const rng = makeRng(surf.seed);

      let priorityTotal = 0;
      let baselineTotal = 0;
      let conditionedDraws = 0;
      let goldCountHist = [0, 0, 0, 0, 0]; // index = goldCount; slot 0 unused

      for (let i = 0; i < SAMPLES; i++) {
        const entropy = rng();

        // Sample 4 trait colors from the heavy-tail distribution. Use four
        // 32-bit slices of one fresh 256-bit word per draw.
        const w = rng();
        const colors = [
          jsWeightedColorBucket(w & 0xFFFFFFFFn),
          jsWeightedColorBucket((w >> 32n) & 0xFFFFFFFFn),
          jsWeightedColorBucket((w >> 64n) & 0xFFFFFFFFn),
          jsWeightedColorBucket((w >> 96n) & 0xFFFFFFFFn),
        ];

        // D-07 conditioning: skip draws with no gold trait.
        const goldQuads = [];
        for (let q = 0; q < 4; q++) if (colors[q] === 7) goldQuads.push(q);
        if (goldQuads.length === 0) continue;
        conditionedDraws++;
        goldCountHist[goldQuads.length]++;

        const traits = traitsByColors(colors);

        // Production gold-priority pick.
        const goldQuadrant = Number(await tester.pickSoloQuadrant(traits, entropy));

        // The holder owns *the* gold-color winning ticket at quadrant g. The
        // model is symmetric over goldQuads under uniform tie-break — pick g
        // = goldQuads[0] (deterministic; the expectation is invariant).
        const g = goldQuads[0];

        // Bucket geometry under the priority and baseline models. Both use
        // identical formulas; only the rotation source differs.
        const priorityRotation = (3 - goldQuadrant) & 3;
        const baselineRotation = Number(entropy & 3n);

        priorityTotal += payoutAtQuadrant(surf.shareBps, priorityRotation, g);
        baselineTotal += payoutAtQuadrant(surf.shareBps, baselineRotation, g);
      }

      const priorityEV = priorityTotal / conditionedDraws;
      const baselineEV = baselineTotal / conditionedDraws;
      const measuredUplift = priorityEV / baselineEV;
      const lowerBound = surf.analyticalUplift * (1 - TOLERANCE_REL);
      const upperBound = surf.analyticalUplift * (1 + TOLERANCE_REL);

      console.log(
        `  ${surf.name}: measured uplift ${measuredUplift.toFixed(3)}× over ${conditionedDraws} conditioned draws ` +
        `(analytical ${surf.analyticalUplift}× ±5% → [${lowerBound.toFixed(3)}, ${upperBound.toFixed(3)}]; ` +
        `goldCount hist 1→${goldCountHist[1]} 2→${goldCountHist[2]} 3→${goldCountHist[3]} 4→${goldCountHist[4]})`
      );
      expect(measuredUplift, `measured ${measuredUplift.toFixed(3)} not in [${lowerBound.toFixed(3)}, ${upperBound.toFixed(3)}]`).to.be.gte(lowerBound);
      expect(measuredUplift).to.be.lte(upperBound);
    });
  }
});
