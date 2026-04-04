# Phase 136: Test Hygiene - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Commit all pending test updates and verify both test suites (Hardhat + Foundry) pass with zero failures. Requirements: TEST-01, TEST-02, TEST-03.

</domain>

<decisions>
## Implementation Decisions

### Test Files to Commit
- **D-01:** Commit modified tests: `test/deploy/DeployScript.test.js`, `test/unit/DGNRSLiquid.test.js`, `test/unit/DegenerusDeityPass.test.js`
- **D-02:** Commit new untracked Foundry fuzz tests: `test/fuzz/LootboxBoonCoexistence.t.sol`, `test/fuzz/SimAdvanceOverflow.t.sol`
- **D-03:** `test/edge/MultiBoon.test.js` already tracked — verify it's committed

### Test Execution
- **D-04:** Run full Hardhat suite: `npx hardhat test`
- **D-05:** Run full Foundry suite: `forge test`
- **D-06:** Both suites must pass with zero failures before phase is complete

### Claude's Discretion
- Commit grouping (single commit or split by test type)
- Whether to run suites before or after committing (running before ensures we don't commit broken tests)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Test Files (modified)
- `test/deploy/DeployScript.test.js` — Deploy script test updates
- `test/unit/DGNRSLiquid.test.js` — DGNRS naming test updates
- `test/unit/DegenerusDeityPass.test.js` — DeityPass ownership model test updates

### Test Files (new/untracked)
- `test/fuzz/LootboxBoonCoexistence.t.sol` — Foundry fuzz: lootbox boon coexistence
- `test/fuzz/SimAdvanceOverflow.t.sol` — Foundry fuzz: sim advance overflow

### Test Files (already tracked)
- `test/edge/MultiBoon.test.js` — Multi-boon coexistence edge case tests

### Requirements
- `.planning/REQUIREMENTS.md` — TEST-01 through TEST-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Test Infrastructure
- Hardhat test suite in `test/` with `.test.js` extension
- Foundry fuzz/invariant tests in `test/fuzz/` with `.t.sol` extension
- Both runners configured and working from prior milestones

### Integration Points
- ContractAddresses.sol has unstaged changes (different deploy addresses) — must NOT be committed (user manages this file)
- Test files reference deployed contract addresses via ContractAddresses library

</code_context>

<specifics>
## Specific Ideas

No specific requirements — this is a mechanical commit-and-verify phase.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 136-test-hygiene*
*Context gathered: 2026-03-28*
