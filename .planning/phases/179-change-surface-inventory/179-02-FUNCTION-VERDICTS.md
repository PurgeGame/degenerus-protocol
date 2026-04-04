# Phase 179: Function-Level Verdicts -- v15.0 Delta

**Baseline:** e2cd1b2b (v15.0 Phase 167 final)
**HEAD:** df283518 (chore: clean up archived planning phases and update project state)
**Format:** Matches v15.0 Phase 165 findings (per D-03)
**Scope:** Every function added or logic-modified in contracts/ since v15.0

## Verdict Scale
- **SAFE** -- No security concern, behavior correct
- **INFO** -- Informational finding, no action needed
- **LOW** -- Minor concern, no immediate risk
- **MEDIUM** -- Moderate concern, should investigate
- **HIGH** -- Critical concern, must address

## Summary Table

| Contract | Functions Audited | SAFE | INFO | LOW+ |
|----------|-------------------|------|------|------|
| DegenerusGameEndgameModule.sol | 7 (deleted) | -- | -- | -- |
| DegenerusGameJackpotModule.sol | 10 | 10 | 0 | 0 |
| DegenerusGameAdvanceModule.sol | 5 | 5 | 0 | 0 |
| DegenerusGameStorage.sol | 6 | 6 | 0 | 0 |
| *HEAVY subtotal* | *28* | *21* | *0* | *0* |

---

## HEAVY Contracts

---

### DegenerusGameEndgameModule.sol -- DELETED
**Attribution:** v16.0-endgame-delete
**Status:** Entire file deleted (571 lines removed). Functions migrated or removed.

| Function | Disposition | Migration Target |
|----------|-------------|------------------|
| `rewardTopAffiliate(uint24)` | INLINED | AdvanceModule._rewardTopAffiliate:561 |
| `runRewardJackpots(uint24,uint256)` | MIGRATED | JackpotModule.runRewardJackpots:2516 |
| `_runBafJackpot(...)` | MIGRATED | JackpotModule._runBafJackpot:2635 |
| `_addClaimableEth(...)` | ABSORBED | JackpotModule (existing helper reused) |
| `_awardJackpotTickets(...)` | MIGRATED | JackpotModule._awardJackpotTickets:2727 |
| `_jackpotTicketRoll(...)` | MIGRATED | JackpotModule._jackpotTicketRoll:2777 |
| `claimWhalePass(address)` | MIGRATED | WhaleModule.claimWhalePass:456 |

No security verdicts apply to deleted code. All migrated functions are audited at their new locations below.

---

### 1. `runRewardJackpots(uint24, uint256)` -- JackpotModule:2516

**Type:** Added (migrated from EndgameModule)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Entry point for BAF and Decimator jackpot resolution during level transitions. Called via delegatecall from AdvanceModule._runRewardJackpots. Snapshots `baseFuturePool` at entry for rebuy reconciliation. BAF fires every 10 levels with percentage-based pool sizing (10%, 20% at level 50/x00). Decimator fires at x00 (30% of base) and at x5 except 95 (10% of remaining). The `futurePoolLocal` variable tracks local mutations while `_getFuturePrizePool()` re-read at line 2590 captures any storage-level rebuy writes from `_processAutoRebuy` during BAF/Decimator execution. The `rebuyDelta = _getFuturePrizePool() - baseFuturePool` correctly isolates auto-rebuy contributions from the local accounting. Commit to storage only when changed (saves SSTORE on non-jackpot levels). `claimablePool += claimableDelta` is safe because claimablePool tracks ETH actually credited to player balances. No reentrancy risk: all state updates complete before event emission. Access control: external but called only via delegatecall within GAME context.

---

### 2. `_runBafJackpot(uint256, uint24, uint256)` -- JackpotModule:2635

**Type:** Added (migrated from EndgameModule)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Distributes BAF jackpot to winners using a large/small split strategy. Large winners (>=5% of pool) get 50% ETH / 50% lootbox; small winners alternate 100% ETH (even index) or 100% lootbox (odd index). The `largeWinnerThreshold = poolWei / 20` correctly computes 5%. For large winners, `ethPortion = amount / 2` and `lootboxPortion = amount - ethPortion` avoids rounding loss. Lootbox portions route through `_awardJackpotTickets` (small) or `_queueWhalePassClaimCore` (large, >LOOTBOX_CLAIM_THRESHOLD) for gas safety. The `netSpend = poolWei - refund` correctly accounts for the external `jackpots.runBafJackpot` refund. `lootboxToFuture = lootboxTotal` correctly tracks ETH that stays in the future pool (lootbox tickets are backed by this ETH). Private function, called only from `runRewardJackpots`. No unchecked arithmetic on winner amounts.

---

### 3. `_awardJackpotTickets(address, uint256, uint24, uint256)` -- JackpotModule:2727

**Type:** Added (migrated from EndgameModule)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Unified ticket award function with three tiers: large (>5 ETH) defers to whale pass claim system, very small (<=0.5 ETH) gets single roll, medium (0.5-5 ETH) gets split into two rolls. The LOOTBOX_CLAIM_THRESHOLD and SMALL_LOOTBOX_THRESHOLD constants define tier boundaries. For the medium path, `halfAmount = amount / 2` and `secondAmount = amount - halfAmount` ensures no dust is lost on odd-wei amounts. The entropy state is correctly threaded through sequential calls via return values. Private function, no direct external access.

---

### 4. `_jackpotTicketRoll(address, uint256, uint24, uint256)` -- JackpotModule:2777

**Type:** Added (migrated from EndgameModule)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Resolves a single roll into ticket awards with probability-based level targeting: 30% at min level, 65% at +1 to +4, 5% at +5 to +50. Entropy is stepped via `EntropyLib.entropyStep` before use. The modular arithmetic `entropy - (entropyDiv100 * 100)` is equivalent to `entropy % 100` but avoids the Solidity modulo opcode (cheaper). Target level calculation uses `minTargetLevel + uint24(offset)` which is safe from overflow because game levels are bounded well below uint24 max. Ticket quantity calculated as `(amount * TICKET_SCALE) / targetPrice` correctly scales to the 2-decimal ticket system. Calls `_queueLootboxTickets` with `rngBypass=true` since this runs during level transition (RNG-locked window). Private function.

---

### 5. `payDailyJackpot(bool, uint24, uint256)` -- JackpotModule:305

**Type:** Modified (storage repack + carryover gas simplification)
**Attribution:** v16.0-repack, pre-v16.0-manual
**Verdict: SAFE**

**Analysis:**
Two changes: (1) All `currentPrizePool` direct reads replaced with `_getCurrentPrizePool()` and writes with `_setCurrentPrizePool()` for the uint128 repack. The helpers correctly widen/narrow between uint256 and uint128. (2) Carryover source selection simplified from the deleted `_selectCarryoverSourceOffset` / `_highestCarryoverSourceOffset` / `_hasActualTraitTickets` (82 lines) to an inline `keccak256(abi.encodePacked(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter)) % DAILY_CARRYOVER_MAX_OFFSET) + 1`. The new approach is simpler and deterministic: always picks a random offset in [1, DAILY_CARRYOVER_MAX_OFFSET] without checking trait ticket existence first. This may occasionally select source levels with empty trait buckets, but the downstream `_distributeTicketsToBucket` handles empty winners gracefully (zero tickets queued). Net simplification with no security regression.

---

### 6. `payDailyJackpotCoinAndTickets(uint256)` -- JackpotModule:530

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTickets` calls at lines 590, 604, 613, 621 now pass `true` as the rngBypass parameter. This is correct: `payDailyJackpotCoinAndTickets` runs during the jackpot phase when `rngLockedFlag` may be set, and these ticket queuing operations are internal to the daily jackpot flow (not player-initiated). The rngBypass=true prevents false `RngLocked` reverts on far-future ticket operations that are part of the game's own jackpot distribution. No other logic changes in this function.

---

### 7. `consolidatePrizePools(uint24, uint256)` -- JackpotModule:730

**Type:** Modified (storage repack helpers)
**Attribution:** v16.0-repack
**Verdict: SAFE**

**Analysis:**
All direct `currentPrizePool` reads/writes replaced with helper calls. `_getCurrentPrizePool() + _getNextPrizePool()` correctly merges next into current. `_getCurrentPrizePool() + moveWei` correctly adds future-to-current transfer at x00 levels. `_creditDgnrsCoinflip(_getCurrentPrizePool())` reads the updated value. The yield accumulator dump logic (50% of yieldAccumulator into futurePool at x00 levels) is unchanged. `_distributeYieldSurplus` reads `_getCurrentPrizePool()` which returns the consolidated value. All arithmetic is safe: pool values cannot exceed total contract balance which fits in uint128.

---

### 8. `_distributeYieldSurplus(uint256)` -- JackpotModule:763

**Type:** Modified (storage repack helper)
**Attribution:** v16.0-repack
**Verdict: SAFE**

**Analysis:**
Single change: `obligations` calculation at line 766 uses `_getCurrentPrizePool()` instead of direct `currentPrizePool` read. The helper returns `uint256(currentPrizePool)` which widens the uint128 to uint256 -- identical semantics to the prior direct read when the variable was uint256. The yield distribution logic (23% each to VAULT, sDGNRS, GNRUS, and yield accumulator) is unchanged.

---

### 9. `processTicketBatch(uint24)` -- JackpotModule:1693

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTickets` calls within `_processOneTicketEntry` (called from this function's loop) now pass `rngBypass=true`. This is correct: `processTicketBatch` runs during the advanceGame flow when RNG may be locked, and ticket redistribution during batch processing is an internal operation. The function signature itself is unchanged. No other logic modifications.

---

### 10. `payDailyCoinJackpot(uint24, uint256)` -- JackpotModule:2164

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTickets` call within `payDailyCoinJackpotAndTickets` (the Phase 2 split function at line 530) passes `rngBypass=true` for the same reason as entry 6 above. The standalone `payDailyCoinJackpot` function at line 2164 itself has no `_queueTickets` calls -- it distributes BURNIE coin, not tickets. The far-future coin award (`_awardFarFutureCoinJackpot`) and near-future trait-matched distribution (`_awardDailyCoinToTraitWinners`) are coin-only paths. No security-relevant changes to this function's logic.

---

### 11. `_rewardTopAffiliate(uint24)` -- AdvanceModule:561

**Type:** Added (inlined from EndgameModule delegatecall)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Previously a delegatecall to `EndgameModule.rewardTopAffiliate`, now inlined directly in AdvanceModule. Reads `affiliate.affiliateTop(lvl)` to find the top affiliate, transfers 1% (AFFILIATE_POOL_REWARD_BPS=100) of the affiliate pool balance to them via `dgnrs.transferFromPool`. Then snapshots 5% (AFFILIATE_DGNRS_LEVEL_BPS=500) of remaining pool into `levelDgnrsAllocation[lvl]` for per-affiliate claims. Called at line 1416 during `_requestRng` when `isTicketJackpotDay && !isRetry` -- before `level = lvl` increment. This timing is correct: affiliate scores routed to `lvl` during the purchase phase are frozen at this point. The `affiliate.affiliateTop` external call is to a trusted contract. No reentrancy risk: the `dgnrs.transferFromPool` call moves tokens within the staking contract, not ETH. Private function.

---

### 12. `_runRewardJackpots(uint24, uint256)` -- AdvanceModule:589

**Type:** Modified (delegatecall target changed)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Delegatecall target changed from `GAME_ENDGAME_MODULE` to `GAME_JACKPOT_MODULE`, and selector changed from `IDegenerusGameEndgameModule.runRewardJackpots` to `IDegenerusGameJackpotModule.runRewardJackpots`. The function signature `(uint24, uint256)` is identical, so ABI encoding is unchanged. The `_revertDelegate(data)` error propagation is the same pattern. Called at line 374 during level transition, after pool consolidation -- correct ordering (pool must be consolidated before jackpot resolution draws from it). Private function.

---

### 13. `_processPhaseTransition(uint24)` -- AdvanceModule:1294

**Type:** Modified (rngBypass parameter)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
Both `_queueTickets` calls (lines 1299-1303 for SDGNRS and 1305-1310 for VAULT) now pass `rngBypass=true` as the fourth parameter. These queue perpetual vault tickets at `purchaseLevel + 99` (far-future level). Since this runs during the phase transition when `rngLockedFlag` is set and `phaseTransitionActive` is true, the bypass is required to prevent false RngLocked reverts. Previously the old guard `!phaseTransitionActive` would have allowed these through; the new `rngBypass` parameter provides the same semantics with explicit intent. No other changes to function logic.

---

### 14. `_applyDailyRng(uint48, uint256)` -- AdvanceModule:1582

**Type:** Modified (revert on zero word)
**Attribution:** pre-v16.0-manual (gameover revert fix)
**Verdict: SAFE**

**Analysis:**
Changed `return 0` to `revert RngNotReady()` when the raw VRF word is not yet available. This is a correctness improvement: previously returning 0 would propagate a zero rngWord through the jackpot system, potentially causing zero-entropy winner selection. Now the function explicitly reverts, causing the advanceGame caller to receive `NotTimeYet`-equivalent behavior. The nudge logic (totalFlipReversals addition) and word storage (rngWordCurrent, rngWordByDay) are unchanged. Private function.

---

### 15. `_evaluateGameOverPossible(uint24, uint24)` -- AdvanceModule:1650

**Type:** Modified (no code change -- logic unchanged, only callers changed)
**Attribution:** v16.0-repack (contextual -- called from new locations)
**Verdict: SAFE**

**Analysis:**
The function body is unchanged. It computes whether projected future pool drip can cover the next-pool deficit. Called at two points: (1) FLAG-01 at line 307 during phase transition completion, and (2) FLAG-02 at line 341 during purchase-phase daily processing. Both call sites pass `(lvl, purchaseLevel)` correctly. The drip projection math (`_projectedDrip`, `_wadPow`) is identical to v15.0. No security change.

---

### 16. `_queueTickets(address, uint24, uint32, bool)` -- Storage:549

**Type:** Modified (rngBypass parameter replaces phaseTransitionActive guard)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
Signature changed from 3 parameters to 4 with `bool rngBypass` added. The guard at line 558 changed from `if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked()` to `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`. This is semantically equivalent for existing callers: all callers during phase transition or jackpot processing pass `rngBypass=true`, while external-facing paths (minting, whale purchases) pass `rngBypass=false`. The improvement is that bypass intent is now explicit at each call site rather than relying on global state. All 12+ call sites across the codebase have been updated with the correct boolean. Internal function.

---

### 17. `_queueTicketsScaled(address, uint24, uint32, bool)` -- Storage:578

**Type:** Modified (rngBypass parameter)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
Same rngBypass parameter addition as `_queueTickets`. Guard at line 587: `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`. All callers updated correctly. The remainder accumulation logic (`uint16 newRem`, TICKET_SCALE promotion) is unchanged. Internal function.

---

### 18. `_queueTicketRange(address, uint24, uint24, uint32, bool)` -- Storage:625

**Type:** Modified (rngBypass parameter)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
Same rngBypass parameter addition. Guard at line 637 within the loop: `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`. The `currentLevel` cache at line 633 (`level`) is read once outside the loop -- unchanged optimization. Callers: `_callRecordTicketPurchase` passes `false` (external mint path), `claimWhalePass` in WhaleModule passes `false` (player-initiated). Both are correct: these are user-facing operations that should respect the RNG lock. Internal function.

---

### 19. `_queueLootboxTickets(address, uint24, uint256, bool)` -- Storage:662

**Type:** Modified (rngBypass parameter)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
Thin wrapper that delegates to `_queueTicketsScaled` with the new rngBypass parameter. The `uint32(quantityScaled)` narrowing is unchanged (TICKET_SCALE ensures values fit). Called from `_jackpotTicketRoll` with `rngBypass=true` (jackpot context) and from lootbox module paths with `rngBypass=false` (player-initiated). Internal function.

---

### 20. `_getCurrentPrizePool()` -- Storage:788

**Type:** Added (new helper for storage repack)
**Attribution:** v16.0-repack
**Verdict: SAFE**

**Analysis:**
Returns `uint256(currentPrizePool)` -- widens the uint128 storage variable to uint256 for caller arithmetic compatibility. Pure read, no side effects. The widening is safe and lossless. Replaces all prior direct `currentPrizePool` reads across the codebase. Internal view function.

---

### 21. `_setCurrentPrizePool(uint256)` -- Storage:795

**Type:** Added (new helper for storage repack)
**Attribution:** v16.0-repack
**Verdict: SAFE**

**Analysis:**
Sets `currentPrizePool = uint128(val)`. The uint256-to-uint128 narrowing is safe because the NatSpec correctly notes that currentPrizePool can never exceed total ETH supply (~1.2e26 wei), well within uint128 max (~3.4e38 wei). All callers pass values derived from pool arithmetic that is bounded by contract balance. Replaces all prior direct `currentPrizePool = ...` writes. Internal function.

---

### Storage Layout Verification (Slot 0-1 Repack)

**Attribution:** v16.0-repack
**Verdict: SAFE**

**Analysis:**
Slot 0 changes: `poolConsolidationDone` removed (was byte [23:24]), all subsequent booleans shifted down by 1 byte position. Two fields added at the end: `ticketsFullyProcessed` at [30:31] and `gameOverPossible` at [31:32] (moved from Slot 1). Slot 0 is now exactly 32/32 bytes -- full.

Slot 1 changes: `ticketsFullyProcessed` removed (moved to Slot 0), `currentPrizePool` added as uint128 at bytes [8:24] (was Slot 2 as uint256). Old Slot 2 is eliminated. The storage layout NatSpec comments in the header match the actual variable declaration order. The `purchaseStartDay` (uint48, bytes [0:6]), `ticketWriteSlot` (uint8, [6:7]), `prizePoolFrozen` (bool, [7:8]) are unchanged. `currentPrizePool` (uint128, [8:24]) fills 16 bytes, leaving 8 bytes padding at [24:32]. Consistent.

The `poolConsolidationDone` removal is safe because it was a per-level guard that prevented double-consolidation. The new code structure (consolidation + reward jackpots as a single atomic block at line 370-374 of AdvanceModule) makes the flag unnecessary -- the operations run once per level transition, not gated by a flag.
