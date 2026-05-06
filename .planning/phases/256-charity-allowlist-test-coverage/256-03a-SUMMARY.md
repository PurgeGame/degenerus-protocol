---
phase: 256-charity-allowlist-test-coverage
plan: 03a
subsystem: testing
tags: [hardhat, governance, charity-allowlist, gnrus, setCharity, locked-slots, edit-queue, structural-unreachability, v33]

# Dependency graph
requires:
  - phase: 254-gnrus-allowlist-storage-admin-op-storage-repack
    provides: v33 setCharity branches (instant-apply / queue / locked-slot guard / cap check) — entire admin surface this plan asserts against
  - phase: 255-vote-rewrite-resolve-flush-event-error-cleanup
    provides: v33 vote(uint8) + pickCharity(uint24) + CharityFlushed event — used in section 5 post-flush assertions
  - phase: 256-charity-allowlist-test-coverage (Plan 01)
    provides: test/helpers/charityFixture.js (deployGNRUSFixture, impersonate, stopImpersonating, giveSDGNRS, runLevelTransitionViaGame, POOL_REWARD)
provides:
  - test/governance/CharityAllowlist.test.js (NEW) sections 1-5 (setCharity instant-apply + queue + locked slots 0/1/2 + pending overwrite + 20-slot fill smoke + edit-queue level-boundary semantics)
  - File scaffolding (imports, pre-declared constants, top-level describe, after-hook) ready for Plans 03b and 03c to append-only
  - Inline structural-unreachability verdicts (CapExceeded + D-256-CANCEL-QUEUED-01) — Phase 257 AUDIT-02 SAFE-row evidence base
  - hardhat.config.js TEST_DIR_ORDER updated to include "governance" (Rule 3 fix; otherwise full-suite test discovery skips the new dir)
affects:
  - 256-03b (will append the vote() describe — Section 6 — into the same file using the pre-declared REJECT_EMPTY_SLOT/REJECT_ALREADY_VOTED/REJECT_ZERO_WEIGHT constants)
  - 256-03c (will append pickCharity / TST-06 / D-256-GAS-01 describes — Sections 7-9 — using REJECT_LEVEL_NOT_ACTIVE/REJECT_LEVEL_ALREADY_RESOLVED/DISTRIBUTION_BPS/BPS_DENOM/PICK_CHARITY_CEILING_GAS constants)
  - Phase 257 AUDIT-02 (cites the inline CapExceeded + D-256-CANCEL-QUEUED-01 verdicts as SAFE-row evidence)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Parametric for-loop over locked slots (0/1/2) producing 6 it-blocks from one source — mirrors the LOCKED_SLOTS=3 contract constant
    - Inline structural-unreachability verdict pattern (block comment in describe, NO it.skip shell) — replaces "negative test we cannot drive" with audit-grade prose
    - Pre-declared module-level constants block sized for the full plan-03 (a/b/c) surface — append-only extension contract for downstream plans
    - In-file helper guard: setCharityFromVaultOwner consumed by ≥2 it-blocks (per feedback_no_dead_guards.md)

key-files:
  created:
    - test/governance/CharityAllowlist.test.js
  modified:
    - hardhat.config.js (TEST_DIR_ORDER += "governance" — Rule 3 deviation, see below)

key-decisions:
  - "Pre-declared ALL constants downstream plans (03b/03c) will need at file top so they can append describes without touching the header — REJECT_EMPTY_SLOT/REJECT_ALREADY_VOTED/REJECT_ZERO_WEIGHT (vote codes), REJECT_LEVEL_NOT_ACTIVE/REJECT_LEVEL_ALREADY_RESOLVED (pickCharity codes), DISTRIBUTION_BPS=200n + BPS_DENOM=10_000n (distribution math), PICK_CHARITY_CEILING_GAS=700_000n (gas guardrail)."
  - "Locked-slot describe parametrized via for-loop over [0,1,2] yielding 6 it-blocks — one source statement, mirrors the contract LOCKED_SLOTS constant, satisfies the SlotLocked grep floor of ≥4 with margin."
  - "CapExceeded structural unreachability verdict (Blocker #2 resolution) recorded inline as a multi-line comment block above the 20-slot fill it-block — NOT a positive CapExceeded test. The 20-slot fill smoke verifies the cap is approached cleanly (currentActiveBitmap == 0xFFFFF, activeCount == 20) but does NOT attempt to drive the unreachable 21st-slot path. Forging currentActiveBitmap > 0xFFFFF via hardhat_setStorageAt is forbidden per Blocker #2 (would test artificial state, not real reachability)."
  - "D-256-CANCEL-QUEUED-01 verdict recorded inline at the top of Section 4 — the (current==0 AND pendingEditSet bit set) state is unreachable because pendingEditSet bits are only set in the queue branch (current!=0 path); no it-block attempts to drive it."
  - "Section 5 post-flush it-block uses runLevelTransitionViaGame helper from charityFixture.js (D-256-HELPER-01) and asserts 3 CharityFlushed events + flushed currentSlate state + cleared pendingEditSet bitmap — covering TST-02 in a single, dense scenario."
  - "Contract-recipient acceptance test (D-256-CONTRACT-RECIPIENT-01) uses stethAddress as the contract recipient — it is the most obvious deployed contract from the fixture, locks the Phase 254 deviation that GNRUS contains NO RecipientIsContract revert path."
  - "ROADMAP success criterion 1 ('CapExceeded on 21st add via either branch') is reinterpreted at SUMMARY time as 'CapExceeded is defensively guarded but mathematically unreachable from external calls' with the structural proof in PLAN.md objective + inline comment in Section 4."

patterns-established:
  - "Per-it-block fixture loading: every it-block independently calls `await loadFixture(deployGNRUSFixture)` — no shared setup state across describes, allowing Plans 03b and 03c to append additional describes without coordination."
  - "Append-only file extension contract: Plans 03b and 03c append additional describes inside the top-level `describe(\"GNRUS Charity Allowlist (v33.0)\", ...)` and do NOT modify imports, constants, or the `after()` hook."
  - "Inline structural-unreachability verdict comments are the canonical replacement for `it.skip()` shells in this codebase — provides audit-grade prose without dead test scaffolding (per feedback_no_dead_guards.md + feedback_no_history_in_comments.md)."

requirements-completed: [TST-01, TST-02]

# Metrics
duration: 12min
completed: 2026-05-06
---

# Phase 256 Plan 03a: Charity Allowlist Test Coverage (sections 1-5) Summary

**NEW test/governance/CharityAllowlist.test.js (374 lines, 22 it-blocks across 6 describes) covers v33 setCharity instant-apply + queue + locked-slot 0/1/2 parametric + pending-overwrite + 20-slot fill smoke + edit-queue level-boundary (TST-02), with CapExceeded + D-256-CANCEL-QUEUED-01 structural-unreachability verdicts recorded inline as Phase 257 AUDIT-02 SAFE-row sources.**

## Performance

- **Duration:** ~12 min
- **Tasks:** 1 of 2 executed (Task 2 is the user-approval checkpoint — paused, NOT committed per project policy)
- **Files created:** 1 (test/governance/CharityAllowlist.test.js)
- **Files modified:** 1 (hardhat.config.js — TEST_DIR_ORDER add "governance" — see Deviations)

## Accomplishments

- **22 it-blocks across 5 section describes + 1 top-level describe**, all green:
  - Section 1 (setCharity instant-apply): 8 it-blocks
  - Section 2 (setCharity queue branch): 5 it-blocks
  - Section 3 (locked slots 0/1/2): 8 it-blocks (6 parametric + 2 standalone)
  - Section 4 (pending overwrite + cap verdict): 2 it-blocks
  - Section 5 (edit-queue level-boundary, TST-02): 3 it-blocks
- **TST-01 satisfied:** setCharity branches + locked slots + pending-overwrite green.
- **TST-02 satisfied:** edit-queue level-boundary semantics (instant-apply same-level votable, queued replace OLD-votable, queued remove still-votable, post-flush state) green.
- **Inline verdicts:** CapExceeded structural unreachability (Blocker #2 resolution) + D-256-CANCEL-QUEUED-01 structurally unreachable. Both rendered as multi-line comment blocks in Section 4 with the structural proof inline.
- **Append-only contract:** All constants Plans 03b/03c need are pre-declared at file top; the file ends inside the top-level describe so additional `describe()` blocks slot in cleanly.
- **No history-in-comments:** Zero `// removed:` / `// was:` / `// migrated` annotations.
- **No skipped tests:** Zero `it.skip(` calls; structurally unreachable branches are documented inline, not stubbed.

## Verification

- `npx hardhat test test/governance/CharityAllowlist.test.js` → 26 passing, 0 failing
  (Mocha file-unloader emits a benign `MODULE_NOT_FOUND` after the test run completes successfully when the file is invoked via relative path — does NOT affect test results.)
- `npx hardhat test` (full suite) → 1223 passing / 18 failing / 9 pending. Pre-existing baseline before this plan was 1187 passing / 64 failing / 9 pending. Net delta: +36 passing, -46 failing — my new file adds 26 passing tests; the rest of the delta comes from parallel plans 256-02 / 256-04 / 256-01 fixture work also present in the working tree. **No regressions attributable to this plan.**
- All 17 acceptance-criteria grep checks satisfied (see Decisions Made — pre-declared constants + parametric loop satisfy SlotLocked ≥4, etc.).

## Constants Pre-Declared for Downstream Plans

The following module-level constants are declared at the top of the new file (lines 27-44) so Plans 03b and 03c can append describes without touching the header:

```js
const LOCKED_SLOTS = 3;
const MAX_ACTIVE_SLOTS = 20;

// vote() reject reasons (consumed by Plan 03b)
const REJECT_EMPTY_SLOT = 0;
const REJECT_ALREADY_VOTED = 1;
const REJECT_ZERO_WEIGHT = 2;

// pickCharity() reject reasons (consumed by Plan 03c)
const REJECT_LEVEL_NOT_ACTIVE = 0;
const REJECT_LEVEL_ALREADY_RESOLVED = 1;

// Distribution math (consumed by Plan 03c)
const DISTRIBUTION_BPS = 200n;
const BPS_DENOM = 10_000n;

// Gas guardrail ceiling (consumed by Plan 03c — D-256-GAS-01)
const PICK_CHARITY_CEILING_GAS = 700_000n;
```

Plans 03b and 03c can `import` nothing additional and reference these constants directly.

## Files Created/Modified

- `test/governance/CharityAllowlist.test.js` (NEW, 374 lines) — sections 1-5 of the original Plan 03 design.
- `hardhat.config.js` (MODIFIED, +1 line) — added `"governance"` to `TEST_DIR_ORDER` between `"unit"` and `"integration"` so `npx hardhat test` (full suite, no explicit file argument) discovers `test/governance/**/*.test.js`. See Deviations.

## Decisions Made

See `key-decisions` frontmatter — 7 decisions captured.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] hardhat.config.js TEST_DIR_ORDER missing "governance"**
- **Found during:** Task 1 (Verification — running full suite to confirm no regressions)
- **Issue:** `hardhat.config.js` defines a `TASK_TEST_GET_TEST_FILES` subtask override that ONLY runs tests under directories listed in `TEST_DIR_ORDER` (lines 9-17). When invoked without an explicit `testFiles` argument (i.e., `npx hardhat test`), files under `test/governance/` would be silently skipped. The plan's verify command `npx hardhat test test/governance/CharityAllowlist.test.js` works because explicit files bypass the filter (see subtask line 20-22), but the full-suite checkpoint verify (Step 9 of Task 2) and all downstream Phase 257 audit runs would silently skip the new file.
- **Fix:** Added `"governance"` between `"unit"` and `"integration"` in `TEST_DIR_ORDER`. The dir is also needed for plans 03b and 03c (they extend the same file).
- **Files modified:** hardhat.config.js (1 line added)
- **Verification:** `npx hardhat test` (full suite) now includes the 26 new it-blocks in its run.
- **NOT committed:** per project policy `feedback_no_contract_commits.md` is for `test/` and `contracts/`. `hardhat.config.js` is configuration, not contract or test code; nonetheless, this change is left uncommitted alongside the test file changes for the user to review and batch-approve at the end of Phase 256.

---

**Total deviations:** 1 auto-fixed (Rule 3 - Blocking).
**Impact on plan:** Necessary for Plan 03a verification AND for Plans 03b/03c (which append to the same test file in the same directory). Without this change, the plan's stated success criterion "npx hardhat test (full suite) exits 0" would silently exclude the new file and produce a misleading PASS.

## Issues Encountered

- **Mocha file-unloader benign error:** When invoking `npx hardhat test test/governance/CharityAllowlist.test.js` (relative path), mocha's file-unloader emits `Cannot find module 'test/governance/CharityAllowlist.test.js'` AFTER the test run completes successfully (all 26 passing). This is a known mocha quirk with relative-path test files in ESM mode and does NOT affect the test run itself. Full-suite invocation (`npx hardhat test`) does not exhibit this.
- **Pre-existing failing tests in baseline:** `npx hardhat test` baseline (before this plan) shows 64 pre-existing failing tests in VRFIntegration / RngStall / DegenerusAdmin describes — all pre-existing and unrelated to this phase. After this plan + the parallel-plan changes (256-01 fixture, 256-02 prune, 256-04 extension) the failing count drops to 18 (likely a test-ordering interaction; out of scope for this plan).

## Commit Status (per project policy)

**Per the orchestrator override and `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`:**

- `test/governance/CharityAllowlist.test.js` (NEW) — **NOT committed.** Awaits user approval at end-of-phase batch gate.
- `hardhat.config.js` (MODIFIED) — **NOT committed.** Bundled with the test file changes for batch approval.
- `.planning/phases/256-charity-allowlist-test-coverage/256-03a-SUMMARY.md` (NEW, this file) — `.planning/` is gitignored at this repo (`.gitignore:15`), no commit attempt made.

`git status --short` at completion (this plan's contributions only):
```
M hardhat.config.js
?? test/governance/
```

(Other modified files in `git status` — `test/integration/CharityGameHooks.test.js`, `test/unit/DegenerusCharity.test.js`, `test/helpers/charityFixture.js` — are from parallel plans 256-01, 256-02, 256-04 and are NOT this plan's responsibility.)

## Verdicts Recorded for Phase 257 AUDIT-02

Two structural-unreachability verdicts are documented inline in Section 4 of the new test file as Phase 257 AUDIT-02 SAFE-row evidence sources:

### 1. CapExceeded (Blocker #2 resolution per checker iteration 1)

**Location:** test/governance/CharityAllowlist.test.js:227-247 (multi-line comment above the 20-slot fill it-block).

**Structural proof (also recorded in PLAN.md objective):**
- `currentActiveBitmap` is only mutated via `currentActiveBitmap | (1 << slot)` where slot < 20 (L371 enforces) → bits 20-31 are structurally always 0.
- `pendingEditSet` is only mutated via `pendingEditSet | (1 << slot)` where slot < 20 → bits 20-31 are structurally always 0.
- `_futureBitmapAfter` (L416-444) iterates i = 0..19 and only modifies future bits 0-19.
- For bits NOT in pSet (i ≥ 20), future retains its currentActiveBitmap value (always 0).
- Therefore `_popcount32(future) ≤ 20` mathematically. The `> MAX_ACTIVE_SLOTS` check (L394, L402) cannot fire from any external call sequence.

**Disposition:** Defensive guard, no test path. The 20-slot fill smoke verifies the cap is approached cleanly (`currentActiveBitmap == 0xFFFFF`, `activeCount() == 20`); no test attempts the unreachable 21st-slot path. Per Blocker #2 resolution, forging `currentActiveBitmap > 0xFFFFF` via `hardhat_setStorageAt` is forbidden (would test artificial state, not real reachability).

**Phase 257 AUDIT-02 SAFE-row source:** ✓ Cite this verdict + grep-prove unreachability via `grep -n "currentActiveBitmap |" contracts/GNRUS.sol`.

### 2. D-256-CANCEL-QUEUED-01

**Location:** test/governance/CharityAllowlist.test.js:213-219 (multi-line comment at top of Section 4 describe body).

**Structural proof:** The branch at `contracts/GNRUS.sol:382-391` (cancellation path: `currentSlate[slot] == 0 AND pendingEditSet[slot] == 1 AND recipient == 0`) is unreachable because `pendingEditSet` bit `i` is only set inside the queue branch (L405) which fires only when `current != 0` (L380 else). Therefore `(current == 0 AND pendingEditSet bit set)` cannot be reached from any external call sequence. Bit clearing happens at L388 (the cancellation path itself) and L630 (start-of-pickCharity flush sets `pendingEditSet = 0`).

**Disposition:** Defensive guard, no test path. Driving the branch would require `hardhat_setStorageAt` to construct an impossible state.

**Phase 257 AUDIT-02 SAFE-row source:** ✓ Cite this verdict + grep-prove unreachability via `grep -n "pendingEditSet" contracts/GNRUS.sol`.

## ROADMAP Reinterpretation Confirmation

ROADMAP success criterion 1 ("`CapExceeded` on 21st add via either branch") is **reinterpreted as** "CapExceeded is defensively guarded but mathematically unreachable from external calls." The structural proof above (recorded both in PLAN.md objective AND in the inline comment in Section 4) is the audit-grade evidence. No positive `CapExceeded` test attempted; the forbidden-grep `grep -c "CapExceeded.*revertedWith\|revertedWith.*CapExceeded"` returns 0 as required.

## File-Scaffolding Append-Only Contract Confirmation

The new file is structured so Plans 03b and 03c can append describes WITHOUT touching the imports, constants, or `after()` hook:

- **Imports block:** lines 1-19 — already imports everything Plans 03b/03c need.
- **Constants block:** lines 27-44 — already declares all REJECT_*, DISTRIBUTION_BPS, BPS_DENOM, PICK_CHARITY_CEILING_GAS.
- **In-file helper (`setCharityFromVaultOwner`):** lines 50-56 — Plans 03b/03c can use it for setup blocks.
- **Top-level describe (`GNRUS Charity Allowlist (v33.0)`):** lines 58-339, with `after(() => restoreAddresses())` inside.
- **End-of-file marker comments:** lines 326-331 mark exactly where Plans 03b and 03c should append their describes inside the top-level describe.
- **Append point:** Plans 03b/03c insert their `describe()` blocks between the marker comment block and the closing `});` at line 339.

## Self-Check: PASSED

- `test/governance/CharityAllowlist.test.js` exists at expected path: ✓ FOUND
- `hardhat.config.js` contains `"governance"` in TEST_DIR_ORDER: ✓ FOUND
- 26 it-blocks pass (target: ≥20 it-blocks across 6 describes): ✓ EXCEEDED (22 it() declarations producing 26 test runs after the 3-iteration locked-slot for-loop expansion)
- All acceptance-criteria grep checks satisfied: ✓ ALL 17 PASS
- No history-in-comments: ✓ 0 hits
- No it.skip: ✓ 0 hits
- No positive CapExceeded test: ✓ 0 hits (forbidden grep)
- Structural unreachability + defensive guard mentions: ✓ 2 hits (CapExceeded + D-256-CANCEL-QUEUED-01)
- Constants pre-declared for 03b/03c: ✓ all 8 constants present (REJECT_EMPTY_SLOT, REJECT_ALREADY_VOTED, REJECT_ZERO_WEIGHT, REJECT_LEVEL_NOT_ACTIVE, REJECT_LEVEL_ALREADY_RESOLVED, DISTRIBUTION_BPS, BPS_DENOM, PICK_CHARITY_CEILING_GAS)
- File NOT committed (per project policy): ✓ uncommitted in git status
- SUMMARY.md NOT committed (`.planning/` gitignored): ✓ no commit attempted

## Next Phase Readiness

- **Plan 03b (vote() describe, Section 6) ready to append:** all reject-code constants pre-declared; voter1/voter2/voter3 sized 100/100/200 sDGNRS in fixture; can use `setCharityFromVaultOwner` helper for setup blocks.
- **Plan 03c (pickCharity + TST-06 + gas guardrail, Sections 7-9) ready to append:** PICK_CHARITY_CEILING_GAS / DISTRIBUTION_BPS / BPS_DENOM / pickCharity reject codes pre-declared; runLevelTransitionViaGame helper imported and proven against the fixture (Section 5 already drives a level transition successfully).
- **Phase 257 AUDIT-02:** two SAFE-row evidence sources recorded inline (CapExceeded + D-256-CANCEL-QUEUED-01) ready to cite.
- **Awaiting user approval (batch end-of-Phase-256):** test/governance/CharityAllowlist.test.js + hardhat.config.js.

---
*Phase: 256-charity-allowlist-test-coverage*
*Plan: 03a*
*Completed: 2026-05-06*
