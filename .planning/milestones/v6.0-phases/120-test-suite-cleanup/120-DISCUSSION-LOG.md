# Phase 120: Test Suite Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 120-test-suite-cleanup
**Areas discussed:** Fix vs delete policy, TicketLifecycle handling, Hardhat baseline, LCOV methodology
**Mode:** Auto (all decisions auto-selected with recommended defaults)

---

## Fix vs Delete Policy

| Option | Description | Selected |
|--------|-------------|----------|
| Fix if covers unique paths | Fix tests covering unique code, delete only if feature removed | ✓ |
| Fix all — never delete | Always fix, even if redundant | |
| Delete all failing | Remove all broken tests, rely on passing ones | |

**User's choice:** [auto] Fix if covers unique paths (recommended default)
**Notes:** Each deletion requires documented justification. Audit-finding-referenced tests get extra protection.

---

## TicketLifecycle Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Investigate and fix | These are test failures, include in the 14 count | ✓ |
| Leave as known-failing | Document as separate work, don't fix in this phase | |
| Delete | Remove the 3 tests entirely | |

**User's choice:** [auto] Investigate and fix in this phase (recommended default)
**Notes:** User's original scope included these in the total count. Root cause likely related to v3.9 far-future ticket changes.

---

## Hardhat Baseline

| Option | Description | Selected |
|--------|-------------|----------|
| Run and fix all failures | TEST-03 requires 100% pass rate | ✓ |
| Run but defer failures | Document failures, fix later | |
| Skip Hardhat for now | Focus only on Foundry | |

**User's choice:** [auto] Run and fix all failures (recommended default)
**Notes:** TEST-03 is a hard requirement — both suites must be green.

---

## LCOV Methodology

| Option | Description | Selected |
|--------|-------------|----------|
| Per-suite LCOV reports | Generate separate reports for Foundry and Hardhat | ✓ |
| Combined report only | Merge into single coverage view | |
| Skip LCOV for now | Defer coverage to Phase 125 | |

**User's choice:** [auto] Per-suite LCOV reports with summary comparison (recommended default)
**Notes:** Feeds Phase 125 redundancy analysis. Per-suite reports allow comparing what each suite covers independently.

---

## Claude's Discretion

- Exact fix approach for each failing test
- Development workflow (rerun vs full suite)
- LCOV storage location and format

## Deferred Ideas

None — discussion stayed within phase scope.
