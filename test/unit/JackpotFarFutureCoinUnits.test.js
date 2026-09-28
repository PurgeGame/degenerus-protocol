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

describe("JackpotFarFutureCoinUnits — the daily jackpot battle's award draw", function () {
  it("snapshots the eligible unminted +1 through +99 levels and draws at most one chunk", function () {
    expect(source).to.match(/JACKPOT_BATTLE_ENTRANTS\s*=\s*JackpotBattleFieldLib\.MAX_CHUNK\s*;/);
    const draw = body("function _collectJackpotChunk(");
    expect(draw).to.include("for (uint256 offset; offset < 99; ++offset)");
    expect(draw).to.include("uint24 candidate = lvl + 1 + uint24(offset)");
    expect(draw).to.include("remaining < JACKPOT_BATTLE_ENTRANTS ? remaining : JACKPOT_BATTLE_ENTRANTS");
  });

  it("reads the far-future queues without mutating them", function () {
    const draw = body("function _collectJackpotChunk(");
    expect(draw).to.include("ticketQueue[_tqFarFutureKey(candidate)]");
    expect(draw).to.include("(entropy >> 128) % len");
    expect(draw).to.include("_tqWordAt(queue, walk.position)");
    expect(draw).to.include("if (len == 0)");
    expect(draw).not.to.match(/queue\s*\[[^\]]+\]\s*=|queue\.push|queue\.pop|delete\s+queue/);
  });

  it("appends each chunk to the table, and the sealing chunk settles on the budget its draw left", function () {
    const play = body("function _playJackpotBattle(");
    expect(play).to.include("IJackpotBattle battle = IJackpotBattle(ContractAddresses.CRAPS)");
    expect(play).to.include("JackpotBattleFieldLib.prepare(winners)");
    expect(play).to.include("battle.appendJackpotBattle(field, next, last)");
    expect(play).to.include("battle.advanceJackpotBattle(JACKPOT_BATTLE_SETTLE_UNITS)");
    expect(play).to.include("JACKPOT_DRAW_BASE_UNITS + winners.length * JACKPOT_DRAW_ENTRY_UNITS");
    expect(play).to.include("battle.advanceJackpotBattle(uint64(JACKPOT_BATTLE_SETTLE_UNITS - drawUnits))");
  });
});
