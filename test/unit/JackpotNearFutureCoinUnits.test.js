// SPDX-License-Identifier: AGPL-3.0-only
// CoinDrawCrapsSeats.t.sol exercises the actual module and table. These checks
// pin the shared unit arithmetic and the trait draw's separate pull sequence.
import { expect } from "chai";
import fs from "node:fs";

const source = fs.readFileSync("contracts/modules/DegenerusGameJackpotModule.sol", "utf8");
const UNIT = 100n * 10n ** 18n;
const SEAT = 2_400n * 10n ** 18n;
const DAY = 20_400n * 10n ** 18n;

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

function plan(budget, seated) {
  const pulls = budget / 2n / SEAT < 25n ? budget / 2n / SEAT : 25n;
  expect(seated <= pulls).to.equal(true);
  const upgrade = DAY - SEAT;
  const affordable = (budget / 2n - seated * SEAT) / upgrade;
  const days = affordable < seated ? affordable : seated;
  const units = (budget - seated * SEAT - days * upgrade) / UNIT;
  const cap = units < 25n ? units : 25n;
  return { pulls, days, cap, amount: cap ? units / cap * UNIT : 0n };
}

describe("JackpotNearFutureCoinUnits — shared coin/Craps plan", function () {
  it("uses up to 25 Craps pulls followed by up to 25 coin pulls", function () {
    const draw = body("function _awardDailyCoinToTraitWinners(");
    expect(draw).to.include("_crapsPulls(coinBudget)");
    expect(draw).to.include("_coinDrawPlan(coinBudget, n)");
    expect(draw).to.match(/i\s*=\s*COIN_DRAW_HALF_SLOTS;\s*i\s*<\s*COIN_DRAW_HALF_SLOTS\s*\+\s*cap/);
    expect(draw).to.include("_finishCoinDraw(craps, crapsLvls, fullDays, coin, 0, paid, amount)");
  });

  it("routes missed Craps pulls into the coin half and computes one whole-unit share", function () {
    const draw = body("function _coinDrawPlan(");
    expect(draw).to.include("(budget >> 1) - n * CRAPS_OPENER_SEAT_VALUE");
    expect(draw).to.include("budget - n * CRAPS_OPENER_SEAT_VALUE - fullDays * CRAPS_DAY_UPGRADE_VALUE");
    expect(draw).to.include("(units / cap) * FlipRoundLib.FLIP_ROUND_UNIT");
    expect(draw).to.include("units < COIN_DRAW_HALF_SLOTS ? units : COIN_DRAW_HALF_SLOTS");
  });

  it("never overspends and pays equal whole-100-FLIP shares across budget and hit counts", function () {
    for (let b = 0n; b <= 1_000_000n; b += 137n) {
      const budget = b * 10n ** 18n;
      const pulls = plan(budget, 0n).pulls;
      for (const seated of [0n, pulls / 2n, pulls]) {
        const { days, cap, amount } = plan(budget, seated);
        expect(cap <= 25n).to.equal(true);
        expect(amount % UNIT).to.equal(0n);
        if (cap) expect(amount >= UNIT).to.equal(true);
        expect(seated * SEAT + days * (DAY - SEAT) + cap * amount <= budget).to.equal(true);
      }
    }
  });
});
