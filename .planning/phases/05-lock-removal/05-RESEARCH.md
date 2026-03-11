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
| LOCK-05 | Remove `rngLockedFlag` from `jackpotResolutionActive` in Degenerette (DegeneretteModule:503) | Strip `rngLockedFlag` from compound condition; freeze branch already routes ETH correctly during jackpot resolution |
| LOCK-06 | Remove redundant `rngLockedFlag` check from lootbox RNG request gate (AdvanceModule:643) | Direct line deletion; `rngRequestTime != 0` on line 644 already prevents concurrent VRF requests |
</phase_requirements>

## Exact Removal Sites

### LOCK-01: MintModule:840
```solidity
// REMOVE this line:
if (rngLockedFlag) revert E();
```
**Context:** `_callTicketPurchase()` -- the core ticket purchase entry point. With the double-buffer, purchases always write to the write slot (via `_tqWriteKey()`), which is independent of the read slot being processed. The freeze branch (Phase 3) routes pool additions to pending accumulators when `prizePoolFrozen == true`. No invariant depends on blocking purchases here.

### LOCK-02: MintModule:627
```solidity
// BEFORE:
if (lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E();
// AFTER:
if (lootBoxAmount != 0 && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E();
```
**Context:** `_purchaseFor()` -- lootbox purchase guard during jackpot resolution. The `rngLockedFlag` component is redundant because: (a) freeze branching now handles ETH routing during jackpot, and (b) the remaining `lastPurchaseDay && (purchaseLevel % 5 == 0)` condition still blocks lootbox purchases during jackpot levels. **WAIT -- re-examine this.** The original condition blocks lootbox purchases only when `rngLockedFlag` is true AND it is a jackpot level AND lastPurchaseDay. The intent was to block lootbox purchases specifically during the RNG-locked window of jackpot resolution. If we remove `rngLockedFlag`, we would block lootbox purchases for the ENTIRE lastPurchaseDay on jackpot levels, which is MORE restrictive than before. This needs careful analysis of whether the block should be removed entirely or just the rngLockedFlag component stripped.

**Decision point:** The REQUIREMENTS.md says "Remove `rngLockedFlag` revert from `_purchaseFor` lootbox gate." This means removing the `rngLockedFlag` component. The remaining `lastPurchaseDay && jackpot-level` condition may need to stay or be removed depending on whether lootbox purchases during jackpot levels are safe with the freeze infrastructure in place. Since the freeze infrastructure now handles all pool routing correctly, the entire line could potentially be removed. However, the requirement specifically says remove the `rngLockedFlag` revert, so the safest interpretation is: **remove `rngLockedFlag &&` from the compound condition**, keeping the rest.

**ACTUALLY** -- re-reading the requirement more carefully: "Remove `rngLockedFlag` revert from `_purchaseFor` lootbox gate (MintModule:627)". The whole line is the "rngLockedFlag revert" -- it only fires when rngLockedFlag is true. The simplest correct change is to delete the entire line, since the condition is specifically an rngLockedFlag-gated revert. If the user wanted to keep the jackpot-level lootbox block, it would be a separate concern. I will flag this as needing user confirmation but recommend removing the entire line.

### LOCK-03: LootboxModule:557
```solidity
// REMOVE this line:
if (rngLockedFlag) revert RngLocked();
```
**Context:** `openLootBox()`. Lootbox opens use `lootboxRngWordByIndex[index]` which is set by the mid-day lootbox VRF flow, completely independent of the daily RNG cycle. The lock was a belt-and-suspenders guard that is no longer needed.

### LOCK-04: LootboxModule:640
```solidity
// REMOVE this line:
if (rngLockedFlag) revert RngLocked();
```
**Context:** `openBurnieLootBox()`. Same rationale as LOCK-03.

### LOCK-05: DegeneretteModule:503
```solidity
// BEFORE:
jackpotResolutionActive = rngLockedFlag && lastPurchaseDay && ((level + 1) % 5 == 0);
// AFTER:
jackpotResolutionActive = lastPurchaseDay && ((level + 1) % 5 == 0);
```
**Context:** `_placeFullTicketBetsCore()`. The `jackpotResolutionActive` flag controls whether ETH Degenerette bets are blocked during jackpot resolution. With freeze infrastructure, ETH bets during jackpot resolution are safe (pool additions route to pending accumulators). However, the downstream code at line 504 and line 576 uses `jackpotResolutionActive` to block ETH-currency Degenerette bets entirely. Same analysis as LOCK-02: removing `rngLockedFlag` makes the block MORE restrictive (blocks all of lastPurchaseDay on jackpot levels, not just during RNG lock).

**Same decision point as LOCK-02.** The requirement says "Remove `rngLockedFlag` from `jackpotResolutionActive`". The freeze infrastructure handles ETH routing correctly, so the ETH block during jackpot levels may itself be unnecessary. But the safest interpretation of the requirement is to strip `rngLockedFlag &&` from the condition. The planner should flag this for the implementer.

### LOCK-06: AdvanceModule:643
```solidity
// REMOVE this line:
if (rngLockedFlag) revert E();
```
**Context:** Lootbox RNG request gate in `_requestLootboxRng()`. Line 644 (`if (rngRequestTime != 0) revert E()`) already prevents concurrent VRF requests. The `rngLockedFlag` check was redundant because: when daily RNG is in-flight, `rngRequestTime != 0` is always true (set at line 1147). Removing this eliminates one redundant SLOAD.

## What Stays (Out of Scope)

These `rngLockedFlag` references are explicitly out of scope per REQUIREMENTS.md:

| Location | Line | Why It Stays |
|----------|------|-------------|
| DegenerusGame.sol:1535 | `setDecimatorAutoRebuy` | Autorebuy/decimator -- keep locked during jackpots |
| DegenerusGame.sol:1556 | `_setAutoRebuy` | Autorebuy -- keep locked |
| DegenerusGame.sol:1571 | `_setTakeProfit` | Take profit -- keep locked |
| DegenerusGame.sol:1636 | `_setAfKing` | AfKing -- keep locked |
| DegenerusGame.sol:2199 | `rngLocked()` view | Public view function, still useful |
| DegenerusGame.sol:2241 | `decWindow()` view | Decimator window calculation |
| DegenerusGame.sol:2306 | `gameInfo()` view | Game info return value |
| AdvanceModule:129 | `purchaseLevel` calc | State machine logic, not a purchase guard |
| AdvanceModule:1148 | `rngLockedFlag = true` | Set site -- must remain |
| AdvanceModule:1215 | `rngLockedFlag = false` | Clear in `forceResetRng` |
| AdvanceModule:1227 | `rngLockedFlag = false` | Clear in `_unlockRng` |
| AdvanceModule:1239 | `reverseFlip()` guard | Not a purchase path |
| AdvanceModule:1276 | VRF callback routing | Distinguishes daily vs lootbox RNG |
| DegenerusGameStorage:266 | Variable declaration | Storage var stays |

## Architecture Patterns

### Pattern: Delete-and-Verify
**What:** Remove guard lines, update NatSpec, verify via grep + tests.
**When to use:** When infrastructure has been built to handle what the guard previously protected.

The pattern for each removal:
1. Delete/modify the specific line
2. Update the NatSpec comment above the function (remove references to RngLocked revert)
3. Remove `error RngLocked()` declaration from LootboxModule IF no other uses remain
4. Run the full test suite

### NatSpec Updates Required

| Module | Function | Update Needed |
|--------|----------|---------------|
| LootboxModule | `openLootBox` | Remove `@custom:reverts RngLocked` and "Blocked during RNG lock" from `@dev` |
| LootboxModule | `openBurnieLootBox` | Remove `@custom:reverts RngLocked` and "Blocked during RNG lock" from `@dev` |
| MintModule | `_callTicketPurchase` | (No explicit RngLocked NatSpec -- just the implicit revert) |
| MintModule | `_purchaseFor` | Remove comment on line 626 about blocking lootbox purchases during resolution |

### Error Declaration Cleanup

After LOCK-03 and LOCK-04 removals, check if `error RngLocked()` in LootboxModule (line 46) is still referenced. If not, remove it. Similarly check AdvanceModule (line 37) -- `reverseFlip()` still uses it (line 1239, out of scope), so it stays.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Verifying removal completeness | Manual code review only | `grep -n rngLockedFlag` across target files | Six sites across four files -- grep is authoritative |
| Gas comparison | Custom gas measurement | `forge snapshot` before/after | Built-in Foundry feature, gives per-test gas diffs |
| Fuzz testing purchase-during-lock | Complex integration harness | Foundry fuzz with direct storage manipulation | Harness pattern already established in Phase 4 |

## Common Pitfalls

### Pitfall 1: Removing the Entire Compound Condition Instead of Just the rngLockedFlag Component
**What goes wrong:** For LOCK-02 and LOCK-05, the removal target is `rngLockedFlag` from a compound condition, not the entire line.
**Why it happens:** The requirement says "remove rngLockedFlag revert" which could be interpreted as removing the entire line.
**How to avoid:** For compound conditions (LOCK-02, LOCK-05), strip `rngLockedFlag &&` from the condition. For simple guards (LOCK-01, LOCK-03, LOCK-04, LOCK-06), delete the entire line.
**Warning signs:** Test failures in jackpot-level lootbox or Degenerette scenarios.

### Pitfall 2: Forgetting NatSpec and Error Declaration Cleanup
**What goes wrong:** Dead NatSpec references to `RngLocked` reverts remain, confusing future readers.
**Why it happens:** Focus on the logic change, not the documentation.
**How to avoid:** Include NatSpec updates in the same task as the line removal.

### Pitfall 3: Breaking the VRF Callback Routing
**What goes wrong:** If someone accidentally removes `rngLockedFlag` from `rawFulfillRandomWords` (AdvanceModule:1276), daily RNG words would be routed to lootbox storage instead of `rngWordCurrent`.
**Why it happens:** Overzealous removal.
**How to avoid:** The six LOCK requirements are the ONLY removal sites. The plan must NOT touch AdvanceModule:1276 or any set/clear site.

### Pitfall 4: Not Taking a Gas Snapshot Baseline Before Changes
**What goes wrong:** Success criterion 4 requires "at least one fewer SSTORE per purchase compared to pre-milestone baseline." Without a baseline, this cannot be verified.
**Why it happens:** Forgetting to snapshot before making changes.
**How to avoid:** Run `forge snapshot` before any code changes in this phase and save the output. The packed pool helpers (Phase 1) already saved 1 SSTORE; removing the `rngLockedFlag` check itself saves 1 SLOAD (not SSTORE). The SSTORE savings are from the packed pools, already in the codebase.

**Important note on SC-4:** The success criterion says "at least one fewer SSTORE per purchase compared to pre-milestone baseline." The packed pool helpers (from Phase 1) already reduced SSTOREs by consolidating two separate pool writes into one packed write. This is already in the codebase. The lock removal itself saves SLOADs (reading `rngLockedFlag`), not SSTOREs. The gas snapshot should compare against the pre-Phase-1 baseline if available, or simply confirm the packed pool savings are present.

## Code Examples

### Simple Guard Removal (LOCK-01, LOCK-03, LOCK-04, LOCK-06)
```solidity
// DELETE the entire line:
if (rngLockedFlag) revert E();  // or revert RngLocked();
```

### Compound Condition Stripping (LOCK-02)
```solidity
// BEFORE (MintModule:627):
if (lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E();

// AFTER -- remove entire line (the condition is wholly rngLockedFlag-gated):
// Line deleted. Lootbox purchases during jackpot levels are now allowed;
// freeze infrastructure routes pool additions correctly.
```

### Compound Condition Stripping (LOCK-05)
```solidity
// BEFORE (DegeneretteModule:503):
jackpotResolutionActive = rngLockedFlag && lastPurchaseDay && ((level + 1) % 5 == 0);

// AFTER -- strip rngLockedFlag:
jackpotResolutionActive = lastPurchaseDay && ((level + 1) % 5 == 0);
```

### Verification Grep Command
```bash
# After changes, verify the six sites are clean:
grep -n "rngLockedFlag" contracts/modules/DegenerusGameMintModule.sol
# Expected: zero results

grep -n "rngLockedFlag" contracts/modules/DegenerusGameLootboxModule.sol
# Expected: zero results

grep -n "rngLockedFlag" contracts/modules/DegenerusGameDegeneretteModule.sol
# Expected: zero results

grep -n "rngLockedFlag" contracts/modules/DegenerusGameAdvanceModule.sol
# Expected: lines 129, 643 removed; lines 1148, 1215, 1227, 1239, 1276 remain
# Wait -- 643 IS being removed (LOCK-06). So remaining: 129, 1148, 1215, 1227, 1239, 1276
```

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
| LOCK-01 | Purchase succeeds during RNG lock | unit+fuzz | `forge test --match-test test_purchaseDuringRngLock -vvv` | Wave 0 |
| LOCK-02 | Lootbox purchase during jackpot level allowed | unit | `forge test --match-test test_lootboxPurchaseDuringJackpot -vvv` | Wave 0 |
| LOCK-03 | openLootBox succeeds during RNG lock | unit | `forge test --match-test test_openLootBoxDuringLock -vvv` | Wave 0 |
| LOCK-04 | openBurnieLootBox succeeds during RNG lock | unit | `forge test --match-test test_openBurnieLootBoxDuringLock -vvv` | Wave 0 |
| LOCK-05 | Degenerette bet routes correctly during jackpot resolution | unit | `forge test --match-test test_degeneretteDuringJackpot -vvv` | Wave 0 |
| LOCK-06 | Lootbox RNG request succeeds when daily RNG not in-flight | unit | `forge test --match-test test_lootboxRngGate -vvv` | Wave 0 |
| SC-1 | Purchase during active RNG lands in write slot | integration | `forge test --match-test test_purchaseLandsinWriteSlot -vvv` | Wave 0 |
| SC-2 | Grep returns zero rngLockedFlag in purchase paths | manual | `grep -c rngLockedFlag contracts/modules/{Mint,Lootbox}Module.sol` | N/A manual |
| SC-3 | Full fuzz suite passes | fuzz | `forge test` | Existing |
| SC-4 | Gas snapshot shows SSTORE reduction | snapshot | `forge snapshot` | Existing |

### Sampling Rate
- **Per task commit:** `forge test --match-path test/fuzz/LockRemoval.t.sol -vvv`
- **Per wave merge:** `forge test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/fuzz/LockRemoval.t.sol` -- new test file covering LOCK-01 through LOCK-06 + SC-1
- [ ] LockRemovalHarness in same file -- extends DegenerusGameStorage, exposes purchase-path simulation with `rngLockedFlag = true`
- [ ] Gas baseline: `forge snapshot > .gas-snapshot-pre-lock-removal` before code changes

## Open Questions

1. **LOCK-02 and LOCK-05: Strip vs Delete**
   - What we know: Both are compound conditions where `rngLockedFlag` is one of several terms. The requirement says "remove rngLockedFlag" from these sites.
   - What's unclear: Whether to strip just `rngLockedFlag &&` (keeping the remaining jackpot-level block) or delete the entire condition (allowing all operations during jackpot levels). With freeze infrastructure, both are safe.
   - Recommendation: For LOCK-02, delete the entire line (the whole revert is rngLockedFlag-gated -- without it, the condition never fires). For LOCK-05, strip `rngLockedFlag &&` from the assignment (the `jackpotResolutionActive` boolean is used downstream for ETH bet blocking, and `lastPurchaseDay && jackpot-level` is still a meaningful business rule independent of RNG lock state).

2. **Gas Snapshot Baseline**
   - What we know: SC-4 requires "at least one fewer SSTORE per purchase compared to pre-milestone baseline." The packed pool helpers from Phase 1 already provide this.
   - What's unclear: Whether a pre-milestone gas snapshot exists to compare against.
   - Recommendation: Take a snapshot now (post-Phase-4, pre-Phase-5) and also compare against any existing `.gas-snapshot` file. The SSTORE savings are from packed pools, not from lock removal itself.

## Sources

### Primary (HIGH confidence)
- Direct source code inspection of all six removal sites
- Grep audit of all `rngLockedFlag` references in `/contracts/`
- Prior phase research and implementation (Phases 1-4 PLAN files)
- Existing test suite (test/fuzz/*.t.sol)

### Secondary (MEDIUM confidence)
- REQUIREMENTS.md Out of Scope section for what stays

## Metadata

**Confidence breakdown:**
- Removal sites: HIGH -- direct code inspection, exact line numbers verified
- What stays: HIGH -- REQUIREMENTS.md explicitly lists out-of-scope items
- Test strategy: HIGH -- follows established Phase 1-4 harness pattern
- LOCK-02/LOCK-05 interpretation: MEDIUM -- compound condition handling needs user input

**Research date:** 2026-03-11
**Valid until:** Indefinite (codebase-specific, not library-dependent)
