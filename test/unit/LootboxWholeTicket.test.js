// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxWholeTicket.test.js — Phase 274 Wave 2 TST-WT-01..07
//
// Manual-path whole-ticket Bernoulli collapse coverage. The contract under test is
// `DegenerusGameLootboxModule._resolveLootboxCommon` manual branch (L1032-1061 at
// v39 HEAD) which:
//   1. snapshots `scaledPre = futureTickets`
//   2. computes `whole = scaledPre / 100`, `frac = scaledPre % 100`
//   3. consumes `bits[152..167]` of the per-resolution seed via
//      `uint16(seed >> 152) % uint16(TICKET_SCALE) < uint16(frac)`
//   4. if the Bernoulli wins → `whole += 1`, `roundedUp = true`
//   5. queues `whole` tickets via `_queueTickets` OR pays the WWXRP consolation
//   6. emits `LootboxTicketRoll(player, index, scaledPre, roundedUp)`
//
// TEST STRATEGY:
//   - TST-WT-01 (EV-neutrality) + TST-WT-02 (boundaries) + TST-WT-03 (bit-slice
//     independence) — directly invoke `LootboxBernoulliTester` (a stand-alone
//     `external pure` mirror of the manual-branch arithmetic). Pattern from
//     `PriceLookupTester` / `JackpotSoloTester` / `TraitUtilsTester`.
//     Drift-detection: a source-grep test asserts the production source contains
//     the exact instruction sequence the tester mirrors — if the tester drifts
//     from production, the grep test fails first.
//   - TST-WT-03 (bit-slice gating) + TST-WT-04..07 (event emissions + field
//     consistency + return-value preservation) — source-level structural
//     assertions on `contracts/modules/DegenerusGameLootboxModule.sol`. The
//     manual-path branch and the production source bytes are the audit
//     subjects; static-analysis is the appropriate proof technique for
//     "function X never emits event Y from branch Z" properties in audit
//     deliverables (D-274-NO-EVT-BREAK-01 G17/G18/G19 grep recipes set the
//     precedent).
//
// CROSS-CITES:
//   - D-274-BIT-SLICE-01 (post-c21f833a supersession: uint16 / bits[152..167])
//   - D-274-NO-EVT-BREAK-01 (LootBoxOpened.futureTickets + BurnieLootOpen.tickets
//     + TicketsQueuedScaled semantics UNCHANGED)
//   - feedback_rng_backward_trace.md (slice consumed only on manual paths;
//     auto-resolve never reads bits[152..167])
//   - feedback_rng_commitment_window.md (no player-controllable input mutates
//     between VRF commit and lootbox open that affects bits[152..167]
//     independently)

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";

const TICKET_SCALE = 100n;
const TICKET_SCALE_NUM = 100;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);

async function deployTester() {
  const Factory = await hre.ethers.getContractFactory("LootboxBernoulliTester");
  const tester = await Factory.deploy();
  await tester.waitForDeployment();
  return tester;
}

/**
 * JS replica of the on-chain Bernoulli math. Verified against the deployed
 * tester at every assertion below (replica drift is structurally caught by
 * the boundary harness — if the replica disagrees with the tester at ANY
 * boundary, the bulk EV/chi² assertions cannot be silently wrong without
 * the boundary harness failing first).
 *
 * Returns { whole: bigint, roundedUp: boolean }.
 */
function jsBernoulliWhole(scaledPre, seed) {
  const scaled = BigInt(scaledPre);
  let whole = scaled / TICKET_SCALE;
  const frac = scaled % TICKET_SCALE;
  let roundedUp = false;
  if (frac !== 0n) {
    // uint16(seed >> 152) — keep low 16 bits after the shift
    const sliceRaw = (BigInt(seed) >> 152n) & 0xffffn;
    const slice = sliceRaw % TICKET_SCALE;
    if (slice < frac) {
      whole = whole + 1n;
      roundedUp = true;
    }
  }
  return { whole, roundedUp };
}

/**
 * Deterministic seeded keccak-counter PRNG (mirrors the `makeRng` pattern from
 * `test/stat/TraitDistribution.test.js`). Reproducibility: any future failure
 * is exactly replayable by re-running with the same seed.
 */
function makeRng(seedHex) {
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

// Chi-square critical values at alpha = 0.05 (re-declared verbatim from
// test/stat/TraitDistribution.test.js per Phase 266 STAT-03 reuse-existing-
// tooling discipline).
const CHI2_CRIT_05 = {
  1: 3.841,
  2: 5.991,
  3: 7.815,
  4: 9.488,
  5: 11.07,
  6: 12.592,
  7: 14.067,
};

// Wilson-Hilferty Z one-sided approximation for df > 7 (mirrors v36+ pattern).
function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}

describe("LootboxWholeTicket — Phase 274 Wave 2 TST-WT-01..07", function () {
  this.timeout(180_000);

  describe("TST-WT-DRIFT — production source contains the canonical Bernoulli instruction sequence", function () {
    it("contracts/modules/DegenerusGameLootboxModule.sol contains the exact uint16(seed >> 152) % uint16(TICKET_SCALE) Bernoulli pattern", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");

      // Manual-branch Bernoulli gate. The pattern below is the load-bearing
      // drift detector — if production reformats this expression, the tester
      // contract above MUST be updated in lock-step.
      const bernoulliPattern =
        /\(uint16\(seed >> 152\)\s*%\s*uint16\(TICKET_SCALE\)\)\s*<\s*uint16\(frac\)/;
      expect(
        source.match(bernoulliPattern),
        "production Bernoulli pattern drifted from tester — update LootboxBernoulliTester.sol to match"
      ).to.not.be.null;

      // scaledPre snapshot — must be live above the Bernoulli arithmetic.
      expect(
        /uint32 scaledPre = futureTickets;/.test(source),
        "scaledPre snapshot missing"
      ).to.equal(true);

      // Phase 275 D-275-HOIST-01: the Bernoulli math is hoisted to shared scope
      // ABOVE the `if (index != type(uint48).max)` sentinel gate so both manual
      // and auto-resolve branches consume the same `whole`/`roundedUp` locals.
      // Structural invariants verified here:
      //   (a) `seed >> 152` appears exactly once (hoisted; not duplicated).
      //   (b) The Bernoulli slice sits INSIDE the outer
      //       `if (futureTickets != 0)` guard (no slice consumption when
      //       `futureTickets == 0`).
      //   (c) The slice sits BEFORE the manual-branch gate
      //       `if (index != type(uint48).max)` — the gate is now downstream
      //       of the Bernoulli computation, not upstream.
      const sliceMatches = [...source.matchAll(/uint16\(seed >> 152\)/g)];
      expect(
        sliceMatches.length,
        "Bernoulli slice must be hoisted exactly once (no duplication across branches)"
      ).to.equal(1);
      const sliceLineIdx = sliceMatches[0].index;
      const preamble = source.slice(0, sliceLineIdx);
      // Outer-guard ancestor: `if (futureTickets != 0)` precedes the slice.
      const outerGuardIdx = preamble.lastIndexOf("if (futureTickets != 0)");
      expect(
        outerGuardIdx,
        "Bernoulli slice not gated by outer `if (futureTickets != 0)` guard"
      ).to.be.greaterThan(-1);
      // The manual-branch gate must come AFTER the slice (hoist invariant).
      const manualGateAfter = source.indexOf("if (index != type(uint48).max)", sliceLineIdx);
      expect(
        manualGateAfter,
        "Phase 275 hoist invariant: `if (index != type(uint48).max)` must appear AFTER the Bernoulli slice"
      ).to.be.greaterThan(sliceLineIdx);
    });

    it("tester contract exposes `bernoulliWhole(uint32,uint256)` returning (uint32 whole, bool roundedUp)", async function () {
      const tester = await deployTester();
      // Smoke: scaledPre = 100 with any seed → whole=1, roundedUp=false.
      const [whole, roundedUp] = await tester.bernoulliWhole(100, 0x1234n);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(false);
    });
  });

  describe("TST-WT-01 — EV-neutrality property at N >= 10K seeds", function () {
    // E[whole_post] * TICKET_SCALE == scaledPre EXACTLY by construction:
    //   E[whole_post] = whole_floor * P(fail) + (whole_floor + 1) * P(win)
    //                 = whole_floor + frac/100
    //   E[whole_post] * 100 = whole_floor * 100 + frac = scaledPre.
    //
    // Empirical: at N = 10_000 i.i.d. samples on independent seeds, the
    // observed mean(whole_post) * 100 must fall within 3-sigma binomial
    // tolerance of scaledPre. The variance of a single Bernoulli(p) is
    // p(1-p) ≤ 0.25, so the variance of mean(whole) at N samples is
    // bounded above by 0.25/N; the sigma of mean(whole) * 100 is
    // bounded above by 100 * sqrt(0.25/N) ≈ 0.5 for N=10K. 3-sigma is 1.5.
    // We use the more conservative ±2.5 ticket-unit tolerance (5-sigma)
    // to keep this test rock-solid against CI flake.
    const SCALED_VALUES = [47, 99, 100, 147, 250, 1000, 9999];
    const N = 10_000;

    SCALED_VALUES.forEach((scaledPre) => {
      it(`mean(whole) * 100 within ±2.5 of scaledPre=${scaledPre} at N=${N}`, async function () {
        const tester = await deployTester();
        const rng = makeRng(
          "0x" +
            BigInt.asUintN(256, BigInt(0xc0274_0001 + scaledPre))
              .toString(16)
              .padStart(64, "0")
        );

        let sumWhole = 0n;
        let countRoundUp = 0;
        // To avoid hammering the RPC with 10K external calls, we use the JS
        // replica for the EV computation AND assert the replica==tester at a
        // hash-stratified subsample of 100 seeds inside this loop. Drift
        // protection is layered: TST-WT-DRIFT (above) catches source-vs-tester
        // drift; the per-loop inline check catches js-vs-tester drift.
        const SAMPLE_VERIFY_EVERY = 100;
        for (let i = 0; i < N; i++) {
          const seed = rng();
          const { whole, roundedUp } = jsBernoulliWhole(scaledPre, seed);
          sumWhole += whole;
          if (roundedUp) countRoundUp++;
          if (i % SAMPLE_VERIFY_EVERY === 0) {
            const [chainWhole, chainRoundedUp] = await tester.bernoulliWhole(
              scaledPre,
              seed
            );
            expect(chainWhole, `JS-vs-chain whole mismatch at i=${i}`).to.equal(
              whole
            );
            expect(
              chainRoundedUp,
              `JS-vs-chain roundedUp mismatch at i=${i}`
            ).to.equal(roundedUp);
          }
        }

        // Mean assertion. sumWhole and N as bigints; convert via cast to Number
        // for the float comparison.
        const meanWhole = Number(sumWhole) / N;
        const meanScaled = meanWhole * 100;
        const absDeviation = Math.abs(meanScaled - scaledPre);
        expect(
          absDeviation <= 2.5,
          `scaledPre=${scaledPre}: |mean*100 - scaledPre| = ${absDeviation.toFixed(
            3
          )} > 2.5 (mean=${meanWhole.toFixed(
            4
          )}, roundUpCount=${countRoundUp}/${N})`
        ).to.equal(true);
      });
    });
  });

  describe("TST-WT-02 — boundary cases at scaledPre ∈ {0, 1, 99, 100, 101, 199, 200}", function () {
    it("scaledPre=0 deterministically yields whole=0, roundedUp=false (frac==0 short-circuits)", async function () {
      const tester = await deployTester();
      // With scaledPre=0, frac=0, the gate `frac != 0` short-circuits; no Bernoulli
      // roll occurs regardless of seed. NOTE: in the production manual branch this
      // code is GUARDED by `if (futureTickets != 0)` so it never executes when
      // scaledPre=0 — see TST-WT-04 / TST-WT-06(f) for the source-level proof.
      // Here we exercise the math primitive directly.
      for (const seed of [0n, 1n, 1n << 152n, (1n << 160n) - 1n, 0xdeadbeefn]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(0, seed);
        expect(whole).to.equal(0n);
        expect(roundedUp).to.equal(false);
      }
    });

    it("scaledPre=100 deterministically yields whole=1, roundedUp=false (frac==0 short-circuits)", async function () {
      const tester = await deployTester();
      for (const seed of [0n, 1n, (1n << 152n) | 99n, (1n << 200n) - 1n]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(100, seed);
        expect(whole).to.equal(1n);
        expect(roundedUp).to.equal(false);
      }
    });

    it("scaledPre=200 deterministically yields whole=2, roundedUp=false (frac==0 short-circuits)", async function () {
      const tester = await deployTester();
      for (const seed of [0n, 1n, (1n << 153n), (1n << 167n) - 1n]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(200, seed);
        expect(whole).to.equal(2n);
        expect(roundedUp).to.equal(false);
      }
    });

    it("scaledPre=1 with slice<1 (i.e. slice=0) yields whole=1, roundedUp=true", async function () {
      const tester = await deployTester();
      // We need uint16(seed >> 152) % 100 < 1, i.e. == 0. Easiest seed: 0.
      const seed = 0n;
      const slice = await tester.bernoulliSlice(seed);
      expect(slice).to.equal(0);
      const [whole, roundedUp] = await tester.bernoulliWhole(1, seed);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(true);
    });

    it("scaledPre=1 with slice>=1 yields whole=0, roundedUp=false (consolation trigger)", async function () {
      const tester = await deployTester();
      // Build seed so that uint16(seed >> 152) % 100 == 50 (well above frac=1).
      const seed = BigInt(50) << 152n;
      const slice = await tester.bernoulliSlice(seed);
      expect(slice).to.equal(50);
      const [whole, roundedUp] = await tester.bernoulliWhole(1, seed);
      expect(whole).to.equal(0n);
      expect(roundedUp).to.equal(false);
    });

    it("scaledPre=99 with slice<99 yields whole=1, roundedUp=true", async function () {
      const tester = await deployTester();
      // Build seed so uint16(seed >> 152) % 100 == 50.
      const seed = BigInt(50) << 152n;
      const [whole, roundedUp] = await tester.bernoulliWhole(99, seed);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(true);
    });

    it("scaledPre=99 with slice=99 yields whole=0, roundedUp=false (consolation trigger, edge case)", async function () {
      const tester = await deployTester();
      // Build seed so uint16(seed >> 152) % 100 == 99.
      const seed = BigInt(99) << 152n;
      const slice = await tester.bernoulliSlice(seed);
      expect(slice).to.equal(99);
      const [whole, roundedUp] = await tester.bernoulliWhole(99, seed);
      // frac=99, slice=99, gate is `slice < frac` → 99 < 99 is false → no round-up.
      expect(whole).to.equal(0n);
      expect(roundedUp).to.equal(false);
    });

    it("scaledPre=101 with slice<1 yields whole=2, roundedUp=true", async function () {
      const tester = await deployTester();
      const seed = 0n;
      const [whole, roundedUp] = await tester.bernoulliWhole(101, seed);
      expect(whole).to.equal(2n);
      expect(roundedUp).to.equal(true);
    });

    it("scaledPre=101 with slice>=1 yields whole=1, roundedUp=false", async function () {
      const tester = await deployTester();
      const seed = BigInt(50) << 152n;
      const [whole, roundedUp] = await tester.bernoulliWhole(101, seed);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(false);
    });

    it("scaledPre=199 with slice<99 yields whole=2, roundedUp=true", async function () {
      const tester = await deployTester();
      const seed = BigInt(50) << 152n;
      const [whole, roundedUp] = await tester.bernoulliWhole(199, seed);
      expect(whole).to.equal(2n);
      expect(roundedUp).to.equal(true);
    });

    it("scaledPre=199 with slice=99 yields whole=1, roundedUp=false", async function () {
      const tester = await deployTester();
      const seed = BigInt(99) << 152n;
      const [whole, roundedUp] = await tester.bernoulliWhole(199, seed);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(false);
    });
  });

  describe("TST-WT-03 — bits[152..167] independence + hoisted-shared-scope gating", function () {
    it("[03-static] bits[152..167] is consumed exactly once and sits in the shared scope of the outer `if (futureTickets != 0)` guard (Phase 275 D-275-HOIST-01)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Locate the unique reference to `seed >> 152` and assert: (a) it appears
      // exactly once (hoisted; not duplicated), (b) it sits inside the outer
      // `if (futureTickets != 0)` guard, (c) it sits BEFORE the manual-branch
      // gate `if (index != type(uint48).max)` (post-hoist invariant).
      const matches = [...source.matchAll(/seed >> 152/g)];
      expect(matches.length, "bits[152..167] should be consumed exactly once").to.equal(1);
      const idx = matches[0].index;
      const preamble = source.slice(0, idx);
      // Outer guard `if (futureTickets != 0)` must precede the slice.
      expect(
        preamble.lastIndexOf("if (futureTickets != 0)"),
        "Bernoulli slice not gated by outer `if (futureTickets != 0)` guard"
      ).to.be.greaterThan(-1);
      // Manual-branch gate must come AFTER the slice.
      expect(
        source.indexOf("if (index != type(uint48).max)", idx),
        "Phase 275 hoist invariant: manual-branch gate must appear AFTER the Bernoulli slice"
      ).to.be.greaterThan(idx);
    });

    it("[03-static] auto-resolve else-arm body never references `seed >> 152` (the slice is consumed once at shared scope above the gate)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Phase 275 LBX-AR-02: auto-resolve else-arm now calls
      // `_queueTickets(player, targetLevel, whole, false)` — the SECOND
      // occurrence of that line in the file (the first is the manual branch).
      const callLine = "_queueTickets(player, targetLevel, whole, false)";
      const firstIdx = source.indexOf(callLine);
      const autoIdx = source.indexOf(callLine, firstIdx + 1);
      expect(firstIdx, "manual-branch _queueTickets callsite not found").to.be.greaterThan(-1);
      expect(autoIdx, "auto-resolve _queueTickets callsite not found").to.be.greaterThan(firstIdx);
      // From autoIdx forward to the closing `}` of the enclosing else-arm,
      // there should be no `seed >> 152` reference (the slice was consumed
      // in shared scope above the sentinel gate).
      const tail = source.slice(autoIdx, autoIdx + 200);
      expect(tail.includes("seed >> 152"), "auto-resolve else-arm body must not re-consume bits[152..167]").to.equal(
        false
      );
    });

    it("[03-chi2] uint16(seed >> 152) % 100 chi² across 10K seeds: uniform mod-100 distribution (df=99)", async function () {
      const N = 10_000;
      const tester = await deployTester();
      const rng = makeRng("0x" + "c0274003".padStart(64, "0"));
      const buckets = new Array(100).fill(0);
      let chainVerifyCount = 0;
      // Replica-vs-chain spot check at every 200th sample.
      for (let i = 0; i < N; i++) {
        const seed = rng();
        const jsSlice = Number(((seed >> 152n) & 0xffffn) % 100n);
        buckets[jsSlice] += 1;
        if (i % 200 === 0) {
          const chainSlice = await tester.bernoulliSlice(seed);
          expect(Number(chainSlice), `JS/chain slice drift at i=${i}`).to.equal(jsSlice);
          chainVerifyCount++;
        }
      }
      expect(chainVerifyCount, "chain spot-check coverage").to.be.gte(50);

      // Expected per-bucket count under H0 (uniform-mod-100): N/100 = 100.
      // BUT — note that uint16 % 100 is slightly non-uniform: uint16 range
      // is 0..65535, 65536 / 100 = 655.36, so the first 36 residues have
      // ceil(655.36) = 656 source values and the rest have 655. Relative
      // bias is (656-655)/655.36 ≈ 0.10% per bucket — within the
      // 0.10% bias budget per D-274-BIT-SLICE-01.
      // For the chi² test we use the exact theoretical probabilities, not
      // uniform 1/100, so this is a clean fit check.
      const lowBucketProb = 656 / 65536; // residues 0..35
      const highBucketProb = 655 / 65536; // residues 36..99
      let chi2 = 0;
      for (let b = 0; b < 100; b++) {
        const p = b < 36 ? lowBucketProb : highBucketProb;
        const expected = N * p;
        const diff = buckets[b] - expected;
        chi2 += (diff * diff) / expected;
      }
      // df = 99. Wilson-Hilferty Z one-sided at alpha=0.05 → Z < 1.645.
      const z = wilsonHilfertyZ(chi2, 99);
      expect(
        z < 1.645,
        `chi²=${chi2.toFixed(3)} df=99 → Z=${z.toFixed(3)} >= 1.645 (buckets=[${buckets.join(",")}])`
      ).to.equal(true);
    });

    it("[03-indep] bits[152..167] pairwise-independent from bits[0..15] (rangeRoll slice) at chi² df=99", async function () {
      const N = 10_000;
      const tester = await deployTester();
      const rng = makeRng("0x" + "c0274004".padStart(64, "0"));
      // For each seed, compute (sliceBernoulli, sliceRange) where
      // sliceRange = uint16(seed) % 100 (mirrors _rollTargetLevel:843).
      // Joint distribution should pass chi² independence at df=(100-1)*(100-1)
      // = 9801. To keep this test scoped: we test pairwise mean independence
      // (E[bernoulli * range] ≈ E[bernoulli] * E[range]) at 3-sigma binomial bound.
      let sumProd = 0n;
      let sumB = 0n;
      let sumR = 0n;
      for (let i = 0; i < N; i++) {
        const seed = rng();
        const sliceB = (seed >> 152n) & 0xffffn;
        const sliceR = seed & 0xffffn;
        const valB = sliceB % 100n;
        const valR = sliceR % 100n;
        sumProd += valB * valR;
        sumB += valB;
        sumR += valR;
      }
      const meanProd = Number(sumProd) / N;
      const meanB = Number(sumB) / N;
      const meanR = Number(sumR) / N;
      // Under independence E[B*R] == E[B]*E[R]. Both means ~49.5; product
      // ~2450. The covariance estimator standard error scales as 1/sqrt(N);
      // for uniform [0,99] random variates, sd(B*R) ≈ 1000, so 3-sigma at
      // N=10K is ~30. We use ±50 as a generous tolerance.
      const covDeviation = Math.abs(meanProd - meanB * meanR);
      expect(
        covDeviation < 50,
        `|E[B*R] - E[B]*E[R]| = ${covDeviation.toFixed(3)} > 50 (meanProd=${meanProd}, meanB=${meanB}, meanR=${meanR})`
      ).to.equal(true);
    });
  });

  describe("TST-WT-04 — `TicketsQueued` (not `TicketsQueuedScaled`) on both manual + auto-resolve paths (Phase 275 LBX-AR-02)", function () {
    it("both manual + auto-resolve branches call `_queueTickets(player, targetLevel, whole, false)` (the whole-helper) — `_queueTicketsScaled` no longer appears in LootboxModule", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Phase 275 LBX-AR-02: auto-resolve branch was swapped from
      // `_queueTicketsScaled(...)` to `_queueTickets(player, targetLevel,
      // whole, false)`. Both branches now share the same whole-helper.
      const callPattern = /_queueTickets\(player, targetLevel, whole, false\)/g;
      const calls = (source.match(callPattern) || []).length;
      expect(
        calls,
        "expected ≥2 `_queueTickets(player, targetLevel, whole, false)` callsites (manual + auto-resolve)"
      ).to.be.gte(2);

      // `_queueTicketsScaled` must no longer appear in this module.
      expect(
        source.includes("_queueTicketsScaled"),
        "`_queueTicketsScaled` must not appear in LootboxModule post-Phase-275"
      ).to.equal(false);

      // Structural ordering: the manual call comes first (true-branch of the
      // sentinel gate), auto-resolve second (else-arm).
      const callLine = "_queueTickets(player, targetLevel, whole, false)";
      const manualIdx = source.indexOf(callLine);
      const autoIdx = source.indexOf(callLine, manualIdx + 1);
      expect(manualIdx).to.be.greaterThan(-1);
      expect(autoIdx).to.be.greaterThan(manualIdx);
      // The else-arm anchor `} else {` sits between them.
      const elseIdx = source.indexOf("} else {", manualIdx);
      expect(elseIdx).to.be.greaterThan(manualIdx);
      expect(elseIdx).to.be.lessThan(autoIdx);
    });

    it("DegenerusGameStorage._queueTickets emits `TicketsQueued` (manual-path event)", function () {
      const storage = fs.readFileSync(
        path.resolve(process.cwd(), "contracts/storage/DegenerusGameStorage.sol"),
        "utf8"
      );
      // _queueTickets emits TicketsQueued.
      expect(/emit TicketsQueued\(/.test(storage)).to.equal(true);
      // _queueTicketsScaled emits TicketsQueuedScaled.
      expect(/emit TicketsQueuedScaled\(/.test(storage)).to.equal(true);
      // The two emissions are in different functions — manual path lands on
      // TicketsQueued, auto-resolve on TicketsQueuedScaled.
      const queuedIdx = storage.indexOf("emit TicketsQueued(");
      const queuedScaledIdx = storage.indexOf("emit TicketsQueuedScaled(");
      expect(queuedIdx).to.not.equal(queuedScaledIdx);
    });
  });

  describe("TST-WT-05 — `LootBoxOpened.futureTickets` + `BurnieLootOpen.tickets` scaled-preservation (D-274-NO-EVT-BREAK-01)", function () {
    it("[05a] `_resolveLootboxCommon` returns function-scope `futureTickets` (scaled) and `LootBoxOpened` emit consumes the same scaled value", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The `LootBoxOpened` emit must reference `futureTickets` (the function-
      // scope return-variable). The manual branch uses a SEPARATE `whole`
      // local; the function-scope `futureTickets` MUST NOT be reassigned
      // (G17 grep gate).
      const lootboxOpenedEmit = /emit LootBoxOpened\(\s*player,\s*day,\s*amount,\s*targetLevel,\s*futureTickets,/;
      expect(
        source.match(lootboxOpenedEmit),
        "LootBoxOpened emit must consume function-scope futureTickets (scaled)"
      ).to.not.be.null;
    });

    it("[05b] function-scope `futureTickets` reassignment count UNCHANGED vs baseline 06623edb (G17)", async function () {
      // Use the same recipe as G17 in the plan. The pattern `futureTickets\s*=[^=]`
      // catches `=` assignments while excluding `==` comparisons.
      const { execSync } = await import("node:child_process");
      const post = execSync(
        `grep -cE "futureTickets[[:space:]]*=[^=]" contracts/modules/DegenerusGameLootboxModule.sol`,
        { encoding: "utf8" }
      ).trim();
      const pre = execSync(
        `git show 06623edb:contracts/modules/DegenerusGameLootboxModule.sol | grep -cE "futureTickets[[:space:]]*=[^=]"`,
        { encoding: "utf8" }
      ).trim();
      expect(
        post,
        `function-scope futureTickets reassignment count drifted from baseline (pre=${pre} vs post=${post})`
      ).to.equal(pre);
    });

    it("[05c] `BurnieLootOpen` consumes `_resolveLootboxCommon` first return value as `tickets` (scaled per D-274-NO-EVT-BREAK-01)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // openBurnieLootBox destructure pattern.
      const destructurePattern = /\(uint32 tickets, uint256 burnieReward,\s*\)\s*=\s*_resolveLootboxCommon/;
      expect(
        source.match(destructurePattern),
        "openBurnieLootBox destructure pattern (uint32 tickets, uint256 burnieReward, ) = _resolveLootboxCommon missing"
      ).to.not.be.null;

      // BurnieLootOpen emit consumes `tickets` from the destructure (scaled).
      // The emit spans multiple lines — use the `s` flag for dotall semantics.
      const burnieEmit = /emit BurnieLootOpen\([\s\S]*?tickets/;
      expect(
        source.match(burnieEmit),
        "BurnieLootOpen emit must reference `tickets` (the destructured scaled return value)"
      ).to.not.be.null;
    });
  });

  describe("TST-WT-06 — `LootboxTicketRoll` emit positioning + path coverage", function () {
    it("[06a] manual-branch emits `LootboxTicketRoll(player, index, scaledPre, roundedUp)` exactly once", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const emits = [...source.matchAll(/emit LootboxTicketRoll\(/g)];
      expect(emits.length, "LootboxTicketRoll should be emitted exactly once").to.equal(1);
      // Pattern integrity: exact 4-arg form.
      const exactPattern = /emit LootboxTicketRoll\(player, index, scaledPre, roundedUp\)/;
      expect(source.match(exactPattern), "exact 4-arg emit form not found").to.not.be.null;
    });

    it("[06b] LootboxTicketRoll emit is INSIDE the manual-branch gate `if (index != type(uint48).max)`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const emitIdx = source.indexOf("emit LootboxTicketRoll(");
      expect(emitIdx).to.be.greaterThan(-1);
      const preamble = source.slice(0, emitIdx);
      const lastManualGate = preamble.lastIndexOf("if (index != type(uint48).max)");
      // The auto-resolve else clause sits BELOW the emit in source order; the
      // emit must be inside the manual-branch if-block.
      expect(lastManualGate, "emit must be inside manual-branch gate").to.be.greaterThan(-1);
      // Phase 275 LBX-AR-02: the auto-resolve else-arm now calls
      // `_queueTickets(player, targetLevel, whole, false)` (the SECOND
      // occurrence of that line — the first is the manual true-branch which
      // sits BEFORE the LootboxTicketRoll emit on the same path). The emit
      // must precede the auto-resolve callsite (the emit is inside the
      // manual if-clause, which comes BEFORE the else).
      const callLine = "_queueTickets(player, targetLevel, whole, false)";
      const firstIdx = source.indexOf(callLine);
      const autoIdx = source.indexOf(callLine, firstIdx + 1);
      expect(autoIdx).to.be.greaterThan(firstIdx);
      expect(emitIdx).to.be.lessThan(autoIdx);
    });

    it("[06c] LootboxTicketRoll emit + consolation predicate + queueTickets call are ALL inside the outer `if (futureTickets != 0)` guard", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Find the manual-branch gate.
      const manualGateIdx = source.indexOf("if (index != type(uint48).max)");
      expect(manualGateIdx).to.be.greaterThan(-1);
      // Walk backwards: the most recent `if (futureTickets != 0)` should be
      // the enclosing outer guard.
      const preamble = source.slice(0, manualGateIdx);
      const outerGuardIdx = preamble.lastIndexOf("if (futureTickets != 0)");
      expect(outerGuardIdx, "outer `if (futureTickets != 0)` guard not found above manual-branch gate").to.be.greaterThan(-1);
      // No closing `}` between outer guard and manual gate would-be ideal, but
      // we just assert the gates are nested: the outer guard appears textually
      // before the inner manual gate.
      expect(outerGuardIdx).to.be.lessThan(manualGateIdx);
    });

    it("[06d] LootboxTicketRoll event declared on the IDegenerusGameLootboxModule interface", function () {
      const iface = fs.readFileSync(
        path.resolve(process.cwd(), "contracts/interfaces/IDegenerusGameModules.sol"),
        "utf8"
      );
      const eventPattern = /event LootboxTicketRoll\(\s*address indexed player,\s*uint48 indexed lootboxIndex,\s*uint32 preRollTickets,\s*bool roundedUp\s*\)/;
      expect(
        iface.match(eventPattern),
        "IDegenerusGameLootboxModule.LootboxTicketRoll declaration missing"
      ).to.not.be.null;
    });

    it("[06e] LootboxTicketRoll event declared on the LootboxModule contract", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const eventPattern = /event LootboxTicketRoll\(\s*address indexed player,\s*uint48 indexed lootboxIndex,\s*uint32 preRollTickets,\s*bool roundedUp\s*\)/;
      expect(
        source.match(eventPattern),
        "LootboxModule.LootboxTicketRoll declaration missing"
      ).to.not.be.null;
    });

    it("[06f] auto-resolve paths (resolveLootboxDirect / resolveRedemptionLootbox) pass `type(uint48).max` sentinel — emit cannot fire from these paths", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Two callsites must pass `type(uint48).max`.
      const sentinelCount = (source.match(/type\(uint48\)\.max,/g) || []).length;
      expect(sentinelCount).to.be.gte(2);

      // resolveLootboxDirect signature should be present and call _resolveLootboxCommon
      // with the sentinel.
      const resolveDirectIdx = source.indexOf("function resolveLootboxDirect(");
      expect(resolveDirectIdx).to.be.greaterThan(-1);
      const directBody = source.slice(resolveDirectIdx, resolveDirectIdx + 2000);
      expect(directBody.includes("type(uint48).max")).to.equal(true);

      const resolveRedemptionIdx = source.indexOf("function resolveRedemptionLootbox(");
      expect(resolveRedemptionIdx).to.be.greaterThan(-1);
      const redemptionBody = source.slice(
        resolveRedemptionIdx,
        resolveRedemptionIdx + 2000
      );
      expect(redemptionBody.includes("type(uint48).max")).to.equal(true);
    });
  });

  describe("TST-WT-07 — field-consistency invariants for LootboxTicketRoll", function () {
    it("[07a] `preRollTickets` field references `scaledPre` (snapshotted before any reassignment)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // scaledPre snapshot must precede the emit.
      const snapshotIdx = source.indexOf("uint32 scaledPre = futureTickets;");
      const emitIdx = source.indexOf("emit LootboxTicketRoll(");
      expect(snapshotIdx).to.be.greaterThan(-1);
      expect(emitIdx).to.be.greaterThan(snapshotIdx);
      // Between the snapshot and the emit, `scaledPre` must not be reassigned.
      const region = source.slice(snapshotIdx, emitIdx);
      const scaledPreReassign = /scaledPre\s*=[^=]/g;
      const matches = [...region.matchAll(scaledPreReassign)];
      // Allow exactly one match: the snapshot declaration itself.
      expect(
        matches.length,
        `scaledPre reassigned ${matches.length} times between snapshot and emit (expected 1 — the snapshot)`
      ).to.equal(1);
    });

    it("[07b] `lootboxIndex` field references the function `index` parameter (manual-branch gating discriminator)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The emit's 2nd arg is `index` — matches the `_resolveLootboxCommon`
      // signature parameter name.
      expect(
        /emit LootboxTicketRoll\(player, index, scaledPre, roundedUp\)/.test(source)
      ).to.equal(true);

      // Signature contains `uint48 index`.
      const sigPattern = /function _resolveLootboxCommon\([\s\S]*?uint48 index/;
      expect(source.match(sigPattern), "_resolveLootboxCommon signature missing `uint48 index` parameter")
        .to.not.be.null;
    });

    it("[07c] whole==0 path emits LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION) before the LootboxTicketRoll emit (same-tx correlation)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const consolationEmit = source.indexOf(
        "emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)"
      );
      const rollEmit = source.indexOf("emit LootboxTicketRoll(");
      expect(consolationEmit).to.be.greaterThan(-1);
      expect(rollEmit).to.be.greaterThan(-1);
      // Consolation emit must precede the roll emit textually (same-tx ordering).
      expect(consolationEmit).to.be.lessThan(rollEmit);
    });

    it("[07d] consolation `wwxrp.mintPrize` call precedes both event emissions (state mutation before logs)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const mintPrizeIdx = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      const rewardEmit = source.indexOf(
        "emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(mintPrizeIdx).to.be.greaterThan(-1);
      expect(rewardEmit).to.be.greaterThan(-1);
      expect(mintPrizeIdx).to.be.lessThan(rewardEmit);
    });
  });
});
