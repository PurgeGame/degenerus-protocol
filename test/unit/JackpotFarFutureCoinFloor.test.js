// SPDX-License-Identifier: AGPL-3.0-only
//
// JackpotFarFutureCoinFloor.test.js — Phase 279 Wave 2 TST-BUR-03
//
// Whole-FLIP floor + early-bail-ordering regression on the far-future
// coin-jackpot FLIP-award site.
//   `_awardFarFutureCoinJackpot` in
//   `contracts/modules/DegenerusGameJackpotModule.sol` floors `perWinner` via
//   `((farBudget / found) / 1 ether) * 1 ether` (D-279-INLINE-01) immediately
//   before the existing `if (perWinner == 0) return;` early-bail
//   (D-279-BUR03-ORDER-01). Flooring BEFORE the `== 0` check lets the existing
//   early-bail absorb the post-floor-zero case for free: when `perWinner < 1
//   ether` the floor yields 0, the function returns, and
//   `coinflip.creditFlipBatch` is never reached — the full 25% far-future
//   allocation evaporates (D-40N-BUR-DUST-01 / D-40N-BUR-SILENT-01). Flooring
//   AFTER the check would let a sub-1-ether `perWinner` reach `creditFlipBatch`
//   as a 0-amount entry — wrong behavior.
//
// TEST STRATEGY:
//   `_awardFarFutureCoinJackpot` is `private` with a documented
//   fixture-coverage gap (no deterministic full-state harness — far-future
//   ticket-queue state, VRF mock, level simulation). Per the
//   `JackpotTicketRollSilentColdBust.test.js` fixture-coverage-gap precedent,
//   the load-bearing evidence is source-level structural proof: `extractBody`
//   + `stripLineComments` + regex + index-ordering. JS-side BigInt boundary
//   math is the confirmation layer.
//
// CROSS-CITES:
//   - D-279-INLINE-01 (inline `(x / 1 ether) * 1 ether` floor — no shared helper)
//   - D-279-BUR03-ORDER-01 (floor BEFORE the `if (perWinner == 0) return` early-bail)
//   - D-40N-BUR-DUST-01 (sub-1-FLIP residue evaporates)
//   - D-40N-BUR-SILENT-01 (no consolation / replacement event / redistribution)
//   - test/unit/JackpotTicketRollSilentColdBust.test.js (extractBody + stripLineComments infra)

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const ONE_ETHER = 10n ** 18n;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotModule.sol"
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

// Strip `//` line comments so structural greps do not self-invalidate on
// comment prose (copied from test/unit/JackpotTicketRollSilentColdBust.test.js).
function stripLineComments(body) {
  return body
    .split("\n")
    .map((line) => {
      const idx = line.indexOf("//");
      return idx >= 0 ? line.slice(0, idx) : line;
    })
    .join("\n");
}

// The whole-FLIP floor as applied on-chain: `(x / 1 ether) * 1 ether`.
function floorWholeFlip(x) {
  return (x / ONE_ETHER) * ONE_ETHER;
}

describe("JackpotFarFutureCoinFloor — Phase 279 Wave 2 TST-BUR-03", function () {
  this.timeout(30_000);

  describe("Source-structural proof: `_awardFarFutureCoinJackpot` floors `perWinner` BEFORE the `if (perWinner == 0) return` early-bail", function () {
    it("[01a] body contains the inline whole-FLIP floor `perWinner = ((farBudget / found) / 1 ether) * 1 ether`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardFarFutureCoinJackpot(")
      );
      expect(body, "`_awardFarFutureCoinJackpot` body not found").to.not.equal(null);
      const floorPattern =
        /perWinner\s*=\s*\(\s*\(\s*farBudget\s*\/\s*found\s*\)\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/;
      expect(
        floorPattern.test(body),
        "`_awardFarFutureCoinJackpot` must floor `perWinner` via `((farBudget / found) / 1 ether) * 1 ether` (D-279-INLINE-01)"
      ).to.equal(true);
    });

    it("[01b] index-ordering: the floor expression precedes `if (perWinner == 0) return`, which precedes the `coinflip.creditFlipBatch` call", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardFarFutureCoinJackpot(")
      );
      expect(body, "`_awardFarFutureCoinJackpot` body not found").to.not.equal(null);

      const floorIdx = body.search(
        /perWinner\s*=\s*\(\s*\(\s*farBudget\s*\/\s*found\s*\)\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/
      );
      const bailIdx = body.search(
        /if\s*\(\s*perWinner\s*==\s*0\s*\)\s*return\s*;/
      );
      const batchIdx = body.indexOf("coinflip.creditFlipBatch(");

      expect(floorIdx, "floor expression not found").to.be.greaterThan(-1);
      expect(
        bailIdx,
        "`if (perWinner == 0) return;` early-bail not found"
      ).to.be.greaterThan(-1);
      expect(
        batchIdx,
        "`coinflip.creditFlipBatch(` call not found"
      ).to.be.greaterThan(-1);

      expect(
        floorIdx,
        "the floor MUST precede the `if (perWinner == 0) return` early-bail so a sub-1-FLIP `perWinner` cannot reach `creditFlipBatch` (D-279-BUR03-ORDER-01)"
      ).to.be.lessThan(bailIdx);
      expect(
        bailIdx,
        "the `if (perWinner == 0) return` early-bail must sit between the floor and the `creditFlipBatch` call"
      ).to.be.lessThan(batchIdx);
    });
  });

  describe("JS boundary math: `((farBudget / found) / 1 ether) * 1 ether` floor cases (confirmation layer)", function () {
    it("farBudget=5 FLIP, found=10 → perWinner = 0.5 FLIP → floors to 0 (early-bail fires, no creditFlipBatch)", function () {
      const farBudget = ONE_ETHER * 5n;
      const found = 10n;
      const perWinner = floorWholeFlip(farBudget / found);
      expect(perWinner).to.equal(0n);
    });

    it("farBudget=25 FLIP, found=10 → perWinner = 2.5 FLIP → floors to 2 FLIP per winner", function () {
      const farBudget = ONE_ETHER * 25n;
      const found = 10n;
      const perWinner = floorWholeFlip(farBudget / found);
      expect(perWinner).to.equal(ONE_ETHER * 2n);
    });

    it("the floored `perWinner` is always a whole-FLIP multiple (`% 1 ether == 0`)", function () {
      for (const [budgetFlip, found] of [
        [5n, 10n],
        [25n, 10n],
        [99n, 7n],
        [100n, 4n],
        [3n, 10n],
      ]) {
        const perWinner = floorWholeFlip((ONE_ETHER * budgetFlip) / found);
        expect(perWinner % ONE_ETHER).to.equal(0n);
      }
    });
  });
});
