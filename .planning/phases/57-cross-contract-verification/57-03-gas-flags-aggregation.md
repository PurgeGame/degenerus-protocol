# Cross-Protocol Gas Flags Aggregation

**Scope:** All 22 deployable contracts + 10 modules + 5 libraries
**Date:** 2026-03-07
**Source:** Phases 50-56 gas flag data + fresh source scan

---

## 1. Impossible Condition Checks (GAS-01)

Scan of ALL source contracts for conditions that can NEVER be true at the point they are checked.

| # | Contract | Function | Line(s) | Condition | Why Impossible | Impact (gas) | Intentional? |
|---|----------|----------|---------|-----------|----------------|-------------|-------------|
| 1 | BurnieCoin | `_mint` | 469 | `to == address(0)` | All callers pass non-zero addresses (game contract, coinflip claims, quest rewards). The only mint paths are `mintForCoinflip` (player from coinflip), `creditLinkReward` (player from admin), and `_recordMintDataModule` return path. All validate upstream. | ~22 gas (JUMPI) | Yes -- defensive ERC20 standard pattern |
| 2 | BurnieCoin | `_burn` | 489 | `from == address(0)` | All callers pass msg.sender or validated player addresses. Zero address cannot hold tokens. | ~22 gas | Yes -- defensive ERC20 standard pattern |
| 3 | BurnieCoin | `_transfer` | 443 | `from == address(0) \|\| to == address(0)` | Standard ERC20 defense; `transfer()` uses msg.sender (never zero), `transferFrom()` checks allowance (zero address has no allowance). | ~44 gas | Yes -- defensive ERC20 standard pattern |
| 4 | DegenerusVaultShare | `vaultMint` | 257 | `to == address(0)` | Only called from vault `burnCoin`/`burnEth` refill path with `msg.sender` (never zero) or vault owner. | ~22 gas | Yes -- defensive |
| 5 | DegenerusVaultShare | `_transfer` | 289 | `to == address(0)` | Standard ERC20 transfer target check. Users would lose tokens. | ~22 gas | Yes -- defensive ERC20 |
| 6 | WrappedWrappedXRP | `_mint` | (internal) | `to == address(0)` | All mint paths validate recipient upstream (game rewards, vault mints). | ~22 gas | Yes -- defensive ERC20 |
| 7 | WrappedWrappedXRP | `_transfer` | (internal) | `to == address(0)` | Standard ERC20 defense. | ~22 gas | Yes -- defensive ERC20 |
| 8 | DegenerusGame | `recordMint` | 397 | `msg.sender != address(this)` | Only called via delegatecall from mint module which executes in game context, so msg.sender IS address(this). This check is a critical safety net preventing external calls. | ~22 gas | Yes -- critical access control |
| 9 | DegenerusGame | `runDecimatorJackpot` | 1222 | `msg.sender != address(this)` | Only called from advance module delegatecall context. Same pattern as recordMint. | ~22 gas | Yes -- critical access control |
| 10 | DegenerusGame | `runTerminalJackpot` | 1250 | `msg.sender != address(this)` | Only called from jackpot module delegatecall context. | ~22 gas | Yes -- critical access control |
| 11 | DegenerusGame | `consumeDecClaim` | 1272 | `msg.sender != address(this)` | Only called from decimator module delegatecall context. | ~22 gas | Yes -- critical access control |
| 12 | DegenerusGame | `consumePurchaseBoost` | 907 | `msg.sender != address(this)` | Only called from mint module delegatecall context. | ~22 gas | Yes -- critical access control |
| 13 | DegenerusGame | `setOperatorApproval` | 477 | `operator == address(0)` | Caller would be setting approval for zero address, which is meaningless but technically possible. | ~22 gas | Yes -- defensive |
| 14 | DegenerusGame | `recordMint` | 404 | `prizeContribution != 0` | With DirectEth, prizeContribution = amount which is always > 0 (validated by `msg.value < amount` check). With Claimable, prizeContribution = amount > 0. With Combined, prizeContribution = msg.value + claimableUsed >= amount > 0. The check is only false if amount=0, but amount=costWei which is always > 0 for valid mints. | ~22 gas | Yes -- defensive for edge cases |
| 15 | DegenerusGame | `recordMint` | 407 | `futureShare != 0` after `(prizeContribution * 1000) / 10000` | futureShare is 10% of prizeContribution. Only zero if prizeContribution < 10 wei, which is impossible given minimum ticket prices (~0.001 ETH). | ~22 gas | Yes -- defensive |
| 16 | DegenerusGame | `_revertDelegate` | 1081 | `reason.length == 0` | Failed delegatecalls to valid module addresses always include revert data. Only empty if delegatecall to EOA (impossible with constant module addresses). | ~22 gas | Yes -- defensive fallback |
| 17 | DegenerusStonk | `constructor` | 349 | `totalAllocated < INITIAL_SUPPLY` | BPS sum is 2000+1143+3428+1143+1143+1143 = 10000 = 100%. With integer division rounding, totalAllocated could be slightly less than INITIAL_SUPPLY. The dust redistribution handles this correctly. | Dust only | Yes -- defensive rounding handler |
| 18 | DegenerusAdmin | `emergencyRecover` | 481 | `subscriptionId == 0` | subscriptionId is set in constructor and only cleared by shutdown (which is gameover-gated). Emergency recovery requires !gameOver, so subscriptionId is always non-zero. | ~22 gas | Yes -- defensive |
| 19 | JackpotBucketLib | `_calcShares` | (lib) | Defensive cap in share calculation | Cap mechanism verified to never trigger with current constants (max 4 buckets, each gets >= floor share). | ~22 gas | Yes -- defensive against future constant changes |

**Summary:** All 19 impossible conditions found are **intentional defensive programming patterns**. None represent true gas waste -- they are safety nets that cost ~22 gas each (a single JUMPI). Removing any of them would save negligible gas while reducing defense-in-depth.

---

## 2. Redundant Storage Reads (GAS-02)

Scan for storage variables read multiple times in the same function where value cannot have changed between reads.

| # | Contract | Function | Line(s) | Variable | Times Read | Could Cache? | Est. Gas Save |
|---|----------|----------|---------|----------|------------|-------------|--------------|
| 1 | BurnieCoinflip | `_claimCoinflipsInternal` | 434,436 | `degenerusGame` (immutable) | 2+ | N/A (immutable, no SLOAD) | 0 -- compiler inlines immutable |
| 2 | BurnieCoinflip | `_depositCoinflip` | 274,290-302 | `degenerusGame` (immutable) | 3 | N/A (immutable) | 0 |
| 3 | BurnieCoinflip | `claimCoinflips` / `claimCoinflipsTakeProfit` / `claimCoinflipsFromBurnie` / `consumeCoinflipsForBurn` | 334,354,364 | `degenerusGame.rngLocked()` | 1 per function | N/A (single read per function) | 0 |
| 4 | DegenerusGame | `claimAffiliateDgnrs` | 1446-1465 | `level` (storage) | 1 | Already cached in local `currLevel` | 0 -- already optimized |
| 5 | DegenerusGame | `recordMint` | 399-416 | `prizeContribution` (local) | N/A (already local var) | N/A | 0 |
| 6 | DegenerusStonk | `lockForLevel` | 438-439 | `game.level()` | 1 | Already cached in local `currentLevel` | 0 -- already optimized |
| 7 | DegenerusStonk | `gamePurchase` | 497-498 | `game.mintPrice()` | 1 | Single read | 0 |
| 8 | DegenerusVault | `_isVaultOwner` | 411-413 | `ethShare.totalSupply()` + `ethShare.balanceOf()` | 2 external calls | Could batch but different calls | ~200 gas (warm STATICCALL overhead) |
| 9 | LootboxModule | `_resolveLootboxCommon` via `_deityBoonForSlot` | (module) | `rngWordByDay[day]` | Up to 3 (once per slot in loop) | Yes -- cache daily seed before loop | ~200 gas (2 warm SLOADs saved) |
| 10 | DegenerusStonk | `_checkAndRecordEthSpend` / `_lockedClaimableValues` | multiple | `game.level()` | Called from multiple functions per tx | Each function caches separately, but cross-function calls may re-read | ~2100 gas (cold) or ~100 gas (warm) per extra read |
| 11 | BurnieCoin | `balanceOfWithClaimable` | 284-290 | `_supply.vaultAllowance` | 1 (only for VAULT) | Single read | 0 |
| 12 | DegenerusAdmin | `onTokenTransfer` | (admin) | `this._linkAmountToEth(amount)` via external self-call | 1 | Necessary for try/catch pattern | 0 -- pattern required |

**Summary:** The codebase is extremely well-optimized for storage reads. Only 2 items have any practical optimization potential:

1. **LootboxModule `rngWordByDay[day]` in boon loop** (Item 9): Could save ~200 gas by caching the daily seed before the 3-iteration boon slot loop. The optimizer may already handle this.
2. **DegenerusStonk cross-function `game.level()` reads** (Item 10): Multiple spend-check functions may redundantly read `game.level()` within the same transaction. Savings depend on call patterns.

All other storage reads are either already cached in local variables, use immutable references (no SLOAD), or are single reads per function.

---

## 3. Prior Audit Gas Flags Aggregated

Non-trivial gas flags extracted from all Phase 50-56 individual audit reports. Entries marked "None" or describing standard/acceptable patterns are excluded. Only entries describing actual gas characteristics worth noting are included.

| # | Phase | Contract | Function | Gas Flag Description | Severity |
|---|-------|----------|----------|---------------------|----------|
| 1 | 50-01 | AdvanceModule | `_currentNudgeCost` | O(n) loop in reversals count. Exponential cost growth makes large n economically infeasible, but technically unbounded by code. | INFO |
| 2 | 50-01 | AdvanceModule | `_findRngWordCurrent` | O(30) worst case with mapping reads. Each cold mapping read ~2100 gas. Max ~63k gas in worst case. Emergency fallback only. | LOW |
| 3 | 50-02 | MintModule | `_handleAffiliate` | Multiple external calls to `affiliate.payAffiliate` (one for fresh ETH, one for claimable) -- cannot be batched due to different `isFreshEth` flags. | INFO |
| 4 | 50-02 | MintModule | `_handleAffiliateCombined` | Three separate `affiliate.payAffiliate` calls for Combined path -- necessarily separate due to `isFreshEth` flag differences. | INFO |
| 5 | 50-03 | JackpotModule | `runTerminalJackpot` | Fixed 100 iterations with 2 entropy steps + 1 winner selection each. Bounded and safe. PriceLookupLib prices cached in memory array. | INFO |
| 6 | 50-04 | JackpotModule | `_distributeETHJackpot` | `soloIdx` and `remainderIdx` computed identically via `JackpotBucketLib.soloBucketIndex(entropy)` -- minor redundancy, compiler likely optimizes. | LOW |
| 7 | 51-01 | EndgameModule | `_handleTransitionHousekeeping` | `_queueTicketRange` loops over 100 levels, performing storage read + potential write per level. O(100) SSTOREs worst case. Unavoidable for ticket distribution. | INFO |
| 8 | 51-02 | LootboxModule | `_resolveLootboxCommon` | `boonAmount` parameter passed by all 3 callers but discarded (dead parameter). No gas cost since it is calldata forwarding. | INFO |
| 9 | 51-02 | LootboxModule | `_deityBoonForSlot` (via loop) | `_deityDailySeed(day)` called inside loop 3 times, each reading `rngWordByDay[day]` from storage. Optimizer should handle this but explicit cache would be safer. | LOW |
| 10 | 51-02 | LootboxModule | `_claimableActivityScore` | `address(this)` external call for `playerActivityScore` -- more expensive than direct storage read but necessary since activity score computation lives on game contract, not module. | INFO |
| 11 | 51-02 | LootboxModule | `_assignDeityBoon` (lootbox boost) | Lootbox boost branch reads up to 3 active flags and writes up to 6 storage slots (3 active + 3 day fields). Most gas-intensive boon type. | LOW |
| 12 | 51-03 | LootboxModule | `_queueTicketsForWhalePass` | 100-iteration loop with external storage writes per iteration (~100 SSTORE operations). Inherently gas-heavy but unavoidable for whale pass design. | MEDIUM |
| 13 | 51-03 | LootboxModule | `_ethPrizeAmount` | Local variable `unit` always `1 ether` -- could be constant. Compiler likely optimizes away. | INFO |
| 14 | 51-04 | GameOverModule | `handleGameOverDrain` | `deityPassOwners` loop unbounded in theory but capped at 32 (symbol IDs 0-31). Worst case 32 iterations. | INFO |
| 15 | 51-04 | GameOverModule | `handleFinalSweep` | Can be called repeatedly; each call after first finds `available == 0` and returns early. Wasted gas on re-calls but harmless no-op. | INFO |
| 16 | 52-01 | WhaleModule | `purchaseWhaleBundle` | `_rewardWhaleBundleDgnrs` called `quantity` times in loop. For qty=100, 200+ external calls minimum. Gas-expensive but necessary since pool balance changes after each transfer. | MEDIUM |
| 17 | 52-01 | WhaleModule | `purchaseDeityPass` | `_queueTickets` called 100 times in loop, each writing `ticketsOwedPacked`. Similar cost to whale bundle. | MEDIUM |
| 18 | 52-01 | WhaleModule | `handleDeityPassTransfer` | Linear scan of `deityPassOwners` array to find `from`. Max 32 entries. O(32) worst case. | INFO |
| 19 | 52-01 | WhaleModule | `_rewardWhaleBundleDgnrs` | Called once per `quantity` in loop. For qty=100, up to 600 external calls total. Gas-heavy but functionally required. | MEDIUM |
| 20 | 52-01 | WhaleModule | `_deityPassPrice` | `IDegenerusGame(address(this)).playerActivityScore(buyer)` is external self-call. Gas-expensive but necessary since function lives on game contract. | LOW |
| 21 | 52-01 | WhaleModule | `_applyWhaleBundleStats` | Uses `BitPackingLib.setPacked` four times sequentially. Could be single bitmask operation but current approach is clearer. | INFO |
| 22 | 52-02 | DegeneretteModule | `_placeFullTicketBetsCore` | `jackpotResolutionActive` double-checked for ETH (already checked in caller). Redundant but defensive. Minimal gas cost. | INFO |
| 23 | 52-03 | BoonModule | `consumeCoinflipBoon` | Always clears `deityPurchaseBoostDay` even for lootbox-rolled boons where it is already 0. SSTORE to same value (no state change) = 100 gas. | INFO |
| 24 | 52-03 | BoonModule | `consumeDecimatorBoost` | Same redundancy as `consumeCoinflipBoon` -- always clears stamp day even when 0. | INFO |
| 25 | 52-03 | BoonModule | `checkAndClearExpiredBoon` | Lootbox boost blocks do not clear `lootboxBoonXXDay` on expiry -- stale stamp day occupies storage. Missed refund on clearing. Minor gas inefficiency. | LOW |
| 26 | 54-03 | DegenerusVault | `_isVaultOwner` | Two external calls per invocation (totalSupply + balanceOf on DegenerusVaultShare). Same-transaction calls to sub-contracts. | INFO |
| 27 | 54-03 | DegenerusVault | `burnCoin` / `burnEth` | Multiple external calls in payout path. Auto-claim of game winnings adds gas but is necessary for correctness. | INFO |
| 28 | 54-04 | DegenerusStonk | `_transfer` | External call to `game.level()` only when `lockedBalance[from] > 0` -- good optimization. | INFO |
| 29 | 54-04 | DegenerusStonk | `ethReserve` | Dead storage variable declared but never written. Occupies storage slot but is never read or written. | LOW |
| 30 | 54-04 | DegenerusStonk | `burn` | Multiple external calls (up to 8+ in worst case) for multi-asset proportional withdrawal. Necessary. | INFO |
| 31 | 54-04 | DegenerusStonk | `gamePurchase` | Two external calls to `quests.playerQuestStates` (before and after purchase). Could be avoided if quest reward is rare. | LOW |
| 32 | 54-04 | DegenerusStonk | `_lockedClaimableValues` | 4 external calls. Called multiple times per transaction in spend-check paths. | LOW |
| 33 | 55-01 | DegenerusDeityPass | `safeTransferFrom` (4-arg) | `data` parameter declared but never forwarded to `onERC721Received`. Minimal gas overhead (calldata is read-only). | INFO |
| 34 | 55-02 | DegenerusAffiliate | `setAffiliateSplitMode` | Event emitted even when mode unchanged (no-op write skipped but event always fires). Minor gas waste on redundant calls. | INFO |
| 35 | 55-02 | DegenerusAffiliate | `payAffiliate` | `vaultInfo` memory struct constructed even when not needed (valid stored code path). Minor gas cost. | INFO |
| 36 | 55-03 | DegenerusQuests | `handleLootboxOpen` | Always fetches `mintPrice` even if lootbox quest is not active. One external call even if progress < target. | LOW |
| 37 | 55-03 | DegenerusQuests | `_questSyncState` / `resetQuestStreak` | No event emitted on game-initiated streak reset (unlike player-initiated path). Intentional gas savings but inconsistent. | INFO |
| 38 | 55-03 | DegenerusQuests | `_questRollNewQuests` | Does not clear `flags` or `difficulty` fields on re-roll. Pre-existing values persist but are not used. Minor storage efficiency gap. | INFO |
| 39 | 56-01 | DegenerusAdmin | `onTokenTransfer` | External self-call `this._linkAmountToEth(amount)` to enable try/catch on view function. Additional gas from external call overhead but necessary since Solidity does not support try/catch on internal calls. | INFO |
| 40 | 56-01 | DegenerusAdmin | `_rewardMultiplier` | `delta2 >= 1e18` guard technically only reachable at exactly `subBal == 1000 ether` (already handled by prior check). Defensive and correct. | INFO |
| 41 | 56-01 | DegenerusAdmin | `_feedHealthy` | Two external calls (latestRoundData + decimals) with try/catch each. Slightly more gas than combining but ensures proper error isolation. Admin-only path. | INFO |
| 42 | 56-01 | DegenerusAdmin | `onlyOwner` modifier | External call on every modifier invocation. Necessary for dynamic ownership model. | INFO |
| 43 | 56-02 | WrappedWrappedXRP | `vaultMintAllowance` (view) | Duplicates public getter for `vaultAllowance` (already public). Technically redundant. | INFO |

---

## 4. Cross-Protocol Gas Patterns

Patterns that repeat across multiple contracts:

### Pattern 1: Defensive Zero-Address Checks (7 contracts)
BurnieCoin, WrappedWrappedXRP, DegenerusVaultShare, DegenerusStonk, DegenerusDeityPass, DegenerusAffiliate, and DegenerusQuests all include `address(0)` checks in `_mint`, `_burn`, or `_transfer`. These are standard ERC20/ERC721 safety patterns that cost ~22 gas each. Total protocol-wide cost: ~154 gas across all contracts per relevant call, but each check protects against catastrophic token loss.

**Verdict:** Intentional. Do not optimize.

### Pattern 2: Self-Call Access Control for Delegatecall Modules (5 functions in DegenerusGame)
`recordMint`, `runDecimatorJackpot`, `runTerminalJackpot`, `consumeDecClaim`, and `consumePurchaseBoost` all check `msg.sender != address(this)`. These functions are only called from delegatecall module context where msg.sender IS address(this). The checks prevent direct external calls that could bypass module logic.

**Verdict:** Critical security pattern. Do not optimize.

### Pattern 3: External Self-Calls for Cross-Module Data (3 contracts)
- WhaleModule: `IDegenerusGame(address(this)).playerActivityScore(buyer)` -- external self-call because function lives on game contract not module
- LootboxModule: `address(this)` external call for `playerActivityScore` -- same pattern
- DegenerusAdmin: `this._linkAmountToEth(amount)` -- external self-call for try/catch

**Estimated waste per call:** ~2600 gas (CALL overhead vs internal function). This pattern is architecturally necessary given the delegatecall module design. Activity score computation cannot be inlined into modules without duplicating complex logic.

**Verdict:** Architecturally necessary. No optimization possible without module redesign.

### Pattern 4: O(100) Ticket Queue Loops (3 functions)
- WhaleModule `purchaseWhaleBundle`: 100 `_queueTickets` calls per bundle
- WhaleModule `purchaseDeityPass`: 100 `_queueTickets` calls for ticket distribution
- EndgameModule `_handleTransitionHousekeeping`: `_queueTicketRange` over 100 levels

Each loop iteration performs 1 SLOAD + 1 potential SSTORE on `ticketsOwedPacked`. Estimated gas per loop: ~300k gas (100 cold SLOADs + potential writes). These are bounded by economics (whale bundles cost 2.4-4 ETH, deity passes cost 24+ ETH).

**Verdict:** Bounded by economics. Acceptable for high-value transactions.

### Pattern 5: Pool Balance Re-reads in Distribution Loops (WhaleModule)
`_rewardWhaleBundleDgnrs` called per quantity (up to 100x), each reading `dgnrs.poolBalance()` externally. The pool balance changes after each transfer, so re-reading is functionally necessary for accurate proportional distribution.

**Verdict:** Functionally necessary. Cannot cache.

### Pattern 6: Dead Storage Variables (1 instance)
DegenerusStonk declares `ethReserve` (storage slot) that is never read or written. This is a dead variable occupying one storage slot. No runtime gas cost but deployment gas for the slot.

**Verdict:** Minor cleanup opportunity. No runtime impact.

---

## 5. Summary Statistics

| Metric | Count |
|--------|-------|
| Total impossible conditions found | 19 |
| - Intentional (defensive) | 19 |
| - Unintentional (true waste) | 0 |
| Total redundant reads found | 12 |
| - Could save >1000 gas | 1 |
| - Minor (< 1000 gas) | 1 |
| - Already optimized / no savings | 10 |
| Prior audit gas flags aggregated | 43 |
| - HIGH severity | 0 |
| - MEDIUM severity | 4 |
| - LOW severity | 10 |
| - INFO severity | 29 |
| Total contracts scanned | 37 |
| Contracts with zero gas flags | 14 |

**Contracts with zero gas flags:** DegenerusVaultShare, Icons32Data, ContractAddresses, BitPackingLib, EntropyLib, GameTimeLib, PriceLookupLib, DegenerusGameEndgameModule (no actionable flags), DegenerusGameGameOverModule (no actionable flags beyond the informational ones above), DegenerusGameMintStreakUtils, DegenerusGamePayoutUtils, DeityBoonViewer, DegenerusJackpots (pure computation), JackpotBucketLib.

---

## 6. Recommendations (Flag-Only)

**Note:** This section documents optimization opportunities only. No code changes in this milestone.

### Top 5 Highest-Impact Gas Optimizations

| Rank | Location | Optimization | Est. Gas Save/Call | Call Frequency |
|------|----------|-------------|-------------------|----------------|
| 1 | WhaleModule `purchaseWhaleBundle` (qty=100) | Batch DGNRS pool reads across quantity iterations instead of per-iteration re-reads | Up to ~50k gas (100 saved warm STATICCALLs) | Low (whale bundles are rare, expensive transactions) |
| 2 | WhaleModule `purchaseDeityPass` / `purchaseWhaleBundle` | Batch `_queueTickets` writes with assembly to reduce per-iteration SSTORE overhead | Up to ~100k gas (100 iterations) | Low (whale/deity purchases) |
| 3 | LootboxModule `_deityBoonForSlot` loop | Cache `rngWordByDay[day]` before 3-iteration boon slot loop | ~200 gas | Medium (every lootbox open for deity pass holders) |
| 4 | DegenerusStonk `_lockedClaimableValues` | Cache `game.level()` result across consecutive spend-check calls within same transaction | ~2100 gas (cold) or ~100 gas (warm) | Medium (per DGNRS action) |
| 5 | DegenerusStonk `ethReserve` | Remove dead storage variable | 0 runtime savings, minor deployment savings | N/A (one-time) |

### Overall Assessment

The protocol is **exceptionally well-optimized** for gas:

1. **Zero unintentional impossible conditions** -- all 19 defensive checks are deliberate safety nets
2. **Near-zero redundant storage reads** -- local variable caching is consistently applied
3. **No HIGH severity gas flags** across 37 contracts and 400+ functions
4. **All MEDIUM severity flags** (4) are in whale/deity pass operations where the transaction value (2.4-24+ ETH) dwarfs the gas cost (~0.01-0.05 ETH)
5. **The viaIR optimizer with 200 runs** already handles many micro-optimizations (constant folding, immutable inlining, dead code elimination)

The total addressable gas savings across all identified optimizations is approximately **150k gas** in the worst case (100x whale bundle), which at 30 gwei gas price equals ~0.0045 ETH -- negligible compared to the 240+ ETH transaction value. No urgent optimization is needed.

