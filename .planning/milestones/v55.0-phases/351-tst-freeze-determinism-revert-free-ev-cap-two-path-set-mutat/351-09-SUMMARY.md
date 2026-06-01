---
phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
plan: 09
subsystem: testing
tags: [foundry, regression-baseline, non-widening, by-name, v54-baseline, empirical-derivation, forge-test, hardhat-sanity, afking-in-game, net-zero]

# Dependency graph
requires:
  - phase: 351-02
    provides: "the adapted AfKing* corpus (Concurrency/Subscription/FundingWaterfall) + V55SetMutationOpenE — the §3a rewrite-map entries + the TST-04 green proofs"
  - phase: 351-03
    provides: "the adapted Keeper* reward/router/faucet corpus — the §3a rewrite-map entries"
  - phase: 351-04
    provides: "V55FreezeDeterminism (TST-01) + the adapted RngLockDeterminism — the A9 StakedStonkRedemption carried-forward baseline red BY NAME"
  - phase: 351-05
    provides: "V55RevertFreeEvCap (TST-02/03) + the adapted KeeperNonBrick — the D-351-02 batchPurchase-isolation 6-test drop"
  - phase: 351-06
    provides: "the D-351-02 whole-file KeeperBatchAffiliateDeltaAudit drop + the RedemptionStethFallback POOL-04(d) custody-recovery-leg drop, BY NAME"
  - phase: 351-07
    provides: "the adapted *Gas corpus (RouterWorstCaseGas/KeeperLeversAndPacking/KeeperResolveBetWorstCaseGas/SweepPerPlayerWorstCaseGas) — the §3a rewrite-map + the RouterWorstCaseGas 7-test + KeeperLeversAndPacking grep-gate D-351-02 drops"
  - phase: 351-08
    provides: "V55AfkingGasMarginal (TST-06) + the reframed KeeperOpenBoxWorstCaseGas — the final additive-green proofs"
  - phase: 349.2
    provides: "the frozen 453f8073 v55 contract subject (the AfKing-in-Game dissolution under test)"
provides:
  - "test/REGRESSION-BASELINE-v55.md — the authoritative NON-WIDENING BY-NAME regression ledger vs the v54 20ca1f79 baseline (7-section v50 format)"
  - "The EMPIRICALLY-established v54 20ca1f79 baseline red union (461/148/16, 11 uncompilable afking/keeper files sidelined) — the v55.0 ceiling"
  - "The binding net-zero proof: the v55 TST-HEAD live failing set (134 names) is a strict subset of the v54 148-name union (v55 - v54 == EMPTY; 14 NARROWING fixes red->green)"
  - "The Hardhat sanity confirmation (npx hardhat compile EXIT 0; DegenerusGame.test.js byte-identical v54->v55 with the afking methods already absent at v54)"
affects: ["352 TERMINAL (the delta-audit consumes this NON-WIDENING ledger as the regression gate)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Empirical v54-baseline derivation under a CHANGED contract tree: when the prior milestone (v54->v55) changed contracts (here the AfKing dissolution), the baseline red union is NOT doc-carried byte-identical — it is established by `git checkout 20ca1f79` + `node patchForFoundry.js` + a WHOLE-TREE `forge test --json` (node_modules persists, gitignored), then a return to HEAD"
    - "The uncompilable-baseline sideline harness: 11 v54 test files hard-error at 20ca1f79 (afKing.poolOf / de-custody API the v54 AfKing never exposed) — sideline ONLY genuine compiler errors (the `Compiler run failed:` banner, never a lint warning) until the tree builds, so the rest of the v54 tree yields its red set; those 11 files contributed ZERO compilable v54 reds (the strongest non-widening position)"
    - "The NON-WIDENING gate is a BY-NAME subset (live - union == EMPTY), computed by set-difference over the two forge --json failing (suite::test) sets — never a bare count; the 14-name `v54 - v55` slack is the NARROWING (v54 reds the v55 adaptation FIXED), proven red->green per-name"
    - "Frozen-subject discipline through the baseline detour: ContractAddresses.sol is restored byte-identical (sha256 80fe0dac) after EVERY patchForFoundry round-trip (the v55 HEAD run, the v54 baseline run, and the Hardhat compile), keeping git diff 453f8073 HEAD -- contracts/ EMPTY throughout"

key-files:
  created:
    - "test/REGRESSION-BASELINE-v55.md"
    - ".planning/phases/351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat/351-09-SUMMARY.md"
  modified: []

key-decisions:
  - "The plan's premise that `git diff 20ca1f79 HEAD -- contracts/` is EMPTY (byte-identical contract tree) is FACTUALLY WRONG — the v54->v55 step IS the AfKing dissolution (13 contract files differ: AfKing.sol present-at-v54/deleted-at-v55, GameAfkingModule.sol new-at-v55). So the v54 baseline red union was established EMPIRICALLY (checkout 20ca1f79 + full forge run), NOT doc-carried. The plan's INTENT (NON-WIDENING vs the v54 20ca1f79 baseline) is honored exactly; only the derivation method changed to match reality."
  - "The v54 20ca1f79 baseline itself does NOT cleanly compile its full test tree — exactly 11 afking/keeper/redemption/gas files hard-error (referencing afKing.poolOf and the de-custody API the v54 AfKing never exposed). These 11 are precisely the files v55 ADAPTED or DROPPED. They contributed ZERO compilable v54 reds — so the wholesale rewrite + the D-351-02 drops could not lose a single PASSING-or-RED v54 test (there were none to lose in those files). Recorded as the §2 NOTE + FC6."
  - "The binding gate is the BY-NAME SUBSET direction (live - union == EMPTY), relaxed from v49 strict-equality for the unseeded DegeneretteBet.inv cluster (§4) AND the v55 NARROWING (§3c). 134 v55-live reds subset of the 148-name v54 union; intersection = 134; 0 names outside. NET-ZERO new regression PROVEN."
  - "The Hardhat sanity arm is satisfied at the COMPILE level (npx hardhat compile EXIT 0, 32 files) + the byte-identity proof (DegenerusGame.test.js is byte-identical v54->v55, and its three referenced afking methods — afKingModeFor/deactivateAfKingFromCoin/syncAfKingLazyPassFromCoin — were ALREADY absent at the v54 baseline). A full Hardhat run is impractical here (the runner recompiles all contracts per test case — a pre-existing env trait that hits the afking-DECOUPLED Icons32Data identically, persists under --no-compile). There is NO v55-introduced ABI break to adapt; the Foundry whole-tree run is the authoritative ledger (CONTEXT Discretion)."
  - "TST-05 MARKED COMPLETE — this plan owns it (the REGRESSION-BASELINE-v55.md NON-WIDENING BY-NAME ledger is authored, the v54 baseline established, the rewrite map + the D-351-02 drops reconciled BY NAME, the net-zero gate proven, the Hardhat sanity confirmed)."

patterns-established:
  - "When a milestone's prior baseline shares NO frozen contract tree with HEAD, the NON-WIDENING ledger MUST establish the baseline empirically (checkout + run) — a doc-carry would silently assume an identity that does not hold and could hide a real widening behind a changed-tree's different red set."

requirements-completed: [TST-05]

# Metrics
duration: 95min
completed: 2026-05-31
---

# Phase 351 Plan 09: REGRESSION-BASELINE-v55.md — the NON-WIDENING BY-NAME Ledger (TST-05) Summary

**Authored `test/REGRESSION-BASELINE-v55.md` (the v50 7-section format, mirrored EXACTLY) and ran the authoritative whole-tree `forge test` at the v55 TST HEAD to prove NET-ZERO new regression vs the v54 baseline `20ca1f79`. Discovered the plan's "byte-identical contract tree" premise is wrong — the v54→v55 step IS the AfKing dissolution — so established the v54 baseline red union EMPIRICALLY (checkout `20ca1f79` → patch → full `forge test --json` with the 11 uncompilable afking/keeper files sidelined → return to HEAD): v54 = 461/148/16. The v55 TST HEAD = 603/134/16, and the binding BY-NAME gate HOLDS: the 134 live reds are a strict SUBSET of the 148-name v54 union (`v55 − v54 == ∅`; intersection = 134; the 14-name `v54 − v55` slack is the NARROWING — v54 reds the v55 adaptation FIXED red→green, never a new red). Reconciled the wholesale D-351-01 rewrite map + every D-351-02 removed-surface drop BY NAME + reason. Confirmed the Hardhat sanity arm (compile EXIT 0; the one afking-referencing suite byte-identical v54→v55 with the methods already absent at v54). ZERO `contracts/*.sol` mutation throughout (incl. the baseline detour — `ContractAddresses.sol` restored byte-identical sha256 `80fe0dac…` after every patch).**

## Performance

- **Duration:** ~95 min
- **Completed:** 2026-05-31
- **Tasks:** 3
- **Files:** 1 created (`test/REGRESSION-BASELINE-v55.md`, 434 lines) + this SUMMARY

## Accomplishments

- **The authoritative whole-tree `forge test` at the v55 TST HEAD is captured: 603 passed / 134 failed / 16 skipped (753 run).** The WHOLE tree COMPILES (`forge build` EXIT 0 — the milestone proving all 7 Wave-2 adaptations + the Wave-0 fixture landed; a scoped run would hide a new red in an un-adapted file). Every red enumerated BY NAME (suite-basename + testName) from `forge test --json` and bucketed: A (VRF/RNG-window) = 41, B (stale-harness/behavioral) = 92, F (unseeded `DegeneretteBet.inv` flaky cluster) = 1.
- **The v54 `20ca1f79` baseline red union is established EMPIRICALLY = 461 passed / 148 failed / 16 skipped.** Because the plan's "byte-identical contract tree" premise is factually wrong (the v54→v55 step dissolves `AfKing.sol` — 13 contract files differ), the baseline could NOT be doc-carried. Checked out `20ca1f79` (carries `contracts/AfKing.sol`), ran `patchForFoundry.js` + the WHOLE-tree `forge test --json` with the **11 uncompilable afking/keeper/redemption/gas files sidelined** (they hard-error on `afKing.poolOf` / the de-custody API the v54 AfKing never exposed), then returned to HEAD. node_modules persisted (gitignored).
- **The binding NON-WIDENING gate is PROVEN: `v55 live failing set − v54 §2 union == ∅` (0 new regressions).** The 134 v55-live reds are a strict SUBSET of the 148-name v54 union (intersection = exactly 134). The 14-name `v54 − v55` slack is the §3c NARROWING (v54 reds the v55 adaptation FIXED red→green: 4 `RngLockDeterminism` + 3 `KeeperOpenBoxWorstCaseGas` + 4 `KeeperResolveBetWorstCaseGas` + 3 `KeeperLeversAndPacking`), NOT a dropped baseline red.
- **The wholesale D-351-01 rewrite map is reconciled (§3a):** each of the 11 uncompilable-at-v54 afking/keeper files → its v55 adapted successor, with the plan + commit. A renamed/relocated test is a rewrite-map entry (OUT-old + IN-new), never a new red.
- **Every D-351-02 removed-surface DROP is listed BY NAME + reason (§3b):** D1 the WHOLE-FILE `KeeperBatchAffiliateDeltaAudit` (3 tests, `c5f600bd`); D2 `RedemptionStethFallback::test_POOL04_BurnAtGameOverRecoversPool_ZeroPoolTokenSafe` (custody-recovery leg, `aad3aad8`); D3 the 6 `KeeperNonBrick` batchPurchase try/catch-isolation tests (`49ce1908`); D4 the 7 `RouterWorstCaseGas` AfKing cursor/bounty tests (`e334a91a`); D5 the `KeeperLeversAndPacking` batchPurchase grep gates asserted-ABSENT (`6c69e627`). Every drop is of a test that was NOT a compilable v54 baseline red (its source file was among the 11 uncompilable-at-v54) — so the drops cannot mask a lost baseline red.
- **The v55 TST-01..06 green proofs are listed (§5, additive green, contribute zero red):** `V55SetMutationOpenE` (10, TST-04), `V55FreezeDeterminism` (7, TST-01), `V55RevertFreeEvCap` (11, TST-02/03), `V55AfkingGasMarginal` (5, TST-06) = 33 dedicated-proof greens, + the §3a adapted-corpus greens (the bulk of the +142 vs the v54 461 passing).
- **The Hardhat `.test.js` sanity arm is confirmed (§7a):** `npx hardhat compile` → EXIT 0 (Compiled 32 Solidity files) — the v55 contracts compile cleanly under Hardhat. The one Hardhat suite with afking references (`test/unit/DegenerusGame.test.js`) is BYTE-IDENTICAL v54→v55 (`git diff 20ca1f79 HEAD -- test/unit/DegenerusGame.test.js` EMPTY) and references three game methods (`afKingModeFor`/`deactivateAfKingFromCoin`/`syncAfKingLazyPassFromCoin`) that were ALREADY ABSENT at the v54 baseline (0 defs at both HEADs) — so its state is carried-forward, with NO v55-introduced ABI break to adapt.
- **ZERO `contracts/*.sol` mutation** — `git diff 453f8073 HEAD -- contracts/` is EMPTY (committed AND working-tree, before AND after the baseline detour); `ContractAddresses.sol` is restored byte-identical (sha256 `80fe0dac5203db7d241d5f636ca0b67323262476a36713407ed1529f9073afee`) after every `patchForFoundry` round-trip (the v55 HEAD run, the v54 baseline run, the Hardhat compile).

## Task Commits

Each task was committed atomically (test/docs only — no contracts/):

1. **Tasks 1 + 2 + 3: author REGRESSION-BASELINE-v55.md (the whole-tree run + the v54 empirical baseline + the rewrite map + the D-351-02 drops + the net-zero proof + the Hardhat sanity)** — `83a6a9ca` (test)

_Tasks 1, 2, and 3 are one cohesive deliverable: Task 1 (the runs + the empirical v54 baseline) and Task 3 (the Hardhat sanity + the binding-gate validation) are RECORDED INTO Task 2's ledger file (`test/REGRESSION-BASELINE-v55.md`) — there is no separate code artifact for 1 or 3, so they commit together as the single ledger commit. The runs themselves mutate nothing (the patch round-trips restore `ContractAddresses.sol` byte-identical)._

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately.

## Files Created/Modified

- `test/REGRESSION-BASELINE-v55.md` (CREATED, 434 lines) — the NON-WIDENING BY-NAME ledger, mirroring `REGRESSION-BASELINE-v50.md`'s 7-section format EXACTLY: §1 the TST-HEAD arithmetic (v54 461/148/16 → v55 603/134/16 with the +142/−14 reconciliation) + the empirical-derivation note; §2 the 148-name v54 `20ca1f79` baseline union BY NAME, bucketed A(41)/B(92)/F(1), with the 11-uncompilable-file NOTE + the 16-`vm.skip` NOTE; §3 the deltas — (3a) the wholesale D-351-01 rewrite map, (3b) the 5 D-351-02 removed-surface drops BY NAME + reason + commit, (3c) the 14 NARROWING fixes red→green; §4 the unseeded `DegeneretteBet.inv` flaky-cluster ⊆-gate rationale (red at both v54 + v55); §5 the v55 TST-01..06 green proof files (33 dedicated greens) + the requirement→proof map; §6 the net-zero PROOF (`live − union == ∅` BY NAME + the FC1-FC6 false-confidence guards, incl. the v55-specific FC6 for the wholesale rewrite / mis-derived-baseline); §7 the scope attestation + the §7a Hardhat sanity arm.

## Decisions Made

- **The v54 baseline was established EMPIRICALLY, not doc-carried — the plan's "byte-identical contract tree" premise is wrong.** The v54→v55 step IS the AfKing-in-Game dissolution: `git diff 20ca1f79 453f8073 -- contracts/` lists 13 files (`AfKing.sol` present-at-v54/deleted-at-v55, `GameAfkingModule.sol` new-at-v55, `DegenerusGame.sol`, …). The plan's `<critical_constraints>` step 2 asserted "the contract tree is byte-identical, only `test/` + docs changed" — factually false for this milestone. The plan's INTENT (NON-WIDENING vs the v54 `20ca1f79` baseline, every pre-existing red BY NAME) is honored exactly; only the derivation switched to the empirical re-run the plan itself offered "for rigor." The scope guard that matters — `git diff 453f8073 HEAD -- contracts/` EMPTY — holds throughout.
- **The 11 uncompilable-at-v54 files are the strongest non-widening position.** At `20ca1f79`, exactly 11 afking/keeper/redemption/gas test files hard-error (`afKing.poolOf` etc. — the v54 AfKing never exposed that API). They contributed ZERO compilable v54 reds, so the wholesale rewrite (§3a) + the D-351-02 drops (§3b) could not lose a single PASSING-or-RED v54 test (there were none in those files to lose). Recorded as the §2 NOTE + the FC6 guard.
- **The binding gate is the BY-NAME SUBSET (`live − union == ∅`), never a count.** 134 ⊆ 148; intersection = 134; 0 names outside. The 14-name `v54 − v55` slack is the §3c NARROWING (v54 reds the v55 adaptation FIXED), proven red→green per-name — the opposite direction from a regression. The strict-equality form is relaxed (v49→v50 precedent) for the unseeded `DegeneretteBet.inv` cluster (§4) + the v55 narrowing.
- **The Hardhat sanity arm is satisfied at the compile level + the byte-identity proof.** `npx hardhat compile` EXIT 0 proves the v55 contracts compile under Hardhat. `DegenerusGame.test.js` is byte-identical v54→v55 and its three referenced afking methods were ALREADY absent at v54 — so there is NO v55-introduced ABI break to adapt (adapting a carried-forward Hardhat state would be out-of-scope rework; the Foundry whole-tree run is the authoritative ledger per CONTEXT Discretion). A full Hardhat run is impractical here (the runner recompiles all contracts per test case — a pre-existing env trait, hits the afking-DECOUPLED `Icons32Data` identically, persists under `--no-compile`).
- **TST-05 MARKED COMPLETE.** This plan owns it (frontmatter `requirements: [TST-05]`); the ledger is authored, the v54 baseline established, the rewrite map + the D-351-02 drops reconciled BY NAME, the net-zero gate proven, the Hardhat sanity confirmed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The plan's baseline-derivation premise (`git diff 20ca1f79 HEAD -- contracts/` EMPTY / byte-identical contract tree) is factually wrong — corrected to an EMPIRICAL baseline run**
- **Found during:** Task 1 (establishing the v54 baseline red union)
- **Issue:** The plan's `<critical_constraints>` step 2 + the `<objective>` assert the v54→v55 contract tree is byte-identical (only `test/` + docs changed), so the baseline could be doc-carried from the v50 ledger. In reality the v54→v55 step IS the AfKing dissolution — `git diff 20ca1f79 453f8073 -- contracts/` lists 13 changed files (`AfKing.sol` deleted, `GameAfkingModule.sol` added, etc.). A doc-carry would have assumed an identity that does not hold and could hide a real widening behind the changed tree's different red set (FC6).
- **Fix:** Established the v54 baseline red union EMPIRICALLY (the path the plan offered "for rigor"): `git checkout 20ca1f79` → `node patchForFoundry.js` → WHOLE-tree `forge test --json` (with the 11 uncompilable files sidelined) → `git checkout main`. Captured 461/148/16. The binding gate is then `v55 live − v54-empirical union == ∅`.
- **Files modified:** none (the runs mutate nothing; the ledger records the result)
- **Verification:** the v54 baseline run completed (461/148/16); the set-difference `v55 − v54 == ∅` proves net-zero; `ContractAddresses.sol` restored byte-identical (sha256 `80fe0dac…`) on return; `git diff 453f8073 HEAD -- contracts/` EMPTY.
- **Committed in:** `83a6a9ca` (recorded in the ledger §1 header + §2 + FC6)

**2. [Rule 3 - Blocking] The v54 `20ca1f79` baseline does not compile its full test tree (11 afking/keeper files hard-error) — sidelined to run the rest**
- **Found during:** Task 1 (the v54 `forge build` at `20ca1f79`)
- **Issue:** Forge compiles the WHOLE tree before any test; at `20ca1f79`, 11 test files (`AfKingConcurrency`, `AfKingFundingWaterfall`, `AfKingSubscription`, `KeeperBatchAffiliateDeltaAudit`, `KeeperFaucetResistance`, `KeeperNonBrick`, `KeeperRewardRoutingSameResults`, `KeeperRouterOneCategory`, `RedemptionStethFallback`, `RouterWorstCaseGas`, `SweepPerPlayerWorstCaseGas`) hard-error on `afKing.poolOf` / the de-custody API the v54 AfKing never exposed — so NO v54 test could run.
- **Fix:** A sideline-and-restore harness (the same idiom 351-02..08 used) — moved ONLY the genuinely-uncompilable files aside (acting solely on the literal `Compiler run failed:` banner, never a lint warning), iterating until the v54 tree built, captured the baseline red set, then restored all 11. These 11 contributed ZERO compilable v54 reds — the cleanest non-widening position (nothing to lose).
- **Files modified:** none on disk after restore (the v54 files are temporary, on a detached checkout; the working tree returned to HEAD clean)
- **Verification:** the v54 tree built EXIT 0 after sidelining exactly 11 files; the baseline run yielded 461/148/16; all 11 restored; the return-to-HEAD working tree is clean except the pre-existing `scope.txt`.
- **Committed in:** `83a6a9ca` (recorded in the ledger §2 NOTE + §3a + FC6)

**Total deviations:** 2 auto-fixed (1 Rule-1 — the wrong baseline-identity premise corrected to an empirical run; 1 Rule-3 blocking — the uncompilable v54 baseline sidelined to run). No architectural changes; no contract edits. **No NEW regression exists** — the net-zero gate HOLDS, so the ledger is correctly marked non-widening.

## Authentication Gates

None.

## Known Stubs

None. The ledger is a records-only markdown document; every figure in it is backed by an empirical run captured this session (the v55 TST-HEAD `forge test --json` 603/134/16, the v54 `20ca1f79` baseline `forge test --json` 461/148/16, the `npx hardhat compile` EXIT 0, the `git diff`/byte-identity proofs). No placeholder or hardcoded-empty value flows to a claim.

## Net-Zero Regression Verdict (for 352 TERMINAL)

| Quantity | Value |
|----------|-------|
| v55 TST HEAD | 603 passed / 134 failed / 16 skipped (753 run) |
| v54 `20ca1f79` baseline (empirical; 11 uncompilable sidelined) | 461 passed / 148 failed / 16 skipped (625 run) |
| `v55 live failing − v54 union` (NEW regression) | **∅ (0 names) — NET-ZERO new regression** |
| `v54 union − v55 live failing` (NARROWING) | 14 names (v54 reds FIXED red→green by the v55 adaptation) |
| intersection (v55 live ⊆ v54 union) | 134 = the whole v55 live set (strict subset) |
| Whole v55 tree compiles | YES (`forge build` EXIT 0) |
| Hardhat sanity | `npx hardhat compile` EXIT 0 (32 files); the afking-referencing suite byte-identical v54→v55 |
| `git diff 453f8073 HEAD -- contracts/` | EMPTY (committed + working-tree) |

## Issues Encountered

- **The plan's baseline-identity premise was wrong** (see Deviation 1) — the v54→v55 step is the AfKing dissolution, so the contract tree is NOT byte-identical and the baseline had to be derived empirically. Surfaced + corrected; the gate still holds net-zero.
- **The v54 `20ca1f79` baseline does not fully compile** (see Deviation 2) — 11 afking/keeper files hard-error; sidelined to run the rest. This is itself a meaningful baseline fact (the v54 corpus was mid-flight broken on the afking surface v55 rewrote).
- **No pretest patch hook** — `patchForFoundry.js` is not auto-invoked; each run requires it first, then `git checkout -- contracts/ContractAddresses.sol` to restore byte-identical (the `.bak`/restore round-trip keeps `contracts/` frozen). Applied at both HEADs + after the Hardhat compile.
- **The Hardhat runner recompiles all contracts per test case** on this machine (a pre-existing env trait — hits the afking-DECOUPLED `Icons32Data` identically, persists under `--no-compile`), making a full Hardhat run impractically slow per-case. The sanity arm is satisfied at the compile level + the byte-identity proof; the Foundry whole-tree run is the authoritative ledger.

## User Setup Required

None.

## Self-Check: PASSED

Created files exist:
- FOUND: `test/REGRESSION-BASELINE-v55.md`
- FOUND: `.planning/phases/351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat/351-09-SUMMARY.md`

Task commit exists:
- FOUND: `83a6a9ca` (the REGRESSION-BASELINE-v55.md ledger)

Scope guard: `git diff --name-only 453f8073 HEAD -- contracts/` = EMPTY (committed AND working-tree); `ContractAddresses.sol` sha256 == frozen baseline `80fe0dac5203db7d241d5f636ca0b67323262476a36713407ed1529f9073afee`; the ledger has all 7 `## N.` sections, 12 net-zero/subset markers, 28 `20ca1f79` references; the binding gate `v55 live (134) − v54 union (148) == ∅` PROVEN net-zero; the Hardhat sanity recorded in §7a.

---
*Phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat*
*Completed: 2026-05-31*
