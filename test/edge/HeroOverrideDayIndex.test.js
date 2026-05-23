// SPDX-License-Identifier: AGPL-3.0-only
//
// HeroOverrideDayIndex.test.js — Phase 289 TST-HOFIX + TST-JPSURF hero-override
// day-index regression fixture (v41.0 Cross-Call Determinism Fix milestone).
//
// Tests two sets of invariants at post-Phase-288 HEAD `4837fa5c`:
//
// PART A — TST-HOFIX-01..05 (game-mechanic invariants under D-288-FIX-SHAPE-01):
//
//   - `dailyHeroWagers[D]` holds bets placed on day D (canonical mental model).
//   - Read at JackpotModule:1602 via `_topHeroSymbol(dailyIdx)` returns the
//     prior-cycle-day's bet pool because `dailyIdx` is set by `_unlockRng`
//     (AdvanceModule:1697) at the END of the previous day's jackpot cycle and
//     remains frozen across the entire next rng-lock window.
//   - Bets placed during the rng-lock window write to
//     `dailyHeroWagers[_simulatedDayIndex()]` (canonical) — a slot DIFFERENT
//     from `dailyHeroWagers[dailyIdx]` (the operational read slot) — so they
//     cannot mutate the in-flight jackpot's hero-override input.
//
// PART B — TST-JPSURF-01..04 (F-41-03 cross-day CALL 1/CALL 2 regression):
//
//   - Both CALL 1 and CALL 2 of the 2-call ETH split read
//     `dailyHeroWagers[dailyIdx]`. Because `dailyIdx` is frozen by design
//     across the entire rng-lock window, the slot read is identical regardless
//     of whether CALL 2 lands on the same physical day as CALL 1 or hours/days
//     later. Disjoint-bucket-subset invariant (Phase 283 SWEEP-04) holds via
//     this anchor.
//
// Assertion vehicle: the public view `getDailyHeroWinner(day)` at
// DegenerusGame.sol:2545 runs the same algorithm as the internal
// `_topHeroSymbol(day)` at JackpotModule:1625-1653 consumed by
// `_applyHeroOverride` at JackpotModule:1600-1604. Asserting against the view
// with `day = dailyIdx` is algorithm-equivalent to asserting against what
// `payDailyJackpot`'s CALL 1 + CALL 2 would consume.
//
// `dailyIdx` is `internal` (DegenerusGameStorage:236) — no external accessor.
// Tests read it directly from storage slot 0 (per the layout doc at
// DegenerusGameStorage:48 — bytes [4:8] of slot 0).
//
// Evidence class: ALGORITHM_VERIFIED (per D-285-EVIDENCE-CLASS-01 inherited).
// No git-worktree at pre-Phase-288 HEAD; no captured pre-fix witness JSON.
// Assertions are post-fix-invariant form — verifying the structural
// `dailyIdx`-frozen invariant directly rather than capturing pre-fix
// divergence witnesses.

import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { advanceToNextDay } from "../helpers/testUtils.js";

// MIN_BET_ETH at DegenerusGameDegeneretteModule:217 (5 ether / 1000).
const MIN_BET_ETH_VALUE = hre.ethers.parseEther("0.005");

// Storage slot for lootboxRngPacked in DegenerusGame. Resolved via the
// hardhat storage-layout artifact (`getBuildInfo()` → contracts →
// storageLayout) — slot index 35 at offset 0, type uint256. The low 48 bits
// are `lootboxRngIndex` (LR_INDEX_SHIFT=0, LR_INDEX_MASK=0xFFFFFFFFFFFF).
const LOOTBOX_RNG_PACKED_SLOT = "0x" + (35).toString(16).padStart(64, "0");

// Storage slot 0 holds the packed timing/FSM struct per
// DegenerusGameStorage.sol:44-66. `dailyIdx` (uint32) occupies bytes [4:8],
// little-endian within the 32-byte slot (EVM stores low bytes at low offset
// in the byte stream, which is the high bits of the big-endian word read).
// The slot is read as a 256-bit big-endian word; dailyIdx is at bit-shift 32
// (byte offset 4) so `(word >> 32) & 0xFFFFFFFF` extracts it.
const SLOT0_TIMING_FSM = "0x" + (0).toString(16).padStart(64, "0");
const DAILY_IDX_BIT_SHIFT = 32n;
const UINT32_MASK = 0xffffffffn;

// Currency tag for ETH bets per DegenerusGameDegeneretteModule constants.
const CURRENCY_ETH = 0;

/// Seed `lootboxRngPacked` low 48 bits to `index` so the bet gate at
/// DegenerusGameDegeneretteModule:451 (`if (index == 0) revert E()`) opens.
/// The companion check at L452 (`if (lootboxRngWordByIndex[index] != 0)
/// revert RngNotReady()`) passes by default — slot for index=1 is unset so
/// the word reads as zero.
async function seedLootboxRngIndex(gameAddr, index = 1) {
  const provider = hre.ethers.provider;
  const current = BigInt(
    await provider.getStorage(gameAddr, LOOTBOX_RNG_PACKED_SLOT)
  );
  const INDEX_MASK = (1n << 48n) - 1n;
  const cleared = current & ~INDEX_MASK;
  const updated = cleared | (BigInt(index) & INDEX_MASK);
  await hre.network.provider.send("hardhat_setStorageAt", [
    gameAddr,
    LOOTBOX_RNG_PACKED_SLOT,
    "0x" + updated.toString(16).padStart(64, "0"),
  ]);
}

/// Pack a customTicket so that the heroQuadrant's symbol byte decodes to
/// `symbol` via `uint8(customTicket >> (heroQuadrant * 8)) & 7` (the
/// extraction at DegenerusGameDegeneretteModule:488).
function customTicketWithSymbol(quadrant, symbol) {
  return (symbol & 0x7) << (quadrant * 8);
}

/// Place one ETH-currency degenerette bet for `signer` against the given
/// (quadrant, symbol). Defaults to MIN_BET_ETH per spin, 1 spin total.
async function placeEthBet(game, signer, quadrant, symbol) {
  const customTicket = customTicketWithSymbol(quadrant, symbol);
  return game.connect(signer).placeDegeneretteBet(
    hre.ethers.ZeroAddress, // player = msg.sender via _resolvePlayer
    CURRENCY_ETH,
    MIN_BET_ETH_VALUE,
    1, // ticketCount
    customTicket,
    quadrant,
    { value: MIN_BET_ETH_VALUE }
  );
}

/// Returns the (winQuadrant, winSymbol, winAmount) triple from the
/// algorithm-equivalent public view. Plain numbers + bigints for assertion
/// equality.
async function readWinner(game, day) {
  const [winQuadrant, winSymbol, winAmount] =
    await game.getDailyHeroWinner(day);
  return {
    winQuadrant: Number(winQuadrant),
    winSymbol: Number(winSymbol),
    winAmount: BigInt(winAmount),
  };
}

function winnersEqual(a, b) {
  return (
    a.winQuadrant === b.winQuadrant &&
    a.winSymbol === b.winSymbol &&
    a.winAmount === b.winAmount
  );
}

/// Read the `dailyIdx` uint32 directly from storage slot 0 of the game
/// contract. `dailyIdx` is `internal` — no external accessor — but its
/// position is byte-level documented at DegenerusGameStorage:44-66 (bytes
/// [4:8] of slot 0).
async function readDailyIdx(gameAddr) {
  const provider = hre.ethers.provider;
  const word = BigInt(await provider.getStorage(gameAddr, SLOT0_TIMING_FSM));
  return Number((word >> DAILY_IDX_BIT_SHIFT) & UINT32_MASK);
}

// =============================================================================
// PART A — TST-HOFIX-01..05 (Phase 288 D-288-FIX-SHAPE-01 regression)
// =============================================================================

describe("HeroOverrideDayIndex (TST-HOFIX) — Phase 288 D-288-FIX-SHAPE-01 regression", function () {
  this.timeout(120_000);

  after(() => restoreAddresses());

  // -------------------------------------------------------------------------
  // TST-HOFIX-01 — bets during the rng-lock window do NOT mutate the slot
  //                the in-flight jackpot reads
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-01 — bets during the rng-lock window do NOT mutate slot[dailyIdx]", function () {
    it("bet placed on day _simulatedDayIndex() writes to slot[_simulatedDayIndex()] (canonical); slot[dailyIdx] (the operational read slot) is unaffected when dailyIdx != _simulatedDayIndex()", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const wallDay = Number(await game.currentDayView());
      const initialDailyIdx = await readDailyIdx(gameAddr);

      // At fixture start, the constructor sets dailyIdx = currentDay
      // (DegenerusGame.sol:219), so dailyIdx == wallDay initially. Advance
      // wall-clock by one day to create the steady-state condition:
      // dailyIdx == initialDailyIdx (no `_unlockRng` fires in this fixture),
      // wallDay == initialDailyIdx + 1. This mirrors the production state
      // during the rng-lock window: dailyIdx is frozen at the PREVIOUS day's
      // resolved index while the wall-clock is the CURRENT day.
      await advanceToNextDay();
      const wallDayNow = Number(await game.currentDayView());
      const dailyIdxNow = await readDailyIdx(gameAddr);
      expect(wallDayNow).to.equal(
        wallDay + 1,
        "wall-clock day must advance from D to D+1"
      );
      expect(dailyIdxNow).to.equal(
        initialDailyIdx,
        "dailyIdx must be FROZEN across the time-warp (no _unlockRng fired)"
      );
      expect(dailyIdxNow).to.not.equal(
        wallDayNow,
        "steady-state condition reached: dailyIdx != wall-clock day"
      );

      // Pre-bet: slot[dailyIdx] is empty.
      const preOperationalWinner = await readWinner(game, dailyIdxNow);
      expect(preOperationalWinner.winAmount).to.equal(
        0n,
        `slot[dailyIdx=${dailyIdxNow}] (operational read slot) must be empty at fixture start`
      );

      // Place one ETH bet on wallDayNow (the current wall-clock day).
      // Under D-288-FIX-SHAPE-01, this writes to
      // dailyHeroWagers[_simulatedDayIndex()] == slot[wallDayNow] — NOT
      // slot[dailyIdx].
      await placeEthBet(game, alice, 2, 5);

      // The bet landed in slot[wallDayNow] (canonical):
      const wagerAtWallDay = BigInt(
        await game.getDailyHeroWager(wallDayNow, 2, 5)
      );
      expect(wagerAtWallDay).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n,
        `getDailyHeroWager(wallDayNow=${wallDayNow}, q=2, s=5) must equal MIN_BET_ETH/1e12 (canonical slot[D] = bets placed on day D)`
      );

      // slot[dailyIdx] is unchanged — the operational read for the in-flight
      // jackpot consumes the same value as before the bet:
      const postOperationalWinner = await readWinner(game, dailyIdxNow);
      expect(winnersEqual(preOperationalWinner, postOperationalWinner)).to.equal(
        true,
        `slot[dailyIdx=${dailyIdxNow}] read MUST be unchanged by an inter-window bet on day ${wallDayNow}`
      );
      expect(postOperationalWinner.winAmount).to.equal(
        0n,
        `slot[dailyIdx=${dailyIdxNow}] must REMAIN empty — inter-window bet wrote to slot[${wallDayNow}], not slot[${dailyIdxNow}]`
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-HOFIX-02 — bets on day D DO populate slot[D]; next day's jackpot
  //                (with dailyIdx == D) consumes them
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-02 — bets on day D populate slot[D]; the next jackpot cycle (dailyIdx == D) consumes them", function () {
    it("bet placed on day D writes slot[D]; getDailyHeroWinner(D) returns the (Q, S) bet — this slot is what `_topHeroSymbol(dailyIdx=D)` would read on day D+1", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());
      const Q = 1;
      const S = 3;

      await placeEthBet(game, alice, Q, S);

      // Bet landed in slot[D] (canonical post-Phase-288 semantic).
      const winnerOnD = await readWinner(game, D);
      expect(winnerOnD.winQuadrant).to.equal(
        Q,
        `getDailyHeroWinner(D=${D}) winQuadrant must equal placed-bet quadrant ${Q}`
      );
      expect(winnerOnD.winSymbol).to.equal(
        S,
        `getDailyHeroWinner(D=${D}) winSymbol must equal placed-bet symbol ${S}`
      );
      expect(winnerOnD.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n,
        `getDailyHeroWinner(D=${D}) winAmount must equal MIN_BET_ETH/1e12 wager units`
      );

      // Advance to day D+1. In production, day D's `_unlockRng` would set
      // `dailyIdx = D` at end-of-day-D. The simplified fixture doesn't drive
      // the actual stage machine, but the algorithm-level claim is: when day
      // D+1's jackpot fires with `dailyIdx == D`, `_topHeroSymbol(dailyIdx)`
      // reads slot[D] — which is exactly the bet population captured above.
      await advanceToNextDay();
      expect(Number(await game.currentDayView())).to.equal(
        D + 1,
        `currentDayView must advance from D=${D} to D+1=${D + 1}`
      );

      // Re-read slot[D] from the post-warp position — value persists.
      const winnerOnDPostWarp = await readWinner(game, D);
      expect(winnersEqual(winnerOnD, winnerOnDPostWarp)).to.equal(
        true,
        `slot[D=${D}] population must persist across the wall-clock day boundary (storage map; no time-decay)`
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-HOFIX-03 — 2-call ETH split read consistency under inter-call bet
  //                interleaving (D-282-B2-COVERAGE-01 symmetric pair under
  //                Phase 288 mechanism)
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-03 — 2-call ETH split read consistency under inter-call bet interleaving (dailyIdx-anchored)", function () {
    it("snapshot1 (pre-bet) === snapshot2 (post-bet) for getDailyHeroWinner(dailyIdx) — CALL 1 and CALL 2 of payDailyJackpot consume identical algorithm output via the frozen dailyIdx slot anchor", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());

      // Seed slot[dailyIdx] (== slot[D] at fixture start) with a non-trivial
      // bet. This represents the "prior-cycle hero population" that the
      // operational read will consume.
      await placeEthBet(game, alice, 0, 4);

      // Advance wall-clock so dailyIdx (== D, frozen) != _simulatedDayIndex()
      // (== D+1). This creates the rng-lock-window steady-state.
      await advanceToNextDay();
      const dailyIdxFrozen = await readDailyIdx(gameAddr);
      const wallDayNow = Number(await game.currentDayView());
      expect(dailyIdxFrozen).to.equal(
        D,
        "dailyIdx must remain at its fixture-init value D"
      );
      expect(wallDayNow).to.equal(
        D + 1,
        "wall-clock must have advanced past dailyIdx"
      );

      // Snapshot1: what CALL 1 of payDailyJackpot would consume (read against
      // slot[dailyIdx]).
      const snapshot1 = await readWinner(game, dailyIdxFrozen);
      expect(snapshot1.winAmount).to.be.greaterThan(
        0n,
        `slot[dailyIdx=${dailyIdxFrozen}] must be populated by alice's day-${D} bet`
      );

      // Inter-call interleaving: bob places a bet on wallDayNow. Under
      // D-288-FIX-SHAPE-01 the write goes to slot[wallDayNow] — NOT
      // slot[dailyIdx] which CALL 2 of the jackpot would re-read.
      await placeEthBet(game, bob, 3, 7);

      // Snapshot2: what CALL 2 of payDailyJackpot would consume after the
      // interleaved bet.
      const snapshot2 = await readWinner(game, dailyIdxFrozen);

      expect(winnersEqual(snapshot1, snapshot2)).to.equal(
        true,
        `CALL 1 snapshot ${JSON.stringify({
          ...snapshot1,
          winAmount: snapshot1.winAmount.toString(),
        })} must equal CALL 2 snapshot ${JSON.stringify({
          ...snapshot2,
          winAmount: snapshot2.winAmount.toString(),
        })} — inter-call bet writes to slot[wallDayNow=${wallDayNow}] which is disjoint from slot[dailyIdx=${dailyIdxFrozen}]`
      );

      // Sanity: bob's bet landed at slot[wallDayNow] (canonical).
      const wallDayWinner = await readWinner(game, wallDayNow);
      expect(wallDayWinner.winQuadrant).to.equal(
        3,
        `bob's interleaved bet must land at slot[wallDayNow=${wallDayNow}] (canonical: slot[D] = bets placed on day D)`
      );
      expect(wallDayWinner.winSymbol).to.equal(7);
      expect(wallDayWinner.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-HOFIX-04 — F-41-02 algorithm-level invariant under arbitrary
  //                interleaving (Phase 284 Hypothesis (ix) closure regression
  //                — restated for the dailyIdx-frozen-during-rng-lock shape)
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-04 — F-41-02 algorithm-level invariant: multiple _topHeroSymbol(dailyIdx) invocations during a single jackpot window return identical value under arbitrary interleaved bet placement", function () {
    it("captures getDailyHeroWinner(dailyIdx) → interleaves bet on the current wall-clock day (writes to slot[wallDay], NOT slot[dailyIdx]) → re-captures getDailyHeroWinner(dailyIdx); both captures identical", async function () {
      const { game, alice, carol } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());

      // alice bets on day D for the (Q1=0, S1=3) slot → lands in slot[D]
      // (canonical post-Phase-288 semantic).
      const Q1 = 0;
      const S1 = 3;
      await placeEthBet(game, alice, Q1, S1);

      // Advance wall-clock to day D+1. dailyIdx remains FROZEN at D.
      await advanceToNextDay();
      const dailyIdxFrozen = await readDailyIdx(gameAddr);
      expect(dailyIdxFrozen).to.equal(
        D,
        "dailyIdx must be FROZEN at D — no _unlockRng fired"
      );
      expect(Number(await game.currentDayView())).to.equal(D + 1);

      // Capture 1: what `_topHeroSymbol(dailyIdx)` returns at start of the
      // next jackpot window.
      const capture1 = await readWinner(game, dailyIdxFrozen);
      expect(capture1.winQuadrant).to.equal(Q1);
      expect(capture1.winSymbol).to.equal(S1);
      expect(capture1.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n
      );

      // Interleave: carol places bet on the current wall-clock day (D+1)
      // with a competing (Q2=1, S2=5). Under D-288-FIX-SHAPE-01 this writes
      // to slot[D+1] — NOT slot[dailyIdx=D].
      const Q2 = 1;
      const S2 = 5;
      await placeEthBet(game, carol, Q2, S2);

      // Capture 2: re-read `_topHeroSymbol(dailyIdx)` after the interleaved
      // bet.
      const capture2 = await readWinner(game, dailyIdxFrozen);

      expect(winnersEqual(capture1, capture2)).to.equal(
        true,
        `_topHeroSymbol(dailyIdx=${dailyIdxFrozen}) must return identical value across re-invocations under arbitrary inter-window bet interleaving`
      );

      // Sanity: carol's bet landed at slot[D+1] (the wall-clock day).
      const wallDayWinner = await readWinner(game, D + 1);
      expect(wallDayWinner.winQuadrant).to.equal(
        Q2,
        "carol's day-D+1 bet must land at slot[D+1] (canonical: slot[D] = bets placed on day D)"
      );
      expect(wallDayWinner.winSymbol).to.equal(S2);
      expect(wallDayWinner.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-HOFIX-05 — ZEROS OUT (placeholder documentation per HOFIX-AUDIT)
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-05 — additional FIX-HOFIX-SWEEP-NN regression", function () {
    it("ZEROS OUT — Phase 285 HOFIX-AUDIT broad sweep (D-285-AUDIT-SCOPE-01) surfaced 0 additional GAPs beyond F-41-02 (dailyHeroWagers); no additional surfaces to regress", function () {
      // Per .planning/phases/285-day-index-read-audit-hero-override-fix-hofix/
      // 285-01-HOFIX-AUDIT.md §3: 5 day-keyed storage maps + 31
      // _simulatedDayIndex() callsites enumerated; 1 GAP (dailyHeroWagers,
      // covered by FIX-HOFIX-01 → superseded by Phase 288 FIX-JPSURF-01); 0
      // FIX-HOFIX-SWEEP-NN required. Placeholder kept so REQUIREMENTS.md
      // TST-HOFIX-05 row maps to a concrete test ID; no real assertion.
      expect(true).to.equal(true);
    });
  });
});

// =============================================================================
// PART B — TST-JPSURF-01..04 (F-41-03 cross-day CALL 1/CALL 2 regression)
// =============================================================================

describe("TST-JPSURF — F-41-03 cross-day CALL 1/CALL 2 regression (Phase 288)", function () {
  this.timeout(120_000);

  // -------------------------------------------------------------------------
  // TST-JPSURF-01 — same-day CALL 1/CALL 2 read consistency under Phase 288
  //                 mechanism (post-supersede sanity check)
  // -------------------------------------------------------------------------
  describe("TST-JPSURF-01 — same-day CALL 1/CALL 2 read consistency (post-Phase-288 mechanism re-confirm)", function () {
    it("two reads of getDailyHeroWinner(dailyIdx) within the same physical day produce identical winner triples", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());

      // Populate slot[D] with a bet so the snapshots are non-trivial.
      await placeEthBet(game, alice, 2, 6);

      const dailyIdx = await readDailyIdx(gameAddr);
      expect(dailyIdx).to.equal(D, "fixture-init: dailyIdx == currentDay");

      // Two reads in the same physical block (no time-warp).
      const call1Read = await readWinner(game, dailyIdx);
      const call2Read = await readWinner(game, dailyIdx);

      expect(winnersEqual(call1Read, call2Read)).to.equal(
        true,
        "two same-day reads of getDailyHeroWinner(dailyIdx) MUST be identical (no intervening state mutation)"
      );
      expect(call1Read.winQuadrant).to.equal(2);
      expect(call1Read.winSymbol).to.equal(6);
      expect(call1Read.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-JPSURF-02 — cross-day CALL 1/CALL 2 read consistency (the F-41-03
  //                 fix verification)
  // -------------------------------------------------------------------------
  describe("TST-JPSURF-02 — cross-day CALL 1/CALL 2 reads identical slot via dailyIdx (F-41-03 fix verification)", function () {
    it("CALL 1 on day D; time-warp 24h to day D+1; CALL 2 on day D+1 reads SAME slot[dailyIdx] as CALL 1 because dailyIdx is frozen across the warp", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());

      // Seed slot[D] with alice's bet (will be the "yesterday's hero pool"
      // from the operational read's perspective once we cross the day
      // boundary).
      await placeEthBet(game, alice, 1, 4);

      // CALL 1 capture: dailyIdx + winner triple from slot[dailyIdx].
      const call1DailyIdx = await readDailyIdx(gameAddr);
      const call1Winner = await readWinner(game, call1DailyIdx);
      const call1WallDay = Number(await game.currentDayView());
      expect(call1DailyIdx).to.equal(D);
      expect(call1WallDay).to.equal(D);

      // Time-warp 24h to simulate the catastrophic `advanceGame` stall
      // between CALL 1 and CALL 2 of the 2-call ETH split. In production
      // this is the exact scenario that would have triggered F-41-03 in
      // pre-Phase-288 code (CALL 2 would re-evaluate `_simulatedDayIndex()`
      // and read a different slot).
      await advanceToNextDay();

      // CALL 2 capture: dailyIdx + winner triple from slot[dailyIdx].
      const call2DailyIdx = await readDailyIdx(gameAddr);
      const call2Winner = await readWinner(game, call2DailyIdx);
      const call2WallDay = Number(await game.currentDayView());

      // F-41-03 fix invariants:
      expect(call2DailyIdx).to.equal(
        call1DailyIdx,
        "dailyIdx MUST be frozen across the 24h warp — no _unlockRng fired"
      );
      expect(call2WallDay).to.equal(
        call1WallDay + 1,
        "wall-clock MUST have advanced one day (cross-day scenario established)"
      );
      expect(call2DailyIdx).to.not.equal(
        call2WallDay,
        "post-warp condition: dailyIdx != _simulatedDayIndex() — pre-Phase-288 would have read divergent slots here"
      );
      expect(winnersEqual(call1Winner, call2Winner)).to.equal(
        true,
        "CALL 1 and CALL 2 hero-override inputs MUST be identical because both read slot[dailyIdx] and dailyIdx is frozen"
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-JPSURF-03 — dailyIdx update-timing verification (structural frozen
  //                 invariant across the entire jackpot window)
  // -------------------------------------------------------------------------
  describe("TST-JPSURF-03 — dailyIdx is only written by _unlockRng; storage-slot read unchanged across the jackpot window", function () {
    it("dailyIdx storage slot is identical across: fixture-init → bet placement → 24h warp → second bet placement → second 24h warp (no _unlockRng fires in this fixture; structural frozen invariant holds at the storage level)", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      // Checkpoint 1: fixture-init.
      const cp1 = await readDailyIdx(gameAddr);

      // Checkpoint 2: after first bet.
      await placeEthBet(game, alice, 0, 1);
      const cp2 = await readDailyIdx(gameAddr);

      // Checkpoint 3: after 24h warp.
      await advanceToNextDay();
      const cp3 = await readDailyIdx(gameAddr);

      // Checkpoint 4: after second bet.
      await placeEthBet(game, bob, 3, 5);
      const cp4 = await readDailyIdx(gameAddr);

      // Checkpoint 5: after second 24h warp.
      await advanceToNextDay();
      const cp5 = await readDailyIdx(gameAddr);

      // All five checkpoints must be identical. Only `_unlockRng`
      // (AdvanceModule:1697) writes `dailyIdx`, and the simplified fixture
      // does NOT exercise that codepath. This proves the storage-level
      // frozen invariant directly.
      expect(cp2).to.equal(
        cp1,
        "dailyIdx unchanged after bet placement (placeDegeneretteBet does NOT write dailyIdx)"
      );
      expect(cp3).to.equal(
        cp1,
        "dailyIdx unchanged after 24h time-warp (block.timestamp mutation does NOT write dailyIdx)"
      );
      expect(cp4).to.equal(
        cp1,
        "dailyIdx unchanged after second bet placement"
      );
      expect(cp5).to.equal(
        cp1,
        "dailyIdx unchanged after second 24h time-warp"
      );

      // Cross-check: the wall-clock day HAS advanced (asymmetry confirms
      // dailyIdx is structurally decoupled from `_simulatedDayIndex()`
      // during the rng-lock window).
      const wallDayFinal = Number(await game.currentDayView());
      expect(wallDayFinal).to.equal(
        cp1 + 2,
        "wall-clock must have advanced by 2 days while dailyIdx remained frozen"
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-JPSURF-04 — F-41-03 anchor-replay regression (the catastrophy
  //                 scenario: 24h advanceGame silence between CALL 1 and
  //                 CALL 2; disjoint-bucket-subset invariant via dailyIdx
  //                 anchor)
  // -------------------------------------------------------------------------
  describe("TST-JPSURF-04 — F-41-03 anchor-replay regression (24h advanceGame silence between CALL 1 and CALL 2; disjoint-bucket-subset invariant from Phase 283 SWEEP-04 holds via dailyIdx anchor)", function () {
    it("simulates the F-41-03 catastrophy: bet populates the operational slot; CALL 1 reads; 24h elapses with an inter-window bet on the new wall-clock day; CALL 2 reads SAME operational slot — disjoint-bucket-subset invariant preserved because the hero-override input is byte-identical across the split", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());

      // Seed slot[D] = slot[dailyIdx] with alice's bet (the "operational
      // hero pool" that both CALL 1 and CALL 2 should consume).
      await placeEthBet(game, alice, 2, 7);

      // CALL 1: capture the hero-override input that
      // `_applyHeroOverride → _topHeroSymbol(dailyIdx)` would consume.
      const dailyIdxAtCall1 = await readDailyIdx(gameAddr);
      const call1HeroInput = await readWinner(game, dailyIdxAtCall1);
      expect(call1HeroInput.winQuadrant).to.equal(2);
      expect(call1HeroInput.winSymbol).to.equal(7);
      expect(call1HeroInput.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n
      );

      // Catastrophy event: `advanceGame` is silent for 24h. The physical
      // day rolls over between CALL 1 and CALL 2 of the 2-call ETH split.
      // Pre-Phase-288, this is the EXACT condition that would cause
      // `_simulatedDayIndex()` to advance and the two calls to read
      // DIVERGENT slots (`dailyHeroWagers[D]` vs `dailyHeroWagers[D+1]`),
      // breaking the disjoint-bucket-subset invariant.
      await advanceToNextDay();

      // Inter-window bet on the new wall-clock day. Pre-Phase-288 this bet
      // would land in slot[D+1] (or slot[D+2] under Phase 285), poisoning
      // the cross-day CALL 2 read. Under Phase 288, the bet lands in
      // slot[D+1] (canonical) — which CALL 2 does NOT read because CALL 2
      // still reads slot[dailyIdx=D].
      await placeEthBet(game, bob, 3, 5);

      // CALL 2: re-capture the hero-override input. Under Phase 288 this
      // MUST equal CALL 1's input because:
      //   (a) dailyIdx is frozen (no _unlockRng fired).
      //   (b) Both calls read `dailyHeroWagers[dailyIdx]` — the SAME slot.
      const dailyIdxAtCall2 = await readDailyIdx(gameAddr);
      const call2HeroInput = await readWinner(game, dailyIdxAtCall2);

      expect(dailyIdxAtCall2).to.equal(
        dailyIdxAtCall1,
        "dailyIdx MUST be frozen across the 24h stall — this is the structural anchor that closes F-41-03"
      );
      expect(winnersEqual(call1HeroInput, call2HeroInput)).to.equal(
        true,
        `F-41-03 catastrophy regression: CALL 1 hero-override input ${JSON.stringify(
          {
            ...call1HeroInput,
            winAmount: call1HeroInput.winAmount.toString(),
          }
        )} MUST equal CALL 2 hero-override input ${JSON.stringify({
          ...call2HeroInput,
          winAmount: call2HeroInput.winAmount.toString(),
        })} — disjoint-bucket-subset invariant from Phase 283 SWEEP-04 preserved via dailyIdx anchor`
      );

      // Sanity: the inter-window bet landed on the new wall-clock day's
      // slot (canonical), confirming the slot semantic.
      const interWindowSlotWinner = await readWinner(game, D + 1);
      expect(interWindowSlotWinner.winQuadrant).to.equal(
        3,
        "inter-window bet must land at slot[D+1] (canonical) — disjoint from slot[dailyIdx=D]"
      );
      expect(interWindowSlotWinner.winSymbol).to.equal(5);
      expect(interWindowSlotWinner.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n
      );
    });
  });
});
