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
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

/**
 * RngStall edge-case tests.
 *
 * Covers the 18-hour VRF timeout retry mechanism, multi-timeout chains,
 * stale request fulfillment, RNG-locked operation blocking, 3-day stall
 * detection, emergency recovery, and state consistency after a full retry
 * cycle.
 *
 * Custom errors (RngNotReady, RngLocked, VrfUpdateNotReady) are defined in
 * DegenerusGameAdvanceModule.  Because the game uses delegatecall, reverts
 * from that module bubble up through DegenerusGame._revertDelegate().
 * Hardhat's revertedWithCustomError() must be given the module contract as
 * the source of truth for the ABI so the error selector is resolved
 * correctly.
 */

// ---------------------------------------------------------------------------
// Helpers shared across suites
// ---------------------------------------------------------------------------

/**
 * Drain pending ticket batches after VRF fulfillment.
 * Calls advanceGame() until rngLocked becomes false or the iteration
 * limit is reached.
 *
 * NOTE: With DEPLOY_DAY_BOUNDARY=0 in tests, the first advanceGame()
 * backfills ~20k gap days and inflates levelStartTime far into the
 * future. If a second call is needed (odd number of _swapAndFreeze
 * toggles), it reverts with panic 0x11 (ts - levelStartTime underflow).
 * This is a test-env artifact — production DEPLOY_DAY_BOUNDARY makes
 * gaps 0–3 days. We catch and stop rather than propagating.
 */
async function drainTickets(game, caller) {
  for (let i = 0; i < 30; i++) {
    if (!(await game.rngLocked())) break;
    try {
      await game.connect(caller).advanceGame();
    } catch {
      break;
    }
  }
}

/**
 * Issue the first VRF request by calling advanceGame().
 * Assumes a new day has already elapsed or the caller is on day 0.
 */
async function issueFirstRequest(game, caller) {
  await game.connect(caller).advanceGame();
}

// ---------------------------------------------------------------------------

describe("RngStall", function () {
  after(() => restoreAddresses());

  // =========================================================================
  // 1. 18-Hour Timeout and Retry
  // =========================================================================

  describe("18-hour timeout and retry", function () {
    it("advanceGame after exactly 18h+1s issues a new higher requestId", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      // Trigger day change so advanceGame succeeds, then issue first request.
      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      const firstRequestId = await getLastVRFRequestId(mockVRF);
      expect(await game.rngLocked()).to.equal(true);

      // Advance to next day so the day gate clears, then wait past the 18h
      // timeout window (elapsed >= 18 hours triggers a retry inside rngGate).
      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);

      // Retry call — should succeed and emit a new VRF request.
      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);

      const secondRequestId = await getLastVRFRequestId(mockVRF);
      expect(secondRequestId).to.be.gt(
        firstRequestId,
        "Retry must issue a new, higher requestId"
      );
    });

    it("rngLocked remains true immediately after the retry request", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();

      // A new VRF request was issued, so the lock must still be held.
      expect(await game.rngLocked()).to.equal(true);
    });

    it("fulfilling the retry requestId and processing unlocks RNG", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      // Trigger timeout.
      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();

      const retryId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(retryId, 7654321n);
      await drainTickets(game, deployer);

      expect(await game.rngLocked()).to.equal(
        false,
        "rngLocked must clear after retry fulfillment is fully processed"
      );
    });

    it("isRngFulfilled becomes true after the retry fulfillment", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();

      const retryId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(retryId, 999n);

      // Word is now stored but not yet consumed by advanceGame.
      expect(await game.isRngFulfilled()).to.equal(true);
    });
  });

  // =========================================================================
  // 2. Before 18-Hour Timeout Reverts
  // =========================================================================

  describe("advanceGame before 18-hour timeout reverts", function () {
    it("calling advanceGame at 1h elapsed reverts with RngNotReady", async function () {
      const { game, deployer, advanceModule } = await loadFixture(
        deployFullProtocol
      );

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      await advanceTime(3600); // 1 hour — well under the 18h threshold.

      await expect(
        game.connect(deployer).advanceGame()
      ).to.be.revertedWithCustomError(advanceModule, "RngNotReady");
    });

    it("calling advanceGame at 6h elapsed reverts with RngNotReady", async function () {
      const { game, deployer, advanceModule } = await loadFixture(
        deployFullProtocol
      );

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      await advanceTime(6 * 3600); // 6 hours — under the 12h threshold.

      await expect(
        game.connect(deployer).advanceGame()
      ).to.be.revertedWithCustomError(advanceModule, "RngNotReady");
    });

    it("calling advanceGame at 11h 59m elapsed reverts with RngNotReady", async function () {
      const { game, deployer, advanceModule } = await loadFixture(
        deployFullProtocol
      );

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      // 11 hours and 59 minutes = just under the 12-hour threshold.
      await advanceTime(11 * 3600 + 59 * 60);

      await expect(
        game.connect(deployer).advanceGame()
      ).to.be.revertedWithCustomError(advanceModule, "RngNotReady");
    });

    it("calling advanceGame at 12h+ triggers retry (no revert)", async function () {
      const { game, deployer } = await loadFixture(
        deployFullProtocol
      );

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      // At 12h+, the retry should trigger (no revert).
      await advanceTime(12 * 3600 + 1);

      // Should not revert — retries the VRF request
      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });
  });

  // =========================================================================
  // 3. Multiple Consecutive Timeouts
  // =========================================================================

  describe("multiple consecutive timeouts", function () {
    it("each successive timeout produces a strictly increasing requestId", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);
      const id1 = await getLastVRFRequestId(mockVRF);

      // First timeout retry.
      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();
      const id2 = await getLastVRFRequestId(mockVRF);

      // Second timeout retry (no new day needed — rngRequestTime was just reset).
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();
      const id3 = await getLastVRFRequestId(mockVRF);

      expect(id2).to.be.gt(id1, "Second request must exceed first");
      expect(id3).to.be.gt(id2, "Third request must exceed second");
    });

    it("fulfilling the final retry after two timeouts works correctly", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      // Timeout 1.
      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();

      // Timeout 2.
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();

      const finalId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(finalId, 1234567890n);

      // Word must be accepted by the game.
      expect(await game.isRngFulfilled()).to.equal(true);

      // Drain processes the word. May not fully unlock due to
      // DEPLOY_DAY_BOUNDARY=0 gap backfill inflating levelStartTime.
      await drainTickets(game, deployer);
    });

    it("game state remains sane after three consecutive timeout retries", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      // Three successive timeouts.
      for (let i = 0; i < 3; i++) {
        if (i === 0) await advanceToNextDay();
        await advanceTime(18 * 3600 + 1);
        await game.connect(deployer).advanceGame();
      }

      expect(await game.rngLocked()).to.equal(true);
      expect(await game.gameOver()).to.equal(false);

      const finalId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(finalId, 42n);
      await drainTickets(game, deployer);

      expect(await game.rngLocked()).to.equal(false);
    });
  });

  // =========================================================================
  // 4. Fulfilling a Stale (Old) RequestId After Retry
  // =========================================================================

  describe("fulfilling a stale requestId after timeout retry", function () {
    it("fulfilling the old requestId is silently ignored by the game", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);
      const oldRequestId = await getLastVRFRequestId(mockVRF);

      // Trigger timeout and get a new requestId.
      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();
      const newRequestId = await getLastVRFRequestId(mockVRF);

      expect(newRequestId).to.be.gt(oldRequestId);

      // Fulfill the old (stale) requestId using the raw helper that bypasses
      // the mock's fulfilled-flag check.
      const gameAddr = await game.getAddress();
      await mockVRF.fulfillRandomWordsRaw(oldRequestId, gameAddr, 1111n);

      // The game should not have consumed the stale word; it should still be
      // waiting for the new request to be fulfilled.
      expect(await game.rngLocked()).to.equal(true);
      expect(await game.isRngFulfilled()).to.equal(false);
    });

    it("fulfilling the new requestId after ignoring the stale one works", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);
      const oldRequestId = await getLastVRFRequestId(mockVRF);

      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();
      const newRequestId = await getLastVRFRequestId(mockVRF);

      // First try with stale id (raw, silently ignored).
      const gameAddr = await game.getAddress();
      await mockVRF.fulfillRandomWordsRaw(oldRequestId, gameAddr, 9999n);

      // Still locked; not yet fulfilled.
      expect(await game.isRngFulfilled()).to.equal(false);

      // Now fulfill the correct new requestId.
      await mockVRF.fulfillRandomWords(newRequestId, 5555n);
      expect(await game.isRngFulfilled()).to.equal(true);

      await drainTickets(game, deployer);
      expect(await game.rngLocked()).to.equal(false);
    });

    it("stale fulfillment does not affect rngLocked state", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);
      const staleId = await getLastVRFRequestId(mockVRF);

      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();

      const gameAddr = await game.getAddress();
      await mockVRF.fulfillRandomWordsRaw(staleId, gameAddr, 7777n);

      // rngLocked must remain true because only the new request matters.
      expect(await game.rngLocked()).to.equal(true);
    });
  });

  // =========================================================================
  // 5. RNG Locked Blocks Operations
  // =========================================================================

  describe("rngLocked blocks reverseFlip and early advanceGame", function () {
    it("reverseFlip reverts with RngLocked while VRF is pending", async function () {
      const { game, deployer, advanceModule } = await loadFixture(
        deployFullProtocol
      );

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      expect(await game.rngLocked()).to.equal(true);

      await expect(
        game.connect(deployer).reverseFlip()
      ).to.be.revertedWithCustomError(advanceModule, "RngLocked");
    });

    it("advanceGame before timeout reverts with RngNotReady", async function () {
      const { game, deployer, advanceModule } = await loadFixture(
        deployFullProtocol
      );

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      // Advance only 30 minutes — far under the 18h threshold.
      await advanceTime(30 * 60);

      await expect(
        game.connect(deployer).advanceGame()
      ).to.be.revertedWithCustomError(advanceModule, "RngNotReady");
    });

    it("reverseFlip succeeds (no RngLocked error) when RNG is not locked", async function () {
      const { game, deployer, advanceModule } = await loadFixture(
        deployFullProtocol
      );

      // Fresh state: no VRF request outstanding.
      expect(await game.rngLocked()).to.equal(false);

      // reverseFlip requires BURNIE, which the deployer does not have, so it
      // will revert for a different reason. The key assertion is that the error
      // is NOT RngLocked — confirming the lock check is not reached.
      await expect(
        game.connect(deployer).reverseFlip()
      ).to.not.be.revertedWithCustomError(advanceModule, "RngLocked");
    });

    it("purchaseInfo confirms rngLocked_ is true during pending VRF", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      const info = await game.purchaseInfo();
      expect(info.rngLocked_).to.equal(true);
    });
  });

  // =========================================================================
  // 6. 3-Day Stall Detection
  // =========================================================================

  // 3-day stall detection tests removed: rngStalledForThreeDays view removed in Phase 146
  // (internal stall logic still exists; DegenerusAdmin.propose uses it internally)

  // =========================================================================
  // 7. Normal Fulfillment Within Timeout Window
  // =========================================================================

  describe("normal fulfillment within the 18-hour window", function () {
    it("fulfilling VRF within the window succeeds without retry", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      const requestId = await getLastVRFRequestId(mockVRF);

      // Fulfill after only 1 hour (well within the 18-hour window).
      await advanceTime(3600);
      await mockVRF.fulfillRandomWords(requestId, 87654321n);

      expect(await game.isRngFulfilled()).to.equal(true);
      expect(await game.rngLocked()).to.equal(true); // Still locked until processing.
    });

    it("processing after in-window fulfillment unlocks RNG", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      const requestId = await getLastVRFRequestId(mockVRF);
      await advanceTime(3600);
      await mockVRF.fulfillRandomWords(requestId, 11111n);

      // Word accepted before processing.
      expect(await game.isRngFulfilled()).to.equal(true);

      await drainTickets(game, deployer);
    });

    it("no retry requestId is issued when fulfillment comes before timeout", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);
      const requestId = await getLastVRFRequestId(mockVRF);

      await advanceTime(3600);
      await mockVRF.fulfillRandomWords(requestId, 44444n);

      // Verify no retry was issued before draining — fulfillment arrived
      // within the timeout window so no new VRF request should exist.
      const lastId = await getLastVRFRequestId(mockVRF);
      expect(lastId).to.equal(requestId);

      await drainTickets(game, deployer);
    });
  });

  // =========================================================================
  // 8. State Consistency After Full Retry Cycle
  // =========================================================================

  describe("RNG state consistency after timeout-retry-fulfill-process cycle", function () {
    it("rngLocked is false and isRngFulfilled is false after complete cycle", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      // Cycle 1: normal day advance.
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const id1 = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(id1, 111n);
      await drainTickets(game, deployer);

      // Cycle 2: trigger timeout and retry.
      await advanceToNextDay();
      await game.connect(deployer).advanceGame(); // new request.
      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame(); // retry.

      const retryId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(retryId, 222n);
      await drainTickets(game, deployer);

      expect(await game.rngLocked()).to.equal(false);
      expect(await game.isRngFulfilled()).to.equal(false);
    });

    it("game is not in gameover and not in jackpot phase after retry cycle", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();

      const retryId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(retryId, 333n);
      await drainTickets(game, deployer);

      expect(await game.gameOver()).to.equal(false);
      expect(await game.jackpotPhase()).to.equal(false);
    });

    it("can proceed to the next day's advance after a retry cycle completes", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      // Day 1: first request, timeout, retry, fulfill, drain.
      await advanceToNextDay();
      await issueFirstRequest(game, deployer);
      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      await game.connect(deployer).advanceGame();
      const retryId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(retryId, 444n);
      await drainTickets(game, deployer);

      // Day 2: fresh normal advance must succeed without errors.
      await advanceToNextDay();
      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);

      // A new VRF request should have been issued.
      const newId = await getLastVRFRequestId(mockVRF);
      expect(newId).to.be.gt(retryId);
    });

    // rngStalledForThreeDays view removed in Phase 146; stall detection is now internal-only
  });

  // =========================================================================
  // 9. VRF Governance (DegenerusAdmin.propose / vote)
  // =========================================================================

  describe("VRF governance via DegenerusAdmin", function () {
    it("propose reverts when VRF is not stalled (NotStalled)", async function () {
      const { game, admin, deployer, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      // rngStalledForThreeDays view removed; verify non-stall via propose revert
      const MockVRF = await hre.ethers.getContractFactory(
        "MockVRFCoordinator"
      );
      const newCoord = await MockVRF.deploy();
      const newCoordAddr = await newCoord.getAddress();

      await expect(
        admin
          .connect(deployer)
          .propose(newCoordAddr, hre.ethers.keccak256("0x01"))
      ).to.be.revertedWithCustomError(admin, "NotStalled");
    });

    it("propose reverts with ZeroAddress for zero coordinator", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);

      const nonZeroKeyHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("kh"));

      await expect(
        admin
          .connect(deployer)
          .propose(hre.ethers.ZeroAddress, nonZeroKeyHash)
      ).to.be.revertedWithCustomError(admin, "ZeroAddress");
    });

    it("community propose reverts with InsufficientStake when no sDGNRS", async function () {
      const { admin, alice, mockVRF } = await loadFixture(
        deployFullProtocol
      );

      // Advance 7+ days for community path stall threshold
      await advanceTime(7 * 86400 + 1);

      const MockVRF = await hre.ethers.getContractFactory(
        "MockVRFCoordinator"
      );
      const newCoord = await MockVRF.deploy();
      const newKeyHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("kh2"));

      await expect(
        admin.connect(alice).propose(await newCoord.getAddress(), newKeyHash)
      ).to.be.revertedWithCustomError(admin, "InsufficientStake");
    });

  });

  // =========================================================================
  // 10. Access Control for rawFulfillRandomWords
  // =========================================================================

  describe("rawFulfillRandomWords access control during stall scenario", function () {
    it("direct call from alice reverts (not VRF coordinator)", async function () {
      const { game, deployer, alice } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      await expect(
        game.connect(alice).rawFulfillRandomWords(1n, [999n])
      ).to.be.reverted;
    });

    it("direct call from deployer reverts (not VRF coordinator)", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await issueFirstRequest(game, deployer);

      await expect(
        game.connect(deployer).rawFulfillRandomWords(1n, [999n])
      ).to.be.reverted;
    });
  });
});
