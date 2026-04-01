# Phase 45: Invariant Test Suite - Research

**Researched:** 2026-03-21
**Domain:** Foundry invariant testing for gambling burn / sDGNRS redemption system
**Confidence:** HIGH

## Summary

This phase requires writing 7 Foundry invariant tests that encode the corrected redemption system properties identified and proven in Phase 44. The project already has a mature invariant testing infrastructure: 11 existing invariant/handler files in `test/fuzz/`, a `DeployProtocol.sol` harness that deploys all 28 contracts, handler contracts with ghost variable tracking, and a `foundry.toml` with `[invariant]` configuration matching the success criteria (256 runs, depth 128).

The 7 invariants map directly to Phase 44's verified properties: ETH segregation solvency (INV-01), no double-claim via CEI (INV-02), period index monotonicity (INV-03), totalSupply consistency (INV-04), 50% cap enforcement (INV-05), roll bounds [25, 175] (INV-06), and aggregate claim tracking (INV-07). Each invariant has a clear assertion pattern derived from the Phase 44 audit.

The primary challenge is writing a `RedemptionHandler` that drives the system through the full burn-resolve-claim lifecycle. The handler must: (1) acquire sDGNRS for actors (via pool transfers during game setup), (2) submit gambling burns, (3) trigger `advanceGame` + VRF fulfillment to resolve periods, and (4) claim redemptions. Ghost variables must track cumulative ETH/BURNIE flows for reconciliation. Several internal state variables (`pendingRedemptionBurnie`, `pendingRedemptionEthBase`, etc.) are `internal` visibility and require `vm.load` with known storage slots to read in assertions.

**Primary recommendation:** Create a single `RedemptionHandler.sol` that wraps burn/resolve/claim operations with ghost tracking, a single `RedemptionInvariants.inv.t.sol` that asserts all 7 invariants, and reuse the existing `DeployProtocol.sol` + `VRFHandler.sol` infrastructure. Apply Phase 44 code fixes (CP-08, CP-06, Seam-1, CP-07) before writing tests so they pass against corrected code.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INV-01 | Foundry invariant -- segregated ETH never exceeds contract balance | `pendingRedemptionEthValue` (slot 9, public) must be <= `address(sdgnrs).balance + steth.balanceOf(sdgnrs) + _claimableWinnings()`. Phase 44 proved solvency; handler exercises submit/resolve/claim sequences. |
| INV-02 | Foundry invariant -- no double-claim (claim deleted before payout) | After every `claimRedemption()` call, `pendingRedemptions[player].periodIndex == 0`. Ghost variable tracks claimed addresses; re-claim attempt must revert with `NoClaim()`. |
| INV-03 | Foundry invariant -- period index monotonically increases | Ghost variable `ghost_lastPeriodIndex` tracked in handler; each new `redemptionPeriodIndex` value (slot 14) must be >= previous. `currentDayView()` is monotonically non-decreasing by construction. |
| INV-04 | Foundry invariant -- totalSupply consistent after burn/claim sequences | `sdgnrs.totalSupply()` (slot 0) must equal `sum(balanceOf[all_known_addresses])`. Ghost tracks total burned; `initialSupply - ghost_totalBurned == totalSupply`. |
| INV-05 | Foundry invariant -- 50% cap correctly enforced per period | Any burn exceeding 50% of `redemptionPeriodSupplySnapshot` (slot 13) must revert with `Insufficient()`. Handler tries capped and over-cap burns; ghost tracks `redemptionPeriodBurned` (slot 15). |
| INV-06 | Foundry invariant -- roll bounds always [25, 175] | After resolution, `redemptionPeriods[periodIndex].roll` must be in [25, 175]. Formula: `(currentWord >> 8) % 151 + 25`. Handler reads resolved periods via `vm.load` on slot 8 mapping. |
| INV-07 | Foundry invariant -- pendingRedemptionEthValue + pendingRedemptionBurnie track matches sum of individual claims | Ghost variables sum per-player `ethValueOwed` and `burnieOwed` from RedemptionSubmitted events; compared against `pendingRedemptionEthValue` (slot 9) and `pendingRedemptionBurnie` (slot 10). Rounding dust bounded at `99 * N` wei per period for the claim phase. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Foundry (forge) | v1.0+ | Invariant test runner | Already installed and configured in `foundry.toml` |
| Solidity | 0.8.34 | Test contract language | Project compiler version |
| forge-std | (bundled) | Test base class (`Test.sol`), `vm` cheatcodes | Standard Foundry test dependency, already in `lib/forge-std/` |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `DeployProtocol.sol` | Deploy all 28 protocol contracts in test setUp | Every invariant test inherits this |
| `VRFHandler.sol` | Mock VRF fulfillment for driving game state | Needed to trigger `advanceGame` -> `rngGate` -> `resolveRedemptionPeriod` |
| `vm.load(address, slot)` | Read `internal` storage variables from test | Required for slots 10-15 (internal visibility) |
| `forge inspect StakedDegenerusStonk storage-layout` | Verify storage slot offsets | Already run; slots documented in this research |

### Alternatives Considered
None. The project already has a Foundry invariant testing infrastructure. No new tools or libraries are needed.

## Architecture Patterns

### Recommended File Structure
```
test/fuzz/
  handlers/
    RedemptionHandler.sol      # NEW -- wraps burn/resolve/claim with ghost tracking
  invariant/
    RedemptionInvariants.inv.t.sol  # NEW -- all 7 INV-xx assertions
  helpers/
    DeployProtocol.sol         # EXISTING -- reuse as-is
    VRFHandler.sol             # EXISTING -- reuse as-is
```

### Pattern 1: Handler-Based Invariant Testing (Existing Project Pattern)
**What:** A handler contract wraps protocol functions with bounded inputs, actor management, ghost variable tracking, and try/catch error swallowing. The invariant test contract inherits `DeployProtocol`, instantiates handlers in `setUp()`, registers them with `targetContract()`, and defines `invariant_*` functions that assert properties.
**When to use:** Always -- this is the established pattern in 11 existing test files.
**Example (from existing `GameHandler.sol`):**
```solidity
contract GameHandler is Test {
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalClaimed;
    address[] public actors;
    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }
    function purchase(uint256 actorSeed, uint256 qty, ...) external useActor(actorSeed) {
        // bound inputs, try/catch, update ghosts
    }
}
```

### Pattern 2: Storage Slot Reading for Internal Variables
**What:** Use `vm.load(address, bytes32(slot))` to read `internal` state variables that have no public getter. Storage slots are obtained via `forge inspect`.
**When to use:** For `pendingRedemptionBurnie` (slot 10), `pendingRedemptionEthBase` (slot 11), `pendingRedemptionBurnieBase` (slot 12), `redemptionPeriodSupplySnapshot` (slot 13), `redemptionPeriodIndex` (slot 14), `redemptionPeriodBurned` (slot 15).
**Example (from existing `CompositionHandler.sol`):**
```solidity
uint256 packed = uint256(vm.load(address(game), bytes32(uint256(MINT_PACKED_SLOT))));
```

### Pattern 3: Multi-Phase Lifecycle in Handler
**What:** The handler must drive the system through the full 3-phase gambling burn lifecycle: submit (burn), resolve (advanceGame + VRF), claim. Each phase requires specific preconditions.
**When to use:** This is unique to the redemption handler and differs from existing handlers which only exercise single-step operations.
**Lifecycle in handler:**
```
1. action_burn(actorSeed, amount)
   - Requires: !gameOver, !rngLocked, actor has sDGNRS, amount <= 50% cap
   - Calls: sdgnrs.burn(amount) or sdgnrs.burnWrapped(amount)
   - Updates: ghost_totalBurned, ghost_ethSegregated, ghost_burnCount

2. action_advanceAndResolve(randomWord)
   - Calls: game.advanceGame(), vrf.fulfillRandomWords(), game.advanceGame()
   - Warps time: vm.warp(block.timestamp + 1 days) to cross day boundary
   - Updates: ghost_periodsResolved

3. action_claim(actorSeed)
   - Requires: actor has pending claim, period resolved, flip resolved
   - Calls: sdgnrs.claimRedemption()
   - Updates: ghost_totalEthClaimed, ghost_totalBurnieClaimed, ghost_claimCount
```

### Storage Slot Map (Verified via `forge inspect`)
```
StakedDegenerusStonk:
  Slot  0: totalSupply                    (uint256, public)
  Slot  1: balanceOf                      (mapping, public)
  Slot  2: poolBalances[0]                (uint256[5], private)
  Slot  7: pendingRedemptions             (mapping, public)
  Slot  8: redemptionPeriods              (mapping, public)
  Slot  9: pendingRedemptionEthValue      (uint256, public)
  Slot 10: pendingRedemptionBurnie        (uint256, internal)
  Slot 11: pendingRedemptionEthBase       (uint256, internal)
  Slot 12: pendingRedemptionBurnieBase    (uint256, internal)
  Slot 13: redemptionPeriodSupplySnapshot (uint256, internal)
  Slot 14: redemptionPeriodIndex          (uint48, internal)
  Slot 15: redemptionPeriodBurned         (uint256, internal)
```

### Mapping Slot Computation
For `pendingRedemptions[addr]` (base slot 7):
```solidity
bytes32 slot = keccak256(abi.encode(addr, uint256(7)));
// slot+0: ethValueOwed (uint256)
// slot+1: burnieOwed (uint256)
// slot+2: periodIndex (uint48, packed in first 6 bytes)
```

For `redemptionPeriods[periodIdx]` (base slot 8):
```solidity
bytes32 slot = keccak256(abi.encode(uint256(periodIdx), uint256(8)));
// Single slot: roll (uint16) at offset 0, flipDay (uint48) at offset 2
```

### Anti-Patterns to Avoid
- **Testing against unfixed code:** The 3 HIGH findings (CP-08, CP-06, Seam-1) and 1 MEDIUM (CP-07) must be fixed before invariant tests are expected to pass. Testing against known-buggy code wastes fuzzer cycles on expected failures.
- **Single-actor handler:** Redemption involves cross-period stacking guards (`UnresolvedClaim`) and per-address claim tracking. Must use multi-actor pattern (existing pattern: 5-10 actors).
- **Skipping time warp:** The gambling burn lifecycle spans multiple days. The handler must `vm.warp` across day boundaries and trigger VRF fulfillment to drive resolution. Without time warps, the fuzzer will never explore post-resolution states.
- **fail_on_revert = true:** The existing config has `fail_on_revert = false` (correct). Many handler calls will legitimately revert (burn during rngLocked, claim when no pending, etc.). Reverting calls should be swallowed with try/catch.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Protocol deployment | Custom deploy script | `DeployProtocol.sol` (existing) | 28 contracts with nonce-dependent address prediction; already working |
| VRF mock fulfillment | Custom VRF stub | `VRFHandler.sol` (existing) | Handles request tracking, fulfillment, timeout warp |
| Storage slot calculation | Manual hex math | `forge inspect StakedDegenerusStonk storage-layout` | Verified output; copy slots as constants |
| Actor management | Ad-hoc address creation | `useActor(uint256 seed)` modifier pattern (existing) | Standard project pattern with `bound(seed, 0, actors.length - 1)` |
| sDGNRS acquisition for actors | Direct mint hack | `sdgnrs.transferFromPool(Pool.Reward, actor, amount)` via `vm.prank(game)` | Game contract has permission to distribute from pools; actors need sDGNRS to burn |

## Common Pitfalls

### Pitfall 1: Actors Don't Have sDGNRS to Burn
**What goes wrong:** Handler tries to call `sdgnrs.burn(amount)` but actors start with 0 sDGNRS. All burns revert with `Insufficient()`.
**Why it happens:** sDGNRS is soulbound (no `transfer` function). Actors can only receive sDGNRS from reward pool distributions (game-authorized) or by wrapping DGNRS.
**How to avoid:** In handler constructor or a setup action, use `vm.prank(address(game))` to call `sdgnrs.transferFromPool(Pool.Reward, actor, amount)` for each actor. The Reward pool starts with a large allocation.
**Warning signs:** All `ghost_burnCount` values remain 0 after test run. `show_metrics = true` reveals 100% revert rate on burn calls.

### Pitfall 2: Period Never Resolves
**What goes wrong:** Burns succeed but claims always revert with `NotResolved()`. Invariants INV-01, INV-02, INV-07 are never actually tested in the claim path.
**Why it happens:** Resolution requires: (1) a VRF request to be pending, (2) VRF fulfillment with a valid random word, (3) `advanceGame()` to process the next day via `rngGate()`, which calls `resolveRedemptionPeriod()`. Without explicit time warps + VRF fulfillment + advance, the period stays unresolved.
**How to avoid:** The handler must have an `action_advanceDay` function that: warps time by >= 1 day, calls `advanceGame()`, fulfills VRF if pending, calls `advanceGame()` again. This must be a separate handler action so the fuzzer interleaves it with burns and claims.
**Warning signs:** `ghost_periodsResolved == 0` after test run.

### Pitfall 3: Coinflip Never Resolves (FlipNotResolved)
**What goes wrong:** Period resolves (roll != 0), but claims revert with `FlipNotResolved()`. The coinflip for `flipDay` was never processed.
**Why it happens:** `resolveRedemptionPeriod` sets `flipDay = day + 1`. The coinflip for `flipDay` is resolved by `processCoinflipPayouts(epoch=flipDay)`, which runs during the NEXT day's `advanceGame`. The handler must advance TWO days after a burn: one to resolve the period, one to resolve the coinflip.
**How to avoid:** `action_advanceDay` should be callable multiple times by the fuzzer. After a burn on day N, two advance calls (day N+1 for period, day N+2 for coinflip) are needed before claim succeeds.
**Warning signs:** `ghost_claimCount == 0` despite `ghost_periodsResolved > 0`.

### Pitfall 4: Compilation Blocked by Unrelated Test
**What goes wrong:** `forge test` fails with `Undeclared identifier MID_DAY_SWAP_THRESHOLD` in `test/fuzz/QueueDoubleBuffer.t.sol:79`.
**Why it happens:** An unrelated test file references a constant that was removed or renamed. Foundry compiles all files in the `test/` directory.
**How to avoid:** Fix or comment out the offending line in `QueueDoubleBuffer.t.sol` before running any tests. Alternatively, use `--no-match-path` if supported by the specific `forge test` version.
**Warning signs:** `forge build` fails even before test execution.

### Pitfall 5: Rounding Dust Causes Invariant Failure
**What goes wrong:** INV-01 (ETH solvency) or INV-07 (aggregate tracking) fails by a few wei due to integer division truncation.
**Why it happens:** Phase 44 proved rounding dust is always positive (contract retains excess), bounded at O(N * 99) wei per period at the claim phase. The invariant assertion must account for this.
**How to avoid:** Use `assertGe` (greater-or-equal) instead of `assertEq` for solvency checks. For INV-07, allow a bounded delta: `assertLe(dust, 99 * ghost_claimantCount)`.
**Warning signs:** Invariant fails with tiny differences (< 1000 wei) in high-claimant scenarios.

## Code Examples

### RedemptionHandler Skeleton
```solidity
// Source: Project convention from existing handlers
contract RedemptionHandler is Test {
    StakedDegenerusStonk public sdgnrs;
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // Ghost variables
    uint256 public ghost_totalBurned;
    uint256 public ghost_totalEthSegregated;
    uint256 public ghost_totalEthClaimed;
    uint256 public ghost_periodsResolved;
    uint256 public ghost_claimCount;
    uint256 public ghost_lastPeriodIndex;
    uint256 public ghost_periodIndexDecreased;
    uint256 public ghost_rollOutOfBounds;

    // Call counters
    uint256 public calls_burn;
    uint256 public calls_advanceDay;
    uint256 public calls_claim;

    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(StakedDegenerusStonk sdgnrs_, DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        sdgnrs = sdgnrs_;
        game = game_;
        vrf = vrf_;
        // Create actors and give them sDGNRS from the Reward pool
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xB0000 + i));
            actors.push(actor);
            vm.deal(actor, 10 ether);
            // Distribute sDGNRS from reward pool
            vm.prank(address(game));
            sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, actor, 1_000_000 ether);
        }
    }

    function action_burn(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        calls_burn++;
        if (game.gameOver() || game.rngLocked()) return;
        uint256 bal = sdgnrs.balanceOf(currentActor);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(currentActor);
        try sdgnrs.burn(amount) {
            ghost_totalBurned += amount;
            // Track ETH segregated via event or storage read
        } catch {}
    }

    function action_advanceDay(uint256 randomWord) external {
        calls_advanceDay++;
        if (game.gameOver()) return;
        vm.warp(block.timestamp + 1 days);
        try game.advanceGame() {} catch {}
        // Fulfill VRF if pending
        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                try vrf.fulfillRandomWords(reqId, randomWord) {} catch {}
            }
        }
        try game.advanceGame() {} catch {}
        // Check period resolution and track roll bounds
        _checkResolvedPeriods();
    }

    function action_claim(uint256 actorSeed) external useActor(actorSeed) {
        calls_claim++;
        uint256 balBefore = currentActor.balance;
        vm.prank(currentActor);
        try sdgnrs.claimRedemption() {
            ghost_claimCount++;
            ghost_totalEthClaimed += currentActor.balance - balBefore;
        } catch {}
    }
}
```

### Invariant Test Contract Skeleton
```solidity
// Source: Project convention from existing invariant tests
contract RedemptionInvariants is DeployProtocol {
    RedemptionHandler public handler;
    VRFHandler public vrfHandler;

    function setUp() public {
        _deployProtocol();
        handler = new RedemptionHandler(sdgnrs, game, mockVRF, 5);
        vrfHandler = new VRFHandler(mockVRF, game);
        targetContract(address(handler));
        targetContract(address(vrfHandler));
    }

    // INV-01: Segregated ETH never exceeds contract balance
    function invariant_ethSegregationSolvency() public view {
        uint256 segregated = sdgnrs.pendingRedemptionEthValue();
        uint256 ethBal = address(sdgnrs).balance;
        // stETH + claimable are additional backing
        assertGe(
            ethBal, // conservative: just ETH balance
            segregated, // Note: this is simplified; full check includes stETH + claimable
            "INV-01: segregated ETH exceeds contract ETH balance"
        );
    }

    // INV-03: Period index monotonically increases
    function invariant_periodIndexMonotonic() public view {
        assertEq(
            handler.ghost_periodIndexDecreased(),
            0,
            "INV-03: period index decreased"
        );
    }

    // INV-06: Roll bounds always [25, 175]
    function invariant_rollBounds() public view {
        assertEq(
            handler.ghost_rollOutOfBounds(),
            0,
            "INV-06: roll outside [25, 175]"
        );
    }
}
```

### Reading Internal Storage Variables
```solidity
// Source: forge inspect StakedDegenerusStonk storage-layout (verified 2026-03-21)
uint256 constant SLOT_PENDING_ETH_VALUE = 9;   // public getter exists
uint256 constant SLOT_PENDING_BURNIE = 10;      // internal -- needs vm.load
uint256 constant SLOT_PENDING_ETH_BASE = 11;    // internal -- needs vm.load
uint256 constant SLOT_PENDING_BURNIE_BASE = 12; // internal -- needs vm.load
uint256 constant SLOT_SUPPLY_SNAPSHOT = 13;      // internal -- needs vm.load
uint256 constant SLOT_PERIOD_INDEX = 14;         // internal -- needs vm.load (uint48)
uint256 constant SLOT_PERIOD_BURNED = 15;        // internal -- needs vm.load

function _readInternalSlot(address target, uint256 slot) internal view returns (uint256) {
    return uint256(vm.load(target, bytes32(slot)));
}

function _readPendingBurnie() internal view returns (uint256) {
    return _readInternalSlot(address(sdgnrs), SLOT_PENDING_BURNIE);
}
```

## Prerequisite: Phase 44 Code Fixes

The invariant tests depend on the Phase 44 code fixes being applied. The current code has 3 HIGH and 1 MEDIUM bugs that would cause certain invariants to fail. These must be resolved before writing tests:

| Finding | Fix Summary | Invariants Affected |
|---------|-------------|---------------------|
| CP-08 (HIGH) | Add `- pendingRedemptionEthValue` and `- pendingRedemptionBurnie` to `_deterministicBurnFrom` lines 477, 482 | INV-01 (solvency), INV-07 (aggregate tracking) |
| CP-06 (HIGH) | Add `resolveRedemptionPeriod` call to `_gameOverEntropy` | INV-03 (monotonicity at game-over), INV-06 (roll bounds) |
| Seam-1 (HIGH) | Revert `DGNRS.burn()` during active game (or equivalent fix) | INV-02 (no double-claim -- orphaned claim under contract address) |
| CP-07 (MEDIUM) | Split claim to allow ETH-only when flip unresolved (or emergency resolution) | INV-01 (solvency at game-over boundary) |

**Recommendation:** Apply fixes as Wave 0 of Phase 45 planning, then write tests against the corrected code.

## Compilation Blocker

`test/fuzz/QueueDoubleBuffer.t.sol:79` references `MID_DAY_SWAP_THRESHOLD` which is undeclared. This blocks `forge build` for the entire `test/` tree. Must be fixed or the file excluded before any Phase 45 test can compile. This is a pre-existing issue unrelated to Phase 45.

**Recommended fix:** Comment out or fix the offending line in `QueueDoubleBuffer.t.sol` as the first task.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No redemption invariant tests | Full 7-invariant suite with handler | Phase 45 (new) | Regression protection for all Phase 44 findings |
| Test only single-step operations | Multi-phase lifecycle handler (burn/resolve/claim) | Phase 45 (new) | Covers adversarial state sequences across day boundaries |
| Manual rounding analysis | Automated dust bounding via ghost variables | Phase 45 (new) | Continuous verification of O(N * 99) wei bound |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry v1.0+ (forge test) |
| Config file | `foundry.toml` [invariant] section |
| Quick run command | `forge test --match-contract RedemptionInvariants -v` |
| Full suite command | `forge test --match-path "test/fuzz/invariant/*" -v` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INV-01 | Segregated ETH <= contract balance | invariant | `forge test --match-test invariant_ethSegregationSolvency -v` | Wave 0 |
| INV-02 | No double-claim (claim deleted before payout) | invariant | `forge test --match-test invariant_noDoubleClaim -v` | Wave 0 |
| INV-03 | Period index monotonically increases | invariant | `forge test --match-test invariant_periodIndexMonotonic -v` | Wave 0 |
| INV-04 | totalSupply consistent after burn/claim sequences | invariant | `forge test --match-test invariant_supplyConsistency -v` | Wave 0 |
| INV-05 | 50% cap correctly enforced per period | invariant | `forge test --match-test invariant_fiftyPercentCap -v` | Wave 0 |
| INV-06 | Roll bounds always [25, 175] | invariant | `forge test --match-test invariant_rollBounds -v` | Wave 0 |
| INV-07 | Aggregate claim tracking matches sum of individuals | invariant | `forge test --match-test invariant_aggregateTracking -v` | Wave 0 |

### Sampling Rate
- **Per task commit:** `forge test --match-contract RedemptionInvariants -v` (< 60 sec with 256 runs, depth 128)
- **Per wave merge:** `forge test --match-path "test/fuzz/invariant/*" -v` (all invariant tests)
- **Phase gate:** All 7 invariant tests pass with zero failures at default profile

### Wave 0 Gaps
- [ ] `test/fuzz/handlers/RedemptionHandler.sol` -- handler for burn/resolve/claim lifecycle
- [ ] `test/fuzz/invariant/RedemptionInvariants.inv.t.sol` -- 7 invariant assertions
- [ ] Fix `test/fuzz/QueueDoubleBuffer.t.sol:79` compilation error (blocks all test runs)
- [ ] Apply Phase 44 code fixes (CP-08, CP-06, Seam-1, CP-07) in 4 contract files

## Open Questions

1. **Exact CP-07 fix design**
   - What we know: The current code blocks ETH claim when coinflip is unresolved. Phase 44 recommended splitting into ETH-only and BURNIE-optional paths.
   - What's unclear: Which fix variant the protocol team has chosen.
   - Recommendation: Implement Option A (split claim) as the simplest safe fix. If the team prefers a different approach, the invariant tests may need minor adjustment to the claim handler.

2. **sDGNRS distribution for test actors**
   - What we know: sDGNRS is soulbound (no transfer). Actors need balance to burn. The Reward pool has a large allocation.
   - What's unclear: Whether `transferFromPool` via `vm.prank(game)` will succeed in the test environment without additional game state setup (e.g., pool initialization).
   - Recommendation: Verify in the first implementation task that `_deployProtocol()` initializes pool balances correctly. The constructor mints `INITIAL_SUPPLY * REWARD_POOL_BPS / BPS_DENOM` to the reward pool, which should be sufficient.

3. **Depth of coverage for game-over boundary**
   - What we know: CP-06 and CP-07 manifest at the game-over boundary. Testing this requires driving the game to level 45+ (liveness guard) or triggering game-over via VRF stall.
   - What's unclear: Whether 128-depth fuzzer runs can reliably reach game-over.
   - Recommendation: The handler should include an `action_triggerGameOver` that warps past the liveness timeout, making game-over reachable in a single action. This ensures the fuzzer explores post-game-over states without needing extreme depth.

## Sources

### Primary (HIGH confidence)
- Direct code analysis: `contracts/StakedDegenerusStonk.sol` (797 lines) -- all state variables, burn/resolve/claim functions
- Direct code analysis: `contracts/modules/DegenerusGameAdvanceModule.sol:770-780` -- roll computation formula
- `forge inspect StakedDegenerusStonk storage-layout` -- verified storage slots 0-15
- Existing test infrastructure: `test/fuzz/helpers/DeployProtocol.sol`, `test/fuzz/helpers/VRFHandler.sol`, `test/fuzz/handlers/GameHandler.sol`, `test/fuzz/handlers/CompositionHandler.sol`
- Existing invariant tests: `test/fuzz/invariant/EthSolvency.inv.t.sol`, `test/fuzz/invariant/CoinSupply.inv.t.sol`, `test/fuzz/invariant/Composition.inv.t.sol`
- Phase 44 deliverables: `44-01-finding-verdicts.md`, `44-02-lifecycle-correctness.md`, `44-03-accounting-solvency-interaction.md`
- `foundry.toml` -- [invariant] config: runs=256, depth=128, fail_on_revert=false, show_metrics=true

### Secondary (MEDIUM confidence)
- [Foundry invariant testing docs](https://getfoundry.sh/forge/invariant-testing) -- handler pattern, targetContract, ghost variables
- Phase 44 rounding analysis: dust bounded at O(N * 99) wei per period at claim phase, always positive direction

### Tertiary (LOW confidence)
None. All findings are code-derived from direct source analysis.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- project already has mature Foundry invariant test infrastructure
- Architecture: HIGH -- patterns directly copied from 11 existing test/handler files
- Storage slots: HIGH -- verified via `forge inspect` output
- Pitfalls: HIGH -- derived from Phase 44 lifecycle analysis (specific day-boundary and VRF dependencies)
- Invariant formulas: HIGH -- each maps directly to a Phase 44 proven property with exact line references

**Research date:** 2026-03-21
**Valid until:** Indefinite (tied to current code state, not external library versions)
