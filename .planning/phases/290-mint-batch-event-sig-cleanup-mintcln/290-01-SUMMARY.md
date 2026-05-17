---
phase: 290-mint-batch-event-sig-cleanup-mintcln
plan: 01
subsystem: audit
tags: [audit, mint-batch, event-cleanup, signature-cleanup, design-intent-trace, v42.0, planning-artifact]

# Dependency graph
requires:
  - phase: v41.0 (closed)
    provides: MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4 (audit baseline; trace + scaffold anchor against this SHA)
  - phase: v41.0 Phase 281 (mint-batch-determinism-fix-fix)
    provides: D-281-STARTINDEX-SEMANTICS-01 + D-281-FIX-SHAPE-01 (v41 anchors being cleaned up at v42)
  - phase: v40.0 Phase 277
    provides: D-40N-EVT-BREAK-01 (operational precedent for the v42 breaking-topic-hash posture; D-42N-EVT-BREAK-01 inherits this disposition verbatim)
provides:
  - 290-01-DESIGN-INTENT-TRACE.md — MINTCLN-10 3-section design-intent trace + decision anchors D-42N-MINTCLN-SCOPE-01 + D-42N-EVT-BREAK-01 + carry-forward anchors + out-of-scope register + sister-plan coverage map + SWEEP-02(i) MINTCLN adversarial-hypothesis pre-emptive answers + Plan-02 pre-patch-gate statement
  - 290-01-MEASUREMENT.md — 6-section attestation scaffold (bytecode delta / storage-slot grep / worst-case gas / selectors / event topic hashes / B2-symmetric-callsite diff check) with FILL-IN-Plan-02 placeholders
  - design-intent-before-deletion gate SATISFIED — Plan 02 cleared to begin its contract-edit task
affects: [290-02 (contract patch reads both artifacts), 291 TST-MINTCLN, 296 SWEEP (adversarial-hypothesis baseline), 297 AUDIT (§9 Deferred to Future Milestones cites the same anchors)]

# Tech tracking
tech-stack:
  added: []  # planning artifacts only; zero contract / test / tooling additions
  patterns:
    - "design-intent-before-deletion gate per feedback_design_intent_before_deletion.md — record original-design rationale for what is about to be deleted/restructured BEFORE the contract patch lands"
    - "measurement scaffold as verbatim copy-forward source for batched commit message body per feedback_no_history_in_comments.md — numerical attestations live in commit body, not NatSpec"
    - "decision-anchor naming convention D-42N-* for v42.0 milestone (parallels D-40N-* / D-41N-* carry-forward chain)"

key-files:
  created:
    - .planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md
    - .planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md
  modified: []

key-decisions:
  - "D-42N-MINTCLN-SCOPE-01 — narrow scope; helper-extraction deferred to v43+; duplicate-logic (processFutureTicketBatch inline loop vs processTicketBatch + _processOneTicketEntry split) flagged-only at v42; processed += take vs processed += writesUsed >> 1 asymmetry flagged but NOT touched (user disposition 2026-05-17)"
  - "D-42N-EVT-BREAK-01 — breaking TraitsGenerated topic-hash accepted at v42 under pre-launch posture; inherits v40 D-40N-EVT-BREAK-01 disposition verbatim; indexer-migration tooling is a forward-handoff in audit/FINDINGS-v42.0.md §9 at Phase 297; tooling NOT produced at v42 (user disposition 2026-05-17)"
  - "_processOneTicketEntry zero-owed→rolled-to-1 stale-low-32-baseKey disposition recorded as ACCEPTABLE under structural-closure reasoning (single-trait emission only; no multi-call drain follows; upper-bit + groupIdx distinctness preserved; keccak uniformity satisfied for any low-32-bit value) — routed to Phase 296 SWEEP-02(i) adversarial re-pass"
  - "Trace doc IS a planning artifact and DOES contain historical rationale by design — feedback_no_history_in_comments.md applies to NatSpec / contract source comments only, NOT to planning artifacts (this is the inverse of the comment rule)"

patterns-established:
  - "Phase-290-style pre-patch gate: Plan 01 lands the design-intent trace + measurement scaffold as AGENT-COMMITTED planning artifacts before Plan 02's contract-patch task begins — applicable to any future cleanup phase that deletes / restructures previously-fixed code"
  - "Measurement scaffold structure (6 sections: bytecode delta / storage-slot grep / worst-case gas / selectors / event topic hashes / B2-symmetric-callsite diff check) as reusable framework for any contract refactor with byte-identity locks"
  - "SWEEP-02 adversarial-hypothesis pre-emptive answers in the trace doc seed the Phase-N+6 SWEEP baseline — adversarial pass has a documented disposition to test against, not a cold-start"

requirements-completed: [MINTCLN-10]

# Metrics
duration: ~10min
completed: 2026-05-17
---

# Phase 290 Plan 01: MINTCLN Pre-Patch Gate Summary

**Design-intent trace + measurement scaffold AGENT-COMMITTED as the design-intent-before-deletion gate for the v42.0 MINTCLN contract patch; D-42N-MINTCLN-SCOPE-01 + D-42N-EVT-BREAK-01 anchors locked; Plan 02 cleared to begin its contract-edit task.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-17T05:33:00Z
- **Completed:** 2026-05-17T05:43:00Z
- **Tasks:** 2 (both AGENT-COMMITTED; zero contract / test edits)
- **Files modified:** 2 created, 0 modified

## Accomplishments

- `290-01-DESIGN-INTENT-TRACE.md` lands at 142 lines covering all three MINTCLN-10 trace sections — (i) original 4-input hash rationale + why `ownedSalt` was passed as a separate 6th positional arg at v41 Phase 281, (ii) original `TraitsGenerated` field-set rationale + `startIndex` naming at v41 Phase 281, (iii) breaking-topic-hash justification under pre-launch posture + indexer-migration handoff inheriting v40 D-40N-EVT-BREAK-01.
- Two phase-scope decision anchors recorded verbatim with user-disposition date 2026-05-17: **D-42N-MINTCLN-SCOPE-01** (narrow scope; no helper extraction) + **D-42N-EVT-BREAK-01** (breaking topic-hash accepted pre-launch).
- Carry-forward anchors recorded: **D-40N-EVT-BREAK-01** (v40 indexer-migration precedent), **D-40N-MINTBOOST-OUT-01** (mint-boost retention), **D-281-STARTINDEX-SEMANTICS-01** (v41 anchor being cleaned up), **D-281-FIX-SHAPE-01** (v41 anchor being cleaned up).
- Out-of-Scope register enumerates **6 items** NOT touched by Phase 290 (helper-extraction, processed-semantics asymmetry, storage-layout, indexer-rebuild tooling, mint-boost fractional retirement, non-`TraitsGenerated` event topic hashes).
- SWEEP-02(i) MINTCLN adversarial-hypothesis pre-emptive answers seeded for Phase 296: 3-input hash determinism re-break (SAFE_BY_STRUCTURAL_CLOSURE), owed-in-baseKey shape-collision griefing (SAFE_BY_DESIGN), breaking-topic-hash parsing-ambiguity vector (SAFE_BY_DESIGN).
- Subtle `_processOneTicketEntry` zero-owed→rolled-to-1 disposition documented as ACCEPTABLE — routes to Phase 296 SWEEP-02(i) for adversarial confirmation.
- Sister-Plan Coverage Map maps MINTCLN-01..10 to Phase 290 plans (MINTCLN-10 → Plan 01; MINTCLN-01..09 → Plan 02 with sub-mapping for 08 + 09 to scaffold §(2) + §(4)/(5)).
- `290-01-MEASUREMENT.md` lands at 99 lines with all 6 attestation section headers + audit-baseline anchor + canonical-form signature strings (both v41 6-field and v42 3-field `TraitsGenerated` signatures recorded as text for the breaking-change structural attestation) + `FILL-IN-Plan-02` placeholders Plan 02 populates post-patch.
- Worst-case gas section provides full theoretical-first derivation framework per `feedback_gas_worst_case.md`: anchor case + per-`_raritySymbolBatch`-invocation delta (`~-30 gas`) + per-`TraitsGenerated`-emit delta (`~-375 gas` from `LOG3 → LOG2` topic cost transition) + cross-call drain total (`~-8100 gas` worst-case) — Plan 02 populates numerical values; framework is LOCKED here.
- B2-symmetric-callsite diff-check method specified (sed-line-range structural diff at the 3 paired callsites mint:423-425/800-802 + mint:469/803 + mint:470-477/804-811).
- Plan-02 pre-patch gate statement present; Plan 02 may now begin Task 2 (contract patch) per the design-intent-before-deletion gate.

## Task Commits

Each task was committed atomically (force-added because `.planning/phases/` is gitignored — matches project pattern at commits `a2e24593` and `e38d944f`):

1. **Task 1: Design-intent trace doc** — `7260e2b7` (docs(290-01): design-intent trace for MINTCLN cleanup (MINTCLN-10 pre-patch gate))
2. **Task 2: Measurement scaffold doc** — `92a6f4ac` (docs(290-01): measurement scaffold for MINTCLN attestations (MINTCLN-08 + MINTCLN-09))

## Files Created/Modified

- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md` (142 lines) — MINTCLN-10 3-section design-intent trace + decision anchors + carry-forward anchors + out-of-scope register + SWEEP-02(i) adversarial-hypothesis pre-emptive answers + sister-plan coverage map + Plan-02 pre-patch-gate statement + source citations.
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md` (99 lines) — 6-section measurement scaffold (bytecode delta / storage-slot grep / worst-case gas / selectors / event topic hashes / B2-symmetric-callsite diff check) with FILL-IN-Plan-02 placeholders + audit-baseline anchor + canonical signature strings + source-doc cross-cite.

## Frozen-Contract Discipline Attestation

`git diff --name-only HEAD~2..HEAD -- contracts/ test/ KNOWN-ISSUES.md` is **EMPTY** post-plan. Zero contract / test / KNOWN-ISSUES modifications across both task commits. Plan 01 is incapable of touching contract source by design — its mutation surface is bounded to two paths under `.planning/phases/290-*/`. T-290-01-06 STRIDE threat (frozen-contract discipline drift) DISPOSITIONED **accept**; surface area bounded to planning artifacts.

## Trace Doc Anchor Coverage

| Anchor | Present | Role |
|--------|---------|------|
| D-42N-MINTCLN-SCOPE-01 | yes | Phase 290 scope anchor (narrow; no helper extraction) |
| D-42N-EVT-BREAK-01 | yes | Phase 290 breaking-topic-hash anchor (pre-launch posture) |
| D-40N-EVT-BREAK-01 | yes | v40 carry-forward (operational precedent for D-42N-EVT-BREAK-01) |
| D-40N-MINTBOOST-OUT-01 | yes | v40 carry-forward (mint-boost retention) |
| D-281-STARTINDEX-SEMANTICS-01 | yes | v41 carry-forward (anchor being cleaned up) |
| D-281-FIX-SHAPE-01 | yes | v41 carry-forward (anchor being cleaned up) |

## Scaffold Doc Section Coverage

| Section | Header | Anchor / Lock |
|---------|--------|---------------|
| (1) Bytecode Delta | yes | vs MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4 |
| (2) Storage-Slot Grep Proof | yes | MINTCLN-08 byte-identity lock |
| (3) Worst-Case Gas | yes | theoretical-first per feedback_gas_worst_case.md |
| (4) Selector Attestations | yes | MINTCLN-09 byte-identity lock for processFutureTicketBatch + processTicketBatch + _processOneTicketEntry |
| (5) Event Topic Hash Attestations | yes | MINTCLN-04 breaking change (TraitsGenerated only) + MINTCLN-09 byte-identity lock (TicketsCredited + TicketsQueued) |
| (6) B2-Symmetric-Callsite Diff Check | yes | v41 Phase 281 precedent |

## Line Counts

- `290-01-DESIGN-INTENT-TRACE.md`: 142 lines (≥ 90 required → PASS)
- `290-01-MEASUREMENT.md`: 99 lines (≥ 35 required → PASS)

## Decisions Made

- **D-42N-MINTCLN-SCOPE-01** locked at user disposition 2026-05-17. Helper-extraction (`processFutureTicketBatch` inline loop vs `processTicketBatch` + `_processOneTicketEntry` split duplicate-logic) flagged-only at v42; deferred to v43+ maintenance bundle per `feedback_design_intent_before_deletion.md` discipline (trace original design intent before consolidation at that future milestone).
- **D-42N-EVT-BREAK-01** locked at user disposition 2026-05-17. Breaking `TraitsGenerated` topic-hash accepted; inherits v40 D-40N-EVT-BREAK-01 posture verbatim; indexer-migration tooling is a forward-handoff at Phase 297 §9 (NOT produced at v42).
- **`_processOneTicketEntry` zero-owed→rolled-to-1 stale-low-32-baseKey** disposition: ACCEPTABLE under structural-closure reasoning (single-trait emission; no multi-call drain follows; upper-bit + `groupIdx` distinctness preserved; keccak uniformity satisfied for any low-32-bit value). Routes to Phase 296 SWEEP-02(i) for adversarial confirmation; expected re-pass outcome SAFE_BY_STRUCTURAL_CLOSURE. Plan 02 is NOT expected to add a separate `_raritySymbolBatch`-callsite rebuild after the `_resolveZeroOwedRemainder` return in this branch (would expand MINTCLN scope).
- Trace doc DOES contain historical rationale by design — `feedback_no_history_in_comments.md` applies to NatSpec / contract source comments only, NOT to planning artifacts (the planning artifact IS the load-bearing historical-rationale record per `feedback_design_intent_before_deletion.md`).

## Deviations from Plan

None — plan executed exactly as written. Both tasks produced the artifacts specified in `must_haves.artifacts`; all `acceptance_criteria` automated `<verify>` blocks PASS; zero contract / test / KNOWN-ISSUES edits per `feedback_no_contract_commits.md`.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. Both artifacts are AGENT-COMMITTED planning docs.

## Next Phase Readiness

- **Plan 02 (`290-02-PLAN.md`) cleared to begin its contract-edit task.** The design-intent-before-deletion gate per `feedback_design_intent_before_deletion.md` is satisfied. Plan 02's first task reads both Plan-01 artifacts; the measurement scaffold's `<FILL-IN-Plan-02>` placeholders are populated post-patch from the v42 close HEAD measurements; the populated values feed verbatim into Plan 02 Task 5's batched commit message body (checkpoint:human-verify).
- **Phase 296 SWEEP-02(i) MINTCLN adversarial baseline** is seeded in `290-01-DESIGN-INTENT-TRACE.md` — the 3 pre-emptive answers (determinism re-break, shape-collision griefing, parsing-ambiguity vector) serve as the disposition record Phase 296 tests against.
- **Phase 297 AUDIT-09 §9 "Deferred to Future Milestones" register** has its anchor IDs ready to copy-forward: `D-42N-MINTCLN-SCOPE-01` (helper-extraction handoff to v43+) + `D-42N-EVT-BREAK-01` (indexer-migration handoff). Forward-cite zero-emission discipline maintained (descriptive labels + anchor IDs only; no numeric milestone references).

## Hand-off Statement

Plan 02 may now begin Task 2 (contract patch) per the design-intent-before-deletion gate per `feedback_design_intent_before_deletion.md`. Both Plan-01 artifacts exist at the paths in `files_modified`; `git diff --name-only HEAD~2..HEAD -- contracts/ test/ KNOWN-ISSUES.md` is EMPTY post-plan.

## Self-Check: PASSED

- `[x]` 290-01-DESIGN-INTENT-TRACE.md exists at the expected path (verified via `test -f`)
- `[x]` 290-01-MEASUREMENT.md exists at the expected path (verified via `test -f`)
- `[x]` Task 1 commit `7260e2b7` exists (verified via `git log`)
- `[x]` Task 2 commit `92a6f4ac` exists (verified via `git log`)
- `[x]` All required anchors present in trace doc (verified via `grep -q` chain on D-42N-MINTCLN-SCOPE-01, D-42N-EVT-BREAK-01, D-40N-EVT-BREAK-01, D-40N-MINTBOOST-OUT-01, D-281-STARTINDEX-SEMANTICS-01, MILESTONE_V41_AT_HEAD baseline)
- `[x]` All 6 scaffold section headers present (verified via `grep -qE` chain on Bytecode Delta, Storage-Slot Grep Proof, Worst-Case Gas, Selector Attestations, Event Topic Hash, B2-Symmetric)
- `[x]` Both `TraitsGenerated` canonical signatures present in scaffold (v41 6-field + v42 3-field)
- `[x]` `processFutureTicketBatch(uint24,uint256)` canonical signature present in scaffold
- `[x]` `FILL-IN-Plan-02` placeholders present in scaffold for all 6 sections
- `[x]` Line counts ≥ thresholds (trace 142 ≥ 90; scaffold 99 ≥ 35)
- `[x]` Zero contract / test / KNOWN-ISSUES modifications across both task commits (verified via `git diff --name-only HEAD~2..HEAD -- contracts/ test/ KNOWN-ISSUES.md` returning EMPTY)

---
*Phase: 290-mint-batch-event-sig-cleanup-mintcln*
*Plan: 01*
*Completed: 2026-05-17*
