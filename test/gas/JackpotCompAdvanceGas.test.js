// Current level-one purchase-day gas witness through real Game -> JackpotModule ->
// CrapsBattle/JackpotBattle wiring. A request freezes Added and the field; bounded
// award/settlement checkpoints finish before the separate 50-share trait draw.
// One mineFlip now composes several checkpoints, so the owner's gas property is per chunk:
// every call carries a realistic 10M allowance and must succeed (zero-progress calls revert),
// which bounds every admitted chunk by 10M (test/helpers/mineFlipChunks.js). Ordering between
// the RNG application, the battle and the trait draw is asserted on log position, not on
// transaction boundaries.
// These fixtures cover awarded-only fields and default boards, not paid/high seats
// or an exhaustive maximum over RNG words. Exact awards, settled seat ownership,
// actual FLIP credits, zero pass balances, and day completion are mandatory witnesses.

import { expect } from "chai";
import hre from "hardhat";
import { readFileSync } from "node:fs";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { advanceToNextDay, getLastVRFRequestId } from "../helpers/testUtils.js";
import { REALISTIC_ALLOWANCE, mine } from "../helpers/mineFlipChunks.js";

const { ethers } = hre;

const WORD = BigInt(ethers.keccak256(ethers.toUtf8Bytes("comp-advance-gas-word")));
const TRAIT_BOARD_TAG = ethers.keccak256(ethers.toUtf8Bytes("degenerus.jackpot.trait-board"));
const FLIP_WIN_TOPIC = ethers.id("JackpotFlipWin(uint32,uint24,uint8,uint256,uint256)");
const BATTLE_ENTRY_TOPIC = ethers.id("JackpotBattleEntry(uint64,uint256,uint32,uint256,uint32)");
const SETTLED_TOPIC = ethers.id("CrapsBetSettled(uint256,uint32,uint256,uint256)");
const POT_TOPIC = ethers.id("CrapsBattlePaid(uint256,bytes32,uint32,uint256)");
const PASS_TOPIC = ethers.id("CrapsPassesCredited(uint32,bool,uint256)");
// 5214f7498 added the hottest-shooter award: 10% of a scheduled main pot, paid as liquid FLIP.
const HOTTEST_TOPIC = ethers.id("CrapsHottestShooterPaid(uint256,bytes32,uint32,uint16,uint256)");
const RNG_APPLIED_TOPIC = ethers.id("DailyRngApplied(uint24,uint256,uint256,uint256)");

const SHARES = 50; // COIN_DRAW_SHARES
const FF_BIT = 1n << 22n;
const VAULT_DEITY_SYMBOL = 0n;
const SDGNRS_DEITY_SYMBOL = 6n;
const TRAIT_HOLDERS = 2000; // per level-1 trait bucket: ~12 pulls each, repeats rare
const FF_HOLDERS = 20; // per unminted level; fresh wallet families separate from trait winners

// Storage roots come from the checked-in layout oracle, which the layout gate verifies
// against production. Reading it avoids forge's incremental artifact cache during a Hardhat run.
const gameLayout = JSON.parse(readFileSync(new URL("../../scripts/layout/golden/DegenerusGame.json", import.meta.url), "utf8"));
function storageRootOf(varName) {
  const entry = gameLayout.find((s) => s.label === varName);
  if (!entry) throw new Error(`${varName} not found in DegenerusGame layout`);
  return BigInt(entry.slot);
}

const pad32 = (v) => ethers.toBeHex(v, 32);
const mapSlot = (key, root) => BigInt(ethers.keccak256(ethers.concat([pad32(key), pad32(root)])));
const arrayData = (lengthSlot) => BigInt(ethers.keccak256(pad32(lengthSlot)));
const hash2 = (a, b) => BigInt(ethers.keccak256(ethers.concat([pad32(a), pad32(b)])));

async function setSlot(addr, slot, value) {
  await hre.network.provider.send("hardhat_setStorageAt", [addr, pad32(slot), pad32(value)]);
}
async function getSlot(addr, slot) {
  return BigInt(await ethers.provider.getStorage(addr, pad32(slot)));
}

// Register wallets in the `wallets` table and return their wallet IDs (the lanes of queues and
// trait buckets). Ordinary address registration is stored separately in walletIds.
async function registerOwners(addr, ownerRoot, lvl, holders) {
  const data = arrayData(ownerRoot);
  const idRoot = storageRootOf("walletIds");
  let count = await getSlot(addr, ownerRoot);
  const ids = [];
  for (const h of holders) {
    const idSlot = mapSlot(BigInt(h), idRoot);
    let id = (await getSlot(addr, idSlot)) & 0xffffffffn;
    if (id === 0n) {
      id = count++;
      await setSlot(addr, data + id, BigInt(h));
      await setSlot(addr, idSlot, id);
    }
    ids.push(id);
  }
  await setSlot(addr, ownerRoot, count);
  return ids;
}

// Replace a packed uint32-lane array (length slot `lenSlot`) with `lanes`.
async function writeLanes(addr, lenSlot, lanes, level = 0n) {
  await setSlot(addr, lenSlot, BigInt(lanes.length) | (level << 232n));
  const base = arrayData(lenSlot);
  for (let w = 0; w * 8 < lanes.length; ++w) {
    let word = 0n;
    for (let j = 0; j < 8 && w * 8 + j < lanes.length; ++j) word |= lanes[w * 8 + j] << BigInt(32 * j);
    await setSlot(addr, base + BigInt(w), word);
  }
}

const holder = (n) => ethers.getAddress("0x" + n.toString(16).padStart(40, "0"));

// JS mirror of JackpotBucketLib.getRandomTraits (hashes the word with TRAIT_BOARD_TAG first).
function traitsOf(entropy) {
  const r = hash2(entropy, BigInt(TRAIT_BOARD_TAG));
  return [
    Number(r & 0x3fn),
    64 + Number((r >> 6n) & 0x3fn),
    128 + Number((r >> 12n) & 0x3fn),
    192 + Number((r >> 18n) & 0x3fn),
  ];
}

async function measureLevelOneAdvance(prevPoolEth, expectedAwards) {
  const fixture = await loadFixture(deployFullProtocol);
  const { game, deployer, mockVRF, alice, coinflip } = fixture;
  const gameAddr = await game.getAddress();
  const crapsAddr = fixture.predicted.get("CRAPS");
  const battle = await ethers.getContractAt("JackpotBattle", crapsAddr);
  const poolRoot = storageRootOf("levelPrizePool");
  const bucketRoot = storageRootOf("lvlTraitEntry");
  const ownerRoot = storageRootOf("wallets");
  const queueRoot = storageRootOf("ticketQueue");
  const deityRoot = storageRootOf("deityBySymbol");
  const crapsLayout = JSON.parse(readFileSync(new URL("../../scripts/layout/golden/CrapsBattle.json", import.meta.url), "utf8"));
  const passRoot = BigInt(crapsLayout.find((entry) => entry.label === "_passCreditsById").slot);
  const betRoot = BigInt(crapsLayout.find((entry) => entry.label === "_bets").slot);
  const traitOwners = new Set();
  const ownerOfId = new Map();
  const idOfOwner = new Map();
  const registerFixtureOwners = async (lvl, owners) => {
    const ids = await registerOwners(gameAddr, ownerRoot, lvl, owners);
    ids.forEach((id, i) => { ownerOfId.set(id, owners[i].toLowerCase()); idOfOwner.set(owners[i].toLowerCase(), id); });
    return ids;
  };
  const fieldOwners = new Set();

  await setSlot(gameAddr, mapSlot(VAULT_DEITY_SYMBOL, deityRoot), 0n);
  await setSlot(gameAddr, mapSlot(SDGNRS_DEITY_SYMBOL, deityRoot), 0n);
  await setSlot(gameAddr, 5n, (await getSlot(gameAddr, 5n)) | (1n << 104n));
  const traitLiveSlot = storageRootOf("traitBucketLive") + 1n;
  let traitLive = await getSlot(gameAddr, traitLiveSlot);
  for (const t of traitsOf(WORD)) {
    const owners = Array.from({ length: TRAIT_HOLDERS }, (_, i) => holder(0xace000000n + BigInt(t) * 0x10000n + BigInt(i + 1)));
    owners.forEach((owner) => traitOwners.add(owner.toLowerCase()));
    const positions = await registerFixtureOwners(1n, owners);
    await writeLanes(gameAddr, mapSlot(1n, bucketRoot) + BigInt(t), positions, 1n);
    traitLive |= 1n << BigInt(t);
  }
  await setSlot(gameAddr, traitLiveSlot, traitLive);
  for (let lvl = 2n; lvl <= 100n; ++lvl) {
    const owners = Array.from({ length: FF_HOLDERS }, (_, i) => holder(0xb00000000n + lvl * 0x100n + BigInt(i + 1)));
    owners.forEach((owner) => fieldOwners.add(owner.toLowerCase()));
    await writeLanes(gameAddr, mapSlot(lvl | FF_BIT, queueRoot), await registerFixtureOwners(lvl, owners));
    // Queue header: owner count in bits 0..31, occupying level tag in bits 32..55.
    await setSlot(gameAddr, mapSlot(lvl | FF_BIT, queueRoot), BigInt(FF_HOLDERS) | (lvl << 32n));
  }
  const recordedPool = ethers.parseEther(prevPoolEth);
  await setSlot(gameAddr, mapSlot(0n, poolRoot), recordedPool);
  await (await game.connect(alice).purchase(0, 200n, 0n, ethers.ZeroHash, 0, false, {
    value: ethers.parseEther("2"),
  })).wait();
  await advanceToNextDay();

  const receipts = [];
  // Setup to the real request at a realistic 10M allowance (success implies progress).
  const advance = async () => {
    const { receipt } = await mine(game, deployer);
    receipts.push(receipt);
    return receipt;
  };
  const oldRequest = await getLastVRFRequestId(mockVRF);
  for (let step = 0; step < 30 && !(await game.rngLocked()); ++step) await advance();
  expect(await game.rngLocked(), "bounded setup must reach a real request").to.equal(true);
  const requestId = await getLastVRFRequestId(mockVRF);
  expect(requestId).to.be.gt(oldRequest);
  const requestDay = await game.currentDayView();
  const locked = await battle.jackpotProgress();
  const baseline = recordedPool * 1000n / (ethers.parseEther("0.01") * 200n);
  const price = await battle.jackpotEntryPriceOf(locked.slot);
  const expectedAdded = baseline * price / 8000n;
  expect(locked.added).to.equal(expectedAdded);
  expect(locked.started).to.equal(false);
  expect(Number(baseline / 10000n)).to.equal(expectedAwards);
  await (await mockVRF.fulfillRandomWords(requestId, WORD)).wait();

  // Stop on the actual day seal; never hide a fulfillment failure or call a completed day.
  // Every call carries a realistic 10M allowance. A chunk is admitted only when its declared
  // bound fits the remaining allowance and must finish inside it, and a chunk that cannot
  // fit leaves the next call unable to progress (InsufficientExecutionGas), so a day that
  // seals through successful 10M calls proves every one of its chunks costs <= 10M.
  const firstDayCall = receipts.length;
  for (let step = 0; step < 100 && await game.rngLocked(); ++step) await advance();
  expect(await game.rngLocked(), "bounded advance chain must seal the day").to.equal(false);
  const dayReceipts = receipts.slice(firstDayCall);
  expect(await game.rngWordForDay(requestDay)).to.equal(WORD);
  const progress = await battle.jackpotProgress();
  expect(progress.started).to.equal(true);
  expect(progress.complete, "all actual battle work must finish").to.equal(true);
  const final = await battle.jackpotBattleOf(progress.slot);
  expect(final.round.paidCount, "this witness is explicitly an awarded-only field").to.equal(0n);
  expect(final.round.awardTarget).to.equal(BigInt(expectedAwards));
  expect(final.round.drawnUnits).to.equal(BigInt(expectedAwards));
  expect(final.round.drawnCount).to.equal(BigInt(expectedAwards));
  expect(final.cursor).to.equal(BigInt(expectedAwards));

  const coder = ethers.AbiCoder.defaultAbiCoder();
  // Event topics carry wallet IDs; the fixture registered every owner, so IDs map back to addresses.
  const addressTopic = (topic) => {
    const owner = ownerOfId.get(BigInt(topic));
    if (owner === undefined) throw new Error(`unregistered wallet id ${BigInt(topic)}`);
    return owner;
  };
  const entries = new Map();
  const settled = new Set();
  const credits = new Map();
  const passes = new Map();
  const traitReceipts = [];
  const battleReceipts = [];
  // Log positions (block, index) order the work across checkpoints and transactions.
  const position = (l) => BigInt(l.blockNumber) * 1_000_000n + BigInt(l.index);
  const appliedPositions = [];
  const battlePositions = [];
  const traitPositions = [];
  let traitShares = 0;
  let traitTotal = 0n;
  let battlePaid = 0n;
  let pots = 0;
  let hottest = 0;
  const addCredit = (owner, amount) => credits.set(owner, (credits.get(owner) ?? 0n) + amount);
  const expectedShare = recordedPool * 1000n / (ethers.parseEther("0.01") * 400n) / 50n;
  for (const r of receipts) {
    const traitLogs = r.logs.filter((l) => l.address.toLowerCase() === gameAddr.toLowerCase() && l.topics[0] === FLIP_WIN_TOPIC);
    const battleLogs = r.logs.filter((l) => l.address.toLowerCase() === crapsAddr.toLowerCase()
      && [BATTLE_ENTRY_TOPIC, SETTLED_TOPIC, POT_TOPIC, HOTTEST_TOPIC, PASS_TOPIC].includes(l.topics[0]));
    if (traitLogs.length) traitReceipts.push(r);
    if (battleLogs.length) battleReceipts.push(r);
    for (const l of r.logs) if (l.topics[0] === RNG_APPLIED_TOPIC) appliedPositions.push(position(l));
    for (const l of battleLogs) battlePositions.push(position(l));
    for (const l of traitLogs) traitPositions.push(position(l));
    for (const l of traitLogs) {
      const owner = addressTopic(l.topics[1]);
      const [amount, index] = coder.decode(["uint256", "uint256"], l.data);
      const trait = BigInt(l.topics[3]);
      expect(BigInt(l.topics[2])).to.equal(1n);
      expect(index).to.be.lt(BigInt(TRAIT_HOLDERS));
      expect(owner, "trait entry index must resolve to its actual registered owner")
        .to.equal(holder(0xace000000n + trait * 0x10000n + index + 1n).toLowerCase());
      expect(traitOwners.has(owner), "trait credit recipient must be a correctly encoded seeded owner").to.equal(true);
      expect(amount).to.equal(expectedShare);
      addCredit(owner, amount); traitTotal += amount; ++traitShares;
    }
    for (const l of battleLogs) {
      if (l.topics[0] === BATTLE_ENTRY_TOPIC) {
        expect(BigInt(l.topics[1])).to.equal(progress.slot);
        const id = l.topics[2]; const owner = addressTopic(l.topics[3]);
        expect(fieldOwners.has(owner), "awarded seat must belong to the seeded future cohort").to.equal(true);
        expect(entries.has(id), "no duplicate seat ids").to.equal(false);
        expect(coder.decode(["uint256", "uint32"], l.data)[0]).to.equal(1n);
        entries.set(id, owner);
      } else if (l.topics[0] === SETTLED_TOPIC) {
        const id = l.topics[1]; const owner = addressTopic(l.topics[2]);
        expect(entries.get(id), "settlement keeps the awarded owner").to.equal(owner);
        expect(settled.has(id), "each seat settles once").to.equal(false); settled.add(id);
        const paid = coder.decode(["uint256", "uint256"], l.data)[1];
        addCredit(owner, paid); battlePaid += paid;
      } else if (l.topics[0] === HOTTEST_TOPIC) {
        expect(BigInt(l.topics[2])).to.equal(progress.slot);
        const owner = addressTopic(l.topics[3]);
        expect(entries.get(l.topics[1]), "hottest-shooter award belongs to an actual awarded seat").to.equal(owner);
        const paid = coder.decode(["uint16", "uint256"], l.data)[1];
        addCredit(owner, paid); battlePaid += paid; ++hottest;
      } else if (l.topics[0] === POT_TOPIC) {
        expect(BigInt(l.topics[2])).to.equal(progress.slot);
        const owner = addressTopic(l.topics[3]);
        expect(entries.get(l.topics[1]), "pot belongs to an actual awarded seat").to.equal(owner);
        const paid = coder.decode(["uint256"], l.data)[0];
        addCredit(owner, paid); battlePaid += paid; ++pots;
      } else {
        const owner = addressTopic(l.topics[1]);
        expect(fieldOwners.has(owner)).to.equal(true);
        const [high, count] = coder.decode(["bool", "uint256"], l.data);
        const prior = passes.get(owner) ?? [0n, 0n]; prior[high ? 1 : 0] += count; passes.set(owner, prior);
      }
    }
  }
  expect(traitReceipts.length).to.equal(1);
  expect(traitShares, "the real trait draw must pay all fifty shares").to.equal(SHARES);
  expect(entries.size, "exact current awarded field must be built").to.equal(expectedAwards);
  expect(settled.size, "every awarded seat must really settle").to.equal(expectedAwards);
  expect(pots, "nonzero pot must pay once").to.equal(1);
  expect(hottest, "the longest shared hand's shooter is paid once from the nonzero main pot").to.equal(1);
  expect(battlePaid).to.be.gt(0n);
  expect(passes.size, "this fixed jackpot field pays liquid FLIP without pass awards").to.equal(0);
  expect(new Set(entries.values()).size, "fixture must retain a substantial fresh-owner field").to.be.gte(Math.floor(expectedAwards * 0.8));
  // A call may now compose the RNG application, battle checkpoints and the trait draw, so
  // separation is proven by order: the battle runs only after the daily word is applied
  // and finishes entirely before the separate trait draw begins.
  expect(appliedPositions.length, "the daily word is applied exactly once").to.equal(1);
  const firstTrait = traitPositions.reduce((m, x) => (x < m ? x : m), traitPositions[0]);
  expect(battlePositions.every((x) => x > appliedPositions[0]), "battle cannot run ahead of the RNG application").to.equal(true);
  expect(battlePositions.every((x) => x < firstTrait), "the entire battle must finish before the trait draw").to.equal(true);
  // These wallet families were freshly seeded only in the Game registry. They had no prior
  // Coinflip/pass balance. Reconcile all published run/pot/share payments to actual ownership.
  for (const [id, owner] of entries) {
    // Scheduled slips recycle their day and pack three 72-bit seats into each word.
    // Authenticate the full day before selecting the seat's 32-bit owner lane.
    const slot = BigInt(id) >> 64n;
    const seat = BigInt(id) & ((1n << 64n) - 1n);
    expect(seat).to.be.gt(0n);
    const key = ((slot & 511n) << 64n) | (1n + (seat - 1n) / 3n);
    const packed = await getSlot(crapsAddr, mapSlot(key, betRoot));
    expect((packed >> 216n) & 0xffffffn, "settled seat belongs to the expected day").to.equal(slot >> 3n);
    const ownerId = (packed >> (((seat - 1n) % 3n) * 72n)) & 0xffffffffn;
    expect(ownerId, "settled seat retains its actual awarded owner id").to.equal(idOfOwner.get(owner));
  }
  for (const [owner, expected] of credits) expect(await coinflip.coinflipAmount(owner), `actual stake for ${owner}`).to.equal(expected);
  for (const owner of new Set(entries.values())) {
    const packed = await getSlot(crapsAddr, mapSlot(idOfOwner.get(owner), passRoot));
    expect(packed & 0xffffffffn, `normal passes for ${owner}`).to.equal(0n);
    expect((packed >> 32n) & 0xffffffffn, `high passes for ${owner}`).to.equal(0n);
  }
  return {
    dayCalls: dayReceipts.length,
    gas: receipts.reduce((max, r) => r.gasUsed > max ? r.gasUsed : max, 0n),
    traitGas: traitReceipts[0].gasUsed,
    battleGas: battleReceipts.reduce((max, r) => r.gasUsed > max ? r.gasUsed : max, 0n),
    transactions: receipts.length, battleTransactions: battleReceipts.length,
    traitShares, traitTotal, awards: entries.size, settled: settled.size,
    distinctBattleOwners: new Set(entries.values()).size, battlePaid,
  };
}

function report(label, t) {
  console.log(`      [COIN-ADV ${label}] ${JSON.stringify(t, (_, value) => typeof value === "bigint" ? value.toString() : value)}`);
  console.log(`      [COIN-ADV-GAS ${label}] heaviest ${REALISTIC_ALLOWANCE}-allowance call=${t.gas}; day sealed in ${t.dayCalls} calls (battle in ${t.battleTransactions})`);
}

describe("JackpotCoinAdvanceGas — current staged battle and separate level-one trait draw", function () {
  this.timeout(300_000);
  after(function () { restoreAddresses(); });
  for (const [pool, awards] of [["520", 26], ["5000", 250], ["10000", 500]]) {
    it(`fully settles ${awards} awarded seats and 50 trait shares in <=10M chunks (${pool} ETH recorded pool)`, async function () {
      report(`${pool} ETH / ${awards} awards`, await measureLevelOneAdvance(pool, awards));
    });
  }
});
