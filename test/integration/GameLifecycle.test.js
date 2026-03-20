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
  ZERO_BYTES32,
  getLastVRFRequestId,
} from "../helpers/testUtils.js";

/**
 * GameLifecycle integration tests.
 *
 * Tests the full purchase → advance → VRF → advance cycle for a game level.
 *
 * Key state machine facts (from DegenerusGame.sol and advance module):
 *  - jackpotPhaseFlag == false  => PURCHASE phase
 *  - jackpotPhaseFlag == true   => JACKPOT phase
 *  - level starts at 0 (purchase phase for level 1)
 *  - Initial price = 0.01 ETH
 *  - Bootstrap prize pool target = 50 ETH
 *  - TICKET_SCALE = 100 (ticketQuantity=100 = 1 full ticket unit)
 *
 * advanceGame():
 *  - Standard flow, always grants BURNIE bounty; requires mint-gate pass (CREATOR bypass).
 *
 * Advance event is emitted by DegenerusGameAdvanceModule (via delegatecall),
 * so it must be parsed with advanceModule.interface, not game.interface.
 *
 * Advance stages (from module constants):
 *  STAGE_RNG_REQUESTED      = 1  (VRF request sent)
 *  STAGE_TICKETS_WORKING    = 5  (batch ticket processing in progress)
 *  STAGE_PURCHASE_DAILY     = 6  (daily purchase-phase jackpot processed, RNG unlocked)
 *
 * VRF flow for first day cycle:
 *  1. advanceGame() → requests VRF → stage=1 (rngLocked=true).
 *  2. mockVRF.fulfillRandomWords(id, word) → rngWordCurrent set (isRngFulfilled=true).
 *  3. advanceGame() → processes word, runs ticket batches → stage=5 repeatedly.
 *  4. advanceGame() again → finishes tickets, unlocks RNG → stage=6, rngLocked=false.
 *
 * Using cap=200 drastically reduces number of batch calls needed vs cap=1.
 * The game pre-queues 16 vault+DGNRS perpetual tickets for each of levels 1-100
 * at construction, so the first advance day must process many queued tickets.
 */
describe("GameLifecycle", function () {
  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /**
   * Parse Advance events from a transaction, using the advanceModule's ABI
   * since the event is emitted in delegatecall context.
   */
  async function getAdvanceEvents(tx, advanceModule) {
    return getEvents(tx, advanceModule, "Advance");
  }

  /**
   * Purchase tickets for a player at the current level (price = 0.01 ETH initially).
   * ticketQuantity=100 = TICKET_SCALE = 1 full ticket unit.
   */
  async function purchaseTickets(
    game,
    player,
    quantity = 100,
    value = eth("0.01")
  ) {
    return game.connect(player).purchase(
      player.address,  // buyer
      quantity,        // ticketQuantity (100 = 1 full ticket at TICKET_SCALE)
      0,               // lootBoxAmount (0 = skip)
      ZERO_BYTES32,    // affiliateCode
      0,               // MintPaymentKind.DirectEth
      { value }
    );
  }

  /**
   * Drive the game through a complete VRF cycle:
   *  1. advanceGame() → triggers VRF request.
   *  2. Fulfill VRF.
   *  3. Call advanceGame() repeatedly until RNG is unlocked.
   *
   * Returns the last Advance event emitted.
   */
  async function driveFullVRFCycle(game, mockVRF, advanceModule, caller) {

    // Step 1: trigger VRF request.
    await game.connect(caller).advanceGame();
    expect(await game.rngLocked()).to.equal(
      true,
      "Expected rngLocked=true after VRF request"
    );

    // Step 2: fulfill VRF.
    const requestId = await getLastVRFRequestId(mockVRF);
    await mockVRF.fulfillRandomWords(requestId, 12345678901234567890n);

    // Step 3: drive advances until RNG unlocks (may need multiple calls for ticket batches).
    let lastAdvanceEvent = null;
    for (let i = 0; i < 30; i++) {
      const locked = await game.rngLocked();
      if (!locked) break;
      const tx = await game.connect(caller).advanceGame();
      const events = await getAdvanceEvents(tx, advanceModule);
      if (events.length > 0) lastAdvanceEvent = events[0];
    }

    return lastAdvanceEvent;
  }

  // ---------------------------------------------------------------------------
  // Basic purchase tests
  // ---------------------------------------------------------------------------

  describe("ticket purchase", function () {
    it("alice can purchase a ticket at level 0 with DirectEth payment", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const tx = await purchaseTickets(game, alice);
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("multiple players can each purchase tickets", async function () {
      const { game, alice, bob, carol } = await loadFixture(deployFullProtocol);

      await purchaseTickets(game, alice);
      await purchaseTickets(game, bob);
      await purchaseTickets(game, carol);

      // purchaseInfo reflects purchase phase and level 1 active ticket level.
      const info = await game.purchaseInfo();
      expect(info.inJackpotPhase).to.equal(false);
      expect(info.lvl).to.equal(1); // active direct-ticket level = level+1 during purchase phase
    });

    it("purchase with zero ETH and zero ticketQuantity reverts", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Sending 0 ETH with 0 ticket quantity should revert (nothing to do).
      await expect(
        game.connect(alice).purchase(
          alice.address,
          0,         // no tickets
          0,         // no lootbox
          ZERO_BYTES32,
          0,
          { value: 0n }
        )
      ).to.be.reverted;
    });

    it("purchase with lootBoxAmount allocates lootbox ETH", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // Send 0.01 ETH ticket + 0.01 ETH lootbox = 0.02 ETH total.
      const tx = await game.connect(alice).purchase(
        alice.address,
        100,
        eth("0.01"), // lootBoxAmount
        ZERO_BYTES32,
        0,
        { value: eth("0.02") }
      );
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("purchasing tickets sends ETH to the game contract", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      const gameAddr = await game.getAddress();
      const balBefore = await hre.ethers.provider.getBalance(gameAddr);

      await purchaseTickets(game, alice, 100, eth("0.01"));

      const balAfter = await hre.ethers.provider.getBalance(gameAddr);
      expect(balAfter).to.be.gt(balBefore);
    });
  });

  // ---------------------------------------------------------------------------
  // advanceGame – first call (triggers VRF request)
  // ---------------------------------------------------------------------------

  describe("advanceGame first call", function () {
    it("succeeds on deploy day (dailyIdx=0 < day=1, so NotTimeYet is not triggered)", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      // dailyIdx starts at 0; day index = 1 on deploy day, so the game immediately
      // allows advancing. cap=1 bypasses mint gate; deployer is also CREATOR.
      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);

      // VRF request should have been sent.
      expect(await game.rngLocked()).to.equal(true);
    });

    it("after advancing to next day, advanceGame() issues a VRF request", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      expect(await game.rngLocked()).to.equal(true);
      const lastId = await getLastVRFRequestId(mockVRF);
      expect(lastId).to.be.gt(0);
    });

    it("advanceGame emits Advance(stage=1) on VRF request (parsed from module ABI)", async function () {
      const { game, deployer, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      const tx = await game.connect(deployer).advanceGame();
      const events = await getAdvanceEvents(tx, advanceModule);

      expect(events.length).to.be.gt(0);
      // STAGE_RNG_REQUESTED = 1
      expect(events[0].args.stage).to.equal(1);
    });
  });

  // ---------------------------------------------------------------------------
  // VRF fulfillment
  // ---------------------------------------------------------------------------

  describe("VRF fulfillment", function () {
    it("fulfilling VRF sets isRngFulfilled to true while rngLocked remains true", async function () {
      const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      expect(await game.rngLocked()).to.equal(true);
      expect(await game.isRngFulfilled()).to.equal(false);

      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 99999n);

      // Word stored; RNG still locked until advanceGame processes it.
      expect(await game.isRngFulfilled()).to.equal(true);
      expect(await game.rngLocked()).to.equal(true);
    });

    it("subsequent advanceGame calls after fulfillment eventually unlock RNG", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 42n);

      // Process tickets and unlock – may take multiple calls.
      let unlocked = false;
      for (let i = 0; i < 30; i++) {
        if (!await game.rngLocked()) { unlocked = true; break; }
        await game.connect(deployer).advanceGame();
      }

      expect(unlocked).to.equal(true);
      expect(await game.rngLocked()).to.equal(false);
      expect(await game.isRngFulfilled()).to.equal(false);
    });

    it("after unlock, stage=6 (STAGE_PURCHASE_DAILY) is emitted", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 777n);

      let finalStage = null;
      for (let i = 0; i < 30; i++) {
        if (!await game.rngLocked()) break;
        const tx = await game.connect(deployer).advanceGame();
        const events = await getAdvanceEvents(tx, advanceModule);
        if (events.length > 0) finalStage = Number(events[0].args.stage);
      }

      // STAGE_PURCHASE_DAILY = 6 is emitted when the daily jackpot is processed
      // and RNG is unlocked.
      expect(finalStage).to.equal(6);
    });
  });

  // ---------------------------------------------------------------------------
  // Full day cycle
  // ---------------------------------------------------------------------------

  describe("full day advance cycle", function () {
    it("driveFullVRFCycle completes without reverting", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await driveFullVRFCycle(game, mockVRF, advanceModule, deployer);

      // RNG should be unlocked at the end.
      expect(await game.rngLocked()).to.equal(false);
    });

    it("remains in purchase phase after first daily advance cycle (prize target not met)", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await driveFullVRFCycle(game, mockVRF, advanceModule, deployer);

      // Without 50 ETH in prize pool, still purchase phase.
      expect(await game.jackpotPhase()).to.equal(false);
    });

    it("level stays at 0 during purchase phase until prize target met", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await driveFullVRFCycle(game, mockVRF, advanceModule, deployer);

      expect(await game.level()).to.equal(0);
    });

    it("three consecutive daily cycles all complete without revert", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      for (let day = 1; day <= 3; day++) {
        await advanceToNextDay();
        await driveFullVRFCycle(game, mockVRF, advanceModule, deployer);
        expect(await game.rngLocked()).to.equal(
          false,
          `Day ${day}: expected RNG unlocked after full cycle`
        );
      }
    });

    it("game is not over and not in jackpot phase after multiple purchase-phase cycles", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      for (let day = 0; day < 3; day++) {
        await advanceToNextDay();
        await driveFullVRFCycle(game, mockVRF, advanceModule, deployer);
      }

      expect(await game.gameOver()).to.equal(false);
      expect(await game.jackpotPhase()).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Prize pool accumulation
  // ---------------------------------------------------------------------------

  describe("prize pool accumulation", function () {
    it("futurePrizePoolView returns non-zero after tickets are purchased", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await purchaseTickets(game, alice, 100, eth("0.01"));

      // futurePrizePool receives 10% (PURCHASE_TO_FUTURE_BPS=1000) of prize contribution.
      const future = await game.futurePrizePoolView();
      expect(future).to.be.gt(0n);
    });

    it("multiple purchases accumulate in the future prize pool", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      await purchaseTickets(game, alice, 100, eth("0.01"));
      const futureAfterAlice = await game.futurePrizePoolView();

      await purchaseTickets(game, bob, 100, eth("0.01"));
      const futureAfterBob = await game.futurePrizePoolView();

      expect(futureAfterBob).to.be.gt(futureAfterAlice);
    });
  });

  // ---------------------------------------------------------------------------
  // Operator approval
  // ---------------------------------------------------------------------------

  describe("operator approval", function () {
    it("bob can purchase on behalf of alice when alice approves bob as operator", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      await game.connect(alice).setOperatorApproval(bob.address, true);
      expect(await game.isOperatorApproved(alice.address, bob.address)).to.equal(true);

      // Bob purchases on behalf of alice.
      const tx = await game.connect(bob).purchase(
        alice.address,
        100,
        0,
        ZERO_BYTES32,
        0,
        { value: eth("0.01") }
      );
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("setOperatorApproval emits OperatorApproval event", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      await expect(game.connect(alice).setOperatorApproval(bob.address, true))
        .to.emit(game, "OperatorApproval")
        .withArgs(alice.address, bob.address, true);
    });

    it("revoking operator approval prevents further purchases on behalf", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      await game.connect(alice).setOperatorApproval(bob.address, true);
      await game.connect(alice).setOperatorApproval(bob.address, false);

      expect(await game.isOperatorApproved(alice.address, bob.address)).to.equal(false);
    });

    it("unapproved bob cannot purchase on behalf of alice", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);

      // bob is not approved — purchasing on behalf of alice should revert.
      await expect(
        game.connect(bob).purchase(
          alice.address,
          100,
          0,
          ZERO_BYTES32,
          0,
          { value: eth("0.01") }
        )
      ).to.be.revertedWithCustomError(game, "NotApproved");
    });
  });

  // ---------------------------------------------------------------------------
  // purchaseInfo consistency
  // ---------------------------------------------------------------------------

  describe("purchaseInfo view", function () {
    it("returns initial state immediately after deploy", async function () {
      const { game } = await loadFixture(deployFullProtocol);

      const info = await game.purchaseInfo();
      expect(info.inJackpotPhase).to.equal(false);
      expect(info.rngLocked_).to.equal(false);
      expect(info.priceWei).to.equal(eth("0.01"));
      // Active ticket level = level+1 = 1 during purchase phase at level 0.
      expect(info.lvl).to.equal(1);
    });

    it("priceWei remains 0.01 ETH before level 5", async function () {
      const { game } = await loadFixture(deployFullProtocol);

      expect(await game.mintPrice()).to.equal(eth("0.01"));
    });

    it("rngLocked_ is true in purchaseInfo while VRF is pending", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      const info = await game.purchaseInfo();
      expect(info.rngLocked_).to.equal(true);
    });

    it("rngLocked_ is false in purchaseInfo after VRF cycle completes", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(deployFullProtocol);

      await advanceToNextDay();
      await driveFullVRFCycle(game, mockVRF, advanceModule, deployer);

      const info = await game.purchaseInfo();
      expect(info.rngLocked_).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Mint data tracking
  // ---------------------------------------------------------------------------

  describe("mint data tracking", function () {
    it("ethMintLastLevel records alice's last ETH mint level", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await purchaseTickets(game, alice);

      // Alice minted at level 0 → active ticket level = 1 during purchase phase.
      // ethMintLastLevel should reflect the level where she minted.
      const lastLevel = await game.ethMintLastLevel(alice.address);
      // Level 1 is the active ticket level for direct purchases during purchase phase.
      expect(lastLevel).to.equal(1);
    });

    it("ethMintStreakCount is 0 before any level completes (streak requires level completion)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // The streak counts consecutive *completed* levels, not just purchases.
      // A single purchase at level 0/1 does not complete a level, so streak = 0.
      await purchaseTickets(game, alice);

      const streak = await game.ethMintStreakCount(alice.address);
      expect(streak).to.equal(0);
    });

    it("ethMintLevelCount increments with each level of purchase", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await purchaseTickets(game, alice);

      const count = await game.ethMintLevelCount(alice.address);
      expect(count).to.equal(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Coinflip BAF-only lock (deposits only locked at level % 10 == 0)
  // ---------------------------------------------------------------------------

  describe("coinflip BAF-only deposit lock", function () {
    it("coinflip deposit is NOT locked during RNG at level 0 (purchaseLevel=1, not BAF)", async function () {
      const { game, coinflip, coin, deployer, alice, vault } =
        await loadFixture(deployFullProtocol);

      // Give alice BURNIE for coinflip deposit
      const vaultAddr = await vault.getAddress();
      await hre.ethers.provider.send("hardhat_setBalance", [
        vaultAddr,
        "0x1000000000000000000",
      ]);
      await hre.ethers.provider.send("hardhat_impersonateAccount", [vaultAddr]);
      const vaultSigner = await hre.ethers.getSigner(vaultAddr);
      await coin.connect(vaultSigner).vaultEscrow(eth(1000));
      await coin.connect(vaultSigner).vaultMintTo(alice.address, eth(1000));
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [
        vaultAddr,
      ]);

      // Trigger RNG lock (level 0, purchaseLevel = 1 → 1 % 10 != 0)
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      expect(await game.rngLocked()).to.equal(true);

      // Coinflip deposit should NOT revert with CoinflipLocked since level is not BAF
      await expect(
        coinflip
          .connect(alice)
          .depositCoinflip("0x0000000000000000000000000000000000000000", eth(100))
      ).to.not.be.revertedWithCustomError(coinflip, "CoinflipLocked");
    });
  });

  // ---------------------------------------------------------------------------
  // Pool consolidation (replaces level jackpot — no separate stages 8/9)
  // ---------------------------------------------------------------------------

  describe("pool consolidation", function () {
    it("transition completes without legacy level jackpot stages (8/9)", async function () {
      const { game, deployer, mockVRF, advanceModule } = await loadFixture(
        deployFullProtocol
      );

      // Drive a full VRF cycle and collect all advance stages emitted
      await advanceToNextDay();
      await game.connect(deployer).advanceGame(); // RNG request → stage 1
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 42n);

      const allStages = [];
      for (let i = 0; i < 30; i++) {
        if (!(await game.rngLocked())) break;
        const tx = await game.connect(deployer).advanceGame();
        const events = await getAdvanceEvents(tx, advanceModule);
        for (const e of events) allStages.push(Number(e.args.stage));
      }

      // Stages 8 (LEVEL_JACKPOT_LOOTBOX) and 9 (LEVEL_JACKPOT_ETH) should never appear
      expect(allStages).to.not.include(8);
      expect(allStages).to.not.include(9);
    });
  });
});
