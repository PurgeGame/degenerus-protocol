---
phase: 353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode
plan: 01
subsystem: spec
tags: [solidity, affiliate, accumulator, storage-packing, quest-core, threat-model, design-lock, paper-only]

# Dependency graph
requires:
  - phase: 348-352 (v55.0)
    provides: the frozen subject 453f8073 (MILESTONE_V55_AT_HEAD) + the 349.2 BURNIE-flip-credit-off-solvency invariant + the AfKing-in-Game box-stamp + the O1 out-of-scope advisory
provides:
  - 353-SPEC.md design-lock DRAFT (AFF-01/AFF-02 locked + all v56 design feeds)
  - the corrected in-Sub-slot accumulator decision (re-pack + whole-BURNIE + 100M clamp + milli-ETH amount + uint24 day/level fields, NO new cold slot — supersedes RESEARCH §3 Option B)
  - the 21-row anchor attestation table (vs 453f8073) with 5 drift reconciliations + frozen-subject guard
  - the unmanipulable / SOLVENCY-01-untouched / RNG-freeze-intact threat re-attestation with per-invariant TST-356 proof obligations
  - the AGG/TKT/QST/QST-05/OPEN design feeds (owned at IMPL 354)
  - the XMODEL-01 (C1-C5) + SPEC Lock PENDING placeholders for Plan 02
affects: [354-impl, 355-gas, 356-tst, 357-terminal, plan-02-xmodel]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "In-slot accumulator via struct re-pack (whole-BURNIE uint32 + saturating clamp + milli-ETH rounding + narrowed day/level fields) instead of a new cold slot"
    - "Anchor attestation table re-grep'd vs the frozen subject before any file:line is written into a SPEC (no by-construction)"
    - "Design-feed sections flagged owned-at-IMPL (requirement-ID over-claim avoided: AFF-01/02 only)"

key-files:
  created:
    - .planning/phases/353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode/353-SPEC.md
  modified: []

key-decisions:
  - "Accumulator fits IN the re-packed Sub slot (NO new cold slot): affiliate base in whole BURNIE as uint32 with a 100M saturating clamp + amount rounded to milli-ETH (uint96→~uint32) + validThroughLevel/lastAutoBoughtDay/lastOpenedDay narrowed uint32→uint24; windowStartDay dropped (global ~10-day epoch). SUPERSEDES RESEARCH §3 Option B (new dedicated slot)."
  - "AFF-01: the scheduled flush rolls on the FIXED window-boundary day (not the live settle-call currentDayIndex); the deterministic 75/20/5 split is the player-flush path (no roll); buyer-never-wins (:579) gives the buyer zero EV regardless of timing."
  - "AFF-02 force-flush-before-jackpot DECLINED: the 5% claim (claimAffiliateDgnrs :216) reads cumulative affiliateScore/totalAffiliateScore (exact regardless of option-A lag); only the minority 1%-top ranking lags (accepted)."
  - "Century/x00 bonus KEPT at parity for afking-ticket buyers (D-10 flipped) — amortized-negligible, reuses existing centuryBonusLevel/Used storage + the per-buy score."
  - "O1 fix is two halves: drop DegenerusQuests:890 at the source AND the v56 afking settle routes the deferred lootbox reward through exactly one creditFlip (the afking per-buy handlePurchase :760 disappears under the aggregator)."

patterns-established:
  - "Pattern 1: re-pack-to-fit-in-slot beats append-a-cold-slot when the existing fields are wastefully wide (validThroughLevel/day markers uint32 → uint24) and the new field tolerates a lossy denomination (whole-BURNIE + clamp, off the solvency path)"
  - "Pattern 2: every cited file:line is grep-re-attested vs the frozen subject and tabulated before it enters the SPEC — drifts (5 here) recorded, not silently absorbed"

requirements-completed: [AFF-01, AFF-02]

# Metrics
duration: ~18min
completed: 2026-06-01
---

# Phase 353 Plan 01: v56.0 Design-Lock SPEC Core Summary

**Authored `353-SPEC.md` — the v56.0 design-lock DRAFT: AFF-01/AFF-02 locked (window-boundary-day roll seed + per-buy immutable taper + option-A leaderboard, force-flush declined), the corrected in-Sub-slot accumulator (re-pack + whole-BURNIE uint32 + 100M clamp + milli-ETH amount + uint24 day/level fields, NO new cold slot), the 21-row anchor attestation table with 5 drift reconciliations, the unmanipulable/SOLVENCY-01/RNG-freeze threat re-attestation, the AGG/TKT/QST/QST-05/OPEN design feeds, and the XMODEL + SPEC-Lock placeholders for Plan 02.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-06-01 (execution start)
- **Completed:** 2026-06-01
- **Tasks:** 3
- **Files modified:** 1 (created `353-SPEC.md`)

## Accomplishments
- **Anchor attestation (Task 1):** re-grep'd all 21 anchors (A1–A21) vs the frozen subject `453f8073` (working tree byte-identical, guard PASS), reconciled the ROADMAP bare module names to `contracts/modules/...` full paths, and recorded all 5 drifts (storm `:708-833`; `claimAffiliateDgnrs :216`; `handleLootBox :698-741`; O1-drop `:890` inside the `if` at `:889`; EV-cap `[player][currentLevel]`=`level+1`).
- **AFF-01/AFF-02 + accumulator + threat model (Task 2):** locked the affiliate roll non-gameability (currentDayIndex pure `:21-34`, buyer-never-wins `:579`, window-boundary-day seed with the explicit TST-356 proof obligation), the taper-at-accrue + option-A leaderboard (`:510`/`:511`/`:521`, cross-level lag accepted, force-flush declined via the `claimAffiliateDgnrs :216` cumulative-score rationale), the corrected in-slot accumulator (232/256 occupancy → re-pack to fit, NO new cold slot, supersedes RESEARCH §3 Option B), and the SOLVENCY-01-byte-unchanged (`:709-710`) / RNG-freeze-intact / unmanipulable re-attestation with per-invariant TST-356 obligations.
- **Design feeds + placeholders (Task 3):** folded AGG (accrue→settle shape, grounded in `353-AFKING-READS-WRITES.md`), TKT (minimal-write primitive + century KEEP at parity, D-10), QST (onlyGame batched-settle entrypoint + non-perturbation + ±10 confirmed-vs-provisional), QST-05 (drop `:890`/keep `:893` O1 fix + the §5.3 afking-settle nuance + `handleLootBox :698-741`/`IDegenerusQuests:107` dead-code removal), OPEN (OPEN-01 cheapest shared materialization + OPEN-02 re-verification), and the XMODEL-01 (C1–C5 + disposition headers) + SPEC Lock PENDING placeholders.

## Task Commits

Each task was committed atomically:

1. **Task 1: Anchor attestation table** — `e4ec0e1d` (docs)
2. **Task 2: AFF-01/AFF-02 + in-slot accumulator + threat re-attestation** — `9580e806` (docs)
3. **Task 3: AGG/TKT/QST/OPEN feeds + O1 fix + XMODEL/Lock placeholders** — `df09381b` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS bookkeeping commit) — see final docs commit.

## Files Created/Modified
- `.planning/phases/353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode/353-SPEC.md` (created, 247 lines) — the v56.0 design-lock DRAFT.

## Decisions Made
- **In-slot accumulator (supersedes RESEARCH §3 Option B):** the attested `Sub` slot is at 232/256 (24 spare), so the naive "spare-bits" premise (176/256) is wrong AND the new-dedicated-slot recommendation is no longer the best answer — instead RE-PACK the slot (whole-BURNIE affiliate base uint32 + 100M saturating clamp + amount→milli-ETH uint96→~uint32 + validThroughLevel/day-markers uint32→uint24, dropping `windowStartDay` for a global ~10-day epoch) so the accumulator (`affiliateBase` + `lastSettledDay` + `questProgress`) fits in the same warm slot with NO new cold SSTORE. This is the USER-locked decision (2026-06-01) and is cheaper than Option B. Exact widths deferred to IMPL 354.
- **AFF-02 force-flush DECLINED** — the 5%-proportional DGNRS claim reads cumulative score (exact regardless of option-A lag), so only the minority 1%-top ranking lags (accepted, D-07).
- **Century bonus KEPT at parity** (D-10 flipped 2026-06-01) — amortized-negligible; reuses existing `centuryBonusLevel`/`centuryBonusUsed` storage + the per-buy score.

## Deviations from Plan

None — plan executed exactly as written. All 3 tasks' `<action>`/`<acceptance_criteria>` satisfied; all automated `<verify>` blocks returned PASS; the paper-only guard (`git diff --quiet 453f8073 HEAD -- contracts/`) stayed clean throughout. The accumulator-layout decision intentionally supersedes RESEARCH §3's Option-B recommendation — that supersession is itself the plan's locked instruction (the plan frontmatter + `<action>` mandate the in-slot re-pack), not a deviation.

## Issues Encountered
- The `.planning/` tree is gitignored but its planning artifacts are tracked (force-added by prior phases). Resolved by staging `353-SPEC.md` with `git add -f` (matching how the sibling `353-*.md` docs are tracked). No impact on content.

## User Setup Required
None — no external service configuration required (paper-only SPEC phase).

## Next Phase Readiness
- **Plan 02 (XMODEL cross-model design-input pass) is ready:** the `## XMODEL-01 Cross-Model Design-Input (PENDING — Plan 02)` placeholder lists the C1–C5 concerns + the disposition-table headers; the `## SPEC Lock (PENDING ...)` placeholder is in place for Plan 02 to flip after folding the codex+gemini disposition table. Both CLIs were confirmed installed (RESEARCH §7).
- **IMPL 354 inherits a fully-reconciled design-lock** (zero "by construction"): the in-slot accumulator principles (exact widths confirmed at 354), the AGG/TKT/QST/QST-05/OPEN design fixed, the O1 two-half fix, and the per-invariant TST-356 proof obligations.
- **No blockers.** The SPEC stays DRAFT until Plan 02 runs XMODEL and flips the SPEC Lock.

## Self-Check: PASSED

- `353-SPEC.md` exists: FOUND.
- Commits exist: `e4ec0e1d` FOUND, `9580e806` FOUND, `df09381b` FOUND.
- All 12 required sections present (Anchor Attestation, AFF-01, AFF-02, Accumulator Layout, Threat Model Re-Attestation, AGG, TKT, QST, QST-05 O1 Fix, OPEN, XMODEL-01 PENDING, SPEC Lock PENDING).
- ZERO `contracts/*.sol` mutation: `git diff --quiet 453f8073 HEAD -- contracts/` clean throughout.

---
*Phase: 353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode*
*Completed: 2026-06-01*
