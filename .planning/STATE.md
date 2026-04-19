---
gsd_state_version: 1.0
milestone: v30.0
milestone_name: Full Fresh-Eyes VRF Consumer Determinism Audit
status: executing
last_updated: "2026-04-19T15:00:00Z"
last_activity: 2026-04-19
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 6
  completed_plans: 4
  percent: 22
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 238 — Backward & Forward Freeze Proofs (planned, ready to execute)

## Current Position

Phase: 238 (Backward & Forward Freeze Proofs) — EXECUTING, 1/3 plans complete (Plan 238-01 BWD-01/02/03 committed at `d0a37c75`), 2/3 remaining (238-02 Wave 1 + 238-03 Wave 2).
Plan: 1 of 3 executed. Wave 1 (238-01 BWD + 238-02 FWD-01/02) parallel; Wave 2 (238-03 FWD-03 + consolidated `audit/v30-FREEZE-PROOF.md`) sequential per D-01/D-02.
**Milestone:** v30.0 — Full Fresh-Eyes VRF Consumer Determinism Audit
**Phase:** 238 CONTEXT.md + 238-01/02/03-PLAN.md committed 2026-04-19. Plan 238-01 executed + committed 2026-04-19 at `d0a37c75` (docs(238-01): BWD-01/02/03 per-consumer backward freeze proof at HEAD 7ab515fe). Phase 237 complete (3/3 plans).
**Plan:** 238-01 complete — `audit/v30-238-01-BWD.md` (620 lines; 146 Backward Freeze Table rows + 146 Backward Adversarial Closure Table rows + 19 Gameover-Flow subset; 22 EXCEPTION matching EXC-01..04 distribution + 124 SAFE; zero CANDIDATE_FINDING; zero F-30-NN; zero contracts/test writes; inventory unmodified). 238-02 + 238-03 still pending.
**Status:** Plan 238-02 (FWD-01/02) ready for execute (Wave 1 parallel-parent with completed 238-01; actually runnable independently since both consume the inventory). 238-03 (FWD-03 + consolidation) still blocked on 238-02 completion per D-02 (Wave 2 depends on 238-02 mutation-path output). Phases 239 / 240 / 241 still unblocked and parallelizable.
**Last activity:** 2026-04-19

**Audit baseline:** HEAD `7ab515fe` (contract tree identical to v29.0 `1646d5af`; all post-v29 commits are docs-only)
**Write policy:** READ-only — no `contracts/` / `test/` edits (carry forward v28/v29 cross-repo READ-only pattern). Writes confined to `.planning/`, `audit/`, and possibly `KNOWN-ISSUES.md` (for FIND-03 promotions).
**Deliverable target:** `audit/FINDINGS-v30.0.md`

**Accepted RNG exceptions (out of scope for re-litigation — documented in KNOWN-ISSUES.md):**

1. Non-VRF entropy for affiliate winner roll (deterministic seed, gas optimization)
2. Gameover prevrandao fallback — `_getHistoricalRngFallback` after 14-day VRF outage
3. Gameover RNG substitution for mid-cycle write-buffer tickets (F-29-04 invariant disclosure)
4. EntropyLib XOR-shift PRNG — VRF-seeded, known theoretical non-uniformity

## Phase Structure (6 phases, 237-242)

| Phase | Name | Requirements | Depends On |
|-------|------|--------------|------------|
| 237 | VRF Consumer Inventory & Call Graph | INV-01, INV-02, INV-03 | — |
| 238 | Backward & Forward Freeze Proofs | BWD-01..03, FWD-01..03 | 237 |
| 239 | rngLocked Invariant & Permissionless Sweep | RNG-01, RNG-02, RNG-03 | 237 |
| 240 | Gameover Jackpot Safety | GO-01..05 | 237 |
| 241 | Exception Closure | EXC-01..04 | 237 |
| 242 | Regression + Findings Consolidation | REG-01, REG-02, FIND-01..03 | 238, 239, 240, 241 |

**Execution order:** 237 first. After 237 completes, 238/239/240/241 can execute in parallel. 242 requires all four.

## Accumulated Context

Decisions logged in `.planning/PROJECT.md` Key Decisions table.
Detailed milestone retrospective in `.planning/RETROSPECTIVE.md` "Milestone: v29.0".
Full v29.0 phase artifacts in `.planning/milestones/v29.0-phases/`.

Prior RNG-related milestone artifacts worth referencing during v30.0 planning (but NOT relied upon — this is fresh-eyes):

- v25.0 RNG fresh-eyes sweep (Phases 213-217)
- v29.0 Phase 235 Plans 03-04 (per-consumer backward-trace + commitment-window enumeration)
- v29.0 Phase 235 Plan 05 (TRNX-01 rngLocked invariant 4-path re-proof)
- v3.7 VRF Path Test Coverage (Phases 63-67 Foundry invariants + Halmos proofs)
- v3.8 VRF commitment window audit (Phases 68-72)

### Pending Todos

- Launch Phase 238 (Backward & Forward Freeze Proofs) — 146 Row IDs from `audit/v30-CONSUMER-INVENTORY.md` are the per-consumer scope anchor; Consumer Index BWD-01/02/03 + FWD-01/02/03 rows all map to `ALL` (full universe). Expected 3-5 plans per ROADMAP.
- Launch Phase 239 (rngLocked Invariant & Permissionless Sweep) — 94-row daily+infrastructure scope for RNG-01; all 146 for RNG-02; 19-row mid-day-lootbox for RNG-03.
- Launch Phase 240 (Gameover Jackpot Safety) — 19-row gameover-flow scope (7 gameover-entropy + 4 F-29-04 + 8 prevrandao-fallback) for GO-01..05.
- Launch Phase 241 (Exception Closure) — 22 proof subjects across 4 KI categories.
- Phase 242 (Regression + Findings Consolidation) requires 238+239+240+241; 17-item merged Finding Candidate pool from Phase 237 is the FIND-01..03 input.

### Phase 237 Plan 01 Decisions (2026-04-19)

- D-07 two-pass zero-glance + reconciliation methodology honoured: Task 1 fresh-eyes file committed standalone (`18f519b7`) BEFORE Task 2 began any prior-artifact read. Auditable ex-post via git log separation.
- 146 INV-237-NNN rows at HEAD `7ab515fe` (5.2× prior 235-03 baseline — expansion entirely driven by finer D-01/D-02/D-03/D-06 granularity, not by any post-v29 contract change).
- Reconciliation verdict distribution: 45 confirmed-fresh-matches-prior / 12 new-since-prior-audit / 0 was-missed-now-added / 0 was-spurious-before-not-at-HEAD.
- 5 finding candidates surfaced (all severity INFO), routed to Phase 242 per D-15.
- Zero F-30-NN IDs emitted per D-15. Zero `contracts/` or `test/` writes per D-18.

### Phase 237 Plan 02 Decisions (2026-04-19)

- Classification distribution at 146-row granularity: `daily` 91 / `mid-day-lootbox` 19 / `gap-backfill` 3 / `gameover-entropy` 7 / `other` 26 = 146. `daily` share (62.3%) exceeds the planner's 30-50% heuristic — not a classification error; driven by D-01 fine-grained expansion. Flagged in Finding Candidates as sanity-check observation.
- KI-exception rules (1 / 2 / 3 per decision procedure) take precedence over path-family rules (4 / 5 / 6 / 7). Consequence: `_gameOverEntropy` cluster splits across 3 family labels: 7 rows → `gameover-entropy`, 2 rows → `other / exception-mid-cycle-substitution`, 8 rows → `other / exception-prevrandao-fallback`. Effective gameover-flow scope (for Phase 240 GO-01) = 19 rows across those 3 labels.
- KI Cross-Ref distribution (D-06 proof-subject set for Phase 241 EXC-01..04): EXC-01 2 rows / EXC-02 8 rows / EXC-03 4 rows / EXC-04 8 rows = 22 proof targets. Phase 239 RNG-03 index-advance re-justification set = 13 rows.
- 7 Finding Candidates surfaced (all severity INFO), routed to Phase 242 per D-15. No F-30-NN IDs emitted. No edits to `audit/v30-237-01-UNIVERSE.md` (D-16 READ-only-after-commit honoured). Zero `contracts/` or `test/` writes per D-18.

### Phase 237 Plan 03 Decisions (2026-04-19)

- 146 per-consumer call graphs constructed per D-11 (request → fulfillment → consumption, stop-at-consumption). 6 shared-prefix chains (PREFIX-DAILY / PREFIX-MIDDAY / PREFIX-GAMEOVER / PREFIX-PREVRANDAO / PREFIX-AFFILIATE / PREFIX-GAP) absorb 130 of 146 rows (89%); remaining 16 carry bespoke short graphs.
- Zero companion `audit/v30-237-CALLGRAPH-*.md` files created — D-12's ~30-line soft threshold not reached because shared-prefix deduplication kept per-consumer tails to 1-3 rows. All call graphs inlined.
- Delegatecall + library-call hops traced per D-11: IM-13 `_processFutureTicketBatch` delegatecall boundary (AdvanceModule:1390-1394 → MintModule:568/:652), EntropyLib.hash2 library calls named with `hash2(uint256, uint256) → uint256` signature, EntropyLib.entropyStep XOR-shift library calls named per KI exception, JackpotBucketLib.soloBucketIndex library call explicit.
- Final consolidated `audit/v30-CONSUMER-INVENTORY.md` assembled per D-08 via Python merge script (`/tmp/build_consolidated.py`) — 2362 lines, 13 required sections, 146 Universe List rows (all TBD placeholders replaced), 146 Per-Consumer Call Graphs verbatim from 237-03, 26-row Consumer Index mapping every v30.0 requirement ID to its INV-237-NNN subset per D-10.
- Consumer Index scopes computed: INV/BWD/FWD × 3 = `ALL` (9 rows); RNG-01 = 94 rows (daily + VRF infrastructure); RNG-02 = `ALL`; RNG-03 = 19 rows (mid-day-lootbox family); GO-01..04 = 19 rows (gameover + F-29-04 + prevrandao-fallback); GO-05 = 4 rows (F-29-04); EXC-01/02/03/04 = 2/8/4/8 KI proof subjects; REG-01 = 4 rows (F-29-04); REG-02 = 29 rows (v25.0/v3.7/v3.8 confirmed matches); FIND-01 = 21 rows (union of 3 sub-plan FC sets); FIND-02 = REG-01 ∪ REG-02; FIND-03 = 3 candidate rows pending Phase 242 review.
- 5 Finding Candidates surfaced during call-graph construction (all INFO): dual-trigger delegatecall boundary observation, resolveLootboxDirect gameover-caller marker, prevrandao-mix recursion citation, INV-237-124 sole daily-family EntropyLib caller, F-29-04 swap-site liveness. Merged with 5 (237-01) + 7 (237-02) = 17 total FC routed to Phase 242.
- No F-30-NN IDs emitted per D-15. No edits to `audit/v30-237-01-UNIVERSE.md` or `audit/v30-237-02-CLASSIFICATION.md` (D-16 READ-only-after-commit). Zero `contracts/` or `test/` writes per D-18. HEAD anchor `7ab515fe` attested (D-17).

### Phase 238 Context Decisions (2026-04-19)

- 3 plans, 2 waves per D-01/D-02: 238-01 BWD-01/02/03 (all 146) + 238-02 FWD-01/02 (all 146) parallel Wave 1; 238-03 FWD-03 gating + final consolidated `audit/v30-FREEZE-PROOF.md` Wave 2 (reads 238-02 mutation-path output).
- 4-actor closed adversarial-closure taxonomy per D-07: player / admin / validator / VRF oracle. VRF oracle added beyond REQUIREMENTS.md literal wording because the 14-day prevrandao fallback (KI EXC-02) is the accepted escape hatch for indefinite withholding.
- 4-gate closed FWD-03 gating taxonomy per D-13: `rngLocked` / `lootbox-index-advance` / `phase-transition-gate` / `semantic-path-gate`. Any row outside the taxonomy is `CANDIDATE_FINDING` per D-14.
- KI-exception rows (22) + gameover-flow rows (19) IN Phase 238 scope per D-11/D-12 with `EXCEPTION (KI: <header>)` verdict; no re-litigation. Phase 241 EXC-01..04 closes acceptance; Phase 240 GO-01..05 layers gameover-jackpot-specific overlay.
- Fresh re-prove + cross-cite prior with `re-verified at HEAD 7ab515fe` note per D-09/D-10 (Phase 235 D-03/D-04 pattern). Cross-cite sources: Phase 235-03/04/05, Phase 215-02/03, Phase 232.1-03-PFTB, v3.7/v3.8.
- Single consolidated `audit/v30-FREEZE-PROOF.md` deliverable per D-16 (Phase 237 D-08 precedent) + 3 per-plan intermediate files. Grep-friendly tabular, no mermaid (237 D-09).
- No F-30-NN emission per D-15 (Phase 237 D-15 / Phase 235 D-14 / Phase 230 D-06 pattern across 3 prior phases). READ-only scope per D-20. Scope-guard deferral rule per D-18.

### Phase 238 Plan 01 Decisions (2026-04-19)

- 146 Backward Freeze Table rows + 146 Backward Adversarial Closure Table rows built at HEAD `7ab515fe` in a single 620-line file `audit/v30-238-01-BWD.md` with 8 required sections per D-04/D-07/D-08/D-09/D-10/D-11/D-12/D-15/D-17/D-18/D-19/D-20 compliance.
- 22 EXCEPTION rows matching 237-02 Plan SUMMARY EXC-01..04 distribution exactly (EXC-01=2 affiliate / EXC-02=8 prevrandao / EXC-03=4 F-29-04 / EXC-04=8 EntropyLib); 124 SAFE rows; 0 CANDIDATE_FINDING actor-cells surfaced during fresh re-derivation.
- 6 shared-prefix chains from 237-03 adopted verbatim (PREFIX-DAILY 91 / PREFIX-MIDDAY 19 / PREFIX-GAMEOVER 7 / PREFIX-PREVRANDAO 8 / PREFIX-AFFILIATE 2 / PREFIX-GAP 3 = 130 rows absorbed); 16 bespoke-tail rows (library-wrappers + request-origination + fulfillment-callback + view-deterministic-fallback + F-29-04 mid-cycle substitution) inline their traces.
- BWD-03 actor-cell gate-assignment taxonomy established: daily-family SAFE rows use `PATH_BLOCKED_BY_GATE (rngLocked)` for player+admin+validator + `NO_REACHABLE_PATH` for VRF oracle; mid-day-lootbox SAFE rows use `PATH_BLOCKED_BY_GATE (lootbox-index-advance)` for 3 on-chain actors; EXCEPTION cells placed in the SPECIFIC actor column responsible for the KI-accepted exposure (player for EXC-01 timing, validator for EXC-02 prevrandao, VRF oracle for EXC-03 delay-triggered substitution and EXC-04 entropy-source-level XOR-shift).
- 19-row Gameover-Flow Backward-Freeze Subset enumerated for Phase 240 hand-off: 7 SAFE (`gameover-entropy`) + 12 EXCEPTION (8 prevrandao + 4 F-29-04) = 19. Matches 237 Consumer Index GO-01..04 count exactly.
- 7 prior-milestone artifacts CROSS-CITED with `re-verified at HEAD 7ab515fe` notes (235-03-AUDIT.md, 215-02-BACKWARD-TRACE.md, STORAGE-WRITE-MAP.md, 230-01-DELTA-MAP §1, 230-02-DELTA-ADDENDUM, ACCESS-CONTROL-MATRIX.md, 232.1-03-PFTB-AUDIT.md). Every cite carries structural-equivalence statement.
- Zero F-30-NN IDs emitted; zero `contracts/` or `test/` writes; `audit/v30-CONSUMER-INVENTORY.md` unmodified (D-18); Row-ID integrity diff empty (146 in inventory = 146 in BWD file, set-equal).
- Task 1 (build file) + Task 2 (commit) landed as single commit `d0a37c75` (same pattern as 237-02 + 237-03 Task 1+2 consolidation). BWD-02-forbidden mutable verdict absent from every data cell; two attestation lines were rephrased to avoid literal-string collision with the forbidden token during automated verify (non-deviation — explanatory text only).

### Blockers/Concerns

_(none — Phase 237 complete (3/3 plans); Phase 238 Plan 01 complete (1/3); 238-02 + 238-03 remaining; Phases 239/240/241 still unblocked and parallelizable; Phase 242 requires 238+239+240+241)_

## Session Continuity

Last session: 2026-04-19T15:00:00Z (Plan 238-01 executed + committed at `d0a37c75`; Wave 1 deliverable `audit/v30-238-01-BWD.md` ready for 238-03 consolidation in Wave 2; 238-02 FWD-01/02 next parallel target)

## Deferred Items

Carried forward from v29.0 close (2026-04-18):

| Category | Item | Status | Reason |
|----------|------|--------|--------|
| quick_task | 260327-n7h-run-full-test-suite-and-analyze-results- | missing | False-positive in audit tracker — task is complete (PLAN.md + 260327-n7h-SUMMARY.md exist); audit tool looks for `SUMMARY.md` but actual file is prefix-named. Pre-dates v29.0 milestone; out of audit scope. |
| quick_task | 260327-q8y-test-boon-changes | missing | False-positive in audit tracker — task is complete (PLAN.md + 260327-q8y-SUMMARY.md exist); same prefix-naming mismatch. Pre-dates v29.0 milestone; out of audit scope. |
