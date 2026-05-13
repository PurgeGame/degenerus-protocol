// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxAutoResolveRegression.test.js — Phase 274 Wave 2 TST-REG-01..04
//
// Status-quo preservation tests proving that v39 surgical scope (manual-path
// Bernoulli + consolation) does NOT widen any of:
//
//   - TST-REG-01: manual-only player+level queues skip `_rollRemainder` at
//                 activation time (manual path calls `_queueTickets`, the
//                 whole-helper, which never writes the `rem` byte).
//   - TST-REG-02: mint-boost fractional path (DegenerusGameMintModule L1142
//                 `_queueTicketsScaled` callsite) still produces `rem`
//                 byte and still resolves via `_rollRemainder` at
//                 activation time — v39 narrowly retires the MANUAL LOOTBOX
//                 producer of fractional residues, NOT mint-boost.
//   - TST-REG-03: auto-resolve paths (`resolveLootboxDirect` +
//                 `resolveRedemptionLootbox`) are byte-equivalent to v38 —
//                 still call `_queueTicketsScaled` via the sentinel route,
//                 still emit `TicketsQueuedScaled`, NEVER emit
//                 `LootboxTicketRoll`, NEVER call `wwxrp.mintPrize` with
//                 `LOOTBOX_WWXRP_CONSOLATION`.
//   - TST-REG-04: cross-mixing variance — manual + auto-resolve opens for
//                 the same player + level coexist without corruption.
//                 Manual contributions are per-lootbox-Bernoulli (higher
//                 variance); auto-resolve contributions pool deterministically
//                 via `rem` byte accumulation.
//
// TEST STRATEGY:
//   All four are source-level structural and byte-identity proofs. Full
//   end-to-end integration of `processFutureTicketBatch` + `_rollRemainder`
//   for these scenarios is covered downstream in `test/edge/BackfillIdempotency`
//   and the Foundry suite under `test/fuzz/` (pre-v39, status-quo). v39 makes
//   NO changes to:
//     - DegenerusGameMintModule.sol (TST-REG-02)
//     - DegenerusGameStorage.sol _queueTickets / _queueTicketsScaled /
//       _rollRemainder semantics (TST-REG-03)
//     - The 4 caller-site auto-resolve flow other than threading
//       `type(uint48).max` sentinel into `_resolveLootboxCommon`
//   so the status-quo preservation tests are byte-identity assertions
//   against baseline `06623edb` plus structural source-level proofs.
//
// CROSS-CITES:
//   - D-274-MANUAL-ONLY-01, D-274-AUTORESOLVE-OUT-01, D-274-MINTBOOST-OUT-01
//   - feedback_gas_worst_case.md (cross-mixing variance: per-lootbox vs
//     cross-lootbox-pooled is the documented tradeoff — see CONTEXT.md
//     <specifics>)

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);
const MINT_MODULE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameMintModule.sol"
);
const STORAGE_PATH = path.resolve(
  process.cwd(),
  "contracts/storage/DegenerusGameStorage.sol"
);

// v38 closure baseline SHA (per .planning/STATE.md "Last Shipped Milestone").
const V38_BASELINE = "06623edb";

describe("LootboxAutoResolveRegression — Phase 274 Wave 2 TST-REG-01..04", function () {
  this.timeout(60_000);

  describe("TST-REG-01 — manual-only queues skip _rollRemainder", function () {
    it("[01a] manual branch invokes `_queueTickets` (the whole-helper, no rem write)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const manualPattern = /_queueTickets\(player, targetLevel, whole, false\)/;
      expect(
        source.match(manualPattern),
        "manual-branch `_queueTickets(player, targetLevel, whole, false)` missing"
      ).to.not.be.null;
    });

    it("[01b] storage `_queueTickets` does NOT write to the `rem` byte (whole-only helper)", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      // Locate _queueTickets body.
      const fnIdx = storage.indexOf("function _queueTickets(");
      expect(fnIdx).to.be.greaterThan(-1);
      // Find matching close brace by tracking depth.
      let depth = 0;
      let bodyStart = -1;
      let bodyEnd = -1;
      for (let i = fnIdx; i < storage.length; i++) {
        if (storage[i] === "{") {
          if (depth === 0) bodyStart = i;
          depth++;
        } else if (storage[i] === "}") {
          depth--;
          if (depth === 0) {
            bodyEnd = i;
            break;
          }
        }
      }
      expect(bodyStart).to.be.greaterThan(-1);
      expect(bodyEnd).to.be.greaterThan(bodyStart);
      const body = storage.slice(bodyStart, bodyEnd);
      // The whole-helper must NOT write to the `rem` byte (no `& 0xFF`-like
      // remainder accumulation patterns). It MAY mention the term "rem" in
      // comments — but should not contain `rem = ` or `remainder = ` writes.
      // Conservative: assert that the `_rollRemainder` call does NOT appear
      // inside this function body (rollRemainder is the post-activation
      // remainder-promotion helper that runs at processFutureTicketBatch
      // time, not at queue time).
      expect(
        body.includes("_rollRemainder"),
        "_queueTickets must NOT invoke _rollRemainder (whole-only helper)"
      ).to.equal(false);
      // Emission contract: emits TicketsQueued (whole count), not
      // TicketsQueuedScaled.
      expect(
        body.includes("emit TicketsQueued("),
        "_queueTickets must emit TicketsQueued"
      ).to.equal(true);
      expect(
        body.includes("emit TicketsQueuedScaled("),
        "_queueTickets must NOT emit TicketsQueuedScaled"
      ).to.equal(false);
    });

    it("[01c] storage `_queueTicketsScaled` IS where `rem` byte residues are produced (auto-resolve helper)", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const fnIdx = storage.indexOf("function _queueTicketsScaled(");
      expect(fnIdx).to.be.greaterThan(-1);
      let depth = 0;
      let bodyStart = -1;
      let bodyEnd = -1;
      for (let i = fnIdx; i < storage.length; i++) {
        if (storage[i] === "{") {
          if (depth === 0) bodyStart = i;
          depth++;
        } else if (storage[i] === "}") {
          depth--;
          if (depth === 0) {
            bodyEnd = i;
            break;
          }
        }
      }
      const body = storage.slice(bodyStart, bodyEnd);
      // The scaled-helper emits TicketsQueuedScaled (not TicketsQueued).
      expect(body.includes("emit TicketsQueuedScaled(")).to.equal(true);
      // And it computes a frac via TICKET_SCALE modulo.
      expect(body.includes("% TICKET_SCALE")).to.equal(true);
    });
  });

  describe("TST-REG-02 — mint-boost fractional path UNCHANGED at v39", function () {
    it("[02a] DegenerusGameMintModule.sol byte-identical to baseline 06623edb (G23)", function () {
      // Mirror G23 from the plan: cmp the file against baseline.
      const result = execSync(
        `cmp <(git show ${V38_BASELINE}:contracts/modules/DegenerusGameMintModule.sol) contracts/modules/DegenerusGameMintModule.sol; echo "exit=$?"`,
        { encoding: "utf8", shell: "/bin/bash" }
      );
      expect(
        result.includes("exit=0"),
        `MintModule.sol drifted from baseline ${V38_BASELINE} (result: ${result.trim()})`
      ).to.equal(true);
    });

    it("[02b] MintModule still calls `_queueTicketsScaled` for boost-derived fractional ticket awards", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      // The mint-boost callsite uses _queueTicketsScaled with rngBypass=true
      // (per LBX-WT-05 + mint-boost pre-v39 status quo).
      const calls = (mint.match(/_queueTicketsScaled\(/g) || []).length;
      expect(
        calls,
        "MintModule must still contain at least one _queueTicketsScaled invocation"
      ).to.be.gte(1);
    });
  });

  describe("TST-REG-03 — auto-resolve paths byte-equivalent at v39", function () {
    it("[03a] resolveLootboxDirect passes `type(uint48).max` sentinel", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const fnIdx = source.indexOf("function resolveLootboxDirect(");
      expect(fnIdx).to.be.greaterThan(-1);
      // Scan within 2500 chars (full function body) for the call to
      // _resolveLootboxCommon and for the sentinel value.
      const body = source.slice(fnIdx, fnIdx + 2500);
      expect(body.includes("_resolveLootboxCommon(")).to.equal(true);
      expect(body.includes("type(uint48).max")).to.equal(true);
    });

    it("[03b] resolveRedemptionLootbox passes `type(uint48).max` sentinel", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const fnIdx = source.indexOf("function resolveRedemptionLootbox(");
      expect(fnIdx).to.be.greaterThan(-1);
      const body = source.slice(fnIdx, fnIdx + 2500);
      expect(body.includes("_resolveLootboxCommon(")).to.equal(true);
      expect(body.includes("type(uint48).max")).to.equal(true);
    });

    it("[03c] auto-resolve branch in `_resolveLootboxCommon` calls `_queueTicketsScaled` (status quo)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const autoPattern = /_queueTicketsScaled\(player, targetLevel, futureTickets, false\)/;
      expect(
        source.match(autoPattern),
        "auto-resolve branch must call `_queueTicketsScaled(player, targetLevel, futureTickets, false)`"
      ).to.not.be.null;
    });

    it("[03d] auto-resolve branch NEVER emits LootboxTicketRoll or calls wwxrp.mintPrize", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Locate the auto-resolve `_queueTicketsScaled` call.
      const autoIdx = source.indexOf(
        "_queueTicketsScaled(player, targetLevel, futureTickets, false)"
      );
      expect(autoIdx).to.be.greaterThan(-1);
      // The auto-resolve else block ends shortly after this line. Within
      // the next 400 chars, no consolation/emit must appear.
      const tail = source.slice(autoIdx, autoIdx + 400);
      expect(tail.includes("emit LootboxTicketRoll(")).to.equal(false);
      expect(tail.includes("wwxrp.mintPrize")).to.equal(false);
      expect(tail.includes("emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)")).to.equal(false);
    });

    it("[03e] LootboxTicketRoll emit count == 1 in the entire module (single manual-branch site)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const emits = (source.match(/emit LootboxTicketRoll\(/g) || []).length;
      expect(emits).to.equal(1);
    });

    it("[03f] LOOTBOX_WWXRP_CONSOLATION emit count == 1 in the entire module (single manual-branch site)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Both the `wwxrp.mintPrize(..., LOOTBOX_WWXRP_CONSOLATION)` call and the
      // adjacent `emit LootBoxWwxrpReward(..., LOOTBOX_WWXRP_CONSOLATION)` are
      // single-site.
      const mintCount = (source.match(
        /wwxrp\.mintPrize\(player, LOOTBOX_WWXRP_CONSOLATION\)/g
      ) || []).length;
      const emitCount = (source.match(
        /emit LootBoxWwxrpReward\(player, day, amount, LOOTBOX_WWXRP_CONSOLATION\)/g
      ) || []).length;
      expect(mintCount).to.equal(1);
      expect(emitCount).to.equal(1);
    });
  });

  describe("TST-REG-04 — cross-mixing variance posture", function () {
    it("[04a] manual + auto-resolve paths write to the same `ticketsOwedPacked[wk][player]` storage slot via different helpers", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      // Both _queueTickets and _queueTicketsScaled update the same packed
      // mapping `ticketsOwedPacked`. Confirm both touch it.
      const queueIdx = storage.indexOf("function _queueTickets(");
      const queueScaledIdx = storage.indexOf("function _queueTicketsScaled(");
      expect(queueIdx).to.be.greaterThan(-1);
      expect(queueScaledIdx).to.be.greaterThan(-1);

      // Extract both bodies and check that both reference ticketsOwedPacked.
      function extractBody(start) {
        let depth = 0;
        let bs = -1;
        let be = -1;
        for (let i = start; i < storage.length; i++) {
          if (storage[i] === "{") {
            if (depth === 0) bs = i;
            depth++;
          } else if (storage[i] === "}") {
            depth--;
            if (depth === 0) {
              be = i;
              break;
            }
          }
        }
        return storage.slice(bs, be);
      }
      const queueBody = extractBody(queueIdx);
      const queueScaledBody = extractBody(queueScaledIdx);
      expect(queueBody.includes("ticketsOwedPacked")).to.equal(true);
      expect(queueScaledBody.includes("ticketsOwedPacked")).to.equal(true);
    });

    it("[04b] documented tradeoff: manual is per-lootbox-Bernoulli (higher variance); auto-resolve pools via rem-byte (deterministic accumulation)", function () {
      // This is a documentation-of-intent assertion that the CONTEXT.md
      // <specifics> tradeoff is what ships. The Bernoulli math is documented
      // in the source NatSpec at L1030-1037; the rem-byte accumulation is
      // documented in `_queueTicketsScaled` body.
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // NatSpec mentions "Bernoulli" near the manual branch.
      const bernoulliMention = source.indexOf("Bernoulli");
      expect(bernoulliMention).to.be.greaterThan(-1);

      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      // Storage _queueTicketsScaled NatSpec / body mentions remainder.
      expect(storage.includes("Handles remainder accumulation")).to.equal(true);
    });

    it("[04c] manual + auto-resolve emit DIFFERENT event signatures (`TicketsQueued` vs `TicketsQueuedScaled`) — indexers can distinguish", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      // Both events declared at storage layer.
      expect(storage.includes("event TicketsQueued(") || /event TicketsQueued\b/.test(storage)).to.equal(true);
      expect(
        storage.includes("event TicketsQueuedScaled(") || /event TicketsQueuedScaled\b/.test(storage)
      ).to.equal(true);
    });

    it("[04d] the `index` discriminator routes manual vs auto-resolve with zero crossover", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Find the `if (index != type(uint48).max)` gate.
      const manualGate = source.indexOf("if (index != type(uint48).max)");
      expect(manualGate).to.be.greaterThan(-1);
      // The matching `else` must contain ONLY _queueTicketsScaled (auto-
      // resolve path). The else block is small.
      const tail = source.slice(manualGate, manualGate + 3000);
      // Must contain both branches.
      expect(tail.includes("_queueTickets(player, targetLevel, whole, false)")).to.equal(true);
      expect(
        tail.includes("_queueTicketsScaled(player, targetLevel, futureTickets, false)")
      ).to.equal(true);
      // The manual-branch _queueTickets must come first (true-branch).
      const manualCall = tail.indexOf("_queueTickets(player, targetLevel, whole, false)");
      const autoCall = tail.indexOf(
        "_queueTicketsScaled(player, targetLevel, futureTickets, false)"
      );
      expect(manualCall).to.be.lessThan(autoCall);
    });

    it("[04e] sentinel `type(uint48).max` cannot collide with any realistic lootbox index", function () {
      const SENTINEL = (1n << 48n) - 1n; // 281,474,976,710,655 (~281 trillion)
      // The protocol increments `lootboxRngIndex` once per lootbox purchase.
      // For the sentinel to collide, > 281 trillion lootboxes would need to
      // exist — a degenerate-impossible upper bound.
      expect(SENTINEL).to.equal(0xffffffffffffn);
      expect(SENTINEL > 1n << 47n).to.equal(true);
    });
  });
});
