# Phase 159 Plan 01: Activity Score & Quest Gas Optimization Architecture Spec

**Created:** 2026-04-01
**Requirement:** SCORE-01
**Status:** Locked -- Phases 160-162 implement against this spec

---

## 1. Score Function Input Map

`_playerActivityScore(player)` at `DegenerusGame.sol:2273` reads the following inputs:

| Input | Source | Storage Type | Gas Cost (cold/warm) | Line | Notes |
|-------|--------|-------------|---------------------|------|-------|
| `deityPassCount[player]` | Mapping SLOAD | uint16 mapping | 2,100 / 100 | L2278 | Boolean check (`!= 0`) |
| `mintPacked_[player]` | Mapping SLOAD | uint256 mapping | 2,100 / 100 | L2279 | Extracts levelCount, frozenUntilLevel, bundleType |
| `_mintStreakEffective(player, level)` | Re-reads `mintPacked_[player]` | warm mapping SLOAD | 100 | MintStreakUtils:53 | Same mapping slot as L2279, always warm |
| `level` (Slot 0) | Storage SLOAD | uint24 packed in Slot 0 | 2,100 cold / 100 warm | L2284 | Slot 0 shared with 12 other fields |
| `jackpotPhaseFlag` (Slot 0) | Storage SLOAD | bool packed in Slot 0 | 100 warm | L2182 via `_activeTicketLevel()` | Same EVM slot as `level`; warm after L2284 |
| `questView.playerQuestStates(player)` | STATICCALL to DegenerusQuests | External call | 2,600 cold + ~4,200-6,300 internal | L2324 | Only uses `questStreakRaw` (first return value); discards 3 other values |
| `affiliate.affiliateBonusPointsBest(currLevel, player)` | STATICCALL to DegenerusAffiliate | External call | 2,600 cold + ~5,200-10,500 internal | L2332-2334 | Loops up to 5 levels of `affiliateCoinEarned[lvl][player]` |

**Total baseline cost of one `_playerActivityScore` call (all cold):** ~16,000-23,600 gas

Breakdown:
- 2 mapping SLOADs cold: 4,200 gas
- 1 mapping SLOAD warm (mintPacked_ re-read): 100 gas
- 1 Slot 0 SLOAD cold (level): 2,100 gas
- 1 Slot 0 SLOAD warm (jackpotPhaseFlag): 100 gas
- questView STATICCALL: 6,800-8,900 gas (2,600 base + 2 SLOADs for activeQuests + 1 SLOAD for questPlayerState + loop overhead)
- affiliate STATICCALL: 5,200-13,100 gas (2,600 base + 1-5 mapping SLOADs for affiliateCoinEarned)

On the purchase path, many of these are warm from prior reads. Realistic purchase-path cost: ~11,700+ gas per call with warm mappings.

---

## 2. Score Consumer Catalog

All 9 known consumers of `playerActivityScore` / `_playerActivityScoreInternal`:

| # | Consumer | File:Line | Call Pattern | On Purchase Path? | Action |
|---|----------|-----------|-------------|-------------------|--------|
| 1 | Lootbox EV snapshot | MintModule:709 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | Yes (lootbox purchase) | OPTIMIZE -- cache and reuse |
| 2 | Affiliate lootbox routing | MintModule:781 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | Yes (lootbox affiliate) | OPTIMIZE -- reuse cached value from #1 |
| 3 | x00 century bonus | MintModule:886 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | Yes (ticket at x00 level) | OPTIMIZE -- reuse cached or compute once |
| 4 | Lootbox EV multiplier | LootboxModule:457 | `IDegenerusGame(address(this)).playerActivityScore(player)` | No (lootbox open, separate tx) | INDIRECT BENEFIT -- internal function becomes cheaper |
| 5 | Whale bundle EV | WhaleModule:735 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | No (whale purchase, separate flow) | INDIRECT BENEFIT -- internal function becomes cheaper |
| 6 | Decimator burn | DecimatorModule:718 | `IDegenerusGame(address(this)).playerActivityScore(player)` | No (decimator, separate tx) | INDIRECT BENEFIT -- internal function becomes cheaper |
| 7 | BurnieCoin decimator | BurnieCoin:611 | `degenerusGame.playerActivityScore(caller)` | No (external contract, separate tx) | NO CHANGE -- external consumer, cannot modify call |
| 8 | sDGNRS claim | StakedDegenerusStonk:800 | `game.playerActivityScore(beneficiary)` | No (external contract, separate tx) | NO CHANGE -- external consumer, cannot modify call |
| 9 | Degenerette score | DegeneretteModule:473 | `_playerActivityScoreInternal(player)` | No (degenerette bet) | ELIMINATE DUPLICATE -- replace with shared implementation |

**Purchase-path consumers (3):** #1, #2, #3 -- these are the optimization targets for compute-once caching.

**Non-purchase consumers (3):** #4, #5, #6 -- benefit indirectly from a cheaper internal `_playerActivityScore` (quest STATICCALL elimination, deityPassCount SLOAD elimination).

**External consumers (2):** #7, #8 -- call the external `playerActivityScore(address)` view. Signature MUST NOT change. These consumers benefit from cheaper internals but cannot be modified.

**Duplicate (1):** #9 -- uses a private copy that must be eliminated.

---

## 3. Packed Struct Investigation

### 3a. Score-Only Packing: Merge `deityPassCount` into `mintPacked_`

**Current `mintPacked_` bit layout** (from BitPackingLib.sol):

```
[0-23]    lastLevel              uint24   (LAST_LEVEL_SHIFT)
[24-47]   levelCount             uint24   (LEVEL_COUNT_SHIFT)
[48-71]   levelStreak            uint24   (LEVEL_STREAK_SHIFT)
[72-103]  lastMintDay            uint32   (DAY_SHIFT)
[104-127] unitsLevel             uint24   (LEVEL_UNITS_LEVEL_SHIFT)
[128-151] frozenUntilLevel       uint24   (FROZEN_UNTIL_LEVEL_SHIFT)
[152-153] whaleBundleType        uint2    (WHALE_BUNDLE_TYPE_SHIFT)
[154-159] (unused)               6 bits
[160-183] mintStreakLastCompleted uint24   (MINT_STREAK_LAST_COMPLETED_SHIFT)
[184-227] (unused)               44 bits
[228-243] levelUnits             uint16   (LEVEL_UNITS_SHIFT)
[244-255] (reserved)             12 bits
```

**Available bits:** 154-159 (6 bits) + 184-227 (44 bits) = 50 unused bits total.

**`deityPassCount` type:** uint16 (16 bits). Maximum value: 65,535. Fits within the 44 unused bits at 184-227.

**Proposed bit assignment:** Bits 184-199 for `deityPassCount` (16 bits within the 44-bit unused range at 184-227).

```
NEW CONSTANT:  DEITY_PASS_COUNT_SHIFT = 184
READ:          uint16(packed >> 184) & MASK_16
WRITE:         BitPackingLib.setPacked(packed, 184, MASK_16, newCount)
```

**Savings per score computation:** 1 cold mapping SLOAD eliminated (2,100 gas cold, 100 gas warm). The `deityPassCount[player]` read at DegenerusGame.sol:2278 is replaced by a bit extraction from the already-loaded `mintPacked_[player]` at L2279.

**Migration cost:** All `deityPassCount[player]` read/write sites must change. These are:

| Site | File | Line | Operation |
|------|------|------|-----------|
| Score check | DegenerusGame.sol | L2278 | Read (boolean check) |
| Score check | DegeneretteModule.sol | L1074 | Read (boolean check, in duplicate) |
| Deity pass claim | DegenerusGame.sol | TBD | Write (increment on claim) |
| Deity pass view | DegenerusGame.sol | TBD | Read (view function) |

**Recommendation: INCLUDE in Phase 160.** The 2,100 gas cold savings per score call is significant, and the migration is mechanical (4-6 sites, all bit-shift operations following established BitPackingLib patterns). Bit position 184 avoids collision with MINT_STREAK_LAST_COMPLETED (160-183) and LEVEL_UNITS (228-243).

### 3b. Combined Score+Quest Packing

Quest streak lives in `DegenerusQuests` (a separate contract, not delegatecall). Co-location options:

**Option A: Duplicate write.** DegenerusQuests writes streak to its own storage AND writes a copy into Game storage via a callback.
- Cost: Extra SSTORE (2,900-5,000 gas depending on dirty/clean) on every quest completion.
- Benefit: Eliminates the 6,800-8,900 gas STATICCALL in `_playerActivityScore`.
- Net: Breakeven to slightly worse. Quest completions happen less frequently than score reads, but the SSTORE cost is high.

**Option B: Parameter forwarding.** `handleMint` and `handleLootBox` already return `streak` as their third return value (confirmed in IDegenerusQuests.sol:57-59). Currently discarded at MintModule:1115. Capture it and forward to `_playerActivityScore` as a parameter.
- Cost: Zero storage overhead. Only stack parameter passing (~3-5 gas per parameter).
- Benefit: Eliminates the entire 6,800-8,900 gas STATICCALL.
- Net: Pure savings of 6,800-8,900 gas per score computation on the purchase path.

**Recommendation: Parameter forwarding is strictly better for quest streak. Combined score+quest packing is NOT recommended.** The cross-contract boundary makes co-location more expensive than forwarding. Score-only packing (deityPassCount into mintPacked_) IS recommended.

---

## 4. Caching Strategy: Parameter Forwarding Chain

The purchase path parameter forwarding chain for score computation:

```
_purchaseFor(buyer, qty, lootbox, affiliate, payKind)          [MintModule:631]
  |
  |-- Read ONCE: level (Slot 0) -> cachedLevel=level+1         L640
  |-- Read ONCE: price (Slot 1) -> priceWei                    L641
  |-- Read ONCE: claimableWinnings[buyer] -> initialClaimable   L654
  |
  |-- _callTicketPurchase(buyer, ...)                           L685
  |     |-- Read ONCE (Slot 0): jackpotPhaseFlag, jackpotCounter,
  |     |     compressedJackpotFlag, rngLockedFlag              L847-852
  |     |-- Execute affiliate routing (payAffiliate calls)      L968-1004
  |     |-- _questMint -> quests.handleMint                     L914/L943
  |     |     -> capture questStreak from return value (3rd arg)
  |     |-- [if x00] cachedScore = _playerActivityScore(buyer, questStreak)  L886
  |     |-- Return (bonusCredit, cachedScore, questStreak)  // NEW return values
  |
  |-- [if lootbox path]
  |     |-- _questMint from lootbox portion                     L803
  |     |     -> capture lbMintStreak (if available)
  |     |-- quests.handleLootBox(buyer, lootBoxAmount)          L810
  |     |     -> capture lbStreak from return value
  |     |-- COMPUTE score AFTER handlers:
  |     |     effectiveStreak = lbStreak (most recent)
  |     |     cachedScore = cachedScore OR _playerActivityScore(buyer, effectiveStreak)
  |     |-- Use cachedScore at L709 site (lootbox EV snapshot)
  |     |-- Use cachedScore at L781 site (affiliate routing)
  |
  |-- Reuse initialClaimable for final claimable calc           L818-820
```

**WHERE score is computed:** Inside `_callTicketPurchase` (for x00 bonus) or in `_purchaseFor` (for lootbox path), exactly ONCE, AFTER quest handlers have executed.

**HOW it reaches consumers:** Returned from `_callTicketPurchase` as a `uint256` return value, reused in the lootbox path section of `_purchaseFor` as a local variable.

### Ordering Constraint (Pitfall 4)

**Current ordering on lootbox path:** Score is called at L709 and L781 BEFORE `handleLootBox` at L810. If forwarding streak from `handleLootBox`, the score computation must move AFTER the handler call.

**Behavioral impact analysis:**
- Current: Lootbox EV snapshot at L709 uses the pre-lootbox-handler score. The `handleLootBox` call may complete a quest and increment streak. The score stored in `lootboxEvScorePacked` reflects the player's score BEFORE this lootbox purchase's quest effect.
- Proposed: Score computed AFTER `handleLootBox` reflects the post-action streak. If the lootbox purchase completes a quest, the stored EV snapshot includes that newly incremented streak.

**Resolution:** The difference is at most 1 streak level (100 BPS). The lootbox EV multiplier formula in LootboxModule has a gradual slope (~0.2% EV change per 100 BPS). This is a negligible behavioral change that slightly rewards active players. The `handleMint` call within `_callTicketPurchase` (L914/L943) already runs before the x00 bonus score call (L886), so the ticket path already uses post-action score. **Accept post-action score uniformly for both paths.** Document as intentional: score reflects all quest progress within the current purchase transaction.

### Pitfall 2: handleMint Streak Is Post-Action

The streak returned from `handleMint` / `handleLootBox` is the post-action value (quest may complete and increment streak during the handler). This is acceptable because:
1. The ticket path already uses post-action state: `_questMint` at L943 runs before `playerActivityScore` at L886.
2. Using post-action streak gives consistent behavior: the player's current purchase contributes to their own score.
3. The external `playerActivityScore(address)` view fetches streak from `questView.playerQuestStates` which also returns post-any-pending-action state.

---

## 5. Cross-Contract Call Elimination

### 5a. Quest Streak Elimination (RECOMMENDED -- per D-07, D-08)

**Current:** `questView.playerQuestStates(player)` STATICCALL at DegenerusGame.sol:2324.
**Cost:** 6,800-8,900 gas per call.
**Observation:** Only the first return value (`questStreakRaw`) is used. The other 3 (lastCompletedDay, progress[2], completed[2]) are discarded.

**Proposed:** Capture `streak` return value from `handleMint` / `handleLootBox` (already returned as 3rd value, currently discarded at MintModule:1115 and L810). Forward as parameter to `_playerActivityScore`.

**Changes required:**

1. **`_questMint` (MintModule:1114):** Change from:
   ```solidity
   (uint256 reward, uint8 questType,, bool completed) = quests.handleMint(player, quantity, paidWithEth);
   ```
   To capture streak:
   ```solidity
   (uint256 reward, uint8 questType, uint32 questStreak, bool completed) = quests.handleMint(player, quantity, paidWithEth);
   ```
   Return `questStreak` to caller (add to return values or refactor to struct return).

2. **`handleLootBox` call (MintModule:810):** Change from:
   ```solidity
   (uint256 lbReward,,, bool lbCompleted) = quests.handleLootBox(buyer, lootBoxAmount);
   ```
   To capture streak:
   ```solidity
   (uint256 lbReward,, uint32 lbStreak, bool lbCompleted) = quests.handleLootBox(buyer, lootBoxAmount);
   ```

3. **`_playerActivityScore` (DegenerusGame.sol:2273):** Add `uint32 questStreak` parameter. Remove `questView.playerQuestStates(player)` STATICCALL at L2324. Use the parameter directly:
   ```solidity
   function _playerActivityScore(
       address player,
       uint32 questStreak
   ) internal view returns (uint256 scoreBps)
   ```

4. **External `playerActivityScore(address)` view (DegenerusGame.sol:2267):** Keep as backward-compatible wrapper. Internally fetches streak via `questView.playerQuestStates` and forwards:
   ```solidity
   function playerActivityScore(address player) external view returns (uint256 scoreBps) {
       (uint32 streak, , , ) = questView.playerQuestStates(player);
       return _playerActivityScore(player, streak);
   }
   ```
   This preserves the `playerActivityScore(address)` signature for BurnieCoin (L611) and StakedDegenerusStonk (L800).

**Savings:** 6,800-8,900 gas per purchase-path score computation eliminated.

### 5b. Affiliate Bonus Elimination (NOT RECOMMENDED -- per D-08 research)

**Current:** `affiliate.affiliateBonusPointsBest(currLevel, player)` STATICCALL at DegenerusGame.sol:2332.
**Cost:** 5,200-13,100 gas (2,600 base + 1-5 mapping SLOADs).

**Why NOT eliminate:**
1. The affiliate contract address is warm on the purchase path from prior `payAffiliate` calls (L968-1004). The STATICCALL base cost is only 100 gas (warm), not 2,600.
2. The real cost is internal: 1-5 mapping SLOADs of `affiliateCoinEarned[lvl][player]` (~2,100-10,500 gas). Co-locating this data in Game storage would require an SSTORE (2,900-5,000 gas) on every `payAffiliate` call.
3. Parameter forwarding from `payAffiliate` is problematic: `payAffiliate` writes to `affiliateCoinEarned` before score computation reads it. The ordering matters -- forwarding pre-write values would give stale data, and computing during `payAffiliate` adds complexity for marginal benefit.
4. The affiliate bonus is a relatively small BPS component (max 50 BPS via AFFILIATE_BONUS_MAX constant), and the STATICCALL overhead is the warm-address 100 gas base, not the cold 2,600.

**Decision:** ACCEPT the affiliate STATICCALL. This is a conscious architectural decision. The internal SLOADs (~2,100-10,500 gas) are the real cost, and they cannot be eliminated without data co-location whose SSTORE overhead exceeds the savings. Potential future optimization only if affiliate storage is restructured for other reasons.

---

## 6. SLOAD Deduplication Catalog

Every duplicate storage read on the purchase path, with caching strategy:

| Variable | Current Reads | Lines | Single Read Location | Caching Method | Savings |
|----------|--------------|-------|---------------------|----------------|---------|
| `level` (Slot 0) | 5-6x | L640, L847, L855, L859, L707, L750 | `_purchaseFor` entry (L640) as `purchaseLevel = level + 1` | Parameter passing to `_callTicketPurchase` and lootbox path | 4-5 warm SLOADs = 400-500 gas |
| `price` (Slot 1) | 3x | L641, L861, L1059 | `_purchaseFor` entry (L641) as `priceWei` | Parameter passing to `_callTicketPurchase` (L861 already uses local but reads storage again) | 2 warm SLOADs = 200 gas |
| `compressedJackpotFlag` (Slot 0) | 3x | L852, L955, L958 | `_callTicketPurchase` entry | Local variable within `_callTicketPurchase` | 2 warm SLOADs = 200 gas |
| `jackpotCounter` (Slot 0) | 2x | L851, L957 | `_callTicketPurchase` entry | Local variable within `_callTicketPurchase` | 1 warm SLOAD = 100 gas |
| `jackpotPhaseFlag` (Slot 0) | 2x | L847, L955 | `_callTicketPurchase` entry | Local variable within `_callTicketPurchase` | 1 warm SLOAD = 100 gas |
| `claimableWinnings[buyer]` | 2-3x | L654, L673, L820 | `_purchaseFor` entry (L654) as `initialClaimable` | Local variable in `_purchaseFor`; L673 shortfall branch re-reads (can use local instead) | 1-2 warm SLOADs = 100-200 gas |
| `mintPacked_[player]` | 2x | score:L2279, MintStreakUtils:53 | `_playerActivityScore` entry (L2279) | Pass raw packed uint256 to `_mintStreakEffective` instead of address | 1 warm SLOAD = 100 gas |
| `playerActivityScore()` calls | 2-3x | L709, L781, L886 | Compute once after quest handlers | Return cached score; reuse in lootbox path | ~11,700-23,400+ gas per eliminated call |

**Slot 0 note:** All Slot 0 variables (`level`, `jackpotPhaseFlag`, `jackpotCounter`, `compressedJackpotFlag`, `rngLockedFlag`) share one EVM slot. The FIRST access to any Slot 0 variable costs 2,100 gas (cold). All subsequent Slot 0 reads cost 100 gas (warm). Warm SLOADs are 100 gas each, NOT free (Pitfall 1). The savings from local variable caching of Slot 0 fields are 100 gas per eliminated warm SLOAD.

**The dominant savings are:**
1. **Eliminating redundant `playerActivityScore` calls** (~11,700+ gas each): up to 2-3 calls on a lootbox purchase at x00 level
2. **Eliminating quest STATICCALL** from score computation: 6,800-8,900 gas per call
3. **deityPassCount SLOAD elimination** via mintPacked_ packing: 2,100 gas cold

SLOAD dedup of warm reads (Slot 0/1 variables) provides ~1,200-1,500 gas savings -- modest but improves code quality by making data flow explicit.

---

## 7. DegeneretteModule Duplicate Elimination

### Current State

- **Canonical:** `_playerActivityScore(player)` at DegenerusGame.sol:2273 uses `_activeTicketLevel()` for streak base level
- **Duplicate:** `_playerActivityScoreInternal(player)` at DegeneretteModule.sol:1069 uses `level + 1` for streak base level
- `_activeTicketLevel()` at DegenerusGame.sol:2182 returns `jackpotPhaseFlag ? level : level + 1`

**Semantic difference (Pitfall 5):**
- During purchase phase (`jackpotPhaseFlag=false`): both produce `level + 1` -- identical
- During jackpot phase (`jackpotPhaseFlag=true`): canonical uses `level`, duplicate uses `level + 1` -- DIFFERENT

The DegeneretteModule intentionally uses `level + 1` because degenerette bets always target the next level regardless of game phase. This preserves consistent streak credit for degenerette players.

**Other differences:** The constant names differ (`PASS_STREAK_FLOOR_POINTS` vs `WHALE_PASS_STREAK_FLOOR_POINTS`, `PASS_MINT_COUNT_FLOOR_POINTS` vs `WHALE_PASS_MINT_COUNT_FLOOR_POINTS`) but all evaluate to the same values (50 and 25 respectively). The visibility differs (`internal` vs `private`). The logic is otherwise identical line-for-line.

### Design: Add `streakBaseLevel` Parameter

The shared implementation accepts `streakBaseLevel` as a parameter:

```solidity
/// Internal: Full implementation with all parameters
function _playerActivityScore(
    address player,
    uint32 questStreak,
    uint24 streakBaseLevel
) internal view returns (uint256 scoreBps)
```

```solidity
/// Internal: Convenience wrapper for standard callers (uses _activeTicketLevel)
function _playerActivityScore(
    address player,
    uint32 questStreak
) internal view returns (uint256 scoreBps) {
    return _playerActivityScore(player, questStreak, _activeTicketLevel());
}
```

```solidity
/// External: Backward-compatible view for BurnieCoin / StakedDegenerusStonk
function playerActivityScore(
    address player
) external view returns (uint256 scoreBps) {
    (uint32 streak, , , ) = questView.playerQuestStates(player);
    return _playerActivityScore(player, streak, _activeTicketLevel());
}
```

**Caller routing:**

| Caller | Passes `streakBaseLevel` as | Passes `questStreak` as |
|--------|---------------------------|------------------------|
| DegenerusGame (purchase path, x00 bonus) | `_activeTicketLevel()` (via 2-arg convenience) | Forwarded from `handleMint` return |
| DegeneretteModule (degenerette bet) | `level + 1` (explicit, preserves semantic) | Forwarded from quest handler or fetched via view |
| External view (BurnieCoin, sDGNRS) | `_activeTicketLevel()` | Fetched via `questView.playerQuestStates` |
| LootboxModule, WhaleModule, DecimatorModule | `_activeTicketLevel()` (via external view) | Fetched via `questView.playerQuestStates` (in external wrapper) |

**DegeneretteModule access pattern:** DegeneretteModule currently uses a private function because it cannot call `_playerActivityScore` (which is internal to DegenerusGame.sol). After consolidation, DegeneretteModule calls the 3-arg internal version directly since all modules share storage via delegatecall and can access internal functions defined in shared inherited contracts. The function must be moved to `DegenerusGameStorage.sol` or a new shared utility contract that both DegenerusGame and DegeneretteModule inherit.

**Alternatively:** DegeneretteModule calls `IDegenerusGame(address(this)).playerActivityScore(player)` via external self-call (same pattern as other modules). This uses the external view wrapper, which always uses `_activeTicketLevel()` not `level + 1`. To preserve the semantic difference, either:
1. Add an overloaded external view: `playerActivityScore(address player, uint24 streakBaseLevel)` callable by modules
2. Move the internal function to a shared base contract

Option 1 adds ABI surface. Option 2 is cleaner. **Recommendation: Option 2 -- move to shared base contract.**

---

## 8. Phase Dependency Matrix

| Optimization | Phase | Depends On | Can Proceed Independently? |
|-------------|-------|------------|---------------------------|
| Score compute-once + quest streak forwarding | 160 | This spec (159) | Yes, after spec locked |
| deityPassCount into mintPacked_ packing | 160 | This spec (159) | Yes, part of score consolidation |
| DegeneretteModule duplicate elimination | 160 | This spec (159) | Yes, part of score consolidation |
| Quest handler merging + mintPrice passthrough | 161 | This spec (159) | Yes, after spec locked |
| SLOAD dedup (Slot 0/1 vars, claimableWinnings) | 162 | This spec (159) | Yes, after spec locked |

### File Ownership Per Phase

| File | Phase 160 (Score) | Phase 161 (Quest) | Phase 162 (SLOAD) |
|------|-------------------|--------------------|--------------------|
| DegenerusGame.sol | Modify: `_playerActivityScore` (add params), external view wrapper, move to shared base | - | - |
| DegenerusGameStorage.sol (or new shared base) | Add: shared `_playerActivityScore` with 3-arg signature | - | - |
| MintModule.sol | Modify: score call sites (L709, L781, L886), `_questMint` return handling (capture streak) | Modify: `_questMint` call site (handler merging), `handleLootBox` call site | Modify: `_purchaseFor` (local caching), `_callTicketPurchase` (local caching) |
| DegeneretteModule.sol | Delete: `_playerActivityScoreInternal`, replace with shared call | - | - |
| DegenerusQuests.sol | - | Modify: merged handler implementation | - |
| IDegenerusQuests.sol | - | Modify: new merged handler signature | - |
| BitPackingLib.sol | Add: `DEITY_PASS_COUNT_SHIFT = 184`, `MASK_16` reference | - | - |

### Conflict Zone: MintModule

MintModule is touched by all 3 phases. Ordering matters:

1. **Phase 160 FIRST:** Changes `_questMint` return handling (capture streak), score call sites (cache and reuse), deityPassCount bit packing. These changes affect the function signatures and return values that Phase 161 builds on.
2. **Phase 161 SECOND:** Changes handler call pattern (merged quest handler), `_questMint` call site restructuring. Builds on Phase 160's streak-capture changes.
3. **Phase 162 LAST:** Caches local variables (`level`, `price`, `compressedJackpotFlag`, etc.) in `_purchaseFor` and `_callTicketPurchase`. This is purely mechanical caching that works regardless of call pattern changes from Phase 160/161.

Phase 162 is fully independent of Phase 160 and Phase 161's structural changes -- it only caches values that are read from the same storage slots regardless of how the call graph is structured.

---

## 9. Gas Savings Summary

| Optimization | Per-Call Savings | Frequency (per purchase) | Net Savings |
|-------------|-----------------|-------------------------|-------------|
| Eliminate 1-2 redundant `playerActivityScore` calls | ~11,700+ each | 1-2 eliminated | 11,700-23,400+ |
| Eliminate `questView.playerQuestStates` STATICCALL | ~6,800-8,900 | 1 per score call | 6,800-8,900 |
| Pack `deityPassCount` into `mintPacked_` | 2,100 (cold SLOAD) | 1 per score call | 2,100 |
| SLOAD dedup: `level` (4-5 warm reads) | ~100 each | 4-5 eliminated reads | 400-500 |
| SLOAD dedup: `price` (2 warm reads) | ~100 each | 2 eliminated reads | 200 |
| SLOAD dedup: `compressedJackpotFlag` (2 warm reads) | ~100 each | 2 eliminated reads | 200 |
| SLOAD dedup: `jackpotCounter` (1 warm read) | ~100 | 1 eliminated read | 100 |
| SLOAD dedup: `jackpotPhaseFlag` (1 warm read) | ~100 | 1 eliminated read | 100 |
| SLOAD dedup: `claimableWinnings` (1-2 warm reads) | ~100 each | 1-2 eliminated reads | 100-200 |
| SLOAD dedup: `mintPacked_` (1 warm read in score) | ~100 | 1 eliminated read | 100 |
| **Total estimated savings (worst case: lootbox at x00)** | | | **~22,800-35,800+** |
| **Total estimated savings (typical purchase, no lootbox)** | | | **~11,700-14,000** |

**Key insight:** The dominant savings come from eliminating redundant score computations (~11,700+ per eliminated call) and cross-contract calls (~6,800-8,900 for quest streak). Phase 162 (SLOAD dedup of warm reads) provides the smallest gas savings (~1,200-1,500 total) but the cleanest code quality improvement by making data flow explicit through parameter passing instead of repeated storage reads.

---

## 10. Open Questions for Implementation

These are implementation-level choices that Phases 160-162 make. All architectural decisions are locked above.

1. **Parameter naming conventions:** Suggested names for new parameters:
   - `cachedLevel` / `targetLevel` -- forwarded level from `_purchaseFor`
   - `cachedPrice` / `priceWei` -- forwarded price (already named `priceWei` at L641)
   - `cachedScore` -- cached `_playerActivityScore` result
   - `questStreak` -- streak captured from quest handler return value
   - `streakBaseLevel` -- level passed to shared score function for streak calculation

2. **Return value structure from `_callTicketPurchase`:** Currently returns `uint256 bonusCredit`. After Phase 160, needs to also return `cachedScore` and `questStreak`. Options:
   - Multiple return values: `returns (uint256 bonusCredit, uint256 cachedScore, uint32 questStreak)`
   - Struct return: `struct TicketPurchaseResult { uint256 bonusCredit; uint256 cachedScore; uint32 questStreak; }`
   - Phase 160 decides based on stack depth constraints.

3. **Lootbox EV snapshot timing:** Current behavior at L709 captures score BEFORE `handleLootBox` runs at L810. After reordering (Section 4), score is captured AFTER handlers. This means a player completing a quest during a lootbox purchase gets a slightly higher EV snapshot stored in `lootboxEvScorePacked`. This is a minor behavioral change (~0.2% EV difference per streak level) that consistently rewards active players. **Recommended: Accept post-action score.** Document in the Phase 160 plan.

---

## Traceability

### Requirement Coverage

| Requirement | Sections | Status |
|-------------|----------|--------|
| SCORE-01 | 1, 2, 3, 4, 5, 6, 7, 8 | Covered -- every storage read catalogued, packing investigated, caching designed, phase dependencies documented |

### Decision Traceability

| Decision | Section | Honored? | Verification |
|----------|---------|----------|-------------|
| D-01 | 1, 2 | Yes | Purchase-path-first analysis; all 9 consumers enumerated in Section 2 |
| D-02 | 2 | Yes | All 9 consumers listed with file:line, call pattern, and optimization action |
| D-03 | 3 | Yes | Both score-only (3a) and combined score+quest (3b) packing investigated; score-only recommended, combined rejected |
| D-04 | 3, 1 | Yes | mintPacked_ layout analyzed, deityPassCount packing proposed (bits 184-199), level analyzed (Section 1), quest streak analyzed (Section 3b), affiliate analyzed (Section 5b) |
| D-05 | 4 | Yes | Stack-passed parameters as primary caching; no transient storage (Paris EVM confirmed) |
| D-06 | 4 | Yes | WHERE: after quest handlers in `_callTicketPurchase` or `_purchaseFor`; HOW: parameter passing chain diagrammed |
| D-07 | 5 | Yes | Parameter forwarding primary (quest streak from handleMint/handleLootBox); data co-location rejected for combined packing |
| D-08 | 5a, 5b | Yes | Quest streak: eliminate via parameter forwarding (5a); affiliate bonus: accept STATICCALL (5b) with justification |
| D-09 | 6 | Yes | Every duplicate catalogued with exact line numbers and read counts |
| D-10 | 6 | Yes | Each duplicate has: (a) single read location, (b) caching method (parameter or local variable), (c) gas savings |
| D-11 | 7 | Yes | `streakBaseLevel` parameter preserves `level + 1` behavior for DegeneretteModule; 3-arg shared implementation specified |

### ROADMAP Success Criteria

| Criterion | Section | Addressed? |
|-----------|---------|-----------|
| 1. Every storage slot and cross-contract call involved in playerActivityScore computation is catalogued with current gas cost | 1 | Yes -- 7 inputs mapped with gas costs, total baseline computed |
| 2. A concrete packed struct layout (or justified rejection of packing) is specified | 3 | Yes -- deityPassCount into mintPacked_ at bits 184-199 (recommended); combined score+quest rejected with justification |
| 3. The caching strategy for score reuse across consumers within a single transaction is designed | 4 | Yes -- parameter forwarding chain diagrammed; WHERE and HOW specified |
| 4. Dependencies between SCORE, QUEST, and SLOAD optimizations are documented | 8 | Yes -- phase dependency matrix with file ownership and ordering constraints |

### Research Pitfall Mitigation

| Pitfall | Section | Mitigated? | How |
|---------|---------|-----------|-----|
| 1. Warm SLOADs not free (100 gas, not 0) | 6 | Yes | Section 6 explicitly notes "Warm SLOADs are 100 gas each, NOT free" and counts 100 gas per eliminated read |
| 2. handleMint streak is post-action | 4 | Yes | Section 4 documents post-action streak behavior, confirms acceptability, and notes consistency with existing ticket-path ordering |
| 3. Breaking external consumers | 5a, 7 | Yes | External `playerActivityScore(address)` view preserved as backward-compatible wrapper; BurnieCoin and StakedDegenerusStonk unchanged |
| 4. Ordering dependency (quest handlers BEFORE score) | 4 | Yes | Section 4 specifies quest handlers run BEFORE score computation; lootbox path reordering documented with behavioral impact analysis |
| 5. DegeneretteModule streak base divergence | 7 | Yes | `streakBaseLevel` parameter preserves `level + 1` for DegeneretteModule; semantic difference explicitly documented |

### Research Open Questions Resolution

| Question | Section | Status |
|----------|---------|--------|
| Q1: Affiliate bonus -- accept or eliminate? | 5b | Resolved -- ACCEPT the STATICCALL; co-location too expensive |
| Q2: Lootbox path score ordering | 4, 10.3 | Resolved -- accept post-action score; behavioral impact is ~0.2% EV per streak level |
| Q3: Packed struct cost/benefit for score+quest | 3b | Resolved -- parameter forwarding strictly better; combined packing NOT recommended |
