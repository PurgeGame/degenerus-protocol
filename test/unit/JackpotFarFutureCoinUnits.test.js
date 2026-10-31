// SPDX-License-Identifier: AGPL-3.0-only
// LevelOneFlipDraw.t.sol tests actual payouts. These checks pin the bounded
// level walk and handoff of the daily future jackpot battle.
import { expect } from "chai";
import fs from "node:fs";

const source = fs.readFileSync("contracts/modules/DegenerusGameJackpotDrawModule.sol", "utf8");

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
    const snapshot = body("function _jackpotDrawLevels(");
    expect(snapshot).to.include("for (uint256 offset; offset < 99; ++offset)");
    expect(snapshot).to.include("uint24 candidate = lvl + 1 + uint24(offset)");
    const draw = body("function _collectJackpotChunkWithLevels(");
    expect(draw).to.include("remaining < JACKPOT_BATTLE_ENTRANTS ? remaining : JACKPOT_BATTLE_ENTRANTS");
  });

  it("reads the far-future queues without mutating them", function () {
    const draw = body("function _collectJackpotChunkWithLevels(");
    expect(draw).to.include("ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(candidate))]");
    expect(draw).to.include("(entropy >> 128) % len");
    expect(draw).to.include("_tqWordAt(queue, walk.position)");
    expect(draw).to.include("if (len == 0)");
    expect(draw).not.to.match(/queue\s*\[[^\]]+\]\s*=|queue\.push|queue\.pop|delete\s+queue/);
  });

  it("appends the frozen field and admits settlement only after marking construction progress", function () {
    const play = body("function _runPurchaseJackpotBattle(");
    expect(play).to.include("IJackpotBattle battle = IJackpotBattle(ContractAddresses.CRAPS)");
    expect(play).to.include("JackpotBattleFieldLib.prepare(winners)");
    expect(play).to.include("battle.appendJackpotBattle(field, next, fieldSealed)");
    expect(play).to.include("MineFlipGas.canRun(meter, GasBounds.JACKPOT_BATTLE_DRAW, GasBounds.DAILY_PHASE_TAIL)");
    const admission = play.indexOf("if (fieldSealed && MineFlipGas.canRun(meter, JACKPOT_BATTLE_SETTLE_ADMISSION, JACKPOT_BATTLE_SETTLE_TAIL))");
    expect(admission).to.be.greaterThan(play.indexOf("MineFlipGas.markProgress(meter)"));
    expect(play.slice(admission)).to.include("_settleJackpotBattle(meter, result, complete)");
    const settle = body("function _settleJackpotBattle(");
    expect(settle).to.include("runDailyBattleWork(childAllowance)");
    expect(settle).to.include("result.rewardBasis += settled.rewardBasis");
    expect(settle).to.include("dailyTicketBudgetsPacked &= ~_JACKPOT_BATTLE_PENDING");
    expect(play.slice(admission)).to.include("MineFlipGas.finish(meter)");
  });
});
