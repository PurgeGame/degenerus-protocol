---
phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre
plan: 02
subsystem: contracts (shared quest core)
tags: [solidity, foundry, degenerus-quests, afking, streak, quest-settle, creditFlip, dead-code]

# Dependency graph
requires:
  - phase: 353-spec-design-lock
    provides: "the LOCKED QST design (settleAfkingQuest entrypoint shape, QST-02/03/04 non-perturbation + delivered-day gate, QST-05 O1 fix + dead-code removal)"
provides:
  - "DegenerusQuests.settleAfkingQuest(player, deliveredStreakDays, currentDay) — the onlyGame GAME-context batched afking-quest streak-settle entrypoint (the streak-machinery half of the v56 settle)"
  - "the QST-05 O1 fix at the source: the duplicate lootbox-leg internal creditFlip in handlePurchase is removed; lootboxReward stays in the return so the caller credits it exactly once"
  - "dead handleLootBox removed from DegenerusQuests + IDegenerusQuests (+ its access-control tests)"
affects: [354-03 GameAfkingModule._settleQuest (the consumer), 356 TST (QST-04 non-perturbation + SEC-01 no-double-credit), 357 TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mirror-an-existing-onlyGame-fn: settleAfkingQuest mirrors awardQuestStreakBonus (sync-first, uint24 clamp, QuestStreakBonusAwarded event) so it provably touches only the same slot-0/streak/anchor fields"
    - "In-core per-day double-credit guard via the completionMask bit-7 STREAK_CREDITED bit + lastCompletedDay == currentDay test (gates streak advancement only, never slot rewards)"

key-files:
  created: []
  modified:
    - contracts/DegenerusQuests.sol
    - contracts/interfaces/IDegenerusQuests.sol
    - test/fuzz/CoverageGap222.t.sol
    - test/unit/DegenerusQuests.test.js

key-decisions:
  - "settleAfkingQuest signature = (address player, uint16 deliveredStreakDays, uint32 currentDay) — the GAME passes the debit-gated delivered-day count; the entrypoint does NOT itself decide deliveredness (that GAME-side gate is afkCoveredThroughDay in 354-03)"
  - "QST-03 in-core guard reads the existing completionMask STREAK_CREDITED bit (reset per-day by _questSyncState) + lastCompletedDay; if a manual completion already credited today, credit one fewer day — at most once per delivered day; slot rewards never suppressed"
  - "QST-01..05 left Pending in REQUIREMENTS.md — they are phase-354-wide (the consumer side / accrue + _settleQuest wiring lands in 354-03/05); marking them Complete now would be inaccurate as no caller wires the entrypoint yet"

patterns-established:
  - "Streak-machinery / BURNIE-mint split: settleAfkingQuest is the streak/anchor half ONLY; the questProgress * QUEST_SLOT0_REWARD + buyerOwedBurnie creditFlip is minted GAME-side in 354-03's _settleQuest (single batched creditFlip, inheriting the post-O1-fix single-credit invariant)"

requirements-completed: []

# Metrics
duration: 24min
completed: 2026-06-01
---

# Phase 354 Plan 02: DegenerusQuests Shared-Core Batched-Settle Entrypoint + O1 Fix + Dead-Code Removal Summary

**Added the `onlyGame` `settleAfkingQuest` streak-settle entrypoint to the shared DegenerusQuests core (sync-first, slot-1-untouched, completionMask STREAK_CREDITED per-day guard), fixed the O1 lootbox-quest double-credit at the source by dropping the duplicate internal `creditFlip`, and removed the dead `handleLootBox` from contract + interface + tests — `forge build` clean.**

## Performance

- **Duration:** ~24 min
- **Started:** 2026-06-01T17:28Z
- **Completed:** 2026-06-01T17:52Z
- **Tasks:** 2
- **Files modified:** 4 (2 contracts, 2 tests)

## Accomplishments
- **Task 1 (QST-01/02/03/04):** new `settleAfkingQuest(address player, uint16 deliveredStreakDays, uint32 currentDay)` in `DegenerusQuests.sol` — `onlyGame`-gated, calls `_questSyncState` FIRST (mirroring `awardQuestStreakBonus`), advances `state.streak` (uint24-clamped) for the DELIVERED-day count only, applies the QST-03 in-core double-credit guard (reads the `completionMask` bit-7 `QUEST_STATE_STREAK_CREDITED` bit + `lastCompletedDay == currentDay` → credits one fewer day when a manual path already credited today), implements the active-pass anti-reset (advances `lastActiveDay`/`lastCompletedDay` to keep `_questSyncState`'s anchorDay current with no daily/shield write), and touches ZERO slot-1 fields (`progress[1]`/`lastProgressDay[1]`/`lastQuestVersion[1]`) — QST-04 non-perturbation. Declared in `IDegenerusQuests.sol`.
- **Task 2 (QST-05 + D-05):** dropped the duplicate `coinflip.creditFlip(player, lootboxReward)` inside `handlePurchase` (the O1 double-credit); kept the burnie-leg internal credit and the `totalReturned = ethMintReward + lootboxReward` return so the MintModule caller credits the lootbox reward exactly once via its batched `creditFlip`. Removed the dead `handleLootBox` function (zero production callers) from `DegenerusQuests.sol`, its decl + comment ref from `IDegenerusQuests.sol`, and its now-stale access-control tests.

## Task Commits

Per the **Phase 354 contract-commit override**: the contract edits (`DegenerusQuests.sol`, `IDegenerusQuests.sol`) are intentionally left UNCOMMITTED in the working tree — they accumulate for the SINGLE USER-approved batched `contracts/*.sol` commit at the 354-06 hand-review gate. There are intentionally ZERO production-code commits in this plan.

1. **Task 1: settleAfkingQuest entrypoint** — working-tree edit, no commit (contract gate)
2. **Task 2: O1 fix + dead-code removal** — working-tree edit, no commit (contract gate); test-file edits committed with the docs commit below

**Plan metadata (docs):** see the docs(354-02) commit (this SUMMARY + STATE.md + ROADMAP.md + the test-file changes + deferred-items.md).

## Files Created/Modified
- `contracts/DegenerusQuests.sol` — **(UNCOMMITTED, contract gate)** added `settleAfkingQuest`; dropped the O1 lootbox-leg internal `creditFlip` in `handlePurchase`; removed `handleLootBox`.
- `contracts/interfaces/IDegenerusQuests.sol` — **(UNCOMMITTED, contract gate)** added `settleAfkingQuest` decl; removed `handleLootBox` decl + comment ref.
- `test/fuzz/CoverageGap222.t.sol` — removed the stale `handleLootBox` access-control low-level-call probe (`o5`) + its assertion.
- `test/unit/DegenerusQuests.test.js` — removed the `handleLootBox` access-control describe block, the `handleLootBox` entry in the "currentDay==0" handler list, and the docblock comment line.

## Decisions Made
- **`settleAfkingQuest` signature** = `(address player, uint16 deliveredStreakDays, uint32 currentDay)` — the plan offered latitude; chose the minimal set the Wave-2 `_settleQuest` needs: the GAME passes the per-window debit-gated delivered-day count, the entrypoint advances the streak by that many days (minus the per-day double-credit). The entrypoint does NOT decide deliveredness — that lives in GameAfkingModule's `afkCoveredThroughDay` (354-01 field / 354-03 advance).
- **QST-03 guard reuses the existing per-day mechanism** — rather than add new storage, it reads the `completionMask` STREAK_CREDITED bit (already reset per-day by `_questSyncState` at the sync-day rollover) plus `lastCompletedDay`. This is the in-core implementation path for the SPEC's "`lastCompletedDay` / `afkCoveredThroughDay` guard gates `state.streak` advancement" (353-SPEC.md:237). It sets the STREAK_CREDITED bit after crediting so a later same-day manual completion / double-settle is idempotent.
- **Requirements left Pending** — QST-01..05 are Phase-354-wide requirements whose consumer side (the GameAfkingModule accrue + `_settleQuest` wiring that actually CALLS this entrypoint, and the ticket buyer-bonus accrual) lands in 354-03 / 354-05. This plan delivers the shared-core half only; marking QST-01..05 Complete now would overstate progress. They flip to Complete when the phase IMPL completes (354-06 / verifier).

## Deviations from Plan

None to the contract logic — the two contract files match the plan's `<interfaces>` anchors and acceptance criteria exactly. Two in-scope-but-not-line-itemized cleanups:

### Auto-fixed Issues

**1. [Rule 3 - Blocking / plan-directed] Removed stale `handleLootBox` access-control tests**
- **Found during:** Task 2 (dead-code removal)
- **Issue:** Two test sites still referenced the removed `handleLootBox` — `test/fuzz/CoverageGap222.t.sol` (a low-level-call access-control probe with a now-misleading "rejected non-coin caller" assertion that would pass only because the selector no longer exists) and `test/unit/DegenerusQuests.test.js` (a describe block + a handler-list entry + a docblock line). The plan's Task 2 action explicitly says to remove "the access-control tests for it."
- **Fix:** Removed the `o5` probe + assertion in the `.t.sol`; removed the `handleLootBox` describe block, the handler-list entry, and the docblock comment line in the `.js`.
- **Files modified:** `test/fuzz/CoverageGap222.t.sol`, `test/unit/DegenerusQuests.test.js`
- **Verification:** `grep -rn handleLootBox` (excl. node_modules) returns zero matches anywhere; `forge build` exits 0.
- **Committed in:** the docs(354-02) commit (test files are AGENT-committable).

---

**Total deviations:** 1 (plan-directed test cleanup; the contract logic was already authored to spec by a prior partial run on this working tree and verified correct, not re-authored).
**Impact on plan:** No scope creep. All acceptance criteria met.

## Issues Encountered
- **Working tree already carried the 354-02 contract edits.** On execution start, `DegenerusQuests.sol` + `IDegenerusQuests.sol` already contained the `settleAfkingQuest` entrypoint, the O1 fix, and the `handleLootBox` removal (a prior partial run). I did NOT re-author — I verified every acceptance criterion against the actual working tree (grep-attested onlyGame + `_questSyncState`-first + `QUEST_STATE_STREAK_CREDITED`/`lastCompletedDay` reads + zero slot-1 refs + interface decl + O1 single-credit + zero `handleLootBox`), then completed the remaining unfinished work (the stale test removals) and confirmed `forge build` clean. The pre-existing 354-01 edits (`GameAfkingModule.sol`, `DegenerusGameStorage.sol`) were left untouched.
- **Pre-existing out-of-scope lint warning** — `forge build` emits an `unsafe-typecast` lint warning at `contracts/modules/DegenerusGameMintModule.sol:1704` (`uint24(day)`). PRE-EXISTING, in a file NOT touched by this plan, informational only (`forge build` exits 0). Logged to `deferred-items.md`; not fixed (SCOPE BOUNDARY).

## User Setup Required
None.

## Next Phase Readiness
- The shared-core entrypoint is ready for 354-03's `GameAfkingModule._settleQuest` to call (the `awardQuestStreakBonus|_questSyncState` key-link). The single-creditFlip invariant the afking settle relies on (QST-05) is now established at the source.
- **Contract gate:** `DegenerusQuests.sol` + `IDegenerusQuests.sol` remain UNCOMMITTED, accumulating with the 354-01 edits for the single USER-approved batched commit at 354-06.

## Self-Check: PASSED

- `354-02-SUMMARY.md` — FOUND
- `deferred-items.md` — FOUND
- `contracts/DegenerusQuests.sol` — modified, UNCOMMITTED (contract gate, as required)
- `contracts/interfaces/IDegenerusQuests.sol` — modified, UNCOMMITTED (contract gate, as required)
- `settleAfkingQuest` present in both contract + interface (1 each)
- `handleLootBox` references repo-wide (excl. node_modules): 0
- `forge build` exit 0

No commit hashes to verify for contract files — they are intentionally left uncommitted per the Phase 354 contract-commit override (single USER-approved batched commit deferred to 354-06).

---
*Phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre*
*Completed: 2026-06-01*
