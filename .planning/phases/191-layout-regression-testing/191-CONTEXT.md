# Phase 191: Layout + Regression Testing - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Mechanical verification that commit `a2d1c585` (BAF simplification) did not alter storage layout or break existing tests. Three tool-based checks: `forge inspect` storage slot comparison, Foundry test suite, Hardhat test suite. No code changes expected — audit-only output.

</domain>

<decisions>
## Implementation Decisions

### Storage Layout Verification (LAYOUT-01)
- **D-01:** Run `forge inspect` on all 6 changed contracts (DegenerusGame, DegenerusGameAdvanceModule, DegenerusGameJackpotModule, DegenerusGameDecimatorModule, DegenerusGamePayoutUtils, and their interfaces) and compare slot assignments to pre-commit baseline
- **D-02:** Pre-commit baseline obtained by checking out the parent commit (`a2d1c585^`) and running `forge inspect` there, then diffing against current HEAD

### Foundry Test Suite (TEST-01)
- **D-03:** Run `forge test` and compare failures against the known pre-existing baseline from Phase 189 (150 pass / 28 pre-existing failures as of v21.0)
- **D-04:** Any NEW failure beyond the pre-existing baseline is a regression finding

### Hardhat Test Suite (TEST-02)
- **D-05:** Run `npx hardhat test` and compare against the known pre-existing baseline from Phase 189 (1231 pass / 13 pre-existing failures as of v21.0)
- **D-06:** Any NEW failure beyond the pre-existing baseline is a regression finding

### Claude's Discretion
- Output document structure and formatting
- Whether to include full forge inspect output or just the diff
- Level of detail in test failure analysis if regressions found

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Changed contracts (from commit a2d1c585)
- `contracts/DegenerusGame.sol` — runBafJackpot proxy signature change
- `contracts/modules/DegenerusGameAdvanceModule.sol` — caller-side BAF simplification
- `contracts/modules/DegenerusGameJackpotModule.sol` — runBafJackpot return value change
- `contracts/interfaces/IDegenerusGame.sol` — interface signature change
- `contracts/interfaces/IDegenerusGameModules.sol` — interface signature change

### Prior phase verification
- `.planning/phases/190-eth-flow-rebuy-delta-event-audit/190-VERIFICATION.md` — Phase 190 behavioral equivalence confirmed

### Requirements
- `.planning/REQUIREMENTS.md` — LAYOUT-01, TEST-01, TEST-02

</canonical_refs>

<code_context>
## Existing Code Insights

### Test Baselines
- Foundry: 150 pass / 28 pre-existing failures (v21.0 baseline from Phase 189)
- Hardhat: 1231 pass / 13 pre-existing failures (v21.0 baseline from Phase 189)
- Note: These baselines may have shifted slightly with recent commits — capture fresh baseline before comparison

### forge inspect Pattern
- Prior phases (v16.0, v18.0, v20.0, v21.0) all used `forge inspect --pretty` with diff comparison
- Standard approach: `forge inspect ContractName storage-layout --pretty`

### Integration Points
- Test files are in `test/` (Hardhat) and `test/foundry/` (Foundry)
- Forge config in `foundry.toml`

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard mechanical verification.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 191-layout-regression-testing*
*Context gathered: 2026-04-05*
