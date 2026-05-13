// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxAutoResolveBoundaries.test.js — Phase 275 Wave 2 TST-LBX-AR-02
//
// Boundary tests for the auto-resolve Bernoulli round-up at scaledPre ∈
// {0, 1, 99, 100, 101, 199, 200}. The hoisted Bernoulli math from Phase 275
// LBX-AR-01 / D-275-HOIST-01 is byte-identical between manual + auto-resolve
// branches, so the existing `LootboxBernoulliTester.bernoulliWhole(...)`
// helper is the load-bearing surface for these boundary assertions. Direct
// integration coverage of the auto-resolve callers lands in TST-LBX-AR-03
// (silent cold-bust regression) and TST-LBX-AR-05 (rem-byte snapshot).
//
// PLACEMENT: edge/ per D-275-TST-PLACEMENT-01 (boundary tests live in edge/).
//
// CROSS-CITES:
//   - D-275-HOIST-01 (Bernoulli math byte-identical between manual + auto-resolve)
//   - D-275-TST-PLACEMENT-01 (edge placement for boundary tests)
//   - TST-LBX-AR-02 per .planning/REQUIREMENTS.md

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
// test/stat/LootboxBernoulliEv.test.js).
function makeRng(seedHex) {
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

describe("LootboxAutoResolveBoundaries — Phase 275 Wave 2 TST-LBX-AR-02", function () {
  this.timeout(180_000);

  describe("Deterministic boundaries", function () {
    it("[0] scaledPre=0 → whole=0, roundedUp=false across N=2000 seeds (deterministic; frac=0)", async function () {
      const tester = await deployTester();
      const rng = makeRng("0x" + "ab0000".padStart(64, "0"));
      for (let i = 0; i < 2000; i++) {
        const seed = rng();
        const [whole, roundedUp] = await tester.bernoulliWhole(0, seed);
        if (whole !== 0n || roundedUp !== false) {
          expect.fail(`scaledPre=0 must be deterministic 0/false; got whole=${whole} roundedUp=${roundedUp} at i=${i}`);
        }
      }
    });

    it("[100] scaledPre=100 → whole=1, roundedUp=false across N=2000 seeds (deterministic; frac=0)", async function () {
      const tester = await deployTester();
      const rng = makeRng("0x" + "ab0100".padStart(64, "0"));
      for (let i = 0; i < 2000; i++) {
        const seed = rng();
        const [whole, roundedUp] = await tester.bernoulliWhole(100, seed);
        if (whole !== 1n || roundedUp !== false) {
          expect.fail(`scaledPre=100 must be deterministic 1/false; got whole=${whole} roundedUp=${roundedUp} at i=${i}`);
        }
      }
    });

    it("[200] scaledPre=200 → whole=2, roundedUp=false across N=2000 seeds (deterministic; frac=0)", async function () {
      const tester = await deployTester();
      const rng = makeRng("0x" + "ab0200".padStart(64, "0"));
      for (let i = 0; i < 2000; i++) {
        const seed = rng();
        const [whole, roundedUp] = await tester.bernoulliWhole(200, seed);
        if (whole !== 2n || roundedUp !== false) {
          expect.fail(`scaledPre=200 must be deterministic 2/false; got whole=${whole} roundedUp=${roundedUp} at i=${i}`);
        }
      }
    });
  });

  describe("Probabilistic boundaries (Bernoulli rate within ±2% of frac/100 at N=2000)", function () {
    // For each scaledPre with frac ∈ {1, 99}, the Bernoulli win-rate is frac/100.
    // The standard error of an empirical proportion at N=2000 is bounded by
    // sqrt(0.25/2000) ≈ 0.0112; 3-sigma is ~0.034. We use ±0.02 (~1.8-sigma)
    // tolerance — a wider net to keep this test rock-solid against CI flake.
    const PROB_CASES = [
      { scaledPre: 1, wholeFloor: 0n, fracOver100: 0.01 },
      { scaledPre: 99, wholeFloor: 0n, fracOver100: 0.99 },
      { scaledPre: 101, wholeFloor: 1n, fracOver100: 0.01 },
      { scaledPre: 199, wholeFloor: 1n, fracOver100: 0.99 },
    ];

    PROB_CASES.forEach(({ scaledPre, wholeFloor, fracOver100 }) => {
      it(`scaledPre=${scaledPre} → mean(roundedUp) within ±0.02 of ${fracOver100} at N=2000`, async function () {
        const tester = await deployTester();
        const rng = makeRng(
          "0x" +
            BigInt.asUintN(256, BigInt(0xab000000 + scaledPre))
              .toString(16)
              .padStart(64, "0")
        );
        let wins = 0;
        let sumWhole = 0n;
        for (let i = 0; i < 2000; i++) {
          const seed = rng();
          const [whole, roundedUp] = await tester.bernoulliWhole(scaledPre, seed);
          // When the Bernoulli predicate fires, whole = wholeFloor + 1; else whole = wholeFloor.
          if (roundedUp) wins++;
          // Per-call structural invariant: whole ∈ {wholeFloor, wholeFloor+1}.
          if (whole !== wholeFloor && whole !== wholeFloor + 1n) {
            expect.fail(`scaledPre=${scaledPre}: whole=${whole} not in {${wholeFloor}, ${wholeFloor + 1n}} at i=${i}`);
          }
          sumWhole += whole;
        }
        const winRate = wins / 2000;
        const winDeviation = Math.abs(winRate - fracOver100);
        expect(
          winDeviation <= 0.02,
          `scaledPre=${scaledPre}: |winRate - frac/100| = ${winDeviation.toFixed(4)} > 0.02 (winRate=${winRate.toFixed(4)})`
        ).to.equal(true);

        // EV-neutrality sanity: mean(whole)*100 within ±2 of scaledPre.
        const meanWhole = Number(sumWhole) / 2000;
        const meanScaled = meanWhole * 100;
        const evDeviation = Math.abs(meanScaled - scaledPre);
        expect(
          evDeviation <= 2.0,
          `scaledPre=${scaledPre}: |mean*100 - scaledPre| = ${evDeviation.toFixed(4)} > 2.0`
        ).to.equal(true);
      });
    });
  });
});
