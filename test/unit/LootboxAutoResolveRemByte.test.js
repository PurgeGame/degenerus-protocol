// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxAutoResolveRemByte.test.js — Phase 275 Wave 2 TST-LBX-AR-05
//
// `_rollRemainder` zero-invocation regression on auto-resolve queues.
//
// The pre-Phase-275 auto-resolve branch routed `futureTickets` (scaled) into
// `_queueTicketsScaled(...)` at `DegenerusGameStorage.sol:596`, which packs a
// fractional remainder into the `rem` byte of `ticketsOwedPacked[wk][buyer]`.
// At trait-assignment time `_rollRemainder` reads + promotes that rem byte to
// a whole ticket via a Bernoulli round-up.
//
// Phase 275 LBX-AR-02 swaps the auto-resolve callsite to
// `_queueTickets(player, targetLevel, wholeTicketsToEntries(whole), false)` at
// `DegenerusGameStorage.sol:562` — the whole-helper. Per D-275-TST-05-01, the
// invariant is: the `_queueTickets` body writes ONLY the whole-ticket count
// into `ticketsOwedPacked` and NEVER touches the rem byte. After Plan A:
//   - rem byte stays 0 across the open → activate flow on auto-resolve queues.
//   - `_rollRemainder` is never invoked for auto-resolve queues (it can only
//     run when rem != 0, by the implementation in DegenerusGameStorage.sol).
//
// TEST STRATEGY:
//   No deterministic fixture exists for `resolveLootboxDirect` /
//   `resolveRedemptionLootbox` at the full-state granularity required (level
//   + day + sDGNRS staking + VRF mock). Per the LBX-02 fixture-coverage-gap
//   precedent, this test combines:
//     (a) Source-level structural proof that `_queueTickets` body writes the
//         packed slot with `rem` carried from the existing slot value
//         unchanged (no fractional accumulation).
//     (b) Source-level proof that `_queueTicketsScaled` body DOES write a
//         non-zero rem byte (positive control — proves the rem-byte mechanism
//         exists and is gated behind the scaled helper that Plan A NO LONGER
//         calls on the auto-resolve path).
//     (c) Source-level proof that the LootboxModule auto-resolve branch
//         calls `_queueTickets` (whole) and NOT `_queueTicketsScaled`.
//
// CROSS-CITES:
//   - D-275-TST-05-01 (rem-byte snapshot approach via ticketsOwedPacked direct read)
//   - D-275-HOIST-01 (Bernoulli math hoisted to shared scope)
//   - LBX-AR-06 (`_rollRemainder` zero-invocation on auto-resolve queues)

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);
const STORAGE_PATH = path.resolve(
  process.cwd(),
  "contracts/storage/DegenerusGameStorage.sol"
);

// Brace-match function-body extractor.
function extractBody(source, signature) {
  const fnIdx = source.indexOf(signature);
  if (fnIdx < 0) return null;
  let depth = 0;
  let bodyStart = -1;
  let bodyEnd = -1;
  for (let i = fnIdx; i < source.length; i++) {
    if (source[i] === "{") {
      if (depth === 0) bodyStart = i;
      depth++;
    } else if (source[i] === "}") {
      depth--;
      if (depth === 0) {
        bodyEnd = i;
        break;
      }
    }
  }
  if (bodyStart < 0 || bodyEnd < 0) return null;
  return source.slice(bodyStart, bodyEnd + 1);
}

describe("LootboxAutoResolveRemByte — Phase 275 Wave 2 TST-LBX-AR-05", function () {
  this.timeout(30_000);

  describe("`_queueTickets` body proof: writes ONLY whole tickets — rem byte carried unchanged from existing slot value (LBX-AR-06)", function () {
    it("[01a] `_queueTickets` body in `ticketsOwedPacked` write packs `(uint40(owed) << 8) | uint40(rem)` where `rem = uint8(packed)` from the PRE-existing slot value (no fractional accumulation)", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const body = extractBody(storage, "function _queueTickets(");
      expect(body, "`_queueTickets` body not found").to.not.equal(null);

      // The write site MUST pack `rem` from the existing slot, never from a
      // newly-computed fractional value. The pattern is:
      //   ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) | uint40(rem);
      expect(
        /ticketsOwedPacked\[wk\]\[buyer\]\s*=\s*\(uint40\(owed\)\s*<<\s*8\)\s*\|\s*uint40\(rem\)/.test(body),
        "_queueTickets must pack `(uint40(owed) << 8) | uint40(rem)` with rem carried from existing slot"
      ).to.equal(true);

      // No fractional/remainder arithmetic appears in the body — specifically,
      // no `% TICKET_SCALE` modulo, no `frac` variable, no `newRem` variable.
      expect(body.includes("% TICKET_SCALE"), "_queueTickets must not compute fractional remainder").to.equal(false);
      expect(/\bfrac\b/.test(body), "_queueTickets must not have a `frac` local").to.equal(false);
      expect(/\bnewRem\b/.test(body), "_queueTickets must not have a `newRem` local").to.equal(false);

      // _rollRemainder is NOT invoked from _queueTickets (whole-only helper).
      expect(body.includes("_rollRemainder"), "_queueTickets must NOT invoke _rollRemainder").to.equal(false);

      // Emission: TicketsQueued (whole-helper), not TicketsQueuedScaled.
      expect(body.includes("emit TicketsQueued("), "_queueTickets must emit TicketsQueued").to.equal(true);
      expect(body.includes("emit TicketsQueuedScaled("), "_queueTickets must NOT emit TicketsQueuedScaled").to.equal(false);
    });

    it("[01b] positive control: `_queueTicketsScaled` body DOES write a non-zero rem byte when frac != 0", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const body = extractBody(storage, "function _queueTicketsScaled(");
      expect(body, "`_queueTicketsScaled` body not found").to.not.equal(null);

      // The scaled helper computes `uint8 frac = uint8(uint256(quantityScaled) % TICKET_SCALE)`
      // and folds it into `newRem` before packing into `ticketsOwedPacked`.
      expect(body.includes("% TICKET_SCALE"), "_queueTicketsScaled must compute frac via % TICKET_SCALE").to.equal(true);
      expect(/\bfrac\b/.test(body), "_queueTicketsScaled must have a `frac` local").to.equal(true);
      expect(/\bnewRem\b/.test(body), "_queueTicketsScaled must have a `newRem` local").to.equal(true);
      // Emission contract: TicketsQueuedScaled (scaled helper).
      expect(body.includes("emit TicketsQueuedScaled("), "_queueTicketsScaled must emit TicketsQueuedScaled").to.equal(true);
    });
  });

  describe("LootboxModule auto-resolve branch calls `_queueTickets` (whole) — not `_queueTicketsScaled` (LBX-AR-02)", function () {
    it("[02a] LootboxModule contains `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` at one source site and ZERO occurrences of `_queueTicketsScaled`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Pre-refactor the manual true-branch and auto-resolve else-arm each had
      // their own `_queueTickets(player, targetLevel, wholeTicketsToEntries(whole), false)` call (the
      // "exactly twice" structure). The refactor unifies both paths into a
      // single per-roll `_settleLootboxRoll` helper, so the whole-ticket queue
      // is now ONE source site (invoked once per roll at runtime — a split box
      // runs the helper twice). The load-bearing invariant survives: the lootbox
      // path queues WHOLE tickets via `_queueTickets`, never `_queueTicketsScaled`.
      const callPattern = /_queueTickets\(player, rollLevel, wholeTicketsToEntries\(whole\), false\)/g;
      const calls = (source.match(callPattern) || []).length;
      expect(calls, "expected exactly one `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` source site (unified per-roll settle path)").to.equal(1);
      expect(
        source.includes("_queueTicketsScaled"),
        "`_queueTicketsScaled` must not appear in DegenerusGameLootboxModule.sol"
      ).to.equal(false);
    });

    it("[02b] the single whole-ticket queue site lives inside `_settleLootboxRoll` (the unified per-roll helper that replaced the manual/auto branch arms)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The pre-refactor manual-first / auto-second branch-ordering invariant is
      // retired: there are no longer two arms. The equivalent structural anchor
      // is that the sole whole-ticket queue call sits inside `_settleLootboxRoll`,
      // which both the manual (payColdBustConsolation = true) and auto-resolve
      // (payColdBustConsolation = false) paths invoke via `_resolveLootboxCommon`.
      const settleBody = extractBody(source, "function _settleLootboxRoll(");
      expect(settleBody, "`_settleLootboxRoll` body not found").to.not.equal(null);
      expect(
        settleBody.includes("_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)"),
        "the whole-ticket queue call must live inside `_settleLootboxRoll`"
      ).to.equal(true);
      // The queue site appears nowhere else in the module.
      const totalCalls = (source.match(/_queueTickets\(player, rollLevel, wholeTicketsToEntries\(whole\), false\)/g) || []).length;
      expect(totalCalls, "the whole-ticket queue call must be single-site").to.equal(1);
    });
  });

  describe("`_rollRemainder` invocation surface — auto-resolve paths cannot reach it because `_queueTickets` never writes the rem byte", function () {
    it("[03a] `_rollRemainder` lives in DegenerusGameMintModule.sol and is invoked ONLY by code paths that read a non-zero `rem` byte from `ticketsOwedPacked` (analytical anchor — empirical confirmation in TST-LBX-AR-06 mint-boost regression)", function () {
      const MINT_MODULE_PATH = path.resolve(
        process.cwd(),
        "contracts/modules/DegenerusGameMintModule.sol"
      );
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      // _rollRemainder exists as an internal helper (positive existence check;
      // mint-boost paths still consume it per D-40N-MINTBOOST-OUT-01).
      expect(
        mint.includes("function _rollRemainder("),
        "_rollRemainder helper must still exist in MintModule (consumed by mint-boost activation path)"
      ).to.equal(true);
      // _rollRemainder is NOT defined in DegenerusGameLootboxModule.sol nor
      // DegenerusGameStorage.sol — it's a MintModule-local helper invoked
      // only from MintModule code paths (mint-boost activation).
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const lootbox = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      expect(storage.includes("function _rollRemainder(")).to.equal(false);
      expect(lootbox.includes("function _rollRemainder(")).to.equal(false);
      expect(lootbox.includes("_rollRemainder("), "LootboxModule must not invoke _rollRemainder").to.equal(false);
    });

    it("[03b] `ticketsOwedPacked` rem byte (uint8) layout: low 8 bits of the packed uint40, whole-count occupies bits [8..39]", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      // The packing pattern `(uint40(owed) << 8) | uint40(rem)` confirms the
      // layout: low 8 bits = rem, high 32 bits = owed (whole count). This is
      // the structural anchor for the rem-byte snapshot strategy.
      expect(
        /\(uint40\(owed\)\s*<<\s*8\)\s*\|\s*uint40\(rem\)/.test(storage),
        "ticketsOwedPacked layout pattern not found in storage"
      ).to.equal(true);
    });
  });
});
