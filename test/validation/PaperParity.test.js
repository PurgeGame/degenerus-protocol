/**
 * Economic examples checked against deployed contracts and production libraries.
 * Literal-only arithmetic assertions were removed: they did not read production
 * constants and could stay green after the corresponding economics changed.
 * This suite checks the examples below, not every number in a historical paper.
 */

import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { eth, ZERO_ADDRESS, ZERO_BYTES32 } from "../helpers/testUtils.js";
import { boCustom } from "../helpers/boxOrder.js";

const { ethers } = hre;
const ZeroHash = ethers.ZeroHash;

// ---------------------------------------------------------------------------
// Shared fixture: deploys full protocol + PriceLookupTester
// ---------------------------------------------------------------------------

async function deployWithTester() {
  const protocol = await deployFullProtocol();

  const Tester = await hre.ethers.getContractFactory("PriceLookupTester");
  const priceTester = await Tester.deploy();
  await priceTester.waitForDeployment();

  return { ...protocol, priceTester };
}

// ---------------------------------------------------------------------------
// Test Suite
// ---------------------------------------------------------------------------

describe("Paper Parity (Phase 46)", function () {
  after(restoreAddresses);

  describe("PAR-01: PriceLookupLib price tiers", function () {
    // Expected prices for every tier boundary
    // Intro tiers (0-9)
    const introTierPrices = [
      // [level, expectedPriceEth]
      [0, "0.01"],
      [1, "0.01"],
      [4, "0.01"],
      [5, "0.02"],
      [6, "0.02"],
      [9, "0.02"],
    ];

    // First full cycle (10-99)
    const firstCyclePrices = [
      [10, "0.04"],
      [15, "0.04"],
      [29, "0.04"],
      [30, "0.08"],
      [45, "0.08"],
      [59, "0.08"],
      [60, "0.12"],
      [75, "0.12"],
      [89, "0.12"],
      [90, "0.16"],
      [95, "0.16"],
      [99, "0.16"],
    ];

    // Cyclic levels (100+)
    const cyclicPrices = [
      [100, "0.24"], // Milestone
      [101, "0.04"],
      [115, "0.04"],
      [129, "0.04"],
      [130, "0.08"],
      [145, "0.08"],
      [159, "0.08"],
      [160, "0.12"],
      [175, "0.12"],
      [189, "0.12"],
      [190, "0.16"],
      [195, "0.16"],
      [199, "0.16"],
      [200, "0.24"], // Milestone
      [201, "0.04"],
      [229, "0.04"],
      [230, "0.08"],
      [259, "0.08"],
      [260, "0.12"],
      [289, "0.12"],
      [290, "0.16"],
      [299, "0.16"],
      [300, "0.24"], // Milestone
    ];

    const allPrices = [
      ...introTierPrices,
      ...firstCyclePrices,
      ...cyclicPrices,
    ];

    for (const [level, expectedEth] of allPrices) {
      it(`level ${level} = ${expectedEth} ETH`, async function () {
        const { priceTester } = await loadFixture(deployWithTester);
        const price = await priceTester.priceForLevel(level);
        expect(price).to.equal(
          ethers.parseEther(expectedEth),
          `Price mismatch at level ${level}`
        );
      });
    }

    it("verifies price at level 0 matches purchaseInfo().priceWei", async function () {
      const { game, priceTester } = await loadFixture(deployWithTester);
      const info = await game.purchaseInfo();
      const contractPrice = info.priceWei;
      const testerPrice = await priceTester.priceForLevel(0);
      expect(contractPrice).to.equal(testerPrice);
    });
  });

  describe("PAR-02: Ticket cost formula costWei = (priceWei * qty) / 400", function () {
    it("1 full ticket (qty=400) costs exactly priceWei", async function () {
      const { game, alice } = await loadFixture(deployWithTester);
      const info = await game.purchaseInfo();
      const priceWei = info.priceWei;

      // 1 full ticket = qty 400 (4 entries, each scaled by 100)
      const qty = 400;
      const expectedCost = (priceWei * BigInt(qty)) / 400n;
      expect(expectedCost).to.equal(priceWei);

      // Actually purchase to verify contract accepts exact amount
      const nextBefore = await game.nextPrizePoolView();
      const futureBefore = await game.futurePrizePoolView();
      await game
        .connect(alice)
        .purchase(0, qty, 0, ZeroHash, 0,false,  { value: expectedCost });

      // Verify pools received funds (90/10 split)
      const nextAfter = await game.nextPrizePoolView();
      const futureAfter = await game.futurePrizePoolView();
      expect(nextAfter + futureAfter).to.be.gt(nextBefore + futureBefore);
    });

    it("1 entry (qty=100) costs priceWei/4", async function () {
      const { game, alice } = await loadFixture(deployWithTester);
      const info = await game.purchaseInfo();
      const priceWei = info.priceWei;

      const qty = 100;
      const expectedCost = (priceWei * BigInt(qty)) / 400n;
      expect(expectedCost).to.equal(priceWei / 4n);

      await game
        .connect(alice)
        .purchase(0, qty, 0, ZeroHash, 0,false,  { value: expectedCost });
    });

    it("10 full tickets (qty=4000) costs 10 * priceWei", async function () {
      const { game, alice } = await loadFixture(deployWithTester);
      const info = await game.purchaseInfo();
      const priceWei = info.priceWei;

      const qty = 4000;
      const expectedCost = (priceWei * BigInt(qty)) / 400n;
      expect(expectedCost).to.equal(priceWei * 10n);

      await game
        .connect(alice)
        .purchase(0, qty, 0, ZeroHash, 0,false,  { value: expectedCost });
    });
  });

  describe("PAR-03: Prize pool split BPS", function () {
    it("ticket purchase: 90% next pool, 10% future pool", async function () {
      const { game, alice } = await loadFixture(deployWithTester);
      const info = await game.purchaseInfo();
      const priceWei = info.priceWei;

      const nextBefore = await game.nextPrizePoolView();
      const futureBefore = await game.futurePrizePoolView();

      const qty = 400;
      const costWei = priceWei;
      await game
        .connect(alice)
        .purchase(0, qty, 0, ZeroHash, 0,false,  { value: costWei });

      const nextDelta = (await game.nextPrizePoolView()) - nextBefore;
      const futureDelta =
        (await game.futurePrizePoolView()) - futureBefore;
      const total = nextDelta + futureDelta;

      // 10% to future: PURCHASE_TO_FUTURE_BPS = 1000 (10%)
      const expectedFuture = (costWei * 1000n) / 10000n;
      const expectedNext = costWei - expectedFuture;

      expect(futureDelta).to.equal(expectedFuture, "Future share should be 10%");
      expect(nextDelta).to.equal(expectedNext, "Next share should be 90%");
    });

    it("lootbox: 90% future, 10% next (presale and after)", async function () {
      // MintModule constants: LOOTBOX_SPLIT_FUTURE_BPS = 9000, LOOTBOX_SPLIT_NEXT_BPS = 1000.
      // Rake-free: ALL lootbox ETH (presale and after) routes 100% to the pools at 90/10
      // future/next. There is no presale-specific split and no vault diversion.
      const { game, alice } = await loadFixture(deployWithTester);

      const nextBefore = await game.nextPrizePoolView();
      const futureBefore = await game.futurePrizePoolView();

      // Lootbox minimum is 0.01 ETH
      const lootboxAmount = ethers.parseEther("0.01");

      await game
        .connect(alice)
        .purchase(0, 0, boCustom(lootboxAmount), ZeroHash, 0,false,  {
          value: lootboxAmount,
        });

      const nextDelta = (await game.nextPrizePoolView()) - nextBefore;
      const futureDelta =
        (await game.futurePrizePoolView()) - futureBefore;

      const expectedFuture = (lootboxAmount * 9000n) / 10000n;
      const expectedNext = (lootboxAmount * 1000n) / 10000n;
      expect(futureDelta).to.equal(expectedFuture, "Lootbox future share should be 90%");
      expect(nextDelta).to.equal(expectedNext, "Lootbox next share should be 10%");
      expect(nextDelta + futureDelta).to.equal(lootboxAmount, "100% to pools, rake-free");
    });

  });

  describe("PAR-06: Activity score components and caps", function () {

    it("contract returns 0 for zero-address player", async function () {
      const { game } = await loadFixture(deployWithTester);
      const [score] = await game.playerActivityScore(ZERO_ADDRESS); // (scorePoints, walletId)
      expect(score).to.equal(0);
    });

    it("on-chain: whale bundle holder gets floor bonuses via playerActivityScore()", async function () {
      // After purchasing a whale bundle, alice gets (playerActivityScore returns whole POINTS):
      //   streakPoints floored to 50 (PASS_STREAK_FLOOR_POINTS)
      //   mintCountPoints floored to 25 (PASS_MINT_COUNT_FLOOR_POINTS)
      //   questStreak = 0
      //   affiliateBonus = 0 (currLevel == 0)
      //   whale pass bonus (bundleType == 3, 100-level bundle) -> +40 points
      //   Total: 50 + 25 + 0 + 0 + 40 = 115 points
      //
      // Note: purchaseWhalePass always sets bundleType=3 (100-level bundle type)
      // because the whale bundle covers 100 levels. The 10-level type (bundleType=1)
      // is set by lazy pass / activate10LevelPass, not whale bundles.
      const { game, alice } = await loadFixture(deployWithTester);

      // Before purchase: score should be 0
      const [scoreBefore] = await game.playerActivityScore(alice.address);
      expect(scoreBefore).to.equal(0, "No activity before purchase");

      // Purchase whale bundle (100-level, bundleType=3)
      await game
        .connect(alice)
        .purchaseWhalePass(0, 1, hre.ethers.ZeroHash, {
          value: ethers.parseEther("2.4"),
        });

      // After purchase: score should reflect pass floor bonuses + whale bonus
      const [scoreAfter] = await game.playerActivityScore(alice.address);
      expect(scoreAfter).to.equal(
        115,
        "Whale bundle holder: 50 streak floor + 25 count floor + 40 whale(100-lvl) bonus = 115 points"
      );
    });
  });

  describe("PAR-10: Whale bundle pricing", function () {
    it("early price (levels 0-3): 2.4 ETH", async function () {
      // WHALE_BUNDLE_EARLY_PRICE = 2.4 ether
      const { game, alice } = await loadFixture(deployWithTester);

      // At level 0, passLevel = 1 (<=4), so early price applies
      const expectedPrice = ethers.parseEther("2.4");

      // Verify by purchasing -- will revert if price is wrong
      await game
        .connect(alice)
        .purchaseWhalePass(0, 1, hre.ethers.ZeroHash, {
          value: expectedPrice,
        });
    });

  });

  describe("PAR-11: Lazy pass pricing", function () {
    it("flat 0.24 ETH at levels 0-2", async function () {
      // At level 0-2: benefitValue = 0.24 ether, totalPrice = 0.24 ether (no boon)
      const { game, alice } = await loadFixture(deployWithTester);

      const expectedPrice = ethers.parseEther("0.24");
      await game
        .connect(alice)
        .purchaseLazyPass(0, hre.ethers.ZeroHash, { value: expectedPrice });
    });

    it("sum-of-10-level-prices at level 3+ (via PriceLookupTester)", async function () {
      const { priceTester } = await loadFixture(deployWithTester);

      // Level 3 startLevel = 4: sum of prices for levels 4-13
      // Levels 4: 0.01, 5-9: 0.02*5=0.10, 10-13: 0.04*4=0.16
      // Total: 0.01 + 0.10 + 0.16 = 0.27 ETH
      const cost = await priceTester.lazyPassCost(4);
      const expected =
        ethers.parseEther("0.01") + // level 4
        ethers.parseEther("0.02") * 5n + // levels 5-9
        ethers.parseEther("0.04") * 4n; // levels 10-13
      expect(cost).to.equal(expected);
    });

    it("lazy pass cost at various starting levels", async function () {
      const { priceTester } = await loadFixture(deployWithTester);

      // startLevel 1: levels 1-10
      // 1-4: 0.01*4, 5-9: 0.02*5, 10: 0.04*1
      const cost1 = await priceTester.lazyPassCost(1);
      const expected1 =
        ethers.parseEther("0.01") * 4n +
        ethers.parseEther("0.02") * 5n +
        ethers.parseEther("0.04") * 1n;
      expect(cost1).to.equal(expected1, "Lazy pass cost starting at level 1");

      // startLevel 90: levels 90-99
      // All 0.16 ETH
      const cost90 = await priceTester.lazyPassCost(90);
      expect(cost90).to.equal(
        ethers.parseEther("0.16") * 10n,
        "Lazy pass cost starting at level 90"
      );

      // startLevel 95: levels 95-104
      // 95-99: 0.16*5, 100: 0.24, 101-104: 0.04*4
      const cost95 = await priceTester.lazyPassCost(95);
      const expected95 =
        ethers.parseEther("0.16") * 5n +
        ethers.parseEther("0.24") * 1n +
        ethers.parseEther("0.04") * 4n;
      expect(cost95).to.equal(expected95, "Lazy pass cost starting at level 95");
    });
  });

  describe("PAR-12: Deity pass T(n) pricing (24 + k*(k+1)/2 ETH)", function () {
    it("first deity pass (k=0): 24 ETH", async function () {
      const { game, alice } = await loadFixture(deployWithTester);

      // basePrice = DEITY_PASS_BASE + (k * (k+1) * 1 ether) / 2
      // k=0: 24 + 0 = 24 ETH
      const expectedPrice = ethers.parseEther("24");
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, { value: expectedPrice });
    });

    it("second deity pass (k=1): 25 ETH", async function () {
      const { game, alice, bob } = await loadFixture(deployWithTester);

      // Buy first pass
      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, {
          value: ethers.parseEther("24"),
        });

      // k=1: 24 + (1*2/2) = 24 + 1 = 25 ETH
      const expectedPrice = ethers.parseEther("25");
      await game
        .connect(bob)
        .purchaseDeityPass(0, 1, hre.ethers.ZeroHash, { value: expectedPrice });
    });

    it("third deity pass (k=2): 27 ETH", async function () {
      const { game, alice, bob, carol } =
        await loadFixture(deployWithTester);

      await game
        .connect(alice)
        .purchaseDeityPass(0, 4, hre.ethers.ZeroHash, {
          value: ethers.parseEther("24"),
        });
      await game
        .connect(bob)
        .purchaseDeityPass(0, 1, hre.ethers.ZeroHash, {
          value: ethers.parseEther("25"),
        });

      // k=2: 24 + (2*3/2) = 24 + 3 = 27 ETH
      const expectedPrice = ethers.parseEther("27");
      await game
        .connect(carol)
        .purchaseDeityPass(0, 2, hre.ethers.ZeroHash, { value: expectedPrice });
    });

  });

  describe("PAR-16: Degenerette base payouts and ROI curve", function () {
    let math;
    before(async function () {
      math = await (await ethers.getContractFactory("DegeneretteMathHarness")).deploy();
    });

    it("shared base payouts match the documented score table", async function () {
      const centiX = [0, 0, 0, 50, 300, 1000, 10000, 62500, 1817328, 23000000];
      for (let score = 0; score < centiX.length; score++) {
        expect(await math.base(score)).to.equal(centiX[score], `score ${score}`);
      }
    });

    it("ordinary matches score 8; a matching wild raises the score and payout multiplier", async function () {
      const [ordinaryScore, ordinaryWilds] = await math.score(0, 0);
      expect(ordinaryScore).to.equal(8);
      expect(ordinaryWilds).to.equal(0);
      const [score, wilds] = await math.score(0x40, 0x40);
      expect(score).to.equal(9);
      expect(wilds).to.equal(1);
      expect(await math.base(score)).to.equal(23000000);
      // 1,000 whole FLIP at maximum ordinary activity, with one result wild.
      expect(await math.payout(score, wilds, 1, 1000n, 30000)).to.equal(287212500n);
    });

    it("activity curve retains the 90 / 98.91 / 99.7 / 99.9% knees", async function () {
      for (const [score, bps] of [[0, 9000], [305, 9891], [500, 9970], [30000, 9990], [65535, 9990]]) {
        expect(await math.roi(score)).to.equal(bps);
      }
    });
  });

  describe("PAR-17: Pass capital injection splits", function () {

    it("whale bundle at level 0 actually splits 30/70", async function () {
      const { game, alice } = await loadFixture(deployWithTester);

      const nextBefore = await game.nextPrizePoolView();
      const futureBefore = await game.futurePrizePoolView();

      const price = ethers.parseEther("2.4");
      await game
        .connect(alice)
        .purchaseWhalePass(0, 1, hre.ethers.ZeroHash, { value: price });

      const nextDelta = (await game.nextPrizePoolView()) - nextBefore;
      const futureDelta =
        (await game.futurePrizePoolView()) - futureBefore;

      const expectedNext = (price * 3000n) / 10000n;
      const expectedFuture = price - expectedNext;

      expect(nextDelta).to.equal(expectedNext, "Whale L0 next = 30%");
      expect(futureDelta).to.equal(
        expectedFuture,
        "Whale L0 future = 70%"
      );
    });
  });

  describe("Cross-cutting formula consistency", function () {

    it("price table is monotonically non-decreasing", async function () {
      const { priceTester } = await loadFixture(deployWithTester);

      let prevPrice = 0n;
      // Check levels 0-300
      for (let lvl = 0; lvl <= 300; lvl++) {
        const price = await priceTester.priceForLevel(lvl);
        // Within a cycle, prices should not decrease EXCEPT after milestone
        // levels (e.g., 100 -> 101 goes from 0.24 to 0.04)
        if (lvl > 0 && lvl % 100 !== 1 && lvl !== 10) {
          expect(price).to.be.gte(
            prevPrice,
            `Price decreased at level ${lvl}: ${prevPrice} -> ${price}`
          );
        }
        prevPrice = price;
      }
    });

  });
});
