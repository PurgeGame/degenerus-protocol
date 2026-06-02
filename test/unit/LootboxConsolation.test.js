// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxConsolation.test.js — Phase 274 Wave 2 TST-WX-01..03
//
// WWXRP cold-bust consolation coverage. The contract under test is the
// ticket-collapse block of `_settleLootboxRoll` at
// `contracts/modules/DegenerusGameLootboxModule.sol` (per-roll settle surface):
//
//   _queueTickets(player, rollLevel, whole, false);
//   if (payColdBustConsolation && whole == 0) {
//       wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
//   }
//
// The consolation payout is `wwxrp.mintPrize`, which emits a standard WWXRP
// ERC-20 `Transfer` event (`0x0` -> player); there is no dedicated
// lootbox-WWXRP event. Off-chain, a consolation is distinguished from the
// regular 10%-path WWXRP win by the absence of a same-tx ticket-path emission.
//
// `_queueTickets` is called unconditionally; its `if (quantity == 0) return;`
// early-return absorbs the `whole == 0` cold-bust case silently. The WWXRP
// consolation is paid on the surviving manual lootbox path — `openLootBox` —
// which passes `payColdBustConsolation = true`. It is gated by a dedicated
// `payColdBustConsolation` flag, NOT by `emitLootboxEvent`. The two
// auto-resolve callers (`resolveLootboxDirect`, `resolveRedemptionLootbox`)
// pass `payColdBustConsolation = false`, so cold-bust is silent for them.
// (v47: the BURNIE-lootbox manual caller `openBurnieLootBox` — which also passed
// `payColdBustConsolation = true` while emitting `BurnieLootOpen` — was removed,
// terminal-paradox closure.)
//
// TEST STRATEGY:
//   - TST-WX-01 (cold-bust trigger) + TST-WX-02 (non-trigger predicate matrix) —
//     mathematical / structural assertions on the trigger predicate
//     `payColdBustConsolation AND scaledPre > 0 AND whole == 0`. The Bernoulli
//     outcome is purely a function of (scaledPre, seed); we verify via the
//     `LootboxBernoulliTester` contract that the math holds at boundary AND under
//     randomized seed sweep.
//   - TST-WX-02 (auto-resolve always-skip) — source-level structural assertion
//     that the consolation `mintPrize` call sits INSIDE the
//     `if (payColdBustConsolation && whole == 0)` gate, and that
//     `_queueTickets` is the single unconditional ticket-award callsite.
//   - TST-WX-03 (magnitude assertion) — direct on-chain constant inspection
//     via the LootboxBernoulliTester mirror constants AND source-grep cross
//     check.
//   - TST-WX-04 (behavioral gate coverage) — deployed-contract verification via
//     the `LootboxBernoulliTester.coldBustConsolationFires` mirror of the
//     production gate, driven with each of the four callers' actual flag values.
//     This exercises the `payColdBustConsolation && whole == 0` decision that
//     CR-01 got wrong. (The `openBurnieLootBox` cold-bust case the prior
//     emitLootboxEvent-gated surface silently dropped is moot in v47 — that
//     BURNIE-lootbox caller was removed.)
//
// CROSS-CITES:
//   - D-274-WX-AMOUNT-01 (magnitude equivalence LOOTBOX_WWXRP_CONSOLATION ==
//     LOOTBOX_WWXRP_PRIZE)
//   - D-274-MANUAL-ONLY-01 (consolation fires on the manual paths only)
//   - D-277-CONSOLATION-GATE-01 (cold-bust consolation gating)
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

    it("[01c] source: consolation payout only reachable when `payColdBustConsolation && whole == 0`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The consolation payout is the `wwxrp.mintPrize` call — there is no
      // dedicated lootbox-WWXRP event. Walk backward to find the enclosing gate.
      const consolationMint = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(consolationMint).to.be.greaterThan(-1);
      // The retired LootBoxWwxrpReward event must not appear anywhere.
      expect(
        source.includes("LootBoxWwxrpReward"),
        "the retired LootBoxWwxrpReward event must not appear in the module"
      ).to.equal(false);
      // Within 600 chars preceding the mint, the
      // `if (payColdBustConsolation && whole == 0)` gate must appear — it is the
      // immediate structural ancestor of the consolation `mintPrize` call.
      const window = source.slice(Math.max(0, consolationMint - 600), consolationMint);
      expect(
        window.includes("if (payColdBustConsolation && whole == 0)"),
        "missing `if (payColdBustConsolation && whole == 0)` ancestor"
      ).to.equal(true);
    });

    it("[01d] consolation `wwxrp.mintPrize` is gated by `payColdBustConsolation && whole == 0` (auto-resolve cannot trigger)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const mintPrize = source.indexOf(
        "wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"
      );
      expect(mintPrize).to.be.greaterThan(-1);
      // Within 600 chars preceding the mintPrize call, the
      // `if (payColdBustConsolation && whole == 0)` gate must appear (the NatSpec
      // comment block between the gate and the call widens the gap).
      // Auto-resolve callers pass `payColdBustConsolation = false`, so they never
      // reach the consolation; the surviving manual caller (`openLootBox`) passes
      // `payColdBustConsolation = true` and can trigger it. (v47: the BURNIE-lootbox
      // manual caller `openBurnieLootBox` was removed.)
      const window = source.slice(Math.max(0, mintPrize - 600), mintPrize);
      expect(
        window.includes("if (payColdBustConsolation && whole == 0)"),
        "consolation mintPrize not gated by `payColdBustConsolation && whole == 0`"
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

    it("[02b] ticket award is a single unconditional `_queueTickets` call; the consolation is `payColdBustConsolation`-gated below it", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The sentinel branch is retired: `_queueTickets(player, rollLevel,
      // whole, false)` is a single source site in `_settleLootboxRoll`,
      // reached unconditionally for every path (manual openLootBox + both
      // auto-resolve callers). Its `if (quantity == 0) return;` early-return
      // absorbs the cold-bust case.
      const callLine = "_queueTickets(player, rollLevel, whole, false)";
      const firstIdx = source.indexOf(callLine);
      const secondIdx = source.indexOf(callLine, firstIdx + 1);
      expect(firstIdx, "`_queueTickets(player, rollLevel, whole, false)` callsite not found").to.be.greaterThan(-1);
      expect(
        secondIdx,
        "`_queueTickets(player, rollLevel, whole, false)` must appear at exactly one source site (sentinel-branch duplication retired)"
      ).to.equal(-1);
      // Immediately after the queue call comes the
      // `if (payColdBustConsolation && whole == 0)` consolation gate — the
      // consolation `mintPrize` call is inside it, so auto-resolve callers
      // (payColdBustConsolation = false) never reach it.
      const tail = source.slice(firstIdx, firstIdx + 600);
      expect(
        tail.includes("if (payColdBustConsolation && whole == 0)"),
        "consolation gate `if (payColdBustConsolation && whole == 0)` must follow the queue call"
      ).to.equal(true);
      const mintIdx = tail.indexOf("wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)");
      const gateIdx = tail.indexOf("if (payColdBustConsolation && whole == 0)");
      expect(mintIdx, "consolation mintPrize must sit after the gate").to.be.greaterThan(gateIdx);
    });

    it("[02c] ticket-path-not-selected case: when `scaledTickets == 0` the outer `if (scaledTickets != 0)` guard skips the entire Bernoulli/queue/consolation block", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The outer `if (scaledTickets != 0)` guard wraps the whole Bernoulli
      // collapse + `_queueTickets` + consolation. Anything inside it requires
      // a non-zero scaled pre-Bernoulli ticket count.
      const outerGuard = source.indexOf("if (scaledTickets != 0)");
      expect(outerGuard).to.be.greaterThan(-1);
      // The `_queueTickets` callsite is inside the outer guard.
      const queueCall = source.indexOf("_queueTickets(player, rollLevel, whole, false)");
      expect(queueCall).to.be.greaterThan(outerGuard);
      // The `payColdBustConsolation && whole == 0` consolation gate is inside the
      // outer guard too (it sits immediately below the queue call).
      const consolationGate = source.indexOf("if (payColdBustConsolation && whole == 0)");
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

  describe("TST-WX-04 — behavioral cold-bust gate coverage (deployed-contract; the gate CR-01 got wrong)", function () {
    // The `LootboxBernoulliTester.coldBustConsolationFires` mirror runs the
    // production Bernoulli collapse + the `payColdBustConsolation && whole == 0`
    // gate exactly as `_resolveLootboxCommon` ships it. Each test drives it with
    // the literal `payColdBustConsolation` value the corresponding caller passes.
    //
    // FIXTURE-COVERAGE NOTE: a pure end-to-end fixture driving the real
    // `openBurnieLootBox` entry point to a deterministic `whole == 0` ticket-path
    // cold-bust is infeasible with the current harness — it requires VRF rigging
    // to force the per-resolution seed's bits[152..167] slice, which the
    // `reachOpenableLootbox` lifecycle helper (test/gas/LootboxOpenGas.test.js)
    // does not support (the documented LBX-02 fixture-coverage gap). The closest
    // behavioral coverage the harness supports is this deployed-contract mirror
    // of the gating decision, driven with the four callers' real flag values —
    // it exercises the exact `payColdBustConsolation && whole == 0` branch that
    // CR-01 mis-gated onto `emitLootboxEvent`.
    //
    // The cold-bust seed forces `uint16(seed >> 152) % 100 == 99`, a losing slice
    // for every `frac < 100` — so `scaledPre ∈ (0, 100)` Bernoulli-collapses to
    // `whole == 0`.
    const COLD_BUST_SEED = BigInt(99) << 152n;
    const WARM_SEED = 0n; // slice == 0 — wins for every frac >= 1

    // [04a] openBurnieLootBox cold-bust — REMOVED (v47): the BURNIE-lootbox manual
    // caller `openBurnieLootBox` was removed (terminal-paradox closure). This case
    // exercised the gate decision with payColdBustConsolation=true on behalf of that
    // removed caller; the identical gate decision for the surviving manual caller
    // (openLootBox, also payColdBustConsolation=true) is covered by [04b], so no
    // coverage is lost. Removed-by-design, not skipped.

    it("[04b] openLootBox cold-bust PAYS the consolation — payColdBustConsolation=true ⇒ fires on whole==0", async function () {
      const tester = await deployTester();
      for (const scaledPre of [1, 47, 50, 99]) {
        const fires = await tester.coldBustConsolationFires(
          true,
          scaledPre,
          COLD_BUST_SEED
        );
        expect(
          fires,
          `openLootBox cold-bust at scaledPre=${scaledPre} must PAY the consolation`
        ).to.equal(true);
      }
    });

    it("[04c] auto-resolve cold-bust stays SILENT — payColdBustConsolation=false ⇒ never fires (D-277-AR-SILENT-01)", async function () {
      const tester = await deployTester();
      // resolveLootboxDirect + resolveRedemptionLootbox both pass
      // payColdBustConsolation = false — cold-bust must stay silent for them.
      for (const scaledPre of [1, 47, 50, 99]) {
        const fires = await tester.coldBustConsolationFires(
          false,
          scaledPre,
          COLD_BUST_SEED
        );
        expect(
          fires,
          `auto-resolve cold-bust at scaledPre=${scaledPre} must stay SILENT (payColdBustConsolation=false)`
        ).to.equal(false);
      }
    });

    it("[04d] a warm roll (whole >= 1) never fires the consolation regardless of payColdBustConsolation", async function () {
      const tester = await deployTester();
      for (const payConsolation of [true, false]) {
        for (const scaledPre of [1, 47, 99, 100, 147, 250]) {
          const fires = await tester.coldBustConsolationFires(
            payConsolation,
            scaledPre,
            WARM_SEED
          );
          expect(
            fires,
            `warm roll at scaledPre=${scaledPre}, payColdBustConsolation=${payConsolation} must NOT fire the consolation (whole >= 1)`
          ).to.equal(false);
        }
      }
    });

    it("[04e] the production gate `payColdBustConsolation && whole == 0` is the tester's mirrored decision (drift detector)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // The behavioral tests above are only load-bearing if the tester mirrors
      // the production gate. Assert the production source still gates the
      // consolation on `payColdBustConsolation && whole == 0` — if it drifts,
      // this fails and the tester (LootboxBernoulliTester.coldBustConsolationFires)
      // must be reconciled in lock-step.
      expect(
        source.includes("if (payColdBustConsolation && whole == 0)"),
        "production consolation gate drifted from `payColdBustConsolation && whole == 0` — update LootboxBernoulliTester.coldBustConsolationFires to match"
      ).to.equal(true);
    });
  });
});
