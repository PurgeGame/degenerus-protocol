# Phase 317: IMPL — Batched ADD+REMOVE Contract Diff + Paired Keeper Rework - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-23
**Phase:** 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
**Areas discussed:** AfKing location & audit scope, Keeper-diff approval gate, Test scope 317 vs 318, Batched diff review format

> Context note: Phase 317's DESIGN is fully locked by `316-SPEC.md` (verified 5/5). Discussion was restricted to execution/process gray areas the SPEC does not decide. No design questions were re-opened.

---

## AfKing location & audit scope

| Option | Description | Selected |
|--------|-------------|----------|
| Copy into contracts/ | Bring AfKing.sol into degenerus-audit/contracts/ — first-class, audited in-tree, part of the approval-gated diff; canonical source. | ✓ |
| Stays in degenerus-utilities | Rework in place in the keeper repo; degenerus-audit only changes the PROTO interface surface; keeper audited separately. | |
| Audit-only frozen copy | Read-only snapshot into contracts/ for audit visibility; canonical stays in degenerus-utilities (dual-maintenance drift risk). | |

**User's choice:** Copy into contracts/ (Recommended)
**Notes:** Chosen over the audit-only frozen copy, so degenerus-audit/contracts/AfKing.sol is canonical, not a snapshot. Consequence: the contract-commit-guard hook now covers it; it's a large new-file part of the one approved diff. The degenerus-utilities deploy/import reconciliation to the canonical AfKing is a research/planning HOW-item.

---

## Keeper-diff approval gate

| Option | Description | Selected |
|--------|-------------|----------|
| Review keeper diff too | Present the degenerus-utilities AfKing rework for explicit review before commit, same discipline as the protocol diff, same review moment. | ✓ |
| Agent-commit the keeper | ROADMAP default — agent commits the keeper autonomously (not this repo's audit-subject; trips no commit hook); review the other repo afterward. | |

**User's choice:** Review keeper diff too (Recommended)
**Notes:** Overrides the ROADMAP's "AGENT-COMMITTED keeper" default. The commit-guard hook does not watch the other repo, so the executor enforces this gate manually by pausing for approval on the keeper diff alongside the protocol diff.

---

## Test scope: 317 vs 318

| Option | Description | Selected |
|--------|-------------|----------|
| Compile-fixes only | 317 patches test/mocks just enough to compile (forge build green = SC#1); no coverage/assertion work; behavioral rework → 318 TST. | ✓ |
| Leave test/mocks untouched | 317 touches zero test/mocks; only src must build; broken tests deferred to 318 (must verify SC#1 still achievable). | |
| Full test rework in 317 | Fold 318's test work into 317 — fix tests to PASS, not just compile; collapses the dedicated TST phase. | |

**User's choice:** Compile-fixes only (Recommended)
**Notes:** Resolves the tension that Foundry's `forge build` compiles `test/` too, so leaving them fully untouched could fail SC#1. The dedicated TST phase (318) is preserved for behavioral test rework + new coverage.

---

## Batched diff review format

| Option | Description | Selected |
|--------|-------------|----------|
| Mapped summary + diff + slots | Requirement-mapped summary (PROTO/RM/JGAS → file:hunk) + full git diff + forge inspect storage before/after, in one review. | ✓ |
| Full git diff only | Raw git diff of the batched contracts/ change, nothing added. | |
| Per-file walkthrough | File-by-file narration before the single approval, then the full diff. | |

**User's choice:** Mapped summary + diff + slots (Recommended)
**Notes:** Best fit for a large, slot-sensitive, multi-requirement diff; lets the user verify the re-derived −2 slot constants via the storage before/after.

---

## Claude's Discretion

- Cross-repo authoring sequence (protocol `batchPurchase` signature vs the keeper's call site — which authored first) left to planner/executor; contract is that the keeper's call MUST match the locked PROTO-04 signature.
- The mechanism degenerus-utilities uses to consume the canonical AfKing (import vs deploy-script reference) is a research/planning HOW-item.

## Deferred Ideas

- Behavioral test rework + new subscription/crank/removal coverage → Phase 318 TST (planned boundary, not a dropped idea; "full test green in 317" explicitly declined).
- No scope-creep ideas surfaced — discussion stayed within the IMPL boundary.
