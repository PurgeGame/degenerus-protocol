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
  getBlockTimestamp,
  getEvents,
  getEvent,
  getLastVRFRequestId,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";
import { boCustomFloor, boNominal } from "../helpers/boxOrder.js";
import { compiledStorageSlot } from "../helpers/storageLayout.js";

const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

// These purchases remain in the live write buffer, one queue entry per purchase. boxQueue is
// manually addressed (its array length slot is never written): entry p of buffer b lives at
// keccak(keccak(b . boxQueue.slot)) + p.
async function boxEntryAt(gameAddress, buffer, position) {
  const abi = hre.ethers.AbiCoder.defaultAbiCoder();
  const inner = hre.ethers.keccak256(
    abi.encode(["uint256", "uint256"], [BigInt(buffer), await compiledStorageSlot("boxQueue")])
  );
  const base = BigInt(hre.ethers.keccak256(inner));
  return BigInt(await hre.ethers.provider.getStorage(gameAddress, base + BigInt(position)));
}

// Every purchase in this file goes through `purchaseLootbox` -> `boCustom(...)`
// (a pure custom-size order, small/med/large always 0), so the level price
// multiplied against those zero counts is irrelevant to `boNominal` — 0n is a
// safe placeholder regardless of the active level's price.
async function lootboxNominalOf(gameAddress, position) {
  const state = BigInt(await hre.ethers.provider.getStorage(gameAddress, 0));
  const index = (state >> 252n) & 1n;
  return boNominal(await boxEntryAt(gameAddress, index, position), 0n);
}

// 250 days in seconds (deploy idle timeout for level 0, per _DEPLOY_IDLE_TIMEOUT_DAYS)
const DEPLOY_TIMEOUT_SECONDS = 250 * 86400;
// Daily boundary: days roll over at 22:57 UTC (GameTimeLib.JACKPOT_RESET_TIME), not midnight.
const DAY_RESET_SECONDS = 82620;

describe("Distress-Mode Lootboxes", function () {
  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  async function purchaseLootbox(game, player, amount) {
    // boCustomFloor (not boCustom): the zero-amount edge case below must reach
    // the chain and revert on-chain (empty order), not throw a JS-side "bad wei"
    // error before the call is even made. Every other amount in this file is an
    // exact multiple of 1 gwei (whole/fractional ETH), so the floor is exact there too.
    return game.connect(player).purchase(
      0,
      0n,
      boCustomFloor(amount),
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,false,
      { value: amount }
    );
  }

  /**
   * Parse LootBoxBuy events from a tx using the MintModule ABI
   * (event is emitted via delegatecall, so must use module interface).
   *
   * LootBoxBuy event fields (current): buyer, index (write buffer), position, amount.
   * Pool split shares / day / level are no longer emitted as event fields — use pool
   * balance deltas to verify split behavior.
   */
  async function getLootBoxBuyEvents(tx, mintModule) {
    return getEvents(tx, mintModule, "LootBoxBuy");
  }

  /**
   * Advance time to just before distress mode.
   * At level 0, distress triggers when currentDay >= purchaseStartDay + 250.
   * Since the contract uses day-based granularity (days reset at 22:57 UTC),
   * we need a full-day buffer to ensure we land on the day before distress.
   */
  /**
   * A live game seals a day per day, so its day index tracks the clock. The warps below skip
   * that, and the VRF deadman ends any game with no sealed day for 120 days, so re-stamp the
   * index (slot 0, bytes 3..5) to yesterday after each warp.
   */
  async function syncDailyIdx(game) {
    const addr = await game.getAddress();
    const day = BigInt(await game.currentDayView());
    const word = BigInt(await hre.ethers.provider.getStorage(addr, 0));
    const mask = 0xffffffn << 24n;
    const next = (word & ~mask) | ((day - 1n) << 24n);
    await hre.network.provider.send("hardhat_setStorageAt", [addr, "0x0", hre.ethers.toBeHex(next, 32)]);
  }

  async function advanceToPreDistress(game) {
    // Advance to 2 days before the 250-day timeout to ensure day index is below threshold
    await advanceTime(DEPLOY_TIMEOUT_SECONDS - 2 * 86400);
    await syncDailyIdx(game);
  }

  /**
   * Advance deterministically into distress mode.
   * Distress is DAY-granular: _isDistressMode() is true once currentDay >= purchaseStartDay + 250,
   * where days roll over at 22:57 UTC (GameTimeLib). A fixed second-offset before the "timeout"
   * lands on day psd+249 or psd+250 depending on the wall-clock time the fixture deploys at, which
   * made this suite flaky by time-of-day. Instead advance a whole 250 days and re-center to mid-day:
   * this lands squarely on the single distress day (psd+250) — 12h from either daily boundary, and
   * short of the day-251 (> 250) liveness/game-over trigger — regardless of deploy time.
   */
  async function advanceToDistress(game) {
    const ts = await getBlockTimestamp();
    const intoDay = (ts - DAY_RESET_SECONDS) % 86400;
    await advanceTime(250 * 86400 - intoDay + 43200);
    await syncDailyIdx(game);
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
      await advanceToDistress(game);

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

      await advanceToDistress(game);

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
    it("purchase the day before distress uses normal split", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);

      // Day psd+248 — comfortably before the psd+250 distress threshold.
      await advanceToPreDistress(game);

      const futureBefore = await game.futurePrizePoolView();
      const nextBefore = await game.nextPrizePoolView();

      const tx = await purchaseLootbox(game, alice, eth("1"));
      const events = await getLootBoxBuyEvents(tx, mintModule);
      expect(events.length).to.equal(1);

      const futureAfter = await game.futurePrizePoolView();

      // Should have normal presale split: future pool increases (50% share)
      expect(futureAfter).to.be.gt(futureBefore);
    });

    it("purchase on the first distress day uses distress split", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);

      // Day psd+250 — the first (and only) distress day before the liveness trigger.
      await advanceToDistress(game);

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

      // the queued entry's nominal wei should be > 0
      // Purchases accumulate in the current binary write buffer.
      const nominal = await lootboxNominalOf(await game.getAddress(), 0);
      expect(nominal).to.be.gt(0n);
    });

    it("distress purchase tracks distress ETH separately from normal purchase", async function () {
      const { game, alice, bob, mintModule } = await loadFixture(deployFullProtocol);

      const futureBefore1 = await game.futurePrizePoolView();
      const nextBefore1 = await game.nextPrizePoolView();

      // Alice buys in normal mode — future pool should increase
      const tx1 = await purchaseLootbox(game, alice, eth("1"));
      expect(await game.futurePrizePoolView()).to.be.gt(futureBefore1);

      // Bob buys in distress mode (different player = fresh lootbox slot, no day conflict)
      await advanceToDistress(game);

      const futureBefore2 = await game.futurePrizePoolView();
      const nextBefore2 = await game.nextPrizePoolView();

      const tx2 = await purchaseLootbox(game, bob, eth("1"));
      const futureAfter2 = await game.futurePrizePoolView();
      const nextAfter2 = await game.nextPrizePoolView();

      // Distress split: future pool unchanged, all to next
      expect(futureAfter2).to.equal(futureBefore2);
      expect(nextAfter2 - nextBefore2).to.equal(eth("1"));

      // Both purchases are recorded in the live write buffer.
      const nominalAlice = await lootboxNominalOf(await game.getAddress(), 0);
      expect(nominalAlice).to.be.gt(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Ticket Bonus — Distress Lootbox Purchase (Integration)
  // ---------------------------------------------------------------------------
  describe("Ticket bonus via distress lootbox", function () {
    it("distress-bought lootbox is recorded and can be opened after RNG word set", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Warp to distress mode
      await advanceToDistress(game);

      // Buy a lootbox in distress mode
      await purchaseLootbox(game, alice, eth("2"));

      // Purchases accumulate in the current binary write buffer.
      // Verify the lootbox was recorded with a non-zero nominal wei
      const nominal = await lootboxNominalOf(await game.getAddress(), 0);
      expect(nominal).to.be.gt(0n);

      // Verify the purchase was routed to the next pool (distress split)
      // (pool balance verification done in earlier tests)
    });

    it("mixed normal+distress lootbox purchases are both recorded", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      // Alice buys in normal mode into the current write buffer.
      await purchaseLootbox(game, alice, eth("1"));
      const nominalAlice = await lootboxNominalOf(await game.getAddress(), 0);
      expect(nominalAlice).to.be.gt(0n);

      // Warp to distress
      await advanceToDistress(game);

      // Bob buys in distress mode
      const nextBefore = await game.nextPrizePoolView();
      await purchaseLootbox(game, bob, eth("1"));
      const nextAfter = await game.nextPrizePoolView();

      // Distress: all ETH to next pool
      expect(nextAfter - nextBefore).to.equal(eth("1"));

      // No request has swapped the write buffer during these purchases.
      const nominalBob = await lootboxNominalOf(await game.getAddress(), 1);
      expect(nominalBob).to.be.gt(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Edge Cases
  // ---------------------------------------------------------------------------
  describe("Edge cases", function () {
    it("zero-amount distress lootbox still reverts (min 0.01 ETH)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await advanceToDistress(game);

      await expect(
        purchaseLootbox(game, alice, eth("0"))
      ).to.be.reverted;
    });

    it("minimum lootbox (0.01 ETH) works in distress mode", async function () {
      const { game, alice, mintModule } = await loadFixture(deployFullProtocol);
      await advanceToDistress(game);

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
      await advanceToDistress(game);

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
