# Unit 4: Endgame + Game Over -- Coverage Checklist

**Agent:** Taskmaster (Coverage Enforcer)
**Contracts:**
- `contracts/modules/DegenerusGameEndgameModule.sol` (565 lines)
- `contracts/modules/DegenerusGameGameOverModule.sol` (235 lines)
- `contracts/modules/DegenerusGamePayoutUtils.sol` (92 lines, inherited by EndgameModule)

**Date:** 2026-03-25

---

## Methodology
- Per D-01: Categories B/C/D only (no Category A -- these are modules, not router)
- Per D-04/D-05: BAF rebuyDelta reconciliation is highest priority
- Per D-06: Fresh analysis, no trusting prior findings
- Per D-08/D-09: Cross-module calls traced for state coherence
- Per D-10: ULTIMATE-AUDIT-DESIGN.md format

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 5 | Full Mad Genius (per D-02) |
| C: Internal Helpers | 7 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure (inherited) | 9 | Minimal; RNG derivation gets extra scrutiny |
| **TOTAL** | **21** | |

---

## Category B: External State-Changing Functions

| # | Function | Lines | Contract | Access Control | Storage Writes | External Calls | Risk Tier | Subsystem | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|---------------|---------------|---------------|-----------|-----------|-----------|------------|--------------|-------------|
| B1 | `runRewardJackpots(uint24 lvl, uint256 rngWord)` | 172-254 | EndgameModule | external (via delegatecall from advanceGame) | prizePoolsPacked (future), claimablePool | IDegenerusGame.runDecimatorJackpot, jackpots.runBafJackpot (via C2) | Tier 1 [BAF-CRITICAL] | REWARD-JACKPOT | YES | YES | YES | YES |
| B2 | `rewardTopAffiliate(uint24 lvl)` | 130-149 | EndgameModule | external (via delegatecall from advanceGame) | levelDgnrsAllocation[lvl] | affiliate.affiliateTop, dgnrs.poolBalance, dgnrs.transferFromPool | Tier 3 | AFFILIATE | YES | YES | YES | YES |
| B3 | `claimWhalePass(address player)` | 540-559 | EndgameModule | external (via delegatecall from DegenerusGame) | whalePassClaims[player], ticketsOwedPacked, ticketQueue, mintPacked_ | none | Tier 2 | WHALE-PASS | YES | YES | YES | YES |
| B4 | `handleGameOverDrain(uint48 day)` | 68-163 | GameOverModule | external (via delegatecall from advanceGame) | gameOver, gameOverTime, gameOverFinalJackpotPaid, claimableWinnings, claimablePool, prizePoolsPacked, currentPrizePool, yieldAccumulator | IDegenerusGame.runTerminalDecimatorJackpot, IDegenerusGame.runTerminalJackpot, dgnrs.burnRemainingPools, steth.balanceOf, steth.transfer, steth.approve, dgnrs.depositSteth | Tier 1 | GAME-OVER | YES | YES | YES | YES |
| B5 | `handleFinalSweep()` | 170-188 | GameOverModule | external (via delegatecall from advanceGame) | finalSwept, claimablePool | admin.shutdownVrf, steth.balanceOf, steth.transfer, steth.approve, dgnrs.depositSteth | Tier 2 | GAME-OVER | YES | YES | YES | YES |

---

## Category C: Internal/Private State-Changing Helpers

| # | Function | Lines | Contract | Called By | Storage Writes | Flags | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|-----------|---------------|-------|-----------|------------|--------------|-------------|
| C1 | `_addClaimableEth(address, uint256, uint256)` | 267-316 | EndgameModule | C2 (via B1) | prizePoolsPacked (future/next), claimableWinnings, claimablePool, ticketsOwedPacked, ticketQueue | [BAF-CRITICAL] | YES | YES | YES | YES |
| C2 | `_runBafJackpot(uint256, uint24, uint256)` | 356-433 | EndgameModule | B1 | via C1, C3, C5, C6 | [BAF-PATH] | YES | YES | YES | YES |
| C3 | `_awardJackpotTickets(address, uint256, uint24, uint256)` | 448-486 | EndgameModule | C2 | ticketsOwedPacked, ticketQueue, whalePassClaims, claimableWinnings, claimablePool (via C6) | | YES | YES | YES | YES |
| C4 | `_jackpotTicketRoll(address, uint256, uint24, uint256)` | 498-531 | EndgameModule | C3 | ticketsOwedPacked, ticketQueue (via _queueLootboxTickets) | | YES | YES | YES | YES |
| C5 | `_creditClaimable(address, uint256)` | 30-36 | PayoutUtils | C1 (no-rebuy path, take-profit), C6 (whale pass remainder) | claimableWinnings | [MULTI-PARENT] | YES | YES | YES | YES |
| C6 | `_queueWhalePassClaimCore(address, uint256)` | 75-91 | PayoutUtils | C2 (large winner lootbox), C3 (large ticket award) | whalePassClaims, claimableWinnings, claimablePool | [MULTI-PARENT] | YES | YES | YES | YES |
| C7 | `_sendToVault(uint256, uint256)` | 197-234 | GameOverModule | B4 (game-over remainder), B5 (final sweep) | (no storage writes; ETH/stETH external transfers) | [MULTI-PARENT] | YES | YES | YES | YES |

---

## Category D: View/Pure Functions (Inherited)

| # | Function | Lines | Contract | Reads/Computes | Security Note | Subsystem | Reviewed? |
|---|----------|-------|----------|---------------|--------------|-----------|-----------|
| D1 | `_calcAutoRebuy(...)` | 38-72 | PayoutUtils | Pure: target level, ticket count, take profit calc | RNG entropy derivation (EntropyLib.entropyStep) for level offset | AUTO-REBUY | YES |
| D2 | `_getFuturePrizePool()` | 746-749 | Storage | Reads prizePoolsPacked high 128 bits | Used in BAF reconciliation | POOL-READ | YES |
| D3 | `_setFuturePrizePool(uint256)` | 752-755 | Storage | Writes prizePoolsPacked (preserves next) | Used in BAF reconciliation write-back | POOL-WRITE | YES |
| D4 | `_getNextPrizePool()` | 734-737 | Storage | Reads prizePoolsPacked low 128 bits | Used in auto-rebuy | POOL-READ | YES |
| D5 | `_setNextPrizePool(uint256)` | 740-743 | Storage | Writes prizePoolsPacked (preserves future) | Used in auto-rebuy and game-over zeroing | POOL-WRITE | YES |
| D6 | `_queueTickets(address, uint24, uint32)` | 528-549 | Storage | Writes ticketsOwedPacked, ticketQueue | RNG-locked guard for far-future tickets | TICKET-QUEUE | YES |
| D7 | `_queueLootboxTickets(address, uint24, uint256)` | 638-645 | Storage | Delegates to _queueTicketsScaled | Wrapper; truncates to uint32 | TICKET-QUEUE | YES |
| D8 | `_queueTicketRange(address, uint24, uint24, uint32)` | 602-632 | Storage | Writes ticketsOwedPacked, ticketQueue per level (loop) | Used by claimWhalePass for 100 levels | TICKET-QUEUE | YES |
| D9 | `_applyWhalePassStats(address, uint24)` | 1067-~1100 | Storage | Writes mintPacked_ (packed bit fields) | Whale pass freeze/stat tracking | WHALE-PASS | YES |

---

## BAF-Critical Call Chains

Every path from a Category B entry point to `_addClaimableEth` (C1) in EndgameModule:

### Chain 1: B1 -> C2 -> C1 (runRewardJackpots -> _runBafJackpot -> _addClaimableEth)
```
B1 runRewardJackpots (line 172)
  caches: futurePoolLocal = _getFuturePrizePool() [line 173]
  caches: baseFuturePool = futurePoolLocal [line 176]
  calls: C2 _runBafJackpot(bafPoolWei, lvl, rngWord) [line 195]
    loops through winners:
      calls: C1 _addClaimableEth(winner, ethPortion, rngWord) [line 396, 416]
        if auto-rebuy: _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent) [line 292]
        ^^^ THIS IS THE BAF WRITE: writes directly to futurePrizePool storage
  write-back:
    rebuyDelta = _getFuturePrizePool() - baseFuturePool [line 245]
    _setFuturePrizePool(futurePoolLocal + rebuyDelta) [line 246]
    ^^^ RECONCILIATION: adds rebuy writes back to local computation
```

**Mad Genius must verify:** Does `rebuyDelta` capture exactly the auto-rebuy writes? Is there any other code path that modifies futurePrizePool storage between L173 and L245?

### Chain 2: B1 -> IDegenerusGame.runDecimatorJackpot (cross-module)
```
B1 runRewardJackpots (line 172)
  caches: futurePoolLocal, baseFuturePool
  calls: IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord) [line 215, 231]
    routes through: DegenerusGame router -> delegatecall DecimatorModule
    DecimatorModule may also call _addClaimableEth which has auto-rebuy path
    Auto-rebuy in DecimatorModule would write to futurePrizePool storage
    ^^^ This is ALSO captured by rebuyDelta reconciliation
```

**Mad Genius must verify:** Does DecimatorModule's auto-rebuy path also write to the same futurePrizePool storage slot? If yes, rebuyDelta captures it.

---

## Cross-Module External Calls

| Call | From Functions | Target Contract | State Impact |
|------|---------------|----------------|-------------|
| `jackpots.runBafJackpot(poolWei, lvl, rngWord)` | C2 | DegenerusJackpots | External call; returns (winners, amounts, refund) |
| `affiliate.affiliateTop(lvl)` | B2 | DegenerusAffiliate | View only |
| `dgnrs.poolBalance(Pool.Affiliate)` | B2 | StakedDegenerusStonk | View only |
| `dgnrs.transferFromPool(Pool.Affiliate, top, amount)` | B2 | StakedDegenerusStonk | External token transfer |
| `IDegenerusGame(address(this)).runDecimatorJackpot(...)` | B1 | via Game router -> DecimatorModule | Delegatecall; writes claimableWinnings, claimablePool, possibly futurePrizePool via auto-rebuy |
| `IDegenerusGame(address(this)).runTerminalDecimatorJackpot(...)` | B4 | via Game router -> DecimatorModule | Delegatecall; writes claimableWinnings, claimablePool |
| `IDegenerusGame(address(this)).runTerminalJackpot(...)` | B4 | via Game router -> JackpotModule | Delegatecall; writes claimableWinnings, claimablePool |
| `dgnrs.burnRemainingPools()` | B4 | StakedDegenerusStonk | External burn |
| `admin.shutdownVrf()` | B5 | DegenerusAdmin | External VRF shutdown (fire-and-forget) |
| `steth.balanceOf(address(this))` | B4, B5 | Lido stETH | View only |
| `steth.transfer(VAULT, amount)` | C7 | Lido stETH | External transfer |
| `steth.approve(SDGNRS, amount)` | C7 | Lido stETH | External approval |
| `dgnrs.depositSteth(amount)` | C7 | StakedDegenerusStonk | External deposit |

Per D-08: Cross-module delegatecalls traced for state coherence only. Full module internals audited in their own unit phases.

---

## RNG/Entropy Usage Map

| Function | Entropy Source | Usage | Derivation |
|----------|---------------|-------|-----------|
| B1 `runRewardJackpots` | `rngWord` parameter (VRF) | Passed to C2 `_runBafJackpot` and cross-module DecimatorJackpot | Direct VRF word |
| C2 `_runBafJackpot` | `rngWord` parameter | Passed to external `jackpots.runBafJackpot()` for winner selection; passed to C1 `_addClaimableEth` for auto-rebuy level offset; passed to C3 `_awardJackpotTickets` for ticket level rolls | VRF propagation |
| C1 `_addClaimableEth` | `entropy` parameter | Passed to `_calcAutoRebuy()` for target level offset | EntropyLib.entropyStep derivation |
| C4 `_jackpotTicketRoll` | `entropy` parameter | EntropyLib.entropyStep for level selection roll (30%/65%/5% distribution) | Stepped entropy |
| D1 `_calcAutoRebuy` | `entropy` parameter | `EntropyLib.entropyStep(entropy ^ uint256(uint160(beneficiary)) ^ weiAmount) & 3` for 1-4 level offset | Player-specific entropy mixing |
