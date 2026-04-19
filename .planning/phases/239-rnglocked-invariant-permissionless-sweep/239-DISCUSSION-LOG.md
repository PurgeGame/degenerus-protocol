# Phase 239: rngLocked Invariant & Permissionless Sweep — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 239-rnglocked-invariant-permissionless-sweep
**Mode:** `--auto` (recommended defaults selected for every question; precedents inherited from Phase 237 / Phase 238)
**Areas discussed:** Plan Split & Wave Topology, RNG-01 Evidence Shape, RNG-02 Taxonomy & Scope, RNG-03 Asymmetry Re-Justification, Output Shape, Scope Boundaries

---

## Plan Split & Wave Topology

| Option | Description | Selected |
|--------|-------------|----------|
| 3 plans strict-per-requirement (RNG-01 / RNG-02 / RNG-03), single Wave 1 parallel | Matches Phase 235 D-01 + Phase 237 D-13 + Phase 238 D-01 precedents; zero cross-plan dependencies at HEAD; max parallelism | ✓ |
| 2 plans (RNG-01 standalone, RNG-02 + RNG-03 combined as "sweep + asymmetry") | Fewer plan files; classification + asymmetry share disjointness evidence | |
| 3 plans but 2-wave (RNG-02 Wave 2 after RNG-03 commits — classification cites asymmetry) | Cleaner cite chain for `respects-equivalent-isolation` rows | |

**Auto-selected:** 3 plans strict-per-requirement, single Wave 1 parallel (D-01, D-02)
**Rationale:** Requirement boundaries map cleanly to deliverables; no cross-plan inputs at HEAD; forward cite from RNG-02 → RNG-03(a) handled by file+section path (D-15) without blocking parallelism; matches the established milestone-pattern "strictest plan split achievable".

---

## RNG-01 Evidence Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Set-Site + Clear-Site + Path-Enumeration + Invariant Proof (4-section table structure) | Enumerates every set/clear SSTORE + every reachable path between them + closed-form invariant argument; mirrors Phase 235 D-07 extended to state machine | ✓ |
| Narrative walk-through of each path with inline citations | Readable but less grep-friendly; doesn't scale to multi-path branches | |
| Full formal specification in TLA+ or Hoare triples | Heavyweight; out of milestone READ-only scope | |

**Auto-selected:** 4-section tabular structure (D-04)
**Rationale:** Phase 237 D-09 "tabular, grep-friendly, no mermaid" + Phase 238 D-25 convention; every verdict anchored by file:line for Phase 242 re-anchoring.

**Verdict taxonomy sub-question:**
- Closed `{AIRTIGHT / CANDIDATE_FINDING}` ✓
- Open `{AIRTIGHT / PARTIAL / CANDIDATE / TBD}` — rejected (hedged verdicts leak pending-state into the v30.0 deliverable)

**Revert-safety + retry-path treatment:**
- L1700 rawFulfillRandomWords guard IS in RNG-01 scope ✓ (D-06)
- 12h retry-timeout path IS in RNG-01 scope ✓ (D-07)

---

## RNG-02 Taxonomy & Scope

| Option | Description | Selected |
|--------|-------------|----------|
| 3-class closed taxonomy per ROADMAP SC-2: `respects-rngLocked` / `respects-equivalent-isolation` / `proven-orthogonal` | Matches ROADMAP wording exactly; zero interpretive drift; `CANDIDATE_FINDING` escape for unclassifiable rows | ✓ |
| 4-class: add `gated-by-caller-context` for inter-module delegatecalls | Over-granular; inter-module is internal per D-09 and filtered out upstream | |
| 2-class binary: `rngLocked-safe` / `rngLocked-unsafe` | Loses the asymmetry + orthogonality distinctions that Phase 239 specifically exists to prove | |

**Auto-selected:** 3-class closed taxonomy (D-08)
**Rationale:** ROADMAP success criterion 2 wording locks the taxonomy; any deviation is scope drift.

**Permissionless scope sub-question:**
- External/public + mutating + no admin/game/self-call gate + production-contracts-only ✓ (D-09)
- Alternative: include admin-gated ("paranoid sweep") — rejected (admin actor class is Phase 238 BWD-03/FWD-02 scope; double-coverage wastes effort)
- Alternative: include mocks — rejected (mocks excluded per Phase 237 D-18 in-scope tree)

**Sweep methodology sub-question:**
- Two-pass: mechanical grep → semantic classification ✓ (D-11)
- Alternative: single-pass semantic-only — rejected (no sanity-check rail for completeness)

**Input dependency:**
- Consumes Phase 237 Consumer Index directly (not Phase 238 output) ✓ (D-12)
- Alternative: wait for Phase 238 per-consumer tables — rejected (breaks parallel topology; Phase 237's RNG-consumer state space is the right granularity for RNG-02's touch-check)

---

## RNG-03 Asymmetry Re-Justification

| Option | Description | Selected |
|--------|-------------|----------|
| Two distinct first-principles proofs, one section each (Asymmetry A + Asymmetry B), proof-by-exhaustion format | Matches ROADMAP SC-3 structure; enumerates storage primitives at HEAD; cross-cites only as "we re-derived same result" | ✓ |
| Single consolidated "asymmetry equivalence" proof | Conflates two distinct mechanisms (index-advance isolation vs branch-gate origin); loses clarity | |
| Proof-by-cite (rely on v29.0 Phase 235 Plan 05 + KNOWN-ISSUES entry) | VIOLATES v30.0 fresh-eyes mandate (PROJECT.md + ROADMAP SC-4); rejected | |

**Auto-selected:** Two distinct first-principles proofs, proof-by-exhaustion (D-13, D-14)
**Rationale:** ROADMAP SC-3 structure + v30.0 fresh-eyes mandate. KI entries are the SUBJECT of Asymmetry A (what we're re-justifying), not its warrant.

**Discharge semantics:**
- Phase 239 RNG-01 + RNG-03 discharge Phase 238 D-13 audit assumptions ✓ (D-29)
- Discharge is evidenced by commit presence, not by re-editing Phase 238 files (Phase 238 is READ-only post-commit per 238 D-20)

---

## Output Shape

| Option | Description | Selected |
|--------|-------------|----------|
| 3 dedicated audit files matching ROADMAP SC-1/2/3 exactly (no consolidated 4th file) | Each file self-contained; no consolidation overhead; mirrors ROADMAP 1:1 | ✓ |
| 4 files: 3 per-requirement + 1 consolidated `v30-RNG-INVARIANT.md` | Phase 238 precedent (D-16) but Phase 238 had cross-cutting gating table that needed merging — Phase 239 does not | |
| 1 consolidated file `v30-RNG-PROOFS.md` | Collapses 3 distinct invariants into one grep surface; hurts Phase 242 regression anchoring | |

**Auto-selected:** 3 dedicated audit files (D-24)
**Rationale:** ROADMAP success criteria 1-3 list 3 specific file paths; deviating creates artificial coupling. Finding Candidates appendix is per-plan (D-23); Phase 242 aggregates across all three.

**File naming:**
- `audit/v30-RNGLOCK-STATE-MACHINE.md` (RNG-01) ✓
- `audit/v30-PERMISSIONLESS-SWEEP.md` (RNG-02) ✓
- `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` (RNG-03) ✓

---

## Scope Boundaries

| Option | Description | Selected |
|--------|-------------|----------|
| Strict: per-consumer = 238; gameover-specific = 240; KI-acceptance = 241; regression = 242 — Phase 239 is ONLY state-machine + permissionless-sweep + two-asymmetry | Zero scope overlap with adjacent phases; clean handoff for Phase 242 consolidation | ✓ |
| Opportunistic: re-verify KI acceptance inside Phase 239 since it's already looking at the asymmetries | Doubles-work with Phase 241; conflates re-justification with re-acceptance | |
| Minimal: drop permissionless sweep, only do state machine + asymmetry | VIOLATES RNG-02 requirement | |

**Auto-selected:** Strict scope boundaries (D-18, D-19, D-20, D-21)
**Rationale:** ROADMAP execution-order narrative places 238/239/240/241 in parallel lanes — scope overlap would invalidate the parallel topology.

**Finding emission:**
- No F-30-NN emission; candidate pool for Phase 242 ✓ (D-22)
- Per-plan Finding Candidates appendix ✓ (D-23)

**Baseline:**
- HEAD `7ab515fe` locked in every plan frontmatter ✓ (D-26)
- READ-only scope, no `contracts/` or `test/` writes ✓ (D-27)
- Phase 237 inventory read-only; gaps → scope-guard deferral ✓ (D-28)

---

## Claude's Discretion

Items the planner decides at plan-drafting time:

- Exact ordering of RNG-01 table subsections (set-first vs clear-first vs path-first)
- Whether to include a prose state-machine diagram summary at top of RNGLOCK file
- Whether Plan 02 preserves raw `grep` commands in SUMMARY
- Whether RNG-03 shares a "freeze-proof equivalence template" across both asymmetries
- Finding Candidate severities (INFO / TBD-242) — planner matches 237/238 precedent
- Row ID prefix (`RNGLOCK-239-NNN` / `PERM-239-NNN` / `ASYM-239-A/B-NNN`)

---

## Deferred Ideas (not in Phase 239 scope)

- Phase 240 gameover-jackpot-specific proofs (GO-01..05)
- Phase 241 KI-exception acceptance re-verification (EXC-01..04)
- Phase 242 FIND-01/02/03 consolidation + F-30-NN ID assignment
- Cross-cycle VRF chaining audit
- Automated invariant runner (Foundry/Halmos-queryable tables)
- Gate-taxonomy expansion in Phase 238 (if RNG-02 surfaces unclassifiable row → candidate-finding, not taxonomy amendment)
- EntropyLib XOR-shift PRNG internal state audit (PRNG primitive; per-caller classified in RNG-02, acceptance in Phase 241 EXC-04)
- rngLocked() external view surface per-site correctness audit (function-body correctness already covered by Phase 238 per-consumer FWD-03 + v25.0 adversarial)
- Admin-actor RNG-state mutation (Phase 238 BWD-03/FWD-02 admin-actor closure)
