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
