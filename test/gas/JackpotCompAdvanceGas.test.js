// JackpotCompAdvanceGas.test.js — the level-1 purchase-day advance carrying BOTH coin draws, measured
// as one complete advanceGame transaction through the REAL deployFixture wiring: real Game
// delegatecalls, the real CrapsBattle seating every craps winner (and reading back into the real
// Game), the real Coinflip batch credits.
//
// Level 1 (storage level 0) has no ETH leg; its daily instead runs TWO coin draws in the same tx:
//   - the trait draw over lvlTraitEntry[1] on the day's bonus traits (`payDailyFlipJackpot`), and
//   - the fill draw over the unminted far-future queues [2, 100] (`payDailyFutureFlipJackpot`).
// Each splits its budget B = levelPrizePool[0] * 1000 / (0.01 * 400): the craps half seats up to 25
// winners on TOMORROW's table (opener via vaultComp kind 5; the half's leftover upgrades seats to the
// whole day via creditPasses), the coin half pays up to 25 shares — so up to 50 Craps awards in one tx.
// Two budgets are measured, every winner a distinct never-touched wallet:
//   - B = 130,000 FLIP (520 ETH): 25 OPENER seats per draw — the heavier seat (a window reservation);
//   - B = 1,250,000 FLIP (5,000 ETH): 25 whole-day seats per draw — the maximum budget.
// Asserted under the EIP-7825 cap; logged against the 10M soft target.

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
const BONUS_TRAITS_TAG = ethers.keccak256(ethers.toUtf8Bytes("BONUS_TRAITS"));
const TRAIT_BOARD_TAG = ethers.keccak256(ethers.toUtf8Bytes("degenerus.jackpot.trait-board"));
const CRAPS_WIN_TOPIC = ethers.id("CoinDrawCrapsWin(address,uint24,bool,bool)");
const FLIP_WIN_TOPIC = ethers.id("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
const FUTURE_WIN_TOPIC = ethers.id("FarFutureFlipJackpotWinner(address,uint24,uint24,uint256)");
const RNG_APPLIED_TOPIC = ethers.id("DailyRngApplied(uint24,uint256,uint256,uint256)");

const EIP7825_TX_GAS_CAP = 16_777_216n;
const SOFT_TARGET = 10_000_000n;
const HALF = 25;
const FF_BIT = 1n << 22n;
const VAULT_DEITY_SYMBOL = 0n;
const SDGNRS_DEITY_SYMBOL = 6n;
const TRAIT_HOLDERS = 2000; // per level-1 bonus bucket: ~12 pulls each, repeats rare
const FF_HOLDERS = 8; // per unminted level: 50 distinct fills within the 16 level picks

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

// Append `holders` to lvlEntryOwner[lvl]; returns their registry positions. Position 0 is kept out
// of any seeded lane (a zero lane index understates gas).
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
    positions.push(count);
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

async function measureLevelOneAdvance(prevPoolEth) {
  const fixture = await loadFixture(deployFullProtocol);
  const { game, deployer, mockVRF, alice } = fixture;
  const gameAddr = await game.getAddress();

  const poolRoot = storageRootOf("levelPrizePool");
  const bucketRoot = storageRootOf("lvlTraitEntry");
  const ownerRoot = storageRootOf("lvlEntryOwner");
  const queueRoot = storageRootOf("ticketQueue");
  const deityRoot = storageRootOf("deityBySymbol");

  // Genesis deities add virtual bucket entries naming VAULT / sDGNRS, whose seats are refused (a
  // cheaper path): exclude them so every seat is a real table write.
  await setSlot(gameAddr, mapSlot(VAULT_DEITY_SYMBOL, deityRoot), 0n);
  await setSlot(gameAddr, mapSlot(SDGNRS_DEITY_SYMBOL, deityRoot), 0n);

  // Trait draw: the level-1 buckets of the day's bonus traits (the day's word is WORD: no nudges).
  const bonusTraits = traitsOf(hash2(WORD, BigInt(BONUS_TRAITS_TAG)));
  for (const t of bonusTraits) {
    const holders = Array.from({ length: TRAIT_HOLDERS }, (_, i) => holder(0xace000000n + BigInt(t) * 0x10000n + BigInt(i + 1)));
    const positions = await registerOwners(gameAddr, ownerRoot, 1n, holders);
    await writeLanes(gameAddr, mapSlot(1n, bucketRoot) + BigInt(t), positions);
  }

  // Fill draw: replace every unminted queue [2, 100] (genesis lanes included) with fresh wallets.
  for (let lvl = 2n; lvl <= 100n; ++lvl) {
    const holders = Array.from({ length: FF_HOLDERS }, (_, i) => holder(0xb00000000n + lvl * 0x100n + BigInt(i + 1)));
    const positions = await registerOwners(gameAddr, ownerRoot, lvl, holders);
    // A queue lane names registry position + 1.
    await writeLanes(gameAddr, mapSlot(lvl | FF_BIT, queueRoot), positions.map((p) => p + 1n));
  }

  await setSlot(gameAddr, mapSlot(0n, poolRoot), ethers.parseEther(prevPoolEth));

  // A real sale, then the day: request the word and drain until both draws land.
  await game.connect(alice).purchase(ethers.ZeroAddress, 200n, 0n, ethers.ZeroHash, 0, false, {
    value: ethers.parseEther("2"),
  });
  await advanceToNextDay();
  await game.connect(deployer).advanceGame();
  const requestId = await getLastVRFRequestId(mockVRF);
  try {
    await mockVRF.fulfillRandomWords(requestId, WORD);
  } catch {
    // advanceGame may consume the fulfillment in-line.
  }

  let receipt = null;
  for (let step = 0; step < 30 && receipt === null; ++step) {
    let tx;
    try {
      tx = await game.connect(deployer).advanceGame({ gasLimit: EIP7825_TX_GAS_CAP });
    } catch {
      break;
    }
    const r = await tx.wait();
    if (r.logs.some((l) => l.topics[0] === CRAPS_WIN_TOPIC || l.topics[0] === FUTURE_WIN_TOPIC)) receipt = r;
  }
  expect(receipt, "the advance chain never reached the level-1 coin draws").to.not.equal(null);

  const coder = ethers.AbiCoder.defaultAbiCoder();
  const seats = receipt.logs.filter((l) => l.topics[0] === CRAPS_WIN_TOPIC);
  const decoded = seats.map((l) => coder.decode(["bool", "bool"], l.data));
  const tally = {
    gas: receipt.gasUsed,
    traitSeats: seats.filter((l) => BigInt(l.topics[2]) === 1n).length,
    fillSeats: seats.filter((l) => BigInt(l.topics[2]) !== 1n).length,
    days: decoded.filter((d) => d[0]).length,
    refused: decoded.filter((d) => d[1]).length,
    traitShares: receipt.logs.filter((l) => l.topics[0] === FLIP_WIN_TOPIC).length,
    fillShares: receipt.logs.filter((l) => l.topics[0] === FUTURE_WIN_TOPIC).length,
    rngApplied: receipt.logs.some((l) => l.topics[0] === RNG_APPLIED_TOPIC),
  };
  const recipients = new Set(
    receipt.logs
      .filter((l) => [CRAPS_WIN_TOPIC, FLIP_WIN_TOPIC, FUTURE_WIN_TOPIC].includes(l.topics[0]))
      .map((l) => l.topics[1])
  );
  tally.distinct = recipients.size;
  return tally;
}

function report(label, t) {
  const soft = t.gas < SOFT_TARGET ? `under 10M by ${SOFT_TARGET - t.gas}` : `OVER 10M by ${t.gas - SOFT_TARGET}`;
  console.log(
    `      [COIN-ADV ${label}] trait seats=${t.traitSeats}, fill seats=${t.fillSeats}, whole days=${t.days}, ` +
      `refused=${t.refused}, trait shares=${t.traitShares}, fill shares=${t.fillShares}, ` +
      `distinct recipients=${t.distinct}, word applied in this tx=${t.rngApplied}`
  );
  console.log(
    `      [COIN-ADV-GAS ${label}] ${t.gas} gas; headroom to ${EIP7825_TX_GAS_CAP} = ` +
      `${EIP7825_TX_GAS_CAP - t.gas}; ${soft}`
  );
}

function expectBothDrawsFull(t, days) {
  expect(t.traitSeats, "the trait draw seated 25").to.equal(HALF);
  expect(t.fillSeats, "the fill draw seated 25").to.equal(HALF);
  expect(t.days, "whole-day upgrades").to.equal(days);
  expect(t.refused, "no seat refused").to.equal(0);
  expect(t.traitShares, "the trait draw paid 25 shares").to.equal(HALF);
  expect(t.fillShares, "the fill draw paid 25 shares").to.equal(HALF);
  expect(t.distinct, "coin-draw recipients are distinct cold wallets").to.be.gte(98);
  expect(t.gas < EIP7825_TX_GAS_CAP, "the two-draw advance tx broke the EIP-7825 ceiling").to.equal(true);
}

describe("JackpotCoinAdvanceGas — both level-1 coin draws inside a real advanceGame tx", function () {
  after(function () {
    restoreAddresses();
  });

  it("50 opener seats (B = 130,000 FLIP per draw) fit the EIP-7825 ceiling", async function () {
    const t = await measureLevelOneAdvance("520");
    report("50 openers", t);
    expectBothDrawsFull(t, 0);
  });

  it("50 whole-day seats (B = 1,250,000 FLIP per draw) fit the EIP-7825 ceiling", async function () {
    const t = await measureLevelOneAdvance("5000");
    report("50 whole days", t);
    expectBothDrawsFull(t, 2 * HALF);
  });
});
