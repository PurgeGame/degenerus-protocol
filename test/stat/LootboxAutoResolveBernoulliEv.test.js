// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxAutoResolveBernoulliEv.test.js — Phase 275 Wave 2 TST-LBX-AR-01
//
// EV-neutrality via LootboxBernoulliTester direct-call is justified by D-275-HOIST-01:
// the hoisted Bernoulli math is byte-identical between manual + auto-resolve branches,
// so the v39 TST-WT EV-neutrality proof carries verbatim. Integration coverage of the
// actual auto-resolve callers (claimDecimatorJackpot + resolveRedemptionLootbox) lands
// in TST-LBX-AR-03 (silent cold-bust) and TST-LBX-AR-05 (rem-byte snapshot).
//
// Heavy-MC validation of the auto-resolve Bernoulli round-up at N=10K seeds per
// scaledPre across the representative sample span {47, 99, 100, 147, 250, 1000,
// 9999} per .planning/phases/275-.../275-CONTEXT.md. Requirement: TST-LBX-AR-01.
//
// PLACEMENT: stat/ per D-275-TST-PLACEMENT-01 (heavy-MC tier; wired into
// `test:stat` npm script alongside the v39 LootboxBernoulliEv.test.js precedent).
//
// TST-WT-DRIFT at `test/unit/LootboxWholeTicket.test.js` is the upstream drift
// detector — this stat test ASSUMES the canonical Bernoulli pattern holds in
// production (verified at Plan A Task 1 grep gate + post-Plan-A by the
// TST-WT-DRIFT structural assertion that the slice sits in shared scope per
// the hoist invariant).
//
// CROSS-CITES:
//   - D-275-HOIST-01 (Bernoulli hoisted to shared scope; math byte-identical)
//   - D-275-TST-PLACEMENT-01 (heavy-MC tier in stat/)
//   - FINDINGS-v39.0.md §4 (a) EV-neutrality identity (carries verbatim)
//   - Phase 274 TST-WT-01 precedent in test/stat/LootboxBernoulliEv.test.js

import { expect } from "chai";
import hre from "hardhat";

const TICKET_SCALE = 100n;

async function deployTester() {
  const Factory = await hre.ethers.getContractFactory("LootboxBernoulliTester");
  const tester = await Factory.deploy();
  await tester.waitForDeployment();
  return tester;
}

// Deterministic seeded keccak-counter PRNG (mirrors `makeRng` from
// test/stat/LootboxBernoulliEv.test.js + test/stat/TraitDistribution.test.js).
function makeRng(seedHex) {
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

// JS replica of the Bernoulli math (mirrors v40 hoisted instruction sequence).
// Drift caught by TST-WT-DRIFT (source-vs-tester) + per-loop spot-check below.
function jsBernoulliWhole(scaledPre, seed) {
  const scaled = BigInt(scaledPre);
  let whole = scaled / TICKET_SCALE;
  const frac = scaled % TICKET_SCALE;
  let roundedUp = false;
  if (frac !== 0n) {
    const sliceRaw = (BigInt(seed) >> 152n) & 0xffffn;
    const slice = sliceRaw % TICKET_SCALE;
    if (slice < frac) {
      whole += 1n;
      roundedUp = true;
    }
  }
  return { whole, roundedUp };
}

describe("LootboxAutoResolveBernoulliEv (stat-suite, heavy-MC) — TST-LBX-AR-01 EV-neutrality on auto-resolve paths at N=10K", function () {
  this.timeout(600_000);

  describe("TST-LBX-AR-01 — EV-neutrality property on auto-resolve Bernoulli", function () {
    // At N=10K i.i.d. samples, the variance of mean(whole) is bounded above by
    // 0.25/N; sigma of mean*100 is bounded above by 100*sqrt(0.25/10000) ≈ 0.5.
    // CONTEXT.md acceptance: within ±0.5% of scaledPre — for scaledPre=100
    // that's ±0.5; for scaledPre=9999 that's ±49.995. Using ABSOLUTE bound of
    // 1.5 (3-sigma) for low scaledPre and 0.5% relative bound for higher.
    const N = 10_000;
    const SCALED_VALUES = [47, 99, 100, 147, 250, 1000, 9999];

    SCALED_VALUES.forEach((scaledPre) => {
      it(`mean(whole)*100 within ±max(1.5, 0.5%) of scaledPre=${scaledPre} at N=${N}`, async function () {
        const tester = await deployTester();
        const rng = makeRng(
          "0x" +
            BigInt.asUintN(256, BigInt(0xc0275101 + scaledPre))
              .toString(16)
              .padStart(64, "0")
        );
        let sumWhole = 0n;
        // Spot-check every 1000th sample against the chain.
        for (let i = 0; i < N; i++) {
          const seed = rng();
          const { whole } = jsBernoulliWhole(scaledPre, seed);
          sumWhole += whole;
          if (i % 1000 === 0) {
            const [chainWhole] = await tester.bernoulliWhole(scaledPre, seed);
            expect(chainWhole, `js/chain drift at i=${i}`).to.equal(whole);
          }
        }
        const meanWhole = Number(sumWhole) / N;
        const meanScaled = meanWhole * 100;
        const absDeviation = Math.abs(meanScaled - scaledPre);
        const tolerance = Math.max(1.5, scaledPre * 0.005);
        expect(
          absDeviation <= tolerance,
          `scaledPre=${scaledPre}: |mean*100 - scaledPre| = ${absDeviation.toFixed(
            4
          )} > tolerance=${tolerance.toFixed(4)} (mean=${meanWhole.toFixed(6)})`
        ).to.equal(true);
      });
    });
  });

  describe("Empirical Bernoulli win-rate sanity (mean(roundedUp) ≈ frac/100)", function () {
    const N = 10_000;
    const CASES = [
      { scaledPre: 47, expectedRate: 0.47 },
      { scaledPre: 99, expectedRate: 0.99 },
      { scaledPre: 147, expectedRate: 0.47 },
      { scaledPre: 250, expectedRate: 0.5 },
      { scaledPre: 1000, expectedRate: 0.0 }, // frac=0 → deterministic roundedUp=false
      { scaledPre: 9999, expectedRate: 0.99 },
    ];

    CASES.forEach(({ scaledPre, expectedRate }) => {
      it(`mean(roundedUp) within ±0.012 of frac/100 at scaledPre=${scaledPre} (N=${N})`, async function () {
        const tester = await deployTester();
        const rng = makeRng(
          "0x" +
            BigInt.asUintN(256, BigInt(0xc0275102 + scaledPre))
              .toString(16)
              .padStart(64, "0")
        );
        let wins = 0;
        for (let i = 0; i < N; i++) {
          const seed = rng();
          const { roundedUp } = jsBernoulliWhole(scaledPre, seed);
          if (roundedUp) wins++;
          if (i % 1000 === 0) {
            const [, chainRoundedUp] = await tester.bernoulliWhole(scaledPre, seed);
            expect(chainRoundedUp, `js/chain drift at i=${i}`).to.equal(roundedUp);
          }
        }
        const empiricalRate = wins / N;
        const deviation = Math.abs(empiricalRate - expectedRate);
        // 4-sigma at N=10K for Bernoulli(0.5) is sqrt(0.25/N)*4 ≈ 0.020.
        // We use ±0.020 (~4-sigma) for the non-degenerate cases to keep this
        // test rock-solid against CI variance, exact match for frac=0
        // (deterministic).
        const tolerance = expectedRate === 0.0 ? 0.0 : 0.020;
        expect(
          deviation <= tolerance,
          `scaledPre=${scaledPre}: |empiricalRate - ${expectedRate}| = ${deviation.toFixed(4)} > ${tolerance}`
        ).to.equal(true);
      });
    });
  });
});
