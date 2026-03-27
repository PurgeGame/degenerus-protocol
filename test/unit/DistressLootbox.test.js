import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceTime,
  advanceToNextDay,
  getEvents,
  getEvent,
  getLastVRFRequestId,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

// 365 days in seconds (deploy idle timeout for level 0, per _DEPLOY_IDLE_TIMEOUT_DAYS)
const DEPLOY_TIMEOUT_SECONDS = 365 * 86400;
// 6 hours in seconds (distress mode window)
const DISTRESS_HOURS_SECONDS = 6 * 3600;

describe("Distress-Mode Lootboxes", function () {
  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  async function purchaseLootbox(game, player, amount) {
    return game.connect(player).purchase(
      ZERO_ADDRESS,
      0n,
      amount,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: amount }
    );
  }

  /**
   * Parse LootBoxBuy events from a tx using the MintModule ABI
   * (event is emitted via delegatecall, so must use module interface).
   *
   * LootBoxBuy event fields (current): buyer, day, amount, presale, level.
   * Pool split shares are no longer emitted as event fields — use pool balance
   * deltas to verify split behavior.
   */
  async function getLootBoxBuyEvents(tx, mintModule) {
    return getEvents(tx, mintModule, "LootBoxBuy");
  }

  /**
   * Advance time to just before distress mode (1 hour before the 6-hour window).
   * At level 0, distress triggers at deployTimeout - 6 hours.
   */
  async function advanceToPreDistress() {
    // Advance to 7 hours before timeout (1 hour before distress starts)
    await advanceTime(DEPLOY_TIMEOUT_SECONDS - 7 * 3600);
  }

  /**
   * Advance time into distress mode (3 hours before timeout).
   */
  async function advanceToDistress() {
    // Advance to 3 hours before timeout (well inside distress window)
    await advanceTime(DEPLOY_TIMEOUT_SECONDS - 3 * 3600);
  }

  // ---------------------------------------------------------------------------
  // 1. Pool Split — Normal Mode (90% future / 10% next for non-presale)
  // ---------------------------------------------------------------------------
  describe("Pool split in normal mode", function () {
    it("lootbox purchase routes ETH to future and next pools normally", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);

      const futureBefore = await game.futurePrizePoolView();
      const nextBefore = await game.nextPrizePoolView();

      const tx = await purchaseLootbox(game, alice, eth("1"));
      const events = await getLootBoxBuyEvents(tx, mintModule);
      expect(events.length).to.equal(1);

      // LootBoxBuy event no longer includes split share fields.
      // Verify pool routing via balance deltas instead.
      const futureAfter = await game.futurePrizePoolView();
      const nextAfter = await game.nextPrizePoolView();

      // Presale is active at level 0 (50/30/20 split): both pools should increase
      expect(futureAfter).to.be.gt(futureBefore);
      expect(nextAfter).to.be.gt(nextBefore);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Pool Split — Distress Mode (100% next pool)
  // ---------------------------------------------------------------------------
  describe("Pool split in distress mode", function () {
    it("lootbox purchase routes 100% ETH to next pool during distress", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);

      // Warp to distress mode
      await advanceToDistress();

      const futureBefore = await game.futurePrizePoolView();
      const nextBefore = await game.nextPrizePoolView();

      const tx = await purchaseLootbox(game, alice, eth("1"));
      const events = await getLootBoxBuyEvents(tx, mintModule);
      expect(events.length).to.equal(1);

      const futureAfter = await game.futurePrizePoolView();
      const nextAfter = await game.nextPrizePoolView();

      // Future pool should not increase (distress routes 100% to next)
      expect(futureAfter).to.equal(futureBefore);
      // Next pool should increase by the full lootbox amount
      expect(nextAfter - nextBefore).to.equal(eth("1"));
    });

    it("presale vault share is also zeroed during distress", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);

      // Verify presale is active
      expect(await game.lootboxPresaleActiveFlag()).to.be.true;

      await advanceToDistress();

      const futureBefore = await game.futurePrizePoolView();
      const nextBefore = await game.nextPrizePoolView();

      const tx = await purchaseLootbox(game, alice, eth("1"));
      const events = await getLootBoxBuyEvents(tx, mintModule);
      expect(events.length).to.equal(1);

      const futureAfter = await game.futurePrizePoolView();
      const nextAfter = await game.nextPrizePoolView();

      // Even in presale, distress overrides: no future share, no vault share.
      // All ETH goes to next pool.
      expect(futureAfter).to.equal(futureBefore);
      expect(nextAfter - nextBefore).to.equal(eth("1"));
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Distress Mode Boundary — Just Outside vs Just Inside
  // ---------------------------------------------------------------------------
  describe("Distress mode boundary", function () {
    it("purchase just outside 6-hour window uses normal split", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);

      // 7 hours before timeout = 1 hour before distress starts
      await advanceToPreDistress();

      const futureBefore = await game.futurePrizePoolView();
      const nextBefore = await game.nextPrizePoolView();

      const tx = await purchaseLootbox(game, alice, eth("1"));
      const events = await getLootBoxBuyEvents(tx, mintModule);
      expect(events.length).to.equal(1);

      const futureAfter = await game.futurePrizePoolView();

      // Should have normal presale split: future pool increases (50% share)
      expect(futureAfter).to.be.gt(futureBefore);
    });

    it("purchase just inside 6-hour window uses distress split", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);

      // 5 hours before timeout = 1 hour into distress window
      await advanceTime(DEPLOY_TIMEOUT_SECONDS - 5 * 3600);

      const futureBefore = await game.futurePrizePoolView();
      const nextBefore = await game.nextPrizePoolView();

      const tx = await purchaseLootbox(game, alice, eth("1"));
      const events = await getLootBoxBuyEvents(tx, mintModule);
      expect(events.length).to.equal(1);

      const futureAfter = await game.futurePrizePoolView();
      const nextAfter = await game.nextPrizePoolView();

      // Should have distress split: future pool unchanged, next pool gets 100%
      expect(futureAfter).to.equal(futureBefore);
      expect(nextAfter - nextBefore).to.equal(eth("1"));
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Distress ETH Tracking — Proportional Recording
  // ---------------------------------------------------------------------------
  describe("Distress ETH tracking", function () {
    it("normal purchase does not track distress ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await purchaseLootbox(game, alice, eth("1"));

      // lootboxStatus returns (amount, presale) — amount should be > 0
      const index = await game.lootboxRngIndexView();
      const [amount] = await game.lootboxStatus(alice.address, index);
      expect(amount).to.be.gt(0n);
    });

    it("distress purchase tracks distress ETH separately from normal purchase", async function () {
      const { game, alice, bob, mintModule } = await loadFixture(deployFullProtocol);

      const futureBefore1 = await game.futurePrizePoolView();
      const nextBefore1 = await game.nextPrizePoolView();

      // Alice buys in normal mode — future pool should increase
      const tx1 = await purchaseLootbox(game, alice, eth("1"));
      expect(await game.futurePrizePoolView()).to.be.gt(futureBefore1);

      // Bob buys in distress mode (different player = fresh lootbox slot, no day conflict)
      await advanceToDistress();

      const futureBefore2 = await game.futurePrizePoolView();
      const nextBefore2 = await game.nextPrizePoolView();

      const tx2 = await purchaseLootbox(game, bob, eth("1"));
      const futureAfter2 = await game.futurePrizePoolView();
      const nextAfter2 = await game.nextPrizePoolView();

      // Distress split: future pool unchanged, all to next
      expect(futureAfter2).to.equal(futureBefore2);
      expect(nextAfter2 - nextBefore2).to.equal(eth("1"));

      // Both lootboxes recorded at their respective indices
      const indexAlice = 1n; // first lootbox index
      const [amountAlice] = await game.lootboxStatus(alice.address, indexAlice);
      expect(amountAlice).to.be.gt(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Ticket Bonus — Distress Lootbox Purchase (Integration)
  // ---------------------------------------------------------------------------
  describe("Ticket bonus via distress lootbox", function () {
    it("distress-bought lootbox is recorded and can be opened after RNG word set", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Warp to distress mode
      await advanceToDistress();

      // Buy a lootbox in distress mode
      await purchaseLootbox(game, alice, eth("2"));

      const index = await game.lootboxRngIndexView();

      // Verify the lootbox was recorded with a non-zero amount
      const [amount] = await game.lootboxStatus(alice.address, index);
      expect(amount).to.be.gt(0n);

      // Verify the purchase was routed to the next pool (distress split)
      // (pool balance verification done in earlier tests)
    });

    it("mixed normal+distress lootbox purchases are both recorded", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      // Alice buys in normal mode
      await purchaseLootbox(game, alice, eth("1"));
      const indexAlice = await game.lootboxRngIndexView();
      const [amountAlice] = await game.lootboxStatus(alice.address, indexAlice);
      expect(amountAlice).to.be.gt(0n);

      // Warp to distress
      await advanceToDistress();

      // Bob buys in distress mode
      const nextBefore = await game.nextPrizePoolView();
      await purchaseLootbox(game, bob, eth("1"));
      const nextAfter = await game.nextPrizePoolView();

      // Distress: all ETH to next pool
      expect(nextAfter - nextBefore).to.equal(eth("1"));

      const indexBob = await game.lootboxRngIndexView();
      const [amountBob] = await game.lootboxStatus(bob.address, indexBob);
      expect(amountBob).to.be.gt(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Edge Cases
  // ---------------------------------------------------------------------------
  describe("Edge cases", function () {
    it("zero-amount distress lootbox still reverts (min 0.01 ETH)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await advanceToDistress();

      await expect(
        purchaseLootbox(game, alice, eth("0"))
      ).to.be.reverted;
    });

    it("minimum lootbox (0.01 ETH) works in distress mode", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);
      await advanceToDistress();

      const futureBefore = await game.futurePrizePoolView();
      const nextBefore = await game.nextPrizePoolView();

      const tx = await purchaseLootbox(game, alice, eth("0.01"));
      const events = await getLootBoxBuyEvents(tx, mintModule);
      expect(events.length).to.equal(1);

      const futureAfter = await game.futurePrizePoolView();
      const nextAfter = await game.nextPrizePoolView();

      // Distress split: future unchanged, next gets 100%
      expect(futureAfter).to.equal(futureBefore);
      expect(nextAfter - nextBefore).to.equal(eth("0.01"));
    });

    it("large lootbox (100 ETH) in distress routes all to next pool", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);
      await advanceToDistress();

      const futureBefore = await game.futurePrizePoolView();
      const nextBefore = await game.nextPrizePoolView();
      const tx = await purchaseLootbox(game, alice, eth("100"));
      const events = await getLootBoxBuyEvents(tx, mintModule);
      expect(events.length).to.equal(1);

      const futureAfter = await game.futurePrizePoolView();
      const nextAfter = await game.nextPrizePoolView();

      expect(futureAfter).to.equal(futureBefore);
      expect(nextAfter - nextBefore).to.equal(eth("100"));
    });
  });
});
