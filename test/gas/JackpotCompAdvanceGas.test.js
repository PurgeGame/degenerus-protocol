// JackpotCompAdvanceGas.test.js — one complete advanceGame transaction through the REAL wiring
// with the coin jackpot in comp mode: real Game delegatecall dispatch, real CrapsBattle pass
// credits, real Coinflip batch. The foundry suite measures the module call in isolation; this
// is the stage-level figure — the tx that actually carries the draw on chain — against the
// EIP-7825 hard ceiling, with the soft-target figure logged beside it.
//
// Level-1 staging is deliberately the heavy case: the purchase-phase advance runs TWO coin
// jackpot calls in one transaction (the main [1,1] draw and the salted [2,5] draw), and both
// clear the comp threshold here, so the measured tx carries two comp draws plus both FLIP
// batches.

import { expect } from "chai";
import hre from "hardhat";
import { execSync } from "node:child_process";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { advanceToNextDay, getLastVRFRequestId } from "../helpers/testUtils.js";

const { ethers } = hre;

const WORD = BigInt(ethers.keccak256(ethers.toUtf8Bytes("comp-advance-gas-word")));
const BONUS_TRAITS_TAG = ethers.keccak256(ethers.toUtf8Bytes("BONUS_TRAITS"));
const COMP_WIN_TOPIC = ethers.id("JackpotCrapsCompWin(address,uint24,uint8,uint32,uint256)");

const EIP7825_TX_GAS_CAP = 16_777_216n;
const SOFT_TARGET = 10_000_000n;

// --- storage roots from forge inspect (never hardcoded) ---
const layoutCache = new Map();
function storageRootOf(contractName, varName) {
  if (!layoutCache.has(contractName)) {
    const raw = execSync(`forge inspect ${contractName} storageLayout --json`, {
      cwd: process.cwd(),
      env: {
        ...process.env,
        FOUNDRY_DISABLE_NIGHTLY_WARNING: "1",
        FOUNDRY_CACHE_PATH: `${process.env.HOME}/.cache/purgegame-tmp/forge-cache-layout`,
      },
      maxBuffer: 64 * 1024 * 1024,
    }).toString();
    layoutCache.set(contractName, JSON.parse(raw));
  }
  const entry = layoutCache.get(contractName).storage.find((s) => s.label === varName);
  if (!entry) throw new Error(`${varName} not found in ${contractName} layout`);
  return BigInt(entry.slot);
}

const pad32 = (v) => ethers.toBeHex(v, 32);
const mapSlot = (key, root) => BigInt(ethers.keccak256(ethers.concat([pad32(key), pad32(root)])));

async function setSlot(addr, slot, value) {
  await hre.network.provider.send("hardhat_setStorageAt", [addr, pad32(slot), pad32(value)]);
}

async function seedBucket(gameAddr, lvl, trait, holders, root) {
  const arraySlot = mapSlot(trait, mapSlot(lvl, root));
  await setSlot(gameAddr, arraySlot, holders.length);
  const dataBase = BigInt(ethers.keccak256(pad32(arraySlot)));
  for (let i = 0; i < holders.length; ++i) {
    await setSlot(gameAddr, dataBase + BigInt(i), BigInt(holders[i]));
  }
}

// --- JS mirrors of the draw's pure derivations (zero hero wagers → base traits) ---
function saltedWordOf(word) {
  return BigInt(ethers.keccak256(ethers.concat([pad32(word), BONUS_TRAITS_TAG])));
}
function traitsOf(entropy) {
  const r = BigInt(entropy);
  return [
    Number(r & 0x3fn),
    64 + Number((r >> 6n) & 0x3fn),
    128 + Number((r >> 12n) & 0x3fn),
    192 + Number((r >> 18n) & 0x3fn),
  ];
}

describe("JackpotCompAdvanceGas — comp-mode coin jackpot inside a real advanceGame tx", function () {
  after(function () {
    restoreAddresses();
  });

  it("the advance tx carrying both comp-mode coin draws fits the EIP-7825 ceiling", async function () {
    const fixture = await loadFixture(deployFullProtocol);
    const { game, deployer, mockVRF, alice } = fixture;
    const gameAddr = await game.getAddress();

    const poolRoot = storageRootOf("DegenerusGame", "levelPrizePool");
    const bucketRoot = storageRootOf("DegenerusGame", "lvlTraitEntry");

    // Both level-1 coin calls draw their traits from their own word; seed each call's four
    // winning-trait buckets at each level its pulls can sample, ten holders apiece, so every
    // scheduled pull finds a candidate and the tx does its full complement of work.
    const holders = [];
    for (let i = 1; i <= 10; ++i) {
      holders.push("0x" + (0xace0000 + i).toString(16).padStart(40, "0"));
    }
    const mainTraits = traitsOf(saltedWordOf(WORD));
    const saltedTraits = traitsOf(saltedWordOf(saltedWordOf(WORD)));
    for (const t of mainTraits) {
      await seedBucket(gameAddr, 1, t, holders, bucketRoot);
    }
    for (let lvl = 2; lvl <= 5; ++lvl) {
      for (const t of saltedTraits) {
        await seedBucket(gameAddr, lvl, t, holders, bucketRoot);
      }
    }

    // levelPrizePool[0] = 2,000 ETH → each call's coinBudget = 500,000 FLIP, far over the
    // 91,200-FLIP comp threshold: both draws run comp mode.
    await setSlot(gameAddr, mapSlot(0, poolRoot), ethers.parseEther("2000"));

    // A real sale, then the day: request the word, pin it, drain until the comp draw lands.
    await game.connect(alice).purchase(
      ethers.ZeroAddress,
      200n,
      0n,
      ethers.ZeroHash,
      0,
      false,
      { value: ethers.parseEther("2") }
    );
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    try {
      await mockVRF.fulfillRandomWords(requestId, WORD);
    } catch {
      // advanceGame may consume the fulfillment in-line.
    }

    let jackpotReceipt = null;
    for (let step = 0; step < 30 && jackpotReceipt === null; ++step) {
      let tx;
      try {
        tx = await game.connect(deployer).advanceGame();
      } catch {
        break;
      }
      const receipt = await tx.wait();
      if (receipt.logs.some((l) => l.topics[0] === COMP_WIN_TOPIC)) {
        jackpotReceipt = receipt;
      }
    }
    expect(jackpotReceipt, "the advance chain never reached a comp-mode coin draw").to.not.equal(null);

    const compEvents = jackpotReceipt.logs.filter((l) => l.topics[0] === COMP_WIN_TOPIC);
    const gasUsed = jackpotReceipt.gasUsed;
    console.log(
      `      [COMP-ADV-GAS] advanceGame tx with ${compEvents.length} comp slot(s): ` +
        `${gasUsed} gas (soft target ${SOFT_TARGET}, hard cap ${EIP7825_TX_GAS_CAP})`
    );
    expect(gasUsed < EIP7825_TX_GAS_CAP, "the comp-mode advance tx broke the EIP-7825 ceiling").to.equal(true);
    expect(gasUsed < SOFT_TARGET, "the comp-mode advance tx broke the 10M soft target").to.equal(true);
  });
});
