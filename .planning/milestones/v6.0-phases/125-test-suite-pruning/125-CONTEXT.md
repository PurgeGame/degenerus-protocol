# Phase 125: Test Suite Pruning - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Identify and remove redundant test coverage across 47 Hardhat and 43 Foundry tests (90 total) without losing any unique line coverage. Full redundancy sweep: cross-suite duplicates, within-suite overlaps, and scattered test category consolidation.

</domain>

<decisions>
## Implementation Decisions

### Pruning Scope
- **D-01:** Full redundancy sweep — not just cross-suite (Hardhat vs Foundry) but also within-suite overlaps and consolidation of scattered test categories (poc/, adversarial/, edge/, unit/ may overlap).

### Deletion Criteria
- **D-02:** Same coverage = delete one. If two tests hit the same contract lines (verified via LCOV), delete the less thorough one. No merging of assertions between tests — keep the better test, delete the other.

### Preservation Rules
- **D-03:** Claude's discretion. No hard preservation rules. Claude determines what's sacred based on the redundancy audit (deploy canary, bug regression tests, simulations — whatever makes sense after seeing the coverage data).

### Claude's Discretion
- Test organization and grouping after pruning
- Which test to keep when two overlap (the "more thorough" judgment)
- Whether to reorganize remaining tests into fewer directories
- LCOV tooling and comparison methodology

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 120 Baseline
- `.planning/phases/120-test-suite-cleanup/120-01-PLAN.md` — How the green baseline was established (Foundry fixes)
- `.planning/phases/120-test-suite-cleanup/120-02-PLAN.md` — Hardhat green baseline + LCOV coverage methodology

### Requirements
- `.planning/REQUIREMENTS.md` — PRUNE-01 through PRUNE-04 definitions

### Test Suites
- `test/` — All 47 Hardhat test files across unit/, edge/, adversarial/, poc/, integration/, simulation/, validation/, gas/, deploy/, access/
- `test/fuzz/` — All 43 Foundry test files across fuzz/ and fuzz/invariant/

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 120 LCOV reports — methodology for generating per-contract line coverage already established
- `hardhat.config.js` — test ordering and mocha configuration
- `foundry.toml` — Foundry test configuration

### Established Patterns
- Hardhat tests use `deployFullProtocol` fixture for integration tests, individual contract deploys for unit tests
- Foundry tests use `DeployProtocol.sol` helper for full-protocol deployment
- Both suites have separate helpers directories (`test/helpers/`, `test/fuzz/helpers/`)

### Integration Points
- 29 contracts under `contracts/` — the coverage targets
- LCOV output from both `forge coverage` and `hardhat-coverage` (solidity-coverage plugin)

</code_context>

<specifics>
## Specific Ideas

- The poc/ directory (Phase 24-28 tests: FormalMethods, DependencyIntegration, GasGriefing, WhiteHat, GameTheory) was created during the v2.0 audit. These may significantly overlap with later adversarial/ and unit/ tests written in v3.x-v5.0 milestones.
- The adversarial/ directory has 3 large test files that may cover ground also covered by unit tests + Foundry invariant tests.
- Foundry invariant/ tests (12 files) are the highest-value tests — they fuzz-test invariants across many inputs. These are unlikely pruning candidates.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 125-test-suite-pruning*
*Context gathered: 2026-03-26*
