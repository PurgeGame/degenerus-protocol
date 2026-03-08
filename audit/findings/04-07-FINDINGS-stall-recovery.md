# 04-07 Findings: Stall Recovery Path Audit

**Requirement:** ACCT-08 -- Verify stall recovery paths cannot be triggered prematurely and correctly attribute all pool funds.

**Scope:** All timeout/liveness guards in AdvanceModule and GameOverModule: 912-day deploy idle, 365-day inactivity, 18-hour VRF retry, 3-day emergency fallback, 30-day final sweep.

---

## Source File References

| File | Key Lines |
|------|-----------|
| `contracts/modules/DegenerusGameAdvanceModule.sol` | L90 (constants), L120-139 (advanceGame entry), L327-377 (_handleGameOverPath), L639-685 (rngGate), L694-770 (_gameOverEntropy + historical fallback), L1138-1165 (updateVrfCoordinatorAndSub), L1270-1275 (_threeDayRngGap) |
| `contracts/modules/DegenerusGameGameOverModule.sol` | L70-151 (handleGameOverDrain), L158-176 (handleFinalSweep), L182-219 (_sendToVault) |
| `contracts/DegenerusGame.sol` | L187 (DEPLOY_IDLE_TIMEOUT_DAYS=912), L255-256 (constructor sets levelStartTime), L2248-2259 (_isGameoverImminent) |
| `contracts/storage/DegenerusGameStorage.sol` | L163 (levelStartTime), L237 (gameOver), L329-335 (claimablePool), L644 (gameOverTime) |

---

## Path 1: 912-Day Deploy Idle Timeout (Level 0)

### Guard Expression

**File:** `DegenerusGameAdvanceModule.sol`, lines 336-337

```solidity
bool livenessTriggered = (lvl == 0 &&
    ts - lst > uint256(DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days) || ...
```

Where:
- `ts` = `uint48(block.timestamp)` (line 122)
- `lst` = `levelStartTime` (line 133, passed as 3rd argument)
- `DEPLOY_IDLE_TIMEOUT_DAYS` = `912` (line 90, type `uint48`)

**Expanded expression:** `block.timestamp - levelStartTime > 912 * 86400`

This equals `block.timestamp - levelStartTime > 78,796,800 seconds` (exactly 912 days).

### Arithmetic Verification

1. **Units correct:** `uint256(912) * 1 days` = `912 * 86400` = `78,796,800 seconds`. The Solidity `1 days` literal equals 86,400 seconds. Correct.

2. **Cast safety:** `uint256(DEPLOY_IDLE_TIMEOUT_DAYS)` widens uint48 to uint256 before multiplication. `912 * 86400 = 78,796,800` -- well within uint256. No overflow possible.

3. **Subtraction safety:** `ts - lst` where both are uint48. `ts = uint48(block.timestamp)` and `lst = levelStartTime` (initialized to `uint48(block.timestamp)` at deploy, line 256 of DegenerusGame.sol). Since `ts >= lst` always (block.timestamp only increases), no underflow. The subtraction result is implicitly widened to uint256 for the `>` comparison.

4. **Strict inequality (`>` not `>=`):** The guard uses strict greater-than. A call at exactly 912 days does NOT trigger -- it requires 912 days + at least 1 second. This is conservative (pro-player).

### Premature Trigger Analysis

- `levelStartTime` is set to `block.timestamp` in the constructor (DegenerusGame.sol line 256).
- At level 0, `levelStartTime` is only updated when transitioning to jackpot phase (AdvanceModule line 247: `levelStartTime = ts`), which requires reaching level 1 first. So at level 0, `levelStartTime` = deploy timestamp.
- Validator timestamp manipulation: Ethereum validators can skew `block.timestamp` by at most ~15 seconds (PoS slot time constraint). To trigger 912 days early, an attacker would need to advance `block.timestamp` by 78,796,800 seconds -- impossible with 15s skew.
- **Premature trigger: IMPOSSIBLE.**

### Accounting Impact

When triggered at level 0:
1. `_handleGameOverPath` calls `_gameOverEntropy` to acquire RNG (lines 363-366).
2. Then delegates to `handleGameOverDrain(_dailyIdx)` (lines 369-376).
3. In `handleGameOverDrain` (GameOverModule):
   - Since `currentLevel < 10` (line 80): deity pass refunds of 20 ETH/pass, budget-capped by `totalFunds - claimablePool` (line 83).
   - `claimablePool += totalRefunded` (lines 106-108) -- correctly increases claimablePool for each refund.
   - `available = totalFunds - claimablePool` (line 112) -- correctly excludes refunded amounts.
   - `gameOver = true; gameOverTime = uint48(block.timestamp)` (lines 114-115).
   - Remaining `available` split: 10% to Decimator jackpot (lines 128-137), 90% to terminal jackpot (lines 141-150).
   - Decimator net spend credited to `claimablePool += decSpend` (lines 132-134).
   - Terminal jackpot credits `claimablePool` inside JackpotModule (line 144 comment).

**claimablePool preservation: CORRECT.** Every credit to `claimableWinnings[x]` has a matching increment to `claimablePool`. The `available` calculation subtracts `claimablePool` before distribution, preventing double-counting.

---

## Path 2: 365-Day Inactivity Timeout (Level 1+)

### Guard Expression

**File:** `DegenerusGameAdvanceModule.sol`, line 338

```solidity
(lvl != 0 && ts - 365 days > lst)
```

Where:
- `ts` = `uint48(block.timestamp)`
- `lst` = `levelStartTime`
- `365 days` = `31,536,000 seconds`

**Expanded:** `block.timestamp - 31,536,000 > levelStartTime`

Equivalently: `block.timestamp > levelStartTime + 31,536,000` (i.e., more than 365 days since levelStartTime was last set).

### Arithmetic Verification

1. **Units correct:** `365 days` = `365 * 86400` = `31,536,000 seconds`. Correct.

2. **Subtraction safety:** `ts - 365 days` subtracts a uint256 from a uint48. In Solidity 0.8+, this is checked arithmetic. If `ts < 365 days`, this would revert. But `ts = uint48(block.timestamp)` and since the contract can only be deployed after Jan 1, 1971 (~31,536,000 seconds since epoch), any realistic deployment has `block.timestamp >> 365 days`. Since Ethereum mainnet launch was in 2015, `block.timestamp` is approximately 1.7 billion -- always far greater than 31,536,000. **No revert risk.**

3. **Comparison direction:** `ts - 365 days > lst` is equivalent to `ts > lst + 365 days` (no overflow since lst is uint48 and adding 365 days still fits in uint256). The comparison is correct.

4. **Strict inequality (`>` not `>=`):** Requires more than exactly 365 days. Conservative.

### When is `levelStartTime` updated?

- **Constructor** (DegenerusGame.sol L256): `levelStartTime = uint48(block.timestamp)` -- deploy time.
- **Purchase-to-Jackpot transition** (AdvanceModule L247): `levelStartTime = ts` -- when a level reaches its prize target and transitions to jackpot phase.

This means `levelStartTime` tracks the start of the most recent jackpot phase, NOT the last purchase. At level 1+, if no one purchases enough to trigger a jackpot phase transition for 365+ days, the guard fires.

### Premature Trigger Analysis

- A purchase alone does NOT reset `levelStartTime`. Only reaching the prize target and triggering the phase transition resets it (line 247).
- This is intentional: the 365-day timer measures stagnation at the jackpot-phase level, not individual activity.
- Validator timestamp manipulation: 15s skew vs 31,536,000s threshold. **Premature trigger: IMPOSSIBLE.**
- An attacker cannot cheaply reset the timer -- they must drive the protocol through a full prize-target-met phase transition, which requires substantial ETH investment.

### Accounting Impact

Identical flow to Path 1 (same `_handleGameOverPath` logic), except:
- `currentLevel >= 1` so the early refund path applies: levels 1-9 (`currentLevel < 10`) get fixed 20 ETH refund per deity pass purchased (GameOverModule lines 80-109), budget-capped by `totalFunds - claimablePool`.
- Levels 10+: no deity pass refund (skips the `currentLevel < 10` branch), so `available = totalFunds - claimablePool` (existing claims preserved).
- Decimator (10%) and terminal jackpot (90%) distribution proceeds identically to Path 1.

**claimablePool preservation: CORRECT.** Same accounting pattern as Path 1.

---

## Path 3: 18-Hour VRF Retry Timeout

### Guard Expression

**File:** `DegenerusGameAdvanceModule.sol`, lines 672-680

```solidity
// Waiting for VRF - check for timeout retry
if (rngRequestTime != 0) {
    uint48 elapsed = ts - rngRequestTime;
    if (elapsed >= 18 hours) {
        _requestRng(isTicketJackpotDay, lvl);
        return 1;
    }
    revert RngNotReady();
}
```

Where:
- `ts` = `uint48(block.timestamp)`
- `rngRequestTime` = timestamp of last VRF request
- `18 hours` = `64,800 seconds`

### Arithmetic Verification

1. **Units correct:** `18 hours` = `18 * 3600` = `64,800 seconds`. Correct.
2. **Subtraction safety:** `ts - rngRequestTime` is safe since `ts >= rngRequestTime` (rngRequestTime was set from a previous `block.timestamp`).
3. **Non-strict inequality (`>=`):** At exactly 18 hours, retry fires. This is correct -- a VRF request that has been pending for exactly 18 hours is retried.

### Does NOT Trigger Game Over

This is in `rngGate()` (normal daily RNG path), NOT in `_handleGameOverPath`. When the 18-hour timeout fires:
1. `_requestRng(isTicketJackpotDay, lvl)` sends a new VRF request.
2. Returns `1` (signal for "RNG requested, try again later").
3. No pool changes, no game-over transition.

**Accounting impact: NEUTRAL.** No funds move. Only a new VRF request is issued.

---

## Path 4: 3-Day Emergency VRF Stall (Game-Over Entropy Fallback)

### Guard Expression

**File:** `DegenerusGameAdvanceModule.sol`, lines 720-736

```solidity
if (rngRequestTime != 0) {
    uint48 elapsed = ts - rngRequestTime;
    if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) {
        // Use earliest historical VRF word as fallback (more secure than blockhash)
        uint256 fallbackWord = _getHistoricalRngFallback(day);
        fallbackWord = _applyDailyRng(day, fallbackWord);
        ...
        return fallbackWord;
    }
    return 0;
}
```

Where:
- `GAMEOVER_RNG_FALLBACK_DELAY` = `3 days` = `259,200 seconds` (line 91)
- This path is ONLY reachable from `_gameOverEntropy()`, which is ONLY called from `_handleGameOverPath()` (line 364)

### Prerequisite: Liveness Guard Already Triggered

The 3-day fallback is NOT an independent trigger for game-over. It is a sub-path of the liveness guard flow:

1. **First**, the 912-day or 365-day guard must trigger (`livenessTriggered = true`, line 336).
2. **Then**, `_handleGameOverPath` tries to acquire RNG via `_gameOverEntropy()` (line 364).
3. **If VRF was requested** but not fulfilled after 3 days, the fallback provides entropy from historical VRF words.

### Arithmetic Verification

1. **Units correct:** `3 days` = `259,200 seconds`. Correct.
2. **Non-strict inequality (`>=`):** At exactly 3 days, fallback fires. Correct.
3. **Historical fallback safety:** `_getHistoricalRngFallback` searches forward from day 1 for a non-zero `rngWordByDay[searchDay]`, capped at 30 iterations (line 760). Returns `keccak256(abi.encodePacked(word, currentDay))` for uniqueness (line 764). If no historical word exists (VRF never worked), reverts with `E()`.

### Does NOT Independently Trigger Game Over

The 3-day delay only controls when fallback entropy becomes available. The actual game-over decision was already made by Path 1 or Path 2 guards. This path provides the RNG needed for `handleGameOverDrain` to distribute funds via BAF/Decimator jackpots.

### Accounting Impact

The fallback word feeds into `handleGameOverDrain` via `rngWordByDay[_dailyIdx]`. The pool attribution in `handleGameOverDrain` is identical regardless of whether the RNG came from VRF directly, VRF callback, or historical fallback.

**Accounting impact: NEUTRAL for the fallback itself.** Pool changes occur in `handleGameOverDrain` (analyzed in Paths 1 and 2).

### Additional: VRF Request Failure Path

If `_tryRequestRng` fails (VRF coordinator down), the function sets `rngRequestTime = ts` to start the 3-day fallback timer (lines 743-746). This is a correct defensive measure -- it starts the clock for historical fallback even when the VRF request itself could not be submitted.

---

## Path 5: 30-Day Final Sweep Delay

### Guard Expression

**File:** `DegenerusGameGameOverModule.sol`, lines 158-160

```solidity
function handleFinalSweep() external {
    if (gameOverTime == 0) return; // Game not over yet
    if (block.timestamp < uint256(gameOverTime) + 30 days) return; // Too early
```

Where:
- `gameOverTime` = `uint48` set to `block.timestamp` when game-over occurs (line 115)
- `30 days` = `2,592,000 seconds`

### Arithmetic Verification

1. **Units correct:** `30 days` = `30 * 86400` = `2,592,000 seconds`. Correct.

2. **Overflow safety:** `uint256(gameOverTime) + 30 days` where `gameOverTime` is uint48. Cast to uint256 before addition. Max uint48 is 281,474,976,710,655. Adding 2,592,000 still fits in uint256. **No overflow.**

3. **Strict inequality (`<`):** `block.timestamp < gameOverTime + 30 days` means the function silently returns (no-op) if less than 30 days. At exactly 30 days, `block.timestamp == gameOverTime + 30 days`, the `<` check is false, and the sweep proceeds. This means the sweep is available at exactly 30 days, not 30 days + 1 second.

4. **Guard pattern:** Uses early return (`return`), not `revert`. This is safe for the calling pattern -- `_handleGameOverPath` calls this via delegatecall and checks `ok` (line 346). A silent return with `ok=true` means "nothing to do yet" which is correct.

### Premature Trigger Analysis

- `gameOverTime` is set in `handleGameOverDrain` (line 115) during the game-over transition.
- It cannot be manipulated externally -- only written by delegatecall from the trusted AdvanceModule flow.
- Validator timestamp skew: 15s vs 2,592,000s. **Premature trigger: IMPOSSIBLE.**

### Sweep is Re-Enterable from advanceGame

The `handleFinalSweep` is called from `_handleGameOverPath` when `gameOver == true` (lines 345-354). This means every `advanceGame()` call after game-over will attempt the sweep. The sweep is idempotent in practice: once all excess funds are swept, `available == 0` and it returns early (line 172).

### Accounting Impact

```solidity
uint256 totalFunds = ethBal + stBal;
uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
if (available == 0) return;
_sendToVault(available, stBal);
```

1. **claimablePool preserved:** `available = totalFunds - claimablePool` (line 170) ensures only excess funds (not reserved for player claims) are swept.
2. **Saturating subtraction:** `totalFunds > claimablePool ? ... : 0` prevents underflow if stETH rebasing caused a minor shortfall.
3. **Distribution:** `_sendToVault` (lines 182-219) splits 50/50 between vault and DGNRS, prioritizing stETH for vault then ETH for remainder. This is standard distribution logic.

**claimablePool preservation: CORRECT.** The invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` is maintained after sweep.

---

## Summary Table

| # | Path | Guard Expression | File:Line | Arithmetic Correct? | Premature Trigger Possible? | Pool Attribution | Verdict |
|---|------|------------------|-----------|----|----|----|---------|
| 1 | 912-day deploy idle (lvl 0) | `ts - lst > uint256(912) * 1 days` | AdvanceModule:336-337 | YES -- 78,796,800s exact | NO -- 15s skew vs 78.8M s | claimablePool += refunds; available = total - claimable | PASS |
| 2 | 365-day inactivity (lvl 1+) | `ts - 365 days > lst` | AdvanceModule:338 | YES -- 31,536,000s exact | NO -- 15s skew vs 31.5M s | Same pattern; early levels get fixed 20 ETH refund | PASS |
| 3 | 18-hour VRF retry | `elapsed >= 18 hours` | AdvanceModule:675 | YES -- 64,800s exact | N/A -- not game-over | NEUTRAL -- only re-requests VRF | PASS |
| 4 | 3-day emergency fallback | `elapsed >= GAMEOVER_RNG_FALLBACK_DELAY` (3 days) | AdvanceModule:722 | YES -- 259,200s exact | N/A -- requires Path 1 or 2 first | NEUTRAL -- provides entropy for drain | PASS |
| 5 | 30-day final sweep | `block.timestamp < uint256(gameOverTime) + 30 days` | GameOverModule:160 | YES -- 2,592,000s exact | NO -- 15s skew vs 2.59M s | available = total - claimablePool; excess to vault/DGNRS | PASS |

---

## Cross-Path Interaction Analysis

### Sequence of Events for Full Stall Recovery

1. **Day 0:** Game deploys. `levelStartTime = block.timestamp`. `level = 0`.
2. **Days 1-912:** Normal operation (or complete inactivity).
3. **Day 912+1s:** Someone calls `advanceGame()`. `livenessTriggered = true` (Path 1).
4. **Same call:** `_gameOverEntropy()` attempts VRF request. If VRF works, RNG word obtained immediately.
5. **If VRF stalled:** Returns 0, caller retries. After 3 days (Path 4), historical fallback provides entropy.
6. **Once RNG obtained:** `handleGameOverDrain()` executes: deity pass refunds, BAF/Decimator distribution. `gameOver = true`.
7. **Days 912 to 942:** `advanceGame()` calls route to `handleFinalSweep()` but return early (< 30 days).
8. **Day 942+:** `handleFinalSweep()` sweeps excess to vault/DGNRS.

### Critical Invariant Across All Paths

**`address(this).balance + steth.balanceOf(this) >= claimablePool`**

This holds because:
- `handleGameOverDrain`: adds to `claimablePool` when crediting deity pass refunds (L106-108), decimator spend (L132-134), and terminal jackpot winnings (inside JackpotModule). Calculates `available` as `totalFunds - claimablePool` before any distribution (L112).
- `handleFinalSweep`: calculates `available = totalFunds - claimablePool` before sweeping, only sending the excess.
- No path decrements `claimablePool` without a corresponding outflow (only `claimWinnings` in DegenerusGame.sol does that, via the pull pattern).

---

## Edge Cases Examined

### Edge Case 1: Level 0, No Deity Passes Sold

If no deity passes were purchased, `deityPassOwners.length == 0`. The refund loop (GameOverModule L85-105) iterates zero times. `totalRefunded = 0`. `claimablePool` unchanged. All funds go to Decimator/terminal jackpot/vault. **Correct.**

### Edge Case 2: Level 0, currentLevel < 10 Branch

At level 0, `currentLevel == 0`, which satisfies `currentLevel < 10` (GameOverModule L80). The deity pass refund loop executes with `refundPerPass = 20 ETH`. If no deity passes exist, the loop body is skipped. **Correct.**

### Edge Case 3: stETH Rebasing Below claimablePool

If stETH rebases down such that `totalFunds < claimablePool`, the saturating subtraction `totalFunds > claimablePool ? totalFunds - claimablePool : 0` yields `available = 0`. Both `handleGameOverDrain` (line 118) and `handleFinalSweep` (line 172) return early with no action. **Correct -- no negative distribution.**

### Edge Case 4: Multiple advanceGame Calls During Game-Over Transition

`handleGameOverDrain` has the idempotency guard `if (gameOverFinalJackpotPaid) return;` (line 71). After the first successful drain, subsequent calls are no-ops. **Correct.**

### Edge Case 5: handleFinalSweep Called Multiple Times

After the first sweep drains excess funds, `available` becomes 0 or near-0 on subsequent calls. The `if (available == 0) return;` guard (line 172) makes it safe to call repeatedly. **Correct.**

---

## ACCT-08 Verdict

### Requirements Checklist

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| 1 | All stall recovery paths correctly guarded against premature triggering | PASS | 912-day and 365-day guards require real elapsed time far exceeding 15s validator skew; 30-day sweep requires gameOverTime + 30 days |
| 2 | All paths correctly preserve claimablePool | PASS | Every credit to claimableWinnings has matching claimablePool increment; sweep calculates available as totalFunds - claimablePool |
| 3 | All paths correctly attribute remaining pool funds | PASS | BAF gets 50% of available, Decimator gets remainder; refund from unrefunded amounts goes to vault; all paths use consistent accounting |
| 4 | 18-hour VRF retry is pool-neutral | PASS | Only re-requests VRF, no fund movement |
| 5 | 3-day emergency fallback provides valid entropy | PASS | Historical VRF word with keccak256 mixing; reverts if no historical word exists (correct fail-safe) |

### ACCT-08: PASS

All five stall recovery paths are correctly guarded against premature triggering, correctly preserve `claimablePool`, and correctly attribute remaining pool funds during recovery transitions. No arithmetic errors, overflow risks, or premature-trigger vulnerabilities found.

### Informational Notes

1. **INFO-01:** The 365-day inactivity timer at level 1+ is keyed to `levelStartTime` (last jackpot-phase transition), not "last purchase timestamp." This means the timer only resets when a full prize target is met and the phase transitions -- individual purchases do not reset it. This is a stronger liveness guarantee than per-purchase tracking.

2. **INFO-02:** The `handleGameOverDrain` receives `_dailyIdx` (the day index at call time) as its RNG key. If `_dailyIdx` has not been updated (stale), the function looks up `rngWordByDay[_dailyIdx]`. This was previously documented as finding FSM-F02 (LOW) in Phase 2 -- the stale dailyIdx may cause the BAF/Decimator distribution to receive RNG from a day that does not match the game-over day. Funds are preserved regardless (any un-distributed amounts flow to final sweep), so accounting integrity is maintained.

3. **INFO-03:** The `_gameOverEntropy` VRF failure path (lines 743-746) sets `rngRequestTime = ts` without actually sending a VRF request. This starts the 3-day fallback timer proactively. On the next `advanceGame()` call 3+ days later, `_getHistoricalRngFallback` provides entropy. This is a correct defensive design for catastrophic VRF failure.
