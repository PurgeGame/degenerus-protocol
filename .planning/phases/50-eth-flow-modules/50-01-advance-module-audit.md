# DegenerusGameAdvanceModule.sol -- Function-Level Audit

**Contract:** DegenerusGameAdvanceModule
**File:** contracts/modules/DegenerusGameAdvanceModule.sol
**Lines:** 1277
**Solidity:** 0.8.34
**Inherits:** DegenerusGameStorage
**Called via:** delegatecall from DegenerusGame
**Audit date:** 2026-03-07

## Summary

DegenerusGameAdvanceModule is the state-machine engine for the Degenerus game protocol. It manages:

1. **Game advancement** (`advanceGame`) -- the main daily tick that processes jackpots, level transitions, prize pool consolidation, and phase transitions (purchase -> jackpot -> purchase).
2. **VRF lifecycle** -- requesting Chainlink VRF V2.5 random words, handling fulfillment callbacks, timeout retries, and game-over entropy fallbacks.
3. **RNG nudging** (`reverseFlip`) -- allowing players to burn BURNIE to shift the pending VRF word.
4. **Lootbox RNG** (`requestLootboxRng`) -- mid-day VRF requests for lootbox resolution.
5. **VRF admin** -- one-time wiring and emergency coordinator rotation.

The module executes via delegatecall from DegenerusGame, sharing the canonical storage layout defined in DegenerusGameStorage. It further delegates into specialized sub-modules (JackpotModule, EndgameModule, MintModule, GameOverModule) for complex operations.

---

## Function Audit

### External / Public Functions

---

### `advanceGame()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function advanceGame() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `msg.sender` (caller for mint-gate and bounty)
- `block.timestamp` (ts)
- `_simulatedDayIndexAt(ts)` -> `day` (inherited from GameTimeLib via Storage)
- `jackpotPhaseFlag` (inJackpot)
- `level` (lvl)
- `lastPurchaseDay` (lastPurchase)
- `rngLockedFlag` (used in purchaseLevel calculation)
- `dailyIdx` (passed to _handleGameOverPath and _enforceDailyMintGate)
- `levelStartTime` (passed to _handleGameOverPath)
- `phaseTransitionActive` (phase transition state)
- `jackpotCounter` (jackpot day counter)
- `dailyJackpotCoinTicketsPending` (split jackpot pending flag)
- `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor` (resume state)
- `rngWordByDay[day]` (via rngGate)
- `rngWordCurrent`, `rngRequestTime` (via rngGate)
- `nextPrizePool`, `levelPrizePool[purchaseLevel - 1]` (target check)
- `poolConsolidationDone` (consolidation guard)
- `ticketCursor`, `ticketLevel` (via _runProcessTicketBatch)
- `lastDailyJackpotLevel` (resume level for split ETH)
- `lootboxPresaleActive`, `lootboxPresaleMintEth` (presale auto-end)

**State Writes:**
- `lastPurchaseDay = true` (when nextPrizePool >= target)
- `compressedJackpotFlag = (day - purchaseStartDay <= 2)` (compressed mode check)
- `levelPrizePool[purchaseLevel] = nextPrizePool` (prize pool snapshot)
- `poolConsolidationDone = true` (consolidation guard)
- `lootboxPresaleActive = false` (presale auto-end)
- `earlyBurnPercent = 0` (reset at jackpot entry)
- `jackpotPhaseFlag = true` (transition to jackpot)
- `decWindowOpen = true` (open decimator at x4/x99 levels)
- `poolConsolidationDone = false` (reset for next cycle)
- `lastPurchaseDay = false` (reset at jackpot entry)
- `levelStartTime = ts` (new level start time)
- `phaseTransitionActive = false` (transition complete)
- `purchaseStartDay = day` (new purchase start)
- `jackpotPhaseFlag = false` (back to purchase)
- Via `_unlockRng(day)`: `dailyIdx = day`, `rngLockedFlag = false`, `rngWordCurrent = 0`, `vrfRequestId = 0`, `rngRequestTime = 0`
- Via delegatecall sub-modules: various prize pool, ticket, jackpot state

**Callers:**
- External callers (any address, subject to mint-gate). Called via delegatecall from DegenerusGame.

**Callees:**
- `_simulatedDayIndexAt(ts)` (inherited helper)
- `_handleGameOverPath(ts, day, levelStartTime, lvl, lastPurchase, dailyIdx)` (private)
- `_enforceDailyMintGate(caller, purchaseLevel, dailyIdx)` (private)
- `rngGate(ts, day, purchaseLevel, lastPurchase)` (internal)
- `_processPhaseTransition(purchaseLevel)` (private)
- `_unlockRng(day)` (private)
- `_prepareFinalDayFutureTickets(lvl)` (private)
- `_runProcessTicketBatch(purchaseLevel)` (private)
- `payDailyJackpot(isDaily, lvl, rngWord)` (internal, delegatecall to JackpotModule)
- `_payDailyCoinJackpot(purchaseLevel, rngWord)` (private, delegatecall to JackpotModule)
- `_applyTimeBasedFutureTake(ts, purchaseLevel, rngWord)` (private)
- `_consolidatePrizePools(purchaseLevel, rngWord)` (private, delegatecall to JackpotModule)
- `_drawDownFuturePrizePool(lvl)` (private)
- `_processFutureTicketBatch(nextLevel)` (private, delegatecall to MintModule)
- `payDailyJackpotCoinAndTickets(rngWord)` (internal, delegatecall to JackpotModule)
- `_awardFinalDayDgnrsReward(lvl, rngWord)` (private, delegatecall to JackpotModule)
- `_rewardTopAffiliate(lvl)` (private, delegatecall to EndgameModule)
- `_runRewardJackpots(lvl, rngWord)` (private, delegatecall to EndgameModule)
- `_endPhase()` (private)
- `coin.creditFlip(caller, ADVANCE_BOUNTY)` (external call to DegenerusCoin)

**ETH Flow:**
- No direct ETH transfers in `advanceGame` itself.
- ETH is moved indirectly through delegatecall sub-modules:
  - `payDailyJackpot` -> currentPrizePool/futurePrizePool -> claimableWinnings (player credits)
  - `_consolidatePrizePools` -> nextPrizePool -> currentPrizePool, futurePrizePool adjustments
  - `_applyTimeBasedFutureTake` -> nextPrizePool -> futurePrizePool (time-based skim)
  - `_drawDownFuturePrizePool` -> futurePrizePool -> nextPrizePool (15% release)
  - `_autoStakeExcessEth` (via _processPhaseTransition) -> excess ETH -> stETH via Lido

**Invariants:**
- `advanceGame` cannot be called twice within the same day (reverts `NotTimeYet` if `day == dailyIdx`)
- Mint-gate: caller must have minted today (with time-based and pass-based bypasses)
- Game-over path takes priority and returns early
- Phase transitions are mutually exclusive: purchase phase XOR jackpot phase
- `poolConsolidationDone` prevents double consolidation
- Level increment happens at RNG request time (not at advance time) to prevent manipulation
- `jackpotCounter` caps at `JACKPOT_LEVEL_CAP = 5` before triggering phase end
- ADVANCE_BOUNTY (500 BURNIE flip credit) always awarded to caller after processing

**NatSpec Accuracy:**
- Line 118-119: NatSpec says "Called daily to process jackpots, mints, and phase transitions" -- ACCURATE. It is the daily tick function.
- NatSpec says "Caller receives ADVANCE_BOUNTY (500 BURNIE) as flip credit" -- ACCURATE. `coin.creditFlip(caller, ADVANCE_BOUNTY)` always runs at line 293.

**Gas Flags:**
- The `do { ... } while(false)` pattern is a clean single-pass state machine with `break` for early exits. No wasted iteration.
- `purchaseLevel` computation reads `rngLockedFlag` even when `lastPurchase` is false (minor: the branch is only taken when both are true, so no wasted SLOAD in practice due to short-circuit).
- `_enforceDailyMintGate` uses `view` and returns early on common paths (no external call unless vault ownership check).
- Multiple delegatecalls in the final jackpot day path (`_awardFinalDayDgnrsReward`, `_rewardTopAffiliate`, `_runRewardJackpots`, `_endPhase`) could approach gas limits, but the split-jackpot mechanism across calls mitigates this.

**Verdict:** CORRECT

---

### `wireVrf(address, uint256, bytes32)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function wireVrf(address coordinator_, uint256 subId, bytes32 keyHash_) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `coordinator_` (address): VRF coordinator address; `subId` (uint256): VRF subscription ID; `keyHash_` (bytes32): gas lane key hash |
| **Returns** | None |

**State Reads:**
- `msg.sender` (access control)
- `vrfCoordinator` (current coordinator for event)

**State Writes:**
- `vrfCoordinator = IVRFCoordinator(coordinator_)`
- `vrfSubscriptionId = subId`
- `vrfKeyHash = keyHash_`

**Callers:**
- DegenerusAdmin contract only (via delegatecall from DegenerusGame). Access restricted: `msg.sender != ContractAddresses.ADMIN` reverts `E()`.

**Callees:**
- None

**ETH Flow:**
- None. Pure configuration function.

**Invariants:**
- Only ContractAddresses.ADMIN can call. There is no one-time guard; ADMIN can re-call to overwrite config. This is documented in NatSpec: "Overwrites any existing config on each call."
- No validation of coordinator_ being non-zero or a valid contract address. This is acceptable since ADMIN is a trusted, immutable contract.

**NatSpec Accuracy:**
- NatSpec says "One-time wiring" but code allows repeated calls. However, the `@dev` clarifies "Overwrites any existing config on each call." The `@notice` is slightly misleading but the `@dev` corrects it. MINOR DISCREPANCY: "One-time" in `@notice` vs "Overwrites on each call" in `@dev`.
- Signature in interface declares `wireVrf(address, uint256, bytes32)` -- matches implementation.

**Gas Flags:**
- Efficient: 3 SSTOREs + 1 SLOAD (for event). Minimal.

**Verdict:** CORRECT. Note: NatSpec `@notice` says "One-time" but it is re-callable. The `@dev` clarifies this adequately.

---

### `requestLootboxRng()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function requestLootboxRng() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `block.timestamp` (nowTs)
- `_simulatedDayIndexAt(nowTs)` (currentDay)
- `_simulatedDayIndexAt(nowTs + 15 minutes)` (pre-reset window check)
- `rngWordByDay[currentDay]` (daily RNG consumed check)
- `rngLockedFlag` (daily lock check)
- `rngRequestTime` (pending request check)
- `vrfCoordinator`, `vrfSubscriptionId` (LINK balance query)
- `vrfKeyHash` (VRF request config)
- `lootboxRngPendingEth`, `lootboxRngPendingBurnie` (threshold check)
- `price` (BURNIE-to-ETH conversion for threshold)
- `lootboxRngThreshold` (configurable threshold)
- `lootboxRngIndex` (via _reserveLootboxRngIndex)

**State Writes:**
- Via `_reserveLootboxRngIndex(id)`:
  - `lootboxRngRequestIndexById[requestId] = lootboxRngIndex`
  - `lootboxRngIndex = index + 1`
  - `lootboxRngPendingEth = 0`
  - `lootboxRngPendingBurnie = 0`
- `vrfRequestId = id`
- `rngWordCurrent = 0`
- `rngRequestTime = uint48(block.timestamp)`

**Callers:**
- Any external caller. No access control beyond the gate checks (timing, daily RNG consumed, not locked, not pending, threshold met, LINK balance).

**Callees:**
- `_simulatedDayIndexAt(nowTs)` (view helper)
- `_simulatedDayIndexAt(nowTs + 15 minutes)` (view helper)
- `vrfCoordinator.getSubscription(vrfSubscriptionId)` (external view call)
- `vrfCoordinator.requestRandomWords(...)` (external state-changing call)
- `_reserveLootboxRngIndex(id)` (private)

**ETH Flow:**
- No direct ETH movement. VRF request costs LINK (paid from subscription, not from game contract).

**Invariants:**
- Cannot be called in the 15-minute pre-reset window (prevents racing daily RNG)
- Cannot be called before today's daily RNG has been recorded (`rngWordByDay[currentDay] == 0` reverts)
- Cannot be called while `rngLockedFlag` is true (daily jackpot resolution in progress)
- Cannot be called while a VRF request is pending (`rngRequestTime != 0`)
- LINK balance must be >= `MIN_LINK_FOR_LOOTBOX_RNG` (40 LINK)
- At least one of pendingEth or pendingBurnie must be > 0
- If BURNIE < BURNIE_RNG_TRIGGER (40000 BURNIE), ETH-equivalent must meet threshold
- `rngLockedFlag` is NOT set by this function (mid-day RNG does not lock daily operations)

**NatSpec Accuracy:**
- NatSpec says "Request lootbox RNG when activity threshold is met" -- ACCURATE.
- NatSpec says "Cannot be called while daily RNG is locked (jackpot resolution)" -- ACCURATE.
- NatSpec says "VRF callback handles finalization directly - no advanceGame needed" -- ACCURATE. `rawFulfillRandomWords` checks `rngLockedFlag == false` for mid-day path.

**Gas Flags:**
- `vrfCoordinator.getSubscription()` is an external view call that reads 5 return values but only `linkBal` is used. The other 4 are discarded. No gas waste since this is a view call (STATICCALL gas cost is the same regardless of return values parsed).
- Threshold logic has multiple branches but all are simple arithmetic. No concern.
- The BURNIE-to-ETH conversion uses `price` which could be zero at level 0 (price starts at 0.01 ETH via Storage default). Since `price` is initialized to `0.01 ether` in DegenerusGameStorage, this division is safe.

**Verdict:** CORRECT

---

### `rngGate(uint48, uint48, uint24, bool)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function rngGate(uint48 ts, uint48 day, uint24 lvl, bool isTicketJackpotDay) internal returns (uint256 word)` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `ts` (uint48): current timestamp; `day` (uint48): current day index; `lvl` (uint24): current purchase level; `isTicketJackpotDay` (bool): true if last purchase day |
| **Returns** | `word` (uint256): RNG word if available, 1 if request sent, reverts if waiting |

**State Reads:**
- `rngWordByDay[day]` (check if already recorded)
- `rngWordCurrent` (check for pending VRF word)
- `rngRequestTime` (check for pending request / timeout)
- `vrfRequestId` (via _finalizeLootboxRng)
- `lootboxRngRequestIndexById[vrfRequestId]` (via _finalizeLootboxRng)
- `totalFlipReversals` (via _applyDailyRng)
- `level` (for bonusFlip check)

**State Writes:**
- Via `_applyDailyRng(day, currentWord)`: `totalFlipReversals = 0`, `rngWordCurrent = finalWord`, `rngWordByDay[day] = finalWord`
- Via `_finalizeLootboxRng(currentWord)`: `lootboxRngWordByIndex[index] = rngWord`
- Via `_requestRng(isTicketJackpotDay, lvl)`: VRF request state (see _requestRng audit)
- `rngWordCurrent = 0` (when stale cross-day word detected)

**Callers:**
- `advanceGame()` (the only caller)

**Callees:**
- `_simulatedDayIndexAt(rngRequestTime)` (view helper, for staleness check)
- `_finalizeLootboxRng(currentWord)` (private)
- `_applyDailyRng(day, currentWord)` (private)
- `coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)` (external call)
- `_requestRng(isTicketJackpotDay, lvl)` (private)

**ETH Flow:**
- No direct ETH flow. `coinflip.processCoinflipPayouts` processes coinflip payouts externally.

**Invariants:**
- Returns immediately if today's RNG already recorded (idempotent for double-entry)
- If VRF word ready and from current day: applies nudges, processes coinflips, finalizes lootbox
- If VRF word ready but from previous day: finalizes for lootbox only, then requests fresh daily RNG
- If VRF pending and 18+ hours elapsed: retries request
- If VRF pending and < 18 hours: reverts `RngNotReady()`
- If no pending request: initiates fresh request, returns 1
- `bonusFlip` is true when `isTicketJackpotDay` OR `level == 0` (first level always gets bonus)

**NatSpec Accuracy:**
- No NatSpec on `rngGate` function itself. The function is internal and self-documenting through its logic. No discrepancy.

**Gas Flags:**
- The staleness check (`requestDay < day`) requires an additional call to `_simulatedDayIndexAt(rngRequestTime)` which involves arithmetic but is pure. Acceptable.
- `coinflip.processCoinflipPayouts` is an external call with potentially high gas cost depending on payout queue size, but this is expected and documented.

**Verdict:** CORRECT

---

### `updateVrfCoordinatorAndSub(address, uint256, bytes32)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `newCoordinator` (address): new VRF coordinator; `newSubId` (uint256): new subscription ID; `newKeyHash` (bytes32): new gas lane key hash |
| **Returns** | None |

**State Reads:**
- `msg.sender` (access control)
- `_simulatedDayIndex()` (current day for 3-day gap check)
- `rngWordByDay[day]`, `rngWordByDay[day-1]`, `rngWordByDay[day-2]` (via _threeDayRngGap)
- `vrfCoordinator` (current coordinator for event)

**State Writes:**
- `vrfCoordinator = IVRFCoordinator(newCoordinator)`
- `vrfSubscriptionId = newSubId`
- `vrfKeyHash = newKeyHash`
- `rngLockedFlag = false`
- `vrfRequestId = 0`
- `rngRequestTime = 0`
- `rngWordCurrent = 0`

**Callers:**
- DegenerusAdmin only (`msg.sender != ContractAddresses.ADMIN` reverts `E()`).

**Callees:**
- `_simulatedDayIndex()` (view helper)
- `_threeDayRngGap(day)` (private view)

**ETH Flow:**
- None. Pure configuration + state reset function.

**Invariants:**
- Only ContractAddresses.ADMIN can call
- Requires 3-day RNG gap (no RNG words recorded for current day, day-1, and day-2)
- Resets all RNG state to allow immediate advancement after rotation
- This is an emergency recovery mechanism, not normal operation

**NatSpec Accuracy:**
- NatSpec says "Emergency VRF coordinator rotation after 3-day stall" -- ACCURATE.
- NatSpec says "Access: ContractAddresses.ADMIN only" -- ACCURATE.
- NatSpec says "SECURITY: Requires 3-day gap to prevent abuse" -- ACCURATE. `_threeDayRngGap` checks 3 consecutive days without RNG.
- Interface declares `updateVrfCoordinatorAndSub(address, uint256, uint32)` but implementation uses `bytes32` for 3rd param. INTERFACE MISMATCH: interface says `uint32 newKeyHash` but implementation says `bytes32 newKeyHash`. However, checking the interface file: the interface actually declares `bytes32 newKeyHash` at line 32 of IDegenerusGameModules.sol. Confirmed: no mismatch.

**Gas Flags:**
- 7 SSTOREs + 1 SLOAD + 3 mapping reads. Efficient for an emergency function.
- `_threeDayRngGap` performs 3 mapping reads. Early-exit on first non-zero optimizes the common denial case.

**Verdict:** CORRECT

---

### `reverseFlip()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function reverseFlip() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `rngLockedFlag` (must be false)
- `totalFlipReversals` (current nudge count for cost calculation)

**State Writes:**
- `totalFlipReversals = reversals + 1` (increment nudge counter)

**Callers:**
- Any external caller. Called via delegatecall from DegenerusGame.

**Callees:**
- `_currentNudgeCost(reversals)` (private pure)
- `coin.burnCoin(msg.sender, cost)` (external call to DegenerusCoin)

**ETH Flow:**
- No ETH flow. Burns BURNIE tokens.

**Invariants:**
- Cannot be called while `rngLockedFlag` is true (reverts `RngLocked()`)
- Cost compounds at 50% per queued nudge: 100, 150, 225, 337.5, 506.25... BURNIE
- `totalFlipReversals` is reset to 0 in `_applyDailyRng` when nudges are consumed
- Nudges shift the VRF word by +1 each, modifying RNG outcomes

**NatSpec Accuracy:**
- NatSpec says "Pay BURNIE to nudge the next RNG word by +1" -- ACCURATE.
- NatSpec says "Cost scales +50% per queued nudge and resets after fulfillment" -- ACCURATE. `_currentNudgeCost` compounds 50% per reversal; `_applyDailyRng` resets counter.
- NatSpec says "Only available while RNG is unlocked (before VRF request is in-flight)" -- ACCURATE.
- NatSpec says "SECURITY: Players cannot predict the base word, only influence it" -- ACCURATE. The base word comes from VRF and is unknown until fulfillment.

**Gas Flags:**
- `_currentNudgeCost` is O(n) in `reversals` count. NatSpec acknowledges this: "O(n) in reversals count - could be optimized with exponentiation for large n, but in practice reversals are bounded by game economics." The exponential cost growth (100 -> 150 -> 225 -> ...) makes large n economically infeasible. Acceptable.

**Verdict:** CORRECT

---

### `rawFulfillRandomWords(uint256, uint256[])` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `requestId` (uint256): VRF request ID to match; `randomWords` (uint256[]): array containing the random word (length 1) |
| **Returns** | None |

**State Reads:**
- `msg.sender` (must be vrfCoordinator address)
- `vrfCoordinator` (for access control comparison)
- `vrfRequestId` (must match requestId)
- `rngWordCurrent` (must be 0, i.e., not already fulfilled)
- `rngLockedFlag` (determines daily vs mid-day path)
- `lootboxRngRequestIndexById[requestId]` (for mid-day finalization)

**State Writes:**
- Daily path (`rngLockedFlag == true`):
  - `rngWordCurrent = word` (store VRF word for advanceGame processing)
- Mid-day path (`rngLockedFlag == false`):
  - `lootboxRngWordByIndex[index] = word` (directly finalize lootbox RNG)
  - `vrfRequestId = 0` (clear request)
  - `rngRequestTime = 0` (clear request time)

**Callers:**
- Chainlink VRF Coordinator only (`msg.sender != address(vrfCoordinator)` reverts `E()`).

**Callees:**
- None (no internal or external calls beyond storage reads/writes and event emission)

**ETH Flow:**
- None. Pure RNG fulfillment handler.

**Invariants:**
- Only the registered VRF coordinator can call
- Silently returns (no revert) if requestId doesn't match current or word already fulfilled -- prevents stale fulfillments from reverting and wasting VRF gas
- Word value of 0 is remapped to 1 (`if (word == 0) word = 1`) to preserve the "0 = pending" sentinel
- Daily path: stores word for later consumption by `advanceGame` -> `rngGate` -> `_applyDailyRng`
- Mid-day path: directly writes to `lootboxRngWordByIndex` for immediate lootbox resolution

**NatSpec Accuracy:**
- NatSpec says "Chainlink VRF callback for random word fulfillment" -- ACCURATE.
- NatSpec says "Access: VRF coordinator only" -- ACCURATE.
- NatSpec says "Daily RNG: stores word for advanceGame processing (nudges applied there)" -- ACCURATE.
- NatSpec says "Mid-day RNG: directly finalizes lootbox RNG, no advanceGame needed" -- ACCURATE.
- NatSpec says "Validates requestId and coordinator address" -- ACCURATE.

**Gas Flags:**
- Minimal gas: 1-2 SLOADs, 1-3 SSTOREs depending on path. Very efficient callback.
- No external calls, making it safe within VRF callback gas limits (300k configured).

**Verdict:** CORRECT

---

## Internal / Private Functions

---

### `_handleGameOverPath(uint48, uint48, uint48, uint24, bool, uint48)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _handleGameOverPath(uint48 ts, uint48 day, uint48 lst, uint24 lvl, bool lastPurchase, uint48 _dailyIdx) private returns (bool shouldReturn)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `ts` (uint48): current timestamp; `day` (uint48): current day index; `lst` (uint48): levelStartTime; `lvl` (uint24): current level; `lastPurchase` (bool): lastPurchaseDay flag; `_dailyIdx` (uint48): daily index |
| **Returns** | `shouldReturn` (bool): true if advanceGame should exit early |

**State Reads:**
- `gameOver` (terminal state check)
- `nextPrizePool` (safety check against premature game-over)
- `levelPrizePool[lvl]` (prize target comparison)
- `rngWordByDay[_dailyIdx]` (RNG availability for drain)
- DEPLOY_IDLE_TIMEOUT_DAYS (constant: 912 days)

**State Writes:**
- `levelStartTime = ts` (when safety check resets liveness timer)
- Via delegatecall to GAME_GAMEOVER_MODULE.handleFinalSweep: game-over drain state
- Via delegatecall to GAME_GAMEOVER_MODULE.handleGameOverDrain: game-over drain state
- Via `_gameOverEntropy(...)`: RNG state (see that function's audit)
- Via `_unlockRng(day)`: resets RNG state

**Callers:**
- `advanceGame()` only

**Callees:**
- `ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(handleFinalSweep.selector)` (post-gameover sweep)
- `ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(handleGameOverDrain.selector, _dailyIdx)` (pre-gameover drain)
- `_gameOverEntropy(ts, day, lvl, lastPurchase)` (private)
- `_unlockRng(day)` (private)
- `_revertDelegate(data)` (private pure)

**ETH Flow:**
- Via delegatecall to GameOverModule: ETH moves from prize pools to claimableWinnings/claimablePool during drain
- handleFinalSweep: transfers remaining ETH to DGNRS/VAULT after 1-month delay
- handleGameOverDrain: distributes prize pools to players/claimable

**Invariants:**
- Liveness check: level 0 = 912-day timeout, level > 0 = 365-day timeout
- If liveness not triggered, returns false immediately (no game-over processing)
- Post-gameover path (gameOver == true): delegates to handleFinalSweep
- Safety check: if `nextPrizePool >= levelPrizePool[lvl]` at level > 0, resets timer and does NOT trigger game-over (prevents premature activation when prize target is already met)
- Pre-gameover path: acquires RNG (with fallback), then delegates to handleGameOverDrain

**NatSpec Accuracy:**
- NatSpec says "Handles gameover state and liveness guard checks. Returns true if advanceGame should exit early." -- ACCURATE.

**Gas Flags:**
- Early return on `!livenessTriggered` is the hot path (99.99%+ of calls). Efficient.
- Liveness arithmetic uses `uint256` promotion for the `DEPLOY_IDLE_TIMEOUT_DAYS * 1 days` multiplication, preventing uint48 overflow. Correct.

**Verdict:** CORRECT

---

### `_endPhase()` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _endPhase() private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `level` (lvl, for x00 check)
- `futurePrizePool` (for x00 seeding)

**State Writes:**
- `phaseTransitionActive = true`
- `levelPrizePool[lvl] = futurePrizePool / 3` (only on x00 levels)
- `jackpotCounter = 0`
- `compressedJackpotFlag = false`

**Callers:**
- `advanceGame()` (after final jackpot day processing)

**Callees:**
- None

**ETH Flow:**
- On x00 levels: seeds `levelPrizePool[lvl]` with 1/3 of futurePrizePool. This sets the prize target for the NEXT purchase phase using current future pool as a baseline. Note: futurePrizePool itself is NOT reduced here; the seed is just a target snapshot.

**Invariants:**
- Always sets `phaseTransitionActive = true` to trigger transition processing on next advanceGame call
- x00 levels get special treatment: prize target seeded from future pool (making x00 levels significant milestones)
- `jackpotCounter` reset ensures next level starts fresh
- `compressedJackpotFlag` cleared so next level can independently determine if compressed

**NatSpec Accuracy:**
- No explicit NatSpec on this function. Section header says "LEVEL END" which is accurate.

**Gas Flags:**
- Very lightweight: 2-4 SSTOREs. Clean.

**Verdict:** CORRECT

---

### `_rewardTopAffiliate(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _rewardTopAffiliate(uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level |
| **Returns** | None |

**State Reads:**
- None directly (delegates all work)

**State Writes:**
- Via delegatecall to GAME_ENDGAME_MODULE.rewardTopAffiliate: affiliate reward state

**Callers:**
- `advanceGame()` (final jackpot day, after coin+ticket distribution)

**Callees:**
- `ContractAddresses.GAME_ENDGAME_MODULE.delegatecall(rewardTopAffiliate.selector, lvl)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via EndgameModule: distributes DGNRS tokens to top affiliate for the level. No direct ETH movement.

**Invariants:**
- Delegatecall failure reverts the entire advanceGame call

**NatSpec Accuracy:**
- NatSpec says "Reward the top affiliate for a level during level transition" -- ACCURATE.

**Gas Flags:**
- Single delegatecall. Cost depends on EndgameModule implementation.

**Verdict:** CORRECT

---

### `_runRewardJackpots(uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runRewardJackpots(uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level; `rngWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:**
- None directly

**State Writes:**
- Via delegatecall to GAME_ENDGAME_MODULE.runRewardJackpots: BAF/Decimator jackpot state

**Callers:**
- `advanceGame()` (final jackpot day)

**Callees:**
- `ContractAddresses.GAME_ENDGAME_MODULE.delegatecall(runRewardJackpots.selector, lvl, rngWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via EndgameModule: distributes BAF jackpot and decimator jackpot pools. ETH moves from designated pools to claimableWinnings.

**Invariants:**
- Called with the same `rngWord` used for the final daily jackpot, ensuring consistent entropy across all level-end distributions.

**NatSpec Accuracy:**
- NatSpec says "Resolve BAF/Decimator jackpots during the level transition RNG period" -- ACCURATE.

**Gas Flags:**
- Single delegatecall. Potentially high gas due to jackpot distribution complexity (multiple winners, trait lookups).

**Verdict:** CORRECT

---

### `_revertDelegate(bytes)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _revertDelegate(bytes memory reason) private pure` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `reason` (bytes): error data from failed delegatecall |
| **Returns** | None (always reverts) |

**State Reads:** None
**State Writes:** None

**Callers:**
- Every delegatecall wrapper: `_rewardTopAffiliate`, `_runRewardJackpots`, `_consolidatePrizePools`, `_awardFinalDayDgnrsReward`, `payDailyJackpot`, `payDailyJackpotCoinAndTickets`, `_payDailyCoinJackpot`, `_processFutureTicketBatch`, `_runProcessTicketBatch`, `_handleGameOverPath`

**Callees:** None (pure function with inline assembly)

**ETH Flow:** None

**Invariants:**
- Always reverts. If reason is empty, reverts with `E()`. Otherwise, propagates the original revert reason from the delegatecall target.
- Assembly block is marked `"memory-safe"` -- correct since it only reads from `reason` memory pointer.

**NatSpec Accuracy:**
- NatSpec says "Bubble up revert reason from delegatecall failure. Uses assembly to preserve original error data." -- ACCURATE.

**Gas Flags:**
- Efficient: single assembly revert with no copies. The `add(32, reason)` skips the length prefix.

**Verdict:** CORRECT

---

### `_consolidatePrizePools(uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _consolidatePrizePools(uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level; `rngWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.consolidatePrizePools

**Callers:**
- `advanceGame()` (during purchase phase, after lastPurchaseDay target met)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(consolidatePrizePools.selector, lvl, rngWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via JackpotModule: merges nextPrizePool into currentPrizePool, rebalances future/current, credits coinflip, distributes stETH yield. Major ETH reorganization point.

**Invariants:**
- Called only once per level (guarded by `poolConsolidationDone` in advanceGame)
- Must happen before jackpot phase entry

**NatSpec Accuracy:**
- NatSpec says "Consolidate prize pools via jackpot module delegatecall. Merges next->current, rebalances future/current, credits coinflip, distributes yield." -- ACCURATE.

**Gas Flags:**
- Single delegatecall. JackpotModule's consolidation is gas-intensive but batched.

**Verdict:** CORRECT

---

### `_awardFinalDayDgnrsReward(uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardFinalDayDgnrsReward(uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level; `rngWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.awardFinalDayDgnrsReward

**Callers:**
- `advanceGame()` (final jackpot day, after coin+ticket distribution complete)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(awardFinalDayDgnrsReward.selector, lvl, rngWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- No direct ETH. Awards DGNRS tokens to the solo bucket winner on the final daily jackpot.

**Invariants:**
- Only called once per level (final jackpot day path in advanceGame)

**NatSpec Accuracy:**
- NatSpec says "Award DGNRS reward to the solo bucket winner after final daily jackpot" -- ACCURATE.

**Gas Flags:** Single delegatecall. Lightweight.

**Verdict:** CORRECT

---

### `payDailyJackpot(bool, uint24, uint256)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyJackpot(bool isDaily, uint24 lvl, uint256 randWord) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `isDaily` (bool): true for jackpot phase, false for purchase phase; `lvl` (uint24): current level; `randWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.payDailyJackpot

**Callers:**
- `advanceGame()`:
  - Purchase phase daily jackpot (line 200): `payDailyJackpot(false, purchaseLevel, rngWord)`
  - Jackpot phase resume (line 266): `payDailyJackpot(true, lastDailyJackpotLevel, rngWord)`
  - Jackpot phase fresh daily (line 288): `payDailyJackpot(true, lvl, rngWord)`

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(payDailyJackpot.selector, isDaily, lvl, randWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via JackpotModule: distributes ETH from currentPrizePool to winners via claimableWinnings. The split-bucket mechanism credits 4 winner buckets (solo, duo, trio, quad) with trait-matched ETH rewards.

**Invariants:**
- Purchase phase (isDaily=false): early-burn distribution from currentPrizePool
- Jackpot phase (isDaily=true): full jackpot distribution from currentPrizePool
- Resume path uses `lastDailyJackpotLevel` to continue a previously interrupted jackpot

**NatSpec Accuracy:**
- NatSpec says "Pay daily jackpot via jackpot module delegatecall. Called each day during purchase phase and jackpot phase." -- ACCURATE.
- NatSpec parameter description: "isDaily True for jackpot phase, false for purchase phase (early-burn)" -- ACCURATE.

**Gas Flags:** Single delegatecall. Gas depends on JackpotModule's distribution complexity (winner selection, trait matching).

**Verdict:** CORRECT

---

### `payDailyJackpotCoinAndTickets(uint256)` [internal]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyJackpotCoinAndTickets(uint256 randWord) internal` |
| **Visibility** | internal |
| **Mutability** | state-changing |
| **Parameters** | `randWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.payDailyJackpotCoinAndTickets

**Callers:**
- `advanceGame()` (when `dailyJackpotCoinTicketsPending` is true)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(payDailyJackpotCoinAndTickets.selector, randWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- Via JackpotModule: distributes BURNIE coin rewards and ticket rewards as the second phase of a split daily jackpot.

**Invariants:**
- Only called when `dailyJackpotCoinTicketsPending` is true
- Completes the split daily jackpot that was started by `payDailyJackpot`

**NatSpec Accuracy:**
- NatSpec says "Pay coin+ticket portion of daily jackpot via jackpot module delegatecall. Called when dailyJackpotCoinTicketsPending is true to complete the split daily jackpot (gas optimization to stay under 15M block limit)." -- ACCURATE.

**Gas Flags:** Single delegatecall. Completing the second half of split jackpot.

**Verdict:** CORRECT

---

### `_payDailyCoinJackpot(uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _payDailyCoinJackpot(uint24 lvl, uint256 randWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level; `randWord` (uint256): VRF random word |
| **Returns** | None |

**State Reads:** None directly
**State Writes:** Via delegatecall to GAME_JACKPOT_MODULE.payDailyCoinJackpot

**Callers:**
- `advanceGame()` (purchase phase, non-lastPurchaseDay daily tick, line 201)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(payDailyCoinJackpot.selector, lvl, randWord)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:**
- No direct ETH. Awards 0.5% of prize pool target in BURNIE to current and future ticket holders.

**Invariants:**
- Only called during purchase phase daily ticks (not lastPurchaseDay, not jackpot phase)

**NatSpec Accuracy:**
- NatSpec says "Pay daily BURNIE jackpot via jackpot module delegatecall. Called each day during purchase phase in its own transaction. Awards 0.5% of prize pool target in BURNIE to current and future ticket holders." -- ACCURATE.

**Gas Flags:** Single delegatecall. BURNIE minting gas depends on winner count.

**Verdict:** CORRECT

---

### `_enforceDailyMintGate(address, uint24, uint48)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _enforceDailyMintGate(address caller, uint24 lvl, uint48 dailyIdx_) private view` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `caller` (address): msg.sender; `lvl` (uint24): current purchase level; `dailyIdx_` (uint48): current daily index |
| **Returns** | None (reverts on failure) |

**State Reads:**
- `mintPacked_[caller]` (bit-packed mint history)
  - Extracts `lastEthDay` via DAY_SHIFT (bits 72-103)
  - Extracts `frozenUntilLevel` via FROZEN_UNTIL_LEVEL_SHIFT (bits 128-151)
- `deityPassCount[caller]` (deity pass bypass)
- `block.timestamp` (elapsed since day boundary)
- `vault.isVaultOwner(caller)` (external view call, last-resort bypass)

**State Writes:** None (view function)

**Callers:**
- `advanceGame()` (line 143)

**Callees:**
- `vault.isVaultOwner(caller)` (external view call to DegenerusVault)

**ETH Flow:** None

**Invariants:**
- Gate bypasses (in order of check):
  1. Day index 0: always bypass (game hasn't started)
  2. Minted today or yesterday (`lastEthDay + 1 >= gateIdx`): pass
  3. Deity pass holder (`deityPassCount[caller] != 0`): always bypass
  4. 30+ minutes after day boundary: anyone bypasses
  5. 15+ minutes after day boundary: any pass holder (frozenUntilLevel > lvl) bypasses
  6. DGVE majority holder (`vault.isVaultOwner`): always bypass
  7. Otherwise: reverts `MustMintToday()`
- The 82620 constant = 22:57 UTC (JACKPOT_RESET_TIME), aligning the gate window with the game day boundary
- `lastEthDay + 1 < gateIdx` means the caller's last mint is more than 1 day old relative to the gate

**NatSpec Accuracy:**
- NatSpec documents 4 bypass tiers with correct ordering -- ACCURATE.
- NatSpec says "only checked on revert path, zero cost for normal callers" -- SLIGHTLY MISLEADING. The mintPacked_ SLOAD and comparison always execute. However, for callers who minted recently, the function returns at the `lastEthDay + 1 >= gateIdx` check (2 SLOADs). The "zero cost" refers to bypass tiers, not the initial check.

**Gas Flags:**
- Hot path (recent minter): 1 SLOAD (mintPacked_) + arithmetic. Very efficient.
- Cold path (non-minter): up to 3 SLOADs + 1 external call (vault.isVaultOwner). The external call is the most expensive but is the last-resort path.

**Verdict:** CORRECT

---

### `_finalizeLootboxRng(uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _finalizeLootboxRng(uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `rngWord` (uint256): finalized RNG word |
| **Returns** | None |

**State Reads:**
- `vrfRequestId` (current request ID)
- `lootboxRngRequestIndexById[vrfRequestId]` (mapped index)

**State Writes:**
- `lootboxRngWordByIndex[index] = rngWord` (writes RNG word for lootbox resolution)

**Callers:**
- `rngGate()` (after daily RNG applied, line 669; after stale cross-day handling, line 659)
- `_gameOverEntropy()` (after game-over RNG applied, lines 717, 734)

**Callees:** None (emits event only)

**ETH Flow:** None

**Invariants:**
- No-op if `lootboxRngRequestIndexById[vrfRequestId] == 0` (no lootbox reservation for this request)
- Writes the same daily RNG word to the lootbox index, reusing daily entropy for lootbox resolution
- The lootbox index was reserved at VRF request time, ensuring lootboxes purchased during the request window will use this word

**NatSpec Accuracy:** No explicit NatSpec. Self-documenting.

**Gas Flags:**
- 2 SLOADs + 1 SSTORE + event emission. Minimal.

**Verdict:** CORRECT

---

### `_gameOverEntropy(uint48, uint48, uint24, bool)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _gameOverEntropy(uint48 ts, uint48 day, uint24 lvl, bool isTicketJackpotDay) private returns (uint256 word)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `ts` (uint48): current timestamp; `day` (uint48): current day index; `lvl` (uint24): current level; `isTicketJackpotDay` (bool): last purchase day flag |
| **Returns** | `word` (uint256): RNG word, 1 if request sent, 0 if waiting on fallback |

**State Reads:**
- `rngWordByDay[day]` (check if already recorded)
- `rngWordCurrent` (check for pending VRF word)
- `rngRequestTime` (check for pending request)
- GAMEOVER_RNG_FALLBACK_DELAY (constant: 3 days)

**State Writes:**
- Via `_applyDailyRng(day, currentWord)`: RNG state
- Via `coinflip.processCoinflipPayouts(...)`: coinflip payout state
- Via `_finalizeLootboxRng(...)`: lootbox RNG state
- `rngWordCurrent = 0` (VRF fallback start)
- `rngRequestTime = ts` (VRF fallback timer)

**Callers:**
- `_handleGameOverPath()` (line 364)

**Callees:**
- `_applyDailyRng(day, currentWord)` (private)
- `coinflip.processCoinflipPayouts(isTicketJackpotDay, currentWord, day)` (external) -- note: only called when `lvl != 0`
- `_finalizeLootboxRng(currentWord)` (private)
- `_getHistoricalRngFallback(day)` (private view)
- `_tryRequestRng(isTicketJackpotDay, lvl)` (private)

**ETH Flow:** None directly. Coinflip payouts happen externally.

**Invariants:**
- Unlike `rngGate`, does NOT revert on timeout -- returns 0 to signal "waiting"
- Level 0 skips coinflip processing (no coinflips at level 0)
- 3-day fallback mechanism: if VRF stalled for 3 days, uses earliest historical VRF word (more secure than blockhash)
- If VRF request itself fails (try/catch in _tryRequestRng), starts fallback timer manually by setting `rngRequestTime = ts` and `rngWordCurrent = 0`

**NatSpec Accuracy:**
- NatSpec says "Game-over RNG gate with fallback for stalled VRF. After 3-day timeout, uses earliest historical VRF word as fallback" -- ACCURATE.
- NatSpec says "more secure than blockhash since it's already verified on-chain and cannot be manipulated" -- ACCURATE. Historical VRF words were verified by Chainlink at fulfillment time.

**Gas Flags:**
- Multiple branches but all with early exits. The fallback path (historical search) is O(30) in worst case but uses cheap mapping reads.

**Verdict:** CORRECT

---

### `_getHistoricalRngFallback(uint48)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _getHistoricalRngFallback(uint48 currentDay) private view returns (uint256 word)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `currentDay` (uint48): current day index |
| **Returns** | `word` (uint256): historical RNG word XOR'd with current day for uniqueness |

**State Reads:**
- `rngWordByDay[searchDay]` (iterates days 1..min(currentDay, 30))

**State Writes:** None (view function)

**Callers:**
- `_gameOverEntropy()` (line 725, after 3-day timeout)

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Searches forward from day 1 (not day 0) up to 30 days
- Returns `keccak256(abi.encodePacked(word, currentDay))` to ensure uniqueness across different days using the same fallback source
- Reverts `E()` if no historical RNG words exist (catastrophic: VRF never worked)
- Capped at 30 iterations for gas safety

**NatSpec Accuracy:**
- NatSpec says "Get historical VRF word as fallback for gameover RNG. Searches forward from day 1 to find the earliest available RNG word (max 30 tries). Reverts if no historical words exist (VRF never worked)." -- ACCURATE.

**Gas Flags:**
- O(30) worst case with mapping reads. Each mapping read is ~2100 gas (cold) or ~100 gas (warm). Max ~63k gas in cold-cache worst case. Acceptable for an emergency fallback.
- Uses `unchecked { ++searchDay; }` for gas optimization in the loop counter.

**Verdict:** CORRECT

---

### `_nextToFutureBps(uint48, uint24)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _nextToFutureBps(uint48 elapsed, uint24 lvl) private pure returns (uint16)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `elapsed` (uint48): time since level start + 11 days; `lvl` (uint24): current level |
| **Returns** | `uint16`: basis points for next-to-future pool transfer |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:**
- `_applyTimeBasedFutureTake()` (line 819)

**Callees:** None

**ETH Flow:** None (pure computation)

**Invariants:**
- Returns BPS value between 0 and 10000 (capped at line 808)
- 4 time tiers:
  - <= 1 day: FAST (3000) + level bonus
  - 1-14 days: linear decay from FAST to MIN (1300)
  - 14-28 days: linear recovery from MIN back to FAST + level bonus
  - 28+ days: FAST + level bonus + 100 bps per additional week
- Level bonus: +1% per 10 levels within 100-level cycle (`(lvl % 100 / 10) * 100`)
- V-shaped curve: incentivizes quick level completion (high early skim) and disincentivizes stalling (high late skim), with a minimum during 1-2 week transitions

**NatSpec Accuracy:** No explicit NatSpec. Section header "FUTURE PRIZE POOL DRAW" provides context.

**Gas Flags:**
- Pure arithmetic with no loops. Efficient. Division by time constants is safe (non-zero denominators).
- The 14-28 day recovery branch subtraction is safe because all components are bounded and positive.

**Verdict:** CORRECT

---

### `_applyTimeBasedFutureTake(uint48, uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyTimeBasedFutureTake(uint48 reachedAt, uint24 lvl, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `reachedAt` (uint48): timestamp when prize target was reached; `lvl` (uint24): current level; `rngWord` (uint256): VRF random word for variance |
| **Returns** | None |

**State Reads:**
- `levelStartTime` (base time for elapsed calculation)
- `nextPrizePool` (source pool)
- `futurePrizePool` (destination pool)
- `levelPrizePool[lvl - 1]` (previous level target for growth adjustment)

**State Writes:**
- `nextPrizePool -= take` (reduces next pool)
- `futurePrizePool += take` (increases future pool)

**Callers:**
- `advanceGame()` (line 228, during pool consolidation on lastPurchaseDay)

**Callees:**
- `_nextToFutureBps(elapsed, lvl)` (private pure)

**ETH Flow:**
- **nextPrizePool -> futurePrizePool**: Skims a time-adjusted percentage of the next pool into the future pool.
- BPS adjusted by: time curve, x9 bonus, ratio adjustment, growth adjustment, random variance.

**Invariants:**
- `take` can never exceed `nextPoolBefore` (capped at line 867)
- Variance is bounded and cannot exceed the take amount
- BPS is capped at 10000 (line 853)
- Division by `nextPoolBefore` is safe in context (prize target met implies > 0)

**NatSpec Accuracy:** No explicit NatSpec. Inline comments explain adjustments adequately.

**Gas Flags:**
- Multiple arithmetic operations but no loops. Pure math with modular reduction for variance.

**Verdict:** CORRECT

---

### `_drawDownFuturePrizePool(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _drawDownFuturePrizePool(uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level |
| **Returns** | None |

**State Reads:**
- `futurePrizePool` (source pool)

**State Writes:**
- `futurePrizePool -= reserved`
- `nextPrizePool += reserved`

**Callers:**
- `advanceGame()` (line 248, during jackpot phase entry)

**Callees:** None

**ETH Flow:**
- **futurePrizePool -> nextPrizePool**: 15% on normal levels, 0% on x00 levels.

**Invariants:**
- x00 levels skip drawdown
- No-op if reserved == 0

**NatSpec Accuracy:**
- Section header: "Release a portion of the future prize pool once per level. Normal levels draw 15%, x00 levels skip the draw." -- ACCURATE.

**Gas Flags:** 1-2 SLOADs + 0-2 SSTOREs. Very efficient.

**Verdict:** CORRECT

---

### `_processFutureTicketBatch(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processFutureTicketBatch(uint24 lvl) private returns (bool worked, bool finished, uint32 writesUsed)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): target level to activate tickets for |
| **Returns** | `worked` (bool): true if entries processed; `finished` (bool): true if all done; `writesUsed` (uint32): SSTOREs used |

**State Reads/Writes:** Via delegatecall to GAME_MINT_MODULE.processFutureTicketBatch

**Callers:**
- `advanceGame()` (line 218)
- `_prepareFinalDayFutureTickets()` (lines 936, 945)

**Callees:**
- `ContractAddresses.GAME_MINT_MODULE.delegatecall(processFutureTicketBatch.selector, lvl)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:** None directly.

**Invariants:**
- Reverts if return data is empty
- Returns decoded tuple from delegatecall

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** Single delegatecall.

**Verdict:** CORRECT

---

### `_prepareFinalDayFutureTickets(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _prepareFinalDayFutureTickets(uint24 lvl) private returns (bool finished)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current jackpot level |
| **Returns** | `finished` (bool): true when all target future levels fully processed |

**State Reads:**
- `ticketLevel` (resumeLevel)

**State Writes:**
- Via `_processFutureTicketBatch(...)`: ticket queue state for levels lvl+2..lvl+5

**Callers:**
- `advanceGame()` (line 181, on final jackpot day)

**Callees:**
- `_processFutureTicketBatch(resumeLevel)` (for resume)
- `_processFutureTicketBatch(target)` (for remaining levels)

**ETH Flow:** None directly.

**Invariants:**
- Processes levels lvl+2..lvl+5 (4 levels)
- Continues in-flight level first, then scans remaining
- Returns false if any level has work to do (multi-call resumable)

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** Max 4 delegatecalls per advanceGame call (usually 1 due to early return).

**Verdict:** CORRECT

---

### `_runProcessTicketBatch(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runProcessTicketBatch(uint24 lvl) private returns (bool worked, bool finished)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): current level |
| **Returns** | `worked` (bool): true if tickets processed; `finished` (bool): true if all done |

**State Reads:**
- `ticketCursor` (prevCursor)
- `ticketLevel` (prevLevel)

**State Writes:**
- Via delegatecall to GAME_JACKPOT_MODULE.processTicketBatch

**Callers:**
- `advanceGame()` (line 188)

**Callees:**
- `ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(processTicketBatch.selector, lvl)`
- `_revertDelegate(data)` (on failure)

**ETH Flow:** None directly.

**Invariants:**
- `worked` derived by comparing cursors before/after delegatecall
- Reverts on empty return data

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 2 SLOADs before + 2 after for work detection.

**Verdict:** CORRECT

---

### `_processPhaseTransition(uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processPhaseTransition(uint24 purchaseLevel) private returns (bool finished)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `purchaseLevel` (uint24): current purchase level |
| **Returns** | `finished` (bool): always true |

**State Reads:**
- `claimablePool` (via _autoStakeExcessEth)
- `address(this).balance` (via _autoStakeExcessEth)

**State Writes:**
- Via `_queueTickets`: queues 16 tickets each for DGNRS and VAULT at purchaseLevel+99
- Via `_autoStakeExcessEth()`: submits excess ETH to stETH

**Callers:**
- `advanceGame()` (line 158)

**Callees:**
- `_queueTickets(ContractAddresses.DGNRS, targetLevel, VAULT_PERPETUAL_TICKETS)`
- `_queueTickets(ContractAddresses.VAULT, targetLevel, VAULT_PERPETUAL_TICKETS)`
- `_autoStakeExcessEth()` (private)

**ETH Flow:**
- Via `_autoStakeExcessEth`: excess ETH above claimablePool -> stETH via Lido

**Invariants:**
- Always returns true (single-call completion)
- Perpetual tickets target level = purchaseLevel + 99

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 2 _queueTickets calls + 1 external stETH call.

**Verdict:** CORRECT

---

### `_autoStakeExcessEth()` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _autoStakeExcessEth() private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `address(this).balance` (current ETH balance)
- `claimablePool` (reserved ETH)

**State Writes:** None directly. ETH sent to Lido; stETH received.

**Callers:**
- `_processPhaseTransition()` (line 1002)

**Callees:**
- `steth.submit{value: stakeable}(address(0))` (external payable call to Lido)

**ETH Flow:**
- **address(this).balance -> stETH**: Stakes excess ETH. claimablePool always preserved in raw ETH.

**Invariants:**
- No-op if ethBal <= claimablePool
- try/catch ensures non-blocking
- address(0) referrer = no referral

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** External call ~30-50k gas. Silent catch is intentional.

**Verdict:** CORRECT

---

### `_requestRng(bool, uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _requestRng(bool isTicketJackpotDay, uint24 lvl) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `isTicketJackpotDay` (bool): true if last purchase day; `lvl` (uint24): current level |
| **Returns** | None |

**State Reads:**
- `vrfKeyHash`, `vrfSubscriptionId` (VRF config)

**State Writes:**
- Via `_finalizeRngRequest(...)`: RNG state

**Callers:**
- `rngGate()` (lines 661, 677, 684)

**Callees:**
- `vrfCoordinator.requestRandomWords(...)` (external, hard revert on failure)
- `_finalizeRngRequest(isTicketJackpotDay, lvl, id)` (private)

**ETH Flow:** None. LINK payment from subscription.

**Invariants:**
- Hard reverts on failure (intentional game halt)
- 10 block confirmations for daily RNG

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** Single external call + internal state updates.

**Verdict:** CORRECT

---

### `_tryRequestRng(bool, uint24)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _tryRequestRng(bool isTicketJackpotDay, uint24 lvl) private returns (bool requested)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `isTicketJackpotDay` (bool): true if last purchase day; `lvl` (uint24): current level |
| **Returns** | `requested` (bool): true if VRF request succeeded |

**State Reads:**
- `vrfCoordinator` (zero check)
- `vrfKeyHash` (zero check)
- `vrfSubscriptionId` (zero check)

**State Writes:**
- Via `_finalizeRngRequest(...)` on success

**Callers:**
- `_gameOverEntropy()` (line 740)

**Callees:**
- `vrfCoordinator.requestRandomWords(...)` (try/catch)
- `_finalizeRngRequest(...)` (on success)

**ETH Flow:** None

**Invariants:**
- Returns false without reverting on failure (graceful for game-over path)
- Pre-checks coordinator/keyHash/subId to avoid unnecessary external calls

**NatSpec Accuracy:** No explicit NatSpec. Self-documenting.

**Gas Flags:** 3 SLOADs for zero-checks. Early exits.

**Verdict:** CORRECT

---

### `_finalizeRngRequest(bool, uint24, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _finalizeRngRequest(bool isTicketJackpotDay, uint24 lvl, uint256 requestId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `isTicketJackpotDay` (bool): true if last purchase day; `lvl` (uint24): current level; `requestId` (uint256): new VRF request ID |
| **Returns** | None |

**State Reads:**
- `vrfRequestId` (prevRequestId), `rngRequestTime`, `rngWordCurrent` (retry detection)
- `lootboxRngRequestIndexById[prevRequestId]` (lootbox index remap)
- `lootboxRngIndex` (fresh reservation)
- `decWindowOpen` (decimator window)

**State Writes:**
- Retry: remap lootbox index from old to new request ID
- Fresh: `_reserveLootboxRngIndex(requestId)`
- Always: `vrfRequestId`, `rngWordCurrent = 0`, `rngRequestTime`, `rngLockedFlag = true`
- Decimator close: `decWindowOpen = false` (at resolution levels)
- Level increment: `level = lvl`, `price = ...` (on fresh isTicketJackpotDay)

**Callers:**
- `_requestRng()` (line 1034)
- `_tryRequestRng()` (line 1061)

**Callees:**
- `_reserveLootboxRngIndex(requestId)` (on fresh request)

**ETH Flow:** None

**Invariants:**
- Level increment only on fresh requests (not retries) to prevent double-increment
- Decimator window closes at specific resolution levels
- Price tiers follow fixed schedule with 100-level cycles

**NatSpec Accuracy:** No explicit NatSpec. Inline comments are clear.

**Gas Flags:** Retry path has extra SLOADs for remapping. Price tier uses sequential if/else (acceptable for once-per-level call).

**Verdict:** CORRECT

---

### `_unlockRng(uint48)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _unlockRng(uint48 day) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): current day index |
| **Returns** | None |

**State Reads:** None

**State Writes:**
- `dailyIdx = day`, `rngLockedFlag = false`, `rngWordCurrent = 0`, `vrfRequestId = 0`, `rngRequestTime = 0`

**Callers:**
- `advanceGame()` (lines 163, 207, 282)
- `_handleGameOverPath()` (line 366)

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Complete RNG state reset
- Updates dailyIdx to prevent re-entry on same day
- Most SSTOREs reset to zero (gas refund eligible)

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 5 SSTOREs, most clearing to zero (gas refunds).

**Verdict:** CORRECT

---

### `_reserveLootboxRngIndex(uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _reserveLootboxRngIndex(uint256 requestId) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `requestId` (uint256): VRF request ID |
| **Returns** | None |

**State Reads:**
- `lootboxRngIndex` (current index)

**State Writes:**
- `lootboxRngRequestIndexById[requestId] = index`
- `lootboxRngIndex = index + 1`
- `lootboxRngPendingEth = 0`
- `lootboxRngPendingBurnie = 0`

**Callers:**
- `_finalizeRngRequest()` (line 1088)
- `requestLootboxRng()` (line 634)

**Callees:** None

**ETH Flow:** None. Bookkeeping.

**Invariants:**
- Monotonically increments lootboxRngIndex
- Resets pending counters for next accumulation cycle

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 1 SLOAD + 4 SSTOREs.

**Verdict:** CORRECT

---

### `_applyDailyRng(uint48, uint256)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _applyDailyRng(uint48 day, uint256 rawWord) private returns (uint256 finalWord)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): day index; `rawWord` (uint256): VRF random word |
| **Returns** | `finalWord` (uint256): nudge-adjusted RNG word |

**State Reads:**
- `totalFlipReversals` (nudge count)

**State Writes:**
- `totalFlipReversals = 0` (reset on consumption)
- `rngWordCurrent = finalWord`
- `rngWordByDay[day] = finalWord`

**Callers:**
- `rngGate()` (line 666)
- `_gameOverEntropy()` (lines 709, 726)

**Callees:** None (emits event)

**ETH Flow:** None

**Invariants:**
- Nudges additive (unchecked wrapping intentional for RNG)
- Counter reset after consumption
- Word recorded in rngWordByDay for historical reference

**NatSpec Accuracy:** ACCURATE.

**Gas Flags:** 1 SLOAD + 2-3 SSTOREs + event. Efficient.

**Verdict:** CORRECT

---

### `_currentNudgeCost(uint256)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _currentNudgeCost(uint256 reversals) private pure returns (uint256 cost)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `reversals` (uint256): nudges already queued |
| **Returns** | `cost` (uint256): BURNIE cost for next nudge |

**State Reads:** None (pure)
**State Writes:** None (pure)

**Callers:**
- `reverseFlip()` (line 1187)

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Base 100 BURNIE, compounds 1.5x per queued nudge
- O(n) loop but economically bounded by exponential cost growth

**NatSpec Accuracy:** ACCURATE. Acknowledges O(n) with economic bound.

**Gas Flags:** O(n) loop with cheap multiplications. n bounded by economics (~30 max realistic).

**Verdict:** CORRECT

---

### `_threeDayRngGap(uint48)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _threeDayRngGap(uint48 day) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `day` (uint48): current day index |
| **Returns** | `bool`: true if 3 consecutive days have no RNG words |

**State Reads:**
- `rngWordByDay[day]`, `rngWordByDay[day - 1]`, `rngWordByDay[day - 2]`

**State Writes:** None (view)

**Callers:**
- `updateVrfCoordinatorAndSub()` (line 1152)

**Callees:** None

**ETH Flow:** None

**Invariants:**
- Returns false if any of 3 days has RNG word
- Underflow protection: `day < 2` returns false
- In practice, `day >= 2` when called (VRF rotation requires 3-day gap, implies game has run at least 2 days)

**NatSpec Accuracy:** No explicit NatSpec. Self-documenting.

**Gas Flags:** 3 mapping SLOADs max. Early exit on first non-zero.

**Verdict:** CORRECT

---

## ETH Mutation Path Map

Trace every path ETH enters, moves between pools, or exits through this module:

| # | Path | Source | Destination | Trigger | Function | Notes |
|---|------|--------|-------------|---------|----------|-------|
| 1 | Future skim (time-based) | nextPrizePool | futurePrizePool | Last purchase day, before pool consolidation | `_applyTimeBasedFutureTake` | Time-curve BPS with ratio/growth/variance adjustments |
| 2 | Pool consolidation | nextPrizePool + futurePrizePool | currentPrizePool | Last purchase day, after future skim | `_consolidatePrizePools` (delegatecall to JackpotModule) | Merges next->current, rebalances, credits coinflip, distributes yield |
| 3 | Future drawdown | futurePrizePool | nextPrizePool | Jackpot phase entry | `_drawDownFuturePrizePool` | 15% on normal levels, 0% on x00 levels |
| 4 | x00 level seeding | futurePrizePool (snapshot) | levelPrizePool[lvl] (target) | Phase end on x00 levels | `_endPhase` | Sets prize target = futurePrizePool / 3. Does NOT move actual ETH. |
| 5 | Daily ETH jackpot | currentPrizePool | claimableWinnings (player credits) | Daily tick (purchase/jackpot phase) | `payDailyJackpot` (delegatecall to JackpotModule) | 4-bucket trait-matched distribution |
| 6 | Coin+ticket jackpot | currentPrizePool | claimableWinnings (player credits) | Split jackpot completion | `payDailyJackpotCoinAndTickets` (delegatecall to JackpotModule) | Second phase of split daily jackpot |
| 7 | Reward jackpots (BAF/Dec) | Designated pools | claimableWinnings (player credits) | Final jackpot day | `_runRewardJackpots` (delegatecall to EndgameModule) | BAF and Decimator jackpot resolution |
| 8 | Top affiliate reward | DGNRS token pool | Affiliate address | Final jackpot day | `_rewardTopAffiliate` (delegatecall to EndgameModule) | DGNRS tokens, not ETH |
| 9 | Auto-stake excess | address(this).balance - claimablePool | stETH (Lido) | Phase transition | `_autoStakeExcessEth` | Non-blocking, try/catch wrapped |
| 10 | Game-over drain | Prize pools | claimableWinnings / DGNRS / VAULT | Liveness timeout | `_handleGameOverPath` (delegatecall to GameOverModule) | handleGameOverDrain + handleFinalSweep |
| 11 | Daily coin jackpot | BURNIE token (minted) | Winners | Purchase phase daily tick | `_payDailyCoinJackpot` (delegatecall to JackpotModule) | BURNIE, not ETH |
| 12 | DGNRS final day reward | DGNRS token pool | Solo bucket winner | Final jackpot day | `_awardFinalDayDgnrsReward` (delegatecall to JackpotModule) | DGNRS tokens, not ETH |
| 13 | Advance bounty | BURNIE token (creditFlip) | Caller | Every advanceGame call | `coin.creditFlip(caller, ADVANCE_BOUNTY)` | 500 BURNIE flip credit, not ETH |

### ETH Pool Lifecycle (Normal Level)

```
Purchase Phase:
  Mints -> nextPrizePool (via MintModule, not in this file)
  Daily: currentPrizePool -> claimableWinnings (early burn jackpots)

Last Purchase Day:
  nextPrizePool -> futurePrizePool (time-based skim, path #1)
  nextPrizePool -> currentPrizePool (consolidation, path #2)
  Level increment at RNG request time

Jackpot Phase Entry:
  futurePrizePool -> nextPrizePool (15% drawdown, path #3)
  currentPrizePool -> claimableWinnings (daily jackpots x5, path #5-6)

Phase End (day 5/3):
  BAF/Decimator pools -> claimableWinnings (path #7)
  address(this).balance -> stETH (auto-stake, path #9)

Phase Transition:
  Vault/DGNRS get perpetual tickets (16 each, +99 levels)
  Purchase phase reopens
```

### VRF Lifecycle State Machine

```
IDLE (rngLockedFlag=false, rngRequestTime=0, rngWordCurrent=0)
  |
  |--> requestRng / requestLootboxRng
  v
PENDING (rngLockedFlag=true/false, rngRequestTime!=0, rngWordCurrent=0)
  |                          |
  |<-- 18h timeout retry     |<-- 3d gameover fallback
  |                          |
  |--> rawFulfillRandomWords (VRF callback)
  v
READY (rngLockedFlag=true/false, rngRequestTime!=0, rngWordCurrent!=0)
  |
  |--> rngGate / _gameOverEntropy (consume word)
  |    _applyDailyRng -> rngWordByDay[day] = finalWord
  |    coinflip.processCoinflipPayouts
  |    _finalizeLootboxRng
  v
CONSUMED -> _unlockRng -> IDLE

Mid-day Lootbox (separate path):
  requestLootboxRng -> PENDING (rngLockedFlag stays false)
  rawFulfillRandomWords -> directly writes lootboxRngWordByIndex[idx]
  Clears vrfRequestId and rngRequestTime (no _unlockRng needed)
```

---

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 2 | (1) NatSpec `@notice` for `wireVrf` says "One-time" but it is re-callable (clarified in `@dev`). (2) `_autoStakeExcessEth` silently swallows Lido failures (intentional, documented). |
| GAS | 1 | `_currentNudgeCost` is O(n) in reversals count, but economically bounded. Documented in NatSpec. |
| CORRECT | 37 | All 37 functions verified correct (7 external/public/internal + 30 private) |

### Concern Details

**CONCERN 1: wireVrf NatSpec minor discrepancy**
- `@notice` says "One-time wiring" but function can be called multiple times by ADMIN
- `@dev` clarifies: "Overwrites any existing config on each call"
- Impact: Documentation confusion only. No code issue.
- Recommendation: Change `@notice` to "Wire VRF config from the ADMIN contract"

**CONCERN 2: Silent Lido failure swallowing**
- `_autoStakeExcessEth` uses try/catch around `steth.submit{value: stakeable}(address(0))`
- If Lido is paused or reverts, excess ETH sits idle until next phase transition
- This is documented and intentional (game continuity > yield optimization)
- Impact: Potential missed yield during Lido outages. No safety issue.
- Recommendation: Emit an event on catch for off-chain monitoring

### Complete Function Inventory

| # | Function | Visibility | Mutability | Lines | Verdict |
|---|----------|-----------|-----------|-------|---------|
| 1 | `advanceGame()` | external | state-changing | 120-294 | CORRECT |
| 2 | `wireVrf(address,uint256,bytes32)` | external | state-changing | 307-319 | CORRECT |
| 3 | `requestLootboxRng()` | external | state-changing | 588-638 | CORRECT |
| 4 | `rngGate(uint48,uint48,uint24,bool)` | internal | state-changing | 640-686 | CORRECT |
| 5 | `updateVrfCoordinatorAndSub(address,uint256,bytes32)` | external | state-changing | 1146-1166 | CORRECT |
| 6 | `reverseFlip()` | external | state-changing | 1184-1192 | CORRECT |
| 7 | `rawFulfillRandomWords(uint256,uint256[])` | external | state-changing | 1212-1233 | CORRECT |
| 8 | `_handleGameOverPath(uint48,uint48,uint48,uint24,bool,uint48)` | private | state-changing | 327-377 | CORRECT |
| 9 | `_endPhase()` | private | state-changing | 382-390 | CORRECT |
| 10 | `_rewardTopAffiliate(uint24)` | private | state-changing | 410-420 | CORRECT |
| 11 | `_runRewardJackpots(uint24,uint256)` | private | state-changing | 423-434 | CORRECT |
| 12 | `_revertDelegate(bytes)` | private | pure | 439-444 | CORRECT |
| 13 | `_consolidatePrizePools(uint24,uint256)` | private | state-changing | 448-461 | CORRECT |
| 14 | `_awardFinalDayDgnrsReward(uint24,uint256)` | private | state-changing | 464-477 | CORRECT |
| 15 | `payDailyJackpot(bool,uint24,uint256)` | internal | state-changing | 484-500 | CORRECT |
| 16 | `payDailyJackpotCoinAndTickets(uint256)` | internal | state-changing | 506-518 | CORRECT |
| 17 | `_payDailyCoinJackpot(uint24,uint256)` | private | state-changing | 525-536 | CORRECT |
| 18 | `_enforceDailyMintGate(address,uint24,uint48)` | private | view | 545-582 | CORRECT |
| 19 | `_finalizeLootboxRng(uint256)` | private | state-changing | 688-693 | CORRECT |
| 20 | `_gameOverEntropy(uint48,uint48,uint24,bool)` | private | state-changing | 699-748 | CORRECT |
| 21 | `_getHistoricalRngFallback(uint48)` | private | view | 755-774 | CORRECT |
| 22 | `_nextToFutureBps(uint48,uint24)` | private | pure | 783-809 | CORRECT |
| 23 | `_applyTimeBasedFutureTake(uint48,uint24,uint256)` | private | state-changing | 811-876 | CORRECT |
| 24 | `_drawDownFuturePrizePool(uint24)` | private | state-changing | 878-890 | CORRECT |
| 25 | `_processFutureTicketBatch(uint24)` | private | state-changing | 906-920 | CORRECT |
| 26 | `_prepareFinalDayFutureTickets(uint24)` | private | state-changing | 927-955 | CORRECT |
| 27 | `_runProcessTicketBatch(uint24)` | private | state-changing | 968-985 | CORRECT |
| 28 | `_processPhaseTransition(uint24)` | private | state-changing | 992-1005 | CORRECT |
| 29 | `_autoStakeExcessEth()` | private | state-changing | 1010-1016 | CORRECT |
| 30 | `_requestRng(bool,uint24)` | private | state-changing | 1022-1035 | CORRECT |
| 31 | `_tryRequestRng(bool,uint24)` | private | state-changing | 1037-1064 | CORRECT |
| 32 | `_finalizeRngRequest(bool,uint24,uint256)` | private | state-changing | 1066-1137 | CORRECT |
| 33 | `_unlockRng(uint48)` | private | state-changing | 1171-1177 | CORRECT |
| 34 | `_reserveLootboxRngIndex(uint256)` | private | state-changing | 1196-1203 | CORRECT |
| 35 | `_applyDailyRng(uint48,uint256)` | private | state-changing | 1236-1251 | CORRECT |
| 36 | `_currentNudgeCost(uint256)` | private | pure | 1259-1269 | CORRECT |
| 37 | `_threeDayRngGap(uint48)` | private | view | 1271-1276 | CORRECT |
