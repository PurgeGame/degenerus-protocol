---
phase: 256-charity-allowlist-test-coverage
plan: 02
subsystem: testing
tags: [hardhat, esm, charity-allowlist, gnrus, v33, prune]

# Dependency graph
requires:
  - phase: 256-charity-allowlist-test-coverage
    plan: 01
    provides: test/helpers/charityFixture.js (impersonate, stopImpersonating, giveSDGNRS, deployGNRUSFixture, POOL_REWARD)
provides:
  - Pruned v33-compatible unit test surface in test/unit/DegenerusCharity.test.js (token mechanics only — metadata, soulbound, burn, burnAtGameOver, receive, edge cases)
  - Local v33-shape distributeGNRUS helper (setCharity instant-apply + voter.vote(slot) + impersonated pickCharity)
affects:
  - 256 end-of-phase batched-approval gate (the prune diff joins 256-01 helper, 256-03a/b/c new file, 256-04 extension under one user-approval reply)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Local-only v33 distributeGNRUS helper (NOT exported from charityFixture.js — kept unit-file-internal per Plan 01 D-256-HELPER-01)
    - vote(uint8 slot) drives bestWeight > 0 to bypass pickCharity skip-path B (single-active-slot zero-vote → LevelSkipped)

key-files:
  created: []
  modified:
    - test/unit/DegenerusCharity.test.js (992 → 390 lines; 78 it-blocks → 30 it-blocks; pruned to v33 token mechanics only)

key-decisions:
  - "Removed the // SKIPPED: 'burn with claimable winnings' comment block at original L363-365 alongside the plan-mandated // SKIPPED comment at original L985-990. Both are explanatory comments about tests that were never written; feedback_no_history_in_comments.md applies identically to both. Plan only called out the second one but the same policy applies."
  - "Did not pad the file to hit the plan's predicted 460-560 line window. Final count is 390 because section-numbering // 1. ... // 9. comments + // ===== separator banners + the L363-365 SKIPPED comment all went per feedback_no_history_in_comments.md. The structural acceptance criteria (zero v32 vocabulary, all kept describes pass, correct imports) are the binding signals; the line-count window was a planner estimate."
  - "Per orchestrator override (feedback_no_contract_commits.md + feedback_batch_contract_approval.md): NO test/ commit made by this agent. Diff staged in working tree only — end-of-phase batched approval gate owned by orchestrator."

patterns-established:
  - "Local distributeGNRUS in unit file uses voter1 (100 sDGNRS, fixture default) — single voter is sufficient because v33 winner-loop uses strict > so a single weighted slot wins."
  - "callsite signature for distributeGNRUS is (charity, deployer, recipientAddr, gameAddress, voter) — recipientAddr is the .address (already-resolved string), not the signer object."

requirements-completed:
  - "TST-01 (prune side) — three v32 governance describes deleted; kept describes still pass against v33 HEAD; v32 token vocabulary purged (PROPOSE_THRESHOLD_BPS / VAULT_VOTE_BPS / MAX_CREATOR_PROPOSALS / propose / proposalCount / hasProposed / creatorProposalCount / ProposalCreated / InvalidProposal / RecipientIsContract — all gone). The setCharity coverage side of TST-01 lands in Plan 03a."

# Metrics
duration: ~12 min
completed: 2026-05-06
---

# Phase 256 Plan 02: DegenerusCharity.test.js v33 Prune Summary

**Pruned `test/unit/DegenerusCharity.test.js` from 992 lines / 78 it-blocks to 390 lines / 30 it-blocks. All three v32 Governance describes (`Governance -- Propose`, `Governance -- Vote`, `Governance -- pickCharity`) deleted entirely. Module-level constants `PROPOSE_THRESHOLD_BPS`, `VAULT_VOTE_BPS`, `MAX_CREATOR_PROPOSALS`, and the local `POOL_REWARD = 3` deleted (POOL_REWARD now imported from `../helpers/charityFixture.js`). In-file `impersonate` / `stopImpersonating` / `giveSDGNRS` / `deployGNRUSFixture` definitions replaced with named imports from the same helper. The `Token Metadata` `proposalCount` assertion deleted. The `Edge Cases` describe pruned from 4 it-blocks to 1 (only `totalSupply is conserved` kept). Local `distributeGNRUS` helper rewritten from v32 `propose`+`vote(id, true)` shape to v33 `setCharity(slot, recipientAddr)`+`voter.vote(slot)`+impersonated `pickCharity(level)` shape, and all 16 callsites rewired to the new 5-arg signature. All 30 surviving tests pass against post-Phase-255 GNRUS HEAD.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-06T09:44:03Z
- **Completed:** 2026-05-06T09:55:24Z
- **Tasks:** 1 of 2 task blocks executed (Task 2 checkpoint commit deferred per orchestrator end-of-phase batched-approval override)
- **Files modified:** 1 (`test/unit/DegenerusCharity.test.js`, in working tree only — no commit per override)

## Accomplishments

- File shrank from 992 → 390 lines (−602 net, 60.7% reduction).
- It-block count dropped from 78 → 30 (kept exactly the v33-relevant token-mechanics surface).
- All 30 retained tests pass: `npx hardhat test test/unit/DegenerusCharity.test.js` → `30 passing`.
- Rewired the local `distributeGNRUS` helper to the v33 `setCharity` instant-apply branch + `voter.vote(slot)` + impersonated `pickCharity` shape — proven correct by the 11 Burn Redemption + 6 burnAtGameOver + 1 Edge Cases callsites that consume it.
- Imports come exclusively from existing helpers (`testUtils.js` for `eth` / `getEvent` / `getEvents` / `ZERO_ADDRESS`; `charityFixture.js` for the v33 fixture surface). No new dependencies added.
- Zero v32 governance vocabulary left in the file. Verified by the full-spectrum grep sweep below.
- Zero history-in-comments leaked through. Per `feedback_no_history_in_comments.md`: deleted lines leave NO trace — no `// removed for v33.0`, no `// was: PROPOSE_THRESHOLD_BPS`, no commented-out code, no `// section X` numbering, no `// =====` banners.

## Final Describe / It-Block Layout

| Describe                       | It-blocks (kept) | Notes |
| ------------------------------ | ---------------- | ----- |
| `Token Metadata`               | 7                | Dropped `proposalCount starts at 0` (v33 has no `proposalCount`) |
| `Soulbound Enforcement`        | 3                | Unchanged |
| `Burn Redemption`              | 11               | All `distributeGNRUS` callsites rewired to 5-arg shape; structure unchanged |
| `burnAtGameOver`               | 6                | One callsite to `distributeGNRUS` rewired; structure unchanged |
| `receive() -- ETH acceptance`  | 2                | Unchanged |
| `Edge Cases`                   | 1                | Pruned from 4 → 1 (kept `totalSupply is conserved`; deleted three v32-shape multi-level / proposer-after-resolve / count-resets it-blocks) |
| **Total**                      | **30**           | (was 78) |

## v33 distributeGNRUS Shape

```js
async function distributeGNRUS(charity, deployer, recipientAddr, gameAddress, voter) {
  const slot = 5;                                                    // any non-locked, non-conflicting slot
  const level = await charity.currentLevel();
  await charity.connect(deployer).setCharity(slot, recipientAddr);   // instant-apply (empty slot)
  await charity.connect(voter).vote(slot);                           // bestWeight > 0 → distribution fires
  const gameSigner = await impersonate(gameAddress);
  await charity.connect(gameSigner).pickCharity(level);              // resolve
  await stopImpersonating(gameAddress);
}
```

The `voter` parameter is required: contract `pickCharity` skip-path B at `contracts/GNRUS.sol:653` (`if (bestSlot == type(uint8).max)`) fires when no slot has `slotApproveWeight[level][i] > 0`, even with exactly one active slot — because `bestSlot` is initialized to `type(uint8).max` and only assigned inside the strict `w > bestWeight` branch (so a slot with `w == 0` never wins). Without a vote, the helper would emit `LevelSkipped` instead of distributing — `voter1` (100 sDGNRS, fixture default) is the natural caller.

All 16 callsites use `voter1`. The voter identity is irrelevant to every assertion in the file — only `balanceOf(recipientAddr)` is asserted post-distribution, so the single voter pattern is uniform and correct.

## Verification Results

### Per-File Hardhat Run

```
npx hardhat test test/unit/DegenerusCharity.test.js

  GNRUS (GNRUS)
    Token Metadata          7 passing
    Soulbound Enforcement   3 passing
    Burn Redemption        11 passing
    burnAtGameOver          6 passing
    receive() ...           2 passing
    Edge Cases              1 passing

  30 passing (16s)
```

(Trailing `Cannot find module 'test/unit/DegenerusCharity.test.js'` Mocha-on-ESM file-unloader error fires AFTER the green summary — same upstream cleanup quirk noted in Plan 01 SUMMARY. Non-functional.)

### Acceptance-Criteria Grep Panel

| Check | Required | Observed |
| ----- | -------- | -------- |
| v32-token sweep (`propose` / `ProposalCreated` / `proposalCount` / `hasProposed` / `creatorProposalCount` / `InvalidProposal` / `RecipientIsContract` / `PROPOSE_THRESHOLD_BPS` / `VAULT_VOTE_BPS` / `MAX_CREATOR_PROPOSALS` / `levelProposalStart` / `levelProposalCount` / `levelVaultOwner` / `levelSdgnrsSnapshot`) | 0 | **0** |
| History-in-comments sweep (`removed` / `was:` / `migrated` / `v32` / `Phase 254` / `Phase 255` / `TODO` / `FIXME`) | 0 | **0** |
| `describe("Governance -- Propose"\|... -- Vote"\|... -- pickCharity"` | 0 | **0** |
| `describe("Token Metadata"\|... Soulbound Enforcement"\|... Burn Redemption"\|... burnAtGameOver"\|... receive() -- ETH acceptance"\|... Edge Cases"` | 6 | **6** |
| `from "../helpers/charityFixture.js"` | 1 | **1** |
| In-file helper defs (`async function impersonate(` / `stopImpersonating(` / `giveSDGNRS(` / `deployGNRUSFixture(`) | 0 | **0** |
| Local `distributeGNRUS` def | 1 | **1** |
| `setCharity(slot, recipientAddr)` instant-apply call (in helper) | 1 | **1** |
| Line count `≥ 460 ∧ ≤ 560` | true | **390** (DEVIATION — see below; no functional impact) |

All 8 binding criteria pass. The line-count predicted window was missed by undershoot (deeper prune than predicted) — see Deviations.

### Cross-File Suite

`npx hardhat test` (full project suite) reports `1221 passing, 9 pending, 20 failing`. The 20 failures are all in `test/gas/AdvanceGameGas.test.js` (gas worst-case benchmark assertions — e.g., `worst case: ETH/stETH split to vault + DGNRS`). These are **pre-existing** and unrelated to this plan: the prune touches no contracts and no other test files. Flagging here so the user is aware of the broader suite state, not as a Plan 02 regression.

## Files Created/Modified

- `test/unit/DegenerusCharity.test.js` (MODIFIED in working tree, NOT committed) — 992 → 390 lines. Three v32 Governance describes removed entirely (no commented-out trace, no `// removed` annotations). Module-level v32 constants removed. In-file helpers replaced by named imports from `charityFixture.js`. Local `distributeGNRUS` rewritten to v33 shape. Token Metadata `proposalCount` assertion removed. Edge Cases reduced to single conservation it-block.

## Decisions Made

- **L363-365 `// SKIPPED: "burn with claimable winnings"` comment removed alongside the plan-mandated L985-990 removal.** Both are explanatory comments about tests that were never written. Plan Edit F explicitly applied `feedback_no_history_in_comments.md` to L985-990 ("v32-era explanatory comment about a test that was never written; it has no analog in v33 and leaving it is history-in-comments"). The same reasoning applies verbatim to L363-365 — extending the same policy to a structurally identical comment 600 lines earlier is mechanical consistency.
- **Did not pad the file to hit the 460-560 line window.** Final 390 lines reflect the deeper-than-predicted prune driven by (a) deletion of all `// =====` separator banners (~24 lines), (b) deletion of `// 1. Token Metadata`, `// 2. Soulbound Enforcement`, ..., `// 9. Edge Cases and Integration` section-numbering comments, and (c) Deviation 1 above. The plan's binding criteria (zero v32 vocabulary, all kept describes pass, correct structure, no history-in-comments) are all satisfied — the line-count window was a planner estimate, not a load-bearing constraint.
- **No `test/` commit made.** Per orchestrator override at spawn time: `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` — all `test/` edits in Phase 256 batch into ONE end-of-phase user approval. The plan's Task 2 checkpoint (per-file commit on user "approved") is superseded by the orchestrator-level batched gate.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — feedback_no_history_in_comments.md scope] Removed the `// SKIPPED: "burn with claimable winnings"` comment block at original L363-365**

- **Found during:** Task 1 (Edit F application — checking the symmetry of the SKIPPED comment policy across the file).
- **Issue:** Plan Edit F mandated removal of the `// SKIPPED:` comment at L985-990 (Edge Cases) under `feedback_no_history_in_comments.md`. A structurally identical `// SKIPPED:` comment exists at L363-365 (Burn Redemption) with the same v32-era "test was never written" character. Leaving one and removing the other would split the policy.
- **Fix:** Removed both. The L363-365 deletion is consistent with the plan's stated rationale ("v32-era explanatory comment about a test that was never written; it has no analog in v33 and leaving it is history-in-comments").
- **Rule:** Rule 1 (consistency with policy choice the plan already made).
- **Files modified:** `test/unit/DegenerusCharity.test.js` (working tree).
- **Committed in:** N/A — see "No commit" under Decisions Made.

**2. [Rule 1 — Acceptance-criterion miss, structural criteria preserved] File line count = 390, plan predicted 460-560**

- **Found during:** Task 1 verification grep panel.
- **Issue:** Plan acceptance criterion: `wc -l test/unit/DegenerusCharity.test.js ≤ 560 and ≥ 460`. Actual: 390. Drivers: (a) deletion of all `// =====` 60-char separator banners (~24 lines across 9 banners) per plan Edit E, (b) deletion of `// 1. Token Metadata`, `// 2. Soulbound Enforcement`, ..., `// 9. Edge Cases and Integration` section-numbering comments per plan Edit E, (c) Deviation 1 above (L363-365 removal, ~3 lines).
- **Fix:** Did NOT pad with no-op or filler comments. The line-count window is a planner estimate; the binding structural criteria (zero v32 vocabulary, kept describes pass, correct imports, no history-in-comments) are all satisfied. Padding would directly violate `feedback_no_history_in_comments.md` (any padding comment would be cruft).
- **Rule:** Rule 1 (acceptance-criterion conflict resolved by selecting the stronger policy criterion over the prediction).
- **Files modified:** None (no remediation needed).
- **Committed in:** N/A.

**3. [Rule 3 — Orchestrator Override] Task 2 commit step skipped — defer to end-of-phase batched approval**

- **Found during:** Task 2 (checkpoint:human-verify gate).
- **Issue:** Plan Task 2 specifies a per-file approval-then-commit gate. Orchestrator override at spawn time per `feedback_batch_contract_approval.md`: all `test/` edits in Phase 256 batch into ONE diff at end of phase, NOT per-plan; per `feedback_no_contract_commits.md`, agents must NEVER commit `test/` files without explicit user approval.
- **Fix:** Left `test/unit/DegenerusCharity.test.js` MODIFIED in the working tree (uncommitted, ` M` in `git status`). Orchestrator owns the end-of-phase batched diff presentation.
- **Files modified:** None (deviation is the absence of a commit).
- **Verification:** `git status --short test/unit/DegenerusCharity.test.js` returns ` M test/unit/DegenerusCharity.test.js` — modified, unstaged, uncommitted. No staged or committed `test/` or `contracts/` change made by this agent.
- **Committed in:** N/A — deferred to end-of-phase batched approval gate.

---

**Total deviations:** 3 auto-fixed (1 policy-consistency extension, 1 line-count window miss with structural criteria preserved, 1 orchestrator-override-driven commit deferral).

**Impact on plan:** All three are scope-preserving. Deviations 1 and 2 are downstream effects of correctly applying `feedback_no_history_in_comments.md`. Deviation 3 is the orchestrator-mandated approval-batching pattern.

## Issues Encountered

- **Pre-existing 20 failures in `test/gas/AdvanceGameGas.test.js`** observed during cross-file `npx hardhat test`. Unrelated to this prune (no contracts touched, no other test files modified). Flagging for user awareness, not as a Plan 02 regression.
- **Trailing Mocha-on-ESM file-unloader error** fires AFTER the green test summary on per-file runs. Same upstream cleanup quirk noted in Plan 01 SUMMARY — non-functional, no remediation possible at this layer.
- **Mid-execution system-reminder** posted during the cross-file suite run noted that the file "was modified, either by the user or by a linter" with instruction "don't revert it unless the user asks you to". The current disk state IS the prune (the modification the system-reminder was describing). No revert occurred; the prune persists. Documenting here for transparency.

## User Setup Required

None for this plan — but the end-of-phase user approval gate is required before any `test/` commit. The diff produced by this plan joins:
- Plan 01: `test/helpers/charityFixture.js` (new, 123 lines)
- Plan 02 (this): `test/unit/DegenerusCharity.test.js` (modified, −602 net)
- Plans 03a / 03b / 03c: `test/governance/CharityAllowlist.test.js` (new)
- Plan 04: `test/integration/CharityGameHooks.test.js` (modified, extension)

Orchestrator owns the consolidated diff presentation.

## Next Phase Readiness

- **Plan 03a, 03b, 03c, 04 unaffected** — they touch disjoint files. The orchestrator's parallel-execution awareness note in the spawn prompt confirmed no cross-file conflict.
- **End-of-phase approval gate pending.** Orchestrator collects the batched Phase 256 diff and presents it to the user for explicit "approved" reply.
- **No `test/` or `contracts/` commits made by this agent** (per orchestrator override + `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`).
- **No blockers.** Pruned file is syntactically valid ESM, all 30 retained tests pass, zero v32 vocabulary remains, no history-in-comments.

## Self-Check: PASSED

- File on disk: `test/unit/DegenerusCharity.test.js` exists at 390 lines (verified via `wc -l`).
- Working-tree state: ` M test/unit/DegenerusCharity.test.js` (modified, uncommitted — verified via `git status --short`).
- Per-file hardhat run: 30 / 30 passing (verified via `npx hardhat test test/unit/DegenerusCharity.test.js`).
- All 8 acceptance-criteria greps pass (verified inline above).
- No `test/` or `contracts/` commits made by this agent (verified — `git log` HEAD unchanged from session start `18cb9276`).
- SUMMARY.md is in `.planning/` (gitignored — orchestrator batches with `-f` at end of phase).

---

*Phase: 256-charity-allowlist-test-coverage*
*Status: COMPLETE — pruned file in working tree, awaiting end-of-phase batched user approval*
*Completed: 2026-05-06*
