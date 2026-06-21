// SPDX-License-Identifier: AGPL-3.0-only
// Phase 327-04 HERO-04 — ETH/WWXRP bonus EV exactness on the 10-bucket S ∈ {0..9}
// scale (WWXRP factor buckets re-bucketed to B = 6..9; ETH bonus EV = 5.000% per N).
//
// Runs ONLY under `npm run test:stat`. Uses the REGENERATED WWXRP factor + payout
// constants from the canonical generator (spawnSync python3 derive_5_tables.py),
// NEVER hand-typed (T-327-04-FC1). The analytical bonus EV is computed against the
// analytical P_N(S) convolution + the regenerated tables (load-bearing).

import { expect } from "chai";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "../..");
const GENERATOR_PATH = resolve(
  REPO_ROOT,
  ".planning/notes/degenerette-recalibration/derive_5_tables.py",
);

const WWXRP_BONUS_FACTOR_SCALE = 1_000_000;
const ETH_ROI_BONUS_BPS = 500;

// ---------------------------------------------------------------------------
// Generator spawn + FINAL PASTE-READY parse (regenerate; never hand-type).
// ---------------------------------------------------------------------------

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

function parseConstants(text) {
  const marker = "FINAL PASTE-READY CONSTANTS";
  const idx = text.indexOf(marker);
  expect(idx, "FINAL PASTE-READY CONSTANTS block not found").to.be.greaterThan(-1);
  const block = text.slice(idx);
  const out = {};
  const re =
    /uint256\s+private\s+constant\s+([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F]+|\d+)\s*;/g;
  let m;
  while ((m = re.exec(block)) !== null) {
    out[m[1]] = BigInt(m[2]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// 10-bucket S ∈ {0..9} analytical reference + dispatch replica.
// ---------------------------------------------------------------------------

function analyticalPScore(N) {
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
  dist = convolve(dist, [7 / 8, 0, 1 / 8]);
  while (dist.length < 10) dist.push(0);
  return dist;
}

function jsGetBasePayoutBps(consts, N, s) {
  if (s >= 9) return consts[`QUICK_PLAY_PAYOUT_N${N}_S9`];
  if (s === 8) return consts[`QUICK_PLAY_PAYOUT_N${N}_S8`];
  const packed = consts[`QUICK_PLAY_PAYOUTS_N${N}_PACKED`];
  return (packed >> (BigInt(s) * 32n)) & 0xFFFFFFFFn;
}

function jsWwxrpBonusBucket(s) {
  if (s < 6) return 0;
  return s;
}

function jsWwxrpFactor(consts, N, bucket) {
  if (bucket < 6 || bucket > 9) return 0n;
  const packed = consts[`WWXRP_FACTORS_N${N}_PACKED`];
  return (packed >> (BigInt(bucket - 6) * 64n)) & 0xFFFFFFFFFFFFFFFFn;
}

// ===========================================================================
// HERO-04 ETH-bonus EV == 5.000% per N (regenerated WWXRP factor tables)
// ===========================================================================

describe("HERO-04 — ETH bonus EV == 5.000% ± 1% per N (regenerated B=6..9 factors)", function () {
  this.timeout(120_000);

  let generated;

  before(function () {
    generated = parseConstants(runGenerator());
  });

  for (let N = 0; N < 5; N++) {
    it(`N=${N}: analytical-P_N(S) bonus EV uplift = 5.000% ± 1% on the regenerated factors`, function () {
      const pS = analyticalPScore(N);

      // ETH bonus EV: the per-N WWXRP factors redistribute ETH_ROI_BONUS_BPS=500
      // across buckets B=6..9. effRoi = 10000 + 500*factor/SCALE; the uplift over
      // the no-bonus baseline (roiBps=10000) is the bonus EV.
      let evWith = 0;
      let evWithout = 0;
      for (let s = 0; s <= 9; s++) {
        const basePayout = Number(jsGetBasePayoutBps(generated, N, s));
        evWithout += pS[s] * basePayout * (10_000 / 10_000);
        const bucket = jsWwxrpBonusBucket(s);
        let effRoi = 10_000;
        if (bucket !== 0) {
          const factor = Number(jsWwxrpFactor(generated, N, bucket));
          effRoi = 10_000 + (ETH_ROI_BONUS_BPS * factor) / WWXRP_BONUS_FACTOR_SCALE;
        }
        evWith += pS[s] * basePayout * (effRoi / 10_000);
      }
      const upliftPct = ((evWith - evWithout) / evWithout) * 100;
      const relErr = (upliftPct - 5.0) / 5.0;
      console.log(
        `[HERO-04 bonus N=${N}] ETH bonus EV uplift = ${upliftPct.toFixed(6)}% ` +
          `(target 5.000%; relative error ${(relErr * 100).toFixed(4)}%)`,
      );
      expect(
        Math.abs(relErr) <= 0.01,
        `HERO-04 N=${N}: ETH bonus EV ${upliftPct.toFixed(6)}% outside ±1% of 5.000%`,
      ).to.equal(true);
    });
  }

  it("WWXRP factor buckets are re-mapped to B=6..9 (shift-by-one from the old 5..8)", function () {
    // Floor S >= 6 => buckets 6/7/8/9; S < 6 => bucket 0 (no bonus). Anchors the
    // re-bucketing onto the 10-point scale.
    expect(jsWwxrpBonusBucket(5)).to.equal(0);
    expect(jsWwxrpBonusBucket(6)).to.equal(6);
    expect(jsWwxrpBonusBucket(7)).to.equal(7);
    expect(jsWwxrpBonusBucket(8)).to.equal(8);
    expect(jsWwxrpBonusBucket(9)).to.equal(9);
    // Each bucket's regenerated factor is nonzero per N (the redistribution
    // actually targets all four top buckets).
    for (let N = 0; N < 5; N++) {
      for (const B of [6, 7, 8, 9]) {
        expect(
          jsWwxrpFactor(generated, N, B) > 0n,
          `N=${N} bucket ${B}: regenerated WWXRP factor must be nonzero`,
        ).to.equal(true);
      }
    }
  });
});

// ===========================================================================
// WWXRP RIG bonus EV — the rigged factors redistribute bonusBps into B=6..9 so
// the uplift == bonusBps/10000 of RTP exactly (5.000% at the ETH 500bps anchor),
// computed against the RIGGED distribution + rigged tables/factors.
// ===========================================================================

function riggedAnalyticalPScore(N) {
  function conv(a, b) {
    const o = new Array(a.length + b.length - 1).fill(0);
    for (let i = 0; i < a.length; i++) for (let j = 0; j < b.length; j++) o[i + j] += a[i] * b[j];
    return o;
  }
  let C = [1];
  for (let q = 0; q < N; q++) C = conv(C, [14 / 15, 1 / 15]);
  for (let q = 0; q < 4 - N; q++) C = conv(C, [13 / 15, 2 / 15]);
  let Y = [1];
  for (let q = 0; q < 3; q++) Y = conv(Y, [7 / 8, 1 / 8]);
  const H = [7 / 8, 1 / 8];
  const out = new Array(10).fill(0);
  const pf = 3 / 5;
  for (let c = 0; c < C.length; c++)
    for (let y = 0; y < Y.length; y++)
      for (let h = 0; h < 2; h++) {
        const p = C[c] * Y[y] * H[h];
        const M = c + y + h;
        const baseS = c + y + 2 * h;
        if (M >= 7) out[baseS] += p;
        else {
          out[baseS] += p * (1 - pf);
          out[baseS + 1] += p * pf;
        }
      }
  return out;
}

function jsGetBasePayoutBpsRig(consts, N, s) {
  if (s >= 9) return consts[`QUICK_PLAY_PAYOUT_N${N}_S9`];
  if (s === 8) return consts[`QUICK_PLAY_PAYOUT_RIG_N${N}_S8`];
  const packed = consts[`QUICK_PLAY_PAYOUTS_RIG_N${N}_PACKED`];
  return (packed >> (BigInt(s) * 32n)) & 0xFFFFFFFFn;
}

function jsWwxrpFactorRig(consts, N, bucket) {
  if (bucket < 6 || bucket > 9) return 0n;
  const packed = consts[`WWXRP_FACTORS_RIG_N${N}_PACKED`];
  return (packed >> (BigInt(bucket - 6) * 64n)) & 0xFFFFFFFFFFFFFFFFn;
}

describe("WWXRP RIG — bonus EV uplift == 5.000% ± 1% per N (rigged factors + rigged dist)", function () {
  this.timeout(120_000);

  let generated;

  before(function () {
    generated = parseConstants(runGenerator());
  });

  for (let N = 0; N < 5; N++) {
    it(`N=${N}: rigged-P_N(S) bonus EV uplift = 5.000% ± 1% on the rigged factors`, function () {
      const pS = riggedAnalyticalPScore(N);
      let evWith = 0;
      let evWithout = 0;
      for (let s = 0; s <= 9; s++) {
        const basePayout = Number(jsGetBasePayoutBpsRig(generated, N, s));
        evWithout += pS[s] * basePayout;
        const bucket = jsWwxrpBonusBucket(s);
        let effRoi = 10_000;
        if (bucket !== 0) {
          const factor = Number(jsWwxrpFactorRig(generated, N, bucket));
          effRoi = 10_000 + (ETH_ROI_BONUS_BPS * factor) / WWXRP_BONUS_FACTOR_SCALE;
        }
        evWith += pS[s] * basePayout * (effRoi / 10_000);
      }
      const upliftPct = ((evWith - evWithout) / evWithout) * 100;
      const relErr = (upliftPct - 5.0) / 5.0;
      console.log(`[RIG bonus N=${N}] uplift = ${upliftPct.toFixed(6)}% (target 5.000%; relErr ${(relErr * 100).toFixed(4)}%)`);
      expect(Math.abs(relErr) <= 0.01, `RIG N=${N}: bonus EV ${upliftPct.toFixed(6)}% outside ±1% of 5%`).to.equal(true);
    });
  }
});
