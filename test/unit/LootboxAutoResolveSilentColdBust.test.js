// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxAutoResolveSilentColdBust.test.js — Phase 275 Wave 2 TST-LBX-AR-03
//
// Silent cold-bust regression on the auto-resolve path:
//   When the Bernoulli round-up fails (`whole == 0` after the Bernoulli math
//   runs on `scaledPre > 0`), an auto-resolve caller produces:
//     - ZERO `EntriesQueued` emit (the `_queueEntries` helper at
//       `DegenerusGameStorage.sol` early-returns on `entries == 0`).
//     - ZERO `wwxrp.mintPrize` invocation (no consolation on auto-resolve) —
//       the consolation is `payColdBustConsolation`-gated and auto-resolve
//       callers pass `payColdBustConsolation = false`. Since the consolation
//       payout is `wwxrp.mintPrize`, zero invocation also means zero WWXRP
//       ERC-20 `Transfer` events for the auto-resolve cold-bust.
//
// Phase 277 retired the `index != type(uint48).max` sentinel: `_queueEntries`
// is now a single unconditional callsite shared by every path, and the WWXRP
// cold-bust consolation sits under `if (payColdBustConsolation && whole == 0)`.
// The `LootboxTicketRoll` event is deleted entirely. The silent cold-bust
// contract is enforced purely by:
//   (i)  auto-resolve callers passing `payColdBustConsolation = false`, which
//        skips the consolation gate (they still emit `LootBoxOpened` like every box
//        path — the emitLootboxEvent flag was removed), and
//   (ii) the `if (entries == 0) return;` early-return inside `_queueEntries`
//        at DegenerusGameStorage.sol, which absorbs the `whole == 0` case.
//
// TEST STRATEGY:
//   No state fixture exists for `resolveLootboxDirect` /
//   `resolveRedemptionLootbox` at the FOG-of-state required (level + day
//   simulation, VRF-derived rngWord with controlled seed bit-slice, sDGNRS
//   staking position, etc.) — same fixture-coverage-gap precedent as LBX-02
//   in v39 Phase 274. Per `feedback_gas_worst_case.md` discipline ("derive
//   theoretical worst case FIRST; if no fixture, source-level/tester-direct
//   evidence is load-bearing"), this test combines:
//     (a) Direct-call cold-bust math verification on the byte-identical
//         Bernoulli (LootboxBernoulliTester).
//     (b) Source-level structural proofs that the ticket award is a single
//         unconditional `_queueEntries` call, that auto-resolve callers pass
//         `payColdBustConsolation = false`, and that the cold-bust gate is the
//         shared `_queueEntries` early-return at DegenerusGameStorage.sol.
//     (c) Manual-path positive control: same cold-bust seed reaches the
//         `payColdBustConsolation && whole == 0` consolation gate, producing
//         the `wwxrp.mintPrize` payout (observable off-chain via the WWXRP
//         ERC-20 `Transfer` event) — proves the assertion mechanism functions
//         on the path where the consolation IS expected.
//
// CROSS-CITES:
//   - D-275-HOIST-01 (Bernoulli math byte-identical between paths)
//   - D-40N-SILENT-01 (auto-resolve cold-bust SILENT)
//   - D-277-CONSOLATION-GATE-01 (manual cold-bust consolation under payColdBustConsolation)
//   - D-277-AR-SILENT-01 (auto-resolve callers pass payColdBustConsolation = false)
//   - feedback_rng_backward_trace.md (cold-bust seed selection upstream)
//   - feedback_rng_commitment_window.md (player cannot mutate seed once
//     `_resolveLootboxCommon` is entered)

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";

const TICKET_SCALE = 100n;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);
const STORAGE_PATH = path.resolve(
  process.cwd(),
  "contracts/storage/DegenerusGameStorage.sol"
);

async function deployTester() {
  const Factory = await hre.ethers.getContractFactory("LootboxBernoulliTester");
  const tester = await Factory.deploy();
  await tester.waitForDeployment();
  return tester;
}

describe("LootboxAutoResolveSilentColdBust — Phase 275 Wave 2 TST-LBX-AR-03", function () {
  this.timeout(60_000);

  describe("Cold-bust math: when whole == 0, the auto-resolve else-arm calls _queueEntries(0) → silent early-return", function () {
    it("[01a] tester confirms cold-bust math: scaledPre ∈ (0, 100) AND Bernoulli loses ⇒ whole=0, roundedUp=false", async function () {
      const tester = await deployTester();
      // Bernoulli loses when uint32(seed >> 224) % 100 >= frac.
      // Force slice == 99 (>= every possible frac < 100) by setting seed
      // such that uint32(seed >> 224) == 99.
      const seedSliceHigh = BigInt(99) << 224n;
      for (const scaledPre of [1, 47, 50, 99]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(scaledPre, seedSliceHigh);
        expect(
          whole,
          `cold-bust must produce whole=0 at scaledPre=${scaledPre} (frac=${scaledPre % 100})`
        ).to.equal(0n);
        expect(
          roundedUp,
          `cold-bust must produce roundedUp=false at scaledPre=${scaledPre}`
        ).to.equal(false);
      }
    });

    it("[01b] tester confirms warm scenarios: scaledPre ∈ (0, 100) AND Bernoulli wins ⇒ whole=1, roundedUp=true", async function () {
      const tester = await deployTester();
      // Force slice == 0 (< every possible frac >= 1) by setting seed=0.
      const seedSliceLow = 0n;
      for (const scaledPre of [1, 47, 50, 99]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(scaledPre, seedSliceLow);
        expect(whole, `warm path must produce whole=1 at scaledPre=${scaledPre}`).to.equal(1n);
        expect(roundedUp, `warm path must produce roundedUp=true at scaledPre=${scaledPre}`).to.equal(true);
      }
    });
  });

  describe("Source-level proof: ticket award is a single unconditional _queueEntries call; auto-resolve callers pass payColdBustConsolation = false", function () {
    it("[02a] `_queueEntries(player, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)` appears at one source site (in `_flushBoxAcc`); the consolation accumulation is `payColdBustConsolation`-gated (in `_settleLootboxRoll`)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Box-order rework: the ticket award queue call moved to `_flushBoxAcc`
      // (flushed once per entry); the cold-bust case is absorbed by
      // `_flushBoxAcc`'s per-lane `if (whole != 0)` guard (a zero-tier never
      // populates `acc.tickets[i]`).
      const callLine = "_queueEntries(player, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)";
      const firstIdx = source.indexOf(callLine);
      const secondIdx = source.indexOf(callLine, firstIdx + 1);
      expect(firstIdx, "`_queueEntries(player, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)` callsite not found").to.be.greaterThan(-1);
      expect(
        secondIdx,
        "`_queueEntries(player, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)` must appear at exactly one source site"
      ).to.equal(-1);
      // The consolation ACCUMULATION (not the queue call — different function
      // now) sits inside `if (payColdBustConsolation && whole == 0)` in
      // `_settleLootboxRoll` — so an auto-resolve caller (payColdBustConsolation
      // = false) never adds to `acc.wwxrp`, and the shared per-entry flush in
      // `_flushBoxAcc` is a no-op for them. There is no dedicated
      // lootbox-WWXRP event; the WWXRP ERC-20 `Transfer` the mint emits is the
      // off-chain correlation surface.
      const accIdx = source.indexOf("acc.wwxrp += _boxWwxrpStake(rollAmount);");
      expect(accIdx, "consolation accumulation callsite not found").to.be.greaterThan(-1);
      const gateWindow = source.slice(Math.max(0, accIdx - 600), accIdx);
      expect(
        gateWindow.includes("if (payColdBustConsolation && whole == 0)"),
        "consolation gate `if (payColdBustConsolation && whole == 0)` must precede the accumulation"
      ).to.equal(true);
      expect(
        source.includes("if (acc.wwxrp != 0) wwxrp.mintPrize(player, acc.wwxrp);"),
        "consolation flush must sit at its own per-entry site"
      ).to.equal(true);
      expect(
        source.includes("LootBoxWwxrpReward"),
        "the retired LootBoxWwxrpReward event must not appear in the module"
      ).to.equal(false);
    });

    it("[02b] both auto-resolve callers (resolveLootboxDirect + resolveRedemptionLootbox) pass `index = 0` and `payColdBustConsolation = false`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // `_resolveLootboxCommon` positional args (12): player(1), index(2), amount(3),
      // targetLevel(4), currentLevel(5), seed(6), payColdBustConsolation(7),
      // distressEth(8), totalPackedEth(9), activityScore(10), allowEthSpin(11),
      // acc(12) — box-order rework added the trailing `BoxAcc memory acc`
      // accumulator param (each roll's tickets/dgnrs/wwxrp/flip land there,
      // flushed once per entry by `_flushBoxAcc`); `allowSplit` no longer
      // exists (the 0.5-ETH auto-split was deleted — one box = one roll,
      // always). The always-true `emitLootboxEvent` flag was removed
      // (every box path emits LootBoxOpened, gated only by !wasSpin). The auto-resolve
      // callers pass `index = 0` and `payColdBustConsolation = false` (silent on cold-bust);
      // allowEthSpin(11) differs by caller (false on the resolveLootboxDirect recirc, true on
      // the redemption chunk). The redemption auto-resolve path holds its
      // `_resolveLootboxCommon` call in the private `_resolveRedemptionChunk` helper (per 5-ETH chunk).
      for (const fnName of ["function resolveLootboxDirect(", "function _resolveRedemptionChunk("]) {
        const fnIdx = source.indexOf(fnName);
        expect(fnIdx, `${fnName} not found`).to.be.greaterThan(-1);
        const body = source.slice(fnIdx, fnIdx + 3000);
        const callIdx = body.indexOf("_resolveLootboxCommon(");
        expect(callIdx, `${fnName} must call _resolveLootboxCommon`).to.be.greaterThan(-1);
        // Extract the call's arg list by paren-matching.
        let depth = 0;
        let argStart = -1;
        let argEnd = -1;
        for (let i = callIdx + "_resolveLootboxCommon".length; i < body.length; i++) {
          if (body[i] === "(") {
            if (depth === 0) argStart = i + 1;
            depth++;
          } else if (body[i] === ")") {
            depth--;
            if (depth === 0) {
              argEnd = i;
              break;
            }
          }
        }
        expect(argEnd, `${fnName}: could not paren-match _resolveLootboxCommon call`).to.be.greaterThan(argStart);
        const args = body
          .slice(argStart, argEnd)
          .split(",")
          .map((a) => a.replace(/\/\/.*$/gm, "").trim())
          .filter((a) => a.length > 0);
        expect(args.length, `${fnName}: _resolveLootboxCommon must receive 12 positional args (emitLootboxEvent removed; allowSplit + activityScore + allowEthSpin)`).to.equal(12);
        expect(args[1], `${fnName} must pass index = 0 (2nd positional)`).to.equal("0");
        // payColdBustConsolation (7th positional) stays false on both auto-resolve callers —
        // silent on cold-bust. The emitLootboxEvent flag is gone (every box path emits).
        expect(args[6], `${fnName} must pass payColdBustConsolation = false (7th positional)`).to.equal("false");
        expect(args[9], `${fnName} must pass activityScore (10th positional)`).to.equal("activityScore");
        expect(args[11], `${fnName} must pass acc (12th positional)`).to.equal("acc");
        expect(
          body.includes("type(uint48).max"),
          `${fnName} must NOT reference the retired type(uint48).max sentinel`
        ).to.equal(false);
      }
    });

    it("[02c] cold-bust gate is the shared `_queueEntries` early-return at DegenerusGameStorage.sol — body contains `if (entries == 0) return;` (D-40N-SILENT-01)", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const fnIdx = storage.indexOf("function _queueEntries(");
      expect(fnIdx, "_queueEntries function not found in storage").to.be.greaterThan(-1);
      // Find function body end by brace-matching.
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
      // The early-return MUST be present; this is the silent-cold-bust gate
      // shared by the auto-resolve path (and the manual path's `whole == 0`
      // branch which calls consolation instead, never reaching _queueEntries).
      expect(
        /if\s*\(\s*entries\s*==\s*0\s*\)\s*return;/.test(body),
        "_queueEntries must contain `if (entries == 0) return;` early-return (D-40N-SILENT-01 silent-cold-bust gate)"
      ).to.equal(true);
    });
  });

  describe("Manual-path positive control: cold-bust seed reaches the payColdBustConsolation-gated consolation (per D-277-CONSOLATION-GATE-01)", function () {
    it("[03a] same cold-bust math at scaledPre=1, slice=99 — whole==0, so a manual open reaches the `payColdBustConsolation && whole == 0` consolation gate", async function () {
      const tester = await deployTester();
      // Same seed as the silent cold-bust test above (slice=99). The Bernoulli
      // math is shared by every path per D-275-HOIST-01 — so every caller sees
      // whole=0. The DIFFERENCE is the `payColdBustConsolation` gate downstream:
      //   - Manual caller `openBox` (payColdBustConsolation = true): the
      //     `if (payColdBustConsolation && whole == 0)` gate opens — pays
      //     _boxWwxrpStake(rollAmount) via wwxrp.mintPrize (observable via the WWXRP
      //     ERC-20 `Transfer` event). (v47: the FLIP-lootbox manual caller
      //     openFlipLootBox, which also passed payColdBustConsolation=true, was
      //     removed — terminal-paradox closure.)
      //   - Auto-resolve callers (payColdBustConsolation = false): the gate
      //     stays shut; `_queueEntries(0)` early-returns → fully silent.
      const seedSliceHigh = BigInt(99) << 224n;
      const [whole, roundedUp] = await tester.bernoulliWhole(1, seedSliceHigh);
      expect(whole).to.equal(0n);
      expect(roundedUp).to.equal(false);
      // The consolation gate is `payColdBustConsolation && whole == 0` AFTER the
      // Bernoulli — verified structurally in LootboxConsolation.test.js [01c]
      // and behaviorally in LootboxConsolation.test.js TST-WX-04.
    });

    it("[03b] consolation accumulation IS present and gated by `payColdBustConsolation && whole == 0`, flushed once per entry via `wwxrp.mintPrize`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Box-order rework: the payout ACCUMULATES via `acc.wwxrp +=
      // _boxWwxrpStake(rollAmount)` inside the `if (payColdBustConsolation &&
      // whole == 0)` gate — the manual-only cold-bust consolation per
      // D-277-CONSOLATION-GATE-01 — then flushes once per entry via
      // `if (acc.wwxrp != 0) wwxrp.mintPrize(player, acc.wwxrp);`. The payout
      // is observable off-chain via the WWXRP ERC-20 `Transfer` event; there is
      // no dedicated lootbox-WWXRP event.
      expect(
        source.includes("acc.wwxrp += _boxWwxrpStake(rollAmount);"),
        "consolation accumulation `acc.wwxrp += _boxWwxrpStake(rollAmount);` missing"
      ).to.equal(true);
      expect(
        source.includes("if (acc.wwxrp != 0) wwxrp.mintPrize(player, acc.wwxrp);"),
        "per-entry WWXRP flush missing"
      ).to.equal(true);
      expect(
        source.includes("LootBoxWwxrpReward"),
        "the retired LootBoxWwxrpReward event must not appear in the module"
      ).to.equal(false);
      // The accumulation must be gated by `if (payColdBustConsolation && whole
      // == 0)` — the gate appears before it in source order.
      const gateIdx = source.indexOf("if (payColdBustConsolation && whole == 0)");
      const accIdx = source.indexOf("acc.wwxrp += _boxWwxrpStake(rollAmount);");
      expect(gateIdx, "consolation gate `if (payColdBustConsolation && whole == 0)` missing").to.be.greaterThan(-1);
      expect(accIdx).to.be.greaterThan(gateIdx);
    });

    it("[03c] the retired `LootboxTicketRoll` event has zero references in the module (Phase 277 deletion)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Phase 277 deleted the v39-additive `LootboxTicketRoll` event entirely —
      // no event def, no emit site. The cold-bust ticket roll is now observable
      // only via the `LootBoxOpened` event's `scaledTickets` + `roundedUp`
      // fields (manual path) or stays silent (auto-resolve path).
      const refs = (source.match(/LootboxTicketRoll/g) || []).length;
      expect(refs, "`LootboxTicketRoll` must have zero references (Phase 277 retired the event)").to.equal(0);
    });
  });
});
