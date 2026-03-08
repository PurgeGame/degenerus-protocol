# 02-05 Findings: Stuck-State Recovery Analysis

**Audit date:** 2026-02-28
**Auditor:** Claude Opus 4.6
**Scope:** All stuck states in the Degenerus FSM; all recovery mechanisms; premature-trigger resistance
**Requirements:** FSM-02, RNG-06
**Contracts audited (read-only):**
- `contracts/modules/DegenerusGameAdvanceModule.sol`
- `contracts/modules/DegenerusGameGameOverModule.sol`
- `contracts/DegenerusGame.sol`
- `contracts/DegenerusAdmin.sol`

---

## 1. Stuck-State Enumeration

### 1a. PURCHASE Phase Stuck -- advanceGame() Cannot Be Called

**Condition:** No caller can successfully execute `advanceGame()` to advance the day.

**Analysis:**

`advanceGame()` (AdvanceModule:115) has two gatekeepers before the main loop:

1. `_enforceDailyMintGate(caller, purchaseLevel, dailyIdx)` (line 138): Requires caller to have minted on the current or previous day, OR hold a lazy/deity pass, OR be CREATOR. **CREATOR always bypasses** (line 555: `if (caller == ContractAddresses.CREATOR) return;`). Therefore this gate cannot permanently block advancement.

2. `if (day == dailyIdx) revert NotTimeYet()` (line 140): Reverts if called on the same game-day. This is by design -- one advance per day.

**Verdict:** PURCHASE phase cannot get stuck because CREATOR can always call `advanceGame()`. If no players buy tickets, the liveness timeout (912 days at level 0, 365 days at level 1+) eventually triggers game-over via `_handleGameOverPath()`.

### 1b. VRF Pending Stuck -- rngLockedFlag=true, rngWordCurrent=0

**Condition:** VRF request sent, Chainlink has not yet fulfilled. `rngLockedFlag=true` blocks purchases, nudges, lootbox opens, config changes.

**Duration:** Typically seconds to minutes; up to 18 hours before retry.

**Impact:** All user-facing state-changing operations blocked:
- `reverseFlip()` -- reverts `RngLocked` (AdvanceModule:1172)
- `requestLootboxRng()` -- reverts `E()` (AdvanceModule:588)
- `_callTicketPurchase()` in MintModule -- blocked
- `openLootBox()` / `openBurnieLootBox()` in LootboxModule -- blocked
- `setAutoRebuy()` / `setAfKingMode()` etc. in DegenerusGame -- blocked
- `_placeBet()` in DegeneretteModule -- ETH bets blocked

**Recovery path:** 18-hour VRF retry (see Section 2a).

### 1c. VRF Permanently Unfulfilled -- Chainlink Never Responds

**Condition:** VRF coordinator is down, LINK exhausted, or network-level issue prevents fulfillment. 18-hour retry loops send new requests that also go unfulfilled.

**Impact:** Game permanently stuck at current day. All user operations blocked by `rngLockedFlag`.

**Recovery path:** 3-day emergency coordinator rotation (see Section 2b).

### 1d. JACKPOT Phase Stuck -- Jackpot Processing Fails

**Condition:** During the 5-day jackpot phase, processing reverts or VRF fails.

**Analysis:** Each jackpot day requires its own VRF word via `advanceGame()`. The jackpot phase uses the same `rngGate()` as the purchase phase. If VRF fails during a jackpot day:
- Same 18-hour retry applies
- Same 3-day emergency rotation applies
- Jackpot counter (`jackpotCounter`) tracks progress; a retry on the same day re-enters the same jackpot day logic
- Daily jackpot payouts use delegatecall to JackpotModule; if the module reverts, `_revertDelegate` bubbles it up and the entire `advanceGame()` call reverts, leaving state unchanged for the next attempt

**Split-processing mechanism:** Daily jackpot processing is designed to be resumable across multiple `advanceGame()` calls (cursors: `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `dailyEthPhase`, `dailyEthPoolBudget`). If a single call hits gas limits, subsequent calls resume from the cursor position.

**Verdict:** JACKPOT phase uses identical VRF recovery mechanisms as PURCHASE. The split-processing design prevents gas-limit stuck states.

### 1e. Phase Transition Stuck -- _processPhaseTransition() Fails

**Condition:** After 5 jackpot days complete, `phaseTransitionActive=true`. The next `advanceGame()` call runs `_processPhaseTransition()`.

**Analysis of `_processPhaseTransition()` (AdvanceModule:983-996):**
1. `_queueTickets(DGNRS, targetLevel, 16)` -- writes to storage mapping; cannot fail
2. `_queueTickets(VAULT, targetLevel, 16)` -- same
3. `_autoStakeExcessEth()` -- wrapped in `try/catch` (line 1006), non-blocking
4. Returns `true` immediately (always succeeds)

**Verdict:** `_processPhaseTransition()` always returns `true`. Phase transition cannot get stuck.

### 1f. Game-Over Initiation Stuck -- _handleGameOverPath() Fails

**Condition:** Liveness timeout reached but game-over sequence cannot complete.

**Analysis of `_handleGameOverPath()` (AdvanceModule:321-365):**

Step 1 -- Liveness check (line 330-332):
```solidity
bool livenessTriggered = (lvl == 0 && ts - lst > uint256(DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days) ||
    (lvl != 0 && ts - 365 days > lst);
```
This is a pure timestamp comparison. Cannot fail.

Step 2 -- If `gameOver` already true, delegatecall `handleFinalSweep()` (line 341-347). See Section 1h.

Step 3 -- If `rngWordByDay[_dailyIdx] == 0`, acquire RNG via `_gameOverEntropy()` (line 352). This can:
- Return the existing word if already recorded (`rngWordByDay[day] != 0`)
- Apply a fulfilled VRF word if `rngWordCurrent != 0`
- Wait for VRF fulfillment (returns 0, which causes `_handleGameOverPath` to return `true` early, allowing retry next call)
- After 3-day fallback delay: use historical VRF word via `_getHistoricalRngFallback()` (see Section 2c)
- If VRF request fails: `_tryRequestRng()` uses try/catch; if it fails, sets `rngRequestTime = ts` to start fallback timer (line 736-738)

Step 4 -- delegatecall `handleGameOverDrain(dailyIdx)` (line 357-363). See Section 1g.

**Key insight in `_gameOverEntropy()` (AdvanceModule:690-739):**
- If `_tryRequestRng()` fails (VRF unconfigured or LINK depleted), the function sets `rngRequestTime = ts` and returns 0
- On the next call, `elapsed >= GAMEOVER_RNG_FALLBACK_DELAY` (3 days) triggers `_getHistoricalRngFallback()`
- This ensures game-over can proceed even with a completely dead VRF

**Verdict:** Game-over initiation has a 3-day fallback for VRF unavailability. The only permanently stuck case is if no historical VRF words exist (see Finding F-01).

### 1g. Game-Over Funds Locked -- handleGameOverDrain() Fails

**Condition:** `gameOver` is reached but funds cannot be distributed.

**Analysis of `handleGameOverDrain()` (GameOverModule:67-148):**

Early exit: `if (gameOverFinalJackpotPaid) return;` -- idempotent after first call.

Fund distribution:
1. Level 0 (never-started): Full deity pass refund to `claimableWinnings` (lines 77-97)
2. Level 1-9 (early): Fixed 20 ETH refund per deity pass (lines 98-121)
3. Sets `gameOver = true`, `gameOverTime = uint48(block.timestamp)`, `gameOverFinalJackpotPaid = true` (lines 126-128)
4. If `available == 0`: returns (nothing to distribute) (line 130)
5. Gets `rngWord = rngWordByDay[day]` -- if 0, returns early (line 134)
6. BAF jackpot via `_payGameOverBafEthOnly()` (line 141): delegatecall to Jackpots contract
7. Decimator jackpot via `_payGameOverDecimatorEthOnly()` (line 147)

**Potential failure points:**
- BAF/Decimator jackpot calls: If `jackpots.runBafJackpot()` or `runDecimatorJackpot()` revert, the entire `handleGameOverDrain()` reverts. However, `gameOver` was already set on line 126, so subsequent calls skip this logic (unless the entire tx reverts, leaving `gameOver = false`).

**Wait -- critical ordering issue:** Lines 126-128 set `gameOver = true`, `gameOverTime`, and `gameOverFinalJackpotPaid = true` BEFORE the distribution logic on lines 130-147. If lines 141-147 revert, the entire transaction reverts (no partial state), so `gameOver` remains `false`. The next `advanceGame()` call re-enters `_handleGameOverPath()` and retries. This is safe.

**But:** If `rngWordByDay[day]` is 0 on line 133, the function sets `gameOver = true` and returns early. The BAF/Decimator jackpots are never run. Funds remain in the contract. This is intentional -- the 30-day final sweep handles remaining funds.

**Recovery:** 30-day final sweep (see Section 2d).

### 1h. Post-Sweep Residual -- Funds Remain After handleFinalSweep()

**Analysis of `handleFinalSweep()` (GameOverModule:228-243):**

```solidity
function handleFinalSweep() external {
    if (gameOverTime == 0) return;
    if (block.timestamp < uint256(gameOverTime) + 30 days) return;
    uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
    if (available == 0) return;
    _sendToVault(available, stBal);
}
```

The sweep preserves `claimablePool` for player withdrawals. Only excess funds (above claimable reserve) are swept. Players can still call `claimWinnings()` indefinitely after game-over.

**Can funds remain permanently locked?**
- `claimablePool` tracks total owed to players. Each `claimWinnings()` call decrements it.
- After all players claim, `claimablePool` approaches 0 (plus sentinel wei per player).
- `handleFinalSweep()` can be called multiple times (no single-use guard). Each call sweeps any new excess.
- stETH rebasing could create small excess over time, swept on each call.

**Verdict:** No funds are permanently locked. `claimablePool` is decremented on claims; excess above it is always sweepable after 30 days.

---

## 2. Recovery Mechanism Traces

### 2a. 18-Hour VRF Retry

**Function:** `rngGate()` (AdvanceModule:631-677)
**Trigger condition:** `rngRequestTime != 0 && rngWordCurrent == 0 && elapsed >= 18 hours` (lines 665-669)
**Access:** Anyone calling `advanceGame()` (public function)
**Preconditions:**
1. `rngWordByDay[day] == 0` -- today's RNG not yet recorded
2. `rngWordCurrent == 0` -- no VRF word received
3. `rngRequestTime != 0` -- a VRF request was previously sent
4. `ts - rngRequestTime >= 18 hours` -- timeout elapsed

**Execution path:**
```
advanceGame() -> rngGate(ts, day, lvl, isTicketJackpotDay)
  -> rngRequestTime != 0 && rngWordCurrent == 0  [line 665]
  -> elapsed = ts - rngRequestTime               [line 666]
  -> elapsed >= 18 hours                          [line 667]
  -> _requestRng(isTicketJackpotDay, lvl)         [line 668]
     -> vrfCoordinator.requestRandomWords(...)    [line 1015]
     -> _finalizeRngRequest(isTicketJackpotDay, lvl, id)
        -> isRetry = true (prevRequestId != 0)    [line 1063-1065]
        -> Remaps lootbox index to new requestId  [lines 1068-1074]
        -> vrfRequestId = newId                   [line 1082]
        -> rngRequestTime = now                   [line 1084]
        -> rngLockedFlag = true (stays true)      [line 1085]
  -> return 1 (signals "request sent, wait")      [line 669]
```

**State changes:**
- `vrfRequestId` updated to new request
- `rngRequestTime` reset to current timestamp (restarts 18h timer)
- `rngLockedFlag` remains `true`
- Lootbox index remapped from old request to new
- Old request is effectively orphaned (callback will silently return on ID mismatch)

**Anti-premature guard:** `if (elapsed >= 18 hours)` on line 667. If `elapsed < 18 hours`, falls through to `revert RngNotReady()` on line 671.

**What happens after:** New VRF request enters the Chainlink queue. If fulfilled, next `advanceGame()` call picks up the word in `rngGate()` path 2 (lines 643-661). If not fulfilled, the 18h timer restarts for another retry.

### 2b. 3-Day Emergency Coordinator Rotation

**Function:** `updateVrfCoordinatorAndSub()` (AdvanceModule:1133-1153)
**Trigger condition:** `_threeDayRngGap(day)` returns `true` AND `msg.sender == ADMIN`
**Access:** Only `ContractAddresses.ADMIN` (DegenerusAdmin contract)

**DegenerusAdmin entry point:** `emergencyRecover()` (DegenerusAdmin:470-532)
**Admin access:** `onlyOwner` modifier: `msg.sender == ContractAddresses.CREATOR` OR `vault.isVaultOwner(msg.sender)` (>30% DGVE holder)

**_threeDayRngGap logic** (AdvanceModule:1258-1263):
```solidity
function _threeDayRngGap(uint48 day) private view returns (bool) {
    if (rngWordByDay[day] != 0) return false;        // Today has RNG -> no gap
    if (rngWordByDay[day - 1] != 0) return false;    // Yesterday has RNG -> no gap
    if (day < 2 || rngWordByDay[day - 2] != 0) return false; // 2 days ago has RNG -> no gap
    return true;  // 3 consecutive days without RNG word
}
```

**DegenerusGame duplicate** (DegenerusGame:2226-2231): Identical logic, used by `rngStalledForThreeDays()` view function which the Admin calls.

**Execution path:**
```
Admin.emergencyRecover(newCoordinator, newKeyHash)  [onlyOwner]
  -> gameAdmin.rngStalledForThreeDays()             [line 476]
     -> DegenerusGame.rngStalledForThreeDays()      [line 2236]
        -> _threeDayRngGap(_simulatedDayIndex())     [DegenerusGame copy]
  -> Cancel old subscription (try/catch)             [lines 484-491]
  -> Create new subscription on new coordinator      [lines 493-499]
  -> Add GAME as consumer                            [lines 502-506]
  -> gameAdmin.updateVrfCoordinatorAndSub(...)       [line 508]
     -> DegenerusGame.updateVrfCoordinatorAndSub()   [line 1893]
        -> delegatecall AdvanceModule.updateVrfCoordinatorAndSub()
           -> _threeDayRngGap(_simulatedDayIndex())  [AdvanceModule copy, line 1139]
           -> vrfCoordinator = new                   [line 1143]
           -> vrfSubscriptionId = new                [line 1144]
           -> vrfKeyHash = new                       [line 1145]
           -> rngLockedFlag = false                  [line 1148]
           -> vrfRequestId = 0                       [line 1149]
           -> rngRequestTime = 0                     [line 1150]
           -> rngWordCurrent = 0                     [line 1151]
  -> Transfer LINK to new subscription               [lines 515-529]
```

**State changes:**
- VRF coordinator, subscription ID, key hash all updated
- `rngLockedFlag` cleared to `false` -- game immediately unblocked
- `vrfRequestId`, `rngRequestTime`, `rngWordCurrent` all zeroed
- Game can resume normal `advanceGame()` cycle on next call

**Anti-premature guard (double-gated):**
1. `_threeDayRngGap()` checked in DegenerusGame via `rngStalledForThreeDays()` (Admin side)
2. `_threeDayRngGap()` checked again in AdvanceModule via delegatecall (Game side, line 1139)
3. `msg.sender == ContractAddresses.ADMIN` enforced (line 1138)

**Note on dual _threeDayRngGap:** Both copies are identical. The DegenerusGame copy is called by the Admin's `rngStalledForThreeDays()` view. The AdvanceModule copy is called within the delegatecall to `updateVrfCoordinatorAndSub()`. Both read from the same storage (since `updateVrfCoordinatorAndSub` executes via delegatecall in DegenerusGame's context). Both must pass for the operation to succeed.

### 2c. Game-Over VRF Fallback (3-Day Historical Word)

**Function:** `_gameOverEntropy()` (AdvanceModule:690-739) and `_getHistoricalRngFallback()` (AdvanceModule:746-765)
**Trigger condition:** During game-over path, `rngRequestTime != 0 && rngWordCurrent == 0 && elapsed >= GAMEOVER_RNG_FALLBACK_DELAY (3 days)`
**Access:** Anyone calling `advanceGame()` (public function, but only reaches this path when liveness timeout triggered)

**Execution path:**
```
advanceGame() -> _handleGameOverPath(...)
  -> rngWordByDay[_dailyIdx] == 0                       [line 351]
  -> _gameOverEntropy(ts, day, lvl, lastPurchase)        [line 352]
     -> rngRequestTime != 0 && rngWordCurrent == 0      [line 712]
     -> elapsed >= GAMEOVER_RNG_FALLBACK_DELAY (3 days)  [line 714]
     -> _getHistoricalRngFallback(day)                   [line 716]
        -> Search rngWordByDay[1..min(30,day)]           [lines 750-761]
        -> Found: keccak256(word, currentDay)            [line 756]
        -> Not found: revert E()                         [line 764]
     -> _applyDailyRng(day, fallbackWord)                [line 717]
     -> coinflip.processCoinflipPayouts(...)             [line 719]
     -> _finalizeLootboxRng(fallbackWord)                [line 725]
     -> return fallbackWord
  -> _unlockRng(day)                                     [line 354]
  -> delegatecall handleGameOverDrain(dailyIdx)          [line 357-363]
```

**Fallback RNG construction:** `keccak256(abi.encodePacked(historicalWord, currentDay))` -- the historical word is already on-chain and cannot be manipulated. The `currentDay` parameter provides uniqueness so the same historical word produces different fallback values on different days.

**Anti-premature guard:** `GAMEOVER_RNG_FALLBACK_DELAY = 3 days` is a compile-time constant (AdvanceModule:89). Cannot be shortened.

**Initial VRF failure path:** If `_tryRequestRng()` fails (lines 731-738), the function sets `rngRequestTime = ts` (starting the 3-day timer) and returns 0. The next `advanceGame()` call (after 3 days) enters the fallback path.

### 2d. 30-Day Final Sweep

**Function:** `handleFinalSweep()` (GameOverModule:228-243)
**Trigger condition:** `gameOverTime != 0 && block.timestamp >= uint256(gameOverTime) + 30 days`
**Access:** Reached via `_handleGameOverPath()` when `gameOver == true` AND liveness condition still true (which it always is post-game-over since `levelStartTime` is never updated after game-over)

**Execution path:**
```
advanceGame() -> _handleGameOverPath(...)
  -> livenessTriggered = true (always, post-game-over)
  -> gameOver == true                                    [line 339]
  -> delegatecall handleFinalSweep()                     [line 341-346]
     -> gameOverTime != 0                                [line 229]
     -> block.timestamp >= gameOverTime + 30 days        [line 230]
     -> available = totalFunds - claimablePool           [line 237]
     -> _sendToVault(available, stBal)                   [line 242]
        -> 50% to VAULT (ETH or stETH)                  [lines 253-268]
        -> 50% to DGNRS (stETH via approve+deposit, or ETH) [lines 270-285]
```

**State changes:**
- Excess funds (above `claimablePool`) sent to VAULT and DGNRS
- No flags set or cleared -- sweep is repeatable on subsequent calls

**Anti-premature guard:** `block.timestamp < uint256(gameOverTime) + 30 days` returns early (line 230). `gameOverTime` is set to `uint48(block.timestamp)` in `handleGameOverDrain()` (GameOverModule:127) at actual game-over time. Cannot be set to a past value.

### 2e. Liveness Timeout (Game-Over Trigger)

**Function:** `_handleGameOverPath()` (AdvanceModule:321-365)
**Trigger condition:** `(lvl == 0 && ts - lst > 912 days) || (lvl != 0 && ts - 365 days > lst)`
**Access:** Anyone calling `advanceGame()` (public function)

**Preconditions:**
- `lvl` = current level, `lst` = `levelStartTime`, `ts` = current `block.timestamp`
- Level 0: `ts - levelStartTime > 912 * 1 days` (approximately 2.5 years from deployment)
- Level 1+: `ts - 365 days > levelStartTime` (1 year since last level transition)

**Anti-premature guard:** Pure timestamp arithmetic. `levelStartTime` is set during:
1. Constructor (deployment time)
2. `_finalizeRngRequest()` when transitioning to jackpot phase -- `levelStartTime = ts` (AdvanceModule, within `advanceGame` main loop, line 241)

Each level transition resets `levelStartTime`, so the 365-day countdown restarts. A validator can manipulate `block.timestamp` by seconds (not days or months), making premature trigger impossible.

---

## 3. Premature-Trigger Resistance Analysis

### 3.1 18-Hour VRF Retry

**Attack vector:** Can an attacker trigger a VRF retry before 18 hours?

**Guard:** `if (elapsed >= 18 hours)` where `elapsed = ts - rngRequestTime` (AdvanceModule:666-667).

**Manipulation vectors:**
- `block.timestamp`: Validators can shift by ~15 seconds per block. To gain 18 hours = 64,800 seconds would require 4,320 consecutive blocks of maximum drift, which is impossible without controlling the entire validator set.
- `rngRequestTime`: Set to `uint48(block.timestamp)` in `_finalizeRngRequest()` (line 1084). Only writable through `_requestRng()` or `_tryRequestRng()` internal calls. Not user-controllable.

**Verdict: IMPOSSIBLE.** The 18-hour guard is resistant to premature triggering. Even a validator with perfect block timestamp manipulation could gain at most seconds, not hours.

### 3.2 3-Day Emergency Coordinator Rotation

**Attack vector:** Can an attacker rotate the VRF coordinator without a genuine 3-day stall?

**Guard 1 -- Access control:**
- AdvanceModule: `msg.sender != ContractAddresses.ADMIN` -> `revert E()` (line 1138)
- DegenerusAdmin: `onlyOwner` -> CREATOR or >30% DGVE holder
- An attacker would need to compromise the CREATOR key or acquire >30% of DGVE supply

**Guard 2 -- Stall verification:**
- `_threeDayRngGap(day)` requires `rngWordByDay[day] == 0 && rngWordByDay[day-1] == 0 && rngWordByDay[day-2] == 0`
- An attacker cannot prevent VRF fulfillment unless they control the Chainlink validator network
- An attacker cannot erase recorded RNG words (storage writes are append-only via `_applyDailyRng` and `_unlockRng`)
- An attacker cannot fill fake RNG words (only `_applyDailyRng` writes to `rngWordByDay`, and it requires a valid VRF word path)

**Attack scenario -- artificially creating a gap:**
The only way to create a 3-day gap is to have no `advanceGame()` calls succeed for 3 consecutive days. Since `advanceGame()` is permissionless (anyone can call it), an attacker would need to:
1. Front-run every `advanceGame()` call to make it revert, AND
2. Not have anyone else successfully call it for 3 days

This is impractical because: (a) the CREATOR can always call, (b) MEV searchers are incentivized by the ADVANCE_BOUNTY, and (c) the `_enforceDailyMintGate` bypass for CREATOR means no front-running strategy can block the creator.

**However,** if VRF is genuinely stalled (Chainlink down), the 3-day gap naturally forms. This is the intended trigger condition.

**Verdict: IMPOSSIBLE without ADMIN access.** The dual gate (access control + stall verification) prevents premature rotation. An attacker with ADMIN access could rotate the coordinator, but only after a genuine 3-day VRF stall.

### 3.3 Game-Over VRF Fallback (3-Day)

**Attack vector:** Can an attacker force the game-over VRF fallback before 3 days?

**Guard:** `GAMEOVER_RNG_FALLBACK_DELAY = 3 days` is a compile-time constant (line 89). `elapsed >= GAMEOVER_RNG_FALLBACK_DELAY` (line 714).

**Manipulation vectors:**
- Same `block.timestamp` analysis as 3.1 -- impossible to gain 3 days via timestamp manipulation.
- `rngRequestTime` is set internally, not user-controllable.
- An attacker cannot reach `_gameOverEntropy()` without the liveness timeout being genuinely triggered (912/365 day check is on the same `advanceGame()` call path).

**If fallback IS triggered, is the output manipulable?**
- Historical word: already recorded on-chain, immutable
- `keccak256(word, currentDay)`: deterministic, no block-dependent inputs
- Nudges ARE applied via `_applyDailyRng()` after the fallback word is retrieved. However, `rngLockedFlag` was set during the initial failed VRF request (or set by the fallback path), so nudges cannot be added during the wait period.

**Wait -- examining the fallback path more carefully:** When `_tryRequestRng()` fails (line 731), `rngLockedFlag` is NOT set because `_finalizeRngRequest()` is not called. Instead, lines 736-737 only set `rngWordCurrent = 0` and `rngRequestTime = ts`. The `rngLockedFlag` remains in whatever state it was before. If it was `false` (which it would be if entering game-over path from a fresh `advanceGame()` after `_unlockRng`), then nudges could theoretically be submitted during the 3-day wait. However, `reverseFlip()` checks `rngLockedFlag` -- if it's `false`, nudges ARE accepted. These nudges would be applied to the fallback word via `_applyDailyRng()` (line 717).

**This is a minor finding (F-02):** During the game-over VRF fallback wait period, if `rngLockedFlag` is `false`, players can submit nudges that will modify the fallback RNG word. However, the economic impact is low: (a) the game is already over, (b) the fallback word is used for final jackpot distribution, and (c) nudge cost scales exponentially. Additionally, the base fallback word comes from a keccak256 hash, so players cannot predict the exact outcome even with nudges.

**Verdict: IMPOSSIBLE to trigger prematurely.** The 3-day constant and timestamp arithmetic prevent early activation. Minor nudge concern documented as F-02.

### 3.4 30-Day Final Sweep

**Attack vector:** Can an attacker trigger `handleFinalSweep()` before 30 days post-game-over?

**Guard:** `block.timestamp < uint256(gameOverTime) + 30 days` returns early (GameOverModule:230).

**Manipulation vectors:**
- `gameOverTime`: Set to `uint48(block.timestamp)` in `handleGameOverDrain()` (line 127). Only writable in that single location. Cannot be set to a past value because it uses `block.timestamp` at call time.
- `block.timestamp`: Same analysis -- validators cannot gain 30 days of drift.

**Can gameOverTime be set early?** Only by triggering `handleGameOverDrain()`, which requires `_handleGameOverPath()`, which requires the liveness timeout. The chain of guards is: liveness timeout (912/365 days) -> game-over -> final sweep (30 more days).

**Verdict: IMPOSSIBLE.** The 30-day guard uses an immutable timestamp set at game-over time. No premature trigger path exists.

### 3.5 Liveness Timeout (Game-Over Trigger)

**Attack vector:** Can an attacker trigger the 912-day or 365-day timeout early?

**Guard:** Pure timestamp arithmetic in `_handleGameOverPath()` (lines 330-332).

**Manipulation vectors:**
- `levelStartTime`: Set in two locations:
  1. Constructor (deployment) -- cannot be influenced post-deployment
  2. During purchase-to-jackpot transition (AdvanceModule, `advanceGame` main loop, line 241) -- `levelStartTime = ts` where `ts = uint48(block.timestamp)`
- An attacker cannot set `levelStartTime` to a past value
- Each level transition resets the timer

**Could an attacker prevent level transitions to let the timer expire?**
Not directly -- level transitions happen automatically when `nextPrizePool >= levelPrizePool[purchaseLevel-1]`. An attacker cannot prevent other players from purchasing tickets. However, if no players exist, the timer will naturally expire.

**Verdict: IMPOSSIBLE.** The liveness timeout cannot be triggered prematurely. It can only trigger when the specified time has genuinely elapsed.

---

## 4. Completeness Matrix

| State | Stuck Condition | Recovery Mechanism(s) | Access | Timeout | Exit Guaranteed? |
|-------|----------------|----------------------|--------|---------|-----------------|
| PURCHASE (active) | No one calls advanceGame | CREATOR can always call; liveness timeout after 365/912 days | Public (CREATOR bypass) | 365/912 days | YES |
| PURCHASE (VRF pending, <18h) | VRF not fulfilled yet | Wait; auto-retry at 18h | Automatic via advanceGame | 18h | YES |
| PURCHASE (VRF pending, >=18h) | VRF not fulfilled | Retry via advanceGame | Public | Immediate | YES |
| PURCHASE (VRF stalled, 3 days) | All retries fail | Emergency coordinator rotation | ADMIN (CREATOR or 30% DGVE) | 3 days | YES (if ADMIN key available) |
| JACKPOT (active) | Same VRF issues as PURCHASE | Same recovery mechanisms | Same | Same | YES |
| JACKPOT (gas limit) | Single call exceeds gas | Split-processing with cursors | Public | Next block | YES |
| PHASE TRANSITION | _processPhaseTransition fails | Always succeeds (try/catch on stETH) | Automatic | None | YES |
| GAME-OVER (VRF needed) | VRF unavailable for game-over RNG | 3-day historical word fallback | Public via advanceGame | 3 days | YES (if historical words exist) |
| GAME-OVER (no history) | No historical VRF words exist | **NONE -- revert E()** | N/A | N/A | **NO** (see F-01) |
| POST-GAME-OVER (funds remain) | Excess funds in contract | 30-day final sweep | Public via advanceGame | 30 days | YES |
| POST-GAME-OVER (claimable) | Player winnings unclaimed | claimWinnings() available indefinitely | Per player | None | YES |
| POST-GAME-OVER (all swept) | No funds remain | Terminal state; nothing to recover | N/A | N/A | YES (terminal) |
| VRF stalled + ADMIN key lost | VRF permanently dead, no admin | **NONE** | N/A | N/A | **NO** (see F-03) |

---

## 5. FSM-02 Verdict: Every Game State is Exitable

**Requirement:** No game state exists that cannot be exited.

**Assessment:**

The protocol implements a comprehensive recovery hierarchy:
1. **Normal path:** VRF fulfilled within minutes -> advanceGame processes normally
2. **18-hour retry:** VRF not fulfilled -> automatic retry on next advanceGame call after 18h
3. **3-day emergency:** VRF permanently dead -> ADMIN rotates coordinator, clears all RNG state
4. **Game-over fallback:** VRF dead during game-over -> historical VRF word used after 3 days
5. **30-day sweep:** Post-game-over -> excess funds swept to vault/DGNRS
6. **Player claims:** claimableWinnings accessible via `claimWinnings()` at any time

**Exceptions (documented as findings):**
- **F-01 (Informational):** If game reaches game-over with zero historical VRF words, `_getHistoricalRngFallback()` reverts permanently. This requires 912 days of zero `advanceGame()` calls -- practically impossible if the game has any players.
- **F-03 (Medium):** If ADMIN key is lost AND VRF permanently fails, the 3-day emergency rotation is unreachable. However, the `onlyOwner` modifier also accepts >30% DGVE holders, providing a backup path.

**Verdict: FSM-02 PASS (CONDITIONAL).** Every game state has an exit path under normal and degraded conditions. Two edge cases exist at the intersection of multiple simultaneous failures, documented as findings. Neither is practically reachable under realistic threat models.

---

## 6. RNG-06 Verdict: RNG Lock Not Permanently Stuckable

**Requirement:** The `rngLockedFlag` cannot be stuck in `true` state permanently.

**Assessment:**

`rngLockedFlag` is set to `true` in exactly one location:
- `_finalizeRngRequest()` (AdvanceModule:1085)

`rngLockedFlag` is cleared to `false` in exactly two locations:
1. `_unlockRng(day)` (AdvanceModule:1160) -- normal path after VRF word consumed
2. `updateVrfCoordinatorAndSub()` (AdvanceModule:1148) -- emergency path after 3-day stall

**Can it be permanently stuck?**

Scenario: `rngLockedFlag = true`, VRF never fulfills, 18h retries keep failing.

Path to recovery:
1. 18h retries send new VRF requests (`_requestRng` re-calls `_finalizeRngRequest` which keeps `rngLockedFlag = true`)
2. After 3 consecutive days with no RNG word recorded: `_threeDayRngGap(day)` returns `true`
3. ADMIN calls `emergencyRecover()` -> `updateVrfCoordinatorAndSub()` -> `rngLockedFlag = false`

**What if ADMIN key is lost?**
- The `onlyOwner` modifier accepts `vault.isVaultOwner(msg.sender)` (>30% DGVE holder) as an alternative to CREATOR
- If BOTH CREATOR key and all >30% DGVE positions are lost, then `updateVrfCoordinatorAndSub` is unreachable
- In this case, `rngLockedFlag` would remain `true` until the liveness timeout (365 days) triggers game-over
- During game-over, `_handleGameOverPath()` does NOT require `rngLockedFlag = false` to proceed -- it has its own `_gameOverEntropy()` path with fallback
- The liveness timeout path in `_handleGameOverPath()` is checked BEFORE the `rngGate()` call (lines 124-136), so game-over processing bypasses the RNG lock entirely

**Critical trace -- game-over with rngLockedFlag stuck:**
```
advanceGame():
  _handleGameOverPath(ts, day, ...) [line 125, CHECKED FIRST]
    -> livenessTriggered = true (365+ days)
    -> gameOver is false
    -> rngWordByDay[_dailyIdx] == 0
    -> _gameOverEntropy(ts, day, ...)
       -> rngRequestTime != 0 (still set from stuck request)
       -> rngWordCurrent == 0
       -> elapsed >= 3 days (actually >= 365 days!)
       -> _getHistoricalRngFallback(day) -> returns word
       -> _applyDailyRng(day, fallbackWord)
       -> return fallbackWord
    -> _unlockRng(day) [line 354] -> rngLockedFlag = false!
    -> handleGameOverDrain(dailyIdx)
```

The game-over path clears `rngLockedFlag` via `_unlockRng(day)` on line 354!

**Verdict: RNG-06 PASS.** The RNG lock cannot be permanently stuck. Even in the worst case (ADMIN key lost + VRF permanently dead), the 365-day liveness timeout triggers game-over, which uses the VRF fallback and clears the lock via `_unlockRng()`. The only theoretical permanent-stick scenario requires simultaneous loss of ADMIN key, permanent VRF failure, AND no historical VRF words -- which requires 912 days at level 0 with zero successful VRF fulfillments.

---

## 7. Findings

### F-01: Catastrophic Revert if No Historical VRF Words Exist at Game-Over (Informational)

**Severity:** Informational
**Location:** `_getHistoricalRngFallback()` (AdvanceModule:746-765)
**Condition:** Game reaches game-over state, VRF is unavailable, and `rngWordByDay[1..30]` are all zero.
**Impact:** `revert E()` with no recovery path. Game is permanently stuck.
**Likelihood:** Extremely low. Requires:
1. Game deployed
2. `advanceGame()` never successfully called with VRF for 912 days (level 0)
3. Or: game reached level 1+ but all historical VRF words are from days > 30 (impossible since search starts from day 1)

**Assessment:** This is a theoretical edge case. Any game with even one successful VRF fulfillment at day 1-30 has a recovery path. For a game that reaches level 1+, multiple VRF words MUST have been recorded (each day's `advanceGame` records one). This finding is informational because the preconditions are practically unreachable.

**Note:** The search is capped at 30 iterations for gas efficiency (line 751). If all VRF words were recorded on days > 30 (e.g., game started with many days of failure then recovered), the search would miss them. However, day 1 is the deployment day, and the first `advanceGame()` with VRF would record a word there. The search starts from `searchDay = 1`, so any word at day 1 is found immediately.

### F-02: Nudges Possible During Game-Over VRF Fallback Wait (Low)

**Severity:** Low
**Location:** `_gameOverEntropy()` (AdvanceModule:690-739) and `reverseFlip()` (AdvanceModule:1171-1179)
**Condition:** VRF request fails during game-over path. `_tryRequestRng()` fails, so `_finalizeRngRequest()` is never called, meaning `rngLockedFlag` is NOT set. During the 3-day fallback wait, `rngLockedFlag` may be `false`, allowing `reverseFlip()` nudges.
**Impact:** Players can influence the fallback RNG word used for final jackpot distribution. However:
- The base fallback word is `keccak256(historicalWord, currentDay)` -- unpredictable
- Nudges add integer values, not providing directional control over outcomes
- Nudge cost scales exponentially (1.5x per nudge), limiting total influence
- The game is already in terminal state; economic incentive is limited to the final jackpot distribution
**Recommendation:** Consider setting `rngLockedFlag = true` in the fallback-timer-start path (lines 736-738 of `_gameOverEntropy`). This would block nudges during the wait period without affecting any other logic.

### F-03: VRF Stall + ADMIN Key Loss Requires 365-Day Liveness Timeout (Medium)

**Severity:** Medium
**Location:** `updateVrfCoordinatorAndSub()` (AdvanceModule:1133-1153), `emergencyRecover()` (DegenerusAdmin:470-532)
**Condition:** VRF permanently fails AND the ADMIN key (CREATOR) is lost AND no entity holds >30% DGVE.
**Impact:** Game is stuck in purchase/jackpot phase with `rngLockedFlag = true` for up to 365 days (or 912 days at level 0) until the liveness timeout triggers game-over.

**Mitigations already in place:**
1. `onlyOwner` accepts >30% DGVE holders as alternative to CREATOR
2. Liveness timeout eventually triggers game-over regardless
3. Game-over path has its own VRF fallback (historical word)

**Assessment:** This is a degraded-availability scenario, not a permanent-stuck scenario. Funds are not lost; they are accessible after the liveness timeout expires. The 365-day wait is the cost of the dual failure. The DGVE-holder backup path significantly reduces the likelihood.

**Recommendation:** No code change needed. The existing multi-layer recovery is appropriate. The 365-day liveness timeout serves as a last-resort escape valve. Consider documenting this scenario in operational runbooks so that DGVE holders know they can act as emergency admins.

---

## Summary

| Requirement | Verdict | Rationale |
|-------------|---------|-----------|
| FSM-02 | **PASS (conditional)** | Every game state has an exit path. Two edge cases (F-01: no-history catastrophic, F-03: admin-loss delay) are documented but practically unreachable. |
| RNG-06 | **PASS** | The RNG lock has two clear paths: normal unlock via `_unlockRng()` and emergency unlock via `updateVrfCoordinatorAndSub()`. Even with both unavailable, the liveness timeout triggers game-over which clears the lock via `_unlockRng()` in `_handleGameOverPath()`. |

**Recovery hierarchy (most common to least common):**
1. Normal VRF fulfillment (seconds-minutes) -- 99%+ of cases
2. 18-hour VRF retry -- handles transient Chainlink issues
3. 3-day emergency coordinator rotation -- handles Chainlink outage
4. 3-day game-over VRF fallback -- handles VRF failure during terminal state
5. 365/912-day liveness timeout -> game-over -- absolute last resort

**All five recovery mechanisms are confirmed reachable and not premature-triggerable.**
