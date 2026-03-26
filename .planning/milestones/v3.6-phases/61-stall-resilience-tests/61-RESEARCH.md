# Phase 61: Stall Resilience Tests - Research

**Researched:** 2026-03-22
**Domain:** Foundry integration testing -- VRF stall, coordinator swap, gap backfill, coinflip/lootbox resolution
**Confidence:** HIGH

## Summary

Phase 61 requires Foundry tests that prove the full VRF stall-to-recovery cycle works end-to-end. The implementation is already complete (Phases 59-60) -- this phase validates it. Three requirements must be covered: TEST-01 (full stall->swap->resume cycle with gap day backfill), TEST-02 (coinflip claims across gap days), and TEST-03 (lootbox opens after orphaned index backfill).

The project already has a mature Foundry test infrastructure: `DeployProtocol.sol` deploys all 28 contracts (5 mocks + 23 protocol) with correct address ordering, `VRFHandler.sol` wraps the mock VRF for test convenience, and `VRFLifecycle.t.sol` demonstrates the pattern for VRF request/fulfill/advance cycles. The tests must be placed in `test/fuzz/` (the Foundry test root per `foundry.toml`), inherit `DeployProtocol`, and follow the existing pattern of `_deployProtocol()` in setUp. The build requires the `make invariant-test` pipeline (patch ContractAddresses -> forge build -> forge test -> restore).

The key testing challenge is orchestrating the multi-step stall scenario: (1) advance the game to establish a baseline day, (2) warp time past multiple day boundaries without fulfilling VRF (simulating the stall), (3) deploy a new MockVRFCoordinator and call `updateVrfCoordinatorAndSub` via the admin address, (4) trigger `advanceGame` + VRF fulfill on the new coordinator to resume, (5) verify that gap days have backfilled RNG words and that coinflip/lootbox resolution works for those gap days.

**Primary recommendation:** Create a single test file `StallResilience.t.sol` in `test/fuzz/` with three focused test functions mapping 1:1 to TEST-01, TEST-02, TEST-03. Each test builds on the same stall scenario setup but verifies different aspects.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | Foundry test simulating full stall->swap->resume cycle with gap day backfill | DeployProtocol base + MockVRFCoordinator swap + advanceGame resume; verify rngWordByDay[gapDay] != 0 and DailyRngApplied events with nudges=0 |
| TEST-02 | Test that coinflip claims work across gap days | Place coinflip stakes via purchase() on gap days, verify coinflipDayResult populated after backfill, verify claims succeed via getCoinflipDayResult |
| TEST-03 | Test that lootbox opens work after orphaned index backfill | Create lootbox via purchase() with lootbox amount, trigger lootbox RNG request, stall VRF, swap coordinator (which backfills orphaned index), verify lootboxRngWord(index) != 0 and openLootBox does not revert |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Solidity | 0.8.34 | Test contract language | Matches project solc_version in foundry.toml |
| Foundry (forge) | latest | Test framework + runner | Project standard, configured in foundry.toml |
| forge-std | latest | Test assertions, vm cheatcodes | Already in lib/forge-std |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DeployProtocol.sol | (internal) | Full protocol deployment | Base contract for all integration tests |
| MockVRFCoordinator.sol | (internal) | VRF request/fulfill simulation | Controlling VRF responses in tests |
| VRFHandler.sol | (internal) | VRF convenience wrapper | Optional -- direct MockVRF calls may be clearer for stall tests |

No new dependencies needed. All test infrastructure exists.

**Build command:** `make invariant-test` (patches ContractAddresses for Foundry deterministic addresses, builds, tests, restores)

**Targeted test command:** After patching, `forge test --match-contract StallResilience -vvv`

## Architecture Patterns

### Recommended Project Structure
```
test/fuzz/
  StallResilience.t.sol     # NEW -- Phase 61 tests (TEST-01, TEST-02, TEST-03)
  helpers/
    DeployProtocol.sol       # EXISTING -- full protocol deployment base
    VRFHandler.sol           # EXISTING -- VRF convenience wrapper
```

### Pattern 1: Stall Scenario Setup (shared by all three tests)

**What:** A reusable internal function that establishes the stall scenario: advance game through day 1, create VRF request on day 2, warp past multiple day boundaries without fulfilling (creating gap days), then swap coordinator.

**When to use:** All three test functions need this same preamble.

**Key timing model:**
- Deploy at `vm.warp(86400)` (handled by DeployProtocol)
- Day boundary resets at 22:57 UTC = 82620 seconds offset from midnight
- Day 1 starts at deploy. `currentDayIndex = ((ts - 82620) / 86400) - DEPLOY_DAY_BOUNDARY + 1`
- For deploy at ts=86400: `(86400 - 82620) / 86400 = 0`, day = `0 - 0 + 1 = 1`
- Next day boundary: need to cross `(DEPLOY_DAY_BOUNDARY + 1) * 86400 + 82620 = 1 * 86400 + 82620 = 169020`
- Simplification: `vm.warp(block.timestamp + 1 days)` reliably advances one day

**Example setup flow:**
```solidity
// Step 1: Day 1 -- initial advanceGame triggers VRF request
game.advanceGame();
assertTrue(game.rngLocked(), "Day 1: VRF request sent");

// Step 2: Fulfill VRF for day 1
uint256 reqId1 = mockVRF.lastRequestId();
mockVRF.fulfillRandomWords(reqId1, 0xDEADBEEF);

// Step 3: Process day 1 (advanceGame consumes the VRF word)
game.advanceGame();
assertFalse(game.rngLocked(), "Day 1: processed");

// Step 4: Warp to day 2, trigger VRF request
vm.warp(block.timestamp + 1 days);
game.advanceGame();
assertTrue(game.rngLocked(), "Day 2: VRF request sent");

// Step 5: STALL -- warp past 3 day boundaries WITHOUT fulfilling VRF
// This creates gap days (days 3, 4, 5 unfulfilled)
vm.warp(block.timestamp + 3 days);

// Step 6: Coordinator swap -- deploy new mock, call updateVrfCoordinatorAndSub
MockVRFCoordinator newVRF = new MockVRFCoordinator();
uint256 newSubId = newVRF.createSubscription();
newVRF.addConsumer(newSubId, address(game));
vm.prank(ContractAddresses.ADMIN);
game.updateVrfCoordinatorAndSub(
    address(newVRF),
    newSubId,
    bytes32(uint256(1)) // arbitrary keyHash
);

// Step 7: Resume -- advanceGame on day 5
game.advanceGame(); // triggers new VRF request on new coordinator

// Step 8: Fulfill new VRF
uint256 reqId2 = newVRF.lastRequestId();
newVRF.fulfillRandomWords(reqId2, 0xCAFEBABE);

// Step 9: advanceGame processes the VRF word, triggering _backfillGapDays
game.advanceGame();
```

### Pattern 2: Coordinator Swap via Admin Prank

**What:** The `updateVrfCoordinatorAndSub` function on DegenerusGame requires `msg.sender == ContractAddresses.ADMIN`. In production this goes through DegenerusAdmin governance. In tests, use `vm.prank(ContractAddresses.ADMIN)` to call it directly on the game contract.

**Critical detail:** The game contract's `updateVrfCoordinatorAndSub` is a delegatecall wrapper. The `msg.sender != ContractAddresses.ADMIN` check happens inside the module. The call must go through `game.updateVrfCoordinatorAndSub(...)` (not the module directly), and the sender must be the ADMIN address.

```solidity
vm.prank(ContractAddresses.ADMIN);
game.updateVrfCoordinatorAndSub(
    address(newVRF),
    newSubId,
    newKeyHash
);
```

### Pattern 3: Coinflip Stake Placement for Gap Day Testing

**What:** To test TEST-02, coinflip stakes must exist on gap days. Stakes are placed via `purchase()` which calls `_addDailyFlip`, which places the stake at `_targetFlipDay() = currentDayView() + 1`.

**Key insight:** If the current day is N, a purchase places the coinflip stake on day N+1. To have stakes on gap days 3 and 4, purchases must happen on days 2 and 3 respectively. But during a stall, `advanceGame` cannot be called (VRF pending), so the game's `dailyIdx` is frozen. However, `currentDayView()` returns the timestamp-based day, not `dailyIdx`. So purchases made during the stall (after warping time) will place stakes on the correct future days.

**Example:**
```solidity
// During stall, warp to day 2 (stake goes to day 3)
vm.warp(/* day 2 timestamp */);
vm.prank(buyer);
game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
// stake is now on day 3 via _targetFlipDay

// Warp to day 3 (stake goes to day 4)
vm.warp(/* day 3 timestamp */);
vm.prank(buyer);
game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
// stake is now on day 4
```

**Note:** Purchase may revert during stall if certain conditions are met (e.g., if RNG is locked, some purchase paths may be blocked). Verify with a try/catch or check if `rngLockedFlag` blocks `purchase()`. The `purchase()` function does NOT check `rngLockedFlag` for the basic mint path -- only `requestLootboxRng()` and `reverseFlip()` check it. So purchases during stall should work.

### Pattern 4: Lootbox RNG Index Orphaning for TEST-03

**What:** To test orphaned index backfill, a lootbox RNG request must be in-flight when the coordinator swaps. The `_requestRng` (daily path) calls `_reserveLootboxRngIndex`, reserving an index. When the coordinator swaps via `updateVrfCoordinatorAndSub`, the orphaned index gets backfilled.

**Setup flow:**
1. Purchase with lootbox amount (creates `lootboxEth[index][buyer]` entry)
2. The daily `advanceGame` + VRF fulfill cycle reserves lootbox indices via `_reserveLootboxRngIndex`
3. Stall the VRF after the request is made but before fulfillment
4. Coordinator swap triggers orphaned index backfill
5. Verify `lootboxRngWord(orphanedIndex) != 0`
6. Verify `openLootBox(buyer, orphanedIndex)` does not revert with RngNotReady

**Key challenge:** The lootbox index is reserved during `_requestRng` (line 1223 via `_finalizeRngRequest`), which is called from `rngGate` or `_requestRng`. The index assigned to the daily request is `lootboxRngIndex` at the time of the request. To know which index was orphaned, read `game.lootboxRngIndexView()` before the swap.

### Anti-Patterns to Avoid

- **Testing via module directly:** All test calls must go through `DegenerusGame` (the proxy), not `DegenerusGameAdvanceModule` directly. The module executes via delegatecall, so direct calls would use wrong storage context.

- **Forgetting ContractAddresses patching:** Foundry tests MUST be run via `make invariant-test` or after manually running `node scripts/lib/patchForFoundry.js`. Without patching, `ContractAddresses.sol` has production addresses that don't match the test deployer's CREATE addresses, causing all cross-contract calls to fail.

- **Using stale VRF request IDs:** After coordinator swap, `vrfRequestId` is cleared to 0. New VRF requests on the new coordinator produce new request IDs. Tests must use `newVRF.lastRequestId()` (not `mockVRF.lastRequestId()`) after the swap.

- **Expecting advanceGame to succeed immediately after swap:** After coordinator swap, `rngLockedFlag = false`, `vrfRequestId = 0`, `rngRequestTime = 0`. The next `advanceGame()` call will enter `rngGate`, find no VRF word ready (`rngWordCurrent == 0`), and call `_requestRng` to send a new VRF request. This request must be fulfilled before the next `advanceGame()` can process the day.

- **Not advancing game enough times:** The game may require multiple `advanceGame()` calls to process tickets, swap slots, etc. The VRFLifecycle test pattern uses a loop of up to 50 calls to drive through all stages.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Protocol deployment | Manual contract creation | `DeployProtocol._deployProtocol()` | 28 contracts with specific ordering; already proven |
| VRF mock | Custom mock | `MockVRFCoordinator.sol` | Has fulfillRandomWords, lastRequestId, pending tracking |
| Time advancement | Manual math | `vm.warp(block.timestamp + N days)` | Foundry cheatcode, deterministic |
| Address impersonation | Deploy admin contract | `vm.prank(ContractAddresses.ADMIN)` | Foundry cheatcode, no deployment needed |
| Event assertions | Manual log parsing | `vm.expectEmit(true, true, true, true)` | Forge-std built-in |

## Common Pitfalls

### Pitfall 1: Day Boundary Alignment
**What goes wrong:** Tests assume `1 days` exactly crosses a day boundary, but the game's day resets at 22:57 UTC (82620 seconds offset), not midnight. If the test's starting timestamp isn't aligned correctly, `vm.warp(block.timestamp + 1 days)` might not actually advance the game day.
**Why it happens:** `DeployProtocol._deployProtocol()` calls `vm.warp(86400)`. At ts=86400: `(86400 - 82620) / 86400 = 0`, day = 1. At ts=86400+86400=172800: `(172800 - 82620) / 86400 = 1`, day = 2. So adding exactly 86400 seconds does advance the day by 1. This works because DEPLOY_DAY_BOUNDARY = 0.
**How to avoid:** Using `vm.warp(block.timestamp + 1 days)` is safe given the deploy alignment. But always verify with `game.currentDayView()` after warping.
**Warning signs:** `advanceGame()` reverting with "NotTimeYet" or day index not advancing.

### Pitfall 2: VRF Request During Stall Days
**What goes wrong:** Calling `advanceGame()` during a stall (VRF request pending, not fulfilled) triggers the 12-hour timeout retry path instead of reverting. If the warp exceeds 12 hours from the original request, `advanceGame()` will send a new VRF request instead of reverting with RngNotReady.
**Why it happens:** `rngGate` checks `elapsed >= 12 hours` and retries. If you warp 3 days (72 hours), the retry triggers immediately.
**How to avoid:** Understand that during the stall, `advanceGame()` may succeed (by retrying the VRF request) rather than reverting. The stall scenario means the VRF coordinator is unresponsive, so even retried requests won't be fulfilled. In tests, simply don't call `advanceGame()` during the stall period, OR if you do call it, don't fulfill the retry request either.
**Warning signs:** Multiple VRF requests accumulating on the old coordinator.

### Pitfall 3: Coinflip Claim Window After Backfill
**What goes wrong:** After backfill, `flipsClaimableDay` jumps from the pre-stall day to the last gap day, then to the current day. Claims iterate from `lastClaim` to `flipsClaimableDay`. If `lastClaim` is 0 or very old, the claim window (`COIN_CLAIM_DAYS`, checked via a cap) may not cover all gap days.
**Why it happens:** The claim logic has a `remaining` counter capped at `COIN_CLAIM_DAYS` (or `windowDays` for auto-rebuy-off). If there are more gap days than this cap, some stakes may not be reachable.
**How to avoid:** Keep the test gap small (2-3 days). Real scenarios with short gaps will always be within the claim window. Testing edge cases of very long gaps is out of scope for this phase.
**Warning signs:** Claims returning 0 when stakes exist on gap days.

### Pitfall 4: Purchase During RNG Lock
**What goes wrong:** Purchases may behave differently when `rngLockedFlag` is true (daily RNG pending). The purchase function itself does not revert on RNG lock, but some post-purchase logic (like ticket processing) may be affected.
**Why it happens:** The `purchase()` -> `_processPaymentAndMint()` path does NOT check `rngLockedFlag`. However, `_addDailyFlip` in BurnieCoinflip also does not check it. The lock only blocks `reverseFlip()` and `requestLootboxRng()`.
**How to avoid:** Purchases during the stall period should work fine for placing coinflip stakes. Verify in the test.
**Warning signs:** Purchase reverting unexpectedly during stall.

### Pitfall 5: Admin Address in Foundry Tests
**What goes wrong:** `ContractAddresses.ADMIN` in Foundry tests is the DegenerusAdmin contract address, which is deployed at a specific nonce-derived address. Using the wrong address for `vm.prank` will cause the `updateVrfCoordinatorAndSub` call to revert with `E()`.
**Why it happens:** The admin address is `address(admin)` (the deployed DegenerusAdmin contract), NOT the test contract address or `msg.sender`.
**How to avoid:** Use `address(admin)` (the DegenerusAdmin instance from DeployProtocol) or `ContractAddresses.ADMIN` for the prank. Both resolve to the same address after patching.
**Warning signs:** `E()` revert on `updateVrfCoordinatorAndSub`.

## Code Examples

### Verified: DeployProtocol setUp pattern (from VRFLifecycle.t.sol)
```solidity
// Source: test/fuzz/VRFLifecycle.t.sol
contract VRFLifecycle is DeployProtocol {
    function setUp() public {
        _deployProtocol();
    }
    // mockVRF, game, admin, coinflip, etc. are all available
}
```

### Verified: VRF request+fulfill+process cycle (from VRFLifecycle.t.sol)
```solidity
// Source: test/fuzz/VRFLifecycle.t.sol:42-79
game.advanceGame(); // triggers VRF request
uint256 reqId = mockVRF.lastRequestId();
mockVRF.fulfillRandomWords(reqId, 12345678901234567890);
// Drive advances until RNG unlocks
for (uint256 i = 0; i < 30; i++) {
    if (!game.rngLocked()) break;
    game.advanceGame();
}
```

### Verified: Purchase pattern for coinflip stake (from VRFLifecycle.t.sol)
```solidity
// Source: test/fuzz/VRFLifecycle.t.sol:46-57
address buyer = makeAddr("buyer");
vm.deal(buyer, 100 ether);
vm.prank(buyer);
game.purchase{value: 0.01 ether}(
    buyer,
    400,       // 1 full ticket (400 units)
    0,         // no lootbox
    bytes32(0),
    MintPaymentKind.DirectEth
);
```

### Verified: Purchase with lootbox amount (from VRFLifecycle.t.sol)
```solidity
// Source: test/fuzz/VRFLifecycle.t.sol:93-102
vm.prank(buyer);
game.purchase{value: 1.01 ether}(
    buyer,
    400,       // 1 full ticket
    1 ether,   // lootbox amount
    bytes32(0),
    MintPaymentKind.DirectEth
);
```

### Verified: rngWordForDay accessor (from DegenerusGame.sol:2258)
```solidity
// Source: contracts/DegenerusGame.sol:2258-2260
function rngWordForDay(uint48 day) external view returns (uint256) {
    return rngWordByDay[day];
}
```

### Verified: lootboxRngWord accessor (from DegenerusGame.sol:2176)
```solidity
// Source: contracts/DegenerusGame.sol:2176-2180
function lootboxRngWord(uint48 lootboxIndex) external view returns (uint256 word) {
    return lootboxRngWordByIndex[lootboxIndex];
}
```

### Verified: getCoinflipDayResult accessor (from BurnieCoinflip.sol:357)
```solidity
// Source: contracts/BurnieCoinflip.sol:357-360
function getCoinflipDayResult(uint48 day) external view returns (uint16 rewardPercent, bool win) {
    CoinflipDayResult memory result = coinflipDayResult[day];
    return (result.rewardPercent, result.win);
}
```

### Verified: updateVrfCoordinatorAndSub with orphaned index backfill (current code)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1334-1379
// Captures outgoingRequestId BEFORE clearing vrfRequestId
// Backfills orphaned lootbox index via keccak256(lastLootboxRngWord, orphanedIndex)
// Clears midDayTicketRngPending
// Emits LootboxRngApplied for orphaned index
```

### Verified: _backfillGapDays (current code)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1459-1473
// Loops startDay..endDay (exclusive), derives keccak256(vrfWord, gapDay)
// Calls coinflip.processCoinflipPayouts per gap day
// Emits DailyRngApplied with nudges=0
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) with forge-std |
| Config file | `foundry.toml` (test root: `test/fuzz/`) |
| Quick run command | `make invariant-build && forge test --match-contract StallResilience -vvv` |
| Full suite command | `make invariant-test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 | Full stall->swap->resume cycle with gap day backfill | integration | `forge test --match-test test_stallSwapResume -vvv` | No -- Wave 0 |
| TEST-02 | Coinflip claims across gap days | integration | `forge test --match-test test_coinflipClaimsAcrossGapDays -vvv` | No -- Wave 0 |
| TEST-03 | Lootbox opens after orphaned index backfill | integration | `forge test --match-test test_lootboxOpenAfterOrphanedIndexBackfill -vvv` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `forge test --match-contract StallResilience -vvv`
- **Per wave merge:** `make invariant-test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/fuzz/StallResilience.t.sol` -- covers TEST-01, TEST-02, TEST-03

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No VRF stall testing | Integration tests proving stall->swap->resume | v3.6 (this phase) | C4A wardens see tested recovery path |
| Hardhat-only VRF tests | Foundry integration tests for VRF lifecycle | Phase 14 (v3.3) | Faster execution, better cheatcode support |

## Open Questions

1. **Purchase viability during stall**
   - What we know: `purchase()` does not check `rngLockedFlag`. Coinflip stakes should be placeable during a stall.
   - What's unclear: Whether any downstream effect (ticket queue processing, slot swapping) could cause revert during a stall.
   - Recommendation: Try the purchase in the test with try/catch first. If it reverts, investigate. Most likely it works because purchases are independent of VRF state.

2. **Lootbox index assignment timing**
   - What we know: `_reserveLootboxRngIndex(id)` is called from `_finalizeRngRequest` (inside `_requestRng`), which runs during `advanceGame()`. The index is `lootboxRngIndex` at call time, incremented after.
   - What's unclear: Whether a basic purchase with lootbox amount causes an immediate lootbox RNG request, or if the request is batched with the daily VRF request. The daily `_requestRng` call always reserves a lootbox index. A lootbox purchase during the stall would accumulate `lootboxRngPendingEth` but not trigger a request (since `requestLootboxRng()` requires `rngRequestTime == 0` and `rngWordByDay[currentDay] != 0`).
   - Recommendation: The daily VRF request always reserves a lootbox index via `_reserveLootboxRngIndex`. The orphaned index in a stall scenario is the one reserved by the stalled daily request. Purchases add to `lootboxEth[index][buyer]` at the current `lootboxRngIndex` value (which advances only when a request is made). To test orphaned lootbox opens, purchase lootboxes BEFORE the stall begins (so their entries are at the index that will be orphaned).

3. **Multi-call advanceGame requirement**
   - What we know: After VRF fulfillment, `advanceGame()` may need to be called multiple times to fully process the day (ticket batching, jackpot phases, etc.).
   - Recommendation: Use the VRFLifecycle pattern: loop up to 50 `advanceGame()` calls, breaking when `rngLocked()` is false. This handles all edge cases.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- Full read of `_backfillGapDays` (lines 1459-1473), `updateVrfCoordinatorAndSub` (lines 1334-1379), `rngGate` (lines 765-831), `_requestRng` (lines 1211-1224), `rawFulfillRandomWords` (lines 1425-1446), `_reserveLootboxRngIndex` (lines 1409-1416)
- `contracts/DegenerusGame.sol` -- `updateVrfCoordinatorAndSub` delegatecall wrapper (lines 1944-1962), public accessors: `rngWordForDay` (2258), `lootboxRngWord` (2176), `rngLocked` (2272), `currentDayView` (506)
- `contracts/BurnieCoinflip.sol` -- `processCoinflipPayouts` (lines 778-857), `getCoinflipDayResult` (lines 357-360), `_addDailyFlip` and `_targetFlipDay` (lines 608-662, 1060-1062), claim skip logic (lines 482-486)
- `contracts/modules/DegenerusGameLootboxModule.sol` -- `openLootBox` (lines 542-614), RngNotReady check (lines 549-550)
- `contracts/mocks/MockVRFCoordinator.sol` -- Full read, `fulfillRandomWords`, `lastRequestId`, `createSubscription`, `addConsumer`
- `contracts/DegenerusAdmin.sol` -- Constructor VRF wiring (lines 331-349), `_executeSwap` (lines 566-627)
- `contracts/libraries/GameTimeLib.sol` -- Day index calculation (lines 21-34)
- `test/fuzz/VRFLifecycle.t.sol` -- Existing VRF test patterns (full file)
- `test/fuzz/helpers/DeployProtocol.sol` -- Full protocol deployment (full file)
- `test/fuzz/helpers/VRFHandler.sol` -- VRF handler pattern (full file)
- `foundry.toml` -- Test root `test/fuzz/`, solc 0.8.34, via_ir=true, optimizer_runs=2

### Secondary (MEDIUM confidence)
- `test/fuzz/AdvanceGameRewrite.t.sol` -- Harness pattern for testing internal state (used as style reference)
- `Makefile` -- Build pipeline: patch -> forge build -> forge test -> restore

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All infrastructure exists, no new dependencies
- Architecture: HIGH -- All patterns verified against existing tests and contract code
- Pitfalls: HIGH -- Day boundary math verified, VRF lifecycle traced through code, admin access pattern confirmed

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable -- test infrastructure is established, contracts are pre-audit)
