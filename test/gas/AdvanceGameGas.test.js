import { expect } from "chai";
import hre from "hardhat";
import { readFileSync } from "node:fs";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { readyDailyFixture, requestMiddayRng } from "../helpers/readyDailyFixture.js";
import { boSmalls } from "../helpers/boxOrder.js";
import {
  CEILING_ALLOWANCE,
  MINER_IDLE,
  MINER_WAIT,
  MINER_TICKETS,
  mine,
  settle,
  measureNextChunk,
  walkDailyChunks,
  walkNextDay,
  heaviestByStage,
} from "../helpers/mineFlipChunks.js";
import {
  eth,
  advanceTime,
  advanceToNextDay,
  getLastVRFRequestId,
  getEvents,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const GAME_LAYOUT = JSON.parse(
  readFileSync(new URL("../../scripts/layout/golden/DegenerusGame.json", import.meta.url), "utf8")
);
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };
// Owner rule (2026-10-03): only the size of one chunk between checkpoints matters, so no
// test here bounds a whole mineFlip transaction. See test/helpers/mineFlipChunks.js for the
// two asserted gas properties (per-chunk <= 10M; realistic allowance succeeds + progresses).
/**
 * AdvanceGame Gas Benchmarks
 *
 * Measures mineFlip code paths under realistic caller allowances.
 * Each test drives the state machine to a specific stage and reports gasUsed.
 *
 * IMPORTANT: The Advance event is declared in DegenerusGameAdvanceModule,
 * emitted via delegatecall from the game proxy. To parse it we must use
 * advanceModule.interface, NOT game.interface. One mineFlip call now composes
 * several checkpoints, so a receipt can carry several Advance stages.
 *
 * Stage constants (DegenerusGameAdvanceModule.sol / DegenerusGameRngModule.sol):
 *   0  = STAGE_GAMEOVER (terminal path)
 *   1  = STAGE_RNG_REQUESTED
 *   3  = STAGE_TRANSITION_DONE
 *   6  = STAGE_PURCHASE_DAILY
 *   7  = STAGE_ENTERED_JACKPOT
 *   8  = STAGE_JACKPOT_COIN_TICKETS
 *   9  = STAGE_JACKPOT_PHASE_ENDED
 *   10 = STAGE_JACKPOT_DAILY_STARTED
 *   12 = STAGE_GAP_BACKFILLED
 *   14 = STAGE_JACKPOT_EARLY_BIRD_TICKETS
 *   15 = STAGE_PURCHASE_DAILY_TICKETS
 *   16 = STAGE_JACKPOT_BATTLE
 *   17 = STAGE_PURCHASE_BATTLE
 *   18 = STAGE_DAILY_WORD_APPLIED
 *   19 = STAGE_JACKPOT_BAF_AWARDS (pays the frozen BAF awards after the level-x0 transition)
 */
/** Parse Advance events using the advanceModule ABI (not game ABI). */
async function getAdvanceEvents(tx, advanceModule) {
  return getEvents(tx, advanceModule, "Advance");
}

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
      console.log(`  ${name.padEnd(48)} ${gasStr}`);
    }

    console.log("-".repeat(72));
    if (sorted.length > 0) {
      const max = sorted[0];
      console.log(
        `  Peak: ${max.name} = ${max.gasUsed.toLocaleString()} gas`
      );
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
        MintPaymentKind.DirectEth,false, 
        { value: eth(totalEth) }
      );
  }

  /** Trigger game over at level 0 (multi-step VRF flow). */
  async function triggerGameOverAtLevel0(game, deployer, mockVRF) {
    await game.connect(deployer).mineFlip();
    const requestId = await getLastVRFRequestId(mockVRF);
    if (requestId > 0n) {
      await mockVRF.fulfillRandomWords(requestId, 42n);
    }
    await game.connect(deployer).mineFlip();
    // Drain any queued tickets: with non-empty queues the terminal stage takes
    // several mineFlip calls before the game-over drain runs and latches
    // gameOver=true.
    for (let i = 0; i < 50; i++) {
      if (await game.gameOver()) return;
      try {
        await game.connect(deployer).mineFlip();
      } catch {
        return;
      }
    }
  }

  // Record-only: a composed transaction's total is reported, never bounded (owner rule).
  function recordGas(name, receipt) {
    const gasUsed = receipt.gasUsed;
    gasResults.push({ name, gasUsed });
    console.log(`      Gas: ${gasUsed.toLocaleString()}`);
  }

  // Far-future queue reads through the layout oracle (TicketModule drain state).
  const TICKET_FAR_FUTURE_BIT = 1n << 22n;
  const layoutSlot = (label) => BigInt(GAME_LAYOUT.find((e) => e.label === label).slot);
  const QUEUE_SLOT = layoutSlot("ticketQueue");
  const TICKET_CURSOR_SLOT = layoutSlot("ticketCursor");
  const mapSlot = (key, base) => hre.ethers.keccak256(
    hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "uint256"], [key, base]));
  const readSlot = async (game, slot) => BigInt(await hre.ethers.provider.getStorage(game.target, slot));

  /** Mirror of DegenerusGameStorage._ticketQueueLength for a far-future key. */
  async function ffQueueLength(game, lvl) {
    const physical = TICKET_FAR_FUTURE_BIT | ((lvl - 1n) % 100n + 1n);
    const header = await readSlot(game, mapSlot(physical, QUEUE_SLOT));
    let occupying = (header >> 32n) & 0xffffffn;
    if (occupying === 0n) occupying = physical & 0x7fn;
    return occupying === lvl ? header & 0xffffffffn : 0n;
  }

  /** Far-future queue lengths plus the ticket drain cursor (ticketCursor/ticketLevel word). */
  async function ffSnapshot(game, levels) {
    const lens = [];
    for (const l of levels) lens.push(await ffQueueLength(game, l));
    const word = await readSlot(game, TICKET_CURSOR_SLOT);
    const cursor = word & 0xffffffffn;
    const marker = (word >> 32n) & 0xffffffn;
    const inProgress = (marker & TICKET_FAR_FUTURE_BIT) !== 0n
      && levels.includes(marker & (TICKET_FAR_FUTURE_BIT - 1n)) && cursor !== 0n;
    return { lens, cursor, marker, inProgress };
  }

  /** A chunk touched a far-future queue: it released one, or advanced a far-future cursor. */
  function ffTouched(before, after) {
    if (before.lens.some((len, i) => len !== 0n && after.lens[i] === 0n)) return true;
    return after.inProgress && (before.marker !== after.marker || after.cursor > before.cursor);
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
          .purchaseWhalePass(buyer.address, 1, hre.ethers.ZeroHash, { value: eth(2.4) });
      } catch {
        // May fail for some buyers
      }
      await buyFullTickets(game, buyer, 500, 5);
    }
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

      // Realistic allowance: the request is an indivisible RNG_REQUEST checkpoint.
      const { tx, receipt } = await mine(game, deployer);
      const events = await getAdvanceEvents(tx, advanceModule);
      expect(events.length).to.be.gte(1);
      expect(events[0].args.stage).to.equal(1n);
      expect(await game.rngLocked(), "the daily request engaged").to.equal(true);
      recordGas("Fresh VRF Request (stage=1)", receipt);
    });
  });

  // =========================================================================
  // 2. RNG 18h Timeout Retry
  // =========================================================================

  // The 12h VRF retry path at AdvanceModule:1205-1212 is structurally
  // unreachable in fresh-fixture scope. The DegenerusGame constructor
  // (DegenerusGame.sol:224-231) pre-queues vault perpetual tickets for
  // levels 1-100 into ticketQueue[lvl] (raw key, since ticketWriteSlot
  // defaults to false). The first mineFlip requests VRF and calls
  // _swapAndFreeze which flips ticketWriteSlot=true and resets
  // ticketsFullyProcessed=false. On the second advance the new-day
  // drain block reads ticketQueue[_tqReadKey(purchaseLevel)] which
  // resolves to the pre-queued raw key — non-empty + no VRF =>
  // RngNotReady at line 270 before rngGate's retry branch can fire.
  // Reaching the retry would require draining the vault pre-queue
  // through 100 levels of gameplay or fulfilling VRF (which defeats
  // the retry test). Worst-case retry gas is observable indirectly via
  // the Fresh VRF Request and VRF Callback benchmarks.
  describe.skip("2. VRF 12h Timeout Retry (path unreachable in fresh fixture)", function () {
    it("worst case: stale VRF retry re-issues request after 12h", async function () {
      // Intentionally skipped — see describe-block comment for rationale.
    });
  });

  // =========================================================================
  // 3. Ticket Batch Processing (STAGE_TICKETS_WORKING = 5)
  // =========================================================================

  describe("3. Ticket Batch Processing (STAGE_TICKETS_WORKING)", function () {
    // Converted from a composed-transaction ceiling (one unbounded call measured 14.38M against
    // an 11.5M cap, i.e. against its own gas limit). The ticket drain is now asserted per chunk
    // and under realistic allowances: one admitted chunk <= 10M, every 10M call succeeds and
    // progresses until the drain completes, and a 16.7M call from the same state succeeds.
    it("worst case: max budget (550 writes) ticket processing", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      for (const buyer of buyers) {
        await buyFullTickets(game, buyer, 50, 0.5);
      }

      await advanceToNextDay();
      await mine(game, deployer);
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 999n);
      // Publication is its own checkpoint; the ticket drain follows it.
      for (let i = 0; i < 5 && (await game.nextMinerAction()) !== MINER_TICKETS; i++) {
        await mine(game, deployer, 1_000_000);
      }
      expect(await game.nextMinerAction(), "the committed cohort's ticket drain is next").to.equal(MINER_TICKETS);

      const start = await hre.ethers.provider.send("evm_snapshot", []);
      const { receipt: ceiling } = await mine(game, deployer, CEILING_ALLOWANCE);
      console.log(`      16.7M-allowance call: ${ceiling.gasUsed.toLocaleString()} gas`);
      await hre.ethers.provider.send("evm_revert", [start]);

      await measureNextChunk(game, deployer, "ticket drain (550 writes)");
      let calls = 0;
      let maxGas = 0n;
      while ((await game.nextMinerAction()) === MINER_TICKETS) {
        const { receipt } = await mine(game, deployer);
        if (receipt.gasUsed > maxGas) maxGas = receipt.gasUsed;
        expect(++calls, "ticket drain finishes in bounded realistic calls").to.be.lte(100);
      }
      console.log(`      realistic 10M calls to finish the drain: ${calls}; max call gas ${maxGas.toLocaleString()}`);
      recordGas("Ticket Batch 550 writes (max 10M-allowance call)", { gasUsed: maxGas });
    });
  });

  // =========================================================================
  // 4. Purchase-Phase Daily Jackpot (STAGE_PURCHASE_DAILY = 6)
  // =========================================================================

  describe("4. Purchase-Phase Daily Jackpot (STAGE_PURCHASE_DAILY)", function () {
    // One call now composes several checkpoints, so the purchase daily is located by its
    // Advance stage among every chunk of the day, and each chunk is measured on its own.
    it("worst case: daily jackpot with many ticket holders", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      for (const buyer of buyers) {
        await buyFullTickets(game, buyer, 20, 0.2);
      }

      // First VRF cycle: processes tickets (realistic allowances throughout).
      await advanceToNextDay();
      await settle(game, deployer, mockVRF, advanceModule, 111n);

      // Second day: the purchase-phase daily, walked chunk by chunk.
      await advanceToNextDay();
      await mine(game, deployer);
      expect(await game.rngLocked(), "second-day request engaged").to.equal(true);
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 222n);
      const chunks = await walkDailyChunks(game, deployer, advanceModule, "purchase day");
      const daily = chunks.find((c) => c.stages.includes(6n));
      expect(daily, "the purchase-phase daily (STAGE_PURCHASE_DAILY) ran as its own chunk").to.not.equal(undefined);
      expect(await game.rngLocked(), "the purchase day sealed").to.equal(false);
      recordGas("Purchase Daily Jackpot chunk (stage=6)", daily.receipt);
    });
  });

  // =========================================================================
  // 5. Enter Jackpot Phase (STAGE_ENTERED_JACKPOT = 7)
  // =========================================================================

  describe("5. Enter Jackpot Phase (STAGE_ENTERED_JACKPOT)", function () {
    // Level 0 runs turbo: the purchase->jackpot transition, every jackpot day and the phase
    // end all complete inside the first daily cycle, so jackpotPhase() is already false again
    // when the day settles. The transition is therefore proven by its own Advance stage (7,
    // the POOL_CONSOLIDATION checkpoint), measured as one chunk like every other chunk.
    it("worst case: purchase->jackpot transition with prize pool consolidation", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 15)];
      await heavyPurchases(game, buyers);

      const nextPool = await game.nextPrizePoolView();
      console.log(`      nextPrizePool: ${hre.ethers.formatEther(nextPool)} ETH`);

      let entered = null;
      const seen = new Set();
      for (let cycle = 0; cycle < 5 && entered === null; cycle++) {
        await advanceToNextDay();
        await mine(game, deployer);
        const requestId = await getLastVRFRequestId(mockVRF);
        await mockVRF.fulfillRandomWords(requestId, BigInt(cycle * 1000 + 42));
        const chunks = await walkDailyChunks(game, deployer, advanceModule, `cycle ${cycle}`);
        for (const c of chunks) for (const st of c.stages) seen.add(Number(st));
        const heaviest = heaviestByStage(chunks);
        for (const st of [10n, 8n, 9n, 3n]) {
          if (heaviest.has(st)) recordGas(`Jackpot phase heaviest chunk (stage=${st})`, heaviest.get(st).receipt);
        }
        entered = chunks.find((c) => c.stages.includes(7n)) ?? null;
      }
      console.log(`      Advance stages observed: ${[...seen].sort((a, b) => a - b).join(", ")}`);
      expect(entered, "the purchase->jackpot transition (STAGE_ENTERED_JACKPOT) must execute").to.not.equal(null);
      expect(await game.level(), "the transition advanced the level").to.be.gte(1n);
      recordGas("Enter Jackpot Phase chunk (stage=7)", entered.receipt);
      // The same turbo day carries the rest of the jackpot phase, each stage walked as its
      // own <=10M chunk above: daily ETH (10), coin+tickets (8), phase end (9), transition (3).
      for (const [stage, name] of [[10, "Jackpot Daily ETH"], [8, "Jackpot Coin+Tickets"],
        [9, "Final Day Phase End"], [3, "Phase Transition"]]) {
        expect(seen.has(stage), `${name} (stage=${stage}) ran inside the turbo jackpot day`).to.equal(true);
      }
    });
  });

  // Sections 6-10 (jackpot daily ETH / ETH resume / coin+tickets / phase end / transition)
  // were removed: their driver waited for a multi-day jackpot phase that the level-0
  // fixture never shows (turbo completes the whole phase inside the first daily cycle), so
  // they only ever reported pending, and their premise was a per-stage transaction cost.
  // Section 5 now walks that turbo day one checkpoint at a time and requires stages
  // 10/8/9/3 to run, each as a <=10M chunk; mid-quadrant resume chunking is covered by
  // test/repro/JackpotCheckpoints.t.sol and test/repro/JackpotTicketAwardChunks.t.sol.

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
            .purchaseDeityPass(buyer.address, i < 5 ? i + 1 : i + 2, hre.ethers.ZeroHash, {
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

      // Step 1: mineFlip -> VRF request (realistic allowance; terminal work is checkpointed)
      const { tx: tx1, receipt: receipt1 } = await mine(game, deployer);
      const events1 = await getAdvanceEvents(tx1, advanceModule);
      const stage1 = events1.length > 0 ? events1[0].args.stage : "?";
      recordGas(`Game Over VRF Request (stage=${stage1})`, receipt1);

      // Step 2: Fulfill VRF
      const requestId = await getLastVRFRequestId(mockVRF);
      if (requestId > 0n) {
        await mockVRF.fulfillRandomWords(requestId, 42n);
      }

      // Step 3: mineFlip -> terminal stage's game-over drain (the expensive one), realistic allowance
      const { tx: tx2, receipt: receipt2 } = await mine(game, deployer);
      const events2 = await getAdvanceEvents(tx2, advanceModule);
      const stage2 = events2.length > 0 ? events2[0].args.stage : "?";
      recordGas(`Game Over Drain (stage=${stage2})`, receipt2);

      // Drain remaining tickets so gameOver latches. With queued tickets the
      // terminal stage spans several mineFlip calls before the game-over drain runs.
      for (let i = 0; i < 50; i++) {
        if (await game.gameOver()) break;
        try {
          await game.connect(deployer).mineFlip();
        } catch {
          break;
        }
      }

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

      const { tx, receipt } = await mine(game, deployer);
      const events = await getAdvanceEvents(tx, advanceModule);
      const stage = events.length > 0 ? events[0].args.stage : "?";
      recordGas(`Final Sweep (stage=${stage})`, receipt);
      expect(receipt.status).to.equal(1);
    });
  });

  // =========================================================================
  // 13. Far-Future Ticket Drain (frozen next-level pool)
  // =========================================================================
  //
  // Entries for levels above _mintCeiling() wait unminted in the far-future key space. The
  // seal that latches lastPurchaseDay freezes the next level's far-future pool, and the
  // Tickets action of the first cohort committed after it drains that queue
  // (TicketModule._selectProducer, `_frozenPoolDue()` branch). The drain is located by its
  // own storage: the ticket cursor marker carries TICKET_FAR_FUTURE_BIT while a far-future
  // queue is in progress, and the queue is released when it finishes.

  describe("13. Far-Future Ticket Drain (frozen next-level pool)", function () {
    it("far-future pool drain: one chunk <= 10M, realistic allowance succeeds and progresses", async function () {
      const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      // Pool past the bootstrap target (latches lastPurchaseDay), plus whale passes whose
      // entries above the mint ceiling land in the far-future key space.
      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 10)];
      await heavyPurchases(game, buyers);
      for (const buyer of others.slice(10, 160)) {
        await game.connect(buyer).purchaseWhalePass(buyer.address, 1, hre.ethers.ZeroHash, { value: eth(2.4) });
      }
      const lvl0 = await game.level();
      const preLens = [];
      for (let l = lvl0 + 1n; l <= lvl0 + 3n; l++) preLens.push(`L${l}=${await ffQueueLength(game, l)}`);
      console.log(`      far-future queues before the drain: ${preLens.join(" ")}`);

      let ffDrain = null;
      for (let day = 0; day < 6 && ffDrain === null; day++) {
        await advanceToNextDay();
        for (let i = 0; i < 400 && ffDrain === null; i++) {
          const action = await game.nextMinerAction();
          if (action === MINER_IDLE) break;
          if (action === MINER_WAIT) {
            await mockVRF.fulfillRandomWords(await getLastVRFRequestId(mockVRF), BigInt(day * 1000 + i + 42));
            continue;
          }
          const lvl = await game.level();
          const ffLevels = [];
          for (let l = lvl + 1n; l <= lvl + 2n; l++) if ((await ffQueueLength(game, l)) !== 0n) ffLevels.push(l);
          if (action !== MINER_TICKETS || ffLevels.length === 0) {
            await mine(game, deployer);
            continue;
          }
          const before = await ffSnapshot(game, ffLevels);

          // Every realistic 10M call must succeed. While it has not reached a far-future
          // queue (the committed near read cohort drains first) its state is kept.
          const snap = await hre.ethers.provider.send("evm_snapshot", []);
          await mine(game, deployer);
          const realistic = await ffSnapshot(game, ffLevels);
          if (!ffTouched(before, realistic)) continue;
          await hre.ethers.provider.send("evm_revert", [snap]);

          // The 10M call made progress on a far-future queue: isolate the admitted chunk.
          const chunk = await measureNextChunk(game, deployer, `far-future drain lvl=${lvl}`);
          const after = await ffSnapshot(game, ffLevels);
          if (!ffTouched(before, after)) continue;
          ffDrain = { lvl, ffLevels, before, after, chunk };
        }
      }
      expect(ffDrain, "a Tickets chunk drained a far-future queue").to.not.equal(null);
      console.log(`      far-future chunk: level=${ffDrain.lvl} queues=${ffDrain.ffLevels.join(",")} ` +
        `lengths ${ffDrain.before.lens.join(",")} marker ${ffDrain.before.marker.toString(16)}->` +
        `${ffDrain.after.marker.toString(16)} cursor ${ffDrain.before.cursor}->${ffDrain.after.cursor}`);
      recordGas("Far-future pool drain entry chunk", ffDrain.chunk.receipt);
      const released = (snap) => snap.lens.some((len, i) => ffDrain.before.lens[i] !== 0n && len === 0n);

      // (a) The rest of the far-future queue drains under realistic 10M calls.
      const resume = await hre.ethers.provider.send("evm_snapshot", []);
      let calls = 0;
      while ((await ffSnapshot(game, ffDrain.ffLevels)).inProgress) {
        await mine(game, deployer);
        expect(++calls, "far-future drain finishes in bounded realistic calls").to.be.lte(100);
      }
      expect(released(await ffSnapshot(game, ffDrain.ffLevels)), "the 10M calls released the far-future queue").to.equal(true);
      console.log(`      realistic 10M calls to finish the far-future drain: ${calls}`);
      await hre.ethers.provider.send("evm_revert", [resume]);

      // (b) Every chunk wholly inside the far-future queue, isolated at its minimum
      // admission allowance, stays <= 10M (asserted by measureNextChunk).
      let pure = 0;
      let maxPure = 0n;
      while ((await ffSnapshot(game, ffDrain.ffLevels)).inProgress) {
        const { receipt } = await measureNextChunk(game, deployer, "far-future drain (in progress)");
        if (receipt.gasUsed > maxPure) maxPure = receipt.gasUsed;
        expect(++pure, "far-future drain finishes in bounded chunks").to.be.lte(200);
      }
      expect(released(await ffSnapshot(game, ffDrain.ffLevels)), "the isolated chunks released the far-future queue").to.equal(true);
      console.log(`      isolated far-future chunks: ${pure}; heaviest ${maxPure.toLocaleString()} gas`);
      if (pure > 0) recordGas("Far-future pool drain heaviest in-progress chunk", { gasUsed: maxPure });
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
              MintPaymentKind.DirectEth,false, 
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
      await mine(game, deployer);
      const requestId = await getLastVRFRequestId(mockVRF);
      await mockVRF.fulfillRandomWords(requestId, 42n);
      for (let i = 0; i < 5 && (await game.nextMinerAction()) !== MINER_TICKETS; i++) {
        await mine(game, deployer, 1_000_000);
      }
      expect(await game.nextMinerAction(), "the Sybil cohort's ticket drain is next").to.equal(MINER_TICKETS);

      // Converted from a composed-transaction ceiling (the first unbounded call measured
      // 12.55M against an 11.5M cap). First cold chunk measured on its own, then the drain
      // must finish under realistic 10M calls; a 16.7M call from the same state succeeds.
      const start = await hre.ethers.provider.send("evm_snapshot", []);
      const { receipt: ceiling } = await mine(game, deployer, CEILING_ALLOWANCE);
      console.log(`      16.7M-allowance call: ${ceiling.gasUsed.toLocaleString()} gas`);
      await hre.ethers.provider.send("evm_revert", [start]);

      const cold = await measureNextChunk(game, deployer, "Sybil first cold ticket chunk");
      recordGas("Sybil Ticket Batch - first cold chunk", cold.receipt);
      let calls = 0;
      let maxGas = 0n;
      while ((await game.nextMinerAction()) === MINER_TICKETS) {
        const { receipt } = await mine(game, deployer);
        if (receipt.gasUsed > maxGas) maxGas = receipt.gasUsed;
        expect(++calls, "Sybil drain finishes in bounded realistic calls").to.be.lte(100);
      }
      console.log(`      realistic 10M calls to finish the Sybil drain: ${calls}; max call gas ${maxGas.toLocaleString()}`);
      expect(await game.nextMinerAction(), "ticket drain complete").to.not.equal(MINER_TICKETS);
    });
  });

  // =========================================================================
  // 15. VRF Callback Gas (rawFulfillRandomWords)
  // =========================================================================

  describe("15. VRF Callback Gas (rawFulfillRandomWords)", function () {
    it("daily RNG path (path 1): VRF callback after mineFlip triggers request", async function () {
      const { game, deployer, mockVRF, alice, bob } =
        await loadFixture(deployFullProtocol);

      // A few purchases so there are tickets in the queue (makes the
      // rngLocked path representative of a real day).
      await buyFullTickets(game, alice, 5, 0.05);
      await buyFullTickets(game, bob, 5, 0.05);

      await advanceToNextDay();

      // mineFlip() triggers the VRF request (stage=1, rngLockedFlag=true)
      await game.connect(deployer).mineFlip();
      const requestId = await getLastVRFRequestId(mockVRF);

      // Fulfill: this is rawFulfillRandomWords() — capture the full receipt.
      // receipt.gasUsed covers coordinator wrapper overhead + game callback.
      const vrfTx = await mockVRF.fulfillRandomWords(requestId, 42n);
      const vrfReceipt = await vrfTx.wait();
      recordGas("VRF Callback - daily RNG (path 1)", vrfReceipt);

      expect(vrfReceipt.status).to.equal(1);
      expect(vrfReceipt.gasUsed).to.be.lt(300_000n);
    });

    it("lootbox RNG path (path 2): VRF callback after mineFlip's mid-day request", async function () {
      // A mid-day request needs today's daily word recorded and the previous read cohort
      // complete (the read-cohort gate), so start from a settled first daily cycle.
      const { game, deployer, mockVRF, alice } = await loadFixture(readyDailyFixture);

      // A full 100-box order at the level-0 price (1 ETH): pending box value must reach the
      // mid-day threshold for mineFlip to select the request without donor credit.
      await game
        .connect(alice)
        .purchase(alice.address, 0n, boSmalls(100), ZERO_BYTES32, MintPaymentKind.DirectEth, false,
          { value: eth(1) });

      const lbRequestId = await requestMiddayRng(game, deployer, mockVRF);

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
  //   Pool >= 200 ETH -> max scale 6.36x -> bucket counts 152/104/48/1 = 305
  //   All 305 winners are unique addresses with autorebuy enabled.
  //   Each winner: _randTraitTicket (SSTORE) + _payNormalBucket/_handleSoloBucketWinner
  //   + _processAutoRebuy (_calcAutoRebuy + _queueEntries + pool writes) + event.
  //   Call 1 processes largest(159) + solo(1) = 160 winners.
  //   Call 2 processes mid(95) + small(50) = 145 winners.
  //   Each call must stay under 16M gas.
  //
  // For purchase phase path: single call, 160 winners, _processDailyEth(SPLIT_NONE).
  // For terminal path: single call, 305 winners, _processDailyEth(SPLIT_NONE).
  //
  // Pool economics at level 0:
  //   Whale bundles at level 0 cost 2.4 ETH each (WHALE_BUNDLE_EARLY_PRICE).
  //   Payment split at level 0: 30% -> nextPool, 70% -> futurePool.
  //   At jackpot transition (x00): nextPool merges into currentPool, plus
  //   35-70% of futurePool flows into currentPool via the keep roll.
  //   Level 0 triggers turbo mode (jackpotFlags=2) on day 1-2 when
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
          MintPaymentKind.DirectEth,false, 
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

      // Auto-rebuy was removed in v46 (df4ef365); the recycle worst-case path is
      // now the afking subscription system. enableAutoRebuy is retained as a
      // parameter for call-site compatibility but is a no-op here — the
      // worst-case advance gas is covered by the forge suites
      // (AdvanceGasCeilingFuzz / AdvanceStageWorstCaseGas).
      void enableAutoRebuy;

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
            .purchaseWhalePass(buyer.address, bundlesPerBuyer, hre.ethers.ZeroHash, {
              value: BigInt(bundlesPerBuyer) * pricePerBundle,
            });
        } catch {
          // If intro price fails, try standard price (4 ETH)
          try {
            await game
              .connect(buyer)
              .purchaseWhalePass(buyer.address, bundlesPerBuyer, hre.ethers.ZeroHash, {
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
     * Walk the 305-player turbo jackpot day one checkpoint at a time. Converted from
     * per-stage composed-transaction ceilings (11.5M on whole mineFlip receipts): every
     * chunk is measured at its own minimum admission allowance and must stay <= 10M, and
     * the daily ETH distribution (stage 10) plus the phase end (stage 9) must run.
     */
    async function walkPostSplit(fixture, word, label) {
      const { game, deployer, advanceModule, mockVRF } = fixture;
      const byStage = new Map();
      for (let day = 0; day < 5 && !byStage.has(9n); day++) {
        await advanceToNextDay();
        heaviestByStage(await walkNextDay(game, deployer, mockVRF, advanceModule,
          BigInt(day * 1000) + word, `${label} day ${day}`), byStage);
      }
      const order = [...byStage.keys()].sort((x, y) => Number(x - y));
      for (const st of order) {
        const c = byStage.get(st);
        console.log(`      ${label} stage ${st}: heaviest chunk ${c.gasUsed.toLocaleString()} gas (admission ${c.allowance.toLocaleString()})`);
      }
      expect(byStage.has(10n), `${label}: daily ETH distribution (stage 10) ran`).to.equal(true);
      expect(byStage.has(9n), `${label}: jackpot phase ended (stage 9)`).to.equal(true);
      return byStage;
    }

    it("SC-1: daily two-call split — 305 players, autorebuy, max-scale pool", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice, bob, carol, dan, eve, others } = fixture;

      // Step 1: Set up 305 unique players with tickets + autorebuy
      const players = await setupPlayers(
        game, [alice, bob, carol, dan, eve], others.slice(0, 300), 305, true
      );

      // Step 2: Fund pool — 5 buyers * 20 bundles * 2.4 ETH = 240 ETH total
      await fundPoolHeavy(game, players.slice(0, 5), 20);

      const byStage = await walkPostSplit(fixture, 305305n, "SC-1");
      recordGas("WC: Daily ETH heaviest chunk (stage=10)", byStage.get(10n).receipt);
      const jpPool = await game.currentPrizePoolView();
      console.log(`      Pool after jackpot: ${hre.ethers.formatEther(jpPool)} ETH`);
    });

    it("SC-2a: purchase phase path — 160 winners, moderate pool", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice, bob, carol, dan, eve, others } = fixture;

      const players = await setupPlayers(
        game, [alice, bob, carol, dan, eve], others.slice(0, 300), 305, false
      );
      await fundPoolHeavy(game, players.slice(0, 5), 20);

      const byStage = await walkPostSplit(fixture, 160160n, "SC-2a");
      recordGas("WC: Early-Burn ETH heaviest chunk (stage=10)", byStage.get(10n).receipt);
    });

    it("SC-2b: terminal jackpot path — 305 winners, no autorebuy, max pool", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice, bob, carol, dan, eve, others } = fixture;

      const players = await setupPlayers(
        game, [alice, bob, carol, dan, eve], others.slice(0, 300), 305, false
      );
      await fundPoolHeavy(game, players.slice(0, 5), 20);

      // Turbo's only draw is also its final day: 100% pool distribution.
      const byStage = await walkPostSplit(fixture, 777777n, "SC-2b");
      recordGas("WC: Terminal Jackpot heaviest chunk (stage=10)", byStage.get(10n).receipt);
      recordGas("WC: Final day phase end chunk (stage=9)", byStage.get(9n).receipt);
    });
  });
});

// ===========================================================================
// Phase 264 SURF-05 D-IMPL-06 — HEAD-only mineFlip margin record.
//
// The disclosed REQUIREMENTS.md SURF-05 invariant is `MAX_BLOCK_GAS /
// WORST_CASE_ADVANCE_GAS ≥ 1.99`. Under the checkpointed engine the unit of
// advance work is one admitted chunk, not a whole transaction (a call keeps admitting
// chunks while its allowance lasts, so a transaction's total only mirrors its gas
// limit). This block re-runs the section-16 SC-1 fixture (305 players, max-scale
// pool), walks the turbo jackpot day one chunk at a time, and asserts the margin
// against the heaviest measured chunk.
// ===========================================================================

describe("Phase 264 SURF-05 — mineFlip 1.99× margin preserved at v35.0 HEAD", function () {
  this.timeout(1_800_000); // 30 min — re-runs the SC-1 305-player setup

  const MAX_BLOCK_GAS = 30_000_000n;
  const REQUIRED_MARGIN = 1.99;

  // Local copies of the section-16 helpers — re-declared inside this describe
  // block to keep the existing section-16 byte-identical (no shared-helper
  // refactor in Phase 264 per D-IMPL-06; section-16 file shape unchanged for
  // git-blame stability).
  async function buyOneTicket(game, buyer) {
    return game.connect(buyer).purchase(
      ZERO_ADDRESS,
      400n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      false,
      { value: eth(0.01) },
    );
  }

  async function setupPlayers(game, namedSigners, otherSigners, count, enableAutoRebuy) {
    const players = [...namedSigners, ...otherSigners].slice(0, count);
    console.log(`      [Phase 264 SURF-05] Setting up ${players.length} players...`);

    const batchSize = 50;
    for (let start = 0; start < players.length; start += batchSize) {
      const batch = players.slice(start, start + batchSize);
      await Promise.all(batch.map(p => buyOneTicket(game, p)));
    }
    console.log(`      [Phase 264 SURF-05] ${players.length} tickets purchased`);

    // Auto-rebuy removed in v46 (df4ef365); no-op here (see section-16 note).
    // The worst-case advance gas is covered by the forge gas suites.
    void enableAutoRebuy;

    return players;
  }

  async function fundPoolHeavy(game, buyers, bundlesPerBuyer) {
    const pricePerBundle = eth(2.4);
    for (const buyer of buyers) {
      try {
        await game
          .connect(buyer)
          .purchaseWhalePass(buyer.address, bundlesPerBuyer, hre.ethers.ZeroHash, {
            value: BigInt(bundlesPerBuyer) * pricePerBundle,
          });
      } catch {
        try {
          await game
            .connect(buyer)
            .purchaseWhalePass(buyer.address, bundlesPerBuyer, hre.ethers.ZeroHash, {
              value: BigInt(bundlesPerBuyer) * eth(4),
            });
        } catch {
          console.log(`      [Phase 264 SURF-05] (Whale bundle failed for ${buyer.address.slice(0, 8)}...)`);
        }
      }
    }
    const pool = await game.currentPrizePoolView();
    const nextPool = await game.nextPrizePoolView();
    console.log(`      [Phase 264 SURF-05] Pool: ${hre.ethers.formatEther(pool)} ETH (current) + ${hre.ethers.formatEther(nextPool)} ETH (next)`);
  }

  async function runWorstCaseBenchmarkAtHead() {
    const fixture = await loadFixture(deployFullProtocol);
    const { game, deployer, advanceModule, mockVRF, alice, bob, carol, dan, eve, others } = fixture;

    // SC-1 fixture composition: 305 players + autorebuy + 5 buyers × 20 bundles.
    const players = await setupPlayers(
      game, [alice, bob, carol, dan, eve], others.slice(0, 300), 305, true,
    );
    await fundPoolHeavy(game, players.slice(0, 5), 20);

    const stageReceipts = new Map();
    for (let day = 0; day < 5 && !stageReceipts.has(9n); day++) {
      await advanceToNextDay();
      heaviestByStage(await walkNextDay(game, deployer, mockVRF, advanceModule,
        BigInt(day * 1000 + 305305), `[Phase 264 SURF-05] day ${day}`), stageReceipts);
      if (stageReceipts.has(9n)) console.log(`      [Phase 264 SURF-05] Jackpot phase ended on day ${day}`);
    }
    return stageReceipts;
  }

  it("preserves 1.99× margin at v35.0 HEAD across the worst-case mineFlip path", async function () {
    const stageReceipts = await runWorstCaseBenchmarkAtHead();

    expect(
      stageReceipts.size > 0,
      "Phase 264 SURF-05: worst-case benchmark fixture failed to capture any mineFlip stages — fixture regression",
    ).to.equal(true);

    let maxGas = 0n;
    let maxStage = -1;
    for (const [stage, chunk] of stageReceipts) {
      if (chunk.gasUsed > maxGas) {
        maxGas = chunk.gasUsed;
        maxStage = Number(stage);
      }
    }

    // Every walked chunk already asserted <= 10M inside measureNextChunk.
    const margin = Number(MAX_BLOCK_GAS) / Number(maxGas);
    console.log(`      [Phase 264 SURF-05] heaviest chunk stage = ${maxStage}, gasUsed = ${maxGas.toLocaleString()}, margin = ${margin.toFixed(3)}× (required ≥ ${REQUIRED_MARGIN})`);

    expect(
      margin >= REQUIRED_MARGIN,
      `Phase 264 SURF-05: mineFlip margin ${margin.toFixed(3)} < required ${REQUIRED_MARGIN} (max-gas stage ${maxStage} = ${maxGas.toLocaleString()})`,
    ).to.equal(true);
  });
});
