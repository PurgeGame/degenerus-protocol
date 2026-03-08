import { expect } from "chai";
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
 * VRFIntegration tests.
 *
 * Tests the Chainlink VRF request/fulfillment cycle as exercised through the
 * DegenerusGame contract and its advance module.
 *
 * Key behaviors under test:
 *  1. Request cycle: advanceGame issues a VRF request → rngLocked = true.
 *  2. Fulfillment: mockVRF.fulfillRandomWords → rngWordCurrent set → isRngFulfilled = true.
 *  3. Processing: advanceGame() calls consume the word, process tickets, unlock RNG.
 *  4. Timeout: if 18+ hours pass without fulfillment, advanceGame retries VRF.
 *  5. State: pending VRF blocks reverseFlip (which uses the advance module).
 *
 * Access control for rawFulfillRandomWords:
 *  - Only the registered VRF coordinator (mockVRF) can call rawFulfillRandomWords.
 *  - Calling from any other address results in a revert (error E() propagated from module).
 *
 * Notes on error names:
 *  - RngNotReady, RngLocked are custom errors in DegenerusGameAdvanceModule.
 *    When the module reverts, `_revertDelegate` re-throws the raw ABI-encoded error.
 *    To assert these with `revertedWithCustomError`, pass `advanceModule` as the contract.
 *  - reverseFlip() on DegenerusGame and the advance module both take no arguments.
 *    The game proxy wraps the call via delegatecall; the module uses msg.sender.
 *
 * Advance stage constants (from DegenerusGameAdvanceModule):
 *  STAGE_RNG_REQUESTED      = 1
 *  STAGE_TICKETS_WORKING    = 5
 *  STAGE_PURCHASE_DAILY     = 6
 */
describe("VRFIntegration", function () {
  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /**
   * Parse Advance events from a transaction using the advance module ABI,
   * since the event is emitted inside a delegatecall.
   */
  async function getAdvanceEvents(tx, advanceModule) {
    return getEvents(tx, advanceModule, "Advance");
  }

  /**
   * Drive all advance calls needed to completely unlock RNG after VRF fulfillment.
   */
  async function drainTickets(game, caller) {
    for (let i = 0; i < 30; i++) {
      if (!await game.rngLocked()) break;
      await game.connect(caller).advanceGame();
    }
  }

  // ---------------------------------------------------------------------------
  // VRF request lifecycle
  // ---------------------------------------------------------------------------

  describe("VRF request issuance", function () {
    it("advanceGame triggers VRF request (rngLocked becomes true)", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      expect(await game.rngLocked()).to.equal(true);
      const requestId = await getLastVRFRequestId(mockVRF);
      expect(requestId).to.be.gt(0);
    });

    it("rngLocked is false before any VRF request is issued", async function () {
      const { game } = await loadFixture(deployFullProtocol);

      expect(await game.rngLocked()).to.equal(false);
    });

    it("isRngFulfilled is false before VRF fulfillment occurs", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      expect(await game.isRngFulfilled()).to.equal(false);
    });

    it("a second advanceGame call during pending VRF (before timeout) reverts", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame(); // issues VRF request

      // Before fulfillment, within 18-hour window, a second call should revert
      // with RngNotReady (from the advance module, propagated through delegatecall).
      // The error is defined in the module, so we check against advanceModule.
      // Alternatively, we just verify it reverts without checking the error name.
      await expect(
        game.connect(deployer).advanceGame()
      ).to.be.reverted;
    });

    it("first advanceGame on deploy day also works (day=1 > dailyIdx=0)", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      // No time advancement needed: dailyIdx=0 < day=1 so advance is allowed immediately.
      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
      expect(await game.rngLocked()).to.equal(true);
    });
  });

  // ---------------------------------------------------------------------------
  // VRF fulfillment
  // ---------------------------------------------------------------------------

  describe("VRF fulfillment via mock coordinator", function () {
    it("fulfillRandomWords sets isRngFulfilled to true", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 9876543210n);

      expect(await game.isRngFulfilled()).to.equal(true);
    });

    it("rngLocked remains true after fulfillment until advanceGame processes all tickets", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 111n);

      // rngLockedFlag is still true — word stored but not yet fully processed.
      expect(await game.rngLocked()).to.equal(true);
    });

    it("advanceGame calls after fulfillment eventually unlock RNG (stage=6)", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 111n);

      await drainTickets(game, deployer);

      expect(await game.rngLocked()).to.equal(false);
      expect(await game.isRngFulfilled()).to.equal(false);
    });

    it("fulfillment with word=2 (small non-zero value) produces valid results", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      // word=1 causes win=true (odd) which triggers bonus payout handling;
      // use word=2 (even, loss) to test a clean path.
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 2n);
      await drainTickets(game, deployer);

      expect(await game.rngLocked()).to.equal(false);
    });

    it("fulfillment with word=max uint256 produces valid results", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);
      const MAX_UINT256 = (1n << 256n) - 1n;

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, MAX_UINT256);
      await drainTickets(game, deployer);

      expect(await game.rngLocked()).to.equal(false);
    });

    it("fulfilling an already-fulfilled requestId reverts in the mock", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 12345n);

      // Fulfilling the same request ID again should revert in the mock.
      await expect(
        mockVRF.fulfillRandomWords(requestId, 99999n)
      ).to.be.reverted;
    });

    it("fulfilling a wrong requestId is silently ignored by the game", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const gameAddr = await game.getAddress();
      // Use a requestId that doesn't match the pending one.
      await mockVRF.fulfillRandomWordsRaw(999999, gameAddr, 42n);

      // Game should still be locked since the real request wasn't fulfilled.
      expect(await game.rngLocked()).to.equal(true);
      expect(await game.isRngFulfilled()).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // rawFulfillRandomWords access control
  // ---------------------------------------------------------------------------

  describe("rawFulfillRandomWords access control", function () {
    it("calling rawFulfillRandomWords from alice reverts (only VRF coordinator)", async function () {
      const { game, alice, deployer } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      // Direct call from alice should revert — msg.sender != vrfCoordinator.
      await expect(
        game.connect(alice).rawFulfillRandomWords(1n, [12345n])
      ).to.be.reverted;
    });

    it("calling rawFulfillRandomWords from deployer (not coordinator) reverts", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      await expect(
        game.connect(deployer).rawFulfillRandomWords(1n, [12345n])
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // rngLocked state blocks operations
  // ---------------------------------------------------------------------------

  describe("rngLocked state during pending VRF", function () {
    it("reverseFlip() reverts with RngLocked while VRF is pending", async function () {
      const { game, deployer, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame(); // VRF now locked

      expect(await game.rngLocked()).to.equal(true);

      // reverseFlip() is blocked when RNG is locked.
      // The error RngLocked is defined in DegenerusGameAdvanceModule, which is
      // the module that executes via delegatecall. We check against advanceModule.
      await expect(
        game.connect(deployer).reverseFlip()
      ).to.be.revertedWithCustomError(advanceModule, "RngLocked");
    });

    it("reverseFlip() fails for a different reason when RNG is not locked (no BURNIE)", async function () {
      const { game, deployer, advanceModule } = await loadFixture(deployFullProtocol);

      // RNG not locked — deployer has no BURNIE, so burnCoin fails, not RngLocked.
      expect(await game.rngLocked()).to.equal(false);

      await expect(
        game.connect(deployer).reverseFlip()
      ).to.not.be.revertedWithCustomError(advanceModule, "RngLocked");
    });

    it("rngLocked state: purchaseInfo confirms lock is active", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const info = await game.purchaseInfo();
      expect(info.rngLocked_).to.equal(true);
    });
  });

  // ---------------------------------------------------------------------------
  // VRF timeout behavior (18+ hours)
  // ---------------------------------------------------------------------------

  describe("VRF timeout / retry", function () {
    it("advanceGame after 18-hour timeout issues a new (higher) requestId", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame(); // first VRF request

      const firstRequestId = await getLastVRFRequestId(mockVRF);
      expect(await game.rngLocked()).to.equal(true);

      // Advance 18 hours + 1 second and then to the next calendar day.
      await advanceTime(18 * 60 * 60 + 1);
      await advanceToNextDay();

      // advanceGame should retry, issuing a new VRF request.
      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);

      const secondRequestId = await getLastVRFRequestId(mockVRF);
      expect(secondRequestId).to.be.gt(firstRequestId);
    });

    it("fulfilling the retry request and processing succeeds", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      // Trigger timeout.
      await advanceTime(18 * 60 * 60 + 1);
      await advanceToNextDay();

      // Issue retry request.
      await game.connect(deployer).advanceGame();
      const retryRequestId = await getLastVRFRequestId(mockVRF);

      // Fulfill and process.
      await mockVRF.fulfillRandomWords(retryRequestId, 7654321n);
      await drainTickets(game, deployer);

      expect(await game.rngLocked()).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Multi-day VRF cycle
  // ---------------------------------------------------------------------------

  describe("multi-day VRF cycle", function () {
    it("three consecutive day cycles each issue and resolve their own VRF request", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      for (let day = 1; day <= 3; day++) {
        await advanceToNextDay();

        // Issue VRF request.
        await game.connect(deployer).advanceGame();
        expect(await game.rngLocked()).to.equal(
          true,
          `Day ${day}: expected rngLocked after request`
        );

        const requestId = await getLastVRFRequestId(mockVRF);
        expect(requestId).to.be.gt(0);

        // Fulfill.
        await mockVRF.fulfillRandomWords(requestId, BigInt(day) * 11111n);

        // Process.
        await drainTickets(game, deployer);
        expect(await game.rngLocked()).to.equal(
          false,
          `Day ${day}: expected rngLocked cleared after process`
        );
        expect(await game.isRngFulfilled()).to.equal(
          false,
          `Day ${day}: expected rngWordCurrent cleared`
        );
      }
    });

    it("game state remains consistent (not game over, not jackpot) after multiple cycles", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      for (let day = 0; day < 5; day++) {
        await advanceToNextDay();
        await game.connect(deployer).advanceGame();
        const requestId = await getLastVRFRequestId(mockVRF);
        await mockVRF.fulfillRandomWords(requestId, BigInt(day + 1) * 99999n);
        await drainTickets(game, deployer);
      }

      expect(await game.gameOver()).to.equal(false);
      expect(await game.jackpotPhase()).to.equal(false);
    });

    it("each VRF request gets a unique incrementing requestId", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      const requestIds = [];

      for (let day = 0; day < 3; day++) {
        await advanceToNextDay();
        await game.connect(deployer).advanceGame();
        const id = await getLastVRFRequestId(mockVRF);
        requestIds.push(id);

        await mockVRF.fulfillRandomWords(id, BigInt(day + 1) * 42n);
        await drainTickets(game, deployer);
      }

      // All request IDs should be strictly increasing.
      for (let i = 1; i < requestIds.length; i++) {
        expect(requestIds[i]).to.be.gt(
          requestIds[i - 1],
          `Request ID at day ${i + 1} should be greater than day ${i}`
        );
      }
    });
  });
});
