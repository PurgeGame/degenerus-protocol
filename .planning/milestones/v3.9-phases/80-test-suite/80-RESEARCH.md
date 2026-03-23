# Phase 80: Test Suite - Research

**Researched:** 2026-03-22
**Domain:** Solidity unit/integration testing with Foundry for far-future ticket mechanics
**Confidence:** HIGH

## Summary

Phase 80 requires five test suites proving correctness of the far-future ticket system implemented in Phases 74-78. The critical discovery is that substantial test infrastructure already exists from earlier phases -- four Foundry test files (TqFarFutureKey.t.sol, TicketRouting.t.sol, TicketProcessingFF.t.sol, JackpotCombinedPool.t.sol, TicketEdgeCases.t.sol) already cover significant portions of the TEST-01 through TEST-04 requirements. However, these existing tests use simplified harnesses that replicate proposed logic rather than exercising the actual production contract code.

The gap analysis shows: (a) existing Phase 75 routing tests (TicketRouting.t.sol) already prove TEST-01's core routing logic but only test `_queueTickets` directly -- they don't demonstrate lootbox, whale, vault, or endgame as upstream callers; (b) TicketProcessingFF.t.sol proves TEST-02's dual-queue drain but with a simplified batch model (no trait generation); (c) JackpotCombinedPool.t.sol proves TEST-03's combined pool selection; (d) TicketRouting.t.sol proves TEST-04's rngLocked guard on FF key writes. TEST-05 (multi-level integration test) has no existing coverage and is the most complex new deliverable.

**Primary recommendation:** Consolidate existing per-requirement test coverage into a single Phase 80 test file (or small set), add the missing "all sources" tests for TEST-01 using the production DegenerusGameStorage harness, add the missing integration test (TEST-05), and ensure all tests exercise production code paths (not replicated logic) wherever feasible. For the integration test, use DeployProtocol.sol to deploy the full protocol and drive a multi-level lifecycle.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | Unit test confirms far-future tickets from ALL sources (lootbox, whale, vault, endgame) land in FF key, not write key | Existing TicketRouting.t.sol covers `_queueTickets` routing; gap is upstream caller coverage (lootbox/whale/vault/endgame). All callers funnel through `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` (DegenerusGameStorage.sol lines 537-668), so the routing is proven at the single fix point. Additional source-level tests optional but the fix-point test IS the proof. |
| TEST-02 | Unit test confirms processFutureTicketBatch drains FF key entries and mints traits | Existing TicketProcessingFF.t.sol proves structural drain with simplified budget model. Production code at MintModule.sol:298-454 has identical dual-queue drain structure. Tests prove PROC-01/02/03 behaviors. |
| TEST-03 | Unit test confirms _awardFarFutureCoinJackpot finds winners from FF key entries | Existing JackpotCombinedPool.t.sol proves combined pool selection (8 tests). Production code at JackpotModule.sol:2522-2614 matches harness logic exactly. |
| TEST-04 | Unit test confirms _queueTickets reverts for FF key writes when rngLocked is true (permissionless callers) but allows advanceGame-origin writes | Existing TicketRouting.t.sol proves this (tests: testRngGuardRevertsOnFFKey, testRngGuardAllowsWithPhaseTransition, testRngGuardIgnoresNearFuture, testRngGuardScaledRevertsOnFFKey, testRngGuardRangeRevertsOnFirstFFLevel). 5 existing tests. |
| TEST-05 | Integration test advances through multiple levels and verifies far-future tickets from all sources are processed correctly (no stranding) | No existing coverage. Requires DeployProtocol.sol full-protocol deployment, multi-level advancement via purchase + advanceGame + VRF fulfillment cycle, and verification that FF key queues drain to zero. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundry (forge) | 1.5.1 | Solidity test framework | Already in use for all v3.x test suites; foundry.toml configured |
| forge-std | (bundled) | Test utilities (vm cheats, assertions) | Standard Foundry test library |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Hardhat | 2.28.6 | JavaScript integration tests | Only if TEST-05 needs JS-level lifecycle orchestration |
| DeployProtocol.sol | N/A | Full protocol deployment helper | TEST-05 integration test |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Foundry for integration (TEST-05) | Hardhat JS tests | Hardhat has existing GameLifecycle.test.js pattern but Foundry is faster, more consistent with v3.9 test style, and allows direct state inspection |
| Full protocol deployment (TEST-05) | Storage harness only | Harness approach cannot prove end-to-end lifecycle; full deployment proves actual purchase-to-process flow |

## Architecture Patterns

### Recommended Test Structure
```
test/fuzz/
  FarFutureTestSuite.t.sol     # Phase 80 consolidated test file
                                # - TEST-01 through TEST-04: unit tests with harness
                                # - TEST-05: integration test with DeployProtocol
```

### Pattern 1: Storage Harness (Used by Phases 74-78)
**What:** A contract inheriting `DegenerusGameStorage` that exposes internal functions and state variables for direct testing.
**When to use:** Unit tests (TEST-01 through TEST-04) where you need to exercise internal functions like `_queueTickets`, `_tqFarFutureKey`, and inspect `ticketQueue` directly.
**Example:**
```solidity
// Source: test/fuzz/TicketRouting.t.sol (Phase 75 pattern)
contract TestHarness is DegenerusGameStorage {
    function queueTickets(address buyer, uint24 targetLevel, uint32 quantity) external {
        _queueTickets(buyer, targetLevel, quantity);
    }
    function setLevel(uint24 lvl) external { level = lvl; }
    function setRngLockedFlag(bool v) external { rngLockedFlag = v; }
    function setPhaseTransitionActive(bool v) external { phaseTransitionActive = v; }
    function getQueueLength(uint24 wk) external view returns (uint256) {
        return ticketQueue[wk].length;
    }
    function tqWriteKey(uint24 lvl) external view returns (uint24) {
        return _tqWriteKey(lvl);
    }
    function tqFarFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }
}
```

### Pattern 2: Replicated Logic Harness (Used by Phases 76-77)
**What:** A contract that replicates proposed production logic in a simplified form to test structural behavior independent of internal dependencies (trait generation, BURNIE crediting, etc.).
**When to use:** When production functions are `private` (not `internal`) and cannot be called from a harness, or when the function has deep dependencies that would require full protocol deployment. `_awardFarFutureCoinJackpot` is `private`, hence JackpotCombinedPool.t.sol replicates its selection logic.
**When NOT to use:** The replicated logic approach has a fidelity risk -- if production code diverges from the replica, the test is invalid. Prefer direct harness or full deployment where possible.

### Pattern 3: Full Protocol Integration (Used by MultiLevel.inv.t.sol)
**What:** Deploy all 23 protocol contracts via `DeployProtocol.sol`, then drive the game through level transitions using `purchase()`, `advanceGame()`, and mock VRF fulfillment.
**When to use:** TEST-05 integration test -- proving zero stranding across multiple levels requires actual contract interactions, not isolated harness calls.
**Key dependency:** `patchForFoundry.js` must have patched `ContractAddresses.sol` before `forge build`.
**Example:**
```solidity
// Source: test/fuzz/invariant/MultiLevel.inv.t.sol
contract IntegrationTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
    }
    // Then drive via game.purchase(), game.advanceGame(), mockVRF.fulfillRandomWords()
}
```

### Anti-Patterns to Avoid
- **Testing replicated logic when production function is accessible:** If the function is `internal`, use a harness that inherits the contract. Don't replicate logic unnecessarily.
- **Asserting on write buffer instead of read buffer:** TQ-01 was caused by reading `_tqWriteKey` instead of `_tqReadKey`. Tests must verify the correct key is used. JackpotCombinedPool.t.sol test 8 explicitly proves this.
- **Assuming advanceGame completes in one call:** The batch processing model means `advanceGame()` must be called repeatedly (it returns stage codes indicating progress). The integration test must loop until stage indicates completion.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Protocol deployment in tests | Manual contract deployment | `DeployProtocol.sol` helper | Address correctness depends on CREATE nonce prediction; DeployProtocol handles all 23 contracts in order |
| VRF fulfillment in tests | Custom VRF mock | `MockVRFCoordinator` + existing VRF handler pattern | Mock already handles request ID tracking and word fulfillment |
| Level advancement | Direct state manipulation for multi-level | Purchase + advanceGame + VRF cycle | Integration test must prove actual game mechanics, not simulated state |
| Entropy/RNG word setup | Custom entropy generation | Use `vm.store` to set `rngWordCurrent` directly | Harness tests can skip VRF by directly setting the entropy word |

## Common Pitfalls

### Pitfall 1: Pragma Version Mismatch
**What goes wrong:** Test files compiled with `pragma solidity ^0.8.26` but some older test files use `pragma solidity 0.8.34` (exact version). Mixing can cause compilation issues.
**Why it happens:** Phase 74 tests (StorageFoundation.t.sol) use exact version; Phases 75-78 use caret version.
**How to avoid:** Use `pragma solidity ^0.8.26` consistently (matches Phases 75-78 pattern). The foundry.toml pins `solc_version = "0.8.34"`.
**Warning signs:** Compilation errors about version mismatch.

### Pitfall 2: ticketWriteSlot State Dependency
**What goes wrong:** Tests fail because the harness defaults to `ticketWriteSlot = 0`, but the test assumes a different slot state.
**Why it happens:** `_tqWriteKey` and `_tqReadKey` output depends on `ticketWriteSlot` value. If not explicitly set, the default (0) means writeKey = raw level, readKey = level | TICKET_SLOT_BIT.
**How to avoid:** Always explicitly set `ticketWriteSlot` in setUp() and document the key mappings in test comments.
**Warning signs:** Assertions about queue lengths failing because the wrong key was queried.

### Pitfall 3: Integration Test Gas / Batch Limits
**What goes wrong:** advanceGame() reverts or appears to not process tickets because the batch budget is exhausted mid-processing.
**Why it happens:** `processFutureTicketBatch` has a `WRITES_BUDGET_SAFE` limit (~10000 write units). Large queues require multiple advanceGame() calls.
**How to avoid:** In integration tests, loop advanceGame() until the Advance event indicates stage 6 (daily purchase complete). Use `vm.roll` and `vm.warp` to advance blocks/time as needed.
**Warning signs:** Stage stuck at 5 (STAGE_TICKETS_WORKING).

### Pitfall 4: Constructor Pre-Queue Contamination
**What goes wrong:** Integration test finds unexpected tickets in queues from the DegenerusGame constructor.
**Why it happens:** Constructor pre-queues 16 vault + 16 sDGNRS tickets for each of levels 1-100. These land in the write buffer (near-future, since `level = 0` at construction time and targets 1-100 are all within +6 of... wait, actually levels 7-100 ARE far-future relative to level 0). This needs careful analysis.
**How to avoid:** Account for constructor pre-queued tickets. At `level = 0`, tickets for levels 7-100 have `targetLevel > 0 + 6 = true`, so they route to FF key. Tickets for levels 1-6 route to write key. This is correct behavior but the integration test must expect FF key entries for levels 7-100.
**Warning signs:** Non-zero FF key entries at levels the test didn't explicitly populate.

### Pitfall 5: patchForFoundry.js Not Run
**What goes wrong:** Full protocol deployment via DeployProtocol.sol fails with address mismatches.
**Why it happens:** ContractAddresses.sol uses compile-time baked addresses based on CREATE nonce prediction. The patch script updates these for Foundry's deployer address.
**How to avoid:** Run `patchForFoundry.js` before `forge build` (or ensure it was already run). Existing CI/test workflow should handle this.
**Warning signs:** Deployment reverts or contracts call wrong addresses.

## Code Examples

### Existing Test Pattern: Routing Verification (TEST-01 basis)
```solidity
// Source: test/fuzz/TicketRouting.t.sol (actual project code)
function testFarFutureRoutesToFFKey() public {
    // level=10, targetLevel=17 (17 > 10+6 = true, far-future)
    harness.queueTickets(buyer, 17, 1);
    uint24 ffKey = harness.tqFarFutureKey(17);
    uint24 writeKey = harness.tqWriteKey(17);
    assertEq(harness.getQueueLength(ffKey), 1, "FF key should have 1 entry");
    assertEq(harness.getQueueEntry(ffKey, 0), buyer, "FF key entry should be buyer");
    assertEq(harness.getQueueLength(writeKey), 0, "write key should be empty");
}
```

### Existing Test Pattern: RNG Guard (TEST-04 basis)
```solidity
// Source: test/fuzz/TicketRouting.t.sol (actual project code)
function testRngGuardRevertsOnFFKey() public {
    harness.setRngLockedFlag(true);
    harness.setPhaseTransitionActive(false);
    vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
    harness.queueTickets(buyer, 17, 1);
}

function testRngGuardAllowsWithPhaseTransition() public {
    harness.setRngLockedFlag(true);
    harness.setPhaseTransitionActive(true);
    harness.queueTickets(buyer, 17, 1);
    uint24 ffKey = harness.tqFarFutureKey(17);
    assertEq(harness.getQueueLength(ffKey), 1, "phaseTransitionActive should exempt from guard");
}
```

### Existing Test Pattern: Combined Pool Selection (TEST-03 basis)
```solidity
// Source: test/fuzz/JackpotCombinedPool.t.sol (actual project code)
function testCombinedPoolReadsBothQueues() public {
    uint24 lvl = 20;
    uint24 readKey = harness.tqReadKey(lvl);
    uint24 ffKey = harness.tqFarFutureKey(lvl);
    harness.setTicketQueue(readKey, 5);
    harness.setTicketQueue(ffKey, 3);
    uint256 entropy = uint256(6) << 32;
    (address winner, bool found) = harness.selectWinner(lvl, entropy);
    assertTrue(found, "winner should be found from combined pool");
}
```

### Integration Test Pattern: Level Advancement (TEST-05 basis)
```solidity
// Source: test/fuzz/invariant/MultiLevel.inv.t.sol + test/fuzz/handlers/MultiLevelHandler.sol
// Pattern for driving game through levels:
//   1. game.purchase{value: price}(buyer, qty, 0, 0, ...) -- buy tickets
//   2. game.advanceGame(200) -- request VRF (returns stage=1)
//   3. mockVRF.fulfillRandomWords(requestId, randomWord) -- fulfill VRF
//   4. game.advanceGame(200) -- process tickets (stage=5, repeat until stage=6)
//   5. Verify FF queue drain
```

## Existing Test Coverage Analysis

**Critical finding:** Phases 74-78 already created 27 Foundry tests across 5 files that cover the core behaviors required by TEST-01 through TEST-04. The key question is whether Phase 80 needs to CREATE additional tests or merely CONSOLIDATE and VERIFY the existing ones.

| Requirement | Existing File | Existing Tests | Gap |
|-------------|--------------|----------------|-----|
| TEST-01 | TicketRouting.t.sol | 7 tests (routing + boundary + scaled + range) | Tests prove routing at `_queueTickets` level. The requirement says "ALL sources (lootbox, whale, vault, endgame)" -- but all sources funnel through `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange`. The single fix point IS the proof. No gap in logic, but the requirement wording implies multi-source demonstration. |
| TEST-02 | TicketProcessingFF.t.sol | 9 tests (dual drain, cursor, resume) | Tests use simplified budget model (budget=10, no trait generation). Structural drain logic matches production MintModule.sol:298-454 exactly. Traits are an orthogonal concern. |
| TEST-03 | JackpotCombinedPool.t.sol | 8 tests (both queues, routing, boundary, EDGE-03) | Uses replicated `_selectWinner` logic (production function is `private`). Matches JackpotModule.sol:2544-2556 exactly. |
| TEST-04 | TicketRouting.t.sol | 5 tests (revert, exemption, near-future, scaled, range) | Fully covered. All guard behaviors tested. |
| TEST-05 | (none) | 0 tests | Complete gap. No multi-level integration test exists. |

**Recommendation:** Phase 80 should NOT duplicate existing tests. Instead:
1. Write a verification document confirming existing tests satisfy TEST-01 through TEST-04
2. Add a small number of supplemental tests if the planner deems the "ALL sources" language in TEST-01 requires explicit demonstration per source type
3. Write the TEST-05 integration test as the primary new deliverable

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) 1.5.1 + forge-std |
| Config file | foundry.toml (root) |
| Quick run command | `forge test --match-contract FarFuture -vvv` |
| Full suite command | `forge test -vvv` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 | FF routing from all sources | unit | `forge test --match-contract TicketRoutingTest -vvv` | Exists (TicketRouting.t.sol, 7 tests) |
| TEST-02 | processFutureTicketBatch drains FF | unit | `forge test --match-contract TicketProcessingFFTest -vvv` | Exists (TicketProcessingFF.t.sol, 9 tests) |
| TEST-03 | _awardFarFutureCoinJackpot finds FF winners | unit | `forge test --match-contract JackpotCombinedPoolTest -vvv` | Exists (JackpotCombinedPool.t.sol, 8 tests) |
| TEST-04 | rngLocked revert on FF writes | unit | `forge test --match-test testRngGuard -vvv` | Exists (TicketRouting.t.sol, 5 tests) |
| TEST-05 | Multi-level integration, zero stranding | integration | `forge test --match-contract FarFutureIntegration -vvv` | Does NOT exist |

### Sampling Rate
- **Per task commit:** `forge test --match-contract "TicketRouting|TicketProcessingFF|JackpotCombinedPool|FarFutureIntegration" -vvv`
- **Per wave merge:** `forge test -vvv`
- **Phase gate:** Full suite green before /gsd:verify-work

### Wave 0 Gaps
- [ ] `test/fuzz/FarFutureIntegration.t.sol` -- covers TEST-05 (multi-level integration)
- [ ] Verification that existing tests (TEST-01 through TEST-04) run green on current code

## Constructor Pre-Queue Analysis (Important for TEST-05)

The DegenerusGame constructor (DegenerusGame.sol:250-251) pre-queues tickets:
```solidity
for each level i in 1..100:
    _queueTickets(ContractAddresses.SDGNRS, i, 16);
    _queueTickets(ContractAddresses.VAULT, i, 16);
```

At construction time, `level = 0`. The routing check `targetLevel > level + 6` means:
- Levels 1-6: `i > 0 + 6 = false` -- routes to write key (near-future)
- Levels 7-100: `i > 0 + 6 = true` -- routes to FF key (far-future)

This means the constructor itself creates FF key entries for levels 7-100 (32 entries each: 16 sDGNRS + 16 vault). The integration test (TEST-05) must account for these pre-existing FF entries when verifying zero stranding.

## Open Questions

1. **Does TEST-01 require explicit per-source tests or is the single fix point sufficient?**
   - What we know: All ticket sources (lootbox, whale, vault, endgame, decimator, jackpot auto-rebuy) funnel through `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` in DegenerusGameStorage.sol. The routing fix is at lines 544-546. Existing TicketRouting.t.sol tests prove this routing works correctly.
   - What's unclear: The REQUIREMENTS.md says "from ALL sources (lootbox, whale, vault, endgame)" -- this could mean (a) prove the routing works (already done) or (b) prove each upstream caller actually passes far-future target levels to the routing function.
   - Recommendation: The planner should interpret TEST-01 as satisfied by existing TicketRouting.t.sol tests (which test the single fix point), with an optional supplemental test demonstrating the callers if the user wants explicit per-source coverage. The integration test (TEST-05) will implicitly cover multiple sources anyway.

2. **TEST-05 scope: how many levels to advance?**
   - What we know: Constructor pre-queues to level 100. A meaningful integration test should advance past at least level 7 (where FF entries begin) and verify processFutureTicketBatch drains them.
   - What's unclear: How many levels is sufficient? Advancing through 3-5 levels after level 7 would prove the mechanism works; advancing through all 100 would be thorough but extremely slow.
   - Recommendation: Advance through 2-3 levels past the first FF-containing level. Verify FF queues drain to zero at each processed level.

## Sources

### Primary (HIGH confidence)
- Direct code inspection: DegenerusGameStorage.sol (lines 537-731), DegenerusGameMintModule.sol (lines 298-454), DegenerusGameJackpotModule.sol (lines 2522-2614)
- Existing test files: TicketRouting.t.sol, TicketProcessingFF.t.sol, JackpotCombinedPool.t.sol, TicketEdgeCases.t.sol, TqFarFutureKey.t.sol
- foundry.toml configuration
- DeployProtocol.sol test helper

### Secondary (MEDIUM confidence)
- GameLifecycle.test.js (Hardhat integration test pattern, used as reference for TEST-05 design)
- MultiLevel.inv.t.sol (Foundry invariant pattern for multi-level testing)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Foundry already in use, no new dependencies needed
- Architecture: HIGH - Five existing test files establish clear patterns; DeployProtocol.sol handles integration
- Pitfalls: HIGH - Constructor pre-queue analysis verified against actual code; batch processing limits documented from production code
- Existing coverage: HIGH - Direct inspection of all 27 existing tests across 5 files confirms coverage map

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable -- v3.9 code changes are complete, only tests remain)
