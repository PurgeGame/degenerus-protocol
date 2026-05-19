# Phase 305: Implementation (IMPL) — Discussion Log

**Discussed:** 2026-05-19
**Mode:** discuss (default, no overlays)
**Phase boundary:** Single batched USER-APPROVED contract diff refactoring `contracts/StakedDegenerusStonk.sol` per Phase 304 SPEC's locked design decisions (SPEC-01..05 + sub-locks a–d), plus interface and call-site updates in `contracts/interfaces/IStakedDegenerusStonk.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol`.

---

## Pre-Loaded Context

The discussion began by loading and grounding against:

- **Phase 304 SPEC** (`.planning/phases/304-spec-invariant-model-spec/304-SPEC.md`, 960 lines) — locks 35 requirements (INV-01..12, SPEC-01..05 with sub-locks, EDGE-01..18) and traces design intent + actor game-theory for all 7 deletions at §4.
- **ROADMAP §"Phase 305"** — goal statement + 5 success criteria + IMPL-01..04 mapping.
- **REQUIREMENTS.md v44.0 block** — full requirement list and the Out-of-Scope table.
- **Source-tree scan** — `contracts/StakedDegenerusStonk.sol` storage block at `:221-231`, the three AdvanceModule call sites at `:1230`, `:1293`, `:1323`, the IStakedDegenerusStonk interface at `contracts/interfaces/IStakedDegenerusStonk.sol:86 + :96`, and the two existing test files (`test/fuzz/RedemptionGas.t.sol` + `test/fuzz/CoverageGap222.t.sol`) that reference the old signatures.
- **Memory** — `feedback_batch_contract_approval.md`, `feedback_never_preapprove_contracts.md`, `feedback_no_contract_commits.md`, `feedback_frozen_contracts_no_future_proofing.md`, `feedback_skip_research_test_phases.md`, `feedback_verify_call_graph_against_source.md`, `feedback_no_history_in_comments.md`.

No prior CONTEXT.md exists for Phase 305 (greenfield); the v43.0 phase precedents (`.planning/milestones/v43.0-phases/30[0-3]-*-CONTEXT.md`) and the Phase 263 IMPL precedent shaped the structure.

---

## Identified Gray Areas (Pre-presentation)

Pre-analysis surfaced four gray areas not already locked by SPEC. The user was asked which to discuss; all other areas defaulted to SPEC-driven or precedent-driven choices.

### Gray Area 1 — Plan slicing shape
- **Options presented (implicit defaults):**
    - Single atomic plan (one `.sol` diff, one user approval at end) — recommended.
    - Multi-plan with end-of-phase batched approval gate.
- **User selection:** Not discussed; defaulted to D-305-PLAN-01 single-plan reference shape per Phase 263 D-PLAN-01 precedent + ROADMAP "Single batched contract diff" anchor. Planner picks final slicing within the atomic-diff constraint.

### Gray Area 2 — Existing test files breaking the build
- **Options presented (implicit defaults):**
    - (a) Update existing tests inside Phase 305's batched diff (AGENT-COMMITTED) — recommended.
    - (b) Bracketed disable until Phase 306 TST rewrites.
    - (c) Delete-and-replace at Phase 305.
- **User selection:** Not discussed; defaulted to (a) per D-305-TESTBREAK-01. Rationale: success criterion #1 requires `forge build` PASS; (b) `vm.skip` only affects test execution, not compilation, so does not help; (c) is scope creep into Phase 306.

### Gray Area 3 — Pre-patch grep re-verification step
- **Options presented (implicit defaults):**
    - Dedicated leading plan step.
    - Roll into the start of the IMPL plan as task 1 — recommended.
- **User selection:** Not discussed; defaulted to D-305-GREP-01 (rolled into IMPL plan as task 1) per `feedback_verify_call_graph_against_source.md`. Phase 304 Plan 05 already grep-verified at v43.0 closure HEAD; structural drift bounded but verify-don't-assume.

### Gray Area 4 — Research-dispatch posture
- **Options presented:**
    - Skip research, plan directly (Recommended).
    - Dispatch research anyway.
- **User selection:** **Skip research, plan directly.**
- **Decision captured:** D-305-RESEARCH-01.
- **Notes:** SPEC.md is 960 lines, every cited file:line grep-verified, all decisions locked. Research adds no new info. Mirrors Phase 263 D-APPROVAL-02 + Phase 259 D-11 + Phase 260 D-11 mechanical-phase precedent.

---

## Decisions Captured

- **D-305-RESEARCH-01** — Skip research, plan directly.
- **D-305-PLAN-01** — Single-plan atomic shape recommended; planner picks final slicing within the atomic-diff constraint.
- **D-305-GREP-01** — Pre-patch grep re-verification of 304-SPEC §5 citations against CURRENT working-tree HEAD as task 1 of the IMPL plan.
- **D-305-TESTBREAK-01** — Update existing test files (`test/fuzz/RedemptionGas.t.sol` + `test/fuzz/CoverageGap222.t.sol`) inside the batched diff so `forge build` PASS.
- **D-305-APPROVAL-01** — All `contracts/` edits batched + presented as one diff + explicit user approval before commit.
- **D-305-APPROVAL-02** — No history comments; describe POST-refactor state only.
- **D-305-APPROVAL-03** — Pre-launch frozen-at-deploy posture; no future-proofing scaffolding; no compatibility shims.
- **D-305-APPROVAL-04** — Manual diff review before push.
- **D-305-DAYTORESOLVE-01** — At all three AdvanceModule call sites, pass `dayToResolve = day - 1` (AdvanceModule-side equivalent of SPEC-03-locked `currentDayView() - 1`).
- **D-305-STORAGE-01** — New `DayPending` struct + `pendingByDay` mapping declarations land roughly where the 5 deleted slots were (`:226-231` region), preserving the storage-block reviewer narrative.

---

## Claude's Discretion (deferred to planner)

- Plan structure within the single-plan shape (planner may split into P1 = pre-patch grep verification AGENT-COMMITTED state file + P2 = the batched USER-APPROVED contract+interface+test diff if the split is clean).
- Comment verbosity for refactored function headers.
- Local variable naming inside refactored bodies.
- Whether to introduce a `DayPending storage pool = pendingByDay[currentDay]` alias inside `_submitGamblingClaimFrom` (gas-neutral / cosmetic).
- Test edit ordering inside the same commit (interleaved vs grouped — diff-presentation cosmetic).

---

## Deferred Ideas (captured for downstream phases)

- New Foundry coverage (TST-01..03) → Phase 306.
- TST-05 `vm.skip` flip + strict byte-identity → Phase 306.
- Gas regression bench (TST-06) → Phase 306.
- 3-skill adversarial sweep (SWP-01..05) → Phase 307.
- 9-section TERMINAL (`audit/FINDINGS-v44.0.md` + closure orchestration) → Phase 308.
- 135 v43 backlog anchors → v45.0+ per `audit/FINDINGS-v43.0.md` §9d handoff register.

---

## Scope Creep Redirects

None during this discussion. The user did not propose any out-of-scope expansions; the gray-area menu held.

---

*Phase: 305-implementation-impl*
*Discussion logged: 2026-05-19*
