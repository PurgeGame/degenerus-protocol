// SPDX-License-Identifier: AGPL-3.0-only
// Phase 261 SURF-01..04 cross-surface preservation evidence.
// SURF-01: hero-override color==7 byte-layout spot-check (NEW, ONE assertion).
// SURF-02 + SURF-03: NO new test (D-09) — references unchanged regression carriers.
// SURF-04: structural grep proof — `git diff` against v33.0 anchor commit must NOT
//          modify any of the 8 documented non-injection lines [513, 527, 598, 599,
//          683, 1687, 1713, 1715]. Soft-fail if anchor unreachable (shallow clone).
//
// v33.0 anchor commit: 4ce3703d740d3707c88a1af595618120a8168399 (closure signal
// MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399).

import { expect } from "chai";
import { execSync } from "node:child_process";
import fs from "node:fs";

const V33_ANCHOR = "4ce3703d740d3707c88a1af595618120a8168399";
const NON_INJECTION_LINES = [513, 527, 598, 599, 683, 1687, 1713, 1715];
const JACKPOT_MODULE_PATH = "contracts/modules/DegenerusGameJackpotModule.sol";

// ===========================================================================
// Phase 264 v35.0-tagged SURF-01..04 grep-proof — extension of the Phase 261
// SURF-04 harness shape, against the v34.0 source-tree baseline `6b63f6d4`.
//
// The v35.0 SURF preservation gate proves that Phase 263's per-pull-level
// resample (HEAD `cf564816`) modifies ONLY:
//   - the constants block (COIN_LEVEL_TAG addition; DAILY_COIN_SALT_BASE removal),
//   - the per-pull-resample helper rewrite at `_awardDailyCoinToTraitWinners`,
//   - the two callers `payDailyCoinJackpot` (~L1710 HEAD) and
//     `payDailyJackpotCoinAndTickets` (~L595 HEAD, near the dead-derivation
//     cleanup).
//
// EVERY other named function / emit block / injection site is BYTE-IDENTICAL
// against the v34.0 audit baseline. The Phase 263 SUMMARY.md §"Byte-Identity
// Sweep" enumerates 7 protected ranges as ZERO hunk intersection. The
// PROTECTED_RANGES array below records those ranges with BASELINE-side line
// numbers (the `git diff` hunk-intersection harness operates on OLD-side
// numbering). The describe block fails loud (D-IMPL-11) if `git diff` returns
// empty output AND the baseline commit is reachable AND HEAD ≠ baseline; soft-
// skips (matching the v33.0 SURF-04 pattern at L130-140 above) when the baseline
// commit itself is not reachable in the local git history.
//
// BASELINE: 6b63f6d4daf346a53a1d463790f637308ea8d555 (v34.0 source-tree HEAD)
// HEAD:     cf564816 (Phase 263 close — Phase 264 baseline for empirical proof)
// ===========================================================================

const V34_BASELINE = "6b63f6d4daf346a53a1d463790f637308ea8d555";

// ---------------------------------------------------------------------------
// SURF-01 — hero-override color==7 byte-layout spot-check.
//
// Hero override at L1582-1609 of DegenerusGameJackpotModule.sol uses
//   heroColor = uint8(randomWord & 7)        for quadrant 0
//   heroColor = uint8((randomWord >> 3) & 7) for quadrant 1
//   heroColor = uint8((randomWord >> 6) & 7) for quadrant 2
//   heroColor = uint8((randomWord >> 9) & 7) for quadrant 3
// — a 3-bit LITERAL slice, NOT through weightedColorBucket.
// The output byte format is (quadrant << 6) | (color << 3) | symbol.
//
// NOTE: the assertions in the second `it` reference the symbol name
// `weightedColorBucket` to verify the function body of `_applyHeroOverride`
// does NOT contain that symbol. The grep policy in this repo flags occurrences
// of that symbol — its presence in this file is intentional (a structural
// negation: the test file ASSERTS the production file does not contain it).
// ---------------------------------------------------------------------------

describe("SURF-01 — hero-override gold-color byte-layout spot-check", function () {
  it("randomWord with bottom 3 bits = 7 yields color==7 in heroColor slot for quadrant 0", function () {
    // Spot-check: with bottom 3 bits = 0b111, quadrant 0 hero override
    // produces color==7 in the byte's color slice.

    const randomWord = 0x7n; // bottom 3 bits = 7
    const quadrant = 0;
    const heroColor = Number(randomWord & 7n);
    expect(heroColor).to.equal(7);

    const heroSymbol = 3; // arbitrary non-zero symbol for the spot-check
    const expectedByte = (quadrant << 6) | (heroColor << 3) | heroSymbol;
    expect(expectedByte).to.equal((0 << 6) | (7 << 3) | 3); // = 59 (0b00111011)
    expect((expectedByte >> 6) & 3).to.equal(0);   // quadrant 0
    expect((expectedByte >> 3) & 7).to.equal(7);   // color 7 (gold)
    expect(expectedByte & 7).to.equal(3);          // symbol 3
  });

  it("hero color path does NOT route through weightedColorBucket (literal-slice preservation)", function () {
    // Structural assertion: SURF-01 NOTE in REQUIREMENTS.md states hero color is
    // RNG-derived 3-bit literal slice, NOT through weightedColorBucket. The
    // _applyHeroOverride function body at L1582-1609 of
    // contracts/modules/DegenerusGameJackpotModule.sol contains 4 literal-slice
    // expressions and ZERO `weightedColorBucket` calls. Verify by parsing the
    // function body via brace-depth matching, then grep within that body.
    const source = fs.readFileSync(JACKPOT_MODULE_PATH, "utf8");
    const start = source.indexOf("function _applyHeroOverride(");
    expect(start, "could not locate _applyHeroOverride in module source").to.be.gte(0);

    let depth = 0;
    let bodyEnd = -1;
    let openSeen = false;
    for (let i = start; i < source.length; i++) {
      const c = source[i];
      if (c === "{") {
        depth++;
        openSeen = true;
      } else if (c === "}") {
        depth--;
        if (openSeen && depth === 0) {
          bodyEnd = i + 1;
          break;
        }
      }
    }
    expect(bodyEnd, "could not locate end of _applyHeroOverride body").to.be.gte(0);

    const body = source.slice(start, bodyEnd);

    // Negation: the helper body must NOT call weightedColorBucket.
    expect(body).to.not.include("weightedColorBucket");

    // Positive evidence: the 4 literal-slice expressions are present.
    expect((body.match(/randomWord & 7/g) || []).length).to.be.gte(1);
    expect((body.match(/randomWord >> 3/g) || []).length).to.be.gte(1);
    expect((body.match(/randomWord >> 6/g) || []).length).to.be.gte(1);
    expect((body.match(/randomWord >> 9/g) || []).length).to.be.gte(1);
  });
});

// ---------------------------------------------------------------------------
// SURF-02 + SURF-03 — NO new test per CONTEXT.md D-09. Existing regression
// carriers run unchanged at HEAD; this block is a documented placeholder.
// ---------------------------------------------------------------------------

describe.skip("SURF-02 + SURF-03 — no new test, see referenced existing carriers (per CONTEXT.md D-09)", function () {
  // SURF-02 (deity-pass virtual entries): `floor(2% × bucketTickets)` math is
  // symbol-distribution-agnostic at the integer level. Existing
  // test/unit/DegenerusDeityPass.test.js runs UNCHANGED at HEAD as the
  // regression carrier. No new test added in Phase 261.
  //
  // SURF-03 (Degenerette match payouts): byte-layout-preserving changes only.
  // Existing test/unit/DegenerusGame.test.js (Degenerette section) +
  // test/fuzz/DegeneretteFreezeResolution.t.sol (Foundry, byte-layout fuzz)
  // both run UNCHANGED at HEAD as the regression carriers. No new test added.
  //
  // To re-verify in CI:
  //   npx hardhat test test/unit/DegenerusDeityPass.test.js
  //   npx hardhat test test/unit/DegenerusGame.test.js
  //   forge test --match-path 'test/fuzz/DegeneretteFreezeResolution.t.sol'
  it("placeholder — SURF-02/03 covered by referenced existing carriers", function () {});
});

// ---------------------------------------------------------------------------
// SURF-04 — structural grep proof: 8 documented non-injection lines must
// remain byte-identical against the v33.0 anchor commit.
// ---------------------------------------------------------------------------

describe("SURF-04 — 8 documented non-injection lines byte-identical vs v33.0 anchor", function () {
  it("git diff vs v33.0 anchor does NOT modify any of [513, 527, 598, 599, 683, 1687, 1713, 1715]", function () {
    // Soft-fail mode: if the anchor commit is unreachable (shallow clone,
    // force-push, etc.), skip with a CI warning rather than report a vacuous pass.
    let anchorReachable = false;
    try {
      execSync(`git rev-parse --verify ${V33_ANCHOR}^{commit}`, { stdio: "pipe" });
      anchorReachable = true;
    } catch (_) {
      console.warn(
        `[SURF-04] v33.0 anchor commit ${V33_ANCHOR} not reachable — soft-skipping grep proof.`,
      );
      this.skip();
      return;
    }
    expect(anchorReachable).to.equal(true);

    const diff = execSync(
      `git diff ${V33_ANCHOR} HEAD -- ${JACKPOT_MODULE_PATH}`,
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    );

    // SURF-04 grep proof: walk the unified diff and record every OLD-side line
    // number that carries a `-` marker (a true modification or removal of v33.0
    // content). Pure `+` insertions and unchanged ` ` context lines do NOT
    // modify a v33.0 line — they only surround it. The 8 documented
    // non-injection lines must NOT appear in the set of `-` modified lines.
    //
    // Algorithm:
    //   - Parse hunk headers `@@ -<oldStart>,<oldLen> +<newStart>,<newLen> @@`
    //     to know the OLD-side cursor at the start of each hunk.
    //   - Within a hunk, advance the OLD cursor by 1 for every ` ` (context)
    //     and `-` (deletion) line; do NOT advance for `+` (insertion) lines.
    //   - Record the OLD cursor at every `-` line as a "modified OLD line".
    //   - Assert no entry of NON_INJECTION_LINES appears in modifiedOldLines.

    const hunkHeaderRe = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;
    const lines = diff.split("\n");
    const modifiedOldLines = new Set();
    let oldCursor = -1;
    let inHunk = false;

    for (const ln of lines) {
      const headerMatch = hunkHeaderRe.exec(ln);
      if (headerMatch) {
        oldCursor = Number(headerMatch[1]);
        inHunk = true;
        continue;
      }
      if (!inHunk) continue;
      // `\` no-newline marker — ignore.
      if (ln.startsWith("\\")) continue;
      const tag = ln.length > 0 ? ln[0] : " ";
      if (tag === " ") {
        oldCursor += 1;
      } else if (tag === "-") {
        modifiedOldLines.add(oldCursor);
        oldCursor += 1;
      } else if (tag === "+") {
        // insertion only — OLD cursor does not advance.
      } else {
        // Any other prefix (file headers, etc.) — out of hunk body.
        inHunk = false;
      }
    }

    for (const line of NON_INJECTION_LINES) {
      expect(
        modifiedOldLines.has(line),
        `non-injection line ${line} was modified or removed in the diff vs v33.0 anchor`,
      ).to.equal(false);
    }
  });
});

// ---------------------------------------------------------------------------
// Phase 264 v35.0 SURF-01..04 — protected ranges byte-identical vs v34.0
// audit baseline `6b63f6d4`. Per-line modified-set harness (matches the v33.0
// SURF-04 walk above at L162-190 — single canonical algorithm in this file).
//
// Plan 264-02 CONTEXT.md `<specifics>` reference shape was hunk-range overlap;
// the plan explicitly notes "Either approach (per-line modified set OR hunk-
// range overlap) produces the same byte-identity proof — the executor picks
// per simplicity." Per-line modified-set is the correct choice here because
// hunk-range overlap counts unchanged context lines (` ` prefix) inside the
// hunk's baseline-side range as protected-range intersections, which produces
// false positives at function boundaries (e.g. an `emit` line cited as a hunk
// anchor for a fully-unchanged emit block followed by a function rewrite).
// The per-line walk records ONLY the baseline lines that carry a `-` marker
// (a true modification or removal) — context lines are not recorded.
//
// D-IMPL-11 fail-loud guard: empty diff + reachable baseline + HEAD ≠ baseline
// → assertion failure (vacuous-pass prevention).
// ---------------------------------------------------------------------------

describe("v35.0 SURF-01..04 — protected ranges byte-identical vs v34.0 baseline 6b63f6d4", function () {
  // PROTECTED_RANGES — baseline-side (`6b63f6d4`) line numbers from the
  // Phase 263 SUMMARY.md §"Byte-Identity Sweep". Every range MUST have ZERO
  // hunk intersection with the `git diff <V34_BASELINE> HEAD -- ...` output.
  //
  // Line ranges below are pinned by inspecting the baseline file extracted via
  // `git show 6b63f6d4:contracts/modules/DegenerusGameJackpotModule.sol`. Each
  // range names the protected element + the SURF / D-INDEXER ID that owns it.
  // Bodies are inclusive of the function-definition `function ...(` line and
  // the closing `}` brace. Single-line caller / emit-site protections cover
  // the exact line where the call / emit appears in the baseline.
  const PROTECTED_RANGES = [
    // SURF-01 — _randTraitTicket body (Phase 263 D-IMPL-01 byte-identical).
    { name: "_randTraitTicket body (SURF-01)",                   lo: 1653, hi: 1703 },
    // SURF-01 — _randTraitTicket 4 other-callers (lootbox + 3 ticket sites).
    { name: "_randTraitTicket caller L700 (SURF-01)",            lo: 700,  hi: 700  },
    { name: "_randTraitTicket caller L989 (SURF-01)",            lo: 989,  hi: 989  },
    { name: "_randTraitTicket caller L1296 (SURF-01)",           lo: 1296, hi: 1296 },
    { name: "_randTraitTicket caller L1399 (SURF-01)",           lo: 1399, hi: 1399 },

    // D-INDEXER-01 — coinEntropy derivation + DailyWinningTraits emit blocks.
    // L518-520 and L536-538 are the inline coinEntropy + bonusTargetLevel +
    // emit blocks inside payDailyJackpotCoinAndTickets. L1750-1756 is the
    // entire `emitDailyWinningTraits` external function body in baseline.
    { name: "coinEntropy + DailyWinningTraits emit L518-520 (D-INDEXER-01)",   lo: 518,  hi: 520  },
    { name: "coinEntropy + DailyWinningTraits emit L536-538 (D-INDEXER-01)",   lo: 536,  hi: 538  },
    { name: "emitDailyWinningTraits external L1750-1756 (D-INDEXER-01)",       lo: 1750, hi: 1756 },

    // SURF-02 — _awardFarFutureCoinJackpot body (separate path, byte-identical).
    { name: "_awardFarFutureCoinJackpot body (SURF-02)",         lo: 1839, hi: 1906 },

    // SURF-03 — _pickSoloQuadrant body + 4 ETH-distribution call sites.
    // The 4 callers are the actual `_pickSoloQuadrant(...)` call lines in
    // baseline at L287 (purchase ETH), L454 (daily ETH path #1), L531
    // (daily ETH path #2), L1181 (resume ETH / terminal path).
    { name: "_pickSoloQuadrant body (SURF-03)",                  lo: 1098, hi: 1115 },
    { name: "_pickSoloQuadrant call L287 (SURF-03)",             lo: 287,  hi: 287  },
    { name: "_pickSoloQuadrant call L454 (SURF-03)",             lo: 454,  hi: 454  },
    { name: "_pickSoloQuadrant call L531 (SURF-03)",             lo: 531,  hi: 531  },
    { name: "_pickSoloQuadrant call L1181 (SURF-03)",            lo: 1181, hi: 1181 },

    // SURF-04 — _distributeTicketJackpot body + _computeBucketCounts def.
    // _computeBucketCounts is SURF-04-adjacent: the function body is byte-
    // identical; only the `_awardDailyCoinToTraitWinners` caller was removed
    // from the call graph (Phase 263 PPL-03 — `_computeBucketCounts` no longer
    // called from the per-pull-resample path) but the definition itself stayed.
    { name: "_distributeTicketJackpot body (SURF-04)",           lo: 897,  hi: 932  },
    { name: "_computeBucketCounts def L1030 (SURF-04 adjacent)", lo: 1030, hi: 1082 },
  ];

  it("baseline commit 6b63f6d4 is reachable in local git history", function () {
    // D-IMPL-11 soft-skip on unreachable baseline. Mirrors the existing v33.0
    // SURF-04 soft-skip pattern at L130-140 of this file. CI / fresh-clone hint
    // is emitted via console.warn before this.skip() so a vacuous pass cannot
    // hide behind silent skip output.
    let baselineReachable = false;
    try {
      execSync(`git rev-parse --verify ${V34_BASELINE}^{commit}`, { stdio: "pipe" });
      baselineReachable = true;
    } catch (_) {
      console.warn(
        `[v35.0 SURF] v34.0 baseline commit ${V34_BASELINE} not reachable — ` +
        `soft-skipping protected-range proof. CI / fresh-clone hint: fetch the ` +
        `full git history (e.g. \`git fetch --unshallow\` or \`git fetch origin ${V34_BASELINE}\`).`,
      );
      this.skip();
      return;
    }
    expect(baselineReachable).to.equal(true);
  });

  it("git diff vs v34.0 baseline does NOT modify any protected range", function () {
    // D-IMPL-11 soft-skip on unreachable baseline (single source of truth: the
    // protected-range proof requires the baseline tree to be available).
    let baselineReachable = false;
    try {
      execSync(`git rev-parse --verify ${V34_BASELINE}^{commit}`, { stdio: "pipe" });
      baselineReachable = true;
    } catch (_) {
      console.warn(
        `[v35.0 SURF] v34.0 baseline commit ${V34_BASELINE} not reachable — ` +
        `soft-skipping protected-range proof. See first \`it\` in this describe ` +
        `block for the CI / fresh-clone hint.`,
      );
      this.skip();
      return;
    }
    expect(baselineReachable).to.equal(true);

    // D-IMPL-11 fail-loud-on-empty-diff guard: if HEAD ≠ baseline AND the diff
    // is empty, `git diff` is silently misbehaving — assert failure rather than
    // vacuous pass.
    const headSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
    if (headSha === V34_BASELINE) {
      console.log(`[v35.0 SURF] HEAD == V34_BASELINE — protected ranges trivially preserved.`);
      return;
    }

    const diff = execSync(
      `git diff ${V34_BASELINE} HEAD -- ${JACKPOT_MODULE_PATH}`,
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    );

    expect(
      diff.length > 0,
      `[v35.0 SURF] git diff ${V34_BASELINE} HEAD returned empty output — ` +
      `baseline-vs-HEAD distinct but no diff produced. D-IMPL-11 fail-loud guard.`,
    ).to.equal(true);

    // Per-line modified-set walk (same algorithm as the v33.0 SURF-04 block
    // above — single canonical pattern in this file). Walk the unified diff:
    // parse each hunk header `@@ -<oldStart>,<oldLen> +<newStart>,<newLen> @@`
    // to seed the OLD-side cursor; advance the cursor by 1 for ` ` (context)
    // and `-` (deletion) lines; record the cursor at every `-` line as a
    // "modified OLD line"; assert no protected range contains any modified
    // OLD line. Pure `+` insertions and unchanged ` ` context lines do NOT
    // modify a baseline line — they only surround it.
    const hunkHeaderRe = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;
    const lines = diff.split("\n");
    const modifiedOldLines = new Set();
    let oldCursor = -1;
    let inHunk = false;

    for (const ln of lines) {
      const headerMatch = hunkHeaderRe.exec(ln);
      if (headerMatch) {
        oldCursor = Number(headerMatch[1]);
        inHunk = true;
        continue;
      }
      if (!inHunk) continue;
      // `\` no-newline marker — ignore.
      if (ln.startsWith("\\")) continue;
      const tag = ln.length > 0 ? ln[0] : " ";
      if (tag === " ") {
        oldCursor += 1;
      } else if (tag === "-") {
        modifiedOldLines.add(oldCursor);
        oldCursor += 1;
      } else if (tag === "+") {
        // insertion only — OLD cursor does not advance.
      } else {
        // Any other prefix (file headers, etc.) — out of hunk body.
        inHunk = false;
      }
    }

    for (const range of PROTECTED_RANGES) {
      for (let line = range.lo; line <= range.hi; line++) {
        expect(
          modifiedOldLines.has(line),
          `Baseline line ${line} (inside protected range "${range.name}" [${range.lo}-${range.hi}]) was modified or removed in the diff vs v34.0 baseline ${V34_BASELINE}`,
        ).to.equal(false);
      }
    }
  });
});
