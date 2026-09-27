// SPDX-License-Identifier: AGPL-3.0-only
// LevelOneFlipDraw.t.sol tests actual payouts. These checks pin the bounded
// level walk and handoff of the daily future jackpot battle.
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
    expect(source).to.match(/JACKPOT_BATTLE_ENTRANTS\s*=\s*50\s*;/);
    const draw = body("function _playJackpotBattle(");
    expect(draw).to.include("pick < FUTURE_FLIP_LEVEL_PICKS && found < JACKPOT_BATTLE_ENTRANTS");
    expect(draw).to.include("uint256 offset = entropy % 99");
    expect(draw).to.include("(visited >> offset) & 1 == 0");
    expect(draw).to.include("visited |= uint256(1) << offset");
    expect(draw).to.include("lvl + 1 + uint24(offset)");
  });

  it("reads the far-future queues from a random starting lane without mutating them", function () {
    const draw = body("function _playJackpotBattle(");
    expect(draw).to.include("ticketQueue[_tqFarFutureKey(candidate)]");
    expect(draw).to.include("(entropy >> 128) % len");
    expect(draw).to.include("_tqWordAt(queue, idx)");
    expect(draw).to.include("if (idx == len) idx = 0");
    expect(draw).not.to.match(/queue\s*\[[^\]]+\]\s*=|queue\.push|queue\.pop|delete\s+queue/);
  });

  it("hands the prepared field and the whole budget to JackpotBattle, then credits its result", function () {
    const draw = body("function _playJackpotBattle(");
    expect(draw).to.include("if (found == 0) return;");
    expect(draw).to.include("mstore(winners, found)");
    expect(draw).to.include("IJackpotBattle battle = IJackpotBattle(ContractAddresses.JACKPOT_BATTLE)");
    expect(draw).to.include("JackpotBattleFieldLib.prepare(winners, coinBudget)");
    expect(draw).to.include("battle.resolve(lvl, field, coinBudget, battleWord)");
    expect(draw).to.include("if (players.length != 0) coinflip.creditFlipBatch(players, owed)");
    // Craps supplies preferences only; the whole pot still goes to one immediate battle.
    expect(draw).not.to.include("ICrapsCoinDrawSeat");
    expect(draw).not.to.include("_finishJackpotBattle");
  });
});
