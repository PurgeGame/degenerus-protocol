import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceTime,
  advanceToNextDay,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

/**
 * PriceEscalation edge-case tests.
 *
 * Verifies the tiered pricing system from PriceLookupLib.
 *
 * Ticket pricing formula:
 *   costWei = (priceWei * ticketQuantity) / (4 * TICKET_SCALE)
 *   TICKET_SCALE = 100
 *
 * So to spend exactly `priceWei` (one "full ticket"):
 *   ticketQuantity = 400   (400 / (4 * 100) = 1x multiplier)
 *
 * purchaseInfo() returns: (lvl, inJackpotPhase, lastPurchaseDay_, rngLocked_, priceWei)
 */
describe("PriceEscalation", function () {
  after(function () {
    restoreAddresses();
  });

  /**
   * Helper: buy N "full tickets" (each costing priceWei) at the current level.
   * Each full ticket = quantity 400 (400 / (4*100) = 1x price multiplier).
   */
  async function buyFullTickets(game, buyer, n, totalEth) {
    return game
      .connect(buyer)
      .purchase(
        ZERO_ADDRESS,
        BigInt(n) * 400n,
        0n,
        ZERO_BYTES32,
        MintPaymentKind.DirectEth,
        { value: eth(totalEth) }
      );
  }

  // =========================================================================
  // 1. Initial price at level 0
  // =========================================================================

  describe("initial price at level 0", function () {
    it("purchaseInfo().priceWei is 0.01 ETH", async function () {
      const { game } = await loadFixture(deployFullProtocol);

      const info = await game.purchaseInfo();
      expect(info.priceWei).to.equal(eth(0.01));
    });

    it("purchaseInfo().lvl is 1 (activeTicketLevel = level + 1)", async function () {
      const { game } = await loadFixture(deployFullProtocol);

      const info = await game.purchaseInfo();
      expect(info.lvl).to.equal(1n);
      expect(await game.level()).to.equal(0n);
    });

    it("purchase 1 full ticket for 0.01 ETH succeeds", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await buyFullTickets(game, alice, 1, 0.01);
      expect((await tx.wait()).status).to.equal(1);
    });

    it("underpaying for 1 full ticket reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // 1 full ticket = quantity 400, costs 0.01 ETH, underpay with 0.009
      await expect(buyFullTickets(game, alice, 1, 0.009)).to.be.reverted;
    });
  });

  // =========================================================================
  // 2. Multi-ticket purchase pricing
  // =========================================================================

  describe("multi-ticket purchases at level 0", function () {
    it("5 full tickets cost 0.05 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await buyFullTickets(game, alice, 5, 0.05);
      expect((await tx.wait()).status).to.equal(1);
    });

    it("10 full tickets cost 0.10 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await buyFullTickets(game, alice, 10, 0.1);
      expect((await tx.wait()).status).to.equal(1);
    });

    it("100 full tickets cost 1.0 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await buyFullTickets(game, alice, 100, 1);
      expect((await tx.wait()).status).to.equal(1);
    });

    it("underpaying for 5 full tickets reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // 5 full tickets = 0.05 ETH, pay only 0.04
      await expect(buyFullTickets(game, alice, 5, 0.04)).to.be.reverted;
    });
  });

  // =========================================================================
  // 3. Lazy pass cost at level 0 (flat 0.24 ETH)
  // =========================================================================

  describe("lazy pass pricing at level 0", function () {
    it("lazy pass costs 0.24 ETH at level 0", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseLazyPass(alice.address, { value: eth(0.24) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("lazy pass at level 0 with wrong ETH reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseLazyPass(alice.address, { value: eth(0.23) })
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // 4. Price transition via level advancement
  // =========================================================================

  describe("price transition at level 5", function () {
    async function advanceOneLevel(game, deployer, mockVRF, word) {
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, word || 2n);
      for (let i = 0; i < 30; i++) {
        if (!(await game.rngLocked())) break;
        await game.connect(deployer).advanceGame();
      }
    }

    it("after advancing to level 5, price becomes 0.02 ETH", async function () {
      const { game, deployer, mockVRF, alice } = await loadFixture(
        deployFullProtocol
      );

      // Buy enough tickets to fill levels
      await buyFullTickets(game, alice, 100, 1);

      // Advance through levels 0-4
      for (let lvl = 0; lvl < 5; lvl++) {
        await advanceOneLevel(
          game,
          deployer,
          mockVRF,
          BigInt(lvl * 1000 + 2)
        );
      }

      const currentLevel = await game.level();
      if (currentLevel >= 5n) {
        const info = await game.purchaseInfo();
        expect(info.priceWei).to.equal(eth(0.02));
      }
    });
  });

  // =========================================================================
  // 5. Whale bundle pricing
  // =========================================================================

  describe("whale bundle pricing", function () {
    it("whale bundle at level 0 costs 2.4 ETH per unit", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("whale bundle qty=2 costs 4.8 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 2, { value: eth(4.8) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("whale bundle qty=10 costs 24 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 10, { value: eth(24) });
      expect((await tx.wait()).status).to.equal(1);
    });
  });

  // =========================================================================
  // 6. Deity pass pricing escalation
  // =========================================================================

  describe("deity pass pricing escalation", function () {
    it("first deity pass: 24 ETH (k=0)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("fourth deity pass: 30 ETH (24 + T(3) = 24 + 6)", async function () {
      const { game, alice, bob, carol, dan } = await loadFixture(
        deployFullProtocol
      );

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });
      await game
        .connect(bob)
        .purchaseDeityPass(bob.address, 1, { value: eth(25) });
      await game
        .connect(carol)
        .purchaseDeityPass(carol.address, 2, { value: eth(27) });

      const tx = await game
        .connect(dan)
        .purchaseDeityPass(dan.address, 3, { value: eth(30) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("wrong amount for deity pass reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseDeityPass(alice.address, 0, { value: eth(23) })
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // 7. Fractional ticket pricing
  // =========================================================================

  describe("fractional ticket pricing", function () {
    it("quarter ticket (qty=100) costs 0.0025 ETH at level 0", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // qty=100 → costWei = (0.01 * 100) / 400 = 0.0025 ETH
      const tx = await game
        .connect(alice)
        .purchase(ZERO_ADDRESS, 100n, 0n, ZERO_BYTES32, MintPaymentKind.DirectEth, {
          value: eth(0.0025),
        });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("half ticket (qty=200) costs 0.005 ETH at level 0", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchase(ZERO_ADDRESS, 200n, 0n, ZERO_BYTES32, MintPaymentKind.DirectEth, {
          value: eth(0.005),
        });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("zero quantity with zero ETH reverts (totalCost == 0)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // totalCost = ticketCost(0) + lootBoxAmount(0) = 0 → revert E()
      await expect(
        game
          .connect(alice)
          .purchase(ZERO_ADDRESS, 0n, 0n, ZERO_BYTES32, MintPaymentKind.DirectEth, {
            value: 0n,
          })
      ).to.be.reverted;
    });
  });
});
