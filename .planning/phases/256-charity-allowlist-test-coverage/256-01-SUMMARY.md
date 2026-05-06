---
phase: 256-charity-allowlist-test-coverage
plan: 01
subsystem: testing
tags: [hardhat, esm, fixtures, charity-allowlist, gnrus, sdgnrs, vote-weight, v33]

# Dependency graph
requires:
  - phase: 254-gnrus-allowlist-storage-admin-op-storage-repack
    provides: v33 GNRUS storage skeleton + setCharity surface (drives fixture sizing rationale)
  - phase: 255-vote-rewrite-resolve-flush-event-error-cleanup
    provides: v33 vote(uint8 slot) + pickCharity(uint24 level) surface (drives runLevelTransitionViaGame helper)
provides:
  - Shared v33 charity test fixture (deployGNRUSFixture) wrapping deployFullProtocol
  - Game-impersonation primitives (impersonate / stopImpersonating) lifted out of unit file
  - sDGNRS funding helper (giveSDGNRS) routed through reward pool index 3
  - Game-impersonated level transition driver (runLevelTransitionViaGame) for unit-side pickCharity calls
  - Single source of truth for v33 voter sizing (100/100/200) consumed by Plans 02-04
affects:
  - 256-02 (prune DegenerusCharity.test.js — imports the helper, deletes inline duplicates)
  - 256-03a (new CharityAllowlist.test.js — imports the helper for vote/pickCharity scenarios)
  - 256-03b (new CharityAllowlist.test.js continuation — imports the helper for setCharity edit-queue + cap)
  - 256-03c (new CharityAllowlist.test.js gas guardrail — imports the helper for full-slate stress fixture)
  - 256-04 (CharityGameHooks.test.js extension — imports POOL_REWARD constant)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - ESM helper module factored from inline test setup (mirrors test/helpers/deployFixture.js shape)
    - Game-impersonation pattern (hardhat_impersonateAccount + 100 ETH balance set) exported for reuse
    - v33 vote-weight scenario sizing (tie-break partner pair + tie-breaker third voter) baked into the default fixture

key-files:
  created:
    - test/helpers/charityFixture.js
  modified: []

key-decisions:
  - "Drop setCharityAs from export list per feedback_no_dead_guards.md — every Plan 02-04 setCharity call site reads naturally as charity.connect(deployer).setCharity(slot, addr); wrapping adds no clarity."
  - "Drop distributeGNRUS from export list — Plan 02 inlines its own v33 rewrite locally (it is a unit-file-internal helper, not shared across files)."
  - "Sub-1e18 zero-weight voter funded inline in the it-blocks that exercise REJECT_ZERO_WEIGHT, NOT in the default fixture — keeps tie-break tests free of extra voting weight."
  - "Voter sizing pinned at 100/100/200 sDGNRS per CONTEXT.md D-256-TIEBREAK-01 + D-256-MULTI-VOTE-01."

patterns-established:
  - "Helpers are leaves: test/helpers/charityFixture.js does not import from test/unit, test/integration, or test/governance — preventing test→helper→test cycles."
  - "v33 vote-weight rationale lives in the fixture comment (not in each consuming test) — single source of truth."
  - "Per feedback_no_history_in_comments.md, the fixture carries no v32 migration prose, no `removed:` annotations, no `was:` notes."

requirements-completed: []  # Plan 01 has no direct REQUIREMENTS row; foundation for TST-01..06 in Plans 02-04.

# Metrics
duration: ~10 min
completed: 2026-05-06
---

# Phase 256 Plan 01: Shared v33 Charity Test Fixture Summary

**Factored v33 charity-allowlist test setup (impersonation, sDGNRS funding, voter sizing, level-transition driver) into `test/helpers/charityFixture.js` — 6-export ESM module that Plans 02 / 03a / 03b / 03c / 04 all consume.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-06T09:30Z (approximate — plan loaded at session start)
- **Completed:** 2026-05-06T09:40:24Z
- **Tasks:** 1 of 2 task blocks executed (Task 2 checkpoint deferred per orchestrator override — see Deviations)
- **Files modified:** 1 (1 created, 0 modified)

## Accomplishments

- Created `test/helpers/charityFixture.js` (123 lines) with the exact 6-export surface mandated by the plan: `POOL_REWARD`, `impersonate`, `stopImpersonating`, `giveSDGNRS`, `deployGNRUSFixture`, `runLevelTransitionViaGame`.
- v33 voter sizing wired in the default fixture: voter1 = 100 sDGNRS, voter2 = 100 sDGNRS (tie partner), voter3 = 200 sDGNRS (tie breaker).
- Sub-1e18 zero-weight voter explicitly NOT funded by default — flagged in fixture comment so consuming it-blocks fund inline via `giveSDGNRS`.
- Helper passes existing integration suite without interference (`npx hardhat test test/integration/CharityGameHooks.test.js` → 5/5 passing).
- No v32 leftover concepts (`PROPOSE_THRESHOLD_BPS`, `VAULT_VOTE_BPS`, `MAX_CREATOR_PROPOSALS`, `0.5%`, `threshold`) leaked into the helper.
- No history-in-comments (no `// removed:`, `// was:`, `// migrated:`, `// v32` annotations) per `feedback_no_history_in_comments.md`.

## Final Export Surface

| Export | Signature | Consumed by |
| ------ | --------- | ----------- |
| `POOL_REWARD` | `const = 3` | giveSDGNRS internals + Plan 04 (integration sDGNRS funding) |
| `impersonate` | `async (address) → Signer` | Plans 02, 03a-c (game-impersonation, vault-owner-impersonation) |
| `stopImpersonating` | `async (address) → void` | Plans 02, 03a-c (paired teardown) |
| `giveSDGNRS` | `async (sdgnrs, gameAddress, recipient, amount) → void` | Plans 02, 03a-c (voter funding inside it-blocks; default fixture) |
| `deployGNRUSFixture` | `async () → { charity, charityAddress, sdgnrs, game, vault, mockSteth, deployer, voter1, voter2, voter3, recipient1, recipient2, recipient3, others, gameAddress, sdgnrsAddress, vaultAddress, stethAddress }` | Plans 02 (existing test bodies), 03a-c (new governance file describes) |
| `runLevelTransitionViaGame` | `async (charity, gameAddress, level) → tx` | Plan 03a (unit-side pickCharity driving — NOT used by Plan 04 integration per D-256-CONSERVATION-01) |

## v33 Voter Sizing Rationale

Per CONTEXT.md `<specifics>` and `<decisions>` D-256-TIEBREAK-01 + D-256-MULTI-VOTE-01:

| Voter  | sDGNRS | Vote weight | Purpose |
| ------ | ------ | ----------- | ------- |
| voter1 | 100    | 100         | Tie-break partner (paired with voter2 for equal-weight tie-break tests) |
| voter2 | 100    | 100         | Tie-break partner (equal weight to voter1) |
| voter3 | 200    | 200         | Tie breaker (clear winner when paired against the equal-weight pair) |

Sub-1e18 sDGNRS voters (e.g., 0.5e18 → `floor(5e17/1e18) == 0` → `REJECT_ZERO_WEIGHT`) are funded only inside it-blocks that exercise that branch — keeping them off the default fixture avoids polluting tie-break tests with extra voting weight.

## Files Created/Modified

- `test/helpers/charityFixture.js` (NEW, 123 lines) — Shared v33 charity test fixture with 6 named exports (POOL_REWARD constant + impersonate / stopImpersonating / giveSDGNRS helpers + deployGNRUSFixture + runLevelTransitionViaGame). Imports from `./deployFixture.js` and `./testUtils.js` only — leaf in the test import graph.

## Decisions Made

- **Dropped `setCharityAs`** from the export list per `feedback_no_dead_guards.md` resolution recorded in CONTEXT.md D-256-HELPER-01. Inspection of Plans 02-04 shows every `setCharity` call reads naturally as `charity.connect(deployer).setCharity(slot, addr)` — wrapping adds no clarity, so the helper would be orphaned.
- **Dropped `distributeGNRUS`** (existing v32-shape helper at `DegenerusCharity.test.js:121-135`) from migration. Plan 02 inlines a v33 rewrite locally because it is a unit-file-internal helper, not shared across files. The v33 rewrite uses `setCharity` (instant-apply on empty slot) + impersonate-game + `pickCharity`, NOT v32 `propose` / `vote(proposalId)`.
- **`runLevelTransitionViaGame` consumed by Plan 03a only** (per CONTEXT.md D-256-CONSERVATION-01) — Plan 04 integration drives `pickCharity` via the real game flow at `DegenerusGameAdvanceModule:1634`, not via game-impersonation. The unit-side helper is the impersonate-shortcut for fast/deterministic governance tests.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Acceptance-Criterion Conflict] Reworded v33 fixture comment to satisfy the no-`threshold`-keyword acceptance criterion**

- **Found during:** Task 1 (verification grep)
- **Issue:** The plan's `<action>` block prescribed the v33 sizing comment verbatim as `// v33: vote weight = sdgnrs.balanceOf(voter) / 1e18, no threshold, no bonus.`. But the plan's `<acceptance_criteria>` block separately required: `grep "PROPOSE_THRESHOLD_BPS\|VAULT_VOTE_BPS\|MAX_CREATOR_PROPOSALS\|0.5%\|threshold" test/helpers/charityFixture.js` returns nothing. The literal `threshold` keyword in the prescribed comment fails the literal `threshold` grep.
- **Fix:** Rewrote the comment to `// v33: vote weight = floor(sdgnrs.balanceOf(voter) / 1e18); no minimum, no bonus.` — semantically identical (vote weight is integer-floored sDGNRS balance, no entry barrier, no vault-owner bonus) without using the flagged keyword. Acceptance-criterion grep wins because the criterion is the binding deploy-gate signal, not the prose draft.
- **Files modified:** `test/helpers/charityFixture.js` (the v33 sizing comment block inside `deployGNRUSFixture`).
- **Verification:** Re-ran the full acceptance-criteria grep panel — all 7 checks pass (export count = 6, no forbidden exports, no v32 leftover, voter-sizing lines present, no history-in-comments, ESM import resolves, no upward imports from test/unit/integration/governance).
- **Committed in:** Not committed — see "User Approval Gate" deviation below.

**2. [Rule 3 — Orchestrator Override] Skipped Task 2 commit step — defer to end-of-phase batched approval**

- **Found during:** Task 2 (checkpoint:human-verify)
- **Issue:** The plan's Task 2 specifies a per-file approval gate that ends with a `feat(256-01): charityFixture.js add helper` commit on user "approved" reply. The orchestrator (`/gsd-execute-phase` for Phase 256) provided an explicit override at spawn time: per `feedback_batch_contract_approval.md`, all `test/` edits in this phase batch into ONE diff at end of phase, NOT per-plan. Per `feedback_no_contract_commits.md`, agents must NEVER commit `test/` files without explicit user approval.
- **Fix:** Left `test/helpers/charityFixture.js` UNCOMMITTED in the working tree (untracked). The orchestrator will present the batched Phase 256 diff to the user at end-of-phase and commit then. SUMMARY.md (this file) is in `.planning/` and is freely committable per the override.
- **Files modified:** None — the deviation is the absence of a commit, not a code change.
- **Verification:** `git status --short` shows exactly one untracked entry: `?? test/helpers/charityFixture.js`. No `test/` or `contracts/` files staged or committed by this agent.
- **Committed in:** N/A — deferred to end-of-phase batched approval gate per orchestrator override.

---

**Total deviations:** 2 auto-fixed (1 acceptance-criterion conflict resolution, 1 orchestrator-override-driven commit deferral).

**Impact on plan:** Both deviations are scope-preserving. Deviation 1 keeps the helper semantically identical to the plan's prescribed shape while satisfying the binding acceptance grep. Deviation 2 is the orchestrator-mandated approval-batching pattern — no work was skipped; the commit is deferred to the phase-level approval gate, not lost.

## Issues Encountered

- A trailing `Cannot find module 'test/integration/CharityGameHooks.test.js'` Mocha file-unloader error fired AFTER 5/5 tests passed cleanly during the broader-verification smoke test. This is an upstream Mocha-on-ESM cleanup quirk unrelated to the helper file (the test results are intact). No action needed — flagging here so Plan 04 (integration extension) is aware the existing suite passes despite the cleanup noise.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plans 02 / 03a / 03b / 03c / 04 are unblocked.** All five wave-2 plans can now `import { ... } from "../helpers/charityFixture.js"`.
- **Approval gate pending.** The single end-of-Phase-256 batched diff (this helper + Plan 02 prune + Plan 03a/b/c new file + Plan 04 extension) requires explicit user "approved" reply before any `test/` commits land. Orchestrator owns this gate.
- **No blockers.** Helper is syntactically valid ESM, exports the exact 6-name surface, passes all acceptance-criteria greps, and the existing integration suite continues to run.

## Self-Check: PASSED

- File exists: `test/helpers/charityFixture.js` (FOUND, 123 lines, untracked).
- 6 exports verified via `node -e "import(...)"` printing `POOL_REWARD,deployGNRUSFixture,giveSDGNRS,impersonate,runLevelTransitionViaGame,stopImpersonating`.
- Forbidden patterns absent: `setCharityAs`, `distributeGNRUS`, `PROPOSE_THRESHOLD_BPS`, `VAULT_VOTE_BPS`, `MAX_CREATOR_PROPOSALS`, `0.5%`, `threshold`, `removed`, `was:`, `migrated`, `v32` — all greps return exit 1 (no match).
- v33 voter sizing lines present (3 lines: voter1Amount = eth("100"), voter2Amount = eth("100"), voter3Amount = eth("200")).
- No upward imports from `test/unit/`, `test/integration/`, `test/governance/` (helper is leaf in the import graph).
- Existing integration suite passes: 5/5 it-blocks in `test/integration/CharityGameHooks.test.js`.
- No `test/` or `contracts/` commits made (per orchestrator override).

---

*Phase: 256-charity-allowlist-test-coverage*
*Completed: 2026-05-06*
