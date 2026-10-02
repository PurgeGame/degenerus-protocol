// SPDX-License-Identifier: AGPL-3.0-only
// Independent event replay for checkpoint streams. No transaction-local cursor
// reconstruction or trying alternative algorithms against the expected answer.
import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { eth, advanceToNextDay, getLastVRFRequestId, ZERO_BYTES32 } from "../helpers/testUtils.js";
import { decodeCheckpointKey, ticketCheckpointTraits } from "../helpers/raritySymbolBatchRef.mjs";

const WORD = 0x2f023456789abcdef0123456789abcdef0123456789abcdef0123456789abcden;
const ADDRESS_MASK = (1n << 160n) - 1n;

function parseInventory(receipt, iface) {
  const streams = [], revealed = [];
  for (const log of receipt.logs) {
    let parsed;
    try { parsed = iface.parseLog(log); } catch {}
    if (parsed?.name === "TraitsGenerated") {
      const key = BigInt(parsed.args.baseKey);
      const decoded = decodeCheckpointKey(key);
      streams.push({ ...decoded, baseKey: key, count: Number(parsed.args.take), player: parsed.args.player });
    } else if (log.topics.length === 4 && log.data.length === 66) {
      // EntryTraitsRevealed is anonymous: four level/address topics and one
      // packed trait/mask word. Reject ordinary event signature topics.
      const topics = log.topics.map(BigInt);
      if (topics.some((v) => v >> 184n !== 0n)) continue;
      const bits = BigInt(log.data), mask = bits >> 128n;
      for (let p = 0; p < 4; ++p) {
        if (!topics[p]) continue;
        for (let q = 0; q < 4; ++q) {
          if ((mask >> BigInt(p * 4 + q) & 1n) === 0n) continue;
          revealed.push({
            level: Number(topics[p] >> 160n),
            player: `0x${(topics[p] & ADDRESS_MASK).toString(16).padStart(40, "0")}`,
            trait: Number(bits >> BigInt(p * 32 + q * 8) & 255n),
          });
        }
      }
    }
  }
  return { streams, revealed };
}

async function drainFixture() {
  const fixture = await loadFixture(deployFullProtocol);
  const { game, deployer, mockVRF, alice } = fixture;
  await game.connect(alice).purchase(hre.ethers.ZeroAddress, 800_000n, 0n, ZERO_BYTES32, 0, false, { value: eth(30) });
  await advanceToNextDay();
  const beforeRequest = await getLastVRFRequestId(mockVRF);
  let request = beforeRequest;
  for (let i = 0; i < 100 && request === beforeRequest; ++i) {
    await game.connect(deployer).mineFlip({ gasLimit: 12_000_000 });
    request = await getLastVRFRequestId(mockVRF);
  }
  expect(request).not.to.equal(beforeRequest, "engine must commit a new request");
  await mockVRF.fulfillRandomWords(request, WORD);
  const storage = await hre.ethers.getContractAt("DegenerusGameStorage", await game.getAddress());
  const streams = [], revealed = [];
  for (let i = 0; i < 300; ++i) {
    const tx = await game.connect(deployer).mineFlip({ gasLimit: 12_000_000 });
    const receipt = await tx.wait();
    expect(receipt.gasUsed).to.be.lte(10_000_000n);
    const inventory = parseInventory(receipt, storage.interface);
    streams.push(...inventory.streams);
    revealed.push(...inventory.revealed);
    if (!(await game.rngLocked()) && i > 4) break;
  }
  const samePlayer = (v) => v.player.toLowerCase() === alice.address.toLowerCase();
  return { ...fixture, streams: streams.filter(samePlayer), revealed: revealed.filter(samePlayer) };
}

describe("Ticket checkpoints — self-contained event replay", function () {
  this.timeout(900_000);
  after(() => restoreAddresses());

  it("reconstructs every ordinary entry from versioned runs and direct seated reveals", async function () {
    const { game, alice, streams, revealed } = await drainFixture();
    expect(streams.length).to.be.greaterThan(1, "large owner reaches multiple solo groups");
    const totals = new Map();
    const add = (lvl, trait) => {
      const key = `${lvl}:${trait}`;
      totals.set(key, (totals.get(key) || 0) + 1);
    };
    for (const run of streams) {
      expect(run.domain).to.be.oneOf([0x20, 0x21, 0x22]);
      for (const trait of ticketCheckpointTraits({ baseKey: run.baseKey, entropyWord: WORD, count: run.count })) {
        add(run.level, trait);
      }
    }
    for (const run of revealed) add(run.level, run.trait);
    const levels = new Set([...streams, ...revealed].map((v) => v.level));
    for (const lvl of levels) {
      for (let trait = 0; trait < 256; ++trait) {
        const [count] = await game.getEntries(trait, lvl, 0, 20_000, alice.address);
        expect(Number(count), `level ${lvl}, trait ${trait}`).to.equal(totals.get(`${lvl}:${trait}`) || 0);
      }
    }
  });

  it("identifies every run by an increasing absolute aligned offset", async function () {
    const { streams } = await drainFixture();
    const ends = new Map();
    for (const run of streams) {
      const id = run.identity.toString();
      expect(run.startIndex % 16).to.equal(0);
      expect(run.startIndex).to.equal(ends.get(id) || 0);
      ends.set(id, run.startIndex + run.count);
    }
  });
});
