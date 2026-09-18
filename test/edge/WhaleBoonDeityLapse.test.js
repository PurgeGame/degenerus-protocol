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
  getLastVRFRequestId,
} from "../helpers/testUtils.js";

/**
 * WhaleBoonDeityLapse -- regression test for the second half of the whale-boon
 * expiry fix in DegenerusGameBoonModule._applyBoon (whale branch, ~line 1037-1053).
 *
 * checkAndClearExpiredBoon (see test/fuzz/WhaleBoonExpiry.t.sol) sweeps a lapsed
 * lootbox-rolled or stale deity-stamped whale lane, but that sweep only runs on the
 * lootbox-open path (_boxBoonContext). The deity gift path -- issueDeityBoon ->
 * _applyBoon -- never calls the sweep, so before this fix a dead lane's stale
 * `existingTier` silently blocked a fresh (even lower-tier) deity gift forever:
 * `newTier > existingTier` compared the incoming tier against a tier that was never
 * cleared. The fix re-derives liveness inline in _applyBoon's whale branch (dead if
 * lootbox-rolled and >4 days lapsed, or deity-stamped on a day other than today) and
 * treats a dead lane as tier 0 before the upgrade comparison.
 *
 * Storage is seeded directly via hardhat_setStorageAt into boonPacked[recipient].slot0
 * -- SLOT_BOON_PACKED = 50, the same mapping slot documented in
 * test/fuzz/LootboxBoonCoexistence.t.sol and test/fuzz/WhaleBoonExpiry.t.sol (both
 * `forge inspect DegenerusGame storage-layout` on the working tree). The whale lane
 * occupies bits 200-255 of slot0: whaleDay[24] | deityWhaleDay[24] | whaleTier[8].
 *
 * A deity boon's type is a weighted roll over the day's VRF word
 * (DeityBoonViewer._boonFromRoll mirrors DegenerusGameBoonModule._boonFromRoll), so
 * getting a specific type (BOON_WHALE_10 = 16, the 10% / tier-1 whale discount) means
 * settling RNG day by day and scanning the deity's three daily slots until one offers
 * it -- the same technique WhaleBundle.test.js's issueWhaleBoonForRecipient uses for
 * "any" whale boon, narrowed here to one exact type so the test controls the tier
 * being gifted. Reproduced standalone rather than imported: the WhaleBundle helper is
 * a local closure, not exported.
 */
describe("WhaleBoonDeityLapse", function () {
  this.timeout(180_000);

  after(function () {
    restoreAddresses();
  });

  const DEITY_BOON_WHALE_10 = 16; // 10% discount -> tier 1

  const SLOT_BOON_PACKED = 50n;
  const BP_WHALE_DAY_SHIFT = 200n;
  const BP_DEITY_WHALE_DAY_SHIFT = 224n;
  const BP_WHALE_TIER_SHIFT = 248n;

  function boonSlot0(player) {
    return hre.ethers.keccak256(
      hre.ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256"],
        [player, SLOT_BOON_PACKED]
      )
    );
  }

  function packWhaleLane(whaleDay, deityWhaleDay, tier) {
    return (
      (BigInt(whaleDay) << BP_WHALE_DAY_SHIFT) |
      (BigInt(deityWhaleDay) << BP_DEITY_WHALE_DAY_SHIFT) |
      (BigInt(tier) << BP_WHALE_TIER_SHIFT)
    );
  }

  function toWord(value) {
    return "0x" + value.toString(16).padStart(64, "0");
  }

  /// @dev Inject a whale boon into boonPacked[player].slot0. The recipients used in
  ///      this file are freshly-loaded hardhat signers that have never touched a boon
  ///      lane, so slot0 starts at 0 and a direct overwrite (rather than a
  ///      read-clear-merge, as the Foundry counterpart does to protect sibling lanes)
  ///      is exact.
  async function injectWhaleBoon(game, player, whaleDay, deityWhaleDay, tier) {
    const slot = boonSlot0(player);
    const packed = packWhaleLane(whaleDay, deityWhaleDay, tier);
    await hre.network.provider.send("hardhat_setStorageAt", [
      await game.getAddress(),
      slot,
      toWord(packed),
    ]);
  }

  async function readWhaleLane(game, player) {
    const [slot0] = await game.boonPacked(player);
    const whaleDay = (slot0 >> BP_WHALE_DAY_SHIFT) & 0xffffffn;
    const deityWhaleDay = (slot0 >> BP_DEITY_WHALE_DAY_SHIFT) & 0xffffffn;
    const tier = (slot0 >> BP_WHALE_TIER_SHIFT) & 0xffn;
    return { whaleDay, deityWhaleDay, tier };
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

  /// @dev Settle RNG day by day until the deity's slot menu offers `targetBoonType`,
  ///      then return the matching slot index WITHOUT issuing it -- the caller seeds
  ///      the recipient's lane relative to the now-current day first, then issues in
  ///      the same day so the contract's `_simulatedDayIndex()` at issuance matches
  ///      the day the caller seeded against. Skips any day where currentDayView() < 10
  ///      so a caller seeding `currentDay - N` (N up to 6) never underflows the uint24.
  async function findWhaleTenSlot(game, deity, deployer, mockVRF, seedBase, maxDays) {
    const Viewer = await hre.ethers.getContractFactory("DeityBoonViewer");
    const viewer = await Viewer.deploy();

    for (let dayOffset = 0; dayOffset < maxDays; dayOffset++) {
      await settleRngDay(game, deployer, mockVRF, BigInt(seedBase + dayOffset));

      const currentDay = await game.currentDayView();
      if (currentDay < 10n) continue;

      const [slots] = await viewer.deityBoonSlots(await game.getAddress(), deity.address);
      for (let slot = 0; slot < 3; slot++) {
        if (Number(slots[slot]) === DEITY_BOON_WHALE_10) return slot;
      }
    }
    throw new Error(
      `No BOON_WHALE_10 (10%) slot found within ${maxDays} days from seedBase ${seedBase}`
    );
  }

  it("a dead lane (lapsed lootbox-rolled tier 3) accepts a lower deity gift instead of staying blocked", async function () {
    const { game, deployer, alice, bob, mockVRF } = await loadFixture(deployFullProtocol);

    // Alice needs deity status to issue boons.
    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, hre.ethers.ZeroHash, { value: eth(24) });

    const slot = await findWhaleTenSlot(game, alice, deployer, mockVRF, 9000, 200);
    const currentDay = await game.currentDayView();

    // Seed bob with a lootbox-rolled tier-3 whale discount 6 days stale (>4-day
    // window, deityWhaleDay = 0) -- lapsed, but never swept (bob never opened a box).
    await injectWhaleBoon(game, bob.address, currentDay - 6n, 0n, 3);
    const before = await readWhaleLane(game, bob.address);
    expect(before.tier).to.equal(3n, "seeded tier must start at 3");
    expect(before.whaleDay).to.equal(currentDay - 6n, "seeded whaleDay must be 6 days stale");
    expect(before.deityWhaleDay).to.equal(0n, "seeded lane must be lootbox-rolled (deityWhaleDay 0)");

    // Before the fix this would be a silent no-op: newTier(1) <= existingTier(3).
    await game.connect(alice).issueDeityBoon(alice.address, bob.address, slot);

    const after_ = await readWhaleLane(game, bob.address);
    expect(after_.tier).to.equal(1n, "dead lane must accept the fresh (lower) deity gift, tier 1");
    expect(after_.whaleDay).to.equal(currentDay, "whaleDay must re-stamp to the issuance day");
    expect(after_.deityWhaleDay).to.equal(currentDay, "deityWhaleDay must stamp to the issuance day");
  });

  it("a live lane (tier 3, within the window) still rejects a lower deity gift", async function () {
    const { game, deployer, alice, bob, mockVRF } = await loadFixture(deployFullProtocol);

    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, hre.ethers.ZeroHash, { value: eth(24) });

    const slot = await findWhaleTenSlot(game, alice, deployer, mockVRF, 9500, 200);
    const currentDay = await game.currentDayView();

    // Seed bob with a lootbox-rolled tier-3 whale discount from yesterday -- still
    // live (inside the 4-day window), deityWhaleDay = 0.
    await injectWhaleBoon(game, bob.address, currentDay - 1n, 0n, 3);
    const before = await readWhaleLane(game, bob.address);
    expect(before.tier).to.equal(3n, "seeded tier must start at 3");

    await game.connect(alice).issueDeityBoon(alice.address, bob.address, slot);

    const after_ = await readWhaleLane(game, bob.address);
    expect(after_.tier).to.equal(3n, "live tier-3 lane must reject the lower (tier 1) gift");
    expect(after_.whaleDay).to.equal(currentDay - 1n, "whaleDay must stay untouched on a rejected gift");
    expect(after_.deityWhaleDay).to.equal(0n, "deityWhaleDay must stay untouched (still lootbox-rolled)");
  });
});
