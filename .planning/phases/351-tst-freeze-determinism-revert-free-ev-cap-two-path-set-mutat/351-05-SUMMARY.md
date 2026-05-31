---
phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
plan: 05
subsystem: testing
tags: [foundry, fuzz, afking, game-resident, revert-free, no-valve, solvency, fail-loud, ev-cap, exactly-once, no-double-draw, gameover, reentrancy, cancel, storage-slots]

# Dependency graph
requires:
  - phase: 351-01
    provides: "the compiling DeployProtocol fixture (GameAfkingModule at GAME_AFKING_MODULE) the revert-free corpus builds on"
  - phase: 351-02
    provides: "the RE-DERIVED game storage slots (_subOf=66, _subscribers=68, _subscriberIndex=69, claimablePool=slot1:off16, afkingFunding=8, mintPacked_=10) + the validated game-resident driving harness (advanceGame STAGE buy / _settleGame VRF drain / _fundPool / _grantDeityPass) + the tandem-claimablePool-credit + single-advance-eviction (PickCharity-dodge) test-infra realities"
  - phase: 351-03
    provides: "the _settleGame VRF-drain donor + the idle-fixture day-saturation reality (one new-day STAGE per fixture)"
  - phase: 351-04
    provides: "the reusable afking-open capture idioms — _pokeAfkingStamp (set an arbitrary (amount,day,score) tuple on an in-set Sub), _settleClean (240-iter robust drain), _setRngWordByDay, _evBenefitUsed (slot 48), the LootBoxOpened decode — ported here for the EV-cap + funded-box-open proofs"
  - phase: 349.2
    provides: "the frozen 453f8073 contract subject (the no-valve _resolveBuy REVERT-01 slice, the checked claimablePool -= solvency debit, the gameover advance leg, resolveAfkingBox's single EV-cap RMW)"
provides:
  - "KeeperNonBrick.t.sol adapted to the game-resident revert-free path (the batchPurchase try/catch-isolation leg DROPPED per D-351-02 with a BY-NAME ledger note; the reentrancy-rollback + un-brickable-cancel + TOMB-04 reclaim/auto-pause-COMMIT + AFSUB-03 mass-eviction properties reframed onto withdrawAfkingFunding/subscribe(_,0)/the STAGE) — 15 tests, 3 fuzz @ 1000 runs"
  - "V55RevertFreeEvCap.t.sol — the dedicated TST-02 (class A revert-free, class B fail-loud-on-solvency, class C gameover-unblocked) + TST-03 (EV-cap exactly-once / no-double-draw / shared-budget / clamp) proofs — 11 tests, 4 fuzz @ 1000 runs"
  - "The trace-confirmed class-B fail-loud at the STAGE debit (advanceGame -> processSubscriberStage -> Panic(0x11)) AND the withdraw tandem release — the SOLVENCY-01 violation propagates, never masked (D-348-04 no try/catch)"
affects: [351-09, "REGRESSION-BASELINE-v55.md (the KeeperNonBrick rewrite map + the 6 dropped batchPurchase-isolation tests BY NAME + reason)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "No-valve no-brick proof shape: REVERT-01 (class A) is the SOLE no-brick guarantor under D-348-04 — a FUNDED well-formed slice is revert-free BY CONSTRUCTION (fuzz amount/claimable-mix/quantity, assert the STAGE stamps every funded sub), there is no try/catch to isolate a poisoned slice, so the proof asserts no-revert (not isolation)"
    - "class-B fail-loud via a forced claimablePool underflow + expectRevert(Panic(0x11)): force claimablePool BELOW the funding (afkingFunding stays >= the debit so the ONLY failing op is the checked uint128 -=), drive the STAGE buy (or the withdraw) -> the checked subtraction reverts; trace-confirm the revert originates in processSubscriberStage (not an unrelated revert) — mitigates the false-GREEN T-351-05-FG #1"
    - "class-C gameover-unblocked: set gameOver, keep an active funded subscriber set present (so the STAGE WOULD have work), advance on a fresh day -> the gameover advance leg returns mult==0 WITHOUT reverting (the STAGE is on the non-gameover new-day path, returned-around at AdvanceModule:192-200) and mintBurnie pays no bounty but does not revert NoWork (the category ran)"
    - "EV-cap exactly-once via the poked-stamp open + the budget read before/after: the poke writes ONLY the Sub slot (never lootboxEvBenefitUsedByLevel), so the budget stays clean through the STAGE stamp (the buy-time EV write is BYPASSED for afking boxes) and is drawn ONCE at open by resolveAfkingBox's single _applyEvMultiplierWithCap RMW; assert the budget increments by exactly adjustedPortion (== amount for amount<=cap)"
    - "shared-budget proof via a deity-passed human buyer: a deity pass yields a 75% activity score (>NEUTRAL), so a real game.purchase lootbox buy by the same player fires the buy-time EV cap draw (MintModule:1298) on the SAME lootboxEvBenefitUsedByLevel[player][level+1] key the afking open used -> the budget is the cumulative sum (afking aAmt then human hAmt), proving one shared budget, non-vacuously"

key-files:
  created:
    - "test/fuzz/V55RevertFreeEvCap.t.sol"
    - ".planning/phases/351-.../351-05-SUMMARY.md"
  modified:
    - "test/fuzz/KeeperNonBrick.t.sol"

key-decisions:
  - "The batchPurchase per-slice try/catch isolation leg is a D-351-02 removed surface (game.batchPurchase does not exist on the v55 game-resident Game — the standalone AfKing batch-buy + BatchBuy event was 349.1 P5 dead-code with NO successor). DROPPED with a BY-NAME ledger note (the 6 tests: testBatchPurchaseIsolatesFailingPlayerAndRefundsSlice / testFuzz_BatchPurchaseFailPositionRefundsAndCompletes / testBatchPurchaseGameOverRejectsWholeBatchAtEntry / testBatchPurchaseRejectsNonKeeperCaller / testKeeperBatchSkipsPoisonedMiddlePlayer / testFuzz_KeeperBatchPoisonPositionNeverBricks + the _driveKeeperBatch/KEEPER_PATH_LANDED machinery). The reentrancy/cancel/reclaim/auto-pause/eviction properties REFRAME (renamed/relocated, NOT removed) and stay."
  - "The class-B fail-loud is asserted at the EXACT plan-specified site — the STAGE debit GameAfkingModule.sol:710 (claimablePool -= uint128(ethValue)). Forcing claimablePool to 0 with afkingFunding[afk] still funded makes the funding check pass and the pool -= the SOLE failing op; the trace confirms the Panic(0x11) originates in advanceGame -> DegenerusGameAdvanceModule::advanceGame -> GameAfkingModule::processSubscriberStage. A SECOND class-B surface (the withdraw tandem release DegenerusGame.sol:1570) is also proven (same invariant, different debit site)."
  - "The EV-cap exactly-once/no-double-draw is proven by reading lootboxEvBenefitUsedByLevel[player][level+1] BEFORE the stamp/open and AFTER the open. The afking arm is reached via the genuine mintBurnie open leg over a POKED in-set Sub stamp (the 351-04 pattern — resolveAfkingBox is internal-only, NOT an external Game stub; a direct call would need a FORBIDDEN contract change). The poke writes ONLY the Sub slot, so the budget is demonstrably 0 through the stamp (no buy-time draw — the buy-time write is bypassed for afking boxes) and drawn ONCE at open."
  - "The shared-budget property uses a deity-passed human buyer so a REAL game.purchase lootbox buy fires the buy-time EV draw (a 75% activity score > NEUTRAL); the budget goes afking aAmt (3 ETH) -> human aAmt+hAmt (7 ETH), proving the afking + human boxes draw the SAME per-level 10-ETH key (equivalent to the v54 per-(sub,level) accumulator). Non-vacuous: if the human draw hadn't fired or keyed differently, the final assert (7 ETH) would fail."
  - "TST-02 + TST-03 MARKED COMPLETE — this plan owns both (frontmatter requirements:[TST-02,TST-03]) and the three revert classes + the EV-cap exactly-once/shared/clamp are all empirically proven, non-vacuously. The class-A funded-slice fuzz that 351-02/03 FED into is now discharged here with the full REVERT-01 + class-B + class-C proof."

patterns-established:
  - "Under a no-valve (D-348-04) design, the no-brick test asserts revert-FREE-by-construction on a FUNDED slice (class A) + fail-LOUD on a forced solvency underflow (class B) — never 'isolation' (there is no valve to isolate). The two are complementary: a funded slice never reverts; a solvency violation always reverts."
  - "To prove a checked-arithmetic fail-loud non-vacuously, force the operand that would underflow BELOW the subtrahend while keeping every upstream check passing, expectRevert(Panic(0x11)), and trace-confirm the revert originates in the target function (not an unrelated guard)."

requirements-completed: [TST-02, TST-03]

# Metrics
duration: 70min
completed: 2026-05-31
---

# Phase 351 Plan 05: Revert-Free / No-Valve No-Brick (TST-02) + EV-Cap Exactly-Once (TST-03) Summary

**Adapted the PRIMARY revert-free corpus `KeeperNonBrick.t.sol` to the game-resident path — dropping the removed `batchPurchase` try/catch-isolation leg (D-351-02, 6 tests BY NAME) and reframing the reentrancy-rollback + un-brickable-cancel + TOMB-04 reclaim/auto-pause-COMMIT + AFSUB-03 mass-eviction properties onto `withdrawAfkingFunding`/`subscribe(_,0)`/the required-path STAGE — and authored the dedicated TST-02 + TST-03 proof `V55RevertFreeEvCap.t.sol`: a FUNDED process STAGE / box open NEVER reverts (REVERT-01 class A, the sole no-brick guarantor under D-348-04's removed valve), a forced `claimablePool` underflow FAILS LOUD with `Panic(0x11)` at the STAGE debit (trace-confirmed `advanceGame -> processSubscriberStage`) AND the withdraw tandem release (class B, never masked), game-over routing PROCEEDS unblocked by the afking STAGE (class C), and the per-`(player,level)` 10-ETH EV-benefit budget is drawn EXACTLY ONCE per open with NO double-draw vs the bypassed buy-time path, from the SAME per-level key a deity-bonus human buy draws (shared budget), hard-clamped at 10 ETH with no revert. 26 tests green in isolation (7 fuzz @ 1000 runs), ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~70 min
- **Completed:** 2026-05-31
- **Tasks:** 3
- **Files:** 1 created (`V55RevertFreeEvCap.t.sol`, 710 lines) + 1 modified (`KeeperNonBrick.t.sol`, 810 lines)
- **Tests:** KeeperNonBrick 15/15 (3 fuzz @ 1000) + V55RevertFreeEvCap 11/11 (4 fuzz @ 1000) = 26 green in isolation; 112/129 in the full Wave-2 corpus run (1 carried-forward A7 baseline red BY NAME, 16 RngLockDeterminism skips)

## Accomplishments

- **TST-02 class A (revert-free-by-construction, REVERT-01)** — `testFundedStageNeverBricks` + `testFuzzClassA_FundedSliceNeverReverts` (1000 runs, fuzzed amount / claimable-mix / quantity 1..3) + `testClassA_ClaimableSentinelAndMinSkipNeverRevert` (the 1-wei claimable sentinel) + `testClassA_FundedBoxOpenNeverReverts`: a FUNDED, well-formed process STAGE / box open never reverts. Under D-348-04 (the per-slice try/catch valve REMOVED) this is the SOLE no-brick guarantor — there is no valve to isolate a poisoned slice, so a funded sub simply CANNOT poison the batch. Non-vacuous: every sub is asserted FUNDED before, and STAMPED (`lastAutoBoughtDay == the process day`) after.
- **TST-02 class B (fail-loud-on-solvency, never masked)** — `testClassB_StageDebitSolvencyFailsLoud` + `testClassB_WithdrawSolvencyFailsLoud` + `testFuzzClassB_SolvencyAlwaysFailsLoud` (1000 runs): a forced `claimablePool` underflow REVERTS with `Panic(0x11)` at the checked `uint128 -=`. The STAGE-debit test forces `claimablePool = 0` with `afkingFunding[afk]` still funded, drives a new-day `advanceGame()`, and the trace confirms the revert originates in `advanceGame -> DegenerusGameAdvanceModule::advanceGame -> GameAfkingModule::processSubscriberStage` (the `:710` debit) — the SOLVENCY-01 violation propagates through the whole advance chain, NEVER swallowed (D-348-04 dropped the try/catch). `expectRevert(Panic(0x11))` targets the underflow specifically (not an unrelated revert).
- **TST-02 class C (terminal-routing-unblocked)** — `testClassC_GameOverRoutingUnblockedByStage`: with `gameOver` set AND an active funded subscriber set present (so the STAGE WOULD have work on a normal day), the advance gameover leg PROCEEDS and returns `mult == 0` WITHOUT reverting (the afking STAGE is on the non-gameover new-day path, returned-around at `AdvanceModule:192-200`), and `mintBurnie()` pays no bounty (`mult == 0`) but does NOT revert `NoWork` (the category ran). The afking STAGE never blocks terminal routing.
- **TST-03 EV-cap exactly-once + no double-draw** — `testEvCapExactlyOnceNoDoubleDraw`: an afking open (the real `mintBurnie` open leg over a poked bonus-score stamp) increments `lootboxEvBenefitUsedByLevel[player][level+1]` by EXACTLY the open's `adjustedPortion` (== `amount` for `amount <= 10 ETH` on a clean budget) in ONE RMW. The budget is asserted CLEAN (0) before AND through the STAGE stamp — the buy-time EV write is BYPASSED for afking boxes (the poke writes only the Sub slot; `DegenerusGameMintModule:1298-1303` is never reached) — and drawn only at open. No double-draw.
- **TST-03 shared budget (afking + human)** — `testEvCapSharedBudgetAcrossAfkingAndHuman`: an afking open draws `aAmt` (3 ETH) into `[p][level+1]`, then a REAL human `game.purchase` lootbox buy by the SAME deity-passed player (a 75% activity score > NEUTRAL fires the buy-time draw at `MintModule:1298`) adds `hAmt` (4 ETH) to the SAME key — the budget is the cumulative 7 ETH, proving one shared per-level 10-ETH budget (equivalent to the v54 per-`(sub,level)` accumulator). Non-vacuous: the budget demonstrably went 0 → 3 → 7 ETH.
- **TST-03 cap clamp (<= 10 ETH, no revert)** — `testEvCapClampsAtTenEthNoRevert` + `testFuzzEvCapMultiOpenClampedCumulative` (1000 runs): with the per-level budget pre-seeded to `cap - 1 ETH`, a 5-ETH bonus open clamps (draws only the remaining 1 ETH), saturating at exactly 10 ETH with NO revert (the no-write 100%-EV short-circuit at `LootboxModule:478-481`). The fuzz proves a multi-open sequence draws the clamped cumulative sum (exactly-once each, `<= cap`).
- **KeeperNonBrick adapted to the game-resident path** — the `batchPurchase` per-slice try/catch isolation leg DROPPED (D-351-02, 6 tests BY NAME + the `_driveKeeperBatch`/`KEEPER_PATH_LANDED` machinery); the reentrancy-rollback (`ReentrantAfkingWithdrawer` re-enters `game.withdrawAfkingFunding` under CEI), un-brickable-cancel (`subscribe(_, 0)` tombstone + `withdrawAfkingFunding`), TOMB-04 reclaim-COMMIT / auto-pause-COMMIT (the STAGE's `SubscriptionExpired(.,2)` / `(.,1)` no-cursor-advance swap-pop), and AFSUB-03 heavy pass-eviction (the single-advance pre-RNG driver to dodge the level-transition `PickCharity` revert) all reframed and green.
- **ZERO `contracts/*.sol` mutation** — `git diff --name-only 453f8073 HEAD -- contracts/` is EMPTY (committed AND working-tree); `ContractAddresses.sol` restored byte-identical after every `patchForFoundry` round-trip.

## Task Commits

Each task was committed atomically (test/ only — no contracts/):

1. **Task 1: adapt KeeperNonBrick — port the harness, drop the batchPurchase isolation leg (D-351-02), reframe reentrancy/cancel** — `49ce1908` (test)
2. **Task 2: author V55RevertFreeEvCap TST-02 — revert-free + fail-loud + gameover-unblocked** — `5e6bf322` (test)
3. **Task 3: TST-03 EV-cap exactly-once — no double-draw vs buy-time, shared budget, clamp** — `2da39d1e` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately.

## Files Created/Modified

- `test/fuzz/V55RevertFreeEvCap.t.sol` (NEW, 710 lines) — the dedicated TST-02 + TST-03 proof. 11 tests (3 unit + class-B-stage/withdraw + class-C + 4 EV-cap unit/fuzz; 4 fuzz @ 1000 runs). Ports `_runStageNewDay`/`_settleGame`/`_settleClean`/`_fundPool`/`_grantDeityPass`/`_pokeAfkingStamp`/`_setRngWordByDay`/`_evBenefitUsed`/the Sub byte offsets/the LootBoxOpened decode from V55FreezeDeterminism + V55SetMutationOpenE; adds `_setClaimablePool`/`_bumpClaimablePool` (the class-B underflow forcing), `_setEvBenefitUsed` (the clamp pre-seed), `_buyHumanBonusBox` (the deity-bonus shared-budget arm). RE-DERIVED slots: `claimablePool=1:16`, `claimableWinnings=7`, `afkingFunding=8`, `mintPacked_=10`, `rngWordByDay=11`, `lootboxEvBenefitUsedByLevel=48`, `_subOf=66`, `_subscribers=68`, `_subscriberIndex=69`.
- `test/fuzz/KeeperNonBrick.t.sol` (MODIFIED, 810 lines) — adapted to the game-resident revert-free path. The `batchPurchase` try/catch-isolation leg DROPPED (D-351-02, the 6 tests + machinery removed; the removed surface noted BY NAME in the docstring for the 351-09 ledger). The harness helpers preserved + re-derived; the reentrancy/cancel/reclaim/auto-pause/eviction/empty-pass properties reframed onto the game-resident withdraw/cancel/STAGE. Non-comment `afKing.` count == 0; `batchPurchase` token count == 0; `AF_KING` token count == 0. 15 tests (3 fuzz @ 1000).

## Decisions Made

- **The `batchPurchase` per-slice try/catch isolation leg is a D-351-02 removed surface — DROPPED with a BY-NAME ledger note.** `game.batchPurchase` does not exist on the v55 game-resident Game (the standalone AfKing batch-buy entrypoint + its `BatchBuy` event was 349.1 P5 dead-code with NO behavioral successor — the per-buy work folded into `advanceGame()`'s required-path STAGE, which is revert-free by construction with no valve to isolate). The 6 dropped tests + the `_driveKeeperBatch`/`KEEPER_PATH_LANDED` machinery are recorded BY NAME in the KeeperNonBrick docstring for `REGRESSION-BASELINE-v55.md` (351-09). Bias = adapt; this is the D-351-02 exception (the entire subject was removed).
- **The reentrancy-rollback + un-brickable-cancel + reclaim/auto-pause-COMMIT + AFSUB-03 properties REFRAME (renamed/relocated, NOT removed).** The reentrancy attacker now re-enters `game.withdrawAfkingFunding` (CEI: the funding debit + tandem `claimablePool` release execute before the `.call`, `DegenerusGame:1568-1571`); cancel is `subscribe(_, dailyQuantity=0)` (the in-place tombstone); the TOMB-04 reclaim/auto-pause COMMIT is the STAGE's `SubscriptionExpired(.,2)`/`(.,1)` no-cursor-advance swap-pop; the AFSUB-03 mass-eviction routes through the tombstone-then-reclaim shape. All preserved, none silent-deleted.
- **class-B fail-loud is asserted at the EXACT plan site (the STAGE debit `:710`) AND a second surface (the withdraw `:1570`).** Forcing `claimablePool = 0` with `afkingFunding[afk]` still funded makes the funding check pass and the `claimablePool -=` the SOLE failing op; the `-vvvv` trace confirms the `Panic(0x11)` originates in `processSubscriberStage`, not an unrelated guard (mitigates the false-GREEN risk T-351-05-FG #1).
- **The EV-cap exactly-once arm is reached via the genuine `mintBurnie` open leg over a poked stamp.** `resolveAfkingBox` is internal-only (NOT an external Game stub); a direct call would need a FORBIDDEN contract change. Poking the in-set Sub's `(amount, scorePlus1, lastAutoBoughtDay, lastOpenedDay)` + `rngWordByDay[day]` feeds the genuine `_openAfkingBox:901-907` the chosen tuple, and — critically — the poke writes ONLY the Sub slot, never `lootboxEvBenefitUsedByLevel`, so it faithfully models the buy-time-EV-write-bypassed afking box (the budget stays clean through the stamp, proving no double-draw).
- **TST-02 + TST-03 MARKED COMPLETE.** This plan owns both (frontmatter `requirements:[TST-02, TST-03]`); the three revert classes + the EV-cap exactly-once/shared/clamp are all empirically proven non-vacuously. The class-A funded-slice fuzz that 351-02/03 FED into is now fully discharged here.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The class-B subscribe{value} accounts had no ETH (the makeAddr/deterministic-address subscribers were never dealt)**
- **Found during:** Task 2 (the first class-B run failed `EvmError: Revert` on the test SETUP `subscribe{value: funded}` line, not the `expectRevert`).
- **Issue:** The class-B tests fund `afkingFunding` the canonical way (the subscribe `msg.value` credits both `afkingFunding` AND `claimablePool` in tandem, so SOLVENCY-01 starts balanced before the forced underflow). But the subscriber addresses (`makeAddr(...)` / a deterministic `player()`) hold no ETH, so `subscribe{value: funded}` reverted `OutOfFunds` before the `expectRevert` could engage.
- **Fix:** `vm.deal(subscriber, funded)` before each class-B `subscribe{value}` (3 sites). A test-fixture funding fix — not a contract change.
- **Files modified:** test/fuzz/V55RevertFreeEvCap.t.sol
- **Commit:** 5e6bf322

**2. [Rule 1 - Bug] The AFSUB-03 mass-eviction test tripped PickCharityRejected(0) under a full settle**
- **Found during:** Task 1 (`testNoBrickUnderHeavyPassEviction` failed `PickCharityRejected(0)` when driven by `_runStageNewDay` — the full `_settleGame` loop).
- **Issue:** The 351-02 idle-fixture reality: poking the global `level` to 1 and then running a full multi-day settle eventually crosses a level transition that calls `charityResolve.pickCharity(lvl-1)` against a GNRUS `currentLevel` still at 0 → revert (orthogonal to the no-brick eviction property under test).
- **Fix:** Adopt the 351-02 `_runStageOnce()` driver — a SINGLE `advanceGame()` after a 1-day warp (no full settle) runs the STAGE strictly PRE-RNG (`AdvanceModule:305-326`) so the eviction completes before `rngGate` and the single advance never reaches the level-transition charity call. Subscribe-before-poke ordering preserved.
- **Files modified:** test/fuzz/KeeperNonBrick.t.sol
- **Commit:** 49ce1908

**3. [Rule 3 - Blocking] `stdError` is not in the test contract's scope (forge-std imports it named inside Test.sol, not transitively re-exported)**
- **Found during:** Task 2 (the first compile failed `Undeclared identifier: stdError`).
- **Issue:** `vm.expectRevert(stdError.arithmeticError)` requires the `stdError` library symbol in scope; forge-std imports it *inside* `Test.sol` but does not re-export it transitively to a derived contract.
- **Fix:** Use the self-contained `vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11))` — the exact encoding the checked-arithmetic underflow produces. This is STRONGER (it pins the panic code 0x11, ruling out an unrelated revert) and needs no extra import.
- **Files modified:** test/fuzz/KeeperNonBrick.t.sol, test/fuzz/V55RevertFreeEvCap.t.sol
- **Commit:** 49ce1908, 5e6bf322

**Total deviations:** 3 auto-fixed (2 Rule-1 fixture bugs — the un-dealt subscribers + the full-settle PickCharity trip; 1 Rule-3 blocking — the stdError scope). No architectural changes; no contract edits.

## Authentication Gates

None.

## Known Stubs

None. Every test asserts a non-vacuous outcome: each funded sub is demonstrably stamped / each box demonstrably materialized (`lastOpenedDay` advanced) / each class-B revert is the specific `Panic(0x11)` from the checked `-=` (not an unrelated revert, trace-confirmed) / the EV-cap budget demonstrably moves (0 → drawn) / the shared-budget arm demonstrably accumulates the human draw on the afking key. No hardcoded empty value flows to an assertion.

## Removed-Surface / Reframe Notes (for the 351-09 REGRESSION-BASELINE-v55 ledger)

- **D-351-02 REMOVED-SURFACE DROP (BY NAME + reason):** the v49 keeper `batchPurchase` per-slice try/catch isolation leg — `game.batchPurchase` does not exist on the v55 game-resident Game (the standalone AfKing batch-buy entrypoint + its `BatchBuy` event was 349.1 P5 dead-code with NO behavioral successor; the per-buy work folded into `advanceGame()`'s required-path STAGE, revert-free by construction). The 6 dropped tests:
  - `testBatchPurchaseIsolatesFailingPlayerAndRefundsSlice`
  - `testFuzz_BatchPurchaseFailPositionRefundsAndCompletes`
  - `testBatchPurchaseGameOverRejectsWholeBatchAtEntry`
  - `testBatchPurchaseRejectsNonKeeperCaller`
  - `testKeeperBatchSkipsPoisonedMiddlePlayer`
  - `testFuzz_KeeperBatchPoisonPositionNeverBricks`
  - (+ the `_driveKeeperBatch` toggle + the `KEEPER_PATH_LANDED` 331-05-gated machinery)
- **Reframes (renamed/relocated, NOT removed — kept):** the reentrancy-rollback → `game.withdrawAfkingFunding` (CEI); un-brickable-cancel → `subscribe(_, 0)` tombstone + `withdrawAfkingFunding`; TOMB-04 reclaim/auto-pause-COMMIT → the STAGE's `SubscriptionExpired(.,2)`/`(.,1)` no-cursor-advance swap-pop; AFSUB-03 mass-eviction → the tombstone-then-reclaim STAGE (single-advance pre-RNG driver).
- **Carried-forward A7 baseline red (BY NAME, seen in the full Wave-2 run, NOT introduced here):** `RngLockDeterminism.testFuzz_RngLockDeterminism_StakedStonkRedemption` (`vm.assume rejected too many inputs`) — the same pre-existing red 351-04 logged; zero afking refs; unrelated to this plan's files.

## Sibling Files NOT Compile-Verified Here (Wave-3 charge)

Per the Wave-2 isolation note, the not-yet-adapted siblings owned by OTHER 351 plans still reference the dissolved standalone AfKing / the removed `ContractAddresses.AF_KING` and were sidelined-and-restored for the isolation build (NOT edited): `KeeperBatchAffiliateDeltaAudit`, `RedemptionStethFallback` (test/fuzz/) and `RouterWorstCaseGas`, `SweepPerPlayerWorstCaseGas`, `KeeperLeversAndPacking`, `KeeperOpenBoxWorstCaseGas`, `KeeperResolveBetWorstCaseGas` (test/gas/). The whole-tree compile + full run is Wave 3 (351-09)'s charge. The already-adapted corpus (V55FreezeDeterminism, V55SetMutationOpenE, AfKing*, the three Keeper* reward/router/faucet files, RngLockDeterminism, DeployCanary) compiled + ran alongside my 2 files: 112/129 (the 1 fail = the A7 baseline red BY NAME, 16 = RngLockDeterminism skips).

## Issues Encountered

- **No pretest patch hook** — `patchForFoundry.js` is not auto-invoked. Each isolation run requires `node scripts/lib/patchForFoundry.js` first (predict the CREATE addresses), then `restoreContractAddresses()` + `cleanupBackup()` to keep `contracts/ContractAddresses.sol` frozen (the `.bak` round-trip). The not-yet-adapted siblings must be sidelined (forge compiles the WHOLE tree) and restored after — done via `/tmp/sidelined_351_05`.
- **The idle-fixture day saturation + the level-0 liveness timeout** (the 351-02/03 reality) constrain multi-day STAGE driving: a single new-day STAGE per fixture; a poked-level full settle trips `PickCharity` (use the single-advance `_runStageOnce`).

## User Setup Required

None.

## Self-Check: PASSED

Created/modified files exist:
- FOUND: `test/fuzz/V55RevertFreeEvCap.t.sol`
- FOUND: `test/fuzz/KeeperNonBrick.t.sol`
- FOUND: `.planning/phases/351-.../351-05-SUMMARY.md`

Task commits exist:
- FOUND: `49ce1908` (Task 1 — KeeperNonBrick adapted; batchPurchase-isolation dropped)
- FOUND: `5e6bf322` (Task 2 — V55RevertFreeEvCap TST-02)
- FOUND: `2da39d1e` (Task 3 — V55RevertFreeEvCap TST-03)

Scope guard: `git diff --name-only 453f8073 HEAD -- contracts/` = EMPTY (committed AND working-tree); KeeperNonBrick 15/15 + V55RevertFreeEvCap 11/11 green in isolation (7 fuzz @ 1000 runs); non-comment `afKing.` count == 0 in KeeperNonBrick; `batchPurchase` token count == 0; `AF_KING` token count == 0; the class-B `Panic(0x11)` revert trace-confirmed in `processSubscriberStage`; the EV-cap slot 48 RE-DERIVED (no AfKing-layout literal); the shared-budget human draw non-vacuous (0 → 3 → 7 ETH).

---
*Phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat*
*Completed: 2026-05-31*
