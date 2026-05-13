// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxConsolation.test.js — Phase 274 Wave 2 TST-WX-01..03
//
// WWXRP cold-bust consolation coverage. The contract under test is the
// manual-branch else clause of `_resolveLootboxCommon` at
// `contracts/modules/DegenerusGameLootboxModule.sol` L1049-1060 (v39 HEAD):
//
//   if (whole != 0) {
//       _queueTickets(player, targetLevel, whole, false);
//   } else {
//       wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
//       emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
//   }
//   emit LootboxTicketRoll(player, index, scaledPre, roundedUp);
//
// TEST STRATEGY:
//   - TST-WX-01 (cold-bust trigger) + TST-WX-02 (non-trigger predicate matrix) —
//     mathematical / structural assertions on the trigger predicate
//     `manualPath AND scaledPre > 0 AND whole == 0`. The trigger is purely a
//     function of (scaledPre, seed); we verify via the `LootboxBernoulliTester`
//     contract that the math holds at boundary AND under randomized seed sweep.
//   - TST-WX-02 (auto-resolve always-skip) — source-level structural assertion
//     that the consolation `mintPrize` + `LootBoxWwxrpReward` emit sit INSIDE
//     the manual-branch `if (index != type(uint48).max)` gate.
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

    it("[01c] source: consolation emit only reachable when `whole == 0` (in `else` of `if (whole != 0)`)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Find consolation emit; walk backward to find the enclosing `else`.
      const consolationEmit = source.indexOf(
        "emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(consolationEmit).to.be.greaterThan(-1);
      // Within 1200 chars preceding the emit, an `else {` must appear (the
      // false-branch of the `if (whole != 0)` gate). The NatSpec comment in
      // the `else` branch widens the gap so we use a generous window.
      const window = source.slice(Math.max(0, consolationEmit - 1200), consolationEmit);
      expect(window.includes("if (whole != 0)"), "missing `if (whole != 0)` ancestor").to.equal(true);
      expect(window.includes("} else {"), "missing `} else {` for consolation branch").to.equal(true);
    });

    it("[01d] consolation `wwxrp.mintPrize` is gated by the manual-branch predicate (auto-resolve cannot trigger)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const mintPrize = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(mintPrize).to.be.greaterThan(-1);
      // Within 2500 chars preceding the mintPrize call, the manual-branch
      // gate `if (index != type(uint48).max)` must appear (it's the outer
      // structural gate around `if (whole != 0) { ... } else { ... }`).
      // Widened to 2500 to accommodate the NatSpec block + scaledPre snapshot
      // + Bernoulli arithmetic between the gate and the mintPrize call.
      const window = source.slice(Math.max(0, mintPrize - 2500), mintPrize);
      expect(
        window.includes("if (index != type(uint48).max)"),
        "consolation mintPrize not gated by manual-branch predicate"
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

    it("[02b] auto-resolve else-block contains ONLY the `_queueTickets(whole)` call — no consolation/emit (Phase 275 LBX-AR-02 + LBX-AR-03)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Phase 275 hoisted the Bernoulli math to shared scope above the
      // sentinel gate; the auto-resolve branch now calls the same
      // `_queueTickets(player, targetLevel, whole, false)` helper as the
      // manual branch. Locate the auto-resolve callsite as the SECOND
      // occurrence of that line (the first is the manual true-branch).
      const callLine = "_queueTickets(player, targetLevel, whole, false)";
      const firstIdx = source.indexOf(callLine);
      const autoResolveStart = source.indexOf(callLine, firstIdx + 1);
      expect(firstIdx).to.be.greaterThan(-1);
      expect(autoResolveStart).to.be.greaterThan(firstIdx);
      // Within the next 300 chars (covering the rest of the else block), there
      // must be no `mintPrize`, no `LootBoxWwxrpReward`, no `LootboxTicketRoll`.
      // Note: `seed >> 152` IS consumed earlier (in shared scope above the
      // sentinel gate per D-275-HOIST-01) — the auto-resolve else-arm itself
      // contains only the queue call.
      const tail = source.slice(autoResolveStart, autoResolveStart + 300);
      expect(tail.includes("mintPrize"), "auto-resolve must not call mintPrize").to.equal(false);
      expect(tail.includes("LootBoxWwxrpReward"), "auto-resolve must not emit LootBoxWwxrpReward").to.equal(false);
      expect(tail.includes("LootboxTicketRoll"), "auto-resolve must not emit LootboxTicketRoll").to.equal(false);
    });

    it("[02c] ticket-path-not-selected case: when `futureTickets == 0` the outer `if (futureTickets != 0)` guard skips the entire Bernoulli/consolation block", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The outer guard sits at L1020 (v39). Anything inside it requires non-
      // zero scaled pre-Bernoulli.
      const outerGuard = source.indexOf("if (futureTickets != 0)");
      expect(outerGuard).to.be.greaterThan(-1);
      // Manual-branch gate must be inside outer guard.
      const manualGate = source.indexOf("if (index != type(uint48).max)");
      expect(manualGate).to.be.greaterThan(outerGuard);
      // Consolation also inside outer guard.
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
