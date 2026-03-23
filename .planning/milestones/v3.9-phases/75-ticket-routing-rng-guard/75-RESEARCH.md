# Phase 75: Ticket Routing + RNG Guard - Research

**Researched:** 2026-03-22
**Domain:** Solidity internal function modification, bitwise key routing, storage-level revert guards
**Confidence:** HIGH

## Summary

Phase 75 modifies the four ticket queue write functions in DegenerusGameStorage.sol to conditionally route far-future tickets (targetLevel > currentLevel + 6) to the new `_tqFarFutureKey` key space established in Phase 74, while preserving the existing `_tqWriteKey` path for near-future tickets. Additionally, `_queueTickets` and `_queueTicketsScaled` gain an rngLocked guard that reverts when writing to the far-future key space during the VRF commitment window, with an exemption for advanceGame-origin writes via the `phaseTransitionActive` sentinel.

The change is concentrated in DegenerusGameStorage.sol, touching four functions: `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`, and implicitly `_queueLootboxTickets` (which delegates to `_queueTicketsScaled`). This is a central fix -- all 11 callers across 7 modules automatically get correct routing without any per-caller changes.

**Primary recommendation:** Add a `level` read and conditional key selection (`_tqFarFutureKey` vs `_tqWriteKey`) to `_queueTickets`, `_queueTicketsScaled`, and `_queueTicketRange`. Add `require(!(isFarFuture && rngLockedFlag && !phaseTransitionActive))` to `_queueTickets` and `_queueTicketsScaled` for the RNG guard.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ROUTE-01 | _queueTickets and _queueTicketsScaled route to _tqFarFutureKey when targetLevel > level + 6 | Key computation change at lines 541/574/633 in DegenerusGameStorage.sol; covers all 11 callers via central fix |
| ROUTE-02 | Near-future tickets (level+0 to level+6) continue routing to _tqWriteKey unchanged | Conditional preserves existing path when targetLevel <= level + 6; no caller code changes |
| ROUTE-03 | _queueTickets reverts for FF key writes when rngLocked, except advanceGame (phaseTransitionActive) | Guard uses phaseTransitionActive sentinel; verified only vault perpetual tickets queue FF during advanceGame |
| RNG-02 | rngLocked guard prevents permissionless far-future writes during commitment window | All permissionless paths (lootbox open, whale purchase, claimWhalePass) pass through _queueTickets/_queueTicketsScaled; guard catches at function level |
</phase_requirements>

## Architecture Patterns

### Existing Functions to Modify

Four functions in DegenerusGameStorage.sol write to the ticket queue. All use `_tqWriteKey(targetLevel)` for key computation:

```
DegenerusGameStorage.sol
  _queueTickets         (line 534)  -- uint24 wk = _tqWriteKey(targetLevel);   [line 541]
  _queueTicketsScaled   (line 567)  -- uint24 wk = _tqWriteKey(targetLevel);   [line 574]
  _queueTicketRange     (line 624)  -- uint24 wk = _tqWriteKey(lvl);           [line 633, in loop]
  _queueLootboxTickets  (line 664)  -- delegates to _queueTicketsScaled        [line 673]
```

### Fix Pattern: Conditional Key Selection

Replace `_tqWriteKey(targetLevel)` with a conditional that reads `level` from storage and routes accordingly:

```solidity
// In _queueTickets and _queueTicketsScaled:
bool isFarFuture = targetLevel > level + 6;
uint24 wk = isFarFuture ? _tqFarFutureKey(targetLevel) : _tqWriteKey(targetLevel);

// In _queueTicketRange (per-iteration):
bool isFarFuture = lvl > level + 6;
uint24 wk = isFarFuture ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
```

### RNG Guard Pattern

The guard prevents permissionless callers from mutating the FF key space during the VRF commitment window:

```solidity
// In _queueTickets (after isFarFuture is computed):
if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
```

**Why `phaseTransitionActive`:** This storage bool is `true` only during the advanceGame flow between `_endPhase()` and `_processPhaseTransition` completion. The only advanceGame-internal caller that produces far-future tickets is `_processPhaseTransition` (vault perpetual tickets at `purchaseLevel + 99`), which runs while `phaseTransitionActive` is `true`. All other advanceGame-internal ticket writes (auto-rebuy from jackpot/endgame/decimator) produce near-future tickets (+1 to +4 levels) that never trigger the FF key.

### Gas Impact Analysis

The routing change adds one SLOAD (reading `level`) per `_queueTickets`/`_queueTicketsScaled` call. This is acceptable because:

1. `level` is in the hot storage path (frequently read by callers before calling these functions)
2. After EIP-2929, a warm SLOAD costs 100 gas
3. The comparison `targetLevel > level + 6` is trivial computation

For `_queueTicketRange`, the `level` read should be hoisted outside the loop to avoid repeated SLOADs:

```solidity
uint24 currentLevel = level; // cache once
for (uint24 i = 0; i < numLevels; ) {
    bool isFarFuture = lvl > currentLevel + 6;
    uint24 wk = isFarFuture ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
    // ... rest of loop
}
```

### Caller Classification (Permissionless vs. AdvanceGame)

| Caller | Context | Can Produce FF Tickets? | rngLocked During Call? | Guard Behavior |
|--------|---------|------------------------|----------------------|----------------|
| Constructor pre-queue | Deploy | Yes (levels 1-100) | No (constructor) | No guard needed |
| Vault perpetual | advanceGame | Yes (purchaseLevel + 99) | Yes | Exempt via phaseTransitionActive |
| Lootbox ETH | Permissionless (openLootBox) | Yes (5% chance: +5 to +50) | Possible | Reverts if rngLocked |
| Lootbox whale pass | Permissionless (openLootBox) | Yes (100-level range) | Possible | Reverts if rngLocked |
| Whale purchase | Permissionless (purchaseWhaleBundle) | Yes (100-level range) | Possible | Reverts if rngLocked |
| Lazy pass | Permissionless (purchaseLazyPass) | Maybe (10 levels from current) | Possible | Near-future only in practice |
| Deity pass | Permissionless (purchaseDeityPass) | Yes (100-level range) | Has own rngLocked guard | Reverts if rngLocked |
| Endgame auto-rebuy | advanceGame (via _runRewardJackpots) | No (+1 to +4 only) | Yes | Near-future, guard irrelevant |
| Decimator auto-rebuy | advanceGame (via _runDecimatorJackpot) | No (+1 to +4 only) | Yes | Near-future, guard irrelevant |
| Jackpot ETH rebuy | advanceGame (payDailyJackpot) | No (+0 to +4 only) | Yes | Near-future, guard irrelevant |
| Jackpot ticket rebuy | advanceGame (payDailyJackpotCoinAndTickets) | No (+1 to +4 only) | Yes | Near-future, guard irrelevant |
| Jackpot lvl+1 rebuy | advanceGame (_distributeTicketJackpot) | No (lvl+1 only) | Yes | Near-future, guard irrelevant |
| MintModule ticket call | Permissionless (mint) | No (near-future ticketLevel) | Possible | Near-future, guard irrelevant |
| claimWhalePass (Endgame) | Permissionless | Yes (100-level range) | Possible | Reverts if rngLocked |
| _jackpotTicketRoll (Endgame) | Permissionless | Yes (5% chance: +5 to +50) | No (via lootbox open) | Follows lootbox guard |

### AdvanceGame Flow Timeline (Proving phaseTransitionActive Correctness)

```
advanceGame() called
  |
  +-- rngGate() -> returns 1 if VRF requested
  |     rngLockedFlag = true                     [AdvanceModule:1325]
  |
  +-- VRF fulfilled, rngGate() returns rngWord
  |     rngLockedFlag STILL TRUE
  |
  +-- Jackpot phase processing (rngLockedFlag = true)
  |     payDailyJackpot          -> tickets at lvl+0..+4    [near-future]
  |     payDailyJackpotCoinAndTickets -> tickets at lvl+1   [near-future]
  |     _runRewardJackpots       -> auto-rebuy at lvl+1..+4 [near-future]
  |     _endPhase()              -> phaseTransitionActive = TRUE  [AdvanceModule:477]
  |
  +-- Next advanceGame() call (rngLockedFlag = true, phaseTransitionActive = true)
  |     _processPhaseTransition  -> vault tickets at purchaseLevel+99 [FAR-FUTURE, EXEMPT]
  |     phaseTransitionActive = false            [AdvanceModule:244]
  |     _unlockRng(day)          -> rngLockedFlag = false   [AdvanceModule:245]
```

The gap between `_endPhase()` and `_processPhaseTransition` completion is exactly the window where `phaseTransitionActive = true`. No other code path sets this flag to true.

### Recommended Project Structure (Changes Only)

```
contracts/
  storage/
    DegenerusGameStorage.sol    # Modify _queueTickets, _queueTicketsScaled, _queueTicketRange
```

No new files. No interface changes. No storage variable additions.

### Anti-Patterns to Avoid

- **Per-caller routing:** Do NOT modify each of the 11 caller sites to compute the key. The routing must be centralized in the 3 queue functions for maintainability and correctness.
- **Adding a new storage variable for the exemption:** `phaseTransitionActive` already exists and has exactly the right semantics. Do not add a new bool.
- **Guarding `_queueTicketRange` separately:** The range function iterates levels and some may be near-future, some far-future. The guard must be per-level inside the loop, just like the routing.
- **Changing function signatures:** Do NOT add parameters like `bool isFarFuture` to the queue functions. The functions should compute this internally from `level` storage to maintain the central-fix property.
- **Checking `msg.sender` for exemption:** Modules run via delegatecall, so `msg.sender` is always the external caller, not advanceGame. Use storage sentinels.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Far-future detection | Custom logic at each caller | `targetLevel > level + 6` inside queue functions | Single fix point; impossible to miss a caller |
| AdvanceGame exemption | New storage flag or msg.sender check | Existing `phaseTransitionActive` bool | Already has correct lifecycle; set by _endPhase, cleared after _processPhaseTransition |
| Key selection | New mapping or if/else chains | Ternary: `isFarFuture ? _tqFarFutureKey(x) : _tqWriteKey(x)` | Minimal code change, uses Phase 74 helper |

## Common Pitfalls

### Pitfall 1: Forgetting _queueTicketRange
**What goes wrong:** `_queueTicketRange` (line 624) has its own inline key computation in a loop. If only `_queueTickets` and `_queueTicketsScaled` are updated, whale pass claims via EndgameModule (100-level range) and lazy pass (10-level range) will still route all tickets to `_tqWriteKey`.
**Why it happens:** `_queueTicketRange` is a separate function that doesn't call `_queueTickets` -- it has its own inline loop.
**How to avoid:** The fix must touch all three key-computing functions: `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`.
**Warning signs:** `_queueTicketRange` still contains only `_tqWriteKey` after the fix.

### Pitfall 2: Not Caching level in _queueTicketRange Loop
**What goes wrong:** If `level` is read inside the `_queueTicketRange` loop, it costs 100 gas per iteration (warm SLOAD) times up to 100 iterations = 10,000 extra gas for whale pass claims.
**Why it happens:** Copy-pasting the pattern from `_queueTickets` where a single SLOAD is fine.
**How to avoid:** Cache `uint24 currentLevel = level;` before the loop.
**Warning signs:** `level` referenced inside `for` body of `_queueTicketRange`.

### Pitfall 3: Guard in _queueTicketRange Without Per-Level Granularity
**What goes wrong:** If the RNG guard is applied to the entire range (checking if ANY level in the range is far-future), it would block near-future tickets unnecessarily.
**Why it happens:** Treating the range as atomic rather than per-level.
**How to avoid:** The guard must be checked per-level inside the loop, same as routing. A range starting at level+1 with 100 levels has 6 near-future and 94 far-future levels.
**Warning signs:** Guard applied outside the loop or to `startLevel + numLevels`.

### Pitfall 4: Missing Guard in _queueTicketsScaled
**What goes wrong:** If the RNG guard is only added to `_queueTickets` but not `_queueTicketsScaled`, lootbox ticket writes (which use `_queueTicketsScaled` via `_queueLootboxTickets`) bypass the guard.
**Why it happens:** Lootbox is the primary permissionless far-future ticket source, and it uses the scaled path.
**How to avoid:** Both `_queueTickets` AND `_queueTicketsScaled` must have the guard. `_queueTicketRange` does not need its own guard because it calls `_queueTickets` conceptually (or has inline logic that should include it).
**Warning signs:** `_queueTicketsScaled` missing `rngLockedFlag` check.

### Pitfall 5: Using level Instead of level + 6 for Far-Future Boundary
**What goes wrong:** If the boundary is `targetLevel > level` instead of `targetLevel > level + 6`, near-future tickets for levels +1 through +6 would be incorrectly routed to the FF key. This breaks `_prepareFutureTickets` which expects these in the read-side queue.
**Why it happens:** Misunderstanding the near-future processing range.
**How to avoid:** The boundary is exactly `level + 6` because `_prepareFutureTickets` processes levels `lvl + 2` through `lvl + 6` from the read-side queue (AdvanceModule:1157-1158). Anything beyond +6 is unreachable by the near-future drain.
**Warning signs:** `_prepareFutureTickets` finding empty queues at levels it expects to drain.

### Pitfall 6: Adding the Guard to _queueLootboxTickets Instead of _queueTicketsScaled
**What goes wrong:** `_queueLootboxTickets` is just a thin wrapper calling `_queueTicketsScaled`. If the guard goes in the wrapper instead of `_queueTicketsScaled`, other callers of `_queueTicketsScaled` (MintModule:1020) bypass it. While MintModule tickets are near-future in practice, the guard should be at the lowest level for defense-in-depth.
**Why it happens:** Treating `_queueLootboxTickets` as the "lootbox guard point" rather than the underlying function.
**How to avoid:** Guard goes in `_queueTicketsScaled`, not `_queueLootboxTickets`.
**Warning signs:** Guard only in wrapper, not in base function.

## Code Examples

### _queueTickets Modification (Complete)

```solidity
// Source: contracts/storage/DegenerusGameStorage.sol, line 534
// BEFORE:
function _queueTickets(
    address buyer,
    uint24 targetLevel,
    uint32 quantity
) internal {
    if (quantity == 0) return;
    emit TicketsQueued(buyer, targetLevel, quantity);
    uint24 wk = _tqWriteKey(targetLevel);
    // ... rest unchanged

// AFTER:
function _queueTickets(
    address buyer,
    uint24 targetLevel,
    uint32 quantity
) internal {
    if (quantity == 0) return;
    emit TicketsQueued(buyer, targetLevel, quantity);
    bool isFarFuture = targetLevel > level + 6;
    if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
    uint24 wk = isFarFuture ? _tqFarFutureKey(targetLevel) : _tqWriteKey(targetLevel);
    // ... rest unchanged
```

### _queueTicketsScaled Modification (Complete)

```solidity
// Source: contracts/storage/DegenerusGameStorage.sol, line 567
// AFTER:
function _queueTicketsScaled(
    address buyer,
    uint24 targetLevel,
    uint32 quantityScaled
) internal {
    if (quantityScaled == 0) return;
    emit TicketsQueuedScaled(buyer, targetLevel, quantityScaled);
    bool isFarFuture = targetLevel > level + 6;
    if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
    uint24 wk = isFarFuture ? _tqFarFutureKey(targetLevel) : _tqWriteKey(targetLevel);
    // ... rest unchanged
```

### _queueTicketRange Modification (Complete)

```solidity
// Source: contracts/storage/DegenerusGameStorage.sol, line 624
// AFTER:
function _queueTicketRange(
    address buyer,
    uint24 startLevel,
    uint24 numLevels,
    uint32 ticketsPerLevel
) internal {
    emit TicketsQueuedRange(buyer, startLevel, numLevels, ticketsPerLevel);
    uint24 currentLevel = level;  // cache outside loop
    uint24 lvl = startLevel;
    for (uint24 i = 0; i < numLevels; ) {
        bool isFarFuture = lvl > currentLevel + 6;
        if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
        uint24 wk = isFarFuture ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
        // ... rest of loop unchanged
```

### Callers That Need NO Changes

All callers continue to pass `targetLevel` as before. The routing decision is made inside the queue functions. No caller-side modifications are required.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge 1.5.1-stable) + Hardhat 2.28.6 |
| Config file | foundry.toml (Foundry), hardhat.config.js (Hardhat) |
| Quick run command | `npx hardhat compile` |
| Full suite command | `forge test && npx hardhat test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ROUTE-01 | Far-future tickets (targetLevel > level+6) route to FF key | unit | `forge test --match-test testFarFutureRouting -vv` | Wave 0 |
| ROUTE-02 | Near-future tickets (targetLevel <= level+6) route to write key | unit | `forge test --match-test testNearFutureRouting -vv` | Wave 0 |
| ROUTE-03 | FF key writes revert when rngLocked && !phaseTransitionActive | unit | `forge test --match-test testRngGuard -vv` | Wave 0 |
| RNG-02 | Permissionless FF writes blocked during commitment window | unit | `forge test --match-test testPermissionlessBlocked -vv` | Wave 0 |

### Sampling Rate
- **Per task commit:** `npx hardhat compile` (must succeed)
- **Per wave merge:** Full test suite `forge test && npx hardhat test`
- **Phase gate:** All 4 requirement tests pass + full suite green

### Wave 0 Gaps
- [ ] Foundry test harness exposing `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange` internals with controllable `level`, `rngLockedFlag`, `phaseTransitionActive` state
- [ ] Test: far-future ticket routes to FF key, near-future to write key
- [ ] Test: rngLocked + FF key = revert
- [ ] Test: rngLocked + FF key + phaseTransitionActive = success
- [ ] Test: near-future tickets unaffected by rngLocked
- [ ] Test: _queueTicketRange splits range correctly (near-future levels to write key, far-future to FF key)

Note: Comprehensive integration tests are deferred to Phase 80 (TEST-01 through TEST-05). This phase's tests focus on the routing logic and guard behavior in isolation.

## Open Questions

1. **Should _queueTicketRange revert on first far-future level or skip far-future levels?**
   - What we know: Whale purchases queue 100 levels. During rngLocked, the first 6-7 near-future levels should succeed, but levels beyond +6 are far-future and should be guarded.
   - What's unclear: Should the function revert mid-range (failing the entire whale purchase) or silently skip guarded levels?
   - Recommendation: Revert. The external callers (purchaseWhaleBundle, purchaseDeityPass, claimWhalePass) should not be callable during rngLocked anyway. purchaseDeityPass already has its own rngLocked guard. If a whale purchase reaches `_queueTicketRange` during rngLocked, the first far-future level will revert, correctly blocking the entire purchase. This is the safest behavior -- partial ticket queuing would leave the purchase in an inconsistent state.

2. **Should the constructor pre-queue (levels 1-100) be handled specially?**
   - What we know: The constructor queues vault perpetual tickets for levels 1-100 at deploy time. Level is 0 at that point, so all 100 levels are far-future (> 0 + 6 = 6).
   - What's unclear: Whether the constructor will hit the guard.
   - Recommendation: No issue. During constructor execution, `rngLockedFlag` is false (default), so the guard is never triggered. The routing will correctly send these to the FF key, which is actually desired behavior since these are far-future relative to level 0.

## Sources

### Primary (HIGH confidence)
- contracts/storage/DegenerusGameStorage.sol -- _queueTickets (line 534), _queueTicketsScaled (line 567), _queueTicketRange (line 624), _queueLootboxTickets (line 664), _tqWriteKey (line 706), _tqFarFutureKey (line 719), rngLockedFlag (line 264), phaseTransitionActive (line 267)
- contracts/modules/DegenerusGameAdvanceModule.sol -- advanceGame flow (lines 130-385), _processPhaseTransition (line 1219), _endPhase (line 475), _prepareFutureTickets (line 1156), rngLockedFlag set (line 1325), rngLockedFlag cleared (line 1411)
- contracts/modules/DegenerusGamePayoutUtils.sol -- _calcAutoRebuy (line 38): targetLevel = currentLevel + 1..4 (always near-future)
- contracts/modules/DegenerusGameJackpotModule.sol -- ETH jackpot rebuy (line 848): baseLevel + 0..4 (near-future), ticket rebuy (line 1008): calc.targetLevel (near-future), lvl+1 rebuy (line 1210): always near-future
- contracts/modules/DegenerusGameLootboxModule.sol -- _rollTargetLevel (line 818): 5% far-future (+5 to +50)
- contracts/modules/DegenerusGameWhaleModule.sol -- purchaseWhaleBundle (line 183): 100-level range, purchaseDeityPass (line 470): 100-level range with rngLocked guard
- contracts/modules/DegenerusGameEndgameModule.sol -- auto-rebuy (line 286): +1 to +4 (near-future), claimWhalePass (line 530): 100-level range, _jackpotTicketRoll (line 488): +5 to +50 possible
- contracts/modules/DegenerusGameDecimatorModule.sol -- auto-rebuy (line 391): +1 to +4 (near-future)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- pure Solidity modification to existing storage contract functions; no new libraries or dependencies
- Architecture: HIGH -- phaseTransitionActive sentinel verified by tracing the complete advanceGame call flow; all 11+ callers classified as permissionless vs. advanceGame-internal with far-future ticket production verified
- Pitfalls: HIGH -- identified from direct code analysis of all queue function call sites, the _prepareFutureTickets boundary, and the advanceGame timing of phaseTransitionActive

**Research date:** 2026-03-22
**Valid until:** Indefinite (Solidity control flow analysis; valid as long as the function signatures and call graph remain unchanged)
