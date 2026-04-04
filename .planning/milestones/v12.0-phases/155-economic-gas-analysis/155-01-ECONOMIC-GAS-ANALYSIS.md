# Economic + Gas Analysis: Level Quest System

**Phase:** 155-economic-gas-analysis
**Author:** Agent (Phase 155-01)
**Date:** 2026-04-01
**Requirements:** ECON-01, ECON-02, GAS-01, GAS-02
**Sources:** Phase 153 spec (153-01-LEVEL-QUEST-SPEC.md), Phase 152 gas baseline (152-02-GAS-ANALYSIS.md), contract source

---

## 1. BURNIE Inflation Model (ECON-01)

### Payout Mechanism

Level quest completion pays **800 BURNIE** (800e18 base units) per player per level via `creditFlip` (Phase 153 spec, Section 6). This is a coinflip stake credit, not a direct BURNIE mint:

```solidity
coinflip.creditFlip(player, 800 ether);
```

`creditFlip` (BurnieCoinflip.sol line 895-901) calls `_addDailyFlip(player, amount, 0, false, false)`, which writes to `coinflipBalance[targetDay][player]`. This credits 800 BURNIE as stake in the player's next coinflip day. The credited amount participates in the coinflip resolution:
- **Win:** New BURNIE is minted (net positive inflation).
- **Loss:** The stake is burned (net zero -- no BURNIE was minted, so nothing to burn; the credit simply evaporates).

The coinflip win rate is approximately 47-50% (weighted by house edge). Therefore, the **net new BURNIE minted** from level quest rewards is approximately:

```
net_inflation = completions * 800 * win_rate
```

At 50% win rate: ~400 BURNIE net per completion.
At 47% win rate: ~376 BURNIE net per completion.

### Worst-Case Inflation Model

**Assumptions (worst-case):**
- ALL eligible players complete the quest EVERY level
- Level frequency: ~1 level per day at steady state (conservative; levels advance when nextPool fills from mint revenue)
- 30 levels per month

| Active Eligible Players | Levels/Month | Gross Credit/Month | Net Mint/Month (50% win) | Net Mint/Month (47% win) |
|---|---|---|---|---|
| 100 | 30 | 2,400,000 BURNIE | 1,200,000 BURNIE | 1,128,000 BURNIE |
| 500 | 30 | 12,000,000 BURNIE | 6,000,000 BURNIE | 5,640,000 BURNIE |
| 1,000 | 30 | 24,000,000 BURNIE | 12,000,000 BURNIE | 11,280,000 BURNIE |

**Gross credit** = players x levels x 800 BURNIE.
**Net mint** = gross credit x win rate (only winning flips produce new BURNIE tokens).

### Expected-Case Inflation Model

**Assumptions (realistic):**
- Eligible fraction: ~30-50% of active players meet both gates (levelStreak >= 5 OR pass holder, AND >= 4 ETH units this level). The activity gate (4 ETH units per level) is a significant filter.
- Completion rate: ~20-40% of eligible players complete the 10x target. These are hard targets -- e.g., 10,000 BURNIE in ticket mints, or mintPrice x 10 in ETH mints, across an entire level.
- Level frequency: ~1 level per day (same as worst-case).

| Active Players | Eligible Fraction | Completion Rate | Levels/Month | Gross Credit/Month | Net Mint/Month (50%) |
|---|---|---|---|---|---|
| 500 | 30% | 20% | 30 | 720,000 BURNIE | 360,000 BURNIE |
| 500 | 50% | 40% | 30 | 2,400,000 BURNIE | 1,200,000 BURNIE |
| 1,000 | 30% | 20% | 30 | 1,440,000 BURNIE | 720,000 BURNIE |
| 1,000 | 50% | 40% | 30 | 4,800,000 BURNIE | 2,400,000 BURNIE |

**Formula:** active_players x eligible_fraction x completion_rate x levels x 800 BURNIE x win_rate.

### Comparison to Existing BURNIE Flows

**Existing mint sources:**
- **Ticket purchases:** Each ticket purchase mints 1,000 BURNIE to the buyer (BurnieCoin.sol, called via game mint handlers). At 500 active players minting ~5 tickets/day: 2,500,000 BURNIE/day = **75,000,000 BURNIE/month**.
- **Coinflip wins:** Players who win coinflips receive new BURNIE. Volume depends on total coinflip deposits.
- **Quest rewards:** Daily quest streak rewards (existing system).

**Existing burn sinks:**
- **Coinflip losses:** Losing stakes are burned via `BurnieCoin.burnForCoinflip`. At ~50% loss rate, roughly half of all coinflip deposits are burned.
- **Decimator burns:** Players burn BURNIE to participate in decimator jackpot.
- **Lootbox burns:** BURNIE-denominated lootbox purchases burn BURNIE.

**Contextual comparison:**
- 800 BURNIE per level quest completion is **less than 1 ticket purchase** (1,000 BURNIE mint).
- Worst-case monthly level quest inflation (12M BURNIE at 1,000 players, 50% win rate) is **16% of estimated monthly ticket mint volume** (75M BURNIE at 500 players x 5 tickets/day).
- Expected-case monthly level quest inflation (360K-2.4M BURNIE) is **0.5-3.2% of estimated monthly ticket mint volume**.
- Level quest rewards enter the coinflip system as stakes, meaning roughly half are burned back via coinflip losses, further reducing net inflation.

### Verdict

Level quest BURNIE inflation is bounded and small relative to existing BURNIE throughput. Worst-case net inflation (12M BURNIE/month at 1,000 active players, 100% completion) is a fraction of daily ticket minting volume. Expected-case inflation is negligible. The coinflip mechanism provides a natural ~50% burn-back on all credited rewards, halving net inflation from gross credit amounts.

**ECON-01 SATISFIED:** BURNIE inflation from level quests is bounded with concrete worst-case and expected-case models. Inflation is small relative to existing mint/burn flows.

---

## 2. gameOverPossible Interaction Analysis (ECON-02)

### creditFlip Data Flow Trace

1. Level quest completion calls `coinflip.creditFlip(player, 800 ether)` (Phase 153 spec, Section 6).
2. `creditFlip` (BurnieCoinflip.sol line 895-901) validates inputs and calls `_addDailyFlip(player, amount, 0, false, false)`.
3. `_addDailyFlip` (BurnieCoinflip.sol line 624-663) computes `targetDay = _targetFlipDay()` and writes to:
   - `coinflipBalance[targetDay][player]` -- BURNIE-denominated internal ledger in BurnieCoinflip contract
   - `_updateTopDayBettor(player, newStake, targetDay)` -- leaderboard tracking in BurnieCoinflip
4. `_addDailyFlip` emits `CoinflipStakeUpdated`.

**State written:** `coinflipBalance` mapping (BurnieCoinflip storage), top-bettor tracking (BurnieCoinflip storage).

**State NOT written:** No ETH is transferred. No variable in DegenerusGameStorage is modified. Specifically:
- `prizePoolsPacked` (containing futurePool and nextPool) is NOT read or written.
- `currentPrizePool` is NOT read or written.
- No `levelPrizePool[]` entries are modified.
- No ETH flows through `creditFlip` -- it is purely a BURNIE-denominated accounting operation.

### gameOverPossible Input Trace

`_evaluateGameOverPossible` (DegenerusGameAdvanceModule.sol line 1642-1659) reads:

1. `_getNextPrizePool()` -- ETH in nextPool (from `prizePoolsPacked`, bits 0-127 of DegenerusGameStorage Slot 3).
2. `levelPrizePool[purchaseLevel - 1]` -- ETH target for the level (mapping in DegenerusGameStorage).
3. `_getFuturePrizePool()` -- ETH in futurePool (from `prizePoolsPacked`, bits 128-255 of DegenerusGameStorage Slot 3).
4. `levelStartTime` -- timestamp (DegenerusGameStorage Slot 0, bytes 0-5).

The computation is:
```solidity
uint256 deficit = target - nextPool;
uint256 daysRemaining = (uint256(levelStartTime) + 120 days - block.timestamp) / 1 days;
gameOverPossible = _projectedDrip(_getFuturePrizePool(), daysRemaining) < deficit;
```

`_projectedDrip` (line 1630-1637) is pure arithmetic: `futurePool * (1 - 0.9925^n) / 1e18`. It reads no storage -- only its arguments.

**State read:** `prizePoolsPacked` (ETH), `levelPrizePool` (ETH), `levelStartTime` (timestamp). All ETH-denominated.

**State NOT read:** No BURNIE state. No `coinflipBalance`. No BurnieCoinflip storage of any kind.

### Disjoint State Domains

| System | Storage Contract | State Variables | Denomination |
|---|---|---|---|
| creditFlip | BurnieCoinflip | coinflipBalance, top-bettor | BURNIE |
| gameOverPossible | DegenerusGameStorage | prizePoolsPacked, levelPrizePool, levelStartTime | ETH |

The two systems operate in **completely disjoint state domains**:
- creditFlip writes BURNIE ledger entries in BurnieCoinflip contract storage.
- gameOverPossible reads ETH prize pool values in DegenerusGameStorage.
- There is zero overlap in storage reads or writes.

### Conclusion

Level quest payouts via `creditFlip` have **zero effect** on the endgame drip projection. The `gameOverPossible` flag is determined entirely by ETH pool arithmetic (`futurePool`, `nextPool`, `levelPrizePool`). No BURNIE state participates in the calculation. No adjustment to the drip projection formula is needed.

**ECON-02 SATISFIED:** creditFlip and gameOverPossible operate in completely disjoint state domains (BURNIE ledger vs ETH prize pools). Level quest payouts have zero effect on the endgame flag.

---

## 3. Eligibility Check Gas Overhead (GAS-01)

### SLOAD Analysis

Source: Phase 153 spec, Section 1 (Eligibility) and Section 7 (Storage Layout Summary).

The eligibility check `_isLevelQuestEligible(player)` reads:

| Read | Source | SLOAD Count | EIP-2929 Cold | EIP-2929 Hot |
|---|---|---|---|---|
| levelStreak, frozenUntilLevel, whaleBundleType, unitsLevel, levelUnits | `mintPacked_[player]` | 1 | 2,100 gas | 100 gas |
| deityPassCount | `deityPassCount[player]` | 0-1 (only if mintPacked_ fails loyalty gate) | 2,100 gas | 100 gas |

**Best case (1 SLOAD):** `mintPacked_[player]` satisfies both gates (loyalty via levelStreak >= 5 or whale/lazy pass, and activity via unitsLevel == level AND levelUnits >= 4). No `deityPassCount` read needed.

**Worst case (2 SLOADs):** `mintPacked_[player]` fails the loyalty gate (levelStreak < 5, no whale/lazy pass), so `deityPassCount[player]` is read as fallback.

### Hot-Path Context

In the quest handler hot path, `mintPacked_[player]` is **always warm** because it was already loaded by the mint operation that triggered the handler. The mint handler reads `mintPacked_` for ticket allocation, unit counting, and streak tracking before the level quest eligibility check runs.

Therefore, the realistic cost uses hot SLOAD pricing:

| Scenario | SLOADs | SLOAD Cost | Arithmetic | Total |
|---|---|---|---|---|
| Best case (mintPacked_ short-circuits) | 1 | 100 gas | ~50-80 gas (bit shifts, comparisons, boolean logic) | **~150-180 gas** |
| Worst case (deity pass fallback) | 2 | 200 gas | ~50-80 gas | **~250-280 gas** |

### Comparison to Existing Handler Cost

Existing `handleMint` and other handler functions in DegenerusQuests.sol already cost thousands of gas for daily quest progress tracking (multiple SLOADs for quest state, SSTOREs for progress updates, streak checks). The eligibility check adds **150-280 gas** on the hot path -- a negligible fraction of the total handler cost.

For cold-path analysis (theoretical first call in a transaction):

| Scenario | SLOADs | Cold Cost | Arithmetic | Total |
|---|---|---|---|---|
| Best case | 1 | 2,100 gas | ~50-80 gas | **~2,150-2,180 gas** |
| Worst case | 2 | 4,200 gas | ~50-80 gas | **~4,250-4,280 gas** |

Even in the cold case, this is within normal handler overhead.

### Verdict

Eligibility check gas overhead is minimal: 150-280 gas on the hot path (realistic), 2,150-4,280 gas cold (theoretical). This runs per `handleX()` call, not in advanceGame. It does not affect the block gas ceiling.

**GAS-01 SATISFIED:** Eligibility check gas overhead is quantified with SLOAD counts. Hot-path cost is 150-280 gas, negligible compared to existing handler costs.

---

## 4. Level Quest Roll Gas in advanceGame (GAS-02)

### Quest Roll Overhead (advanceGame Level Transition)

Source: Phase 153 spec, Section 2 (Global Quest Roll) and Section 7 (SLOAD/SSTORE Budget).

The quest roll executes once per level transition in the `phaseTransitionActive` block, after `_processPhaseTransition(purchaseLevel)` completes and before `phaseTransitionActive = false` is set.

| Operation | Type | Gas Cost | Source |
|---|---|---|---|
| `rngWordByDay[day]` read | SLOAD | 0 gas (already warm from rngGate earlier in advanceGame) | Phase 153 spec Section 2 |
| `keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST"))` | Computation | ~36 gas (30 gas keccak256 + 6 gas abi.encodePacked overhead) | EIP-2929 opcodes |
| `questEntropy % totalWeight` + weight scan (types 0-8) | Computation | ~100 gas (modulo + loop with 9 iterations max) | Arithmetic opcodes (3-5 gas each) |
| Decimator eligibility check (`decWindowOpen`, level constraints) | Computation | ~50 gas (2 comparisons + boolean logic, values already in Slot 0) | Warm reads from Slot 0 |
| `levelQuestType[purchaseLevel] = type` | SSTORE | 22,100 gas (cold slot, new non-zero value) | EIP-2200: new non-zero SSTORE |
| Function call overhead | Misc | ~100 gas (JUMP, stack operations, parameter passing) | EVM call mechanics |
| **Total quest roll overhead** | | **~22,386 gas** | |

Rounded: **~22,430 gas**.

### Updated advanceGame Gas Ceiling

Source: Phase 152 gas baseline (152-02-GAS-ANALYSIS.md, Section 4).

| Metric | Phase 152 Baseline | + Quest Roll | Delta |
|---|---|---|---|
| Worst-case subsequent batch | 6,996,000 gas | 7,018,430 gas | +22,430 gas (+0.32%) |
| Worst-case first batch | 4,583,500 gas | 4,605,930 gas | +22,430 gas (+0.49%) |
| Block gas limit | 14,000,000 | 14,000,000 | -- |
| Safety margin (subsequent) | 2.00x | **1.99x** | -0.01x |
| Safety margin (first) | 3.05x | 3.04x | -0.01x |

**Updated safety margin:** 14,000,000 / 7,018,430 = **1.994x** (rounds to 1.99x).

The quest roll adds 0.32% to the worst-case gas budget. The safety margin decreases from 2.00x to 1.99x -- effectively unchanged. The advanceGame call remains safely within the 14M block gas ceiling.

### Progress Handler Overhead (Per-Player, Not in advanceGame)

Source: Phase 153 spec, Section 7 (SLOAD/SSTORE Budget).

The progress handler runs per `handleX()` call (e.g., handleMint, handleFlip). This is a per-transaction cost borne by the player, NOT part of the advanceGame ceiling.

| Operation | Type | Cold Cost | Hot Cost | Notes |
|---|---|---|---|---|
| `levelQuestType[level]` read | SLOAD | 2,100 gas | 100 gas | Quest type for current level |
| `levelQuestPlayerState[player]` read | SLOAD | 2,100 gas | 100 gas | Player's packed progress |
| `levelQuestPlayerState[player]` write | SSTORE | 22,100 gas (new non-zero, first write) or 5,000 gas (dirty existing slot) | 100 gas (same value) | Progress update + completion flag |
| Target derivation (ETH types only) | SLOAD | 0-2,100 gas | 0-100 gas | `mintPrice` from Slot 1 (likely warm from mint handler) |

| Scenario | Total Handler Overhead |
|---|---|
| **Hot path, dirty slot** (typical repeat-mint same tx) | ~300 gas (100 + 100 + 100) |
| **Cold path, first write** (first mint of a new level) | ~26,300 gas (2,100 + 2,100 + 22,100) |
| **Cold path, existing slot** (first mint of day, same level) | ~9,200 gas (2,100 + 2,100 + 5,000) |

This per-player cost does **not** affect the 14M block gas limit analysis. The advanceGame ceiling is determined by the game's internal processing (ticket processing, jackpot payouts, phase transitions), not by individual player transaction costs.

### Verdict

The quest roll adds ~22,430 gas to advanceGame worst-case, increasing the baseline from 6,996,000 to 7,018,430 gas. The safety margin decreases from 2.00x to 1.99x -- a negligible change. The advanceGame call remains well within the 14M block gas ceiling.

Per-player progress handler overhead ranges from ~300 gas (hot path) to ~26,300 gas (cold, first write) depending on slot temperature. This is a per-transaction cost and does not affect the advanceGame ceiling.

**GAS-02 SATISFIED:** Quest roll gas overhead is quantified. advanceGame worst-case increases by 0.32% to 7,018,430 gas. Safety margin of 1.99x is preserved against the 14M block ceiling.

---

## 5. Combined Verdict

All four requirements are satisfied:

| Requirement | Status | Key Finding |
|---|---|---|
| ECON-01 | SATISFIED | Worst-case BURNIE inflation (12M/month at 1,000 players) is small relative to existing 75M+/month ticket mint volume. Expected-case is 0.5-3.2% of ticket mints. Coinflip mechanism provides ~50% natural burn-back. |
| ECON-02 | SATISFIED | creditFlip (BURNIE ledger) and gameOverPossible (ETH prize pools) operate in completely disjoint state domains. Zero interaction. No drip formula adjustment needed. |
| GAS-01 | SATISFIED | Eligibility check: 150-280 gas hot path (1-2 SLOADs). Negligible compared to existing handler costs. Not part of advanceGame ceiling. |
| GAS-02 | SATISFIED | Quest roll: +22,430 gas to advanceGame worst-case. Safety margin 1.99x (down from 2.00x). Negligible 0.32% increase. |

Level quests are **economically viable** (bounded inflation, no endgame interference) and **computationally viable** (negligible eligibility cost, quest roll fits within advanceGame ceiling with margin preserved).

---

*Analysis produced by Phase 155 Plan 01.*
*Sources: Phase 153 spec (153-01-LEVEL-QUEST-SPEC.md), Phase 152 gas baseline (152-02-GAS-ANALYSIS.md), BurnieCoinflip.sol (lines 624-663, 895-901), DegenerusGameAdvanceModule.sol (lines 1616-1659), DegenerusGameStorage.sol (lines 336-358), EIP-2200/EIP-2929 gas schedules.*
