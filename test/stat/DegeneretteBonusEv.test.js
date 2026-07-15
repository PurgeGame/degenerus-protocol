// SPDX-License-Identifier: AGPL-3.0-only
// Phase 454 TST — v73 Variant-2 ETH/WWXRP bonus-EV exactness on the 10-bucket
// S ∈ {0..9} scale. The +5% bonus (ETH 500bps) is redistributed into the top
// score buckets B = 6..9 via the per-N factor tables so the EV uplift == 5.000%.
//
// v73: the HONEST (ETH/FLIP) factor family is split per (N, heroIsGold) (DEC-02
// Option B) — each sub-case's bonus EV is 5.000% against its OWN Variant-2 P(S);
// the WWXRP _RIG_ factors stay averaged at 5 per-N tables, validated against the
// R2 rigged distribution.
//
// Runs ONLY under `npm run test:stat`. Uses the REGENERATED factor + payout
// constants from the canonical generator (spawnSync python3 derive_5_tables.py),
// NEVER hand-typed. The analytical bonus EV is computed against the Variant-2
// per-quadrant convolution + the regenerated tables (load-bearing).

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
    /uint256\s+private\s+constant\s+([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F_]+|[\d_]+)\s*;/g;
  let m;
  while ((m = re.exec(block)) !== null) out[m[1]] = BigInt(m[2].replace(/_/g, ""));
  return out;
}

// ---------------------------------------------------------------------------
// v73 constant naming (honest split per (N,heroIsGold); rigged by N).
// ---------------------------------------------------------------------------

const HONEST_SUBCASES = [
  [0, false], [1, true], [1, false], [2, true],
  [2, false], [3, true], [3, false], [4, true],
];

function honestSuffix(N, g) {
  if (N === 0) return "N0";
  if (N === 4) return "N4";
  return `N${N}_${g ? "HEROGOLD" : "HEROCOMMON"}`;
}

// ---------------------------------------------------------------------------
// Variant-2 per-quadrant float distributions (color gated behind symbol).
// ---------------------------------------------------------------------------

function convolve(a, b) {
  const out = new Array(a.length + b.length - 1).fill(0);
  for (let i = 0; i < a.length; i++)
    for (let j = 0; j < b.length; j++) out[i + j] += a[i] * b[j];
  return out;
}

const PS = 1 / 8;
function ordinaryQuad(pc) {
  return [1 - PS, PS * (1 - pc), PS * pc];
}
function heroQuad(pc) {
  return [1 - PS, 0, PS * (1 - pc), PS * pc];
}

// Honest Variant-2 P(S | N, heroIsGold).
function honestPScore(N, heroIsGold) {
  const heroColor = heroIsGold ? 1 / 15 : 2 / 15;
  const ordGold = heroIsGold ? N - 1 : N;
  const ordCommon = heroIsGold ? 4 - N : 3 - N;
  let dist = heroQuad(heroColor);
  for (let q = 0; q < ordGold; q++) dist = convolve(dist, ordinaryQuad(1 / 15));
  for (let q = 0; q < ordCommon; q++) dist = convolve(dist, ordinaryQuad(2 / 15));
  while (dist.length < 10) dist.push(0);
  return dist;
}

// R2 rigged P_N(S) (averaged over hero placement; mirrors p_score_distribution_rigged).
function quadStates(pc) {
  const states = [];
  for (const sm of [0, 1]) {
    const pSm = sm === 1 ? PS : 1 - PS;
    for (const cm of [0, 1]) states.push([sm, cm, pSm * (cm === 1 ? pc : 1 - pc)]);
  }
  return states;
}
function riggedPScore(N) {
  const pf = 3 / 5;
  const out = new Array(12).fill(0);
  for (const [heroIsGold, weight, ordGold, ordCommon] of [
    [true, N / 4, N - 1, 4 - N],
    [false, (4 - N) / 4, N, 3 - N],
  ]) {
    if (weight === 0) continue;
    const heroColor = heroIsGold ? 1 / 15 : 2 / 15;
    const quads = [[quadStates(heroColor), true]];
    for (let q = 0; q < ordGold; q++) quads.push([quadStates(1 / 15), false]);
    for (let q = 0; q < ordCommon; q++) quads.push([quadStates(2 / 15), false]);
    let partials = new Map([["0,0,0,0", weight]]);
    for (const [states, isHero] of quads) {
      const nxt = new Map();
      for (const [key, pacc] of partials) {
        const [S, M, e1, e2] = key.split(",").map(Number);
        for (const [sm, cm, pp] of states) {
          let dS = 0;
          if (sm === 1) { dS += isHero ? 2 : 1; if (cm === 1) dS += 1; }
          let de1 = 0, de2 = 0;
          if (!isHero && sm === 0) { if (cm === 0) de1 += 1; else de2 += 1; }
          if (sm === 1 && cm === 0) de1 += 1;
          const nk = `${S + dS},${M + sm + cm},${e1 + de1},${e2 + de2}`;
          nxt.set(nk, (nxt.get(nk) || 0) + pacc * pp);
        }
      }
      partials = nxt;
    }
    for (const [key, p] of partials) {
      const [S, M, e1, e2] = key.split(",").map(Number);
      const etot = e1 + e2;
      if (M >= 7) out[S] += p;
      else if (etot === 0) out[S] += p;
      else {
        out[S] += p * (1 - pf);
        out[S + 1] += p * pf * (e1 / etot);
        if (e2) out[S + 2] += p * pf * (e2 / etot);
      }
    }
  }
  return out.slice(0, 10);
}

// ---------------------------------------------------------------------------
// Dispatch replicas.
// ---------------------------------------------------------------------------

function honestBase(consts, N, g, s) {
  if (s >= 9) return consts[`QUICK_PLAY_PAYOUT_N${N}_S9`];
  if (s === 8) return consts[`QUICK_PLAY_PAYOUT_${honestSuffix(N, g)}_S8`];
  const packed = consts[`QUICK_PLAY_PAYOUTS_${honestSuffix(N, g)}_PACKED`];
  return (packed >> (BigInt(s) * 32n)) & 0xffffffffn;
}
function honestFactor(consts, N, g, bucket) {
  if (bucket < 6 || bucket > 9) return 0n;
  const packed = consts[`WWXRP_FACTORS_${honestSuffix(N, g)}_PACKED`];
  return (packed >> (BigInt(bucket - 6) * 64n)) & 0xffffffffffffffffn;
}
function rigBase(consts, N, s) {
  if (s >= 9) return consts[`QUICK_PLAY_PAYOUT_N${N}_S9`];
  if (s === 8) return consts[`QUICK_PLAY_PAYOUT_RIG_N${N}_S8`];
  const packed = consts[`QUICK_PLAY_PAYOUTS_RIG_N${N}_PACKED`];
  return (packed >> (BigInt(s) * 32n)) & 0xffffffffn;
}
function rigFactor(consts, N, bucket) {
  if (bucket < 6 || bucket > 9) return 0n;
  const packed = consts[`WWXRP_FACTORS_RIG_N${N}_PACKED`];
  return (packed >> (BigInt(bucket - 6) * 64n)) & 0xffffffffffffffffn;
}
function wwxrpBonusBucket(s) {
  return s < 6 ? 0 : s;
}

function bonusUpliftPct(pS, baseFn, factorFn) {
  let evWith = 0, evWithout = 0;
  for (let s = 0; s <= 9; s++) {
    const basePayout = Number(baseFn(s));
    evWithout += pS[s] * basePayout;
    const bucket = wwxrpBonusBucket(s);
    let effRoi = 10_000;
    if (bucket !== 0) {
      const factor = Number(factorFn(bucket));
      effRoi = 10_000 + (ETH_ROI_BONUS_BPS * factor) / WWXRP_BONUS_FACTOR_SCALE;
    }
    evWith += pS[s] * basePayout * (effRoi / 10_000);
  }
  return ((evWith - evWithout) / evWithout) * 100;
}

// ===========================================================================
// Honest per-(N,heroIsGold) ETH bonus EV == 5.000% ± 1%
// ===========================================================================

describe("v73 — honest ETH bonus EV == 5.000% ± 1% per (N,heroIsGold) sub-case", function () {
  this.timeout(120_000);
  let g;
  before(function () {
    g = parseConstants(runGenerator());
  });

  for (const [N, hg] of HONEST_SUBCASES) {
    const label = honestSuffix(N, hg);
    it(`${label}: Variant-2 P(S) bonus EV uplift = 5.000% ± 1% on the split factors`, function () {
      const pS = honestPScore(N, hg);
      const uplift = bonusUpliftPct(
        pS,
        (s) => honestBase(g, N, hg, s),
        (b) => honestFactor(g, N, hg, b),
      );
      const relErr = (uplift - 5.0) / 5.0;
      console.log(`[v73 honest bonus ${label}] uplift = ${uplift.toFixed(6)}% (relErr ${(relErr * 100).toFixed(4)}%)`);
      expect(Math.abs(relErr) <= 0.01, `${label}: ETH bonus EV ${uplift.toFixed(6)}% outside ±1% of 5.000%`).to.equal(true);
    });
  }

  it("WWXRP factor buckets are B=6..9 (S<6 -> no bonus) and every split factor is nonzero", function () {
    expect(wwxrpBonusBucket(5)).to.equal(0);
    for (const B of [6, 7, 8, 9]) expect(wwxrpBonusBucket(B)).to.equal(B);
    for (const [N, hg] of HONEST_SUBCASES) {
      for (const B of [6, 7, 8, 9]) {
        expect(honestFactor(g, N, hg, B) > 0n, `${honestSuffix(N, hg)} bucket ${B}: factor must be nonzero`).to.equal(true);
      }
    }
  });
});

// ===========================================================================
// WWXRP RIG bonus EV == 5.000% ± 1% per N (rigged factors + R2 rigged dist)
// ===========================================================================

describe("v73 — WWXRP RIG bonus EV == 5.000% ± 1% per N (rigged factors + R2 dist)", function () {
  this.timeout(120_000);
  let g;
  before(function () {
    g = parseConstants(runGenerator());
  });

  for (let N = 0; N < 5; N++) {
    it(`N=${N}: R2 rigged P_N(S) bonus EV uplift = 5.000% ± 1% on the rigged factors`, function () {
      const pS = riggedPScore(N);
      const uplift = bonusUpliftPct(pS, (s) => rigBase(g, N, s), (b) => rigFactor(g, N, b));
      const relErr = (uplift - 5.0) / 5.0;
      console.log(`[v73 RIG bonus N=${N}] uplift = ${uplift.toFixed(6)}% (relErr ${(relErr * 100).toFixed(4)}%)`);
      expect(Math.abs(relErr) <= 0.01, `RIG N=${N}: bonus EV ${uplift.toFixed(6)}% outside ±1% of 5%`).to.equal(true);
    });
  }
});
