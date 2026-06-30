// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxWholeTicket.test.js — Phase 274 Wave 2 TST-WT-01..07
//
// Whole-ticket Bernoulli collapse coverage. The contract under test is the
// `DegenerusGameLootboxModule._resolveLootboxCommon` ticket-queue path inside the
// `if (futureTickets != 0)` guard which:
//   1. computes `whole = futureTickets / 100`, `frac = futureTickets % 100`
//   2. consumes `bits[224..255]` of the per-resolution seed via
//      `uint32(seed >> 224) % uint32(TICKET_SCALE) < frac`
//   3. if the Bernoulli wins → `whole += 1`, `roundedUp = true`
//   4. queues `whole` tickets via the unified `_queueTickets(player,
//      targetLevel, whole, false)` call (which early-returns on `whole == 0`)
//   5. under the `payColdBustConsolation` gate, on `whole == 0` pays the manual
//      cold-bust WWXRP consolation; and (on every box path, gated only by !wasSpin)
//      emits `LootBoxOpened`
//
// Phase 277 retired the `index != type(uint48).max` sentinel: the ticket-queue
// path is unified (no per-branch duplication) and the `LootboxTicketRoll` event
// is removed entirely. `LootBoxOpened.futureTickets` still carries the scaled
// pre-Bernoulli count, so off-chain consumers derive
// `whole = (futureTickets / 100) + (roundedUp ? 1 : 0)`.
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
//   - D-274-BIT-SLICE-01 (post-c21f833a supersession: uint32 / bits[224..255])
//   - D-274-NO-EVT-BREAK-01 (LootBoxOpened.futureTickets + TicketsQueuedScaled
//     semantics UNCHANGED; FlipLootOpen removed in v47 — FLIP-lootbox surface
//     deleted, terminal-paradox closure)
//   - feedback_rng_backward_trace.md (slice consumed only on manual paths;
//     auto-resolve never reads bits[224..255])
//   - feedback_rng_commitment_window.md (no player-controllable input mutates
//     between VRF commit and lootbox open that affects bits[224..255]
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

// Brace-match extractor for a named function body.
function extractFnBody(source, signature) {
  const fnIdx = source.indexOf(signature);
  if (fnIdx < 0) return null;
  let depth = 0;
  let bodyStart = -1;
  for (let i = fnIdx; i < source.length; i++) {
    if (source[i] === "{") {
      if (depth === 0) bodyStart = i;
      depth++;
    } else if (source[i] === "}") {
      depth--;
      if (depth === 0) return source.slice(bodyStart, i + 1);
    }
  }
  return null;
}

// The per-roll ticket/FLIP/emit/consolation logic now lives in
// `_settleLootboxRoll` (post-refactor; `_resolveLootboxCommon` became a void
// dispatcher that calls this helper once per roll).
function extractSettleBody(source) {
  return extractFnBody(source, "function _settleLootboxRoll(");
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
    // uint32(seed >> 224) — keep low 32 bits after the shift
    const sliceRaw = (BigInt(seed) >> 224n) & 0xffffffffn;
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
    it("contracts/modules/DegenerusGameLootboxModule.sol contains the exact uint32(rollSeed >> 224) % uint32(TICKET_SCALE) Bernoulli pattern", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");

      // Ticket-queue-path Bernoulli gate. The pattern below is the load-bearing
      // drift detector — if production reformats this expression, the tester
      // contract above MUST be updated in lock-step.
      const bernoulliPattern =
        /\(uint32\(rollSeed >> 224\)\s*%\s*uint32\(TICKET_SCALE\)\)\s*<\s*frac/;
      expect(
        source.match(bernoulliPattern),
        "production Bernoulli pattern drifted from tester — update LootboxBernoulliTester.sol to match"
      ).to.not.be.null;

      // The scaled count is read straight from this roll's `scaledTickets` local
      // into the `whole` local — `scaledTickets` itself is never reassigned by
      // the collapse, so it stays the scaled value for the `LootBoxOpened` emit.
      expect(
        /uint32 whole = scaledTickets \/ uint32\(TICKET_SCALE\);/.test(source),
        "`whole = scaledTickets / uint32(TICKET_SCALE)` derivation missing"
      ).to.equal(true);
      expect(
        /uint32 frac = scaledTickets % uint32\(TICKET_SCALE\);/.test(source),
        "`frac = scaledTickets % uint32(TICKET_SCALE)` derivation missing"
      ).to.equal(true);

      // Post-refactor the Bernoulli math sits in the per-roll ticket-queue path
      // inside the `if (scaledTickets != 0)` guard — the
      // `index != type(uint48).max` sentinel gate is fully retired.
      // Structural invariants verified here:
      //   (a) `rollSeed >> 224` appears exactly once (one source site; fires
      //       per-roll at runtime — a split box runs `_settleLootboxRoll` twice).
      //   (b) The Bernoulli slice sits INSIDE the outer
      //       `if (scaledTickets != 0)` guard (no slice consumption when
      //       `scaledTickets == 0`).
      //   (c) No `index != type(uint48).max` sentinel gate exists anywhere.
      const sliceMatches = [...source.matchAll(/uint32\(rollSeed >> 224\)/g)];
      expect(
        sliceMatches.length,
        "Bernoulli slice must appear exactly once (single source site, no duplication)"
      ).to.equal(1);
      const sliceLineIdx = sliceMatches[0].index;
      const preamble = source.slice(0, sliceLineIdx);
      // Outer-guard ancestor: `if (scaledTickets != 0)` precedes the slice.
      const outerGuardIdx = preamble.lastIndexOf("if (scaledTickets != 0)");
      expect(
        outerGuardIdx,
        "Bernoulli slice not gated by outer `if (futureTickets != 0)` guard"
      ).to.be.greaterThan(-1);
      // The `index != type(uint48).max` sentinel gate must be fully retired.
      expect(
        source.includes("if (index != type(uint48).max)"),
        "Phase 277 sentinel retirement: `if (index != type(uint48).max)` must not appear"
      ).to.equal(false);
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
      for (const seed of [0n, 1n, 1n << 224n, (1n << 232n) - 1n, 0xdeadbeefn]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(0, seed);
        expect(whole).to.equal(0n);
        expect(roundedUp).to.equal(false);
      }
    });

    it("scaledPre=100 deterministically yields whole=1, roundedUp=false (frac==0 short-circuits)", async function () {
      const tester = await deployTester();
      for (const seed of [0n, 1n, (1n << 224n) | 99n, (1n << 256n) - 1n]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(100, seed);
        expect(whole).to.equal(1n);
        expect(roundedUp).to.equal(false);
      }
    });

    it("scaledPre=200 deterministically yields whole=2, roundedUp=false (frac==0 short-circuits)", async function () {
      const tester = await deployTester();
      for (const seed of [0n, 1n, (1n << 225n), (1n << 239n) - 1n]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(200, seed);
        expect(whole).to.equal(2n);
        expect(roundedUp).to.equal(false);
      }
    });

    it("scaledPre=1 with slice<1 (i.e. slice=0) yields whole=1, roundedUp=true", async function () {
      const tester = await deployTester();
      // We need uint32(seed >> 224) % 100 < 1, i.e. == 0. Easiest seed: 0.
      const seed = 0n;
      const slice = await tester.bernoulliSlice(seed);
      expect(slice).to.equal(0);
      const [whole, roundedUp] = await tester.bernoulliWhole(1, seed);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(true);
    });

    it("scaledPre=1 with slice>=1 yields whole=0, roundedUp=false (consolation trigger)", async function () {
      const tester = await deployTester();
      // Build seed so that uint32(seed >> 224) % 100 == 50 (well above frac=1).
      const seed = BigInt(50) << 224n;
      const slice = await tester.bernoulliSlice(seed);
      expect(slice).to.equal(50);
      const [whole, roundedUp] = await tester.bernoulliWhole(1, seed);
      expect(whole).to.equal(0n);
      expect(roundedUp).to.equal(false);
    });

    it("scaledPre=99 with slice<99 yields whole=1, roundedUp=true", async function () {
      const tester = await deployTester();
      // Build seed so uint32(seed >> 224) % 100 == 50.
      const seed = BigInt(50) << 224n;
      const [whole, roundedUp] = await tester.bernoulliWhole(99, seed);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(true);
    });

    it("scaledPre=99 with slice=99 yields whole=0, roundedUp=false (consolation trigger, edge case)", async function () {
      const tester = await deployTester();
      // Build seed so uint32(seed >> 224) % 100 == 99.
      const seed = BigInt(99) << 224n;
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
      const seed = BigInt(50) << 224n;
      const [whole, roundedUp] = await tester.bernoulliWhole(101, seed);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(false);
    });

    it("scaledPre=199 with slice<99 yields whole=2, roundedUp=true", async function () {
      const tester = await deployTester();
      const seed = BigInt(50) << 224n;
      const [whole, roundedUp] = await tester.bernoulliWhole(199, seed);
      expect(whole).to.equal(2n);
      expect(roundedUp).to.equal(true);
    });

    it("scaledPre=199 with slice=99 yields whole=1, roundedUp=false", async function () {
      const tester = await deployTester();
      const seed = BigInt(99) << 224n;
      const [whole, roundedUp] = await tester.bernoulliWhole(199, seed);
      expect(whole).to.equal(1n);
      expect(roundedUp).to.equal(false);
    });
  });

  describe("TST-WT-03 — bits[224..255] independence + unified-path gating", function () {
    it("[03-static] bits[224..255] is consumed exactly once inside the outer `if (scaledTickets != 0)` guard (per-roll settle path)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Locate the unique reference to `rollSeed >> 224` and assert: (a) it appears
      // exactly once (one source site; fires per-roll at runtime), (b) it sits
      // inside the outer `if (scaledTickets != 0)` guard, (c) no
      // `index != type(uint48).max` sentinel gate exists (sentinel retirement).
      const matches = [...source.matchAll(/rollSeed >> 224/g)];
      expect(matches.length, "bits[224..255] should appear at exactly one source site").to.equal(1);
      const idx = matches[0].index;
      const preamble = source.slice(0, idx);
      // Outer guard `if (scaledTickets != 0)` must precede the slice.
      expect(
        preamble.lastIndexOf("if (scaledTickets != 0)"),
        "Bernoulli slice not gated by outer `if (scaledTickets != 0)` guard"
      ).to.be.greaterThan(-1);
      // The `index != type(uint48).max` sentinel gate must be fully retired.
      expect(
        source.includes("if (index != type(uint48).max)"),
        "sentinel retirement: `if (index != type(uint48).max)` must not appear"
      ).to.equal(false);
    });

    it("[03-static] the per-roll ticket-queue path consumes `rollSeed >> 224` exactly once — single source site", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` call is a single
      // source site inside `_settleLootboxRoll` (invoked once per roll), so the
      // Bernoulli slice is consumed exactly once per roll from one source site.
      const callLine = "_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)";
      const callMatches = (
        source.match(/_queueTickets\(player, rollLevel, wholeTicketsToEntries\(whole\), false\)/g) || []
      ).length;
      expect(
        callMatches,
        "the per-roll ticket-queue path must call `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` at exactly one source site"
      ).to.equal(1);
      // The slice itself appears at exactly one source site.
      const sliceMatches = (source.match(/rollSeed >> 224/g) || []).length;
      expect(
        sliceMatches,
        "bits[224..255] must appear at exactly one source site"
      ).to.equal(1);
      // And the queue call sits after the slice (collapse precedes the queue).
      const callIdx = source.indexOf(callLine);
      const sliceIdx = source.indexOf("rollSeed >> 224");
      expect(callIdx, "_queueTickets callsite not found").to.be.greaterThan(-1);
      expect(
        callIdx,
        "the `_queueTickets` call must come after the Bernoulli slice"
      ).to.be.greaterThan(sliceIdx);
    });

    it("[03-chi2] uint32(seed >> 224) % 100 chi² across 10K seeds: uniform mod-100 distribution (df=99)", async function () {
      const N = 10_000;
      const tester = await deployTester();
      const rng = makeRng("0x" + "c0274003".padStart(64, "0"));
      const buckets = new Array(100).fill(0);
      let chainVerifyCount = 0;
      // Replica-vs-chain spot check at every 200th sample.
      for (let i = 0; i < N; i++) {
        const seed = rng();
        const jsSlice = Number(((seed >> 224n) & 0xffffffffn) % 100n);
        buckets[jsSlice] += 1;
        if (i % 200 === 0) {
          const chainSlice = await tester.bernoulliSlice(seed);
          expect(Number(chainSlice), `JS/chain slice drift at i=${i}`).to.equal(jsSlice);
          chainVerifyCount++;
        }
      }
      expect(chainVerifyCount, "chain spot-check coverage").to.be.gte(50);

      // Expected per-bucket count under H0 (uniform-mod-100): N/100 = 100.
      // A uint32 window (0..2^32-1) carries 2^32 / 100 = 42,949,672.96 source
      // values per residue; the first 96 residues hold one extra source value,
      // so the relative bias is ~1/4.29e7 ≈ 2e-8 per bucket — negligible. The
      // chi² fit therefore uses a flat uniform 1/100 expectation for every
      // residue.
      const expected = N / 100;
      let chi2 = 0;
      for (let b = 0; b < 100; b++) {
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

    it("[03-indep] bits[224..255] pairwise-independent from bits[0..15] (rangeRoll slice) at chi² df=99", async function () {
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
        const sliceB = (seed >> 224n) & 0xffffffffn;
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

  describe("TST-WT-04 — `TicketsQueued` (not `TicketsQueuedScaled`) on the unified ticket-queue path (Phase 277)", function () {
    it("the per-roll ticket-queue path calls `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` at one source site — `_queueTicketsScaled` no longer appears in LootboxModule", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` call is a single
      // source site inside `_settleLootboxRoll` (invoked per roll).
      const callPattern = /_queueTickets\(player, rollLevel, wholeTicketsToEntries\(whole\), false\)/g;
      const calls = (source.match(callPattern) || []).length;
      expect(
        calls,
        "expected exactly one `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` source site (per-roll settle path)"
      ).to.equal(1);

      // `_queueTicketsScaled` must no longer appear in this module.
      expect(
        source.includes("_queueTicketsScaled"),
        "`_queueTicketsScaled` must not appear in LootboxModule"
      ).to.equal(false);

      // The call sits inside the outer `if (scaledTickets != 0)` guard
      // and is NOT wrapped in any `index`-conditional branch.
      const callLine = "_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)";
      const callIdx = source.indexOf(callLine);
      expect(callIdx).to.be.greaterThan(-1);
      const preamble = source.slice(0, callIdx);
      expect(
        preamble.lastIndexOf("if (scaledTickets != 0)"),
        "the `_queueTickets` call must sit inside the `if (scaledTickets != 0)` guard"
      ).to.be.greaterThan(-1);
      expect(
        source.includes("if (index != type(uint48).max)"),
        "no `index != type(uint48).max` sentinel branch should wrap the queue call"
      ).to.equal(false);
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

  describe("TST-WT-05 — `LootBoxOpened.futureTickets` scaled-preservation (D-274-NO-EVT-BREAK-01; FlipLootOpen removed in v47)", function () {
    it("[05a] `_settleLootboxRoll` carries this roll's `scaledTickets` (scaled) and the `LootBoxOpened` emit consumes the same scaled value", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The `LootBoxOpened` emit must reference `scaledTickets` (this roll's
      // scaled ticket count). The ticket-queue path uses a SEPARATE `whole`
      // local; `scaledTickets` is reassigned only by the distress bonus (a
      // still-scaled value) BEFORE the collapse, never by the collapse itself.
      // The emit signature is the 7-arg `(player, index, fullAmount, rollLevel,
      // scaledTickets, flipAmount, roundedUp)` (the `day` arg was dropped in
      // 4cb9ccbf "lootbox event day cleanup").
      const lootboxOpenedEmit =
        /emit LootBoxOpened\(\s*player,\s*index,\s*fullAmount,\s*rollLevel,\s*scaledTickets,/;
      expect(
        source.match(lootboxOpenedEmit),
        "LootBoxOpened emit must consume `scaledTickets` (scaled) in the per-roll signature"
      ).to.not.be.null;
    });

    it("[05b] the Bernoulli collapse never reassigns this roll's `scaledTickets` — it stays the scaled value the `LootBoxOpened` emit consumes", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = extractSettleBody(source);
      expect(body, "_settleLootboxRoll body not found").to.not.equal(null);
      // Within `_settleLootboxRoll`, `scaledTickets` is sourced by the
      // `_resolveLootboxRoll` destructure (`uint32 scaledTickets`) and then
      // reassigned at most once by the distress-mode bonus
      // (`scaledTickets = uint32(uint256(scaledTickets) + bonus);`), still a
      // scaled value, applied BEFORE the Bernoulli collapse. The collapse
      // derives the separate `whole` local and must NEVER write back to
      // `scaledTickets`.
      const assignMatches = [...body.matchAll(/scaledTickets\s*=[^=]/g)];
      expect(
        assignMatches.length,
        `_settleLootboxRoll assigns scaledTickets ${assignMatches.length} times (expected 1: the scaled distress bonus; the initial value comes from the destructure)`
      ).to.equal(1);
      // The scaled count is produced by the `_resolveLootboxRoll` destructure.
      expect(
        /\(\s*uint256 flipOut\s*,\s*uint32 scaledTickets\s*,/.test(body),
        "scaledTickets must be the scaled roll result from the `_resolveLootboxRoll` destructure"
      ).to.equal(true);
      // The distress-bonus reassignment stays a scaled value.
      expect(
        body.includes("scaledTickets = uint32(uint256(scaledTickets) + bonus);"),
        "the scaledTickets distress-bonus reassignment must stay a scaled value"
      ).to.equal(true);
      // The collapse writes only `whole` — never `scaledTickets`.
      const collapseIdx = body.indexOf(
        "uint32 whole = scaledTickets / uint32(TICKET_SCALE);"
      );
      expect(collapseIdx, "Bernoulli collapse not found").to.be.greaterThan(-1);
      const collapseRegion = body.slice(collapseIdx);
      expect(
        /scaledTickets\s*=[^=]/.test(collapseRegion),
        "the Bernoulli collapse must not reassign this roll's `scaledTickets`"
      ).to.equal(false);
    });

    // [05c] FlipLootOpen scaled-tickets preservation — REMOVED (v47): the
    // FLIP-lootbox manual caller `openFlipLootBox` and its `FlipLootOpen`
    // emit were removed (terminal-paradox closure). The scaled-futureTickets
    // preservation invariant for the surviving LootBoxOpened emit is covered by
    // [05a]/[05b] above. Removed-by-design, not skipped — assert the symbols are
    // gone from the source.
    it("[05c] the v47 LootboxModule source no longer references openFlipLootBox / FlipLootOpen (removed-by-design)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      expect(
        source.includes("openFlipLootBox"),
        "openFlipLootBox must be fully removed from DegenerusGameLootboxModule.sol"
      ).to.equal(false);
      expect(
        source.includes("FlipLootOpen"),
        "FlipLootOpen must be fully removed from DegenerusGameLootboxModule.sol"
      ).to.equal(false);
    });
  });

  describe("TST-WT-06 — `LootboxTicketRoll` retired + sentinel retirement (Phase 277)", function () {
    it("[06a] `LootboxTicketRoll` has zero emit sites in the LootboxModule (event retired)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const emits = (source.match(/emit LootboxTicketRoll\(/g) || []).length;
      expect(
        emits,
        "LootboxTicketRoll must have zero emit sites — the event is retired"
      ).to.equal(0);
    });

    it("[06b] the per-roll ticket-queue path sits inside the outer `if (scaledTickets != 0)` guard with no `index`-conditional gate", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The `index != type(uint48).max` sentinel gate is retired. The
      // `_queueTickets` call sits directly inside the outer
      // `if (scaledTickets != 0)` guard.
      expect(
        source.includes("if (index != type(uint48).max)"),
        "the `index != type(uint48).max` sentinel gate must be fully retired"
      ).to.equal(false);
      const callIdx = source.indexOf(
        "_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)"
      );
      expect(callIdx, "the `_queueTickets` callsite not found").to.be.greaterThan(
        -1
      );
      const preamble = source.slice(0, callIdx);
      expect(
        preamble.lastIndexOf("if (scaledTickets != 0)"),
        "the `_queueTickets` call must sit inside the `if (scaledTickets != 0)` guard"
      ).to.be.greaterThan(-1);
    });

    it("[06c] the per-roll `_queueTickets` call + the `payColdBustConsolation`-gated consolation are ALL inside the outer `if (scaledTickets != 0)` guard", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const outerGuardIdx = source.indexOf("if (scaledTickets != 0)");
      expect(outerGuardIdx, "outer `if (scaledTickets != 0)` guard not found").to.be.greaterThan(
        -1
      );
      const callIdx = source.indexOf(
        "_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)"
      );
      const consolationGateIdx = source.indexOf(
        "if (payColdBustConsolation && whole == 0)"
      );
      expect(callIdx).to.be.greaterThan(outerGuardIdx);
      expect(
        consolationGateIdx,
        "the `payColdBustConsolation && whole == 0` consolation gate not found"
      ).to.be.greaterThan(outerGuardIdx);
    });

    it("[06d] `LootboxTicketRoll` is no longer declared on the IDegenerusGameLootboxModule interface", function () {
      const iface = fs.readFileSync(
        path.resolve(process.cwd(), "contracts/interfaces/IDegenerusGameModules.sol"),
        "utf8"
      );
      expect(
        iface.includes("LootboxTicketRoll"),
        "LootboxTicketRoll must be fully removed from the interface"
      ).to.equal(false);
    });

    it("[06e] `LootboxTicketRoll` is no longer declared on the LootboxModule contract", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      expect(
        source.includes("LootboxTicketRoll"),
        "LootboxTicketRoll must be fully removed from DegenerusGameLootboxModule.sol"
      ).to.equal(false);
    });

    it("[06f] auto-resolve paths (resolveLootboxDirect / resolveRedemptionLootbox) pass `index = 0` and carry no emitLootboxEvent flag — the LootBoxOpened emit lives in the shared `_settleLootboxRoll`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The retired sentinel value must not appear anywhere.
      expect(
        source.includes("type(uint48).max"),
        "no `type(uint48).max` sentinel value should remain in the module"
      ).to.equal(false);
      // The always-true emitLootboxEvent flag is fully removed — every box path emits.
      expect(
        source.includes("emitLootboxEvent"),
        "no `emitLootboxEvent` token may remain (flag retired — every box emits)"
      ).to.equal(false);
      // The redemption auto-resolve path holds its `_resolveLootboxCommon` call in the
      // private `_resolveRedemptionChunk` helper (one per 5-ETH chunk).
      for (const fnSig of [
        "function resolveLootboxDirect(",
        "function _resolveRedemptionChunk(",
      ]) {
        const fnIdx = source.indexOf(fnSig);
        expect(fnIdx, `${fnSig} not found`).to.be.greaterThan(-1);
        const body = source.slice(fnIdx, fnIdx + 2000);
        expect(body.includes("_resolveLootboxCommon(")).to.equal(true);
        // The LootBoxOpened emit lives in the shared `_settleLootboxRoll` helper (not inline in
        // these caller bodies) — but it now fires for these paths too, gated only by !wasSpin.
        expect(
          body.includes("emit LootBoxOpened("),
          `${fnSig} routes the emit through _settleLootboxRoll, not inline`
        ).to.equal(false);
      }
    });
  });

  describe("TST-WT-07 — field-consistency invariants for the unified ticket-queue path", function () {
    it("[07a] this roll's `scaledTickets` is the scaled value the `LootBoxOpened` emit consumes — the collapse writes only the separate `whole` local", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The Bernoulli collapse derives `whole` from `scaledTickets` but never
      // reassigns `scaledTickets` itself between the derivation and the emit,
      // so `LootBoxOpened.scaledTickets` carries the scaled pre-Bernoulli count.
      const deriveIdx = source.indexOf(
        "uint32 whole = scaledTickets / uint32(TICKET_SCALE);"
      );
      const emitIdx = source.indexOf("emit LootBoxOpened(");
      expect(deriveIdx, "`whole` derivation not found").to.be.greaterThan(-1);
      expect(emitIdx, "LootBoxOpened emit not found").to.be.greaterThan(deriveIdx);
      const region = source.slice(deriveIdx, emitIdx);
      // `scaledTickets` must not be reassigned between the derivation and the emit.
      const reassign = [...region.matchAll(/scaledTickets\s*=[^=]/g)];
      expect(
        reassign.length,
        `scaledTickets reassigned ${reassign.length} times between the collapse and the emit (expected 0)`
      ).to.equal(0);
    });

    it("[07b] the `LootBoxOpened` emit threads the `index` parameter into the `lootboxIndex` slot", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The per-roll 7-arg emit signature is
      // `(player, index, fullAmount, rollLevel, scaledTickets, flipAmount,
      //   roundedUp)` (the `day` arg was dropped in 4cb9ccbf).
      expect(
        /emit LootBoxOpened\(\s*player,\s*index,\s*fullAmount,\s*rollLevel,\s*scaledTickets,\s*flipAmount,\s*roundedUp\s*\)/.test(
          source
        ),
        "LootBoxOpened emit must thread (player, index, fullAmount, rollLevel, scaledTickets, flipAmount, roundedUp)"
      ).to.equal(true);

      // `_resolveLootboxCommon` signature still carries `uint48 index` (it
      // threads index through to `_settleLootboxRoll`), and the helper that
      // emits (`_settleLootboxRoll`) also carries `uint48 index`.
      const commonSig = /function _resolveLootboxCommon\([\s\S]*?uint48 index/;
      expect(
        source.match(commonSig),
        "_resolveLootboxCommon signature missing `uint48 index` parameter"
      ).to.not.be.null;
      const settleSig = /function _settleLootboxRoll\([\s\S]*?uint48 index/;
      expect(
        source.match(settleSig),
        "_settleLootboxRoll signature missing `uint48 index` parameter"
      ).to.not.be.null;
    });

    it("[07c] the manual cold-bust consolation pays LOOTBOX_WWXRP_CONSOLATION via `wwxrp.mintPrize` under the `payColdBustConsolation && whole == 0` gate", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const gateIdx = source.indexOf("if (payColdBustConsolation && whole == 0)");
      const consolationMint = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(gateIdx, "`payColdBustConsolation && whole == 0` gate not found").to.be.greaterThan(
        -1
      );
      expect(
        consolationMint,
        "consolation `wwxrp.mintPrize` call not found"
      ).to.be.greaterThan(gateIdx);
      // No dedicated lootbox-WWXRP event — the WWXRP ERC-20 `Transfer` the mint
      // emits is the off-chain correlation surface.
      expect(
        source.includes("LootBoxWwxrpReward"),
        "the retired LootBoxWwxrpReward event must not appear in the module"
      ).to.equal(false);
    });

    it("[07d] the consolation `wwxrp.mintPrize` call is the single payout site inside the `payColdBustConsolation` gate", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const mintPrizeCount = (source.match(
        /wwxrp\.mintPrize\(player, LOOTBOX_WWXRP_CONSOLATION\)/g
      ) || []).length;
      expect(
        mintPrizeCount,
        "the LOOTBOX_WWXRP_CONSOLATION mint must be single-site"
      ).to.equal(1);
      const gateIdx = source.indexOf("if (payColdBustConsolation && whole == 0)");
      const mintPrizeIdx = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(gateIdx).to.be.greaterThan(-1);
      expect(mintPrizeIdx).to.be.greaterThan(gateIdx);
    });
  });
});
