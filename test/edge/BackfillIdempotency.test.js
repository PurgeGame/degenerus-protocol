import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol } from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };
const BOOTSTRAP_PRIZE_POOL = eth(50);

/**
 * BackfillIdempotency — empirical reproduction of the multi-day VRF stall
 * backfill double-execution bug fixed at AdvanceModule:1174.
 *
 * Authoring source: audit/v32-248-BFL.md §7.1 verbatim 8-step trigger sequence.
 * Cross-cite: §3 BFL-03 worked-numeric example (testnet blocks 10759449 +
 * 10761786 multi-day VRF stall). This test isolates the L1174 backfill
 * sentinel's load-bearing role.
 *
 * RNG commitment-window invariant (per feedback_rng_backward_trace.md +
 * feedback_rng_commitment_window.md): no player-controllable state changes
 * between _backfillGapDays first call (Step 5) and second call (Step 7) that
 * would invalidate the L1174 sentinel-clear logic. Verified by inspection of
 * the trigger sequence: only `block.timestamp` advances; no purchase / freeze
 * / unfreeze / phase-transition mutations occur between the two calls.
 *
 * Pre-state setup (BFL §7.1):
 *   1. dailyIdx = N, rngWordByDay[N] = W_prev populated cleanly via prior
 *      cycles (drives game past initial state and produces a recorded gap).
 *   2. Issue daily VRF request via advanceGame → rngLockedFlag = true,
 *      rngRequestTime = T1.
 *   3. Mock rawFulfillRandomWords delivers currentWord = W1 while
 *      rngLockedFlag remains true (i.e., _unlockRng has NOT run yet).
 *   4. advanceToNextDay() — bump block.timestamp by 1 day. NO _unlockRng.
 *   5. advanceGame() → rngGate fresh-word branch executes; backfill
 *      bumps purchaseStartDay by gapCount = day - idx - 1.
 *   6. advanceToNextDay() — bump again. Still no _unlockRng (drain
 *      stops at intermediate stage).
 *   7. advanceGame() → rngGate fresh-word branch re-enters.
 *      PRE-FIX (state C): backfill body re-executes for the same gap range;
 *      purchaseStartDay BUMPS AGAIN with the new gapCount = day - idx - 1
 *      (where idx is unchanged because _unlockRng hasn't run). Total
 *      psd delta exceeds the natural day-count.
 *      POST-FIX (state D): L1174 sentinel sees rngWordByDay[idx + 1] != 0
 *      (Step 5's _backfillGapDays wrote it); the guarded block SKIPS;
 *      psd is NOT re-bumped beyond what natural advance does.
 *   8. Assert: psd delta over the trigger sequence equals the expected
 *      single-bump amount (one bump per gap day, no double application).
 *
 * Storage-slot decoding: purchaseStartDay is at slot 0 bytes [0:4] (uint32),
 * per contracts/storage/DegenerusGameStorage.sol L228 + slot-layout comment.
 * No public accessor exists; we read via eth_getStorageAt and decode the
 * lowest 4 bytes (little-endian within the 32-byte slot).
 */

const SLOT0_PSD_MASK32 = (1n << 32n) - 1n;

async function readPurchaseStartDay(gameAddr) {
  const slot0 = BigInt(await hre.ethers.provider.getStorage(gameAddr, 0));
  return Number(slot0 & SLOT0_PSD_MASK32);
}

async function buyFullTickets(game, buyer, n, totalEth) {
  return game.connect(buyer).purchase(
    ZERO_ADDRESS,
    BigInt(n) * 400n,
    0n,
    ZERO_BYTES32,
    MintPaymentKind.DirectEth,false, 
    { value: eth(totalEth) }
  );
}

async function heavyPurchases(game, buyers) {
  for (const buyer of buyers) {
    try {
      await game
        .connect(buyer)
        .purchaseWhalePass(buyer.address, 1, { value: eth(2.4) });
    } catch {}
    await buyFullTickets(game, buyer, 500, 5);
  }
}

async function driveCycleToDailyClose(game, deployer, mockVRF, word, gapDays = 0) {
  await advanceToNextDay();
  for (let i = 0; i < gapDays; i++) await advanceToNextDay();
  await game.connect(deployer).advanceGame();
  const requestId = await getLastVRFRequestId(mockVRF);
  try { await mockVRF.fulfillRandomWords(requestId, word); } catch {}
  for (let i = 0; i < 200; i++) {
    if (!(await game.rngLocked())) return;
    try { await game.connect(deployer).advanceGame(); } catch { return; }
  }
}

describe("BackfillIdempotency (multi-day VRF stall double-execution)", function () {
  it(
    "does NOT double-bump purchaseStartDay across a 2-day VRF stall (BFL §7.1)",
    async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        fixture;
      const gameAddr = await game.getAddress();

      // ---- Step 1: pre-state — populate dailyIdx via prior cycles ----
      // Drive the game past initial state so dailyIdx > 0 and
      // rngWordByDay[N] is populated cleanly. Mirror the proven
      // LastPurchaseDayRace multi-day-drain pre-state.
      await buyFullTickets(game, alice, 30, 0.3);
      await driveCycleToDailyClose(game, deployer, mockVRF, 11n, 1);
      expect(await game.purchaseInfo().then(i => i.lastPurchaseDay_)).to.equal(false);

      await buyFullTickets(game, bob, 30, 0.3);
      await driveCycleToDailyClose(game, deployer, mockVRF, 13n, 1);
      expect(await game.purchaseInfo().then(i => i.lastPurchaseDay_)).to.equal(false);

      // Heavy mints push pool past threshold.
      const buyers = [carol, dan, eve, ...others.slice(0, 16)];
      await heavyPurchases(game, buyers);
      expect(await game.nextPrizePoolView()).to.be.gte(BOOTSTRAP_PRIZE_POOL);

      // ---- Step 2: freeze cycle — issue VRF request via advanceGame ----
      // purchaseDays > 1 (3-day skip) so turbo skipped. _requestRng with
      // isTicketJackpotDay=false freezes pool past-threshold; rngLocked=true.
      await advanceToNextDay();
      await advanceToNextDay();
      await advanceToNextDay();
      await game.connect(alice).advanceGame();
      expect(await game.rngLocked()).to.equal(true, "Step 2: rngLockedFlag must be true after freeze");
      expect(await game.level()).to.equal(0n);

      const requestId = await getLastVRFRequestId(mockVRF);

      // Long pre-VRF gap (extends the lock window across multiple wall-clock days).
      for (let i = 0; i < 5; i++) await advanceToNextDay();

      // Capture purchaseStartDay BEFORE Step 3 fulfillment.
      // (After this point, drain begins and may bump psd via backfill.)
      const psdBefore = await readPurchaseStartDay(gameAddr);

      // ---- Step 3: rawFulfillRandomWords delivers W1 while lock held ----
      await mockVRF.fulfillRandomWords(requestId, 7777n);

      // ---- Steps 4-7: drain across MULTIPLE wall-clock days ----
      // Mirror the proven multi-day-drain harness from
      // LastPurchaseDayRace.test.js L262-298. After the first stage-4
      // event (rngGate fresh-word ran, psd bumped by gapCount), advance
      // the wall clock by 1 day. The next call's rngGate sees a NEW day
      // — pre-fix, this re-enters the backfill body; post-fix, the L1174
      // sentinel rngWordByDay[idx+1] != 0 short-circuits.
      let panicked = false;
      let panicMsg = "";
      const stages = {};
      let dayBumps = 0;
      let firstStageFourSeen = false;

      for (let i = 0; i < 500; i++) {
        if (firstStageFourSeen && dayBumps === 0) {
          await advanceToNextDay();
          dayBumps++;
        }
        let lastStage = -1;
        try {
          const tx = await game.connect(alice).advanceGame();
          const receipt = await tx.wait();
          for (const log of receipt.logs) {
            try {
              const parsed = advanceModule.interface.parseLog(log);
              if (parsed && parsed.name === "Advance") {
                const s = Number(parsed.args.stage);
                stages[s] = (stages[s] || 0) + 1;
                lastStage = s;
              }
            } catch {}
          }
          if (lastStage === 4) firstStageFourSeen = true;
        } catch (e) {
          const msg = (e && (e.shortMessage || e.message)) || "";
          console.log(`BFL iter ${i} (dayBumps=${dayBumps}, lastStage=${lastStage}): ${msg.slice(0, 200)}`);
          if (msg.includes("0x11") || msg.toLowerCase().includes("panic")) {
            panicked = true;
            panicMsg = msg;
          }
          break;
        }
        if (!(await game.rngLocked())) break;
        if (await game.jackpotPhase()) break;
      }

      const psdAfter = await readPurchaseStartDay(gameAddr);
      const psdDelta = psdAfter - psdBefore;
      console.log(`BFL psdBefore=${psdBefore} psdAfter=${psdAfter} delta=${psdDelta} dayBumps=${dayBumps} stages=${JSON.stringify(stages)} panicked=${panicked}`);

      // ---- Step 8: primary assertion — backfill idempotency ----
      // Pre-state: 5-day pre-VRF gap (Steps before fulfill) + dayBumps
      // additional wall-clock day(s) introduced during drain.
      //
      // Backfill bump algebra (BFL §7.1 + §6 BFL-06 conservation):
      //   - Step 5 first-call: psd += (gapDays_at_step5)
      //   - Step 7 second-call:
      //       PRE-FIX (state C, backfill reverted):
      //         backfill body re-executes; psd += (gapDays_at_step7)
      //         where gapDays_at_step7 ≥ gapDays_at_step5 + dayBumps
      //         (idx unchanged because _unlockRng didn't run).
      //         This is the over-application — the same gap range is
      //         credited twice + the new dayBumps is credited again.
      //       POST-FIX (state D, L1174 sentinel in place):
      //         backfill body SKIPS; psd is NOT bumped on Step 7. The
      //         only psd change is from Step 5's first call. Total
      //         delta equals the natural one-time gapDays bump.
      //
      // The discriminating assertion: state C's psdDelta is strictly
      // greater than state D's psdDelta. The exact state-D value depends
      // on the runtime gapDays computation; we assert the upper bound that
      // state-D MUST satisfy and state-C MUST violate.
      //
      // Concrete bound: in the proven multi-day-drain pattern, the first
      // backfill bumps by ~5-8 days (the pre-VRF gap). Pre-fix re-application
      // would roughly DOUBLE this. Post-fix delta should be ≤ initial gap
      // bump (no re-application). We assert delta ≤ the initial pre-VRF
      // gap (5) + a generous slack (3) = 8. State C should produce ≥ 10.
      //
      // To make the test robust against minor harness changes, we assert:
      //   - panicked == false (state-D smoke-check; aligns with TST-02)
      //   - psdDelta ≤ MAX_EXPECTED_DELTA (catches over-bump)
      //   - psdDelta ≥ MIN_EXPECTED_DELTA (catches under-bump regression)
      const MIN_EXPECTED_DELTA = 1;
      const MAX_EXPECTED_DELTA = 8;

      expect(panicked).to.equal(
        false,
        `BackfillIdempotency: drain panicked (state-C bug recurrence): ${panicMsg}`
      );

      expect(psdDelta).to.be.lte(
        MAX_EXPECTED_DELTA,
        `purchaseStartDay over-bumped — psdDelta=${psdDelta} > MAX_EXPECTED_DELTA=${MAX_EXPECTED_DELTA}. ` +
          `Backfill guard L1174 violation: gap range was credited twice across the multi-day VRF stall.`
      );

      expect(psdDelta).to.be.gte(
        MIN_EXPECTED_DELTA,
        `purchaseStartDay under-bumped — psdDelta=${psdDelta} < MIN_EXPECTED_DELTA=${MIN_EXPECTED_DELTA}. ` +
          `Possible regression: gap-day backfill never executed.`
      );
    }
  );
});
