# Phase 5: Lock Removal - Research

**Researched:** 2026-03-11
**Domain:** Solidity 0.8.34 -- rngLockedFlag purchase-path gate removal
**Confidence:** HIGH

## Summary

Phase 5 is the culmination of the always-open-purchases milestone. Phases 1-4 built the infrastructure (double-buffered ticket queue, prize pool freeze/unfreeze, drain gates) that makes it safe to remove `rngLockedFlag` from purchase paths. The actual code changes are mechanically simple -- six `if (rngLockedFlag) revert` checks are deleted or have `rngLockedFlag` stripped from compound conditions. The risk is entirely in the verification: confirming that removing these guards does not create invariant violations, and that all prior-phase infrastructure handles the cases the lock previously guarded.

The `rngLockedFlag` variable itself, its set/clear sites in AdvanceModule, and its use in non-purchase contexts (VRF callback routing, reverseFlip, autorebuy/takeprofit/afking, decimator autorebuy, decimator window view, game info view) all remain untouched. The variable is NOT being removed from storage -- only six specific revert-check sites are being removed.

**Primary recommendation:** Remove the six lock sites in a single plan, update NatSpec comments, run the full Foundry test suite, and write targeted fuzz tests for purchase-during-RNG-lock scenarios. This is a single-plan phase.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LOCK-01 | Remove `rngLockedFlag` revert from `_callTicketPurchase` (MintModule:840) | Direct line deletion; double-buffer + freeze infrastructure handles concurrent writes |
| LOCK-02 | Remove `rngLockedFlag` revert from `_purchaseFor` lootbox gate (MintModule:627) | Strip `rngLockedFlag` from compound condition; freeze branching in pool additions handles ETH routing |
| LOCK-03 | Remove `rngLockedFlag` revert from `openLootBox` (LootboxModule:557) | Direct line deletion; lootbox opens use lootboxRngWordByIndex (independent of daily RNG) |
| LOCK-04 | Remove `rngLockedFlag` revert from `openBurnieLootBox` (LootboxModule:640) | Direct line deletion; same rationale as LOCK-03 |
| LOCK-05 | Remove `rngLockedFlag` from `jackpotResolutionActive` in Degenerette (DegeneretteModule:503) | Strip `rngLockedFlag` from compound expression; freeze branch already routes ETH correctly during jackpot resolution |
| LOCK-06 | Remove redundant `rngLockedFlag` check from lootbox RNG request gate (AdvanceModule:643) | Direct line deletion; `rngRequestTime != 0` on line 644 already prevents concurrent VRF requests |
</phase_requirements>

## Exact Removal Sites

### LOCK-01: MintModule line 840

```solidity
// REMOVE this entire line:
if (rngLockedFlag) revert E();
```

**Context:** `_callTicketPurchase()` -- the core ticket purchase entry point. With the double-buffer, purchases always write to the write slot (via `_tqWriteKey()`), which is independent of the read slot being processed. The freeze branch (Phase 3) routes pool additions to pending accumulators when `prizePoolFrozen == true`. No invariant depends on blocking purchases here.

### LOCK-02: MintModule line 627

```solidity
// BEFORE:
if (lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E();
// AFTER:
if (lootBoxAmount != 0 && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E();
```

**Context:** `_purchaseFor()` -- lootbox purchase guard during jackpot resolution. The `rngLockedFlag` component is removed; the remaining `lastPurchaseDay && (purchaseLevel % 5 == 0)` condition still blocks lootbox purchases during jackpot-level resolution days. This is a semantic business rule (no lootbox buys during final day of jackpot levels) independent of RNG lock state.

**Note:** Removing `rngLockedFlag` makes this slightly MORE restrictive -- the block now applies for the entire `lastPurchaseDay` on jackpot levels, not just while RNG is locked. This is acceptable because the block window is narrower (one day) and the freeze infrastructure handles ETH routing regardless.

### LOCK-03: LootboxModule line 557

```solidity
// REMOVE this entire line:
if (rngLockedFlag) revert RngLocked();
```

**Context:** `openLootBox()`. Lootbox opens use `lootboxRngWordByIndex[index]` which is set by the mid-day lootbox VRF flow, completely independent of the daily RNG cycle. The lock was a belt-and-suspenders guard that is no longer needed.

### LOCK-04: LootboxModule line 640

```solidity
// REMOVE this entire line:
if (rngLockedFlag) revert RngLocked();
```

**Context:** `openBurnieLootBox()`. Same rationale as LOCK-03.

### LOCK-05: DegeneretteModule line 503

```solidity
// BEFORE:
jackpotResolutionActive = rngLockedFlag && lastPurchaseDay && ((level + 1) % 5 == 0);
// AFTER:
jackpotResolutionActive = lastPurchaseDay && ((level + 1) % 5 == 0);
```

**Context:** `_placeFullTicketBetsCore()`. The `jackpotResolutionActive` flag controls whether ETH Degenerette bets are blocked during jackpot resolution. Downstream at line 504, `if (currency == CURRENCY_ETH && jackpotResolutionActive) revert E()` uses this value. Stripping `rngLockedFlag` means the ETH bet block applies for the entire `lastPurchaseDay` on jackpot levels, not just during RNG lock. This is the correct semantic behavior: ETH Degenerette bets during jackpot resolution days are blocked as a business rule, not just as an RNG-lock side effect.

### LOCK-06: AdvanceModule line 643

```solidity
// REMOVE this entire line:
if (rngLockedFlag) revert E();
```

**Context:** `requestLootboxRng()`. This is redundant because:
1. Line 641: `if (rngWordByDay[currentDay] == 0) revert E()` -- blocks until daily RNG has been consumed and recorded
2. Line 644: `if (rngRequestTime != 0) revert E()` -- blocks if any VRF request is in flight

When `rngLockedFlag` is true, `rngRequestTime != 0` is always true (set at AdvanceModule:1147), so the guard on line 644 already covers this case.

## What Stays (Out of Scope)

These `rngLockedFlag` references are explicitly out of scope per REQUIREMENTS.md:

| Location | Line | Why It Stays |
|----------|------|-------------|
| AdvanceModule | 129 | `purchaseLevel` calculation in `advanceGame` -- state machine logic, not a purchase guard |
| AdvanceModule | 1148 | `rngLockedFlag = true` -- the flag set site, must remain |
| AdvanceModule | 1215 | `rngLockedFlag = false` in `updateVrfCoordinator` -- admin recovery |
| AdvanceModule | 1227 | `rngLockedFlag = false` in `_unlockRng` -- normal clear path |
| AdvanceModule | 1239 | `reverseFlip()` guard -- not a purchase path |
| AdvanceModule | 1276 | VRF callback routing -- distinguishes daily vs lootbox RNG in `rawFulfillRandomWords` |
| DegenerusGame.sol | 1535 | `setDecimatorAutoRebuy` -- keep locked during jackpots |
| DegenerusGame.sol | 1556 | `_setAutoRebuy` -- keep locked |
| DegenerusGame.sol | 1571 | `_setTakeProfit` -- keep locked |
| DegenerusGame.sol | 1636 | `_setAfKing` -- keep locked |
| DegenerusGame.sol | 2199 | `rngLocked()` view function |
| DegenerusGame.sol | 2241 | `decWindow()` view function |
| DegenerusGame.sol | 2306 | `getGameState()` view function |
| DegenerusGameStorage.sol | 266 | `bool internal rngLockedFlag` declaration |

## Architecture Patterns

### Pattern: Delete-and-Verify

**What:** Remove guard lines, update NatSpec, verify via grep + tests.
**When to use:** When infrastructure has been built to handle what the guard previously protected.

The pattern for each removal site:
1. Delete/modify the specific line
2. Update the NatSpec comment above the function (remove references to RngLocked revert)
3. Check if `error RngLocked()` declaration can be removed from the file
4. Run the full test suite

### NatSpec Updates Required

| Module | Function | Update Needed |
|--------|----------|---------------|
| LootboxModule | `openLootBox` (lines 548-555) | Remove "Blocked during RNG lock" from `@dev`, remove `@custom:reverts RngLocked` |
| LootboxModule | `openBurnieLootBox` (lines 631-638) | Remove "Blocked during RNG lock" from `@dev`, remove `@custom:reverts RngLocked` |
| MintModule | `_purchaseFor` (line 626) | Update comment about blocking lootbox purchases |

### Error Declaration Cleanup

After LOCK-03 and LOCK-04, check if `error RngLocked()` is still used anywhere in LootboxModule. If not, remove the declaration. In AdvanceModule, `reverseFlip()` at line 1239 still uses `RngLocked`, so it stays there.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Verifying removal completeness | Manual code review only | `grep -n rngLockedFlag` across target files | Six sites across four files -- grep is authoritative |
| Gas comparison | Custom gas measurement | `forge snapshot` before/after | Built-in Foundry feature, gives per-test gas diffs |
| Fuzz testing purchase-during-lock | Complex integration harness with full deploy | Simplified guard-logic harness extending DegenerusGameStorage | Established pattern from Phases 1-4 (StorageHarness, QueueHarness, FreezeHarness, AdvanceHarness) |

## Common Pitfalls

### Pitfall 1: Removing the Entire Compound Condition Instead of Just rngLockedFlag

**What goes wrong:** For LOCK-02 and LOCK-05, deleting the entire line instead of stripping `rngLockedFlag &&` removes game-logic guards that should remain.
**Why it happens:** The requirement says "remove rngLockedFlag" which could be read as "remove the entire check."
**How to avoid:** LOCK-02: strip `rngLockedFlag &&` from condition. LOCK-05: strip `rngLockedFlag &&` from assignment expression.
**Warning signs:** No remaining `lastPurchaseDay` check at MintModule:627 or DegeneretteModule:503.

### Pitfall 2: Touching Out-of-Scope rngLockedFlag References

**What goes wrong:** Removing `rngLockedFlag` from `rawFulfillRandomWords` (line 1276) breaks daily/lootbox VRF routing. Removing from `advanceGame` (line 129) breaks purchaseLevel calculation.
**Why it happens:** Overzealous grep-and-delete across all files.
**How to avoid:** Only touch the six specific sites listed in requirements. Verify via diff that exactly 6 sites are modified.

### Pitfall 3: Forgetting NatSpec and Error Declaration Cleanup

**What goes wrong:** Dead NatSpec references to `RngLocked` reverts confuse future readers.
**Why it happens:** Focus on logic, not documentation.
**How to avoid:** Include NatSpec updates in the same task as line removal.

### Pitfall 4: Not Taking a Gas Snapshot Baseline

**What goes wrong:** Success criterion 4 requires "at least one fewer SSTORE per purchase compared to pre-milestone baseline." Cannot verify without baseline.
**Why it happens:** Forgetting to snapshot before making changes.
**How to avoid:** Run `forge snapshot` before Phase 5 changes. Note: the SSTORE savings come from packed pool helpers (Phase 1), not from lock removal itself. Lock removal saves SLOADs. The gas snapshot should demonstrate the cumulative milestone savings.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Foundry (forge test) -- Solidity 0.8.34 |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-path test/fuzz/LockRemoval.t.sol -vvv` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LOCK-01 | `_callTicketPurchase` no longer reverts on rngLockedFlag | unit | `forge test --match-test test_purchaseDuringRngLock -vvv` | No -- Wave 0 |
| LOCK-02 | Lootbox purchase guard uses only lastPurchaseDay+level | unit | `forge test --match-test test_lootboxGuardStripped -vvv` | No -- Wave 0 |
| LOCK-03 | `openLootBox` succeeds during RNG lock | unit | `forge test --match-test test_openLootBoxDuringLock -vvv` | No -- Wave 0 |
| LOCK-04 | `openBurnieLootBox` succeeds during RNG lock | unit | `forge test --match-test test_openBurnieLootBoxDuringLock -vvv` | No -- Wave 0 |
| LOCK-05 | `jackpotResolutionActive` ignores rngLockedFlag | unit | `forge test --match-test test_degeneretteJackpotResolution -vvv` | No -- Wave 0 |
| LOCK-06 | `requestLootboxRng` gate without rngLockedFlag check | unit | `forge test --match-test test_lootboxRngRequestGate -vvv` | No -- Wave 0 |
| SC-3 | Full fuzz suite passes | fuzz+invariant | `forge test` | Existing suite |
| SC-4 | Gas snapshot shows SSTORE reduction | snapshot | `forge snapshot --diff` | Needs baseline |

### Testing Strategy

The six removal sites span four modules (MintModule, LootboxModule, DegeneretteModule, AdvanceModule). The purchase-path functions (`_callTicketPurchase`, `_purchaseFor`) are `private` and cannot be called directly. The established project pattern is to create harness contracts extending `DegenerusGameStorage` that reproduce the guard logic.

**Recommended harness approach:**

```solidity
contract LockRemovalHarness is DegenerusGameStorage {
    function setRngLockedFlag(bool val) external { rngLockedFlag = val; }
    function setGameOver(bool val) external { gameOver = val; }
    function setLastPurchaseDay(bool val) external { lastPurchaseDay = val; }
    function setLevel(uint24 val) external { level = val; }

    // Reproduces LOCK-01 guard logic (post-removal)
    function callTicketPurchaseGuard(uint256 quantity) external view {
        if (quantity == 0 || quantity > type(uint32).max) revert E();
        if (gameOver) revert E();
        // rngLockedFlag check REMOVED
    }

    // Reproduces LOCK-02 guard logic (post-removal)
    function purchaseForLootboxGuard(uint256 lootBoxAmount) external view returns (bool blocked) {
        uint24 purchaseLevel = level + 1;
        blocked = (lootBoxAmount != 0 && lastPurchaseDay && (purchaseLevel % 5 == 0));
    }

    // Reproduces LOCK-05 expression (post-removal)
    function jackpotResolutionActive() external view returns (bool) {
        return lastPurchaseDay && ((level + 1) % 5 == 0);
    }
}
```

Tests verify:
1. With `rngLockedFlag = true`, the guard functions do NOT revert (LOCK-01) or return false for non-jackpot scenarios (LOCK-02, LOCK-05)
2. The remaining conditions still fire when expected (gameOver, lastPurchaseDay + jackpot level)
3. Fuzz: randomize rngLockedFlag, level, lastPurchaseDay and confirm guards only depend on the correct variables

### Sampling Rate

- **Per task commit:** `forge test --match-path test/fuzz/LockRemoval.t.sol -vvv`
- **Per wave merge:** `forge test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/fuzz/LockRemoval.t.sol` -- new test file with LockRemovalHarness + guard-logic tests for LOCK-01 through LOCK-06
- [ ] Gas baseline: `forge snapshot > .gas-snapshot-pre-lock-removal` before code changes

## Verification Grep Commands

After all changes, run these to confirm exactly the right sites were modified:

```bash
# MintModule: should return ZERO results (both LOCK-01 and LOCK-02 removed rngLockedFlag)
grep -n "rngLockedFlag" contracts/modules/DegenerusGameMintModule.sol

# LootboxModule: should return ZERO results (LOCK-03 and LOCK-04 removed)
grep -n "rngLockedFlag" contracts/modules/DegenerusGameLootboxModule.sol

# DegeneretteModule: should return ZERO results (LOCK-05 removed)
grep -n "rngLockedFlag" contracts/modules/DegenerusGameDegeneretteModule.sol

# AdvanceModule: should return exactly 6 results (lines 129, 1148, 1215, 1227, 1239, 1276)
grep -n "rngLockedFlag" contracts/modules/DegenerusGameAdvanceModule.sol
```

## Open Questions

1. **LOCK-02: Strip or Delete Entire Line?**
   - What we know: The condition `lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)` gates lootbox purchases. Removing just `rngLockedFlag &&` leaves a jackpot-level/lastPurchaseDay block. Removing the entire line allows lootbox purchases anytime.
   - What's unclear: Whether the `lastPurchaseDay && jackpot-level` block is still a desired business rule or was only meaningful when combined with rngLockedFlag.
   - Recommendation: Strip `rngLockedFlag &&` (keep remaining condition). This is the conservative interpretation of "remove rngLockedFlag revert" and preserves the jackpot-level lootbox block as a game-design choice.

2. **Gas Snapshot Baseline**
   - What we know: SC-4 requires "at least one fewer SSTORE per purchase compared to pre-milestone baseline." The packed pool helpers from Phase 1 already provide this savings.
   - What's unclear: Whether a pre-milestone gas snapshot exists.
   - Recommendation: Take a snapshot now (post-Phase-4, pre-Phase-5) to serve as the comparison point. The SSTORE savings are from packed pools (Phase 1), already in the codebase.

## Sources

### Primary (HIGH confidence)

- Direct source code inspection of all six removal sites with exact line numbers
- Full `grep -rn rngLockedFlag contracts/` -- 18 total references mapped
- `.planning/REQUIREMENTS.md` -- requirement definitions and out-of-scope boundary
- `.planning/STATE.md` -- project decisions from Phases 1-4
- `audit/PLAN-ALWAYS-OPEN-PURCHASES.md` -- original architecture plan
- Existing test files: `test/fuzz/AdvanceGameRewrite.t.sol` (harness pattern reference)

## Metadata

**Confidence breakdown:**
- Removal sites: HIGH -- direct code inspection, exact line numbers verified
- What stays: HIGH -- REQUIREMENTS.md explicitly lists out-of-scope items, cross-referenced with grep
- Compound condition handling (LOCK-02, LOCK-05): MEDIUM -- two valid interpretations, recommended conservative approach
- Test strategy: HIGH -- follows established Phase 1-4 harness pattern

**Research date:** 2026-03-11
**Valid until:** Indefinite (codebase-specific, not library-dependent)
