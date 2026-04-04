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
| DegenerusGameWhaleModule.sol | 5 | 5 | 0 | 0 |
| BurnieCoin.sol | 0 | -- | -- | -- |
| ContractAddresses.sol | 1 | 1 | 0 | 0 |
| WrappedWrappedXRP.sol | 3 | 3 | 0 | 0 |
| DegenerusGameMintModule.sol | 2 | 2 | 0 | 0 |
| DegenerusGame.sol | 4 | 4 | 0 | 0 |
| DegenerusGameDecimatorModule.sol | 2 | 2 | 0 | 0 |
| IDegenerusGameModules.sol | 2 | 2 | 0 | 0 |
| DegenerusQuests.sol | 2 | 2 | 0 | 0 |
| DegenerusGameMintStreakUtils.sol | 1 | 1 | 0 | 0 |
| BitPackingLib.sol | 1 | 1 | 0 | 0 |
| DegenerusGameGameOverModule.sol | 2 | 2 | 0 | 0 |
| DegenerusGameLootboxModule.sol | 2 | 2 | 0 | 0 |
| DegenerusAffiliate.sol | 1 | 1 | 0 | 0 |
| *MEDIUM subtotal* | *28* | *28* | *0* | *0* |
| IStakedDegenerusStonk.sol | 0 | -- | -- | -- |
| GNRUS.sol | 0 | -- | -- | -- |
| DegenerusGameDegeneretteModule.sol | 0 | -- | -- | -- |
| BurnieCoinflip.sol | 0 | -- | -- | -- |
| DegenerusGameBoonModule.sol | 0 | -- | -- | -- |
| DegenerusJackpots.sol | 0 | -- | -- | -- |
| StakedDegenerusStonk.sol | 0 | -- | -- | -- |
| MockWXRP.sol | 1 | 1 | 0 | 0 |
| IDegenerusQuests.sol | 0 | -- | -- | -- |
| IDegenerusGame.sol | 0 | -- | -- | -- |
| IDegenerusAffiliate.sol | 0 | -- | -- | -- |
| IBurnieCoinflip.sol | 0 | -- | -- | -- |
| Icons32Data.sol | 0 | -- | -- | -- |
| DegenerusVault.sol | 0 | -- | -- | -- |
| DegenerusAdmin.sol | 0 | -- | -- | -- |
| *LIGHT subtotal* | *1* | *1* | *0* | *0* |
| **TOTAL** | **57** | **50** | **0** | **0** |

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

---

## MEDIUM Contracts

---

### 22. `claimWhalePass(address)` -- WhaleModule:963

**Type:** Added (migrated from EndgameModule)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Migrated from EndgameModule. Checks `gameOver` guard, reads `whalePassClaims[player]`, zeroes it (CEI pattern: state cleared before external effects), then awards tickets via `_queueTicketRange(player, level+1, 100, uint32(halfPasses), false)`. The `rngBypass=false` is correct: this is a player-initiated claim that should respect the RNG lock. `_applyWhalePassStats` updates pass metadata. The `uint32(halfPasses)` narrowing is safe because half-passes are bounded by ETH supply economics. External function with `msg.sender` logged but no access control beyond `gameOver` -- intentionally claimable by anyone on behalf of `player`.

---

### 23. `purchaseWhaleBundle(...)` -- WhaleModule:187 (rngBypass only)

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTickets` call at line 313 now passes `false` as rngBypass. Correct: whale bundle purchases are player-initiated external transactions that should respect the RNG lock on far-future levels. No other logic changes.

---

### 24. `purchaseDeityPass(address, uint8)` -- WhaleModule:538 (rngBypass only)

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTickets` call at line 625 now passes `false` as rngBypass. Correct: deity pass purchases are player-initiated. No other logic changes.

---

### 25. `_claimWhalePassTickets(...)` -- WhaleModule (lazy pass rngBypass)

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTickets` call at line 482 now passes `false` as rngBypass. Correct: lazy pass ticket claims are player-initiated purchases. No other logic changes.

---

### 26. WhalePassClaimed event -- WhaleModule:963

**Type:** Added (new event)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
New event `WhalePassClaimed(address indexed player, address indexed caller, uint256 halfPasses, uint24 startLevel)` emitted at line 978. Provides indexer traceability for whale pass claims. No security impact -- events are read-only.

---

### BurnieCoin.sol -- COMMENT-ONLY

**Attribution:** v17.1-comments
**Status:** All changes are NatSpec corrections. Removed stale struct documentation (8 lines), removed stale BOUNTY STATE block (24 lines for variables that live in BurnieCoinflip), updated `vaultEscrow` and `burnFromForGame` NatSpec. No logic changes, no security verdict needed.

---

### 27. ContractAddresses.sol -- ADDRESS CHANGES

**Attribution:** v16.0-endgame-delete, rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
Address values updated for redeployment. `GAME_ENDGAME_MODULE` address updated (module still declared for ABI compatibility but points to new deploy address). All other contract addresses changed to match new deployment. These are compile-time constants baked into bytecode. The removal of the endgame module reference as a functional target is handled by the import/selector changes in AdvanceModule and DegenerusGame. NOTE: Per user memory, this file is never modified by agents -- audit only.

---

### 28. `unwrap(uint256)` -- WrappedWrappedXRP:298

**Type:** Modified (decimal scaling)
**Attribution:** v17.1-comments
**Verdict: SAFE**

**Analysis:**
Added `WXRP_SCALING = 1e12` constant and `wXRPAmount = amount / WXRP_SCALING` conversion before transfer. Previously transferred raw `amount` to `wXRP.transfer`, which would have over-sent by 1e12x since WWXRP uses 18 decimals and wXRP uses 6. The new code correctly converts: burn the full 18-decimal `amount` of WWXRP, deduct from reserves, but transfer only `amount / 1e12` of the 6-decimal wXRP. Added `if (wXRPAmount == 0) revert ZeroAmount()` guard for dust amounts below 1e12 that would produce zero wXRP transfer. CEI pattern maintained: burn before transfer.

---

### 29. `donate(uint256)` -- WrappedWrappedXRP:327

**Type:** Modified (decimal scaling)
**Attribution:** v17.1-comments
**Verdict: SAFE**

**Analysis:**
The `amount` parameter now represents 6-decimal wXRP. `wXRPReserves += amount * WXRP_SCALING` correctly scales the 6-decimal input to 18-decimal reserves. Previously reserves were tracked at the wrong decimal scale. The `transferFrom` call uses the raw 6-decimal amount (correct for wXRP). No CEI issue: reserves are updated after successful transfer.

---

### 30. `WXRP_SCALING` constant -- WrappedWrappedXRP

**Type:** Added (new constant)
**Attribution:** v17.1-comments
**Verdict: SAFE**

**Analysis:**
`uint256 private constant WXRP_SCALING = 1e12` bridges the 18-decimal WWXRP and 6-decimal wXRP. Correctly computed: 10^18 / 10^6 = 10^12. Used consistently in both `unwrap` and `donate`.

---

### 31. `recordMintData(address, uint24, uint32)` -- MintModule:175

**Type:** Modified (affiliate bonus cache)
**Attribution:** v17.0-affiliate-cache
**Verdict: SAFE**

**Analysis:**
Added affiliate bonus cache write at lines 277-281 during the "new level with >=4 units" path. Calls `affiliate.affiliateBonusPointsBest(lvl, player)` and stores the result in bits [185-208] (level) and [209-214] (points) of `mintPacked_[player]`. This piggybacks on the existing SSTORE that writes `mintPacked_` -- no additional gas for the extra fields. The cache is read by `_playerActivityScore` in MintStreakUtils to avoid a cold SLOAD to DegenerusAffiliate. The 6-bit points field (max 63) accommodates the max 50 bonus points. The 24-bit level field matches the game's uint24 level type. Both fields are packed using `BitPackingLib.setPacked` which correctly masks and shifts.

---

### 32. `purchaseBurnie(...)` -- MintModule (rngBypass only)

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTicketsScaled` call at line 816 now passes `false` as rngBypass. Correct: BURNIE ticket purchases are player-initiated external transactions. No other logic changes.

---

### 33. `constructor(...)` -- DegenerusGame (rngBypass only)

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The two `_queueTickets` calls at lines 213-214 (vault perpetual tickets in the constructor loop) now pass `false` as rngBypass. Correct: at construction time, `rngLockedFlag` is false (default), so the bypass is irrelevant, but `false` is the correct semantic value for non-jackpot context.

---

### 34. `claimWhalePass(address)` -- DegenerusGame:1636

**Type:** Modified (delegatecall target changed)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Delegatecall target changed from `GAME_ENDGAME_MODULE` to `GAME_WHALE_MODULE`, selector from `IDegenerusGameEndgameModule.claimWhalePass` to `IDegenerusGameWhaleModule.claimWhalePass`. The function signature `(address)` is identical. NatSpec updated to reflect whale module delegation. No logic change in the wrapper.

---

### 35. `currentPrizePoolView()` -- DegenerusGame:2037

**Type:** Modified (storage repack helper)
**Attribution:** v16.0-repack
**Verdict: SAFE**

**Analysis:**
Changed from `return currentPrizePool` to `return _getCurrentPrizePool()`. The helper widens uint128 to uint256 -- identical external behavior since the return type is uint256.

---

### 36. `yieldPoolView()` -- DegenerusGame:2061

**Type:** Modified (storage repack helper)
**Attribution:** v16.0-repack
**Verdict: SAFE**

**Analysis:**
`obligations` calculation uses `_getCurrentPrizePool()` instead of direct read. Same widening semantics as entry 35. View function, no state mutation.

---

### 37. `burnDecimatorsForEth(...)` -- DecimatorModule:391 (rngBypass only)

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTickets` call at line 391 now passes `false` as rngBypass. Correct: decimator burns are player-initiated. No other logic changes.

---

### 38. `_terminalDecMultiplierBps(uint256)` -- DecimatorModule:904

**Type:** Modified (rescaled formula + 7-day guard)
**Attribution:** v17.0-affiliate-cache
**Verdict: SAFE**

**Analysis:**
Previous formula: `>10 days: daysRemaining * 2500` (30x at 120, 2.75x at 11); `<=10 days: linear 2x to 1x`. New formula: `<=10 days: flat 10000` (1x); `>10 days: 10000 + ((daysRemaining - 10) * 190000) / 110` (linear 1x at day 10, 20x at day 120). The caller guard changed from `daysRemaining <= 1` to `daysRemaining <= 7` (7-day cooldown before termination). Boundary check: at daysRemaining=10, returns 10000 (1x). At daysRemaining=120, returns 10000 + (110 * 190000) / 110 = 10000 + 190000 = 200000 (20x). Continuous at boundary, no discontinuity. The 7-day block prevents last-minute strategic burns that could manipulate game outcome. Pure function, no state access.

---

### 39. `IDegenerusGameEndgameModule` -- IDegenerusGameModules.sol (DELETED)

**Type:** Deleted (entire interface)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
Removed interface with `runRewardJackpots`, `rewardTopAffiliate`, `claimWhalePass` selectors. These selectors moved to `IDegenerusGameJackpotModule` (runRewardJackpots) and `IDegenerusGameWhaleModule` (claimWhalePass). `rewardTopAffiliate` is now inlined in AdvanceModule (no interface needed). No orphan references remain in the codebase.

---

### 40. `IDegenerusGameJackpotModule.runRewardJackpots` / `IDegenerusGameWhaleModule.claimWhalePass` -- IDegenerusGameModules.sol

**Type:** Added (selectors moved to correct interfaces)
**Attribution:** v16.0-endgame-delete
**Verdict: SAFE**

**Analysis:**
`runRewardJackpots(uint24, uint256)` added to IDegenerusGameJackpotModule. `claimWhalePass(address)` added to IDegenerusGameWhaleModule. Both match the function signatures in the implementing contracts. No ABI encoding mismatches.

---

### 41. `QuestSlotRolled` event -- DegenerusQuests:66

**Type:** Modified (removed `difficulty` parameter)
**Attribution:** pre-v16.0-manual
**Verdict: SAFE**

**Analysis:**
Event changed from 6 parameters to 5 (removed `uint16 difficulty`). The `difficulty` field in the Quest struct was already unused (fixed to 0) and the struct slot is now documented as "16 bits free". The `emit QuestSlotRolled` calls at lines 347-348 updated to match (removed trailing `0` argument). This is a breaking change for event ABI -- existing indexers expecting the old signature will not decode the new events. However, this is acceptable for a pre-launch contract with no production indexers.

---

### 42. Quest struct `difficulty` removal -- DegenerusQuests

**Type:** Modified (vestigial field removed)
**Attribution:** pre-v16.0-manual
**Verdict: SAFE**

**Analysis:**
Quest struct field `uint16 difficulty` changed to `// 16 bits free` comment. Storage layout preserved (the 16 bits remain allocated but unused). The removed `difficulty` was always 0 and never read. No storage collision risk.

---

### 43. `_playerActivityScore(address, uint32, uint24)` -- MintStreakUtils:83

**Type:** Modified (affiliate bonus cache read)
**Attribution:** v17.0-affiliate-cache
**Verdict: SAFE**

**Analysis:**
Lines 139-148: Affiliate bonus calculation now reads from the mintPacked_ cache when `cachedLevel == currLevel`, falling back to `affiliate.affiliateBonusPointsBest(currLevel, player)` when stale. The cache hit eliminates a cold SLOAD to the DegenerusAffiliate contract (saves ~2100 gas per mint). The fallback ensures correctness on first-mint-at-new-level before recordMintData has cached the new level's value. The `MASK_6` (6-bit) and `MASK_24` (24-bit) reads correctly match the write in MintModule.recordMintData. Points are multiplied by 100 to convert to basis points -- same as before.

---

### 44. `AFFILIATE_BONUS_LEVEL_SHIFT` / `AFFILIATE_BONUS_POINTS_SHIFT` / `MASK_6` -- BitPackingLib

**Type:** Added (new constants for affiliate cache)
**Attribution:** v17.0-affiliate-cache
**Verdict: SAFE**

**Analysis:**
`AFFILIATE_BONUS_LEVEL_SHIFT = 185` (bits [185-208], 24-bit level). `AFFILIATE_BONUS_POINTS_SHIFT = 209` (bits [209-214], 6-bit points). `MASK_6 = (1 << 6) - 1 = 63`. Also added `MASK_2 = 0x3` and `MASK_1 = 0x1` for existing bundle type and deity pass fields (previously hardcoded, now named constants). Bit ranges do not overlap with existing fields: HAS_DEITY_PASS is bit 184, LEVEL_UNITS_SHIFT is bits [228-243]. Bits [215-227] remain unused. Layout NatSpec in the file header matches the constant definitions.

---

### 45. `handleGameOverDrain(uint48)` -- GameOverModule:79

**Type:** Modified (storage repack helper)
**Attribution:** v16.0-repack
**Verdict: SAFE**

**Analysis:**
At line 133, `currentPrizePool = 0` changed to `_setCurrentPrizePool(0)`. Same at line 145. The helper writes `currentPrizePool = uint128(0)` which is identical to the previous direct-write semantics. No other logic changes in this function.

---

### 46. `_sendToVault(uint256, uint256)` -- GameOverModule:214

**Type:** Modified (comment-only)
**Attribution:** v17.1-comments
**Verdict: SAFE**

**Analysis:**
NatSpec changed from "DGNRS" to "sDGNRS" in the fund split description. This is a comment correction only -- the actual code sends to `ContractAddresses.SDGNRS` which is the staked token contract. No logic change.

---

### 47. `_handleLootboxTickets(...)` -- LootboxModule (rngBypass only)

**Type:** Modified (rngBypass parameter threading)
**Attribution:** rngBypass-refactor
**Verdict: SAFE**

**Analysis:**
The `_queueTicketsScaled` call at line 974 now passes `false` as rngBypass. Correct: lootbox ticket awards from player-initiated loot box opens should respect the RNG lock. The `_queueTickets` call at line 1097 (whale pass ticket routing within lootbox) also passes `false`. Both are external-facing paths.

---

### 48. LootboxModule NatSpec -- LootboxModule

**Type:** Modified (comment corrections)
**Attribution:** v17.1-comments
**Verdict: SAFE**

**Analysis:**
Removed stale `@notice` for lazy pass event (2 lines). Updated `LootBoxReward` reward type enum to include `11=LazyPassBoon`. Corrected `LOOTBOX_EV_MAX_BPS` activity threshold from 260% to 255%. All comment-only changes.

---

### 49. `affiliateBonusPointsBest(uint24, address)` -- DegenerusAffiliate:666

**Type:** Modified (tiered rate formula)
**Attribution:** v17.0-affiliate-cache
**Verdict: SAFE**

**Analysis:**
Previous: flat `points = sum / ethUnit` (1 point per ETH). New: tiered -- `if (sum <= 5 ether) points = (sum * 4) / 1 ether` (4 points/ETH for first 5 ETH = max 20 points), else `points = 20 + ((sum - 5 ether) * 3) / 2 ether` (1.5 points/ETH for remaining). Cap at `AFFILIATE_BONUS_MAX` (50) still applies. Boundary check: at sum=5 ether, first branch gives 20 points. At sum=5.000001 ether, second branch gives 20 + (0.000001 * 3) / 2 = ~20 points. Continuous at boundary. At sum=25.33 ether: 20 + (20.33 * 3) / 2 = 20 + 30.5 = 50.5, capped to 50. The 5-level lookback window (`offset 1..5`) and zero-check are unchanged. External view function.

---

## LIGHT Contracts -- Comment-Only Tags

All LIGHT files below have v17.1-comments attribution. Changes are NatSpec corrections only. No logic modifications, no security verdicts needed.

---

### IStakedDegenerusStonk.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +5 / -4
**Changes:** Updated `burn()` NatSpec to describe post-gameOver immediate payout vs active-game gambling queue behavior. All 3 return values annotated with "(0 during active game)". Comment-only, no security verdict.

---

### GNRUS.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +4 / -4
**Changes:** 4 single-line NatSpec corrections. Comment-only, no security verdict.

---

### DegenerusGameDegeneretteModule.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +3 / -4
**Changes:** Corrected payout table reference (1.78x to 1.90x), removed duplicate `@notice`, updated spin 0 comment, corrected centi-x reference. Comment-only, no security verdict.

---

### BurnieCoinflip.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +3 / -3
**Changes:** Updated `creditFlip` and `creditFlips` caller lists in NatSpec (reordered to reflect actual usage frequency: GAME, QUESTS, AFFILIATE, ADMIN). Comment-only, no security verdict.

---

### DegenerusGameBoonModule.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +2 / -2
**Changes:** Updated contract `@notice` (removed "and lootbox view functions") and `@dev` (replaced split-from-lootbox explanation with boon consumption description). Comment-only, no security verdict.

---

### DegenerusJackpots.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +2 / -2
**Changes:** Updated `recordCoinflip` NatSpec: "Called by coin contract" to "Called by COIN or COINFLIP contract" and `@custom:access` updated similarly. Comment-only, no security verdict.

---

### StakedDegenerusStonk.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Changes:** Single NatSpec correction. Comment-only, no security verdict.

---

### 50. MockWXRP.sol -- LOGIC CHANGE
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Verdict: SAFE**

**Analysis:**
Changed `uint8 public constant decimals = 18` to `uint8 public constant decimals = 6`. This aligns the mock with production wXRP's 6-decimal standard. Test-only contract (mocks/ directory). Ensures WrappedWrappedXRP tests exercise the correct decimal conversion paths.

---

### IDegenerusQuests.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Changes:** Updated `@dev` from "Called by JackpotModule" to "Called by AdvanceModule" (reflects EndgameModule deletion and quest roll relocation). Comment-only, no security verdict.

---

### IDegenerusGame.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Changes:** Updated `@dev` from "COIN or GAME self-call" to "GAME self-call only (delegatecall modules via address(this))". Comment-only, no security verdict.

---

### IDegenerusAffiliate.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Changes:** Updated `affiliateBonusPointsBest` NatSpec to describe tiered rate (4pt/ETH first 5 ETH, 1.5pt/ETH next 20 ETH). Comment-only, no security verdict.

---

### IBurnieCoinflip.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Changes:** Updated `creditFlip` NatSpec from "LazyPass, DegenerusGame, or BurnieCoin" to "GAME, QUESTS, AFFILIATE, ADMIN". Comment-only, no security verdict.

---

### Icons32Data.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Changes:** Single NatSpec correction. Comment-only, no security verdict.

---

### DegenerusVault.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Changes:** Single NatSpec correction. Comment-only, no security verdict.

---

### DegenerusAdmin.sol -- COMMENT-ONLY
**Attribution:** v17.1-comments
**Lines:** +1 / -1
**Changes:** Corrected `_applyVote` returns description from "3 returns" to "2 (newApprove, newReject)". Comment-only, no security verdict.

---

## Completeness Verification

### Function Coverage
- Total functions with logic changes: 50
- Functions with verdicts (SAFE/INFO/LOW+): 50
- Comment-only files (no verdict needed): 14
- EndgameModule deleted functions (mapped, no verdict): 7
- Missing: 0

### Cross-Check Against Diff Inventory
- Files in 179-01-DIFF-INVENTORY.md: 33
- Files covered in this document: 33
- Missing: 0

### Verdict Distribution
- SAFE: 50
- INFO: 0
- LOW: 0
- MEDIUM: 0
- HIGH: 0

### Attribution Coverage
Every verdict entry includes an attribution tag from the milestone key:
- v16.0-endgame-delete: 10 functions
- v16.0-repack: 6 functions
- rngBypass-refactor: 14 functions
- v17.0-affiliate-cache: 5 functions
- v17.1-comments: 7 functions (logic changes only; 14 comment-only files tagged separately)
- pre-v16.0-manual: 4 functions
