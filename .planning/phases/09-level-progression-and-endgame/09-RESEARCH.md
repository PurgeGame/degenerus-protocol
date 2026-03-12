# Phase 9: Level Progression and Endgame - Research

**Researched:** 2026-03-12
**Domain:** Solidity smart contract economic analysis -- level transitions, price curves, death clock, terminal distribution
**Confidence:** HIGH

## Summary

Phase 9 documents the complete lifecycle of the Degenerus game from level transitions through terminal game-over conditions. The core mechanics are: (1) a repeating 100-level price curve with intro-tier overrides, (2) a ratcheting purchase target that determines when each level's purchase phase ends, (3) a 120-day liveness timeout per level (365-day at level 0) that triggers game over, (4) distress mode activating 6 hours before timeout, and (5) a terminal distribution that pays 10% to decimator and 90% to next-level ticketholders.

The activity score system combines mint streaks, mint count participation, quest streaks, affiliate bonuses, and pass/deity bonuses into a single BPS value. This score directly affects degenerette (lottery) ROI curves and lootbox ticket multipliers. Whale bundle and lazy pass economics shift across levels because their ticket quantities are fixed while ticket prices rise with the price curve -- making early-level passes dramatically more valuable per ETH.

**Primary recommendation:** Structure documentation as three interconnected reference documents: (1) price curve + level transition mechanics, (2) death clock + terminal distribution, (3) activity score system. Each must include exact Solidity expressions for agent consumption.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LEVL-01 | Document price curve across all level ranges with exact values | PriceLookupLib.priceForLevel() -- complete price table extracted, 7 tiers + 100-level cycle |
| LEVL-02 | Document level length (120d) effects on pool accumulation dynamics | _applyTimeBasedFutureTake with time-decay BPS curve, _drawDownFuturePrizePool 15% drawdown, purchase target ratchet |
| LEVL-03 | Document how whale bundle and lazy pass duration economics change across levels | WhaleModule pricing (2.4/4 ETH), _lazyPassCost sum-of-prices, ticket-to-price ratio analysis across tiers |
| LEVL-04 | Document activity score system and consecutive streak mechanics | _playerActivityScore component breakdown, MintStreakUtils consecutive-level logic, module score thresholds |
| END-01 | Document death clock (120d timeout, 365d deploy, distress mode, terminal gameOver) | _handleGameOverPath liveness guard, _isDistressMode 6-hour window, _isGameoverImminent 5-day early signal |
| END-02 | Document final distribution when gameOver triggers | handleGameOverDrain 10/90 split, deity pass early refund, handleFinalSweep 30-day unclaimed forfeiture |
</phase_requirements>

## Standard Stack

Not applicable -- this is a documentation/analysis phase, not a code implementation phase. The "stack" is the contract source code being analyzed.

### Key Source Contracts

| Contract | Path | Relevance |
|----------|------|-----------|
| PriceLookupLib | contracts/libraries/PriceLookupLib.sol | Complete price curve definition |
| DegenerusGameAdvanceModule | contracts/modules/DegenerusGameAdvanceModule.sol | Level transitions, purchase target, future pool drawdown, death clock |
| DegenerusGameGameOverModule | contracts/modules/DegenerusGameGameOverModule.sol | Terminal distribution, final sweep |
| DegenerusGameEndgameModule | contracts/modules/DegenerusGameEndgameModule.sol | BAF/Decimator during transitions (already documented in Phase 7, but contextually relevant) |
| DegenerusGameStorage | contracts/storage/DegenerusGameStorage.sol | Distress mode, constants, pool helpers |
| DegenerusGame | contracts/DegenerusGame.sol | Activity score, view helpers, constructor |
| DegenerusGameWhaleModule | contracts/modules/DegenerusGameWhaleModule.sol | Whale bundle and lazy pass pricing |
| DegenerusGameMintStreakUtils | contracts/modules/DegenerusGameMintStreakUtils.sol | Consecutive streak recording/evaluation |

## Architecture Patterns

### LEVL-01: Complete Price Curve

PriceLookupLib.priceForLevel() defines a 100-level repeating cycle with intro overrides:

**Intro Tiers (levels 0-9):**

| Level Range | Price (ETH) | Override of |
|-------------|-------------|-------------|
| 0-4 | 0.01 | Would be 0.04 in cycle |
| 5-9 | 0.02 | Would be 0.04 in cycle |

**First Full Cycle (levels 10-99):**

| Level Range | Price (ETH) |
|-------------|-------------|
| 10-29 | 0.04 |
| 30-59 | 0.08 |
| 60-89 | 0.12 |
| 90-99 | 0.16 |

**Repeating Cycle (levels 100+):**

| Level Range | Price (ETH) | Pattern |
|-------------|-------------|---------|
| x00 (100, 200, 300...) | 0.24 | Milestone |
| x01-x29 | 0.04 | Early cycle |
| x30-x59 | 0.08 | Mid cycle |
| x60-x89 | 0.12 | Late cycle |
| x90-x99 | 0.16 | Final cycle |

**Exact Solidity (PriceLookupLib.sol:21-46):**
```solidity
function priceForLevel(uint24 targetLevel) internal pure returns (uint256) {
    if (targetLevel < 5) return 0.01 ether;
    if (targetLevel < 10) return 0.02 ether;
    if (targetLevel < 30) return 0.04 ether;
    if (targetLevel < 60) return 0.08 ether;
    if (targetLevel < 90) return 0.12 ether;
    if (targetLevel < 100) return 0.16 ether;
    uint256 cycleOffset = targetLevel % 100;
    if (cycleOffset == 0) return 0.24 ether;
    else if (cycleOffset < 30) return 0.04 ether;
    else if (cycleOffset < 60) return 0.08 ether;
    else if (cycleOffset < 90) return 0.12 ether;
    else return 0.16 ether;
}
```

### LEVL-02: Level Length and Pool Accumulation

**Purchase Target Ratchet:**
- Level 0 target: `BOOTSTRAP_PRIZE_POOL = 50 ether` (set in constructor)
- Level N target: `levelPrizePool[N] = _getNextPrizePool()` at level N transition (snapshot at AdvanceModule:269)
- x00 levels special: `levelPrizePool[lvl] = _getFuturePrizePool() / 3` (set in `_endPhase()`, AdvanceModule:430)
- Level advances when: `_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1]` (AdvanceModule:243)

**120-Day Level Duration Effect:**
- `levelStartTime` is set to `block.timestamp` at each jackpot phase entry (AdvanceModule:289)
- The liveness guard fires when `ts - 120 days > levelStartTime` for levels > 0
- Longer levels increase the time-based future pool skim via `_applyTimeBasedFutureTake`

**Time-Based Future Take (`_nextToFutureBps`):**
The BPS rate for skimming nextPool into futurePool depends on how long the level took:

| Elapsed Time | BPS Formula | Range (level 0, no bonus) |
|-------------|-------------|---------------------------|
| <= 1 day | `FAST(3000) + lvlBonus` | 3000-3900 |
| 1-14 days | Linear decay from FAST to MIN(1300) | 3000->1300 |
| 14-28 days | Linear rise from MIN to FAST+lvlBonus | 1300->3000+ |
| > 28 days | `FAST + lvlBonus + weekStep(100) * weeks_past_28` | Uncapped (max 10000) |

Where `lvlBonus = (lvl % 100 / 10) * 100` (e.g., level 50 = +500 BPS)

Additional modifiers (AdvanceModule:871+):
- x9 levels: `+NEXT_TO_FUTURE_BPS_X9_BONUS(200)`
- Ratio adjust: +/-2% based on future:next ratio (baseline 2:1)
- Growth adjust: +/-2% based on pool growth vs previous level

**Future Pool Drawdown (`_drawDownFuturePrizePool`):**
At each jackpot phase entry:
- Normal levels: 15% of futurePool moves to nextPool
- x00 levels: 0% (skip draw)

### LEVL-03: Whale Bundle and Lazy Pass Across Levels

**Whale Bundle (100-level):**

| Property | Value |
|----------|-------|
| Early price (levels 0-3) | 2.4 ETH per unit |
| Standard price (levels 4+) | 4 ETH per unit |
| Boon discount | 10/25/50% off standard (4 ETH base) |
| Max quantity per purchase | 100 units |
| Tickets per level (levels 1-10) | 40 per unit (bonus) |
| Tickets per level (levels 11+) | 2 per unit (standard) |
| Freeze duration | 100 levels from purchase |
| Pool split (level 0) | 30% next / 70% future |
| Pool split (level 1+) | 5% next / 95% future |
| Lootbox (presale) | 20% of price |
| Lootbox (post-presale) | 10% of price |

**Key economic shift:** At 4 ETH for 100 levels x 2 tickets/level = 200 tickets. Ticket value depends on price tier:
- At 0.04 ETH levels: 200 tickets worth 8 ETH (2x)
- At 0.08 ETH levels: 200 tickets worth 16 ETH (4x)
- At 0.12 ETH levels: 200 tickets worth 24 ETH (6x)
- At 0.16 ETH levels: 200 tickets worth 32 ETH (8x)
- At 0.24 ETH milestone: 200 tickets worth 48 ETH (12x)

Whale bundles become dramatically more valuable when purchased before high-price-tier level ranges.

**Lazy Pass (10-level):**

| Property | Value |
|----------|-------|
| Availability | Levels 0-2, or x9 (9,19,29...), or with boon |
| Early price (levels 0-2) | Flat 0.24 ETH |
| Standard price (levels 3+) | Sum of `PriceLookupLib.priceForLevel(startLevel + i)` for i in 0..9 |
| Tickets per level | 4 |
| Freeze duration | 10 levels |
| Renewal window | When <= 7 levels remain on current freeze |
| Pool split | 10% future (`LAZY_PASS_TO_FUTURE_BPS=1000`), 90% next |
| Lootbox (presale) | 20% of benefit value |
| Lootbox (post-presale) | 10% of benefit value |
| Boon discount default | 10% (`LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS=1000`) |

**Lazy pass cost examples by starting level:**

| Start Level | Levels Covered | Sum of Prices | Per-Level Avg |
|------------|----------------|---------------|---------------|
| 1 (from level 0) | 1-10 | 5 x 0.01 + 5 x 0.02 = 0.15 ETH | 0.015 |
| 10 | 10-19 | 10 x 0.04 = 0.40 ETH | 0.04 |
| 30 | 30-39 | 10 x 0.08 = 0.80 ETH | 0.08 |
| 60 | 60-69 | 10 x 0.12 = 1.20 ETH | 0.12 |
| 90 | 90-99 | 10 x 0.16 = 1.60 ETH | 0.16 |
| 100 | 100-109 | 0.24 + 9 x 0.04 = 0.60 ETH | 0.06 |

### LEVL-04: Activity Score System

**Components (all in BPS, additive):**

**For non-deity, non-pass players:**

| Component | Calculation | Max BPS |
|-----------|-------------|---------|
| Mint streak | 1% per consecutive level minted | 5000 (50 levels) |
| Mint count | `(mintCount * 25) / currLevel * 100` BPS | 2500 (100% participation = 25pts) |
| Quest streak | 1% per quest streak | 10000 (100 quests) |
| Affiliate bonus | `affiliateBonusPointsBest * 100` | variable |
| Whale bundle bonus (10-level, type 1) | +1000 BPS | 1000 (while frozen) |
| Whale bundle bonus (100-level, type 3) | +4000 BPS | 4000 (while frozen) |

**For active lazy/whale pass holders (frozenUntilLevel > currentLevel):**
- Streak floor: `PASS_STREAK_FLOOR_POINTS = 50` (i.e., 5000 BPS minimum)
- Mint count floor: `PASS_MINT_COUNT_FLOOR_POINTS = 25` (i.e., 2500 BPS minimum)

**For deity pass holders:**
- Fixed: 50 * 100 + 25 * 100 = 7500 BPS (replaces streak+count components)
- Plus: `DEITY_PASS_ACTIVITY_BONUS_BPS = 8000`
- Plus: quest streak + affiliate bonus (same as above)
- Total deity minimum: 15500 BPS (before quest/affiliate)

**Mint Streak Mechanics (MintStreakUtils.sol):**
- `_recordMintStreakForLevel(player, mintLevel)`: idempotent per level
- Streak increments if `lastCompleted + 1 == mintLevel` (consecutive)
- Streak resets to 1 if gap detected
- Stored in `mintPacked_[player]` bits [160:184] (lastCompleted) and [LEVEL_STREAK_SHIFT] (streak)
- `_mintStreakEffective(player, currentMintLevel)`: returns 0 if `currentMintLevel > lastCompleted + 1` (gap detection)

**Where activity score is consumed:**

| Consumer | Threshold Constants | Effect |
|----------|-------------------|--------|
| Lootbox tickets | NEUTRAL=6000, MAX=25500 BPS | Scales future ticket multiplier |
| Degenerette ROI | MID=7500, HIGH=25500, MAX=30500 BPS | Three-tier piecewise ROI curve |
| Degenerette WWXRP | Same tiers | Separate high-value ROI function |

### END-01: Death Clock

**Three liveness conditions:**

1. **Deploy timeout (level 0 only):** `ts - levelStartTime > 365 days`
2. **Level timeout (level > 0):** `ts - 120 days > levelStartTime` (equivalently `ts - levelStartTime > 120 days`)
3. **Safety valve:** If `_getNextPrizePool() >= levelPrizePool[lvl]` when timeout fires, the level simply resets `levelStartTime = ts` and continues (AdvanceModule:401-403)

**Distress Mode (`_isDistressMode`):**
- Activates 6 hours before liveness timeout: `ts + 6 hours > levelStartTime + 120 days`
- Level 0: `ts + 6 hours > levelStartTime + 365 days`
- Effects: lootbox purchases route 100% to nextPool and get 25% ticket bonus on distress portion
- Constant: `DISTRESS_TICKET_BONUS_BPS = 2500`

**Game Over Imminent (`_isGameoverImminent`):**
- Level 0: `ts + 10 days > levelStartTime + 365 days`
- Level > 0: `ts + 5 days > levelStartTime + 120 days`
- Effect: allows decimator burns near liveness timeout

**RNG for game over:**
- Normal: VRF request with standard flow
- Fallback after 3 days (`GAMEOVER_RNG_FALLBACK_DELAY`): hashes up to 5 early historical VRF words + currentDay + block.prevrandao
- Purpose: ensures game can always terminate even if Chainlink VRF is stalled

### END-02: Terminal Distribution (handleGameOverDrain)

**Flow:**

1. **Early game over (levels 0-9):** Fixed 20 ETH refund per deity pass purchased
   - FIFO by `deityPassOwners` array order
   - Budget-capped: `totalFunds - claimablePool`
   - Constant: `DEITY_PASS_EARLY_GAMEOVER_REFUND = 20 ether`

2. **Set terminal state:** `gameOver = true`, `gameOverTime = block.timestamp`

3. **Clear all pool storage:** nextPrizePool, futurePrizePool, currentPrizePool all set to 0

4. **Decimator (10%):** `remaining / 10` to `runDecimatorJackpot`
   - Refunds flow back to remaining for terminal jackpot

5. **Terminal Jackpot (90% + decimator refund):** `runTerminalJackpot(remaining, lvl + 1, rngWord)`
   - Uses next-level ticketholders (Day-5-style bucket distribution)
   - `gameOver=true` prevents auto-rebuy inside `_addClaimableEth`

6. **Undistributed remainder:** swept to vault via `_sendToVault`

7. **DGNRS cleanup:** burns undistributed pool tokens (`dgnrs.burnForGame`)

**Final Sweep (handleFinalSweep):**
- Triggers 30 days after `gameOverTime`
- Forfeits ALL unclaimed winnings (`claimablePool = 0`)
- Splits entire remaining balance 50/50: vault and DGNRS contract
- Shuts down VRF subscription (fire-and-forget)
- stETH prioritized over ETH for transfers

**Vault split (`_sendToVault`):**
- 50% to `ContractAddresses.VAULT` (stETH preferred, ETH fallback)
- 50% to `ContractAddresses.DGNRS` (stETH via `depositSteth`, ETH via direct transfer)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Price curve computation | Manual tier tables | Extract directly from PriceLookupLib.priceForLevel() | Exact Solidity logic, no approximation errors |
| Purchase target explanation | Prose descriptions of "when level ends" | Document the ratchet: `nextPool >= levelPrizePool[level]` | Single comparison expression is the complete rule |
| Activity score tiers | Separate component descriptions | Unified formula with exact BPS thresholds from code | Components interact (floors for pass holders change the math) |

## Common Pitfalls

### Pitfall 1: x00 Level Special Cases
**What goes wrong:** Missing that x00 levels have THREE special behaviors
**Why it happens:** The specials are spread across different functions
**How to avoid:** Document all three in one place:
1. Price = 0.24 ETH (PriceLookupLib)
2. `levelPrizePool[lvl] = _getFuturePrizePool() / 3` instead of nextPool snapshot (_endPhase)
3. `_drawDownFuturePrizePool` skips the 15% draw (reserved = 0)

### Pitfall 2: Purchase Target is NOT a Fixed Formula
**What goes wrong:** Describing the target as "always equal to the previous level's nextPool"
**Why it happens:** That IS the normal case, but x00 levels override it
**How to avoid:** Clearly state: normal levels use `levelPrizePool[N] = nextPool at transition`, x00 levels use `futurePrizePool / 3`

### Pitfall 3: Distress Mode vs Game Over Imminent vs Actual Timeout
**What goes wrong:** Conflating the three escalation stages
**Why it happens:** They're similar countdown checks with different offsets
**How to avoid:** Document as a timeline:
- 120 days - 5 days = "imminent" (decimator burns allowed)
- 120 days - 6 hours = "distress" (lootbox 100% next, 25% bonus)
- 120 days = game over triggers (if nextPool still < target)

### Pitfall 4: Activity Score Pass Holder Floors
**What goes wrong:** Computing activity score without applying floors for active pass holders
**Why it happens:** The floor logic is conditional and easy to miss
**How to avoid:** Explicitly state: when `frozenUntilLevel > currentLevel` AND `bundleType in {1,3}`, streak and mint count floors override lower computed values

### Pitfall 5: Terminal Distribution Level Reference
**What goes wrong:** Assuming terminal jackpot pays current-level ticketholders
**Why it happens:** Intuition says "pay the people playing now"
**How to avoid:** Code uses `lvl + 1` for terminal jackpot -- pays NEXT level ticketholders (people who bought ahead)

## Code Examples

### Purchase Target Check (Level Advancement Trigger)
```solidity
// Source: DegenerusGameAdvanceModule.sol:243-246
if (_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1]) {
    lastPurchaseDay = true;
    compressedJackpotFlag = (day - purchaseStartDay <= 2);
}
```

### Liveness Guard (Death Clock)
```solidity
// Source: DegenerusGameAdvanceModule.sol:380-382
bool livenessTriggered = (lvl == 0 &&
    ts - lst > uint256(DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days) ||
    (lvl != 0 && ts - 120 days > lst);
```

### Distress Mode Check
```solidity
// Source: DegenerusGameStorage.sol:169-178
function _isDistressMode() internal view returns (bool) {
    if (gameOver) return false;
    uint48 lst = levelStartTime;
    uint48 ts = uint48(block.timestamp);
    if (level == 0) {
        return uint256(ts) + uint256(DISTRESS_MODE_HOURS) * 1 hours >
            uint256(lst) + uint256(_DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days;
    }
    return uint256(ts) + uint256(DISTRESS_MODE_HOURS) * 1 hours > uint256(lst) + 120 days;
}
```

### Game Over Terminal Distribution
```solidity
// Source: DegenerusGameGameOverModule.sol:136-158
// 10% Decimator
uint256 decPool = remaining / 10;
uint256 decRefund = runDecimatorJackpot(decPool, lvl, rngWord);
remaining -= decPool;
remaining += decRefund; // Return decimator refund for terminal jackpot

// 90% (+ decimator refund) to next-level ticketholders
uint256 termPaid = runTerminalJackpot(remaining, lvl + 1, rngWord);
remaining -= termPaid;
if (remaining != 0) _sendToVault(remaining, stBal);
```

### Activity Score Components
```solidity
// Source: DegenerusGame.sol:2387-2463
// Non-deity, non-pass:
//   streakPoints = min(streak, 50) * 100 BPS
//   mintCountPoints = min((mintCount * 25) / currLevel, 25) * 100 BPS
//   questStreak = min(questStreakRaw, 100) * 100 BPS
//   affiliateBonus = affiliateBonusPointsBest * 100 BPS
//
// Active pass holder (frozenUntilLevel > currLevel, bundleType 1 or 3):
//   streakPoints = max(computed, 50) * 100 BPS
//   mintCountPoints = max(computed, 25) * 100 BPS
//   bundleBonus = 1000 (type 1) or 4000 (type 3) BPS
//
// Deity pass:
//   fixed 7500 BPS + DEITY_PASS_ACTIVITY_BONUS_BPS(8000) + quest + affiliate
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Fixed price per level | 100-level repeating cycle with intro tiers | Contract design (v1.0) | Price resets at each century boundary |
| Simple timeout | 3-stage escalation (imminent/distress/timeout) | Contract design (v1.0) | Players have incentive windows before game over |

## Open Questions

1. **Terminal jackpot internals**
   - What we know: `runTerminalJackpot(remaining, lvl + 1, rngWord)` uses Day-5-style bucket distribution
   - What's unclear: Exact mechanics of `runTerminalJackpot` in JackpotModule (already documented in Phase 7?)
   - Recommendation: Cross-reference Phase 7 jackpot phase draws documentation; if terminal jackpot specifics are missing, trace through JackpotModule

2. **stETH handling in game over**
   - What we know: `_sendToVault` prioritizes stETH transfers, splits 50/50 vault/DGNRS
   - What's unclear: Whether stETH yield that accrued during game lifetime is included or separate
   - Recommendation: Note as cross-reference to Phase 10 stETH documentation (STETH-01/02)

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) |
| Config file | foundry.toml (if exists) |
| Quick run command | `forge test --match-contract LevelProgressionTest -x` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LEVL-01 | Price curve values match PriceLookupLib | manual-only | N/A -- documentation audit | N/A |
| LEVL-02 | Pool accumulation formulas match AdvanceModule | manual-only | N/A -- documentation audit | N/A |
| LEVL-03 | Whale/lazy pass cost calculations match WhaleModule | manual-only | N/A -- documentation audit | N/A |
| LEVL-04 | Activity score components match DegenerusGame | manual-only | N/A -- documentation audit | N/A |
| END-01 | Death clock timing constants match AdvanceModule + Storage | manual-only | N/A -- documentation audit | N/A |
| END-02 | Terminal distribution formulas match GameOverModule | manual-only | N/A -- documentation audit | N/A |

### Sampling Rate
- **Per task commit:** Manual review -- verify all Solidity expressions match source
- **Per wave merge:** Cross-check constant values against contract source
- **Phase gate:** All documented formulas traceable to exact source lines

### Wave 0 Gaps
None -- this is a documentation phase, not a code phase. No test infrastructure needed.

## Sources

### Primary (HIGH confidence)
- `contracts/libraries/PriceLookupLib.sol` -- complete price curve logic (47 lines, fully read)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- level transitions, purchase target, future pool dynamics, death clock, all constants
- `contracts/modules/DegenerusGameGameOverModule.sol` -- terminal distribution, final sweep (234 lines, fully read)
- `contracts/modules/DegenerusGameEndgameModule.sol` -- BAF/Decimator at transitions (522 lines, fully read)
- `contracts/storage/DegenerusGameStorage.sol` -- distress mode, bootstrap pool, DISTRESS_MODE_HOURS
- `contracts/DegenerusGame.sol` -- _playerActivityScore, _mintCountBonusPoints, _isGameoverImminent, constructor
- `contracts/modules/DegenerusGameWhaleModule.sol` -- whale bundle pricing, lazy pass pricing, ticket quantities
- `contracts/modules/DegenerusGameMintStreakUtils.sol` -- streak recording and evaluation (62 lines, fully read)

### Secondary (MEDIUM confidence)
- `audit/06-pool-architecture.md` -- prior phase documentation confirming purchase target ratchet system

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all source contracts fully read, no external dependencies
- Architecture: HIGH -- every formula extracted directly from Solidity source with line numbers
- Pitfalls: HIGH -- derived from actual code complexity (x00 specials, pass floors, terminal level reference)

**Research date:** 2026-03-12
**Valid until:** Indefinite (contract source is immutable deployed code)
