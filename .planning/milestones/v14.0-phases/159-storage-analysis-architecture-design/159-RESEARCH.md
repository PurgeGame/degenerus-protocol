# Phase 159: Storage Analysis & Architecture Design - Research

**Researched:** 2026-04-01
**Domain:** Solidity storage layout analysis, EVM gas optimization, struct packing
**Confidence:** HIGH

## Summary

Phase 159 is a design-only phase that produces an architecture spec for gas optimization of the activity score computation and quest handling on the purchase path. The research below catalogues the storage layout, cross-contract call graph, and SLOAD patterns from direct source code analysis.

The codebase is Solidity 0.8.34 targeting Paris EVM (no transient storage, no PUSH0). All game modules execute via delegatecall and share storage defined in `DegenerusGameStorage.sol`. The `_playerActivityScore` function reads from 4 data sources: `mintPacked_[player]` (1 mapping SLOAD), `deityPassCount[player]` (1 mapping SLOAD), `questView.playerQuestStates(player)` (1 cross-contract STATICCALL to DegenerusQuests), and `affiliate.affiliateBonusPointsBest(level, player)` (1 cross-contract STATICCALL to DegenerusAffiliate). The storage variable `level` is read from Slot 0 (shared with 12 other packed fields).

**Primary recommendation:** The design spec should specify: (1) a parameter-forwarding chain where quest streak is captured from `handleMint`/`handleLootBox` return values and passed into score computation, (2) affiliate bonus forwarded similarly or accepted as a non-eliminable cross-contract call, (3) score computed once in `_purchaseFor` and passed as a stack parameter to all downstream consumers, (4) SLOAD deduplication via local variable caching within `_callTicketPurchase`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Purchase-path-first analysis with a complete consumer catalog. The purchase path (MintModule._purchaseFor + _callTicketPurchase) is the hot path and primary optimization target, but the design must enumerate ALL playerActivityScore consumers to ensure no non-purchase path breaks.
- **D-02:** Current known consumers: MintModule (3 sites: lootbox EV score L709, claimable payment L781, x00 century bonus L886), LootboxModule (L457), DegeneretteModule (L473, uses duplicate _playerActivityScoreInternal), WhaleModule (L735), BurnieCoin.sol (L611), StakedDegenerusStonk (L800).
- **D-03:** Investigate BOTH score-only packing AND combined score+quest packing, then recommend based on gas savings vs complexity.
- **D-04:** The packed struct analysis must account for: mintPacked_ (already packed per-player), deityPassCount, level, quest streak (currently external call to questView.playerQuestStates), affiliate bonus (currently external call to affiliate.affiliateBonusPointsBest).
- **D-05:** Stack-passed parameters as primary caching strategy. Paris EVM target means NO transient storage (EIP-1153 requires Cancun+).
- **D-06:** The design must specify WHERE the score is computed once (which function), and HOW it reaches all downstream consumers (parameter passing chain).
- **D-07:** Parameter forwarding as primary approach, with data co-location as fallback.
- **D-08:** Two external calls to eliminate from _playerActivityScore: (1) questView.playerQuestStates(player) for quest streak, (2) affiliate.affiliateBonusPointsBest(currLevel, player) for affiliate bonus.
- **D-09:** The design spec must catalog every duplicate SLOAD on the purchase path with exact line numbers and read counts.
- **D-10:** For each duplicate, the spec must propose: (a) where the single read occurs, (b) how the cached value reaches all consumers, (c) whether the fix is parameter-passing or local-variable-based.
- **D-11:** _playerActivityScoreInternal (DegeneretteModule:1069) is a near-exact duplicate of _playerActivityScore (DegenerusGame:2273). The design must specify how to eliminate this duplicate while preserving the streak base difference.

### Claude's Discretion
- Whether to use static SLOAD counting from source code or supplement with forge gas traces for actual numbers
- Format and structure of the design spec document
- Level of detail in the packed struct bit allocation map
- Whether to include a gas savings estimate per optimization or just structural decisions

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCORE-01 | Activity score inputs consolidated into minimal storage reads (investigate unified packed struct for score + quest data) | Full storage layout mapping below; mintPacked_ already packs 6 fields in 256 bits with 74 bits unused; quest streak lives in external contract (DegenerusQuests) making co-location require data migration or parameter forwarding; analysis of both approaches provided |
</phase_requirements>

## Project Constraints (from CLAUDE.md / Memory)

- **No contract commits without approval:** NEVER commit contracts/ or test/ changes without explicit user approval
- **Present fix and wait:** Present fix and wait for explicit approval before editing code
- **No dead guards:** Remove unreachable safety caps; don't waste gas on dead branches
- **ContractAddresses.sol hands-off:** NEVER checkout/restore/modify ContractAddresses.sol
- **Comments describe what IS:** Never what changed or what it used to be
- **Paris EVM target:** Confirmed in foundry.toml (`evm_version = "paris"`); no EIP-1153 transient storage, no PUSH0

**Phase 159 is design-only -- no code changes.** These constraints are documented for downstream implementation phases (160-162).

## EVM Gas Cost Reference

All gas costs below use post-EIP-2929 pricing (active since Berlin, applies to Paris target):

| Operation | Gas (Cold) | Gas (Warm) | Notes |
|-----------|-----------|-----------|-------|
| SLOAD | 2,100 | 100 | First vs subsequent read of same slot in tx |
| SSTORE (0->nonzero) | 22,100 | 20,000 | New storage allocation |
| SSTORE (nonzero->nonzero) | 5,000 | 2,900 | Update existing value |
| STATICCALL (cold address) | 2,600 | 100 | First call to external contract |
| STATICCALL (warm address) | 100 | 100 | Subsequent call to same address |
| Memory/stack ops | 3-5 | 3-5 | MLOAD, MSTORE, stack manipulation |

**Critical nuance for Slot 0:** All 13 variables packed in Slot 0 (level, jackpotPhaseFlag, compressedJackpotFlag, jackpotCounter, etc.) share one 32-byte EVM storage slot. The first SLOAD of ANY Slot 0 variable warms the slot -- subsequent reads of OTHER Slot 0 variables cost only 100 gas. However, Solidity still emits an SLOAD opcode per named variable access; the warm-slot discount applies automatically but the compiler does not cache the slot in a local variable across separate statements.

## Architecture Patterns

### Storage Slot Map (Score-Relevant Variables)

```
EVM SLOT 0 (31 bytes used):
  [0:6]   levelStartTime        uint48
  [6:12]  dailyIdx              uint48
  [12:18] rngRequestTime        uint48
  [18:21] level                 uint24   <-- READ by score (L2284)
  [21:22] jackpotPhaseFlag      bool     <-- READ by _activeTicketLevel (L2182)
  [22:23] jackpotCounter        uint8    <-- READ 2x in _callTicketPurchase (L851, L957)
  [23:24] poolConsolidationDone bool
  [24:25] lastPurchaseDay       bool
  [25:26] decWindowOpen         bool
  [26:27] rngLockedFlag         bool     <-- READ 1x in _callTicketPurchase (L850)
  [27:28] phaseTransitionActive bool
  [28:29] gameOver              bool     <-- READ 1x in _purchaseFor (L638)
  [29:30] dailyJackpotCoinTicketsPending bool
  [30:31] compressedJackpotFlag uint8    <-- READ 2x in _callTicketPurchase (L852, L955+L958)

EVM SLOT 1 (25 bytes used):
  [0:6]   purchaseStartDay      uint48
  [6:22]  price                 uint128  <-- READ 3x (_purchaseFor L641, _callTicketPurchase L861, _applyLootboxBoostOnPurchase L1059)
  [22:23] ticketWriteSlot       uint8
  [23:24] ticketsFullyProcessed bool
  [24:25] prizePoolFrozen       bool     <-- READ 1x in _purchaseFor lootbox path (L761)
  [25:26] gameOverPossible      bool

MAPPING SLOTS (per-player):
  mintPacked_[player]           uint256  <-- READ 2x (score L2279 + _mintStreakEffective L53)
  deityPassCount[player]        uint16   <-- READ 1x (score L2278)
  claimableWinnings[player]     uint256  <-- READ 2-3x (_purchaseFor L654, L673, L820)
```

### Score Function Input Map

`_playerActivityScore(player)` at DegenerusGame.sol:2273 reads:

| Input | Source | Gas Cost | Line |
|-------|--------|----------|------|
| deityPassCount[player] | Mapping SLOAD | 2,100 cold | L2278 |
| mintPacked_[player] | Mapping SLOAD | 2,100 cold | L2279 |
| _mintStreakEffective(player, level) | Re-reads mintPacked_ | 100 warm (same slot) | L2283 via L53 |
| level (Slot 0) | Storage SLOAD | 2,100 cold or 100 warm | L2284 |
| jackpotPhaseFlag (Slot 0) | Storage SLOAD | 100 warm (same slot as level) | via _activeTicketLevel L2182 |
| questView.playerQuestStates(player) | STATICCALL to DegenerusQuests | 2,600 cold + internal SLOADs | L2324 |
| affiliate.affiliateBonusPointsBest(level, player) | STATICCALL to DegenerusAffiliate | 2,600 cold + internal SLOADs | L2332-2334 |

**Total baseline cost of one _playerActivityScore call (cold):** ~11,700+ gas
- 2 mapping SLOADs cold: 4,200
- 1 mapping SLOAD warm (mintPacked_ re-read): 100
- 1 Slot 0 SLOAD cold: 2,100
- 1 Slot 0 SLOAD warm: 100
- 2 STATICCALLs cold: 5,200 base + internal costs

### Cross-Contract Call Breakdown

**1. questView.playerQuestStates(player)** -- DegenerusQuests.sol:841

Internally reads:
- `activeQuests` (storage array, 2 slots = 2 SLOADs)
- `questPlayerState[player]` (mapping SLOAD, struct with streak + lastCompletedDay + progress + completionMask)
- Calls `_currentQuestDay(local)` (pure, no storage)
- Loops 2 iterations checking `_questProgressValid` and `_questCompleted`

Cost: 2,600 (STATICCALL cold) + ~4,200-6,300 (internal SLOADs) = ~6,800-8,900 gas

**Only value used by score:** `questStreakRaw` (uint32) -- the first return value. The other 3 return values (lastCompletedDay, progress[2], completed[2]) are discarded.

**2. affiliate.affiliateBonusPointsBest(currLevel, player)** -- DegenerusAffiliate.sol:665

Internally reads:
- `affiliateCoinEarned[lvl][player]` in a loop (up to 5 iterations, 5 mapping SLOADs)

Cost: 2,600 (STATICCALL cold) + ~10,500 (5 cold mapping SLOADs) = ~13,100 gas worst case (currLevel >= 6), ~5,200 gas best case (currLevel <= 1, early return)

### Purchase Path Call Graph (Hot Path)

```
_purchaseFor(buyer, qty, lootbox, affiliate, payKind)  [MintModule:631]
  |
  |-- level (SLOAD Slot 0)                              L640
  |-- price (SLOAD Slot 1)                              L641
  |-- claimableWinnings[buyer] (SLOAD mapping)          L654
  |-- [if lootbox shortfall] claimableWinnings[buyer]   L673 (2nd read)
  |-- [if lootbox shortfall] claimableWinnings[buyer] = L677 (SSTORE)
  |
  |-- _callTicketPurchase(buyer, ...)                   L685
  |     |-- jackpotPhaseFlag (SLOAD Slot 0)             L847
  |     |-- level (SLOAD Slot 0)                        L847, L855, L859
  |     |-- rngLockedFlag (SLOAD Slot 0)                L850
  |     |-- jackpotCounter (SLOAD Slot 0)               L851, L957
  |     |-- compressedJackpotFlag (SLOAD Slot 0)        L852, L955, L958
  |     |-- price (SLOAD Slot 1)                        L861
  |     |-- [if x00] playerActivityScore(buyer)         L886 (full score compute)
  |     |-- _questMint -> quests.handleMint             L914/L943
  |     |   returns (reward, questType, streak, completed)
  |
  |-- [if lootbox]
  |     |-- level (SLOAD Slot 0)                        L707, L750
  |     |-- playerActivityScore(buyer)                  L709 (lootbox EV snapshot)
  |     |-- playerActivityScore(buyer)                  L781 (affiliate routing)
  |     |-- quests.handleLootBox(buyer, amount)          L810
  |     |   returns (reward, questType, streak, completed)
  |
  |-- claimableWinnings[buyer] (SLOAD mapping)          L820 (3rd read)
```

### SLOAD Duplication Catalog (Purchase Path)

| Variable | Reads | Lines | Same EVM Slot | Savings Strategy |
|----------|-------|-------|---------------|------------------|
| level (Slot 0) | 5-6x | L640, L847, L855, L859, L707, L750 | Yes (Slot 0) | Read once into local at _purchaseFor entry, pass as parameter |
| price (Slot 1) | 3x | L641, L861, L1059 | Yes (Slot 1) | Already cached as `priceWei` in _purchaseFor (L641) but re-read in _callTicketPurchase (L861) and _applyLootboxBoost (L1059) |
| compressedJackpotFlag (Slot 0) | 3x | L852, L955, L958 | Yes (Slot 0) | Cache in local at _callTicketPurchase entry |
| jackpotCounter (Slot 0) | 2x | L851, L957 | Yes (Slot 0) | Cache in local at _callTicketPurchase entry |
| jackpotPhaseFlag (Slot 0) | 2x | L847, L955 | Yes (Slot 0) | Cache in local at _callTicketPurchase entry |
| claimableWinnings[buyer] | 2-3x | L654, L673, L820 | Mapping (unique slot) | Read once into local, use cached value |
| mintPacked_[player] | 2x | score:L2279, _mintStreakEffective:L53 | Mapping (unique slot) | Read once, pass to _mintStreakEffective |
| playerActivityScore(buyer) | 2-3x | L709, L781, L886 | N/A (function calls) | Compute once, cache result, pass to all consumers |

**Warm vs cold gas note:** All Slot 0 variables share one physical slot. After the first access to ANY Slot 0 variable (2,100 gas cold), all subsequent Slot 0 reads cost 100 gas warm. The duplicate reads of `level` at L847/L855/L859 are 100 gas each (warm), not 2,100. The real waste is at the Solidity level -- the compiler emits separate SLOAD opcodes even for warm reads, each costing 100 gas + extract overhead.

**The big savings are in:**
1. **Eliminating redundant `playerActivityScore` calls** (each ~11,700+ gas cold): L709 + L781 + L886 = up to 3 calls on a purchase with lootbox at x00 level
2. **Eliminating cross-contract STATICCALLs** from score computation: questView (6,800-8,900 gas) + affiliate (5,200-13,100 gas) per score call
3. **SLOAD dedup of mapping reads** (claimableWinnings, mintPacked_): 2,100 gas each cold duplicate

### Score Consumer Catalog

| Consumer | File:Line | Call Pattern | On Purchase Path? | Needs Change? |
|----------|-----------|-------------|-------------------|---------------|
| Lootbox EV snapshot | MintModule:709 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | Yes (lootbox buy) | Yes -- cache + pass |
| Affiliate lootbox score | MintModule:781 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | Yes (lootbox affiliate) | Yes -- reuse cached |
| x00 century bonus | MintModule:886 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | Yes (ticket at x00 level) | Yes -- reuse cached |
| Lootbox EV multiplier | LootboxModule:457 | `IDegenerusGame(address(this)).playerActivityScore(player)` | No (lootbox open) | Indirect benefit |
| Whale bundle EV | WhaleModule:735 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | No (whale purchase) | Indirect benefit |
| Decimator burn | DecimatorModule:718 | `IDegenerusGame(address(this)).playerActivityScore(player)` | No (decimator) | Indirect benefit |
| BurnieCoin decimator | BurnieCoin:611 | `degenerusGame.playerActivityScore(caller)` | No (BURNIE burn) | No (external contract, separate tx) |
| sDGNRS claim | StakedDegenerusStonk:800 | `game.playerActivityScore(beneficiary)` | No (sDGNRS) | No (external contract, separate tx) |
| Degenerette score | DegeneretteModule:473 | `_playerActivityScoreInternal(player)` | No (Degenerette bet) | Yes -- eliminate duplicate |

### DegeneretteModule Duplicate Analysis

**Canonical:** `_playerActivityScore(player)` in DegenerusGame.sol:2273
**Duplicate:** `_playerActivityScoreInternal(player)` in DegeneretteModule.sol:1069

**Differences found:**

| Aspect | DegenerusGame (canonical) | DegeneretteModule (duplicate) |
|--------|--------------------------|-------------------------------|
| Streak base level | `_mintStreakEffective(player, _activeTicketLevel())` | `_mintStreakEffective(player, level + 1)` |
| Pass floor constant names | `PASS_STREAK_FLOOR_POINTS` (50) | `WHALE_PASS_STREAK_FLOOR_POINTS` (50) |
| Pass floor constant names | `PASS_MINT_COUNT_FLOOR_POINTS` (25) | `WHALE_PASS_MINT_COUNT_FLOOR_POINTS` (25) |
| Visibility | `internal` | `private` |

**Semantic difference:** `_activeTicketLevel()` returns `jackpotPhaseFlag ? level : level + 1`. The DegeneretteModule hardcodes `level + 1`. During purchase phase (jackpotPhaseFlag=false), both produce `level + 1` -- identical. During jackpot phase (jackpotPhaseFlag=true), the canonical version uses `level` while the duplicate uses `level + 1`. This means the DegeneretteModule gives slightly different streak credit during jackpot phase.

**Resolution options:**
1. **Add streakBaseLevel parameter:** Make `_playerActivityScore(player, streakBaseLevel)` an internal function in a shared location. DegenerusGame passes `_activeTicketLevel()`, DegeneretteModule passes `level + 1`.
2. **External view with parameter:** Add `playerActivityScore(player, streakBaseLevel)` overload callable by modules via `IDegenerusGame(address(this))`.
3. **Accept the phase-dependent difference:** If the DegeneretteModule intentionally always uses `level + 1` (Degenerette bets always target the next level regardless of phase), preserve this with a parameter.

### Quest Handler Return Values

Both `handleMint` and `handleLootBox` already return `streak` as their third return value:

```solidity
function handleMint(address player, uint32 quantity, bool paidWithEth)
    external returns (uint256 reward, uint8 questType, uint32 streak, bool completed);

function handleLootBox(address player, uint256 amountWei)
    external returns (uint256 reward, uint8 questType, uint32 streak, bool completed);
```

Currently, `_questMint` (MintModule:1114) discards the streak:
```solidity
(uint256 reward, uint8 questType,, bool completed) = quests.handleMint(player, quantity, paidWithEth);
```

And `handleLootBox` call at L810 also discards streak:
```solidity
(uint256 lbReward,,, bool lbCompleted) = quests.handleLootBox(buyer, lootBoxAmount);
```

**Key insight:** The quest streak is already available as a return value from handlers that execute BEFORE score is needed. No new cross-contract call is required -- just capture the return value and forward it.

### Affiliate Bonus Elimination Difficulty

`affiliate.affiliateBonusPointsBest(currLevel, player)` reads `affiliateCoinEarned[lvl][player]` across up to 5 levels. This data lives in DegenerusAffiliate's storage (a separate contract, not delegatecall). Options:

1. **Accept the call:** The affiliate address is warm after `payAffiliate` calls earlier in the purchase path. The STATICCALL base cost is only 100 gas (warm). The 5 mapping SLOADs inside are the real cost (~10,500 gas cold).
2. **Parameter forwarding from payAffiliate:** `payAffiliate` already runs before score is needed on some paths. It could return a bonus-points value. But `payAffiliate` writes to `affiliateCoinEarned`, meaning the score computation after payAffiliate would see updated values. The order matters.
3. **Data co-location:** Mirror affiliate bonus data into Game storage. Adds SSTORE overhead on every `payAffiliate` call for a relatively small savings.

**Recommendation:** Accept the affiliate STATICCALL. The address is warm (100 gas base). The internal SLOADs are the dominant cost, and mirroring data would cost more (SSTORE) than it saves. The design should document this as a conscious decision.

### Caching Strategy: Parameter Forwarding Chain

For the purchase path, the optimal flow is:

```
_purchaseFor(buyer, ...)
  |-- Read: level, price, claimableWinnings[buyer] once
  |-- _callTicketPurchase(buyer, ..., cachedLevel, cachedPrice)
  |     |-- Read Slot 0 once for jackpotPhaseFlag/jackpotCounter/compressedJackpotFlag
  |     |-- _questMint -> quests.handleMint -> capture streak return
  |     |-- [if x00] _playerActivityScoreWithStreak(player, streak) -> cache result
  |
  |-- [if lootbox]
  |     |-- Reuse cachedScore (or compute if not yet computed)
  |     |-- quests.handleLootBox -> capture streak (if score not yet computed)
  |     |-- Use cachedScore for L709, L781 sites
  |
  |-- Reuse claimableWinnings from initial read
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Transient storage for caching | Storage slot cache (SSTORE+SLOAD at 20K+ gas) | Stack parameter passing | Paris EVM has no EIP-1153; storage caching is 100x more expensive than parameter passing |
| Cross-contract data mirroring | Mirror affiliate data into Game storage | Accept the STATICCALL (warm: 100 gas base) | SSTORE overhead on every payAffiliate call exceeds STATICCALL savings |
| Custom bit packing library | New packing scheme | Extend existing BitPackingLib patterns | mintPacked_ pattern already proven; reuse shift/mask approach |

## Common Pitfalls

### Pitfall 1: Confusing EVM Slot Warmth with No-Cost Reads
**What goes wrong:** Assuming Slot 0 variables are "free" after the first read because they share a slot.
**Why it happens:** Warm SLOAD is 100 gas (not 0). Multiple warm SLOADs of the same slot still cost 100 gas each. The compiler emits separate SLOAD opcodes per named variable access.
**How to avoid:** Cache the full slot value in a local variable, extract fields with bit shifts. Or at minimum, recognize that warm reads cost 100 gas each and multiply accordingly.
**Warning signs:** Counting only cold SLOADs in gas budgets.

### Pitfall 2: Forgetting That handleMint Streak Reflects Post-Action State
**What goes wrong:** Using the streak returned from `handleMint` as pre-action streak for score computation.
**Why it happens:** `handleMint` may complete a quest and increment the streak before returning it. The streak returned is the post-action value.
**How to avoid:** Verify that the score computation can use post-action streak (it can -- the quest completion within the same tx is valid for score purposes). Document this explicitly in the design.
**Warning signs:** Score values differing between "score then quest" vs "quest then score" ordering.

### Pitfall 3: Breaking External Score Consumers
**What goes wrong:** Changing `playerActivityScore(address)` signature or behavior breaks BurnieCoin, StakedDegenerusStonk, and any off-chain indexers.
**Why it happens:** BurnieCoin.sol:611 and StakedDegenerusStonk.sol:800 call `playerActivityScore` as an external view. They cannot be changed in a Game-only deployment.
**How to avoid:** Keep `playerActivityScore(address)` as the public interface. Internal optimizations (parameter-passing, caching) must not change the external function's behavior.
**Warning signs:** Modifying the external function signature or adding required parameters.

### Pitfall 4: Ordering Dependency Between Quest Handlers and Score
**What goes wrong:** Computing score before quest handlers run, meaning quest streak used in score is stale.
**Why it happens:** On the purchase path, score is currently computed via `IDegenerusGame(address(this)).playerActivityScore(buyer)` which internally calls `questView.playerQuestStates(player)`. If quest handlers have not yet run, the streak is pre-action.
**How to avoid:** The design must ensure quest handlers run BEFORE score computation on the purchase path, so the forwarded streak is current. Currently `_questMint` (L943) runs before `playerActivityScore` is called at L886 (x00 bonus) -- this ordering is already correct for tickets. For lootbox, `handleLootBox` (L810) runs after the score calls at L709/L781 -- this ordering would need adjustment.
**Warning signs:** Different score values depending on whether tickets or lootbox path is taken.

### Pitfall 5: DegeneretteModule Streak Base Semantic Divergence
**What goes wrong:** Eliminating the DegeneretteModule duplicate without preserving the `level + 1` streak base behavior.
**Why it happens:** The canonical function uses `_activeTicketLevel()` which varies by game phase. The DegeneretteModule hardcodes `level + 1`. During jackpot phase, these differ.
**How to avoid:** The shared implementation must accept a `streakBaseLevel` parameter. DegeneretteModule passes `level + 1`, other callers pass `_activeTicketLevel()`.
**Warning signs:** Degenerette activity scores changing during jackpot phase after the refactor.

## Code Examples

### Pattern: Quest Streak Forwarding (Capturing Return Value)

```solidity
// Current (discards streak):
(uint256 reward, uint8 questType,, bool completed) = quests.handleMint(player, quantity, paidWithEth);

// Proposed (captures streak):
(uint256 reward, uint8 questType, uint32 questStreak, bool completed) = quests.handleMint(player, quantity, paidWithEth);
// questStreak is now available for score computation without a cross-contract call
```

### Pattern: Parameterized Score Function

```solidity
// Current:
function _playerActivityScore(address player) internal view returns (uint256 scoreBps) {
    // ... reads questView.playerQuestStates(player) internally
}

// Proposed (with forwarded streak):
function _playerActivityScore(
    address player,
    uint32 questStreak    // forwarded from handleMint/handleLootBox
) internal view returns (uint256 scoreBps) {
    // ... uses questStreak parameter instead of external call
}

// Backward-compatible external view (for BurnieCoin, StakedDegenerusStonk):
function playerActivityScore(address player) external view returns (uint256 scoreBps) {
    (uint32 streak, , , ) = questView.playerQuestStates(player);
    return _playerActivityScore(player, streak);
}
```

### Pattern: Slot 0 Cache (If Pursuing Aggressive SLOAD Dedup)

```solidity
// Read entire Slot 0 once via assembly, extract fields:
uint256 slot0;
assembly { slot0 := sload(0) }  // Note: actual slot number depends on inheritance
uint24 cachedLevel = uint24(slot0 >> 144);  // offset depends on packing
bool cachedJackpotPhaseFlag = (slot0 >> 168) & 1 != 0;
// etc.
```

**Note:** This pattern is fragile (hardcoded slot offsets break if storage layout changes). A safer alternative is to read each variable once into a local and pass it. The warm-read cost (100 gas each) is low enough that the assembly optimization may not be worth the maintenance risk.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Transient storage (EIP-1153) for caching | Not available on Paris | Cancun fork (2024) | Paris target means parameter passing is the only zero-overhead caching |
| Single SLOAD cost model | Cold/warm SLOAD (EIP-2929) | Berlin fork (2021) | Duplicate reads of same slot cost 100 gas (warm), not 2,100. Reduces savings from slot dedup |
| PUSH0 opcode | Not available on Paris | Shanghai fork (2023) | Minor: no impact on storage optimization strategy |

## Open Questions

1. **Affiliate bonus: accept or eliminate?**
   - What we know: The affiliate address is warm on purchase path (prior payAffiliate calls). Base STATICCALL cost is 100 gas (warm). Internal cost is up to 10,500 gas (5 mapping SLOADs).
   - What's unclear: Whether the 10,500 gas savings justifies the complexity of data co-location or parameter forwarding from payAffiliate.
   - Recommendation: Accept the STATICCALL for Phase 160. Document as a potential future optimization if affiliate data is co-located for other reasons.

2. **Lootbox path score ordering**
   - What we know: On the lootbox path, `playerActivityScore` is called at L709 and L781 BEFORE `handleLootBox` runs at L810. If we want to use handleLootBox's returned streak, the score calls must move after the handler.
   - What's unclear: Whether the lootbox EV snapshot at L709 (stored in `lootboxEvScorePacked`) intentionally captures pre-quest-action score.
   - Recommendation: The design must specify whether lootbox EV snapshots should use pre-action or post-action score. If pre-action is intentional, the quest streak must be fetched separately for lootbox score (a lighter call than full playerQuestStates).

3. **Packed struct cost/benefit for score + quest data**
   - What we know: Quest streak lives in DegenerusQuests (separate contract). Co-locating it in Game storage requires either (a) duplicating the write (SSTORE in both contracts), or (b) making Game the source of truth and having Quests read from Game.
   - What's unclear: Whether the implementation complexity is justified given that parameter forwarding eliminates the cross-contract read without any storage changes.
   - Recommendation: Parameter forwarding is strictly better for quest streak. Reserve struct packing investigation for score-internal data (combining deityPassCount into mintPacked_ to save one SLOAD).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge test) + Hardhat (npx hardhat test) |
| Config file | foundry.toml, hardhat.config.js |
| Quick run command | `forge test --match-contract ActivityScore` |
| Full suite command | `npx hardhat test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCORE-01 | Design spec validates storage read count reduction | manual-only | N/A (design document review) | N/A |

### Sampling Rate
- **Per task commit:** Manual review of design document completeness
- **Per wave merge:** N/A (no code changes)
- **Phase gate:** Design spec reviewed for completeness against all 4 success criteria

### Wave 0 Gaps
None -- Phase 159 is a design-only phase producing a document, not code. No test infrastructure needed.

## Sources

### Primary (HIGH confidence)
- `contracts/storage/DegenerusGameStorage.sol` -- Storage slot layout, all variable declarations
- `contracts/DegenerusGame.sol:2273-2349` -- Canonical _playerActivityScore implementation
- `contracts/modules/DegenerusGameDegeneretteModule.sol:1069-1139` -- Duplicate _playerActivityScoreInternal
- `contracts/modules/DegenerusGameMintModule.sol:631-1021` -- Purchase path (_purchaseFor + _callTicketPurchase)
- `contracts/DegenerusQuests.sol:841-863` -- playerQuestStates implementation
- `contracts/DegenerusAffiliate.sol:665-681` -- affiliateBonusPointsBest implementation
- `contracts/libraries/BitPackingLib.sol` -- Existing packing patterns
- `contracts/interfaces/IDegenerusQuests.sol` -- Handler signatures with streak return values
- `foundry.toml` -- Paris EVM target confirmation

### Secondary (MEDIUM confidence)
- [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929) -- Cold/warm SLOAD gas costs (2,100/100)
- [Understanding gas costs after Berlin](https://hackmd.io/@fvictorio/gas-costs-after-berlin) -- STATICCALL address access costs (2,600/100)
- [EVM Opcodes gas reference](https://github.com/wolflo/evm-opcodes/blob/main/gas.md) -- Comprehensive gas cost table

### Tertiary (LOW confidence)
None -- all findings verified against source code.

## Metadata

**Confidence breakdown:**
- Storage layout: HIGH -- direct source code analysis, slot comments verified
- SLOAD duplication: HIGH -- line-by-line trace through purchase path
- Cross-contract call costs: HIGH -- EIP-2929 is well-documented, verified against source
- DegeneretteModule difference: HIGH -- exact diff identified (L2283 vs L1079)
- Affiliate elimination feasibility: MEDIUM -- cost/benefit tradeoff requires design judgment

**Research date:** 2026-04-01
**Valid until:** Stable -- storage layout does not change between milestones without explicit migration
