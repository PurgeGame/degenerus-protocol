# Phase 125: Test Suite Pruning - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 125-test-suite-pruning
**Areas discussed:** Pruning scope, Deletion criteria, Preservation rules

---

## Pruning Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-suite only | Only prune where Hardhat and Foundry test the exact same thing | |
| Cross-suite + poc/adversarial cleanup | Also consolidate poc/ tests which may overlap with adversarial/ and unit/ | |
| Full redundancy sweep | Cross-suite duplicates + within-suite overlaps + consolidate scattered categories | ✓ |

**User's choice:** Full redundancy sweep
**Notes:** Most aggressive option — all 90 test files are candidates

---

## Deletion Criteria

| Option | Description | Selected |
|--------|-------------|----------|
| Same coverage = delete one | If two tests hit same lines via LCOV, delete the less thorough one | ✓ |
| Merge unique assertions | Merge unique assertions from overlapping tests before deletion | |
| LCOV-only: zero lost lines | Purely mechanical — delete if LCOV doesn't drop, ignore assertion quality | |

**User's choice:** Same coverage = delete one
**Notes:** Simple rule, easy to justify. No assertion merging.

---

## Preservation Rules

| Option | Description | Selected |
|--------|-------------|----------|
| Deploy canary + simulations only | Always keep DeployCanary.t.sol and simulation tests | |
| Bug regression tests too | Also preserve tests written for past bugs | |
| You decide | Claude determines sacred tests based on audit | ✓ |

**User's choice:** You decide
**Notes:** No hard preservation rules — Claude's discretion

## Claude's Discretion

- Test organization and grouping after pruning
- Which test to keep when two overlap
- Whether to reorganize remaining tests
- LCOV tooling and comparison methodology
- Which tests are sacred (preservation judgment)

## Deferred Ideas

None
