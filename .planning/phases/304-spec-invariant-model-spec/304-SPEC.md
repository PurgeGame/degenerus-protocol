# Phase 304 — sStonk Per-Day Redemption Refactor: SPEC + Invariant Model

## §0 — Header

- **Milestone:** v44.0 sStonk Per-Day Redemption Refactor + Accounting Invariant Proof
- **Phase:** 304 — SPEC + Invariant Model (SPEC)
- **Baseline:** `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`
- **Load-bearing inputs:**
  - `audit/FINDINGS-v43.0.md` §9d HANDOFF-111..117 (the 7 sStonk anchors closed by v44.0)
  - `.planning/RNGLOCK-FIXREC.md` §103 (V-184 mechanic — catastrophic cross-day re-roll)
  - `.planning/REQUIREMENTS.md` v44.0 block (canonical INV-01..12, SPEC-01..05, EDGE-01..18, IMPL-01..04)
- **Downstream consumer:** Phase 305 IMPL — single batched USER-APPROVED diff against `contracts/StakedDegenerusStonk.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` (+ optional `IDegenerusGamePlayer` minimum delta). Every locked decision in §1–§4 of this SPEC is a load-bearing input for that diff per `feedback_batch_contract_approval.md` and `feedback_never_preapprove_contracts.md`.
- **Posture:** pre-launch, frozen-at-deploy per `feedback_frozen_contracts_no_future_proofing.md`. Storage layout breaks are ACCEPTED; redeploy-fresh; no migration prose appears anywhere in this SPEC; no future-extensibility speculation appears anywhere in this SPEC.
- **Comment policy:** per `feedback_no_history_in_comments.md`, §1/§2/§3/§5 prose describes the POST-REFACTOR state — what IS — and never narrates "what changed" or "what it used to be." Pre-refactor narrative appears ONLY in §4 design-intent walk under explicit `ORIGINAL DESIGN INTENT` subheadings; nowhere else.

### §0 — Requirement Traceability

> At-a-glance map a Phase 306 TST author uses to locate the SPEC text for any requirement ID. Every requirement maps to a primary SPEC section. INV-NN are doc'd at §1; SPEC-NN are locked at §2; EDGE-NN are enumerated at §3.

| Requirement | Section | Status |
|-------------|---------|--------|
| INV-01 | §1 | Filled by Plan 01 |
| INV-02 | §1 | Filled by Plan 01 |
| INV-03 | §1 | Filled by Plan 01 |
| INV-04 | §1 | Filled by Plan 01 |
| INV-05 | §1 | Filled by Plan 01 |
| INV-06 | §1 | Filled by Plan 01 |
| INV-07 | §1 | Filled by Plan 01 |
| INV-08 | §1 | Filled by Plan 01 |
| INV-09 | §1 | Filled by Plan 01 |
| INV-10 | §1 | Filled by Plan 01 |
| INV-11 | §1 | Filled by Plan 01 |
| INV-12 | §1 | Filled by Plan 01 |
| SPEC-01 | §2 | Filled by Plan 02 |
| SPEC-02 | §2 | Filled by Plan 02 |
| SPEC-03 | §2 | Filled by Plan 02 |
| SPEC-04 | §2 | Filled by Plan 02 |
| SPEC-05 | §2 | Filled by Plan 02 |
| EDGE-01 | §3 | Filled by Plan 03 |
| EDGE-02 | §3 | Filled by Plan 03 |
| EDGE-03 | §3 | Filled by Plan 03 |
| EDGE-04 | §3 | Filled by Plan 03 |
| EDGE-05 | §3 | Filled by Plan 03 |
| EDGE-06 | §3 | Filled by Plan 03 |
| EDGE-07 | §3 | Filled by Plan 03 |
| EDGE-08 | §3 | Filled by Plan 03 |
| EDGE-09 | §3 | Filled by Plan 03 |
| EDGE-10 | §3 | Filled by Plan 03 |
| EDGE-11 | §3 | Filled by Plan 03 |
| EDGE-12 | §3 | Filled by Plan 03 |
| EDGE-13 | §3 | Filled by Plan 03 |
| EDGE-14 | §3 | Filled by Plan 03 |
| EDGE-15 | §3 | Filled by Plan 03 |
| EDGE-16 | §3 | Filled by Plan 03 |
| EDGE-17 | §3 | Filled by Plan 03 |
| EDGE-18 | §3 | Filled by Plan 03 |

## §1 — Invariant Model (INV-01..12)

_To be filled by Plan 01 — see PLAN.md_

## §2 — Locked Design Decisions (SPEC-01..05)

_To be filled by Plan 02 — see PLAN.md_

## §3 — Edge Scenario Enumeration (EDGE-01..18)

_To be filled by Plan 03 — see PLAN.md_

## §4 — Design-Intent Backward-Trace + Actor Game-Theory Walk

_To be filled by Plan 04 — see PLAN.md_

## §5 — Source-Verified Citation Manifest

_To be filled by Plan 05 — see PLAN.md_
