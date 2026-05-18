---
phase: 294-deity-pass-gold-nerf-dpnerf
plan: 01
subsystem: audit
tags: [audit, deity-pass, gold-nerf, design-intent-trace, measurement-scaffold, pre-patch-gate, v42.0, dpnerf]

requires:
  - phase: 292-hero-override-weighted-roll-hrroll
    provides: storage+ABI byte-identity attestation chain Phase 294 inherits and re-attests on top of (intermediate anchor in §1)
  - phase: 290-mint-batch-event-sig-cleanup-mintcln
    provides: 3-sidecar plan-artifact pattern (PLAN + DESIGN-INTENT-TRACE + MEASUREMENT) reused at Phase 294
provides:
  - 294-01-DESIGN-INTENT-TRACE.md (DPNERF-06 4-section trace + 5 anchors + out-of-scope register + SWEEP-02(iii) pre-emptive answers + RNG-methodology disposition + Sister-Plan Coverage Map)
  - 294-01-MEASUREMENT.md (6-section scaffold; §1 + §3 FINAL at Plan 01 time; §2/§4/§5/§6 carry FILL-IN-Plan-02 placeholders Plan 02 populates post-patch)
  - Design-intent-before-deletion gate satisfied (feedback_design_intent_before_deletion.md) — Plan 02 unblocked for its contract-patch task
affects: [294-02 (contract patch task; reads both sidecars + copies §1 + §3 forward into commit body), 295 (TST-DPNERF references audit-subject commit + 4-callsite enumeration), 296 (SWEEP DPNERF hypothesis surface extends to all 4 callsites per D-294-CALLER-UNIFORM-01), 297 (§3.A delta-surface table cites all 4 callsites under DPNERF row)]

tech-stack:
  added: []
  patterns:
    - "3-sidecar plan-artifact pattern (PLAN + DESIGN-INTENT-TRACE + MEASUREMENT) extended from Phase 290/292 precedent"
    - "AGENT-COMMITTED planning artifacts (no contract/test edits → no user-approval gate) per feedback_no_contract_commits.md"
    - "FINAL-at-Plan-01 sections (§1 + §3) + FILL-IN-Plan-02 placeholder sections (§2 + §4 + §5 + §6) in MEASUREMENT.md scaffold"
    - "Theoretical-first bytecode-delta attestation per feedback_gas_worst_case.md (no empirical second-pass at Phase 294 — TST-DPNERF-01..05 ships no gas-regression test)"

key-files:
  created:
    - .planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md
    - .planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-MEASUREMENT.md
    - .planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-SUMMARY.md
  modified: []

key-decisions:
  - "D-42N-GOLD-FLOOR-01 (user-locked 2026-05-17): gold-tier (color==7) virtualCount=1 flat; commons (color in [0..6]) virtualCount=max(len/50,2) UNCHANGED"
  - "D-42N-DEITY-EV-01 (user-locked 2026-05-17): intentional EV reduction; no common-tier compensation; commons-bump and rebias-toward-commons REJECTED"
  - "D-42N-PATH-COVERAGE-01 (user-locked 2026-05-17): single _randTraitTicket body change reaches both ETH and BURNIE paths; no callsite flag; ETH-only alternative REJECTED"
  - "D-294-CALLER-UNIFORM-01 (planner-locked 2026-05-17): all 4 _randTraitTicket callsites (L698 + L988 + L1296 + L1399) uniform by construction; SWEEP scope extended to all 4 callsites"
  - "D-294-NATSPEC-01 (planner-locked 2026-05-17): 5-line two-tier 'what IS' comment shape at L1721-1723; zero history language; zero decision-anchor citations in source comments"

patterns-established:
  - "DPNERF design-intent-before-deletion gate: AGENT-COMMITTED 4-section trace + measurement scaffold land BEFORE the contract patch lands"
  - "Out-of-scope register enumerates 17 items (a..q) explicitly per REQUIREMENTS.md + CONTEXT.md surface-tree carve-outs"
  - "SWEEP-02(iii) DPNERF adversarial-hypothesis pre-emptive answers (4 hypotheses: all-4-callsite uniformity / carryover-ticket-distribution uniformity / secondary-strategy destabilization / ETH vs BURNIE differential-behavior) recorded in trace doc for Phase 296 baseline disposition"

requirements-completed: [DPNERF-02, DPNERF-03, DPNERF-04, DPNERF-05, DPNERF-06]

duration: ~3 min
completed: 2026-05-17
---

# Phase 294 Plan 01: DPNERF Design-Intent Trace + Measurement Scaffold Summary

**AGENT-COMMITTED pre-patch gate landed: 5 decision anchors (D-42N-GOLD-FLOOR-01 + D-42N-DEITY-EV-01 + D-42N-PATH-COVERAGE-01 + D-294-CALLER-UNIFORM-01 + D-294-NATSPEC-01) + 4-section DPNERF-06 trace + 6-section measurement scaffold with §1 audit baseline and §3 callsite enumeration FINAL at Plan 01 time; Plan 02 contract-patch task unblocked.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-05-17T~13:33Z
- **Completed:** 2026-05-17T~13:36Z
- **Tasks:** 2
- **Files created:** 2 (planning artifacts only; zero `contracts/` / `test/` / `KNOWN-ISSUES.md` edits)

## Accomplishments

### Trace Doc Anchor Coverage (Task 1)

All 5 phase-scope decision anchors recorded verbatim in `294-01-DESIGN-INTENT-TRACE.md`:

- `D-42N-GOLD-FLOOR-01` ✓
- `D-42N-DEITY-EV-01` ✓
- `D-42N-PATH-COVERAGE-01` ✓
- `D-294-CALLER-UNIFORM-01` ✓
- `D-294-NATSPEC-01` ✓

Carry-forward anchors cited for completeness: `D-42N-MILESTONE-OPEN-01` + `D-281-FIX-SHAPE-01` + `D-288-FIX-SHAPE-01` + `D-271-ADVERSARIAL-01/02/03`.

DPNERF-06 4-section trace structure:
- §(i) original `virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2` rationale — small-bucket baseline payout for deity-pass holders; v41 design treated all 8 colors uniformly
- §(ii) gold-tile concentration issue — small gold buckets × min-2 floor produce 3-7% deity-win probability vs the 2%-target; over-extraction documented with example bucket sizes
- §(iii) compensation trade-offs (3 alternatives: constant-EV-via-commons-bump REJECTED / intentional reduction LOCKED / rebias-toward-commons REJECTED)
- §(iv) path-coverage trade-offs (3 alternatives: ETH-only REJECTED / both ETH+BURNIE symmetric / all-4-callsite uniform LOCKED)

Out-of-scope register enumerates 17 items (a..q) covering REQUIREMENTS.md lines 22-27 + CONTEXT.md `<code_context>` Out-of-Scope Source-Tree Surfaces + Claude's Discretion dispositions.

SWEEP-02(iii) DPNERF adversarial-hypothesis pre-emptive answers recorded for Phase 296 baseline:
- Hypothesis 1 (all-4-callsite uniformity) → SAFE_BY_DESIGN
- Hypothesis 2 (carryover-ticket-distribution path uniformity) → SAFE_BY_STRUCTURAL_UNIFORMITY
- Hypothesis 3 (secondary-strategy destabilization) → SAFE_BY_INTENT
- Hypothesis 4 (ETH vs BURNIE differential-behavior) → SAFE_BY_CONSTRUCTION

RNG audit-methodology disposition explicit: `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` NOT applicable to Phase 294 (DPNERF doesn't introduce a new RNG consumer; commitment-window invariant unchanged).

Sister-Plan Coverage Map populated for all 6 DPNERF-NN requirements showing Plan 01 vs Plan 02 split.

### Scaffold Doc Section Coverage (Task 2)

All 6 attestation section headers present in `294-01-MEASUREMENT.md`:

- §1 Audit Baseline ✓ (FINAL at Plan 01 time; `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` + Phase 292 close intermediate anchor)
- §2 Storage Byte-Identity Attestation (DPNERF-04) ✓ (`<FILL-IN-Plan-02>` placeholders for forge inspect storageLayout EMPTY diff)
- §3 Callsite Enumeration (D-294-CALLER-UNIFORM-01) ✓ (FINAL at Plan 01 time; 4 callsites L698 + L988 + L1296 + L1399 + BURNIE path via payDailyCoinJackpot → _awardDailyCoinToTraitWinners)
- §4 Public ABI Byte-Identity Attestation (DPNERF-05) ✓ (`<FILL-IN-Plan-02>` placeholders for forge inspect methodIdentifiers EMPTY diff)
- §5 Theoretical Bytecode-Delta Estimate ✓ (FRAMEWORK FINAL at Plan 01 time; pre/post-patch bytecode shape + ~+10-30 byte analytical estimate + "no empirical second-pass at Phase 294" disposition per `feedback_gas_worst_case.md`; only post-patch byte count fills at Plan 02)
- §6 Zero-New-State Grep-Proof (DPNERF-04 strengthening) ✓ (`<FILL-IN-Plan-02>` placeholders for post-patch SSTORE/SLOAD grep evidence)

15 `<FILL-IN-Plan-02>` placeholders across §2 + §4 + §5 + §6; ZERO placeholders in §1 + §3 (both FINAL).

### Line Counts

- `294-01-DESIGN-INTENT-TRACE.md`: **206 lines** (acceptance criterion ≥ 90).
- `294-01-MEASUREMENT.md`: **171 lines** (acceptance criterion ≥ 40).
- `294-01-SUMMARY.md`: this file.

## Task Commits

Each task was committed atomically:

1. **Task 1: Author 294-01-DESIGN-INTENT-TRACE.md** — `109fc9e1` (docs)
2. **Task 2: Author 294-01-MEASUREMENT.md scaffold** — `50cb625d` (docs)

Plan metadata commit follows this SUMMARY.

## Files Created/Modified

- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md` — DPNERF-06 4-section trace + 5 decision anchors + 17-item out-of-scope register + SWEEP-02(iii) pre-emptive answers + RNG audit-methodology disposition + Sister-Plan Coverage Map + 13-row source-citations table. AGENT-COMMITTED.
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-MEASUREMENT.md` — 6-section attestation scaffold. §1 audit baseline + §3 callsite enumeration FINAL at Plan 01 time; §2/§4/§5/§6 carry `<FILL-IN-Plan-02>` placeholders Plan 02 populates post-patch. AGENT-COMMITTED.
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-SUMMARY.md` — this file (plan completion record).

`git diff --name-only HEAD -- contracts/ test/ KNOWN-ISSUES.md` is **EMPTY** post-plan ✓ (zero contract / test / KI edits as required).

## Decisions Made

None new at execution time. All 5 phase-scope decision anchors were locked at CONTEXT-gathering (user-locked: D-42N-GOLD-FLOOR-01 + D-42N-DEITY-EV-01 + D-42N-PATH-COVERAGE-01 on 2026-05-17 per ROADMAP.md; planner-locked: D-294-CALLER-UNIFORM-01 + D-294-NATSPEC-01 per CONTEXT.md `<decisions>`). Plan 01 records these anchors in the AGENT-COMMITTED trace doc; no new decisions taken.

## Deviations from Plan

None — plan executed exactly as written. Both tasks landed verbatim per the `<action>` specifications in `294-01-PLAN.md`; all acceptance criteria pass on first attempt; the 9-point `<verification>` block passes:

1. `294-01-DESIGN-INTENT-TRACE.md` exists ✓
2. `294-01-MEASUREMENT.md` exists ✓
3. All 5 phase-scope anchors present (29 grep matches across the doc) ✓
4. All 4 DPNERF-06 trace sections present (4 grep matches) ✓
5. All 6 measurement attestation headers present (9 grep matches including §5 sub-headers) ✓
6. All 4 callsite line numbers cited in §3 (5 grep matches across the doc) ✓
7. `git diff --name-only HEAD -- contracts/ test/ KNOWN-ISSUES.md` is EMPTY ✓
8. `git status --porcelain .planning/phases/294-deity-pass-gold-nerf-dpnerf/` shows the two new artifacts staged + committed ✓
9. Both files AGENT-COMMITTED (no user-approval gate triggered; zero `contracts/` or `test/` edits) ✓

## Issues Encountered

None. Plan-execution context was load-bearing-complete from CONTEXT.md + PLAN.md + sister precedent docs (Phase 290 + Phase 292 trace + measurement); no codebase exploration needed beyond the @-references already provided by the planner.

## User Setup Required

None — Plan 01 is AGENT-COMMITTED planning-artifact authoring. No external service configuration, no environment variables, no user approval gate fired.

## Next Phase Readiness

**Plan 02 may now begin its contract-patch task per the design-intent-before-deletion gate per `feedback_design_intent_before_deletion.md`.** Both AGENT-COMMITTED Plan 01 artifacts exist at the paths in `files_modified`:
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md`
- `.planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-MEASUREMENT.md`

Plan 02's first task reads both artifacts and copies forward:
- The 5 decision anchors → batched contract commit message body
- §1 audit baseline + §3 callsite enumeration (FINAL at Plan 01 time) → commit body verbatim
- §2 + §4 + §5 + §6 (`<FILL-IN-Plan-02>` placeholders) → Plan 02 populates post-patch with `forge inspect storageLayout` EMPTY diff + `forge inspect methodIdentifiers` EMPTY diff + actual bytecode-delta byte count + post-patch SSTORE/SLOAD grep evidence

Plan 02 contract-patch task is USER-APPROVAL gated per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`. The planner has NOT pre-approved the contract diff; Plan 02's executor presents the full diff to the user for explicit review before staging or committing.

Downstream Phase 295 / 296 / 297 hand-off:
- Phase 295 TST-DPNERF-01..05 references the audit-subject commit (Plan 02 batched commit) + the 4-callsite enumeration in §3
- Phase 296 SWEEP DPNERF hypothesis surface uses the SWEEP-02(iii) pre-emptive answers as baseline disposition record
- Phase 297 §3.A delta-surface table cites all 4 callsites by line number under the DPNERF row per `D-294-CALLER-UNIFORM-01`

## Self-Check: PASSED

Verified all artifacts and commits exist:

- `[ -f .planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md ]` → FOUND ✓
- `[ -f .planning/phases/294-deity-pass-gold-nerf-dpnerf/294-01-MEASUREMENT.md ]` → FOUND ✓
- `git log --oneline -3 | grep 109fc9e1` → FOUND (Task 1 commit) ✓
- `git log --oneline -3 | grep 50cb625d` → FOUND (Task 2 commit) ✓
- `git diff --name-only HEAD -- contracts/ test/ KNOWN-ISSUES.md` → EMPTY ✓
- All 5 phase-scope anchors grep-matched in trace doc (29 occurrences) ✓
- All 4 DPNERF-06 trace section headers present in trace doc ✓
- All 6 measurement attestation section headers present in scaffold doc ✓
- All 4 callsite line numbers cited in §3 of scaffold doc ✓
- §1 + §3 of scaffold doc carry zero `<FILL-IN-Plan-02>` placeholders (FINAL at Plan 01 time) ✓
- §2 + §4 + §5 + §6 of scaffold doc carry 15 `<FILL-IN-Plan-02>` placeholders (Plan 02 populates post-patch) ✓

---

*Phase: 294-deity-pass-gold-nerf-dpnerf*
*Plan: 01*
*Completed: 2026-05-17*
