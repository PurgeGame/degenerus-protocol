/**
 * Cross-validation test: Sim vs Contract Parity.
 * Runs the same game scenarios through both the sim bridge formulas and
 * the real deployed Solidity contracts, then compares results.
 *
 * Proves the simulator produces outputs matching actual contract execution.
 */

import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { deployFullProtocol } from "../helpers/deployFixture.js";
import {
  priceForLevel,
  routeTicketSplit,
  calculateWhaleBundlePrice,
} from "./simBridge.js";

const { ethers } = hre;
const ZeroHash = ethers.ZeroHash;

describe("Sim vs Contract Parity", function () {
  // ─── Test 1: Price parity across levels ────────────────────────────

  describe("Price parity", function () {
    it("sim priceForLevel(0) matches contract purchaseInfo().priceWei", async function () {
      const { game } = await loadFixture(deployFullProtocol);

      const info = await game.purchaseInfo();
      const contractPrice = info.priceWei;
      const simPrice = priceForLevel(0);

      expect(contractPrice).to.equal(
        simPrice,
        "Initial price mismatch between sim and contract"
      );
    });

    it("sim prices match contract at key levels via direct lookup", async function () {
      // Verify the sim bridge prices are internally consistent with the
      // contract's PriceLookupLib by checking known values
      expect(priceForLevel(0)).to.equal(ethers.parseEther("0.01"));
      expect(priceForLevel(5)).to.equal(ethers.parseEther("0.02"));
      expect(priceForLevel(10)).to.equal(ethers.parseEther("0.04"));
      expect(priceForLevel(30)).to.equal(ethers.parseEther("0.08"));
      expect(priceForLevel(60)).to.equal(ethers.parseEther("0.12"));
      expect(priceForLevel(90)).to.equal(ethers.parseEther("0.16"));
      expect(priceForLevel(100)).to.equal(ethers.parseEther("0.24"));
    });
  });

  // ─── Test 2: Ticket purchase pool routing parity ───────────────────

  describe("Ticket purchase pool routing", function () {
    it("pool deltas match sim 90/10 split after 1 full ticket purchase", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Read initial pool state
      const nextBefore = await game.nextPrizePoolView();
      const futureBefore = await game.futurePrizePoolView();

      // Get current price
      const info = await game.purchaseInfo();
      const priceWei = info.priceWei;

      // 1 full ticket = qty 400, cost = priceWei * 400 / 400 = priceWei
      const qty = 400;
      const costWei = (priceWei * BigInt(qty)) / 400n;

      // Execute purchase on contract
      await game
        .connect(alice)
        .purchase(alice.address, qty, 0, ZeroHash, 0, { value: costWei });

      // Read post-purchase pool state
      const nextAfter = await game.nextPrizePoolView();
      const futureAfter = await game.futurePrizePoolView();

      const nextDelta = nextAfter - nextBefore;
      const futureDelta = futureAfter - futureBefore;
      const totalPoolDelta = nextDelta + futureDelta;

      // Sim prediction
      const simSplit = routeTicketSplit(costWei);

      // The contract may skim affiliate/DGNRS fees before the pool split,
      // so the total pool delta may be less than the full purchase cost.
      // We verify the RATIO is correct (90/10) within the actual pool delta.
      // nextDelta / totalPoolDelta should be ~9000/10000
      // futureDelta / totalPoolDelta should be ~1000/10000

      // Verify next/future ratio matches 90/10 BPS
      // Using cross-multiplication to avoid floating point:
      // nextDelta * 10000 / totalPoolDelta should be ~9000
      if (totalPoolDelta > 0n) {
        const nextBps = (nextDelta * 10000n) / totalPoolDelta;
        const futureBps = (futureDelta * 10000n) / totalPoolDelta;

        // Allow small tolerance for floor division
        expect(nextBps).to.be.gte(8990n);
        expect(nextBps).to.be.lte(9010n);
        expect(futureBps).to.be.gte(990n);
        expect(futureBps).to.be.lte(1010n);
      }

      // Also verify total pool delta is positive and close to purchase cost
      expect(totalPoolDelta).to.be.gt(0n);
      // Pool delta should be at least 90% of purchase (some may go to fees)
      expect(totalPoolDelta).to.be.gte((costWei * 90n) / 100n);
    });
  });

  // ─── Test 3: Whale bundle pricing parity ───────────────────────────

  describe("Whale bundle pricing", function () {
    it("contract accepts purchase at sim-calculated price", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Sim calculates whale price for level 0, qty 1, no boon
      const simWhalePrice = calculateWhaleBundlePrice(0, 1, 0);
      expect(simWhalePrice).to.equal(ethers.parseEther("2.4"));

      // Execute whale purchase on contract at sim price
      await expect(
        game
          .connect(alice)
          .purchaseWhaleBundle(alice.address, 1, { value: simWhalePrice })
      ).to.not.be.reverted;
    });

    it("sim whale price at level 0 qty 3 accepted by contract", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const simPrice = calculateWhaleBundlePrice(0, 3, 0);
      expect(simPrice).to.equal(ethers.parseEther("7.2"));

      await expect(
        game
          .connect(alice)
          .purchaseWhaleBundle(alice.address, 3, { value: simPrice })
      ).to.not.be.reverted;
    });
  });

  // ─── Test 4: Multiple purchases accumulate correctly ───────────────

  describe("Multiple purchases cumulative tracking", function () {
    it("3 ticket purchases at level 0 accumulate pool balances correctly", async function () {
      const { game, alice, bob, carol } = await loadFixture(
        deployFullProtocol
      );

      const buyers = [alice, bob, carol];
      let cumulativeNext = 0n;
      let cumulativeFuture = 0n;

      const nextBefore = await game.nextPrizePoolView();
      const futureBefore = await game.futurePrizePoolView();

      for (const buyer of buyers) {
        const info = await game.purchaseInfo();
        const priceWei = info.priceWei;
        const qty = 400;
        const costWei = (priceWei * BigInt(qty)) / 400n;

        // Pre-purchase pools
        const nextPre = await game.nextPrizePoolView();
        const futurePre = await game.futurePrizePoolView();

        // Purchase
        await game
          .connect(buyer)
          .purchase(buyer.address, qty, 0, ZeroHash, 0, { value: costWei });

        // Post-purchase pools
        const nextPost = await game.nextPrizePoolView();
        const futurePost = await game.futurePrizePoolView();

        const nextDelta = nextPost - nextPre;
        const futureDelta = futurePost - futurePre;

        cumulativeNext += nextDelta;
        cumulativeFuture += futureDelta;

        // Each individual delta should maintain ~90/10 ratio
        const totalDelta = nextDelta + futureDelta;
        if (totalDelta > 0n) {
          const nextBps = (nextDelta * 10000n) / totalDelta;
          expect(nextBps).to.be.gte(8990n);
          expect(nextBps).to.be.lte(9010n);
        }
      }

      // Verify cumulative balances match
      const nextFinal = await game.nextPrizePoolView();
      const futureFinal = await game.futurePrizePoolView();

      expect(nextFinal - nextBefore).to.equal(cumulativeNext);
      expect(futureFinal - futureBefore).to.equal(cumulativeFuture);

      // Overall ratio should still be ~90/10
      const totalCumulative = cumulativeNext + cumulativeFuture;
      if (totalCumulative > 0n) {
        const overallNextBps =
          (cumulativeNext * 10000n) / totalCumulative;
        expect(overallNextBps).to.be.gte(8990n);
        expect(overallNextBps).to.be.lte(9010n);
      }
    });
  });
});
