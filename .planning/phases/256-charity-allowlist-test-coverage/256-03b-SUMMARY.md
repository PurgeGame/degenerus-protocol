---
phase: 256-charity-allowlist-test-coverage
plan: 03b
subsystem: charity-allowlist
tags: [test, governance, vote, tdd, audit-prep]
requires: [256-01, 256-03a]
provides: [TST-03]
affects: [test/governance/CharityAllowlist.test.js]
tech_stack:
  added: []
  patterns:
    - "Custom-error revert assertions WITH .withArgs(reasonCode) (multi-line chain)"
    - "fixture-as-state pattern (loadFixture per it-block)"
    - "Fresh-signer funding via giveSDGNRS for sub-1e18 zero-weight path"
key_files:
  created: []
  modified:
    - test/governance/CharityAllowlist.test.js
decisions:
  - "Plan 03b appended Section 6 between Plan 03a's Section 5 closing }); and the top-level describe's closing }); (pure append)"
  - "Pre-declared REJECT_EMPTY_SLOT / REJECT_ALREADY_VOTED / REJECT_ZERO_WEIGHT constants from 03a reused; NOT redeclared"
  - "Locked-slot vote positive case (D-256-LOCKED-SLOT-01) kept ONLY in Section 3; not duplicated in Section 6 to avoid coverage redundancy"
  - "InvalidSlot tested at both slot=20 (boundary) and slot=255 (uint8 max) for two-point coverage"
  - "Revert-order verification (InvalidSlot before EMPTY_SLOT) lives in its own dedicated it-block to lock the L560-563 ordering for future refactors"
metrics:
  duration_minutes: ~10
  tasks_completed: 1
  files_modified: 1
  it_blocks_added: 9
  cumulative_line_count: 511
  completed_date: 2026-05-06
---

# Phase 256 Plan 03b: vote(uint8 slot) test describe (Section 6) Summary

Appended Section 6 (`describe("vote(uint8 slot)")`) to `test/governance/CharityAllowlist.test.js`, satisfying TST-03 with 9 new it-blocks covering all four reject paths via reason-code asserts, multi-slot independence (D-256-MULTI-VOTE-01), per-(level, voter, slot) hasVoted state, and the InvalidSlot-before-EMPTY_SLOT revert order.

## Key Achievements

- **All 4 vote sad paths covered with reason-code asserts:**
  - `InvalidSlot` (slot >= 20) — tested at slot=20 (boundary) and slot=255 (uint8 max).
  - `VoteRejected(REJECT_EMPTY_SLOT)` via never-filled slot 7.
  - `VoteRejected(REJECT_ALREADY_VOTED)` via second vote on same (level, voter, slot).
  - `VoteRejected(REJECT_ZERO_WEIGHT)` via sub-1e18 sDGNRS balance — explicitly exercises the `weight = balanceOf / 1e18` integer-floor path at contracts/GNRUS.sol L572-573 (NOT a balance == 0 short-circuit).
- **Multi-slot vote independence (D-256-MULTI-VOTE-01):** voter1 (100 sDGNRS) votes slots 3, 5, 7 — each accumulates the FULL 100 weight. Sum across the three slots = 300 (proves the vote isn't divided per slot).
- **hasVoted state asserted per (level, voter, slot) tuple:** positive assertion + three orthogonal negative assertions (different slot, different voter, different level).
- **Revert order locked:** dedicated it-block proves InvalidSlot fires BEFORE EMPTY_SLOT at slot=20 on a pristine slate (both gates would semantically apply; only InvalidSlot is observable per L560-563).
- **All 35 tests pass** (`npx hardhat test test/governance/CharityAllowlist.test.js` exits 0): 26 from Plan 03a + 9 from this plan.

## Coverage Verification (TST-03)

| Reject Path                       | Test Case                                                         | Reason Code Source       |
| --------------------------------- | ----------------------------------------------------------------- | ------------------------ |
| `InvalidSlot` (slot >= 20)        | "InvalidSlot on slot == 20" + "InvalidSlot on slot == 255"        | contracts/GNRUS.sol L560 |
| `VoteRejected(REJECT_EMPTY_SLOT)` | "VoteRejected(REJECT_EMPTY_SLOT) on slot never filled"            | L563                     |
| `VoteRejected(REJECT_ALREADY_VOTED)` | "VoteRejected(REJECT_ALREADY_VOTED) on second vote..."         | L568                     |
| `VoteRejected(REJECT_ZERO_WEIGHT)` | "VoteRejected(REJECT_ZERO_WEIGHT) on sub-1e18 sDGNRS balance..." | L573                     |
| Revert order (InvalidSlot first)  | "vote revert order: InvalidSlot fires before EMPTY_SLOT..."       | L560-563                 |

## Plan 03a Preservation

Plan 03b modified ONLY the placeholder comment block at lines 369-374 of the post-03a file (the explicit "Plan 03b will append" stub). All Plan 03a content preserved verbatim:

- All imports, constants (LOCKED_SLOTS, MAX_ACTIVE_SLOTS, REJECT_*, DISTRIBUTION_BPS, BPS_DENOM, PICK_CHARITY_CEILING_GAS), helpers, and top-level describe — unchanged.
- All Sections 1-5 it-blocks — unchanged.
- D-256-CANCEL-QUEUED-01 structural-unreachability comment block (Section 4 header) — preserved.
- CapExceeded structural-unreachability verdict block (Section 4 mid-section) — preserved.
- After-hook (`restoreAddresses()`) — unchanged.
- Pre-declared REJECT_* constants reused directly; NOT redeclared in Section 6.

`grep -ic "structurally unreachable" test/governance/CharityAllowlist.test.js` returns 1, `grep -ic "defensive guard" test/governance/CharityAllowlist.test.js` returns 1 — verdict comments intact.

## Acceptance Criteria Audit

| Criterion                                                       | Required | Actual |
| --------------------------------------------------------------- | -------- | ------ |
| `npx hardhat test test/governance/CharityAllowlist.test.js`     | exit 0   | 35 passing (exit 0) |
| `describe(` literal opens (code only)                           | 7        | 7      |
| `it(` literal opens (code only)                                 | >= 28    | 31     |
| `withArgs(REJECT_EMPTY_SLOT)` reference                         | >= 1     | 1 (line 460) |
| `withArgs(REJECT_ALREADY_VOTED)` reference                      | >= 1     | 1 (line 471) |
| `withArgs(REJECT_ZERO_WEIGHT)` reference                        | >= 1     | 1 (line 491) |
| `InvalidSlot` references                                        | >= 2     | 13     |
| `hasVoted` references                                           | >= 2     | 7      |
| `describe("vote(uint8 slot)"` count                             | == 1     | 1      |
| `describe("setCharity` count                                    | >= 4     | 5      |
| History-in-comments forbidden tokens                            | == 0     | 0      |
| `it.skip(` count                                                | == 0     | 0      |
| File line count                                                 | >= 380   | 511    |
| CapExceeded structural unreachability comment preserved         | >= 1     | 1      |

Note: the plan's `withArgs` greps used a single-line regex; my Section 6 uses the multi-line chain style identical to Plan 03a's setCharity assertions (`.to.be.revertedWithCustomError(charity, "VoteRejected")` on one line, `.withArgs(REJECT_*)` on the next). All three reason-code asserts are present and verified by the code-only `grep -nE "withArgs\(REJECT_"` shown above.

## Confirmation: Pre-declared 03a Constants Reused (No Redeclaration)

Section 6 references `REJECT_EMPTY_SLOT` (line 460), `REJECT_ALREADY_VOTED` (line 471), and `REJECT_ZERO_WEIGHT` (line 491) directly from the module-level constants block at lines 31-33 of the file (declared by Plan 03a). No `const REJECT_*` declarations exist inside Section 6.

## Test Count Delta

- Pre-03b file count: 26 it-blocks (all from 03a).
- Post-03b file count: 35 it-blocks (26 + 9 new).
- Full-suite delta: 1223 passing (post-03a) -> 1232 passing (post-03b) = +9, exactly matching new it-blocks.

## Pre-Existing Failing Tests (Out of Scope)

Full-suite run shows 18 failing tests, all in `VRFIntegration` and `RngStall` describes — pre-existing baseline noted in Plan 03a's SUMMARY (`256-03a-SUMMARY.md` line 150). These are unrelated to the charity allowlist subsystem and out of scope for this plan per the SCOPE BOUNDARY rule. No regressions attributable to Plan 03b.

## Deviations from Plan

None — plan executed exactly as written. The locked-slot vote positive case mentioned in the plan's Section 6 spec was deliberately kept in Section 3 only (planner discretion noted in plan: "OR planner chooses to leave the locked-slot vote in 03a only and skips here") to avoid coverage duplication; this is in line with the plan's explicit acceptance criteria tolerance.

## Commit Status

**Per orchestrator override + `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`:** NO `test/` commits made by this executor. The `test/governance/CharityAllowlist.test.js` modification is left uncommitted in the working tree along with Plan 03a's untracked file. End-of-phase batch approval (single diff, single user approval) will land all `test/` changes in one commit.

`.planning/` is gitignored — this SUMMARY.md is also uncommitted; orchestrator will batch-commit `.planning/` files with `-f` at end of phase.

## Self-Check: PASSED

- `test/governance/CharityAllowlist.test.js` FOUND (511 lines, 35 it-blocks, 7 code-only describes).
- All 9 new it-blocks named in `<action>` are present in Section 6.
- Pre-declared 03a constants (REJECT_EMPTY_SLOT / REJECT_ALREADY_VOTED / REJECT_ZERO_WEIGHT) reused; NOT redeclared.
- Plan 03a's verdict comments (CapExceeded + D-256-CANCEL-QUEUED-01 structural unreachability) preserved unchanged.
- `npx hardhat test test/governance/CharityAllowlist.test.js` -> 35 passing.
- `npx hardhat test` (full suite) -> 1232 passing / 18 failing (all 18 pre-existing VRF/RngStall, identical failure list as 03a baseline) / 9 pending. Net +9 passing matches the 9 new it-blocks 1:1.
- No `test/` or `contracts/` commits made.
- No `.planning/` commits made.
