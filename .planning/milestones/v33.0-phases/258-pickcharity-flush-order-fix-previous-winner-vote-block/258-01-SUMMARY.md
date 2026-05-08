---
phase: 258-pickcharity-flush-order-fix-previous-winner-vote-block
phase_number: 258
plan: 01
plan_id: 258-01
plan_number: 01
subsystem: governance/contracts
tags:
  - fix
  - charity-allowlist-governance
  - FIX-01
  - FIX-02
  - pickCharity-reorder
  - previous-winner-block
  - feedback_no_contract_commits
  - feedback_batch_contract_approval
  - feedback_never_preapprove_contracts
  - feedback_no_history_in_comments
  - feedback_no_dead_guards
  - feedback_manual_review_before_push
  - feedback_wait_for_approval

# Dependency graph
requires:
  - phase: 257-delta-audit-findings-consolidation
    reason: "Phase 257's independent re-run surfaced FIX-01 (pickCharity flush ordering) and FIX-02 (previous-winner block) as gaps in the v33.0 charity-allowlist closure; 258 fixes them under a post-closure patch."
provides:
  - "contracts/GNRUS.sol pickCharity flush-after-payout reorder (FIX-01) — queued setCharity edits at level L now apply to L+1 instead of redirecting L's votes mid-flush"
  - "contracts/GNRUS.sol lastWinningRecipient state slot + PreviousWinnerNotVotable error + vote() guard (FIX-02) — prevents consecutive wins by the same recipient; skipped levels retain prior block"
  - "test/governance/CharityAllowlist.test.js flipped Section 5 queued-replace it-block (OLD-recipient-pays-at-L semantic) + new describe with 3 prev-winner-block it-blocks"
affects:
  - v33.0-milestone-supersedence-pending
  - audit/FINDINGS-v33.0.md-re-open-pending

# Tech-stack
tech-stack:
  added: []
  patterns:
    - "Storage-slot single-writer: lastWinningRecipient is written ONLY in the distribution-paid path of pickCharity(); skip-paths leave it unchanged so the previous-winner block correctly survives skipped levels."
    - "Error-first guard: vote(uint8) reverts PreviousWinnerNotVotable() AFTER slot-bounds + empty-slot guards — preserves existing revert ordering."
    - "Flush-after-payout: pickCharity body restructured so all skip-paths fall through to the queued-edit flush block instead of returning early; flush is the function's tail phase."

# Key files
key-files:
  created:
    - .planning/phases/258-pickcharity-flush-order-fix-previous-winner-vote-block/258-01-SUMMARY.md
  modified:
    - contracts/GNRUS.sol
    - test/governance/CharityAllowlist.test.js
    - test/unit/DegenerusCharity.test.js

# Decisions
key-decisions:
  - id: D-258-01-DEVIATION-01
    description: "Third file (test/unit/DegenerusCharity.test.js) added to the batched approval gate. The FIX-02 previous-winner guard caused a downstream regression in the conservation test (consecutive distributions to the same slot now revert PreviousWinnerNotVotable). Fix parameterized the distributeGNRUS(slot = 5) helper and rotated slots across consecutive distributions in the conservation test. Direct downstream regression-fix from the contract change; in-scope per Phase 258 success criterion 6 ('no regressions in DegenerusCharity.test.js'). User explicitly approved batched landing of all three files."
  - id: D-258-01-FLUSH-ORDER
    description: "Chose flush-after-payout (single tail block) over per-skip-path duplicate-flush. Single-tail keeps the flush invariant in one location, eliminates dead branches per feedback_no_dead_guards, and matches the must_haves truth: 'Skip-paths A/B/C fall through to the flush phase instead of returning early'."
  - id: D-258-01-LASTWINNER-SCOPE
    description: "lastWinningRecipient is written ONLY in the distribution-paid path (after the balanceOf write), NOT in skip-paths. Skipped levels MUST retain the prior winner's block so a one-level vote skip cannot be exploited to re-elect the L-1 winner at L+1. Pinned by the third new it-block ('skipped level retains prior block')."

# Requirements
requirements-completed:
  - FIX-01
  - FIX-02

# Audit anchors
baseline: dcb70941
head_anchor_at_plan_start: eb0dfa2a
head_anchor_at_plan_close: 4ce3703d740d3707c88a1af595618120a8168399

# Metrics
metrics:
  duration: ~ (continuation agent — commits + summary only; full plan execution spanned prior agent + this one)
  completed: 2026-05-06
  tasks_completed: 4
  files_modified: 3
  files_created: 1
  commits: 2
---

# Phase 258 Plan 01: pickCharity Flush-After-Payout + Previous-Winner Vote Block — Summary

## One-liner

Restructured `pickCharity(uint24)` to flush queued setCharity edits AFTER the distribution payout (FIX-01), and added a `lastWinningRecipient` state slot + `PreviousWinnerNotVotable()` revert in `vote(uint8)` to prevent consecutive wins by the same recipient (FIX-02) — pinned by a flipped Section 5 queued-replace assertion and three new previous-winner-block it-blocks.

## What Was Built

**Contract (`contracts/GNRUS.sol`):**

1. **FIX-01 — pickCharity flush-after-payout reorder.** The function body was restructured so that all four execution paths (distribution-paid, skip-A no-votes, skip-B all-equal, skip-C all-zero) fall through to a single tail-phase queued-edit flush block. Previously skip-paths returned early and queued edits during level L could silently redirect L's votes mid-flush. After this change, queued `setCharity` edits during level L apply to L+1.

2. **FIX-02 — previous-winner vote block.** Added `address public lastWinningRecipient;` storage slot, written only in the distribution-paid path immediately after the recipient's balance is credited. Skip-paths leave the slot unchanged so a skipped level retains the prior level's block. Added `error PreviousWinnerNotVotable();` declaration and a guard in `vote(uint8 slot)` that reverts when `currentSlate[slot] == lastWinningRecipient` (placed after existing slot-bounds and empty-slot guards to preserve revert ordering).

**Tests:**

3. **`test/governance/CharityAllowlist.test.js` Section 5 queued-replace flip.** The existing it-block was flipped from the old (incorrect) semantic to the corrected FIX-01 semantic: voters pay the OLD recipient at level L payout; the NEW recipient appears in `currentSlate` only after `pickCharity(L)` returns; the new recipient is votable starting at L+1 (subject to `PreviousWinnerNotVotable` if the OLD recipient won L).

4. **`test/governance/CharityAllowlist.test.js` new `describe('vote() previous-winner block (FIX-02)')`** with three it-blocks:
   - (a) Charity that won level L cannot be voted for at L+1 via the slot it occupied — reverts `PreviousWinnerNotVotable`.
   - (b) Vault-owner queue-replace between level L payout and level L+1 vote opening unblocks the slot (new recipient is votable at L+1).
   - (c) Skipped level (no winner) leaves `lastWinningRecipient` unchanged — the L-1 winner remains blocked at L+1.

5. **`test/unit/DegenerusCharity.test.js` regression-fix (D-258-01-DEVIATION-01).** Parameterized the `distributeGNRUS(slot = 5)` helper and updated the conservation test to rotate slots (5/6) across consecutive distributions. Required because FIX-02 now blocks re-distributing to the slot that won the prior level — the conservation invariant is unaffected, only the test's slot-reuse pattern needed updating. In-scope per Phase 258 success criterion 6.

## Verification (run by prior agent before approval gate)

| Suite | Result |
|---|---|
| `npx hardhat compile` | clean, 28 files |
| `npx hardhat test test/governance/CharityAllowlist.test.js` | 52 passing (49 baseline + 3 new) |
| `npx hardhat test test/integration/CharityGameHooks.test.js test/unit/DegenerusCharity.test.js` | 36 passing |

## Commits

| # | Hash | Subject |
|---|------|---------|
| 1 | 636f60ea | feat(258-01): pickCharity flush-after-payout reorder + lastWinningRecipient + PreviousWinnerNotVotable |
| 2 | 4ce3703d | test(258-01): flip queued-replace assertion to OLD-recipient-pays-at-L semantic + add prev-winner block coverage |

`head_anchor_at_plan_close = 4ce3703d740d3707c88a1af595618120a8168399`

## Deviations

**D-258-01-DEVIATION-01 — Third file added to batched approval gate.**
The plan's `files_modified` listed two files (`contracts/GNRUS.sol`, `test/governance/CharityAllowlist.test.js`). During Task 3 execution, the prior agent discovered that FIX-02 caused a downstream regression in `test/unit/DegenerusCharity.test.js`: the conservation test re-distributes to the same slot across consecutive levels, which now reverts `PreviousWinnerNotVotable`. The fix (parameterizing the helper + rotating slots in the conservation test) is a direct downstream regression-fix from the contract change, NOT a scope expansion — Phase 258 success criterion 6 explicitly requires "no regressions in DegenerusCharity.test.js". The third file was added to the batched diff and reviewed by the user under the same approval gate. **Honors `feedback_batch_contract_approval` (single batched review at end of phase) and `feedback_never_preapprove_contracts` (Task 4 IS the approval gate, not a formality).**

No other deviations.

## Authentication Gates

None — purely local contract + test work, no external services.

## Project Feedback Rules Honored

| Rule | Honored | Notes |
|---|---|---|
| `feedback_no_contract_commits` | YES | Commits 1 + 2 fired only after explicit user "approved" review of the full three-file diff. `CONTRACTS_COMMIT_APPROVED=1` was set per-commit (the pre-commit hook required it; this is the mechanical enforcement of the rule, not a bypass). |
| `feedback_batch_contract_approval` | YES | All three contract + test edits were batched into a single Task 4 approval gate; user reviewed once, two atomic commits landed under that single approval. |
| `feedback_never_preapprove_contracts` | YES | Orchestrator (and this executor) did NOT pre-approve. Task 4 was the actual review-and-approve gate; user explicitly typed "approved" after seeing the diff. |
| `feedback_no_history_in_comments` | YES | All NatSpec and inline comments in `contracts/GNRUS.sol` describe what the code IS; no "was previously" / "changed from" / "old behavior" prose. (Verified by prior agent during Task 1+2 staging.) |
| `feedback_no_dead_guards` | YES | The flush-after-payout reorder eliminated duplicate flush blocks across skip-paths; chose single-tail flush over per-path duplication (D-258-01-FLUSH-ORDER). No unreachable safety caps added. |
| `feedback_manual_review_before_push` | YES | No push fired in this plan. Two local commits land at HEAD; remote push is out of scope (would be a separate user-initiated step). |
| `feedback_wait_for_approval` | YES | Prior agent presented the full diff at Task 4 and waited; user typed "approved"; this continuation agent fired commits only after that explicit approval. |
| `feedback_contract_locations` | YES | All contract reads/writes targeted `contracts/GNRUS.sol` only; no stale-copy paths touched. |
| `feedback_skip_research_test_phases` | YES | This plan was a direct execution plan with no research phase — appropriate for a mechanical post-closure patch. |

## Closure Signal

**NOT emitted by this plan.** Phase 258 closure signal (v33.0 milestone supersedence + audit/FINDINGS-v33.0.md re-open) will be emitted by **258-02**, which reads `head_anchor_at_plan_close` (= `4ce3703d740d3707c88a1af595618120a8168399`) from this SUMMARY's frontmatter as its starting anchor.

## Self-Check: PASSED

**Files claimed modified — all verified:**
- `contracts/GNRUS.sol` — committed in `636f60ea` (1 file changed, 64 insertions, 51 deletions)
- `test/governance/CharityAllowlist.test.js` — committed in `4ce3703d` (part of 2 files / 139 insertions / 19 deletions)
- `test/unit/DegenerusCharity.test.js` — committed in `4ce3703d` (part of same commit)

**Commits claimed — both verified at HEAD:**
- `636f60ea` — present in `git log --oneline -3` output
- `4ce3703d` — present at HEAD

**Diff scope — verified:**
- `git diff --stat HEAD~2..HEAD -- contracts/ test/` reports exactly the three files listed above; no out-of-scope files included.

**Plan success criteria — all 7 ROADMAP items addressed (criteria 1-5 in this plan; 6 = no-regressions verified by prior agent's test run; 7 = closure attestation deferred to 258-02 per plan scope).**

PASSED.
