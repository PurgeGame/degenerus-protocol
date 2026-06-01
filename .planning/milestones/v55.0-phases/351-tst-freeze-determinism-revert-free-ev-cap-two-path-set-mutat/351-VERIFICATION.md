---
phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
verified: 2026-05-31T21:52:20Z
status: passed
score: 6/6
overrides_applied: 0
---

# Phase 351: TST Verification Report

**Phase Goal:** Prove the v55 AfKing-in-Game redesign behaviorally correct empirically against the game-resident model — freeze/determinism with the seed using the STAMPED day (TST-01); funded process/open never reverts on well-formed slices + the no-valve form (TST-02); the per-(player,level) 10-ETH EV budget enforced exactly once per open, no double-draw (TST-03); two-path open coexistence + set-mutation + OPEN-E 4-protection (TST-04); the suite NON-WIDENING vs the v54 baseline 20ca1f79, every red BY NAME (TST-05); per-buy + per-open marginal gas under the 16.7M ceiling, GAS-01/02/03 same-results (TST-06). ZERO contracts/*.sol mutation.
**Verified:** 2026-05-31T21:52:20Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | TST-01: Stamp+open yields a byte-identical box independent of open timing/block; seed uses the STAMPED day; differential oracle (afking-vs-human same tuple) | VERIFIED | `test/fuzz/V55FreezeDeterminism.t.sol` (665 lines, 7 functions): `testStampedDayDeterminismOpenAtTwoBlocks`, `testFuzzNoBlockEntropyInTheDraw` (vm.roll/warp/prevrandao perturbed), `testDifferentialAfkingVsHumanOpenSameTuple`+`testFuzzDifferentialAfkingVsHumanOpen` (resolveAfkingBox vs openLootBox byte-identical for same (amount,level,rngWord,score)), `testIndexBindingMidDayAdvanceDoesNotRebind`, `testPreRngStampNotOpenableUntilWordLands`, `testFuzzIndexBindingAdvanceInvariant`. Freeze target is the SEED (keccak256(rngWordByDay[stampDay], player, stampDay, amount)) — the test DOES NOT assert level/baseLevel frozen; the differential is at the SAME live level. Non-vacuous: asserts box materialized (lastOpenedDay flips, LootBoxOpened event). §5 of REGRESSION-BASELINE-v55.md: "7 passing, all Success". TST-01 marked Complete in REQUIREMENTS.md. |
| 2 | TST-02: A funded process/open never reverts on well-formed slices; solvency violation fails loud (class B); game-over routing never blocked (class C) | VERIFIED | `test/fuzz/V55RevertFreeEvCap.t.sol` (710 lines, 11 functions): `testFuzzClassA_FundedSliceNeverReverts` (fuzz amount/claimable-mix), `testClassA_ClaimableSentinelAndMinSkipNeverRevert`, `testClassA_FundedBoxOpenNeverReverts` (class A — 3 functions); `testClassB_StageDebitSolvencyFailsLoud`, `testClassB_WithdrawSolvencyFailsLoud`, `testFuzzClassB_SolvencyAlwaysFailsLoud` (class B: vm.expectRevert on forced claimablePool underflow at the checked uint128 -=); `testClassC_GameOverRoutingUnblockedByStage` (class C). Adapted `KeeperNonBrick.t.sol` carries the reentrancy-rollback + un-brickable-cancel properties. batchPurchase try/catch isolation leg DROPPED (D-351-02, no successor). TST-02 marked Complete. |
| 3 | TST-03: EV-cap drawn exactly once per open; no double-draw vs buy-time path; shared budget; clamp at 10 ETH | VERIFIED | `test/fuzz/V55RevertFreeEvCap.t.sol`: `testEvCapExactlyOnceNoDoubleDraw` (reads lootboxEvBenefitUsedByLevel slot before STAGE stamp + after open → exactly one RMW, no buy-time write for the afking box), `testEvCapSharedBudgetAcrossAfkingAndHuman` (afking open + human open draw from same [player][level+1] map key), `testEvCapClampsAtTenEthNoRevert` (saturates at cap, no revert), `testFuzzEvCapMultiOpenClampedCumulative`. Slot re-derived via forge inspect. TST-03 marked Complete. |
| 4 | TST-04: Two-path open coexistence (no shared mutable-state hazard); set-mutation (swap-pop/tombstone/streak-preserved); OPEN-E 4-protection | VERIFIED | `test/fuzz/V55SetMutationOpenE.t.sol` (519 lines, 10 functions): `testTwoPathOpenCoexistenceNoCrossCorruption` (afking stamp + human lootboxEth open in same fixture state, neither path mutates the other's ledger), `testNoOrphanControlInSetSubOpens`+`testNoOrphanRemovedSubGetsNoBox`+`testNoOrphanGuardLeavesPendingBoxSubUntouchedByStage` (NO-ORPHAN guard: removed sub gets no free box — non-vacuous: control proves box would have materialized), `testStreakNotCorruptedBySwapPop` (scorePlus1 byte-identical to undisplaced control after swap-pop relocation), `testOpenEConsentGateUnapprovedReverts` (consent-gate), `testOpenEDefaultSelfByteIdentical` (default-self), `testOpenENoEscalation`, `testOpenETrustTheSubRevokeDoesNotStop`, `testFuzzOpenEDefaultSelfHoldsUnderOrderings` (fuzz orderings). TST-04 marked Complete. |
| 5 | TST-05: Suite NON-WIDENING vs v54 baseline 20ca1f79; every red BY NAME; REGRESSION-BASELINE-v55.md authored | VERIFIED | `test/REGRESSION-BASELINE-v55.md` (434 lines, 7 sections per v50 format). v54 baseline established EMPIRICALLY (checkout 20ca1f79 + full forge test — the plan's "byte-identical contract tree" premise was wrong, auto-corrected). v54 = 461/148/16; v55 = 603/134/16. The 134 v55-live reds are a strict SUBSET of the 148-name v54 union (live − union == ∅, intersection = 134). 14-name NARROWING (v54 reds FIXED by v55). D-351-01 rewrite map reconciled (11 uncompilable-at-v54 files → their v55 adapted successors, BY NAME + commit). D-351-02 drops listed BY NAME + reason: D1 KeeperBatchAffiliateDeltaAudit (3 tests, c5f600bd), D2 RedemptionStethFallback::test_POOL04 (aad3aad8), D3 KeeperNonBrick 6 tests (49ce1908), D4 RouterWorstCaseGas 7 tests (e334a91a), D5 KeeperLeversAndPacking grep gates (6c69e627). Every D-351-02 drop is from the 11 uncompilable-at-v54 files (zero compilable v54 reds lost). Hardhat: npx hardhat compile EXIT 0 (32 files), DegenerusGame.test.js byte-identical v54→v55. Forge build EXIT 0 (whole tree). FC1-FC6 guards documented in §6. TST-05 marked Complete. |
| 6 | TST-06: Per-buy + per-open marginal under 16.7M ceiling; GAS-02 no-STATICCALL trace; GAS-03 Outcome-A N/A recorded | VERIFIED | `test/gas/V55AfkingGasMarginal.t.sol` (676 lines, 5 functions): `testPerBuyMarginalReportedAsIsVsColdLedgerOracle` (loop-N-divide (gas for N − gas for N−1)/1 via new-day advanceGame() STAGE, asserts << v54 cold-ledger ~120-130k AND < 16.7M * 50); `testPerOpenMarginalIsUniformStampDerivedOpen` (loop-N-divide over N ready stamped boxes via autoOpen, asserts < 16.7M); `testStage50ChunkAndOpenLegFitUnderHardCeiling` (EFFECTIVE_GAS_CEILING = 16_700_000, both legs asserted); `testGas02NoForeignAfkingFundingStaticcallOnProcessAndOpenPath` (no STATICCALL to a foreign address on the process/open hot path — in-context SLOADs confirmed; carve-outs honored); `testGas03OutcomeAClaimablePoolFlushNotExercised` (records GAS-03 N/A under Outcome A). Per-buy marginal INCLUDES 349.2 BURNIE side-effects as-is (not subtracted). RouterWorstCaseGas adapted with 16_700_000 ceiling assertion. KeeperOpenBoxWorstCaseGas reframed onto the afking open. TST-06 marked Complete. |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/fuzz/V55FreezeDeterminism.t.sol` | TST-01 proof (stamped-day determinism + differential oracle) | VERIFIED | 665 lines, 7 test functions, non-vacuous. Contains `resolveAfkingBox` differential. |
| `test/fuzz/V55RevertFreeEvCap.t.sol` | TST-02 (3-class revert-free) + TST-03 (EV-cap exactly-once) | VERIFIED | 710 lines, 11 test functions, fuzzed class-A. Contains `lootboxEvBenefitUsedByLevel`. |
| `test/fuzz/V55SetMutationOpenE.t.sol` | TST-04 (two-path + NO-ORPHAN + streak + OPEN-E 4-prot) | VERIFIED | 519 lines, 10 test functions, fuzz orderings. Contains `swap`, `ORPHAN`, consent-gate tests. |
| `test/gas/V55AfkingGasMarginal.t.sol` | TST-06 marginal harness + GAS-02 no-STATICCALL + GAS-03 N/A | VERIFIED | 676 lines, 5 test functions. Contains `perBuyMarginal`, `16_700_000`. |
| `test/REGRESSION-BASELINE-v55.md` | TST-05 NON-WIDENING ledger vs v54 20ca1f79 | VERIFIED | 434 lines, 7 sections (mirrors v50 format exactly). Contains "net-zero new regression", 44 occurrences of 20ca1f79. All 7 sections confirmed (§1 arithmetic, §2 BY-NAME union, §3 deltas+rewrite-map+drops, §4 flaky cluster, §5 green proofs, §6 net-zero proof+FC guards, §7 scope attestation). |
| `test/fuzz/helpers/DeployProtocol.sol` | Game-resident afking + bingo module deploy; AfKing standalone removed | VERIFIED | Wave 0 (351-01): GameAfkingModule + DegenerusGameBingoModule deployed at ContractAddresses constants. AfKing import removed. DeployCanary alignment guard proves correct nonce positions. |
| `scripts/lib/predictAddresses.js` | DEPLOY_ORDER with GAME_AFKING_MODULE + GAME_BINGO_MODULE, AF_KING dropped | VERIFIED | 351-01 commit 8ce35690. DEPLOY_ORDER + KEY_TO_CONTRACT both updated. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `V55FreezeDeterminism.t.sol` | `DegenerusGameLootboxModule.resolveAfkingBox` vs `openLootBox` | `resolveAfkingBox` byte-identical assertion via real mintBurnie open leg over poked stamp | VERIFIED | Differential uses the REAL mintBurnie open path (no test-only contract entrypoint). Pokes (amount, day, scorePlus1) + rngWordByDay[day] → the genuine _openAfkingBox:901-907 reads them. |
| `V55FreezeDeterminism.t.sol` | corrected freeze target (SEED frozen, level LIVE) | vm.roll/warp/prevrandao perturbation between stamp and open; live level held fixed in differential | VERIFIED | File docstring (lines 11-38) explicitly states: "LEVEL resolves LIVE at open" and "Do NOT assert level frozen". No test asserts targetLevel/baseLevel is frozen across a live level change. |
| `V55RevertFreeEvCap.t.sol` | `_applyEvMultiplierWithCap` via `lootboxEvBenefitUsedByLevel[player][level+1]` | Single RMW at open; buy-time write bypassed | VERIFIED | testEvCapExactlyOnceNoDoubleDraw reads slot before STAGE stamp and after open — the increment happens only once, after the open, never during the stamp. |
| `V55SetMutationOpenE.t.sol` | `GameAfkingModule subscribe / processSubscriberStage swap-pop` | game.subscribe(...,dailyQuantity=0) cancel + advanceGame STAGE | VERIFIED | NO-ORPHAN guard tested on all four orphan paths (re-stamp/cancel-reclaim/evict/funding-kill). Non-vacuous: control proves box WOULD materialize absent the guard. |
| `V55AfkingGasMarginal.t.sol` | `GameAfkingModule processSubscriberStage (buy) + _openAfkingBox/resolveAfkingBox (open)` | loop-N-divide marginal under 16.7M, no-STATICCALL trace | VERIFIED | perBuyMarginal measured (gas for N - gas for N-1)/1. STATICCALL assertion uses vm.startStateDiffRecording. Carve-outs for same-contract delegatecalls honored (quests/affiliate/coinflip/resolveAfkingBox). |
| `test/REGRESSION-BASELINE-v55.md` | whole-tree forge test failing set | live − union == ∅ binding subset gate, 134 ⊆ 148 | VERIFIED | v54 baseline run EMPIRICAL (20ca1f79 checkout + full forge test, 11 uncompilable files sidelined). v55 live = 603/134/16. Set-difference proven empty. |

### Data-Flow Trace (Level 4)

Not applicable — this is a TEST phase. The artifacts are Foundry test files and a markdown ledger. They do not render dynamic data from a backend; they read from on-chain state/events via the Foundry test harness.

### Behavioral Spot-Checks

| Behavior | Evidence | Status |
|----------|----------|--------|
| forge test whole-tree compiles (forge build EXIT 0) | 351-09-SUMMARY.md: "The whole tree COMPILES (forge build EXIT 0 — the milestone proving all 7 Wave-2 adaptations + the Wave-0 fixture landed)" | PASS |
| v55 TST HEAD run = 603/134/16 | REGRESSION-BASELINE-v55.md §1 table; 351-09-SUMMARY.md Net-Zero Verdict table | PASS |
| v55 live failing set − v54 union == ∅ (net-zero) | REGRESSION-BASELINE-v55.md §6: "0 names outside the v54 148-name union. NET-ZERO new regression PROVEN" | PASS |
| git diff 453f8073 HEAD -- contracts/ EMPTY | `git diff --name-only 453f8073 HEAD -- contracts/` executed — no output (empty) | PASS |
| 4 dedicated proof files exist + substantive | All 4 files exist: V55FreezeDeterminism 665L/7 tests, V55RevertFreeEvCap 710L/11 tests, V55SetMutationOpenE 519L/10 tests, V55AfkingGasMarginal 676L/5 tests | PASS |
| Hardhat compile sanity | 351-09-SUMMARY.md: "npx hardhat compile EXIT 0 (Compiled 32 Solidity files)" | PASS |

### Probe Execution

No probe scripts declared or applicable to this documentation/test phase. Step 7c: SKIPPED (no probe-*.sh files declared; phase is test-authoring, not migration/CLI tooling).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TST-01 | 351-04 | Freeze/determinism — stamp+open byte-identical; seed uses stamped day; index-binding across mid-day advance | Complete | V55FreezeDeterminism.t.sol (7 tests, 4 fuzz); 351-04-SUMMARY requirements-completed: [TST-01]; REQUIREMENTS.md: [x] TST-01 |
| TST-02 | 351-05 | Revert-free — no revert on well-formed funded slices; solvency fails loud; gameover unblocked | Complete | V55RevertFreeEvCap.t.sol class A/B/C (11 tests); 351-05-SUMMARY requirements-completed: [TST-02]; REQUIREMENTS.md: [x] TST-02 |
| TST-03 | 351-05 | EV-cap exactly-once, no double-draw, shared budget, clamp ≤10 ETH | Complete | V55RevertFreeEvCap.t.sol (4 EV-cap tests); 351-05 requirements-completed: [TST-03]; REQUIREMENTS.md: [x] TST-03 |
| TST-04 | 351-02 | Two-path coexistence + set-mutation + OPEN-E 4-protection | Complete | V55SetMutationOpenE.t.sol (10 tests); 351-02 requirements-completed: [TST-04]; REQUIREMENTS.md: [x] TST-04 |
| TST-05 | 351-09 | NON-WIDENING vs v54 20ca1f79 baseline, BY NAME, REGRESSION-BASELINE-v55.md | Complete | test/REGRESSION-BASELINE-v55.md (434 lines, 7 sections); 351-09 requirements-completed: [TST-05]; REQUIREMENTS.md: [x] TST-05 |
| TST-06 | 351-08 | Per-buy + per-open marginal under 16.7M; GAS-02 no-STATICCALL; GAS-03 Outcome-A N/A | Complete | V55AfkingGasMarginal.t.sol (5 tests); 351-08 requirements-completed: [TST-06]; REQUIREMENTS.md: [x] TST-06 |

No orphaned requirements: TST-01..06 are all owned by Phase 351 per the ROADMAP traceability table (29/29 requirements mapped).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | No TBD/FIXME/XXX markers found in the 4 proof files | — | — |
| (none) | — | No stub patterns (return null/[]/{}), no hardcoded empty values | — | — |

Debt marker gate: no unreferenced TBD/FIXME/XXX found in any phase-modified file.

### Human Verification Required

None. All TST-01..06 properties are verified programmatically via forge test (the empirical proofs are the test suite itself). The Foundry whole-tree run (603/134/16) is the authoritative gate — no human visual/UX/real-time verification is needed for a test-only phase.

### Gaps Summary

No gaps. All 6 TST requirements are delivered, the proof files are substantive and wired, the NON-WIDENING ledger is empirically grounded, and zero contracts were mutated.

---

## Phase-Level Critical Checks

### Corrected Freeze Target Compliance

The CONTEXT ⚠ warning about the corrected freeze target is respected correctly:

- `V55FreezeDeterminism.t.sol` docstring (lines 11-38) explicitly states the LEVEL resolves LIVE at open (matching `resolveLootboxDirect`/human `openLootBox`) and the freeze target is the SEED: `keccak256(abi.encode(rngWordByDay[stampDay], player, stampDay, amount))`.
- The determinism test perturbs `vm.roll`/`vm.warp`/`vm.prevrandao` between the two opens **while holding the live level fixed** (a sub-day warp), proving seed freeze in isolation.
- The differential (`_runDifferential`) compares afking-vs-human **at the same live level** — it does NOT assert `targetLevel` is frozen across a live level change.
- The 4-field stamp (`scorePlus1(16) + amount(96) + lastAutoBoughtDay(32) + lastOpenedDay(32)`) matches `DegenerusGameStorage.sol:1867`; the 5-field stamp (with `baseLevelPlus1`) mentioned in earlier CONTEXT was superseded by 349.1 (which DROPPED `_afkingEpoch`/`index`). The test correctly targets the COMMITTED stamp shape.

### NON-WIDENING Empirical Derivation

The plan's implicit assumption that the v54 contract tree is byte-identical to the v55 tree was WRONG (the v54→v55 step IS the AfKing dissolution — 13 contract files differ). The executor correctly auto-fixed this by establishing the v54 baseline EMPIRICALLY (checkout `20ca1f79` + full `forge test --json` with the 11 uncompilable files sidelined). This is the correct method, the plan itself offered it "for rigor," and the intent (net-zero vs v54) is fully honored. The strongest possible non-widening position results: those 11 files contributed ZERO compilable v54 reds, so no baseline red could have been lost by the wholesale rewrite or the D-351-02 drops.

### ZERO Contract Mutation Confirmed

`git diff --name-only 453f8073 HEAD -- contracts/` produces no output (empty). Verified directly. The IMPL subject (`contracts/` at `453f8073`) is frozen throughout this phase.

---

_Verified: 2026-05-31T21:52:20Z_
_Verifier: Claude (gsd-verifier)_
