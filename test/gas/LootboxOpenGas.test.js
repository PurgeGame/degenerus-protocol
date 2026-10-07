// SPDX-License-Identifier: AGPL-3.0-only
// Box-opening gas witnesses through mineFlip, the single engine door. These replace the
// never-pinned historical entropy-refactor benchmark: no pre/post micro-optimization delta
// is claimed. Real purchases and VRF callbacks create one ordinary box or the maximum
// 100-box order. Each measured receipt is a separate cold transaction, including intrinsic
// gas. The engine's human-box stage admits whole entries while the call's remaining gas
// covers the next entry's declared bound, so each measured call starts at that stage with
// a realistic 10M allowance (or one sized for exactly one maximum entry) and must open the
// first queued entry in full; the measured receipt is checked against the declared entry
// bound (the per-chunk property).
import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { restoreAddresses } from "../helpers/deployFixture.js";
import { compiledStorageLayout } from "../helpers/storageLayout.js";
import { boCustom, boSmalls, boCount } from "../helpers/boxOrder.js";
import {
  readyDailyFixture, mineAll, requestMiddayRng, MINER_HUMAN_BOXES,
} from "../helpers/readyDailyFixture.js";
import { eth, ZERO_BYTES32 } from "../helpers/testUtils.js";

// Realistic caller allowance for one mineFlip call (owner rule: per-chunk <= 10M).
const OPEN_GAS_ALLOWANCE = 10_000_000n;
// MineFlipGasBounds: HUMAN_ENTRY_GAS, HUMAN_BOX_GAS, HUMAN_TAIL_GAS (one entry's admission bound).
const HUMAN_ENTRY_GAS = 1_300_000n;
const HUMAN_BOX_GAS = 27_500n;
const HUMAN_TAIL_GAS = 80_000n;
// One maximum entry's declared bound is 4.13M; the engine admits the next entry only while
// the remaining allowance covers that bound, so 4.85M admits exactly one 100-box entry and
// the break must leave the next owner whole for its own transaction.
const ONE_MAX_ENTRY_ALLOWANCE = 4_850_000n;
// Intrinsic gas, calldata, Game -> miner -> AFK module dispatch, the empty consumer stages
// after the human orders and the read certificate.
const ENGINE_OVERHEAD_GAS = 100_000n;
const MINER_TICKETS = 4n; // DegenerusGameStorage.MinerAction.Tickets
const TICKET_CHECKPOINT_GAS = 3_000_000;
// Clears the AFKing consumer stage (its genesis ring scan) but cannot admit a human entry
// (declared >= 1.41M plus the engine's worker and return reserves).
const AFKING_STAGE_GAS = 1_300_000;
const WORD = 266266n;
const root = async (name) => {
  const entry = (await compiledStorageLayout()).storage.find((item) => item.label === name);
  if (!entry) throw new Error(`Missing verified storage root: ${name}`);
  return { slot: BigInt(entry.slot), offset: BigInt(entry.offset) };
};
const coder = hre.ethers.AbiCoder.defaultAbiCoder();
const slot = (key, base) => hre.ethers.keccak256(coder.encode(["uint256", "uint256"], [key, base]));
async function read(game, position) {
  return BigInt(await hre.ethers.provider.getStorage(await game.getAddress(), position));
}
async function indexOf(game) { return ((await read(game, 0)) >> 252n) & 1n; }
// Queue entry `position` of write buffer `index`: boxQueue is manually addressed (the array
// length slot is never written), entry p at keccak(keccak(index . boxQueue.slot)) + p.
async function entryAt(game, index, position) {
  const base = BigInt(hre.ethers.keccak256(slot(BigInt(index) & 1n, (await root("boxQueue")).slot)));
  return read(game, base + BigInt(position));
}
// Entries are never marked processed: the sealed read buffer's boxCursor is the only progress.
async function boxCursorOf(game) {
  const r = await root("boxCursor");
  return ((await read(game, r.slot)) >> (r.offset * 8n)) & 0xffffffffffffn;
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
    0, 400n, packed, ZERO_BYTES32, 0, false, { value: nominal + eth(0.01) },
  );
}

async function prepare(f, buyers, count, singleCustom) {
  const index = await indexOf(f.game);
  for (const [position, buyer] of buyers.entries()) {
    await purchase(f, buyer, singleCustom ? boCustom(eth(1)) : boSmalls(count), eth(1));
    expect(boCount(await entryAt(f.game, index, position)), "exact committed box count").to.equal(count);
  }
  expect(await wordOf(f.game, index), "purchases precede revelation").to.equal(0n);
  expect(await f.game.boxesPending(), "unready boxes cannot be consumed").to.equal(false);
  // The pending box ETH clears the mid-day threshold, so mineFlip's request stage is the
  // creditless caller's next action and opens nothing.
  const request = await requestMiddayRng(f.game, f.deployer, f.mockVRF);
  for (const position of buyers.keys()) {
    expect(boCount(await entryAt(f.game, index, position)), "the request opens no box").to.equal(count);
  }
  expect(await boxCursorOf(f.game), "the request opens no box").to.equal(0n);
  await f.mockVRF.fulfillRandomWords(request, WORD);
  // Publication is its own keeper checkpoint and runs outside the measured open. A bounded
  // allowance admits only that checkpoint: an unbounded mineFlip keeps admitting work and
  // would open the boxes itself (the engine spends whatever gas it is given).
  await f.game.mineFlip({ gasLimit: 1_000_000 });
  // The buyers' real tickets were frozen into the read cohort by the mid-day request. Their
  // drain is a keeper-only checkpoint that precedes every box stage; a bounded allowance
  // admits a ticket round but not a 100-box entry (declared ~4.13M), so it stays unopened.
  for (let i = 0; i < 10 && (await f.game.rngConsumerStage()) === 0n; i++) {
    expect(await f.game.nextMinerAction(), "only the ticket checkpoint precedes the boxes").to.equal(MINER_TICKETS);
    await f.game.mineFlip({ gasLimit: TICKET_CHECKPOINT_GAS });
  }
  expect(await f.game.rngConsumerStage(), "box consumers are next").to.be.oneOf([2n, 3n]);
  // The AFKing stage precedes the human orders. A bounded allowance clears it without
  // admitting a human entry, so every measured call starts at the human-box stage.
  for (let i = 0; i < 5 && (await f.game.rngConsumerStage()) === 2n; i++) {
    await f.game.mineFlip({ gasLimit: AFKING_STAGE_GAS });
  }
  expect(await f.game.nextMinerAction(), "measured calls start at the human-box stage").to.equal(MINER_HUMAN_BOXES);
  expect(await boxCursorOf(f.game), "no box opens before the measured call").to.equal(0n);
  expect(await wordOf(f.game, index), "delivered word is bound to the original index").to.equal(WORD);
  expect(await indexOf(f.game)).to.equal(index ^ 1n);
  expect(await f.game.boxesPending(), "measured entry is ready").to.equal(true);
  // A later unworded order must survive every measured opening and the final replay probe.
  await purchase(f, f.alice, boSmalls(1), eth(0.01));
  const nextOrder = await entryAt(f.game, index ^ 1n, 0);
  expect(boCount(nextOrder)).to.equal(1n);
  return { index, nextOrder };
}

function boxResolutions(f, receipts, gameAddress) {
  const summaries = [];
  for (const receipt of receipts) {
    for (const log of receipt.logs) {
      if (log.address.toLowerCase() !== gameAddress) continue;
      for (const iface of [f.lootboxModule.interface, f.degeneretteModule.interface]) {
        let parsed;
        try { parsed = iface.parseLog(log); } catch { continue; }
        if (parsed && ["LootBoxOpened", "BoxSpin"].includes(parsed.name)) summaries.push(parsed);
      }
    }
  }
  return summaries;
}

async function measureOpen(f, state, player, position, count, allowance = OPEN_GAS_ALLOWANCE) {
  expect(await f.game.nextMinerAction(), "the measured call starts at the human-box stage").to.equal(MINER_HUMAN_BOXES);
  const receipt = await (await f.game.connect(f.carol).mineFlip({ gasLimit: allowance })).wait();
  expect(receipt.status, "realistic allowance does not run out of gas").to.equal(1);
  const declared = HUMAN_ENTRY_GAS + count * HUMAN_BOX_GAS + HUMAN_TAIL_GAS;
  // Per-chunk property: the measured entry, with intrinsic gas and engine dispatch, stays
  // inside the declared admission bound the engine reserves for it (and so under 10M).
  expect(receipt.gasUsed, "measured entry fits its declared admission bound").to.be.lte(declared + ENGINE_OVERHEAD_GAS);
  expect(declared, "declared entry bound is a <=10M chunk").to.be.lte(10_000_000n);
  expect(await boxCursorOf(f.game), "the queued entry opens in full").to.equal(BigInt(position) + 1n);
  expect(await entryAt(f.game, state.index ^ 1n, 0), "unrevealed next-index order survives").to.equal(state.nextOrder);
  const summaries = boxResolutions(f, [receipt], (await f.game.getAddress()).toLowerCase());
  expect(summaries.length, "every consumed box publishes its actual resolution").to.be.gte(Number(count));
  for (const event of summaries) expect(event.args.player).to.equal(player.address);
  console.log(`      [OPEN-BOXES] boxes=${count} gas=${receipt.gasUsed} declared-entry-bound=${declared} allowance=${allowance}`);
  return receipt;
}

// Run the engine to rest: no box may open again (no replay, no duplicate) and the later
// unworded order must stay queued.
async function expectNoFurtherOpening(f, state) {
  const receipts = await mineAll(f.game, f.carol);
  const reopened = boxResolutions(f, receipts, (await f.game.getAddress()).toLowerCase());
  expect(reopened.length, "no box opens after its entry resolved").to.equal(0);
  expect(await f.game.boxesPending(), "no ready entry remains").to.equal(false);
  expect(await entryAt(f.game, state.index ^ 1n, 0), "the later unworded order is not opened").to.equal(state.nextOrder);
}

describe("LootboxOpenGas — mineFlip box opening and maximum-size order", function () {
  this.timeout(600_000);
  after(function () { restoreAddresses(); });

  it("opens one committed ordinary box in a cold transaction below 10M", async function () {
    const f = await loadFixture(readyDailyFixture);
    const state = await prepare(f, [f.alice], 1n, true);
    await measureOpen(f, state, f.alice, 0, 1n);
    expect(await f.game.boxIndexComplete(state.index)).to.equal(true);
    await expectNoFurtherOpening(f, state);
  });

  it("opens two maximum 100-box orders in separate bounded cold transactions without skipping the second owner", async function () {
    const f = await loadFixture(readyDailyFixture);
    const state = await prepare(f, [f.alice, f.bob], 100n, false);
    const first = await measureOpen(f, state, f.alice, 0, 100n, ONE_MAX_ENTRY_ALLOWANCE);
    expect(await boxCursorOf(f.game), "budget break leaves the next owner's entry unopened").to.equal(1n);
    expect(await f.game.boxIndexComplete(state.index)).to.equal(false);
    const second = await measureOpen(f, state, f.bob, 1, 100n, ONE_MAX_ENTRY_ALLOWANCE);
    expect(second.blockNumber).to.be.gt(first.blockNumber);
    expect(await f.game.boxIndexComplete(state.index)).to.equal(true);
    await expectNoFurtherOpening(f, state);
  });
});
