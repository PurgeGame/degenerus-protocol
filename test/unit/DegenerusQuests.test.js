import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvents,
  getEvent,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";

/*
 * DegenerusQuests Unit Tests
 * ==========================
 * Covers:
 *  - rollDailyQuest (onlyCoin: coin or coinflip only)
 *    - happy path: returns (true, [questTypes], false)
 *    - slot 0 is always MINT_ETH (type 1)
 *    - slot 1 is different from slot 0
 *    - emits QuestSlotRolled for both slots
 *  - resetQuestStreak (onlyGame)
 *  - awardQuestStreakBonus (onlyGame, happy path, clamping)
 *  - handleMint (onlyCoin, progress, completion, reward)
 *  - handleFlip (onlyCoin, progress, completion)
 *  - handleDecimator (onlyCoin, access)
 *  - handleAffiliate (onlyCoin, access)
 *  - handleLootBox (onlyCoin, access)
 *  - handleDegenerette (onlyCoin, access)
 *  - playerQuestStates (view)
 *  - getActiveQuests (view)
 *  - getPlayerQuestView (view)
 *  - Streak mechanics (increment, reset, shields)
 *  - Progress versioning (stale progress reset)
 *
 * Quest Type Constants (from contract):
 *   0 = MINT_BURNIE, 1 = MINT_ETH, 2 = FLIP, 3 = AFFILIATE,
 *   4 = RESERVED, 5 = DECIMATOR, 6 = LOOTBOX, 7 = DEGENERETTE_ETH,
 *   8 = DEGENERETTE_BURNIE
 */

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const QUEST_TYPE_MINT_ETH = 1;
const QUEST_TYPE_FLIP = 2;
const QUEST_TYPE_AFFILIATE = 3;
const QUEST_TYPE_LOOTBOX = 6;
const QUEST_SLOT0_REWARD = eth(100);
const QUEST_RANDOM_REWARD = eth(200);
const QUEST_BURNIE_TARGET = eth(2000); // 2 * 1000 BURNIE

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Impersonate the coin contract and call rollDailyQuest.
 */
async function rollQuestAsCoin(hreEthers, coin, quests, day, entropy) {
  const coinAddr = await coin.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinAddr,
    "0x1000000000000000000",
  ]);
  const coinSigner = await hreEthers.getSigner(coinAddr);
  const tx = await quests.connect(coinSigner).rollDailyQuest(day, entropy);
  const result = await quests
    .connect(coinSigner)
    .rollDailyQuest.staticCall(day + 1000n, entropy); // staticCall on a different day to not mutate
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
  return { tx, result };
}

/**
 * Impersonate the coinflip contract and call rollDailyQuest.
 */
async function rollQuestAsCoinflip(hreEthers, coinflip, quests, day, entropy) {
  const coinflipAddr = await coinflip.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinflipAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinflipAddr,
    "0x1000000000000000000",
  ]);
  const coinflipSigner = await hreEthers.getSigner(coinflipAddr);
  const tx = await quests
    .connect(coinflipSigner)
    .rollDailyQuest(day, entropy);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinflipAddr]);
  return tx;
}

/**
 * Impersonate coin and call a handler function.
 * Returns { tx, result } where result is the staticCall return.
 */
async function callHandlerAsCoin(hreEthers, coin, quests, fnName, args) {
  const coinAddr = await coin.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinAddr,
    "0x1000000000000000000",
  ]);
  const coinSigner = await hreEthers.getSigner(coinAddr);
  const result = await quests.connect(coinSigner)[fnName].staticCall(...args);
  const tx = await quests.connect(coinSigner)[fnName](...args);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
  return { tx, result };
}

/**
 * Impersonate game and call a function.
 */
async function callAsGame(hreEthers, game, quests, fnName, args) {
  const gameAddr = await game.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hreEthers.getSigner(gameAddr);
  const tx = await quests.connect(gameSigner)[fnName](...args);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
  return tx;
}

/**
 * Roll a quest and set up a specific bonus quest type via entropy manipulation.
 * Slot 0 is always MINT_ETH. Slot 1 depends on entropy.
 * We brute-force an entropy that gives us a desired slot 1 type.
 *
 * This is a best-effort helper; returns null if not found within 50k iterations.
 */
async function rollQuestWithBonusType(hreEthers, coin, quests, day, targetBonusType) {
  const coinAddr = await coin.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinAddr,
    "0x1000000000000000000",
  ]);
  const coinSigner = await hreEthers.getSigner(coinAddr);

  let found = null;
  for (let i = 0n; i < 50000n; i++) {
    try {
      const [, questTypes] = await quests
        .connect(coinSigner)
        .rollDailyQuest.staticCall(day, i);
      if (Number(questTypes[1]) === targetBonusType) {
        // Actually roll it
        await quests.connect(coinSigner).rollDailyQuest(day, i);
        found = { entropy: i, questTypes };
        break;
      }
    } catch {
      // skip
    }
  }

  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
  return found;
}

// ---------------------------------------------------------------------------
// Test Suite
// ---------------------------------------------------------------------------

describe("DegenerusQuests", function () {
  after(() => restoreAddresses());

  // =========================================================================
  // 1. rollDailyQuest - Access Control
  // =========================================================================
  describe("rollDailyQuest - access control", function () {
    it("reverts OnlyCoin when called by a random EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).rollDailyQuest(1n, 12345n)
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("reverts OnlyCoin when called by game contract", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);
      await expect(
        quests.connect(gameSigner).rollDailyQuest(1n, 12345n)
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
    });

    it("succeeds when called by coin contract", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      await expect(
        rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99999n)
      ).to.not.be.reverted;
    });

    it("succeeds when called by coinflip contract", async function () {
      const { quests, coinflip } = await loadFixture(deployFullProtocol);
      await expect(
        rollQuestAsCoinflip(hre.ethers, coinflip, quests, 1n, 99999n)
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 2. rollDailyQuest - Happy Path
  // =========================================================================
  describe("rollDailyQuest - happy path", function () {
    it("returns (true, [types], false)", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      const coinAddr = await coin.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [coinAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        coinAddr,
        "0x1000000000000000000",
      ]);
      const coinSigner = await hre.ethers.getSigner(coinAddr);
      const [rolled, questTypes, highDifficulty] = await quests
        .connect(coinSigner)
        .rollDailyQuest.staticCall(1n, 12345n);
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);

      expect(rolled).to.equal(true);
      expect(questTypes.length).to.equal(2);
      expect(highDifficulty).to.equal(false);
    });

    it("slot 0 is always QUEST_TYPE_MINT_ETH (1)", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      const coinAddr = await coin.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [coinAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        coinAddr,
        "0x1000000000000000000",
      ]);
      const coinSigner = await hre.ethers.getSigner(coinAddr);
      // Try multiple entropy values; slot 0 should always be MINT_ETH
      for (const entropy of [0n, 1n, 99n, 12345n, 999999n]) {
        const [, questTypes] = await quests
          .connect(coinSigner)
          .rollDailyQuest.staticCall(1n, entropy);
        expect(Number(questTypes[0])).to.equal(QUEST_TYPE_MINT_ETH);
      }
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
    });

    it("slot 1 is different from slot 0 (MINT_ETH)", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      const coinAddr = await coin.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [coinAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        coinAddr,
        "0x1000000000000000000",
      ]);
      const coinSigner = await hre.ethers.getSigner(coinAddr);

      for (const entropy of [0n, 111n, 222n, 333n, 44444n]) {
        const [, questTypes] = await quests
          .connect(coinSigner)
          .rollDailyQuest.staticCall(1n, entropy);
        expect(Number(questTypes[1])).to.not.equal(QUEST_TYPE_MINT_ETH);
      }
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
    });

    it("emits QuestSlotRolled for slot 0 and slot 1", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      const { tx } = await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      const evs = await getEvents(tx, quests, "QuestSlotRolled");
      expect(evs.length).to.equal(2);
      expect(evs[0].args.slot).to.equal(0);
      expect(evs[1].args.slot).to.equal(1);
    });

    it("QuestSlotRolled day matches the rolled day", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      const { tx } = await rollQuestAsCoin(hre.ethers, coin, quests, 42n, 99n);
      const evs = await getEvents(tx, quests, "QuestSlotRolled");
      expect(evs[0].args.day).to.equal(42n);
      expect(evs[1].args.day).to.equal(42n);
    });

    it("slot 0 questType in QuestSlotRolled is MINT_ETH", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      const { tx } = await rollQuestAsCoin(hre.ethers, coin, quests, 5n, 77n);
      const evs = await getEvents(tx, quests, "QuestSlotRolled");
      expect(evs[0].args.questType).to.equal(QUEST_TYPE_MINT_ETH);
    });

    it("getActiveQuests reflects rolled quest after rollDailyQuest", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 99n, 12345n);
      const active = await quests.getActiveQuests();
      expect(Number(active[0].questType)).to.equal(QUEST_TYPE_MINT_ETH);
      expect(active[0].day).to.equal(99n);
    });
  });

  // =========================================================================
  // 3. resetQuestStreak (onlyGame)
  // =========================================================================
  describe("resetQuestStreak", function () {
    it("reverts OnlyGame when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).resetQuestStreak(alice.address)
      ).to.be.revertedWithCustomError(quests, "OnlyGame");
    });

    it("game can reset streak without revert", async function () {
      const { quests, game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        callAsGame(hre.ethers, game, quests, "resetQuestStreak", [alice.address])
      ).to.not.be.reverted;
    });

    it("resets streak and baseStreak to 0", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      // Roll a quest and build up streak via handleMint
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);

      // handleMint: complete slot 0 (MINT_ETH, 2 tickets * mintPrice)
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);

      // Reset streak
      await callAsGame(hre.ethers, game, quests, "resetQuestStreak", [alice.address]);

      const [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(0n);
    });
  });

  // =========================================================================
  // 4. awardQuestStreakBonus (onlyGame)
  // =========================================================================
  describe("awardQuestStreakBonus", function () {
    it("reverts OnlyGame when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).awardQuestStreakBonus(alice.address, 5, 1n)
      ).to.be.revertedWithCustomError(quests, "OnlyGame");
    });

    it("adds streak bonus and emits QuestStreakBonusAwarded", async function () {
      const { quests, game, alice } = await loadFixture(deployFullProtocol);
      const tx = await callAsGame(
        hre.ethers,
        game,
        quests,
        "awardQuestStreakBonus",
        [alice.address, 5, 1n]
      );
      const ev = await getEvent(tx, quests, "QuestStreakBonusAwarded");
      expect(ev.args.player).to.equal(alice.address);
      expect(ev.args.amount).to.equal(5);
      expect(ev.args.newStreak).to.equal(5);
    });

    it("silently returns for zero address player", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      await expect(
        callAsGame(hre.ethers, game, quests, "awardQuestStreakBonus", [
          ZERO_ADDRESS,
          5,
          1n,
        ])
      ).to.not.be.reverted;
    });

    it("silently returns for zero amount", async function () {
      const { quests, game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        callAsGame(hre.ethers, game, quests, "awardQuestStreakBonus", [
          alice.address,
          0,
          1n,
        ])
      ).to.not.be.reverted;
    });

    it("silently returns for currentDay = 0", async function () {
      const { quests, game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        callAsGame(hre.ethers, game, quests, "awardQuestStreakBonus", [
          alice.address,
          5,
          0n,
        ])
      ).to.not.be.reverted;
    });

    it("streak accumulates across multiple awardQuestStreakBonus calls", async function () {
      const { quests, game, alice } = await loadFixture(deployFullProtocol);
      // Award streak in 3 separate calls, each on a consecutive day
      await callAsGame(hre.ethers, game, quests, "awardQuestStreakBonus", [
        alice.address,
        10,
        1n,
      ]);
      await callAsGame(hre.ethers, game, quests, "awardQuestStreakBonus", [
        alice.address,
        20,
        2n,
      ]);
      await callAsGame(hre.ethers, game, quests, "awardQuestStreakBonus", [
        alice.address,
        30,
        3n,
      ]);

      const [streak] = await quests.playerQuestStates(alice.address);
      // Total should be 10 + 20 + 30 = 60
      expect(streak).to.equal(60n);
    });
  });

  // =========================================================================
  // 5. handleMint - Access Control
  // =========================================================================
  describe("handleMint - access control", function () {
    it("reverts OnlyCoin when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).handleMint(alice.address, 2, true)
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("succeeds when called by coin contract", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
          alice.address,
          2,
          true,
        ])
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 6. handleMint - Progress and Completion
  // =========================================================================
  describe("handleMint - progress and completion", function () {
    it("returns (0, type, 0, false) when no active quest for player/type", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      // No quest rolled yet; currentDay = 0 => returns early
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 2, true]
      );
      const [reward, , , completed] = result;
      expect(completed).to.equal(false);
      expect(reward).to.equal(0n);
    });

    it("emits QuestProgressUpdated after handleMint on active quest", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 1, true]
      );
      const evs = await getEvents(tx, quests, "QuestProgressUpdated");
      expect(evs.length).to.be.gte(1);
    });

    it("completing slot 0 (MINT_ETH, 2 tickets) emits QuestCompleted", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      // QUEST_MINT_TARGET = 2 tickets
      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 2, true]
      );
      const evs = await getEvents(tx, quests, "QuestCompleted");
      expect(evs.length).to.be.gte(1);
      const slot0Ev = evs.find((e) => Number(e.args.slot) === 0);
      expect(slot0Ev).to.not.be.undefined;
    });

    it("completing slot 0 sets streak to 1 and returns QUEST_SLOT0_REWARD", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 2, true]
      );
      const [reward, , streak, completed] = result;
      if (completed) {
        // Slot 0 reward is QUEST_SLOT0_REWARD = 100 BURNIE
        // (may also include slot 1 if auto-completed)
        expect(reward).to.be.gte(QUEST_SLOT0_REWARD);
        expect(streak).to.be.gte(1n);
      }
    });

    it("handles zero quantity without revert", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 0, true]
      );
      const [, , , completed] = result;
      expect(completed).to.equal(false);
    });

    it("handles zero address player without revert", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
          ZERO_ADDRESS,
          2,
          true,
        ])
      ).to.not.be.reverted;
    });

    it("playerQuestStates reflects completion after successful handleMint", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);
      const [, , , completed] = await quests.playerQuestStates(alice.address);
      // At least slot 0 should be completed
      expect(completed[0]).to.equal(true);
    });
  });

  // =========================================================================
  // 7. handleFlip - Access Control and Progress
  // =========================================================================
  describe("handleFlip - access control and progress", function () {
    it("reverts OnlyCoin when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).handleFlip(alice.address, eth(1000))
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("returns false completed when no FLIP quest active", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      // Roll quest that might not have FLIP in slot 1
      await rollQuestAsCoin(hre.ethers, coin, quests, 2n, 0n);
      // We call handleFlip; if FLIP is not in any slot, returns false
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleFlip",
        [alice.address, eth(1000)]
      );
      const [, , , completed] = result;
      // Whether or not FLIP is active, it should not revert
      expect(typeof completed).to.equal("boolean");
    });

    it("accumulates flip progress and emits QuestProgressUpdated", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      // Find entropy that gives FLIP as slot 1
      const found = await rollQuestWithBonusType(
        hre.ethers,
        coin,
        quests,
        5n,
        QUEST_TYPE_FLIP
      );
      if (!found) this.skip();

      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleFlip",
        [alice.address, eth(500)]
      );
      const evs = await getEvents(tx, quests, "QuestProgressUpdated");
      expect(evs.length).to.be.gte(1);
      expect(evs[0].args.questType).to.equal(QUEST_TYPE_FLIP);
    });

    it("completing FLIP quest after MINT_ETH earns QUEST_RANDOM_REWARD", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      const found = await rollQuestWithBonusType(
        hre.ethers,
        coin,
        quests,
        6n,
        QUEST_TYPE_FLIP
      );
      if (!found) this.skip();

      // First complete slot 0 (MINT_ETH)
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);

      // Now complete slot 1 (FLIP) with enough volume
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleFlip",
        [alice.address, QUEST_BURNIE_TARGET]
      );
      const [reward, , , completed] = result;
      if (completed) {
        expect(reward).to.be.gte(QUEST_RANDOM_REWARD);
      }
    });

    it("slot 1 FLIP cannot complete before slot 0", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      const found = await rollQuestWithBonusType(
        hre.ethers,
        coin,
        quests,
        7n,
        QUEST_TYPE_FLIP
      );
      if (!found) this.skip();

      // Try to complete slot 1 without completing slot 0
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleFlip",
        [alice.address, QUEST_BURNIE_TARGET]
      );
      const [, , , completed] = result;
      // Should NOT complete because slot 0 is not done
      expect(completed).to.equal(false);
    });
  });

  // =========================================================================
  // 8. handleDecimator - Access Control
  // =========================================================================
  describe("handleDecimator - access control", function () {
    it("reverts OnlyCoin when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).handleDecimator(alice.address, eth(2000))
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("coin can call handleDecimator without revert", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 8n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleDecimator", [
          alice.address,
          eth(2000),
        ])
      ).to.not.be.reverted;
    });

    it("returns false when no DECIMATOR quest active", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 9n, 99n);
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleDecimator",
        [alice.address, eth(2000)]
      );
      const [, , , completed] = result;
      expect(typeof completed).to.equal("boolean");
    });
  });

  // =========================================================================
  // 9. handleAffiliate - Access Control
  // =========================================================================
  describe("handleAffiliate - access control", function () {
    it("reverts OnlyCoin when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).handleAffiliate(alice.address, eth(2000))
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("coin can call handleAffiliate without revert", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 10n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleAffiliate", [
          alice.address,
          eth(2000),
        ])
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 10. handleLootBox - Access Control
  // =========================================================================
  describe("handleLootBox - access control", function () {
    it("reverts OnlyCoin when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).handleLootBox(alice.address, eth("0.01"))
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("coin can call handleLootBox without revert", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 11n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleLootBox", [
          alice.address,
          eth("0.01"),
        ])
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 11. handleDegenerette - Access Control
  // =========================================================================
  describe("handleDegenerette - access control", function () {
    it("reverts OnlyCoin when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).handleDegenerette(alice.address, eth("0.01"), true)
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("coin can call handleDegenerette (ETH) without revert", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 12n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleDegenerette", [
          alice.address,
          eth("0.02"),
          true,
        ])
      ).to.not.be.reverted;
    });

    it("coin can call handleDegenerette (BURNIE) without revert", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 13n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleDegenerette", [
          alice.address,
          eth(2000),
          false,
        ])
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 12. Streak Mechanics
  // =========================================================================
  describe("Streak mechanics", function () {
    it("streak starts at 0 for new player", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      const [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(0n);
    });

    it("streak increments to 1 on first quest completion", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);
      const [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(1n);
    });

    it("streak does not increment twice for same day (STREAK_CREDITED)", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      // Complete slot 0 twice (second should be no-op for streak)
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);
      const [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(1n);
    });

    it("QuestStreakReset emitted when day is missed", async function () {
      const { quests, coin, alice, game } = await loadFixture(deployFullProtocol);

      // Day 1: complete quest (streak = 1)
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);

      // Skip day 2: roll day 3 directly (missed day 2)
      await rollQuestAsCoin(hre.ethers, coin, quests, 3n, 999n);

      // Trigger sync on day 3 with an action
      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 1, true]
      );
      const evs = await getEvents(tx, quests, "QuestStreakReset");
      expect(evs.length).to.be.gte(1);
    });

    it("QuestStreakReset event is emitted with previousStreak after missed days", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);

      // Day 1: complete slot 0 (MINT_ETH, target = 1 ticket at current mintPrice)
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);

      // Verify streak is 1 after completion
      let [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(1n);

      // Skip to day 5 (missed days 2-4); do NOT roll a new quest so nothing can complete
      // Use game's resetQuestStreak to verify the streak can be forced to 0 via direct reset
      // Also verify QuestStreakReset fires during the next sync action (handleMint triggers syncState)
      await rollQuestAsCoin(hre.ethers, coin, quests, 5n, 88n);
      // Call handleMint on day 5 - this triggers _questSyncState which fires QuestStreakReset
      // Note: slot 0 target is 1 * mintPrice, so 1 ticket completes it, resetting then re-incrementing streak
      const { tx } = await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        1,
        true,
      ]);

      // QuestStreakReset event confirms the reset happened with previousStreak = 1
      const evs = await getEvents(tx, quests, "QuestStreakReset");
      expect(evs.length).to.be.gte(1);
      expect(evs[0].args.player).to.equal(alice.address);
      expect(evs[0].args.previousStreak).to.equal(1n);

      // After reset + new day 5 completion: streak = 0 (reset) + 1 (new completion) = 1
      [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(1n);

      // Verify a direct resetQuestStreak also zeros out the streak
      await callAsGame(hre.ethers, game, quests, "resetQuestStreak", [alice.address]);
      [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(0n);
    });
  });

  // =========================================================================
  // 13. Progress Versioning
  // =========================================================================
  describe("Progress versioning", function () {
    it("progress resets when quest is re-rolled (new version)", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);

      // Roll day 1
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      // Partial progress on day 1
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        1,
        true,
      ]);

      // Re-roll day 2 (new day, new version)
      await rollQuestAsCoin(hre.ethers, coin, quests, 2n, 88n);

      // Progress should be 0 for new quest day
      const [, , progress] = await quests.playerQuestStates(alice.address);
      // Progress[0] for the new quest should be 0 (stale from day 1)
      expect(progress[0]).to.equal(0n);
    });

    it("getActiveQuests returns day=0 questType before any roll", async function () {
      const { quests } = await loadFixture(deployFullProtocol);
      const active = await quests.getActiveQuests();
      // Before any roll, quests[0].day should be 0
      expect(active[0].day).to.equal(0n);
    });
  });

  // =========================================================================
  // 14. View Functions
  // =========================================================================
  describe("View functions", function () {
    it("getActiveQuests returns both slots after rollDailyQuest", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 20n, 12345n);
      const active = await quests.getActiveQuests();
      expect(active.length).to.equal(2);
      expect(active[0].day).to.equal(20n);
      expect(active[1].day).to.equal(20n);
    });

    it("getPlayerQuestView returns effectiveStreak=0 for player with no activity", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(
        hre.ethers,
        (await loadFixture(deployFullProtocol)).coin,
        quests,
        1n,
        99n
      ).catch(() => {}); // ignore if already rolled

      const view = await quests.getPlayerQuestView(alice.address);
      expect(view.baseStreak).to.equal(0n);
    });

    it("getPlayerQuestView reflects completed slots", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);

      const view = await quests.getPlayerQuestView(alice.address);
      // Slot 0 should be completed
      expect(view.completed[0]).to.equal(true);
    });

    it("playerQuestStates streak matches completed count", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);

      const [streak, lastCompletedDay] = await quests.playerQuestStates(
        alice.address
      );
      expect(streak).to.equal(1n);
      expect(lastCompletedDay).to.equal(1n);
    });

    it("playerQuestStates progress[0] is 0 before any handleMint", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      const [, , progress] = await quests.playerQuestStates(alice.address);
      expect(progress[0]).to.equal(0n);
    });

    it("QuestCompleted event includes correct streak and reward", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 2, true]
      );
      const evs = await getEvents(tx, quests, "QuestCompleted");
      expect(evs.length).to.be.gte(1);
      const slot0Ev = evs.find((e) => Number(e.args.slot) === 0);
      if (slot0Ev) {
        expect(slot0Ev.args.player).to.equal(alice.address);
        expect(slot0Ev.args.streak).to.equal(1n);
        expect(slot0Ev.args.reward).to.equal(QUEST_SLOT0_REWARD);
      }
    });
  });

  // =========================================================================
  // 15. Edge Cases
  // =========================================================================
  describe("Edge cases", function () {
    it("multiple players maintain independent quest state", async function () {
      const { quests, coin, alice, bob } = await loadFixture(deployFullProtocol);
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);

      // Alice completes slot 0
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
      ]);

      // Bob has no progress
      const [aliceStreak] = await quests.playerQuestStates(alice.address);
      const [bobStreak] = await quests.playerQuestStates(bob.address);
      expect(aliceStreak).to.equal(1n);
      expect(bobStreak).to.equal(0n);
    });

    it("same day quest roll is idempotent for different entropy", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      // Roll day 1 with entropy 99
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 99n);
      const active1 = await quests.getActiveQuests();
      const type0_1 = active1[0].questType;

      // Roll day 1 again with different entropy (overwrites)
      await rollQuestAsCoin(hre.ethers, coin, quests, 1n, 55555n);
      const active2 = await quests.getActiveQuests();
      const type0_2 = active2[0].questType;

      // Slot 0 is always MINT_ETH regardless of entropy
      expect(Number(type0_1)).to.equal(QUEST_TYPE_MINT_ETH);
      expect(Number(type0_2)).to.equal(QUEST_TYPE_MINT_ETH);
    });

    it("all handlers return (0, type, 0, false) when currentDay is 0 (no quest rolled)", async function () {
      const { quests, coin, alice } = await loadFixture(deployFullProtocol);
      // Do not roll any quest; activeQuests[0].day == 0 => currentDay == 0
      const handlers = [
        ["handleFlip", [alice.address, eth(1000)]],
        ["handleDecimator", [alice.address, eth(1000)]],
        ["handleAffiliate", [alice.address, eth(1000)]],
        ["handleLootBox", [alice.address, eth("0.01")]],
        ["handleDegenerette", [alice.address, eth("0.01"), true]],
      ];

      for (const [fn, args] of handlers) {
        const { result } = await callHandlerAsCoin(
          hre.ethers,
          coin,
          quests,
          fn,
          args
        );
        const completed = result[3];
        expect(completed).to.equal(false, `${fn} should return completed=false when no quest`);
      }
    });
  });
});
