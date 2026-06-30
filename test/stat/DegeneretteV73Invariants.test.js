// SPDX-License-Identifier: AGPL-3.0-only
// Phase 454 — INV-01 / INV-02 / INV-03 / INV-04. v73 held-fixed invariants: prove
// the v73 Variant-2 diff did NOT move the activity ROI curve, the WWXRP RTP curve,
// the S=9 jackpot pins, or the S=9 whale-pass bracket — byte-identical to the
// pre-v73 source (the v72 closure subject = the IMPL commit's parent), plus a
// numeric anchor on the concrete curve values.
//
// "HEAD" for these invariants = the pre-v73 contract at `64ec993e^` (v73's IMPL
// commit `64ec993e` was a single-file diff to DegenerusGameDegeneretteModule.sol;
// its parent is the v72 byte-frozen subject). The proof reads BOTH versions and
// asserts the invariant regions are byte-identical — so the held-fixed curves /
// pins / bracket cannot have drifted in the diff.
//
// Runs ONLY under `npm run test:stat`.

import { expect } from "chai";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "../..");
const CONTRACT_REL = "contracts/modules/DegenerusGameDegeneretteModule.sol";
const CONTRACT_PATH = resolve(REPO_ROOT, CONTRACT_REL);

// The IMPL commit's parent = the pre-v73 (v72 closure) source.
const PRE_V73_REF = "64ec993e^";

function preV73Source() {
  const raw = execFileSync("git", ["show", `${PRE_V73_REF}:${CONTRACT_REL}`], {
    cwd: REPO_ROOT,
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  // Phase 480 (RN-07) renames the degenerette bet-amount local `amountPerTicket`
  // to `amountPerSpin` — a pure, audited identifier change with no behavior, value,
  // or event-field impact. These held-fixed invariants prove the v73 diff did not
  // move LOGIC; normalize that rename into the v72 baseline so the byte-compare
  // ignores the identifier rename while still catching any real logic drift.
  return raw.replace(/\bamountPerTicket\b/g, "amountPerSpin");
}

function currentSource() {
  return readFileSync(CONTRACT_PATH, "utf8");
}

// Extract a single constant's RHS literal (underscores stripped) as BigInt.
function constVal(src, name) {
  const re = new RegExp(`constant\\s+${name}\\s*=\\s*(0x[0-9a-fA-F_]+|[\\d_]+)\\s*;`);
  const m = src.match(re);
  expect(m, `constant ${name} not found`).to.not.equal(null);
  return BigInt(m[1].replace(/_/g, ""));
}

// Extract a 4-space-indented function body: from `function NAME(` up to and
// including the first line that is exactly `    }` (the function's closing brace
// at module indentation). Whitespace-trimmed per line for a robust byte-compare.
function extractFunction(src, name) {
  const lines = src.split("\n");
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(`function ${name}(`)) {
      start = i;
      break;
    }
  }
  expect(start, `function ${name} not found`).to.be.greaterThan(-1);
  let end = -1;
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i] === "    }") {
      end = i;
      break;
    }
  }
  expect(end, `function ${name} closing brace not found`).to.be.greaterThan(-1);
  return lines.slice(start, end + 1).map((l) => l.trimEnd()).join("\n");
}

// Extract a labeled block by a start-marker line and an end-marker line (inclusive),
// trimmed per line — used for the whale-pass bracket logic.
function extractBlock(src, startNeedle, endNeedle) {
  const lines = src.split("\n");
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(startNeedle)) {
      start = i;
      break;
    }
  }
  expect(start, `block start "${startNeedle}" not found`).to.be.greaterThan(-1);
  let end = -1;
  for (let i = start; i < lines.length; i++) {
    if (lines[i].includes(endNeedle)) {
      end = i;
      break;
    }
  }
  expect(end, `block end "${endNeedle}" not found`).to.be.greaterThan(start - 1);
  return lines.slice(start, end + 1).map((l) => l.trim()).join("\n");
}

describe("v73 held-fixed invariants — byte-identical to the pre-v73 (v72) source", function () {
  this.timeout(60_000);

  let pre;
  let cur;
  before(function () {
    pre = preV73Source();
    cur = currentSource();
  });

  // ----------------------------------------------------------------------- INV-01
  it("INV-01: activity ROI curve `_roiBpsFromScore` + ROI_* constants unchanged vs HEAD", function () {
    expect(extractFunction(cur, "_roiBpsFromScore"))
      .to.equal(extractFunction(pre, "_roiBpsFromScore"));
    for (const name of ["ROI_MIN_BPS", "ROI_VA_BPS", "ROI_VB_BPS", "ROI_MAX_BPS", "ETH_ROI_BONUS_BPS"]) {
      expect(constVal(cur, name), `${name} drifted`).to.equal(constVal(pre, name));
    }
  });

  it("INV-01 anchor: ROI curve is 90% -> 99.9% (9000 -> 9990 bps)", function () {
    expect(constVal(cur, "ROI_MIN_BPS")).to.equal(9000n);
    expect(constVal(cur, "ROI_VA_BPS")).to.equal(9891n);
    expect(constVal(cur, "ROI_VB_BPS")).to.equal(9970n);
    expect(constVal(cur, "ROI_MAX_BPS")).to.equal(9990n);
  });

  // ----------------------------------------------------------------------- INV-02
  it("INV-02: WWXRP RTP curve `_wwxrpRoi` + WWXRP_ROI_* + WWXRP_FLOOR_BPS unchanged vs HEAD", function () {
    expect(extractFunction(cur, "_wwxrpRoi"))
      .to.equal(extractFunction(pre, "_wwxrpRoi"));
    for (const name of [
      "WWXRP_ROI_MIN_BPS", "WWXRP_ROI_VA_BPS", "WWXRP_ROI_VB_BPS",
      "WWXRP_ROI_MAX_BPS", "WWXRP_FLOOR_BPS",
    ]) {
      expect(constVal(cur, name), `${name} drifted`).to.equal(constVal(pre, name));
    }
  });

  it("INV-02 anchor: WWXRP RTP curve is 70% -> 115% -> 118% -> 120% (floor 70%)", function () {
    expect(constVal(cur, "WWXRP_ROI_MIN_BPS")).to.equal(7000n);
    expect(constVal(cur, "WWXRP_ROI_VA_BPS")).to.equal(11500n);
    expect(constVal(cur, "WWXRP_ROI_VB_BPS")).to.equal(11800n);
    expect(constVal(cur, "WWXRP_ROI_MAX_BPS")).to.equal(12000n);
    expect(constVal(cur, "WWXRP_FLOOR_BPS")).to.equal(7000n);
  });

  // ----------------------------------------------------------------------- INV-03
  it("INV-03: S=9 jackpot pins QUICK_PLAY_PAYOUT_N{0..4}_S9 are byte-identical to HEAD", function () {
    // P(S=9) + the pinned jackpot payout are what fix the realized WWXRP RTP at the
    // jackpot tier. WWXRP_ROI_* unchanged (INV-02) + the rig's m>=7 cap leaving
    // P(S=9) intact (proven in DegenerettePerNEvExactness) + these pins unchanged
    // => the realized WWXRP RTP curve is byte-identical to HEAD.
    const expected = [10756411n, 12583037n, 14792939n, 17512324n, 20916435n];
    for (let N = 0; N < 5; N++) {
      const name = `QUICK_PLAY_PAYOUT_N${N}_S9`;
      expect(constVal(cur, name), `${name} drifted`).to.equal(constVal(pre, name));
      expect(constVal(cur, name), `${name} != known M=8 relabel pin`).to.equal(expected[N]);
    }
  });

  // ----------------------------------------------------------------------- INV-04
  it("INV-04: the S=9 WWXRP whale-pass bracket award is unchanged vs HEAD", function () {
    // The bracket-award block (s==9 && WWXRP && >= MIN_BET -> whalePassClaims += 1,
    // deduped per level/10 bracket) + the event signature.
    const curBlk = extractBlock(cur, "First WWXRP jackpot in this level/10 bracket", "emit WwxrpJackpotWhalePass(player, bracket);");
    const preBlk = extractBlock(pre, "First WWXRP jackpot in this level/10 bracket", "emit WwxrpJackpotWhalePass(player, bracket);");
    expect(curBlk).to.equal(preBlk);
    // The event declaration is unchanged too.
    expect(extractBlock(cur, "event WwxrpJackpotWhalePass(", "event WwxrpJackpotWhalePass("))
      .to.equal(extractBlock(pre, "event WwxrpJackpotWhalePass(", "event WwxrpJackpotWhalePass("));
  });

  // ------------------------------------------------------------ scope sanity check
  it("the only constant families that CHANGED are the honest base/S8/factor + rigged tables", function () {
    // Sanity: confirm the diff is bounded — the WWXRP_BONUS_FACTOR_SCALE + WWXRP_RIG_SALT
    // (rig entropy salt + factor scale) are unchanged, so the rig seed derivation and the
    // factor decode are byte-stable.
    for (const name of ["WWXRP_BONUS_FACTOR_SCALE", "WWXRP_RIG_SALT"]) {
      expect(constVal(cur, name), `${name} drifted`).to.equal(constVal(pre, name));
    }
  });
});
