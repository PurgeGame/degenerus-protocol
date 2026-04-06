# Phase 193: Gas Ceiling & Test Regression - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify the new jackpot code paths (from commits 93c05869 and 520249a2) do not push advanceGame beyond safe gas limits, and confirm both test suites have zero new regressions vs the v22.0 baseline. Audit-only — no code changes.

</domain>

<decisions>
## Implementation Decisions

### Gas Analysis
- **D-01:** Measure worst-case advanceGame gas consumption with all new jackpot paths active (specialized events, whale pass daily path, DGNRS fold)
- **D-02:** Safety margin threshold is ≥1.5x against the 30M block gas limit (i.e., worst-case must be ≤20M gas)
- **D-03:** Follow established gas ceiling methodology from v15.0 Phase 167 — forge test gas reporting on advanceGame worst-case scenario

### Test Regression
- **D-04:** Foundry baseline from v22.0: 150 passing / 28 pre-existing failures — zero new failures required
- **D-05:** Hardhat baseline from v22.0: 1225 passing / 19 failing / 3 pending — zero new failures required
- **D-06:** Any new failures must be investigated and attributed to specific code changes

### Claude's Discretion
- Report structure and formatting
- Order of test suite execution
- Level of detail in gas breakdown documentation
- Whether to include per-function gas breakdown or just advanceGame total

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gas Target
- `contracts/modules/DegenerusGameAdvanceModule.sol` — Contains advanceGame entry point, calls into JackpotModule
- `contracts/modules/DegenerusGameJackpotModule.sol` — New jackpot paths (specialized events, whale pass daily, DGNRS fold)

### Prior Gas Analysis
- `.planning/PROJECT.md` §v15.0 — Prior gas ceiling result: advanceGame 7,023,530 gas, 1.99x margin

### Phase 192 Delta Reference
- `.planning/phases/192-delta-extraction-behavioral-verification/192-01-AUDIT.md` — Function-level changelog of all changes
- `.planning/phases/192-delta-extraction-behavioral-verification/192-02-AUDIT.md` — Intentional change correctness proofs

### Test Suites
- `test/` — Hardhat test suite
- `test/fuzz/` — Foundry fuzz test suite

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `forge test --gas-report` — Standard Foundry gas reporting
- Prior milestone gas analysis methodology (static call-tree analysis + forge gas measurement)

### Established Patterns
- Test baselines documented as "X passing / Y failing" with attribution of pre-existing failures
- Gas ceiling expressed as absolute value + safety margin multiplier against 30M limit
- All prior delta audits (v15.0-v22.0) include test regression verification

### Integration Points
- advanceGame → _consolidatePoolsAndRewardJackpots → runBafJackpot (new jackpot paths)
- JackpotModule specialized events emitted within jackpot reward paths

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow established gas ceiling and test regression methodology from prior milestones.

</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope.

</deferred>

---

*Phase: 193-gas-ceiling-test-regression*
*Context gathered: 2026-04-06*
