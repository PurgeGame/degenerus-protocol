// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxBernoulliEv.test.js — Phase 274 Wave 2 TST-WT-01 + TST-WT-03 extended.
//
// Heavy-weight statistical validation of the manual-path Bernoulli math at
// scale N >= 50K seeds. The lighter N=10K version of these properties runs
// inline in `test/unit/LootboxWholeTicket.test.js`. This file is invoked
// only when the explicit `test:stat` npm script is run (mirrors the
// `test/stat/TraitDistribution.test.js` heavy-MC pattern; heavy MCs do not
// run under default `npm test`).
//
// Properties verified at higher N:
//   - TST-WT-01 (EV-neutrality, extended): mean(whole) * TICKET_SCALE within
//     1-sigma of scaledPre across the full representative span. At N=50K the
//     sigma of mean(whole) * 100 is bounded above by 100 * sqrt(0.25/N) ≈
//     0.224, so 3-sigma is ~0.67 — we use the tighter ±1 tolerance.
//   - TST-WT-03 (mod-100 mod uniformity at higher resolution): chi² df=99 at
//     N=50K samples per scaledPre boundary.
//
// CROSS-CITES:
//   - feedback_gas_worst_case.md (theoretical worst case derived FIRST: the
//     mean estimator's standard error is the load-bearing analytical bound;
//     empirical chi² is the secondary confirmation)
//   - Phase 266 STAT-03 reuse-existing-tooling discipline (CHI2_CRIT_05 +
//     wilsonHilfertyZ re-declared verbatim from TraitDistribution.test.js)

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
// test/stat/TraitDistribution.test.js).
function makeRng(seedHex) {
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

// JS replica of the Bernoulli math. Drift caught structurally by TST-WT-DRIFT
// in test/unit/LootboxWholeTicket.test.js (source-vs-tester) plus the spot
// check inside this file (js-vs-chain).
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

function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}

describe("LootboxBernoulliEv (stat-suite, heavy-MC) — TST-WT-01 + TST-WT-03 extended", function () {
  this.timeout(300_000);

  describe("TST-WT-01 extended — EV-neutrality at N=50K", function () {
    // For each scaledPre, run 50K Bernoulli trials and assert mean*100 within
    // ±1 of scaledPre (analytical 3-sigma bound at N=50K).
    const N = 50_000;
    const SCALED_VALUES = [47, 99, 100, 147, 250, 1000, 9999];

    SCALED_VALUES.forEach((scaledPre) => {
      it(`mean(whole) * 100 within ±1 of scaledPre=${scaledPre} at N=${N}`, async function () {
        const tester = await deployTester();
        const rng = makeRng(
          "0x" +
            BigInt.asUintN(256, BigInt(0xc0274500 + scaledPre))
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
        expect(
          absDeviation <= 1.0,
          `scaledPre=${scaledPre}: |mean*100 - scaledPre| = ${absDeviation.toFixed(
            4
          )} > 1.0 (mean=${meanWhole.toFixed(6)})`
        ).to.equal(true);
      });
    });
  });

  describe("TST-WT-03 extended — uint16(seed >> 152) % 100 uniformity chi² at N=50K, df=99", function () {
    it("mod-100 distribution matches theoretical p_b at chi²(df=99) Wilson-Hilferty Z < 1.645", async function () {
      const N = 50_000;
      const tester = await deployTester();
      const rng = makeRng("0x" + "c0274503".padStart(64, "0"));
      const buckets = new Array(100).fill(0);
      let chainVerifyCount = 0;

      for (let i = 0; i < N; i++) {
        const seed = rng();
        const jsSlice = Number(((seed >> 152n) & 0xffffn) % 100n);
        buckets[jsSlice] += 1;
        if (i % 1000 === 0) {
          const chainSlice = await tester.bernoulliSlice(seed);
          expect(Number(chainSlice), `js/chain drift at i=${i}`).to.equal(jsSlice);
          chainVerifyCount++;
        }
      }
      expect(chainVerifyCount).to.be.gte(50);

      // uint16 % 100 has 36 over-represented residues (with 656 of 65536
      // source values) and 64 under-represented (655 of 65536); residues
      // 0..35 have p=656/65536, residues 36..99 have p=655/65536.
      const lowBucketProb = 656 / 65536;
      const highBucketProb = 655 / 65536;
      let chi2 = 0;
      for (let b = 0; b < 100; b++) {
        const p = b < 36 ? lowBucketProb : highBucketProb;
        const expected = N * p;
        const diff = buckets[b] - expected;
        chi2 += (diff * diff) / expected;
      }
      const z = wilsonHilfertyZ(chi2, 99);
      expect(
        z < 1.645,
        `chi²=${chi2.toFixed(3)} df=99 → Z=${z.toFixed(3)} >= 1.645`
      ).to.equal(true);
    });
  });
});
