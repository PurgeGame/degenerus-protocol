// SPDX-License-Identifier: AGPL-3.0-only
// Phase 454 TST-01 / INV-03 — v73 Variant-2 byte-reproduce gate + per-(N,heroIsGold)
// basePayoutEV exactness + exact EV-equality (DEC-02 Option B) + R2 rigged-dist
// neutral baseline + P(S=9) invariance, on the 10-bucket S ∈ {0..9} scale.
//
// Heavy analytical + spawned-generator byte-reproduce gate — runs ONLY under
// `npm run test:stat` (NOT default `npm test`).
//
// ============================================================================
// v73 — Variant-2 (color-gated-by-symbol) scoring
// ============================================================================
//
// Per quadrant a SYMBOL match scores +1 (the hero quadrant's symbol +2), and that
// quadrant's COLOR scores +1 ONLY IF that quadrant's symbol also matched. The four
// quadrants are therefore no longer independent axes — each contributes a joint
// (symbol, color) score and the ticket score is the convolution of the four:
//   - 3 ordinary quadrants over {0, +1, +2}
//   - 1 hero quadrant over {0, +2, +3}   (index +1 is structurally zero)
// Max S = 9 = hero quad (3) + three ordinary quads (2 each) = the all-8-axes event.
//
// DEC-02 Option B: the HONEST (ETH/FLIP) payout + ETH-bonus family is split per
// (N, hero-is-gold) — 8 base tables (N0, N1/2/3 × {gold,common}, N4) + matching _S8
// and factor tables — each solved against its OWN Variant-2 distribution so every
// pick is EXACTLY EV-equal. The WWXRP _RIG_ family stays AVERAGED at 5 per-N tables
// (hero-placement drift accepted by-design). S=9 pins are by N only (P(S=9) is
// placement-independent).
//
// ============================================================================
// byte-reproduce gate (TST-01)
// ============================================================================
//
// The canonical generator
//   .planning/notes/degenerette-recalibration/derive_5_tables.py
// is the SINGLE source of truth for the 44 v73 payout / factor constants. This
// gate SPAWNS it (spawnSync; status === 0 asserted BEFORE any parse), parses the
// "FINAL PASTE-READY CONSTANTS" stdout (NEVER hand-typed), reads the contract
// source, and DIFFS each regenerated constant against the contract literal. Diff
// == 0 for EVERY constant => PASS. Underscores in the literals are normalized so
// the S9 pins (contract keeps HEAD's underscore form) compare exactly.
//
// The per-(N,heroIsGold) basePayoutEV exactness assertions run against the CONTRACT's
// landed constants with exact BigInt arithmetic (no floating-point slack can hide an
// EV-positive baseline at the boundary).

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
// The v73 constant family (44 total).
// ---------------------------------------------------------------------------

// The 8 structurally-valid honest sub-cases as (N, heroIsGold). N0 is always
// hero-common; N4 always hero-gold; N∈{1,2,3} split both ways.
const HONEST_SUBCASES = [
  [0, false],
  [1, true],
  [1, false],
  [2, true],
  [2, false],
  [3, true],
  [3, false],
  [4, true],
];

// Honest constant-name suffix for a sub-case (N0/N4 collapse, no infix).
function honestSuffix(N, heroIsGold) {
  if (N === 0) return "N0";
  if (N === 4) return "N4";
  return `N${N}_${heroIsGold ? "HEROGOLD" : "HEROCOMMON"}`;
}

function honestBaseName(N, g) {
  return `QUICK_PLAY_PAYOUTS_${honestSuffix(N, g)}_PACKED`;
}
function honestS8Name(N, g) {
  return `QUICK_PLAY_PAYOUT_${honestSuffix(N, g)}_S8`;
}
function honestFactorName(N, g) {
  return `WWXRP_FACTORS_${honestSuffix(N, g)}_PACKED`;
}

// Every v73 byte-reproduce target (44 constants).
function expectedConstantNames() {
  const names = [];
  for (const [N, g] of HONEST_SUBCASES) {
    names.push(honestBaseName(N, g)); // 8 honest base
    names.push(honestS8Name(N, g)); // 8 honest S8
    names.push(honestFactorName(N, g)); // 8 honest factors
  }
  for (let N = 0; N < 5; N++) {
    names.push(`QUICK_PLAY_PAYOUT_N${N}_S9`); // 5 S9 pins (by N)
    names.push(`QUICK_PLAY_PAYOUTS_RIG_N${N}_PACKED`); // 5 rigged base
    names.push(`QUICK_PLAY_PAYOUT_RIG_N${N}_S8`); // 5 rigged S8
    names.push(`WWXRP_FACTORS_RIG_N${N}_PACKED`); // 5 rigged factors
  }
  return names;
}

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

// Normalize a hex/decimal literal (strip Solidity `_` separators) to BigInt.
function toBig(raw) {
  const clean = raw.replace(/_/g, "");
  return clean.startsWith("0x") ? BigInt(clean) : BigInt(clean);
}

// Parse the "FINAL PASTE-READY CONSTANTS" block — { NAME: bigint } for every
// `uint256 private constant NAME = VALUE;`.
function parseConstants(text) {
  const marker = "FINAL PASTE-READY CONSTANTS";
  const idx = text.indexOf(marker);
  expect(idx, "FINAL PASTE-READY CONSTANTS block not found in generator stdout")
    .to.be.greaterThan(-1);
  const block = text.slice(idx);
  const out = {};
  const re =
    /uint256\s+private\s+constant\s+([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F_]+|[\d_]+)\s*;/g;
  let m;
  while ((m = re.exec(block)) !== null) out[m[1]] = toBig(m[2]);
  return out;
}

// Read the contract source and extract the same constant literals.
function parseContractConstants() {
  const src = readFileSync(CONTRACT_PATH, "utf8");
  const out = {};
  const re =
    /uint256\s+private\s+constant\s+([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F_]+|[\d_]+)\s*;/g;
  let m;
  while ((m = re.exec(src)) !== null) out[m[1]] = toBig(m[2]);
  return out;
}

// ---------------------------------------------------------------------------
// Variant-2 analytical P(S | N, heroIsGold) — exact BigInt numerators over the
// common denominator 120^4 = 207_360_000 (per quad: color /15 × symbol /8 = /120).
//
// Per-quad score numerators over 120 (mirrors derive_5_tables.py
// _ordinary_quadrant_dist / _hero_quadrant_dist):
//   ordinary common color (pc=2/15): +0:105  +1:13  +2:2
//   ordinary gold   color (pc=1/15): +0:105  +1:14  +2:1
//   hero     common color:           +0:105  +1:0   +2:13  +3:2
//   hero     gold   color:           +0:105  +1:0   +2:14  +3:1
// (symbol match 1/8 -> the +1/+2/+3 buckets; 7/8 miss -> +0; color gates the color
//  point behind the symbol so it only appears in the symbol-matched buckets.)
// ---------------------------------------------------------------------------

const QUAD_DENOM = 120n;
const TICKET_DENOM = QUAD_DENOM ** 4n; // 207_360_000

const ORD_COMMON = [105n, 13n, 2n];
const ORD_GOLD = [105n, 14n, 1n];
const HERO_COMMON = [105n, 0n, 13n, 2n];
const HERO_GOLD = [105n, 0n, 14n, 1n];

function convolveBig(a, b) {
  const out = new Array(a.length + b.length - 1).fill(0n);
  for (let i = 0; i < a.length; i++)
    for (let j = 0; j < b.length; j++) out[i + j] += a[i] * b[j];
  return out;
}

// Exact P(S | N, heroIsGold) as numerators over TICKET_DENOM (length 10).
function exactPScoreSubcase(N, heroIsGold) {
  const ordGold = heroIsGold ? N - 1 : N;
  const ordCommon = heroIsGold ? 4 - N : 3 - N;
  let nums = heroIsGold ? HERO_GOLD.slice() : HERO_COMMON.slice();
  for (let q = 0; q < ordGold; q++) nums = convolveBig(nums, ORD_GOLD);
  for (let q = 0; q < ordCommon; q++) nums = convolveBig(nums, ORD_COMMON);
  while (nums.length < 10) nums.push(0n);
  return nums; // sums to TICKET_DENOM
}

// Averaged honest P(S | N) (hero gold w.p. N/4, common w.p. (4-N)/4) over a common
// denominator 4*TICKET_DENOM — used for the placement-independent S9 invariant.
function exactPScoreAveraged(N) {
  const out = new Array(10).fill(0n);
  if (N >= 1) {
    const g = exactPScoreSubcase(N, true);
    for (let s = 0; s < 10; s++) out[s] += BigInt(N) * g[s];
  }
  if (N <= 3) {
    const c = exactPScoreSubcase(N, false);
    for (let s = 0; s < 10; s++) out[s] += BigInt(4 - N) * c[s];
  }
  return { nums: out, denom: 4n * TICKET_DENOM };
}

// ---------------------------------------------------------------------------
// Contract dispatch replicas (mirror _getBasePayoutBps).
// ---------------------------------------------------------------------------

function honestBasePayout(consts, N, g, s) {
  if (s >= 9) return consts[`QUICK_PLAY_PAYOUT_N${N}_S9`];
  if (s === 8) return consts[honestS8Name(N, g)];
  const packed = consts[honestBaseName(N, g)];
  return (packed >> (BigInt(s) * 32n)) & 0xffffffffn;
}

function rigBasePayout(consts, N, s) {
  if (s >= 9) return consts[`QUICK_PLAY_PAYOUT_N${N}_S9`];
  if (s === 8) return consts[`QUICK_PLAY_PAYOUT_RIG_N${N}_S8`];
  const packed = consts[`QUICK_PLAY_PAYOUTS_RIG_N${N}_PACKED`];
  return (packed >> (BigInt(s) * 32n)) & 0xffffffffn;
}

// ---------------------------------------------------------------------------
// R2 rigged analytical P_N(S) (float; mirrors p_score_distribution_rigged).
//
// Averaged over hero placement. Per full-roll outcome the rig forces ONE
// score-bearing cell w.p. 3/5 when M<=6: a +1 cell (e1) or a +2 color-unlock cell
// (e2). M>=7 untouched; empty pool (e1+e2==0) no-op. Eligible pool:
//   (a) unmatched non-hero symbol -> +1 (cm==0) or +2 unlock (cm==1)
//   (b) unmatched color on a symbol-matched quad (incl. hero color) -> +1
// ---------------------------------------------------------------------------

function quadStates(pColorMatch) {
  const ps = 1 / 8;
  const states = [];
  for (const sm of [0, 1]) {
    const pSm = sm === 1 ? ps : 1 - ps;
    for (const cm of [0, 1]) {
      const pCm = cm === 1 ? pColorMatch : 1 - pColorMatch;
      states.push([sm, cm, pSm * pCm]);
    }
  }
  return states;
}

function riggedAnalyticalPScore(N) {
  const pf = 3 / 5;
  const out = new Array(12).fill(0); // length 12 so a stray +2 overflow is caught
  for (const [heroIsGold, weight, ordGold, ordCommon] of [
    [true, N / 4, N - 1, 4 - N],
    [false, (4 - N) / 4, N, 3 - N],
  ]) {
    if (weight === 0) continue;
    const heroColor = heroIsGold ? 1 / 15 : 2 / 15;
    const quads = [[quadStates(heroColor), true]];
    for (let q = 0; q < ordGold; q++) quads.push([quadStates(1 / 15), false]);
    for (let q = 0; q < ordCommon; q++) quads.push([quadStates(2 / 15), false]);

    // Fold the four quadrants into partials keyed (S, M, e1, e2).
    let partials = new Map([["0,0,0,0", weight]]);
    for (const [states, isHero] of quads) {
      const nxt = new Map();
      for (const [key, pacc] of partials) {
        const [S, M, e1, e2] = key.split(",").map(Number);
        for (const [sm, cm, pp] of states) {
          let dS = 0;
          if (sm === 1) {
            dS += isHero ? 2 : 1;
            if (cm === 1) dS += 1;
          }
          const dM = sm + cm;
          let de1 = 0;
          let de2 = 0;
          if (!isHero && sm === 0) {
            if (cm === 0) de1 += 1;
            else de2 += 1;
          }
          if (sm === 1 && cm === 0) de1 += 1;
          const nk = `${S + dS},${M + dM},${e1 + de1},${e2 + de2}`;
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
  // The m>=7 cap guarantees a fired roll stays S<=8 -> no mass above index 9.
  expect(out[10] + out[11], "rig produced impossible S>9 mass").to.be.lessThan(1e-15);
  return out.slice(0, 10);
}

// ===========================================================================
// byte-reproduce gate (TST-01)
// ===========================================================================

describe("v73 TST-01 — byte-reproduce gate (44 Variant-2 constants)", function () {
  this.timeout(120_000);

  let generated;
  let contractConsts;

  before(function () {
    generated = parseConstants(runGenerator());
    contractConsts = parseContractConstants();
  });

  it("derive_5_tables.py spawns, exits 0, and emits all 44 canonical constants", function () {
    for (const name of expectedConstantNames()) {
      expect(generated, `generator missing ${name}`).to.have.property(name);
    }
  });

  it("the contract source declares all 44 byte-reproduce target constants", function () {
    for (const name of expectedConstantNames()) {
      expect(contractConsts, `contract missing ${name}`).to.have.property(name);
    }
  });

  it("PASS_ALL: every regenerated constant byte-matches the contract (diff == 0)", function () {
    const mismatches = [];
    for (const name of expectedConstantNames()) {
      if (generated[name] !== contractConsts[name]) {
        mismatches.push(
          `${name}:\n    contract  = 0x${contractConsts[name].toString(16)}\n    generated = 0x${generated[name].toString(16)}`,
        );
      }
    }
    expect(
      mismatches.length,
      `byte-reproduce: ${mismatches.length}/44 constants diverge from the canonical generator:\n${mismatches.join("\n")}`,
    ).to.equal(0);
  });

  it("the S9 pins are by-N only (no _HEROGOLD/_HEROCOMMON split — placement-independent)", function () {
    // P(S=9) is placement-independent, so there must be exactly one S9 constant per N.
    const src = readFileSync(CONTRACT_PATH, "utf8");
    expect(/QUICK_PLAY_PAYOUT_N\d_HERO(GOLD|COMMON)_S9/.test(src),
      "S9 pin must NOT be split per heroIsGold").to.equal(false);
  });
});

// ===========================================================================
// Honest per-(N,heroIsGold) basePayoutEV exactness + exact EV-equality (Option B)
// ===========================================================================

describe("v73 — honest per-(N,heroIsGold) basePayoutEV neutral-or-just-under (exact contract constants)", function () {
  this.timeout(120_000);

  let c;
  before(function () {
    c = parseContractConstants();
  });

  for (const [N, g] of HONEST_SUBCASES) {
    const label = honestSuffix(N, g);
    it(`${label}: exact basePayoutEV over its OWN Variant-2 P(S) is <= 100 and ~100 (>= 99.95) centi-x`, function () {
      const nums = exactPScoreSubcase(N, g);
      const sum = nums.reduce((a, b) => a + b, 0n);
      expect(sum === TICKET_DENOM, `${label}: P(S) numerators ${sum} != denom ${TICKET_DENOM}`).to.equal(true);

      let evNum = 0n;
      for (let s = 0; s <= 9; s++) evNum += honestBasePayout(c, N, g, s) * nums[s];
      const evCentiX = Number(evNum) / Number(TICKET_DENOM);
      console.log(`[v73 honest EV ${label}] basePayoutEV = ${evCentiX.toFixed(6)} centi-x`);

      // Never EV-positive: evNum/denom <= 100.
      expect(evNum <= 100n * TICKET_DENOM,
        `${label}: basePayoutEV ${evCentiX.toFixed(6)} is EV-POSITIVE (> 100)`).to.equal(true);
      // ~neutral (no slack edge): evNum/denom >= 99.95.
      expect(evNum * 100n >= 9995n * TICKET_DENOM,
        `${label}: basePayoutEV ${evCentiX.toFixed(6)} is too far below 100 (< 99.95)`).to.equal(true);
    });
  }

  // EVEQ-01 / DEC-02 Option B: exact EV-equality across hero placement within a fixed N.
  for (const N of [1, 2, 3]) {
    it(`N=${N}: EV(hero gold) == EV(hero common) within 0.01 centi-x (exact EV-equality)`, function () {
      const evNumFor = (g) => {
        const nums = exactPScoreSubcase(N, g);
        let ev = 0n;
        for (let s = 0; s <= 9; s++) ev += honestBasePayout(c, N, g, s) * nums[s];
        return ev;
      };
      const evGold = evNumFor(true);
      const evCommon = evNumFor(false);
      const driftCentiX = Math.abs(Number(evGold - evCommon)) / Number(TICKET_DENOM);
      console.log(`[v73 EVEQ N=${N}] |drift| = ${driftCentiX.toFixed(6)} centi-x`);
      // 0.01 centi-x tolerance (generator reports max 0.00007).
      const diff = evGold > evCommon ? evGold - evCommon : evCommon - evGold;
      expect(diff * 100n <= TICKET_DENOM,
        `N=${N}: hero-placement EV drift ${driftCentiX.toFixed(6)} centi-x exceeds 0.01 (Option B not exactly EV-equal)`).to.equal(true);
    });
  }
});

// ===========================================================================
// WWXRP RIG — rigged-dist neutral baseline + P(S=9) invariance (INV-03)
// ===========================================================================

describe("v73 — R2 rigged baseline EV + P(S=9) invariance (INV-03)", function () {
  this.timeout(120_000);

  let c;
  before(function () {
    c = parseContractConstants();
  });

  for (let N = 0; N < 5; N++) {
    it(`N=${N}: rigged base table EV over R2 rigged P_N(S) is <= 100 and ~100 (>= 99.9) centi-x`, function () {
      const pS = riggedAnalyticalPScore(N);
      const total = pS.reduce((a, b) => a + b, 0);
      expect(Math.abs(total - 1), `rigged P_N(S) sum ${total} != 1`).to.be.lessThan(1e-9);

      let ev = 0;
      for (let s = 0; s <= 9; s++) ev += pS[s] * Number(rigBasePayout(c, N, s));
      console.log(`[v73 RIG EV N=${N}] rigged basePayoutEV = ${ev.toFixed(6)} centi-x`);
      expect(ev <= 100.0 + 1e-6, `RIG N=${N}: rigged EV ${ev.toFixed(6)} is EV-POSITIVE (>100)`).to.equal(true);
      expect(ev >= 99.9, `RIG N=${N}: rigged EV ${ev.toFixed(6)} too far below 100 (<99.9)`).to.equal(true);
    });
  }

  it("the R2 rig leaves P(S=9) exactly invariant (rigged jackpot odds == honest)", function () {
    for (let N = 0; N < 5; N++) {
      // Honest averaged P(S=9) as an exact rational.
      const { nums, denom } = exactPScoreAveraged(N);
      const honestS9 = Number(nums[9]) / Number(denom);
      const rig = riggedAnalyticalPScore(N);
      const rel = Math.abs(rig[9] - honestS9) / honestS9;
      expect(rel < 1e-12, `N=${N}: rig changed P(S=9) (${rig[9]} vs honest ${honestS9})`).to.equal(true);
    }
  });

  it("honest P(S=9) is placement-independent (every (N,heroIsGold) sub-case shares the per-N value)", function () {
    for (const N of [1, 2, 3]) {
      const g = exactPScoreSubcase(N, true)[9]; // numerator over TICKET_DENOM
      const cm = exactPScoreSubcase(N, false)[9];
      expect(g === cm, `N=${N}: hero-gold P(S=9) num ${g} != hero-common ${cm}`).to.equal(true);
    }
  });

  it("honest P(S=9) == the HEAD all-8-axes match event (1/15)^N (2/15)^(4-N) (1/8)^4", function () {
    for (let N = 0; N < 5; N++) {
      const { nums, denom } = exactPScoreAveraged(N);
      // Expected as exact rational: (1)^N (2)^(4-N) over 15^4, times 1 over 8^4.
      // numerator (over 15^4 * 8^4 = TICKET_DENOM): 1^N * 2^(4-N) * 1 (all symbols 1/8).
      const expNum = 2n ** BigInt(4 - N); // over 15^4 * 8^4
      // nums[9]/denom must equal expNum / TICKET_DENOM.
      // denom = 4*TICKET_DENOM ; nums[9] should be 4*expNum.
      expect(nums[9] === 4n * expNum,
        `N=${N}: P(S=9) numerator ${nums[9]} != 4*${expNum} (all-8-match event)`).to.equal(true);
    }
  });
});
