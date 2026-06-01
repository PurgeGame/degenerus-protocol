---
phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
plan: 02
subsystem: testing
tags: [foundry, fuzz, afking, game-resident, set-mutation, swap-pop, no-orphan, open-e, funding-waterfall, vm-load, storage-slots]

# Dependency graph
requires:
  - phase: 351-01
    provides: "the compiling DeployProtocol fixture (GameAfkingModule deployed at GAME_AFKING_MODULE) the AfKing corpus adaptation builds on"
  - phase: 349.2
    provides: "the frozen 453f8073 contract subject (game-resident afking surface + processSubscriberStage STAGE + the NO-ORPHAN guard)"
provides:
  - "Three adapted AfKing fuzz files (Concurrency / Subscription / FundingWaterfall) running against the game-resident GameAfkingModule path"
  - "The dedicated TST-04 proof V55SetMutationOpenE.t.sol (two-path coexistence + NO-ORPHAN + streak-preserved swap-pop + the OPEN-E 4-protection)"
  - "A validated game-resident driving harness: the per-sub buy is the advanceGame() STAGE (processSubscriberStage(50)); the afking box open is mintBurnie()'s open leg; the funding waterfall is the in-context afkingFunding[src] SLOAD"
  - "RE-DERIVED game storage slots for the whole downstream corpus: _subOf=66, _fundingSourceOf=67, _subscribers=68, _subscriberIndex=69, _subCursor=70(off0), _afkingResetDay=70(off4), subsFullyProcessed=slot0(off31), mintPacked_=10, claimablePool=slot1(off16), afkingFunding=8; Sub packed offsets verified by round-trip"
affects: [351-05, 351-09, "TST-02 funded-slice (KeeperNonBrick reuses the FundingWaterfall corners)", "REGRESSION-BASELINE-v55.md (the rewrite map for these 3 files)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Δ4 buy-driver remap: afKing.autoBuy(N) -> a new-day game.advanceGame() that runs the pre-RNG processSubscriberStage STAGE (the standalone autoBuy + its mid-block cursor are GONE)"
    - "Single-advance eviction driver: a SINGLE advanceGame() runs the STAGE pre-RNG (evict/refresh/buy) and STOPS before the level-transition charity call (which reverts on a poked level)"
    - "afking box open = game.mintBurnie() open leg ONLY (the afking autoOpen selector collides with the human autoOpen(uint256), so it is not re-exposed on the Game)"
    - "Sibling-isolation compile: move the still-broken keeper/router corpus aside, compile + run only the owned files (forge compiles the WHOLE tree before any test), restore after"
    - "Tandem claimablePool credit on a claimableWinnings slot poke (keep SOLVENCY-01 balanced so a claimable-funded buy's claimablePool -= does not underflow)"

key-files:
  created:
    - "test/fuzz/V55SetMutationOpenE.t.sol"
    - ".planning/phases/351-.../351-02-SUMMARY.md"
  modified:
    - "test/fuzz/AfKingConcurrency.t.sol"
    - "test/fuzz/AfKingSubscription.t.sol"
    - "test/fuzz/AfKingFundingWaterfall.t.sol"

key-decisions:
  - "Marked ONLY TST-04 complete; left TST-02 Pending — this plan FEEDS TST-02 (the funded-slice fuzz + revert-free corners) but the full TST-02 proof (the _resolveBuy REVERT-01 invariants, the class-B solvency fail-loud, the class-C gameover-unblocked) is owned by 351-05 (KeeperNonBrick). Marking TST-02 complete here would be a false claim."
  - "The 'two same-block autoBuy callers self-partition via the mid-block cursor' property has NO v55 successor (the buy is single-shot in advanceGame); reframed onto the full-STAGE 'every active sub processed exactly once, no double, no miss' (D-351-01 renamed-mechanism, not a removed surface)"
  - "The per-day reset re-stamp could not be driven by warping days (the idle fixture's day index saturates without ticket purchases); reframed to prove the reset GATE non-vacuously (closed-after-STAGE with cursor at set-end -> reopened by the reset to subsFullyProcessed=false + _subCursor=0, the exact AdvanceModule:305-309 fields)"
  - "Streak-preserved swap-pop reframed: scorePlus1 is re-derived per fresh buy (not carried), so the property is that the swap-pop RELOCATION does not corrupt the mover's streak-derived score — proven byte-identical to an undisplaced control + the cancelled record fully deleted"

patterns-established:
  - "Empirically verify storage offsets + the driving harness with a scratch probe BEFORE writing large adapted files (de-risks the whole plan)"

requirements-completed: [TST-04]

# Metrics
duration: 75min
completed: 2026-05-31
---

# Phase 351 Plan 02: AfKing Corpus Adaptation + TST-04 Set-Mutation/OPEN-E Proof Summary

**Adapted the three `AfKing*` fuzz files to the game-resident `GameAfkingModule` path (the buy folded into `advanceGame()`'s `processSubscriberStage` STAGE, the funding waterfall now an in-context `afkingFunding[src]` SLOAD, all 136 `afKing.` call-sites + every pinned storage slot RE-DERIVED) and authored the dedicated TST-04 proof — two-path open coexistence + the NO-ORPHAN guard + streak-preserved swap-pop + the OPEN-E 4-protection — 44 tests green in isolation, ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~75 min
- **Completed:** 2026-05-31
- **Tasks:** 3
- **Files modified:** 3 adapted + 1 new = 4 test files
- **Tests:** 44 total (12 Concurrency + 8 Subscription + 14 FundingWaterfall + 10 V55SetMutationOpenE), all passing in isolation

## Accomplishments

- **The three `AfKing*` fuzz files are adapted to the game-resident path** — all `afKing.` call-sites (68 + 29 + 39 = 136) rewritten via the five D-351-01 deltas; both `AfKing.sol` import breaks cleared; the AfKing-standalone-layout slot constants (`SUBOF_SLOT=1`, `SUBSCRIBER_INDEX_SLOT=3`, `AUTOBUY_SLOT=4`) replaced with the RE-DERIVED game-resident slots.
- **The dedicated TST-04 proof `V55SetMutationOpenE.t.sol` (10 tests) is authored** — two-path coexistence (BOX-05), the NO-ORPHAN guard across the removed-sub + the contract's own pending-box-protect path, the streak-not-corrupted-by-swap-pop property, and all four OPEN-E protections — every assertion non-vacuous, the orderings fuzzed.
- **A validated game-resident driving harness** — proven empirically by a scratch probe before the real files: the per-sub buy is `advanceGame()`'s pre-RNG STAGE (`processSubscriberStage(50)`), the afking box open is `mintBurnie()`'s open leg (the afking `autoOpen` selector collides with the human `autoOpen(uint256)` so it is reachable ONLY via `mintBurnie`), the funding waterfall is the in-context `afkingFunding[src]` SLOAD.
- **The H-CANCEL-SWAP-MISS resolution is regressed on the game-resident set** — the in-place cancel-tombstone + the STAGE's deferred reclaim (no cursor advance after the swap-pop) re-reads the mover at the freed slot THIS pass; the swap-pop-occupant no-skip property is asserted non-vacuously (the moved sub is processed) in both `AfKingConcurrency` and `V55SetMutationOpenE`.
- **ZERO `contracts/*.sol` mutation** — `git diff --name-only 453f8073 HEAD -- contracts/` is EMPTY; `ContractAddresses.sol` restored byte-identical after every `patchForFoundry` round-trip.

## Task Commits

Each task was committed atomically (test/ only — no contracts/):

1. **Task 1: Adapt AfKingConcurrency + AfKingSubscription** — `0f78c896` (test)
2. **Task 2: Adapt AfKingFundingWaterfall** — `5b3f6dd3` (test)
3. **Task 3: Author V55SetMutationOpenE (the TST-04 proof)** — `5a40624b` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately.

## Files Created/Modified

- `test/fuzz/AfKingConcurrency.t.sol` — the PRIMARY set-mutation/swap-pop/tombstone analog. Reframed the whole H-CANCEL-SWAP-MISS corpus onto the game-resident `_subscribers` swap-pop + the STAGE reclaim. 12 tests incl. a fuzz over cancel orderings + the pass-eviction swap-pop invariant. The "two same-block autoBuy callers split" property (no v55 successor) reframed to the full-STAGE exactly-once; the per-day reset reframed to the reset-gate flip (the idle fixture's day index saturates).
- `test/fuzz/AfKingSubscription.t.sol` — crossing refresh/evict (AFSUB-02/03), AFSUB-01 no-BURNIE-at-subscribe, the single-creditFlip `mintBurnie` bounty, the OPEN-E subscribe-only consent gate. The `IGame from AfKing.sol` import dropped; the 336-04 no-SLOAD oracle reframed to the in-context stored-field crossing check. 8 tests.
- `test/fuzz/AfKingFundingWaterfall.t.sol` — the funding waterfall (DirectEth/Claimable/Combined/sentinel/InsufficientPool) now reads the in-context `afkingFunding[src]` SLOAD; the cross-contract `poolOf` STATICCALL plumbing replaced. LANDMINE-A (`testFundingSourceVaultDoesNotInheritExemption`) preserved + green; the SUB-06 two-tier pinned-identity skip-kill preserved; the grep-clean test repointed to `GameAfkingModule.sol`; adds `testFuzzFundedSliceNeverRevertsAndChargesExactEthValue` (the TST-02 funded-slice fuzz). 14 tests.
- `test/fuzz/V55SetMutationOpenE.t.sol` — NEW. The dedicated TST-04 proof (10 tests). See Accomplishments.

## Decisions Made

- **TST-04 marked complete; TST-02 left Pending.** This plan fully discharges TST-04 (two-path coexistence + set-mutation/swap-pop/streak + the OPEN-E 4-protection). It FEEDS TST-02 (the `testFuzzFundedSliceNeverRevertsAndChargesExactEthValue` + the InsufficientPool/revert-free corners), but TST-02's full proof — the `_resolveBuy` REVERT-01 invariants, the class-B solvency fail-loud, the class-C gameover-unblocked — is owned by 351-05 (the `KeeperNonBrick` template, PATTERNS §6). Marking TST-02 complete here would over-claim.
- **The "two same-block autoBuy callers self-partition via the mid-block cursor" property has no v55 successor.** In v55 the per-sub buy is single-shot inside `advanceGame()`'s STAGE (no `autoBuy(maxCount)` with a re-entrant cursor two callers can split). Per D-351-01 this is a renamed/relocated mechanism (NOT a removed surface), so it reframes onto the full-STAGE "every active sub processed exactly once, no double, no miss" — the actual invariant that matters.
- **The per-day reset re-stamp is proven via the reset GATE, not a real day rollover.** The idle test fixture's day index (`_simulatedDayIndexAt`) saturates without ticket purchases (verified by a probe: `dailyIdx` pins at 3, the stamp at 2, across many warps), so a second real STAGE re-buy cannot be reliably driven. The honest, non-vacuous proof asserts the exact `AdvanceModule:305-309` gate: after a completed STAGE the gate is CLOSED (`subsFullyProcessed == true`, cursor at the set end); the per-day reset re-OPENS it (`subsFullyProcessed = false`, `_subCursor = 0`).
- **Streak-preserved swap-pop reframed to a byte-identical control comparison.** In v55 `scorePlus1` is re-derived per fresh buy (`_playerActivityScore + 1`, GameAfkingModule.sol:785-793), NOT carried across the swap-pop. The property TST-04 regresses is that the swap-pop RELOCATION does not corrupt the mover's streak-derived score — proven by asserting the displaced mover's `scorePlus1` is byte-identical to an undisplaced control with the same activity, the cancelled record fully deleted, and a pre-seeded `0xBEEF` garbage overwritten.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The plan's `forge test --match-contract ... --skip` isolation does not stop COMPILATION of broken siblings**
- **Found during:** Task 1 (first compile attempt)
- **Issue:** Foundry compiles the WHOLE `test/` tree before running ANY test; `--skip` only filters which tests RUN. The 10 sibling keeper/router/sweep corpus files (owned by other 351 plans) still hard-break on the deleted `contracts/AfKing.sol`, so no owned test could compile.
- **Fix:** A sideline-and-restore harness — move the still-broken sibling files aside, compile + run only the owned files, restore them. (No sibling file was edited; their breaks are pre-existing per `deferred-items.md`.)
- **Files modified:** none (test-harness only; the sibling files are untouched on disk after restore)
- **Commit:** n/a (verification-only mechanism)

**2. [Rule 1 - Bug] A poked `level=1` + a full multi-day settle reverts `PickCharityRejected(0)` (a test-fixture artifact)**
- **Found during:** Task 1 (the pass-eviction tests)
- **Issue:** Forcing the crossing by poking the global `level` to 1 and then running a full `_settleGame` loop eventually crosses a level transition that calls `charityResolve.pickCharity(lvl-1)` against a GNRUS `currentLevel` still at 0 → revert.
- **Fix:** A `_runStageOnce()` driver — a SINGLE `advanceGame()` runs the STAGE strictly PRE-RNG (the eviction/refresh/buy completes) and STOPS before the level-transition charity call. Subscribe-first (subscribe blocks during rngLock), then poke level, then the single advance.
- **Files modified:** test/fuzz/AfKingConcurrency.t.sol, test/fuzz/AfKingSubscription.t.sol, test/fuzz/AfKingFundingWaterfall.t.sol
- **Commit:** 0f78c896, 5b3f6dd3

**3. [Rule 1 - Bug] A raw `claimableWinnings` slot poke underflows the contract's `claimablePool -=` on a claimable-funded buy**
- **Found during:** Task 2 (the Claimable + Combined waterfall tests)
- **Issue:** Setting `claimableWinnings[p]` via `vm.store` without bumping `claimablePool` breaks the SOLVENCY-01 invariant; when the buy consumes claimable, the contract's checked `claimablePool -=` underflows (Panic 0x11).
- **Fix:** `_setClaimable` credits `claimablePool` (slot 1, offset 16, uint128) in tandem — exactly as the contract does — so the master invariant stays balanced. A test-fixture correctness fix, not a contract change.
- **Files modified:** test/fuzz/AfKingFundingWaterfall.t.sol
- **Commit:** 5b3f6dd3

**Total deviations:** 3 auto-fixed (1 blocking-harness, 2 fixture-correctness bugs). No architectural changes; no contract edits.

## Authentication Gates

None.

## Known Stubs

None. Every test asserts a non-vacuous outcome (the sub actually existed / the box would have materialized absent the guard / the control proves the expected value is well-defined). No hardcoded empty values flow to an assertion.

## Sibling Files NOT Compile-Verified in Isolation (Wave-3 charge)

Per the plan's Wave-2 isolation note, these 10 sibling files (owned by OTHER 351 plans) still reference the dissolved standalone AfKing and were NOT compiled/run here — the whole-tree compile + full run is Wave 3 (351-09)'s charge:
`KeeperRewardRoutingSameResults`, `KeeperNonBrick`, `RngLockDeterminism`, `KeeperFaucetResistance`, `KeeperRouterOneCategory`, `KeeperBatchAffiliateDeltaAudit`, `RedemptionStethFallback` (test/fuzz/) and `SweepPerPlayerWorstCaseGas`, `KeeperLeversAndPacking`, `RouterWorstCaseGas` (test/gas/). This is expected, not a failure.

## Issues Encountered

- **The idle test fixture's day index saturates** without ticket-purchase activity (`_simulatedDayIndexAt` pins after a few warps), so any test that needs a SECOND real fresh-day STAGE cycle on the same subs cannot drive it via warping. Worked around by proving the per-day reset GATE directly (see Decisions). Downstream plans driving multi-day afking flows should expect this and either drive real purchases or poke the gate fields.

## User Setup Required

None.

## Self-Check: PASSED

Created/modified files exist:
- FOUND: `test/fuzz/AfKingConcurrency.t.sol`
- FOUND: `test/fuzz/AfKingSubscription.t.sol`
- FOUND: `test/fuzz/AfKingFundingWaterfall.t.sol`
- FOUND: `test/fuzz/V55SetMutationOpenE.t.sol`

Task commits exist:
- FOUND: `0f78c896` (Task 1 — Concurrency + Subscription)
- FOUND: `5b3f6dd3` (Task 2 — FundingWaterfall)
- FOUND: `5a40624b` (Task 3 — V55SetMutationOpenE)

Scope guard: `git diff --name-only 453f8073 HEAD -- contracts/` = EMPTY (committed AND working-tree); all 4 owned files compile + 44/44 tests pass in isolation; `afKing.` non-comment count == 0 in all 4; no AfKing-layout slot literal survives.

---
*Phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat*
*Completed: 2026-05-31*
