---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 07
subsystem: contract-commit-orchestration
tags: [batched-contract-commit, user-approved, commit-guard-bypass, deferred-docs, keeper-pending]
requires:
  - "317-02..317-06 (all Wave-2/3/4 contract edits + the assembled D-04 review package)"
  - "USER approval at the Task-2 blocking-human checkpoint"
provides:
  - "The single batched USER-APPROVED degenerus-audit/contracts/ commit (14 files)"
  - "The deferred test/ slot re-derivation + D-03 compile-fix commit"
  - "The deferred .planning/ docs commit + ROADMAP plan-progress (01-06 complete)"
affects:
  - "Phase 318 TST (tests target this committed patched tree)"
  - "The keeper-side D-01b Option A (../degenerus-utilities) — STILL PENDING, separate agent"
  - "Phase 317 final verification + completion — STILL PENDING, orchestrator-owned"
tech-stack:
  added: []
  patterns:
    - "CONTRACTS_COMMIT_APPROVED=1 guard-hook bypass used ONLY for the one approved commit"
    - "Commit ordering: contracts/ first (unblocks the guard), then test/, then force-added .planning/"
key-files:
  created:
    - ".planning/phases/317-.../317-07-SUMMARY.md"
  modified:
    - "contracts/ (14 files — committed in df4ef365)"
    - "test/ (13 files — committed in 16b0837f)"
    - ".planning/ROADMAP.md (plan-progress 01-06 -> [x])"
decisions:
  - "Commit ONLY the audit-repo; ../degenerus-utilities left untouched (keeper D-01b Option A is a separate agent's job, after this)"
  - "Nothing pushed (feedback_manual_review_before_push — user reviews before any push)"
metrics:
  duration: "single session 2026-05-23"
  completed: "2026-05-23"
---

# Phase 317 Plan 07: Batched Contract Commit + Deferred Docs/Test Commits Summary

The single batched USER-APPROVED `degenerus-audit/contracts/` commit was made exactly once (14 files,
`CONTRACTS_COMMIT_APPROVED=1` guard-hook bypass after the human approved at the Task-2 blocking-human
checkpoint), followed by the deferred `test/` slot-re-derivation commit and the force-added `.planning/`
docs commit. The contracts/ tree is clean post-commit. Nothing was pushed. `../degenerus-utilities` was
NOT touched — the keeper-side D-01b Option A and the phase-level verification remain pending.

## What Was Done (Task 3 — Tasks 1-2 already complete)

Tasks 1 (assemble the D-04 review package) and 2 (the blocking-human USER-APPROVAL checkpoint) were
completed in the prior session. The user reviewed `317-DIFF-REVIEW.md` + `git diff -- contracts/` +
`contracts/AfKing.sol` and responded **approved**, explicitly accepting: the 26 mapped requirements, the
4 net-new SUB-09 `afKing` keeper-reference matches, the out-of-scope `BurnieCoinflip._targetFlipDay`
GameTimeLib gas opt, and the BurnieCoinflip header doc-comment cleanup. The user also chose D-01b
**Option A** (remap `../degenerus-utilities` to the canonical `contracts/AfKing.sol`) — OUT OF SCOPE for
this agent; handled separately afterward.

This plan executed Task 3 — the three commits, audit-repo only.

## The Three Commits (exact order)

The order is mandatory: the commit-guard hook blocks ALL commits while `contracts/*.sol` is dirty, so the
approved contracts/ commit must land FIRST to unblock the test/ and docs commits.

| # | Type | SHA | Files | Notes |
|---|------|-----|-------|-------|
| 1 | `feat(317)` batched contracts/ | `df4ef365` | 14 (13 modified + new `contracts/AfKing.sol`) | The approved mainnet commit; `CONTRACTS_COMMIT_APPROVED=1`; requirement-mapped message (PROTO-01..05, CRANK-01..04, REW-01..04, SUB-01..09, RM-01..06, JGAS-02 + new in-tree AfKing keeper + the out-of-scope `_targetFlipDay` gas opt) |
| 2 | `test(317)` slot re-derivation | `16b0837f` | 13 test/ files | RM-06 SLOT_* re-derivation (−2 family) + D-03 compile-fixes; ZERO contracts/*.sol |
| 3 | `docs(317)` phase artifacts | (this docs commit) | force-added `.planning/` artifacts + ROADMAP/STATE updates + this SUMMARY | ZERO contracts/*.sol |

**The 14 staged-and-committed contract files (commit 1):** `AfKing.sol` (NEW), `BurnieCoin.sol`,
`BurnieCoinflip.sol`, `ContractAddresses.sol`, `DegenerusGame.sol`, `DegenerusVault.sol`,
`StakedDegenerusStonk.sol`, `interfaces/IBurnieCoinflip.sol`, `interfaces/IDegenerusGame.sol`,
`modules/DegenerusGameAdvanceModule.sol`, `modules/DegenerusGameJackpotModule.sol`,
`modules/DegenerusGameMintModule.sol`, `modules/DegenerusGamePayoutUtils.sol`,
`storage/DegenerusGameStorage.sol`. Verified before commit: exactly 14 files, all under `contracts/`,
NONE under `contracts/test` or `contracts/mocks`, and no test/ or `.planning/` files in the same commit.
`git diff --stat`: 14 files changed, 1286 insertions(+), 753 deletions(-). No whole-file deletions (the
753 deletions are intra-file legacy-code removals, as expected for the RM-01..06 + JGAS-02 surface).

## Post-Commit State (verified)

- `git status --porcelain -- contracts/` is **EMPTY** — the contracts/ working tree is clean.
- Exactly ONE commit (`df4ef365`) contains `contracts/*.sol` changes. Commits 2 and 3 contain ZERO
  `contracts/*.sol`.
- ROADMAP plan-progress: plans 317-01..317-06 are `[x]` complete; **317-07 remains `[ ]`** and the phase
  is **NOT** marked complete (the orchestrator owns final phase completion).

## What Remains Pending (NOT this agent's scope)

1. **Keeper-side D-01b Option A** — remap/rework `../degenerus-utilities` to consume the canonical
   `contracts/AfKing.sol`, then commit it in its own repo. A separate agent handles this after the
   audit-repo commits. `../degenerus-utilities` was left entirely untouched here.
2. **Phase 317 verification + completion** — orchestrator-owned. Plan 07 and the phase are intentionally
   left unchecked.

## Absolute Rules Honored

- **Nothing pushed** (`feedback_manual_review_before_push` — the user reviews the diff before any push).
- **`../degenerus-utilities` untouched** — not staged, not committed, not modified.
- **Exactly ONE contracts/ commit** (commit 1); commits 2 and 3 carry zero `contracts/*.sol`.
- The guard-hook bypass (`CONTRACTS_COMMIT_APPROVED=1`) was used ONLY for the one approved commit; the
  test/ and docs commits ran with the guard active (and passed because contracts/ was clean).
- No edit was ever described as "pre-approved" — it was reviewed and approved at the checkpoint.

## Self-Check: PASSED

- Commit 1 `df4ef365` exists and contains exactly the 14 contract files. CONFIRMED.
- Commit 2 `16b0837f` exists, 13 test/ files, zero contracts/*.sol. CONFIRMED.
- contracts/ working tree clean post-commit. CONFIRMED.
- `../degenerus-utilities` untouched; nothing pushed. CONFIRMED.
