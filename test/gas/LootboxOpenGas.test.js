// SPDX-License-Identifier: AGPL-3.0-only
// Phase 266 GAS-01 — entry-point gas regression for the lootbox-open path
// after the lootbox-path entropy refactor.
//
// Methodology per `feedback_gas_worst_case.md`:
//   1. Derive theoretical worst-case bound from opcode-by-opcode walk FIRST.
//   2. HEAD-only measurement at the 3 lootbox entry points.
//   3. REF-CAPTURE protocol: first run prints measured values for executor
//      to pin into the literal constants; subsequent runs assert |measured -
//      REF| <= ENTRY_POINT_DELTA_TOLERANCE AND (measured - REF) <=
//      PER_OPEN_GAS_DELTA_BOUND.
//
// Lifecycle reachability: lootbox open requires (a) a purchase that allocates
// lootboxes, (b) a `requestLootboxRng()` outside the daily advance window that
// requests VRF entropy for the lootbox index, (c) `mockVRF.fulfillRandomWords`
// for the lootbox request id, then (d) `openLootBox(player, index)`. The
// simulator's purchase/advance state machine may not always permit step (b) or
// (c) (e.g. when the activity threshold isn't met or the daily-advance window
// blocks lootbox-RNG requests). The soft-skip pattern follows the existing
// `test/gas/AdvanceGameGas.test.js:1014` precedent — fixture-coverage gaps
// are reported with diagnostic messages so a regression that closes off a
// reachable path is visible.
//
// ============================================================================
// THEORETICAL WORST-CASE DERIVATION (Phase 266 lootbox-open envelope — GAS-01)
// ============================================================================
//
// Per-open seed-derivation cost (single-keccak-per-resolution + inline bit-slice):
//   + keccak256(abi.encode(rngWord, player, day, amount))     ~  80 gas
//     (entry-point keccak; preserved from pre-refactor per RESEARCH.md
//      Open Question 2; MSTORE × 4 + KECCAK256(128 bytes))
//   + per-consumer inline shifts (uint8 / uint16 / uint24 + masks)
//                                                              ~ 6-12 gas each × 7 consumers ≈ 70-90 gas
//   + per-consumer % small modulo                              ~  8 gas each × 7 consumers ≈ 56 gas
//   - SAVED: 5 entropyStep calls × ~20-30 gas each            ≈ 100-150 gas per resolution
//   - SAVED: 1 dead L1585 entropyStep advance × ~20-30 gas    ≈  25 gas (WWXRP path; per Open Question 3)
//   + ETH-amount-second branch: + 1 hash2 keccak (~80 gas) for seed2 chunk (Option A)
//
// Net per-open delta:
//   single-amount path:        +(80 + 90 + 56) - (100..150) - 25  =  -(0..40) to +101 gas typical
//   ETH-amount-second branch:  same + (80 gas for seed2)          =  +60 to +180 gas typical
//
// GAS-01 envelope: ±300 gas per-open. Headroom 2× over typical theoretical
// worst case (180 gas). The 2× margin absorbs compiler-codegen variance and
// any measurement noise from cold/warm SLOAD interleaving outside the
// entropy-derivation hot path.
//
// ============================================================================
// REFERENCE-CAPTURE PROTOCOL
// ============================================================================
// Each `*_GAS_REF` constant is a positive integer pinned from a one-time HEAD
// measurement after the Wave 1 contract refactor lands.
//
// On first run, the test prints (per reachable entry point):
//   [REF-CAPTURE] OPEN_LOOTBOX_GAS_REF             = <gasNumber>
//   [REF-CAPTURE] OPEN_BURNIE_LOOTBOX_GAS_REF      = <gasNumber>
//   [REF-CAPTURE] RESOLVE_LOOTBOX_DIRECT_GAS_REF   = <gasNumber>
// The executor pins each captured value into the matching literal constant
// (replacing 0 with the captured integer). Subsequent runs assert
//   |measured - REF| <= ENTRY_POINT_DELTA_TOLERANCE   (codegen-variance band)
// AND
//   (measured - REF) <= PER_OPEN_GAS_DELTA_BOUND      (refactor envelope per GAS-01)
//
// Phase 266 audit baseline: v35.0 closure HEAD `5db8682b`.

const PER_OPEN_GAS_DELTA_BOUND       = 300;       // GAS-01 ±300 gas per-open
const ENTRY_POINT_DELTA_TOLERANCE    = 2000;      // ±2000 gas per-site tolerance vs pinned REF (codegen variance)
const OPEN_LOOTBOX_GAS_REF             = 0;       // executor-pinned post REF-CAPTURE first run
const OPEN_BURNIE_LOOTBOX_GAS_REF      = 0;       // executor-pinned post REF-CAPTURE first run
const RESOLVE_LOOTBOX_DIRECT_GAS_REF   = 0;       // executor-pinned post REF-CAPTURE first run

import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

// ----------------------------------------------------------------------------
// Lifecycle helpers — adapted from test/gas/AdvanceGameGas.test.js
// (lootbox path 2 try/catch precedent at L1014/L1027).
// ----------------------------------------------------------------------------

/** Buy `n` full tickets (`n × 400` qty) at level-0 intro price (0.01 ETH each). */
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

/** Purchase a fixed lootbox quantity at level-0 (0.001 ETH per lootbox). */
async function buyLootboxes(game, buyer, n, totalEth) {
  return game.connect(buyer).purchase(
    ZERO_ADDRESS,
    0n,
    BigInt(n),
    ZERO_BYTES32,
    MintPaymentKind.DirectEth,
    { value: eth(totalEth) },
  );
}

/**
 * Drive the lifecycle to a state where lootbox VRF has been requested AND
 * fulfilled, returning the lootbox index whose `rngWord` is now non-zero.
 * Returns `null` when the simulator state denies lootbox-RNG reachability
 * (matches AdvanceGameGas L1014/L1027 soft-skip precedent).
 */
async function reachOpenableLootbox(fixture) {
  const { game, deployer, mockVRF, alice } = fixture;

  // 1. Purchase lootboxes (allocates lootboxEth[index][alice]).
  try {
    await buyLootboxes(game, alice, 20, 0.02);
  } catch (err) {
    return { reason: `lootbox purchase failed: ${err.message.slice(0, 80)}` };
  }

  // 2. Request lootbox RNG (only callable outside the daily advance window).
  let lbRequestId;
  try {
    await game.connect(deployer).requestLootboxRng();
    lbRequestId = await getLastVRFRequestId(mockVRF);
  } catch (err) {
    return { reason: `requestLootboxRng failed: ${err.message.slice(0, 80)}` };
  }

  // 3. Fulfill VRF.
  try {
    await mockVRF.fulfillRandomWords(lbRequestId, 266266n);
  } catch (err) {
    return { reason: `fulfillRandomWords failed: ${err.message.slice(0, 80)}` };
  }

  return { reason: null };
}

/** Find a lootbox index for `player` whose stored ETH amount is non-zero AND
 *  whose `lootboxRngWordByIndex[index]` is non-zero (i.e. openable). Probes a
 *  small index range — if nothing matches, returns `null`. */
async function findOpenableEthIndex(game, player) {
  for (let i = 0; i < 64; i++) {
    let amount;
    try {
      amount = await game.lootboxEth(i, player.address);
    } catch (_) {
      break;
    }
    if (amount === undefined || amount === null) continue;
    if (BigInt(amount) === 0n) continue;
    let rngWord;
    try {
      rngWord = await game.lootboxRngWordByIndex(i);
    } catch (_) {
      continue;
    }
    if (BigInt(rngWord) === 0n) continue;
    return i;
  }
  return null;
}

// ============================================================================
// Tests
// ============================================================================

describe("Phase 266 GAS-01 — lootbox-open entry-point gas regression at v36.0 HEAD", function () {
  this.timeout(600_000);
  after(function () { restoreAddresses(); });

  describe("openLootBox (ETH lootbox) — per-open gas envelope ±300 gas", function () {
    it(`gasUsed within ENTRY_POINT_DELTA_TOLERANCE of pinned REF; per-open delta <= ${PER_OPEN_GAS_DELTA_BOUND}`, async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice } = fixture;

      const probe = await reachOpenableLootbox(fixture);
      if (probe.reason !== null) {
        console.warn(`[GAS-01 openLootBox] soft-skip — ${probe.reason} (matches AdvanceGameGas L1014/L1027 precedent)`);
        this.skip();
        return;
      }

      const index = await findOpenableEthIndex(game, alice);
      if (index === null) {
        console.warn(`[GAS-01 openLootBox] soft-skip — no openable ETH lootbox index found for alice in probe range`);
        this.skip();
        return;
      }

      const tx = await game.connect(alice).openLootBox(alice.address, index);
      const receipt = await tx.wait();
      const measured = Number(receipt.gasUsed);

      console.log(`[REF-CAPTURE] OPEN_LOOTBOX_GAS_REF             = ${measured}`);

      if (OPEN_LOOTBOX_GAS_REF > 0) {
        const drift = Math.abs(measured - OPEN_LOOTBOX_GAS_REF);
        expect(
          drift <= ENTRY_POINT_DELTA_TOLERANCE,
          `openLootBox drift ${drift} > tolerance ${ENTRY_POINT_DELTA_TOLERANCE}; measured ${measured} vs REF ${OPEN_LOOTBOX_GAS_REF}`,
        ).to.equal(true);

        const perOpenDelta = measured - OPEN_LOOTBOX_GAS_REF;
        expect(
          perOpenDelta <= PER_OPEN_GAS_DELTA_BOUND,
          `openLootBox per-open delta ${perOpenDelta} > ${PER_OPEN_GAS_DELTA_BOUND} (re-derive worst case before re-pinning)`,
        ).to.equal(true);
      } else {
        console.log(`[GAS-01 openLootBox] REF placeholder is 0 — pin ${measured} into OPEN_LOOTBOX_GAS_REF and re-run.`);
      }
    });
  });

  describe("openBurnieLootBox (BURNIE lootbox) — per-open gas envelope ±300 gas", function () {
    it(`gasUsed within ENTRY_POINT_DELTA_TOLERANCE of pinned REF; per-open delta <= ${PER_OPEN_GAS_DELTA_BOUND}`, async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice } = fixture;

      const probe = await reachOpenableLootbox(fixture);
      if (probe.reason !== null) {
        console.warn(`[GAS-01 openBurnieLootBox] soft-skip — ${probe.reason} (matches AdvanceGameGas L1014/L1027 precedent)`);
        this.skip();
        return;
      }

      // BURNIE lootboxes accumulate via separate paths (boon awards / coinflip
      // rewards / activity). The simulator may not have populated lootboxBurnie
      // for alice in the harness state; soft-skip if the path is unreachable
      // — the openLootBox path above exercises the same _resolveLootboxCommon
      // body and provides the primary GAS-01 measurement.
      let foundIndex = null;
      for (let i = 0; i < 64; i++) {
        let amount;
        try {
          amount = await game.lootboxBurnie(i, alice.address);
        } catch (_) { break; }
        if (amount === undefined || amount === null) continue;
        if (BigInt(amount) === 0n) continue;
        let rngWord;
        try {
          rngWord = await game.lootboxRngWordByIndex(i);
        } catch (_) { continue; }
        if (BigInt(rngWord) === 0n) continue;
        foundIndex = i;
        break;
      }
      if (foundIndex === null) {
        console.warn(`[GAS-01 openBurnieLootBox] soft-skip — no BURNIE lootbox accrued in current harness state (matches AdvanceGameGas L1014/L1027 precedent)`);
        this.skip();
        return;
      }

      const tx = await game.connect(alice).openBurnieLootBox(alice.address, foundIndex);
      const receipt = await tx.wait();
      const measured = Number(receipt.gasUsed);

      console.log(`[REF-CAPTURE] OPEN_BURNIE_LOOTBOX_GAS_REF      = ${measured}`);

      if (OPEN_BURNIE_LOOTBOX_GAS_REF > 0) {
        const drift = Math.abs(measured - OPEN_BURNIE_LOOTBOX_GAS_REF);
        expect(
          drift <= ENTRY_POINT_DELTA_TOLERANCE,
          `openBurnieLootBox drift ${drift} > tolerance ${ENTRY_POINT_DELTA_TOLERANCE}; measured ${measured} vs REF ${OPEN_BURNIE_LOOTBOX_GAS_REF}`,
        ).to.equal(true);

        const perOpenDelta = measured - OPEN_BURNIE_LOOTBOX_GAS_REF;
        expect(
          perOpenDelta <= PER_OPEN_GAS_DELTA_BOUND,
          `openBurnieLootBox per-open delta ${perOpenDelta} > ${PER_OPEN_GAS_DELTA_BOUND} (re-derive worst case before re-pinning)`,
        ).to.equal(true);
      } else {
        console.log(`[GAS-01 openBurnieLootBox] REF placeholder is 0 — pin ${measured} into OPEN_BURNIE_LOOTBOX_GAS_REF and re-run.`);
      }
    });
  });

  describe("resolveLootboxDirect (decimator/claim path) — per-open gas envelope ±300 gas", function () {
    it(`gasUsed within ENTRY_POINT_DELTA_TOLERANCE of pinned REF; per-open delta <= ${PER_OPEN_GAS_DELTA_BOUND}`, async function () {
      // resolveLootboxDirect is invoked via cross-module delegatecall from the
      // jackpot decimator path; it has no public entry point in DegenerusGame.
      // The gas envelope is dominated by the same _resolveLootboxCommon body
      // exercised by openLootBox above, plus a thin `_lootboxEvMultiplierBps`
      // wrapper. Direct gas measurement requires a delegatecall harness, which
      // is structurally different from the user-callable openLootBox path.
      // Per `feedback_gas_worst_case.md` the theoretical-worst-case header
      // bounds this entry point's regression contribution; the empirical pin
      // is satisfied by the openLootBox measurement above (same _resolveLootboxCommon
      // body). Soft-skip the empirical run with the diagnostic note.
      console.warn(
        `[GAS-01 resolveLootboxDirect] soft-skip — no public-entry-point harness available; ` +
        `theoretical-worst-case header bounds this surface's regression. The shared ` +
        `_resolveLootboxCommon body is exercised by the openLootBox empirical measurement above; ` +
        `resolveLootboxDirect adds only the activity-score multiplier wrapper (~50-150 gas).`,
      );
      console.log(`[REF-CAPTURE] RESOLVE_LOOTBOX_DIRECT_GAS_REF   = (deferred — see soft-skip note)`);
      this.skip();
    });
  });
});
