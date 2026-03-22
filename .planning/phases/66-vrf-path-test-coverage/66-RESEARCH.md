# Phase 66: VRF Path Test Coverage - Research

**Researched:** 2026-03-22
**Domain:** Foundry fuzz/invariant testing and Halmos symbolic verification for VRF path invariants
**Confidence:** HIGH

## Summary

Phase 66 consolidates the verified invariants from Phases 63-65 into executable test coverage: Foundry fuzz tests for lootbox RNG index lifecycle (TEST-01), Foundry invariant tests for VRF stall-to-recovery state machine (TEST-02), Foundry fuzz tests for gap backfill edge cases (TEST-03), and Halmos symbolic verification of the redemption roll formula (TEST-04).

The project already has substantial test coverage from Phase 63 (VRFCore.t.sol, 22 tests), Phase 64 (LootboxRngLifecycle.t.sol, 16 tests), and Phase 65 (VRFStallEdgeCases.t.sol, 17 tests). These are per-property fuzz and unit tests. What Phase 66 adds is different: (a) Foundry invariant tests that use handler contracts to drive the system through arbitrary sequences of operations and check invariants after every call, and (b) Halmos symbolic proofs that the redemption roll formula `uint16((word >> 8) % 151 + 25)` produces identical results [25, 175] across all 3 call sites.

The distinction matters: existing tests prove specific scenarios (fuzz individual inputs to known flows), while invariant tests prove properties hold across arbitrary operation sequences (the fuzzer chooses which functions to call and in what order). The Halmos test proves the formula algebraically, covering the full input space.

**Primary recommendation:** Two plans: (1) Foundry invariant test with a VRFPathHandler driving purchase/advanceGame/fulfillVrf/coordinatorSwap/warpTime with ghost variables tracking lootbox index invariants, stall-to-recovery transitions, and gap backfill correctness, (2) Halmos symbolic test proving redemption roll bounds consistency across the 3 call sites (rngGate normal, gameOverEntropy normal, gameOverEntropy fallback).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | Foundry fuzz tests for lootboxRngIndex lifecycle invariants -- index never skips, never double-increments on retry, every index has a corresponding word | Invariant handler tracks ghost_lootboxRngIndex and ghost_wordWriteCount; after every operation, asserts index == expected and every filled index has nonzero word. Section "Architecture Patterns -- Invariant Handler Design" |
| TEST-02 | Foundry invariant tests for VRF stall-to-recovery scenarios -- system transitions correctly through stall, coordinator swap, gap backfill, normal operation | Handler drives coordinator swap + warp + resume sequences; ghost variables track state machine transitions. Section "Architecture Patterns -- Stall Recovery State Machine" |
| TEST-03 | Foundry tests for gap backfill edge cases covering multi-day gaps and boundary conditions (1-day gap, maximum gap, gap at game boundaries) | Parameterized fuzz tests with bounded gap sizes; handler exercises gap sizes 1..30 with boundary assertions. Section "Architecture Patterns -- Gap Backfill Edge Cases" |
| TEST-04 | Halmos symbolic verification proves entropy bounds consistency -- redemption roll formula [25, 175] produces identical results across all 3 call sites | Pure function Halmos check_ test for `(word >> 8) % 151 + 25` on symbolic uint256 input. Section "Architecture Patterns -- Halmos Redemption Roll" |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundry (forge) | 1.5.1 | Fuzz/invariant testing framework | Already configured in foundry.toml; project standard |
| forge-std | Latest (lib/) | Test assertions, vm cheatcodes, bound() | Already installed |
| Halmos | 0.3.3 | Symbolic verification of arithmetic properties | Already installed; used for Arithmetic.t.sol and NewProperties.t.sol |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MockVRFCoordinator | Custom (contracts/mocks/) | Simulates Chainlink VRF V2.5 coordinator | All VRF tests |
| VRFHandler | Custom (test/fuzz/helpers/) | Wraps mock VRF for invariant testing | Reuse in invariant handler |
| DeployProtocol | Custom (test/fuzz/helpers/) | Full protocol deployment for testing | Base contract for all test files |

### Existing Test Files (Phase 63-65, Will NOT Be Modified)
| File | Tests | Coverage |
|------|-------|----------|
| test/fuzz/VRFCore.t.sol | 22 tests | VRFC-01..04: callback safety, requestId lifecycle, mutual exclusion, timeout retry |
| test/fuzz/LootboxRngLifecycle.t.sol | 16 tests | LBOX-01..05: index mutations, word writes, zero guards, entropy uniqueness, full lifecycle |
| test/fuzz/VRFStallEdgeCases.t.sol | 17 tests | STALL-01..07: gap backfill, manipulation, gas ceiling, coordinator swap, zero-seed, gameover, timing |
| test/fuzz/StallResilience.t.sol | 3 tests | Integration: stall-swap-resume, coinflip claims, orphaned lootbox |

**Installation:** No new packages needed. All infrastructure exists.

**Test commands:**
```bash
# Run new Phase 66 invariant tests
forge test --match-path test/fuzz/invariant/VRFPathInvariants.inv.t.sol -vvv
# Run new Phase 66 fuzz tests for gap backfill edge cases
forge test --match-path test/fuzz/VRFPathCoverage.t.sol -vvv --fuzz-runs 1000
# Run new Phase 66 Halmos test
halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000
# Full suite
forge test -vvv --fuzz-runs 1000
```

## Architecture Patterns

### Existing Test vs Phase 66 Test: What's Different

The key distinction:

| Phase 63-65 Tests | Phase 66 Tests |
|-------------------|----------------|
| Test specific scenarios with fuzzed inputs | Test properties across arbitrary operation sequences |
| `test_retryDetection_fuzz(word)` -- fuzzes the VRF word, but the scenario is fixed (request -> timeout -> retry) | `invariant_indexNeverSkips()` -- fuzzer picks ANY sequence of purchase/advanceGame/fulfillVrf/swap/warp, invariant must hold after every call |
| Proves a code path works correctly | Proves no sequence of operations can violate the property |

Phase 63-65 tests answer "does this specific flow work?" Phase 66 invariant tests answer "does ANY sequence of operations preserve this property?"

### Invariant Handler Design (TEST-01 + TEST-02 + TEST-03)

**Pattern:** A single VRFPathHandler drives all three requirements. It wraps the game's external interface and tracks ghost state.

```
test/fuzz/
  handlers/
    VRFPathHandler.sol       -- NEW: handler for VRF path invariant testing
  invariant/
    VRFPathInvariants.inv.t.sol  -- NEW: invariant assertions
  VRFPathCoverage.t.sol      -- NEW: additional parametric fuzz tests for gap edge cases
```

**VRFPathHandler actions (fuzzer-callable):**
1. `purchase(actorSeed, qty, lootboxAmt)` -- buy tickets with optional lootbox
2. `advanceGame()` -- trigger daily VRF request / process
3. `fulfillVrf(randomWord)` -- fulfill pending VRF with fuzzed word
4. `requestLootboxRng()` -- trigger mid-day lootbox VRF request
5. `coordinatorSwap()` -- emergency coordinator rotation (creates stall conditions)
6. `warpTime(delta)` -- advance block.timestamp (bounded 1min..30days)
7. `warpPastTimeout()` -- jump 13+ hours for timeout retry path

**Ghost variables tracked:**
```solidity
// TEST-01: Lootbox index lifecycle
uint48 public ghost_expectedIndex;         // Tracks expected index (incremented on fresh request, mid-day request)
uint256 public ghost_indexSkipViolations;   // Counted when actual != expected
uint256 public ghost_doubleIncrementCount;  // Counted when index jumps by >1 in single fresh request
uint256 public ghost_orphanedIndices;       // Indices with no corresponding word after unlock

// TEST-02: Stall-to-recovery state machine
uint256 public ghost_stallCount;            // Times coordinator swap happened
uint256 public ghost_recoveryCount;         // Times game successfully resumed after swap
uint256 public ghost_stateViolations;       // Bad transitions (e.g., rngLocked after swap, gap days not backfilled)

// TEST-03: Gap backfill tracking
uint256 public ghost_maxGapSize;            // Largest gap observed
uint256 public ghost_gapBackfillFailures;   // Gap days with missing words after resume
```

**Invariant assertions:**
```solidity
// TEST-01
function invariant_indexNeverSkips() external view;         // ghost_indexSkipViolations == 0
function invariant_noDoubleIncrement() external view;       // ghost_doubleIncrementCount == 0
function invariant_everyIndexHasWord() external view;       // For all i < currentIndex, word[i] != 0 after unlock

// TEST-02
function invariant_stallRecoveryComplete() external view;   // ghost_stateViolations == 0
function invariant_rngUnlockedAfterSwap() external view;    // After coordinatorSwap, rngLocked() == false

// TEST-03
function invariant_allGapDaysBackfilled() external view;    // ghost_gapBackfillFailures == 0
```

### Stall Recovery State Machine (TEST-02)

The VRF stall-to-recovery sequence has 4 states:

```
NORMAL --> STALLED --> SWAPPED --> RESUMING --> NORMAL
  |                      ^            |
  |  (VRF timeout)       |            |
  +---[12h+]------> RETRYING --------+
```

The handler tracks transitions:
- **NORMAL -> STALLED:** VRF request pending, time advances past stale threshold (coordinator goes offline)
- **STALLED -> SWAPPED:** `updateVrfCoordinatorAndSub` called -- clears rngLocked, vrfRequestId, rngRequestTime, rngWordCurrent, midDayTicketRngPending
- **SWAPPED -> RESUMING:** `advanceGame` fires new VRF request to new coordinator
- **RESUMING -> NORMAL:** VRF fulfilled, gap backfill runs, day processed

**Invariants checked at each transition:**
- After SWAPPED: `rngLocked() == false`, `vrfRequestId == 0`, `rngRequestTime == 0`, `rngWordCurrent == 0`
- After NORMAL (post-recovery): All gap days have nonzero `rngWordForDay`, all orphaned lootbox indices have nonzero words, `dailyIdx` advanced to current day

### Gap Backfill Edge Cases (TEST-03)

Boundary conditions to cover:

| Case | Gap Size | Setup | Key Assertion |
|------|----------|-------|---------------|
| Minimum gap | 1 day | Stall day N, resume day N+2 | Exactly 1 gap day backfilled with `keccak256(vrfWord, gapDay)` |
| Small gap | 3 days | Standard stall + swap | All 3 gap days have unique words |
| Medium gap | 30 days | Extended stall | Gas < 10M, all words unique |
| Maximum gap | 120 days | Death clock maximum | Gas < 25M, all words unique, no zero words |
| Gap at game start | N/A | Swap before any day completes | lootboxRngIndex starts at 1, orphaned index 0 handled |
| Gap with mid-day pending | 3 days | requestLootboxRng before stall | midDayTicketRngPending cleared by swap, orphaned lootbox index backfilled |

**Existing coverage from Phase 65:** VRFStallEdgeCases.t.sol already has `test_gapBackfillGas30Days`, `test_gapBackfillGas120Days`, `test_gapBackfillSingleDayGap`, and `test_gapBackfillEntropyUnique_fuzz`. Phase 66 adds the invariant-based coverage (arbitrary sequences) and additional boundary conditions (game start, mid-day pending).

### Halmos Redemption Roll Verification (TEST-04)

**The formula (identical at all 3 call sites):**
```solidity
uint16 redemptionRoll = uint16((word >> 8) % 151 + 25);
```

**3 call sites in DegenerusGameAdvanceModule.sol:**
1. **Line 817:** Normal rngGate path -- uses `currentWord` (post-nudge daily RNG word)
2. **Line 880:** gameOverEntropy normal VRF path -- uses `currentWord` (post-nudge current word)
3. **Line 909:** gameOverEntropy fallback path -- uses `fallbackWord` (post-nudge historical fallback word)

**Halmos proof strategy:** Pure function check that for ANY uint256 input word:
1. Result is always in [25, 175] (bounds)
2. Result is always a valid uint16 (no truncation issues)
3. The formula is deterministic (same input -> same output)
4. All 3 call sites use the identical formula (verified by source audit, proven by shared function)

**Why Halmos over fuzz:** Fuzz testing with 10000 runs covers 10000 random inputs. Halmos proves the property for ALL 2^256 possible inputs. For a pure arithmetic property like this, Halmos provides complete formal verification.

**Implementation pattern (from existing NewProperties.t.sol):**
```solidity
// test/halmos/RedemptionRoll.t.sol
pragma solidity 0.8.34;

import "forge-std/Test.sol";

contract RedemptionRollSymbolicTest is Test {
    /// @notice Redemption roll is always in [25, 175]
    function check_redemption_roll_bounds(uint256 word) public pure {
        uint16 roll = uint16((word >> 8) % 151 + 25);
        assert(roll >= 25);
        assert(roll <= 175);
    }

    /// @notice Redemption roll is deterministic
    function check_redemption_roll_deterministic(uint256 word) public pure {
        uint16 roll1 = uint16((word >> 8) % 151 + 25);
        uint16 roll2 = uint16((word >> 8) % 151 + 25);
        assert(roll1 == roll2);
    }

    /// @notice Intermediate value (word >> 8) % 151 is in [0, 150]
    function check_redemption_roll_modulo_range(uint256 word) public pure {
        uint256 intermediate = (word >> 8) % 151;
        assert(intermediate <= 150);
        // Adding 25 gives [25, 175], which fits in uint16
        assert(intermediate + 25 <= type(uint16).max);
    }

    /// @notice uint16 cast is safe (no truncation)
    function check_redemption_roll_no_truncation(uint256 word) public pure {
        uint256 fullResult = (word >> 8) % 151 + 25;
        uint16 castResult = uint16(fullResult);
        assert(uint256(castResult) == fullResult);
    }
}
```

**Solver expectations:** Based on the existing Halmos tests (Arithmetic.t.sol, NewProperties.t.sol), these pure arithmetic properties solve in under 10 seconds with default settings. The formula involves no loops, no storage access, and no external calls -- ideal for SMT solvers.

### Recommended File Layout

```
test/fuzz/
  handlers/
    VRFPathHandler.sol           # NEW: handler for VRF path invariant testing
  invariant/
    VRFPathInvariants.inv.t.sol  # NEW: invariant test assertions (TEST-01, TEST-02, TEST-03)
  VRFPathCoverage.t.sol          # NEW: additional parametric fuzz tests for gap edge cases
test/halmos/
  RedemptionRoll.t.sol           # NEW: Halmos symbolic test (TEST-04)
```

### Anti-Patterns to Avoid
- **Testing the mock, not the contract:** Avoid assertions on MockVRFCoordinator internals. Always assert on game contract state (game.lootboxRngWord, game.rngWordForDay, game.rngLocked).
- **Unbounded loops in handlers:** The handler must use `try/catch` for all game calls (they can revert). Limit iteration bounds (50 advanceGame loops is the project convention).
- **State pollution across invariant runs:** Each invariant test run starts fresh (setUp). Do NOT carry state between test contracts.
- **Halmos on full contract:** The DegenerusGame contract with 10 delegatecall modules exceeds Halmos solver capacity (documented in GameFSM.t.sol). Halmos tests MUST be pure function tests on isolated formulas.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VRF mock | Custom VRF simulator | MockVRFCoordinator (contracts/mocks/) | Already handles fulfillRandomWords, fulfillRandomWordsRaw, pendingRequests |
| Protocol deployment | Manual contract creation | DeployProtocol.sol (test/fuzz/helpers/) | Deploys all 23 contracts with correct nonce ordering |
| Actor management | Custom address arrays | bound() + makeAddr pattern from forge-std | Standard Foundry practice, used in all existing handlers |
| Invariant handler pattern | Custom test driver | Foundry invariant testing (targetContract) | Project already has 11 invariant tests using this pattern |

## Common Pitfalls

### Pitfall 1: Handler Actions Must Be Idempotent-Safe
**What goes wrong:** Handler calls purchase/advanceGame but doesn't handle reverts, causing the invariant fuzzer to count the run as a failure.
**Why it happens:** Many game functions revert under specific conditions (RngNotReady, NotTimeYet, InsufficientFunds).
**How to avoid:** Wrap ALL game calls in `try/catch` blocks. Failed calls should be no-ops, not test failures.
**Warning signs:** Invariant tests fail with "EvmError: Revert" instead of invariant violations.

### Pitfall 2: Foundry Invariant Depth vs State Space
**What goes wrong:** Invariant tests pass but never actually exercise stall/recovery paths because the default depth (128) isn't enough to reach the stall state.
**Why it happens:** Reaching a stall requires: purchase -> advanceGame -> VRF request -> warp 12h+ -> advanceGame timeout -> coordinator swap. That's 5-6 handler calls minimum.
**How to avoid:** Use the project's default invariant config (depth=128, runs=256) which is already tuned. Also add a targeted test that forces the stall path (unit test, not invariant) to confirm the handler CAN exercise it.
**Warning signs:** ghost_stallCount always 0 after invariant runs.

### Pitfall 3: Absolute vs Relative Timestamps
**What goes wrong:** Tests fail because day boundaries don't align with expectations.
**Why it happens:** The protocol uses absolute timestamps (day = ts / 86400). Deploy is at ts=86400 (day 1). Relative warps (`block.timestamp + 1 days`) can land mid-day.
**How to avoid:** Use absolute timestamps for day boundaries (`vm.warp(N * 86400)`) as established in Phase 63. The handler's warpTime should use bounded deltas that the invariant fuzzer controls.
**Warning signs:** `game.currentDayView()` returns unexpected values.

### Pitfall 4: Halmos Pragma Must Match foundry.toml
**What goes wrong:** Halmos test compilation fails or produces wrong bytecode.
**Why it happens:** Halmos tests in this project use `pragma solidity 0.8.34` (matching foundry.toml's `solc_version`), not `^0.8.26` (which the fuzz tests use for broader compatibility). The existing Halmos tests (Arithmetic.t.sol, NewProperties.t.sol) all use exact 0.8.34.
**How to avoid:** New Halmos tests must use `pragma solidity 0.8.34` (not `^0.8.26`).
**Warning signs:** Compilation errors when running halmos.

### Pitfall 5: Invariant Test Must Check Ghost Variables, Not Live State
**What goes wrong:** Invariant assertion reads game state directly, which changes between handler calls and invariant checks.
**Why it happens:** Foundry calls invariant_ functions after every handler call. If the invariant reads mutable state, it may see mid-operation values.
**How to avoid:** Ghost variables in the handler capture state snapshots after each operation. Invariant assertions check ghost variables, not live game state. Exception: read-only view functions (game.lootboxRngWord, game.rngLocked) are safe to read in invariants.
**Warning signs:** Flaky invariant tests that pass/fail depending on which handler action ran last.

## Code Examples

### Foundry Invariant Test Pattern (from GameFSM.inv.t.sol)

Source: test/fuzz/invariant/GameFSM.inv.t.sol (existing project pattern)
```solidity
contract VRFPathInvariants is DeployProtocol {
    VRFPathHandler public handler;

    function setUp() public {
        _deployProtocol();
        handler = new VRFPathHandler(game, mockVRF, 5);
        targetContract(address(handler));
    }

    function invariant_indexNeverSkips() public view {
        assertEq(handler.ghost_indexSkipViolations(), 0,
            "VRFPath: lootboxRngIndex skipped a value");
    }
}
```

### Handler Pattern (from FSMHandler.sol)

Source: test/fuzz/handlers/FSMHandler.sol (existing project pattern)
```solidity
function advanceGame() external {
    uint48 indexBefore = game.lootboxRngIndexView();
    bool lockedBefore = game.rngLocked();

    try game.advanceGame() {} catch { return; }

    uint48 indexAfter = game.lootboxRngIndexView();

    // Track if index jumped by more than 1 (double increment)
    if (indexAfter > indexBefore + 1) {
        ghost_doubleIncrementCount++;
    }
    // ... update other ghost variables
}
```

### Halmos Pure Function Pattern (from NewProperties.t.sol)

Source: test/halmos/NewProperties.t.sol (existing project pattern)
```solidity
contract RedemptionRollSymbolicTest is Test {
    function check_redemption_roll_bounds(uint256 word) public pure {
        uint16 roll = uint16((word >> 8) % 151 + 25);
        assert(roll >= 25);
        assert(roll <= 175);
    }
}
```

### Foundry Config (foundry.toml, existing)

```toml
[invariant]
runs = 256
depth = 128
fail_on_revert = false       # Critical: handler calls can revert
shrink_run_limit = 5000
show_metrics = true
dictionary_weight = 80
include_storage = true
include_push_bytes = true
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry 1.5.1 + Halmos 0.3.3 |
| Config file | foundry.toml (existing, no changes needed) |
| Quick run command | `forge test --match-path test/fuzz/invariant/VRFPathInvariants.inv.t.sol -vvv` |
| Full suite command | `forge test -vvv --fuzz-runs 1000 && halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 | lootboxRngIndex lifecycle invariants | invariant | `forge test --match-contract VRFPathInvariants --match-test invariant_index -vvv` | Wave 0 |
| TEST-02 | VRF stall-to-recovery scenarios | invariant | `forge test --match-contract VRFPathInvariants --match-test invariant_stall -vvv` | Wave 0 |
| TEST-03 | Gap backfill edge cases | fuzz+invariant | `forge test --match-path test/fuzz/VRFPathCoverage.t.sol -vvv --fuzz-runs 1000` | Wave 0 |
| TEST-04 | Halmos redemption roll bounds | symbolic | `halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000` | Wave 0 |

### Sampling Rate
- **Per task commit:** `forge test --match-path test/fuzz/invariant/VRFPathInvariants.inv.t.sol -vvv && forge test --match-path test/fuzz/VRFPathCoverage.t.sol -vvv`
- **Per wave merge:** Full suite: `forge test -vvv --fuzz-runs 1000 && halmos --contract RedemptionRollSymbolicTest --forge-build-out forge-out --solver-timeout-assertion 60000`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/fuzz/handlers/VRFPathHandler.sol` -- handler for VRF path invariant testing
- [ ] `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` -- invariant assertions for TEST-01, TEST-02, TEST-03
- [ ] `test/fuzz/VRFPathCoverage.t.sol` -- parametric fuzz tests for gap backfill edge cases (TEST-03)
- [ ] `test/halmos/RedemptionRoll.t.sol` -- Halmos symbolic test for TEST-04

## Open Questions

1. **Invariant test depth for stall coverage**
   - What we know: Default depth=128 should be sufficient for the handler to exercise stall paths (5-6 calls minimum). The FSMHandler with similar depth successfully drives level advancement.
   - What's unclear: Whether the fuzzer will naturally discover coordinator swap sequences, or if we need weighted action selection.
   - Recommendation: Start with default config. If ghost_stallCount stays at 0, add a higher-weight `coordinatorSwap` action or a targeted unit test that forces the path.

2. **Halmos solver timeout for uint256 modulo**
   - What we know: Existing Halmos tests use `--solver-timeout-assertion 60000` (60s) and pass. The redemption roll formula is simpler than the existing BPS split tests.
   - What's unclear: Whether `(word >> 8) % 151` triggers any solver pathology due to 256-bit modular arithmetic.
   - Recommendation: Use the same timeout as existing tests. If it times out, add `if (word > 1e78) return;` bounds (standard Halmos pattern for managing solver complexity).

## Sources

### Primary (HIGH confidence)
- Foundry foundry.toml (project config) -- confirmed fuzz/invariant settings, solc version, test paths
- test/fuzz/VRFCore.t.sol, LootboxRngLifecycle.t.sol, VRFStallEdgeCases.t.sol -- existing Phase 63-65 tests, verified patterns
- test/fuzz/invariant/GameFSM.inv.t.sol + handlers/FSMHandler.sol -- established invariant test pattern
- test/halmos/NewProperties.t.sol + Arithmetic.t.sol -- established Halmos test pattern
- contracts/modules/DegenerusGameAdvanceModule.sol lines 817, 880, 909 -- all 3 redemption roll call sites verified identical
- contracts/libraries/EntropyLib.sol -- xorshift implementation verified

### Secondary (MEDIUM confidence)
- Halmos 0.3.3 command-line options -- verified via `halmos --help`
- Foundry 1.5.1 invariant testing -- well-established, documented

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already installed and configured in this project
- Architecture: HIGH -- all patterns copied from existing project tests (FSMHandler, GameFSM.inv.t.sol, NewProperties.t.sol)
- Pitfalls: HIGH -- derived from direct observation of existing tests and Phase 63-65 execution notes (absolute timestamps, try/catch, pragma version)

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable -- Foundry/Halmos/Solidity versions fixed by project config)
