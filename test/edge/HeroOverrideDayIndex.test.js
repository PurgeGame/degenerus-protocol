// SPDX-License-Identifier: AGPL-3.0-only
//
// HeroOverrideDayIndex.test.js — Phase 286 TST-HOFIX hero-override
// day-index regression fixture (v41.0 Cross-Call Determinism Fix milestone).
//
// Tests the post-Phase-285 D-285-FIX-SHAPE-01 (Approach B write-side `+1`
// offset at DegenerusGameDegeneretteModule:486) invariants:
//
//   - Slot dailyHeroWagers[D] represents "bets feeding day D's jackpot" (=
//     bets placed on day D-1 when the write site was active that day).
//   - Read at JackpotModule:1595 via _topHeroSymbol(_simulatedDayIndex())
//     returns a stable result for a given day, even under arbitrary
//     interleaved placeDegeneretteBet calls on that same day (those bets
//     write to slot[currentDay + 1], not slot[currentDay]).
//
// Assertion vehicle: the public view getDailyHeroWinner(day) at
// DegenerusGame.sol:2551 runs the same algorithm as the internal
// _topHeroSymbol(day) at JackpotModule:1618-1646 consumed by
// _applyHeroOverride at JackpotModule:1593-1597. Asserting against the view
// is algorithm-equivalent to asserting against what payDailyJackpot's
// CALL 1 + CALL 2 would consume.
//
// Evidence class: ALGORITHM_VERIFIED (per D-285-EVIDENCE-CLASS-01). Lighter
// test infra than Phase 282 — no git-worktree at pre-Phase-285 HEAD; no
// captured pre-fix witness JSON; assertions are post-fix-invariant form
// only ("bets on day D do NOT affect day D's jackpot"), not pre-fix-bug
// witness form.
//
// Test target: post-Phase-285 HEAD c4d62564.

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
// storageLayout) — slot index 37 at offset 0, type uint256. The low 48 bits
// are `lootboxRngIndex` (LR_INDEX_SHIFT=0, LR_INDEX_MASK=0xFFFFFFFFFFFF).
const LOOTBOX_RNG_PACKED_SLOT = "0x" + (37).toString(16).padStart(64, "0");

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

describe("HeroOverrideDayIndex (TST-HOFIX) — Phase 285 D-285-FIX-SHAPE-01 regression", function () {
  this.timeout(120_000);

  after(() => restoreAddresses());

  // -------------------------------------------------------------------------
  // TST-HOFIX-01 — bets on day D do NOT affect day D's jackpot
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-01 — bets on day D do NOT affect day D's jackpot", function () {
    it("places bet on day D before jackpot fires; getDailyHeroWinner(D) reflects empty slot[D] (write went to slot[D+1])", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());

      // Pre-bet: slot[D] is empty.
      const preWinner = await readWinner(game, D);
      expect(preWinner.winAmount).to.equal(
        0n,
        `slot[D=${D}] must be empty at fixture start`
      );

      // Place one ETH bet on day D (quadrant=2, symbol=5).
      await placeEthBet(game, alice, 2, 5);

      // Post-bet on day D: getDailyHeroWinner(D) must still reflect empty
      // slot[D]. The write landed in slot[D+1].
      const postWinner = await readWinner(game, D);
      expect(postWinner.winAmount).to.equal(
        0n,
        `slot[D=${D}] must remain empty — bet on day D writes to slot[D+1] under D-285-FIX-SHAPE-01`
      );

      // Cross-check: raw wager view at slot[D] for (q=2, s=5) is zero;
      // slot[D+1] reflects the MIN_BET_ETH wager scaled to 1e12 units.
      const wagerAtD = BigInt(await game.getDailyHeroWager(D, 2, 5));
      const wagerAtDplus1 = BigInt(await game.getDailyHeroWager(D + 1, 2, 5));
      expect(wagerAtD).to.equal(
        0n,
        `getDailyHeroWager(D=${D}, q=2, s=5) must be zero`
      );
      expect(wagerAtDplus1).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n,
        `getDailyHeroWager(D+1=${D + 1}, q=2, s=5) must equal MIN_BET_ETH / 1e12`
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-HOFIX-02 — bets on day D DO affect day D+1's jackpot
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-02 — bets on day D DO affect day D+1's jackpot", function () {
    it("places bet on day D; advances to day D+1; getDailyHeroWinner(D+1) returns the (Q, S) bet from day D", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());
      const Q = 1;
      const S = 3;

      await placeEthBet(game, alice, Q, S);

      // Advance to day D+1 — the day this bet was placed to influence.
      await advanceToNextDay();
      const DnextRaw = Number(await game.currentDayView());
      expect(DnextRaw).to.equal(
        D + 1,
        `currentDayView must advance from D=${D} to D+1=${D + 1}`
      );

      const winner = await readWinner(game, D + 1);
      expect(winner.winQuadrant).to.equal(
        Q,
        `getDailyHeroWinner(D+1) winQuadrant must equal placed-bet quadrant ${Q}`
      );
      expect(winner.winSymbol).to.equal(
        S,
        `getDailyHeroWinner(D+1) winSymbol must equal placed-bet symbol ${S}`
      );
      expect(winner.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n,
        `getDailyHeroWinner(D+1) winAmount must equal MIN_BET_ETH/1e12 wager units`
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-HOFIX-03 — 2-call ETH split read consistency under inter-call bet
  //                interleaving (D-282-B2-COVERAGE-01 symmetric pair)
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-03 — 2-call ETH split read consistency under inter-call bet interleaving", function () {
    it("snapshot1 (pre-bet) === snapshot2 (post-bet) for getDailyHeroWinner(D) — CALL 1 and CALL 2 of payDailyJackpot consume identical algorithm output", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());

      // Seed slot[D] from a prior-day bet so the snapshot is non-trivial.
      // Step 1: place alice's bet on day D-1 (i.e., this current day before
      // we advance); since fixture starts at day D, we simulate "previous
      // day wrote to slot[D]" by placing on day D and advancing once.
      await placeEthBet(game, alice, 0, 4);
      await advanceToNextDay();
      const Dnow = Number(await game.currentDayView());
      expect(Dnow).to.equal(D + 1);

      // Snapshot1: what CALL 1 of payDailyJackpot on day Dnow would consume.
      const snapshot1 = await readWinner(game, Dnow);
      expect(snapshot1.winAmount).to.be.greaterThan(
        0n,
        `slot[Dnow=${Dnow}] must be seeded by alice's day-${Dnow - 1} bet`
      );

      // Inter-call interleaving: bob places a bet on day Dnow. Post-fix,
      // this writes to slot[Dnow + 1] — NOT slot[Dnow] which CALL 2 of the
      // jackpot would re-read.
      await placeEthBet(game, bob, 3, 7);

      // Snapshot2: what CALL 2 of payDailyJackpot on day Dnow would consume
      // after the interleaved bet.
      const snapshot2 = await readWinner(game, Dnow);

      expect(winnersEqual(snapshot1, snapshot2)).to.equal(
        true,
        `CALL 1 snapshot ${JSON.stringify({
          ...snapshot1,
          winAmount: snapshot1.winAmount.toString(),
        })} must equal CALL 2 snapshot ${JSON.stringify({
          ...snapshot2,
          winAmount: snapshot2.winAmount.toString(),
        })} — inter-call bet must not mutate the day-Dnow read slot`
      );

      // Sanity: bob's bet landed at slot[Dnow + 1].
      const nextDayWinner = await readWinner(game, Dnow + 1);
      expect(nextDayWinner.winQuadrant).to.equal(
        3,
        "bob's interleaved bet must land at slot[Dnow+1] under D-285-FIX-SHAPE-01"
      );
      expect(nextDayWinner.winSymbol).to.equal(7);
      expect(nextDayWinner.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n
      );
    });
  });

  // -------------------------------------------------------------------------
  // TST-HOFIX-04 — F-41-02 algorithm-level invariant under arbitrary
  //                interleaving (Phase 284 Hypothesis (ix) closure regression)
  // -------------------------------------------------------------------------
  describe("TST-HOFIX-04 — F-41-02 algorithm-level invariant: multiple _topHeroSymbol invocations during a single jackpot day return identical value under arbitrary interleaved bet placement", function () {
    it("captures getDailyHeroWinner(D+1) → interleaves bet on day D+1 (writes to slot[D+2]) → re-captures getDailyHeroWinner(D+1); both captures identical", async function () {
      const { game, alice, carol } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await seedLootboxRngIndex(gameAddr, 1);

      const D = Number(await game.currentDayView());

      // alice bets on day D for the (Q1=0, S1=3) slot → lands in
      // slot[D+1].
      const Q1 = 0;
      const S1 = 3;
      await placeEthBet(game, alice, Q1, S1);

      // Advance to day D+1 — the day this bet feeds.
      await advanceToNextDay();
      expect(Number(await game.currentDayView())).to.equal(D + 1);

      // Capture 1: what _topHeroSymbol(D+1) returns at start of day D+1.
      const capture1 = await readWinner(game, D + 1);
      expect(capture1.winQuadrant).to.equal(Q1);
      expect(capture1.winSymbol).to.equal(S1);
      expect(capture1.winAmount).to.equal(
        MIN_BET_ETH_VALUE / 1_000_000_000_000n
      );

      // Interleave: carol places bet on day D+1 with a competing
      // (Q2=1, S2=5). Post-fix, this writes to slot[D+2] — NOT slot[D+1].
      const Q2 = 1;
      const S2 = 5;
      await placeEthBet(game, carol, Q2, S2);

      // Capture 2: re-read _topHeroSymbol(D+1) after the interleaved bet.
      const capture2 = await readWinner(game, D + 1);

      expect(winnersEqual(capture1, capture2)).to.equal(
        true,
        `_topHeroSymbol(D+1) must return identical value across re-invocations under arbitrary day-D+1 bet interleaving`
      );

      // Sanity: carol's bet landed at slot[D+2].
      const dPlus2Winner = await readWinner(game, D + 2);
      expect(dPlus2Winner.winQuadrant).to.equal(
        Q2,
        "carol's day-D+1 bet must land at slot[D+2]"
      );
      expect(dPlus2Winner.winSymbol).to.equal(S2);
      expect(dPlus2Winner.winAmount).to.equal(
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
      // covered by FIX-HOFIX-01); 0 FIX-HOFIX-SWEEP-NN required.
      // Placeholder kept so REQUIREMENTS.md TST-HOFIX-05 row maps to a
      // concrete test ID; no real assertion.
      expect(true).to.equal(true);
    });
  });
});
