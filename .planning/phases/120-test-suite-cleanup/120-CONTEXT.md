# Phase 120: Test Suite Cleanup - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix all 14 failing Foundry tests and establish a green baseline for both test suites (Foundry + Hardhat) before any contract changes in subsequent phases. Generate LCOV coverage reports documenting per-contract line coverage for safe pruning in Phase 125.

</domain>

<decisions>
## Implementation Decisions

### Fix vs delete policy
- **D-01:** Fix tests that cover unique code paths. Delete only if the test targets a feature/pattern that was intentionally removed or fundamentally changed.
- **D-02:** For each deletion, document what the test covered and why deletion is justified (e.g., "tests removed `lastLootboxRngWord` behavior that Phase 121 will deprecate").
- **D-03:** Never delete a test whose filename references an audit finding ID without confirming the finding is resolved.

### Failing test disposition
- **D-04:** The 6 "already fulfilled" VRF mock tests (LootboxRngLifecycle x4, VRFCore x2) are test setup issues — the VRF mock coordinator thinks a request was already fulfilled. Fix the mock setup, not the contracts.
- **D-05:** The 3 VRFStallEdgeCases tests reference `lastLootboxRngWord` and `midDayTicketRngPending` state — these reflect contract changes from v3.6-v3.8. Fix the test assertions to match current contract behavior.
- **D-06:** The 1 FuturepoolSkim `test_pipeline_varianceBeforeCap` has an 80% cap precision issue (79.93% vs 80.00%) — fix the assertion tolerance or the test math.
- **D-07:** The 1 VRFLifecycle `test_vrfLifecycle_levelAdvancement` fails to advance past level 0 — likely a test setup issue with insufficient game state. Fix the setup.
- **D-08:** The 3 TicketLifecycle queue drain tests (testFiveLevelIntegration, testMultiLevelZeroStranding, testZeroStrandingSweepAfterTransitions) all fail with "read queue not drained" — investigate root cause and fix. These are test-side or contract-behavior issues from the far-future ticket changes.

### Hardhat baseline
- **D-09:** Run `npx hardhat test` and fix any failures found. TEST-03 requires 100% pass rate.
- **D-10:** Known pre-existing Hardhat failures (if any) must be documented — zero tolerance for silent known-failures.

### LCOV coverage methodology
- **D-11:** Generate per-suite LCOV reports: `forge coverage --report lcov` for Foundry, `npx hardhat coverage` for Hardhat.
- **D-12:** Document per-contract line coverage percentages from both suites. This feeds Phase 125 redundancy analysis.

### Claude's Discretion
- Exact fix approach for each failing test (mock setup changes, assertion tolerance, state initialization)
- Whether to use `forge test --rerun` during development or run full suite
- LCOV report format and storage location

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Failing test files
- `test/fuzz/LootboxRngLifecycle.t.sol` — 4 "already fulfilled" failures
- `test/fuzz/VRFCore.t.sol` — 2 failures (1 "already fulfilled", 1 stale word)
- `test/fuzz/VRFStallEdgeCases.t.sol` — 3 failures (lastLootboxRngWord, midDayPending)
- `test/fuzz/VRFLifecycle.t.sol` — 1 failure (level advancement)
- `test/fuzz/FuturepoolSkim.t.sol` — 1 failure (80% cap precision)
- `test/fuzz/TicketLifecycle.t.sol` — 3 failures (queue drain)

### Test infrastructure
- `test/fuzz/helpers/DeployProtocol.sol` — Foundry 23-contract deploy base
- `test/helpers/deployFixture.js` — Hardhat deploy fixture

### Contracts referenced by failing tests
- `contracts/modules/DegenerusGameAdvanceModule.sol` — VRF fulfillment, lastLootboxRngWord writes
- `contracts/modules/DegenerusGameJackpotModule.sol` — lootbox RNG consumer
- `contracts/storage/DegenerusGameStorage.sol` — storage layout (lastLootboxRngWord declaration)

### Prior audit context
- `.planning/research/SUMMARY.md` — Research findings on test failure root causes
- `audit/FINDINGS.md` — v5.0 master findings (I-01 through I-04)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `test/fuzz/helpers/DeployProtocol.sol` — Full 23-contract protocol deploy for Foundry tests
- `test/helpers/deployFixture.js` — Hardhat fixture with full protocol deploy
- VRF mock coordinator in test helpers — used by all VRF-related tests

### Established Patterns
- Foundry tests use `DeployProtocol` base contract with `setUp()` deploying full protocol
- Hardhat tests use `loadFixture(deployFixture)` pattern
- VRF tests mock `rawFulfillRandomWords` via direct coordinator calls
- Fuzz tests use `vm.assume()` for input bounds

### Integration Points
- All 14 failing tests are in `test/fuzz/` directory
- Hardhat tests are in `test/` subdirectories (unit, edge, integration, etc.)
- 29 Foundry test files, ~44 Hardhat test files

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard test fix and baseline establishment approach.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 120-test-suite-cleanup*
*Context gathered: 2026-03-25*
