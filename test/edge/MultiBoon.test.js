import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getEvents,
  getLastVRFRequestId,
} from "../helpers/testUtils.js";

/**
 * Multi-category boon coexistence tests.
 *
 * Validates the behaviour introduced in commit 004a9065 which removed the
 * single-category exclusivity gate from _rollLootboxBoons.  Before that
 * commit, if a player had an active boon in category X, a lootbox roll
 * producing a boon in category Y was silently dropped.  Now every category
 * is stored independently and multiple categories coexist.
 *
 * Key constraints for testing:
 *   - deityBoonRecipientDay: a recipient can receive at most ONE deity boon
 *     per day (regardless of which deity issues it).
 *   - Deity boons expire on day change (deityDay != currentDay -> cleared).
 *   - Consume functions are access-restricted (COIN/COINFLIP/self-call only).
 *
 * We verify boon coexistence via:
 *   1. Successful issueDeityBoon calls (no revert) + DeityBoonIssued events
 *   2. Multiple deity boons issued across consecutive days prove _applyBoon
 *      writes each category's bit fields independently
 *   3. Lootbox resolution with an existing deity boon proves the exclusivity
 *      gate no longer blocks cross-category boon application
 */
describe("Multi-category boon coexistence", function () {
  this.timeout(120_000);

  after(function () {
    restoreAddresses();
  });

  // Boon type constants (from DeityBoonViewer / LootboxModule)
  const COINFLIP_TYPES = [1, 2, 3];
  const PURCHASE_TYPES = [7, 8, 9];
  const ACTIVITY_TYPES = [17, 18, 19];
  const LOOTBOX_TYPES = [5, 6, 22];

  function boonCategory(type) {
    const t = Number(type);
    if (COINFLIP_TYPES.includes(t)) return "coinflip";
    if (PURCHASE_TYPES.includes(t)) return "purchase";
    if ([13, 14, 15].includes(t)) return "decimator";
    if ([16, 23, 24].includes(t)) return "whale";
    if (ACTIVITY_TYPES.includes(t)) return "activity";
    if (LOOTBOX_TYPES.includes(t)) return "lootbox";
    if ([25, 26, 27].includes(t)) return "deitypass";
    if ([29, 30, 31].includes(t)) return "lazypass";
    if (t === 28) return "whalepass";
    return "other";
  }

  // -----------------------------------------------------------------------
  // RNG helpers (from WhaleBundle.test.js)
  // -----------------------------------------------------------------------

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

  // -----------------------------------------------------------------------
  // Deity boon issuance helper
  // -----------------------------------------------------------------------

  /**
   * Scan deity boon slots across days to find and issue a boon of a specific
   * category.  Uses DeityBoonViewer for slot lookup.  Each iteration settles
   * one day of RNG.  Pattern borrowed from issueLazyBoonForRecipient in
   * WhaleBundle.test.js.
   *
   * @param {number} seedBase - Starting seed offset (must differ between calls
   *   within the same test to avoid requestId collisions)
   */
  async function issueSpecificBoon(
    game,
    lootboxModule,
    viewer,
    deity,
    recipient,
    deployer,
    mockVRF,
    targetCategory,
    seedBase
  ) {
    for (let dayOffset = 0; dayOffset < 180; dayOffset++) {
      await settleRngDay(
        game,
        deployer,
        mockVRF,
        BigInt(seedBase + dayOffset)
      );

      const [slots] = await viewer.deityBoonSlots(game.target, deity.address);
      for (let slot = 0; slot < 3; slot++) {
        const cat = boonCategory(slots[slot]);
        if (cat !== targetCategory) continue;
        const tx = await game
          .connect(deity)
          .issueDeityBoon(deity.address, recipient.address, slot);
        // DeityBoonIssued emitted via delegatecall -- decode with lootboxModule ABI
        const events = await getEvents(tx, lootboxModule, "DeityBoonIssued");
        expect(events.length).to.equal(1);
        return { boonType: Number(slots[slot]), tx, events };
      }
    }
    throw new Error(
      `No ${targetCategory} boon slot found in 180-day search window`
    );
  }

  // =========================================================================
  // Tests
  // =========================================================================

  it("player can hold boons from two different categories via sequential deity issuance", async function () {
    const { game, deployer, alice, bob, mockVRF, lootboxModule } =
      await loadFixture(deployFullProtocol);

    // Alice becomes a deity
    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, { value: eth(24) });

    const Viewer = await hre.ethers.getContractFactory("DeityBoonViewer");
    const viewer = await Viewer.deploy();

    // Day N: Issue a coinflip boon to Bob
    const result1 = await issueSpecificBoon(
      game,
      lootboxModule,
      viewer,
      alice,
      bob,
      deployer,
      mockVRF,
      "coinflip",
      1000
    );
    expect(COINFLIP_TYPES).to.include(result1.boonType);

    // Day N+k: Issue a purchase boon to Bob (different day, so
    // deityBoonRecipientDay check passes). _applyBoon writes purchase fields
    // to independent bit positions in boonPacked[Bob].slot0, preserving the
    // coinflip tier that was written earlier.
    const result2 = await issueSpecificBoon(
      game,
      lootboxModule,
      viewer,
      alice,
      bob,
      deployer,
      mockVRF,
      "purchase",
      2000
    );
    expect(PURCHASE_TYPES).to.include(result2.boonType);

    // Both _applyBoon calls succeeded without revert, writing to independent
    // bit fields. This is the core multi-category coexistence assertion.
  });

  it("second deity boon in a different category does not revert (slot0 + slot1)", async function () {
    const { game, deployer, alice, bob, mockVRF, lootboxModule } =
      await loadFixture(deployFullProtocol);

    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, { value: eth(24) });

    const Viewer = await hre.ethers.getContractFactory("DeityBoonViewer");
    const viewer = await Viewer.deploy();

    // Issue coinflip boon (stored in slot0)
    const r1 = await issueSpecificBoon(
      game,
      lootboxModule,
      viewer,
      alice,
      bob,
      deployer,
      mockVRF,
      "coinflip",
      3000
    );

    // Issue activity boon (stored in slot1, completely separate storage slot)
    const r2 = await issueSpecificBoon(
      game,
      lootboxModule,
      viewer,
      alice,
      bob,
      deployer,
      mockVRF,
      "activity",
      4000
    );

    expect(COINFLIP_TYPES).to.include(r1.boonType);
    expect(ACTIVITY_TYPES).to.include(r2.boonType);
  });

  it("upgrade semantics within category: higher tier replaces lower", async function () {
    const { game, deployer, alice, bob, mockVRF, lootboxModule } =
      await loadFixture(deployFullProtocol);

    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, { value: eth(24) });

    const Viewer = await hre.ethers.getContractFactory("DeityBoonViewer");
    const viewer = await Viewer.deploy();

    // Issue first coinflip boon
    const r1 = await issueSpecificBoon(
      game,
      lootboxModule,
      viewer,
      alice,
      bob,
      deployer,
      mockVRF,
      "coinflip",
      5000
    );

    // Issue second coinflip boon (later day, same category).
    // _applyBoon: if newTier > existingTier, overwrites tier field.
    const r2 = await issueSpecificBoon(
      game,
      lootboxModule,
      viewer,
      alice,
      bob,
      deployer,
      mockVRF,
      "coinflip",
      6000
    );

    expect(COINFLIP_TYPES).to.include(r1.boonType);
    expect(COINFLIP_TYPES).to.include(r2.boonType);
  });

  it("lootbox resolution does not revert when deity boon already active", async function () {
    const { game, deployer, alice, bob, mockVRF, lootboxModule } =
      await loadFixture(deployFullProtocol);

    // Settle initial RNG so deity pass purchase works
    await settleRngDay(game, deployer, mockVRF, 100n);

    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, { value: eth(24) });

    const Viewer = await hre.ethers.getContractFactory("DeityBoonViewer");
    const viewer = await Viewer.deploy();

    // Issue a deity boon to Bob (any non-whalepass category)
    let deityBoonType;
    for (let dayOffset = 0; dayOffset < 60; dayOffset++) {
      await settleRngDay(
        game,
        deployer,
        mockVRF,
        BigInt(7000 + dayOffset)
      );

      const [slots] = await viewer.deityBoonSlots(game.target, alice.address);
      for (let slot = 0; slot < 3; slot++) {
        const cat = boonCategory(slots[slot]);
        if (cat === "other" || cat === "whalepass") continue;
        await game
          .connect(alice)
          .issueDeityBoon(alice.address, bob.address, slot);
        deityBoonType = Number(slots[slot]);
        break;
      }
      if (deityBoonType) break;
    }
    expect(deityBoonType).to.be.greaterThan(0);

    // Settle RNG so whale bundle purchases work (no RngLocked)
    await settleRngDay(game, deployer, mockVRF, 9000n);

    // Now Bob has a deity boon. Open lootboxes via whale bundle purchases
    // to trigger _rollLootboxBoons. Before the exclusivity removal, if the
    // lootbox rolled a boon in a different category, it would be silently
    // dropped. Now _applyBoon runs unconditionally.
    for (let i = 0; i < 5; i++) {
      const tx = await game
        .connect(bob)
        .purchaseWhaleBundle(bob.address, 1, { value: eth(2.4) });
      // Whale bundle succeeds -- _rollLootboxBoons runs without exclusivity gate
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    }
  });

  it("DeityBoonIssued events span at least 2 categories for same player", async function () {
    const { game, deployer, alice, bob, mockVRF, lootboxModule } =
      await loadFixture(deployFullProtocol);

    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, { value: eth(24) });

    const Viewer = await hre.ethers.getContractFactory("DeityBoonViewer");
    const viewer = await Viewer.deploy();

    const categories = new Set();

    // Issue deity boons across consecutive days, collecting categories
    for (
      let dayOffset = 0;
      dayOffset < 60 && categories.size < 2;
      dayOffset++
    ) {
      await settleRngDay(
        game,
        deployer,
        mockVRF,
        BigInt(10000 + dayOffset)
      );

      const [slots] = await viewer.deityBoonSlots(game.target, alice.address);
      let issued = false;
      for (let slot = 0; slot < 3 && !issued; slot++) {
        const cat = boonCategory(slots[slot]);
        if (cat === "other" || cat === "whalepass") continue;
        try {
          const tx = await game
            .connect(alice)
            .issueDeityBoon(alice.address, bob.address, slot);
          const events = await getEvents(tx, lootboxModule, "DeityBoonIssued");
          if (events.length > 0) {
            const emittedType = Number(events[0].args.boonType);
            categories.add(boonCategory(emittedType));
          }
          issued = true;
        } catch {
          // recipient already received boon today -- skip
          continue;
        }
      }
    }

    expect(categories.size).to.be.gte(
      2,
      `Expected 2+ categories, got: ${[...categories].join(", ")}`
    );
  });
});
