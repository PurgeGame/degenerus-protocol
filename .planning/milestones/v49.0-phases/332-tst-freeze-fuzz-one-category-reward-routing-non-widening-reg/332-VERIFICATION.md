---
phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
verified: 2026-05-27T18:40:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 332: TST — Freeze Fuzz + One-Category + Reward-Routing + Non-Widening Regression Verification Report

**Phase Goal:** The new keeper-router composition is proven behaviorally correct empirically — the router advance-consume reads only frozen state mid-tx (the `totalFlipReversals` class), no single tx earns more than one category's bounty + the router→game→`creditFlip` path cannot double-pay, `advanceGame` is unrewarded standalone but rewarded via `doWork` (multiplier honored) + the GASOPT micro-opts produce byte-identical results, and the full suite is NON-WIDENING vs the v48.0 baseline — restoring a clean v49.0 regression baseline against the GAS-calibrated constants.
**Verified:** 2026-05-27T18:40:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Router advance-consume reads only FROZEN `totalFlipReversals` mid-tx (byte-identical VRF output under same-tx `doWork`/`autoBuy` perturbation), non-vacuously proven | VERIFIED | `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` in `test/fuzz/RngLockDeterminism.t.sol`; dual non-vacuity: `assertGt(movedReversals, 0)` + differential control run (`controlWord != baselineWord`); passes under default and `FOUNDRY_PROFILE=deep` |
| 2 | No single `doWork()` tx earns more than one category bounty; the router→game→`creditFlip` path cannot double-pay | VERIFIED | `KeeperRouterOneCategory.t.sol` — 5 count proofs (buy/advance/open == 1; bountyEarned==0 skip == 0; NoWork == 0); structural reentrancy grep-attest: single `creditFlip(msg.sender, bountyEarned)` CEI-last, pinned GAME/COINFLIP targets only, zero ETH-push in legs; NO attacker harness (D-01) |
| 3 | `advanceGame` is unrewarded standalone, rewarded via `doWork` with multiplier honored; GASOPT micro-opts produce byte-identical results | VERIFIED | `KeeperRewardRoutingSameResults.t.sol` — 7 tests: standalone count==0 (day still ticks), router count==1 with `mult==6 > mult==2` strictly; mid-day `mult==1` rewarded; gameover `mult==0` unrewarded; `keeperSnapshot` element-by-element equal to N individual reads; owedMap pointer hoist full-drain byte-identical |
| 4 | `degeneretteResolve` pays flat 1 BURNIE/tx (not per-item), ≥3 non-WWXRP gate, revert on no-work, WWXRP excluded, RESULTS byte-identical to per-item path | VERIFIED | `DegeneretteResolveRepeg.t.sol` — 7 tests: case a count==1 AND amount==1e18; case b 1-2 unpaid no revert; case c 0 reverts NoWork(); case d 3 WWXRP-only unpaid; case e mixed paid once; RESULTS-equality value-invariant with `assertGt` non-vacuity; Hardhat stat gate 24 passing / 1 pending (v48 parity) |
| 5 | Full suite is NON-WIDENING vs v48.0 baseline — failing set == exactly 42 v48-baseline reds BY NAME, net-zero new regression | VERIFIED | Live `forge test` whole-tree at HEAD: **666 passed / 42 failed / 17 skipped** (725 run); strict NAME-set equality confirmed: `live − v48_union == ∅` AND `v48_union − live == ∅`; 17 premise-retired reds deleted (commit `8041451d`); 5 `Crank*`→`Keeper*` renames (commit `52452fe1`) proven behavior-neutral |

**Score:** 5/5 truths verified

---

### Phase-Specific Load-Bearing Truth Verification

#### Truth LB-1: NON-WIDENING by NAME (not count)

The live `forge test` run at HEAD `7d59ec16` returns **666 passed / 42 failed / 17 skipped**. Unique failing test names (deduplicated) = 42. Every failing name is in the v48 §2 union (Bucket A + Bucket B + Bucket C). No failing name is outside the union (new regression). No name in the union is missing from the live set (no baseline red silently dropped). `test/REGRESSION-BASELINE-v49.md` §2 carries the 42-name union verbatim, and §6 records the strict set-equality proof.

Spot-checked two B-bucket names that could have been inadvertently introduced: `testRenewalExactlyAtCostFullBurn` (B9) and `testFundingSourceVaultDoesNotInheritExemption` (B10) — both confirmed in `REGRESSION-BASELINE-v48.md §2`.

**Status: VERIFIED**

#### Truth LB-2: Subject byte-frozen

`git diff 4c9f9d9b..HEAD -- contracts/` returns no output. Zero `contracts/*.sol` mutations across all 6 phase plans. All 9 test commits touch only `test/` and `.planning/`. The audit subject is frozen at `63bc16ca` + `4c9f9d9b` exactly as specified.

**Status: VERIFIED**

#### Truth LB-3: TST-01 non-vacuity

`test/fuzz/RngLockDeterminism.t.sol:1867` — `assertGt(movedReversals, 0, "TST-01 non-vacuity: reverseFlip must move totalFlipReversals pre-lock")`. Additionally at line 1923-1926: `controlWord != baselineWord` assertion proves the consumed word genuinely incorporates the frozen read (a no-op perturbation would make controlWord == baselineWord and FAIL the test). Two independent non-vacuity guards; neither can pass vacuously.

**Status: VERIFIED**

#### Truth LB-4: TST-02 structural reentrancy, no attacker harness

`test/fuzz/KeeperRouterOneCategory.t.sol` — only one `contract` declaration: `KeeperRouterOneCategory is DeployProtocol` (line 51). No reentrant mock, no attacker contract. `testDoWorkReentrancyStructurallySafeSourceAttest` uses `_extractFunctionBody` + `_countOccurrences` on comment-stripped source to assert the single CEI-last `creditFlip(msg.sender, bountyEarned)` (count==1 file-wide) and zero ETH-push in the `doWork` legs. The `bountyEarned==0` skip path is proven at line 225-248 (category runs, count==0, no revert). All 9 tests in `KeeperRouterOneCategory` pass (verified by live forge run above).

**Status: VERIFIED**

#### Truth LB-5: TST-05 flat 1-BURNIE/tx specifics

`test/fuzz/DegeneretteResolveRepeg.t.sol`:
- `RESOLVE_FLAT_BURNIE = 1e18` declared at line 77
- Case (a) `testGteThreeNonWwxrpPaysExactlyOneFlat` (line 145): count==1 AND amount==RESOLVE_FLAT_BURNIE asserted
- WWXRP exclusion proven in cases (d) and (e)
- `testResultsEqualityValueInvariant` (line 368): RESULTS byte-identical with `assertGt` non-vacuity
- Hardhat stat gate recorded: 24 passing / 1 pending (v48 parity; the STAT-02 pending is by design)
- All 7 tests pass in live run

**Status: VERIFIED**

#### Truth LB-6: 17 deletions + 5 Crank→Keeper renames

Commit `8041451d`: 4 files, 736 deletions — deletes all 17 enumerated premise-retired reds (9 from CrankFaucetResistance, 2 from CrankLeversAndPacking, 4 from CrankNonBrick, 2 from RngFreezeAndRemovalProofs) plus orphaned helpers/constants.

Commit `52452fe1`: 5 renames at R094-R098 similarity (CrankFaucetResistance→KeeperFaucetResistance, CrankNonBrick→KeeperNonBrick, CrankLeversAndPacking→KeeperLeversAndPacking, CrankOpenBoxWorstCaseGas→KeeperOpenBoxWorstCaseGas, CrankResolveBetWorstCaseGas→KeeperResolveBetWorstCaseGas).

Confirmed: `ls test/fuzz/CrankFaucetResistance.t.sol` → does not exist; `ls test/fuzz/KeeperFaucetResistance.t.sol` → exists. Same pattern for all 5.

`grep -rn Crank test/ --include="*.sol"` (code-level only, excluding comments) returns only `test/fuzz/RngFreezeAndRemovalProofs.t.sol:129: function testCrankBoxOpenStaysPostUnlock()` — the one deliberate retained green survivor per D-07.

`test/REGRESSION-BASELINE-v49.md` §3 records all 17 deletions with per-test re-homing justification; §4 records all 5 renames with the git mv mapping and behavior-neutrality proof. Counts re-verified live.

**Status: VERIFIED**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/fuzz/RngLockDeterminism.t.sol` | Extended with 2 new perturbation classes (cls 9/10) + 3 TST-01 functions | VERIFIED | `N_PERTURB_ACTIONS = 11` at line 160; `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe`, `testAutoOpenBlockedDuringRngLockNoOps`, `testAutoOpenNoMaroonedBoxesAfterUnlock` at lines 1839/1934/1986; passes 4/1 fail/16 skip |
| `test/fuzz/KeeperRouterOneCategory.t.sol` | New TST-02 proof file (9 tests) | VERIFIED | 708 lines; `contract KeeperRouterOneCategory is DeployProtocol`; 9 tests pass in live run |
| `test/fuzz/KeeperRewardRoutingSameResults.t.sol` | New TST-03 proof file (7 tests) | VERIFIED | 712 lines; 7 tests pass in live run |
| `test/fuzz/DegeneretteResolveRepeg.t.sol` | New TST-05 proof file (7 tests) | VERIFIED | 742 lines; 7 tests pass in live run |
| `test/fuzz/KeeperFaucetResistance.t.sol` | Renamed from CrankFaucetResistance, 9 reds deleted | VERIFIED | Exists; original Crank file absent |
| `test/fuzz/KeeperNonBrick.t.sol` | Renamed from CrankNonBrick, 4 reds deleted | VERIFIED | Exists; SAFE-03 / H-CANCEL-SWAP cases preserved |
| `test/gas/KeeperLeversAndPacking.t.sol` | Renamed from CrankLeversAndPacking, 2 reds deleted | VERIFIED | Exists |
| `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | Renamed from CrankOpenBoxWorstCaseGas (pure rename) | VERIFIED | Exists |
| `test/gas/KeeperResolveBetWorstCaseGas.t.sol` | Renamed from CrankResolveBetWorstCaseGas (pure rename) | VERIFIED | Exists |
| `test/REGRESSION-BASELINE-v49.md` | NON-WIDENING gate ledger mirroring v48, 42-name union + 17 deletions + 5 renames | VERIFIED | 358 lines; §1-§7 present; 42-name union carried verbatim; per-suite membership table in §6 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `RngLockDeterminism.t.sol::_perturb` | `AfKing.sol::doWork / autoBuy` | `try afKing.doWork() {} catch` at line 224; `try afKing.autoBuy(0) {} catch` at line 230 | WIRED | Classes 9/10 reachable via `seed % 11` |
| `KeeperRouterOneCategory.t.sol` | `AfKing.sol::doWork (:883-919)` | `vm.recordLogs(); afKing.doWork(); _countCoinflipStakeUpdatedFor(keeper)` | WIRED | All 3 branch proofs drive `doWork()` directly |
| `KeeperRouterOneCategory.t.sol (grep-attest)` | `contracts/AfKing.sol` source | `vm.readFile + _stripComments + _extractFunctionBody + _countOccurrences` | WIRED | Single `creditFlip(msg.sender, bountyEarned)` count==1 verified |
| `KeeperRewardRoutingSameResults.t.sol` | `contracts/DegenerusGame.sol::keeperSnapshot (:2628)` | `game.keeperSnapshot(players)` element-by-element == N individual calls | WIRED | `testKeeperSnapshotEqualsIndividualReads` at line 347 |
| `DegeneretteResolveRepeg.t.sol` | `contracts/DegenerusGame.sol::degeneretteResolve (:1595-1631)` | direct `game.degeneretteResolve(players, betIds)` call; `_keeperCredit(keeper)` log oracle | WIRED | All 7 case functions wired to the live contract |
| `test/REGRESSION-BASELINE-v49.md §2` | `test/REGRESSION-BASELINE-v48.md §2` (42-name union) | verbatim carry-forward by NAME; §6 set-equality proof | WIRED | Live run confirms `live == union` strict equality |

### Data-Flow Trace (Level 4)

Not applicable — this is a pure `test/` + `.planning/` phase. No dynamic data rendered from a live data source; the proof artifacts drive and observe the FROZEN contracts directly. The contracts are not modified.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| TST-01: RngLockDeterminism new functions pass | `forge test --match-contract RngLockDeterminism` | 4 pass / 1 fail (A7 unchanged) / 16 skip | PASS |
| TST-02/03/05: New proof files all green | `forge test --match-contract "KeeperRouterOneCategory\|KeeperRewardRoutingSameResults\|DegeneretteResolveRepeg"` | 23 passed / 0 failed | PASS |
| TST-04: Full suite NON-WIDENING | `forge test` whole tree | 666 passed / 42 failed / 17 skipped | PASS |
| Subject frozen | `git diff 4c9f9d9b..HEAD -- contracts/` | empty (no output) | PASS |
| Crank files absent | `ls test/fuzz/CrankFaucetResistance.t.sol` | No such file | PASS |
| Keeper files present | `ls test/fuzz/KeeperFaucetResistance.t.sol` | exists | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` declared for this phase. TST is a test-authoring + ledger phase; the proof run IS the probe. The whole-tree `forge test` serves as the behavioral gate (see Behavioral Spot-Checks above).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TST-01 | 332-01 | Freeze-invariant fuzz: router advance-consume reads only frozen `totalFlipReversals` | SATISFIED | `RngLockDeterminism.t.sol` +292 lines; commits `a8b93040`+`41a49223`; 3 new functions pass default + deep profile |
| TST-02 | 332-02 | One-category / no-stacking + structural reentrancy attest + default-batch/escapes | SATISFIED | `KeeperRouterOneCategory.t.sol` (708 lines, 9 tests); commit `c7c57376`; no attacker harness (D-01 honored); count proofs (D-02 honored) |
| TST-03 | 332-03 | `advanceGame` unrewarded standalone + rewarded via `doWork` + GASOPT-01/03 same-results | SATISFIED | `KeeperRewardRoutingSameResults.t.sol` (712 lines, 7 tests); commit `e2fff795` |
| TST-04 | 332-05 + 332-06 | Full-suite NON-WIDENING regression vs v48.0 baseline; 17 deletions + oracle migration | SATISFIED | Commits `8041451d`+`52452fe1`+`11d1b1f5`; live run 666/42/17; `REGRESSION-BASELINE-v49.md` authored; SAFE-03/H-CANCEL-SWAP preserved |
| TST-05 | 332-04 | `degeneretteResolve` rename + flat ~1 BURNIE re-peg + ≥3-gate + WWXRP-excluded + RESULTS-equality | SATISFIED | `DegeneretteResolveRepeg.t.sol` (742 lines, 7 tests); commits `6f8bd35a`+`75284aac`; Hardhat stat gate 24 passing / 1 pending (v48 parity) |

All 5 requirements assigned to Phase 332 are SATISFIED. No orphaned requirements (SWEEP-01/02/03 and BATCH-02/03 are Phase 333 items; ROUTER/ADV/GAS/GASOPT requirements are Phase 329-331 items; all accounted for in REQUIREMENTS.md traceability table).

### Anti-Patterns Found

Scanned the 4 new proof files (`RngLockDeterminism.t.sol` extension + `KeeperRouterOneCategory.t.sol` + `KeeperRewardRoutingSameResults.t.sol` + `DegeneretteResolveRepeg.t.sol`) and the 6 modified files (`KeeperFaucetResistance`, `KeeperNonBrick`, `KeeperLeversAndPacking`, `KeeperOpenBoxWorstCaseGas`, `KeeperResolveBetWorstCaseGas`, `RngFreezeAndRemovalProofs`):

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | No `TBD`/`FIXME`/`XXX` debt markers found in any phase-touched file | — | — |

No stub patterns, no placeholder returns, no hardcoded empty data sources in proof-critical paths. The one `TODO`-adjacent pattern — `vm.skip` blocks in `RngLockDeterminism.t.sol` — is the pre-existing v48-baseline gated-deep-fuzz mechanism (not a debt marker; the tests pass under `FOUNDRY_PROFILE=deep`).

### Human Verification Required

No human verification items for this phase. All proofs are Foundry-automated with no visual, UI, or external-service components. The Hardhat stat secondary gate was run and recorded within the execution (24 passing / 1 pending, v48 parity — the `pending` is the `STAT-02` round-trip lifecycle self-soft-skip, documented as by-design).

---

## Scope Attestation

- **Zero `contracts/*.sol` (mainnet) modifications** this phase. `git diff 4c9f9d9b..HEAD -- contracts/` is empty. The audit subject is FROZEN at `63bc16ca` + `4c9f9d9b`.
- **Full `forge test` tree run (NOT `--match-path`)** at the v49 TST HEAD — 666 passed / 42 failed / 17 skipped (725 run).
- **Failing set == the 42 v48.0 union by NAME** — strict set equality, net-zero new regression, zero dropped baseline red.
- **All 5 TST requirements (TST-01..05) satisfied** with substantive, non-vacuous Foundry proofs.
- **CONTEXT D-01/D-02/D-04/D-07 honored**: no attacker harness, count-not-amount oracle, delete-not-repair, de-crank renames.

---

_Verified: 2026-05-27T18:40:00Z_
_Verifier: Claude (gsd-verifier)_
