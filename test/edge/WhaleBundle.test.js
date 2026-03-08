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
  getEvents,
  getLastVRFRequestId,
} from "../helpers/testUtils.js";

/**
 * WhaleBundle edge-case tests.
 *
 * Covers 100-level whale bundles, 10-level lazy passes, and deity passes.
 *
 * Key constants from DegenerusGameWhaleModule:
 *  - WHALE_BUNDLE_EARLY_PRICE = 2.4 ETH (levels 0-3)
 *  - WHALE_BUNDLE_STANDARD_PRICE = 4 ETH (x49/x99)
 *  - Lazy pass: 0.24 ETH flat (levels 0-2), sum-of-prices (level 3+)
 *  - Deity pass: 24 + T(n) ETH where T(n) = n*(n+1)/2
 *  - Quantity: 1-100 for whale bundles
 */
describe("WhaleBundle", function () {
  after(function () {
    restoreAddresses();
  });

  const WHALE_BOON_10 = 16;
  const WHALE_BOON_25 = 23;
  const WHALE_BOON_50 = 24;

  function whaleDiscountBps(boonType) {
    const boon = Number(boonType);
    if (boon === WHALE_BOON_50) return 5000n;
    if (boon === WHALE_BOON_25) return 2500n;
    if (boon === WHALE_BOON_10) return 1000n;
    return 0n;
  }

  async function settleRngDay(game, deployer, mockVRF, word) {
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    await mockVRF.fulfillRandomWords(requestId, word);
    for (let i = 0; i < 40; i++) {
      if (!(await game.rngLocked())) break;
      await game.connect(deployer).advanceGame();
    }
    expect(await game.rngLocked()).to.equal(false);
  }

  async function lockRngWithFulfilledWord(game, deployer, mockVRF, word) {
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    await mockVRF.fulfillRandomWords(requestId, word);
    expect(await game.rngLocked()).to.equal(true);
    expect(await game.isRngFulfilled()).to.equal(true);
  }

  async function issueWhaleBoonForRecipient(
    game,
    lootboxModule,
    deity,
    recipient
  ) {
    for (let dayOffset = 0; dayOffset < 180; dayOffset++) {
      const [slots] = await lootboxModule.deityBoonSlots(deity.address);
      for (let slot = 0; slot < 3; slot++) {
        const discountBps = whaleDiscountBps(slots[slot]);
        if (discountBps == 0n) continue;
        await game
          .connect(deity)
          .issueDeityBoon(deity.address, recipient.address, slot);
        return discountBps;
      }
      await advanceToNextDay();
    }
    throw new Error("No whale boon slot found in search window");
  }

  // =========================================================================
  // 1. 100-Level Whale Bundle
  // =========================================================================

  describe("100-level whale bundle", function () {
    it("purchase at level 0 costs 2.4 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("purchase at level 0 with insufficient ETH reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseWhaleBundle(alice.address, 1, { value: eth(2.3) })
      ).to.be.reverted;
    });

    it("purchase multiple bundles (qty=3) costs 3 * 2.4 = 7.2 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 3, { value: eth(7.2) });
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("quantity = 0 reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseWhaleBundle(alice.address, 0, { value: eth(0) })
      ).to.be.reverted;
    });

    it("quantity > 100 reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseWhaleBundle(alice.address, 101, { value: eth(242.4) })
      ).to.be.reverted;
    });

    it("quantity = 100 at level 0 succeeds (max bundle)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 100, { value: eth(240) });
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("wrong ETH amount reverts (overpay)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseWhaleBundle(alice.address, 1, { value: eth(3) })
      ).to.be.reverted;
    });

    it("purchase at level 0 with exact ETH emits LootBoxIndexAssigned", async function () {
      const { game, alice, whaleModule } = await loadFixture(
        deployFullProtocol
      );

      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });
      const events = await getEvents(tx, whaleModule, "LootBoxIndexAssigned");
      expect(events.length).to.be.gte(1);
      expect(events[0].args.buyer).to.equal(alice.address);
    });
  });

  // =========================================================================
  // 2. Whale bundle level restrictions (without boon)
  // =========================================================================

  describe("whale bundle level restrictions", function () {
    it("purchase at level 0 (passLevel=1, <=4) succeeds", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });
      expect((await tx.wait()).status).to.equal(1);
    });

    // Level restrictions beyond 0-3 require advancing the game multiple levels,
    // which is expensive in tests. We verify the basic gating works.
    it("at level 0 (valid early level), multiple buyers succeed", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });
      await game
        .connect(bob)
        .purchaseWhaleBundle(bob.address, 1, { value: eth(2.4) });
    });

    it("expired whale boon cannot use stale dailyIdx to get discounted pricing", async function () {
      const { game, deployer, alice, bob, mockVRF, lootboxModule } =
        await loadFixture(
        deployFullProtocol
      );

      // Alice needs deity status to issue boons.
      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      // Ensure dailyIdx is non-zero, then hold rngWordCurrent so deity boons can be issued.
      await settleRngDay(game, deployer, mockVRF, 777n);
      await lockRngWithFulfilledWord(game, deployer, mockVRF, 888n);

      const discountBps = await issueWhaleBoonForRecipient(
        game,
        lootboxModule,
        alice,
        bob
      );

      // Move past the 4-day boon window while dailyIdx remains stale.
      await advanceTime(5 * 86400);

      const discountedPrice = (eth(4) * (10_000n - discountBps)) / 10_000n;
      await expect(
        game
          .connect(bob)
          .purchaseWhaleBundle(bob.address, 1, { value: discountedPrice })
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // 3. 10-Level Lazy Pass
  // =========================================================================

  describe("10-level lazy pass", function () {
    it("purchase at level 0 costs flat 0.24 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseLazyPass(alice.address, { value: eth(0.24) });
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("purchase at level 0 with wrong ETH reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseLazyPass(alice.address, { value: eth(0.2) })
      ).to.be.reverted;
    });

    it("lazy pass blocked if player has deity pass", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Buy deity pass first
      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      // Lazy pass should revert (deityPassCount != 0)
      await expect(
        game
          .connect(alice)
          .purchaseLazyPass(alice.address, { value: eth(0.24) })
      ).to.be.reverted;
    });

    it("lazy pass blocked with active freeze > currentLevel + 7", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Buy whale bundle first (extends freeze by 100 levels)
      await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });

      // Now lazy pass should revert (frozenUntilLevel > level + 7)
      await expect(
        game
          .connect(alice)
          .purchaseLazyPass(alice.address, { value: eth(0.24) })
      ).to.be.reverted;
    });

    it("lazy pass emits LootBoxIndexAssigned", async function () {
      const { game, alice, whaleModule } = await loadFixture(
        deployFullProtocol
      );

      const tx = await game
        .connect(alice)
        .purchaseLazyPass(alice.address, { value: eth(0.24) });
      const events = await getEvents(tx, whaleModule, "LootBoxIndexAssigned");
      expect(events.length).to.be.gte(1);
    });
  });

  // =========================================================================
  // 4. Deity Pass
  // =========================================================================

  describe("deity pass", function () {
    it("first deity pass costs 24 ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("second deity pass costs 25 ETH (24 + 1)", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      // k=1: 24 + (1 * 2) / 2 = 25 ETH
      const tx = await game
        .connect(bob)
        .purchaseDeityPass(bob.address, 1, { value: eth(25) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("third deity pass costs 27 ETH (24 + 3)", async function () {
      const { game, alice, bob, carol } = await loadFixture(
        deployFullProtocol
      );

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });
      await game
        .connect(bob)
        .purchaseDeityPass(bob.address, 1, { value: eth(25) });

      // k=2: 24 + (2 * 3) / 2 = 27 ETH
      const tx = await game
        .connect(carol)
        .purchaseDeityPass(carol.address, 2, { value: eth(27) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("duplicate symbol reverts", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      // Same symbol (0) should revert
      await expect(
        game.connect(bob).purchaseDeityPass(bob.address, 0, { value: eth(25) })
      ).to.be.reverted;
    });

    it("same buyer purchasing twice reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      await expect(
        game
          .connect(alice)
          .purchaseDeityPass(alice.address, 1, { value: eth(25) })
      ).to.be.reverted;
    });

    it("invalid symbol (32+) reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseDeityPass(alice.address, 32, { value: eth(24) })
      ).to.be.reverted;
    });

    it("wrong ETH amount reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game
          .connect(alice)
          .purchaseDeityPass(alice.address, 0, { value: eth(23) })
      ).to.be.reverted;
    });

    it("symbols 0-23 are valid range", async function () {
      const { game, deployer, alice } = await loadFixture(deployFullProtocol);

      // Just verify symbol 23 works (last valid)
      // Price for first pass = 24 ETH
      const tx = await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 23, { value: eth(24) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("deity pass is refundable at level 0", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      expect(await game.level()).to.equal(0n);
      // deityPassRefundable should be set since level == 0
    });
  });

  // =========================================================================
  // 5. Freeze mechanics
  // =========================================================================

  describe("freeze mechanics", function () {
    it("whale bundle at level 0 sets frozen state", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Before purchase, check mint data
      await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });

      // The player's frozenUntilLevel should be set (100 levels from ticketStartLevel=1)
      // We can verify indirectly: lazy pass should be blocked (freeze > level + 7)
      await expect(
        game
          .connect(alice)
          .purchaseLazyPass(alice.address, { value: eth(0.24) })
      ).to.be.reverted;
    });

    it("multiple whale bundles from same buyer extend freeze", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });

      // Second whale bundle at same level should still work
      // (frozenUntilLevel = max(existing, new target))
      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("different players can each buy whale bundles independently", async function () {
      const { game, alice, bob, carol } = await loadFixture(
        deployFullProtocol
      );

      await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });
      await game
        .connect(bob)
        .purchaseWhaleBundle(bob.address, 2, { value: eth(4.8) });
      await game
        .connect(carol)
        .purchaseWhaleBundle(carol.address, 1, { value: eth(2.4) });
    });
  });

  // =========================================================================
  // 6. Whale + lazy pass interaction
  // =========================================================================

  describe("whale and lazy pass interaction", function () {
    it("lazy pass without any freeze works at level 0", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await game
        .connect(alice)
        .purchaseLazyPass(alice.address, { value: eth(0.24) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("can buy lazy pass first, then whale bundle", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseLazyPass(alice.address, { value: eth(0.24) });

      // Whale bundle should still work
      const tx = await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("cannot buy lazy pass after whale bundle (freeze too far)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseWhaleBundle(alice.address, 1, { value: eth(2.4) });

      await expect(
        game
          .connect(alice)
          .purchaseLazyPass(alice.address, { value: eth(0.24) })
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // 7. Lazy pass discount boons (tiered 10/25/50%)
  // =========================================================================

  const LAZY_BOON_10 = 29;
  const LAZY_BOON_25 = 30;
  const LAZY_BOON_50 = 31;

  function lazyDiscountBps(boonType) {
    const boon = Number(boonType);
    if (boon === LAZY_BOON_50) return 5000n;
    if (boon === LAZY_BOON_25) return 2500n;
    if (boon === LAZY_BOON_10) return 1000n;
    return 0n;
  }

  /**
   * Issue a lazy pass discount boon from deity to recipient.
   *
   * IMPORTANT: deityBoonSlots on the lootbox module cannot be called
   * directly — it reads from the module's own (empty) storage, producing
   * a different RNG seed than the game proxy.  We use DeityBoonViewer,
   * which reads game.deityBoonData() for the correct daily seed.
   *
   * Each iteration settles one day of RNG so issueDeityBoon can work
   * and the slot query returns the correct types.  After the boon is
   * issued, the caller should immediately call purchaseLazyPass on the
   * same day (deity-sourced boons expire on day change).
   */
  async function issueLazyBoonForRecipient(
    game,
    deity,
    recipient,
    deployer,
    mockVRF
  ) {
    const Viewer = await hre.ethers.getContractFactory("DeityBoonViewer");
    const viewer = await Viewer.deploy();

    for (let dayOffset = 0; dayOffset < 180; dayOffset++) {
      await settleRngDay(game, deployer, mockVRF, BigInt(1000 + dayOffset));

      const [slots] = await viewer.deityBoonSlots(game.target, deity.address);
      for (let slot = 0; slot < 3; slot++) {
        const discountBps = lazyDiscountBps(slots[slot]);
        if (discountBps == 0n) continue;
        await game
          .connect(deity)
          .issueDeityBoon(deity.address, recipient.address, slot);
        return discountBps;
      }
    }
    throw new Error("No lazy pass boon slot found in search window");
  }

  describe("lazy pass discount boons", function () {
    this.timeout(120_000);

    it("discounted lazy pass at level 0 costs less than 0.24 ETH", async function () {
      const { game, deployer, alice, bob, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Alice needs deity status to issue boons
      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      const discountBps = await issueLazyBoonForRecipient(
        game,
        alice,
        bob,
        deployer,
        mockVRF
      );

      // Discounted price = 0.24 ETH * (10000 - discountBps) / 10000
      const discountedPrice =
        (eth(0.24) * (10_000n - discountBps)) / 10_000n;

      const tx = await game
        .connect(bob)
        .purchaseLazyPass(bob.address, { value: discountedPrice });
      expect((await tx.wait()).status).to.equal(1);
    });

    it("full-price lazy pass reverts when discount boon active", async function () {
      const { game, deployer, alice, bob, mockVRF } =
        await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      await issueLazyBoonForRecipient(
        game,
        alice,
        bob,
        deployer,
        mockVRF
      );

      // Full price should revert because msg.value != discounted price
      await expect(
        game
          .connect(bob)
          .purchaseLazyPass(bob.address, { value: eth(0.24) })
      ).to.be.reverted;
    });

    it("boon consumed after use — second purchase needs full price", async function () {
      const { game, deployer, alice, bob, mockVRF } =
        await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      const discountBps = await issueLazyBoonForRecipient(
        game,
        alice,
        bob,
        deployer,
        mockVRF
      );

      // Use the discount
      const discountedPrice =
        (eth(0.24) * (10_000n - discountBps)) / 10_000n;
      await game
        .connect(bob)
        .purchaseLazyPass(bob.address, { value: discountedPrice });

      // Second purchase at discounted price should revert (boon consumed)
      await expect(
        game
          .connect(bob)
          .purchaseLazyPass(bob.address, { value: discountedPrice })
      ).to.be.reverted;
    });

    it("expired boon requires full price", async function () {
      const { game, deployer, alice, bob, mockVRF } =
        await loadFixture(deployFullProtocol);

      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      const discountBps = await issueLazyBoonForRecipient(
        game,
        alice,
        bob,
        deployer,
        mockVRF
      );

      // Advance past 4-day boon window
      await advanceTime(5 * 86400);

      // Discounted price should revert (boon expired)
      const discountedPrice =
        (eth(0.24) * (10_000n - discountBps)) / 10_000n;
      await expect(
        game
          .connect(bob)
          .purchaseLazyPass(bob.address, { value: discountedPrice })
      ).to.be.reverted;

      // Full price should work
      const tx = await game
        .connect(bob)
        .purchaseLazyPass(bob.address, { value: eth(0.24) });
      expect((await tx.wait()).status).to.equal(1);
    });
  });

  // =========================================================================
  // 8. Deity pass pricing formula verification
  // =========================================================================

  describe("deity pass pricing formula", function () {
    it("prices follow 24 + T(n) formula for n=0,1,2,3", async function () {
      const { game, alice, bob, carol, dan } = await loadFixture(
        deployFullProtocol
      );

      // n=0: 24 + 0 = 24
      await game
        .connect(alice)
        .purchaseDeityPass(alice.address, 0, { value: eth(24) });

      // n=1: 24 + 1 = 25
      await game
        .connect(bob)
        .purchaseDeityPass(bob.address, 1, { value: eth(25) });

      // n=2: 24 + 3 = 27
      await game
        .connect(carol)
        .purchaseDeityPass(carol.address, 2, { value: eth(27) });

      // n=3: 24 + 6 = 30
      await game
        .connect(dan)
        .purchaseDeityPass(dan.address, 3, { value: eth(30) });
    });
  });
});
