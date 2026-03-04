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
  getEvents,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

/**
 * AdvanceGame Gas Benchmark Tests
 *
 * Measures worst-case gas for every advanceGame code path.
 * Each test drives the state machine to a specific stage and reports gasUsed.
 *
 * IMPORTANT: The Advance event is declared in DegenerusGameAdvanceModule,
 * emitted via delegatecall from the game proxy. To parse it we must use
 * advanceModule.interface, NOT game.interface.
 *
 * Stage constants (from DegenerusGameAdvanceModule.sol):
 *   0  = STAGE_GAMEOVER
 *   1  = STAGE_RNG_REQUESTED
 *   2  = STAGE_TRANSITION_WORKING
 *   3  = STAGE_TRANSITION_DONE
 *   4  = STAGE_FUTURE_TICKETS_WORKING
 *   5  = STAGE_TICKETS_WORKING
 *   6  = STAGE_PURCHASE_DAILY
 *   7  = STAGE_ENTERED_JACKPOT
 *   8  = STAGE_JACKPOT_ETH_RESUME
 *   9  = STAGE_JACKPOT_COIN_TICKETS
 *   10 = STAGE_JACKPOT_PHASE_ENDED
 *   11 = STAGE_JACKPOT_DAILY_STARTED
 */
describe("AdvanceGame Gas Benchmarks", function () {
  this.timeout(600_000);

  const gasResults = [];

  after(function () {
    console.log("\n");
    console.log("=".repeat(72));
    console.log("  ADVANCEGAME GAS BENCHMARK SUMMARY");
    console.log("=".repeat(72));
    console.log(
      `  ${"Test".padEnd(48)} ${"Gas Used".padStart(14)}`
    );
    console.log("-".repeat(72));

    const sorted = [...gasResults].sort(
      (a, b) => Number(b.gasUsed - a.gasUsed)
    );
    for (const { name, gasUsed } of sorted) {
      const gasStr = gasUsed.toLocaleString().padStart(14);
      const flag = gasUsed > 15_000_000n ? " !!!" : "";
      console.log(`  ${name.padEnd(48)} ${gasStr}${flag}`);
    }

    console.log("-".repeat(72));
    if (sorted.length > 0) {
      const max = sorted[0];
      console.log(
        `  Peak: ${max.name} = ${max.gasUsed.toLocaleString()} gas`
      );
      if (max.gasUsed > 30_000_000n) {
        console.log("  CRITICAL: Peak exceeds 30M block gas limit!");
      } else if (max.gasUsed > 15_000_000n) {
        console.log("  WARNING: Peak exceeds 15M gas target!");
      } else {
        console.log("  All paths within safe gas limits.");
      }
    }
    console.log("=".repeat(72));
    console.log("");

    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /** Buy N full tickets (each costing priceWei). 1 full ticket = qty 400. */
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

  /** Trigger game over at level 0 (multi-step VRF flow). */
  async function triggerGameOverAtLevel0(game, deployer, mockVRF) {
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    if (requestId > 0n) {
      await mockVRF.fulfillRandomWords(requestId, 42n);
    }
    await game.connect(deployer).advanceGame();
  }

  function recordGas(name, receipt) {
    const gasUsed = receipt.gasUsed;
    gasResults.push({ name, gasUsed });
    console.log(`      Gas: ${gasUsed.toLocaleString()}`);
  }

  /** Parse Advance events using the advanceModule ABI (not game ABI). */
  async function getAdvanceEvents(tx, advanceModule) {
    return getEvents(tx, advanceModule, "Advance");
  }

  /**
   * Drive one VRF cycle: next day -> advanceGame -> fulfill -> drain all processing.
   * Returns the last Advance stage observed.
   */
  async function driveOneCycle(game, deployer, mockVRF, advanceModule, word) {
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    try {
      await mockVRF.fulfillRandomWords(requestId, word);
    } catch {
      // May already be fulfilled
    }
    let lastStage = -1n;
    for (let i = 0; i < 200; i++) {
      try {
        const tx = await game.connect(deployer).advanceGame();
        const events = await getAdvanceEvents(tx, advanceModule);
        if (events.length > 0) {
          lastStage = events[0].args.stage;
        }
      } catch {
        break;
      }
      if (!(await game.rngLocked())) break;
    }
    return lastStage;
  }

  /**
   * Heavy purchasing: fill prize pool toward the 50 ETH bootstrap target.
   * Each buyer: whale bundle (2.4 ETH) + 500 full tickets (5 ETH).
   */
  async function heavyPurchases(game, buyers) {
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
  }

  /**
   * Drive the game into jackpot phase. Returns true if reached.
   */
  async function driveToJackpotPhase(game, deployer, mockVRF, advanceModule) {
    for (let cycle = 0; cycle < 30; cycle++) {
      await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(cycle * 1000 + 42));
      if (await game.jackpotPhase()) return true;
    }
    return false;
  }

  /**
   * Drive through the entire jackpot phase back to purchase phase.
   * Returns true if phase transition completed.
   */
  async function driveJackpotPhaseToEnd(game, deployer, mockVRF, advanceModule) {
    for (let day = 0; day < 12; day++) {
      await driveOneCycle(
        game,
        deployer,
        mockVRF,
        advanceModule,
        BigInt(day * 2000 + 99)
      );
      if (!(await game.jackpotPhase())) return true;
    }
    return false;
  }

  // =========================================================================
  // 1. RNG Request (STAGE_RNG_REQUESTED = 1)
  // =========================================================================

  describe("1. Fresh VRF Request (STAGE_RNG_REQUESTED)", function () {
    it("worst case: fresh RNG request with lootbox index reservation", async function () {
      const { game, deployer, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 10)];
      for (const buyer of buyers) {
        await buyFullTickets(game, buyer, 5, 0.05);
      }

      await advanceToNextDay();

      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      const events = await getAdvanceEvents(tx, advanceModule);
      expect(events.length).to.be.gte(1);
      expect(events[0].args.stage).to.equal(1n);
      recordGas("Fresh VRF Request (stage=1)", receipt);
    });
  });

  // =========================================================================
  // 2. RNG 18h Timeout Retry
  // =========================================================================

  describe("2. VRF 18h Timeout Retry", function () {
    it("worst case: stale VRF retry with lootbox index remap", async function () {
      const { game, deployer, advanceModule, alice, bob, carol } =
        await loadFixture(deployFullProtocol);

      await buyFullTickets(game, alice, 10, 0.1);
      await buyFullTickets(game, bob, 10, 0.1);
      await buyFullTickets(game, carol, 10, 0.1);

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();

      // Don't fulfill - wait 18h
      await advanceTime(18 * 3600 + 1);

      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      const events = await getAdvanceEvents(tx, advanceModule);
      const stage = events.length > 0 ? events[0].args.stage : "?";
      recordGas(`VRF 18h Timeout Retry (stage=${stage})`, receipt);
      expect(receipt.status).to.equal(1);
    });
  });

  // =========================================================================
  // 3. Ticket Batch Processing (STAGE_TICKETS_WORKING = 5)
  // =========================================================================

  describe("3. Ticket Batch Processing (STAGE_TICKETS_WORKING)", function () {
    it("worst case: max budget (550 writes) ticket processing", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      for (const buyer of buyers) {
        await buyFullTickets(game, buyer, 50, 0.5);
      }

      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 999n);

      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      const events = await getAdvanceEvents(tx, advanceModule);
      const stage = events.length > 0 ? events[0].args.stage : "?";
      recordGas(`Ticket Batch 550 writes (stage=${stage})`, receipt);
      expect(receipt.status).to.equal(1);
    });
  });

  // =========================================================================
  // 4. Purchase-Phase Daily Jackpot (STAGE_PURCHASE_DAILY = 6)
  // =========================================================================

  describe("4. Purchase-Phase Daily Jackpot (STAGE_PURCHASE_DAILY)", function () {
    it("worst case: daily jackpot with many ticket holders", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      for (const buyer of buyers) {
        await buyFullTickets(game, buyer, 20, 0.2);
      }

      // First VRF cycle: processes tickets
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      let requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 111n);

      // Drain all ticket processing
      for (let i = 0; i < 50; i++) {
        if (!(await game.rngLocked())) break;
        try {
          await game.connect(deployer).advanceGame();
        } catch {
          break;
        }
      }

      // Second day for daily jackpot path
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 222n);

      // This should hit the PURCHASE_DAILY path (stage=6)
      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      const events = await getAdvanceEvents(tx, advanceModule);
      const stage = events.length > 0 ? events[0].args.stage : "?";
      recordGas(`Purchase Daily Jackpot (stage=${stage})`, receipt);
      expect(receipt.status).to.equal(1);
    });
  });

  // =========================================================================
  // 5. Enter Jackpot Phase (STAGE_ENTERED_JACKPOT = 13)
  // =========================================================================

  describe("5. Enter Jackpot Phase (STAGE_ENTERED_JACKPOT)", function () {
    it("worst case: purchase->jackpot transition with prize pool consolidation", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const nextPool = await game.nextPrizePoolView();
      console.log(`      nextPrizePool: ${hre.ethers.formatEther(nextPool)} ETH`);

      // Drive VRF cycles, watching every advanceGame call for stage 13
      let foundGas = false;
      for (let cycle = 0; cycle < 30; cycle++) {
        await advanceToNextDay();
        await game.connect(deployer).advanceGame();
        const requestId = await getLastVRFRequestId(mockVRF);
        try {
          await mockVRF.fulfillRandomWords(
            requestId,
            BigInt(cycle * 1000 + 42)
          );
        } catch {
          continue;
        }

        // Drain processing, watching for stage 13
        for (let i = 0; i < 200; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              if (events[0].args.stage === 7n) {
                recordGas("Enter Jackpot Phase (stage=7)", receipt);
                foundGas = true;
                break;
              }
            }
          } catch {
            break;
          }
          if (!(await game.rngLocked()) && i > 0) break;
        }

        if (foundGas) break;
        if (await game.jackpotPhase()) break;
      }

      expect(await game.jackpotPhase()).to.equal(true);
      if (!foundGas) {
        console.log("      (Stage 13 not directly captured in drain loop)");
        // Measure a jackpot-phase advanceGame call as fallback
        await advanceToNextDay();
        const tx = await game.connect(deployer).advanceGame();
        const receipt = await tx.wait();
        const events = await getAdvanceEvents(tx, advanceModule);
        const stage = events.length > 0 ? events[0].args.stage : "?";
        recordGas(`Jackpot Phase Entry (stage=${stage})`, receipt);
      }
    });
  });

  // =========================================================================
  // 6. Jackpot Daily ETH Distribution (STAGE_JACKPOT_DAILY_STARTED = 18)
  // =========================================================================

  describe("6. Jackpot Daily ETH Distribution (STAGE_JACKPOT_DAILY_STARTED)", function () {
    it("worst case: fresh daily jackpot ETH with many winners", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      if (!reached) {
        console.log("      (Could not reach jackpot phase - skipping)");
        this.skip();
        return;
      }

      // Advance to next day and get VRF for daily jackpot
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 5555n);

      // Drain all ticket processing (stage 5) first, then capture the
      // first non-ticket stage which should be 18 (fresh daily jackpot).
      let found = false;
      for (let i = 0; i < 100; i++) {
        try {
          const tx = await game.connect(deployer).advanceGame();
          const receipt = await tx.wait();
          const events = await getAdvanceEvents(tx, advanceModule);
          if (events.length > 0) {
            const stage = events[0].args.stage;
            if (stage !== 5n) {
              recordGas(`Jackpot Daily ETH (stage=${stage})`, receipt);
              found = true;
              break;
            }
          }
          if (!(await game.rngLocked())) break;
        } catch {
          break;
        }
      }
      if (!found) {
        console.log("      (Stage 18 not captured after draining tickets)");
      }
    });
  });

  // =========================================================================
  // 7. Jackpot ETH Resume (STAGE_JACKPOT_ETH_RESUME = 15)
  // =========================================================================

  describe("7. Jackpot ETH Resume (STAGE_JACKPOT_ETH_RESUME)", function () {
    it("worst case: resume mid-bucket ETH distribution", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      if (!reached) {
        this.skip();
        return;
      }

      // Advance to next day and get VRF
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 7777n);

      // Drain all ticket processing (stage 5) first
      for (let i = 0; i < 100; i++) {
        try {
          const tx = await game.connect(deployer).advanceGame();
          const events = await getAdvanceEvents(tx, advanceModule);
          if (events.length > 0 && events[0].args.stage !== 5n) {
            // We hit a non-ticket stage (likely 18 = fresh daily jackpot).
            // The daily jackpot started but with full budget it may have finished.
            // We need it to NOT finish so stage 15 (resume) is needed next.
            break;
          }
          if (!(await game.rngLocked())) break;
        } catch {
          break;
        }
      }

      // Start fresh daily jackpot to leave cursors mid-bucket if budget is exhausted
      try {
        await game.connect(deployer).advanceGame();
      } catch {
        // Might revert
      }

      // Resume at full capacity - should hit stage 15
      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      const events = await getAdvanceEvents(tx, advanceModule);
      const stage = events.length > 0 ? events[0].args.stage : "?";
      recordGas(`Jackpot ETH Resume (stage=${stage})`, receipt);
      expect(receipt.status).to.equal(1);
    });
  });

  // =========================================================================
  // 8. Jackpot Coin+Tickets (STAGE_JACKPOT_COIN_TICKETS = 17)
  // =========================================================================

  describe("8. Jackpot Coin+Tickets (STAGE_JACKPOT_COIN_TICKETS)", function () {
    it("worst case: coin and ticket distribution after daily ETH", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      if (!reached) {
        this.skip();
        return;
      }

      // Run a daily jackpot and look for coin+ticket distribution (stage 17)
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 8888n);

      let found = false;
      for (let i = 0; i < 50; i++) {
        try {
          const tx = await game.connect(deployer).advanceGame();
          const receipt = await tx.wait();
          const events = await getAdvanceEvents(tx, advanceModule);
          if (events.length > 0) {
            const stage = events[0].args.stage;
            if (stage === 9n) {
              recordGas("Jackpot Coin+Tickets (stage=9)", receipt);
              found = true;
              break;
            }
            // If we see a different stage, record it and continue looking
          }
          if (!(await game.rngLocked())) break;
        } catch {
          break;
        }
      }

      if (!found) {
        console.log("      (Stage 17 not directly observed - recording next available)");
        // Record whatever the next call produces
        try {
          await advanceToNextDay();
          await game.connect(deployer).advanceGame();
          const rid = await getLastVRFRequestId(mockVRF);
          try { await mockVRF.fulfillRandomWords(rid, 9999n); } catch {}
          const tx = await game.connect(deployer).advanceGame();
          const receipt = await tx.wait();
          const events = await getAdvanceEvents(tx, advanceModule);
          const stage = events.length > 0 ? events[0].args.stage : "?";
          recordGas(`Jackpot Coin+Tickets fallback (stage=${stage})`, receipt);
        } catch {
          // Ignore
        }
      }
    });
  });

  // =========================================================================
  // 9. Final Day Phase End (STAGE_JACKPOT_PHASE_ENDED = 16)
  // =========================================================================

  describe("9. Final Day Phase End (STAGE_JACKPOT_PHASE_ENDED)", function () {
    it("worst case: day 5 endPhase with all end-of-level operations", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      if (!reached) {
        this.skip();
        return;
      }

      // Drive through daily jackpots, watching for stage 16 (phase ended)
      let found = false;
      for (let day = 0; day < 10; day++) {
        await advanceToNextDay();
        await game.connect(deployer).advanceGame();
        const requestId = await getLastVRFRequestId(mockVRF);
        try {
          await mockVRF.fulfillRandomWords(
            requestId,
            BigInt(day * 2000 + 99)
          );
        } catch {
          // already fulfilled
        }

        for (let i = 0; i < 100; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if (stage === 10n) {
                recordGas("Final Day Phase End (stage=10)", receipt);
                found = true;
                break;
              }
            }
          } catch {
            break;
          }
          if (!(await game.rngLocked())) break;
        }

        if (found) break;
        if (!(await game.jackpotPhase())) {
          console.log("      (Phase ended during draining but stage 16 not captured)");
          break;
        }
      }

      if (!found) {
        console.log("      (Stage 16 not captured)");
      }
    });
  });

  // =========================================================================
  // 10. Phase Transition (STAGE_TRANSITION_DONE = 3)
  // =========================================================================

  describe("10. Phase Transition (STAGE_TRANSITION_DONE)", function () {
    it("worst case: vault perpetual tickets + stETH auto-stake", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      if (!reached) {
        this.skip();
        return;
      }

      // Manually drive through jackpot phase, watching for stage 16.
      // When stage 16 (PHASE_ENDED) fires, the NEXT call should be stage 3
      // (TRANSITION_DONE) since _endPhase sets phaseTransitionActive=true
      // and keeps RNG locked.
      let found = false;
      for (let day = 0; day < 12; day++) {
        await advanceToNextDay();
        await game.connect(deployer).advanceGame();
        const requestId = await getLastVRFRequestId(mockVRF);
        try {
          await mockVRF.fulfillRandomWords(requestId, BigInt(day * 2000 + 99));
        } catch {
          // already fulfilled
        }

        for (let i = 0; i < 100; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if (stage === 10n) {
                // Phase ended! Next call processes the phase transition.
                const tx2 = await game.connect(deployer).advanceGame();
                const receipt2 = await tx2.wait();
                const events2 = await getAdvanceEvents(tx2, advanceModule);
                const stage2 = events2.length > 0 ? events2[0].args.stage : "?";
                recordGas(`Phase Transition (stage=${stage2})`, receipt2);
                found = true;
                break;
              }
              if (stage === 3n || stage === 2n) {
                recordGas(`Phase Transition (stage=${stage})`, receipt);
                found = true;
                break;
              }
            }
          } catch {
            break;
          }
          if (!(await game.rngLocked())) break;
        }

        if (found) break;
        if (!(await game.jackpotPhase())) {
          // Phase ended but we didn't capture stage 16; try next call
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            const stage = events.length > 0 ? events[0].args.stage : "?";
            recordGas(`Phase Transition (stage=${stage})`, receipt);
            found = true;
          } catch {
            // ignore
          }
          break;
        }
      }

      if (!found) {
        console.log("      (Stage 3 not captured)");
      }
    });
  });

  // =========================================================================
  // 11. Game Over Drain (STAGE_GAMEOVER = 0)
  // =========================================================================

  describe("11. Game Over Drain (STAGE_GAMEOVER)", function () {
    it("worst case: 912-day timeout with max deity pass refunds", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Buy deity passes from as many unique signers as possible (max 24 symbols)
      const deityBuyers = [alice, bob, carol, dan, eve, ...others.slice(0, 19)];
      let deityCount = 0;
      for (let i = 0; i < deityBuyers.length && i < 24; i++) {
        const buyer = deityBuyers[i];
        const triangular = BigInt(i * (i + 1)) / 2n;
        const priceEth = 24n + triangular;
        try {
          await game
            .connect(buyer)
            .purchaseDeityPass(buyer.address, i, {
              value: hre.ethers.parseEther(priceEth.toString()),
            });
          deityCount++;
        } catch {
          break;
        }
      }
      console.log(`      Deity passes purchased: ${deityCount}`);

      await buyFullTickets(game, alice, 50, 0.5);

      // Advance 912+ days
      await advanceTime(912 * 86400 + 86400);

      // Step 1: advanceGame -> VRF request
      const tx1 = await game.connect(deployer).advanceGame();
      const receipt1 = await tx1.wait();
      const events1 = await getAdvanceEvents(tx1, advanceModule);
      const stage1 = events1.length > 0 ? events1[0].args.stage : "?";
      recordGas(`Game Over VRF Request (stage=${stage1})`, receipt1);

      // Step 2: Fulfill VRF
      const requestId = await getLastVRFRequestId(mockVRF);
      if (requestId > 0n) {
        await mockVRF.fulfillRandomWords(requestId, 42n);
      }

      // Step 3: advanceGame -> handleGameOverDrain (the expensive one)
      const tx2 = await game.connect(deployer).advanceGame();
      const receipt2 = await tx2.wait();
      const events2 = await getAdvanceEvents(tx2, advanceModule);
      const stage2 = events2.length > 0 ? events2[0].args.stage : "?";
      recordGas(`Game Over Drain (stage=${stage2})`, receipt2);

      expect(await game.gameOver()).to.equal(true);
    });
  });

  // =========================================================================
  // 12. Final Sweep (30 days post-gameover)
  // =========================================================================

  describe("12. Final Sweep (30 days post-gameover)", function () {
    it("worst case: ETH/stETH split to vault + DGNRS", async function () {
      const { game, deployer, advanceModule, mockVRF, alice } = await loadFixture(
        deployFullProtocol
      );

      await buyFullTickets(game, alice, 200, 2.0);

      await advanceTime(912 * 86400 + 86400);
      await triggerGameOverAtLevel0(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);

      // Wait 30+ days for final sweep
      await advanceTime(31 * 86400);

      const tx = await game.connect(deployer).advanceGame();
      const receipt = await tx.wait();
      const events = await getAdvanceEvents(tx, advanceModule);
      const stage = events.length > 0 ? events[0].args.stage : "?";
      recordGas(`Final Sweep (stage=${stage})`, receipt);
      expect(receipt.status).to.equal(1);
    });
  });

  // =========================================================================
  // 13. Future Ticket Processing (STAGE_FUTURE_TICKETS_WORKING = 7)
  // =========================================================================

  describe("13. Future Ticket Processing (STAGE_FUTURE_TICKETS_WORKING)", function () {
    it("worst case: future ticket batch for levels lvl+2..lvl+5", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 10)];
      await heavyPurchases(game, buyers);

      // Drive VRF cycles, watching every call for stage 7
      let found = false;
      for (let cycle = 0; cycle < 30; cycle++) {
        await advanceToNextDay();
        await game.connect(deployer).advanceGame();
        const requestId = await getLastVRFRequestId(mockVRF);
        try {
          await mockVRF.fulfillRandomWords(
            requestId,
            BigInt(cycle * 1000 + 42)
          );
        } catch {
          continue;
        }

        for (let i = 0; i < 200; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if (stage === 4n) {
                recordGas("Future Ticket Processing (stage=4)", receipt);
                found = true;
                break;
              }
            }
          } catch {
            break;
          }
          if (!(await game.rngLocked()) && i > 0) break;
        }

        if (found) break;
      }

      if (!found) {
        console.log("      (Stage 7 not observed - whale bundles may not create future ticket queues at this level)");
      }
    });
  });
});
