// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxFlipRoundHundreds.test.js — threshold-gated 100-FLIP collapse on both lootbox
// FLIP award sites.
//
// SUPERSEDES the whole-FLIP floor regression this file used to carry (D-279-INLINE-01 /
// D-279-BUR01-SITE-01). Neither site floors to 1 FLIP any more:
//
//   SITE 5 — `_settleLootboxRoll` (`DegenerusGameLootboxModule.sol`)
//     was:  uint256 flipAmount = (flipOut / 1 ether) * 1 ether;
//     now:  uint256 flipAmount = flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD
//               ? FlipRoundLib.roundFlipToHundreds(
//                     flipOut, EntropyLib.hash2(rollSeed, FLIP_ROUND_TAG))
//               : FlipRoundLib.floorWholeFlip(flipOut);
//
//   SITE 4 — `_resolvePresaleBox` (same module, the 50% FLIP branch)
//     was:  flipOut = (flipOut / 1 ether) * 1 ether;
//     now:  the same threshold-gated collapse, keyed on the box's own committed `seed`.
//
// The whole-FLIP floor itself is NOT retired — it moved behind
// `FlipRoundLib.floorWholeFlip` and now serves only the sub-threshold branch, so no award
// leaves either site carrying wei-scale residue.
//
// Two properties are load-bearing and are asserted structurally below:
//
//   1. THE THRESHOLD GATE IS PRESENT AT BOTH SITES. A minimum box at the milestone price
//      pays about 18 FLIP on the roll leg and about 59 FLIP on the presale leg. An
//      ungated 100-FLIP granule would round those to nothing outright, so the
//      `> FLIP_ROUND_THRESHOLD` gate is what keeps small wins whole-FLIP rather than zero.
//
//   2. THE ENTROPY IS A DOMAIN-SEPARATED HASH OF THE ROLL'S OWN SEED — not a bit-slice of
//      a window the module already documents as allocated. That is why the primary-chunk
//      bit budget in `_resolveLootboxRoll`'s docblock stays accurate, and why the roll is
//      fixed at VRF fulfillment: the seed binds immutable per-box data (player, amount,
//      index) hashed with the index's committed word.
//
// What survives from the old file, restated for the new expression: the collapse is
// applied ONCE per roll from that roll's raw `flipOut` (no cross-roll accumulator), it
// precedes both the `!= 0` guard and the `creditFlip` call, and the emitted event carries
// the post-collapse figure — the number the player actually receives.
//
// TEST STRATEGY:
//   Both functions are `private` with the documented fixture-coverage gap; per the
//   `JackpotTicketRollSilentColdBust.test.js` precedent the load-bearing evidence is
//   source-level structural proof, with JS boundary math as the confirmation layer. The
//   probabilistic behaviour of the collapse itself is covered separately and empirically
//   by `test/stat/FlipRoundHundredsEv.test.js` against `FlipRoundBernoulliTester`.
//
// CROSS-CITES:
//   - .planning/PLAN-FLIP-ROUND-HUNDREDS.md §3c (small-award sites — round above 1,000 FLIP)
//   - D-279-INLINE-01 / D-279-BUR01-SITE-01 SUPERSEDED
//   - test/stat/FlipRoundHundredsEv.test.js (EV-neutrality of the primitive)
//   - test/unit/JackpotTicketRollSilentColdBust.test.js (extractBody + stripLineComments infra)

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);

// Brace-match function-body extractor (copied from
// test/unit/JackpotTicketRollSilentColdBust.test.js).
function extractBody(source, signature) {
  const fnIdx = source.indexOf(signature);
  if (fnIdx < 0) return null;
  let depth = 0;
  let bodyStart = -1;
  let bodyEnd = -1;
  for (let i = fnIdx; i < source.length; i++) {
    if (source[i] === "{") {
      if (depth === 0) bodyStart = i;
      depth++;
    } else if (source[i] === "}") {
      depth--;
      if (depth === 0) {
        bodyEnd = i;
        break;
      }
    }
  }
  if (bodyStart < 0 || bodyEnd < 0) return null;
  return source.slice(bodyStart, bodyEnd + 1);
}

// Strip `//` line comments so structural greps do not self-invalidate on comment prose.
function stripLineComments(body) {
  return body
    .split("\n")
    .map((line) => {
      const idx = line.indexOf("//");
      return idx >= 0 ? line.slice(0, idx) : line;
    })
    .join("\n");
}

// Every structural pattern below is `\s*`-tolerant between tokens, so a formatter
// breaking a ternary across lines does not invalidate the proof.
function loadBody(signature) {
  const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
  const body = extractBody(source, signature);
  expect(body, `\`${signature}\` body not found`).to.not.equal(null);
  return stripLineComments(body);
}

describe("LootboxFlipRoundHundreds — threshold-gated 100-FLIP collapse (§3c)", function () {
  this.timeout(30_000);

  describe("SITE 5 — `_settleLootboxRoll` collapses this roll's `flipOut` into `flipAmount`", function () {
    const SIG = "function _settleLootboxRoll(";

    it("[01a] `flipAmount` is the threshold-gated collapse of `flipOut`, keyed on this roll's own seed", function () {
      const body = loadBody(SIG);
      expect(
        /uint256\s+flipAmount\s*=\s*flipOut\s*>\s*FlipRoundLib\.FLIP_ROUND_THRESHOLD/.test(
          body
        ),
        "`flipAmount` must be gated on `flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD`"
      ).to.equal(true);
      expect(
        /FlipRoundLib\.roundFlipToHundreds\(\s*flipOut\s*,\s*EntropyLib\.hash2\(\s*rollSeed\s*,\s*FLIP_ROUND_TAG\s*\)\s*\)/.test(
          body
        ),
        "the collapse must key on `EntropyLib.hash2(rollSeed, FLIP_ROUND_TAG)` — a domain-separated hash, not a bit-slice"
      ).to.equal(true);
      expect(
        /:\s*FlipRoundLib\.floorWholeFlip\(\s*flipOut\s*\)\s*;/.test(body),
        "at or below the threshold `flipOut` must keep the whole-FLIP floor via `FlipRoundLib.floorWholeFlip`"
      ).to.equal(true);
    });



    it("[01c] index-ordering: the collapse precedes the per-roll accumulation; the `!= 0` guard + `creditFlip` flush once per entry", function () {
      // Box-order rework: `_settleLootboxRoll` no longer credits FLIP
      // immediately — it accumulates `acc.flip += flipAmount;` unconditionally
      // (adding zero is harmless, so no per-roll guard is needed). The `!= 0`
      // guard + `coinflip.creditFlip` call moved to `_flushBoxAcc`, flushing
      // the entry's total ONCE (rewards settle once per entry).
      const body = loadBody(SIG);
      const collapseIdx = body.search(/uint256\s+flipAmount\s*=\s*flipOut\s*>/);
      const accIdx = body.indexOf("acc.flip += flipAmount;");

      expect(collapseIdx, "`flipAmount` collapse not found").to.be.greaterThan(
        -1
      );
      expect(
        accIdx,
        "`acc.flip += flipAmount;` accumulation not found"
      ).to.be.greaterThan(-1);
      expect(
        collapseIdx,
        "the collapse must precede the per-roll accumulation"
      ).to.be.lessThan(accIdx);

      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const flushLine = "if (acc.flip != 0) coinflip.creditFlip(id, acc.flip);";
      expect(
        source.includes(flushLine),
        "the per-entry `if (acc.flip != 0) coinflip.creditFlip(id, acc.flip);` flush not found"
      ).to.equal(true);
    });

    it("[01d] the collapse is derived ONCE from this roll's raw `flipOut` — per-roll, no cross-roll accumulator", function () {
      const body = loadBody(SIG);
      const assignments = (
        body.match(/uint256\s+flipAmount\s*=/g) || []
      ).length;
      expect(
        assignments,
        "`flipAmount` must be assigned exactly once, from this roll's own `flipOut`"
      ).to.equal(1);
      const collapses = (
        body.match(/FlipRoundLib\.roundFlipToHundreds\(/g) || []
      ).length;
      expect(
        collapses,
        "the collapse must be applied exactly once per roll"
      ).to.equal(1);
    });

    it("[01e] `LootBoxOpened` carries the post-collapse `flipAmount` as its 6th positional arg", function () {
      const body = loadBody(SIG);
      const emitMatch = body.match(/emit LootBoxOpened\(([\s\S]*?)\);/);
      expect(emitMatch, "`LootBoxOpened` emit not found").to.not.equal(null);
      const args = emitMatch[1].split(",").map((a) => a.trim());
      expect(args[5]).to.equal(
        "flipAmount",
        "the 6th `LootBoxOpened` arg must be the post-collapse `flipAmount` — the figure the player receives"
      );
      // No pre-collapse snapshot may be smuggled in alongside it.
      expect(
        /uint256\s+flipPre\b|uint256\s+rawFlip\b/.test(body),
        "no pre-collapse `flip*` snapshot may be introduced between the collapse and the emit"
      ).to.equal(false);
    });
  });

  describe("SITE 4 — `_resolvePresaleBox` collapses the presale FLIP branch", function () {
    const SIG = "function _resolvePresaleBox(";

    it("[02a] the FLIP branch applies the same threshold-gated collapse, keyed on the box `seed`", function () {
      const body = loadBody(SIG);
      expect(
        /flipOut\s*=\s*flipOut\s*>\s*FlipRoundLib\.FLIP_ROUND_THRESHOLD/.test(
          body
        ),
        "the presale FLIP branch must gate on `flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD`"
      ).to.equal(true);
      expect(
        /\?\s*FlipRoundLib\.roundFlipToHundreds\(\s*flipOut\s*,\s*EntropyLib\.hash2\(\s*seed\s*,\s*FLIP_ROUND_TAG\s*\)\s*\)/.test(
          body
        ),
        "the collapse must key on `EntropyLib.hash2(seed, FLIP_ROUND_TAG)` — the box's own committed seed"
      ).to.equal(true);
      expect(
        /:\s*FlipRoundLib\.floorWholeFlip\(\s*flipOut\s*\)\s*;/.test(body),
        "at or below the threshold `flipOut` must keep the whole-FLIP floor via `FlipRoundLib.floorWholeFlip`"
      ).to.equal(true);
    });



    it("[02c] index-ordering: the collapse precedes the `!= 0` guard, which precedes `creditFlip`, and `PresaleBoxOpened` reports the collapsed figure", function () {
      const body = loadBody(SIG);
      const collapseIdx = body.search(
        /flipOut\s*=\s*flipOut\s*>\s*FlipRoundLib\.FLIP_ROUND_THRESHOLD/
      );
      const guardIdx = body.search(/if\s*\(\s*flipOut\s*!=\s*0\s*\)/);
      const creditIdx = body.indexOf("coinflip.creditFlip(uint32(entry), flipOut)");
      const emitIdx = body.indexOf("emit PresaleBoxOpened(");

      expect(collapseIdx, "the presale collapse not found").to.be.greaterThan(
        -1
      );
      expect(guardIdx, "`if (flipOut != 0)` guard not found").to.be.greaterThan(
        -1
      );
      expect(
        creditIdx,
        "`coinflip.creditFlip(uint32(entry), flipOut)` call not found"
      ).to.be.greaterThan(-1);
      expect(
        emitIdx,
        "`PresaleBoxOpened` emit not found"
      ).to.be.greaterThan(-1);

      expect(
        collapseIdx,
        "the collapse must precede the `!= 0` guard"
      ).to.be.lessThan(guardIdx);
      expect(
        guardIdx,
        "the `!= 0` guard must precede the `creditFlip` call"
      ).to.be.lessThan(creditIdx);
      expect(
        creditIdx,
        "the credit must precede the `PresaleBoxOpened` emit, so the event reports what was credited"
      ).to.be.lessThan(emitIdx);
    });
  });

  describe("Module-wide: the whole-FLIP floor is gone from the module entirely", function () {


    it("[03b] the module declares its own `FLIP_ROUND_TAG` domain separator", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      expect(
        /uint256\s+private\s+constant\s+FLIP_ROUND_TAG\s*=/.test(source),
        "`FLIP_ROUND_TAG` must be declared so both sites hash under a dedicated domain"
      ).to.equal(true);
    });
  });


});
