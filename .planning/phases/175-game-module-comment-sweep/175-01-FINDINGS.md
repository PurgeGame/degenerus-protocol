# Phase 175 Comment Audit — Plan 01 Findings
**Contracts:** DegenerusGameAdvanceModule, DegenerusGameMintModule
**Requirement:** CMT-01
**Date:** 2026-04-03
**Total findings this plan:** 3 LOW, 9 INFO

---

## DegenerusGameAdvanceModule

Audited: `contracts/modules/DegenerusGameAdvanceModule.sol` (1673 lines, main repo)

Focus areas checked: BURNIE endgame gate, absorbed EndgameModule functions, activity score refactoring, level quest integration, general NatSpec.

---

### ADV-CMT-01 — INFO — Stale line references in BIT ALLOCATION MAP

**Location:** `DegenerusGameAdvanceModule.sol` lines 823-840 (BIT ALLOCATION MAP comment block)

**Comment says:**
```
// 8+       Redemption roll             (currentWord >> 8) % 151 + 25     AdvanceModule.sol:795
// full     Lootbox RNG                 stored as lootboxRngWordByIndex   AdvanceModule.sol:826
// full     Future take variance        rngWord % (variance * 2 + 1)      AdvanceModule.sol:1033
```

**Code does:** The actual code for each consumer is at different line numbers in the current file. The redemption roll is at line 884 (not 795). The lootbox RNG storage (`lootboxRngWordByIndex[index] = rngWord`) is at line 923 (not 826). The future take variance (`bps += rngWord % (ADDITIVE_RANDOM_BPS + 1)`) is at line 1145 (not 1033).

**Root cause:** These line numbers were accurate when the comment was written but shifted as code was added and reorganized (AffiliateDgnrsReward event added at line 81, new constants at lines 135-139, `_rewardTopAffiliate` expanded from delegatecall wrapper to inline function, `_runRewardJackpots` moved from jackpot-phase close to purchase-phase close).

---

### ADV-CMT-02 — INFO — `_payDailyCoinJackpot` NatSpec uses "current and future ticket holders"

**Location:** `DegenerusGameAdvanceModule.sol` lines 684-688

**Comment says:**
```solidity
/// @dev Pay daily BURNIE jackpot via jackpot module delegatecall.
///      Called each day during purchase phase in its own transaction.
///      Awards 0.5% of prize pool target in BURNIE to current and future ticket holders.
```

**Code does:** `payDailyCoinJackpot` in JackpotModule selects one random target level from [lvl, lvl+4] (the near-future range) for 75% of the budget, and distributes 25% to far-future queue holders [lvl+5, lvl+99]. The award does not go to "current" level ticket holders in the sense of a guaranteed current-level award — it picks a random level in the near-future range. Saying "current and future" implies current-level holders always win, which is incorrect.

---

### ADV-CMT-03 — LOW — `_runRewardJackpots` NatSpec describes stale call timing

**Location:** `DegenerusGameAdvanceModule.sol` line 588

**Comment says:**
```solidity
/// @dev Resolve BAF/Decimator jackpots during the level transition RNG period.
```

**Code does:** `_runRewardJackpots` is now called at line 373 inside the purchase-phase closure block — specifically during the `lastPurchaseDay` transition to jackpot phase, after `_consolidatePrizePools`. It is called at the moment the level transitions FROM purchase to jackpot phase, not at the end of the jackpot phase as the prior version had it (where it ran alongside `_rewardTopAffiliate` after the final jackpot day draw). "During the level transition RNG period" is ambiguous enough to mislead: a reader familiar with the old flow would assume this is called at jackpot-phase end, not at purchase-phase close.

---

### ADV-CMT-04 — INFO — `_rewardTopAffiliate` change from delegatecall to inline — verified accurate

**Location:** `DegenerusGameAdvanceModule.sol` lines 553-586

**Code does:** This function was formerly a delegatecall to `GAME_ENDGAME_MODULE` but is now inlined as direct calls to `affiliate.affiliateTop()` and `dgnrs.transferFromPool()`. The NatSpec accurately describes the current implementation. No discrepancy found.

---

### ADV-CMT-05 — INFO — Delegate module list — verified accurate

**Location:** `DegenerusGameAdvanceModule.sol` lines 537-551

**Code does:** EndgameModule has been removed. The list correctly shows: GAME_DECIMATOR_MODULE, GAME_MINT_MODULE, GAME_WHALE_MODULE, GAME_JACKPOT_MODULE. Accurate.

---

### ADV-CMT-06 — LOW — `_gameOverEntropy` inline comments cite stale rngGate line numbers

**Location:** `DegenerusGameAdvanceModule.sol` lines 950 and 989

**Comment says:**
```solidity
// Resolve gambling burn period if pending (mirrors rngGate lines 792-802)
```

**Code does:** The redemption resolution block in `rngGate` is at lines 878-898 (not lines 792-802). The cited lines 792-802 in the current file fall within `requestLootboxRng`, not `rngGate`. This stale comment appears twice (lines 950 and 989) in `_gameOverEntropy`.

---

### ADV-CMT-07 — INFO — Turbo-mode inline comment omits `!lastPurchaseDay` pre-condition

**Location:** `DegenerusGameAdvanceModule.sol` lines 156-166

**Comment says:**
```solidity
// Turbo: if target already met on day ≤1, flag now so _requestRng
// does the level pre-increment (matching normal lastPurchaseDay flow).
```

**Code does:** The outer guard is `if (!inJackpot && !lastPurchaseDay)`. The `!lastPurchaseDay` pre-condition means this block only executes once per purchase phase (on the first evaluation where lastPurchaseDay is false). The comment doesn't mention this, so a reader might think the turbo check runs every day.

---

### ADV-CMT-08 — INFO — `_processPhaseTransition` NatSpec mentions deity pass in misleading context

**Location:** `DegenerusGameAdvanceModule.sol` lines 1290-1294

**Comment says:**
```solidity
/// @dev Process jackpot→purchase transition housekeeping (vault perpetual tickets + auto-stake).
///      Deity pass holders get virtual trait-targeted tickets at jackpot resolution time
///      (zero gas cost here). Vault addresses (DGNRS, VAULT) get generic queued tickets.
```

**Code does:** The function body only queues tickets for `ContractAddresses.SDGNRS` and `ContractAddresses.VAULT` and calls `_autoStakeExcessEth()`. Deity pass holder processing happens elsewhere. The comment is technically correct ("zero gas cost here") but the sentence structure suggests deity pass processing is related to this function, which it is not. A reader scanning this NatSpec may expect deity pass logic in or near this function.

---

### ADV-CMT-09 — INFO — `DEPLOY_IDLE_TIMEOUT_DAYS` applies to level-0 only; level 1+ uses hardcoded 120 days

**Location:** `DegenerusGameAdvanceModule.sol` line 103 and lines 481-484

**Comment says:** No comment on the constant:
```solidity
uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365;
```

**Code does:**
```solidity
bool livenessTriggered = (lvl == 0 &&
    ts - lst > uint256(DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days) ||
    (lvl != 0 && ts - 120 days > lst);
```

The constant `DEPLOY_IDLE_TIMEOUT_DAYS = 365` applies ONLY to level 0. For lvl != 0, the hardcoded `120 days` is used. The constant name implies it governs the entire idle timeout, but it only governs the level-0 case. Adding a `@dev` annotation to the constant would clarify this asymmetry.

---

### ADV-CMT-10 — INFO — `_enforceDailyMintGate` bypass tier 3 description conflates "lazy" and whale concepts

**Location:** `DegenerusGameAdvanceModule.sol` lines 702-707

**Comment says:**
```solidity
///        3. Any pass holder (lazy/whale freeze active) — bypasses 15+ min after day boundary
```

**Code does (lines 734-739):**
```solidity
if (elapsed >= 15 minutes) {
    uint24 frozenUntilLevel = uint24(
        (mintData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
            BitPackingLib.MASK_24
    );
    if (frozenUntilLevel > lvl) return;
}
```

The code checks `frozenUntilLevel > lvl` — this is the whale bundle holder check. There is no "lazy pass" flag in BitPackingLib or mintPacked_. The "lazy/whale" phrasing either refers to a historical design artifact or colloquially labels whale bundle holders as "lazy pass holders." The code does not check for a separate lazy pass. The NatSpec should say "Whale bundle holder (frozenUntilLevel > lvl)" to be precise.

---

## DegenerusGameMintModule

Audited: `contracts/modules/DegenerusGameMintModule.sol` (1133 lines, main repo)

Focus areas checked: affiliate bonus cache (lines 276-282), recordMintData (NatSpec + logic), activity score contributions, level quest triggering from mint, general NatSpec, inline clarifying comments.

---

### MINT-CMT-01 — LOW — NatSpec note about Affiliate Points tracking is stale after affiliate bonus cache

**Location:** `DegenerusGameMintModule.sol` lines 56-58

**Comment says:**
```
* Note: Quest Streak and Affiliate Points are tracked separately in their respective contracts
* (DegenerusQuests.questPlayerState and DegenerusAffiliate.affiliateBonusPointsBest).
```

**Code does:** With the affiliate bonus cache added at lines 276-281, `Affiliate Points` are now ALSO cached in `mintPacked_` (bits 185-208: `affBonusLevel`; bits 209-214: `affBonusPoints`). The `_playerActivityScore` function in `MintStreakUtils` reads from the cache when `cachedLevel == currLevel` and falls back to `affiliateBonusPointsBest` when stale. The note should say "Affiliate Points are primarily tracked in DegenerusAffiliate but cached in mintPacked_ on level transitions for gas efficiency."

---

### MINT-CMT-02 — INFO — Bit packing layout Activity Score table omits `mintStreakLast` field

**Location:** `DegenerusGameMintModule.sol` lines 37-55

**Comment says:**
The Activity Score System bullet list does not mention the `mintStreakLast` (bits 160-183) field stored in `mintPacked_`.

**Code does:** The `mintPacked_` layout includes `mintStreakLast` at bits 160-183 — the last level credited for the mint streak (managed by `MintStreakUtils._recordMintStreakForLevel`). This field is used by `_mintStreakEffective` to determine whether the current streak is valid. It is listed in the bit packing table but absent from the Activity Score metrics bullet list, which lists "Level Streak" without explaining how streak validity is maintained.

---

### MINT-CMT-03 — INFO — `recordMintData` NatSpec `@param lvl` says "Current game level" but receives target ticket level

**Location:** `DegenerusGameMintModule.sol` lines 160-161

**Comment says:**
```
* @param lvl Current game level.
```

**Code does:** `recordMintData` is called from `DegenerusGame.recordMint` which receives `lvl` as `targetLevel` from `_callTicketPurchase`. `targetLevel` is `level + 1` during purchase phase, `level` during jackpot phase (except on the last jackpot day where it routes to `level + 1`). It is not always "the current game level." The parameter should be described as "Target level for this purchase (level tickets are queued to)."

---

### MINT-CMT-04 — INFO — `recordMintData` Activity Score State Updates comment mentions "whale bonuses, milestones"

**Location:** `DegenerusGameMintModule.sol` lines 163-166

**Comment says:**
```
* ## Activity Score State Updates
*
* - `mintPacked_[player]` updated with level count, whale bonuses, milestones
* - Only writes to storage if data actually changed
```

**Code does:** `recordMintData` updates: `lastLevel`, `levelCount`, `levelUnits`, `unitsLevel`, frozen-flag clearance on expiry, and the affiliate bonus cache. It does not set whale bonuses (WhaleModule sets those on bundle purchase). "Milestones" is not a defined concept in the current code. Both phrases are carryovers from a prior version. The accurate description would be: "updated with last level, level count, level units, affiliate bonus cache (on new-level transitions); frozen state cleared on expiry."

---

### MINT-CMT-05 — INFO — `recordMintData` Level Transition Logic has stale "Century boundary" bullet

**Location:** `DegenerusGameMintModule.sol` lines 167-173

**Comment says:**
```
* ## Level Transition Logic
*
* - Same level: Just update units
* - New level with <4 units: Only track units, don't count as "minted"
* - New level with ≥4 units: Update level count total
* - Century boundary (level 100, 200...): Total continues to accumulate
```

**Code does:** The first three bullets accurately describe the code. The fourth bullet implies special handling at century boundaries, but the current `recordMintData` has no century-boundary-specific logic. Total accumulation is uniform regardless of level. Century boundary special handling (prize pool splits etc.) lives in `_endPhase` and `AdvanceModule`, not here. The bullet should be removed or replaced with a note that total accumulates identically at century and non-century levels.

---

### MINT-CMT-06 — INFO — Affiliate bonus cache block does not document within-level staleness trade-off

**Location:** `DegenerusGameMintModule.sol` lines 276-281

**Comment says:**
```solidity
// Cache affiliate bonus for activity score (piggybacks on existing SSTORE)
{
    uint256 affPoints = affiliate.affiliateBonusPointsBest(lvl, player);
    data = BitPackingLib.setPacked(data, BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT, BitPackingLib.MASK_24, lvl);
    data = BitPackingLib.setPacked(data, BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT, BitPackingLib.MASK_6, affPoints);
}
```

**Code does:** The cache is only written on "new level with ≥4 units" transitions. On same-level updates (the early-exit at line 233-240), the affiliate bonus cache is NOT updated. This means the cached value at `affBonusLevel == currLevel` may be stale within a level if the affiliate bonus changed after the player's first qualifying mint at this level. The comment explains the gas rationale ("piggybacks on existing SSTORE") but does not document the staleness window (intentional design: cache refreshes per level, not per mint).

---

### MINT-CMT-07 — INFO — `purchaseCoin` NatSpec omits `gameOverPossible` gate on ticket purchases

**Location:** `DegenerusGameMintModule.sol` lines 572-574

**Comment says:**
```solidity
/// @notice Purchase tickets and optional BURNIE loot boxes.
/// @dev BURNIE ticket and loot box purchases are allowed whenever RNG is unlocked.
```

**Code does (lines 605-608):**
```solidity
if (ticketQuantity != 0) {
    // ENF-01: Block BURNIE tickets when drip projection cannot cover nextPool deficit.
    if (gameOverPossible) revert GameOverPossible();
```

BURNIE ticket purchases are also blocked when `gameOverPossible` is true. The NatSpec says "allowed whenever RNG is unlocked" but omits this second gate. BURNIE lootbox purchases (via `_purchaseBurnieLootboxFor`) are not blocked by `gameOverPossible`, so the comment is accurate only for lootboxes but incomplete for ticket purchases.

---

### MINT-CMT-08 — INFO — `_processFutureTicketBatch` wrapper NatSpec says "Called during jackpot phase of level N-1 only"

**Location:** `DegenerusGameAdvanceModule.sol` lines 1204-1209

**Comment says:**
```solidity
/// @dev Process a batch of future ticket rewards for the specified level.
///      Called during jackpot phase of level N-1 to activate tickets for level N.
```

**Code does:** `_processFutureTicketBatch` is called from multiple sites: `_prepareFutureTickets` (during BOTH purchase and jackpot phase for lvl+1..lvl+4), the FF drain at phase transition (line 294), and the pre-jackpot activation (line 362). It is not exclusively called "during jackpot phase of level N-1." The NatSpec in AdvanceModule covers only one of the call patterns.

---

### MINT-CMT-09 — INFO — `_purchaseBurnieLootboxFor` does not explain why `mintPrice = 0` passed to `_questMint`

**Location:** `DegenerusGameMintModule.sol` lines 1040-1044

**Comment says:**
```solidity
{
    uint256 questUnitsRaw = burnieAmount / PRICE_COIN_UNIT;
    if (questUnitsRaw != 0) {
        _questMint(buyer, uint32(questUnitsRaw), false, 0);
    }
}
```

**Code does:** `_questMint` is called with `paidWithEth = false` and `mintPrice = 0`. The `false` for `paidWithEth` is correct (BURNIE lootbox purchase). The `0` for `mintPrice` is passed to `quests.handleMint` where it is used in quest eligibility calculations. No comment explains why `mintPrice` is 0 here versus being set to the current level price (as in ETH purchase paths). The omission of context makes this harder to audit without tracing into DegenerusQuests.

---

## Summary Table

| ID | Severity | Contract | Lines | Description |
|----|----------|----------|-------|-------------|
| ADV-CMT-01 | INFO | AdvanceModule | 823-840 | BIT ALLOCATION MAP has 3 stale line number self-references (lines 795/826/1033) |
| ADV-CMT-02 | INFO | AdvanceModule | 684-688 | `_payDailyCoinJackpot` NatSpec says "current and future" — awards near-future range [lvl,lvl+4] randomly |
| ADV-CMT-03 | LOW | AdvanceModule | 588 | `_runRewardJackpots` NatSpec says "level transition RNG period" — now called at purchase-phase close, not jackpot-phase end |
| ADV-CMT-04 | INFO | AdvanceModule | 553-586 | `_rewardTopAffiliate` is now inlined (verified accurate, no discrepancy) |
| ADV-CMT-05 | INFO | AdvanceModule | 537-551 | Delegate module list verified accurate after EndgameModule removal |
| ADV-CMT-06 | LOW | AdvanceModule | 950, 989 | `_gameOverEntropy` inline comments cite stale rngGate line numbers (lines 792-802 vs actual 878-898) |
| ADV-CMT-07 | INFO | AdvanceModule | 156-166 | Turbo-mode comment omits `!lastPurchaseDay` pre-condition |
| ADV-CMT-08 | INFO | AdvanceModule | 1290-1294 | `_processPhaseTransition` NatSpec mentions deity pass in misleading context |
| ADV-CMT-09 | INFO | AdvanceModule | 103, 481-484 | `DEPLOY_IDLE_TIMEOUT_DAYS` applies only to level-0; lvl>0 uses hardcoded 120 days with no named constant |
| ADV-CMT-10 | INFO | AdvanceModule | 702-707 | Bypass tier 3 "lazy/whale freeze" — code only checks `frozenUntilLevel > lvl` (whale bundle), no lazy pass flag |
| MINT-CMT-01 | LOW | MintModule | 56-58 | Stale note: Affiliate Points now also cached in `mintPacked_` (bits 185-214) |
| MINT-CMT-02 | INFO | MintModule | 37-55 | Activity Score table omits `mintStreakLast` (bits 160-183) field used by streak validity |
| MINT-CMT-03 | INFO | MintModule | 160-161 | `@param lvl` says "Current game level" but receives target ticket level (level+1 during purchase phase) |
| MINT-CMT-04 | INFO | MintModule | 163-166 | "whale bonuses, milestones" in Activity Score State Updates is stale — code does neither |
| MINT-CMT-05 | INFO | MintModule | 167-173 | "Century boundary: Total continues to accumulate" implies special handling that does not exist in this function |
| MINT-CMT-06 | INFO | MintModule | 276-281 | Affiliate bonus cache comment does not document within-level staleness trade-off |
| MINT-CMT-07 | INFO | MintModule | 572-574 | `purchaseCoin` NatSpec omits `gameOverPossible` gate on BURNIE ticket purchases |
| MINT-CMT-08 | INFO | AdvanceModule | 1204-1209 | `_processFutureTicketBatch` NatSpec says "jackpot phase only" — has multiple call sites including purchase phase |
| MINT-CMT-09 | INFO | MintModule | 1040-1044 | No comment explaining why `mintPrice = 0` passed to `_questMint` from BURNIE lootbox path |
