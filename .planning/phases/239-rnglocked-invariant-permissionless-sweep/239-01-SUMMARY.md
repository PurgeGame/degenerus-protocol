---
phase: 239-rnglocked-invariant-permissionless-sweep
plan: 239-01
subsystem: audit
tags: [v30.0, VRF, RNG-01, rngLockedFlag, state-machine, invariant-proof, fresh-eyes, HEAD-7ab515fe]
head_anchor: 7ab515fe

# Dependency graph
requires:
  - phase: 237-vrf-consumer-inventory-call-graph
    provides: "audit/v30-CONSUMER-INVENTORY.md Consumer Index RNG-01 scope (106-row Named Gate = rngLocked subset per 238-03 SUMMARY: 90 PREFIX-DAILY + 7 PREFIX-GAMEOVER + 6 library-wrapper + 3 request-origination)"
provides:
  - "audit/v30-RNGLOCK-STATE-MACHINE.md — RNG-01 deliverable per D-04: Set-Site Table (1 row) + Clear-Site Table (3 rows) + Path Enumeration Table (9 rows) + Invariant Proof + Prior-Artifact Cross-Cites + Finding Candidates + Scope-Guard Deferrals + Attestation at HEAD 7ab515fe."
  - "Verdict distribution: Set-Site AIRTIGHT=1 / Clear-Site AIRTIGHT=3 / Path SET_CLEARS_ON_ALL_PATHS=7 (P-001, P-002, P-003, P-005, P-006, P-007, P-008) / Path CLEAR_WITHOUT_SET_UNREACHABLE=2 (P-004, P-009) / CANDIDATE_FINDING=0. RNG-01 AIRTIGHT."
  - "Phase 238-03 FWD-03 gating rngLocked audit assumption (Scope-Guard Deferral #1 in audit/v30-FREEZE-PROOF.md) DISCHARGED by this plan commit per D-29."
affects: [239-02-permissionless-sweep, 239-03-asymmetry-re-justification, 240-gameover-jackpot-safety, 241-exception-closure, 242-findings-consolidation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-04 Set-Site + Clear-Site + Path Enumeration tabular format (Phase 235 D-07 pattern extended to state-machine analysis)"
    - "D-05 closed verdict taxonomy {AIRTIGHT / CANDIDATE_FINDING} for Set/Clear sites; {SET_CLEARS_ON_ALL_PATHS / CLEAR_WITHOUT_SET_UNREACHABLE / CANDIDATE_FINDING} for Path rows — no hedged verdicts"
    - "D-06 L1700 revert-safety enumerated as dedicated Clear-Site-Ref (RNGLOCK-239-C-03) + dedicated Path row (RNGLOCK-239-P-002)"
    - "D-07 12h retry-timeout path enumerated as dedicated Path row (RNGLOCK-239-P-004 — CLEAR_WITHOUT_SET_UNREACHABLE semantics)"
    - "D-19 gameover-VRF-request bracket bookkeeping IN scope (Path RNGLOCK-239-P-007); jackpot-input determinism OUT (Phase 240 GO-02)"
    - "D-22 no F-30-NN finding-ID emission — none needed because zero CANDIDATE_FINDING rows surfaced"
    - "D-25 tabular / grep-friendly / no mermaid (prose-diagram in ASCII ` ▼ ┘ ` characters per CONTEXT.md Claude's Discretion)"
    - "D-26 HEAD anchor 7ab515fe locked in frontmatter + echoed in audit file Attestation"
    - "D-27 READ-only — zero contracts/ or test/ writes; KNOWN-ISSUES untouched"
    - "D-28 scope-guard deferral for out-of-inventory paths (none surfaced); Phase 237 inventory READ-only"
    - "D-29 Phase 238 discharge evidenced by commit presence — no re-edit of 238 output (audit/v30-238-01-BWD.md, audit/v30-238-02-FWD.md, audit/v30-238-03-GATING.md, audit/v30-FREEZE-PROOF.md all unchanged)"

key-files:
  created:
    - "audit/v30-RNGLOCK-STATE-MACHINE.md (317 lines committed at 5764c8a4 — 11 sections: Executive Summary / State-Machine Overview (Prose Diagram) / Set-Site Table (1 row) / Clear-Site Table (3 rows) / Path Enumeration Table (9 rows) / Invariant Proof / Prior-Artifact Cross-Cites (5 cites, 7 re-verified-at-HEAD notes) / Grep Commands (reproducibility) / Finding Candidates (None surfaced) / Scope-Guard Deferrals (None surfaced) / Attestation)"
    - ".planning/phases/239-rnglocked-invariant-permissionless-sweep/239-01-SUMMARY.md"
  modified: []

requirements-completed: [RNG-01]

metrics:
  duration: "~11 minutes"
  completed: 2026-04-19
  tasks_executed: 3
  lines_in_audit_file: 317
  commits:
    - sha: 5764c8a4
      subject: "docs(239-01): RNG-01 rngLockedFlag state machine airtight proof at HEAD 7ab515fe"
---

# Phase 239 Plan 01: RNG-01 rngLockedFlag State Machine Airtight Proof Summary

**Single-file RNG-01 state-machine proof at HEAD `7ab515fe`: every set site (1), every clear site (3 — including L1700 Clear-Site-Ref per D-06), every reachable path from set through early-returns + reverts to matching clear (9 paths) enumerated exhaustively with closed-form biconditional invariant proof. Discharges Phase 238-03 FWD-03 gating rngLocked audit assumption.**

## Performance

- **Started:** 2026-04-19T04:48:08Z
- **Completed:** 2026-04-19T04:59:xxZ (~11 minutes wall-clock)
- **Tasks executed:** 3 (Task 1 build Set/Clear tables + Task 2 build Path Enumeration + Invariant Proof + cross-cites + commit + Task 3 SUMMARY)
- **Commits on main:** 2 (Task 1+2 combined → `5764c8a4` audit file; Task 3 → this SUMMARY)
- **Files created:** 2 (audit/v30-RNGLOCK-STATE-MACHINE.md + 239-01-SUMMARY.md)
- **Files modified:** 0 in `contracts/` or `test/` (READ-only per D-27); 0 in Phase 237/238 output files (READ-only per D-28/D-29); 0 in KNOWN-ISSUES.md (D-27)
- **Lines authored:** 317 in audit file + this SUMMARY

## Accomplishments

- **Set-Site Table:** 1 row — `RNGLOCK-239-S-01` @ `contracts/modules/DegenerusGameAdvanceModule.sol:1579` inside `_finalizeRngRequest`. Verdict `AIRTIGHT` (idempotent SSTORE paired atomically with `vrfRequestId`, `rngWordCurrent`, `rngRequestTime` at `:1576-1578`).
- **Clear-Site Table:** 3 rows — `RNGLOCK-239-C-01` (`_unlockRng @ :1676`, 6 call sites in `advanceGame` do-while), `RNGLOCK-239-C-02` (`updateVrfCoordinatorAndSub @ :1635`, admin-gated emergency rotation), `RNGLOCK-239-C-03` (L1700 `rawFulfillRandomWords` branch Clear-Site-Ref per D-06 — control-flow structure, no SSTORE). All three `AIRTIGHT`.
- **Path Enumeration Table:** 9 rows exhaustive enumeration (superset of v29.0 Phase 235-05 4-path walk). Verdict distribution: `SET_CLEARS_ON_ALL_PATHS` = 7 (P-001 daily-happy, P-002 L1700 revert-safety, P-003 fresh-vs-retry idempotent-set, P-005 phase-transition-done, P-006 jackpot-resume + coin+tickets, P-007 gameover-bracket, P-008 admin-rotation); `CLEAR_WITHOUT_SET_UNREACHABLE` = 2 (P-004 12h retry-timeout + set-on-set idempotency, P-009 tx-revert rollback).
- **D-06 L1700 revert-safety:** enumerated as `RNGLOCK-239-C-03` (Clear-Site-Ref) + `RNGLOCK-239-P-002` (dedicated Path row). Verdict `SET_CLEARS_ON_ALL_PATHS`; no `rngLockedFlag` SSTORE inside `rawFulfillRandomWords` in either daily or mid-day branch — revert-safety invariant (stale VRF cannot leave flag stuck true) holds because fulfillment populates `rngWordCurrent`, triggering `_unlockRng` on the next `advanceGame` call. Cross-cites v3.7 Phase 63 with `re-verified at HEAD 7ab515fe — rawFulfillRandomWords body at L1690-1711 structurally unchanged`.
- **D-07 12h retry-timeout:** enumerated as `RNGLOCK-239-P-004` with explicit `CLEAR_WITHOUT_SET_UNREACHABLE` verdict semantics — the retry re-writes `rngLockedFlag = true` to an already-true slot (no-op at flag level), preserving the set-site SSTORE; the prior request's implicit clear (via atomic re-write of `vrfRequestId`/`rngRequestTime`/`rngWordCurrent`) is paired with the retry's set-on-same-flag, satisfying Invariant 2 (clear←set) matching. Cross-cites v2.1 VRF retry timeout + v3.7 lifecycle + v29.0 Phase 235-05.
- **D-19 gameover-VRF-request bracket:** enumerated as `RNGLOCK-239-P-007` — set via `_finalizeRngRequest` (called from `_tryRequestRng` inside `_gameOverEntropy`), clear via `_unlockRng(day)` @ `:625` (called from `_handleGameOverPath` after `handleGameOverDrain` delegatecall). Terminal-state post-`handleFinalSweep` blocks further VRF cycles by construction. **Jackpot-input determinism explicitly OUT of scope — routed to Phase 240 GO-02.**
- **Invariant Proof:** closed-form biconditional with both directions (Invariant 1 set→clear + Invariant 2 clear←set) + corollary stating `RNG-01 AIRTIGHT`. Each direction proven by enumeration over the 9 Path rows + 3 Clear-Site rows; every Set-Site has a matching clear path (or tx-revert rollback); every Clear-Site has a matched Set-Site predecessor.
- **Prior-Artifact Cross-Cites (5 cites, 7 `re-verified at HEAD 7ab515fe` notes):** v29.0 Phase 235-05-TRNX-01.md 4-path walk / v3.7 Phase 63 `rawFulfillRandomWords` revert-safety / v3.8 Phases 68-72 commitment window 51/51 SAFE / v25.0 Phase 215 RNG fresh-eyes SOUND verdict / v29.0 Phase 232.1-03-PFTB-AUDIT.md non-zero-entropy + semantic-path-gate archetypes. All CORROBORATING; Phase 239 verdicts re-derived fresh at HEAD.
- **Grep Commands section:** reviewer-reproducibility mechanical grep commands preserved per Claude's Discretion encouragement in CONTEXT.md (Plan 02 precedent applied to Plan 01 for Set/Clear/Read-site discovery transparency).
- **Finding Candidates:** `None surfaced.` Zero `CANDIDATE_FINDING` rows across 13 total rows (1 Set + 3 Clear + 9 Path). No routing to Phase 242 FIND-01 intake from this plan.
- **Scope-Guard Deferrals:** `None surfaced.` rngLockedFlag surface at HEAD fully anchored in `audit/v30-CONSUMER-INVENTORY.md` (the 106-row Named Gate = `rngLocked` subset per 238-03 SUMMARY).

## Task Commits

1. **Task 1 + Task 2 (combined commit): Build Set/Clear tables + Path Enumeration + Invariant Proof + cross-cites + Finding Candidates + Scope-Guard Deferrals + Attestation + commit** — `5764c8a4` (`docs(239-01): RNG-01 rngLockedFlag state machine airtight proof at HEAD 7ab515fe`). 317 lines; zero F-30-NN; zero mermaid; zero placeholder tokens; HEAD anchor attested. Single-file stage (`audit/v30-RNGLOCK-STATE-MACHINE.md`) — no `contracts/`, `test/`, KNOWN-ISSUES.md, Phase 237/238 output, or STATE.md bundled. STATE.md separately modified by orchestrator (position tracking) — not staged in this commit per D-27/D-29 discipline.

2. **Task 3: SUMMARY write + commit** — this file at its own commit (see final commit in plan-close sequence).

Note: Plan separates Task 1 (Set/Clear tables) from Task 2 (Path Enumeration + commit). Because there is no intermediate checkpoint between the tables and the commit, both land as one commit — same pattern as 237-02/03, 238-01/02 precedent (single-commit-per-plan for audit-file-only deliverables).

## Files Created/Modified

- `audit/v30-RNGLOCK-STATE-MACHINE.md` (CREATED — 317 lines, commit `5764c8a4`)
- `.planning/phases/239-rnglocked-invariant-permissionless-sweep/239-01-SUMMARY.md` (CREATED — this file)
- `audit/v30-CONSUMER-INVENTORY.md` (UNCHANGED per D-28 — inventory READ-only after 237 commit)
- `audit/v30-238-01-BWD.md`, `audit/v30-238-02-FWD.md`, `audit/v30-238-03-GATING.md`, `audit/v30-FREEZE-PROOF.md` (UNCHANGED per D-29 — Phase 238 output READ-only; Phase 238 audit-assumption discharge is evidenced by presence of this plan's commit, not by edits to 238 files)
- `KNOWN-ISSUES.md` (UNCHANGED per D-27 — Phase 242 FIND-03 owns KI promotions)
- `contracts/`, `test/` (UNCHANGED per D-27 — READ-only audit phase; `git status --porcelain contracts/ test/` empty throughout)

## Decisions Made

1. **Prose-state-machine diagram included** (CONTEXT.md Claude's Discretion — optional readability aid). Used ASCII box-drawing characters (`▼`, `│`, `┘`, `─`) rather than mermaid (D-25 forbids mermaid). The diagram shows the set/clear lifecycle + L1700 branch + revert-rollback semantics at a glance; complements the tabular enumeration.
2. **Grep commands preserved in a dedicated `## Grep Commands (reproducibility)` section** (CONTEXT.md Claude's Discretion encouragement carried from Plan 02 to Plan 01). Enables reviewer sanity-check by re-running the mechanical greps at HEAD `7ab515fe` and comparing to expected counts (1 set SSTORE / 2 clear SSTOREs / 1 L1700 branch / 4 revert-guards / 6 `_unlockRng` sites).
3. **L1700 branch treated as `RNGLOCK-239-C-03` Clear-Site-Ref row** (per D-06 literal) rather than being absorbed as a footnote inside C-01's row. Rationale: D-06 explicitly says "enumerated as a Clear-Site Ref with its own Path Enumeration row"; giving it a dedicated Row ID makes the state-machine structure visible to reviewers and enables Phase 242 to grep-anchor any future observation about the L1700 branch.
4. **9 Path rows instead of strict v29.0 4-path baseline**: the five additional rows (P-003 fresh-vs-retry idempotency, P-005 phase-transition-done, P-006 jackpot-resume + coin+tickets + `_endPhase` interaction, P-008 admin-rotation-clear, P-009 tx-revert-rollback) cover D-06/D-07/D-19/admin-actor/revert-semantics scope requirements that were implicit or scope-excluded in v29.0 TRNX-01. This is an explicit v30.0 fresh-eyes expansion per D-16 (v29.0 Phase 235-05 is CORROBORATING; this file's enumeration is the warrant).
5. **Finding Candidate severities: N/A (zero candidates)**; if any had surfaced, they would have carried `SEVERITY: TBD-242` per CONTEXT.md Claude's Discretion precedent from 237/238 (planner picks; 237/238 both used TBD-242 for unclassifiable candidates).

## Phase 238 Discharge Note (D-29)

Phase 238-03 FWD-03 gating (`audit/v30-FREEZE-PROOF.md` §Scope-Guard Deferrals entry 1 — "Phase 239 RNG-01 / RNG-03 audit assumption (APPLICABLE)") cited Phase 239 RNG-01 as an audit assumption pending first-principles re-proof of the `rngLockedFlag` state-machine. This plan's commit (`5764c8a4`) DISCHARGES the RNG-01 portion of that assumption:

- Every `rngLockedFlag` SSTORE site at HEAD `7ab515fe` re-enumerated fresh via direct `contracts/`-tree grep (1 set @ `:1579`, 2 clears @ `:1635`, `:1676`, plus L1700 Clear-Site-Ref structural).
- Every reachable execution path from set to matching clear proven `SET_CLEARS_ON_ALL_PATHS` (7 rows) or `CLEAR_WITHOUT_SET_UNREACHABLE` (2 rows) — zero `CANDIDATE_FINDING` rows.
- Closed-form biconditional invariant proof holds in both directions (Invariant 1 set→clear + Invariant 2 clear←set); corollary states **RNG-01 AIRTIGHT**.
- No re-edit of Phase 238 files — discharge is evidenced by presence of RNG-01 verdicts at commit `5764c8a4`. Phase 242 REG-01/02 cross-checks the discharge at milestone consolidation.

Note: Phase 238's Scope-Guard Deferral #1 also bundled `lootbox-index-advance` gate correctness as an audit assumption pending Phase 239 RNG-03(a). That portion is **NOT** discharged by this plan (Plan 239-01 owns RNG-01 only; Plan 239-03 owns RNG-03 asymmetry re-justification including `lootbox-index-advance`). Plan 239-03 commit will discharge the remaining RNG-03 portion independently in Wave 1 parallel per D-02.

## Deviations from Plan

**None — plan executed exactly as written.** Task 1 and Task 2 landed as a single commit per the plan's explicit Task 2 Step 7 directive ("Stage ONLY `audit/v30-RNGLOCK-STATE-MACHINE.md`. Commit with message..."); Task 1's build-without-commit + Task 2's extend + commit land together because the plan intentionally bundles them (per CONTEXT.md D-24 single-file pattern + Task 1 acceptance criteria "No commit yet (commit happens in Task 2...)"). No deviation rules invoked (no bugs found, no missing critical functionality, no blocking issues, no architectural changes).

One minor in-plan iteration: the initial draft of the Executive Summary and Invariant Proof listed path-verdict distribution as `SET_CLEARS_ON_ALL_PATHS = 8 / CLEAR_WITHOUT_SET_UNREACHABLE = 1`; re-tally after row-by-row re-inspection showed the correct distribution is `7 / 2` (P-003 `SET_CLEARS_ON_ALL_PATHS` bolded primary with `CLEAR_WITHOUT_SET_UNREACHABLE` as explanatory reference; P-004 + P-009 as the two primary `CLEAR_WITHOUT_SET_UNREACHABLE` rows). Corrected before commit. Not a deviation — internal accounting fix during build.

## Issues Encountered

**None.** The state machine at HEAD `7ab515fe` is structurally simple (1 set SSTORE, 2 clear SSTOREs, 1 structural L1700 branch) — the airtight verdict emerged cleanly from first-principles enumeration. No ambiguous paths, no unresolved semantics, no out-of-inventory surfaces.

## User Setup Required

None — no external service configuration. Deliverable is markdown-only under `audit/`. No credentials, API keys, browser verification, or manual actions required.

## Next Phase Readiness

**Phase 239 Plan 01 complete (RNG-01 closed).** Plans 239-02 (RNG-02 permissionless sweep with 3-class classification) + 239-03 (RNG-03 asymmetry re-justification — lootbox index-advance + `phaseTransitionActive`) running in parallel Wave 1 per D-02 — no cross-dependencies at HEAD `7ab515fe`. Phase 239 overall closes when all three plans commit.

Phase 242 REG-01/02 will cross-check this plan's Phase 238 discharge claim at milestone consolidation. Phase 242 FIND-01 intake receives zero candidates from this plan (all 13 rows AIRTIGHT / SET_CLEARS_ON_ALL_PATHS / CLEAR_WITHOUT_SET_UNREACHABLE; no `CANDIDATE_FINDING`).

## Self-Check: PASSED

- [x] `audit/v30-RNGLOCK-STATE-MACHINE.md` exists at commit `5764c8a4` (verified via `git log --oneline --all | grep 5764c8a4`)
- [x] 11 required sections present (Executive Summary / State-Machine Overview / Set-Site Table / Clear-Site Table / Path Enumeration Table / Invariant Proof / Prior-Artifact Cross-Cites / Grep Commands / Finding Candidates / Scope-Guard Deferrals / Attestation)
- [x] Set-Site Table row count (1) matches grep count of `rngLockedFlag = true` SSTOREs in `contracts/` excluding mocks (1) at HEAD `7ab515fe`
- [x] Clear-Site Table row count (3) = grep count of `rngLockedFlag = false` SSTOREs (2) + L1700 Clear-Site-Ref (1) per D-06
- [x] Path Enumeration Table row count (9) ≥ v29.0 Phase 235-05 4-path baseline (4) + D-06 + D-07 + D-19 dedicated rows
- [x] All Set-Site + Clear-Site verdicts ∈ `{AIRTIGHT, CANDIDATE_FINDING}` per D-05 (distribution: 4 AIRTIGHT / 0 CANDIDATE_FINDING)
- [x] All Path verdicts ∈ `{SET_CLEARS_ON_ALL_PATHS, CLEAR_WITHOUT_SET_UNREACHABLE, CANDIDATE_FINDING}` per D-04/D-05 (distribution: 7 / 2 / 0)
- [x] Closed-form Invariant Proof with both directions (Invariant 1 + Invariant 2) present per D-04
- [x] Prior-Artifact Cross-Cites: 5 cites (v29.0 Phase 235-05, v3.7 Phase 63, v3.8 Phases 68-72, v25.0 Phase 215, v29.0 Phase 232.1-03-PFTB), 7 `re-verified at HEAD 7ab515fe` notes
- [x] D-06 L1700 revert-safety enumerated (RNGLOCK-239-C-03 + RNGLOCK-239-P-002)
- [x] D-07 12h retry-timeout enumerated (RNGLOCK-239-P-004)
- [x] D-19 gameover-VRF-request bracket enumerated (RNGLOCK-239-P-007); Phase 240 GO-02 out-of-scope marker present
- [x] D-22 zero F-30-NN IDs (`grep -E 'F-30-[0-9]' audit/v30-RNGLOCK-STATE-MACHINE.md` returns zero matches)
- [x] D-25 zero mermaid fences (`grep -i '```mermaid'` returns zero matches)
- [x] D-26 HEAD anchor `7ab515fe` in frontmatter + echoed in Attestation section + in SUMMARY frontmatter + throughout body
- [x] D-27 READ-only: `git status --porcelain contracts/ test/` empty; `git diff --name-only 7ab515fe..HEAD -- contracts/ test/` empty; KNOWN-ISSUES.md untouched
- [x] D-28 Scope-Guard Deferrals section present with `None surfaced.` (inventory scope anchor holds)
- [x] D-29 Phase 238 output files unchanged (`git status --porcelain audit/v30-238-01-BWD.md audit/v30-238-02-FWD.md audit/v30-238-03-GATING.md audit/v30-FREEZE-PROOF.md` empty); discharge evidenced by commit presence, no re-edit
- [x] Commit subject prefix matches `^docs\(239-01\):` regex; exactly one file staged in Task 1+2 commit (`audit/v30-RNGLOCK-STATE-MACHINE.md`)
- [x] No `--no-verify`, no force-push, no push-to-remote
- [x] Phase 237 inventory (`audit/v30-CONSUMER-INVENTORY.md`) unmodified

**Self-check verdict: PASSED.** All must_haves truths from `239-01-PLAN.md` frontmatter satisfied; all plan acceptance criteria met for Tasks 1, 2, 3.
