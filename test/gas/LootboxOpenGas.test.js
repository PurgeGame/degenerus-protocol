// SPDX-License-Identifier: AGPL-3.0-only
// Current public openBoxes gas witnesses. These replace the never-pinned historical
// entropy-refactor benchmark: no pre/post micro-optimization delta is claimed.
// Real purchases and VRF callbacks create one ordinary box or the maximum 100-box
// order. Each measured receipt is a separate cold transaction, including intrinsic
// gas, with a 10M normal target and an absolute 11.5M owner ceiling. A first-entry
// 100-box overshoot is intentional production behavior and must fit that ceiling.

import { expect } from "chai";
import hre from "hardhat";
import { readFileSync } from "node:fs";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { boCustom, boSmalls, boCount } from "../helpers/boxOrder.js";
import { eth, advanceToNextDay, getLastVRFRequestId, ZERO_BYTES32 } from "../helpers/testUtils.js";

const NORMAL_GAS_TARGET = 10_000_000n;
const AUDIT_GAS_CEILING = 11_500_000n;
const WORD = 266266n;
const MASK48 = (1n << 48n) - 1n;
const layout = JSON.parse(readFileSync(new URL("../../scripts/layout/golden/DegenerusGame.json", import.meta.url), "utf8"));
const root = (name) => {
  const entry = layout.find((item) => item.label === name);
  if (!entry) throw new Error(`Missing verified storage root: ${name}`);
  return BigInt(entry.slot);
};
const slot = (key, base) => hre.ethers.keccak256(hre.ethers.AbiCoder.defaultAbiCoder().encode(
  ["uint256", "uint256"], [key, base],
));
async function read(game, position) {
  return BigInt(await hre.ethers.provider.getStorage(await game.getAddress(), position));
}
async function indexOf(game) { return (await read(game, root("lootboxRngPacked"))) & MASK48; }
async function orderOf(game, index, player) {
  return read(game, slot(BigInt(player), BigInt(slot(index, root("lootboxOrder")))));
}
async function wordOf(game, index) { return read(game, slot(index, root("lootboxRngWordByIndex"))); }

async function readyDailyFixture() {
  const f = await deployFullProtocol();
  await f.mockVRF.fundSubscription(1, eth(100));
  await advanceToNextDay();
  for (let calls = 0; calls < 50 && !(await f.game.rngLocked()); calls++) {
    await f.game.connect(f.deployer).advanceGame();
  }
  expect(await f.game.rngLocked(), "daily request must engage").to.equal(true);
  const request = await getLastVRFRequestId(f.mockVRF);
  expect(request, "fresh real VRF request").to.be.gt(0n);
  await f.mockVRF.fulfillRandomWords(request, 0xB007n);
  for (let calls = 0; calls < 100 && await f.game.rngLocked(); calls++) {
    await f.game.connect(f.deployer).advanceGame();
  }
  expect(await f.game.rngLocked(), "daily work must finish within its bound").to.equal(false);
  await f.game.openBoxes(1000);
  expect(await f.game.level(), "fixed live game level").to.equal(0n);
  expect(await f.game.boxesPending(), "fixture starts with no ready entries").to.equal(false);
  return f;
}

async function purchase(f, player, packed, nominal) {
  // A real ticket purchase supplies the ordinary activity score; no storage seeding.
  await f.game.connect(player).purchase(
    player.address, 400n, packed, ZERO_BYTES32, 0, false, { value: nominal + eth(0.01) },
  );
}

async function prepare(f, buyers, count, singleCustom) {
  const index = await indexOf(f.game);
  for (const buyer of buyers) {
    await purchase(f, buyer, singleCustom ? boCustom(eth(1)) : boSmalls(count), eth(1));
    expect(boCount(await orderOf(f.game, index, buyer.address)), "exact committed box count").to.equal(count);
  }
  expect(await wordOf(f.game, index), "purchases precede revelation").to.equal(0n);
  expect(await f.game.openBoxes.staticCall(1), "unready boxes cannot be consumed").to.equal(0n);
  await f.game.connect(f.deployer).requestLootboxRng();
  const request = await getLastVRFRequestId(f.mockVRF);
  await f.mockVRF.fulfillRandomWords(request, WORD);
  expect(await wordOf(f.game, index), "delivered word is bound to the original index").to.equal(WORD);
  expect(await indexOf(f.game)).to.equal(index + 1n);
  expect(await f.game.boxesPending(), "measured entry is ready").to.equal(true);
  // A later unworded order must survive every measured opening and the final replay probe.
  await purchase(f, f.alice, boSmalls(1), eth(0.01));
  const nextOrder = await orderOf(f.game, index + 1n, f.alice.address);
  expect(boCount(nextOrder)).to.equal(1n);
  return { index, nextOrder };
}

async function measureOpen(f, state, player, count) {
  // One step pays for the genesis afking-ring scan; the second reaches the human entry.
  expect(await f.game.connect(f.carol).openBoxes.staticCall(2, { gasLimit: AUDIT_GAS_CEILING }),
    "the first queued entry must open in full").to.equal(count);
  const receipt = await (await f.game.connect(f.carol).openBoxes(2, { gasLimit: AUDIT_GAS_CEILING })).wait();
  expect(receipt.gasUsed, "owner's hard transaction ceiling").to.be.lte(AUDIT_GAS_CEILING);
  expect(receipt.gasUsed, "normal public-opening witness").to.be.lte(NORMAL_GAS_TARGET);
  expect(await orderOf(f.game, state.index, player.address), "measured order fully consumed").to.equal(0n);
  expect(await orderOf(f.game, state.index + 1n, f.alice.address), "unrevealed next-index order survives").to.equal(state.nextOrder);
  const summaries = [];
  for (const log of receipt.logs) {
    if (log.address.toLowerCase() !== (await f.game.getAddress()).toLowerCase()) continue;
    for (const iface of [f.lootboxModule.interface, f.degeneretteModule.interface]) {
      let parsed;
      try { parsed = iface.parseLog(log); } catch { continue; }
      if (parsed && ["LootBoxOpened", "BoxSpin"].includes(parsed.name)) summaries.push(parsed);
    }
  }
  expect(summaries.length, "every consumed box publishes its actual resolution").to.be.gte(Number(count));
  for (const event of summaries) expect(event.args.player).to.equal(player.address);
  console.log(`      [OPEN-BOXES] boxes=${count} gas=${receipt.gasUsed} hard-headroom=${AUDIT_GAS_CEILING - receipt.gasUsed}`);
  return receipt;
}

describe("LootboxOpenGas — current public opening and maximum-size order", function () {
  this.timeout(600_000);
  after(function () { restoreAddresses(); });

  it("opens one committed ordinary box in a cold transaction below 10M", async function () {
    const f = await loadFixture(readyDailyFixture);
    const state = await prepare(f, [f.alice], 1n, true);
    await measureOpen(f, state, f.alice, 1n);
    expect(await f.game.boxIndexComplete(state.index)).to.equal(true);
    expect(await f.game.openBoxes.staticCall(1000), "no replay and no opening of the later unworded order").to.equal(0n);
    expect(await orderOf(f.game, state.index + 1n, f.alice.address)).to.equal(state.nextOrder);
  });

  it("opens two maximum 100-box orders in separate bounded cold transactions without skipping the second owner", async function () {
    const f = await loadFixture(readyDailyFixture);
    const state = await prepare(f, [f.alice, f.bob], 100n, false);
    const bobOrder = await orderOf(f.game, state.index, f.bob.address);
    const first = await measureOpen(f, state, f.alice, 100n);
    expect(await orderOf(f.game, state.index, f.bob.address), "budget break preserves the next owner").to.equal(bobOrder);
    expect(await f.game.boxIndexComplete(state.index)).to.equal(false);
    const second = await measureOpen(f, state, f.bob, 100n);
    expect(second.blockNumber).to.be.gt(first.blockNumber);
    expect(await f.game.boxIndexComplete(state.index)).to.equal(true);
    expect(await f.game.openBoxes.staticCall(1000), "no duplicate opening").to.equal(0n);
  });
});
