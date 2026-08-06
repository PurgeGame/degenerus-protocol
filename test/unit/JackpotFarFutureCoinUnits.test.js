// SPDX-License-Identifier: AGPL-3.0-only
//
// JackpotFarFutureCoinUnits.test.js — 100-FLIP unit split on the far-future coin jackpot.
//
// SUPERSEDES the whole-FLIP floor regression this file used to carry (D-279-INLINE-01 /
// D-279-BUR03-ORDER-01):
//   `_awardFarFutureCoinJackpot` in
//   `contracts/modules/DegenerusGameJackpotModule.sol` no longer computes
//   `perWinner = ((farBudget / found) / 1 ether) * 1 ether` and bails when it floors to
//   zero. It splits the budget into whole 100-FLIP units and pays a PREFIX of the sampled
//   winners, one unit minimum each:
//
//     units     = farBudget / FLIP_ROUND_UNIT
//     payCount  = min(units, found)
//     if (payCount == 0) return;             // a sub-100-FLIP budget pays nobody
//     amount    = (units / payCount) * UNIT  // >= 100 FLIP, identical for every winner
//
//   EQUAL SHARES ARE THE POINT (OWNER-RULED). An earlier revision handed `units % payCount`
//   winners one extra unit apiece so the budget was spent to the last unit; that is gone,
//   and the leftover is deliberately not minted. No winner may receive a different amount
//   from another winner in the same draw.
//
//   The sampling loop discovers `found` (<= FAR_FUTURE_FLIP_SAMPLES) winners BEFORE the
//   budget is known to divide, so truncating to `payCount` simply pays fewer of them.
//   `winners[]` is already ordered by its own per-sample VRF draw, so taking a prefix
//   introduces no new choice for anyone to steer — that is the load-bearing property here
//   and it is asserted structurally below (the array is indexed `[i]`, never reordered).
//
//   The old ORDER property survives in its new form: the `payCount == 0` bail must sit
//   between the unit math and the `creditFlipBatch` call, so an under-funded draw cannot
//   reach the batch credit. What is gone: `perWinner`, the extra-unit window, the
//   `(x / 1 ether) * 1 ether`
//   floor, and any path that credits a sampled winner zero.
//
// TEST STRATEGY:
//   `_awardFarFutureCoinJackpot` is `private` with the same fixture-coverage gap as its
//   near-future sibling (ticketQueue state across 95 far-future levels, VRF word,
//   per-sample draws). Load-bearing evidence is source-level structural proof; JS-side
//   BigInt unit math is the confirmation layer, and that math is EXACT.
//
// CROSS-CITES:
//   - .planning/PLAN-FLIP-ROUND-HUNDREDS.md §3a (budget-split sites — floor the winner count)
//   - D-279-INLINE-01 SUPERSEDED / D-279-BUR03-ORDER-01 restated for the new bail
//   - D-40N-BUR-DUST-01 (budget remainder evaporates — now sub-100-FLIP, was sub-1-FLIP)
//   - test/unit/JackpotNearFutureCoinUnits.test.js (the sibling site, same unit math)

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const ONE_FLIP = 10n ** 18n;
const UNIT = 100n * ONE_FLIP; // FlipRoundLib.FLIP_ROUND_UNIT
const FAR_FUTURE_FLIP_SAMPLES = 10n;

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
function loadBody() {
  const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
  const body = extractBody(source, "function _awardFarFutureCoinJackpot(");
  expect(body, "`_awardFarFutureCoinJackpot` body not found").to.not.equal(null);
  return stripLineComments(body);
}

// The on-chain unit split, replicated exactly.
function splitUnits(budgetWei, found) {
  const units = budgetWei / UNIT;
  const payCount = units < found ? units : found;
  if (payCount === 0n) {
    return { units, payCount: 0n, amount: 0n, leftover: units };
  }
  return {
    units,
    payCount,
    amount: (units / payCount) * UNIT,
    leftover: units % payCount,
  };
}


describe("JackpotFarFutureCoinUnits — 100-FLIP unit split (§3a)", function () {
  this.timeout(30_000);

  describe("Source-structural proof: `_awardFarFutureCoinJackpot` pays a prefix of the sampled winners in whole units", function () {
    it("[01a] derives `units` from the budget and truncates the winner list to `min(units, found)`", function () {
      const body = loadBody();
      expect(
        /uint256\s+units\s*=\s*farBudget\s*\/\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "`units` must be `farBudget / FlipRoundLib.FLIP_ROUND_UNIT`"
      ).to.equal(true);
      expect(
        /uint256\s+payCount\s*=\s*units\s*<\s*found\s*\?\s*units\s*:\s*found\s*;/.test(
          body
        ),
        "`payCount` must be `min(units, found)`"
      ).to.equal(true);
      expect(
        /if\s*\(\s*payCount\s*==\s*0\s*\)\s*return\s*;/.test(body),
        "a budget under one 100-FLIP unit must pay nobody (`if (payCount == 0) return;`)"
      ).to.equal(true);
    });

    it("[01b] every winner's share is ONE expression computed ONCE, outside the loop", function () {
      const body = loadBody();
      expect(
        /uint256\s+amount\s*=\s*\(\s*units\s*\/\s*payCount\s*\)\s*\*\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "the share must be `(units / payCount) * FlipRoundLib.FLIP_ROUND_UNIT`"
      ).to.equal(true);
      const assignments = (body.match(/\bamount\s*=/g) || []).length;
      expect(
        assignments,
        "`amount` must be assigned exactly once — a second assignment would mean per-winner variation"
      ).to.equal(1);
      const loopIdx = body.search(/for\s*\(\s*uint256\s+i\s*;/);
      const amountIdx = body.search(/uint256\s+amount\s*=/);
      expect(amountIdx, "`amount` declaration not found").to.be.greaterThan(-1);
      expect(loopIdx, "the payout loop not found").to.be.greaterThan(-1);
      expect(
        amountIdx,
        "`amount` must be computed BEFORE the payout loop, not inside it"
      ).to.be.lessThan(loopIdx);
    });

    it("[01c] the retired whole-FLIP floor and its `perWinner` local are WHOLLY ABSENT (D-279-INLINE-01 superseded)", function () {
      const body = loadBody();
      expect(
        /\/ 1 ether\s*\)\s*\*\s*1 ether/.test(body),
        "the `(x / 1 ether) * 1 ether` whole-FLIP floor must be gone — the unit split replaces it"
      ).to.equal(false);
      expect(
        /\bperWinner\b/.test(body),
        "`perWinner` must be wholly removed — the equal share supersedes it"
      ).to.equal(false);
    });

    it("[01d] the extra-unit machinery is WHOLLY ABSENT — equal shares are owner-ruled", function () {
      const body = loadBody();
      for (const token of [
        "extra",
        "extraStart",
        "baseUnits",
        "FLIP_EXTRA_UNIT_TAG",
      ]) {
        expect(
          new RegExp(`\\b${token}\\b`).test(body),
          `\`${token}\` must be gone — every paid winner receives the SAME amount, and the ` +
            `\`units % payCount\` leftover is deliberately not minted`
        ).to.equal(false);
      }
    });

    it("[01e] the prefix is taken in place — `winners[]` is read by index and never reordered", function () {
      const body = loadBody();
      // The payout loop reads `winners[i]` / `winnerLevels[i]` directly, so the
      // truncation is a prefix of an order fixed by the per-sample VRF draw.
      expect(
        /batchPlayers\[i\]\s*=\s*winners\[i\]\s*;/.test(body),
        "the payout loop must read `winners[i]` in place"
      ).to.equal(true);
      expect(
        /for\s*\(\s*uint256\s+i\s*;\s*i\s*<\s*payCount\s*;\s*\)/.test(body),
        "the payout loop must be bounded by `payCount`, not by `found`"
      ).to.equal(true);
      // No sort/swap machinery may creep in — a reorder would hand the caller a choice.
      expect(
        /\bsort\b|\bswap\b/i.test(body),
        "the winner array must not be reordered before truncation"
      ).to.equal(false);
    });

    it("[01f] the sampling loop still fills `winners[]` from `FAR_FUTURE_FLIP_SAMPLES` draws", function () {
      const body = loadBody();
      expect(
        /for\s*\(\s*uint8\s+s\s*;\s*s\s*<\s*FAR_FUTURE_FLIP_SAMPLES\s*;\s*\)/.test(
          body
        ),
        "the sampling loop must still be bounded by `FAR_FUTURE_FLIP_SAMPLES`"
      ).to.equal(true);
      expect(
        /if\s*\(\s*found\s*==\s*0\s*\)\s*return\s*;/.test(body),
        "an empty sample must still bail before the unit math"
      ).to.equal(true);
    });
  });

  describe("Index-ordering proof: the zero-unit bail sits between the unit math and the batch credit", function () {
    it("[02a] `found == 0` return → `units` → `payCount == 0` return → payout loop → `creditFlipBatch`", function () {
      const body = loadBody();

      const foundReturnIdx = body.search(
        /if\s*\(\s*found\s*==\s*0\s*\)\s*return\s*;/
      );
      const unitsIdx = body.indexOf("uint256 units = farBudget");
      const payCountReturnIdx = body.search(
        /if\s*\(\s*payCount\s*==\s*0\s*\)\s*return\s*;/
      );
      const emitIdx = body.indexOf("emit FarFutureFlipJackpotWinner(");
      const batchCallIdx = body.indexOf(
        "coinflip.creditFlipBatch(batchPlayers, batchAmounts)"
      );

      expect(
        foundReturnIdx,
        "`if (found == 0) return;` empty-sample bail not found"
      ).to.be.greaterThan(-1);
      expect(unitsIdx, "`units` derivation not found").to.be.greaterThan(-1);
      expect(
        payCountReturnIdx,
        "`if (payCount == 0) return;` zero-unit bail not found"
      ).to.be.greaterThan(-1);
      expect(
        emitIdx,
        "`FarFutureFlipJackpotWinner` emit not found"
      ).to.be.greaterThan(-1);
      expect(
        batchCallIdx,
        "`coinflip.creditFlipBatch(batchPlayers, batchAmounts)` call not found"
      ).to.be.greaterThan(-1);

      expect(
        foundReturnIdx,
        "the empty-sample bail must precede the unit math"
      ).to.be.lessThan(unitsIdx);
      expect(
        unitsIdx,
        "the unit math must precede the `payCount == 0` bail"
      ).to.be.lessThan(payCountReturnIdx);
      expect(
        payCountReturnIdx,
        "the `payCount == 0` bail MUST precede the batch credit so an under-funded draw cannot reach `creditFlipBatch` (D-279-BUR03-ORDER-01, restated)"
      ).to.be.lessThan(batchCallIdx);
      expect(
        payCountReturnIdx,
        "the `payCount == 0` bail must precede the payout loop's emit"
      ).to.be.lessThan(emitIdx);
      expect(
        emitIdx,
        "the emit must precede the post-loop batch call"
      ).to.be.lessThan(batchCallIdx);
    });
  });

  describe("JS unit math: the split is EXACT, not merely EV-exact (confirmation layer)", function () {
    it("a sub-100-FLIP budget pays nobody, whatever `found` was", function () {
      for (let found = 1n; found <= FAR_FUTURE_FLIP_SAMPLES; found++) {
        for (const budgetFlip of [0n, 1n, 50n, 99n]) {
          const { payCount } = splitUnits(ONE_FLIP * budgetFlip, found);
          expect(payCount).to.equal(
            0n,
            `budget ${budgetFlip} FLIP with found=${found} must pay nobody`
          );
        }
      }
    });

    it("a budget short of the sample count pays a prefix, one unit each", function () {
      // 5 units, 10 sampled winners → the first 5 take 100 FLIP each; 5 are dropped.
      const { units, payCount, amount, leftover } = splitUnits(
        5n * UNIT,
        FAR_FUTURE_FLIP_SAMPLES
      );
      expect(units).to.equal(5n);
      expect(payCount).to.equal(5n);
      expect(amount).to.equal(UNIT);
      expect(leftover).to.equal(0n);
      expect(payCount * amount).to.equal(units * UNIT);
    });

    it("an unevenly-divisible budget pays equal shares and declines the leftover", function () {
      // 27 units over 10 sampled winners → 2 units each, 7 units not minted.
      const { payCount, amount, leftover } = splitUnits(
        27n * UNIT,
        FAR_FUTURE_FLIP_SAMPLES
      );
      expect(payCount).to.equal(10n);
      expect(amount).to.equal(2n * UNIT, "every winner takes the same 200 FLIP");
      expect(leftover).to.equal(7n);
      expect(payCount * amount).to.equal(20n * UNIT);
    });

    it("across a budget × found sweep: every paid winner is identical, clears 100 FLIP, and the budget is never overshot", function () {
      const budgets = [100n, 137n, 999n, 1_000n, 2_500n, 12_345n, 1_000_000n];
      for (let found = 1n; found <= FAR_FUTURE_FLIP_SAMPLES; found++) {
        for (const budgetFlip of budgets) {
          const budget = ONE_FLIP * budgetFlip;
          const { units, payCount, amount, leftover } = splitUnits(
            budget,
            found
          );
          if (payCount === 0n) continue;

          expect(payCount).to.equal(units < found ? units : found);
          expect(payCount <= found).to.equal(
            true,
            "never pay more winners than were sampled"
          );
          expect(amount % UNIT).to.equal(
            0n,
            `share ${amount} is not a 100-FLIP multiple`
          );
          expect(amount >= UNIT).to.equal(
            true,
            `share ${amount} is below one unit (budget ${budgetFlip} FLIP, found ${found})`
          );

          const spent = payCount * amount;
          expect(spent <= budget).to.equal(
            true,
            "the budget can never be overshot"
          );
          expect(leftover).to.equal(
            units % payCount,
            "the unminted leftover is exactly the uneven-division remainder"
          );
          expect(budget - spent).to.equal(
            leftover * UNIT + (budget - units * UNIT),
            `unminted budget at ${budgetFlip} FLIP, found ${found}`
          );
          expect(leftover < payCount).to.equal(
            true,
            "the leftover is always under one full round of shares"
          );
        }
      }
    });
  });
});
