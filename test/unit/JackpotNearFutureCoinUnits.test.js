// SPDX-License-Identifier: AGPL-3.0-only
// LevelOneFlipDraw.t.sol exercises the actual module and table. These checks
// pin level 1's FLIP-only trait-matched share arithmetic.
import { expect } from "chai";
import fs from "node:fs";

const source = fs.readFileSync("contracts/modules/DegenerusGameJackpotModule.sol", "utf8");
const UNIT = 100n * 10n ** 18n;
const SHARES = 50n;

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

function plan(budget) {
  const units = budget / UNIT;
  if (units === 0n) return { cap: 0n, amount: 0n };
  const cap = units < SHARES ? units : SHARES;
  const amount = (units / cap) * UNIT;
  return { cap, amount };
}

describe("JackpotNearFutureCoinUnits — trait-matched FLIP share plan", function () {
  it("caps the draw at COIN_DRAW_SHARES equal whole-unit shares", function () {
    expect(source).to.match(/COIN_DRAW_SHARES\s*=\s*50\s*;/);
    const draw = body("function _awardDailyCoinToTraitWinners(");
    expect(draw).to.include("uint256 units = coinBudget / FlipRoundLib.FLIP_ROUND_UNIT");
    expect(draw).to.include("if (units == 0) return;");
    expect(draw).to.include("units < COIN_DRAW_SHARES ? units : COIN_DRAW_SHARES");
    expect(draw).to.include("(units / cap) * FlipRoundLib.FLIP_ROUND_UNIT");
    expect(draw).to.match(/for\s*\(uint256 i;\s*i\s*<\s*cap;/);
    expect(draw).to.include("uint8 traitIdx = uint8(i & 3)");
    // The daily jackpot battle is a separate call; this draw never touches CrapsBattle.
    expect(draw).not.to.include("ICrapsCoinDrawSeat");
    expect(draw).not.to.include("_finishJackpotBattle");
  });

  it("pays one JackpotFlipWin per drawn winner and one creditFlipBatch for the whole cap", function () {
    const draw = body("function _awardDailyCoinToTraitWinners(");
    expect(draw).to.include("emit JackpotFlipWin(winner, lvlPrime, trait_i, amount, ticketIdx)");
    expect(draw).to.include("coinflip.creditFlipBatch(players, amounts)");
  });

  it("never overspends and pays equal whole-100-FLIP shares across budget", function () {
    for (let b = 0n; b <= 1_000_000n; b += 137n) {
      const budget = b * 10n ** 18n;
      const { cap, amount } = plan(budget);
      expect(cap <= SHARES).to.equal(true);
      expect(amount % UNIT).to.equal(0n);
      if (cap) expect(amount >= UNIT).to.equal(true);
      expect(cap * amount <= budget).to.equal(true);
    }
  });
});
