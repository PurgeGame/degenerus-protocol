# Phase 109: Decimator System - Research

## Contract Under Audit

**DegenerusGameDecimatorModule.sol** -- 930 lines (including constants, events, errors, interfaces)
- Inherits: DegenerusGamePayoutUtils -> DegenerusGameStorage
- Executed via delegatecall from DegenerusGame.sol (all storage reads/writes operate on Game's storage)
- 7 external state-changing entry points, 13 internal/private state-changing helpers, 8 view/pure functions

## Complete Function Inventory

### Category B: External State-Changing Functions (7)

| # | Function | Lines | Access Control | Risk Tier | Key Concern |
|---|----------|-------|---------------|-----------|-------------|
| B1 | `recordDecBurn(address,uint24,uint8,uint256,uint256)` | 129-188 | `OnlyCoin` (msg.sender == COIN) | Tier 2 | Bucket migration on improvement, subbucket aggregate accounting, uint192 saturation |
| B2 | `runDecimatorJackpot(uint256,uint24,uint256)` | 205-256 | `OnlyGame` (msg.sender == GAME) | Tier 2 | VRF-based winning subbucket selection, claim round snapshot, double-snapshot guard |
| B3 | `consumeDecClaim(address,uint24)` | 301-307 | `OnlyGame` (msg.sender == GAME) | Tier 3 | Thin wrapper around _consumeDecClaim |
| B4 | `claimDecimatorJackpot(uint24)` | 316-338 | any (player-callable, prizePoolFrozen guard) | **Tier 1** | **BAF-CRITICAL**: 50/50 split, auto-rebuy chain, futurePrizePool read-then-write pattern, lootbox delegatecall |
| B5 | `recordTerminalDecBurn(address,uint24,uint256)` | 707-770 | `OnlyCoin` (msg.sender == COIN) | Tier 2 | Self-call via IDegenerusGame, time multiplier, activity-score bucket, lazy level reset, uint80/uint88 saturation |
| B6 | `runTerminalDecimatorJackpot(uint256,uint24,uint256)` | 783-825 | `OnlyGame` (msg.sender == GAME) | Tier 2 | Reuses decBucketOffsetPacked, uint96 poolWei truncation, double-resolution guard |
| B7 | `claimTerminalDecimatorJackpot()` | 833-840 | any (player-callable, prizePoolFrozen guard) | Tier 2 | GAMEOVER-only claim, passes entropy=0 to _addClaimableEth (auto-rebuy skipped when gameOver=true) |

**Risk tier justification:**
- B4 is Tier 1: The claimDecimatorJackpot function contains the BAF-critical auto-rebuy chain. It reads _getFuturePrizePool() at L336, then calls _creditDecJackpotClaimCore -> _addClaimableEth -> _processAutoRebuy -> _setFuturePrizePool(). This is the exact pattern of the original BAF cache-overwrite bug.
- B1, B2, B5, B6 are Tier 2: Significant state-changing logic with arithmetic edge cases, but no BAF-critical chain.
- B3, B7 are Tier 3 (promoted to Tier 2 for B7): B3 is a thin wrapper. B7 calls _addClaimableEth but passes entropy=0 and is only active when gameOver=true (auto-rebuy returns early on gameOver).

### Category C: Internal/Private State-Changing Helpers (13)

| # | Function | Lines | Called By | Key Storage Writes | Flags |
|---|----------|-------|-----------|-------------------|-------|
| C1 | `_consumeDecClaim(address,uint24)` | 270-293 | B3, B4 | decBurn[lvl][player].claimed | [MULTI-PARENT] |
| C2 | `_processAutoRebuy(address,uint256,uint256)` | 362-408 | C3 | autoRebuyState (read), prizePoolsPacked (via _setFuturePrizePool/_setNextPrizePool), ticketQueue (via _queueTickets), claimableWinnings (via _creditClaimable), claimablePool | [BAF-CRITICAL] |
| C3 | `_addClaimableEth(address,uint256,uint256)` | 414-424 | C4, B4 (gameOver path), B7 | claimableWinnings (via _creditClaimable or _processAutoRebuy) | [BAF-CRITICAL] [MULTI-PARENT] |
| C4 | `_creditDecJackpotClaimCore(address,uint256,uint256)` | 433-447 | B4 | claimablePool (decrement), delegates to _addClaimableEth and _awardDecimatorLootbox | |
| C5 | `_decUpdateSubbucket(uint24,uint8,uint8,uint192)` | 577-585 | B1 (accumulate), B1 (migrate) | decBucketBurnTotal[lvl][denom][sub] | [MULTI-PARENT] |
| C6 | `_decRemoveSubbucket(uint24,uint8,uint8,uint192)` | 592-602 | B1 (migrate path) | decBucketBurnTotal[lvl][denom][sub] | |
| C7 | `_awardDecimatorLootbox(address,uint256,uint256)` | 627-651 | C4 | whalePassClaims (via _queueWhalePassClaimCore), or delegatecall to LootboxModule | |
| C8 | `_consumeTerminalDecClaim(address)` | 869-893 | B7 | terminalDecEntries[player].weightedBurn = 0 | |
| C9 | `_creditClaimable(address,uint256)` | PayoutUtils L30-36 | C2 (fallback), C2 (reserved) | claimableWinnings[beneficiary] | [MULTI-PARENT] (inherited) |
| C10 | `_calcAutoRebuy(...)` | PayoutUtils L38-72 | C2 | None (pure computation) | Inherited, pure |
| C11 | `_queueWhalePassClaimCore(address,uint256)` | PayoutUtils L75-91 | C7 (whale threshold) | whalePassClaims[], claimableWinnings[], claimablePool | [MULTI-PARENT] (inherited) |
| C12 | `_queueTickets(address,uint24,uint32)` | Storage L528 | C2 | ticketQueue[lvl], ticketsOwedPacked[][] | Inherited from Storage |
| C13 | `_revertDelegate(bytes)` | 80-85 | C7 | None (pure revert propagation) | |

### Category D: View/Pure Functions (8)

| # | Function | Lines | Reads/Computes | Security Note |
|---|----------|-------|---------------|---------------|
| D1 | `decClaimable(address,uint24)` | 346-355 | decClaimRounds, decBurn, decBucketOffsetPacked | View wrapper for _decClaimable |
| D2 | `terminalDecClaimable(address)` | 846-866 | lastTerminalDecClaimRound, terminalDecEntries, decBucketOffsetPacked | View, pro-rata calculation |
| D3 | `_decEffectiveAmount(uint256,uint256,uint256)` | 454-473 | Pure arithmetic | Multiplier cap logic; verify boundary correctness |
| D4 | `_decWinningSubbucket(uint256,uint8)` | 479-485 | Pure: keccak256(entropy, denom) % denom | Modulo bias check: denom 2-12, 256-bit hash, bias negligible |
| D5 | `_packDecWinningSubbucket(uint64,uint8,uint8)` | 493-501 | Pure: bit packing | 4 bits per denom, 11 denoms = 44 bits in uint64 |
| D6 | `_unpackDecWinningSubbucket(uint64,uint8)` | 507-514 | Pure: bit unpacking | Guard for denom < 2 returns 0 |
| D7 | `_decClaimableFromEntry(uint256,uint256,DecEntry,uint64)` | 522-543 | View: pro-rata calculation | Division by zero guarded (totalBurn == 0 check) |
| D8 | `_decClaimable(DecClaimRound,address,uint24)` | 551-570 | View: wraps D7 | Claimed-flag check |
| D9 | `_decSubbucketFor(address,uint24,uint8)` | 610-621 | Pure: keccak256(player, lvl, bucket) % bucket | Deterministic assignment; bucket=0 guard |
| D10 | `_terminalDecMultiplierBps(uint256)` | 903-909 | Pure: time multiplier | Discontinuity at day 10 (intentional per comment) |
| D11 | `_terminalDecBucket(uint256)` | 912-919 | Pure: activity-to-bucket | Boundary clamping to [2, 12] |
| D12 | `_terminalDecDaysRemaining()` | 922-929 | View: block.timestamp vs levelStartTime | Division truncation on days remaining |

**Note:** D3 and D9-D12 are pure/view helpers called within state-changing chains. They remain Category D because they have no storage writes.

## BAF-Critical Path Analysis

### Primary BAF Chain: claimDecimatorJackpot (B4)

```
B4: claimDecimatorJackpot(lvl)            L316-338
  |-- _consumeDecClaim(msg.sender, lvl)    L323   -> writes decBurn[lvl][player].claimed
  |-- [gameOver path] _addClaimableEth     L326   -> EXITS (no futurePrizePool concern)
  |-- _creditDecJackpotClaimCore           L330-331
  |   |-- _addClaimableEth(ethPortion)     L442
  |   |   |-- _processAutoRebuy           L420
  |   |   |   |-- _calcAutoRebuy          L372-380  (pure)
  |   |   |   |-- _setFuturePrizePool     L387  *** WRITES futurePrizePool ***
  |   |   |   |-- _setNextPrizePool       L389  *** WRITES nextPrizePool ***
  |   |   |   |-- _queueTickets           L391  *** WRITES ticketQueue ***
  |   |   |   |-- _creditClaimable        L394  *** WRITES claimableWinnings ***
  |   |   |   |-- claimablePool -= ...    L398  *** WRITES claimablePool ***
  |   |   |-- _creditClaimable            L423  (fallback if auto-rebuy disabled)
  |   |-- claimablePool -= lootboxPortion  L445  *** WRITES claimablePool ***
  |   |-- _awardDecimatorLootbox           L446
  |       |-- _queueWhalePassClaimCore     L634  (if amount > threshold)
  |       |   |-- whalePassClaims[]        *** WRITES whalePassClaims ***
  |       |   |-- claimableWinnings[]      *** WRITES claimableWinnings ***
  |       |   |-- claimablePool            *** WRITES claimablePool ***
  |       |-- delegatecall LootboxModule   L638-650 (if amount <= threshold)
  |-- lootboxPortion check                L335-337
  |-- _setFuturePrizePool(READ + add)     L336  *** READS then WRITES futurePrizePool ***
```

**CRITICAL PATTERN at L336:**
```solidity
uint256 lootboxPortion = _creditDecJackpotClaimCore(msg.sender, amountWei, ...);
if (lootboxPortion != 0) {
    _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);  // L336
}
```

The _getFuturePrizePool() at L336 is called AFTER _creditDecJackpotClaimCore returns. Inside _creditDecJackpotClaimCore -> _addClaimableEth -> _processAutoRebuy -> _setFuturePrizePool() may have already modified futurePrizePool. Since _getFuturePrizePool() is a FRESH storage read (not cached in a local variable before the call), the L336 read will pick up the updated value. This means the pattern is **NOT** a stale-cache overwrite -- the read happens after the write.

However, this must be verified by the Mad Genius with line-by-line analysis.

### Secondary BAF Chain: claimTerminalDecimatorJackpot (B7)

```
B7: claimTerminalDecimatorJackpot()       L833-840
  |-- _consumeTerminalDecClaim(msg.sender) L836  -> writes terminalDecEntries[].weightedBurn=0
  |-- _addClaimableEth(msg.sender, amt, 0) L839
      |-- _processAutoRebuy               L420  -> returns false (gameOver == true at L367)
      |-- _creditClaimable                L423  -> writes claimableWinnings[]
```

Auto-rebuy is disabled during gameOver. The BAF chain is not reachable from B7. This must be confirmed by the Mad Genius.

## Storage Slot Map

### DecimatorModule-Specific Storage

| Slot/Mapping | Type | Written By | Read By |
|-------------|------|------------|---------|
| `decBurn[lvl][player]` | DecEntry (uint192+uint8+uint8+uint8) | B1, C1 | C1, D1, D7, D8 |
| `decBucketBurnTotal[lvl][denom][sub]` | uint256[13][13] | C5, C6, B1 (via C5/C6) | B2 |
| `decClaimRounds[lvl]` | DecClaimRound (uint256+uint256+uint232) | B2 | C1, D1, D8, B4 |
| `decBucketOffsetPacked[lvl]` | uint64 | B2, B6 | C1, D1, D7, D8, B7 (via C8), D2 |
| `terminalDecEntries[player]` | TerminalDecEntry (80+88+8+8+48 bits) | B5, C8 | C8, D2 |
| `terminalDecBucketBurnTotal[key]` | uint256 | B5 | B6 |
| `lastTerminalDecClaimRound` | TerminalDecClaimRound (24+96+128 bits) | B6 | C8, D2 |

### Inherited Storage Written by This Module

| Slot/Mapping | Written By | Via |
|-------------|------------|-----|
| `claimableWinnings[player]` | C2, C9, C11 | _creditClaimable, _queueWhalePassClaimCore |
| `claimablePool` | C2 (L398), C4 (L445), C11 | Direct decrement, _queueWhalePassClaimCore |
| `prizePoolsPacked` (futurePrizePool) | C2 (L387), B4 (L336) | _setFuturePrizePool |
| `prizePoolsPacked` (nextPrizePool) | C2 (L389) | _setNextPrizePool |
| `ticketQueue[lvl]` | C2 (via C12) | _queueTickets |
| `ticketsOwedPacked[player][lvl]` | C2 (via C12) | _queueTickets |
| `whalePassClaims[player]` | C7 (via C11) | _queueWhalePassClaimCore |
| `autoRebuyState[player]` | Read only by C2 | Not written |
| `decimatorAutoRebuyDisabled[player]` | Read only by C2 | Not written |

### Shared Storage: decBucketOffsetPacked Collision Risk

Both B2 (runDecimatorJackpot) and B6 (runTerminalDecimatorJackpot) write to `decBucketOffsetPacked[lvl]`. If both run at the same level:
- B2 snapshots regular decimator winning subbuckets for level N
- B6 snapshots terminal decimator winning subbuckets for the GAMEOVER level

**Analysis:** Terminal decimator (B6) runs ONLY at GAMEOVER. Regular decimator (B2) runs at normal level transitions (via jackpot phase). At GAMEOVER, the regular decimator for the current level has already been resolved (or will not be resolved if no jackpot phase was reached). However, if the GAMEOVER level is the same as a level that already had a regular decimator resolution, B6 would overwrite the packed offsets.

This requires careful investigation: does B6 check decClaimRounds[lvl].poolWei before overwriting? No -- B6 uses `lastTerminalDecClaimRound.lvl` for its double-resolution guard, which is separate. But the packedOffsets at `decBucketOffsetPacked[lvl]` would be overwritten. Claims from the regular decimator at that same level would then use the WRONG winning subbuckets.

**POTENTIAL FINDING: decBucketOffsetPacked collision between regular and terminal decimator at the same level.**

## Risk Tiers

### Tier 1 (BAF-Critical / Complex Multi-Path)
- **B4: claimDecimatorJackpot** -- BAF-critical auto-rebuy chain, futurePrizePool read-after-write pattern, 50/50 split with lootbox delegatecall

### Tier 2 (Significant State Changes / Arithmetic Edge Cases)
- **B1: recordDecBurn** -- Bucket migration, aggregate accounting, saturation arithmetic
- **B2: runDecimatorJackpot** -- VRF-based selection, claim round snapshot, writes to shared decBucketOffsetPacked
- **B5: recordTerminalDecBurn** -- Self-call pattern, time multiplier, activity-score bucket, lazy reset
- **B6: runTerminalDecimatorJackpot** -- Shared decBucketOffsetPacked write, uint96 truncation, GAMEOVER-only
- **B7: claimTerminalDecimatorJackpot** -- GAMEOVER claim, auto-rebuy expected to be skipped

### Tier 3 (Thin Wrappers)
- **B3: consumeDecClaim** -- OnlyGame guard + direct delegation to _consumeDecClaim

## Key Pitfalls and Attack Surfaces

### 1. decBucketOffsetPacked Collision (INVESTIGATE)
Both regular and terminal decimator resolution write to the same packed offset mapping at the same level key. If terminal resolution happens at a level where regular decimator claims are still pending, the winning subbuckets for the regular decimator are overwritten.

### 2. futurePrizePool Read-After-Write in claimDecimatorJackpot (VERIFY)
Line 336 reads _getFuturePrizePool() after _creditDecJackpotClaimCore returns. The subordinate chain may have modified futurePrizePool via auto-rebuy. If the read is fresh from storage (not cached before the call), this is safe. Must verify no local caching.

### 3. claimablePool Accounting in Decimator Claims (VERIFY)
claimDecimatorJackpot does NOT add amountWei to claimablePool before the split. The comment at L397 says "Decimator pool was pre-reserved in claimablePool." Must verify that the resolution function (B2) actually reserves the pool in claimablePool. If not, claimablePool -= operations in C2/C4 would underflow.

### 4. uint96 Truncation in Terminal Decimator (INVESTIGATE)
B6 at L821: `lastTerminalDecClaimRound.poolWei = uint96(poolWei)`. If poolWei > type(uint96).max (~79,228 ETH), it silently truncates. With 10% of remaining funds at GAMEOVER, this could be significant. However, type(uint96).max is ~79K ETH which far exceeds realistic pool sizes.

### 5. Terminal Decimator Self-Call Pattern (INVESTIGATE)
B5 at L718: `IDegenerusGame(address(this)).playerActivityScore(player)`. This is a self-call via the public interface. Since the module runs via delegatecall, `address(this)` is the Game contract. This routes through the Game's fallback, which delegates to the appropriate module. Potential concern: reentrancy via this call path, or gas limits on the self-call.

### 6. _decEffectiveAmount Multiplier Cap Math (VERIFY)
Lines 454-473: The capped multiplier arithmetic has a two-part calculation (multiplied portion + unmultiplied remainder). Verify that the boundary condition (prevBurn == DECIMATOR_MULTIPLIER_CAP - 1) produces correct results and no off-by-one.

### 7. Bucket Migration Aggregate Underflow (VERIFY)
B1 line 148: `_decRemoveSubbucket` is called during bucket migration. If the aggregate somehow became inconsistent (e.g., due to prior saturation), the subtraction at L600 could revert via the `if (slotTotal < uint256(delta)) revert E()` guard. This is a liveness concern, not a fund-loss concern.

### 8. Terminal Decimator Death Clock Edge Cases (VERIFY)
B5 at L715: `_terminalDecDaysRemaining()` uses `levelStartTime` and `block.timestamp`. If level == 0, uses TERMINAL_DEC_IDLE_TIMEOUT_DAYS (365 days). If level > 0, uses TERMINAL_DEC_DEATH_CLOCK (120 days). Edge case: what if levelStartTime is 0 (never set)? The deadline would be 0 + timeout, which is in the past, returning 0, blocking burns. This is safe-fail behavior.

---

*Research completed: 2026-03-25*
*Contract: DegenerusGameDecimatorModule.sol (930 lines, 28 functions)*
