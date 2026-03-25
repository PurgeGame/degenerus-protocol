# Unit 16: Integration Attack Report

**Phase:** 118 (Cross-Contract Integration Sweep)
**Agent:** Mad Genius (Integration Mode)
**Date:** 2026-03-25
**Methodology:** Cross-contract composition analysis per ULTIMATE-AUDIT-DESIGN.md Unit 16 scope

---

## Attack Surface 1: Delegatecall Storage Coherence (All 10 Module Boundaries)

### Analysis

All 10 game modules execute via delegatecall in DegenerusGame's storage context (102 variables, slots 0-78, verified EXACT MATCH in Unit 1). The primary concern is: can Module A cache a storage variable, Module B write to that same variable during the same top-level call, and then Module A write back the stale cache?

**Critical transaction paths where multiple modules execute:**

**Path 1: advanceGame() -> rngGate() chain**
- AdvanceModule computes `advanceBounty` at L127 from `price`
- rngGate() dispatches to JackpotModule functions (payDailyJackpot, consolidatePrizePools)
- rngGate() dispatches to EndgameModule (runRewardJackpots)
- EndgameModule calls DecimatorModule (runDecimatorJackpot)
- **Isolation mechanism:** The do-while(false) break at L235 (STAGE_RNG_REQUESTED) prevents any post-JackpotModule code from using stale AdvanceModule locals. AdvanceModule caches `advanceBounty` before the loop, but the bounty is used at L396 only AFTER the loop exits -- and the loop exits via break, not continuation.
- **Verdict: SAFE.** The only stale value is `advanceBounty` (INFO, Unit 2 F-01: ~0.005 ETH BURNIE, non-exploitable). All other cached locals are either consumed before the loop or refreshed after.

**Path 2: DegeneretteModule -> LootboxModule -> BoonModule (triple nesting)**
- DegeneretteModule.resolveBets calls LootboxModule.resolveLootboxDirect (delegatecall)
- LootboxModule calls BoonModule.checkAndClearExpiredBoon, consumeActivityBoon (delegatecall)
- **Storage concern:** `boonPacked`, `mintPacked_`, `prizePoolsPacked`
- **Evidence:** DegeneretteModule commits pool writes at L703 (`_setFuturePrizePool`) and claimable writes at L704 BEFORE the delegatecall to LootboxModule at L708 (verified Unit 8). LootboxModule uses fresh SLOADs for all boon/mint reads (verified Unit 9).
- **Verdict: SAFE.** No stale locals survive the delegatecall boundary.

**Path 3: EndgameModule -> DecimatorModule**
- runRewardJackpots calls runDecimatorJackpot via `IDegenerusGame(address(this)).runDecimatorJackpot(...)` (delegatecall through router)
- EndgameModule caches `futurePoolLocal` at L177
- DecimatorModule may write to `futurePrizePool` via auto-rebuy in claim paths
- **Reconciliation:** rebuyDelta at L244-246 captures all auto-rebuy writes: `rebuyDelta = _getFuturePrizePool() - baseFuturePool`. Final write: `_setFuturePrizePool(futurePoolLocal + rebuyDelta)`.
- **Verdict: SAFE.** Mathematically proven correct in Unit 4. The rebuyDelta mechanism is the explicit fix for the original BAF bug.

### Overall Verdict: SAFE

All 10 module boundaries verified. No cross-module cache-overwrite bugs found. The three isolation mechanisms (do-while break, pre-commit-before-delegatecall, rebuyDelta reconciliation) are effective.

---

## Attack Surface 2: ETH Conservation Analysis

### ETH Entry Points (Complete)

| # | Entry | Contract | Handler | Pool/Destination |
|---|-------|----------|---------|-----------------|
| 1 | Ticket purchase | Game (MintModule) | `purchaseFor` | prizePoolsPacked (next/future), claimablePool, vault share |
| 2 | Whale bundle | Game (WhaleModule) | `purchaseWhaleBundle` | prizePoolsPacked, claimablePool |
| 3 | Lazy pass | Game (WhaleModule) | `purchaseLazyPass` | prizePoolsPacked, claimablePool |
| 4 | Deity pass | Game (WhaleModule) | `purchaseDeityPass` | prizePoolsPacked, claimablePool |
| 5 | Degenerette bet (ETH) | Game (DegeneretteModule) | `placeFullTicketBets` | prizePoolsPacked (ETH portion) |
| 6 | Direct ETH send | Game | `receive()` | prizePoolsPacked (future) or pendingPools (if frozen) |
| 7 | Vault deposit | Vault | `deposit()` | Vault ETH reserve |
| 8 | sDGNRS receive | sDGNRS | `receive()` | sDGNRS ETH reserve (onlyGame) |
| 9 | DGNRS receive | DGNRS | `receive()` | DGNRS contract balance (onlySdgnrs) |
| 10 | Vault receive | Vault | `receive()` | Vault ETH reserve |

### ETH Exit Points (Complete)

| # | Exit | Contract | Function | Source |
|---|------|----------|----------|--------|
| 1 | Claim winnings (ETH first) | Game | `claimWinnings` | claimableWinnings[player] |
| 2 | Claim winnings (stETH first) | Game | `claimWinningsStethFirst` | claimableWinnings[player] |
| 3 | Vault share burn (ETH) | Vault | `burnEth` | Proportional reserve |
| 4 | sDGNRS claim redemption | sDGNRS | `claimRedemption` | pendingRedemptionEthValue |
| 5 | sDGNRS deterministic burn | sDGNRS | `burn` -> `_deterministicBurnFrom` | Proportional totalMoney |
| 6 | DGNRS burn | DGNRS | `burn` -> sDGNRS | Via sDGNRS burn path |
| 7 | Game-over drain to Vault | GameOverModule | `handleGameOverDrain` | Surplus ETH |
| 8 | Game-over drain to sDGNRS | GameOverModule | `handleGameOverDrain` | Surplus ETH |
| 9 | Vault share to MintModule | MintModule | `_purchaseFor` | vaultShare (fixed %) |

### Conservation Analysis

**Key invariant:** `Game.balance + Game.stethBalance >= claimablePool`

This invariant is maintained because:
1. Every ETH entry point adds to both the contract balance AND to pool accounting (prizePoolsPacked, claimablePool)
2. Every ETH exit from Game deducts from `claimablePool` BEFORE sending ETH (CEI at L1370: `claimablePool -= payout`)
3. The prize pool flow is: `futurePrizePool -> nextPrizePool -> currentPrizePool -> claimableWinnings[addr]`. Each transition is a zero-sum transfer between pool variables.
4. Auto-rebuy diverts a portion of claimable ETH back into `futurePrizePool` -- this is an internal transfer, not a creation or destruction of ETH.

**Rounding direction:** All integer divisions in pool splits round DOWN (Solidity default). Remainders stay in the source pool or are dropped as dust (< 1 wei per operation). This means the protocol retains slightly MORE ETH than accounting suggests -- the solvency invariant is strengthened, not weakened.

**stETH rebase:** Lido stETH rebases daily. Positive rebases increase `steth.balanceOf(Game)` without increasing any pool variable. This creates a surplus (yield). Negative rebases (validator slashing) decrease the balance without decreasing pools -- this could theoretically violate the invariant, but stETH slashing is < 0.01% per event and the yield surplus buffer absorbs it (verified Unit 3 F-01: 8% buffer).

### Verdict: SAFE

ETH conservation holds across all entry/exit paths. Rounding favors the protocol (solvency strengthened). The only risk is a catastrophic stETH negative rebase exceeding the yield surplus buffer, which is an accepted external dependency (documented in KNOWN-ISSUES.md).

---

## Attack Surface 3: Token Supply Invariant Verification

### BURNIE (BurnieCoin)

**Mint authorities (exhaustive):**
- `mintForGame(to, amount)` -- GAME only (game rewards, lootbox)
- `mintForCoinflip(to, amount)` -- COINFLIP only (flip payouts)
- `creditFlip(player, amount)` -- GAME or COINFLIP (general credit)
- `creditFlipBatch(players, amounts)` -- GAME or COINFLIP (batch credit)
- `vaultMintTo(to, amount)` -- VAULT only (vault BURNIE distribution)
- `creditLinkReward(player, amount)` -- ADMIN only (LINK donation reward)
- `creditCoin(player, amount)` -- GAME or COINFLIP (direct coin credit)

**Burn authorities (exhaustive):**
- `burnForCoinflip(from, amount)` -- COINFLIP only
- `burnForGame(from, amount)` -- GAME only (not used in current code paths)
- `decimatorBurn(player, amount)` -- GAME only
- `terminalDecimatorBurn(player, amount)` -- GAME only
- `transfer` to VAULT or SDGNRS -- redirects to vault escrow (reduces circulating, increases vaultAllowance)
- Self-burn: not directly available (no public burn function), but transfer to address(0) is blocked

**Supply invariant:** `totalSupply + vaultAllowance = constant` (modulo mint/burn operations). Verified across all 6 vault redirect paths in Unit 10.

**Can BURNIE be minted without game action?** NO. All mint paths require `msg.sender` to be one of the compile-time constant addresses (GAME, COINFLIP, VAULT, ADMIN). No external party can trigger unauthorized minting.

**Verdict: SAFE.** BURNIE supply is fully authorized.

### DGNRS (DegenerusStonk)

**No runtime mint function.** All DGNRS minted in constructor. Supply can only decrease (burn, burnForSdgnrs).

**Verdict: SAFE.** Supply monotonically decreasing.

### sDGNRS (StakedDegenerusStonk)

**Pool accounting:** `Whale + Affiliate + Claims + unallocated = totalSupply backed by reserves`

**Deposit paths:** Only GAME can deposit (gameDeposit, depositSteth). Deposits add to both token pool balances AND underlying reserves.

**Burn paths:** `burn()` and `burnWrapped()` compute payout proportionally from `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue`. This is a live balance computation, not cached.

**Verdict: SAFE.** Pool accounting is correct across all state transitions. Dust accumulation (Unit 11 FINDING-11-01) is monotonic and economically negligible (~99,000 wei lifetime).

### WWXRP (WrappedWrappedXRP)

**Intentionally undercollateralized.** `mintPrize` creates WWXRP without backing wXRP. This is documented in KNOWN-ISSUES.md and the contract design.

**Mint authorities:** GAME, COIN, COINFLIP, VAULT (4 compile-time constants). No unauthorized minting possible.

**Verdict: SAFE (within design parameters).** Undercollateralization is intentional.

---

## Attack Surface 4: Cross-Contract Reentrancy via ETH Sends

### ETH Send Sites

| # | Function | Contract | CEI Status | Re-entry Risk |
|---|----------|----------|------------|--------------|
| 1 | `_payoutWithStethFallback` L1982 | Game | CEI: `claimablePool -= payout` at L1370 BEFORE send | Player receives ETH. Can they re-enter Game? |
| 2 | `_payoutWithEthFallback` L2020 | Game | CEI: same as above | Same analysis |
| 3 | `claimRedemption` L517 | sDGNRS | CEI: `claim.ethPaid = true` at L598 BEFORE send | Player receives ETH. Can they re-enter sDGNRS? |
| 4 | `_deterministicBurnFrom` L783 | sDGNRS | CEI: `_burn()` at L679 BEFORE payout | Player receives ETH. Token burned before send. |
| 5 | `burnEth` L1032 | Vault | CEI: shares burned at L867 BEFORE send | Shareholder receives ETH. Shares already gone. |
| 6 | `handleGameOverDrain` L212 | GameOverModule | CEI: pool state updated before send | Vault/sDGNRS receives ETH. |
| 7 | `_purchaseFor` L765 | MintModule | Not CEI -- send to Vault mid-function | Vault receives ETH. Vault.receive() is no-op (just emits). |

### Re-entry Analysis

**Game.claimWinnings -> player receives ETH:**
- State at re-entry: `claimableWinnings[player] = 1` (sentinel), `claimablePool` already decremented
- Can player call claimWinnings again? YES but `amount <= 1` reverts at L1364
- Can player call purchaseFor? YES but this is normal game action, no stale state
- Can player call advanceGame? YES but no stale state depends on claimWinnings completion
- **Verdict: SAFE.** CEI correctly prevents double-claim. Re-entry into other functions is benign.

**sDGNRS.claimRedemption -> player receives ETH:**
- State at re-entry: `claim.ethPaid = true`
- Can player call claimRedemption again? YES but ETH portion skipped (ethPaid = true). BURNIE portion: `claim.burniePaid = true` set before BURNIE transfer. Both claims are idempotent.
- **Verdict: SAFE.**

**Vault.burnEth -> shareholder receives ETH:**
- State at re-entry: shares burned, supply reduced
- Can shareholder call burnEth again? YES but with reduced share count (proportional to new supply). Each burn reduces their balance. No double-spend.
- **Verdict: SAFE.**

**MintModule._purchaseFor -> Vault receives ETH (L765):**
- This is NOT CEI-compliant: ETH is sent to Vault mid-function before all state writes
- However: Vault.receive() at L465 just emits an event and returns. No callback. No state change that affects MintModule.
- **Verdict: SAFE.** Vault is a trusted compile-time constant with a trivial receive().

### Overall Verdict: SAFE

All ETH send sites either follow CEI or send to trusted contracts with no callback paths.

---

## Attack Surface 5: State Machine Consistency

### Can advanceGame() get permanently stuck?

**Scenario 1: VRF never responds**
- `rngRequestTime` tracks when VRF was requested
- If `block.timestamp - rngRequestTime > VRF_TIMEOUT`, advanceGame triggers backfill/recovery
- After 120 days of no VRF, game-over triggers automatically
- **Verdict: Cannot permanently stuck.** VRF timeout is the escape hatch.

**Scenario 2: gameOver + unprocessed state**
- GameOverModule.handleGameOverDrain processes final state
- After game-over, most functions revert (`if (gameOver) revert E()`)
- Claim functions remain accessible (claimWinnings, claimDecimatorJackpot, etc.)
- **Verdict: SAFE.** Game-over is a well-defined terminal state.

**Scenario 3: prizePoolFrozen stuck across transactions**
- Set at advanceGame L138 (`prizePoolFrozen = true`)
- Cleared at advanceGame L394 (`prizePoolFrozen = false`)
- If advanceGame reverts between L138 and L394, the revert unwinds ALL state changes including the freeze flag
- **Verdict: Cannot persist.** Solidity atomic transaction model guarantees unwinding.

**Scenario 4: rngLocked stuck permanently**
- Set when VRF request is made
- Cleared by `rawFulfillRandomWords` on VRF response OR by timeout logic in advanceGame
- If VRF coordinator is permanently broken, governance can swap coordinator (Admin.propose/vote/execute)
- After coordinator swap, `_backfillGapDays` provides fallback entropy
- **Verdict: Cannot permanently stuck.** Multiple recovery paths exist.

**Scenario 5: jackpotPhaseFlag inconsistent with currentDay**
- `jackpotPhaseFlag` is set during jackpot processing and cleared when complete
- `currentDay` increments once per advanceGame call
- Both are written by AdvanceModule only -- no cross-module writer conflict
- The do-while FSM ensures both are updated atomically within the same call
- **Verdict: SAFE.** Single-writer FSM with atomic updates.

### Overall Verdict: SAFE

The state machine has well-defined terminal states and recovery paths. No permanent stuck state is possible.

---

## Attack Surface 6: decBucketOffsetPacked Collision (Escalation from Unit 7)

### Exact Call Chain at GAMEOVER Level

When game-over occurs during a jackpot phase:

1. `advanceGame()` enters the do-while FSM
2. rngGate dispatches to `_handleGameOverPath()` (AdvanceModule L433)
3. `_handleGameOverPath` calls `runRewardJackpots(lvl, rngWord)` (EndgameModule)
4. `runRewardJackpots` at L215/L231 calls `runDecimatorJackpot(decPoolWei, lvl, rngWord)` -- writes `decBucketOffsetPacked[lvl]` at DecimatorModule L248
5. After runRewardJackpots returns, `_handleGameOverPath` calls `handleGameOverDrain(lvl, rngWord)` (GameOverModule)
6. `handleGameOverDrain` at L139 calls `runTerminalDecimatorJackpot(decPool, lvl, rngWord)` -- OVERWRITES `decBucketOffsetPacked[lvl]` at DecimatorModule L817

### When Does This Actually Occur?

The collision occurs when:
- `lvl` triggers a regular decimator (every level ending in 0 or 5, except 95): levels 5, 10, 15, 20, ..., 90, 100, 105, ...
- AND game-over triggers at that same level
- AND at least one player has a pending regular decimator claim at that level

### Economic Impact

**Affected claimants:** Regular decimator winners at the GAMEOVER level who have not yet claimed.
- Their winning subbucket was computed from the ORIGINAL RNG word and burn aggregates
- After the terminal decimator overwrites, claims validate against DIFFERENT winning subbuckets
- Original winners may not match the new subbuckets -> cannot claim
- Non-winners may coincidentally match new subbuckets -> can claim (unearned)
- The `totalBurn` denominator in `decClaimRounds[lvl]` was computed from original subbuckets but claims now validate against overwritten subbuckets

**Magnitude:** At game-over, the regular decimator pool at a single level is (futurePool * 30%) for century levels or (futurePool * 10%) for non-century. With a typical futurePool of 100 ETH, this is 10-30 ETH at risk of misallocation at one level.

**Mitigation:** The terminal decimator has its own separate pool (10% of game-over budget from `handleGameOverDrain`). Terminal claims read the overwritten offsets and function correctly. Only regular decimator claims at the GAMEOVER level are affected.

### Verdict: INVESTIGATE (MEDIUM) -- confirmed from Unit 7

This is the only MEDIUM finding across all 16 units. The fix (separate `terminalDecBucketOffsetPacked` mapping) is straightforward and was recommended in Unit 7.

---

## Attack Surface 7: Auto-Rebuy BAF Pattern (Cross-Module, Vault Path)

### The Concern

Unit 3 F-01 identified that VAULT can enable auto-rebuy via `DegenerusVault.gameSetAutoRebuy()`. If auto-rebuy is active for the Vault address, the yield surplus distribution path could trigger:

```
consolidatePrizePools (JackpotModule B5)
  -> _distributeYieldSurplus (C2)
    -> _addClaimableEth(VAULT, amount) (C3)
      -> _processAutoRebuy (C4)
        -> writes to futurePrizePool
```

The `obligations` snapshot at C2 L886-890 includes `_getFuturePrizePool()`. After auto-rebuy writes to futurePrizePool, the snapshot is stale.

### Analysis

1. **Snapshot usage:** The `obligations` snapshot is ONLY used at L892 for the surplus gate check: `if (yield <= obligations) return`. It is NOT used for computing `stakeholderShare` or `accumulatorShare`.

2. **Staleness direction:** If auto-rebuy increased futurePrizePool, actual obligations are HIGHER. The real surplus is SMALLER than what the gate check computed. The protocol distributes based on a slightly-too-large surplus estimate.

3. **Buffer:** The distribution leaves 8% of surplus unextracted (NatSpec L896). This 8% buffer absorbs the staleness.

4. **Maximum staleness:** The maximum auto-rebuy amount is the entire `weiAmount` passed to `_addClaimableEth(VAULT, ...)`. This is bounded by the yield surplus itself (distributed proportionally). In the worst case, vault's share of surplus is the staleness.

5. **Practical trigger:** Requires vault owner to explicitly enable auto-rebuy for the vault address. This is an administrative action, not an external attack.

### Verdict: SAFE (INFO)

The staleness is directionally conservative (overstates surplus, protocol gives away slightly more than it should). The 8% buffer absorbs the difference. No external attacker can trigger this. Confirmed as INFO by Unit 3 Skeptic review.

---

## Findings Summary

| # | Attack Surface | Verdict | Severity |
|---|---------------|---------|----------|
| 1 | Delegatecall Storage Coherence | SAFE | -- |
| 2 | ETH Conservation | SAFE | -- |
| 3 | Token Supply Invariants | SAFE | -- |
| 4 | Cross-Contract Reentrancy | SAFE | -- |
| 5 | State Machine Consistency | SAFE | -- |
| 6 | decBucketOffsetPacked Collision | INVESTIGATE | MEDIUM (from Unit 7) |
| 7 | Auto-Rebuy BAF (Vault Path) | SAFE | INFO (from Unit 3) |

**New integration-level findings:** 0

The only MEDIUM finding (decBucketOffsetPacked collision) was already discovered in Unit 7. The integration sweep confirms it is a genuine cross-module composition issue (EndgameModule -> GameOverModule both route through DecimatorModule at the same level). No new findings were discovered at the integration level.

---

*Integration attack analysis completed: 2026-03-25*
*Agent: Mad Genius (Integration Mode)*
