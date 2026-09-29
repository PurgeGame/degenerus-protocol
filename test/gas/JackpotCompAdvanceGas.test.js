// Current level-one purchase-day gas witness through real Game -> JackpotModule ->
// CrapsBattle/JackpotBattle wiring. A request freezes Added and the field; bounded
// award/settlement transactions finish before the separate 50-share trait draw.
// Every advance is a separate cold transaction under the owner's 11.5M hard ceiling.
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

const { ethers } = hre;

const WORD = BigInt(ethers.keccak256(ethers.toUtf8Bytes("comp-advance-gas-word")));
const TRAIT_BOARD_TAG = ethers.keccak256(ethers.toUtf8Bytes("degenerus.jackpot.trait-board"));
const FLIP_WIN_TOPIC = ethers.id("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
const BATTLE_ENTRY_TOPIC = ethers.id("JackpotBattleEntry(uint64,uint256,address,uint256,uint32)");
const SETTLED_TOPIC = ethers.id("CrapsBetSettled(uint256,address,uint256,uint256)");
const POT_TOPIC = ethers.id("CrapsBattlePaid(uint256,bytes32,address,uint256)");
const PASS_TOPIC = ethers.id("CrapsPassesCredited(address,bool,uint256)");
const RNG_APPLIED_TOPIC = ethers.id("DailyRngApplied(uint24,uint256,uint256,uint256)");

const AUDIT_GAS_CEILING = 11_500_000n;
const SOFT_TARGET = 10_000_000n;
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

// Append owners and return FF queue positions: registry index PLUS ONE.
// Trait occurrence lanes instead store raw registry indices (subtract one at that call site).
// The dummy prefix is excluded from every seeded lane.
async function registerOwners(addr, ownerRoot, lvl, holders) {
  const lenSlot = mapSlot(lvl, ownerRoot);
  const data = arrayData(lenSlot);
  let count = await getSlot(addr, lenSlot);
  if (count === 0n) {
    await setSlot(addr, data, 1n);
    count = 1n;
  }
  const positions = [];
  for (const h of holders) {
    await setSlot(addr, data + count, BigInt(h));
    positions.push(count + 1n);
    count += 1n;
  }
  await setSlot(addr, lenSlot, count);
  return positions;
}

// Replace a packed uint32-lane array (length slot `lenSlot`) with `lanes`.
async function writeLanes(addr, lenSlot, lanes) {
  await setSlot(addr, lenSlot, BigInt(lanes.length));
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
  const ownerRoot = storageRootOf("lvlEntryOwner");
  const queueRoot = storageRootOf("ticketQueue");
  const deityRoot = storageRootOf("deityBySymbol");
  const crapsLayout = JSON.parse(readFileSync(new URL("../../scripts/layout/golden/CrapsBattle.json", import.meta.url), "utf8"));
  const passRoot = BigInt(crapsLayout.find((entry) => entry.label === "_passCredits").slot);
  const betRoot = BigInt(crapsLayout.find((entry) => entry.label === "_bets").slot);
  const traitOwners = new Set();
  const fieldOwners = new Set();

  await setSlot(gameAddr, mapSlot(VAULT_DEITY_SYMBOL, deityRoot), 0n);
  await setSlot(gameAddr, mapSlot(SDGNRS_DEITY_SYMBOL, deityRoot), 0n);
  for (const t of traitsOf(WORD)) {
    const owners = Array.from({ length: TRAIT_HOLDERS }, (_, i) => holder(0xace000000n + BigInt(t) * 0x10000n + BigInt(i + 1)));
    owners.forEach((owner) => traitOwners.add(owner.toLowerCase()));
    const positions = await registerOwners(gameAddr, ownerRoot, 1n, owners);
    await writeLanes(gameAddr, mapSlot(1n, bucketRoot) + BigInt(t), positions.map((pos) => pos - 1n));
  }
  for (let lvl = 2n; lvl <= 100n; ++lvl) {
    const owners = Array.from({ length: FF_HOLDERS }, (_, i) => holder(0xb00000000n + lvl * 0x100n + BigInt(i + 1)));
    owners.forEach((owner) => fieldOwners.add(owner.toLowerCase()));
    await writeLanes(gameAddr, mapSlot(lvl | FF_BIT, queueRoot), await registerOwners(gameAddr, ownerRoot, lvl, owners));
  }
  const recordedPool = ethers.parseEther(prevPoolEth);
  await setSlot(gameAddr, mapSlot(0n, poolRoot), recordedPool);
  await (await game.connect(alice).purchase(ethers.ZeroAddress, 200n, 0n, ethers.ZeroHash, 0, false, {
    value: ethers.parseEther("2"),
  })).wait();
  await advanceToNextDay();

  const receipts = [];
  const advance = async () => {
    const r = await (await game.connect(deployer).advanceGame({ gasLimit: AUDIT_GAS_CEILING })).wait();
    expect(r.gasUsed < AUDIT_GAS_CEILING, "every real advance must fit the 11.5M hard cap").to.equal(true);
    receipts.push(r);
    return r;
  };
  const oldRequest = await getLastVRFRequestId(mockVRF);
  for (let step = 0; step < 30 && !(await game.rngLocked()); ++step) await advance();
  expect(await game.rngLocked(), "bounded setup must reach a real request").to.equal(true);
  const requestId = await getLastVRFRequestId(mockVRF);
  expect(requestId).to.be.gt(oldRequest);
  const requestDay = await game.currentDayView();
  const locked = await battle.jackpotProgress();
  const expectedAdded = recordedPool * ethers.parseEther("1000") / (ethers.parseEther("0.01") * 200n);
  expect(locked.added).to.equal(expectedAdded);
  expect(locked.started).to.equal(false);
  expect(Number(expectedAdded / ethers.parseEther("10000"))).to.equal(expectedAwards);
  await (await mockVRF.fulfillRandomWords(requestId, WORD)).wait();

  // Stop on the actual day seal; never hide a fulfillment failure or call a completed day.
  for (let step = 0; step < 100 && await game.rngLocked(); ++step) await advance();
  expect(await game.rngLocked(), "bounded advance chain must seal the day").to.equal(false);
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
  const addressTopic = (topic) => ethers.getAddress(ethers.dataSlice(topic, 12)).toLowerCase();
  const entries = new Map();
  const settled = new Set();
  const credits = new Map();
  const passes = new Map();
  const traitReceipts = [];
  const battleReceipts = [];
  let traitShares = 0;
  let traitTotal = 0n;
  let battlePaid = 0n;
  let pots = 0;
  const addCredit = (owner, amount) => credits.set(owner, (credits.get(owner) ?? 0n) + amount);
  const expectedShare = recordedPool * ethers.parseEther("1000") / (ethers.parseEther("0.01") * 400n) / 50n;
  for (const r of receipts) {
    const traitLogs = r.logs.filter((l) => l.address.toLowerCase() === gameAddr.toLowerCase() && l.topics[0] === FLIP_WIN_TOPIC);
    const battleLogs = r.logs.filter((l) => l.address.toLowerCase() === crapsAddr.toLowerCase()
      && [BATTLE_ENTRY_TOPIC, SETTLED_TOPIC, POT_TOPIC, PASS_TOPIC].includes(l.topics[0]));
    if (traitLogs.length) traitReceipts.push(r);
    if (battleLogs.length) battleReceipts.push(r);
    expect(traitLogs.length === 0 || battleLogs.length === 0, "battle and trait work must use separate transactions").to.equal(true);
    if (battleLogs.length) expect(r.logs.some((l) => l.topics[0] === RNG_APPLIED_TOPIC), "battle cannot ride the RNG application").to.equal(false);
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
  expect(battlePaid).to.be.gt(0n);
  expect(passes.size, "this fixed jackpot field pays liquid FLIP without pass awards").to.equal(0);
  expect(new Set(entries.values()).size, "fixture must retain a substantial fresh-owner field").to.be.gte(Math.floor(expectedAwards * 0.8));
  expect(battleReceipts.every((r) => r.blockNumber < traitReceipts[0].blockNumber), "the entire battle must finish before the trait draw").to.equal(true);
  // These wallet families were freshly seeded only in the Game registry. They had no prior
  // Coinflip/pass balance. Reconcile all published run/pot/share payments to actual ownership.
  for (const [id, owner] of entries) {
    const stored = await getSlot(crapsAddr, mapSlot(BigInt(id), betRoot));
    expect(stored & ((1n << 160n) - 1n), "settled seat retains its actual awarded owner").to.equal(BigInt(owner));
  }
  for (const [owner, expected] of credits) expect(await coinflip.coinflipAmount(owner), `actual stake for ${owner}`).to.equal(expected);
  for (const owner of new Set(entries.values())) {
    const packed = await getSlot(crapsAddr, mapSlot(BigInt(owner), passRoot));
    expect(packed & 0xffffffffn, `normal passes for ${owner}`).to.equal(0n);
    expect((packed >> 32n) & 0xffffffffn, `high passes for ${owner}`).to.equal(0n);
  }
  return {
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
  console.log(`      [COIN-ADV-GAS ${label}] max=${t.gas}; headroom to ${AUDIT_GAS_CEILING}=${AUDIT_GAS_CEILING - t.gas}; soft-target headroom=${SOFT_TARGET - t.gas}`);
}

describe("JackpotCoinAdvanceGas — current staged battle and separate level-one trait draw", function () {
  this.timeout(300_000);
  after(function () { restoreAddresses(); });
  for (const [pool, awards] of [["520", 26], ["5000", 250], ["10000", 500]]) {
    it(`fully settles ${awards} awarded seats and 50 trait shares below the 11.5M hard cap (${pool} ETH recorded pool)`, async function () {
      report(`${pool} ETH / ${awards} awards`, await measureLevelOneAdvance(pool, awards));
    });
  }
});
