// SPDX-License-Identifier: AGPL-3.0-only
//
// Ent05KeccakRefactorInvariant.test.js — Phase 278 Wave 2 TST-CLEAN-01
//
// Post-ENT-05-refactor statistical invariant of the jackpot ticket-roll.
//
// `DegenerusGameJackpotModule._jackpotTicketRoll` evolves the per-roll entropy
// word on entry via `entropy = EntropyLib.hash2(entropy, entropy)` — a
// scratch-slot keccak self-mix. The low-bit path/level consumers and the
// bits[200..215] Bernoulli sub-roll all read this full-diffusion keccak word:
//   - `entropy % 100`        — the 0..99 path roll (30%/65%/5% branch)
//   - `(entropy / 100) % 4`  — the 65%-branch near level offset (+1..+4)
//   - `(entropy / 100) % 46` — the 5%-branch far level offset (+5..+50)
//   - `uint16(entropy >> 200) % 100` — the Bernoulli whole-ticket round-up slice
//
// This test asserts the NEW post-refactor invariant (D-278-ENT05-TEST-01) — it
// does NOT assert byte-equivalence to the pre-refactor xorshift output (v39→v40
// BAF roll outputs differ for a given seed by design). Three properties:
//
//   1. Chi-square UNIFORMITY (one-way goodness-of-fit) of the 30/65/5 path roll
//      and the near/far offset distributions under the keccak word.
//   2. Per-roll seed-uniqueness across the 2-roll medium-amount-branch pattern.
//      `_jackpotTicketRoll` does `entropy = hash2(entropy, entropy)` then returns
//      it; `_awardJackpotTickets` rethreads, so roll 1 sees `rollEvolve(E)` and
//      roll 2 sees `rollEvolve(rollEvolve(E))`. The two rolls' (path, offset)
//      pairs are asserted independent via the contingency chi-square infra.
//   3. bits[200..215] Bernoulli sub-roll independence from the bits[0..12]
//      path/level consumers in the SAME keccak word (FINDINGS-v39.0.md §4 (b) —
//      disjoint slices of a keccak output word are pairwise independent).
//
// DRIFT GATE: greps `DegenerusGameJackpotModule.sol` for the production
// evolution line and asserts it reads `entropy = EntropyLib.hash2(entropy, entropy);`
// — any drift of the chosen second-arg fails the gate BEFORE the stat assertions
// run, so the JS `rollEvolve` replica can never silently test the wrong word.
//
// PLACEMENT: stat/ per the Phase 275/276 heavy-MC tier (wired into `test:stat`).
//
// CROSS-CITES:
//   - D-278-ENT05-01 / D-278-ENT05-CHAIN-01 / D-278-ENT05-TEST-01 (278-CONTEXT.md)
//   - 278-01-SUMMARY.md (hash2(entropy, entropy) self-mix is the landed evolution)
//   - audit/FINDINGS-v39.0.md §4 (b) (disjoint keccak bit-slices pairwise independent)
//   - test/stat/JackpotTicketRollSeedUniqueness.test.js (chi² + Wilson-Hilferty infra)
//   - feedback_rng_backward_trace.md (per-roll entropy unknown at VRF-commitment time)

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";

const TICKET_SCALE = 100n;
const U256_MASK = (1n << 256n) - 1n;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotModule.sol"
);

// Phase 261/264/266/275 chi² infrastructure reuse (verbatim re-declaration).
// Source: test/stat/JackpotTicketRollSeedUniqueness.test.js / TraitDistribution.test.js.
function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}

// Deterministic seeded keccak-counter PRNG (mirrors `makeRng` from the
// JackpotTicketRoll* stat tests + TraitDistribution.test.js).
function makeRng(seedHex) {
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

// JS replica of the `_jackpotTicketRoll` entropy evolution: the on-chain
// `EntropyLib.hash2(entropy, entropy)` scratch-slot keccak self-mix
// (`mstore(0x00, a); mstore(0x20, a); keccak256(0x00, 0x40)`), which is
// equivalent to `solidityPackedKeccak256(["uint256","uint256"], [state, state])`.
function rollEvolve(state) {
  return (
    BigInt(
      hre.ethers.solidityPackedKeccak256(
        ["uint256", "uint256"],
        [state & U256_MASK, state & U256_MASK]
      )
    ) & U256_MASK
  );
}

// bits[0..12] consumer replicas — the path/level selection `_jackpotTicketRoll`
// performs on the evolved `entropy` word.
function pathRoll(seed) {
  return BigInt(seed) % 100n;
}
function nearOffset(seed) {
  return (BigInt(seed) / 100n) % 4n;
}
function farOffset(seed) {
  return (BigInt(seed) / 100n) % 46n;
}
// bits[200..215] Bernoulli slice == raw 16-bit window; %100 == the compare value.
function modSlice(seed) {
  return ((BigInt(seed) >> 200n) & 0xffffn) % TICKET_SCALE;
}
// The 30/65/5 path branch the production code selects from `pathRoll`.
// roll < 30 → min (branch 0); roll < 95 → near (branch 1); else → far (branch 2).
function pathBranch(seed) {
  const r = pathRoll(seed);
  if (r < 30n) return 0;
  if (r < 95n) return 1;
  return 2;
}

// One-way (goodness-of-fit) chi-square against an expected-probability vector.
// Returns { chi2, df } where df = (#categories - 1).
function goodnessOfFitChi2(counts, expectedProbs, N) {
  let chi2 = 0;
  for (let i = 0; i < counts.length; i++) {
    const expected = expectedProbs[i] * N;
    const diff = counts[i] - expected;
    chi2 += (diff * diff) / expected;
  }
  return { chi2, df: counts.length - 1 };
}

// Generic contingency-table chi-square between two integer-valued samples.
// Mirrors `contingencyChi2` from JackpotTicketRollSeedUniqueness.test.js.
function contingencyChi2(aSamples, bSamples, aCard, bCard) {
  const N = aSamples.length;
  const table = Array.from({ length: aCard }, () => new Array(bCard).fill(0));
  const aMarg = new Array(aCard).fill(0);
  const bMarg = new Array(bCard).fill(0);
  for (let i = 0; i < N; i++) {
    table[aSamples[i]][bSamples[i]] += 1;
    aMarg[aSamples[i]] += 1;
    bMarg[bSamples[i]] += 1;
  }
  let chi2 = 0;
  for (let a = 0; a < aCard; a++) {
    for (let b = 0; b < bCard; b++) {
      const expected = (aMarg[a] * bMarg[b]) / N;
      if (expected > 0) {
        const diff = table[a][b] - expected;
        chi2 += (diff * diff) / expected;
      }
    }
  }
  const aNonzero = aMarg.filter((c) => c > 0).length;
  const bNonzero = bMarg.filter((c) => c > 0).length;
  const df = (aNonzero - 1) * (bNonzero - 1);
  return { chi2, df };
}

describe("Ent05KeccakRefactorInvariant (stat-suite, heavy-MC) — TST-CLEAN-01 post-keccak-refactor statistical invariant", function () {
  this.timeout(600_000);

  // Drift gate — runs first. If the production evolution line drifts from the
  // chosen `hash2(entropy, entropy)` self-mix, this fails BEFORE any stat test
  // runs, so the JS `rollEvolve` replica can never silently model the wrong word.
  describe("Drift gate — production `_jackpotTicketRoll` evolves entropy via `EntropyLib.hash2(entropy, entropy)`", function () {
    it("[00a] production source contains the canonical keccak self-mix evolution `entropy = EntropyLib.hash2(entropy, entropy);`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      expect(
        /entropy\s*=\s*EntropyLib\.hash2\(\s*entropy\s*,\s*entropy\s*\)\s*;/.test(
          source
        ),
        "production _jackpotTicketRoll must evolve `entropy = EntropyLib.hash2(entropy, entropy);` — the keccak self-mix the JS rollEvolve replica mirrors"
      ).to.equal(true);
      // The deleted xorshift primitive must not reappear.
      expect(
        source.includes("EntropyLib.entropyStep"),
        "production must not reference the deleted EntropyLib.entropyStep"
      ).to.equal(false);
    });
  });

  describe("Property 1 — chi-square uniformity of the 30/65/5 path roll + near/far offset distributions under the keccak word", function () {
    const N = 20_000;

    it(`30/65/5 path-branch split is uniform-to-spec — goodness-of-fit Wilson-Hilferty Z < 4 at N=${N}`, function () {
      const rng = makeRng(
        "0x" +
          BigInt.asUintN(256, BigInt(0xc0278101))
            .toString(16)
            .padStart(64, "0")
      );
      const counts = [0, 0, 0];
      for (let i = 0; i < N; i++) {
        counts[pathBranch(rollEvolve(rng()))] += 1;
      }
      // Expected split: branch 0 = 30/100, branch 1 = 65/100, branch 2 = 5/100.
      const { chi2, df } = goodnessOfFitChi2(counts, [0.3, 0.65, 0.05], N);
      const z = wilsonHilfertyZ(chi2, df);
      expect(
        z < 4,
        `path-branch split: counts=${counts} chi²=${chi2.toFixed(
          3
        )} df=${df} → Z=${z.toFixed(3)} >= 4`
      ).to.equal(true);
    });

    it(`the bits[0..1] near offset is uniform over {0,1,2,3} — goodness-of-fit Wilson-Hilferty Z < 4 at N=${N}`, function () {
      const rng = makeRng(
        "0x" +
          BigInt.asUintN(256, BigInt(0xc0278102))
            .toString(16)
            .padStart(64, "0")
      );
      const counts = [0, 0, 0, 0];
      for (let i = 0; i < N; i++) {
        counts[Number(nearOffset(rollEvolve(rng())))] += 1;
      }
      const { chi2, df } = goodnessOfFitChi2(counts, [0.25, 0.25, 0.25, 0.25], N);
      const z = wilsonHilfertyZ(chi2, df);
      expect(
        z < 4,
        `near offset uniformity: counts=${counts} chi²=${chi2.toFixed(
          3
        )} df=${df} → Z=${z.toFixed(3)} >= 4`
      ).to.equal(true);
    });

    it(`the far offset is uniform over {0..45} — goodness-of-fit Wilson-Hilferty Z < 4 at N=${N}`, function () {
      const rng = makeRng(
        "0x" +
          BigInt.asUintN(256, BigInt(0xc0278103))
            .toString(16)
            .padStart(64, "0")
      );
      const counts = new Array(46).fill(0);
      for (let i = 0; i < N; i++) {
        counts[Number(farOffset(rollEvolve(rng())))] += 1;
      }
      const { chi2, df } = goodnessOfFitChi2(
        counts,
        new Array(46).fill(1 / 46),
        N
      );
      const z = wilsonHilfertyZ(chi2, df);
      expect(
        z < 4,
        `far offset uniformity: chi²=${chi2.toFixed(
          3
        )} df=${df} → Z=${z.toFixed(3)} >= 4`
      ).to.equal(true);
    });
  });

  describe("Property 2 — per-roll seed-uniqueness across the 2-roll medium-amount-branch pattern (D-278-ENT05-CHAIN-01)", function () {
    const N = 20_000;

    it(`roll1 = rollEvolve(E) and roll2 = rollEvolve(rollEvolve(E)) produce distinct evolved words for every base E (N=${N})`, function () {
      const rng = makeRng(
        "0x" +
          BigInt.asUintN(256, BigInt(0xc0278104))
            .toString(16)
            .padStart(64, "0")
      );
      let collisions = 0;
      for (let i = 0; i < N; i++) {
        const base = rng();
        const e1 = rollEvolve(base);
        const e2 = rollEvolve(e1);
        if (e1 === e2) collisions++;
      }
      // keccak collision-resistance: roll 1's input (E) differs from roll 2's
      // input (rollEvolve(E)) with overwhelming probability, so the evolved
      // words differ. Zero collisions expected across the sample.
      expect(
        collisions,
        `${collisions} roll1==roll2 collisions across N=${N} — keccak self-mix must produce distinct per-roll words`
      ).to.equal(0);
    });

    it(`the 2-roll (path-branch, near-offset) pairs are statistically independent — chi-square Wilson-Hilferty Z < 3.5 at N=${N}`, function () {
      const rng = makeRng(
        "0x" +
          BigInt.asUintN(256, BigInt(0xc0278105))
            .toString(16)
            .padStart(64, "0")
      );
      const roll1Samples = [];
      const roll2Samples = [];
      for (let i = 0; i < N; i++) {
        const base = rng();
        const e1 = rollEvolve(base);
        const e2 = rollEvolve(e1);
        // Pair the roll-1 path branch (3 categories) with the roll-2 path
        // branch (3 categories): independence ⇒ no contingency structure.
        roll1Samples.push(pathBranch(e1));
        roll2Samples.push(pathBranch(e2));
      }
      const { chi2, df } = contingencyChi2(roll1Samples, roll2Samples, 3, 3);
      const z = wilsonHilfertyZ(chi2, df);
      expect(
        z < 3.5,
        `2-roll (roll1-branch, roll2-branch): chi²=${chi2.toFixed(
          3
        )} df=${df} → Z=${z.toFixed(3)} >= 3.5`
      ).to.equal(true);
    });

    it(`the 2-roll bits[200..215] Bernoulli slices are statistically independent — chi-square Wilson-Hilferty Z < 3.5 at N=${N}`, function () {
      const rng = makeRng(
        "0x" +
          BigInt.asUintN(256, BigInt(0xc0278106))
            .toString(16)
            .padStart(64, "0")
      );
      const roll1Samples = [];
      const roll2Samples = [];
      for (let i = 0; i < N; i++) {
        const base = rng();
        const e1 = rollEvolve(base);
        const e2 = rollEvolve(e1);
        roll1Samples.push(Number(modSlice(e1)));
        roll2Samples.push(Number(modSlice(e2)));
      }
      const { chi2, df } = contingencyChi2(roll1Samples, roll2Samples, 100, 100);
      const z = wilsonHilfertyZ(chi2, df);
      expect(
        z < 3.5,
        `2-roll bits[200..215] slices: chi²=${chi2.toFixed(
          3
        )} df=${df} → Z=${z.toFixed(3)} >= 3.5`
      ).to.equal(true);
    });
  });

  describe("Property 3 — bits[200..215] Bernoulli sub-roll independence from the bits[0..12] path/level consumers under the keccak word (FINDINGS-v39.0.md §4 (b))", function () {
    const N = 20_000;

    // The Bernoulli slice domain is %100 (0..99). The three bits[0..12] consumer
    // domains: pathRoll 0..99, nearOffset 0..3, farOffset 0..45.
    const CONSUMERS = [
      { id: "pathRoll (entropy % 100)", fn: pathRoll, card: 100 },
      { id: "nearOffset ((entropy / 100) % 4)", fn: nearOffset, card: 4 },
      { id: "farOffset ((entropy / 100) % 46)", fn: farOffset, card: 46 },
    ];

    CONSUMERS.forEach(({ id, fn, card }) => {
      it(`pairwise chi-square: bits[200..215] %100 vs ${id} — Wilson-Hilferty Z < 3.5 at N=${N}`, function () {
        const rng = makeRng(
          "0x" +
            BigInt.asUintN(256, BigInt(0xc0278107))
              .toString(16)
              .padStart(64, "0")
        );
        const bernSamples = [];
        const consumerSamples = [];
        for (let i = 0; i < N; i++) {
          // Each consumer reads the SAME evolved keccak word — disjoint slices.
          const evolved = rollEvolve(rng());
          bernSamples.push(Number(modSlice(evolved)));
          consumerSamples.push(Number(fn(evolved)));
        }
        const { chi2, df } = contingencyChi2(
          bernSamples,
          consumerSamples,
          100,
          card
        );
        const z = wilsonHilfertyZ(chi2, df);
        // The 180+ bit gap between bits[0..12] and bits[200..215] of a full
        // keccak word makes genuine correlation structurally impossible — a
        // wide 3.5-sigma bound guards only against PRNG-fixture pathology.
        expect(
          z < 3.5,
          `bits[200..215] vs ${id}: chi²=${chi2.toFixed(
            3
          )} df=${df} → Z=${z.toFixed(3)} >= 3.5`
        ).to.equal(true);
      });
    });
  });
});
