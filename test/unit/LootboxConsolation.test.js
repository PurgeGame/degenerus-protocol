// SPDX-License-Identifier: AGPL-3.0-only
// Consolation arithmetic and source gate checks; tester methods are mathematical mirrors.
// Protocol settlement/ID credit execution is covered by LootboxOpenGoldens and BoxResolutionIds.

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
      // uint32(seed >> 224) % 100 = 99 (slice >= every possible frac < 100).
      const seed = BigInt(99) << 224n;
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
      // Warm scenarios: seed forces uint32(seed >> 224) % 100 = 0 (slice < every
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
      // The consolation payout ACCUMULATES into `acc.wwxrp` here (box-order rework:
      // rewards settle once per entry) — there is no dedicated lootbox-WWXRP event,
      // and no per-box mint anymore. Walk backward to find the enclosing gate.
      const consolationMint = source.indexOf(
        "acc.wwxrp += _boxWwxrpStake(rollAmount);"
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


  });

  describe("TST-WX-02 — non-trigger predicate matrix", function () {
    it("[02a] whole >= 1 case: scaledPre=100..200 + frac=0 ⇒ whole >= 1, no consolation", async function () {
      const tester = await deployTester();
      // Whole multiples never trigger consolation regardless of seed.
      for (const scaledPre of [100, 200, 247, 300, 9999]) {
        for (const seed of [0n, BigInt(99) << 224n, BigInt(50) << 224n]) {
          const [whole, _roundedUp] = await tester.bernoulliWhole(scaledPre, seed);
          expect(
            whole,
            `whole must be >= 1 at scaledPre=${scaledPre}, seed=${seed.toString(16)}`
          ).to.be.gte(1n);
        }
      }
    });

    it("[02b] ticket award is a single unconditional `_queueEntries` call (flushed once per entry); the consolation accumulation is `payColdBustConsolation`-gated in the per-roll settle function", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Box-order rework: `_queueEntries` moved out of the per-roll
      // `_settleLootboxRoll` into `_flushBoxAcc`, which flushes the accumulated
      // per-level tallies ONCE per entry (reached unconditionally for every
      // caller — manual openBox + both auto-resolve callers — its own
      // `if (whole != 0)` per-lane guard absorbs an all-cold-bust entry).
      const callLine =
        "_queueEntries(id, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)";
      const firstIdx = source.indexOf(callLine);
      const secondIdx = source.indexOf(callLine, firstIdx + 1);
      expect(firstIdx, "`_queueEntries(id, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)` callsite not found").to.be.greaterThan(-1);
      expect(
        secondIdx,
        "`_queueEntries(id, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)` must appear at exactly one source site (sentinel-branch duplication retired)"
      ).to.equal(-1);
      expect(
        source.indexOf("function _flushBoxAcc("),
        "`_flushBoxAcc` must exist"
      ).to.be.greaterThan(-1);
      // Separately: the consolation ACCUMULATION (not the flush) is
      // `payColdBustConsolation`-gated inside `_settleLootboxRoll` — auto-resolve
      // callers (payColdBustConsolation = false) never add to `acc.wwxrp`, so
      // the shared flush in `_flushBoxAcc` is a no-op for them.
      const accLine = "acc.wwxrp += _boxWwxrpStake(rollAmount);";
      const accIdx = source.indexOf(accLine);
      expect(accIdx, "`acc.wwxrp += _boxWwxrpStake(rollAmount);` callsite not found").to.be.greaterThan(-1);
      const gateWindow = source.slice(Math.max(0, accIdx - 600), accIdx);
      expect(
        gateWindow.includes("if (payColdBustConsolation && whole == 0)"),
        "consolation gate `if (payColdBustConsolation && whole == 0)` must precede the accumulation"
      ).to.equal(true);
      const flushLine = "if (acc.wwxrp != 0) wwxrp.creditPrize(id, acc.wwxrp);";
      expect(
        source.includes(flushLine),
        "the per-entry WWXRP flush site must exist"
      ).to.equal(true);
    });

    it("[02c] ticket-path-not-selected case: when `scaledWholeTickets == 0` the outer `if (scaledWholeTickets != 0)` guard skips the Bernoulli collapse + ticket accumulation + consolation accumulation", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Box-order rework: the outer `if (scaledWholeTickets != 0)` guard (inside
      // `_settleLootboxRoll`) wraps the Bernoulli collapse, the per-level ticket
      // accumulation (`acc.tickets[...]`), AND the consolation accumulation
      // (`acc.wwxrp += ...`) — anything inside it requires a non-zero scaled
      // pre-Bernoulli ticket count. The actual `_queueEntries` flush moved out
      // to `_flushBoxAcc` (reached unconditionally later), but a zero-tier
      // never populates `acc.tickets[i]`, so `_flushBoxAcc`'s own
      // `if (whole != 0)` per-lane guard skips queuing for it — same net
      // effect, different mechanism.
      const outerGuard = source.indexOf("if (scaledWholeTickets != 0)");
      expect(outerGuard).to.be.greaterThan(-1);
      const guardWindow = source.slice(outerGuard, outerGuard + 3000);
      const consolationGate = guardWindow.indexOf("if (payColdBustConsolation && whole == 0)");
      expect(
        consolationGate,
        "consolation gate must sit inside the outer `scaledWholeTickets != 0` guard"
      ).to.be.greaterThan(-1);
      const accLine = guardWindow.indexOf(
        "acc.wwxrp += _boxWwxrpStake(rollAmount);",
        consolationGate
      );
      expect(
        accLine,
        "consolation accumulation must sit inside the outer guard, after its own gate"
      ).to.be.greaterThan(consolationGate);
      // The `_flushBoxAcc` queue call must exist, but is intentionally NOT
      // inside this guard — it lives in a different function, gated instead by
      // its own per-lane `if (whole != 0)`.
      expect(
        source.includes("_queueEntries(id, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)"),
        "the per-entry `_queueEntries` flush callsite must exist"
      ).to.equal(true);
    });

    it("[02d] WWXRP spins retain fractional stake; cold-bust consolation uses the whole-token helper", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      // Both WWXRP magnitudes derive from the same helper, so they are equal by
      // construction at equal roll value. The spin sits in `_resolveLootboxRoll`
      // (param `amount`); the consolation sits in `_settleLootboxRoll` (param
      // `rollAmount`) — each passes the roll amount its own frame carries.
      expect(
        /_callWwxrpSpin\(\s*id,\s*_boxWwxrpSpinStake\(amount\)/.test(source),
        "the standard WWXRP win must stake `_boxWwxrpStake(amount)` via `_callWwxrpSpin`"
      ).to.equal(true);
      expect(
        source.includes("acc.wwxrp += _boxWwxrpStake(rollAmount);"),
        "the cold-bust consolation must accumulate `_boxWwxrpStake(rollAmount)`"
      ).to.equal(true);
      // Neither site may re-introduce a flat magnitude that ignores box size.
      expect(
        /_callWwxrpSpin\(\s*id,\s*LOOTBOX_WWXRP_PRIZE\b/.test(source),
        "the WWXRP spin must not stake a flat constant"
      ).to.equal(false);
    });
  });

  describe("TST-WX-03 — magnitude assertion (`_boxWwxrpStake`: 500 WWXRP per ETH, floored at one whole token)", function () {
    it("[03a] tester mirror scales at 500 WWXRP per ETH — 5 WWXRP per 0.01 ETH of roll value", async function () {
      const tester = await deployTester();
      for (const [eth, expected] of [
        ["0.01", "5"],
        ["0.09", "45"],
        ["0.45", "225"],
        ["1", "500"],
        ["49.5", "24750"],
      ]) {
        expect(
          await tester.boxWwxrpStake(hre.ethers.parseEther(eth)),
          `stake at ${eth} ETH roll`
        ).to.equal(BigInt(expected));
      }
    });

    it("[03b] tester mirror preserves the one-token minimum spin stake", async function () {
      const tester = await deployTester();
      const oneToken = 1n;
      // Below 0.002 ETH the ×500 scaling would fall under one token; the floor holds
      // it at exactly one WWXRP. The floor sizes the token spin; it grants no whale pass.
      for (const eth of ["0", "0.0000001", "0.0005", "0.001", "0.0019"]) {
        expect(
          await tester.boxWwxrpStake(hre.ethers.parseEther(eth)),
          `floor at ${eth} ETH roll`
        ).to.equal(oneToken);
      }
      // 0.002 ETH is the exact crossover — scaling takes over at and above it.
      expect(await tester.boxWwxrpStake(hre.ethers.parseEther("0.002"))).to.equal(oneToken);
      expect(
        await tester.boxWwxrpStake(hre.ethers.parseEther("0.003"))
      ).to.equal(1n);
    });

    it("[03c] production module declares the ratio and the floor, and the helper applies both", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      expect(
        source.match(/uint256 private constant LOOTBOX_WWXRP_PRIZE\s*=\s*1;/),
        "LOOTBOX_WWXRP_PRIZE = 1 declaration missing"
      ).to.not.be.null;
      expect(
        source.match(/uint256 private constant LOOTBOX_WWXRP_PER_ETH\s*=\s*500;/),
        "LOOTBOX_WWXRP_PER_ETH = 500 declaration missing"
      ).to.not.be.null;
      expect(source.includes("return _boxWwxrpSpinStake(amount) / TOKEN_MATH_SCALE;")).to.equal(true);
      // The helper must both scale and floor — dropping either half is the drift
      // this catches (an unfloored stake changes the smallest boxes' token payouts).
      expect(
        source.includes("stake = amount * LOOTBOX_WWXRP_PER_ETH;"),
        "`_boxWwxrpStake` must scale by LOOTBOX_WWXRP_PER_ETH"
      ).to.equal(true);
      expect(
        source.includes("if (stake < LOOTBOX_WWXRP_PRIZE * TOKEN_MATH_SCALE) stake = LOOTBOX_WWXRP_PRIZE * TOKEN_MATH_SCALE;"),
        "`_boxWwxrpStake` must floor at LOOTBOX_WWXRP_PRIZE"
      ).to.equal(true);
    });


  });

  describe("TST-WX-04 — behavioral cold-bust gate coverage (deployed-contract; the gate CR-01 got wrong)", function () {
    // The `LootboxBernoulliTester.coldBustConsolationFires` mirror runs the
    // production Bernoulli collapse + the `payColdBustConsolation && whole == 0`
    // gate exactly as `_resolveLootboxCommon` ships it. Each test drives it with
    // the literal `payColdBustConsolation` value the corresponding caller passes.
    //
    // FIXTURE-COVERAGE NOTE: a pure end-to-end fixture driving the real
    // `openFlipLootBox` entry point to a deterministic `whole == 0` ticket-path
    // cold-bust is infeasible with the current harness — it requires VRF rigging
    // to force the per-resolution seed's bits[224..255] slice, which the
    // `reachOpenableLootbox` lifecycle helper (test/gas/LootboxOpenGas.test.js)
    // does not support (the documented LBX-02 fixture-coverage gap). The closest
    // behavioral coverage the harness supports is this deployed-contract mirror
    // of the gating decision, driven with the four callers' real flag values —
    // it exercises the exact `payColdBustConsolation && whole == 0` branch that
    // CR-01 mis-gated onto `emitLootboxEvent`.
    //
    // The cold-bust seed forces `uint32(seed >> 224) % 100 == 99`, a losing slice
    // for every `frac < 100` — so `scaledPre ∈ (0, 100)` Bernoulli-collapses to
    // `whole == 0`.
    const COLD_BUST_SEED = BigInt(99) << 224n;
    const WARM_SEED = 0n; // slice == 0 — wins for every frac >= 1

    // [04a] openFlipLootBox cold-bust — REMOVED (v47): the FLIP-lootbox manual
    // caller `openFlipLootBox` was removed (terminal-paradox closure). This case
    // exercised the gate decision with payColdBustConsolation=true on behalf of that
    // removed caller; the identical gate decision for the surviving manual caller
    // (openBox, also payColdBustConsolation=true) is covered by [04b], so no
    // coverage is lost. Removed-by-design, not skipped.

    it("[04b] openBox cold-bust PAYS the consolation — payColdBustConsolation=true ⇒ fires on whole==0", async function () {
      const tester = await deployTester();
      for (const scaledPre of [1, 47, 50, 99]) {
        const fires = await tester.coldBustConsolationFires(
          true,
          scaledPre,
          COLD_BUST_SEED
        );
        expect(
          fires,
          `openBox cold-bust at scaledPre=${scaledPre} must PAY the consolation`
        ).to.equal(true);
      }
    });

    it("[04c] auto-resolve cold-bust stays SILENT — payColdBustConsolation=false ⇒ never fires (D-277-AR-SILENT-01)", async function () {
      const tester = await deployTester();
      // Direct recirculation passes
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


  });
});
