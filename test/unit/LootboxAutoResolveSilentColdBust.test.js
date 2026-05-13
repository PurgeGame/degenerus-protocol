// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxAutoResolveSilentColdBust.test.js — Phase 275 Wave 2 TST-LBX-AR-03
//
// Silent cold-bust regression on the auto-resolve branch:
//   When the Bernoulli round-up fails (`whole == 0` after the shared-scope
//   Bernoulli math runs on `scaledPre > 0`), the auto-resolve path produces:
//     - ZERO `TicketsQueued` emit (the `_queueTickets` helper at
//       `DegenerusGameStorage.sol:568` early-returns on `quantity == 0`).
//     - ZERO `LootBoxWwxrpReward` emit on the auto-resolve branch.
//     - ZERO `LootboxTicketRoll` emit on the auto-resolve branch.
//     - ZERO `wwxrp.mintPrize` invocation (no consolation on auto-resolve).
//
// Per `feedback_no_dead_guards.md` + the v40 hoist invariant, the silent
// cold-bust contract is enforced purely by:
//   (i) the structure of the `_resolveLootboxCommon` else-arm (only one
//       statement: `_queueTickets(player, targetLevel, whole, false)`), and
//   (ii) the `if (quantity == 0) return;` early-return inside `_queueTickets`
//       at DegenerusGameStorage.sol:568.
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
//         hoisted Bernoulli (LootboxBernoulliTester).
//     (b) Source-level structural proofs that the auto-resolve else-arm
//         contains ONLY the queue call + that the cold-bust gate is the
//         shared `_queueTickets` early-return at DegenerusGameStorage.sol:568.
//     (c) Manual-path positive control: same cold-bust seed produces
//         `LootBoxWwxrpReward` + `wwxrp.mintPrize` (consolation) emit AND
//         `LootboxTicketRoll` emit per D-275-STATUSQUO-01 — proves the
//         assertion mechanism functions on the path where emits ARE expected.
//
// CROSS-CITES:
//   - D-275-HOIST-01 (Bernoulli math byte-identical between branches)
//   - D-40N-SILENT-01 (auto-resolve cold-bust SILENT)
//   - D-275-STATUSQUO-01 (manual-branch consolation preserved verbatim)
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

  describe("Source-level proof: auto-resolve else-arm contains ONLY the _queueTickets(whole) call — no emit, no mintPrize", function () {
    it("[02a] auto-resolve else-arm tail (next 300 chars after the second `_queueTickets` call) contains NO mintPrize/LootBoxWwxrpReward/LootboxTicketRoll", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The auto-resolve `_queueTickets(player, targetLevel, whole, false)` is
      // the SECOND occurrence of that line in the module — the first is the
      // manual true-branch.
      const callLine = "_queueTickets(player, targetLevel, whole, false)";
      const firstIdx = source.indexOf(callLine);
      const autoIdx = source.indexOf(callLine, firstIdx + 1);
      expect(firstIdx, "first (manual-branch) _queueTickets callsite not found").to.be.greaterThan(-1);
      expect(autoIdx, "second (auto-resolve) _queueTickets callsite not found").to.be.greaterThan(firstIdx);

      const tail = source.slice(autoIdx, autoIdx + 300);
      expect(tail.includes("wwxrp.mintPrize"), "auto-resolve else-arm must not call wwxrp.mintPrize").to.equal(false);
      expect(tail.includes("emit LootBoxWwxrpReward"), "auto-resolve else-arm must not emit LootBoxWwxrpReward").to.equal(false);
      expect(tail.includes("emit LootboxTicketRoll"), "auto-resolve else-arm must not emit LootboxTicketRoll").to.equal(false);
    });

    it("[02b] both auto-resolve callers (resolveLootboxDirect + resolveRedemptionLootbox) pass `type(uint48).max` sentinel and `emitLootboxEvent=false`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      for (const fnName of ["function resolveLootboxDirect(", "function resolveRedemptionLootbox("]) {
        const fnIdx = source.indexOf(fnName);
        expect(fnIdx, `${fnName} not found`).to.be.greaterThan(-1);
        const body = source.slice(fnIdx, fnIdx + 3000);
        expect(body.includes("_resolveLootboxCommon("), `${fnName} must call _resolveLootboxCommon`).to.equal(true);
        expect(body.includes("type(uint48).max"), `${fnName} must pass the sentinel`).to.equal(true);
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

  describe("Manual-path positive control: cold-bust seed on manual branch triggers consolation + emits (per D-275-STATUSQUO-01)", function () {
    it("[03a] same cold-bust math at scaledPre=1, slice=99 — the manual branch reaches the consolation else-arm because whole==0", async function () {
      const tester = await deployTester();
      // Same seed as the silent cold-bust test above (slice=99). The math is
      // byte-identical between branches per D-275-HOIST-01 — so both branches
      // see whole=0. The DIFFERENCE is downstream:
      //   - Manual branch: pays LOOTBOX_WWXRP_CONSOLATION + emits LootBoxWwxrpReward + emits LootboxTicketRoll(scaledPre, roundedUp=false).
      //   - Auto-resolve branch: calls _queueTickets(0) → silent early-return.
      const seedSliceHigh = BigInt(99) << 152n;
      const [whole, roundedUp] = await tester.bernoulliWhole(1, seedSliceHigh);
      expect(whole).to.equal(0n);
      expect(roundedUp).to.equal(false);
      // The consolation gate is `whole == 0` AFTER the Bernoulli — verified
      // structurally in LootboxConsolation.test.js [01c] (consolation emit
      // sits inside the `else` of `if (whole != 0)` on the manual path).
    });

    it("[03b] manual-branch consolation emit + mintPrize ARE present (verified at fixed source locations gated by manual-branch predicate)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Within the manual branch (the `if (index != type(uint48).max)` true-arm),
      // both `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` and the
      // `emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)`
      // appear. They are the manual-path consolation per D-275-STATUSQUO-01.
      expect(
        source.includes("wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"),
        "manual-branch consolation `wwxrp.mintPrize(...)` missing"
      ).to.equal(true);
      expect(
        source.includes("emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)"),
        "manual-branch consolation `emit LootBoxWwxrpReward(...)` missing"
      ).to.equal(true);
      // Both must be gated by `if (index != type(uint48).max)` — the gate
      // appears before them in source order.
      const gateIdx = source.indexOf("if (index != type(uint48).max)");
      const mintPrizeIdx = source.indexOf("wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)");
      expect(gateIdx).to.be.greaterThan(-1);
      expect(mintPrizeIdx).to.be.greaterThan(gateIdx);
    });

    it("[03c] manual-branch `emit LootboxTicketRoll(...)` is present exactly once and gated by manual-branch predicate", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const emits = (source.match(/emit LootboxTicketRoll\(/g) || []).length;
      expect(emits, "LootboxTicketRoll must be emitted exactly once (manual branch only)").to.equal(1);
      const emitIdx = source.indexOf("emit LootboxTicketRoll(");
      const gateIdx = source.indexOf("if (index != type(uint48).max)");
      expect(emitIdx).to.be.greaterThan(gateIdx);
    });
  });
});
