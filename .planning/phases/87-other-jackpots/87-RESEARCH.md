# Phase 87: Other Jackpots - Research

**Researched:** 2026-03-23
**Domain:** Solidity smart contract audit -- early-bird lootbox, BAF, decimator, degenerette, and final-day DGNRS jackpot mechanics
**Confidence:** HIGH

## Summary

Phase 87 requires exhaustive code tracing of five distinct jackpot subsystems that fall outside the daily ETH / daily coin+ticket jackpot scopes covered by Phases 85-86. Each jackpot type has different trigger conditions, prize pool sources, winner selection algorithms, payout mechanics, and RNG dependencies. The five subsystems are:

1. **Early-bird lootbox jackpot** -- Runs on jackpot Day 1 of each level, allocating 3% of futurePrizePool to 100 trait-based winners who receive tickets at the current level (or +0 to +4 level offset).

2. **BAF (Big-Ass Flip) jackpot** -- Leaderboard-based distribution triggered every 10 levels. Uses a standalone `DegenerusJackpots.sol` contract for winner selection (top BAF bettors, top coinflip bettor, far-future ticket holders, scatter ticket sampling). The EndgameModule processes payouts with a large/small winner split (ETH vs lootbox).

3. **Decimator jackpot** -- Burn-based bucket/subbucket system with deferred (claimable) distribution. Fires at levels x5 (not x95) and x00 (special 30% pool). The terminal decimator ("death bet") is a separate always-open variant resolved at GAMEOVER.

4. **Degenerette jackpot** -- Symbol-match betting game (4 quadrants, 8 attributes). ETH payouts split 25% claimable ETH / 75% lootbox, with a 10% futurePrizePool cap. sDGNRS rewards from Reward pool on 6+ match ETH bets. Consolation prize (1 WWXRP) for qualifying losing bets.

5. **Final-day DGNRS distribution** -- Awards 1% of the sDGNRS Reward pool to the solo bucket winner from Day 5 winning traits. Fires once per level transition (after last daily jackpot).

The codebase is spread across 6 contract files and uses delegatecall architecture throughout. The most complex subsystem is BAF, which spans two contracts (`DegenerusJackpots.sol` for winner selection, `DegenerusGameEndgameModule.sol` for payout processing). The decimator is the most stateful, with per-player DecEntry structs, bucket aggregates, packed winning subbucket storage, and a separate terminal variant for GAMEOVER.

**Primary recommendation:** Audit each jackpot type independently with full file:line citations. For each: trace the trigger path from advanceGame, document prize pool source and allocation, trace winner selection algorithm, document payout mechanics (ETH/tickets/DGNRS), verify RNG dependencies, and flag any discrepancies with prior audit documentation.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| OJCK-01 | Early-bird lootbox jackpot mechanics documented with file:line | `_runEarlyBirdLootboxJackpot` at JM:801-864, triggered at JM:381 on jackpot Day 1. Sources 3% from futurePrizePool, 100 winners via trait sampling, tickets queued at current+0 to +4 level offset, budget recycled to nextPrizePool. |
| OJCK-02 | BAF (Buy and Flip) jackpot mechanics documented with file:line | Two-contract system: `DegenerusJackpots.runBafJackpot` (DJ:229-529) selects winners + amounts, `EndgameModule._runBafJackpot` (EM:345-423) processes payouts. Trigger: `runRewardJackpots` (EM:168) at levels x0. Pool: 10-20% of futurePrizePool. Distribution: 10% top BAF, 5% top coinflip, 5% random 3rd/4th, 10% far-future (two draws), 70% scatter (50 rounds x top-2). |
| OJCK-03 | Decimator jackpot mechanics documented with file:line | Burn tracking: `recordDecBurn` (DM:129-188). Resolution: `runDecimatorJackpot` (DM:205-256). Claims: `claimDecimatorJackpot` (DM:316-338) with 50/50 ETH/lootbox split. Terminal variant: `recordTerminalDecBurn` (DM:707-770), `runTerminalDecimatorJackpot` (DM:783-825), `claimTerminalDecimatorJackpot` (DM:833-840). |
| OJCK-04 | Degenerette jackpot mechanics documented with file:line | Bet placement: `placeFullTicketBets` (DDM:388-404). Resolution: `_resolveFullTicketBet` (DDM:585-672). Payout: `_distributePayout` (DDM:680-715) -- 25% ETH (capped at 10% pool), 75% lootbox. sDGNRS rewards: `_awardDegeneretteDgnrs` (DDM:1164-1178) on 6+ matches. Consolation: `_maybeAwardConsolation` (DDM:722-737). |
| OJCK-05 | Final day DGNRS distribution mechanics documented with file:line | `awardFinalDayDgnrsReward` at JM:773-798. Awards 1% (FINAL_DAY_DGNRS_BPS=100) of sDGNRS Reward pool. Uses `lastDailyJackpotWinningTraits` to re-derive solo bucket, selects one winner via `_randTraitTicket`, transfers from Reward pool. Triggered at AM:365 when jackpotCounter >= JACKPOT_LEVEL_CAP (5). |
| OJCK-06 | Every discrepancy and new finding tagged | Research identified key areas to check: sampleFarFutureTickets using _tqWriteKey (known from Phase 81 DSC-02, BAF uses this), Degenerette _addClaimableEth does NOT auto-rebuy (unlike JM/DM versions), topDegeneretteByLevel is only written not consumed by jackpot logic. |
</phase_requirements>

## Architecture Patterns

### Contract Architecture (Delegatecall)

All five jackpot types execute via delegatecall from `DegenerusGame.sol`, sharing the storage layout in `DegenerusGameStorage.sol`. The BAF jackpot uniquely spans two contracts:

| Module | File | Lines | Jackpot Role |
|--------|------|-------|--------------|
| JackpotModule | `contracts/modules/DegenerusGameJackpotModule.sol` | 2794 | Early-bird lootbox (JM:801), final-day DGNRS (JM:773), terminal jackpot (JM:282) |
| EndgameModule | `contracts/modules/DegenerusGameEndgameModule.sol` | 555 | BAF trigger+payout (EM:168, EM:345), decimator trigger dispatch (EM:205-231) |
| DecimatorModule | `contracts/modules/DegenerusGameDecimatorModule.sol` | 930 | Decimator burn tracking, resolution, claims; terminal decimator |
| DegeneretteModule | `contracts/modules/DegenerusGameDegeneretteModule.sol` | 1179 | Degenerette bets, resolution, payouts, sDGNRS rewards |
| DegenerusJackpots | `contracts/DegenerusJackpots.sol` | 689 | BAF leaderboard + winner selection (standalone contract, NOT delegatecall) |
| GameOverModule | `contracts/modules/DegenerusGameGameOverModule.sol` | 235 | Terminal decimator + terminal jackpot dispatch at GAMEOVER |
| AdvanceModule | `contracts/modules/DegenerusGameAdvanceModule.sol` | 1558 | Trigger orchestration for all level-transition jackpots |

### Call Chain Architecture

```
advanceGame (AdvanceModule)
  |
  +-- Level Transition Path (jackpotCounter >= 5 after last daily jackpot):
  |     |-- _awardFinalDayDgnrsReward(lvl, rngWord)    -> JackpotModule.awardFinalDayDgnrsReward
  |     |-- _rewardTopAffiliate(lvl)                    -> EndgameModule.rewardTopAffiliate
  |     +-- _runRewardJackpots(lvl, rngWord)            -> EndgameModule.runRewardJackpots
  |           |-- BAF jackpot (levels %10 == 0)         -> jackpots.runBafJackpot (external call)
  |           |                                            -> _runBafJackpot (payout processing)
  |           |-- Decimator jackpot (levels %10 == 5, not %100 == 95)
  |           |                                         -> IDegenerusGame.runDecimatorJackpot (self-call)
  |           |                                            -> DecimatorModule.runDecimatorJackpot
  |           +-- Decimator jackpot (levels %100 == 0)  -> IDegenerusGame.runDecimatorJackpot
  |
  +-- Jackpot Day 1:
  |     +-- _runEarlyBirdLootboxJackpot(lvl+1, rngWord) -> JackpotModule (private)
  |
  +-- Pool Consolidation (before jackpot phase):
        +-- _consolidatePrizePools(lvl, rngWord)         -> JackpotModule.consolidatePrizePools

GAMEOVER Path (GameOverModule.handleGameOverDrain):
  |-- Terminal Decimator (10% of remaining)
  |     -> IDegenerusGame.runTerminalDecimatorJackpot -> DecimatorModule
  +-- Terminal Jackpot (90% + decimator refund)
        -> IDegenerusGame.runTerminalJackpot -> JackpotModule
```

### Degenerette operates independently (not in advanceGame)

```
User -> DegenerusGame.placeFullTicketBets -> delegatecall -> DegeneretteModule._placeFullTicketBets
User -> DegenerusGame.resolveBets -> delegatecall -> DegeneretteModule._resolveFullTicketBet
  (resolution uses lootbox RNG word; triggers _distributePayout, _awardDegeneretteDgnrs, _maybeAwardConsolation)
```

## Detailed Jackpot Mechanics (Audit Targets)

### 1. Early-Bird Lootbox Jackpot (OJCK-01)

**Trigger:** Jackpot Day 1 of each level, called at JM:381 inside `payDailyJackpot` when `isEarlyBirdDay` is true.

**Entry point:** `_runEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord)` at JM:801.

**Prize pool source:** 3% of `_getFuturePrizePool()` (JM:803). Deducted from future pool at JM:807.

**Winner selection:** 100 iterations (JM:829). For each:
- `EntropyLib.entropyStep(entropy)` advances RNG (JM:830)
- `traitId = uint8(entropy)` -- uniform trait, NOT burn-weighted (JM:831)
- `_randTraitTicket(traitBurnTicket[lvl], entropy, traitId, 1, uint8(i))` selects one winner (JM:832-838)
- If winner is non-zero, roll for level offset 0-4 (20% each) at JM:843
- Convert perWinnerEth to tickets at that level's price (JM:846)
- Queue tickets via `_queueTickets(winner, baseLevel + levelOffset, ticketCount)` at JM:848

**Budget recycling:** All budget goes to `_setNextPrizePool(_getNextPrizePool() + totalBudget)` at JM:863. This recycles the ETH value back into the pool system as backing for the newly-queued tickets.

**Key storage:**
- `traitBurnTicket[lvl]` -- read for winner selection
- `futurePrizePool` -- read and written (deducted)
- `nextPrizePool` -- written (added to)
- `ticketQueue` -- written (via `_queueTickets`)

**RNG dependency:** Uses `rngWord` from VRF via advanceGame. Called DURING jackpot phase (rngLockedFlag may be set).

**Audit points:**
- `traitId = uint8(entropy)` uses low 8 bits, values 0-255, but there are only 32 traits (0-31). Need to verify if `_randTraitTicket` handles traitId > 31.
- `perWinnerEth = totalBudget / 100` -- integer division dust (up to 99 wei) is never distributed but goes to nextPrizePool anyway.
- Ticket queuing during jackpot phase: rngLockedFlag is true but `_queueTickets` at near-future levels (level+0 to level+4) routes to `_tqWriteKey`, not `_tqFarFutureKey`, so the rngLocked guard does NOT trigger (only FF writes are blocked).

### 2. BAF (Buy and Flip) Jackpot (OJCK-02)

**Trigger:** `runRewardJackpots` at EM:168, called at levels where `lvl % 10 == 0`.

**Pool allocation (EM:180):**
- Non-century, non-level-50: 10% of futurePrizePool
- Level 50: 20% of futurePrizePool
- Level x00 (century): 20% of futurePrizePool

**Phase 1: Winner Selection (DegenerusJackpots.sol, DJ:229-529)**

External call from EndgameModule (EM:363): `jackpots.runBafJackpot(poolWei, lvl, rngWord)`.

Returns: `(address[] winners, uint256[] amounts, uint256 winnerMask, uint256 returnAmountWei)`.

**Prize distribution slices:**
| Slice | % | Recipient | Method |
|-------|---|-----------|--------|
| A | 10% | Top BAF bettor (slot 0) | `_bafTop(lvl, 0)` at DJ:253 |
| A2 | 5% | Top coinflip bettor (last 24h) | `coin.coinflipTopLastDay()` at DJ:266 |
| B | 5% | Random pick: 3rd or 4th BAF slot | `_bafTop(lvl, 2 + uint8(entropy & 1))` at DJ:283 |
| D | 5% | Far-future ticket holders (3% 1st, 2% 2nd by BAF score) | `degenerusGame.sampleFarFutureTickets(entropy)` at DJ:298 |
| D2 | 5% | Far-future ticket holders, 2nd draw (3% 1st, 2% 2nd) | DJ:340 |
| E-1st | 45% | Scatter 1st place (50 rounds, trait sampling) | DJ:382-480 |
| E-2nd | 25% | Scatter 2nd place (50 rounds) | DJ:483-498 |

**BAF state tracking:**
- `bafTotals[lvl][player]` -- accumulated coinflip stake per player per level
- `bafTop[lvl]` -- top-4 leaderboard (PlayerScore[4], sorted descending)
- `bafTopLen[lvl]` -- current leaderboard length
- `bafEpoch[lvl]` / `bafPlayerEpoch[lvl][player]` -- lazy reset mechanism
- Recording: `recordBafFlip(player, lvl, amount)` at DJ:174, called by coin/coinflip contracts

**Scatter mechanics (DJ:393-463):**
- 50 rounds with fixed `BAF_SCATTER_ROUNDS` (DJ:114)
- Level targeting varies: non-century uses lvl+1 to +4 (weighted), century uses lvl+1/+2/+3 (12 rounds) + random from past 99 levels (38 rounds)
- Samples via `degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy)` -- returns up to 4 tickets
- Top-2 by BAF score selected per round
- Last 40 scatter winners get `winnerMask` flags (`BAF_SCATTER_TICKET_WINNERS = 40`)

**Phase 2: Payout Processing (EndgameModule._runBafJackpot, EM:345-423)**

- `largeWinnerThreshold = poolWei / 20` (5% of pool) at EM:373
- Large winners (>= threshold): 50% ETH via `_addClaimableEth`, 50% lootbox (small: `_awardJackpotTickets`, large: `_queueWhalePassClaimCore`)
- Small winners: alternating -- even index gets 100% ETH, odd index gets 100% lootbox tickets
- Lootbox ETH stays in future pool: `lootboxToFuture = lootboxTotal` at EM:419

**Key interaction:** `sampleFarFutureTickets` (DG:2669-2705) reads from `_tqWriteKey` (DG:2681). This is the known DSC-02 issue from Phase 81 -- it samples the write buffer, which may not reflect the most current ticket state after a swap.

**Cleanup:** `_clearBafTop(lvl)` at DJ:526, epoch increment at DJ:527, `lastBafResolvedDay` updated at DJ:528.

### 3. Decimator Jackpot (OJCK-03)

**3a. Regular Decimator**

**Trigger:** `runRewardJackpots` at EM:168. Fires at:
- Levels x5 (not x95): 10% of *current* futurePrizePool (EM:222) -- note: this reads from futurePrizePool AFTER BAF deduction on x0 levels
- Levels x00: 30% of *original* baseFuturePool (EM:206) -- reads pre-BAF value

**Burn tracking: `recordDecBurn(player, lvl, bucket, baseAmount, multBps)` at DM:129**
- Called by BurnieCoin on every decimator burn
- First burn sets bucket (denom 2-12) and deterministic subbucket: `_decSubbucketFor(player, lvl, bucket)` at DM:145
- Better bucket (lower denom) causes migration: old subbucket removed, new one seeded with carried-over burn (DM:148-154)
- Effective amount: `_decEffectiveAmount` applies multiplier with 200-mint cap (`DECIMATOR_MULTIPLIER_CAP`) at DM:159
- Burn accumulated with uint192 saturation at DM:166-168
- Subbucket aggregate updated at DM:176

**Resolution: `runDecimatorJackpot(poolWei, lvl, rngWord)` at DM:205**
- Access: game contract only (self-call via `IDegenerusGame(address(this))`)
- Returns full pool if already snapshotted (DM:213-215) -- double-snapshot guard
- Selects winning subbucket per denom (2-12) via `_decWinningSubbucket(decSeed, denom)` at DM:224
- Packs winning subbuckets into `decBucketOffsetPacked[lvl]` (4 bits per denom) at DM:248
- Snapshots `decClaimRounds[lvl]` with poolWei, totalBurn, rngWord at DM:251-253
- Returns 0 if winners exist (funds held for claims); returns full pool if no qualifying burns

**Claims: `claimDecimatorJackpot(uint24 lvl)` at DM:316**
- Blocked when `prizePoolFrozen` (DM:321) -- prevents corruption during jackpot phase
- Validates via `_consumeDecClaim`: checks poolWei != 0, not already claimed, player's subbucket matches winning subbucket, pro-rata share > 0
- Pro-rata: `(poolWei * playerBurn) / totalBurn` at DM:542
- Normal mode: 50/50 ETH/lootbox via `_creditDecJackpotClaimCore` (DM:433-447)
  - ETH half: `_addClaimableEth` (includes auto-rebuy if enabled)
  - Lootbox half: `_awardDecimatorLootbox` (DM:627) -- delegates to LootboxModule for amounts <= 5 ETH, whale pass for larger
  - `claimablePool -= lootboxPortion` at DM:445 (lootbox portion no longer claimable ETH)
  - Caller adds lootboxPortion to futurePrizePool at DM:336
- GAMEOVER mode: 100% ETH via `_addClaimableEth` (DM:326)

**Storage layout:**
- `decBurn[lvl][player]` -- DecEntry struct (burn: uint192, bucket: uint8, subBucket: uint8, claimed: uint8)
- `decBucketBurnTotal[lvl][denom][sub]` -- uint256[13][13] aggregates
- `decClaimRounds[lvl]` -- DecClaimRound struct (poolWei, rngWord, totalBurn: uint232)
- `decBucketOffsetPacked[lvl]` -- uint64, 4 bits per denom

**3b. Terminal Decimator (Death Bet)**

**Trigger:** GAMEOVER via `handleGameOverDrain` (GOVM:68) -- 10% of remaining funds

**Burn tracking: `recordTerminalDecBurn(player, lvl, baseAmount)` at DM:707**
- Always open (except <= 1 day remaining on death clock, DM:715)
- Bucket/multiplier from activity score (`playerActivityScore`), not player-chosen
- Activity cap: `TERMINAL_DEC_ACTIVITY_CAP_BPS = 23500` (DM:697)
- Time multiplier: `_terminalDecMultiplierBps(daysRemaining)` at DM:903-909
  - > 10 days: `daysRemaining * 2500` BPS (e.g., 120 days = 30x, 11 days = 2.75x)
  - <= 10 days: linear from 2x (day 10) to 1x (day 2); day 1 blocked
  - Intentional discontinuity at day 10 (2.75x -> 2x regime change)
- Uses `TerminalDecEntry` struct: totalBurn (uint80), weightedBurn (uint88), bucket, subBucket, burnLevel (uint48)
- Lazy reset on level change (DM:726-731)
- Bucket aggregates keyed by `keccak256(abi.encode(lvl, bucket, subBucket))` in `terminalDecBucketBurnTotal`

**Resolution: `runTerminalDecimatorJackpot(poolWei, lvl, rngWord)` at DM:783**
- Same winning subbucket selection as regular decimator
- Double-resolution guard at DM:791
- Snapshots `lastTerminalDecClaimRound` (single slot: lvl uint24, poolWei uint96, totalBurn uint128)
- Note: `decBucketOffsetPacked[lvl]` is shared with regular decimator -- potential collision if same level has both

**Claims: `claimTerminalDecimatorJackpot()` at DM:833**
- Always 100% ETH (GAMEOVER, no lootbox/auto-rebuy)
- Claimed flag: `weightedBurn` zeroed at DM:892
- `prizePoolFrozen` guard at DM:834

### 4. Degenerette Jackpot (OJCK-04)

**Bet placement: `placeFullTicketBets` at DDM:388**

- Currency: ETH (0), BURNIE (1), WWXRP (3)
- Minimum bets: 0.005 ETH, 100 BURNIE, 1 WWXRP
- Max spins per bet: 10 (`MAX_SPINS_PER_BET`)
- Uses lootbox RNG index (`lootboxRngIndex` at DDM:473) -- ties bet to pending VRF word
- Packed bet storage: `degeneretteBets[player][nonce]` -- 256-bit packed struct

**ETH fund flow (DDM:547-565):**
- ETH collected goes to futurePrizePool (not nextPrizePool)
- If `prizePoolFrozen`: goes to pending pools instead
- `lootboxRngPendingEth += totalBet` for RNG tracking

**Resolution: `resolveBets` at DDM:411 / `_resolveFullTicketBet` at DDM:585**

- Requires RNG word available: `lootboxRngWordByIndex[index] != 0`
- Per-spin result derived deterministically from `keccak256(rngWord, index, [spinIdx,] QUICK_PLAY_SALT)` at DDM:617-618
- Match counting: 8 attributes (4 quadrants x color + symbol) at DDM:855-876
- Payout calculation: base multiplier table scaled by ROI BPS (activity-score-based, 90-99.9%)
  - 0-1 match: 0x; 2 match: 1.90x; 3: 4.75x; 4: 15x; 5: 42.5x; 6: 195x; 7: 1000x; 8: 100,000x
  - EV normalization per outcome for equal EV regardless of trait selection
  - Hero quadrant boost/penalty (EV-neutral)
  - ETH: +5% bonus ROI redistributed to 5+ match buckets
  - WWXRP: up to 109.9% high-value ROI target for 5+ match buckets

**ETH payout distribution: `_distributePayout` at DDM:680**
- Blocked during `prizePoolFrozen` (DDM:685) -- prevents futurePrizePool corruption
- 25% as claimable ETH (capped at 10% of futurePrizePool via `ETH_WIN_CAP_BPS = 1000`)
- 75% + any cap excess: converted to lootbox via delegatecall to `resolveLootboxDirect`
- futurePrizePool reduced by ETH portion (DDM:702-703)

**sDGNRS rewards: `_awardDegeneretteDgnrs` at DDM:1164**
- Only on ETH bets with 6+ matches
- BPS rates: 6 match = 4%, 7 match = 8%, 8 match = 15% (of Reward pool per ETH wagered)
- Bet capped at 1 ETH for reward calculation (DDM:1173)
- Transfer from `IStakedDegenerusStonk.Pool.Reward`

**Consolation: `_maybeAwardConsolation` at DDM:722**
- 1 WWXRP for total losing bets (totalPayout == 0)
- Minimum qualifiers: 0.01 ETH, 500 BURNIE, 20 WWXRP

**Notable: Degenerette's `_addClaimableEth` (DDM:1153-1159) is a DIFFERENT function from EndgameModule/JackpotModule versions -- it does NOT include auto-rebuy logic. Just credits `claimablePool` and `claimableWinnings`.**

**Per-level tracking:**
- `playerDegeneretteEthWagered[player][lvl]` -- ETH wagered per player per level (GS:1351)
- `topDegeneretteByLevel[lvl]` -- packed (amount << 160 | address), tracks top bettor (GS:1355)
- `dailyHeroWagers[day][quadrant]` -- packed uint256, 32-bit per symbol (GS:1343)

### 5. Final-Day DGNRS Distribution (OJCK-05)

**Trigger:** `_awardFinalDayDgnrsReward(lvl, rngWord)` called at AM:365, AFTER last daily jackpot completes (jackpotCounter >= JACKPOT_LEVEL_CAP = 5).

**Implementation: `awardFinalDayDgnrsReward(uint24 lvl, uint256 rngWord)` at JM:773**

**Pool source:** 1% (`FINAL_DAY_DGNRS_BPS = 100` at JM:173) of `dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Reward)` (JM:774-775)

**Winner selection:**
1. Derive entropy: `rngWord ^ (uint256(lvl) << 192)` at JM:779
2. Determine solo bucket index: `JackpotBucketLib.soloBucketIndex(entropy)` at JM:780
3. Unpack Day 5 winning traits from `lastDailyJackpotWinningTraits` at JM:781-782
4. Select winner via `_randTraitTicket(traitBurnTicket[lvl], entropy, traitIds[soloIdx], 1, 254)` at JM:784-790
5. If winner found: `dgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, winners[0], reward)` at JM:792-796

**Key dependency:** `lastDailyJackpotWinningTraits` must have been set by Day 5's `payDailyJackpot` (stored at JM:2632). This is set during the final daily jackpot that runs just before this function is called.

**Storage:**
- `lastDailyJackpotWinningTraits` -- uint32 packed 4 trait IDs (GS:843)

## Common Pitfalls

### Pitfall 1: Shared decBucketOffsetPacked Between Regular and Terminal Decimator
**What goes wrong:** Both `runDecimatorJackpot` (DM:248) and `runTerminalDecimatorJackpot` (DM:817) write to `decBucketOffsetPacked[lvl]`. If the terminal decimator resolves at the same level as the last regular decimator, the packed offsets are overwritten.
**Why it happens:** Terminal decimator only fires at GAMEOVER; the last regular decimator fires at level %10 == 5 (or %100 == 0). If GAMEOVER occurs at a level that just had a regular decimator, both resolve at the same level.
**How to avoid:** Verify that terminal decimator uses `lastTerminalDecClaimRound` (which stores its own lvl) rather than relying on `decBucketOffsetPacked` for claims. Check if regular decimator claims still work after terminal overwrites the packed offsets.
**Warning signs:** Claims reverting with DecNotWinner after GAMEOVER on levels that had regular decimator snapshots.

### Pitfall 2: sampleFarFutureTickets Using _tqWriteKey
**What goes wrong:** BAF far-future ticket sampling reads from the write buffer (DG:2681), not the far-future key or read buffer. After a swap, these may be stale or empty.
**Why it happens:** Known issue from Phase 81 (DSC-02). View function, not a direct vulnerability, but affects BAF winner selection fairness.
**How to avoid:** Document the impact on BAF distribution: during jackpot phase (post-swap), the write key contains newly-written tickets for next level, not processed tickets. This means far-future sampling may miss valid ticket holders.
**Warning signs:** BAF far-future slices returning 0 winners and refunding pool.

### Pitfall 3: Degenerette ETH Payouts Draining futurePrizePool During Jackpot Phase
**What goes wrong:** `_distributePayout` at DDM:680 reads and writes `futurePrizePool`. During jackpot phase, pool snapshots are being used for daily jackpot calculations.
**Why it happens:** Guard exists at DDM:685: `if (prizePoolFrozen) revert E()`. This blocks resolution during frozen state. Must verify all paths.
**How to avoid:** Confirm that `prizePoolFrozen` is set before any jackpot calculations touch futurePrizePool, and unset only after all level-transition jackpots complete.
**Warning signs:** futurePrizePool mismatch between snapshot and actual value.

### Pitfall 4: Early-Bird Trait Selection Modular Bias
**What goes wrong:** `traitId = uint8(entropy)` at JM:831 gives values 0-255, but traits are 0-31. If `_randTraitTicket` uses traitId directly as array index, values >= 32 would access empty arrays (since `traitBurnTicket[lvl]` is indexed by trait 0-31 from processing).
**Why it happens:** The entropy step provides 256 bits; only low 8 bits are taken, but trait space is 5 bits.
**How to avoid:** Verify `_randTraitTicket` handles traitId >= 32 gracefully (likely returns empty array / no winner) -- this is not a vulnerability but affects winner distribution (higher traits unlikely to match).

### Pitfall 5: Terminal Decimator poolWei Truncation
**What goes wrong:** `lastTerminalDecClaimRound.poolWei` is uint96 (DM:821), but the pool could exceed uint96.max (79.2 billion ETH). In practice impossible with real ETH supply, but worth documenting.
**Why it happens:** Storage packing optimization.

## Code Examples (Key Patterns)

### BAF Prize Split Pattern (EndgameModule)
```solidity
// EM:373: Large/small winner threshold
uint256 largeWinnerThreshold = poolWei / 20; // 5% of pool

// Large winners: 50/50 ETH/lootbox
if (amount >= largeWinnerThreshold) {
    uint256 ethPortion = amount / 2;
    uint256 lootboxPortion = amount - ethPortion;
    claimableDelta += _addClaimableEth(winner, ethPortion, rngWord);
    // Lootbox: small -> immediate tickets, large -> whale pass
    if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD) {
        rngWord = _awardJackpotTickets(winner, lootboxPortion, lvl, rngWord);
    } else {
        _queueWhalePassClaimCore(winner, lootboxPortion);
    }
}
// Small winners: alternating ETH/lootbox
else if (i % 2 == 0) {
    claimableDelta += _addClaimableEth(winner, amount, rngWord);
} else {
    rngWord = _awardJackpotTickets(winner, amount, lvl, rngWord);
}
```

### Decimator Pro-Rata Claim Pattern
```solidity
// DM:542: Pro-rata share calculation
amountWei = (poolWei * uint256(entryBurn)) / totalBurn;
```

### Degenerette ETH Payout Cap Pattern
```solidity
// DDM:690-703: 25/75 split with 10% pool cap
uint256 ethPortion = payout / 4;
uint256 lootboxPortion = payout - ethPortion;
uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000; // 10% of pool
if (ethPortion > maxEth) {
    lootboxPortion += ethPortion - maxEth;
    ethPortion = maxEth;
}
pool -= ethPortion;
_setFuturePrizePool(pool);
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Trait-based winner selection | Custom array iteration | Verify `_randTraitTicket` in JackpotModule | Already handles array indexing, empty arrays, salt separation |
| BAF leaderboard sorting | Manual sort | Verify `_updateBafTop` in DegenerusJackpots | Bubble-sort on insertion, handles all edge cases (update existing, insert new, replace bottom) |
| Decimator bucket packing | Custom bit ops | Verify `_packDecWinningSubbucket` / `_unpackDecWinningSubbucket` | 4-bit per denom packing, well-defined shift layout |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Combined pool for coin jackpot (read + FF) | FF-only read | Commit 2bf830a2 (post-v3.9 Phase 77) | `_awardFarFutureCoinJackpot` reads only FF key; v3.9 proof documentation is stale |
| Single decimator (regular only) | Regular + terminal decimator | Unknown (pre-v4.0) | Terminal decimator adds GAMEOVER-specific death bet with time multiplier |

## Open Questions

1. **decBucketOffsetPacked collision between regular and terminal decimator**
   - What we know: Both write to `decBucketOffsetPacked[lvl]`. Terminal decimator stores its own claim round separately.
   - What's unclear: Whether regular decimator claims at the same level break after terminal decimator overwrites packed offsets.
   - Recommendation: Trace both claim paths at the same level to verify independence.

2. **_randTraitTicket behavior with traitId >= 32**
   - What we know: Early-bird lootbox passes `uint8(entropy)` (0-255) as traitId.
   - What's unclear: Whether traits > 31 have any entries in `traitBurnTicket` arrays. If not, those winners are silently skipped (no revert, no payout).
   - Recommendation: Verify `traitBurnTicket` population logic in ticket processing (Phase 82 territory, but affects early-bird winner distribution fairness).

3. **BAF scatter winnerMask usage in EndgameModule**
   - What we know: `runBafJackpot` returns a `winnerMask` with flags for the last 40 scatter winners.
   - What's unclear: EndgameModule at EM:363 receives `winnerMask` as third return value but assigns it to an unnamed variable (`, ,`). Need to verify if it's used anywhere.
   - Recommendation: Trace whether winnerMask is consumed or dead code.

4. **Degenerette topDegeneretteByLevel consumption**
   - What we know: Written at DDM:518-523 during bet placement. Read at DG:2817 (view function).
   - What's unclear: Whether any jackpot or reward mechanism reads this for distribution. It may be frontend-only state.
   - Recommendation: Verify all readers -- if view-only, document as INFO.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- Early-bird lootbox (JM:801-864), final-day DGNRS (JM:773-798)
- `contracts/DegenerusJackpots.sol` -- BAF leaderboard and winner selection (DJ:229-529)
- `contracts/modules/DegenerusGameEndgameModule.sol` -- BAF payout processing (EM:345-423), reward jackpot trigger (EM:168-243)
- `contracts/modules/DegenerusGameDecimatorModule.sol` -- All decimator mechanics (DM:1-929)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` -- All degenerette mechanics (DDM:1-1179)
- `contracts/modules/DegenerusGameGameOverModule.sol` -- Terminal jackpot dispatch (GOVM:68-163)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- Jackpot trigger orchestration (AM:290-380)
- `contracts/storage/DegenerusGameStorage.sol` -- All storage definitions and _awardEarlybirdDgnrs (GS:923-983)
- `contracts/DegenerusGame.sol` -- Self-call wrappers, sampleFarFutureTickets (DG:2669-2705)

### Secondary (MEDIUM confidence)
- `audit/v4.0-ticket-creation-queue-mechanics.md` -- Phase 81 DSC-02 re: sampleFarFutureTickets

## Metadata

**Confidence breakdown:**
- Early-bird lootbox: HIGH -- single function, fully traced
- BAF jackpot: HIGH -- both contracts fully read, all slices traced
- Decimator jackpot: HIGH -- burn/resolution/claim paths fully traced
- Degenerette: HIGH -- bet/resolution/payout paths fully traced
- Final-day DGNRS: HIGH -- single function, fully traced
- Cross-system interactions: MEDIUM -- decBucketOffsetPacked collision and _randTraitTicket behavior need code-level verification during audit

**Research date:** 2026-03-23
**Valid until:** 2026-04-23 (stable codebase, no active development on these subsystems)
