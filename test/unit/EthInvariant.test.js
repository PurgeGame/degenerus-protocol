/**
 * @file EthInvariant.test.js
 * @description ETH solvency invariant tests for Degenerus protocol (Phase 08 audit, ACCT-01, ACCT-08).
 *
 * Tests the solvency invariant:
 *   game.balance + steth.balanceOf(game) >= currentPool + nextPool + futurePool + claimablePool
 *
 * across 7 state sequences:
 *   1. Fresh deploy
 *   2. After purchase
 *   3. After advanceGame (VRF request)
 *   4. After VRF fulfillment + processing
 *   5. After claimWinnings (if any winner)
 *   6. After adminStakeEthForStEth
 *   7. Game-over terminal state (ACCT-08)
 *
 * ACCT-02 context: All 11 _creditClaimable call sites were verified PASS in plan 08-01.
 * No known FINDING sites exist. If this test fails unexpectedly, it is a new ACCT-01 finding.
 */

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
import {
  assertSolvencyInvariant,
  assertClaimablePoolConsistency,
} from "../helpers/invariantUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

// 912 days in seconds — pre-game liveness timeout
const SECONDS_912_DAYS = 912 * 86400;

describe("EthInvariant (ACCT-01, ACCT-08)", function () {
  after(function () {
    restoreAddresses();
  });

  // ===========================================================================
  // Checkpoint 1: Fresh deploy
  // ===========================================================================
  it("1. Fresh deploy — solvency invariant holds", async function () {
    const { game, mockStETH } = await loadFixture(deployFullProtocol);
    // ACCT-02 context: no FINDING sites — this should always pass
    await assertSolvencyInvariant(game, mockStETH);
  });

  // ===========================================================================
  // Checkpoint 2: After purchase
  // ===========================================================================
  it("2. After purchase — solvency invariant holds", async function () {
    const { game, mockStETH, alice } = await loadFixture(deployFullProtocol);

    // Purchase 1 full ticket (qty=400 = 1 ticket at mintPrice=0.01 ETH)
    // Cost: (priceWei * ticketQuantity) / 400 = 0.01 ETH * 400 / 400 = 0.01 ETH
    const priceWei = await game.mintPrice(); // 0.01 ETH
    await game.connect(alice).purchase(
      ZERO_ADDRESS, // buyer = msg.sender
      400n,         // 4 scaled tickets = 1 full ticket
      0n,           // no lootbox
      ZERO_BYTES32, // no affiliate
      MintPaymentKind.DirectEth,
      { value: priceWei }
    );

    await assertSolvencyInvariant(game, mockStETH);
  });

  // ===========================================================================
  // Checkpoint 3: After advanceGame (VRF request issued)
  // ===========================================================================
  it("3. After advanceGame (VRF request) — solvency invariant holds", async function () {
    const { game, mockStETH, deployer } = await loadFixture(deployFullProtocol);

    // Advance to next day and call advanceGame — this issues a VRF request
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();

    await assertSolvencyInvariant(game, mockStETH);
  });

  // ===========================================================================
  // Checkpoint 4: After VRF fulfillment + processing
  // ===========================================================================
  it("4. After VRF fulfillment — solvency invariant holds", async function () {
    const { game, mockStETH, deployer, mockVRF } = await loadFixture(
      deployFullProtocol
    );

    // Advance and trigger VRF
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();

    const requestId = await getLastVRFRequestId(mockVRF);
    if (requestId > 0n) {
      await mockVRF.fulfillRandomWords(requestId, 123456n);

      // Process the fulfilled word (may take multiple advanceGame calls)
      for (let i = 0; i < 15; i++) {
        if (!(await game.rngLocked())) break;
        await game.connect(deployer).advanceGame();
      }
    }

    // ACCT-02 context: no FINDING sites — all jackpot distributions correctly paired
    await assertSolvencyInvariant(game, mockStETH);
  });

  // ===========================================================================
  // Checkpoint 5: After claimWinnings
  // ===========================================================================
  it("5. After claimWinnings — solvency invariant holds (1-wei sentinel preserved)", async function () {
    const { game, mockStETH, alice } = await loadFixture(deployFullProtocol);

    // Purchase tickets first to ensure some ETH is in the pools
    const priceWei = await game.mintPrice();
    await game.connect(alice).purchase(
      ZERO_ADDRESS,
      400n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: priceWei }
    );

    // Check if alice has any claimable winnings (may be 0 at level 0)
    const aliceClaimable = await game.claimableWinningsOf(alice.address);
    if (aliceClaimable > 1n) {
      // Alice has winnings — claim them
      await game.connect(alice).claimWinnings(alice.address);
    }

    // The solvency invariant holds after claimWinnings.
    // NOTE: claimablePool is NOT zero — 1-wei sentinel remains per the protocol design.
    // Do NOT assert claimablePool == 0 here.
    await assertSolvencyInvariant(game, mockStETH);
    await assertClaimablePoolConsistency(game, [alice.address]);
  });

  // ===========================================================================
  // Checkpoint 6: After adminStakeEthForStEth
  // ===========================================================================
  it("6. After adminStakeEthForStEth — solvency invariant holds (ETH→stETH conversion)", async function () {
    const { game, mockStETH, deployer, alice, admin } = await loadFixture(
      deployFullProtocol
    );

    // Purchase to put ETH into the game contract
    const priceWei = await game.mintPrice();
    await game.connect(alice).purchase(
      ZERO_ADDRESS,
      400n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: priceWei }
    );

    // Check if there is any stakeable ETH (ethBal > claimablePool)
    const gameAddr = await game.getAddress();
    const ethBal = await hre.ethers.provider.getBalance(gameAddr);
    const claimablePool = await game.claimablePoolView();

    if (ethBal > claimablePool) {
      // Stake a small portion (1 wei more than claimablePool gives minimum stakeable)
      const stakeable = ethBal - claimablePool;
      if (stakeable > 0n) {
        const stakeAmount = stakeable / 2n; // Stake half the available ETH
        if (stakeAmount > 0n) {
          // Admin calls stakeGameEthToStEth (which calls game.adminStakeEthForStEth internally)
          // deployer is CREATOR = onlyOwner on admin
          await admin.connect(deployer).stakeGameEthToStEth(stakeAmount);
        }
      }
    }

    // After staking, ETH decreases but stETH increases — invariant still holds
    await assertSolvencyInvariant(game, mockStETH);
  });

  // ===========================================================================
  // Checkpoint 7: Game-over terminal state (ACCT-08)
  // ===========================================================================
  it("7. Game-over terminal state — solvency invariant holds (ACCT-08)", async function () {
    const { game, mockStETH, deployer, mockVRF, alice } = await loadFixture(
      deployFullProtocol
    );

    // Purchase some tickets first to fund the pools
    const priceWei = await game.mintPrice();
    await game.connect(alice).purchase(
      ZERO_ADDRESS,
      400n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: priceWei }
    );

    // Trigger game-over via 912-day liveness timeout (level 0)
    // This is the established pattern from GameOver.test.js
    await advanceTime(SECONDS_912_DAYS + 86400);

    // Step 1: advanceGame issues VRF request (but does NOT set gameOver yet)
    await game.connect(deployer).advanceGame();

    // Step 2: Fulfill VRF
    const requestId = await getLastVRFRequestId(mockVRF);
    if (requestId > 0n) {
      await mockVRF.fulfillRandomWords(requestId, 42n);
    }

    // Step 3: advanceGame processes word → handleGameOverDrain → gameOver = true
    await game.connect(deployer).advanceGame();

    // Verify game is over
    expect(await game.gameOver()).to.equal(
      true,
      "Game should be over after 912-day timeout"
    );

    // ACCT-08: Solvency invariant holds in game-over terminal state
    await assertSolvencyInvariant(game, mockStETH);

    // Also verify per-player consistency for alice (may have no winnings at level 0)
    await assertClaimablePoolConsistency(game, [alice.address, deployer.address]);
  });
});
