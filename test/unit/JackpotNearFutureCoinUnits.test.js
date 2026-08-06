// SPDX-License-Identifier: AGPL-3.0-only
//
// JackpotNearFutureCoinUnits.test.js — 100-FLIP unit split on the near-future coin jackpot.
//
// SUPERSEDES the whole-FLIP floor regression this file used to carry (D-279-INLINE-01):
//   `_awardDailyCoinToTraitWinners` in
//   `contracts/modules/DegenerusGameJackpotModule.sol` no longer divides the budget and
//   floors the quotient to 1 FLIP. It splits the budget into whole 100-FLIP units and
//   floors the PULL COUNT to the units available, so every pull is worth at least one
//   unit and — the property this file exists to pin — EVERY PULL IS WORTH THE SAME:
//
//     units  = coinBudget / FLIP_ROUND_UNIT
//     cap    = min(units, DAILY_COIN_MAX_WINNERS)
//     if (cap == 0) return;                        // a sub-100-FLIP budget pays nobody
//     amount = (units / cap) * FLIP_ROUND_UNIT     // >= 100 FLIP, identical for every pull
//
//   EQUAL SHARES ARE THE POINT (OWNER-RULED). An earlier revision handed `units % cap`
//   pulls one extra unit apiece, placed by a VRF-derived contiguous window, so that the
//   budget was spent to the last unit. That is gone: no winner may receive a different
//   amount from another winner in the same draw, because two winners comparing their
//   pulls must never find one short. The `units % cap` leftover is simply not minted.
//   Exact budget spend was traded away deliberately — see the negative assertions in
//   [01e], which fail the moment the extra-unit machinery is reintroduced.
//
//   No randomness is consumed by the split at all any more. `randomWord` still drives the
//   level sample and the holder index, but nothing about the AMOUNT is random.
//
//   What is NO LONGER true, and is asserted negatively below: there is no `baseAmount`,
//   no `(x / 1 ether) * 1 ether` floor, and no `amount != 0` clause on the winner guard —
//   a paid pull can no longer be credited zero, so the clause would be a dead guard.
//   What IS still true: an empty `(lvl', trait_i)` bucket silently skips and its share is
//   simply not minted (D-40N-BUR-SILENT-01), and the budget remainder evaporates one
//   granule up from the old sub-1-FLIP dust (D-40N-BUR-DUST-01).
//
// TEST STRATEGY:
//   `_awardDailyCoinToTraitWinners` is `private` with a documented fixture-coverage gap
//   (no deterministic full-state harness — winner selection, level + day simulation,
//   trait-burn-ticket state, deity cache). Per the
//   `JackpotTicketRollSilentColdBust.test.js` fixture-coverage-gap precedent, the
//   load-bearing evidence is source-level structural proof: `extractBody` +
//   `stripLineComments` + regex + index-ordering. JS-side BigInt unit math is the
//   confirmation layer — and unlike the Bernoulli collapse it replaces, that math is
//   EXACT, so it wants unit assertions rather than a statistical suite.
//
// CROSS-CITES:
//   - .planning/PLAN-FLIP-ROUND-HUNDREDS.md §3a (budget-split sites — floor the winner count)
//   - D-279-INLINE-01 SUPERSEDED (the inline whole-FLIP floor is gone from this site)
//   - D-40N-BUR-DUST-01 (budget remainder evaporates — now sub-100-FLIP, was sub-1-FLIP)
//   - D-40N-BUR-SILENT-01 (no consolation / replacement event / redistribution)
//   - test/unit/JackpotTicketRollSilentColdBust.test.js (extractBody + stripLineComments infra)

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const ONE_FLIP = 10n ** 18n;
const UNIT = 100n * ONE_FLIP; // FlipRoundLib.FLIP_ROUND_UNIT
const DAILY_COIN_MAX_WINNERS = 50n;

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

// Every structural pattern below is `\s*`-tolerant between tokens, so a formatter
// breaking a ternary across lines does not invalidate the proof.
function loadBody() {
  const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
  const body = extractBody(source, "function _awardDailyCoinToTraitWinners(");
  expect(body, "`_awardDailyCoinToTraitWinners` body not found").to.not.equal(
    null
  );
  return stripLineComments(body);
}

// The on-chain unit split, replicated exactly. `leftover` is the part of the budget the
// equal-share rule declines to mint.
function splitUnits(budgetWei, maxWinners) {
  const units = budgetWei / UNIT;
  const cap = units < maxWinners ? units : maxWinners;
  if (cap === 0n) {
    return { units, cap: 0n, amount: 0n, leftover: units };
  }
  return {
    units,
    cap,
    amount: (units / cap) * UNIT,
    leftover: units % cap,
  };
}

describe("JackpotNearFutureCoinUnits — 100-FLIP equal-share split (§3a)", function () {
  this.timeout(30_000);

  describe("Source-structural proof: `_awardDailyCoinToTraitWinners` splits into equal 100-FLIP shares and floors the pull count", function () {
    it("[01a] derives `units` from the budget against `FlipRoundLib.FLIP_ROUND_UNIT`", function () {
      const body = loadBody();
      expect(
        /uint256\s+units\s*=\s*coinBudget\s*\/\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "`units` must be `coinBudget / FlipRoundLib.FLIP_ROUND_UNIT`"
      ).to.equal(true);
    });

    it("[01b] floors the pull count to `min(units, DAILY_COIN_MAX_WINNERS)` and bails at zero", function () {
      const body = loadBody();
      expect(
        /uint256\s+cap\s*=\s*units\s*<\s*DAILY_COIN_MAX_WINNERS\s*\?\s*units\s*:\s*DAILY_COIN_MAX_WINNERS\s*;/.test(
          body
        ),
        "`cap` must be `min(units, DAILY_COIN_MAX_WINNERS)`"
      ).to.equal(true);
      expect(
        /if\s*\(\s*cap\s*==\s*0\s*\)\s*return\s*;/.test(body),
        "a budget under one 100-FLIP unit must pay nobody (`if (cap == 0) return;`)"
      ).to.equal(true);
    });

    it("[01c] every pull's share is ONE expression computed ONCE, outside the loop", function () {
      const body = loadBody();
      expect(
        /uint256\s+amount\s*=\s*\(\s*units\s*\/\s*cap\s*\)\s*\*\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "the share must be `(units / cap) * FlipRoundLib.FLIP_ROUND_UNIT`"
      ).to.equal(true);
      // Hoisted above the loop: one assignment in the whole body, so no per-pull path can
      // reach a different figure.
      const assignments = (body.match(/\bamount\s*=/g) || []).length;
      expect(
        assignments,
        "`amount` must be assigned exactly once — a second assignment would mean per-pull variation"
      ).to.equal(1);
      const loopIdx = body.search(/for\s*\(\s*uint256\s+i\s*;/);
      const amountIdx = body.search(/uint256\s+amount\s*=/);
      expect(amountIdx, "`amount` declaration not found").to.be.greaterThan(-1);
      expect(loopIdx, "the pull loop not found").to.be.greaterThan(-1);
      expect(
        amountIdx,
        "`amount` must be computed BEFORE the pull loop, not inside it"
      ).to.be.lessThan(loopIdx);
    });

    it("[01d] the retired whole-FLIP floor and its `baseAmount` local are WHOLLY ABSENT (D-279-INLINE-01 superseded)", function () {
      const body = loadBody();
      expect(
        /\/ 1 ether\s*\)\s*\*\s*1 ether/.test(body),
        "the `(x / 1 ether) * 1 ether` whole-FLIP floor must be gone — the unit split replaces it"
      ).to.equal(false);
      expect(
        /\bbaseAmount\b/.test(body),
        "`baseAmount` must be wholly removed — the equal share supersedes it"
      ).to.equal(false);
    });

    it("[01e] the extra-unit machinery is WHOLLY ABSENT — equal shares are owner-ruled", function () {
      const body = loadBody();
      for (const token of [
        "extra",
        "extraStart",
        "baseUnits",
        "FLIP_EXTRA_UNIT_TAG",
      ]) {
        expect(
          new RegExp(`\\b${token}\\b`).test(body),
          `\`${token}\` must be gone — every paid pull receives the SAME amount, and the ` +
            `\`units % cap\` leftover is deliberately not minted`
        ).to.equal(false);
      }
      // The split consumes no entropy whatsoever now.
      const hashCount = (body.match(/EntropyLib\.hash2\(/g) || []).length;
      expect(
        hashCount,
        "the equal-share split must draw no entropy at all — nothing about the amount is random"
      ).to.equal(0);
    });

    it("[01f] the winner guard no longer carries a dead `amount != 0` clause", function () {
      const body = loadBody();
      expect(
        /if\s*\(\s*winner\s*!=\s*address\(0\)\s*\)\s*\{/.test(body),
        "the guard must be `if (winner != address(0))`"
      ).to.equal(true);
      expect(
        /amount\s*!=\s*0/.test(body),
        "the `amount != 0` clause must be gone — every paid pull clears one 100-FLIP unit by construction"
      ).to.equal(false);
    });

    it("[01g] `randomWord` still feeds both keccak draws (level sample + holder index)", function () {
      const body = loadBody();
      expect(
        /\brandomWord\b/.test(body),
        "`randomWord` must still appear — it drives the level and holder draws"
      ).to.equal(true);
      const keccakDraws = (body.match(/abi\.encode\(randomWord,/g) || []).length;
      expect(
        keccakDraws,
        "`randomWord` must feed both keccak draws (level sample + holder index)"
      ).to.be.gte(2);
    });

    it("[01h] both `++i` loop increments are intact (empty-bucket continue + loop tail)", function () {
      const body = loadBody();
      const incCount = (body.match(/\+\+i\s*;/g) || []).length;
      expect(
        incCount,
        "both `++i` increments (empty-bucket continue branch + loop tail) must survive"
      ).to.equal(2);
    });
  });

  describe("Index-ordering proof: the zero-unit bail precedes the loop, and the batch call sits behind `anyWinner`", function () {
    it("[02a] `cap == 0` return → winner guard → `JackpotFlipWin` emit → batch accumulation → `anyWinner` gate → `creditFlipBatch`", function () {
      const body = loadBody();

      const capReturnIdx = body.search(
        /if\s*\(\s*cap\s*==\s*0\s*\)\s*return\s*;/
      );
      const guardIdx = body.search(/if\s*\(\s*winner\s*!=\s*address\(0\)\s*\)/);
      const emitIdx = body.indexOf("emit JackpotFlipWin(");
      const accumIdx = body.indexOf("batchPlayers[i] = winner");
      const batchCallIdx = body.indexOf(
        "coinflip.creditFlipBatch(batchPlayers, batchAmounts)"
      );
      const anyWinnerGateIdx = body.search(/if\s*\(\s*anyWinner\s*\)/);

      expect(
        capReturnIdx,
        "`if (cap == 0) return;` zero-unit bail not found"
      ).to.be.greaterThan(-1);
      expect(
        guardIdx,
        "`if (winner != address(0))` guard not found"
      ).to.be.greaterThan(-1);
      expect(emitIdx, "`JackpotFlipWin` emit not found").to.be.greaterThan(-1);
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
        capReturnIdx,
        "the `cap == 0` bail must precede the winner guard so a sub-unit budget skips the whole selection loop"
      ).to.be.lessThan(guardIdx);
      expect(
        guardIdx,
        "the winner guard must precede the `JackpotFlipWin` emit so an empty bucket emits nothing"
      ).to.be.lessThan(emitIdx);
      expect(
        emitIdx,
        "the `JackpotFlipWin` emit must precede the batch accumulation (both inside the guard)"
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

  describe("JS unit math: every pull is equal and no pull is zero (confirmation layer)", function () {
    it("a sub-100-FLIP budget pays nobody", function () {
      for (const budgetFlip of [0n, 1n, 50n, 99n]) {
        const { cap } = splitUnits(
          ONE_FLIP * budgetFlip,
          DAILY_COIN_MAX_WINNERS
        );
        expect(cap).to.equal(0n, `budget ${budgetFlip} FLIP must pay nobody`);
      }
    });

    it("the worked 100-ETH-pool example: 4,687 FLIP → 46 pulls of exactly 100 FLIP, 87 FLIP evaporates", function () {
      const budget = ONE_FLIP * 4_687n;
      const { units, cap, amount, leftover } = splitUnits(
        budget,
        DAILY_COIN_MAX_WINNERS
      );
      expect(units).to.equal(46n);
      expect(cap).to.equal(46n);
      expect(amount).to.equal(UNIT);
      expect(leftover).to.equal(0n, "the budget-bound regime wastes no unit");
      expect(budget - cap * amount).to.equal(
        ONE_FLIP * 87n,
        "the evaporating sub-unit dust"
      );
    });

    it("the ceiling-bound example: 75 units over 50 pulls → every pull 100 FLIP, 25 units decline to be minted", function () {
      const budget = 75n * UNIT;
      const { units, cap, amount, leftover } = splitUnits(
        budget,
        DAILY_COIN_MAX_WINNERS
      );
      expect(units).to.equal(75n);
      expect(cap).to.equal(50n);
      expect(amount).to.equal(UNIT, "every pull is one unit — none is doubled");
      expect(leftover).to.equal(25n);
      // This is the deliberate trade: equal shares cost 25 units of spend here.
      expect(cap * amount).to.equal(50n * UNIT);
      expect(budget - cap * amount).to.equal(25n * UNIT);
    });

    it("an evenly-divisible ceiling-bound budget wastes nothing: 150 units over 50 pulls → every pull 300 FLIP", function () {
      const budget = 150n * UNIT;
      const { cap, amount, leftover } = splitUnits(
        budget,
        DAILY_COIN_MAX_WINNERS
      );
      expect(cap).to.equal(50n);
      expect(amount).to.equal(3n * UNIT);
      expect(leftover).to.equal(0n);
      expect(cap * amount).to.equal(budget);
    });

    it("across a budget sweep: every pull is identical, clears 100 FLIP, and the budget is never overshot", function () {
      const budgets = [
        100n,
        137n,
        999n,
        1_000n,
        4_687n,
        5_000n,
        7_500n,
        12_345n,
        1_000_000n,
      ];
      for (const budgetFlip of budgets) {
        const budget = ONE_FLIP * budgetFlip;
        const { units, cap, amount, leftover } = splitUnits(
          budget,
          DAILY_COIN_MAX_WINNERS
        );
        if (cap === 0n) continue;

        expect(cap).to.equal(
          units < DAILY_COIN_MAX_WINNERS ? units : DAILY_COIN_MAX_WINNERS,
          `cap at budget ${budgetFlip} FLIP`
        );
        expect(amount % UNIT).to.equal(
          0n,
          `share ${amount} is not a 100-FLIP multiple`
        );
        expect(amount >= UNIT).to.equal(
          true,
          `share ${amount} is below one unit at budget ${budgetFlip} FLIP`
        );

        const spent = cap * amount;
        expect(spent <= budget).to.equal(
          true,
          "the budget can never be overshot"
        );
        expect(leftover).to.equal(
          units % cap,
          "the unminted leftover is exactly the uneven-division remainder"
        );
        // Everything not minted is the leftover units plus the sub-unit dust.
        expect(budget - spent).to.equal(
          leftover * UNIT + (budget - units * UNIT),
          `unminted budget at ${budgetFlip} FLIP`
        );
        expect(leftover < cap).to.equal(
          true,
          "the leftover is always under one full round of shares"
        );
      }
    });
  });
});
