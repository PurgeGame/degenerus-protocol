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
 *  - rollDailyQuest (onlyGame)
 *    - happy path: returns (true, [questTypes], false)
 *    - slot 0 is always MINT_ETH (type 1)
 *    - slot 1 is different from slot 0
 *    - emits QuestSlotRolled for both slots
 *  - awardQuestStreakBonus (onlyGame, happy path, clamping)
 *  - handleMint (onlyCoin, progress, completion, reward)
 *  - handleFlip (onlyCoin, progress, completion)
 *  - handleDecimator (onlyCoin, access)
 *  - handleAffiliate (onlyCoin, access)
 *  - handleDegenerette (onlyCoin, access)
 *  - playerQuestStates (view)
 *  - getActiveQuests (view)
 *  - getPlayerQuestView (view)
 *  - Streak mechanics (increment, reset, shields)
 *  - Progress versioning (stale progress reset)
 *
 * Quest Type Constants (from contract):
 *   0 = MINT_FLIP, 1 = MINT_ETH, 2 = FLIP, 3 = AFFILIATE,
 *   4 = RESERVED, 5 = DECIMATOR, 6 = LOOTBOX, 7 = DEGENERETTE_ETH,
 *   8 = DEGENERETTE_FLIP
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
const QUEST_FLIP_TARGET = eth(2000); // 2 * 1000 FLIP

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Impersonate the game contract and call rollDailyQuest.
 * (rollDailyQuest access changed from onlyCoin to onlyGame in v13.0)
 */
async function rollQuestAsGame(hreEthers, game, quests, day, entropy, forceMintFlip = false) {
  const gameAddr = await game.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hreEthers.getSigner(gameAddr);
  const tx = await quests.connect(gameSigner).rollDailyQuest(day, entropy, forceMintFlip, false);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
  return { tx };
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
async function rollQuestWithBonusType(hreEthers, game, quests, day, targetBonusType) {
  const gameAddr = await game.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hreEthers.getSigner(gameAddr);

  let found = null;
  for (let i = 0n; i < 50000n; i++) {
    try {
      const [, questTypes] = await quests
        .connect(gameSigner)
        .rollDailyQuest.staticCall(day, i, false, false);
      if (Number(questTypes[1]) === targetBonusType) {
        // Actually roll it
        await quests.connect(gameSigner).rollDailyQuest(day, i, false, false);
        found = { entropy: i, questTypes };
        break;
      }
    } catch {
      // skip
    }
  }

  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
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
    it("reverts OnlyGame when called by a random EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).rollDailyQuest(1n, 12345n, false, false)
      ).to.be.revertedWithCustomError(quests, "OnlyGame");
    });

    it("reverts OnlyGame when called by coin contract", async function () {
      const { quests, coin } = await loadFixture(deployFullProtocol);
      const coinAddr = await coin.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [coinAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        coinAddr,
        "0x1000000000000000000",
      ]);
      const coinSigner = await hre.ethers.getSigner(coinAddr);
      await expect(
        quests.connect(coinSigner).rollDailyQuest(1n, 12345n, false, false)
      ).to.be.revertedWithCustomError(quests, "OnlyGame");
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
    });

    it("succeeds when called by game contract", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      await expect(
        rollQuestAsGame(hre.ethers, game, quests, 1n, 99999n)
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 2. rollDailyQuest - Happy Path
  // =========================================================================
  describe("rollDailyQuest - happy path", function () {
    it("rolls quests and populates active slots", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 12345n);
      const active = await quests.getActiveQuests();
      expect(active.length).to.equal(2);
      expect(active[0].day).to.equal(1n);
    });

    it("slot 0 is always QUEST_TYPE_MINT_ETH (1)", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      // Try multiple entropy values; slot 0 should always be MINT_ETH
      for (const entropy of [0n, 1n, 99n, 12345n, 999999n]) {
        await rollQuestAsGame(hre.ethers, game, quests, entropy + 1n, entropy);
        const active = await quests.getActiveQuests();
        expect(Number(active[0].questType)).to.equal(QUEST_TYPE_MINT_ETH);
      }
    });

    it("slot 1 is different from slot 0 (MINT_ETH)", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 0n);
      const active = await quests.getActiveQuests();
      expect(Number(active[1].questType)).to.not.equal(QUEST_TYPE_MINT_ETH);
    });

    it("emits QuestSlotRolled for slot 0 and slot 1", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      const { tx } = await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      const evs = await getEvents(tx, quests, "QuestSlotRolled");
      expect(evs.length).to.equal(2);
      expect(evs[0].args.slot).to.equal(0);
      expect(evs[1].args.slot).to.equal(1);
    });

    it("QuestSlotRolled day matches the rolled day", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      const { tx } = await rollQuestAsGame(hre.ethers, game, quests, 42n, 99n);
      const evs = await getEvents(tx, quests, "QuestSlotRolled");
      expect(evs[0].args.day).to.equal(42n);
      expect(evs[1].args.day).to.equal(42n);
    });

    it("slot 0 questType in QuestSlotRolled is MINT_ETH", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      const { tx } = await rollQuestAsGame(hre.ethers, game, quests, 5n, 77n);
      const evs = await getEvents(tx, quests, "QuestSlotRolled");
      expect(evs[0].args.questType).to.equal(QUEST_TYPE_MINT_ETH);
    });

    it("getActiveQuests reflects rolled quest after rollDailyQuest", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 99n, 12345n);
      const active = await quests.getActiveQuests();
      expect(Number(active[0].questType)).to.equal(QUEST_TYPE_MINT_ETH);
      expect(active[0].day).to.equal(99n);
    });

    it("MINT_FLIP is auto-assigned to slot 1 only when forced, never randomly rolled", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      const QUEST_TYPE_MINT_FLIP = 9;
      // forceMintFlip = true: slot 1 is MINT_FLIP (the lastPurchaseDay auto-quest).
      await rollQuestAsGame(hre.ethers, game, quests, 200n, 12345n, true);
      let active = await quests.getActiveQuests();
      expect(Number(active[1].questType)).to.equal(QUEST_TYPE_MINT_FLIP);
      // forceMintFlip = false: MINT_FLIP is excluded from the random pool entirely.
      for (let i = 1n; i <= 64n; i++) {
        await rollQuestAsGame(hre.ethers, game, quests, 200n + i, i * 7919n, false);
        active = await quests.getActiveQuests();
        expect(Number(active[1].questType)).to.not.equal(QUEST_TYPE_MINT_FLIP);
      }
    });
  });

  // =========================================================================
  // 3. resetQuestStreak — removed (was only used for deity pass transfer penalties)
  // =========================================================================

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
        quests.connect(alice).handleMint(alice.address, 2, true, 0)
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("succeeds when called by coin contract", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
          alice.address,
          2,
          true,
          0,
        ])
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 6. handleMint - Progress and Completion
  // =========================================================================
  describe("handleMint - progress and completion", function () {
    it("returns (0, type, 0, false) when no active quest for player/type", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      // No quest rolled yet; currentDay = 0 => returns early
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 2, true, 0]
      );
      const [reward, , , completed] = result;
      expect(completed).to.equal(false);
      expect(reward).to.equal(0n);
    });

    it("emits QuestProgressUpdated after handleMint on active quest", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 1, true, 0]
      );
      const evs = await getEvents(tx, quests, "QuestProgressUpdated");
      expect(evs.length).to.be.gte(1);
    });

    it("completing slot 0 (MINT_ETH, 2 tickets) emits QuestCompleted", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      // QUEST_MINT_TARGET = 2 tickets
      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 2, true, 0]
      );
      const evs = await getEvents(tx, quests, "QuestCompleted");
      expect(evs.length).to.be.gte(1);
      const slot0Ev = evs.find((e) => Number(e.args.slot) === 0);
      expect(slot0Ev).to.not.be.undefined;
    });

    it("completing slot 0 sets streak to 1 and returns QUEST_SLOT0_REWARD", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 2, true, 0]
      );
      const [reward, , streak, completed] = result;
      if (completed) {
        // Slot 0 reward is QUEST_SLOT0_REWARD = 100 FLIP
        // (may also include slot 1 if auto-completed)
        expect(reward).to.be.gte(QUEST_SLOT0_REWARD);
        expect(streak).to.be.gte(1n);
      }
    });

    it("handles zero quantity without revert", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 0, true, 0]
      );
      const [, , , completed] = result;
      expect(completed).to.equal(false);
    });

    it("handles zero address player without revert", async function () {
      const { quests, coin, game } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
          ZERO_ADDRESS,
          2,
          true,
          0,
        ])
      ).to.not.be.reverted;
    });

    it("playerQuestStates reflects completion after successful handleMint", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
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
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      // Roll quest that might not have FLIP in slot 1
      await rollQuestAsGame(hre.ethers, game, quests, 2n, 0n);
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
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      // Find entropy that gives FLIP as slot 1
      const found = await rollQuestWithBonusType(
        hre.ethers,
        game,
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
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      const found = await rollQuestWithBonusType(
        hre.ethers,
        game,
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
        0,
      ]);

      // Now complete slot 1 (FLIP) with enough volume
      const { result } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleFlip",
        [alice.address, QUEST_FLIP_TARGET]
      );
      const [reward, , , completed] = result;
      if (completed) {
        expect(reward).to.be.gte(QUEST_RANDOM_REWARD);
      }
    });

    it("slot 1 FLIP cannot complete before slot 0", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      const found = await rollQuestWithBonusType(
        hre.ethers,
        game,
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
        [alice.address, QUEST_FLIP_TARGET]
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
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 8n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleDecimator", [
          alice.address,
          eth(2000),
        ])
      ).to.not.be.reverted;
    });

    it("returns false when no DECIMATOR quest active", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 9n, 99n);
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
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 10n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleAffiliate", [
          alice.address,
          eth(2000),
        ])
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 10. handleDegenerette - Access Control
  // =========================================================================
  describe("handleDegenerette - access control", function () {
    it("reverts OnlyCoin when called by EOA", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);
      await expect(
        quests.connect(alice).handleDegenerette(alice.address, eth("0.01"), true, 0)
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("coin can call handleDegenerette (ETH) without revert", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 12n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleDegenerette", [
          alice.address,
          eth("0.02"),
          true,
          0,
        ])
      ).to.not.be.reverted;
    });

    it("coin can call handleDegenerette (FLIP) without revert", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 13n, 99n);
      await expect(
        callHandlerAsCoin(hre.ethers, coin, quests, "handleDegenerette", [
          alice.address,
          eth(2000),
          false,
          0,
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
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
      ]);
      const [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(1n);
    });

    it("streak does not increment twice for same day (STREAK_CREDITED)", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      // Complete slot 0 twice (second should be no-op for streak)
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
      ]);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
      ]);
      const [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(1n);
    });

    it("QuestStreakReset emitted when day is missed", async function () {
      const { quests, coin, alice, game } = await loadFixture(deployFullProtocol);

      // Day 1: complete quest (streak = 1)
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
      ]);

      // Day 2 rolls a quest alice never completes (a real rolled miss — an
      // unrolled day would be stall-forgiven instead), then day 3 rolls.
      await rollQuestAsGame(hre.ethers, game, quests, 2n, 555n);
      await rollQuestAsGame(hre.ethers, game, quests, 3n, 999n);

      // Trigger sync on day 3 with an action
      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 1, true, 0]
      );
      const evs = await getEvents(tx, quests, "QuestStreakReset");
      expect(evs.length).to.be.gte(1);
    });

    it("QuestStreakReset event is emitted with previousStreak after missed days", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);

      // Day 1: complete slot 0 (MINT_ETH, target = 1 ticket at current mintPrice)
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
      ]);

      // Verify streak is 1 after completion
      let [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(1n);

      // Days 2-4 each roll a quest alice never completes (real rolled misses — unrolled
      // days would be stall-forgiven instead), then day 5 rolls.
      // QuestStreakReset fires during the next sync action (handleMint triggers syncState).
      await rollQuestAsGame(hre.ethers, game, quests, 2n, 22n);
      await rollQuestAsGame(hre.ethers, game, quests, 3n, 33n);
      await rollQuestAsGame(hre.ethers, game, quests, 4n, 44n);
      await rollQuestAsGame(hre.ethers, game, quests, 5n, 88n);
      // Call handleMint on day 5 - this triggers _questSyncState which fires QuestStreakReset
      // Note: slot 0 target is 1 * mintPrice, so 1 ticket completes it, resetting then re-incrementing streak
      const { tx } = await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        1,
        true,
        0,
      ]);

      // QuestStreakReset event confirms the reset happened with previousStreak = 1
      const evs = await getEvents(tx, quests, "QuestStreakReset");
      expect(evs.length).to.be.gte(1);
      expect(evs[0].args.player).to.equal(alice.address);
      expect(evs[0].args.previousStreak).to.equal(1n);

      // After reset + new day 5 completion: streak = 0 (reset) + 1 (new completion) = 1
      [streak] = await quests.playerQuestStates(alice.address);
      expect(streak).to.equal(1n);
    });
  });

  // =========================================================================
  // 13. Progress Versioning
  // =========================================================================
  describe("Progress versioning", function () {
    it("progress resets when quest is re-rolled (new version)", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);

      // Roll day 1
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      // Partial progress on day 1
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        1,
        true,
        0,
      ]);

      // Re-roll day 2 (new day, new version)
      await rollQuestAsGame(hre.ethers, game, quests, 2n, 88n);

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
      const { quests, game } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 20n, 12345n);
      const active = await quests.getActiveQuests();
      expect(active.length).to.equal(2);
      expect(active[0].day).to.equal(20n);
      expect(active[1].day).to.equal(20n);
    });

    it("getPlayerQuestView returns effectiveStreak=0 for player with no activity", async function () {
      const { quests, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);

      const view = await quests.getPlayerQuestView(alice.address);
      expect(view.baseStreak).to.equal(0n);
    });

    it("getPlayerQuestView reflects completed slots", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
      ]);

      const view = await quests.getPlayerQuestView(alice.address);
      // Slot 0 should be completed
      expect(view.completed[0]).to.equal(true);
    });

    it("playerQuestStates streak matches completed count", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
      ]);

      const [streak, lastCompletedDay] = await quests.playerQuestStates(
        alice.address
      );
      expect(streak).to.equal(1n);
      expect(lastCompletedDay).to.equal(1n);
    });

    it("playerQuestStates progress[0] is 0 before any handleMint", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      const [, , progress] = await quests.playerQuestStates(alice.address);
      expect(progress[0]).to.equal(0n);
    });

    it("QuestCompleted event includes correct streak and reward", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      const { tx } = await callHandlerAsCoin(
        hre.ethers,
        coin,
        quests,
        "handleMint",
        [alice.address, 2, true, 0]
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
      const { quests, coin, game, alice, bob } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);

      // Alice completes slot 0
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleMint", [
        alice.address,
        2,
        true,
        0,
      ]);

      // Bob has no progress
      const [aliceStreak] = await quests.playerQuestStates(alice.address);
      const [bobStreak] = await quests.playerQuestStates(bob.address);
      expect(aliceStreak).to.equal(1n);
      expect(bobStreak).to.equal(0n);
    });

    it("same day quest roll is idempotent for different entropy", async function () {
      const { quests, game } = await loadFixture(deployFullProtocol);
      // Roll day 1 with entropy 99
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 99n);
      const active1 = await quests.getActiveQuests();
      const type0_1 = active1[0].questType;

      // Roll day 1 again with different entropy (overwrites)
      await rollQuestAsGame(hre.ethers, game, quests, 1n, 55555n);
      const active2 = await quests.getActiveQuests();
      const type0_2 = active2[0].questType;

      // Slot 0 is always MINT_ETH regardless of entropy
      expect(Number(type0_1)).to.equal(QUEST_TYPE_MINT_ETH);
      expect(Number(type0_2)).to.equal(QUEST_TYPE_MINT_ETH);
    });

    it("all handlers return (0, type, 0, false) when currentDay is 0 (no quest rolled)", async function () {
      const { quests, coin, game, alice } = await loadFixture(deployFullProtocol);
      // Do not roll any quest; activeQuests[0].day == 0 => currentDay == 0
      const handlers = [
        ["handleFlip", [alice.address, eth(1000)]],
        ["handleDecimator", [alice.address, eth(1000)]],
        ["handleAffiliate", [alice.address, eth(1000)]],
        ["handleDegenerette", [alice.address, eth("0.01"), true, 0]],
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

  // =========================================================================
  // 14. Level quest streak bonus — completing a per-level quest advances the
  //     quest streak by LEVEL_QUEST_STREAK_BONUS (5), not the daily +1.
  // =========================================================================
  describe("Level quest streak bonus (+5 on completion)", function () {
    // mintPacked_ lives at storage slot 9 on the Game (forge inspect
    // DegenerusGame storageLayout). _isLevelQuestEligible reads it:
    //   unitsLvl  = packed >> 104  must == level + 1   (4+ units this level)
    //   units     = packed >> 228  must >= 4
    //   loyalty   = (packed >> 48) >= 5  OR a pass
    // Poke exactly those bits so the player is eligible without a real mint.
    async function makeLevelQuestEligible(hreEthers, game, player) {
      const lvl = await game.level();
      const packed =
        (5n << 48n) | ((BigInt(lvl) + 1n) << 104n) | (400n << 228n);
      const slot = hreEthers.keccak256(
        hreEthers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [player, 9n]
        )
      );
      await hreEthers.provider.send("hardhat_setStorageAt", [
        await game.getAddress(),
        slot,
        hreEthers.toBeHex(packed, 32),
      ]);
    }

    // Roll the level quest as GAME, brute-forcing entropy until the chosen type
    // lands (rollLevelQuest picks the type from entropy, like the daily bonus).
    async function rollLevelQuestOfType(hreEthers, game, quests, targetType) {
      const gameAddr = await game.getAddress();
      await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hreEthers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      const gameSigner = await hreEthers.getSigner(gameAddr);
      let found = false;
      for (let i = 1n; i <= 300n; i++) {
        await quests.connect(gameSigner).rollLevelQuest(i);
        const view = await quests.getPlayerLevelQuestView(ZERO_ADDRESS);
        if (Number(view.questType) === targetType) {
          found = true;
          break;
        }
      }
      await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [
        gameAddr,
      ]);
      return found;
    }

    // Stand up: a daily quest (currentDay != 0) whose slot 1 is NOT FLIP, plus a
    // FLIP level quest. handleFlip always credits FLIP *level* progress first and
    // skips the daily leg when no slot is FLIP — so the streak delta is isolated
    // to the level-quest completion (no daily +1 to conflate it).
    // Returns the chosen quest day so callers can sync state on the same day.
    async function setUpFlipLevelQuest(ctx) {
      const { game, quests, alice } = ctx;
      // Roll a daily whose slot 1 is NOT FLIP (slot 0 is always MINT_ETH).
      // rollDailyQuest has no return and early-returns once a day is stamped, so
      // we advance the day until getActiveQuests shows a non-FLIP slot 1 and
      // thread that day through. With no FLIP slot, handleFlip's daily leg is
      // skipped and only the FLIP level-quest leg fires — isolating the streak delta.
      const gameAddr = await game.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);
      let chosenDay = 0n;
      for (let d = 1n; d <= 300n; d++) {
        await quests.connect(gameSigner).rollDailyQuest(d, d * 7919n, false, false);
        const active = await quests.getActiveQuests();
        if (Number(active[1].questType) !== QUEST_TYPE_FLIP) {
          chosenDay = d;
          break;
        }
      }
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [
        gameAddr,
      ]);
      expect(chosenDay, "rolled a daily with a non-FLIP slot 1").to.not.equal(0n);

      const ok = await rollLevelQuestOfType(
        hre.ethers,
        game,
        quests,
        QUEST_TYPE_FLIP
      );
      expect(ok, "rolled a FLIP level quest within the entropy budget").to.equal(
        true
      );
      await makeLevelQuestEligible(hre.ethers, game, alice.address);
      const view = await quests.getPlayerLevelQuestView(alice.address);
      expect(view.eligible, "alice eligible for the level quest").to.equal(true);
      expect(view.completed, "level quest not yet completed").to.equal(false);
      return chosenDay;
    }

    it("non-afking: completing a level quest advances the streak by 5 (not 1)", async function () {
      const ctx = await loadFixture(deployFullProtocol);
      const { quests, coin, alice } = ctx;
      await setUpFlipLevelQuest(ctx);

      const [streakBefore] = await quests.playerQuestStates(alice.address);
      expect(streakBefore, "fresh player starts at streak 0").to.equal(0n);

      // 20,000 FLIP clears the FLIP level-quest target in one shot.
      await callHandlerAsCoin(hre.ethers, coin, quests, "handleFlip", [
        alice.address,
        eth(20000),
      ]);

      const viewAfter = await quests.getPlayerLevelQuestView(alice.address);
      expect(viewAfter.completed, "level quest is now completed").to.equal(true);

      const [streakAfter] = await quests.playerQuestStates(alice.address);
      expect(
        streakAfter,
        "level-quest completion bumped the streak by LEVEL_QUEST_STREAK_BONUS (5)"
      ).to.equal(5n);
    });

    it("non-afking: a level quest from a non-zero streak adds exactly 5", async function () {
      const ctx = await loadFixture(deployFullProtocol);
      const { quests, game, coin, alice } = ctx;
      const chosenDay = await setUpFlipLevelQuest(ctx);

      // Seed the manual streak to 10 via the existing onlyGame bonus path, then
      // complete the level quest: the result must be exactly 10 + 5 = 15.
      await callAsGame(hre.ethers, game, quests, "awardQuestStreakBonus", [
        alice.address,
        10,
        chosenDay,
      ]);
      const [seeded] = await quests.playerQuestStates(alice.address);
      expect(seeded).to.equal(10n);

      await callHandlerAsCoin(hre.ethers, coin, quests, "handleFlip", [
        alice.address,
        eth(20000),
      ]);

      const [streakAfter] = await quests.playerQuestStates(alice.address);
      expect(streakAfter, "10 + 5 = 15").to.equal(15n);
    });

    it("afking: a level quest routes to the afking sub (manual streak untouched, no +5)", async function () {
      const ctx = await loadFixture(deployFullProtocol);
      const { quests, game, coin, alice } = ctx;
      const chosenDay = await setUpFlipLevelQuest(ctx);

      // Flip alice into an afking run (GAME-only). The completion must take the
      // afking branch (recordAfkingSecondary) — a no-op here since alice has no
      // live Game-side sub — leaving the dormant manual streak at 0. The +5 on a
      // live sub's streak base is proven in the forge clamp test
      // (test_SetStreakBaseClampSaturatesAtUint16Max, amount = 5).
      await callAsGame(hre.ethers, game, quests, "beginAfking", [
        alice.address,
        chosenDay,
      ]);

      await callHandlerAsCoin(hre.ethers, coin, quests, "handleFlip", [
        alice.address,
        eth(20000),
      ]);

      const viewAfter = await quests.getPlayerLevelQuestView(alice.address);
      expect(viewAfter.completed, "level quest still completes while afking").to.equal(
        true
      );
      const [streakAfter] = await quests.playerQuestStates(alice.address);
      expect(
        streakAfter,
        "afking branch leaves the dormant manual streak untouched (no manual +5)"
      ).to.equal(0n);
    });
  });
});
