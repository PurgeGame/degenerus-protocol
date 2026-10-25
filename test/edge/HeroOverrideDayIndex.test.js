// SPDX-License-Identifier: AGPL-3.0-only
// Hero weights follow daily commitments. Calendar changes alone never seal a pool.
import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { advanceToNextDay } from "../helpers/testUtils.js";
import { compiledStorageLayout } from "../helpers/storageLayout.js";

const BET = hre.ethers.parseEther("0.005");
const UNITS = BET / 100_000_000_000_000n;
async function bet(game, signer, quadrant, symbol) {
  await game.connect(signer).placeDegeneretteBet(0, 0, BET, 1, quadrant * 8 + symbol, { value: BET });
}
async function winner(game, day) {
  const [quadrant, symbol, amount] = await game.getDailyHeroWinner(day);
  return [quadrant, symbol, amount];
}
async function dailyIdx(game) {
  const layout = await compiledStorageLayout();
  const field = layout.storage.find((entry) => entry.label === "dailyIdx");
  const word = BigInt(await hre.ethers.provider.getStorage(await game.getAddress(), field.slot));
  return (word >> (BigInt(field.offset) * 8n)) & 0xffffffn;
}
async function requestNextDay(game) {
  await advanceToNextDay();
  for (let i = 0; i < 12 && !(await game.rngLocked()); ++i) await game.mineFlip(0, { gasLimit: 16_777_216 });
  expect(await game.rngLocked(), "a real daily request sealed the pool").to.equal(true);
  return (await game.currentDayView_g542950()) - 1n;
}

describe("HeroOverrideDayIndex — daily commitment and stalled accumulation", function () {
  this.timeout(180_000);
  after(() => restoreAddresses());

  it("carries an unsealed pool across calendar days and exposes it under today's view", async function () {
    const { game, alice, bob } = await loadFixture(deployFullProtocol);
    const start = await game.currentDayView_g542950();
    const index = await dailyIdx(game);
    await bet(game, alice, 2, 5);
    expect(await game.getDailyHeroWager(start, 2, 5)).to.equal(UNITS);
    await advanceToNextDay();
    await bet(game, bob, 2, 5);
    expect(await game.getDailyHeroWager(start, 2, 5)).to.equal(2n * UNITS);
    expect(await game.getDailyHeroWager(start + 1n, 2, 5)).to.equal(0n);
    expect(await dailyIdx(game)).to.equal(index, "clock and wagers do not advance the operational index");
  });

  it("freezes the accumulated winner at the real daily request", async function () {
    const { game, alice, bob } = await loadFixture(deployFullProtocol);
    const start = await game.currentDayView_g542950();
    await bet(game, alice, 1, 3);
    const expected = await winner(game, start);
    expect(expected).to.deep.equal([1n, 3n, UNITS]);
    const sealed = await requestNextDay(game);
    expect(sealed).to.equal(start);
    expect(await winner(game, sealed)).to.deep.equal(expected);
    expect(await winner(game, sealed)).to.deep.equal(expected, "repeated payout reads agree");
    await bet(game, bob, 2, 7);
    expect(await winner(game, sealed)).to.deep.equal(expected, "later wager cannot alter the frozen draw");
    expect(await winner(game, await game.currentDayView_g542950())).to.deep.equal([2n, 7n, UNITS]);
  });

  it("keeps both payout reads identical across three stalled days of interleaved wagers", async function () {
    const { game, alice, bob } = await loadFixture(deployFullProtocol);
    await bet(game, alice, 0, 3);
    const sealed = await requestNextDay(game);
    const before = await winner(game, sealed);
    const frozenIndex = await dailyIdx(game);
    expect(before).to.deep.equal([0n, 3n, UNITS]);
    for (let i = 0; i < 3; ++i) {
      await advanceToNextDay();
      await bet(game, bob, 2, 7);
      expect(await winner(game, sealed)).to.deep.equal(before);
      expect(await game.getDailyHeroWager(await game.currentDayView_g542950(), 2, 7)).to.equal(BigInt(i + 1) * UNITS);
      expect(await dailyIdx(game)).to.equal(frozenIndex);
    }
    expect(await game.getDailyHeroWager(sealed + 2n, 2, 7)).to.equal(0n, "no invented calendar-day history");
  });

  it("keeps an empty committed draw empty while later bets build the next pool", async function () {
    const { game, carol } = await loadFixture(deployFullProtocol);
    const sealed = await requestNextDay(game);
    const before = await winner(game, sealed);
    expect(before[2]).to.equal(0n);
    await bet(game, carol, 1, 6);
    expect(await winner(game, sealed)).to.deep.equal(before);
    expect(await game.getDailyHeroWager(await game.currentDayView_g542950(), 1, 6)).to.equal(UNITS);
  });
});
