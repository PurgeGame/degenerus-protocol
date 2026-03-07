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
