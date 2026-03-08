# ECON-05: Block Proposer Timing Manipulation Analysis

**Requirement:** Block proposer cannot manipulate advanceGame timing to control which level transitions occur

**Verdict: PASS**

The block proposer's only lever is WHEN advanceGame executes, not WHAT it does. VRF words are pre-committed by Chainlink, day-index gates limit advanceGame to once per day boundary, and all prize distribution outcomes are deterministic from (VRF word, game state) with no block-manipulable inputs.

---

## 1. advanceGame State Machine Trace

### 1a. Day-Index Gate

```solidity
// AdvanceModule.sol line 117-118
uint48 ts = uint48(block.timestamp);
uint48 day = _simulatedDayIndexAt(ts);

// AdvanceModule.sol line 140
if (day == dailyIdx) revert NotTimeYet();
```

**Day computation chain:**

1. `_simulatedDayIndexAt(ts)` calls `GameTimeLib.currentDayIndexAt(ts)`
2. `GameTimeLib.currentDayIndexAt(ts)`:
   ```solidity
   uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
   return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
   ```
3. `JACKPOT_RESET_TIME = 82620` (22:57 UTC)
4. `1 days = 86400 seconds`

The day index is `block.timestamp` divided by 86400 (with a 22:57 UTC offset). Two calls in the same calendar day (22:57-to-22:57) produce the same `day` value and the second reverts with `NotTimeYet()`.

**Key property:** A block proposer can manipulate `block.timestamp` by at most +-15 seconds per Ethereum consensus rules. Since the day boundary spans 86,400 seconds, a +-15 second manipulation can only matter at the exact 22:57 UTC boundary:

- **Within a day:** No effect. Day value is identical regardless of +-15 seconds.
- **At day boundary:** Proposer could advance or delay the day transition by at most one block (12 seconds). But the next block's proposer can include the transaction anyway, so the delay is at most 12 seconds -- trivial compared to the 24-hour day cycle.

### 1b. VRF Word Consumption

```solidity
// AdvanceModule.sol line 145
uint256 rngWord = rngGate(ts, day, purchaseLevel, lastPurchase);
```

The `rngGate` function (lines 631-677):

1. Checks `rngWordByDay[day]` -- if already recorded for today, returns it (idempotent)
2. Checks `rngWordCurrent` -- if a fulfilled VRF word exists, processes it via `_applyDailyRng`
3. If no VRF word exists, calls `_requestRng` and returns sentinel value 1 (advanceGame emits `STAGE_RNG_REQUESTED` and exits)

**Critical path:** When `rngWordCurrent != 0` and `rngRequestTime != 0`, the word is used. The VRF word was stored by `rawFulfillRandomWords` (called by the Chainlink VRF Coordinator) in a prior transaction:

```solidity
// rawFulfillRandomWords (line 1199-1220)
if (rngLockedFlag) {
    rngWordCurrent = word;  // Stored for advanceGame to consume
}
```

**The proposer cannot change `rngWordCurrent`.** It was committed by Chainlink's VRF oracle and stored on-chain in a previous transaction. The proposer of the current block only decides whether to include the `advanceGame` call, not what VRF word it uses.

### 1c. Level Transition Logic

Level transitions are governed by:

```solidity
// AdvanceModule.sol line 196-198
if (nextPrizePool >= levelPrizePool[purchaseLevel - 1]) {
    lastPurchaseDay = true;
}
```

The transition condition is: `nextPrizePool >= levelPrizePool[purchaseLevel - 1]` (the ratchet target). This is purely a comparison of accumulated ETH from ticket purchases against the previous level's prize pool. No `block.timestamp` or block-manipulable value influences this comparison.

Level increment occurs at VRF request time (not at advanceGame execution time):

```solidity
// _finalizeRngRequest (line 1096-1097)
if (isTicketJackpotDay && !isRetry) {
    level = lvl;  // lvl is purchaseLevel at this point
}
```

Since `isTicketJackpotDay` is `lastPurchaseDay` (determined by prize pool threshold), and the VRF request occurs within the same `advanceGame` call, the proposer cannot separate the threshold check from the level increment.

### 1d. Jackpot Distribution

All jackpot distribution functions receive `rngWord` as a parameter:

```solidity
payDailyJackpot(false, purchaseLevel, rngWord);        // line 194
_payDailyCoinJackpot(purchaseLevel, rngWord);           // line 195
_consolidatePrizePools(purchaseLevel, rngWord);         // line 222
payDailyJackpot(true, lvl, rngWord);                    // line 282
payDailyJackpotCoinAndTickets(rngWord);                 // line 267
```

The JackpotModule (`DegenerusGameJackpotModule.sol`) contains **zero references** to `block.timestamp`, `blockhash`, or `block.number`. All winner selection is purely derived from:

- `rngWord` (VRF-committed)
- Game state (ticket arrays, prize pools)
- Deterministic bucket/cursor iteration

The EndgameModule similarly has **zero references** to `block.timestamp`. Winner selection in endgame settlements is also purely VRF + game state.

---

## 2. Block Proposer Timing Control

### 2a. Include/Exclude advanceGame

**Capability:** The proposer can choose not to include an `advanceGame` transaction in their block.

**Impact:** This delays `advanceGame` by at most 12 seconds (one block slot). Any user can submit `advanceGame`, and the next block's proposer (a different validator in Ethereum PoS) will include it. A proposer cannot permanently block `advanceGame`.

**Economic consequence:** Delaying `advanceGame` by one block does not change the outcome. The same VRF word will be consumed, the same prize pool threshold check will execute, and the same jackpot winners will be selected. The delay only shifts the execution timestamp by 12 seconds, which is below the day-boundary granularity.

### 2b. Timestamp Manipulation

**Capability:** The proposer can set `block.timestamp` within +-15 seconds of true time (Ethereum consensus constraint).

**Impact on day index:** Since `day = (ts - 82620) / 86400`, a +-15 second change affects the day boundary only within a 30-second window at exactly 22:57 UTC. At all other times, +-15 seconds produces the same day value.

**Impact on `_applyTimeBasedFutureTake`:** This function computes the future pool take based on `reachedAt - (levelStartTime + 11 days)`. The function uses day/week-scale thresholds (1 day, 14 days, 28 days). A +-15 second manipulation on these values produces a change in BPS of less than 0.02% (15 / 86400 = 0.017%), which is below the 10% variance band already applied by the RNG-based randomization in the same function:

```solidity
// Variance: +/-X% random adjustment (line 848-862)
uint256 variance = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000;  // 10%
```

The timestamp manipulation is completely dominated by the VRF-based variance.

### 2c. Transaction Ordering

**Capability:** The proposer can order their own transactions before or after `advanceGame` within their block.

**Impact:**

1. **Buying tickets before advanceGame:** The proposer buys at the current level's price. When `advanceGame` executes next, the tickets are already in the current level's pool. No cross-level value extraction.

2. **Buying tickets after advanceGame:** If `advanceGame` triggers a level transition, the proposer buys at the new (higher) price. No advantage.

3. **Claiming winnings before advanceGame:** If `advanceGame` would distribute jackpots, the proposer cannot claim winnings that haven't been distributed yet. Claiming only withdraws from `claimableWinnings[player]`, which is set during `advanceGame`, not before it.

4. **Claiming winnings after advanceGame:** Normal operation. The proposer claims newly distributed winnings in the same block. This is equivalent to any player claiming immediately after `advanceGame` -- no special advantage.

---

## 3. VRF Word Commitment Analysis

### 3a. VRF Word Lifecycle

1. `advanceGame` calls `rngGate`, which calls `_requestRng` if no VRF word is available
2. `_requestRng` calls `vrfCoordinator.requestRandomWords(...)` -- this submits an on-chain request to Chainlink
3. `_finalizeRngRequest` sets `rngLockedFlag = true` (line 1085), `rngWordCurrent = 0`, `rngRequestTime = block.timestamp`
4. After 10 block confirmations (VRF_REQUEST_CONFIRMATIONS = 10, ~120 seconds), Chainlink's VRF oracle generates the random word off-chain
5. The VRF coordinator calls `rawFulfillRandomWords` on the game contract
6. `rawFulfillRandomWords` stores the word: `rngWordCurrent = word` (line 1211)
7. The NEXT `advanceGame` call reads `rngWordCurrent` and processes the day

### 3b. Can the Proposer See and Act on the VRF Word?

**Yes, the proposer who includes `rawFulfillRandomWords` can see the VRF word in the transaction calldata.** However:

1. **rngLockedFlag is already set** (since step 3, ~120 seconds ago). This blocks:
   - `reverseFlip` (nudge) -- reverts with `RngLocked` (line 1172)
   - `setAutoRebuy` -- reverts with `RngLocked` (line 1573)
   - `setAfKingMode` -- reverts with `RngLocked` (line 1653)
   - `setDecimatorAutoRebuy` -- reverts with `RngLocked` (line 1552)
   - `requestLootboxRng` -- reverts with `E` (line 588)
   - Lootbox opening (lines 545, 622 of LootboxModule) -- reverts with `RngLocked`
   - Lootbox purchases with `lastPurchaseDay && (purchaseLevel % 5 == 0)` (MintModule line 607) -- reverts
   - MintModule recycled purchase during RNG lock (line 802) -- reverts

2. **Can the proposer call advanceGame in the same block as VRF fulfillment?**

   After `rawFulfillRandomWords` executes and sets `rngWordCurrent = word`, the state is:
   - `rngLockedFlag = true` (set by `_finalizeRngRequest`, NOT cleared by `rawFulfillRandomWords`)
   - `rngWordCurrent = word` (just set)
   - `rngRequestTime != 0` (still set from the request)

   If a proposer orders `advanceGame` AFTER `rawFulfillRandomWords` in the same block:
   - `advanceGame` reads `day = _simulatedDayIndexAt(block.timestamp)`
   - Checks `day == dailyIdx` -- if day hasn't changed, reverts `NotTimeYet()`
   - If day HAS changed: enters `rngGate`, which finds `rngWordCurrent != 0 && rngRequestTime != 0`
   - Processes the VRF word normally via `_applyDailyRng`

   **This IS possible but provides NO advantage.** The VRF word is already committed. `advanceGame`'s output is deterministic from the committed word and game state. The proposer sees the word but cannot change the game's response to it. They cannot front-run with state changes because `rngLockedFlag` blocks all state-changing operations.

3. **rawFulfillRandomWords does NOT clear rngLockedFlag.** This is confirmed at line 1209-1211:
   ```solidity
   if (rngLockedFlag) {
       rngWordCurrent = word;  // Store only, do not clear lock
   }
   ```
   The lock is cleared only by `_unlockRng(day)` (called within `advanceGame` after processing) or by `updateVrfCoordinatorAndSub` (emergency rotation). This means the proposer CANNOT:
   - See the VRF word
   - Clear the lock
   - Make state changes based on the word
   - Then let `advanceGame` execute

   The lock persists through VRF fulfillment, preventing any state manipulation between seeing the word and consuming it.

### 3c. VRF Fulfillment Withholding

**Can the proposer withhold `rawFulfillRandomWords`?**

Yes, a proposer can choose not to include the VRF fulfillment transaction in their block. However:

1. The VRF fulfillment will be included by the next honest proposer (within 12 seconds)
2. The VRF word is generated by Chainlink's oracle, not by the proposer -- withholding does not change the word
3. If VRF is not fulfilled within 18 hours, `rngGate` allows a retry:
   ```solidity
   // rngGate line 666-668
   uint48 elapsed = ts - rngRequestTime;
   if (elapsed >= 18 hours) {
       _requestRng(isTicketJackpotDay, lvl);
       return 1;
   }
   ```
4. A single proposer controls only 1 of ~900,000 slots per day. They cannot sustain VRF censorship.

---

## 4. Proposer Profit Scenarios

### Scenario 1: Delay advanceGame to Buy Tickets at Current Level Price

**Attack:** Proposer sees that `advanceGame` would trigger `lastPurchaseDay = true` (prize pool target met). They exclude `advanceGame` from their block and buy tickets at the current level price before the transition.

**Analysis:**
- Tickets purchased at the current level price go into the current level's ticket pool
- When `advanceGame` eventually executes (next block), the transition still occurs
- The proposer's tickets are at the current level, which will receive the current level's jackpot payouts
- There is no cross-level price arbitrage because tickets at level N earn jackpots from level N's pool, not level N+1's pool
- **Profit: None.** The proposer pays the correct price for the level they participate in.

### Scenario 2: Delay advanceGame to Prevent a Rival from Winning Jackpot

**Attack:** Proposer knows that `advanceGame` would distribute a jackpot. They delay it to prevent a rival from winning.

**Analysis:**
- The jackpot outcome is deterministic from the VRF word, which is already committed
- Delaying by one block (12 seconds) does not change who wins -- the same VRF word selects the same winners
- The proposer cannot change the VRF word or the game state during the `rngLockedFlag` window
- **Profit: None.** Delay changes timing, not outcomes.

### Scenario 3: Include advanceGame + Own Purchase in Same Block

**Attack:** Proposer orders `advanceGame` first (which transitions the level), then buys tickets at the new price in the same block.

**Analysis:**
- After `advanceGame` transitions to the new level, the price is updated
- The proposer buys at the new (higher) price
- This is identical to any user buying tickets after a level transition -- standard operation
- The proposer pays the correct price for the correct level
- **Profit: None.** This is normal game behavior.

### Scenario 4: Withhold rawFulfillRandomWords (Censor VRF)

**Attack:** Proposer sees the VRF fulfillment transaction and decides the VRF word would produce an unfavorable outcome (e.g., a rival wins the jackpot). They exclude the VRF fulfillment from their block.

**Analysis:**
- The VRF fulfillment is a Chainlink coordinator transaction. The next honest proposer includes it.
- A single proposer controls ~1/900,000 slots per day. Sustained censorship is infeasible.
- Even if delayed, the SAME VRF word will be delivered. The proposer cannot change the word.
- After 18 hours without fulfillment, the game re-requests VRF with a new request (generating a new word). But the proposer cannot predict this new word either.
- **Profit: None.** Temporary delay, no outcome change.

### Scenario 5: Selective Transaction Ordering Around Day Boundary

**Attack:** At the 22:57 UTC day boundary, the proposer manipulates `block.timestamp` by +-15 seconds to force `advanceGame` into the previous day or next day.

**Analysis:**
- If the proposer pushes `advanceGame` to the "next" day, it processes one day early relative to calendar time. But the VRF word for that day is the same regardless.
- If the proposer pushes `advanceGame` to the "previous" day, it would revert with `NotTimeYet()` because `dailyIdx` already equals the previous day.
- The maximum impact is a 15-second shift in when the day boundary is crossed. Since all outcomes within a day are deterministic from the VRF word (which is already committed), this shift changes nothing meaningful.
- The `_applyTimeBasedFutureTake` function's sensitivity to timestamp is dominated by the 10% VRF-based variance (see Section 2b).
- **Profit: None.** Day-level granularity absorbs +-15 second manipulation entirely.

### Scenario 6: Proposer Sees VRF Word and Front-Runs with Ticket Purchase

**Attack:** The proposer is also a player. They see the VRF word in the `rawFulfillRandomWords` calldata, determine whether they would win a jackpot, and buy/sell tickets accordingly.

**Analysis:**
- `rngLockedFlag` is already set (since the VRF request, ~120+ seconds ago)
- During `rngLockedFlag = true`:
  - Ticket purchases are allowed but do NOT change jackpot eligibility for the current day (tickets are already committed to the current level's pool from prior days)
  - The MintModule blocks lootbox purchases during `rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)` (line 607)
  - Auto-rebuy and afKing mode changes are blocked
  - Lootbox opening is blocked
- Ticket purchases during `rngLockedFlag` enter the current level's ticket pool for FUTURE jackpots, not the current day's distribution
- The proposer cannot retroactively add themselves to today's jackpot pool
- **Profit: None.** Seeing the VRF word does not enable extractive action because the lock prevents state changes that would affect the current distribution.

---

## 5. Timestamp Sensitivity Audit

All uses of `block.timestamp` in `advanceGame`'s execution path:

| Location | Use | Sensitivity to +-15s |
|----------|-----|---------------------|
| Line 117: `ts = uint48(block.timestamp)` | Captured for all timestamp uses | Base value |
| Line 118: `day = _simulatedDayIndexAt(ts)` | Day index computation (86400s granularity) | **None** except at exact 22:57 UTC boundary |
| Line 128: `_handleGameOverPath(ts, day, levelStartTime, ...)` | Liveness timeout check (365+ days) | **None** (15s vs 365 days) |
| Line 221: `_applyTimeBasedFutureTake(ts, purchaseLevel, rngWord)` | Future pool take BPS calculation | **Negligible** (15s vs 1-28 day thresholds, dominated by 10% VRF variance) |
| Line 241: `levelStartTime = ts` | Records when level started for future time-based calculations | +-15s on a value used with day-scale granularity |
| Line 1084: `rngRequestTime = uint48(block.timestamp)` | Records VRF request time for 18h retry check | +-15s on an 18-hour threshold is negligible |

**Conclusion:** No `block.timestamp` use in the advanceGame path is sensitive to the +-15 second manipulation available to a block proposer.

---

## 6. Cross-Reference with Prior Phase Findings

### Phase 2, Plan 01 (RNG-01, RNG-08):
- **RNG-01 PASS:** Lock continuously held from VRF request through word consumption with no exploitable gap
- **RNG-08 PASS:** Block proposer cannot front-run VRF fulfillment with reverseFlip nudges because lock is set 10+ blocks before fulfillment arrives

These findings are consistent with this analysis. The rngLockedFlag prevents the proposer from modifying game state between seeing the VRF word and its consumption by advanceGame.

### Phase 2, Plan 04 (FSM-01, FSM-03):
- **FSM-01 PASS:** All 7 legal transitions enumerated; 7 illegal transitions proved unreachable
- **FSM-03 PASS:** Multi-step game-over handles all intermediate states

The FSM transitions are deterministic from game state + VRF word. The block proposer cannot cause illegal transitions or skip states.

---

## 7. ECON-05 Verdict

### ECON-05: PASS

**Reasoning:**

1. **VRF word commitment:** The VRF word is generated by Chainlink's oracle, transmitted via `rawFulfillRandomWords`, and stored in `rngWordCurrent`. The proposer can see this word but cannot modify it. By the time the word arrives, `rngLockedFlag` has been set for 10+ blocks (~120 seconds), blocking all state-changing operations that could exploit foreknowledge.

2. **Deterministic outcomes:** All prize distribution functions (jackpot, endgame, level transition) receive `rngWord` as input and use no block-manipulable values (`block.timestamp`, `blockhash`, `block.number`). The JackpotModule and EndgameModule have zero references to any of these.

3. **Day-index gate:** `advanceGame` is limited to once per day boundary (86,400 seconds). A block proposer's +-15 second timestamp manipulation is absorbed entirely by this granularity.

4. **No cross-level arbitrage:** Tickets belong to the level at which they were purchased. Buying tickets before a level transition gives the proposer tickets at the current level's price -- which is the correct price for that level. There is no mechanism to extract value across levels.

5. **Single-block censorship limitation:** A proposer controls one block (12 seconds). They cannot sustain censorship of `advanceGame` or `rawFulfillRandomWords` transactions beyond one slot. The 18-hour VRF retry timeout provides a backstop.

6. **rngLockedFlag continuity:** The lock is set in `_finalizeRngRequest` (at VRF request time) and cleared in `_unlockRng` (after `advanceGame` processes the day). `rawFulfillRandomWords` does NOT clear the lock. This prevents the proposer from using the VRF-fulfillment-to-advanceGame gap for state manipulation.

**No findings.** The block proposer timing attack surface is fully mitigated by the combination of VRF commitment, rngLockedFlag, deterministic outcome computation, and day-level time granularity.

---

## Appendix: Attack Surface Summary Table

| Attack Vector | Proposer Capability | Defense Mechanism | Outcome |
|--------------|---------------------|-------------------|---------|
| Exclude advanceGame | Delay 12s (one block) | Next proposer includes it; outcomes unchanged | No profit |
| Timestamp manipulation | +-15 seconds | Day-level granularity (86,400s); 10% VRF variance dominates | No profit |
| Transaction ordering | Reorder within block | rngLockedFlag blocks state changes; ticket purchases enter correct level | No profit |
| VRF censorship | Exclude rawFulfillRandomWords | Next proposer includes it; 18h retry; word unchanged | No profit |
| VRF word foreknowledge | See word in calldata | rngLockedFlag already set 10+ blocks prior; blocked from state changes | No profit |
| Day boundary gaming | Shift day by +-15s | Day index absorbs; no outcome change within same day | No profit |
