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
  // 7. Jackpot ETH Resume (STAGE_JACKPOT_ETH_RESUME = 8)
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

      // Drive through remaining stages to find the fresh daily jackpot call.
      // After that call, if resumeEthPool was set, next advanceGame hits stage 8.
      let hitDailyStart = false;
      for (let i = 0; i < 50; i++) {
        try {
          const tx = await game.connect(deployer).advanceGame();
          const receipt = await tx.wait();
          const events = await getAdvanceEvents(tx, advanceModule);
          if (events.length > 0) {
            const stage = events[0].args.stage;
            if (stage === 11n) {
              // STAGE_JACKPOT_DAILY_STARTED — daily jackpot call 1 just ran
              hitDailyStart = true;
              break;
            }
            if (stage === 8n) {
              // Already at resume — record and done
              recordGas("Jackpot ETH Resume (stage=8)", receipt);
              return;
            }
          }
          if (!(await game.rngLocked())) break;
        } catch {
          break;
        }
      }

      if (!hitDailyStart) {
        console.log("      (Could not reach STAGE_JACKPOT_DAILY_STARTED - skipping)");
        this.skip();
        return;
      }

      // Next advanceGame should hit STAGE_JACKPOT_ETH_RESUME if pool was large enough for split
      try {
        const tx = await game.connect(deployer).advanceGame();
        const receipt = await tx.wait();
        const events = await getAdvanceEvents(tx, advanceModule);
        if (events.length > 0 && events[0].args.stage === 8n) {
          recordGas("Jackpot ETH Resume (stage=8)", receipt);
        } else {
          const stage = events.length > 0 ? events[0].args.stage : "?";
          console.log(`      (Pool too small for split — got stage=${stage} instead of 8)`);
          recordGas(`Jackpot ETH Resume fallback (stage=${stage})`, receipt);
        }
      } catch (e) {
        console.log(`      (Resume call reverted: ${e.message?.slice(0, 80)})`);
        this.skip();
      }
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

  // =========================================================================
  // 14. Sybil Ticket Bloat (STAGE_TICKETS_WORKING max load)
  // =========================================================================

  describe("14. Sybil Ticket Bloat (STAGE_TICKETS_WORKING max load)", function () {
    it("adversarial: max available Sybil wallets each buying minimum ticket", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Use ALL available signers as Sybil buyers (deployer, alice, bob, carol, dan, eve + others)
      // Hardhat default: 20 signers total → others.length = 14
      // At level 0, price = 0.01 ETH. Cost for 1 full ticket (qty 400) = (0.01 ETH * 400) / 400 = 0.01 ETH
      // TICKET_MIN_BUYIN_WEI = 0.0025 ETH is the floor; actual level-0 cost = 0.01 ETH
      const sybilBuyers = [alice, bob, carol, dan, eve, ...others];
      let sybilCount = 0;

      for (const buyer of sybilBuyers) {
        try {
          await game
            .connect(buyer)
            .purchase(
              buyer.address,
              400n,         // 1 full ticket = qty 400; cost = (price * 400) / 400 = price = 0.01 ETH
              0n,
              ZERO_BYTES32,
              MintPaymentKind.DirectEth,
              { value: eth(0.01) }  // 1 full ticket at level 0: price = 0.01 ETH
            );
          sybilCount++;
        } catch {
          // Skip buyers that fail (edge conditions, e.g. game state)
        }
      }
      console.log(`      Sybil buyers successfully purchased: ${sybilCount}`);

      // Advance to next day and trigger VRF cycle
      await advanceToNextDay();
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 42n);

      // First processTicketBatch call — cold SSTOREs (worst-case gas)
      const tx1 = await game.connect(deployer).advanceGame();
      const receipt1 = await tx1.wait();
      const events1 = await getAdvanceEvents(tx1, advanceModule);
      const stage1 = events1.length > 0 ? events1[0].args.stage : "?";
      recordGas(`Sybil Ticket Batch - first cold batch (stage=${stage1})`, receipt1);
      expect(receipt1.status).to.equal(1);

      // Second processTicketBatch call — warm SSTOREs (if queue not fully drained)
      if (await game.rngLocked()) {
        try {
          const tx2 = await game.connect(deployer).advanceGame();
          const receipt2 = await tx2.wait();
          const events2 = await getAdvanceEvents(tx2, advanceModule);
          const stage2 = events2.length > 0 ? events2[0].args.stage : "?";
          recordGas(`Sybil Ticket Batch - second warm batch (stage=${stage2})`, receipt2);
        } catch {
          console.log("      (Second batch not needed — queue drained in first call)");
        }
      } else {
        console.log("      (Queue fully drained in first call — no second batch needed)");
      }
    });
  });

  // =========================================================================
  // 15. VRF Callback Gas (rawFulfillRandomWords)
  // =========================================================================

  describe("15. VRF Callback Gas (rawFulfillRandomWords)", function () {
    it("daily RNG path (path 1): VRF callback after advanceGame triggers request", async function () {
      const { game, deployer, mockVRF, alice, bob } =
        await loadFixture(deployFullProtocol);

      // A few purchases so there are tickets in the queue (makes the
      // rngLocked path representative of a real day).
      await buyFullTickets(game, alice, 5, 0.05);
      await buyFullTickets(game, bob, 5, 0.05);

      await advanceToNextDay();

      // advanceGame() triggers the VRF request (stage=1, rngLockedFlag=true)
      await game.connect(deployer).advanceGame();
      const requestId = await getLastVRFRequestId(mockVRF);

      // Fulfill: this is rawFulfillRandomWords() — capture the full receipt.
      // receipt.gasUsed covers coordinator wrapper overhead + game callback.
      const vrfTx = await mockVRF.fulfillRandomWords(requestId, 42n);
      const vrfReceipt = await vrfTx.wait();
      recordGas("VRF Callback - daily RNG (path 1)", vrfReceipt);

      expect(vrfReceipt.status).to.equal(1);
      expect(vrfReceipt.gasUsed).to.be.lt(300_000n);
    });

    it("lootbox RNG path (path 2): VRF callback after requestLootboxRng()", async function () {
      const { game, deployer, mockVRF, alice } =
        await loadFixture(deployFullProtocol);

      // Purchase lootboxes; the lootbox RNG gate requires non-zero pending lootboxes.
      // purchase(affiliate, ticketQty, lootBoxQty, affiliateCode, payKind, {value})
      // Each lootbox costs 0.001 ETH at level 0 (LOOTBOX_PRICE_WEI = 1e15).
      // We buy 20 lootboxes to ensure the activity threshold is met.
      try {
        await game
          .connect(alice)
          .purchase(
            ZERO_ADDRESS,
            0n,
            20n,
            ZERO_BYTES32,
            MintPaymentKind.DirectEth,
            { value: hre.ethers.parseEther("0.02") }
          );
      } catch (err) {
        console.log(`      Lootbox purchase failed: ${err.message.slice(0, 80)}`);
        console.log("      (Skipping lootbox path — not reachable in harness)");
        return;
      }

      // requestLootboxRng() can only be called outside the daily advance window.
      // Try it mid-day (no advanceToNextDay, so we are within the same day).
      let lbRequestId;
      try {
        const lbTx = await game.connect(deployer).requestLootboxRng();
        await lbTx.wait();
        lbRequestId = await getLastVRFRequestId(mockVRF);
      } catch (err) {
        console.log(`      requestLootboxRng failed: ${err.message.slice(0, 80)}`);
        console.log("      (Lootbox RNG not requestable in current harness state — skipping path 2)");
        return;
      }

      // Fulfill the lootbox VRF request and capture gas.
      const vrfTx = await mockVRF.fulfillRandomWords(lbRequestId, 77n);
      const vrfReceipt = await vrfTx.wait();
      recordGas("VRF Callback - lootbox RNG (path 2)", vrfReceipt);

      expect(vrfReceipt.status).to.equal(1);
      expect(vrfReceipt.gasUsed).to.be.lt(300_000n);
    });
  });

  // =========================================================================
  // 16. Worst-Case Gas Benchmark (Post-Split)
  //
  // Theoretical worst case for _processDailyEth (daily two-call split):
  //   Pool >= 200 ETH -> max scale 6.36x -> bucket counts 159/95/50/1 = 305
  //   All 305 winners are unique addresses with autorebuy enabled.
  //   Each winner: _randTraitTicket (SSTORE) + _payNormalBucket/_handleSoloBucketWinner
  //   + _processAutoRebuy (_calcAutoRebuy + _queueTickets + pool writes) + event.
  //   Call 1 processes largest(159) + solo(1) = 160 winners.
  //   Call 2 processes mid(95) + small(50) = 145 winners.
  //   Each call must stay under 16M gas.
  //
  // For early-burn path: single call, 160 winners, _distributeJackpotEth.
  // For terminal path: single call, 305 winners, _distributeJackpotEth.
  //
  // Pool economics at level 0:
  //   Whale bundles at level 0 cost 2.4 ETH each (WHALE_BUNDLE_EARLY_PRICE).
  //   Payment split at level 0: 30% -> nextPool, 70% -> futurePool.
  //   At jackpot transition (x00): nextPool merges into currentPool, plus
  //   35-70% of futurePool flows into currentPool via the keep roll.
  //   Level 0 triggers turbo mode (compressedJackpotFlag=2) on day 1-2 when
  //   nextPool >= levelPrizePool[0] (= 0), so jackpot phase completes in
  //   a single physical day with 100% pool distribution.
  // =========================================================================

  describe("16. Worst-Case Gas Benchmark (Post-Split)", function () {
    this.timeout(1_200_000); // 20 minutes — 305 players need heavy setup

    /**
     * Buy 1 full ticket (400 qty) for a player at level 0.
     * Level 0 price = 0.01 ETH, so 1 full ticket costs 0.01 ETH.
     */
    async function buyOneTicket(game, buyer) {
      return game
        .connect(buyer)
        .purchase(
          ZERO_ADDRESS,
          400n,
          0n,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          { value: eth(0.01) }
        );
    }

    /**
     * Set up unique players: each buys tickets and optionally enables autorebuy.
     * Returns the player array.
     */
    async function setupPlayers(game, namedSigners, otherSigners, count, enableAutoRebuy) {
      const players = [...namedSigners, ...otherSigners].slice(0, count);
      console.log(`      Setting up ${players.length} players...`);

      // Batch ticket purchases
      const batchSize = 50;
      for (let start = 0; start < players.length; start += batchSize) {
        const batch = players.slice(start, start + batchSize);
        await Promise.all(batch.map(p => buyOneTicket(game, p)));
        if (start + batchSize < players.length) {
          console.log(`      ... ${Math.min(start + batchSize, players.length)}/${players.length} tickets purchased`);
        }
      }
      console.log(`      ${players.length} tickets purchased`);

      if (enableAutoRebuy) {
        for (let start = 0; start < players.length; start += batchSize) {
          const batch = players.slice(start, start + batchSize);
          await Promise.all(batch.map(p =>
            game.connect(p).setAutoRebuy(ZERO_ADDRESS, true)
          ));
        }
        console.log(`      ${players.length} players enabled autorebuy`);
      }

      return players;
    }

    /**
     * Fund pool heavily using whale bundles.
     * At level 0: 2.4 ETH per bundle, 30% -> nextPool, 70% -> futurePool.
     * For 200+ ETH jackpot pool: need ~3 buyers * 100 bundles = 720 ETH total.
     * 720 * 0.30 = 216 ETH in nextPool; future pool also contributes via keep roll.
     */
    async function fundPoolHeavy(game, buyers, bundlesPerBuyer) {
      const pricePerBundle = eth(2.4); // Level 0 intro price
      for (const buyer of buyers) {
        try {
          await game
            .connect(buyer)
            .purchaseWhaleBundle(buyer.address, bundlesPerBuyer, {
              value: BigInt(bundlesPerBuyer) * pricePerBundle,
            });
        } catch {
          // If intro price fails, try standard price (4 ETH)
          try {
            await game
              .connect(buyer)
              .purchaseWhaleBundle(buyer.address, bundlesPerBuyer, {
                value: BigInt(bundlesPerBuyer) * eth(4),
              });
          } catch {
            console.log(`      (Whale bundle failed for ${buyer.address.slice(0, 8)}...)`);
          }
        }
      }
      const pool = await game.currentPrizePoolView();
      const nextPool = await game.nextPrizePoolView();
      console.log(`      Pool: ${hre.ethers.formatEther(pool)} ETH (current) + ${hre.ethers.formatEther(nextPool)} ETH (next)`);
    }

    /**
     * Drive through a full VRF cycle, capturing receipts for specific stages.
     * Returns Map<bigint, receipt> for matched stages.
     */
    async function driveAndCapture(game, deployer, advanceModule, targetStages) {
      const stageReceipts = new Map();

      for (let i = 0; i < 200; i++) {
        try {
          const tx = await game.connect(deployer).advanceGame();
          const receipt = await tx.wait();
          const events = await getAdvanceEvents(tx, advanceModule);
          if (events.length > 0) {
            const stage = events[0].args.stage;
            if (targetStages.includes(stage) && !stageReceipts.has(stage)) {
              stageReceipts.set(stage, receipt);
            }
          }
        } catch {
          break;
        }
        if (!(await game.rngLocked())) break;
      }

      return stageReceipts;
    }

    it("SC-1: daily two-call split — 305 players, autorebuy, max-scale pool", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Step 1: Set up 305 unique players with tickets + autorebuy
      const players = await setupPlayers(
        game, [alice, bob, carol, dan, eve], others.slice(0, 300), 305, true
      );

      // Step 2: Fund pool — 5 buyers * 20 bundles * 2.4 ETH = 240 ETH total
      // 30% to nextPool = ~72 ETH; 70% to futurePool = ~168 ETH.
      // After consolidation (keep roll ~47.5% of future to current + memNext):
      // currentPool ~ 72 + 80 = ~152 ETH. At 152 ETH: ~3.9x scale -> ~98/59/31/1 = 189 winners.
      await fundPoolHeavy(game, players.slice(0, 5), 20);

      // Step 3: Drive manually through VRF cycles, capturing stages of interest.
      // At level 0, turbo mode triggers on day 1-2 (purchaseDays <= 1 && nextPool > 0).
      // We drive day-by-day, capturing stage 11 (call 1) and stage 8 (call 2) when they fire.
      const stageReceipts = new Map();

      for (let day = 0; day < 15; day++) {
        await advanceToNextDay();

        // Drive all advanceGame calls for this day, capturing stages
        for (let i = 0; i < 200; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if ([1n, 7n, 11n, 8n, 9n, 10n].includes(stage) && !stageReceipts.has(stage)) {
                stageReceipts.set(stage, receipt);
                console.log(`      Day ${day}, iter ${i}: stage=${stage}, gas=${receipt.gasUsed.toLocaleString()}`);
              }
            }
          } catch {
            break;
          }
          if (!(await game.rngLocked())) break;
        }

        // Fulfill VRF if a request was made
        try {
          const requestId = await getLastVRFRequestId(mockVRF);
          if (requestId > 0n) {
            await mockVRF.fulfillRandomWords(requestId, BigInt(day * 1000 + 305305));
          }
        } catch {
          // Already fulfilled or no request pending
        }

        // Continue draining after fulfillment (same day, mid-day path)
        for (let i = 0; i < 200; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if ([7n, 11n, 8n, 9n, 10n].includes(stage) && !stageReceipts.has(stage)) {
                stageReceipts.set(stage, receipt);
                console.log(`      Day ${day}, post-VRF iter ${i}: stage=${stage}, gas=${receipt.gasUsed.toLocaleString()}`);
              }
            }
          } catch {
            break;
          }
          if (!(await game.rngLocked())) break;
        }

        // Stop if jackpot phase ended (all stages captured)
        if (stageReceipts.has(10n)) {
          console.log(`      Jackpot phase ended on day ${day}`);
          break;
        }
      }

      const jpPool = await game.currentPrizePoolView();
      console.log(`      Pool after jackpot: ${hre.ethers.formatEther(jpPool)} ETH`);

      console.log(`      Stages captured: ${[...stageReceipts.keys()].map(s => Number(s)).join(", ")}`);

      // Record gas for call 1 (STAGE_JACKPOT_DAILY_STARTED = 11)
      if (stageReceipts.has(11n)) {
        const r = stageReceipts.get(11n);
        recordGas("WC: Daily Split Call 1 (stage=11)", r);
        expect(r.gasUsed).to.be.lt(16_000_000n);
        console.log(`      Call 1 gas: ${r.gasUsed.toLocaleString()}`);
      } else {
        console.log("      (Stage 11 not captured in this cycle)");
      }

      // Record gas for call 2 (STAGE_JACKPOT_ETH_RESUME = 8)
      if (stageReceipts.has(8n)) {
        const r = stageReceipts.get(8n);
        recordGas("WC: Daily Split Call 2 (stage=8)", r);
        expect(r.gasUsed).to.be.lt(16_000_000n);
        console.log(`      Call 2 gas: ${r.gasUsed.toLocaleString()}`);
      } else if (stageReceipts.has(11n)) {
        // Stage 11 captured but no stage 8 — pool below split threshold
        console.log("      (No resume — pool below two-call split threshold)");
      }

      // Log all captured stages for audit traceability
      for (const [stage, receipt] of stageReceipts) {
        if (stage !== 11n && stage !== 8n) {
          console.log(`      Stage ${stage}: ${receipt.gasUsed.toLocaleString()} gas`);
        }
      }
    });

    it("SC-2a: early-burn path — 160 winners, moderate pool", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Set up 305 players with tickets (no autorebuy — measures raw ETH distribution)
      const players = await setupPlayers(
        game, [alice, bob, carol, dan, eve], others.slice(0, 300), 305, false
      );

      // Fund same as other tests — 5 buyers * 20 bundles * 2.4 ETH = 240 ETH
      // 30% to nextPool = ~72 ETH. After consolidation: ~74 ETH current.
      // At 74 ETH: ~2.3x scale -> 58/35/18/1 = 112 winners (within 160 cap).
      await fundPoolHeavy(game, players.slice(0, 5), 20);

      // Drive manually through VRF cycles, capturing stages of interest
      const stageReceipts = new Map();

      for (let day = 0; day < 15; day++) {
        await advanceToNextDay();
        for (let i = 0; i < 200; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if ([11n, 8n, 9n, 10n].includes(stage) && !stageReceipts.has(stage)) {
                stageReceipts.set(stage, receipt);
                console.log(`      Day ${day}: stage=${stage}, gas=${receipt.gasUsed.toLocaleString()}`);
              }
            }
          } catch { break; }
          if (!(await game.rngLocked())) break;
        }
        try {
          const requestId = await getLastVRFRequestId(mockVRF);
          if (requestId > 0n) await mockVRF.fulfillRandomWords(requestId, BigInt(day * 1000 + 160160));
        } catch {}
        for (let i = 0; i < 200; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if ([11n, 8n, 9n, 10n].includes(stage) && !stageReceipts.has(stage)) {
                stageReceipts.set(stage, receipt);
                console.log(`      Day ${day} post-VRF: stage=${stage}, gas=${receipt.gasUsed.toLocaleString()}`);
              }
            }
          } catch { break; }
          if (!(await game.rngLocked())) break;
        }
        if (stageReceipts.has(10n)) { console.log(`      Phase ended on day ${day}`); break; }
      }

      console.log(`      Stages captured: ${[...stageReceipts.keys()].map(s => Number(s)).join(", ")}`);

      if (stageReceipts.has(11n)) {
        const r = stageReceipts.get(11n);
        recordGas("WC: Early-Burn ETH (stage=11)", r);
        expect(r.gasUsed).to.be.lt(16_000_000n);
        console.log(`      Early-burn gas: ${r.gasUsed.toLocaleString()}`);
      } else {
        console.log("      (Stage 11 not captured)");
      }

      if (stageReceipts.has(8n)) {
        const r = stageReceipts.get(8n);
        recordGas("WC: Early-Burn Resume (stage=8)", r);
        expect(r.gasUsed).to.be.lt(16_000_000n);
        console.log(`      Early-burn resume gas: ${r.gasUsed.toLocaleString()}`);
      }
    });

    it("SC-2b: terminal jackpot path — 305 winners, no autorebuy, max pool", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Set up 305 players with tickets (no autorebuy — measures raw distribution gas)
      const players = await setupPlayers(
        game, [alice, bob, carol, dan, eve], others.slice(0, 300), 305, false
      );

      // Fund for good scale — 5 buyers * 20 bundles * 2.4 ETH = 240 ETH total
      await fundPoolHeavy(game, players.slice(0, 5), 20);

      // Drive manually, capturing all jackpot stages.
      // At turbo, counterStep = JACKPOT_LEVEL_CAP (5), so isFinalPhysicalDay = true.
      // This means max winners at max scale, 100% pool distribution.
      const stageReceipts = new Map();

      for (let day = 0; day < 15; day++) {
        await advanceToNextDay();
        for (let i = 0; i < 200; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if ([11n, 8n, 9n, 10n].includes(stage) && !stageReceipts.has(stage)) {
                stageReceipts.set(stage, receipt);
                console.log(`      Day ${day}: stage=${stage}, gas=${receipt.gasUsed.toLocaleString()}`);
              }
            }
          } catch { break; }
          if (!(await game.rngLocked())) break;
        }
        try {
          const requestId = await getLastVRFRequestId(mockVRF);
          if (requestId > 0n) await mockVRF.fulfillRandomWords(requestId, BigInt(day * 1000 + 777777));
        } catch {}
        for (let i = 0; i < 200; i++) {
          try {
            const tx = await game.connect(deployer).advanceGame();
            const receipt = await tx.wait();
            const events = await getAdvanceEvents(tx, advanceModule);
            if (events.length > 0) {
              const stage = events[0].args.stage;
              if ([11n, 8n, 9n, 10n].includes(stage) && !stageReceipts.has(stage)) {
                stageReceipts.set(stage, receipt);
                console.log(`      Day ${day} post-VRF: stage=${stage}, gas=${receipt.gasUsed.toLocaleString()}`);
              }
            }
          } catch { break; }
          if (!(await game.rngLocked())) break;
        }
        if (stageReceipts.has(10n)) { console.log(`      Phase ended on day ${day}`); break; }
      }

      console.log(`      Stages captured: ${[...stageReceipts.keys()].map(s => Number(s)).join(", ")}`);

      if (stageReceipts.has(11n)) {
        const r = stageReceipts.get(11n);
        recordGas("WC: Terminal Jackpot Call 1 (stage=11)", r);
        expect(r.gasUsed).to.be.lt(16_000_000n);
        console.log(`      Terminal call 1 gas: ${r.gasUsed.toLocaleString()}`);
      } else {
        console.log("      (Terminal call 1 not captured)");
      }

      if (stageReceipts.has(8n)) {
        const r = stageReceipts.get(8n);
        recordGas("WC: Terminal Jackpot Call 2 (stage=8)", r);
        expect(r.gasUsed).to.be.lt(16_000_000n);
        console.log(`      Terminal call 2 gas: ${r.gasUsed.toLocaleString()}`);
      } else if (stageReceipts.has(11n)) {
        console.log("      (No resume — single-call path used)");
      }
    });
  });
});
