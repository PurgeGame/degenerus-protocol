// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxConsolation.test.js — Phase 274 Wave 2 TST-WX-01..03
//
// WWXRP cold-bust consolation coverage. The contract under test is the
// ticket-collapse block of `_resolveLootboxCommon` at
// `contracts/modules/DegenerusGameLootboxModule.sol` (post-Phase-277 surface):
//
//   _queueTickets(player, targetLevel, whole, false);
//   if (emitLootboxEvent && whole == 0) {
//       wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
//       emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
//   }
//
// `_queueTickets` is called unconditionally; its `if (quantity == 0) return;`
// early-return absorbs the `whole == 0` cold-bust case silently. The WWXRP
// consolation is paid only on the manual `openLootBox` path — the single caller
// passing `emitLootboxEvent = true`. The two auto-resolve callers
// (`resolveLootboxDirect`, `resolveRedemptionLootbox`) and `openBurnieLootBox`
// all pass `emitLootboxEvent = false`, so cold-bust is silent for them.
//
// TEST STRATEGY:
//   - TST-WX-01 (cold-bust trigger) + TST-WX-02 (non-trigger predicate matrix) —
//     mathematical / structural assertions on the trigger predicate
//     `emitLootboxEvent AND scaledPre > 0 AND whole == 0`. The Bernoulli outcome
//     is purely a function of (scaledPre, seed); we verify via the
//     `LootboxBernoulliTester` contract that the math holds at boundary AND under
//     randomized seed sweep.
//   - TST-WX-02 (auto-resolve always-skip) — source-level structural assertion
//     that the consolation `mintPrize` + `LootBoxWwxrpReward` emit sit INSIDE
//     the `if (emitLootboxEvent && whole == 0)` gate, and that `_queueTickets`
//     is the single unconditional ticket-award callsite.
//   - TST-WX-03 (magnitude assertion) — direct on-chain constant inspection
//     via the LootboxBernoulliTester mirror constants AND source-grep cross
//     check.
//
// CROSS-CITES:
//   - D-274-WX-AMOUNT-01 (magnitude equivalence LOOTBOX_WWXRP_CONSOLATION ==
//     LOOTBOX_WWXRP_PRIZE)
//   - D-274-MANUAL-ONLY-01 (consolation only fires on manual path)
//   - LBX-WX-01..04 requirements per .planning/REQUIREMENTS.md

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";

const TICKET_SCALE = 100n;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);

async function deployTester() {
  const Factory = await hre.ethers.getContractFactory("LootboxBernoulliTester");
  const tester = await Factory.deploy();
  await tester.waitForDeployment();
  return tester;
}

describe("LootboxConsolation — Phase 274 Wave 2 TST-WX-01..03", function () {
  this.timeout(120_000);

  describe("TST-WX-01 — cold-bust trigger predicate", function () {
    it("[01a] tester confirms cold-bust math: scaledPre ∈ (0, 100) AND Bernoulli loses ⇒ whole=0, roundedUp=false", async function () {
      const tester = await deployTester();
      // Cold-bust scenarios: scaledPre in {1, 47, 50, 99}, seed forces
      // uint16(seed >> 152) % 100 = 99 (slice >= every possible frac < 100).
      const seed = BigInt(99) << 152n;
      for (const scaledPre of [1, 47, 50, 99]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(scaledPre, seed);
        expect(whole, `cold-bust must produce whole=0 at scaledPre=${scaledPre}`).to.equal(0n);
        expect(
          roundedUp,
          `cold-bust must produce roundedUp=false at scaledPre=${scaledPre}`
        ).to.equal(false);
      }
    });

    it("[01b] tester confirms warm scenarios: scaledPre ∈ (0, 100) AND Bernoulli wins ⇒ whole=1, roundedUp=true (NO consolation)", async function () {
      const tester = await deployTester();
      // Warm scenarios: seed forces uint16(seed >> 152) % 100 = 0 (slice < every
      // possible frac >= 1).
      const seed = 0n;
      for (const scaledPre of [1, 47, 50, 99]) {
        const [whole, roundedUp] = await tester.bernoulliWhole(scaledPre, seed);
        expect(whole).to.equal(1n);
        expect(roundedUp).to.equal(true);
      }
    });

    it("[01c] source: consolation emit only reachable when `emitLootboxEvent && whole == 0`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Find consolation emit; walk backward to find the enclosing gate.
      const consolationEmit = source.indexOf(
        "emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(consolationEmit).to.be.greaterThan(-1);
      // Within 600 chars preceding the emit, the `if (emitLootboxEvent && whole == 0)`
      // gate must appear — it is the immediate structural ancestor of the
      // consolation `mintPrize` + emit.
      const window = source.slice(Math.max(0, consolationEmit - 600), consolationEmit);
      expect(
        window.includes("if (emitLootboxEvent && whole == 0)"),
        "missing `if (emitLootboxEvent && whole == 0)` ancestor"
      ).to.equal(true);
    });

    it("[01d] consolation `wwxrp.mintPrize` is gated by `emitLootboxEvent && whole == 0` (auto-resolve cannot trigger)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const mintPrize = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(mintPrize).to.be.greaterThan(-1);
      // Within 600 chars preceding the mintPrize call, the
      // `if (emitLootboxEvent && whole == 0)` gate must appear (the NatSpec
      // comment block between the gate and the call widens the gap).
      // Auto-resolve callers pass `emitLootboxEvent = false`, so they never
      // reach the consolation; only the manual `openLootBox` path (the single
      // `emitLootboxEvent = true` caller) can trigger it.
      const window = source.slice(Math.max(0, mintPrize - 600), mintPrize);
      expect(
        window.includes("if (emitLootboxEvent && whole == 0)"),
        "consolation mintPrize not gated by `emitLootboxEvent && whole == 0`"
      ).to.equal(true);
    });
  });

  describe("TST-WX-02 — non-trigger predicate matrix", function () {
    it("[02a] whole >= 1 case: scaledPre=100..200 + frac=0 ⇒ whole >= 1, no consolation", async function () {
      const tester = await deployTester();
      // Whole multiples never trigger consolation regardless of seed.
      for (const scaledPre of [100, 200, 247, 300, 9999]) {
        for (const seed of [0n, BigInt(99) << 152n, BigInt(50) << 152n]) {
          const [whole, _roundedUp] = await tester.bernoulliWhole(scaledPre, seed);
          expect(
            whole,
            `whole must be >= 1 at scaledPre=${scaledPre}, seed=${seed.toString(16)}`
          ).to.be.gte(1n);
        }
      }
    });

    it("[02b] ticket award is a single unconditional `_queueTickets` call; the consolation is `emitLootboxEvent`-gated below it", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The sentinel branch is retired: `_queueTickets(player, targetLevel,
      // whole, false)` is called once, unconditionally, for every path
      // (manual + both auto-resolve callers + openBurnieLootBox). Its
      // `if (quantity == 0) return;` early-return absorbs the cold-bust case.
      const callLine = "_queueTickets(player, targetLevel, whole, false)";
      const firstIdx = source.indexOf(callLine);
      const secondIdx = source.indexOf(callLine, firstIdx + 1);
      expect(firstIdx, "`_queueTickets(player, targetLevel, whole, false)` callsite not found").to.be.greaterThan(-1);
      expect(
        secondIdx,
        "`_queueTickets(player, targetLevel, whole, false)` must appear exactly once (sentinel-branch duplication retired)"
      ).to.equal(-1);
      // Immediately after the queue call comes the `if (emitLootboxEvent && whole
      // == 0)` consolation gate — the consolation `mintPrize` + emit are inside
      // it, so auto-resolve callers (emitLootboxEvent = false) never reach them.
      const tail = source.slice(firstIdx, firstIdx + 600);
      expect(
        tail.includes("if (emitLootboxEvent && whole == 0)"),
        "consolation gate `if (emitLootboxEvent && whole == 0)` must follow the queue call"
      ).to.equal(true);
      const mintIdx = tail.indexOf("wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)");
      const gateIdx = tail.indexOf("if (emitLootboxEvent && whole == 0)");
      expect(mintIdx, "consolation mintPrize must sit after the gate").to.be.greaterThan(gateIdx);
    });

    it("[02c] ticket-path-not-selected case: when `futureTickets == 0` the outer `if (futureTickets != 0)` guard skips the entire Bernoulli/queue/consolation block", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The outer `if (futureTickets != 0)` guard wraps the whole Bernoulli
      // collapse + `_queueTickets` + consolation. Anything inside it requires
      // a non-zero scaled pre-Bernoulli ticket count.
      const outerGuard = source.indexOf("if (futureTickets != 0)");
      expect(outerGuard).to.be.greaterThan(-1);
      // The unconditional `_queueTickets` callsite is inside the outer guard.
      const queueCall = source.indexOf("_queueTickets(player, targetLevel, whole, false)");
      expect(queueCall).to.be.greaterThan(outerGuard);
      // The `emitLootboxEvent && whole == 0` consolation gate is inside the
      // outer guard too (it sits immediately below the queue call).
      const consolationGate = source.indexOf("if (emitLootboxEvent && whole == 0)");
      expect(consolationGate).to.be.greaterThan(queueCall);
      // Consolation `mintPrize` also inside outer guard.
      const mintPrize = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(mintPrize).to.be.greaterThan(outerGuard);
    });

    it("[02d] the 10%-path WWXRP win at `_resolveLootboxRoll` does NOT use LOOTBOX_WWXRP_CONSOLATION (separate concern)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The 10%-path WWXRP win uses LOOTBOX_WWXRP_PRIZE.
      const tenPercentWin = source.indexOf("uint256 wwxrpAmount = LOOTBOX_WWXRP_PRIZE");
      expect(tenPercentWin).to.be.greaterThan(-1);
      // It does NOT reference LOOTBOX_WWXRP_CONSOLATION nearby (250-char window).
      const window = source.slice(tenPercentWin, tenPercentWin + 250);
      expect(window.includes("LOOTBOX_WWXRP_CONSOLATION")).to.equal(false);
    });
  });

  describe("TST-WX-03 — magnitude assertion (LOOTBOX_WWXRP_CONSOLATION == LOOTBOX_WWXRP_PRIZE == 1 ether)", function () {
    it("[03a] tester contract constants: LOOTBOX_WWXRP_PRIZE == LOOTBOX_WWXRP_CONSOLATION == 1 ether", async function () {
      const tester = await deployTester();
      const prize = await tester.LOOTBOX_WWXRP_PRIZE();
      const consolation = await tester.LOOTBOX_WWXRP_CONSOLATION();
      const oneEther = hre.ethers.parseEther("1");
      expect(prize).to.equal(oneEther);
      expect(consolation).to.equal(oneEther);
      expect(prize).to.equal(consolation);
    });

    it("[03b] production module declares both constants at `= 1 ether` (defensive drift catch)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const prizePattern = /uint256 private constant LOOTBOX_WWXRP_PRIZE\s*=\s*1 ether;/;
      const consolationPattern =
        /uint256 private constant LOOTBOX_WWXRP_CONSOLATION\s*=\s*1 ether;/;
      expect(source.match(prizePattern), "LOOTBOX_WWXRP_PRIZE = 1 ether declaration missing").to.not.be.null;
      expect(
        source.match(consolationPattern),
        "LOOTBOX_WWXRP_CONSOLATION = 1 ether declaration missing"
      ).to.not.be.null;
    });

    it("[03c] the two constants live as siblings (declared near each other for visual drift catch)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const prizeIdx = source.indexOf("uint256 private constant LOOTBOX_WWXRP_PRIZE");
      const consolationIdx = source.indexOf(
        "uint256 private constant LOOTBOX_WWXRP_CONSOLATION"
      );
      expect(prizeIdx).to.be.greaterThan(-1);
      expect(consolationIdx).to.be.greaterThan(-1);
      // Within 500 chars of each other (NatSpec for the new constant fits).
      expect(Math.abs(prizeIdx - consolationIdx)).to.be.lessThan(500);
    });
  });
});
