// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxAutoResolveSilentColdBust.test.js — Phase 275 Wave 2 TST-LBX-AR-03
//
// Silent cold-bust regression on the auto-resolve path:
//   When the Bernoulli round-up fails (`whole == 0` after the Bernoulli math
//   runs on `scaledPre > 0`), an auto-resolve caller produces:
//     - ZERO `TicketsQueued` emit (the `_queueTickets` helper at
//       `DegenerusGameStorage.sol` early-returns on `quantity == 0`).
//     - ZERO `wwxrp.mintPrize` invocation (no consolation on auto-resolve) —
//       the consolation is `payColdBustConsolation`-gated and auto-resolve
//       callers pass `payColdBustConsolation = false`. Since the consolation
//       payout is `wwxrp.mintPrize`, zero invocation also means zero WWXRP
//       ERC-20 `Transfer` events for the auto-resolve cold-bust.
//
// Phase 277 retired the `index != type(uint48).max` sentinel: `_queueTickets`
// is now a single unconditional callsite shared by every path, and the WWXRP
// cold-bust consolation sits under `if (payColdBustConsolation && whole == 0)`.
// The `LootboxTicketRoll` event is deleted entirely. The silent cold-bust
// contract is enforced purely by:
//   (i)  auto-resolve callers passing `payColdBustConsolation = false`, which
//        skips the consolation gate (they also pass `emitLootboxEvent = false`,
//        skipping the `LootBoxOpened` emit), and
//   (ii) the `if (quantity == 0) return;` early-return inside `_queueTickets`
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
//         unconditional `_queueTickets` call, that auto-resolve callers pass
//         `payColdBustConsolation = false`, and that the cold-bust gate is the
//         shared `_queueTickets` early-return at DegenerusGameStorage.sol.
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

  describe("Cold-bust math: when whole == 0, the auto-resolve else-arm calls _queueTickets(0) → silent early-return", function () {
    it("[01a] tester confirms cold-bust math: scaledPre ∈ (0, 100) AND Bernoulli loses ⇒ whole=0, roundedUp=false", async function () {
      const tester = await deployTester();
      // Bernoulli loses when uint16(seed >> 152) % 100 >= frac.
      // Force slice == 99 (>= every possible frac < 100) by setting seed
      // such that uint16(seed >> 152) == 99.
      const seedSliceHigh = BigInt(99) << 152n;
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

  describe("Source-level proof: ticket award is a single unconditional _queueTickets call; auto-resolve callers pass payColdBustConsolation = false", function () {
    it("[02a] `_queueTickets(player, targetLevel, whole, false)` appears exactly once; the consolation that follows it is `payColdBustConsolation`-gated", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The sentinel branch is retired: the ticket award is a single
      // unconditional `_queueTickets(player, targetLevel, whole, false)`
      // callsite shared by every path. The cold-bust case is absorbed by the
      // helper's `if (quantity == 0) return;` early-return.
      const callLine = "_queueTickets(player, targetLevel, whole, false)";
      const firstIdx = source.indexOf(callLine);
      const secondIdx = source.indexOf(callLine, firstIdx + 1);
      expect(firstIdx, "`_queueTickets(player, targetLevel, whole, false)` callsite not found").to.be.greaterThan(-1);
      expect(
        secondIdx,
        "`_queueTickets(player, targetLevel, whole, false)` must appear exactly once (sentinel-branch duplication retired)"
      ).to.equal(-1);
      // The consolation `mintPrize` payout that follows the queue call sits
      // inside `if (payColdBustConsolation && whole == 0)` — so an auto-resolve
      // caller (payColdBustConsolation = false) never reaches it. There is no
      // dedicated lootbox-WWXRP event; the WWXRP ERC-20 `Transfer` the mint
      // emits is the off-chain correlation surface.
      const tail = source.slice(firstIdx, firstIdx + 600);
      expect(
        tail.includes("if (payColdBustConsolation && whole == 0)"),
        "consolation gate `if (payColdBustConsolation && whole == 0)` must follow the queue call"
      ).to.equal(true);
      const gateIdx = tail.indexOf("if (payColdBustConsolation && whole == 0)");
      expect(
        tail.indexOf("wwxrp.mintPrize", gateIdx),
        "consolation mintPrize must sit inside the payColdBustConsolation gate"
      ).to.be.greaterThan(gateIdx);
      expect(
        source.includes("LootBoxWwxrpReward"),
        "the retired LootBoxWwxrpReward event must not appear in the module"
      ).to.equal(false);
    });

    it("[02b] both auto-resolve callers (resolveLootboxDirect + resolveRedemptionLootbox) pass `index = 0`, `emitLootboxEvent = false`, and `payColdBustConsolation = false`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // v47 `_resolveLootboxCommon` positional args (now 2-bool / 11 args — the old
      // 5-bool presale/allowPasses/allowBoons gating params were removed; the 3 ETH
      // callers always roll full boons+passes): player(1), day(2), index(3),
      // amount(4), targetLevel(5), currentLevel(6), seed(7), emitLootboxEvent(8),
      // payColdBustConsolation(9), distressEth(10), totalPackedEth(11). The
      // auto-resolve callers pass `index = 0`, `emitLootboxEvent = false`, and
      // `payColdBustConsolation = false` (silent on cold-bust).
      for (const fnName of ["function resolveLootboxDirect(", "function resolveRedemptionLootbox("]) {
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
        expect(args.length, `${fnName}: _resolveLootboxCommon must receive 11 positional args (v47 2-bool shape)`).to.equal(11);
        expect(args[2], `${fnName} must pass index = 0 (3rd positional)`).to.equal("0");
        expect(args[7], `${fnName} must pass emitLootboxEvent = false (8th positional)`).to.equal("false");
        expect(args[8], `${fnName} must pass payColdBustConsolation = false (9th positional)`).to.equal("false");
        expect(
          body.includes("type(uint48).max"),
          `${fnName} must NOT reference the retired type(uint48).max sentinel`
        ).to.equal(false);
      }
    });

    it("[02c] cold-bust gate is the shared `_queueTickets` early-return at DegenerusGameStorage.sol — body contains `if (quantity == 0) return;` (D-40N-SILENT-01)", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const fnIdx = storage.indexOf("function _queueTickets(");
      expect(fnIdx, "_queueTickets function not found in storage").to.be.greaterThan(-1);
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
      // branch which calls consolation instead, never reaching _queueTickets).
      expect(
        /if\s*\(\s*quantity\s*==\s*0\s*\)\s*return;/.test(body),
        "_queueTickets must contain `if (quantity == 0) return;` early-return (D-40N-SILENT-01 silent-cold-bust gate)"
      ).to.equal(true);
    });
  });

  describe("Manual-path positive control: cold-bust seed reaches the payColdBustConsolation-gated consolation (per D-277-CONSOLATION-GATE-01)", function () {
    it("[03a] same cold-bust math at scaledPre=1, slice=99 — whole==0, so a manual open reaches the `payColdBustConsolation && whole == 0` consolation gate", async function () {
      const tester = await deployTester();
      // Same seed as the silent cold-bust test above (slice=99). The Bernoulli
      // math is shared by every path per D-275-HOIST-01 — so every caller sees
      // whole=0. The DIFFERENCE is the `payColdBustConsolation` gate downstream:
      //   - Manual caller `openLootBox` (payColdBustConsolation = true): the
      //     `if (payColdBustConsolation && whole == 0)` gate opens — pays
      //     LOOTBOX_WWXRP_CONSOLATION via wwxrp.mintPrize (observable via the WWXRP
      //     ERC-20 `Transfer` event). (v47: the BURNIE-lootbox manual caller
      //     openBurnieLootBox, which also passed payColdBustConsolation=true, was
      //     removed — terminal-paradox closure.)
      //   - Auto-resolve callers (payColdBustConsolation = false): the gate
      //     stays shut; `_queueTickets(0)` early-returns → fully silent.
      const seedSliceHigh = BigInt(99) << 152n;
      const [whole, roundedUp] = await tester.bernoulliWhole(1, seedSliceHigh);
      expect(whole).to.equal(0n);
      expect(roundedUp).to.equal(false);
      // The consolation gate is `payColdBustConsolation && whole == 0` AFTER the
      // Bernoulli — verified structurally in LootboxConsolation.test.js [01c]
      // and behaviorally in LootboxConsolation.test.js TST-WX-04.
    });

    it("[03b] consolation mintPrize IS present and gated by `payColdBustConsolation && whole == 0`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` payout appears
      // inside the `if (payColdBustConsolation && whole == 0)` gate — the
      // manual-only cold-bust consolation per D-277-CONSOLATION-GATE-01. The
      // payout is observable off-chain via the WWXRP ERC-20 `Transfer` event;
      // there is no dedicated lootbox-WWXRP event.
      expect(
        source.includes("wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"),
        "consolation `wwxrp.mintPrize(...)` missing"
      ).to.equal(true);
      expect(
        source.includes("LootBoxWwxrpReward"),
        "the retired LootBoxWwxrpReward event must not appear in the module"
      ).to.equal(false);
      // The mint must be gated by `if (payColdBustConsolation && whole == 0)` —
      // the gate appears before it in source order.
      const gateIdx = source.indexOf("if (payColdBustConsolation && whole == 0)");
      const mintPrizeIdx = source.indexOf("wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)");
      expect(gateIdx, "consolation gate `if (payColdBustConsolation && whole == 0)` missing").to.be.greaterThan(-1);
      expect(mintPrizeIdx).to.be.greaterThan(gateIdx);
    });

    it("[03c] the retired `LootboxTicketRoll` event has zero references in the module (Phase 277 deletion)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Phase 277 deleted the v39-additive `LootboxTicketRoll` event entirely —
      // no event def, no emit site. The cold-bust ticket roll is now observable
      // only via the `LootBoxOpened` event's `futureTickets` + `roundedUp`
      // fields (manual path) or stays silent (auto-resolve path).
      const refs = (source.match(/LootboxTicketRoll/g) || []).length;
      expect(refs, "`LootboxTicketRoll` must have zero references (Phase 277 retired the event)").to.equal(0);
    });
  });
});
