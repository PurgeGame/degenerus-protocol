// SPDX-License-Identifier: AGPL-3.0-only
// Current public openBoxes gas witnesses. These replace the never-pinned historical
// entropy-refactor benchmark: no pre/post micro-optimization delta is claimed.
// Real purchases and VRF callbacks create one ordinary box or the maximum 100-box
// order. Each measured receipt is a separate cold transaction, including intrinsic
// gas. openBoxes is a caller-sized in-order door that admits whole entries while the
// supplied gas covers the next entry's declared bound, so the witness supplies a
// realistic 10M allowance and requires the first queued entry (the indivisible chunk)
// to open in full; the measured receipt is checked against the declared entry bound.
import { expect } from "chai";
import hre from "hardhat";
import { readFileSync } from "node:fs";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { restoreAddresses } from "../helpers/deployFixture.js";
import { boCustom, boSmalls, boCount } from "../helpers/boxOrder.js";
import { readyDailyFixture } from "../helpers/readyDailyFixture.js";
import { eth, getLastVRFRequestId, ZERO_BYTES32 } from "../helpers/testUtils.js";

// Realistic caller allowance for the player-facing door (owner rule: per-chunk <= 10M).
const OPEN_GAS_ALLOWANCE = 10_000_000n;
// MineFlipGasBounds: HUMAN_ENTRY_GAS, HUMAN_BOX_GAS, HUMAN_TAIL_GAS (one entry's admission bound).
const HUMAN_ENTRY_GAS = 550_000n;
const HUMAN_BOX_GAS = 70_000n;
const HUMAN_TAIL_GAS = 250_000n;
// One maximum entry's declared bound is 7.8M; the door admits the next entry only while the
// remaining allowance covers that bound, so 8.5M admits exactly one 100-box entry and the
// break must leave the next owner whole for its own transaction.
const ONE_MAX_ENTRY_ALLOWANCE = 8_500_000n;
// Intrinsic gas, calldata, Game -> AFK module dispatch and the empty AFK-stage probe.
const DOOR_OVERHEAD_GAS = 100_000n;
const MINER_TICKETS = 4n; // DegenerusGameStorage.MinerAction.Tickets
const TICKET_CHECKPOINT_GAS = 3_000_000;
const WORD = 266266n;
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
async function indexOf(game) { return ((await read(game, 0)) >> 252n) & 1n; }
async function orderOf(game, index, player) {
  const word = await read(game, slot(BigInt(player), BigInt(slot(index & 1n, root("lootboxOrder")))));
  return word & (1n << 255n) ? 0n : word;
}
async function wordOf(game, index) {
  const flags = await read(game, 0);
  const readBuffer = ((flags >> 252n) & 1n) ^ 1n;
  if (readBuffer !== BigInt(index) || (flags & (1n << 255n)) === 0n) return 0n;
  const stored = await read(game, 3);
  return stored === 1n ? 0n : stored;
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
  // Publication is its own keeper checkpoint and runs outside the measured open. A bounded
  // allowance admits only that checkpoint: an unbounded mineFlip keeps admitting work and
  // would open the boxes itself (the engine spends whatever gas it is given).
  await f.game.mineFlip({ gasLimit: 1_000_000 });
  // The buyers' real tickets were frozen into the read cohort by the mid-day request. Their
  // drain is a keeper-only checkpoint that precedes every box stage; a bounded allowance
  // admits a ticket round but not a 100-box entry (declared ~7.8M), so it stays unopened.
  for (let i = 0; i < 10 && (await f.game.rngConsumerStage()) === 0n; i++) {
    expect(await f.game.nextMinerAction(), "only the ticket checkpoint precedes the boxes").to.equal(MINER_TICKETS);
    await f.game.mineFlip({ gasLimit: TICKET_CHECKPOINT_GAS });
  }
  expect(await f.game.rngConsumerStage(), "box consumers are next").to.be.oneOf([2n, 3n]);
  expect(await wordOf(f.game, index), "delivered word is bound to the original index").to.equal(WORD);
  expect(await indexOf(f.game)).to.equal(index ^ 1n);
  expect(await f.game.boxesPending(), "measured entry is ready").to.equal(true);
  // A later unworded order must survive every measured opening and the final replay probe.
  await purchase(f, f.alice, boSmalls(1), eth(0.01));
  const nextOrder = await orderOf(f.game, index ^ 1n, f.alice.address);
  expect(boCount(nextOrder)).to.equal(1n);
  return { index, nextOrder };
}

async function measureOpen(f, state, player, count, allowance = OPEN_GAS_ALLOWANCE) {
  // One step pays for the genesis afking-ring scan; the second reaches the human entry.
  expect(await f.game.connect(f.carol).openBoxes.staticCall(2, { gasLimit: allowance }),
    "the first queued entry must open in full under a realistic allowance").to.equal(count);
  const receipt = await (await f.game.connect(f.carol).openBoxes(2, { gasLimit: allowance })).wait();
  expect(receipt.status, "realistic allowance does not run out of gas").to.equal(1);
  const declared = HUMAN_ENTRY_GAS + count * HUMAN_BOX_GAS + HUMAN_TAIL_GAS;
  // Per-chunk property: the measured entry, with intrinsic gas and door dispatch, stays
  // inside the declared admission bound the engine reserves for it (and so under 10M).
  expect(receipt.gasUsed, "measured entry fits its declared admission bound").to.be.lte(declared + DOOR_OVERHEAD_GAS);
  expect(declared, "declared entry bound is a <=10M chunk").to.be.lte(10_000_000n);
  expect(await orderOf(f.game, state.index, player.address), "measured order fully consumed").to.equal(0n);
  expect(await orderOf(f.game, state.index ^ 1n, f.alice.address), "unrevealed next-index order survives").to.equal(state.nextOrder);
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
  console.log(`      [OPEN-BOXES] boxes=${count} gas=${receipt.gasUsed} declared-entry-bound=${declared} allowance=${allowance}`);
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
    expect(await orderOf(f.game, state.index ^ 1n, f.alice.address)).to.equal(state.nextOrder);
  });

  it("opens two maximum 100-box orders in separate bounded cold transactions without skipping the second owner", async function () {
    const f = await loadFixture(readyDailyFixture);
    const state = await prepare(f, [f.alice, f.bob], 100n, false);
    const bobOrder = await orderOf(f.game, state.index, f.bob.address);
    const first = await measureOpen(f, state, f.alice, 100n, ONE_MAX_ENTRY_ALLOWANCE);
    expect(await orderOf(f.game, state.index, f.bob.address), "budget break preserves the next owner").to.equal(bobOrder);
    expect(await f.game.boxIndexComplete(state.index)).to.equal(false);
    const second = await measureOpen(f, state, f.bob, 100n, ONE_MAX_ENTRY_ALLOWANCE);
    expect(second.blockNumber).to.be.gt(first.blockNumber);
    expect(await f.game.boxIndexComplete(state.index)).to.equal(true);
    expect(await f.game.openBoxes.staticCall(1000), "no duplicate opening").to.equal(0n);
  });
});
