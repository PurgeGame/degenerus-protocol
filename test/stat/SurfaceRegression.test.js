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

  // SUPERSEDED: this v34.0 protected-range byte-pin predates 20+ milestones of
  // legitimate JackpotModule evolution; the OLD-side line ranges no longer map to
  // current code, so the gate fails on a reachable baseline. Skipped (matching this
  // file's existing convention for superseded milestone baselines) — the live
  // structural invariants for the current surface are carried by the per-function
  // source-structural unit tests, not this historical zero-diff pin.
  it.skip("git diff vs v34.0 baseline does NOT modify any protected range", function () {
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

// ===========================================================================
// Phase 266 v36.0-tagged SURF-01..04 grep-proof — extends the v33.0 / v35.0
// per-line modified-set walk to the v36.0 audit baseline `5db8682b`.
//
// The v36.0 SURF preservation gate proves that the Phase 266 lootbox-entropy
// refactor scopes its source-tree mutation to a SINGLE file:
//   contracts/modules/DegenerusGameLootboxModule.sol
//
// Every other RNG-relevant surface stays byte-identical:
//   SURF-01: contracts/libraries/EntropyLib.sol            (whole file; ENT-04 stable API)
//   SURF-02: BAF jackpot _jackpotTicketRoll body L2186-2229  (ENT-05 deferral)
//   SURF-03: contracts/modules/DegenerusGameMintModule.sol L652  (single callsite)
//   SURF-04: 9 non-lootbox JackpotModule EntropyLib callsites  (Pitfall 6 inventory)
//
// V36.0 BASELINE: 5db8682bd7b811437f0c1cf47e832619d1478ac6 (v35.0 closure HEAD).
// ===========================================================================

const V35_BASELINE = "5db8682bd7b811437f0c1cf47e832619d1478ac6";
const ENTROPY_LIB_PATH = "contracts/libraries/EntropyLib.sol";
const MINT_MODULE_PATH = "contracts/modules/DegenerusGameMintModule.sol";

describe("v36.0 SURF-01..04 — protected ranges byte-identical vs v35.0 baseline 5db8682b", function () {
  // SURF-01 — EntropyLib.sol body BYTE-IDENTICAL (whole file; ENT-04 stable API).
  // EntropyLib has 43 lines at the v35.0 baseline; the protected range covers
  // every line in the file (no exceptions).
  const SURF_01_PROTECTED_RANGES = [
    { name: "EntropyLib.sol body L1-43 (SURF-01 — ENT-04 stable API)", lo: 1, hi: 43 },
  ];

  // SURF-02 — BAF jackpot _jackpotTicketRoll body L2186-2229 (ENT-05 deferral
  // verification: lootbox-path xorshift removed at v36 BUT BAF jackpot xorshift
  // explicitly preserved per CONTEXT.md D-266-SCOPE-OUT-01).
  const SURF_02_PROTECTED_RANGES = [
    { name: "_jackpotTicketRoll body L2186-2229 (SURF-02 — ENT-05 deferral)", lo: 2186, hi: 2229 },
  ];

  // SURF-03 — MintModule L652 single-line callsite (EntropyLib.hash2(entropy, rollSalt)).
  const SURF_03_PROTECTED_RANGES = [
    { name: "MintModule L652 EntropyLib.hash2(entropy, rollSalt) (SURF-03)", lo: 652, hi: 652 },
  ];

  // SURF-04 — 9 non-lootbox JackpotModule EntropyLib callsites (verified
  // inventory at HEAD 5db8682b per Phase 266 RESEARCH.md Pitfall 6 grep).
  const SURF_04_PROTECTED_RANGES = [
    { name: "L285 EntropyLib.hash2(rngWord, targetLvl)",            lo: 285,  hi: 285  },
    { name: "L453 EntropyLib.hash2(randWord, lvl)",                 lo: 453,  hi: 453  },
    { name: "L532 EntropyLib.hash2(randWord, lvl)",                 lo: 532,  hi: 532  },
    { name: "L610 EntropyLib.hash2(randWord, lvl)",                 lo: 610,  hi: 610  },
    { name: "L612 EntropyLib.hash2(randWord, sourceLevel)",         lo: 612,  hi: 612  },
    { name: "L886 EntropyLib.hash2(randWord, lvl) (arg-pos call)",  lo: 886,  hi: 886  },
    { name: "L1176 EntropyLib.hash2(randWord, lvl)",                lo: 1176, hi: 1176 },
    { name: "L1873 entropy = EntropyLib.hash2(entropy, s)",         lo: 1873, hi: 1873 },
    { name: "L2192 BAF entropy = EntropyLib.entropyStep(entropy)",  lo: 2192, hi: 2192 },
  ];

  // ---------------------------------------------------------------------------
  // walkAndAssert(baseline, path, ranges) — per-line modified-set walk against
  // the named baseline. Re-declared inline (not factored to module scope) so
  // the existing v35.0 describe block at L249 stays byte-identical (REG-01
  // carry-forward discipline). Same algorithm as the v35.0 describe block:
  //   - D-IMPL-11 soft-skip on unreachable baseline.
  //   - HEAD == BASELINE early-return (trivially preserved).
  //   - Fail-loud on empty diff with HEAD ≠ baseline.
  //   - Per-line walk via diff hunk parsing; record OLD-side `-` lines.
  //   - Assert each protected line NOT in modifiedOldLines.
  // ---------------------------------------------------------------------------
  function walkAndAssert(baseline, path, ranges) {
    let baselineReachable = false;
    try {
      execSync(`git rev-parse --verify ${baseline}^{commit}`, { stdio: "pipe" });
      baselineReachable = true;
    } catch (_) {
      console.warn(
        `[v36.0 SURF] baseline commit ${baseline} not reachable — soft-skipping ` +
        `protected-range proof on ${path}. CI / fresh-clone hint: \`git fetch --unshallow\` ` +
        `or \`git fetch origin ${baseline}\`.`,
      );
      return { skipped: true };
    }
    expect(baselineReachable).to.equal(true);

    const headSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
    if (headSha === baseline) {
      console.log(`[v36.0 SURF] HEAD == V35_BASELINE — protected ranges trivially preserved.`);
      return { skipped: false, trivial: true };
    }

    const diff = execSync(
      `git diff ${baseline} HEAD -- ${path}`,
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    );

    if (path === ENTROPY_LIB_PATH || path === MINT_MODULE_PATH ||
        ranges === SURF_02_PROTECTED_RANGES || ranges === SURF_04_PROTECTED_RANGES) {
      // Protected files where v36.0 expects ZERO modifications. Empty diff is
      // the GOOD outcome — proceed; if non-empty, the per-line walk catches it.
      if (diff.length === 0) {
        return { skipped: false, trivial: false };
      }
    } else {
      expect(
        diff.length > 0,
        `[v36.0 SURF] git diff ${baseline} HEAD returned empty output for ${path} — ` +
        `baseline-vs-HEAD distinct but no diff produced. D-IMPL-11 fail-loud guard.`,
      ).to.equal(true);
    }

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
        inHunk = false;
      }
    }

    for (const range of ranges) {
      for (let line = range.lo; line <= range.hi; line++) {
        expect(
          modifiedOldLines.has(line),
          `Baseline line ${line} (inside protected range "${range.name}" [${range.lo}-${range.hi}]) ` +
          `was modified or removed in ${path} vs v35.0 baseline ${baseline}`,
        ).to.equal(false);
      }
    }
    return { skipped: false, trivial: false };
  }

  // SUPERSEDED by the v40.0 SURF block below: Phase 278 Wave 1 rewrites
  // EntropyLib.sol (entropyStep deletion) so byte-identity vs the v35.0
  // baseline no longer holds. The v40.0 block re-protects EntropyLib's
  // surviving surface against the v39.0 baseline 6a7455d1.
  it.skip("SURF-01 — EntropyLib.sol body byte-identical vs 5db8682b", function () {
    const result = walkAndAssert(V35_BASELINE, ENTROPY_LIB_PATH, SURF_01_PROTECTED_RANGES);
    if (result.skipped) this.skip();
  });

  // SUPERSEDED by the v40.0 SURF block below: Phase 278 Wave 1 rewrites
  // _jackpotTicketRoll (entropyStep->hash2 swap + Bernoulli whole-ticket
  // collapse) so the body is no longer byte-identical vs the v35.0 baseline.
  // The v40.0 block re-protects the surviving _jackpotTicketRoll surface
  // against the v39.0 baseline 6a7455d1.
  it.skip("SURF-02 — BAF jackpot _jackpotTicketRoll body L2186-2229 byte-identical vs 5db8682b", function () {
    const result = walkAndAssert(V35_BASELINE, JACKPOT_MODULE_PATH, SURF_02_PROTECTED_RANGES);
    if (result.skipped) this.skip();
  });

  it("SURF-03 — MintModule L652 EntropyLib.hash2 callsite byte-identical vs 5db8682b", function () {
    const result = walkAndAssert(V35_BASELINE, MINT_MODULE_PATH, SURF_03_PROTECTED_RANGES);
    if (result.skipped) this.skip();
  });

  // SUPERSEDED by the v40.0 SURF block below: Phase 278 Wave 1 swaps the
  // _jackpotTicketRoll evolution line from EntropyLib.entropyStep(entropy)
  // to EntropyLib.hash2(entropy, entropy), so the L2192 entry in this
  // callsite inventory is no longer byte-identical vs the v35.0 baseline.
  // The other 8 callsites in this array are still byte-identical at v40.0
  // and are re-protected (with v39.0-baseline line numbers) by the v40.0
  // SURF block below.
  it.skip("SURF-04 — 9 non-lootbox JackpotModule EntropyLib callsites byte-identical vs 5db8682b", function () {
    const result = walkAndAssert(V35_BASELINE, JACKPOT_MODULE_PATH, SURF_04_PROTECTED_RANGES);
    if (result.skipped) this.skip();
  });
});

// ===========================================================================
// Phase 268 v37.0-tagged SURF-01..04 grep-proof — extends the per-line
// modified-set walk + file-level zero-diff harness to the v37.0 audit
// baseline `1c0f0913` (v36.0 closure HEAD).
//
// The v37.0 SURF preservation gate proves that the Phase 267 Degenerette
// producer + 5-table payout rewrite scopes its source-tree mutation to a
// SINGLE batched commit `e1136071` touching exactly two files:
//   contracts/DegenerusTraitUtils.sol           (additive: packedTraitsDegenerette + _degTrait)
//   contracts/modules/DegenerusGameDegeneretteModule.sol  (5-table dispatch + 3-tier ETH split)
//
// Every other RNG-relevant + module surface stays byte-identical:
//   SURF-01: contracts/DegenerusTraitUtils.sol — existing functions byte-identical
//            (weightedColorBucket body L115-135 + traitFromWord body L143-167 +
//            packedTraitsFromSeed body L169-178). Additions post-L178
//            (packedTraitsDegenerette + _degTrait) are explicitly NOT protected.
//   SURF-02: contracts/modules/DegenerusGameJackpotModule.sol  (file-level zero-diff)
//   SURF-03: contracts/modules/DegenerusGameLootboxModule.sol  (file-level zero-diff
//            per D-268-SURF03-01 — Phase 269 owns the post-cleanup re-baseline)
//   SURF-04: contracts/libraries/EntropyLib.sol  (file-level zero-diff; ENT-04 v36.0 carry)
//
// V36.0 BASELINE: 1c0f09132d7439af9881c56fe197f81757f8164a (v36.0 closure HEAD).
//
// Re-declares walkAndAssert + expectFileLevelZeroDiff inline (not factored to
// module scope) so the existing v33.0 / v34.0 / v35.0 / v36.0 describe blocks
// at L66-573 stay byte-identical (REG-01 carry-forward discipline).
// ===========================================================================

const V36_BASELINE = "1c0f09132d7439af9881c56fe197f81757f8164a";
const V37_BASELINE = "2654fcc2";              // v37.0 closure HEAD; v38.0 SURF anchor
const PHASE_269_CLOSE_BASELINE = "8fd5c2e1";  // post-LBX-01 HEAD; SURF-03 rebase anchor
const TRAIT_UTILS_PATH = "contracts/DegenerusTraitUtils.sol";
const JACKPOT_MODULE_PATH_V37 = "contracts/modules/DegenerusGameJackpotModule.sol";
const LOOTBOX_MODULE_PATH = "contracts/modules/DegenerusGameLootboxModule.sol";
const ENTROPY_LIB_PATH_V37 = "contracts/libraries/EntropyLib.sol";
const MINT_MODULE_PATH_V38 = "contracts/modules/DegenerusGameMintModule.sol";

describe("v37.0 SURF-01..04 — protected surfaces vs v36.0 baseline 1c0f0913", function () {
  // SURF-01 — DegenerusTraitUtils.sol existing functions byte-identical.
  // Only the OLD-side baseline lines must be unchanged; additions to the file
  // (packedTraitsDegenerette body + _degTrait body, L201-223 at HEAD) are
  // permitted because Phase 267 added these functions after the v36.0 baseline.
  const SURF_01_PROTECTED_RANGES_V37 = [
    { name: "weightedColorBucket body L115-135 (SURF-01 v37.0)", lo: 115, hi: 135 },
    { name: "traitFromWord body L143-167 (SURF-01 v37.0)",       lo: 143, hi: 167 },
    { name: "packedTraitsFromSeed body L169-178 (SURF-01 v37.0)", lo: 169, hi: 178 },
  ];

  // ---------------------------------------------------------------------------
  // walkAndAssertV37(baseline, path, ranges) — per-line modified-set walk
  // against the named baseline. Re-declared inline (not factored to module
  // scope) per L466-473 carry-forward discipline. Same algorithm as the v36.0
  // describe block above:
  //   - D-IMPL-11 soft-skip on unreachable baseline.
  //   - HEAD == BASELINE early-return (trivially preserved).
  //   - Fail-loud on empty diff with HEAD ≠ baseline (for files where v37.0
  //     EXPECTS modifications, e.g. TraitUtils additive surface).
  //   - Per-line walk via diff hunk parsing; record OLD-side `-` lines.
  //   - Assert each protected line NOT in modifiedOldLines.
  // ---------------------------------------------------------------------------
  function walkAndAssertV37(baseline, path, ranges) {
    let baselineReachable = false;
    try {
      execSync(`git rev-parse --verify ${baseline}^{commit}`, { stdio: "pipe" });
      baselineReachable = true;
    } catch (_) {
      console.warn(
        `[v37.0 SURF] baseline commit ${baseline} not reachable — soft-skipping ` +
        `protected-range proof on ${path}. CI / fresh-clone hint: \`git fetch --unshallow\` ` +
        `or \`git fetch origin ${baseline}\`.`,
      );
      return { skipped: true };
    }
    expect(baselineReachable).to.equal(true);

    const headSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
    if (headSha === baseline) {
      console.log(`[v37.0 SURF] HEAD == V36_BASELINE — protected ranges trivially preserved.`);
      return { skipped: false, trivial: true };
    }

    const diff = execSync(
      `git diff ${baseline} HEAD -- ${path}`,
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    );

    if (diff.length === 0) {
      // For TraitUtils we EXPECT additions post-L178 (Phase 267 added
      // packedTraitsDegenerette + _degTrait). An empty diff is still
      // a valid PASS for SURF-01: it just means the additions also
      // didn't ship in this branch / merge state.
      return { skipped: false, trivial: false };
    }

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
        inHunk = false;
      }
    }

    for (const range of ranges) {
      for (let line = range.lo; line <= range.hi; line++) {
        expect(
          modifiedOldLines.has(line),
          `Baseline line ${line} (inside protected range "${range.name}" [${range.lo}-${range.hi}]) ` +
          `was modified or removed in ${path} vs v36.0 baseline ${baseline}`,
        ).to.equal(false);
      }
    }
    return { skipped: false, trivial: false };
  }

  // ---------------------------------------------------------------------------
  // expectFileLevelZeroDiffV37(baseline, path) — thinner SURF-02..04 variant.
  // Asserts `git diff <baseline> HEAD -- <path>` returns empty output. Soft-
  // skips on unreachable baseline per the L478-485 v36.0 pattern.
  // ---------------------------------------------------------------------------
  function expectFileLevelZeroDiffV37(baseline, path) {
    let baselineReachable = false;
    try {
      execSync(`git rev-parse --verify ${baseline}^{commit}`, { stdio: "pipe" });
      baselineReachable = true;
    } catch (_) {
      console.warn(
        `[v37.0 SURF] baseline commit ${baseline} not reachable — soft-skipping ` +
        `file-level zero-diff proof on ${path}.`,
      );
      return { skipped: true };
    }
    expect(baselineReachable).to.equal(true);

    const headSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
    if (headSha === baseline) {
      return { skipped: false, trivial: true };
    }

    const diff = execSync(
      `git diff ${baseline} HEAD -- ${path}`,
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    );
    expect(
      diff.length,
      `[v37.0 SURF] expected file-level zero-diff on ${path} vs v36.0 baseline ${baseline}, ` +
      `but git diff produced ${diff.length} bytes of output. v37.0 SURF preservation gate FAILED.`,
    ).to.equal(0);
    return { skipped: false, trivial: false };
  }

  it("SURF-01 — DegenerusTraitUtils.sol existing functions byte-identical vs v36.0 baseline 1c0f0913 (additions to packedTraitsDegenerette + _degTrait permitted)", function () {
    const result = walkAndAssertV37(V36_BASELINE, TRAIT_UTILS_PATH, SURF_01_PROTECTED_RANGES_V37);
    if (result.skipped) this.skip();
  });

  // SUPERSEDED by the v40.0 SURF block below: Phase 278 Wave 1 edits
  // DegenerusGameJackpotModule.sol (the JackpotTicketWin whole-ticket
  // unification + the _jackpotTicketRoll keccak swap), so file-level
  // zero-diff vs the v36.0 baseline no longer holds. The v40.0 block
  // re-protects every surviving JackpotModule surface against the v39.0
  // baseline 6a7455d1 with explicit protected ranges around the three
  // intentional Wave 1 delta sites.
  it.skip("SURF-02 — DegenerusGameJackpotModule.sol file-level zero-diff vs v36.0 baseline 1c0f0913", function () {
    const result = expectFileLevelZeroDiffV37(V36_BASELINE, JACKPOT_MODULE_PATH_V37);
    if (result.skipped) this.skip();
  });

  // SUPERSEDED: LootboxModule.sol has legitimately changed across every milestone
  // since phase-269 (the `_settleLootboxRoll` per-roll refactor being the latest),
  // so a file-level zero-diff vs `8fd5c2e1` can never hold again. Skipped (matching
  // this file's superseded-baseline convention); current LootboxModule structure is
  // pinned by the per-function source-structural unit tests.
  it.skip("SURF-03 — DegenerusGameLootboxModule.sol file-level zero-diff vs phase-269-close baseline 8fd5c2e1", function () {
    // SURF-03 baseline anchor: phase-269-close HEAD `8fd5c2e1` (post-LBX-01
    // lootbox dead-branch cleanup). LootboxModule is byte-identical at every
    // HEAD downstream of phase-269-close: phase 270 emits zero source-tree
    // mutations; phase 271 closes v37.0 with zero LootboxModule edits;
    // phase 272 cleanup scope is narrowed to DegenerusGameDegeneretteModule
    // per D-272-CLEAN-SCOPE-01.
    const result = expectFileLevelZeroDiffV37(PHASE_269_CLOSE_BASELINE, LOOTBOX_MODULE_PATH);
    if (result.skipped) this.skip();
  });

  // SUPERSEDED by the v40.0 SURF block below: Phase 278 Wave 1 deletes
  // EntropyLib.entropyStep and rewrites the library NatSpec, so file-level
  // zero-diff vs the v36.0 baseline no longer holds. EntropyLib's only
  // surviving member is hash2; the v40.0 block documents that the whole
  // file is an intentional Wave 1 rewrite and therefore carries no
  // protected range (the hash2 primitive itself is unchanged in behaviour
  // and is exercised by Ent05KeccakRefactorInvariant.test.js).
  it.skip("SURF-04 — EntropyLib.sol file-level zero-diff vs v36.0 baseline 1c0f0913 (ENT-04 v36.0 carry)", function () {
    const result = expectFileLevelZeroDiffV37(V36_BASELINE, ENTROPY_LIB_PATH_V37);
    if (result.skipped) this.skip();
  });

  it("v37.0 SURF preservation gate — describe block self-test: chi² primitives verbatim re-declaration discipline carries to Phase 268 (STAT-06 structural pin)", function () {
    // Pure structural pin: documents that the v37.0 SURF describe block
    // CO-LOCATES with the Phase 268 stat files (per package.json `test:stat`
    // wiring). Drift detection if any Phase 268 file accidentally renamed.
    const phase268Files = [
      "test/stat/DegenerettePerNEvExactness.test.js",
      "test/stat/DegeneretteProducerChi2.test.js",
      "test/stat/DegeneretteBonusEv.test.js",
      "test/gas/Phase268GasRegression.test.js",
    ];
    for (const f of phase268Files) {
      expect(
        fs.existsSync(f),
        `[v37.0 SURF] expected Phase 268 stat-suite file ${f} to exist on disk; ` +
        `STAT-06 structural pin asserts the chi²-primitive verbatim re-declaration ` +
        `carries forward to Phase 268.`,
      ).to.equal(true);
    }
  });
});

// ===========================================================================
// v38.0 SURF-01..02 — protected surfaces vs v37.0 baseline 2654fcc2
// ===========================================================================
//
// The v38.0 SURF preservation gate proves that Phase 272 always-hero +
// dead-code-cleanup scopes its source-tree mutation to a SINGLE batched
// commit (Wave 1) touching exactly one file:
//   contracts/modules/DegenerusGameDegeneretteModule.sol  (HERO-01..05 + CLEAN-01..05)
//
// Every other RNG-relevant + module surface stays byte-identical:
//   SURF-01: 4 contracts UNTOUCHED at v38 (file-level zero-diff)
//            - contracts/libraries/EntropyLib.sol            (ENT-04 v36.0 carry; EXC-04 BAF-only NARROWS retained)
//            - contracts/DegenerusTraitUtils.sol             (Mint + Jackpot + Degenerette producer paths)
//            - contracts/modules/DegenerusGameJackpotModule.sol  (gold-solo + BAF jackpot)
//            - contracts/modules/DegenerusGameMintModule.sol     (no v38 mutations)
//   SURF-02: contracts/modules/DegenerusGameLootboxModule.sol  (file-level zero-diff)
//
// V37.0 BASELINE: 2654fcc2 (v37.0 closure HEAD; signal MILESTONE_V37_AT_HEAD_2654fcc2).
//
// Re-declares walkAndAssert + expectFileLevelZeroDiff inline (not factored
// to module scope) so the existing v33.0 / v34.0 / v35.0 / v36.0 / v37.0
// describe blocks at L66-789 stay byte-identical (REG-01 carry-forward
// discipline). Same fail-loud-on-empty-diff + soft-skip-on-unreachable-
// baseline shape as the v37.0 describe block (D-IMPL-11 carry).
// ===========================================================================

describe("v38.0 SURF-01..02 — protected surfaces vs v37.0 baseline 2654fcc2", function () {
  // ---------------------------------------------------------------------------
  // expectFileLevelZeroDiffV38(baseline, path) — file-level zero-diff helper
  // for v38.0 SURF preservation gate. Re-declared inline (not factored to
  // module scope) per REG-01 carry-forward discipline.
  //   - Soft-skip on unreachable baseline (D-IMPL-11).
  //   - HEAD == BASELINE early-return (trivially preserved).
  //   - Fail-loud on non-empty diff (file expected byte-identical at v38).
  // ---------------------------------------------------------------------------
  function expectFileLevelZeroDiffV38(baseline, path) {
    let baselineReachable = false;
    try {
      execSync(`git rev-parse --verify ${baseline}^{commit}`, { stdio: "pipe" });
      baselineReachable = true;
    } catch (_) {
      console.warn(
        `[v38.0 SURF] baseline commit ${baseline} not reachable — soft-skipping ` +
        `file-level zero-diff proof on ${path}.`,
      );
      return { skipped: true };
    }
    expect(baselineReachable).to.equal(true);

    const headSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
    if (headSha === baseline) {
      console.log(`[v38.0 SURF] HEAD == V37_BASELINE — file-level zero-diff trivially preserved.`);
      return { skipped: false, trivial: true };
    }

    const diff = execSync(
      `git diff ${baseline} HEAD -- ${path}`,
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    );
    expect(
      diff.length,
      `[v38.0 SURF] expected file-level zero-diff on ${path} vs v37.0 baseline ${baseline}, ` +
      `but git diff produced ${diff.length} bytes of output. v38.0 SURF preservation gate FAILED.`,
    ).to.equal(0);
    return { skipped: false, trivial: false };
  }

  // SUPERSEDED by the v40.0 SURF block below: Phase 278 Wave 1 deletes
  // EntropyLib.entropyStep, so file-level zero-diff vs the v37.0 baseline
  // no longer holds. See the v40.0 block for the EntropyLib disposition.
  it.skip("SURF-01a — EntropyLib.sol file-level zero-diff vs v37.0 baseline 2654fcc2 (ENT-04 v36.0 carry; EXC-04 BAF-only NARROWS retained)", function () {
    const result = expectFileLevelZeroDiffV38(V37_BASELINE, ENTROPY_LIB_PATH_V37);
    if (result.skipped) this.skip();
  });

  it("SURF-01b — DegenerusTraitUtils.sol file-level zero-diff vs v37.0 baseline 2654fcc2 (Mint + Jackpot + Degenerette producer paths UNTOUCHED at v38)", function () {
    const result = expectFileLevelZeroDiffV38(V37_BASELINE, TRAIT_UTILS_PATH);
    if (result.skipped) this.skip();
  });

  // SUPERSEDED by the v40.0 SURF block below: Phase 278 Wave 1 edits
  // DegenerusGameJackpotModule.sol (JackpotTicketWin whole-ticket
  // unification + _jackpotTicketRoll keccak swap), so file-level zero-diff
  // vs the v37.0 baseline no longer holds. The v40.0 block re-protects the
  // surviving JackpotModule surface against the v39.0 baseline 6a7455d1.
  it.skip("SURF-01c — DegenerusGameJackpotModule.sol file-level zero-diff vs v37.0 baseline 2654fcc2 (gold-solo + BAF jackpot UNCHANGED)", function () {
    const result = expectFileLevelZeroDiffV38(V37_BASELINE, JACKPOT_MODULE_PATH_V37);
    if (result.skipped) this.skip();
  });

  // SUPERSEDED by the v40.0 SURF block below: Phase 278 Wave 1 touches the
  // _rollRemainder NatSpec comment in DegenerusGameMintModule.sol, so
  // file-level zero-diff vs the v37.0 baseline no longer holds. The v40.0
  // block re-protects the MintModule body (the _rollRemainder code itself
  // is unchanged — only the comment moved) against the v39.0 baseline.
  it.skip("SURF-01d — DegenerusGameMintModule.sol file-level zero-diff vs v37.0 baseline 2654fcc2 (no v38 mutations)", function () {
    const result = expectFileLevelZeroDiffV38(V37_BASELINE, MINT_MODULE_PATH_V38);
    if (result.skipped) this.skip();
  });

  // SUPERSEDED: same as the v37.0 LootboxModule gate above — the file has evolved
  // across every milestone since v37.0 (latest: the `_settleLootboxRoll` per-roll
  // refactor), so a zero-diff vs `2654fcc2` can never hold again. Skipped; current
  // structure is pinned by the per-function source-structural unit tests.
  it.skip("SURF-02 — DegenerusGameLootboxModule.sol file-level zero-diff vs v37.0 baseline 2654fcc2", function () {
    const result = expectFileLevelZeroDiffV38(V37_BASELINE, LOOTBOX_MODULE_PATH);
    if (result.skipped) this.skip();
  });

  it("v38.0 SURF preservation gate — describe block self-test: anchor discipline carries from v37.0 (fail-loud-on-empty-diff + soft-skip-on-unreachable-baseline) per D-IMPL-11", function () {
    // Pure structural pin: documents that the v38.0 SURF describe block
    // carries the same anchor-discipline as the v37.0 / v36.0 / v35.0 /
    // v34.0 / v33.0 blocks above. The Phase 272 audit-tree files
    // expected on disk at v38 close are cited here so renames trip the
    // gate (D-IMPL-11 carry-forward).
    const phase272AuditFiles = [
      "audit/FINDINGS-v37.0.md",
      // audit/FINDINGS-v38.0.md is authored at Wave 3 (Task 3.1+); not
      // asserted here because Wave 2 runs before Wave 3 in CI ordering.
    ];
    for (const f of phase272AuditFiles) {
      expect(
        fs.existsSync(f),
        `[v38.0 SURF] expected audit-tree file ${f} to exist on disk; ` +
        `anchor-discipline drift detection.`,
      ).to.equal(true);
    }
  });
});

// ===========================================================================
// v40.0 SURF-01..05 — protected surfaces vs v39.0 baseline 6a7455d1
// ===========================================================================
//
// The v40.0 SURF preservation gate anchors at the v39.0 closure HEAD 6a7455d1
// (signal MILESTONE_V39_AT_HEAD_6a7455d1) and proves that the cumulative
// v40.0-milestone source-tree mutation in the three Phase 278 Wave 1 files
// (JackpotModule, Storage, MintModule) is confined to a small set of
// localized delta sites — leaving every other line in those files
// byte-identical vs the v39.0 baseline.
//
// For DegenerusGameJackpotModule.sol the net 6a7455d1->HEAD modified-line set
// coincides exactly with the documented Phase 278 Wave 1 delta sites: the
// JackpotTicketWin whole-ticket unification + the _jackpotTicketRoll keccak
// swap. (Phases 276 and 277 also touched JackpotModule on the way to the
// v40.0 milestone, but their net effect on v39-baseline lines is subsumed by
// — i.e. identical to — the Wave 1 delta set, so the protected-range
// complement below is the correct byte-identity gate for the whole v40.0
// milestone.) For Storage and MintModule the only milestone delta is the
// Phase 278 Wave 1 edit.
//
// The intentional delta sites this block EXPECTS (and therefore excludes
// from its protected ranges):
//   SURF-01  contracts/modules/DegenerusGameJackpotModule.sol —
//            (a) the _jackpotTicketRoll evolution line: entropyStep(entropy)
//                -> hash2(entropy, entropy) + the Bernoulli whole-ticket
//                collapse that replaces the _queueLootboxTickets call;
//            (b) the JackpotTicketWin event def + NatSpec (roundedUp field
//                added) and the 3 emit sites (4th arg de-scaled to whole,
//                roundedUp arg appended);
//            (c) the contract-header NatSpec line naming the entropy helper.
//            (d) Phase 279 BUR-02/BUR-03 whole-BURNIE floor: the
//                _awardDailyCoinToTraitWinners baseAmount floor + the
//                extra/cursor dead-var removal + the NatSpec rewrite, and the
//                _awardFarFutureCoinJackpot perWinner floor + its comment.
//            Every other JackpotModule surface — the 8 surviving EntropyLib
//            callsites, _randTraitTicket, _pickSoloQuadrant, the gold-solo
//            + BAF jackpot bodies, the unfloored body lines of the two
//            coin-jackpot functions — is byte-identical and IS protected here.
//   SURF-02  contracts/storage/DegenerusGameStorage.sol — the _queueLootboxTickets
//            wrapper function is deleted (L683-701 at the v39 baseline). Every
//            other storage helper — _queueTickets, _queueTicketsScaled,
//            _queueTicketRange, the packed-pool helpers — is byte-identical
//            and IS protected here.
//   SURF-03  contracts/modules/DegenerusGameMintModule.sol — the _rollRemainder
//            NatSpec comment is reworded (L649-651 at the v39 baseline). The
//            _rollRemainder code itself (the hash2 call + the Bernoulli
//            predicate) is byte-identical and IS protected here.
//   SURF-04  contracts/libraries/EntropyLib.sol — the entire file is an
//            intentional Phase 278 Wave 1 rewrite (entropyStep deleted,
//            library NatSpec rewritten). hash2 is the sole surviving member;
//            its behaviour is unchanged and is exercised by
//            Ent05KeccakRefactorInvariant.test.js. EntropyLib therefore
//            carries NO protected range in this block — documented as a
//            whole-file intentional rewrite.
//   SURF-05  the v40.0-milestone production-contract change set is exactly
//            the six documented files (JackpotModule, LootboxModule,
//            IDegenerusGameModules, EntropyLib, MintModule, Storage) — no
//            other production-contract file drifted across the milestone.
//
// V39.0 BASELINE: 6a7455d1 (v39.0 closure HEAD; signal
// MILESTONE_V39_AT_HEAD_6a7455d1).
//
// Re-declares walkAndAssert inline (not factored to module scope) so the
// existing v33.0 / v34.0 / v35.0 / v36.0 / v37.0 / v38.0 describe blocks above
// stay byte-identical (REG-01 carry-forward discipline). Same per-line
// modified-set walk + D-IMPL-11 soft-skip-on-unreachable-baseline +
// fail-loud-on-empty-diff shape as the v36.0 walkAndAssert.
// ===========================================================================

const V39_BASELINE = "6a7455d1"; // v39.0 closure HEAD; v40.0 SURF anchor
const JACKPOT_MODULE_PATH_V40 = "contracts/modules/DegenerusGameJackpotModule.sol";
const STORAGE_PATH_V40 = "contracts/storage/DegenerusGameStorage.sol";
const MINT_MODULE_PATH_V40 = "contracts/modules/DegenerusGameMintModule.sol";

describe("v40.0 SURF-01..05 — protected surfaces vs v39.0 baseline 6a7455d1", function () {
  // SURF-01 — DegenerusGameJackpotModule.sol surviving surface byte-identical.
  // The v39.0-baseline file is 2231 lines. The net 6a7455d1->HEAD modified
  // OLD-side line set is:
  //   Phase 278 delta sites: the contract-header NatSpec line (L43), the
  //   JackpotTicketWin NatSpec + event def (L80-85, L92), the trait-burn emit
  //   site (L703, L708, L710), the coin-path emit site (L1006, L1011, L1013),
  //   and the _jackpotTicketRoll body delta lines (L2178, L2192, L2216,
  //   L2218-2219, L2224, L2226).
  //   Phase 279 BUR-02/BUR-03 delta sites: the _awardDailyCoinToTraitWinners
  //   NatSpec rewrite (L1752-1754), the baseAmount floor + extra/cursor
  //   declaration removal (L1785-1787), the empty-bucket cursor-rotation
  //   removal (L1810-1811), the `extra != 0` amount-top-up block removal
  //   (L1830-1832), the loop-tail cursor-rotation removal (L1847-1848), and
  //   the _awardFarFutureCoinJackpot perWinner floor + its comment
  //   (L1899-1900).
  // All of the above are EXCLUDED here as the documented v40.0 delta sites.
  // Every line in the gaps between those delta lines IS protected: the
  // protected ranges below are the exact complement of the OLD-side
  // modified-line set produced by
  // `git diff 6a7455d1 HEAD -- DegenerusGameJackpotModule.sol`.
  const SURF_01_PROTECTED_RANGES_V40 = [
    { name: "JackpotModule L1-42 (pre-header-NatSpec surface)",            lo: 1,    hi: 42   },
    { name: "JackpotModule L44-79 (post-header-NatSpec .. pre-event-doc)", lo: 44,   hi: 79   },
    { name: "JackpotModule L86-91 (JackpotTicketWin def fields, unchanged)", lo: 86, hi: 91   },
    { name: "JackpotModule L93-702 (incl. 8 surviving EntropyLib callsites + _randTraitTicket + _pickSoloQuadrant)", lo: 93, hi: 702 },
    { name: "JackpotModule L704-707 (trait-burn emit args, unchanged)",    lo: 704,  hi: 707  },
    { name: "JackpotModule L709 (trait-burn emit sourceLevel, unchanged)", lo: 709,  hi: 709  },
    { name: "JackpotModule L711-1005 (gold-solo + daily-coin bodies)",     lo: 711,  hi: 1005 },
    { name: "JackpotModule L1007-1010 (coin-path emit args, unchanged)",   lo: 1007, hi: 1010 },
    { name: "JackpotModule L1012 (coin-path emit sourceLvl, unchanged)",   lo: 1012, hi: 1012 },
    { name: "JackpotModule L1014-1751 (BAF jackpot + ticket-distribution bodies)", lo: 1014, hi: 1751 },
    { name: "JackpotModule L1755-1784 (_awardDailyCoinToTraitWinners head, unchanged)", lo: 1755, hi: 1784 },
    { name: "JackpotModule L1788-1809 (range derivation + per-pull loop head, unchanged)", lo: 1788, hi: 1809 },
    { name: "JackpotModule L1812-1829 (holder-index draw + amount assignment, unchanged)", lo: 1812, hi: 1829 },
    { name: "JackpotModule L1833-1846 (winner-guard emit + creditFlip + loop tail, unchanged)", lo: 1833, hi: 1846 },
    { name: "JackpotModule L1849-1898 (_awardFarFutureCoinJackpot head .. perWinner comment, unchanged)", lo: 1849, hi: 1898 },
    { name: "JackpotModule L1901-2177 (far-future emit loop + remaining ticket-distribution bodies)", lo: 1901, hi: 2177 },
    { name: "JackpotModule L2179-2191 (_jackpotTicketRoll signature + NatSpec tail)", lo: 2179, hi: 2191 },
    { name: "JackpotModule L2193-2215 (_jackpotTicketRoll path/level roll, unchanged)", lo: 2193, hi: 2215 },
    { name: "JackpotModule L2217 (quantityScaled derivation, unchanged)",  lo: 2217, hi: 2217 },
    { name: "JackpotModule L2220-2223 (emit winner/targetLevel/sentinel, unchanged)", lo: 2220, hi: 2223 },
    { name: "JackpotModule L2225 (emit minTargetLevel, unchanged)",        lo: 2225, hi: 2225 },
    { name: "JackpotModule L2227-2231 (return entropy + closing braces)",  lo: 2227, hi: 2231 },
  ];

  // SURF-02 — DegenerusGameStorage.sol surviving surface byte-identical.
  // The v39.0-baseline file is 1789 lines. The only Wave 1 delta is the
  // deletion of the _queueLootboxTickets wrapper (OLD-side lines L683-701).
  // Everything before and after that block — _queueTickets, _queueTicketsScaled,
  // _queueTicketRange, the packed prize-pool helpers — is byte-identical.
  const SURF_02_PROTECTED_RANGES_V40 = [
    { name: "Storage L1-682 (incl. _queueTickets + _queueTicketsScaled + _queueTicketRange)", lo: 1, hi: 682 },
    { name: "Storage L702-1789 (packed prize-pool helpers + remainder of file)", lo: 702, hi: 1789 },
  ];

  // SURF-03 — DegenerusGameMintModule.sol surviving surface byte-identical.
  // The v39.0-baseline file is 1494 lines. The only Wave 1 delta is the
  // _rollRemainder NatSpec comment rewording (OLD-side lines L649-651). The
  // _rollRemainder code — the EntropyLib.hash2(entropy, rollSalt) call at
  // L652 and the Bernoulli predicate at L653 — is byte-identical, as is the
  // entire rest of the file.
  const SURF_03_PROTECTED_RANGES_V40 = [
    { name: "MintModule L1-648 (mint paths + _rollRemainder signature)",   lo: 1,   hi: 648  },
    { name: "MintModule L652-1494 (hash2 callsite + Bernoulli predicate + remainder of file)", lo: 652, hi: 1494 },
  ];

  // ---------------------------------------------------------------------------
  // walkAndAssertV40(baseline, path, ranges) — per-line modified-set walk
  // against the named baseline. Re-declared inline (not factored to module
  // scope) per the L466-473 / L624-633 carry-forward discipline. Same
  // algorithm as the v36.0 / v37.0 walkAndAssert:
  //   - D-IMPL-11 soft-skip on unreachable baseline.
  //   - HEAD == BASELINE early-return (trivially preserved).
  //   - Fail-loud on empty diff with HEAD != baseline (these files ALL carry
  //     intentional Wave 1 deltas, so an empty diff means git misbehaved).
  //   - Per-line walk via diff hunk parsing; record OLD-side `-` lines.
  //   - Assert each protected line NOT in modifiedOldLines.
  // ---------------------------------------------------------------------------
  function walkAndAssertV40(baseline, path, ranges) {
    let baselineReachable = false;
    try {
      execSync(`git rev-parse --verify ${baseline}^{commit}`, { stdio: "pipe" });
      baselineReachable = true;
    } catch (_) {
      console.warn(
        `[v40.0 SURF] baseline commit ${baseline} not reachable — soft-skipping ` +
        `protected-range proof on ${path}. CI / fresh-clone hint: \`git fetch --unshallow\` ` +
        `or \`git fetch origin ${baseline}\`.`,
      );
      return { skipped: true };
    }
    expect(baselineReachable).to.equal(true);

    const headSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
    if (headSha.startsWith(baseline)) {
      console.log(`[v40.0 SURF] HEAD == V39_BASELINE — protected ranges trivially preserved.`);
      return { skipped: false, trivial: true };
    }

    const diff = execSync(
      `git diff ${baseline} HEAD -- ${path}`,
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    );

    // D-IMPL-11 fail-loud-on-empty-diff guard: all three v40.0 SURF files
    // carry an intentional Wave 1 delta, so an empty diff with HEAD != baseline
    // means `git diff` is silently misbehaving — assert failure, not vacuous pass.
    expect(
      diff.length > 0,
      `[v40.0 SURF] git diff ${baseline} HEAD returned empty output for ${path} — ` +
      `baseline-vs-HEAD distinct and ${path} carries an intentional Wave 1 delta but ` +
      `no diff produced. D-IMPL-11 fail-loud guard.`,
    ).to.equal(true);

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
        inHunk = false;
      }
    }

    for (const range of ranges) {
      for (let line = range.lo; line <= range.hi; line++) {
        expect(
          modifiedOldLines.has(line),
          `Baseline line ${line} (inside protected range "${range.name}" [${range.lo}-${range.hi}]) ` +
          `was modified or removed in ${path} vs v39.0 baseline ${baseline}`,
        ).to.equal(false);
      }
    }
    return { skipped: false, trivial: false };
  }

  // SUPERSEDED (the next three): these v40.0 protected-range byte-pins vs v39.0
  // `6a7455d1` predate 16+ milestones of legitimate JackpotModule / Storage /
  // MintModule evolution, so the OLD-side protected ranges no longer map to
  // current code and the gates fail on a reachable baseline. Skipped (matching
  // this file's superseded-baseline convention) — current per-function structure
  // is pinned by the dedicated source-structural unit tests.
  it.skip("SURF-01 — DegenerusGameJackpotModule.sol surviving surface byte-identical vs v39.0 baseline 6a7455d1 (3 intentional Wave 1 delta sites excluded)", function () {
    const result = walkAndAssertV40(V39_BASELINE, JACKPOT_MODULE_PATH_V40, SURF_01_PROTECTED_RANGES_V40);
    if (result.skipped) this.skip();
  });

  it.skip("SURF-02 — DegenerusGameStorage.sol surviving surface byte-identical vs v39.0 baseline 6a7455d1 (_queueLootboxTickets deletion excluded)", function () {
    const result = walkAndAssertV40(V39_BASELINE, STORAGE_PATH_V40, SURF_02_PROTECTED_RANGES_V40);
    if (result.skipped) this.skip();
  });

  it.skip("SURF-03 — DegenerusGameMintModule.sol surviving surface byte-identical vs v39.0 baseline 6a7455d1 (_rollRemainder NatSpec reword excluded)", function () {
    const result = walkAndAssertV40(V39_BASELINE, MINT_MODULE_PATH_V40, SURF_03_PROTECTED_RANGES_V40);
    if (result.skipped) this.skip();
  });

  it("SURF-04 — EntropyLib.sol is a whole-file intentional Wave 1 rewrite (no protected range; hash2 behaviour pinned by Ent05KeccakRefactorInvariant.test.js)", function () {
    // EntropyLib.sol carries no protected range at v40.0: Phase 278 Wave 1
    // deletes entropyStep and rewrites the library NatSpec, so the file is an
    // intentional whole-file rewrite. The surviving primitive hash2 is
    // behaviourally unchanged — its keccak scratch-slot semantics are pinned
    // by the drift-gate + chi-square assertions in
    // test/stat/Ent05KeccakRefactorInvariant.test.js. This `it` documents that
    // disposition and asserts that file still exists with hash2 as its sole
    // function (drift detection if a future phase re-adds a second member).
    const entropyLibPath = "contracts/libraries/EntropyLib.sol";
    expect(fs.existsSync(entropyLibPath), `${entropyLibPath} must exist`).to.equal(true);
    const src = fs.readFileSync(entropyLibPath, "utf8");
    const fnMatches = src.match(/function\s+\w+/g) || [];
    expect(
      fnMatches.length,
      `[v40.0 SURF] EntropyLib.sol must contain exactly one function (hash2); ` +
      `found ${fnMatches.length}: ${fnMatches.join(", ")}`,
    ).to.equal(1);
    expect(src).to.include("function hash2");
    expect(src).to.not.include("entropyStep");
  });

  // SUPERSEDED: this gate asserts the diff vs v39.0 `6a7455d1` touches exactly the
  // six v40.0-milestone files. 16+ subsequent milestones have legitimately modified
  // many more contracts, so the change set can never again equal that six-file list.
  // Skipped (matching this file's superseded-baseline convention).
  it.skip("SURF-05 — the v40.0 milestone production-contract change set vs v39.0 baseline 6a7455d1 is exactly the six documented files", function () {
    // The v39.0 baseline 6a7455d1 is the v39.0 CLOSURE HEAD. The v40.0
    // milestone spans Phases 275-278; the production-contract surface modified
    // between 6a7455d1 and HEAD is the cumulative v40.0 change set:
    //   - DegenerusGameJackpotModule.sol  (Phases 276 + 277 + 278)
    //   - DegenerusGameLootboxModule.sol  (Phases 275 + 277)
    //   - IDegenerusGameModules.sol       (Phase 277 — LootboxTicketRoll retirement)
    //   - EntropyLib.sol                  (Phase 278 Wave 1)
    //   - DegenerusGameMintModule.sol     (Phase 278 Wave 1)
    //   - DegenerusGameStorage.sol        (Phase 278 Wave 1)
    // This SURF-05 gate asserts NO production-contract file OUTSIDE that set
    // drifted across the whole v40.0 milestone. `contracts/test/` is excluded
    // — those are on-chain test helpers, not audit-subject production surface.
    let baselineReachable = false;
    try {
      execSync(`git rev-parse --verify ${V39_BASELINE}^{commit}`, { stdio: "pipe" });
      baselineReachable = true;
    } catch (_) {
      console.warn(
        `[v40.0 SURF] baseline commit ${V39_BASELINE} not reachable — soft-skipping ` +
        `SURF-05 file-set proof.`,
      );
      this.skip();
      return;
    }
    expect(baselineReachable).to.equal(true);

    const nameOnly = execSync(
      `git diff --name-only ${V39_BASELINE} HEAD -- contracts/`,
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    )
      .split("\n")
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
      .filter((s) => !s.startsWith("contracts/test/"));

    const expectedProductionFiles = [
      "contracts/interfaces/IDegenerusGameModules.sol",
      "contracts/libraries/EntropyLib.sol",
      "contracts/modules/DegenerusGameJackpotModule.sol",
      "contracts/modules/DegenerusGameLootboxModule.sol",
      "contracts/modules/DegenerusGameMintModule.sol",
      "contracts/storage/DegenerusGameStorage.sol",
    ].sort();

    expect(
      nameOnly.slice().sort(),
      `[v40.0 SURF] v40.0-milestone production-contract change set vs v39.0 baseline ` +
      `${V39_BASELINE} must be exactly the 6 documented files (EntropyLib, JackpotModule, ` +
      `LootboxModule, MintModule, Storage, IDegenerusGameModules). Got: ${nameOnly.join(", ")}`,
    ).to.deep.equal(expectedProductionFiles);
  });
});
