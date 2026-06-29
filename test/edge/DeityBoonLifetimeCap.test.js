import { expect } from "chai";
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
 * Deity boon per-(deity, recipient) lifetime cap.
 *
 * issueDeityBoon enforces DEITY_RECIPIENT_BOON_CAP (= 10) boons per (deity,
 * recipient) pair over the game's lifetime, tracked in
 * deityRecipientBoonCount[deity][recipient]. Once a deity has issued 10 boons to
 * a recipient, further issuance from that deity to that recipient reverts
 * RecipientBoonCapReached. A different deity, or a different recipient, has its
 * own independent count. The pre-existing one-boon-per-recipient-per-day gate
 * (deityBoonRecipientDay, keyed by recipient across all deities) is unchanged.
 *
 * The deity passes are purchased at genesis (before any day is settled) and RNG
 * is settled with words >= 1000 to avoid the genesis level-0 low-entropy
 * mock-VRF artifact.
 */
describe("Deity boon per-(deity, recipient) lifetime cap", function () {
  this.timeout(240_000);

  const PAIR_CAP = 10;

  after(function () {
    restoreAddresses();
  });

  // Settle a day's RNG. Crossing a level boundary can chain a fresh VRF request,
  // so re-fulfill any newly issued request id rather than only the first.
  async function settleRngDay(game, deployer, mockVRF, word) {
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();
    let lastFulfilled = -1n;
    for (let i = 0; i < 80; i++) {
      if (!(await game.rngLocked())) break;
      const requestId = await getLastVRFRequestId(mockVRF);
      if (requestId !== lastFulfilled) {
        await mockVRF.fulfillRandomWords(requestId, word + BigInt(i));
        lastFulfilled = requestId;
      } else {
        await game.connect(deployer).advanceGame();
      }
    }
    expect(await game.rngLocked()).to.equal(false);
  }

  it("reverts the 11th boon from one deity to the same recipient", async function () {
    const { game, deployer, alice, bob, mockVRF, lootboxModule } =
      await loadFixture(deployFullProtocol);

    // Deity pass purchased at genesis, before any day is settled.
    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, { value: eth(24) });

    // One boon per day to Bob (recipient is limited to one boon per day). Slot 0
    // is always free on a fresh day because the deity's used-slot mask resets on
    // the day rollover.
    for (let i = 0; i < PAIR_CAP; i++) {
      await settleRngDay(game, deployer, mockVRF, BigInt(1000 + i * 7));
      await expect(
        game.connect(alice).issueDeityBoon(alice.address, bob.address, 0)
      ).to.not.be.reverted;
    }

    // 11th boon from alice to bob on a fresh day: pair cap reached.
    await settleRngDay(game, deployer, mockVRF, 9001n);
    await expect(
      game.connect(alice).issueDeityBoon(alice.address, bob.address, 0)
    ).to.be.revertedWithCustomError(lootboxModule, "RecipientBoonCapReached");
  });

  it("cap is per recipient: a second recipient is unaffected by the first hitting the cap", async function () {
    const { game, deployer, alice, bob, carol, mockVRF, lootboxModule } =
      await loadFixture(deployFullProtocol);

    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, { value: eth(24) });

    // Fill the alice->bob pair to the cap.
    for (let i = 0; i < PAIR_CAP; i++) {
      await settleRngDay(game, deployer, mockVRF, BigInt(2000 + i * 7));
      await game.connect(alice).issueDeityBoon(alice.address, bob.address, 0);
    }

    await settleRngDay(game, deployer, mockVRF, 9002n);
    // alice->bob is capped...
    await expect(
      game.connect(alice).issueDeityBoon(alice.address, bob.address, 0)
    ).to.be.revertedWithCustomError(lootboxModule, "RecipientBoonCapReached");
    // ...but alice->carol (fresh recipient) still receives on the same day.
    await expect(
      game.connect(alice).issueDeityBoon(alice.address, carol.address, 1)
    ).to.not.be.reverted;
  });

  it("cap is per deity: a second deity can still boon a recipient the first deity has capped", async function () {
    const { game, deployer, alice, bob, dan, mockVRF, lootboxModule } =
      await loadFixture(deployFullProtocol);

    // Two independent deities.
    await game
      .connect(alice)
      .purchaseDeityPass(alice.address, 0, { value: eth(24) });
    // Second deity pass: the bonding-curve price has stepped up from 24 to 25.
    await game
      .connect(dan)
      .purchaseDeityPass(dan.address, 1, { value: eth(25) });

    // Fill the alice->bob pair to the cap.
    for (let i = 0; i < PAIR_CAP; i++) {
      await settleRngDay(game, deployer, mockVRF, BigInt(3000 + i * 7));
      await game.connect(alice).issueDeityBoon(alice.address, bob.address, 0);
    }

    await settleRngDay(game, deployer, mockVRF, 9003n);
    // alice->bob is capped...
    await expect(
      game.connect(alice).issueDeityBoon(alice.address, bob.address, 0)
    ).to.be.revertedWithCustomError(lootboxModule, "RecipientBoonCapReached");
    // ...but dan->bob is a fresh pair, so dan can still boon bob the same day
    // (the failed alice attempt did not consume bob's one-boon-per-day slot).
    await expect(
      game.connect(dan).issueDeityBoon(dan.address, bob.address, 0)
    ).to.not.be.reverted;
  });
});
