// SPDX-License-Identifier: AGPL-3.0-only
// CoinDrawCrapsSeats.t.sol tests actual payouts. These checks pin the bounded
// level walk and handoff of the purchase-day future draw.
import { expect } from "chai";
import fs from "node:fs";

const source = fs.readFileSync("contracts/modules/DegenerusGameJackpotModule.sol", "utf8");

function body(signature) {
  const start = source.indexOf(signature);
  expect(start, `${signature} missing`).to.be.greaterThan(-1);
  const open = source.indexOf("{", start);
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === "{") depth++;
    else if (source[i] === "}" && --depth === 0) return source.slice(open, i + 1);
  }
  throw new Error(`unclosed ${signature}`);
}

describe("JackpotFarFutureCoinUnits — purchase-day future fill", function () {
  it("picks at most 16 distinct levels in the unminted +1 through +99 band", function () {
    expect(source).to.match(/FUTURE_FLIP_LEVEL_PICKS\s*=\s*16\s*;/);
    const draw = body("function _awardFutureCoinFill(");
    expect(draw).to.include("pick < FUTURE_FLIP_LEVEL_PICKS && found < want");
    expect(draw).to.include("uint256 offset = entropy % 99");
    expect(draw).to.include("(visited >> offset) & 1 == 0");
    expect(draw).to.include("visited |= uint256(1) << offset");
    expect(draw).to.include("lvl + 1 + uint24(offset)");
  });

  it("reads the far-future queues from a random starting lane without mutating them", function () {
    const draw = body("function _awardFutureCoinFill(");
    expect(draw).to.include("ticketQueue[_tqFarFutureKey(candidate)]");
    expect(draw).to.include("(entropy >> 128) % len");
    expect(draw).to.include("_tqWordAt(queue, idx)");
    expect(draw).to.include("if (idx == len) idx = 0");
    expect(draw).not.to.match(/queue\s*\[[^\]]+\]\s*=|queue\.push|queue\.pop|delete\s+queue/);
  });

  it("allocates the first found wallets to Craps, then at most 25 equal coin shares", function () {
    const draw = body("function _awardFutureCoinFill(");
    expect(draw).to.include("uint256 want = pulls + COIN_DRAW_HALF_SLOTS");
    expect(draw).to.include("uint256 n = found < pulls ? found : pulls");
    expect(draw).to.include("_coinDrawPlan(coinBudget, n)");
    expect(draw).to.include("if (paid > cap) paid = cap");
    expect(draw).to.include("_finishCoinDraw(craps, crapsLvls, fullDays, winners, n, paid, amount)");
  });
});
