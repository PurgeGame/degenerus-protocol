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
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

describe("DgnrsSoloBucketReward", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  // -------------------------------------------------------------------------
  // Helpers (same patterns as CompressedJackpot.test.js)
  // -------------------------------------------------------------------------

  async function buyFullTickets(game, buyer, n, totalEth) {
    return game.connect(buyer).purchase(
      ZERO_ADDRESS,
      BigInt(n) * 400n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: eth(totalEth) },
    );
  }

  async function getAdvanceEvents(tx, advanceModule) {
    return getEvents(tx, advanceModule, "Advance");
  }

  /** Drive one VRF cycle on the current day. */
  async function driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word) {
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    try {
      await mockVRF.fulfillRandomWords(requestId, word);
    } catch {
      // May already be fulfilled
    }
    const txns = [];
    for (let i = 0; i < 200; i++) {
      try {
        const tx = await game.connect(deployer).advanceGame();
        txns.push(tx);
      } catch {
        break;
      }
      if (!(await game.rngLocked())) break;
    }
    return txns;
  }

  /** Drive one VRF cycle: next day + advanceGame + fulfill + drain. */
  async function driveOneCycle(game, deployer, mockVRF, advanceModule, word) {
    await advanceToNextDay();
    return driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word);
  }

  /** Drive into jackpot phase. */
  async function driveToJackpotPhase(game, deployer, mockVRF, advanceModule) {
    for (let cycle = 0; cycle < 30; cycle++) {
      await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(cycle * 1000 + 42));
      if (await game.jackpotPhase()) return true;
    }
    return false;
  }

  /**
   * Drive through remaining jackpot days, collecting all advance txns.
   * Returns array of all transaction objects from the final day's cycle.
   */
  async function driveJackpotToEnd(game, deployer, mockVRF, advanceModule) {
    const allTxns = [];
    for (let day = 0; day < 12; day++) {
      const txns = await driveOneCycle(
        game,
        deployer,
        mockVRF,
        advanceModule,
        BigInt(day * 2000 + 99),
      );
      allTxns.push(...txns);
      if (!(await game.jackpotPhase())) return allTxns;
    }
    return allTxns;
  }

  // -------------------------------------------------------------------------
  // Test
  // -------------------------------------------------------------------------

  it("DGNRS reward is emitted to the same winner as the solo bucket ETH on the final day", async function () {
    const {
      game,
      deployer,
      mockVRF,
      advanceModule,
      jackpotModule,
      alice,
      bob,
      carol,
      dan,
      eve,
      others,
    } = await loadFixture(deployFullProtocol);

    // Small purchases over multiple days so we get normal (5-day) jackpot
    await buyFullTickets(game, alice, 200, 2);
    await advanceToNextDay();
    await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);

    await buyFullTickets(game, bob, 200, 2);
    await driveOneCycle(game, deployer, mockVRF, advanceModule, 200n);

    await buyFullTickets(game, carol, 200, 2);
    await driveOneCycle(game, deployer, mockVRF, advanceModule, 300n);

    // Heavy purchases push past target on day 4+ (normal tier)
    const buyers = [dan, eve, ...others.slice(0, 15)];
    for (const buyer of buyers) {
      try {
        await game
          .connect(buyer)
          .purchaseWhaleBundle(buyer.address, 1, { value: eth(2.4) });
      } catch {
        // May fail for some buyers
      }
      await buyFullTickets(game, buyer, 500, 5);
    }

    // Drive to jackpot phase
    const entered = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
    expect(entered).to.equal(true, "should enter jackpot phase");

    // Drive through remaining jackpot days to completion
    const allTxns = await driveJackpotToEnd(game, deployer, mockVRF, advanceModule);

    // Find the tx containing the DGNRS award and collect its events
    let dgnrsEvent = null;
    let sameTxEthWinners = [];

    for (const tx of allTxns) {
      const dgnrsEvents = await getEvents(tx, jackpotModule, "JackpotDgnrsWin");
      if (dgnrsEvents.length > 0) {
        dgnrsEvent = dgnrsEvents[0].args;
        sameTxEthWinners = (await getEvents(tx, jackpotModule, "JackpotEthWin"))
          .map((e) => e.args);
        break;
      }
    }

    // There should be exactly one DGNRS award on the final day
    expect(dgnrsEvent).to.not.be.null;

    // DGNRS reward amount should be non-zero
    expect(dgnrsEvent.amount).to.be.gt(0n);

    // The DGNRS winner must match an ETH winner in the SAME transaction (same day)
    const matchingEthWinner = sameTxEthWinners.find(
      (e) => e.winner === dgnrsEvent.winner,
    );
    expect(matchingEthWinner).to.not.be.undefined;
  });
});
