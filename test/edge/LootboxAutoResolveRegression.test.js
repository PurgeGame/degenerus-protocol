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
//                 `resolveRedemptionLootbox`) call `_queueTickets(player,
//                 targetLevel, whole, false)` (the whole-helper) on the unified
//                 ticket-queue path, emit `TicketsQueued`, and stay silent.
//                 Post-Phase-277 the `index != type(uint48).max` sentinel is
//                 retired: there is no `LootboxTicketRoll` event anywhere in
//                 the module, the manual cold-bust WWXRP consolation is gated
//                 by the dedicated `payColdBustConsolation` flag (true for both
//                 manual callers, false for the auto-resolve callers), and both
//                 auto-resolve callers pass `index = 0`,
//                 `emitLootboxEvent = false`, and `payColdBustConsolation = false`.
//                 Bernoulli math is shared-scope per D-275-HOIST-01.
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
//   and the Foundry suite under `test/fuzz/` (pre-v39, status-quo). The
//   following remain unchanged and are asserted as such:
//     - DegenerusGameMintModule.sol (TST-REG-02) — byte-identical to baseline
//     - DegenerusGameStorage.sol _queueTickets / _queueTicketsScaled /
//       _rollRemainder semantics (TST-REG-03 / TST-REG-04)
//   TST-REG-03 is updated for the Phase 277 sentinel retirement: the
//   `index != type(uint48).max` gate is gone, auto-resolve callers pass
//   `index = 0` + `emitLootboxEvent = false` + `payColdBustConsolation = false`,
//   the cold-bust consolation is `payColdBustConsolation`-gated, and
//   `LootboxTicketRoll` is fully removed.
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

// Extract the top-level positional args of the first `_resolveLootboxCommon(...)`
// call within a function-body slice. Paren-depth-aware so `uint32(index)` stays
// one arg. Returns a string[] of trimmed args, or null if not found.
function extractResolveCommonArgs(body) {
  const marker = "_resolveLootboxCommon(";
  const idx = body.indexOf(marker);
  if (idx < 0) return null;
  const open = idx + marker.length - 1; // position of `(`
  let depth = 0;
  let close = -1;
  for (let i = open; i < body.length; i++) {
    if (body[i] === "(") depth++;
    else if (body[i] === ")") {
      depth--;
      if (depth === 0) {
        close = i;
        break;
      }
    }
  }
  if (close < 0) return null;
  const inner = body.slice(open + 1, close);
  const args = [];
  let argDepth = 0;
  let cur = "";
  for (const ch of inner) {
    if (ch === "(") argDepth++;
    if (ch === ")") argDepth--;
    if (ch === "," && argDepth === 0) {
      args.push(cur.trim());
      cur = "";
    } else {
      cur += ch;
    }
  }
  if (cur.trim().length > 0) args.push(cur.trim());
  return args;
}

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
    // SUPERSEDED by the v40.0 SURF-03 block in test/stat/SurfaceRegression.test.js:
    // Phase 278 reworded the _rollRemainder NatSpec comment in
    // DegenerusGameMintModule.sol (the dead `entropyStep` name dropped), so
    // byte-identity vs the v38 baseline 06623edb no longer holds. The
    // _rollRemainder code itself is unchanged — only the comment moved — and
    // the v40.0 SURF-03 gate re-protects the MintModule body against the v39
    // baseline 6a7455d1 with the comment reword excluded.
    it.skip("[02a] DegenerusGameMintModule.sol byte-identical to baseline 06623edb (G23)", function () {
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

  describe("TST-REG-03 — auto-resolve paths silent + sentinel retired (Phase 277)", function () {
    it("[03a] resolveLootboxDirect passes `index = 0` and `emitLootboxEvent = false` to _resolveLootboxCommon", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const fnIdx = source.indexOf("function resolveLootboxDirect(");
      expect(fnIdx).to.be.greaterThan(-1);
      // Scan within 2500 chars (full function body) for the call to
      // _resolveLootboxCommon.
      const body = source.slice(fnIdx, fnIdx + 2500);
      expect(body.includes("_resolveLootboxCommon(")).to.equal(true);
      // Sentinel value is fully retired — the caller passes `0`, not the sentinel.
      expect(body.includes("type(uint48).max")).to.equal(false);
      const args = extractResolveCommonArgs(body);
      expect(args, "_resolveLootboxCommon call args not parsed").to.not.equal(null);
      // Positional: 3rd arg = index, 10th arg = emitLootboxEvent.
      expect(args[2], "resolveLootboxDirect must pass index = 0").to.equal("0");
      expect(
        args[9],
        "resolveLootboxDirect must pass emitLootboxEvent = false"
      ).to.equal("false");
    });

    it("[03b] resolveRedemptionLootbox passes `index = 0` and `emitLootboxEvent = false` to _resolveLootboxCommon", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const fnIdx = source.indexOf("function resolveRedemptionLootbox(");
      expect(fnIdx).to.be.greaterThan(-1);
      const body = source.slice(fnIdx, fnIdx + 2500);
      expect(body.includes("_resolveLootboxCommon(")).to.equal(true);
      expect(body.includes("type(uint48).max")).to.equal(false);
      const args = extractResolveCommonArgs(body);
      expect(args, "_resolveLootboxCommon call args not parsed").to.not.equal(null);
      expect(args[2], "resolveRedemptionLootbox must pass index = 0").to.equal("0");
      expect(
        args[9],
        "resolveRedemptionLootbox must pass emitLootboxEvent = false"
      ).to.equal("false");
    });

    it("[03c] the unified ticket-queue path in `_resolveLootboxCommon` calls `_queueTickets(player, targetLevel, whole, false)` exactly once (sentinel retired — no per-branch duplication)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Phase 277 retired the `index != type(uint48).max` sentinel branch. The
      // manual and auto-resolve paths now share one unconditional
      // `_queueTickets(player, targetLevel, whole, false)` call.
      const callPattern = /_queueTickets\(player, targetLevel, whole, false\)/g;
      const calls = (source.match(callPattern) || []).length;
      expect(
        calls,
        "expected exactly one `_queueTickets(player, targetLevel, whole, false)` callsite (unified path post-Phase-277)"
      ).to.equal(1);
      // `_queueTicketsScaled` MUST no longer appear in `DegenerusGameLootboxModule.sol`
      expect(
        source.includes("_queueTicketsScaled"),
        "`_queueTicketsScaled` must not appear in LootboxModule post-Phase-275 LBX-AR-02"
      ).to.equal(false);
    });

    it("[03d] auto-resolve is silent: LootboxTicketRoll is gone, the cold-bust consolation is `payColdBustConsolation`-gated, and both auto-resolve callers pass `emitLootboxEvent = false` + `payColdBustConsolation = false`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // (1) LootboxTicketRoll is fully retired from the module.
      expect(
        (source.match(/LootboxTicketRoll/g) || []).length,
        "LootboxTicketRoll must not appear anywhere in DegenerusGameLootboxModule.sol"
      ).to.equal(0);
      // (2) The manual cold-bust WWXRP consolation is gated on
      //     `payColdBustConsolation && whole == 0` — it cannot fire on the
      //     auto-resolve (payColdBustConsolation = false) path.
      expect(
        /if \(payColdBustConsolation && whole == 0\)/.test(source),
        "the manual cold-bust consolation must be gated on `payColdBustConsolation && whole == 0`"
      ).to.equal(true);
      // (3) Both auto-resolve callers pass emitLootboxEvent = false (10th
      //     positional) AND payColdBustConsolation = false (11th positional).
      for (const fnSig of [
        "function resolveLootboxDirect(",
        "function resolveRedemptionLootbox(",
      ]) {
        const fnIdx = source.indexOf(fnSig);
        const body = source.slice(fnIdx, fnIdx + 2500);
        const args = extractResolveCommonArgs(body);
        expect(args, `${fnSig} _resolveLootboxCommon call args not parsed`).to.not.equal(
          null
        );
        expect(
          args[9],
          `${fnSig} must pass emitLootboxEvent = false`
        ).to.equal("false");
        expect(
          args[10],
          `${fnSig} must pass payColdBustConsolation = false`
        ).to.equal("false");
      }
    });

    it("[03e] LootboxTicketRoll emit count == 0 in the entire module (event retired)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const emits = (source.match(/emit LootboxTicketRoll\(/g) || []).length;
      expect(emits).to.equal(0);
    });

    it("[03f] the cold-bust WWXRP consolation is single-site and sits under the `payColdBustConsolation` gate (manual-only)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The `wwxrp.mintPrize(..., LOOTBOX_WWXRP_CONSOLATION)` call is single-site,
      // inside the `payColdBustConsolation && whole == 0` block. The payout is
      // observable off-chain via the WWXRP ERC-20 `Transfer` event the mint
      // emits — there is no dedicated lootbox-WWXRP event.
      const mintCount = (source.match(
        /wwxrp\.mintPrize\(player, LOOTBOX_WWXRP_CONSOLATION\)/g
      ) || []).length;
      expect(mintCount).to.equal(1);
      expect(
        source.includes("LootBoxWwxrpReward"),
        "the retired LootBoxWwxrpReward event must not appear in the module"
      ).to.equal(false);
      // The consolation mint sits textually after the
      // `payColdBustConsolation && whole == 0` gate that opens its block.
      const gateIdx = source.indexOf("if (payColdBustConsolation && whole == 0)");
      const mintIdx = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(gateIdx, "`payColdBustConsolation && whole == 0` gate not found").to.be.greaterThan(
        -1
      );
      expect(
        mintIdx,
        "the consolation mint must sit inside the `payColdBustConsolation` gate"
      ).to.be.greaterThan(gateIdx);
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

    it("[04d] manual vs auto-resolve are discriminated by dedicated flags, not by the `index` value — the unified ticket-queue path has zero per-branch crossover", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Phase 277 retired the `index != type(uint48).max` sentinel gate. Routing
      // is now two dedicated bools: `emitLootboxEvent` gates the `LootBoxOpened`
      // emit, and `payColdBustConsolation` gates the manual cold-bust WWXRP
      // consolation. The `_queueTickets(player, targetLevel, whole, false)` call
      // is unconditional and shared by both paths.
      expect(
        source.includes("if (index != type(uint48).max)"),
        "the `index != type(uint48).max` sentinel gate must be fully retired"
      ).to.equal(false);
      // The unified `_queueTickets` call appears exactly once — no per-branch
      // duplication, so manual and auto-resolve cannot cross over on the queue.
      const callMatches = (
        source.match(/_queueTickets\(player, targetLevel, whole, false\)/g) || []
      ).length;
      expect(
        callMatches,
        "the unified ticket-queue path must call `_queueTickets(player, targetLevel, whole, false)` exactly once"
      ).to.equal(1);
      // The `LootBoxOpened` emit is gated by `emitLootboxEvent`; the manual
      // cold-bust consolation is gated by the dedicated `payColdBustConsolation`.
      expect(
        /if \(emitLootboxEvent\)/.test(source),
        "the `LootBoxOpened` emit must be gated by `emitLootboxEvent`"
      ).to.equal(true);
      expect(
        /if \(payColdBustConsolation && whole == 0\)/.test(source),
        "the manual cold-bust consolation must be gated by `payColdBustConsolation`"
      ).to.equal(true);
    });

    it("[04e] auto-resolve callers pass `index = 0` — the value gates nothing and is emitted nowhere after sentinel retirement", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Post-Phase-277 the `uint48 index` parameter is purely the event
      // identifier on the manual `LootBoxOpened` emit. Auto-resolve callers,
      // which emit nothing, pass the clean `0` default (D-277-AR-INDEX-01).
      for (const fnSig of [
        "function resolveLootboxDirect(",
        "function resolveRedemptionLootbox(",
      ]) {
        const fnIdx = source.indexOf(fnSig);
        expect(fnIdx, `${fnSig} not found`).to.be.greaterThan(-1);
        const body = source.slice(fnIdx, fnIdx + 2500);
        const args = extractResolveCommonArgs(body);
        expect(args, `${fnSig} _resolveLootboxCommon args not parsed`).to.not.equal(
          null
        );
        expect(args[2], `${fnSig} must pass index = 0`).to.equal("0");
      }
    });
  });
});
