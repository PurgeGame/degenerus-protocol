// SPDX-License-Identifier: AGPL-3.0-only
// Phase 327-04 HERO-04 — PASS_ALL byte-reproduce gate + per-N basePayoutEV
// exactness on the 10-bucket S ∈ {0..9} scale (S = A + 2*H, pay floor S >= 2).
//
// Heavy analytical + spawned-generator byte-reproduce gate — runs ONLY under
// `npm run test:stat` (NOT default `npm test`).
//
// ============================================================================
// HERO-04 PASS_ALL byte-reproduce gate (T-327-04-FC1 / FC2 / FC5 mitigation)
// ============================================================================
//
// The canonical generator
//   .planning/notes/degenerette-recalibration/derive_5_tables.py
// is the SINGLE source of truth for the per-N Degenerette payout / WWXRP-factor
// constants. This gate:
//   1. SPAWNS `python3 derive_5_tables.py` (spawnSync; status === 0 asserted
//      BEFORE any parse — a generator failure surfaces as a test failure, never
//      a silently-empty parse) — T-327-04-FC5.
//   2. PARSES the "FINAL PASTE-READY CONSTANTS" stdout block (the script's
//      regenerated hex — NEVER hand-typed in this test) — T-327-04-FC1.
//   3. READS the contract source (fs.readFileSync
//      contracts/modules/DegenerusGameDegeneretteModule.sol) and regexes the
//      QUICK_PLAY_PAYOUTS_N{N}_PACKED / _S8 / _S9 / WWXRP_FACTORS_N{N}_PACKED
//      literals.
//   4. DIFFS each regenerated constant against the contract literal. Diff == 0
//      for EVERY constant => PASS (the contract holds the byte-reproduced
//      finals). Any nonzero diff => the test FAILS and prints the exact
//      placeholder→final diff (T-327-04-FC2: the gate is NEVER weakened to pass
//      against placeholders — a RED gate against the intentional Phase-326
//      placeholders is the EXPECTED, in-scope no-contract-phase outcome; the
//      contract-constant landing is OUT OF this TST phase and owned by the
//      cross-phase 327-06 closure).
//
// The per-N basePayoutEV exactness assertion uses the REGENERATED tables (parsed
// from the script stdout), so the EV check is anchored on the canonical source,
// not on whatever the contract currently holds.

import { expect } from "chai";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "../..");
const GENERATOR_PATH = resolve(
  REPO_ROOT,
  ".planning/notes/degenerette-recalibration/derive_5_tables.py",
);
const CONTRACT_PATH = resolve(
  REPO_ROOT,
  "contracts/modules/DegenerusGameDegeneretteModule.sol",
);

// ---------------------------------------------------------------------------
// Generator spawn + FINAL PASTE-READY parse (regenerate; never hand-type).
// ---------------------------------------------------------------------------

/// Spawn the canonical python generator and return its stdout. Asserts the
/// process exited 0 BEFORE the caller parses (T-327-04-FC5: a generator failure
/// must surface as a hard failure, never a silently-empty parse).
function runGenerator() {
  const res = spawnSync("python3", [GENERATOR_PATH], {
    cwd: REPO_ROOT,
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (res.error) {
    throw new Error(`derive_5_tables.py spawn error: ${res.error.message}`);
  }
  expect(
    res.status,
    `derive_5_tables.py must exit 0 (status=${res.status}); stderr:\n${res.stderr}`,
  ).to.equal(0);
  expect(res.stdout, "derive_5_tables.py produced empty stdout").to.be.a("string")
    .and.to.have.length.greaterThan(0);
  return res.stdout;
}

/// Parse the "FINAL PASTE-READY CONSTANTS" block. Returns a map
/// { CONST_NAME: bigint } for every QUICK_PLAY_PAYOUTS / _S8 / _S9 / WWXRP_FACTORS
/// constant. The generated literals are hex (0x...) or decimal; both normalize to
/// BigInt for an exact diff.
function parseConstants(text) {
  const marker = "FINAL PASTE-READY CONSTANTS";
  const idx = text.indexOf(marker);
  expect(idx, "FINAL PASTE-READY CONSTANTS block not found in generator stdout")
    .to.be.greaterThan(-1);
  const block = text.slice(idx);

  const out = {};
  // Match: uint256 private constant <NAME> = <VALUE>;  (VALUE = 0x… or decimal)
  const re =
    /uint256\s+private\s+constant\s+([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F]+|\d+)\s*;/g;
  let m;
  while ((m = re.exec(block)) !== null) {
    const name = m[1];
    const raw = m[2];
    out[name] = raw.startsWith("0x") ? BigInt(raw) : BigInt(raw);
  }
  return out;
}

/// Read the contract source and extract the same constant literals.
function parseContractConstants() {
  const src = readFileSync(CONTRACT_PATH, "utf8");
  const out = {};
  const re =
    /uint256\s+private\s+constant\s+(QUICK_PLAY_PAYOUTS_N\d_PACKED|QUICK_PLAY_PAYOUT_N\d_S[89]|WWXRP_FACTORS_N\d_PACKED)\s*=\s*(0x[0-9a-fA-F]+|[\d_]+)\s*;/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const name = m[1];
    const raw = m[2].replace(/_/g, "");
    out[name] = raw.startsWith("0x") ? BigInt(raw) : BigInt(raw);
  }
  return out;
}

// The full set of constants the gate covers (per-N × 4 families = 20).
function expectedConstantNames() {
  const names = [];
  for (let N = 0; N < 5; N++) {
    names.push(`QUICK_PLAY_PAYOUTS_N${N}_PACKED`);
    names.push(`QUICK_PLAY_PAYOUT_N${N}_S8`);
    names.push(`QUICK_PLAY_PAYOUT_N${N}_S9`);
    names.push(`WWXRP_FACTORS_N${N}_PACKED`);
  }
  return names;
}

// ---------------------------------------------------------------------------
// 10-bucket S ∈ {0..9} analytical reference (Fraction-free; BigInt + rationals
// via integer convolution — mirrors derive_5_tables.py P_score_distribution).
// ---------------------------------------------------------------------------

// Per-axis Bernoulli numerators over a common denominator.
//   color common: [13/15, 2/15] ; color gold: [14/15, 1/15]
//   symbol: [7/8, 1/8] ; hero symbol (contributes 0 or 2): [7/8, 0, 1/8]
function analyticalPScore(N) {
  // Work in floating point for the EV assertion tolerance (±0.5 centi-x);
  // the per-bin probabilities are tiny but the EV is dominated by S=2..6.
  function convolve(a, b) {
    const out = new Array(a.length + b.length - 1).fill(0);
    for (let i = 0; i < a.length; i++) {
      for (let j = 0; j < b.length; j++) out[i + j] += a[i] * b[j];
    }
    return out;
  }
  let dist = [1];
  for (let q = 0; q < N; q++) dist = convolve(dist, [14 / 15, 1 / 15]);
  for (let q = 0; q < 4 - N; q++) dist = convolve(dist, [13 / 15, 2 / 15]);
  for (let q = 0; q < 3; q++) dist = convolve(dist, [7 / 8, 1 / 8]);
  dist = convolve(dist, [7 / 8, 0, 1 / 8]); // hero axis: +2 on match
  while (dist.length < 10) dist.push(0);
  return dist; // dist[S] = P_N(S), S ∈ {0..9}
}

// Exact rational P_N(S) as integer numerators over a common denominator (mirrors
// the derive_5_tables.py Fraction math). denom = 15^4 * 8^4 = 207_360_000 — the
// 4 color axes (each /15) and 4 symbol axes (3 non-hero + 1 hero, each /8). Using
// exact BigInt integers means NO floating-point slack can mask an EV-positive
// baseline at the boundary.
function exactPScoreNumerators(N) {
  function convolve(a, b) {
    const out = new Array(a.length + b.length - 1).fill(0n);
    for (let i = 0; i < a.length; i++) {
      for (let j = 0; j < b.length; j++) out[i + j] += a[i] * b[j];
    }
    return out;
  }
  let nums = [1n];
  for (let q = 0; q < N; q++) nums = convolve(nums, [14n, 1n]); // gold color /15
  for (let q = 0; q < 4 - N; q++) nums = convolve(nums, [13n, 2n]); // common color /15
  for (let q = 0; q < 3; q++) nums = convolve(nums, [7n, 1n]); // non-hero symbol /8
  nums = convolve(nums, [7n, 0n, 1n]); // hero symbol /8 (+2 on match)
  while (nums.length < 10) nums.push(0n);
  return { nums, denom: 15n ** 4n * 8n ** 4n }; // 207_360_000
}

// JS-replica dispatch on the 10-bucket S-scale (mirror
// DegenerusGameDegeneretteModule.sol _getBasePayoutBps L1038-1060): S=8/S=9 are
// separate uint256s, S=0..7 from the packed slot.
function jsGetBasePayoutBps(consts, N, s) {
  if (s >= 9) return consts[`QUICK_PLAY_PAYOUT_N${N}_S9`];
  if (s === 8) return consts[`QUICK_PLAY_PAYOUT_N${N}_S8`];
  const packed = consts[`QUICK_PLAY_PAYOUTS_N${N}_PACKED`];
  return (packed >> (BigInt(s) * 32n)) & 0xFFFFFFFFn;
}

// WWXRP bucket / factor (mirror _wwxrpBonusBucket L959-964 + _wwxrpFactor
// L973-982): floor S >= 6, buckets 6..9, factor packed 64 bits, B=6 low.
function jsWwxrpBonusBucket(s) {
  if (s < 6) return 0;
  return s; // 6,7,8,9
}
function jsWwxrpFactor(consts, N, bucket) {
  if (bucket < 6 || bucket > 9) return 0n;
  const packed = consts[`WWXRP_FACTORS_N${N}_PACKED`];
  return (packed >> (BigInt(bucket - 6) * 64n)) & 0xFFFFFFFFFFFFFFFFn;
}

const WWXRP_BONUS_FACTOR_SCALE = 1_000_000;
const ETH_ROI_BONUS_BPS = 500;

// ===========================================================================
// HERO-04 PASS_ALL byte-reproduce gate
// ===========================================================================

describe("HERO-04 — PASS_ALL byte-reproduce gate (10-bucket S ∈ {0..9})", function () {
  this.timeout(120_000);

  let generated;
  let contractConsts;

  before(function () {
    const stdout = runGenerator();
    generated = parseConstants(stdout);
    contractConsts = parseContractConstants();
  });

  it("derive_5_tables.py spawns, exits 0, and emits all 20 canonical constants", function () {
    for (const name of expectedConstantNames()) {
      expect(generated, `generator missing ${name}`).to.have.property(name);
    }
  });

  it("the contract source declares all 20 byte-reproduce target constants", function () {
    for (const name of expectedConstantNames()) {
      expect(contractConsts, `contract missing ${name}`).to.have.property(name);
    }
  });

  it("PASS_ALL: every regenerated constant byte-matches the contract source (diff == 0)", function () {
    // This is the load-bearing gate. The constants compared are the SCRIPT's
    // regenerated values (parsed above) — NEVER hand-typed. A nonzero diff on
    // ANY constant fails the gate and prints the exact placeholder→final diff.
    //
    // EXPECTED OUTCOME in the no-contract TST phase: the Phase-326 placeholders
    // (QUICK_PLAY_PAYOUTS_N{N}_PACKED = old M-indexed, _S8 = 0, WWXRP = old) are
    // still present, so this gate is RED-with-diff. The _S9 constants are FINAL
    // (the M=8 relabel) and match. The recorded diff is the ready-to-apply
    // contract-constant landing (out of this phase; closed by 327-06). The gate
    // is intentionally NOT weakened to pass against placeholders (T-327-04-FC2).
    const mismatches = [];
    for (const name of expectedConstantNames()) {
      const gen = generated[name];
      const con = contractConsts[name];
      if (gen !== con) {
        mismatches.push(
          `${name}:\n    contract  = 0x${con.toString(16)}\n    generated = 0x${gen.toString(16)}`,
        );
      }
    }
    if (mismatches.length > 0) {
      console.log(
        "\n[HERO-04 PASS_ALL] RED — contract holds placeholders for " +
          `${mismatches.length}/20 constants. Placeholder→final diff:\n` +
          mismatches.join("\n") +
          "\n\nThis RED-with-diff is the EXPECTED no-contract-phase outcome. " +
          "The S9 (relabel) constants match; the contract-constant landing of " +
          "the S0..8 packed/_S8 + WWXRP finals is out of this TST phase " +
          "(327-06 cross-phase closure). The gate is NOT weakened to pass.\n",
      );
    }
    expect(
      mismatches.length,
      `HERO-04 PASS_ALL: ${mismatches.length}/20 constants diverge from the canonical generator (see log)`,
    ).to.equal(0);
  });

  it("S9 relabel constants are FINAL (match the contract — the M=8 jackpot relabel)", function () {
    // The S9 constants are the one family that is FINAL in the Phase-326 diff.
    // Asserting they match independently anchors the relabel even while the
    // packed/_S8/WWXRP placeholders keep the PASS_ALL gate red.
    for (let N = 0; N < 5; N++) {
      const name = `QUICK_PLAY_PAYOUT_N${N}_S9`;
      expect(
        generated[name],
        `${name}: generated S9 must equal the contract's final relabel constant`,
      ).to.equal(contractConsts[name]);
    }
  });
});

// ===========================================================================
// Per-N basePayoutEV exactness on the REGENERATED 10-bucket tables
// ===========================================================================

describe("HERO-04 — per-N basePayoutEV neutral-or-just-under (regenerated tables)", function () {
  this.timeout(120_000);

  let generated;

  before(function () {
    generated = parseConstants(runGenerator());
  });

  for (let N = 0; N < 5; N++) {
    it(`N=${N}: analytical-P_N(S) × regenerated tables yields basePayoutEV <= 100 and ~100 centi-x`, function () {
      const pS = analyticalPScore(N);
      // sum_S P_N(S) == 1 (within fp).
      const total = pS.reduce((a, b) => a + b, 0);
      expect(Math.abs(total - 1), `P_N(S) sum ${total} != 1`).to.be.lessThan(1e-9);

      let ev = 0;
      for (let s = 0; s <= 9; s++) {
        const basePayout = Number(jsGetBasePayoutBps(generated, N, s));
        ev += pS[s] * basePayout;
      }
      console.log(
        `[HERO-04 EV N=${N}] basePayoutEV = ${ev.toFixed(6)} centi-x (must be <= 100, ~100)`,
      );
      // Neutral-or-just-under: never EV-positive (<= 100, allowing only fp noise)
      // and within 0.5 centi-x of neutral (no slack house edge on the base table).
      expect(
        ev <= 100.0 + 1e-6,
        `HERO-04 N=${N}: basePayoutEV ${ev.toFixed(6)} centi-x is EV-POSITIVE (> 100)`,
      ).to.equal(true);
      expect(
        ev >= 99.5,
        `HERO-04 N=${N}: basePayoutEV ${ev.toFixed(6)} centi-x is too far below 100 (< 99.5)`,
      ).to.equal(true);
    });
  }

  it("S=9 is exactly the all-7-ordinary + hero-symbol event (== old M=8 odds)", function () {
    // P_N(S=9) must equal (1/15)^N (2/15)^(4-N) × (1/8)^4 — the 4 colors + 4
    // symbols all match (hero symbol among them). This is the relabel anchor.
    for (let N = 0; N < 5; N++) {
      const pS = analyticalPScore(N);
      const expectedS9 =
        Math.pow(1 / 15, N) * Math.pow(2 / 15, 4 - N) * Math.pow(1 / 8, 4);
      const rel = Math.abs(pS[9] - expectedS9) / expectedS9;
      expect(
        rel < 1e-9,
        `N=${N}: P(S=9) ${pS[9]} != all-match event ${expectedS9}`,
      ).to.equal(true);
    }
  });
});

// ===========================================================================
// HARD baseline neutrality — exact, every-scenario, never EV-positive.
//
// The "baseline" is the player's expected return on the BASE payout table
// alone: BEFORE the activity-score ROI scaling (roiBps <= 9990 = 99.9%) and
// BEFORE the ETH/WWXRP lootbox bonus (both applied on top, out of scope here).
// It MUST be neutral-or-just-under — basePayoutEV <= 100 centi-x for EVERY
// player pick (gold-quadrant count N ∈ {0..4}), integrated EXACTLY over the
// full score distribution P_N(S), S ∈ {0..9}. This reads the CONTRACT's landed
// constants and uses exact integer (BigInt) arithmetic so no floating-point
// rounding can hide an EV-positive baseline at the boundary.
// ===========================================================================

describe("HERO-04 — baseline basePayoutEV neutral-or-just-under (exact contract constants, never EV-positive)", function () {
  this.timeout(120_000);

  let contractConsts;

  before(function () {
    contractConsts = parseContractConstants();
  });

  for (let N = 0; N < 5; N++) {
    it(`N=${N}: exact basePayoutEV over P_N(S) is <= 100 centi-x (never positive) and ~100 (>= 99.5)`, function () {
      const { nums, denom } = exactPScoreNumerators(N);
      // sum_S P_N(S) == 1 exactly.
      const sumNums = nums.reduce((a, b) => a + b, 0n);
      expect(
        sumNums === denom,
        `N=${N}: P_N(S) numerators sum ${sumNums} != denom ${denom}`,
      ).to.equal(true);

      // evNum / denom = basePayoutEV (centi-x), from the CONTRACT's landed table.
      let evNum = 0n;
      for (let s = 0; s <= 9; s++) {
        evNum += jsGetBasePayoutBps(contractConsts, N, s) * nums[s];
      }
      const evCentiX = Number(evNum) / Number(denom);
      console.log(
        `[HERO-04 baseline N=${N}] exact basePayoutEV = ${evCentiX.toFixed(6)} centi-x (must be <= 100, ~100)`,
      );

      // Exact integer comparisons — no floating-point slack.
      // Never EV-positive: evNum/denom <= 100  ⟺  evNum <= 100*denom.
      expect(
        evNum <= 100n * denom,
        `HERO-04 N=${N}: baseline basePayoutEV ${evCentiX.toFixed(6)} centi-x is EV-POSITIVE (> 100) — the base table must be neutral or just under`,
      ).to.equal(true);
      // ~100 (no slack edge): evNum/denom >= 99.5  ⟺  10*evNum >= 995*denom.
      expect(
        10n * evNum >= 995n * denom,
        `HERO-04 N=${N}: baseline basePayoutEV ${evCentiX.toFixed(6)} centi-x is too far below 100 (< 99.5)`,
      ).to.equal(true);
    });
  }
});
