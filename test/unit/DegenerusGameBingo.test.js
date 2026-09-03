import { expect } from "chai";
import hre from "hardhat";
import * as bucketSeed from "../helpers/bucketSeed.js";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { execSync } from "node:child_process";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";

const REWARD_POOL = 3;
const BINGO_DGNRS_BPS = 5n;
const BPS_DENOMINATOR = 10_000n;
const BINGO_FLIP = hre.ethers.parseEther("1000");
const ZERO_SLOTS = Array(8).fill(0);

let lvlTraitEntrySlot;
let bingoClaimedSlot;

function deriveStorageSlot(variable) {
  const output = execSync(
    "FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect " +
      "contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage " +
      "storageLayout 2>/dev/null"
  ).toString();

  for (const line of output.split("\n")) {
    if (!line.includes(variable)) continue;
    const cells = line.split("|").map((cell) => cell.trim());
    const labelIndex = cells.indexOf(variable);
    if (labelIndex !== -1 && /^[0-9]+$/.test(cells[labelIndex + 2] ?? "")) {
      return BigInt(cells[labelIndex + 2]);
    }
  }

  throw new Error(`Could not derive storage slot for ${variable}`);
}

function wordHex(value) {
  return `0x${BigInt(value).toString(16).padStart(64, "0")}`;
}

function traitBucketSlot(level, trait, baseSlot) {
  const outer = BigInt(
    hre.ethers.keccak256(
      hre.ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint24", "uint256"],
        [level, baseSlot]
      )
    )
  );
  return outer + BigInt(trait);
}

function arrayElementSlot(lengthSlot, index) {
  return BigInt(hre.ethers.keccak256(wordHex(lengthSlot))) + BigInt(index);
}

async function setStorage(gameAddress, slot, value) {
  await hre.network.provider.send("hardhat_setStorageAt", [
    gameAddress,
    wordHex(slot),
    wordHex(value),
  ]);
}

async function seedTraitBucket(gameAddress, level, trait, holders) {
  await bucketSeed.seedTraitBucket(gameAddress, level, trait, holders, {
    traitSlot: lvlTraitEntrySlot,
  });
}

async function seedBingo(gameAddress, level, symbol, holders) {
  const quadrant = symbol >> 3;
  const symbolInQuadrant = symbol & 7;
  const traitBase = (quadrant << 6) | symbolInQuadrant;

  for (let color = 0; color < 8; color++) {
    await seedTraitBucket(
      gameAddress,
      level,
      traitBase | (color << 3),
      holders
    );
  }
}

function bingoClaimLeaf(level, player) {
  const inner = hre.ethers.keccak256(
    hre.ethers.AbiCoder.defaultAbiCoder().encode(
      ["uint24", "uint256"],
      [level, bingoClaimedSlot]
    )
  );
  return BigInt(
    hre.ethers.keccak256(
      hre.ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "bytes32"],
        [player, inner]
      )
    )
  );
}

async function bingoAtGame(game) {
  return hre.ethers.getContractAt(
    "DegenerusGameBingoModule",
    await game.getAddress()
  );
}

function bingoEvents(receipt, bingo) {
  const events = [];
  for (const log of receipt.logs) {
    try {
      const parsed = bingo.interface.parseLog(log);
      if (parsed?.name === "BingoClaimed") events.push(parsed.args);
    } catch {
      // Ignore logs from sDGNRS and Coinflip interactions.
    }
  }
  return events;
}

describe("DegenerusGame simple bingo", function () {
  before(function () {
    lvlTraitEntrySlot = deriveStorageSlot("lvlTraitEntry");
    bingoClaimedSlot = deriveStorageSlot("bingoClaimed");
    expect(lvlTraitEntrySlot).to.equal(8n);
    expect(bingoClaimedSlot).to.equal(51n);
  });

  after(function () {
    restoreAddresses();
  });

  it("pays the normal 5 bps + 1,000 FLIP reward and stores one bool", async function () {
    const { game, sdgnrs, coinflip, alice } = await loadFixture(
      deployFullProtocol
    );
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    expect(
      bingo.interface.fragments.some(
        (fragment) =>
          fragment.type === "event" &&
          (fragment.name === "FirstSymbolBingo" ||
            fragment.name === "FirstQuadrantBingo")
      )
    ).to.equal(false);
    const level = 11;
    const symbol = 5;
    await seedBingo(gameAddress, level, symbol, [alice.address]);

    const poolBefore = await sdgnrs.poolBalance(REWARD_POOL);
    const dgnrsBefore = await sdgnrs.balanceOf(alice.address);
    const flipBefore = await coinflip.coinflipAmount(alice.address);
    const expectedDgnrs = (poolBefore * BINGO_DGNRS_BPS) / BPS_DENOMINATOR;

    const receipt = await (
      await bingo
        .connect(alice)
        .claimBingo(alice.address, level, symbol, ZERO_SLOTS)
    ).wait();

    expect(await sdgnrs.balanceOf(alice.address)).to.equal(
      dgnrsBefore + expectedDgnrs
    );
    expect(await sdgnrs.poolBalance(REWARD_POOL)).to.equal(
      poolBefore - expectedDgnrs
    );
    expect(await coinflip.coinflipAmount(alice.address)).to.equal(
      flipBefore + BINGO_FLIP
    );
    expect(
      BigInt(
        await hre.ethers.provider.getStorage(
          gameAddress,
          wordHex(bingoClaimLeaf(level, alice.address))
        )
      )
    ).to.equal(1n);

    const events = bingoEvents(receipt, bingo);
    expect(events).to.have.length(1);
    const [event] = events;
    expect(event.player).to.equal(alice.address);
    expect(event.level).to.equal(BigInt(level));
    expect(event.symbol).to.equal(BigInt(symbol));
    expect(event.flipReward).to.equal(BINGO_FLIP);
    expect(event.dgnrsPaid).to.equal(expectedDgnrs);
  });

  it("rejects every second claim on the same level, across symbols and quadrants", async function () {
    const { game, sdgnrs, coinflip, alice } = await loadFixture(
      deployFullProtocol
    );
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    const level = 12;

    await seedBingo(gameAddress, level, 0, [alice.address]);
    await seedBingo(gameAddress, level, 1, [alice.address]);
    await seedBingo(gameAddress, level, 8, [alice.address]);
    await bingo.connect(alice).claimBingo(alice.address, level, 0, ZERO_SLOTS);
    const dgnrsAfterFirst = await sdgnrs.balanceOf(alice.address);
    const flipAfterFirst = await coinflip.coinflipAmount(alice.address);

    await expect(
      bingo.connect(alice).claimBingo(alice.address, level, 1, ZERO_SLOTS)
    ).to.be.revertedWithCustomError(bingo, "AlreadyClaimed");
    await expect(
      bingo.connect(alice).claimBingo(alice.address, level, 8, ZERO_SLOTS)
    ).to.be.revertedWithCustomError(bingo, "AlreadyClaimed");
    expect(await sdgnrs.balanceOf(alice.address)).to.equal(dgnrsAfterFirst);
    expect(await coinflip.coinflipAmount(alice.address)).to.equal(
      flipAfterFirst
    );
  });

  it("resets eligibility independently for the next level", async function () {
    const { game, coinflip, alice } = await loadFixture(deployFullProtocol);
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    const flipBefore = await coinflip.coinflipAmount(alice.address);

    await seedBingo(gameAddress, 20, 2, [alice.address]);
    await seedBingo(gameAddress, 21, 17, [alice.address]);
    await bingo.connect(alice).claimBingo(alice.address, 20, 2, ZERO_SLOTS);
    await bingo.connect(alice).claimBingo(alice.address, 21, 17, ZERO_SLOTS);

    expect(await coinflip.coinflipAmount(alice.address)).to.equal(
      flipBefore + BINGO_FLIP * 2n
    );
  });

  it("lets multiple players claim the same level and symbol with no first bonus", async function () {
    const { game, sdgnrs, coinflip, alice, bob } = await loadFixture(
      deployFullProtocol
    );
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    const level = 30;
    const symbol = 24;
    const holders = [alice.address, bob.address];
    await seedBingo(gameAddress, level, symbol, holders);

    const pool0 = await sdgnrs.poolBalance(REWARD_POOL);
    const aliceExpected = (pool0 * BINGO_DGNRS_BPS) / BPS_DENOMINATOR;
    await bingo
      .connect(alice)
      .claimBingo(alice.address, level, symbol, Array(8).fill(0));

    const pool1 = await sdgnrs.poolBalance(REWARD_POOL);
    const bobExpected = (pool1 * BINGO_DGNRS_BPS) / BPS_DENOMINATOR;
    await bingo
      .connect(bob)
      .claimBingo(bob.address, level, symbol, Array(8).fill(1));

    expect(await sdgnrs.balanceOf(alice.address)).to.equal(aliceExpected);
    expect(await sdgnrs.balanceOf(bob.address)).to.equal(bobExpected);
    expect(await coinflip.coinflipAmount(alice.address)).to.equal(BINGO_FLIP);
    expect(await coinflip.coinflipAmount(bob.address)).to.equal(BINGO_FLIP);
  });

  it("allows permissionless settlement but pays only the bingo owner", async function () {
    const { game, sdgnrs, coinflip, alice, carol } = await loadFixture(
      deployFullProtocol
    );
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    const level = 40;
    await seedBingo(gameAddress, level, 3, [alice.address]);

    const ownerDgnrsBefore = await sdgnrs.balanceOf(alice.address);
    const callerDgnrsBefore = await sdgnrs.balanceOf(carol.address);
    const callerFlipBefore = await coinflip.coinflipAmount(carol.address);
    await bingo
      .connect(carol)
      .claimBingo(alice.address, level, 3, ZERO_SLOTS);

    expect(await sdgnrs.balanceOf(alice.address)).to.be.gt(ownerDgnrsBefore);
    expect(await sdgnrs.balanceOf(carol.address)).to.equal(callerDgnrsBefore);
    expect(await coinflip.coinflipAmount(alice.address)).to.equal(BINGO_FLIP);
    expect(await coinflip.coinflipAmount(carol.address)).to.equal(
      callerFlipBefore
    );
  });

  it("treats address(0) as the caller", async function () {
    const { game, coinflip, alice } = await loadFixture(deployFullProtocol);
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    const level = 41;
    await seedBingo(gameAddress, level, 4, [alice.address]);

    await bingo
      .connect(alice)
      .claimBingo(hre.ethers.ZeroAddress, level, 4, ZERO_SLOTS);

    expect(await coinflip.coinflipAmount(alice.address)).to.equal(BINGO_FLIP);
  });

  it("rejects invalid symbols and ownership proofs without consuming the claim", async function () {
    const { game, coinflip, alice, bob } = await loadFixture(
      deployFullProtocol
    );
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    const level = 50;
    await seedBingo(gameAddress, level, 7, [alice.address]);

    await expect(
      bingo.connect(alice).claimBingo(alice.address, level, 32, ZERO_SLOTS)
    ).to.be.revertedWithCustomError(bingo, "InvalidSymbol");
    await expect(
      bingo
        .connect(bob)
        .claimBingo(bob.address, level, 7, ZERO_SLOTS)
    ).to.be.revertedWithCustomError(bingo, "NotSlotOwner");
    await expect(
      bingo
        .connect(alice)
        .claimBingo(alice.address, level, 7, [0, 0, 0, 0, 0, 0, 0, 1])
    ).to.be.revertedWithCustomError(bingo, "NotSlotOwner");

    const missingColorTrait = 7 | (7 << 3);
    await setStorage(
      gameAddress,
      traitBucketSlot(level, missingColorTrait, lvlTraitEntrySlot),
      0
    );
    await expect(
      bingo.connect(alice).claimBingo(alice.address, level, 7, ZERO_SLOTS)
    ).to.be.revertedWithCustomError(bingo, "NotSlotOwner");
    await seedTraitBucket(gameAddress, level, missingColorTrait, [
      alice.address,
    ]);

    await bingo.connect(alice).claimBingo(alice.address, level, 7, ZERO_SLOTS);
    expect(await coinflip.coinflipAmount(alice.address)).to.equal(BINGO_FLIP);
  });

  it("honors the game-over cutoff without consuming the claim", async function () {
    const { game, coinflip, alice } = await loadFixture(deployFullProtocol);
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    const level = 60;
    await seedBingo(gameAddress, level, 9, [alice.address]);

    const originalHeader = BigInt(
      await hre.ethers.provider.getStorage(gameAddress, wordHex(0n))
    );
    const gameOverMask = 1n << (21n * 8n);
    await setStorage(gameAddress, 0n, originalHeader | gameOverMask);

    await expect(
      bingo.connect(alice).claimBingo(alice.address, level, 9, ZERO_SLOTS)
    ).to.be.revertedWithCustomError(bingo, "GameOver");

    await setStorage(gameAddress, 0n, originalHeader);
    await bingo.connect(alice).claimBingo(alice.address, level, 9, ZERO_SLOTS);
    expect(await coinflip.coinflipAmount(alice.address)).to.equal(BINGO_FLIP);
  });

  it("still credits FLIP and consumes the claim when Pool.Reward is empty", async function () {
    const { game, sdgnrs, coinflip, deployer, alice } = await loadFixture(
      deployFullProtocol
    );
    const gameAddress = await game.getAddress();
    const bingo = await bingoAtGame(game);
    const level = 70;
    const symbol = 31;
    await seedBingo(gameAddress, level, symbol, [alice.address]);

    await hre.network.provider.send("hardhat_impersonateAccount", [gameAddress]);
    await hre.network.provider.send("hardhat_setBalance", [
      gameAddress,
      wordHex(hre.ethers.parseEther("1")),
    ]);
    const gameSigner = await hre.ethers.getSigner(gameAddress);
    const poolBalance = await sdgnrs.poolBalance(REWARD_POOL);
    await sdgnrs
      .connect(gameSigner)
      .transferFromPool(REWARD_POOL, deployer.address, poolBalance);
    await hre.network.provider.send("hardhat_stopImpersonatingAccount", [
      gameAddress,
    ]);

    const receipt = await (
      await bingo
        .connect(alice)
        .claimBingo(alice.address, level, symbol, ZERO_SLOTS)
    ).wait();

    expect(await sdgnrs.balanceOf(alice.address)).to.equal(0n);
    expect(await coinflip.coinflipAmount(alice.address)).to.equal(BINGO_FLIP);
    const [event] = bingoEvents(receipt, bingo);
    expect(event.dgnrsPaid).to.equal(0n);

    await expect(
      bingo
        .connect(alice)
        .claimBingo(alice.address, level, symbol, ZERO_SLOTS)
    ).to.be.revertedWithCustomError(bingo, "AlreadyClaimed");
  });
});
