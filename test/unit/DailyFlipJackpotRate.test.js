// SPDX-License-Identifier: AGPL-3.0-only

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const ONE_ETHER = 10n ** 18n;
const PRICE_COIN_UNIT = 1_000n * ONE_ETHER;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotModule.sol"
);

function extractBody(source, signature) {
  const fnIdx = source.indexOf(signature);
  if (fnIdx < 0) return null;

  let depth = 0;
  let bodyStart = -1;
  for (let i = fnIdx; i < source.length; i++) {
    if (source[i] === "{") {
      if (depth === 0) bodyStart = i;
      depth++;
    } else if (source[i] === "}") {
      depth--;
      if (depth === 0) {
        return bodyStart < 0 ? null : source.slice(bodyStart, i + 1);
      }
    }
  }

  return null;
}

describe("Daily FLIP jackpot rate", function () {
  it("budgets 0.25% of the prior ratchet pool at the current-level FLIP price", function () {
    const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
    const body = extractBody(source, "function _calcDailyCoinBudget(");

    expect(body, "`_calcDailyCoinBudget` body not found").to.not.equal(null);
    expect(body).to.match(
      /return\s*\(\s*levelPrizePool\s*\[\s*lvl\s*-\s*1\s*\]\s*\*\s*PRICE_COIN_UNIT\s*\)\s*\/\s*\(\s*priceWei\s*\*\s*400\s*\)\s*;/
    );
    expect(body).not.to.match(/priceWei\s*\*\s*200/);
  });

  it("halves the former 0.5% budget while preserving its ETH-equivalent basis", function () {
    const priorPool = 100n * ONE_ETHER;
    const currentPrice = ONE_ETHER / 100n; // 0.01 ETH per 1,000 FLIP

    const formerBudget =
      (priorPool * PRICE_COIN_UNIT) / (currentPrice * 200n);
    const newBudget =
      (priorPool * PRICE_COIN_UNIT) / (currentPrice * 400n);
    const newEthEquivalent =
      (newBudget * currentPrice) / PRICE_COIN_UNIT;

    expect(newBudget).to.equal(formerBudget / 2n);
    expect(newBudget).to.equal(25_000n * ONE_ETHER);
    expect(newEthEquivalent).to.equal(priorPool / 400n);
  });
});
