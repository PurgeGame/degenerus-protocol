// SPDX-License-Identifier: AGPL-3.0-only
//
// FlipRoundHundredsEv.test.js — statistical validation of the 100-FLIP award collapse.
//
// `FlipRoundLib.roundFlipToHundreds` is the ticket Bernoulli collapse re-pointed from
// ticket counts to FLIP amounts, with the granule moved from 1 FLIP to 100 FLIP: the
// 0..99 whole-FLIP remainder rounds up with probability rem/100 against a uint32 window
// of a committed-VRF-derived word. This file asserts the properties that make that
// collapse safe to ship at the four §3c award sites:
//
//   - EV-neutrality: mean(rounded) tracks `floorWholeFlip(amount)`, so the collapse costs
//     the player only the sub-1-FLIP dust the previous whole-FLIP floor already discarded.
//   - Granularity: every output is an exact multiple of 100 FLIP.
//   - Round-up frequency: fires at rate rem/100, per remainder.
//   - Window uniformity: `uint32(entropy) % 100` is uniform (chi², df=99), so the
//     ~2e-8 modulo bias is the only deviation.
//   - The threshold gate: at or below 1,000 FLIP the award is paid EXACTLY, so a small
//     win never rounds to nothing.
//
// CROSS-CITES:
//   - test/stat/LootboxBernoulliEv.test.js (the ticket-collapse suite this mirrors;
//     `makeRng` / `wilsonHilfertyZ` re-declared verbatim from it)
//   - D-279-INLINE-01 SUPERSEDED — the whole-FLIP inline floor is replaced by this
//     collapse at the award sites.

import { expect } from "chai";
import hre from "hardhat";

const ONE_FLIP = 10n ** 18n;
const UNIT = 100n * ONE_FLIP; // FLIP_ROUND_UNIT
const THRESHOLD = 1_000n * ONE_FLIP; // FLIP_ROUND_THRESHOLD

async function deployTester() {
  const Factory = await hre.ethers.getContractFactory(
    "FlipRoundBernoulliTester"
  );
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

// JS replica of the collapse. Drift vs the deployed library is caught by the
// js-vs-chain spot check below.
function jsRoundFlipToHundreds(amount, entropy) {
  let hundreds = amount / UNIT;
  const remFlip = (amount % UNIT) / ONE_FLIP;
  if (remFlip !== 0n) {
    const slice = (entropy & 0xffffffffn) % 100n;
    if (slice < remFlip) hundreds += 1n;
  }
  return hundreds * UNIT;
}

function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}

// Representative remainders: no remainder, the smallest, an odd interior value, the
// maximum-variance midpoint, and the largest.
const REMAINDERS_FLIP = [0n, 1n, 37n, 50n, 99n];

describe("FlipRoundHundredsEv (stat-suite) — 100-FLIP award collapse", function () {
  this.timeout(300_000);

  let tester;
  before(async function () {
    tester = await deployTester();
  });

  describe("EV-neutrality at N=10K per remainder", function () {
    const N = 10_000;

    // Base award of 47 whole units (4,700 FLIP) — comfortably above the threshold so
    // the gate is not what is under test here.
    const BASE_UNITS = 47n;

    for (const rem of REMAINDERS_FLIP) {
      it(`remainder ${rem} FLIP: mean(rounded) tracks the raw award within 4 sigma (N=${N})`, async function () {
        const amount = BASE_UNITS * UNIT + rem * ONE_FLIP;
        const rng = makeRng(hre.ethers.id(`flip-round-ev-${rem}`));

        let sum = 0n;
        let upCount = 0;
        for (let i = 0; i < N; i++) {
          const rounded = jsRoundFlipToHundreds(amount, rng());
          expect(rounded % UNIT).to.equal(
            0n,
            "every rounded award must be a whole 100-FLIP multiple"
          );
          sum += rounded;
          if (rounded > BASE_UNITS * UNIT) upCount++;
        }

        // Target: the raw award less its sub-1-FLIP dust (there is none here — the
        // sweep is constructed on whole FLIP).
        const targetWei = amount;
        const meanWei = sum / BigInt(N);

        // sd(mean) in FLIP = 100 * sqrt(p(1-p)/N), maximised at p=0.5 → 0.5 FLIP at
        // N=10K. 4 sigma is 2 FLIP; use that as the band for every remainder.
        const bandWei = 2n * ONE_FLIP;
        const delta = meanWei > targetWei ? meanWei - targetWei : targetWei - meanWei;
        expect(delta <= bandWei).to.equal(
          true,
          `mean ${meanWei} deviates from ${targetWei} by ${delta} wei (band ${bandWei})`
        );

        // Round-up frequency tracks rem/100 on the same 4-sigma logic.
        const expectedUps = (Number(rem) / 100) * N;
        const sigmaUps = Math.sqrt(
          (Number(rem) / 100) * (1 - Number(rem) / 100) * N
        );
        expect(Math.abs(upCount - expectedUps)).to.be.at.most(
          4 * sigmaUps + 1,
          `round-up count ${upCount} vs expected ${expectedUps}`
        );
      });
    }
  });

  describe("js-vs-chain parity — the JS replica reproduces the deployed library", function () {
    it("agrees across a sweep of amounts and entropies", async function () {
      const rng = makeRng(hre.ethers.id("flip-round-parity"));
      for (const rem of REMAINDERS_FLIP) {
        for (const units of [0n, 1n, 9n, 47n, 1234n]) {
          for (let k = 0; k < 8; k++) {
            const entropy = rng();
            const amount = units * UNIT + rem * ONE_FLIP;
            const onChain = await tester.roundFlipToHundreds(amount, entropy);
            expect(onChain).to.equal(
              jsRoundFlipToHundreds(amount, entropy),
              `parity break at units=${units} rem=${rem}`
            );
          }
        }
      }
    });

    it("discards sub-1-FLIP dust unconditionally, exactly as the old whole-FLIP floor did", async function () {
      const rng = makeRng(hre.ethers.id("flip-round-dust"));
      // 3 units + 99 whole FLIP + 0.999… FLIP of dust: the dust can never tip the
      // round-up, because the remainder is reduced to whole FLIP before the compare.
      const dust = ONE_FLIP - 1n;
      const amount = 3n * UNIT + 99n * ONE_FLIP + dust;
      for (let k = 0; k < 64; k++) {
        const entropy = rng();
        const withDust = await tester.roundFlipToHundreds(amount, entropy);
        const withoutDust = await tester.roundFlipToHundreds(
          amount - dust,
          entropy
        );
        expect(withDust).to.equal(withoutDust);
      }
    });
  });

  describe("Threshold gate — small awards keep the whole-FLIP floor", function () {
    it("at or below 1,000 FLIP the gated form floors to whole FLIP and nothing more", async function () {
      const rng = makeRng(hre.ethers.id("flip-round-threshold"));
      // The §3c sites bottom out near 18 FLIP at the milestone price; sample across
      // that span up to and including the threshold itself. The odd wei on each
      // sample is the residue the floor must discard.
      const samples = [
        1n,
        13n * ONE_FLIP,
        18n * ONE_FLIP + 1n,
        110n * ONE_FLIP,
        352n * ONE_FLIP + 999_999_999n,
        999n * ONE_FLIP + ONE_FLIP / 2n,
        THRESHOLD,
      ];
      for (const amount of samples) {
        const floored = (amount / ONE_FLIP) * ONE_FLIP;
        for (let k = 0; k < 4; k++) {
          // The draw is consumed either way, so an entropy-dependent result here
          // would show up as a mismatch across the four rolls.
          expect(await tester.roundGated(amount, rng())).to.equal(
            floored,
            `award ${amount} at or below the threshold must floor to ${floored}`
          );
        }
      }
    });

    it("the floor is protocol-favourable: it never pays more than the raw award", async function () {
      const samples = [
        0n,
        1n,
        ONE_FLIP - 1n,
        ONE_FLIP,
        ONE_FLIP + 1n,
        777n * ONE_FLIP + 123_456_789n,
        THRESHOLD,
      ];
      for (const amount of samples) {
        const floored = await tester.floorWholeFlip(amount);
        expect(floored % ONE_FLIP).to.equal(
          0n,
          `floor of ${amount} left wei-scale residue`
        );
        expect(floored <= amount).to.equal(
          true,
          `floor of ${amount} paid ${floored}, more than the raw award`
        );
        expect(amount - floored < ONE_FLIP).to.equal(
          true,
          `floor of ${amount} discarded a whole FLIP or more`
        );
      }
    });

    it("one wei above the threshold the gate engages and the output is a 100-FLIP multiple", async function () {
      const rng = makeRng(hre.ethers.id("flip-round-threshold-above"));
      const amount = THRESHOLD + 1n;
      for (let k = 0; k < 32; k++) {
        const paid = await tester.roundGated(amount, rng());
        expect(paid % UNIT).to.equal(0n);
        // 1,000 FLIP is exactly 10 units with a zero whole-FLIP remainder, so the
        // extra wei is dust and the collapse is a pure floor here.
        expect(paid).to.equal(THRESHOLD);
      }
    });

    it("the tester's threshold constants match the library", async function () {
      expect(await tester.FLIP_ROUND_UNIT()).to.equal(UNIT);
      expect(await tester.FLIP_ROUND_THRESHOLD()).to.equal(THRESHOLD);
    });
  });

  describe("Window uniformity — `uint32(entropy) % 100` chi², df=99", function () {
    it("the mod-100 window is uniform at N=50K", async function () {
      const N = 50_000;
      const rng = makeRng(hre.ethers.id("flip-round-chi2"));
      const bins = new Array(100).fill(0);
      for (let i = 0; i < N; i++) {
        bins[Number((rng() & 0xffffffffn) % 100n)]++;
      }
      const expected = N / 100;
      let chi2 = 0;
      for (const observed of bins) {
        const d = observed - expected;
        chi2 += (d * d) / expected;
      }
      // Wilson-Hilferty normal approximation; |z| <= 4 is a two-sided ~6e-5 gate.
      expect(Math.abs(wilsonHilfertyZ(chi2, 99))).to.be.at.most(
        4,
        `chi2=${chi2} (df=99) is not consistent with a uniform mod-100 window`
      );
    });

    it("the on-chain window matches the JS slice", async function () {
      const rng = makeRng(hre.ethers.id("flip-round-slice"));
      for (let k = 0; k < 32; k++) {
        const entropy = rng();
        expect(await tester.roundSlice(entropy)).to.equal(
          Number((entropy & 0xffffffffn) % 100n)
        );
        expect(await tester.roundRaw32(entropy)).to.equal(
          Number(entropy & 0xffffffffn)
        );
      }
    });
  });

  describe("Decomposition boundaries", function () {
    it("splits an award into units / whole-FLIP remainder / sub-1-FLIP dust", async function () {
      const cases = [
        { amount: 0n, hundreds: 0n, rem: 0n, dust: 0n },
        { amount: ONE_FLIP - 1n, hundreds: 0n, rem: 0n, dust: ONE_FLIP - 1n },
        { amount: ONE_FLIP, hundreds: 0n, rem: 1n, dust: 0n },
        { amount: 99n * ONE_FLIP, hundreds: 0n, rem: 99n, dust: 0n },
        { amount: UNIT, hundreds: 1n, rem: 0n, dust: 0n },
        { amount: UNIT + ONE_FLIP - 1n, hundreds: 1n, rem: 0n, dust: ONE_FLIP - 1n },
        {
          amount: 5n * UNIT + 37n * ONE_FLIP + 12345n,
          hundreds: 5n,
          rem: 37n,
          dust: 12345n,
        },
      ];
      for (const c of cases) {
        const [hundreds, rem, dust] = await tester.decompose(c.amount);
        expect(hundreds).to.equal(c.hundreds, `hundreds @ ${c.amount}`);
        expect(rem).to.equal(c.rem, `remainder @ ${c.amount}`);
        expect(dust).to.equal(c.dust, `dust @ ${c.amount}`);
      }
    });

    it("an award under 100 FLIP with a zero draw floors to zero, and the threshold gate is what keeps that off the live sites", async function () {
      // Ungated, a 99-FLIP award rounds to 0 whenever the draw lands at or above 99.
      // Every production call site gates on `> 1,000 FLIP`, so this state is
      // unreachable in the shipped paths — asserted here so the gate's purpose is
      // pinned by a test rather than only by a comment.
      const rng = makeRng(hre.ethers.id("flip-round-sub-unit"));
      let sawZero = false;
      for (let k = 0; k < 256 && !sawZero; k++) {
        const entropy = rng();
        if ((await tester.roundFlipToHundreds(99n * ONE_FLIP, entropy)) === 0n) {
          sawZero = true;
        }
        expect(await tester.roundGated(99n * ONE_FLIP, entropy)).to.equal(
          99n * ONE_FLIP
        );
      }
      expect(sawZero).to.equal(
        true,
        "ungated, a sub-100-FLIP award must be able to round to zero"
      );
    });
  });
});
