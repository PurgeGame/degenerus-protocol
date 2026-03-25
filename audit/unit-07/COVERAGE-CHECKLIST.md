# Unit 7: Decimator System -- Coverage Checklist

## Contracts Under Audit
- `contracts/modules/DegenerusGameDecimatorModule.sol` (930 lines)
- `contracts/modules/DegenerusGamePayoutUtils.sol` (92 lines, inherited helpers only)

## Methodology
- Per D-01: Categories B/C/D only (no Category A -- this is a module, not the router)
- Per D-02: Category B functions get full Mad Genius treatment
- Per D-03: Category C functions traced via parent call trees; standalone for [MULTI-PARENT]
- Per D-04/D-05: Auto-rebuy BAF chain is priority #1 investigation
- Per D-06: Fresh analysis -- no prior audit findings trusted
- Per D-12: Report format per ULTIMATE-AUDIT-DESIGN.md

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 7 | Full Mad Genius (per D-02) |
| C: Internal Helpers | 13 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 12 | Minimal; RNG derivation and arithmetic edge cases get extra scrutiny |
| **TOTAL** | **32** | |

---

## Category B: External State-Changing Functions

| # | Function | Lines | Access Control | Storage Writes | External Calls | Risk Tier | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|---------------|---------------|-----------|-----------|-----------|-------------|-------------|
| B1 | `recordDecBurn(address,uint24,uint8,uint256,uint256)` | 129-188 | `OnlyCoin` (msg.sender == ContractAddresses.COIN) | decBurn[lvl][player], decBucketBurnTotal[lvl][denom][sub] | None | Tier 2 | pending | pending | pending | pending |
| B2 | `runDecimatorJackpot(uint256,uint24,uint256)` | 205-256 | `OnlyGame` (msg.sender == ContractAddresses.GAME) | decBucketOffsetPacked[lvl], decClaimRounds[lvl] | None | Tier 2 | pending | pending | pending | pending |
| B3 | `consumeDecClaim(address,uint24)` | 301-307 | `OnlyGame` (msg.sender == ContractAddresses.GAME) | decBurn[lvl][player].claimed | None | Tier 3 | pending | pending | pending | pending |
| B4 | `claimDecimatorJackpot(uint24)` | 316-338 | any (prizePoolFrozen guard L321) | claimableWinnings[], claimablePool, prizePoolsPacked (future/next), ticketQueue, ticketsOwedPacked, whalePassClaims[], decBurn[].claimed | delegatecall LootboxModule.resolveLootboxDirect | **Tier 1** [BAF-CRITICAL] | pending | pending | pending | pending |
| B5 | `recordTerminalDecBurn(address,uint24,uint256)` | 707-770 | `OnlyCoin` (msg.sender == ContractAddresses.COIN) | terminalDecEntries[player], terminalDecBucketBurnTotal[key] | self-call: IDegenerusGame(address(this)).playerActivityScore | Tier 2 | pending | pending | pending | pending |
| B6 | `runTerminalDecimatorJackpot(uint256,uint24,uint256)` | 783-825 | `OnlyGame` (msg.sender == ContractAddresses.GAME) | decBucketOffsetPacked[lvl], lastTerminalDecClaimRound | None | Tier 2 | pending | pending | pending | pending |
| B7 | `claimTerminalDecimatorJackpot()` | 833-840 | any (prizePoolFrozen guard L834) | terminalDecEntries[].weightedBurn, claimableWinnings[] | None | Tier 2 | pending | pending | pending | pending |

---

## Category C: Internal/Private State-Changing Helpers

| # | Function | Lines | Contract | Called By | Key Storage Writes | Flags | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|-----------|-------------------|-------|-----------|-----------|-------------|-------------|
| C1 | `_consumeDecClaim(address,uint24)` | 270-293 | Decimator | B3, B4 | decBurn[lvl][player].claimed = 1 | [MULTI-PARENT] | pending | pending | pending | pending |
| C2 | `_processAutoRebuy(address,uint256,uint256)` | 362-408 | Decimator | C3 | prizePoolsPacked (via _setFuturePrizePool/_setNextPrizePool), ticketQueue (via _queueTickets), claimableWinnings (via _creditClaimable), claimablePool | [BAF-CRITICAL] | pending | pending | pending | pending |
| C3 | `_addClaimableEth(address,uint256,uint256)` | 414-424 | Decimator | C4, B4 (gameOver), B7 | Delegates to C2 or C9 | [BAF-CRITICAL] [MULTI-PARENT] | pending | pending | pending | pending |
| C4 | `_creditDecJackpotClaimCore(address,uint256,uint256)` | 433-447 | Decimator | B4 | claimablePool -= lootboxPortion (L445) | | pending | pending | pending | pending |
| C5 | `_decUpdateSubbucket(uint24,uint8,uint8,uint192)` | 577-585 | Decimator | B1 (accumulate + migrate) | decBucketBurnTotal[lvl][denom][sub] += delta | [MULTI-PARENT] | pending | pending | pending | pending |
| C6 | `_decRemoveSubbucket(uint24,uint8,uint8,uint192)` | 592-602 | Decimator | B1 (migrate only) | decBucketBurnTotal[lvl][denom][sub] -= delta | | pending | pending | pending | pending |
| C7 | `_awardDecimatorLootbox(address,uint256,uint256)` | 627-651 | Decimator | C4 | whalePassClaims (via C11), or delegatecall LootboxModule | | pending | pending | pending | pending |
| C8 | `_consumeTerminalDecClaim(address)` | 869-893 | Decimator | B7 | terminalDecEntries[player].weightedBurn = 0 | | pending | pending | pending | pending |
| C9 | `_creditClaimable(address,uint256)` | PayoutUtils 30-36 | PayoutUtils | C2 (fallback, reserved), C3 (fallback) | claimableWinnings[beneficiary] | [MULTI-PARENT] (inherited) | pending | pending | pending | pending |
| C10 | `_calcAutoRebuy(...)` | PayoutUtils 38-72 | PayoutUtils | C2 | None (pure computation) | Inherited, pure | pending | pending | pending | pending |
| C11 | `_queueWhalePassClaimCore(address,uint256)` | PayoutUtils 75-91 | PayoutUtils | C7 | whalePassClaims[], claimableWinnings[], claimablePool | [MULTI-PARENT] (inherited) | pending | pending | pending | pending |
| C12 | `_queueTickets(address,uint24,uint32)` | Storage 528 | Storage | C2 | ticketQueue[lvl], ticketsOwedPacked[][] | Inherited from Storage | pending | pending | pending | pending |
| C13 | `_revertDelegate(bytes)` | 80-85 | Decimator | C7 | None (pure revert propagation) | | pending | pending | pending | pending |

---

## Category D: View/Pure Functions

| # | Function | Lines | Reads/Computes | Security Note | Reviewed? |
|---|----------|-------|---------------|---------------|-----------|
| D1 | `decClaimable(address,uint24)` | 346-355 | decClaimRounds, decBurn, decBucketOffsetPacked | View wrapper; no state writes | pending |
| D2 | `terminalDecClaimable(address)` | 846-866 | lastTerminalDecClaimRound, terminalDecEntries, decBucketOffsetPacked | View; pro-rata calculation correctness | pending |
| D3 | `_decEffectiveAmount(uint256,uint256,uint256)` | 454-473 | Pure arithmetic: multiplier cap logic | Boundary: prevBurn at cap, partial cap, zero baseAmount | pending |
| D4 | `_decWinningSubbucket(uint256,uint8)` | 479-485 | Pure: keccak256(entropy, denom) % denom | Modulo bias: denom 2-12, 256-bit hash, negligible bias | pending |
| D5 | `_packDecWinningSubbucket(uint64,uint8,uint8)` | 493-501 | Pure: bit packing (4 bits per denom) | 11 denoms x 4 bits = 44 bits fits uint64 | pending |
| D6 | `_unpackDecWinningSubbucket(uint64,uint8)` | 507-514 | Pure: bit unpacking | Guard: denom < 2 returns 0 | pending |
| D7 | `_decClaimableFromEntry(uint256,uint256,DecEntry,uint64)` | 522-543 | View: pro-rata (pool x burn / totalBurn) | Division by zero guarded (totalBurn == 0 returns 0) | pending |
| D8 | `_decClaimable(DecClaimRound,address,uint24)` | 551-570 | View: wraps D7 with claimed check | Already-claimed returns (0, false) | pending |
| D9 | `_decSubbucketFor(address,uint24,uint8)` | 610-621 | Pure: keccak256(player, lvl, bucket) % bucket | bucket=0 returns 0 (guard); deterministic assignment | pending |
| D10 | `_terminalDecMultiplierBps(uint256)` | 903-909 | Pure: time multiplier calculation | Intentional discontinuity at day 10 (2.75x -> 2x); day 2 gives 10000 BPS (1x) | pending |
| D11 | `_terminalDecBucket(uint256)` | 912-919 | Pure: activity-score to bucket mapping | Boundary clamped to [2, 12]; rounding via half-up | pending |
| D12 | `_terminalDecDaysRemaining()` | 922-929 | View: block.timestamp vs levelStartTime + timeout | level == 0 uses 365 days; division truncation on day boundary | pending |

---

## BAF-Critical Call Chains

Every path from a Category B entry point to `_addClaimableEth` (C3):

### Chain 1: claimDecimatorJackpot (normal path)
```
B4 -> C1 (_consumeDecClaim) -> mark claimed
B4 -> C4 (_creditDecJackpotClaimCore)
  -> C3 (_addClaimableEth) with ethPortion
    -> C2 (_processAutoRebuy)
      -> C10 (_calcAutoRebuy) [pure]
      -> _setFuturePrizePool *** WRITES futurePrizePool ***
      -> _setNextPrizePool   *** WRITES nextPrizePool ***
      -> C12 (_queueTickets)  *** WRITES ticketQueue ***
      -> C9 (_creditClaimable) *** WRITES claimableWinnings ***
      -> claimablePool -= ethSpent *** WRITES claimablePool ***
    -> C9 (_creditClaimable) [fallback if auto-rebuy disabled]
  -> claimablePool -= lootboxPortion *** WRITES claimablePool ***
  -> C7 (_awardDecimatorLootbox)
    -> C11 (_queueWhalePassClaimCore) [if > threshold]
    -> delegatecall LootboxModule [if <= threshold]
B4 -> _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion) *** READS then WRITES futurePrizePool ***
```

**BAF CHECK:** At L336, _getFuturePrizePool() is called AFTER C4 returns. If C2 wrote to futurePrizePool during the call, the L336 read picks up the updated value (fresh storage read, not cached local). **Mad Genius must verify no local variable caches futurePrizePool before the C4 call.**

### Chain 2: claimDecimatorJackpot (gameOver path)
```
B4 -> C1 (_consumeDecClaim) -> mark claimed
B4 -> C3 (_addClaimableEth) with full amountWei
  -> C2 (_processAutoRebuy) returns false (gameOver check at L367)
  -> C9 (_creditClaimable) *** WRITES claimableWinnings ***
B4 -> return (no lootboxPortion)
```

**BAF CHECK:** Auto-rebuy disabled by gameOver guard. No futurePrizePool/nextPrizePool writes. SAFE.

### Chain 3: claimTerminalDecimatorJackpot
```
B7 -> C8 (_consumeTerminalDecClaim) -> mark claimed (weightedBurn = 0)
B7 -> C3 (_addClaimableEth) with amountWei, entropy=0
  -> C2 (_processAutoRebuy) returns false (gameOver check at L367)
  -> C9 (_creditClaimable) *** WRITES claimableWinnings ***
```

**BAF CHECK:** Terminal claims only happen post-GAMEOVER. Auto-rebuy disabled. SAFE.

---

## Cross-Module External Calls

| Call | From Functions | Target | State Impact |
|------|---------------|--------|-------------|
| `delegatecall LootboxModule.resolveLootboxDirect` | C7 (_awardDecimatorLootbox) | GAME_LOOTBOX_MODULE | Lootbox resolution (runs in Game's storage context) |
| `IDegenerusGame(address(this)).playerActivityScore` | B5 (recordTerminalDecBurn) | Self (Game via router) | View call -- reads playerMintPacked_ and other state for activity computation |

---

## Shared Storage: decBucketOffsetPacked Collision Risk

**CRITICAL:** Both B2 (runDecimatorJackpot) and B6 (runTerminalDecimatorJackpot) write to `decBucketOffsetPacked[lvl]`.

- B2 writes at L248 during normal level jackpot resolution
- B6 writes at L817 during GAMEOVER terminal resolution

If B6 runs at the same `lvl` where B2 already stored winning subbuckets, B6 **overwrites** the packed offsets. Subsequent regular decimator claims for that level (via B4/claimDecimatorJackpot) would use the WRONG winning subbuckets (the terminal decimator's selections instead of the regular decimator's).

**Mad Genius must determine:**
1. Can B2 and B6 execute at the same level?
2. If yes, does the overwrite corrupt regular decimator claims?
3. Are there timing guards that prevent this?

---

## RNG/Entropy Usage Map

| Function | Entropy Source | Usage | Concern |
|----------|---------------|-------|---------|
| B2: runDecimatorJackpot | rngWord (VRF) | keccak256(rngWord, denom) % denom -> winning subbucket | Modulo bias negligible (denom 2-12 vs 256-bit space) |
| B4: claimDecimatorJackpot | decClaimRounds[lvl].rngWord | Passed to _addClaimableEth for auto-rebuy level selection | RNG word stored at resolution time; player cannot influence after resolution |
| B5: recordTerminalDecBurn | None (activity score + time) | Bucket from activity, time multiplier from death clock | No VRF needed -- deterministic from on-chain state |
| B6: runTerminalDecimatorJackpot | rngWord (VRF) | keccak256(rngWord, denom) % denom -> winning subbucket | Same as B2 |
| B7: claimTerminalDecimatorJackpot | entropy=0 passed to _addClaimableEth | Auto-rebuy bypassed (gameOver), entropy unused | SAFE -- entropy never consumed |
| C2: _processAutoRebuy | entropy (from parent) | EntropyLib.entropyStep for level offset selection | 1-4 levels ahead; player cannot control offset at claim time |

---

*Checklist compiled: 2026-03-25*
*Taskmaster: All 32 functions inventoried. Ready for Mad Genius.*
