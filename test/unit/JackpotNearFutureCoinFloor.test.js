// SPDX-License-Identifier: AGPL-3.0-only
//
// JackpotNearFutureCoinFloor.test.js — Phase 279 Wave 2 TST-BUR-02
//
// Whole-BURNIE floor + dead-variable removal regression on the near-future
// coin-jackpot BURNIE-award site.
//   `_awardDailyCoinToTraitWinners` in
//   `contracts/modules/DegenerusGameJackpotModule.sol` floors `baseAmount` via
//   `((coinBudget / cap) / 1 ether) * 1 ether` (D-279-INLINE-01), and the
//   cursor-rotation `+1`-wei distribution machinery retires per A1: the `extra`
//   and `cursor` declarations, both `++cursor`/wrap blocks, and the
//   `amount += 1` block are fully deleted (D-279-BUR02-DEADVAR-01 —
//   `feedback_no_dead_guards.md`). `amount` becomes simply the floored
//   `baseAmount`. `randomWord` STAYS — still consumed by the level/winner
//   keccak draws.
//
//   Budget evaporation: when `baseAmount < 1 ether`, the floor yields
//   `amount == 0` and the existing `if (winner != address(0) && amount != 0)`
//   guard silently skips both the `JackpotBurnieWin` emit and the
//   `coinflip.creditFlip(winner, amount)` call — the full daily near-future
//   budget evaporates with no consolation (D-40N-BUR-DUST-01 / D-40N-BUR-SILENT-01).
//
// TEST STRATEGY:
//   `_awardDailyCoinToTraitWinners` is `private` with a documented
//   fixture-coverage gap (no deterministic full-state harness — winner
//   selection, level + day simulation, trait-burn-ticket state, deity cache).
//   Per the `JackpotTicketRollSilentColdBust.test.js` fixture-coverage-gap
//   precedent, the load-bearing evidence is source-level structural proof:
//   `extractBody` + `stripLineComments` + regex + dead-var-absence +
//   index-ordering. JS-side BigInt boundary math is the confirmation layer.
//
// CROSS-CITES:
//   - D-279-INLINE-01 (inline `(x / 1 ether) * 1 ether` floor — no shared helper)
//   - D-279-BUR02-DEADVAR-01 (full `extra`/`cursor` dead-var removal)
//   - D-40N-BUR-DUST-01 (sub-1-BURNIE residue evaporates)
//   - D-40N-BUR-SILENT-01 (no consolation / replacement event / redistribution)
//   - D-279-DISAMBIG-01 (the ticket-award cursor-rotation near :1003 is OUT OF SCOPE)
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

// The whole-BURNIE floor as applied on-chain: `(x / 1 ether) * 1 ether`.
function floorWholeBurnie(x) {
  return (x / ONE_ETHER) * ONE_ETHER;
}

describe("JackpotNearFutureCoinFloor — Phase 279 Wave 2 TST-BUR-02", function () {
  this.timeout(30_000);

  describe("Source-structural proof: `_awardDailyCoinToTraitWinners` floors `baseAmount` and the `extra`/`cursor` machinery is fully removed", function () {
    it("[01a] body contains the inline whole-BURNIE floor `baseAmount = ((coinBudget / cap) / 1 ether) * 1 ether`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardDailyCoinToTraitWinners(")
      );
      expect(body, "`_awardDailyCoinToTraitWinners` body not found").to.not.equal(null);
      const floorPattern =
        /baseAmount\s*=\s*\(\s*\(\s*coinBudget\s*\/\s*cap\s*\)\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/;
      expect(
        floorPattern.test(body),
        "`_awardDailyCoinToTraitWinners` must floor `baseAmount` via `((coinBudget / cap) / 1 ether) * 1 ether` (D-279-INLINE-01)"
      ).to.equal(true);
    });

    it("[01b] the `extra` and `cursor` dead vars are WHOLLY ABSENT from the function body (D-279-BUR02-DEADVAR-01)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardDailyCoinToTraitWinners(")
      );
      expect(body, "`_awardDailyCoinToTraitWinners` body not found").to.not.equal(null);
      // `\b` word-boundary so a substring like "extra" inside a longer
      // identifier would not match — both identifiers must be wholly gone.
      expect(
        /\bextra\b/.test(body),
        "`extra` must be wholly removed from `_awardDailyCoinToTraitWinners` (only read by the retired cursor-rotation check — D-279-BUR02-DEADVAR-01)"
      ).to.equal(false);
      expect(
        /\bcursor\b/.test(body),
        "`cursor` must be wholly removed from `_awardDailyCoinToTraitWinners` (only read by the retired cursor-rotation check — D-279-BUR02-DEADVAR-01)"
      ).to.equal(false);
    });

    it("[01c] `amount` is assigned only `baseAmount` — no `amount += 1` cursor-rotation top-up", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardDailyCoinToTraitWinners(")
      );
      expect(body, "`_awardDailyCoinToTraitWinners` body not found").to.not.equal(null);
      expect(
        /uint256\s+amount\s*=\s*baseAmount\s*;/.test(body),
        "`amount` must be declared as `uint256 amount = baseAmount;`"
      ).to.equal(true);
      expect(
        /\bamount\s*\+=\s*1\b/.test(body),
        "the `amount += 1` cursor-rotation top-up must be wholly removed (D-279-BUR02-DEADVAR-01)"
      ).to.equal(false);
    });

    it("[01d] `randomWord` survives — still consumed by the level/winner keccak draws", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardDailyCoinToTraitWinners(")
      );
      expect(body, "`_awardDailyCoinToTraitWinners` body not found").to.not.equal(null);
      expect(
        /\brandomWord\b/.test(body),
        "`randomWord` must still appear — only the `cursor = randomWord % cap` read retired, not `randomWord` itself"
      ).to.equal(true);
      // It is consumed by the two `abi.encode(randomWord, ...)` keccak draws
      // (the level sample + the holder index).
      const keccakDraws = (
        body.match(/abi\.encode\(randomWord,/g) || []
      ).length;
      expect(
        keccakDraws,
        "`randomWord` must feed both keccak draws (level sample + holder index)"
      ).to.be.gte(2);
    });

    it("[01e] both `++i` loop increments are intact (the dead-var removal does not perturb loop progress)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardDailyCoinToTraitWinners(")
      );
      expect(body, "`_awardDailyCoinToTraitWinners` body not found").to.not.equal(null);
      const incCount = (body.match(/\+\+i\s*;/g) || []).length;
      expect(
        incCount,
        "both `++i` increments (empty-bucket continue branch + loop tail) must survive the cursor-rotation removal"
      ).to.equal(2);
    });
  });

  describe("Budget-evaporation structural proof: a sub-1-BURNIE `baseAmount` floors `amount` to 0 and the selection loop is skipped before any emit or credit", function () {
    it("[02a] index-ordering: the `baseAmount == 0` early-return precedes the loop; inside it the winner-guard precedes the `JackpotBurnieWin` emit, which precedes the batch accumulation; the single `creditFlipBatch` call sits after the loop behind `anyWinner`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardDailyCoinToTraitWinners(")
      );
      expect(body, "`_awardDailyCoinToTraitWinners` body not found").to.not.equal(null);

      const floorReturnIdx = body.search(
        /if\s*\(\s*baseAmount\s*==\s*0\s*\)\s*return\s*;/
      );
      const guardIdx = body.search(
        /if\s*\(\s*winner\s*!=\s*address\(0\)\s*&&\s*amount\s*!=\s*0\s*\)/
      );
      const emitIdx = body.indexOf("emit JackpotBurnieWin(");
      const accumIdx = body.indexOf("batchPlayers[i] = winner");
      const batchCallIdx = body.indexOf(
        "coinflip.creditFlipBatch(batchPlayers, batchAmounts)"
      );
      const anyWinnerGateIdx = body.search(/if\s*\(\s*anyWinner\s*\)/);

      expect(
        floorReturnIdx,
        "`if (baseAmount == 0) return;` floor early-return not found"
      ).to.be.greaterThan(-1);
      expect(
        guardIdx,
        "`if (winner != address(0) && amount != 0)` guard not found"
      ).to.be.greaterThan(-1);
      expect(emitIdx, "`JackpotBurnieWin` emit not found").to.be.greaterThan(-1);
      expect(
        accumIdx,
        "`batchPlayers[i] = winner` batch accumulation not found"
      ).to.be.greaterThan(-1);
      expect(
        batchCallIdx,
        "`coinflip.creditFlipBatch(batchPlayers, batchAmounts)` call not found"
      ).to.be.greaterThan(-1);
      expect(
        anyWinnerGateIdx,
        "`if (anyWinner)` gate on the batch call not found"
      ).to.be.greaterThan(-1);

      expect(
        floorReturnIdx,
        "the `baseAmount == 0` early-return must precede the winner-guard so a floored budget skips the whole selection loop"
      ).to.be.lessThan(guardIdx);
      expect(
        guardIdx,
        "the `amount != 0` guard must precede the `JackpotBurnieWin` emit so a zero `amount` silently skips the emit"
      ).to.be.lessThan(emitIdx);
      expect(
        emitIdx,
        "the `JackpotBurnieWin` emit must precede the batch accumulation (both inside the guard)"
      ).to.be.lessThan(accumIdx);
      expect(
        anyWinnerGateIdx,
        "the `anyWinner` gate must precede the batch call so an all-skipped loop makes no external call"
      ).to.be.lessThan(batchCallIdx);
      expect(
        accumIdx,
        "the batch accumulation must precede the post-loop `creditFlipBatch` call"
      ).to.be.lessThan(batchCallIdx);
    });
  });

  describe("JS boundary math: `((coinBudget / cap) / 1 ether) * 1 ether` floor cases (confirmation layer)", function () {
    it("coinBudget=50 BURNIE, cap=100 → baseAmount = 0.5 BURNIE → floors to 0 (full daily budget evaporates)", function () {
      const coinBudget = ONE_ETHER * 50n;
      const cap = 100n;
      const baseAmount = floorWholeBurnie(coinBudget / cap);
      expect(baseAmount).to.equal(0n);
    });

    it("coinBudget=150 BURNIE, cap=100 → baseAmount = 1.5 BURNIE → floors to 1 BURNIE per winner", function () {
      const coinBudget = ONE_ETHER * 150n;
      const cap = 100n;
      const baseAmount = floorWholeBurnie(coinBudget / cap);
      expect(baseAmount).to.equal(ONE_ETHER);
    });

    it("the floored `baseAmount` is always a whole-BURNIE multiple (`% 1 ether == 0`)", function () {
      for (const budgetBurnie of [50n, 150n, 99n, 100n, 250n, 1000n]) {
        const baseAmount = floorWholeBurnie((ONE_ETHER * budgetBurnie) / 100n);
        expect(baseAmount % ONE_ETHER).to.equal(0n);
      }
    });
  });
});
