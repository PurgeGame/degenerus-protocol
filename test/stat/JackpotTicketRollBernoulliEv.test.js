// SPDX-License-Identifier: AGPL-3.0-only
//
// JackpotTicketRollBernoulliEv.test.js — EV-neutrality stat test for the jackpot ticket-roll Bernoulli
//
// EV-neutrality of the jackpot ticket-roll Bernoulli whole-ticket collapse.
//
// `DegenerusGameJackpotModule._jackpotTicketRoll` has an inline Bernoulli round-up: the scaled ticket count
// `quantityScaled` is collapsed to a whole-ticket count `whole`, with the
// fractional part `frac` rounding up with probability `frac/TICKET_SCALE`
// using bits[96..127] of the per-roll `entropy` word. EV-neutrality is the
// identity `E[whole] * TICKET_SCALE == scaledTickets` (the same identity as the
// lootbox whole-ticket EV-neutrality); the jackpot inline Bernoulli is the same
// Bernoulli(frac/100) round-up, so the proof carries to this surface unchanged.
//
// EV-neutrality via `JackpotBernoulliTester.bernoulliWhole` direct-call is
// justified because the inline Bernoulli math in `_jackpotTicketRoll`
// is byte-arithmetically identical to the tester (the tester substitutes `seed`
// for the production `entropy` local; the predicate and the `>> 96` slice
// offset are otherwise identical). That byte-identity is enforced by the
// tester-vs-source drift gate in this same file:
// if production drifts from the tester, the drift gate fails BEFORE the stat
// tests run. Integration coverage of the actual `_jackpotTicketRoll` caller
// path is covered by the silent cold-bust source-structural proof.
//
// Heavy-MC validation at N=10K seeds per scaledTickets across the representative
// sample span {47, 99, 100, 147, 250, 1000, 9999} (≥10K sample size).
//
// PLACEMENT: stat/ (heavy-MC tier; wired into the `test:stat` npm script alongside
// test/stat/LootboxAutoResolveBernoulliEv.test.js).
//
// Entropy notes: the per-roll entropy word is evolved via EntropyLib.hash2(entropy, entropy)
// on _jackpotTicketRoll entry, so it is unknown to the winner at jackpot-resolution
// VRF-commitment time, and the winner cannot mutate it once _jackpotTicketRoll is entered
// (bits[96..127] is derived from the already-evolved word).

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";

const TICKET_SCALE = 100n;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotDrawModule.sol"
);
const TESTER_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/test/JackpotBernoulliTester.sol"
);

async function deployTester() {
  const Factory = await hre.ethers.getContractFactory("JackpotBernoulliTester");
  const tester = await Factory.deploy();
  await tester.waitForDeployment();
  return tester;
}

// Deterministic seeded keccak-counter PRNG (mirrors `makeRng` from
// test/stat/LootboxAutoResolveBernoulliEv.test.js + test/stat/TraitDistribution.test.js).
function makeRng(seedHex) {
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

// JS replica of the jackpot inline Bernoulli math (mirrors the _jackpotTicketRoll
// instruction sequence — slice offset >> 96). Drift caught by the source-vs-tester
// gate below + the per-loop js/chain spot-check.
function jsBernoulliWhole(scaledTickets, seed) {
  const scaled = BigInt(scaledTickets);
  let whole = scaled / TICKET_SCALE;
  const frac = scaled % TICKET_SCALE;
  let roundedUp = false;
  if (frac !== 0n) {
    const sliceRaw = (BigInt(seed) >> 96n) & 0xffffffffn;
    const slice = sliceRaw % TICKET_SCALE;
    if (slice < frac) {
      whole += 1n;
      roundedUp = true;
    }
  }
  return { whole, roundedUp };
}

describe("JackpotTicketRollBernoulliEv (stat-suite, heavy-MC) — EV-neutrality on the jackpot ticket-roll Bernoulli at N=10K", function () {
  this.timeout(600_000);

  // Tester-vs-source drift gate. Runs first — if the
  // production inline predicate drifts from the JackpotBernoulliTester
  // passthrough, this fails BEFORE any stat test runs.
  describe("Tester-vs-source drift gate — JackpotBernoulliTester.bernoulliWhole is byte-arithmetically identical to the _jackpotTicketRoll inline Bernoulli (T-276B-01)", function () {
    it("[00a] production `_jackpotTicketRoll` contains the canonical inline Bernoulli predicate `(uint32(entropy >> 96) % uint32(QTY_SCALE)) < frac` verbatim", function () {
      // Drift gate reads production source: fs.readFileSync DegenerusGameJackpotModule.sol
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      expect(
        /\(uint32\(entropy\s*>>\s*96\)\s*%\s*uint32\(QTY_SCALE\)\)\s*<\s*frac/.test(
          source
        ),
        "production _jackpotTicketRoll must contain `(uint32(entropy >> 96) % uint32(QTY_SCALE)) < frac` — the canonical bits[96..127] Bernoulli predicate"
      ).to.equal(true);
      // The scaled→whole→frac decomposition must also be present verbatim.
      expect(
        /uint32\s+whole\s*=\s*scaledWholeTickets\s*\/\s*uint32\(QTY_SCALE\)/.test(
          source
        ),
        "production must decompose `whole = scaledWholeTickets / uint32(QTY_SCALE)`"
      ).to.equal(true);
      expect(
        /uint32\s+frac\s*=\s*scaledWholeTickets\s*%\s*uint32\(QTY_SCALE\)/.test(
          source
        ),
        "production must decompose `frac = scaledWholeTickets % uint32(QTY_SCALE)`"
      ).to.equal(true);
    });

    it("[00b] `JackpotBernoulliTester` uses the SAME predicate with `seed` substituted for `entropy` (slice offset >> 96, NOT >> 224)", function () {
      const tester = fs.readFileSync(TESTER_SOURCE_PATH, "utf8");
      expect(
        /\(uint32\(seed\s*>>\s*96\)\s*%\s*uint32\(QTY_SCALE\)\)\s*<\s*frac/.test(
          tester
        ),
        "JackpotBernoulliTester must use `(uint32(seed >> 96) % uint32(QTY_SCALE)) < frac` — the inline predicate with `seed` substituted for `entropy`"
      ).to.equal(true);
      // It must NOT carry the lootbox >> 224 slice copied from the analog.
      expect(
        tester.includes("seed >> 224"),
        "JackpotBernoulliTester must NOT use the lootbox bits[224..255] slice (>> 224) — the jackpot surface reads bits[96..127] (>> 96)"
      ).to.equal(false);
      // Same scaled→whole→frac decomposition.
      expect(
        /whole\s*=\s*scaledTickets\s*\/\s*uint32\(QTY_SCALE\)/.test(tester),
        "JackpotBernoulliTester must decompose `whole = scaledTickets / uint32(QTY_SCALE)`"
      ).to.equal(true);
      expect(
        /uint32\s+frac\s*=\s*scaledTickets\s*%\s*uint32\(QTY_SCALE\)/.test(
          tester
        ),
        "JackpotBernoulliTester must decompose `frac = scaledTickets % uint32(QTY_SCALE)`"
      ).to.equal(true);
    });
  });

  describe("EV-neutrality property on the jackpot ticket-roll Bernoulli", function () {
    // At N=10K i.i.d. samples, the variance of mean(whole) is bounded above by
    // 0.25/N; sigma of mean*100 is bounded above by 100*sqrt(0.25/10000) ≈ 0.5.
    // Acceptance: within ±0.5% of scaledTickets — for scaledTickets=100
    // that's ±0.5; for scaledTickets=9999 that's ±49.995. Using ABSOLUTE bound of
    // 1.5 (3-sigma) for low scaledTickets and 0.5% relative bound for higher.
    const N = 10_000;
    const SCALED_VALUES = [47, 99, 100, 147, 250, 1000, 9999];

    SCALED_VALUES.forEach((scaledTickets) => {
      it(`mean(whole)*100 within ±max(1.5, 0.5%) of scaledTickets=${scaledTickets} at N=${N}`, async function () {
        const tester = await deployTester();
        const rng = makeRng(
          "0x" +
            BigInt.asUintN(256, BigInt(0xc0276101 + scaledTickets))
              .toString(16)
              .padStart(64, "0")
        );
        let sumWhole = 0n;
        // Spot-check every 1000th sample against the chain.
        for (let i = 0; i < N; i++) {
          const seed = rng();
          const { whole } = jsBernoulliWhole(scaledTickets, seed);
          sumWhole += whole;
          if (i % 1000 === 0) {
            const [chainWhole] = await tester.bernoulliWhole(scaledTickets, seed);
            expect(chainWhole, `js/chain drift at i=${i}`).to.equal(whole);
          }
        }
        const meanWhole = Number(sumWhole) / N;
        const meanScaled = meanWhole * 100;
        const absDeviation = Math.abs(meanScaled - scaledTickets);
        const tolerance = Math.max(1.5, scaledTickets * 0.005);
        expect(
          absDeviation <= tolerance,
          `scaledTickets=${scaledTickets}: |mean*100 - scaledTickets| = ${absDeviation.toFixed(
            4
          )} > tolerance=${tolerance.toFixed(4)} (mean=${meanWhole.toFixed(6)})`
        ).to.equal(true);
      });
    });
  });

  describe("Empirical Bernoulli win-rate sanity (mean(roundedUp) ≈ frac/100)", function () {
    const N = 10_000;
    const CASES = [
      { scaledTickets: 47, expectedRate: 0.47 },
      { scaledTickets: 99, expectedRate: 0.99 },
      { scaledTickets: 147, expectedRate: 0.47 },
      { scaledTickets: 250, expectedRate: 0.5 },
      { scaledTickets: 100, expectedRate: 0.0 }, // frac=0 → deterministic roundedUp=false
      { scaledTickets: 1000, expectedRate: 0.0 }, // frac=0 → deterministic roundedUp=false
      { scaledTickets: 9999, expectedRate: 0.99 },
    ];

    CASES.forEach(({ scaledTickets, expectedRate }) => {
      it(`mean(roundedUp) within ±0.020 of frac/100 at scaledTickets=${scaledTickets} (N=${N})`, async function () {
        const tester = await deployTester();
        const rng = makeRng(
          "0x" +
            BigInt.asUintN(256, BigInt(0xc0276102 + scaledTickets))
              .toString(16)
              .padStart(64, "0")
        );
        let wins = 0;
        for (let i = 0; i < N; i++) {
          const seed = rng();
          const { roundedUp } = jsBernoulliWhole(scaledTickets, seed);
          if (roundedUp) wins++;
          if (i % 1000 === 0) {
            const [, chainRoundedUp] = await tester.bernoulliWhole(
              scaledTickets,
              seed
            );
            expect(chainRoundedUp, `js/chain drift at i=${i}`).to.equal(
              roundedUp
            );
          }
        }
        const empiricalRate = wins / N;
        const deviation = Math.abs(empiricalRate - expectedRate);
        // 4-sigma at N=10K for Bernoulli(0.5) is sqrt(0.25/N)*4 ≈ 0.020.
        // We use ±0.020 (~4-sigma) for the non-degenerate cases to keep this
        // test rock-solid against CI variance, exact match for frac=0
        // (deterministic roundedUp=false).
        const tolerance = expectedRate === 0.0 ? 0.0 : 0.02;
        expect(
          deviation <= tolerance,
          `scaledTickets=${scaledTickets}: |empiricalRate - ${expectedRate}| = ${deviation.toFixed(
            4
          )} > ${tolerance}`
        ).to.equal(true);
      });
    });
  });
});
