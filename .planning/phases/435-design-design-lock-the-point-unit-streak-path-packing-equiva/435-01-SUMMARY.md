---
phase: 435-design-design-lock-the-point-unit-streak-path-packing-equiva
plan: 01
subsystem: audit
tags: [design-lock, activity-score, points, streak, subStreakLatch, sDGNRS-sentinel, v69]

# Dependency graph
requires:
  - phase: v68.0 baseline (contracts/ tree e9a5fc24)
    provides: byte-frozen _playerActivityScoreAt, Sub accumulator slot, streak path, finalize floor-hack
provides:
  - DESIGN-01 design-lock — point unit (1 pt = 100 bps), additive-contributor inventory, floor(questStreak/2) rule, 655-point cap + sDGNRS sentinel headroom, Sub.score stays uint16
  - DESIGN-02 design-lock — subStreakLatch uint8→uint16 widening, dropped 255 clamp, deleted finalize floor-hack, single exact integer streak path, semantics-preserving actor walk
  - Executor-ready per-symbol edit surface (a)-(f) for the 436 IMPL diff
affects: [436-IMPL, 437-TST, 438-REAUDIT, plan 02 (DESIGN-03 packing — owns the freed-bits slot arithmetic)]

# Tech tracking
tech-stack:
  added: []
  patterns: [source-anchored design-lock with per-symbol edit surface and actor/game-theory walk]

key-files:
  created:
    - .planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-DESIGN-LOCK.md
  modified: []

key-decisions:
  - "Point unit locked: 1 point = 100 bps; every additive bps contributor in _playerActivityScoreAt is a clean multiple of 100 except the quest-streak ×50 leg (:335) — the sole sub-point contributor"
  - "Quest-streak floor rule locked: floor(questStreak / 2) (1 pt per 2 quests; trailing 0.5 pt dropped at odd counts) — the only intentional precision loss"
  - "Point cap locked: floor(65534/100) = 655 points; sDGNRS sentinel re-checked (655+1=656 fits uint16, no collision with the 0 unset sentinel); Sub.score stays uint16"
  - "subStreakLatch widened uint8→uint16 (8 bits from the DESIGN-03 pendingFlip narrowing, plan 02); the 255 clamp at _setStreakBase and the finalize floor-hack at DegenerusQuests.sol:546-551 are both removed"
  - "Single exact integer streak path; afking-XOR-manual _effectiveQuestStreak semantics preserved; only behaviour change is removing the prior silent 255-truncation + its exit-restore"

patterns-established:
  - "Design-lock anchors are re-confirmed against the frozen source while authoring; corrections to CONTEXT.md anchors are flagged inline with [ANCHOR NOTE], source is ground truth"

requirements-completed: [DESIGN-01, DESIGN-02]

# Metrics
duration: ~15min
completed: 2026-06-18
---

# Phase 435 Plan 01: Design-Lock the Point Unit + Streak Path Summary

**Authored the DESIGN-01 (1 pt = 100 bps point unit, `floor(questStreak/2)` floor, 655-point cap with sDGNRS-sentinel headroom) and DESIGN-02 (`subStreakLatch` uint8→uint16 widening, dropped 255 clamp, deleted finalize floor-hack, semantics-preserving actor walk) sections of the v69 design-lock document — read-only against the byte-frozen v68 baseline, NO `.sol` change.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-06-18
- **Tasks:** 2
- **Files modified:** 1 created (435-DESIGN-LOCK.md, 174 lines), 1 summary

## Accomplishments
- **DESIGN-01:** Inventoried all 9 additive legs of `_playerActivityScoreAt` (`MintStreakUtils:282-372`) with source lines and multiple-of-100 status; confirmed the quest-streak `×50` leg (`:335`) is the sole sub-point contributor and every other leg (mint streak/count/affiliate/deity base/deity pass 8000/whale 1000-4000/curse) is a clean multiple of 100. Locked `floor(questStreak/2)`, the 655-point cap (`floor(65534/100)`), the sDGNRS `+1` sentinel headroom check (`655+1=656` fits uint16), and `Sub.score` staying uint16.
- **DESIGN-02:** Stated the grievance (uint8/255 clamp at `_setStreakBase:2259-2261` + the compensating finalize floor-hack at `DegenerusQuests.sol:546-551` — a width mismatch papered over twice), locked the uint8→uint16 latch widening with the exact per-symbol edit surface (a)-(f), cross-referenced the 8 freed bits to plan 02's `pendingFlip` narrowing, and produced the 6-point actor/game-theory walk proving the only behaviour change is removing the prior silent 255-truncation.
- Re-confirmed every cited file:line anchor against the frozen `e9a5fc24` tree; recorded 4 [ANCHOR NOTE] corrections where CONTEXT.md/plan anchors were imprecise (source is ground truth).

## Task Commits

Each task was committed atomically with `git add -f` (`.planning/` is gitignored in this repo):

1. **Task 1: Author the DESIGN-01 section** - `417b8c90` (docs)
2. **Task 2: Author the DESIGN-02 section** - `42092a8b` (docs)

## Files Created/Modified
- `.planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-DESIGN-LOCK.md` - The v69 design-lock document; DESIGN-01 + DESIGN-02 sections (174 lines)

## Decisions Made
None beyond recording the USER-locked decisions D-01..D-05 (the plan's decisions are LOCKED in CONTEXT.md; this plan records them with source-anchored rationale). Claude's-discretion items (exact constant naming, source placement of the floor/cap, the uint16-vs-255 type-safety clamp in `_setStreakBase`) were deferred to 436 IMPL as the plan specified.

## Deviations from Plan

None - plan executed exactly as written. No deviation rules (1-4) triggered; no `contracts/*.sol`, STATE.md, or ROADMAP.md touched.

## Anchor Corrections (source is ground truth)

The plan's `<interfaces>` block and CONTEXT.md were re-confirmed against the frozen `e9a5fc24` tree. Four anchors were imprecise and corrected inline in the design-lock with `[ANCHOR NOTE]` tags (none change a locked decision):

1. **sDGNRS sentinel** — CONTEXT.md cited `sDGNRS.sol:1135-1142`; the exact write is `:1140` (`uint16(...) + 1`) with the `claim.activityScore == 0` guard at `:1139`. Corrected to `:1138-1141`.
2. **`beginAfking` return type** — the plan said "returns state.streak (uint16)"; the function return **type** is `uint24 streak` (`DegenerusQuests.sol:504`), sourced from the underlying uint16 `state.streak` field (`:281`). The symmetry argument (match the latch to the uint16 manual streak) holds either way.
3. **Finalize floor-hack condition** — the plan abbreviated it to `if (finalStreak < preRun)`; the live code at `:550` guards `finalStreak != 0 && finalStreak < preRun` (so a genuine decay-to-0 is not floored back up). The exact block to DELETE is `:549-550`; the type-clamp at `:551` is a separate retained concern.
4. **subStreakLatch width comment** — `Storage:2244-2256` masks the **full byte** (`SUB_STREAK_MASK = 0xff`, 8 bits), but a stale comment at `Storage:2144` describes `streakAtAfkingStart (bits 0-6)` (7 bits). The live width is 8 bits; the widening edit must also fix that stale comment.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required. This is a documentation-only design-lock phase.

## Next Phase Readiness
- DESIGN-01 + DESIGN-02 are design-locked with source-anchored rationale and an executor-ready per-symbol edit surface. Ready for 436 IMPL to implement (alongside DESIGN-03/04 from plan 02).
- The 8 freed bits for the latch widening depend on plan 02's `pendingFlip` uint32→uint24 narrowing (D-06/D-07); plan 02 owns the slot arithmetic, EIP-170 re-check, and layout-golden recapture. Cross-reference is recorded in the DESIGN-02 section.
- No blockers. NO `contracts/*.sol`, STATE.md, or ROADMAP.md modified (orchestrator owns those writes).

## Self-Check: PASSED
- `435-DESIGN-LOCK.md` exists (174 lines, both `## DESIGN-01` and `## DESIGN-02` sections present) ✓
- Commits `417b8c90` + `42092a8b` exist in git log, each with the `.planning/` file in the commit ✓
- `floor(questStreak / 2)`, `655`, `8000`/`DEITY_PASS_ACTIVITY_BONUS_BPS`, `uint8→uint16`, `546-551`/`floor-hack`, `_effectiveQuestStreak` all present (Task 1 + Task 2 automated verify PASS) ✓
- No `contracts/*.sol` modified (`git status --porcelain contracts/` empty) ✓

---
*Phase: 435-design-design-lock-the-point-unit-streak-path-packing-equiva*
*Completed: 2026-06-18*
