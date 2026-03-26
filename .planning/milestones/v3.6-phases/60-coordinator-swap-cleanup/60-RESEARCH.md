# Phase 60: Coordinator Swap Cleanup - Research

**Researched:** 2026-03-22
**Domain:** Solidity smart contract audit -- VRF coordinator swap stale state analysis
**Confidence:** HIGH

## Summary

Phase 60 audits `updateVrfCoordinatorAndSub` for completeness of stale state handling after a VRF coordinator swap, and documents the `totalFlipReversals` design decision. Phase 59 already added the two most critical fixes: orphaned lootbox index recovery (via `keccak256(lastLootboxRngWord, orphanedIndex)`) and `midDayTicketRngPending = false`. The question now is whether any additional VRF-related state remains stale after a swap.

After thorough investigation of all VRF-related state variables in `DegenerusGameStorage.sol` and their write sites across the codebase, I found **two issues** that Phase 60 should address: (1) a missing `LootboxRngApplied` event emission for the orphaned index backfill, and (2) the `totalFlipReversals` design decision needs documentation as a NatSpec comment explaining why it intentionally carries over. All other VRF state is either already reset by `updateVrfCoordinatorAndSub`, intentionally preserved (like `lastVrfProcessedTimestamp` per DegenerusAdmin's explicit comment), or naturally handled by the normal `advanceGame` flow upon resume.

**Primary recommendation:** Add a `LootboxRngApplied` event emission for the orphaned index fallback word, and add a NatSpec comment to `updateVrfCoordinatorAndSub` documenting the `totalFlipReversals` carry-over decision. These are the only changes needed -- the function is already handling stale state correctly for all other variables.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SWAP-01 | updateVrfCoordinatorAndSub properly handles all stale state from the failed coordinator | Full inventory of 15 VRF-related state variables completed; all are either reset, intentionally preserved, or naturally handled. One missing event emission found (LootboxRngApplied for orphaned index). See Architecture Patterns section. |
| SWAP-02 | totalFlipReversals handling documented (carry-over vs reset -- design decision) | Analysis complete: carry-over is correct. Nudges were purchased with BURNIE before/during the stall; resetting would steal user value. Document as NatSpec comment. See totalFlipReversals Analysis section. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Solidity | 0.8.34 | Smart contract language | Project standard |
| Foundry (forge) | latest | Compilation verification | Already configured |

No new dependencies. This phase is a contract audit + minor fixes.

## Architecture Patterns

### Relevant Contract Architecture
```
contracts/
  DegenerusAdmin.sol                # Governance: _executeSwap calls updateVrfCoordinatorAndSub
  modules/
    DegenerusGameAdvanceModule.sol   # Contains updateVrfCoordinatorAndSub (line 1334)
      updateVrfCoordinatorAndSub()   # THE function under audit
      _applyDailyRng()              # Consumes totalFlipReversals
      _backfillGapDays()            # Gap day backfill (Phase 59)
      reverseFlip()                 # Writes totalFlipReversals
      rawFulfillRandomWords()       # VRF callback
      _finalizeLootboxRng()         # Lootbox RNG finalization (emits LootboxRngApplied)
      rngGate()                     # Daily RNG processing gate
  storage/
    DegenerusGameStorage.sol         # All VRF-related state variables
```

### Pattern 1: Complete VRF State Inventory

Every VRF-related state variable and its handling during coordinator swap:

| Variable | Storage Location | Current Swap Handling | Status |
|----------|-----------------|----------------------|--------|
| `vrfCoordinator` | GameStorage:1284 | Updated to new coordinator | OK |
| `vrfSubscriptionId` | GameStorage:1292 | Updated to new sub ID | OK |
| `vrfKeyHash` | GameStorage:1288 | Updated to new key hash | OK |
| `rngLockedFlag` | GameStorage:256 (Slot 0) | Set to `false` | OK |
| `vrfRequestId` | GameStorage:357 | Set to `0` | OK |
| `rngRequestTime` | GameStorage:210 (Slot 0) | Set to `0` | OK |
| `rngWordCurrent` | GameStorage:351 | Set to `0` | OK |
| `midDayTicketRngPending` | GameStorage:1352 | Set to `false` (Phase 59 fix) | OK |
| `lootboxRngWordByIndex[orphaned]` | GameStorage:1335 | Backfilled via keccak256 (Phase 59 fix) | OK -- but missing event |
| `lastLootboxRngWord` | GameStorage:1348 | Updated during orphan backfill | OK |
| `totalFlipReversals` | GameStorage:361 | NOT reset (intentional) | Needs documentation |
| `lastVrfProcessedTimestamp` | GameStorage:1554 | NOT reset (intentional) | OK -- documented in Admin |
| `dailyIdx` | GameStorage:202 (Slot 0) | NOT reset (correct) | OK -- gap backfill handles |
| `lootboxRngPendingEth` | GameStorage:1302 | NOT reset (correct) | OK -- accumulates normally |
| `lootboxRngPendingBurnie` | GameStorage:1343 | NOT reset (correct) | OK -- accumulates normally |

### Pattern 2: What updateVrfCoordinatorAndSub Currently Does (Post-Phase 59)

Source: `contracts/modules/DegenerusGameAdvanceModule.sol` lines 1334-1373

```solidity
function updateVrfCoordinatorAndSub(
    address newCoordinator,
    uint256 newSubId,
    bytes32 newKeyHash
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();

    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(newCoordinator);
    vrfSubscriptionId = newSubId;
    vrfKeyHash = newKeyHash;

    // [Phase 59] Orphaned lootbox index backfill
    uint256 outgoingRequestId = vrfRequestId;
    if (outgoingRequestId != 0) {
        uint48 orphanedIndex = lootboxRngRequestIndexById[outgoingRequestId];
        if (orphanedIndex != 0 && lootboxRngWordByIndex[orphanedIndex] == 0) {
            uint256 fallbackWord = uint256(keccak256(abi.encodePacked(
                lastLootboxRngWord, orphanedIndex
            )));
            if (fallbackWord == 0) fallbackWord = 1;
            lootboxRngWordByIndex[orphanedIndex] = fallbackWord;
            lastLootboxRngWord = fallbackWord;
            // NOTE: No LootboxRngApplied event emitted <-- FINDING
        }
    }

    // Reset RNG state
    rngLockedFlag = false;
    vrfRequestId = 0;
    rngRequestTime = 0;
    rngWordCurrent = 0;

    // [Phase 59] Clear mid-day pending flag
    midDayTicketRngPending = false;

    emit VrfCoordinatorUpdated(current, newCoordinator);
}
```

### Pattern 3: Missing Event Emission (FINDING)

The `_finalizeLootboxRng` function (line 833-838) emits `LootboxRngApplied(index, rngWord, vrfRequestId)` whenever a lootbox index gets its RNG word. The orphaned index backfill in `updateVrfCoordinatorAndSub` writes to `lootboxRngWordByIndex[orphanedIndex]` but does NOT emit this event.

This is a LOW-severity finding but matters for off-chain indexers that track lootbox RNG state. Without the event, indexers cannot detect that the orphaned index was resolved during the swap rather than via normal VRF callback.

**Fix:** Add `emit LootboxRngApplied(orphanedIndex, fallbackWord, outgoingRequestId);` after the backfill write.

### Pattern 4: totalFlipReversals Analysis (SWAP-02)

**What it is:** `totalFlipReversals` (uint256, GameStorage slot after vrfRequestId) tracks how many "reverse flip" nudges players have purchased via `reverseFlip()`. Each nudge costs BURNIE (100 ether base, compounding +50% per additional nudge). The value is consumed (added to the VRF word) by `_applyDailyRng()` and then reset to 0.

**Lifecycle:**
1. Players call `reverseFlip()` which increments `totalFlipReversals` (line 1397)
2. `reverseFlip()` only works when `rngLockedFlag == false` (before daily RNG request)
3. When `_applyDailyRng()` runs, it adds `totalFlipReversals` to the raw VRF word, then sets it to 0 (line 1474-1480)
4. Gap days do NOT consume nudges -- `_backfillGapDays` uses raw derived words (line 1445 comment)

**During VRF stall scenario:**
1. Day N: VRF request sent, `rngLockedFlag = true` -- no more nudges possible
2. Days N+1 to N+K: Stall -- no `advanceGame()` runs, no nudges possible (rngLockedFlag stays true)
3. Coordinator swap: `rngLockedFlag = false` -- nudges become possible again
4. Between swap and first post-swap `advanceGame()`: Players CAN call `reverseFlip()` again
5. First `advanceGame()`: `_applyDailyRng` consumes whatever nudges exist

**Should it reset on swap?**

**No -- carry-over is correct.** Here is the analysis:

| Scenario | totalFlipReversals at swap | What happens |
|----------|--------------------------|--------------|
| Nudges queued before stall, VRF never arrived | N > 0 | _applyDailyRng was never called for that day. The nudges were paid for and should apply to the NEXT day processed (the first post-gap day). Resetting would steal value. |
| No nudges before stall | 0 | No-op either way |
| Nudges queued after swap (between swap and first advanceGame) | N > 0 | Normal behavior -- players nudge, next advanceGame consumes them |

**The design decision:** `totalFlipReversals` intentionally carries over across coordinator swaps because:
- Nudges were purchased with BURNIE burns (irreversible)
- Players expected them to influence the next RNG word
- The first post-gap VRF word will have them applied via normal `_applyDailyRng`
- Resetting would be a theft of user value (burned BURNIE for nothing)

**Edge case -- nudges applied to keccak-derived word:** The backfilled gap days use raw `keccak256(vrfWord, gapDay)` without nudges (correct -- see Phase 59 research anti-pattern). But the CURRENT day (processed via `_applyDailyRng`) gets the raw VRF word + nudges. This means nudges purchased before the stall influence the first post-gap current day, which is acceptable -- that is the next actual VRF word to be processed.

### Pattern 5: lastVrfProcessedTimestamp -- Intentionally NOT Reset

The `lastVrfProcessedTimestamp` is NOT reset in `updateVrfCoordinatorAndSub`. This is intentional and already documented in `DegenerusAdmin.sol` (line 563-565):

```solidity
// Intentional: lastVrfProcessedTimestamp is NOT reset here -- the old stall
// timestamp carries over so governance can rapidly re-swap if the new
// coordinator also fails, without waiting for a fresh stall window.
```

If the new coordinator also stalls, the old timestamp means the `ADMIN_STALL_THRESHOLD` (20 hours) is already exceeded, allowing immediate re-proposal. `lastVrfProcessedTimestamp` is updated by `_applyDailyRng()` (line 1484) on the first successful post-swap daily processing.

**Contrast with wireVrf:** The initial `wireVrf()` function (line 391-410) DOES set `lastVrfProcessedTimestamp = uint48(block.timestamp)` because it runs at deploy time when no stall recovery is needed.

### Pattern 6: Variables That Should NOT Be Reset

These variables look VRF-adjacent but should NOT be touched by the coordinator swap:

| Variable | Why NOT Reset |
|----------|---------------|
| `dailyIdx` | Gap day backfill handles the idx gap. Resetting would corrupt the entire day sequencing. |
| `lootboxRngIndex` | This is a monotonic counter for lootbox indices. Resetting would cause index collisions. The orphaned index is handled by backfill. |
| `lootboxRngPendingEth` | These are purchase accumulators unrelated to VRF state. Purchases continue normally. |
| `lootboxRngPendingBurnie` | Same as above. |
| `rngWordByDay[*]` | Historical data. Gap days are backfilled by `_backfillGapDays` on the next `advanceGame()`. |
| `lootboxRngRequestIndexById[outgoingRequestId]` | Stale mapping entry but harmless: vrfRequestId is cleared to 0, so it cannot be looked up again. No gas savings from deleting (cold SSTORE cost). |
| `lastPurchaseDay` | Game FSM state, not VRF state. Carries forward correctly. |
| `phaseTransitionActive` | Same -- game FSM. |
| `prizePoolFrozen` | Set during daily RNG request, cleared by `_unfreezePool()`. If VRF stalled during jackpot resolution, the freeze state carries forward and resolves when `advanceGame()` processes the day. |

### Anti-Patterns to Avoid

- **Resetting totalFlipReversals on swap:** Would steal BURNIE from players who paid for nudges. See SWAP-02 analysis above.
- **Resetting lastVrfProcessedTimestamp on swap:** Would prevent rapid re-swap if new coordinator also fails. Already documented in DegenerusAdmin.
- **Resetting dailyIdx or game FSM state:** Would corrupt game progression. These are NOT VRF state.
- **Adding event parameters to VrfCoordinatorUpdated:** The existing event is sufficient. The orphaned lootbox fix should use the existing `LootboxRngApplied` event instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Event for orphaned index | New event type | Existing `LootboxRngApplied(index, word, requestId)` | Indexers already parse this event; using the same event with the outgoingRequestId maintains consistency |

## Common Pitfalls

### Pitfall 1: Confusing "Missing Reset" with "Bug"

**What goes wrong:** Over-zealous reset of state variables in `updateVrfCoordinatorAndSub` corrupts game state.

**Why it happens:** When auditing for stale state, the instinct is "if it touches VRF, reset it." But many variables that reference VRF outputs (like `dailyIdx`, `rngWordByDay`, `lootboxRngIndex`) are game state anchored to the VRF lifecycle, not VRF configuration state.

**How to avoid:** For each variable, ask: "Is this VRF _configuration/request_ state (should reset) or game _progression_ state that references VRF outputs (should NOT reset)?" The former includes `vrfRequestId`, `rngRequestTime`, `rngWordCurrent`, `rngLockedFlag`. The latter includes `dailyIdx`, `rngWordByDay`, `lootboxRngIndex`.

**Warning signs:** Any proposal to reset `dailyIdx`, `lootboxRngIndex`, or `rngWordByDay` in the swap function.

### Pitfall 2: Stale Mapping Entry in lootboxRngRequestIndexById

**What goes wrong:** After coordinator swap, `lootboxRngRequestIndexById[outgoingRequestId]` still maps the old requestId to the orphaned index. Someone might worry this is a dangling reference.

**Why it's harmless:** The `outgoingRequestId` is a Chainlink-generated unique identifier. No new request from the new coordinator will ever reuse this ID. The mapping entry is dead weight but costs nothing to leave (no gas savings from deletion since the slot is cold after the tx). The only reader is `_finalizeLootboxRng` which uses `vrfRequestId` (now 0) as the lookup key, so the stale entry is unreachable.

**How to avoid:** Do not add a `delete lootboxRngRequestIndexById[outgoingRequestId]` -- it costs 2,100 gas (cold SSTORE) for zero benefit.

### Pitfall 3: Event Emission Ordering for Orphaned Index

**What goes wrong:** If `LootboxRngApplied` is emitted AFTER `vrfRequestId = 0`, the event's `requestId` parameter would be 0 instead of the actual outgoing request ID.

**How to avoid:** The orphaned index code block already runs BEFORE `vrfRequestId = 0` (Phase 59 design). The event must be emitted within the same block, using `outgoingRequestId` (already captured in a local variable).

## Code Examples

### Current updateVrfCoordinatorAndSub with Phase 59 fixes (lines 1334-1373)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1334-1373
function updateVrfCoordinatorAndSub(
    address newCoordinator,
    uint256 newSubId,
    bytes32 newKeyHash
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();

    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(newCoordinator);
    vrfSubscriptionId = newSubId;
    vrfKeyHash = newKeyHash;

    // Backfill orphaned lootbox index from the stalled VRF request.
    // Must happen BEFORE clearing vrfRequestId -- we need it to look up the index.
    uint256 outgoingRequestId = vrfRequestId;
    if (outgoingRequestId != 0) {
        uint48 orphanedIndex = lootboxRngRequestIndexById[outgoingRequestId];
        if (orphanedIndex != 0 && lootboxRngWordByIndex[orphanedIndex] == 0) {
            uint256 fallbackWord = uint256(keccak256(abi.encodePacked(
                lastLootboxRngWord, orphanedIndex
            )));
            if (fallbackWord == 0) fallbackWord = 1;
            lootboxRngWordByIndex[orphanedIndex] = fallbackWord;
            lastLootboxRngWord = fallbackWord;
        }
    }

    // Reset RNG state to allow immediate advancement
    rngLockedFlag = false;
    vrfRequestId = 0;
    rngRequestTime = 0;
    rngWordCurrent = 0;

    // Clear mid-day lootbox RNG pending flag to prevent post-swap deadlock.
    midDayTicketRngPending = false;

    emit VrfCoordinatorUpdated(current, newCoordinator);
}
```

### How _applyDailyRng consumes totalFlipReversals (lines 1469-1486)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1469-1486
function _applyDailyRng(
    uint48 day,
    uint256 rawWord
) private returns (uint256 finalWord) {
    uint256 nudges = totalFlipReversals;
    finalWord = rawWord;
    if (nudges != 0) {
        unchecked {
            finalWord += nudges;
        }
        totalFlipReversals = 0;
    }
    rngWordCurrent = finalWord;
    rngWordByDay[day] = finalWord;
    lastVrfProcessedTimestamp = uint48(block.timestamp);
    emit DailyRngApplied(day, rawWord, nudges, finalWord);
}
```

### How _finalizeLootboxRng emits event (lines 833-838)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:833-838
function _finalizeLootboxRng(uint256 rngWord) private {
    uint48 index = lootboxRngRequestIndexById[vrfRequestId];
    if (index == 0) return;
    lootboxRngWordByIndex[index] = rngWord;
    lastLootboxRngWord = rngWord;
    emit LootboxRngApplied(index, rngWord, vrfRequestId);
}
```

### DegenerusAdmin intentional lastVrfProcessedTimestamp comment (lines 562-565)
```solidity
// Source: contracts/DegenerusAdmin.sol:562-565
/// @dev Execute VRF coordinator swap and void all other active proposals.
// Intentional: lastVrfProcessedTimestamp is NOT reset here -- the old stall
// timestamp carries over so governance can rapidly re-swap if the new
// coordinator also fails, without waiting for a fresh stall window.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| updateVrfCoordinatorAndSub only reset 4 VRF vars | Phase 59 added orphaned lootbox + midDayTicketRngPending | v3.6 Phase 59 | No more bricked lootboxes or post-swap deadlocks |
| No event for orphaned index backfill | (Pending) Add LootboxRngApplied event | v3.6 Phase 60 | Indexer parity with normal VRF path |
| totalFlipReversals undocumented during swap | (Pending) NatSpec documenting carry-over | v3.6 Phase 60 | Design decision visible to C4A wardens |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat (ethers v6) |
| Config file | `foundry.toml` / `hardhat.config.cjs` |
| Quick run command | `forge build` |
| Full suite command | `npx hardhat test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SWAP-01 | All stale VRF state properly reset during swap | audit | `forge build` (compilation check only; functional tests in Phase 61 TEST-01) | N/A -- audit phase, not implementation |
| SWAP-02 | totalFlipReversals carry-over documented | manual-only | grep for NatSpec comment | N/A -- documentation task |

### Sampling Rate
- **Per task commit:** `forge build`
- **Per wave merge:** `forge build` + `npx hardhat test`
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. Comprehensive stall-swap-resume tests are scoped to Phase 61 (TEST-01, TEST-02, TEST-03).

## Open Questions

1. **Should the stale `lootboxRngRequestIndexById[outgoingRequestId]` mapping entry be cleaned up?**
   - What we know: The entry maps the old Chainlink requestId to the orphaned index. The requestId will never be reused by the new coordinator.
   - What's unclear: Whether the 2,100 gas cost of deletion is worth the cleanliness.
   - Recommendation: Do NOT delete. The entry is unreachable after `vrfRequestId = 0`. Deleting costs gas for zero functional benefit. A C4A warden might flag it as INFO-severity "stale storage" but not as a vulnerability. If desired for cleanliness, add `delete lootboxRngRequestIndexById[outgoingRequestId]` after the backfill block.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- Full read of updateVrfCoordinatorAndSub (1334-1373), _applyDailyRng (1469-1486), reverseFlip (1391-1399), _finalizeLootboxRng (833-838), rngGate (765-831), _backfillGapDays (1453-1467), rawFulfillRandomWords (1419-1440), _requestRng (1211-1224), _finalizeRngRequest (1255-1326), requestLootboxRng (679-741)
- `contracts/storage/DegenerusGameStorage.sol` -- All 15 VRF-related state variables verified (storage slots, types, initialization)
- `contracts/DegenerusAdmin.sol` -- _executeSwap (566-625), lastVrfProcessedTimestamp comment (563-565), stall threshold usage (301, 551)
- `contracts/BurnieCoinflip.sol` -- processCoinflipPayouts, flipsClaimableDay, coinflipDayResult
- `.planning/phases/59-rng-gap-backfill-implementation/59-RESEARCH.md` -- Phase 59 research (predecessor phase)
- `.planning/phases/59-rng-gap-backfill-implementation/59-01-PLAN.md` -- Gap backfill implementation plan
- `.planning/phases/59-rng-gap-backfill-implementation/59-02-PLAN.md` -- Orphaned lootbox + midDayTicketRngPending plan

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- No new dependencies, pure audit + minor fix phase
- Architecture: HIGH -- Every VRF state variable traced to source, all write sites verified
- Pitfalls: HIGH -- Each "should this reset?" question answered with evidence from the codebase

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable -- contract is pre-audit, changes are controlled)
