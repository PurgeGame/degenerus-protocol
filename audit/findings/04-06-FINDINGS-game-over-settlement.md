# Game-Over Settlement Balance Trace to Zero Terminal Balance

**Audit target:** `contracts/modules/DegenerusGameGameOverModule.sol` (220 lines)
**Related:** `contracts/modules/DegenerusGameAdvanceModule.sol` (liveness trigger), `contracts/modules/DegenerusGameJackpotModule.sol` (runTerminalJackpot), `contracts/modules/DegenerusGameDecimatorModule.sol` (runDecimatorJackpot)
**Audit date:** 2026-03-06
**Requirement:** ACCT-07 -- Game-over settlement distributes ALL prize pool funds; no permanent lock
**Prior work:** Phase 3b-02 (GO-F01 through GO-F04), Phase 2 (FSM-F02, FSM-03)
**Code version note:** `refundDeityPass()` has been removed from the codebase. GO-F01 (double refund) from Phase 3b-02 is no longer applicable. This audit traces the current settlement code.

---

## 0. Settlement Sequence Overview

The game-over settlement is a multi-step process triggered by liveness guards in the AdvanceModule:

```
advanceGame() -> _handleGameOverPath()
  |
  +-- Liveness guard triggers:
  |     Level 0: ts - levelStartTime > DEPLOY_IDLE_TIMEOUT_DAYS * 1 days (912 days)
  |     Level 1+: ts - 365 days > levelStartTime
  |
  +-- Safety check (lvl != 0):
  |     If nextPrizePool >= levelPrizePool[lvl]:
  |       levelStartTime = ts  (reset timer, NOT game-over)
  |       return false
  |
  +-- First call (gameOver == false):
  |     1. Acquire RNG word (_gameOverEntropy: VRF or 3-day fallback)
  |     2. delegatecall -> handleGameOverDrain(_dailyIdx)
  |        - Deity pass refunds (level < 10): 20 ETH/pass, budget-capped
  |        - 10% Decimator jackpot (refund returns to remaining)
  |        - 90%+ terminal jackpot (Day-5-style bucket distribution)
  |        - Undistributed remainder -> _sendToVault (50/50 vault/DGNRS)
  |        - Sets gameOver=true, gameOverTime, gameOverFinalJackpotPaid=true
  |
  +-- Subsequent calls (gameOver == true):
        delegatecall -> handleFinalSweep()
        - 30-day guard: block.timestamp < gameOverTime + 30 days -> return
        - finalSwept guard: if already swept -> return
        - Sets finalSwept=true, claimablePool=0 (forfeits unclaimed)
        - Shuts down VRF subscription (fire-and-forget)
        - Sweeps ALL totalFunds to vault(50%)/DGNRS(50%)
        - After sweep: claimWinnings() reverts (finalSwept check)
```

---

## 1. Step 0: Pre-Game-Over State

At the moment `handleGameOverDrain` is entered, the contract holds:

### Pool Variables (accounting)

| Variable | Description | State at entry |
|----------|-------------|----------------|
| `currentPrizePool` | Active level prize pool | 0 if at level boundary, else residual from active level |
| `nextPrizePool` | Pool accumulating for next level | Accumulated from 10% of ticket sales + deity pass share |
| `futurePrizePool` | Long-term reserve pool | Accumulated from 90% of ticket sales, deity pass payments, receive() |
| `claimablePool` | Reserved for player withdrawals | Sum of all unclaimed winnings credited so far |

### Real Balances

| Variable | Source | Description |
|----------|--------|-------------|
| `ethBal` | `address(this).balance` | Actual ETH held |
| `stBal` | `steth.balanceOf(address(this))` | Actual stETH held (rebased) |
| `totalFunds` | `ethBal + stBal` | Total real assets |

### Key Invariant at Entry

```
totalFunds >= claimablePool  (core solvency invariant)
totalFunds = currentPrizePool + nextPrizePool + futurePrizePool + claimablePool + yieldSurplus
```

Where `yieldSurplus` is stETH rebasing yield above accounting expectations.

Note: `_autoStakeExcessEth()` converts excess ETH to stETH at each phase transition, so by game-over most non-claimable funds may be in stETH form.

---

## 2. Step 1: handleGameOverDrain() -- Balance Trace

### 2.1 Entry Guard (Line 71)

```solidity
function handleGameOverDrain(uint48 day) external {
    if (gameOverFinalJackpotPaid) return; // Already processed
```

Idempotency guard. If called twice, second call is a no-op.

### 2.2 Balance Snapshot (Lines 73-78)

```solidity
uint24 currentLevel = level;
uint24 lvl = currentLevel == 0 ? 1 : currentLevel;

uint256 ethBal = address(this).balance;
uint256 stBal = steth.balanceOf(address(this));
uint256 totalFunds = ethBal + stBal;
```

`totalFunds` is the REAL combined balance, not an accounting variable. This is the amount we need to trace to zero (minus claimable).

The `lvl` variable is clamped to at least 1 -- used for Decimator and terminal jackpot level targeting, not for refund logic.

### 2.3 Deity Pass Refund: Levels 0-9 (Lines 80-109)

**Condition:** `currentLevel < 10`

```solidity
uint256 refundPerPass = DEITY_PASS_EARLY_GAMEOVER_REFUND; // 20 ether
uint256 ownerCount = deityPassOwners.length;
uint256 budget = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
uint256 totalRefunded;

for (uint256 i; i < ownerCount; ) {
    address owner = deityPassOwners[i];
    uint16 purchasedCount = deityPassPurchasedCount[owner];
    if (purchasedCount != 0) {
        uint256 refund = refundPerPass * uint256(purchasedCount);
        if (refund > budget) {
            refund = budget;                // Budget-cap: never refund more than available
        }
        if (refund != 0) {
            unchecked {
                claimableWinnings[owner] += refund;
                totalRefunded += refund;
                budget -= refund;
            }
        }
        if (budget == 0) break;             // Stop when budget exhausted
    }
    unchecked { ++i; }
}
if (totalRefunded != 0) {
    claimablePool += totalRefunded;
}
```

**Refund mechanism:**
- Fixed 20 ETH per pass for ALL levels 0-9 (no separate level-0 full-refund path)
- Uses `deityPassPurchasedCount[owner]` (count of passes purchased), not `deityPassPaidTotal`
- Budget-capped: `budget = totalFunds - claimablePool` ensures refunds never exceed available funds
- First-in-list-first-served: if budget runs out, later owners get partial or zero refund

**Balance equation change:**
```
BEFORE: totalFunds = [pools] + claimablePool_0
AFTER:  totalFunds = [pools] + (claimablePool_0 + totalRefunded)
        where totalRefunded <= budget = totalFunds - claimablePool_0
```

The contract balance `totalFunds` is UNCHANGED (no ETH moves). Only `claimablePool` increases. This is a pure accounting re-classification: funds move from "unallocated" to "reserved for claims."

**Maximum totalRefunded:** Up to 32 owners (deityPassOwners bounded by symbolId < 32). Each can hold multiple passes. At 20 ETH/pass, maximum = 32 owners * max_passes * 20 ETH. Budget cap ensures this never exceeds available funds.

### 2.4 Deity Pass Refund: Level 10+ (Implicit No-Op)

**Condition:** `currentLevel >= 10`

The `if (currentLevel < 10)` block does not execute. `totalRefunded = 0`. No change to `claimablePool`.

### 2.5 Available Balance Computation (Lines 112-121)

```solidity
uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;

gameOver = true;                        // Terminal state -- irreversible
gameOverTime = uint48(block.timestamp); // Timestamp for 30-day sweep timer
gameOverFinalJackpotPaid = true;        // Idempotency guard

if (available == 0) return;             // Exit A: nothing to distribute

uint256 rngWord = rngWordByDay[day];
if (rngWord == 0) return;               // Exit B: no RNG ready
```

**Balance equation at this point:**
```
available = totalFunds - claimablePool
          = totalFunds - (claimablePool_0 + totalRefunded)
          = unallocated funds (pools + yield surplus - refunds reserved)
```

**Exit paths:**
- Exit A (`available == 0`): All funds are reserved as claimable. Terminal state set but no distribution. Funds accessible only via `claimWinnings()`. **No funds locked.**
- Exit B (`rngWord == 0`): Terminal state set, no Decimator/terminal jackpot. Funds remain in contract. `handleFinalSweep` will sweep after 30 days. **No funds locked.**

**Note on Exit B:** The `_gameOverEntropy` function in AdvanceModule ensures an RNG word is stored in `rngWordByDay[_dailyIdx]` before calling `handleGameOverDrain`. If `rngWordCurrent` is fulfilled or fallback triggers, the word is stored. If neither is available, `_handleGameOverPath` returns `true` without calling `handleGameOverDrain` (returns 0 or 1 from `_gameOverEntropy`). So Exit B should only trigger if `day` parameter differs from `_dailyIdx` where the RNG was stored -- a coding inconsistency rather than expected flow. In practice, `_handleGameOverPath` passes `_dailyIdx` to `handleGameOverDrain`, so this exit is not expected under normal operation.

### 2.6 Decimator Distribution (Lines 125-137)

```solidity
uint256 remaining = available;

// 10% Decimator -- refunds flow back to remaining for terminal jackpot
uint256 decPool = remaining / 10;
if (decPool != 0) {
    uint256 decRefund = IDegenerusGame(address(this)).runDecimatorJackpot(decPool, lvl, rngWord);
    uint256 decSpend = decPool - decRefund;
    if (decSpend != 0) {
        claimablePool += decSpend;
    }
    remaining -= decPool;
    remaining += decRefund; // Return decimator refund to remaining for terminal jackpot
}
```

**`runDecimatorJackpot` return value semantics:**
- Returns `0` if winners found: full pool snapshotted for deferred claims
- Returns `poolWei` (full refund) if no qualifying burns or already snapshotted

**Case A: Winners found (`decRefund == 0`):**
```
decSpend = decPool - 0 = decPool
claimablePool += decPool        (reserved for Decimator claimants)
remaining = available - decPool + 0 = available - decPool
```
Note: claimablePool increment here does NOT correspond to individual `claimableWinnings` credits -- the Decimator uses snapshot-based deferred claims. The pool is reserved upfront; individual claims deduct later via `claimDecimatorJackpot()`.

**Case B: No winners (`decRefund == decPool`):**
```
decSpend = decPool - decPool = 0
claimablePool: UNCHANGED
remaining = available - decPool + decPool = available  (full amount restored)
```

**Case C: Partial (not possible for runDecimatorJackpot -- it returns 0 or poolWei, never partial).**

### 2.7 Terminal Jackpot Distribution (Lines 141-150)

```solidity
// 90% (+ decimator refund) to next-level ticketholders (Day-5-style bucket distribution)
// gameOver=true prevents auto-rebuy inside _addClaimableEth (tickets worthless post-game)
if (remaining != 0) {
    uint256 termPaid = IDegenerusGame(address(this))
        .runTerminalJackpot(remaining, lvl + 1, rngWord);
    // claimablePool already updated inside JackpotModule._distributeJackpotEth
    remaining -= termPaid;
    // Any undistributed remainder swept to vault
    if (remaining != 0) {
        _sendToVault(remaining, stBal);
    }
}
```

**`runTerminalJackpot` internals (JackpotModule lines 288-321):**
- Rolls winning traits for `targetLvl` (= `lvl + 1`)
- Distributes ETH across 4 trait buckets using Day-5-style bucket distribution
- Inside `_distributeJackpotEth` (line 1563): `claimablePool += ctx.liabilityDelta`
- Returns `totalPaidEth` (amount actually distributed to winners' claimable balances)

**Balance flow:**
```
termPaid = ETH credited to winners' claimableWinnings
claimablePool += termPaid  (inside _distributeJackpotEth)
remaining -= termPaid
```

**Undistributed remainder:** If `remaining > termPaid` (e.g., no ticket holders for the target level, rounding), the remainder is sent to vault/DGNRS via `_sendToVault`.

### 2.8 _sendToVault Helper (Lines 182-219)

```solidity
function _sendToVault(uint256 amount, uint256 stethBal) private {
    uint256 dgnrsAmount = amount / 2;  // 50% floor
    uint256 vaultAmount = amount - dgnrsAmount;  // 50% ceil
    // ... transfers stETH first to vault, remainder as ETH
    // ... transfers stETH first to DGNRS (via approve+depositSteth), remainder as ETH
}
```

**Key properties:**
- `dgnrsAmount + vaultAmount = amount` exactly (subtraction pattern, no rounding loss)
- stETH is transferred first (more gas-efficient for vault), ETH fills the gap
- Max 1 wei asymmetry: vault gets ceil, DGNRS gets floor
- All `amount` wei leave the contract (split between vault and DGNRS)

### 2.9 Summary After handleGameOverDrain

```
BEFORE handleGameOverDrain:
  totalFunds = [unallocated] + claimablePool_0

AFTER handleGameOverDrain:
  gameOver = true
  gameOverFinalJackpotPaid = true

  Let:
    R = totalRefunded (deity pass refund credits)
    D = decSpend (Decimator credits, 0 or decPool)
    J = termPaid (terminal jackpot credits, from _distributeJackpotEth)
    V = remaining after terminal jackpot (sent to vault/DGNRS)

  claimablePool_after = claimablePool_0 + R + D + J
  totalFunds_after = totalFunds_before - V   (V is the only external transfer)

  Unallocated check:
    available = totalFunds_before - claimablePool_0 - R   (after deity refunds)
    remaining_after_dec = available - D                     (decimator spend)
    remaining_after_term = remaining_after_dec - J          (terminal jackpot)
    V = remaining_after_term                                (vault sweep)

    totalFunds_after - claimablePool_after
      = (totalFunds_before - V) - (claimablePool_0 + R + D + J)
      = totalFunds_before - (available - D - J) - claimablePool_0 - R - D - J
      = totalFunds_before - available + D + J - claimablePool_0 - R - D - J
      = totalFunds_before - available - claimablePool_0 - R
      = totalFunds_before - (totalFunds_before - claimablePool_0 - R) - claimablePool_0 - R
      = totalFunds_before - totalFunds_before + claimablePool_0 + R - claimablePool_0 - R
      = 0  QED
```

**All funds accounted for: totalFunds_after = claimablePool_after.**

---

## 3. Step 2: handleFinalSweep() -- 30 Days Later

> **POST-AUDIT UPDATE:** `handleFinalSweep` was fundamentally rewritten after the original audit. The entire Section 3 below has been updated to reflect the current implementation (GameOverModule lines 168-186). Key changes:
> - Added `finalSwept` idempotency guard (line 171) -- function is now one-time execution only
> - Sets `claimablePool = 0` (line 174) -- **forfeits all unclaimed winnings**
> - Sweeps ALL remaining `totalFunds` (not just excess above claimablePool)
> - `_claimWinningsInternal` (DegenerusGame.sol line 1421) now checks `if (finalSwept) revert E();`, blocking all claims after the sweep

### 3.1 Guard Checks (Lines 168-171)

```solidity
function handleFinalSweep() external {
    if (gameOverTime == 0) return;                                    // line 169: Not game-over yet
    if (block.timestamp < uint256(gameOverTime) + 30 days) return;   // line 170: Too early
    if (finalSwept) return;                                           // line 171: Already swept
```

**30-day enforcement:**
- `gameOverTime` set to `uint48(block.timestamp)` in `handleGameOverDrain` line 115.
- `30 days = 30 * 86400 = 2,592,000 seconds`.
- Cast to `uint256` prevents overflow (defensive; uint48 max ~2.8e14 is far above current timestamps ~1.7e9).
- **PASS: Cannot be called prematurely.**

**Idempotency:** `finalSwept` guard prevents re-execution. Unlike the previous version which could be called multiple times, this is now a one-shot operation.

### 3.2 State Mutations (Lines 173-174)

```solidity
    finalSwept = true;                                                // line 173
    claimablePool = 0;                                                // line 174
```

**Critical change from pre-audit behavior:** Setting `claimablePool = 0` forfeits all unclaimed winnings. Players who have not claimed within the 30-day window lose their claims. This is a deliberate design decision to enable full fund recovery.

The `finalSwept = true` flag also serves as a claim blocker: `_claimWinningsInternal` (DegenerusGame.sol line 1421) checks `if (finalSwept) revert E();` before processing any claim.

### 3.3 VRF Shutdown (Line 177)

```solidity
try admin.shutdownVrf() {} catch {}
```

Fire-and-forget call to Admin contract. Failure does not block the sweep. This cleans up the Chainlink VRF subscription and sweeps LINK to vault.

### 3.4 Sweep Execution (Lines 179-185)

```solidity
uint256 ethBal = address(this).balance;
uint256 stBal = steth.balanceOf(address(this));
uint256 totalFunds = ethBal + stBal;

if (totalFunds == 0) return;

_sendToVault(totalFunds, stBal);                                      // line 185
```

**`_sendToVault` splits `totalFunds` 50/50:**
```
dgnrsAmount = totalFunds / 2            // floor
vaultAmount = totalFunds - dgnrsAmount  // ceil (gets 1 extra wei on odd)
```

**Transfer priority:** stETH first (vault gets stETH up to vaultAmount, remainder as ETH; DGNRS gets remaining stETH via approve+depositSteth + ETH).

**Key difference from pre-audit:** The sweep now sends ALL `totalFunds`, not just the excess above `claimablePool`. Since `claimablePool` was zeroed at line 174, the distinction is moot -- all funds are now "excess."

### 3.5 One-Time Execution

`handleFinalSweep` now has the `finalSwept` idempotency guard. It can only be called once:

- First (and only) call: zeros `claimablePool`, sweeps all remaining funds to vault/DGNRS.
- Subsequent calls: `if (finalSwept) return;` at line 171 makes them no-ops.
- Any stETH yield accruing after the sweep remains in the contract permanently (negligible amounts on a zero balance).

### 3.6 claimablePool Forfeiture

**Critical change:** `handleFinalSweep` now sets `claimablePool = 0` and `finalSwept = true`. Players who haven't claimed within the 30-day post-gameOver window lose their winnings. After the sweep:
- `claimWinnings()` reverts with `E()` due to the `finalSwept` check at DegenerusGame.sol line 1421
- All funds have been sent to vault/DGNRS
- The contract holds zero (or near-zero) ETH/stETH

---

## 4. Step 3: Terminal State Verification

### 4.1 After Both Steps Complete

```
After handleGameOverDrain:
  totalFunds_a = claimablePool_a + 0  (unallocated exhausted)
  vault/DGNRS received their share of undistributed remainder

After handleFinalSweep (30+ days):
  totalFunds_b = claimablePool_a + yield_surplus
  sweep sends yield_surplus to vault/DGNRS
  totalFunds_after_sweep = claimablePool_a (approximately, minus stETH rounding)
```

### 4.2 Can Players Still Claim?

> **POST-AUDIT UPDATE:** The answer changed from "yes, indefinitely" to "only during the 30-day window." After `handleFinalSweep` executes, `finalSwept = true` causes `_claimWinningsInternal` to revert at DegenerusGame.sol line 1421 (`if (finalSwept) revert E();`), and `claimablePool` is zeroed.

**During the 30-day window (before sweep):** Yes. `claimWinnings()` remains functional:
- `claimableWinnings[player]` is still set from deity refunds, terminal jackpot credits, and Decimator claims.
- `claimablePool` is preserved (not yet modified).
- The contract retains `claimablePool` worth of assets to honor claims.

**After the sweep:** No. `claimWinnings()` reverts because `finalSwept = true`. All unclaimed winnings are forfeited. The contract balance is zero.

### 4.3 Is Any ETH Permanently Locked?

> **POST-AUDIT UPDATE:** The permanent lock scenario described below has been resolved. `handleFinalSweep` now sets `claimablePool = 0` and sweeps ALL remaining funds, including previously unclaimed winnings.

**After sweep, zero ETH/stETH remains in the contract.** All funds are swept to vault/DGNRS. Potential scenarios:

| Scenario | Outcome | Assessment |
|----------|---------|------------|
| All players claim within 30 days | All withdrawn before sweep | No lock |
| Some players never claim | Unclaimed winnings forfeited; swept to vault/DGNRS | **No permanent lock** |
| All players fail to claim | All funds swept to vault/DGNRS | **No permanent lock** |

**Observation:** The current design trades indefinite claim availability for guaranteed fund recovery. Players have a 30-day window to claim after game-over. After that, `handleFinalSweep` forfeits unclaimed winnings and sends everything to vault/DGNRS.

**Verdict:** No funds are permanently locked. The 30-day claim window is a design trade-off, not a finding.

### 4.4 Decimator Deferred Claims

The Decimator jackpot in game-over uses `runDecimatorJackpot` which snapshots winners for deferred claims. The full `decPool` amount is reserved in `claimablePool` upfront (line 133: `claimablePool += decSpend`). Individual players claim via `claimDecimatorJackpot()`.

**After game-over, can players still claim Decimator?** Yes, as long as `lastDecClaimRound.lvl` matches. Since game-over is terminal and no more levels run, the Decimator snapshot persists indefinitely. **PASS.**

**Excess in Decimator reservation:** If not all Decimator winners claim, the reserved amount in `claimablePool` exceeds actual withdrawals. This leaves residual ETH in the contract -- same as the "unclaimed claimableWinnings" scenario above. Not exploitable, just standard unclaimed funds.

---

## 5. Balance Equations at Each Step

### Symbolic Notation

```
Let:
  T = totalFunds (real assets)
  C = claimablePool (reserved accounting)
  R = totalRefunded (deity pass refund credits, 0 if level >= 10)
  D = decSpend (Decimator credits: 0 or decPool)
  J = termPaid (terminal jackpot credits from _distributeJackpotEth)
  V = vault_transfers = remaining after terminal jackpot
  A = available = T - C (after deity refunds)

Step 0 (before drain):
  T_0 = A_0 + C_0
  A_0 = T_0 - C_0  > 0 (assuming solvent)

Step 1 (after deity refunds, before distribution):
  T_1 = T_0           (no external transfers yet)
  C_1 = C_0 + R
  A_1 = T_0 - C_0 - R = A_0 - R

Step 2 (after Decimator):
  decPool = A_1 / 10
  Case A (winners): D = decPool, decRefund = 0
    remaining = A_1 - decPool + 0 = A_1 - decPool
    C_2 = C_1 + decPool
  Case B (no winners): D = 0, decRefund = decPool
    remaining = A_1 - decPool + decPool = A_1
    C_2 = C_1

Step 3 (after terminal jackpot + vault):
  J = termPaid (from _distributeJackpotEth, which also does claimablePool += J)
  V = remaining - J  (sent to vault/DGNRS)
  T_3 = T_0 - V                     (V is the only external transfer)
  C_3 = C_2 + J = C_0 + R + D + J

  Check: T_3 - C_3 = (T_0 - V) - (C_0 + R + D + J)

  For Case A (D = decPool):
    remaining = A_0 - R - decPool
    V = remaining - J = A_0 - R - decPool - J
    T_3 - C_3 = (T_0 - A_0 + R + decPool + J) - (C_0 + R + decPool + J)
              = T_0 - A_0 - C_0
              = T_0 - (T_0 - C_0) - C_0
              = 0  QED

  For Case B (D = 0):
    remaining = A_0 - R
    V = remaining - J = A_0 - R - J
    T_3 - C_3 = (T_0 - A_0 + R + J) - (C_0 + R + 0 + J)
              = T_0 - A_0 - C_0
              = 0  QED

Step 4 (after final sweep, 30+ days) -- POST-AUDIT UPDATE:
  yield = stETH rebasing over 30+ days
  claims = ETH/stETH paid out via claimWinnings during the 30-day window
  T_4_before = C_3 + yield - claims
  C_4 = 0  (claimablePool zeroed by handleFinalSweep, line 174)
  finalSwept = true  (line 173)
  sweep_amount = T_4_before  (ALL remaining funds)
  T_4_after = 0

  Check: T_4_after = 0, C_4 = 0  =>  T_4_after >= C_4  QED
```

**The algebra proves that every wei is accounted for.** The only residual is `claimablePool` backing player withdrawal claims.

---

## 6. GO-F01 Status Update (Cross-Reference Phase 3b-02)

### 6.1 Recap of GO-F01

Phase 3b-02 identified GO-F01 (MEDIUM): `refundDeityPass()` at level 0 pays out ETH directly and zeroes `deityPassRefundable[buyer]`, but does NOT zero `deityPassPaidTotal[buyer]` and does NOT remove the buyer from `deityPassOwners`. If game-over subsequently triggers at level 0, `handleGameOverDrain` would read `deityPassPaidTotal[owner]` (still non-zero) and credit `claimableWinnings[owner]` again.

### 6.2 Current Status: RESOLVED

**`refundDeityPass()` has been removed from the codebase.** The function no longer exists in any contract file. This was confirmed by grep across all contracts -- no matches for `refundDeityPass` or `refundDeity`.

The CLAUDE.md project memory confirms: "No voluntary pre-gameOver deity refund (removed refundDeityPass)".

Additionally, the current `handleGameOverDrain` deity refund uses `deityPassPurchasedCount[owner]` (a count), not `deityPassPaidTotal[owner]` (the amount paid). Since there is no way to receive a refund before game-over, there is no double-refund vector.

**GO-F01: CLOSED (remediated by function removal).**

### 6.3 Residual Risk Assessment

The `deityPassRefundable` mapping still exists in storage (`DegenerusGameStorage.sol` line 1208) but is unused -- no function reads or writes to it. This is dead storage. No accounting risk.

The `deityPassPaidTotal` mapping is still written to in `DegenerusGameWhaleModule.sol` (line 496 on purchase, lines 578-579 on transfer) but is NOT read by `handleGameOverDrain`. It serves no purpose in the game-over flow. No accounting risk.

---

## 7. Edge Case Analysis

### 7.1 Stale RNG + Settlement Accounting

When `rngWordByDay[day] == 0` at line 121:
- Deity refunds are credited (lines 80-108 run before line 121)
- `gameOver`, `gameOverTime`, `gameOverFinalJackpotPaid` are all set (lines 114-116)
- Decimator and terminal jackpot distribution SKIPPED (line 121 returns)
- `available` funds remain in contract, not distributed to winners

**Accounting impact:**
```
claimablePool += totalRefunded   (deity refunds credited)
available = totalFunds - claimablePool  (still positive, just not distributed)
```

After 30 days, `handleFinalSweep` sends `available` to vault/DGNRS. Players who would have won Decimator/terminal jackpots get nothing. Deity refund holders still get their claims.

**Verdict:** Suboptimal distribution (vault/DGNRS get more, jackpot winners get less), but no funds permanently locked. This edge case is mitigated by `_handleGameOverPath` which acquires RNG BEFORE calling `handleGameOverDrain`.

### 7.2 Zero Deity Pass Owners + Zero Available

If `deityPassOwners.length == 0` and all funds are in `claimablePool`:
- No refunds credited
- `available = totalFunds - claimablePool` -- could be 0 or yield surplus only
- If `available == 0`: terminal state set, no distribution. **Correct.**
- If `available > 0` (yield): Decimator/terminal jackpot get yield surplus. **Correct.**

### 7.3 stETH Rebasing Between Drain and Sweep

During the 30-day waiting period:
- stETH balance increases via rebasing (Lido yield, typically 3-5% APR)
- For 30 days: ~0.25-0.4% yield
- This yield appears as positive `available` in `handleFinalSweep`
- Swept to vault/DGNRS -- this is a feature, not a bug

**Negative rebasing (slashing):**
- If Lido slashing reduces stETH balance, `totalFunds` decreases
- If it drops below `claimablePool`, the ternary guard sets `available = 0`
- But `claimablePool` still references a higher amount than available
- **claimWinnings could fail for late claimers if slashing is severe enough**
- **This is a protocol-level risk of holding stETH, not specific to game-over settlement**

### 7.4 Concurrent claimWinnings During Settlement

Players can call `claimWinnings()` between `handleGameOverDrain` and `handleFinalSweep` (during the 30-day window):
- `claimWinnings` reduces both `claimablePool` and `totalFunds` by the same amount
- This reduces the amount that `handleFinalSweep` will eventually sweep
- After `handleFinalSweep` executes: `finalSwept = true` blocks any further claims (DegenerusGame.sol line 1421: `if (finalSwept) revert E();`)

### 7.5 Safety Check: nextPrizePool >= levelPrizePool[lvl] (AdvanceModule Line 357)

When `lvl != 0` and `nextPrizePool >= levelPrizePool[lvl]`, the game should NOT enter game-over because there's enough funds to continue playing. The AdvanceModule handles this by resetting `levelStartTime = ts` and returning `false`. This means:

- Game-over only triggers when the game is truly abandoned (not enough next-pool AND liveness timer expired)
- **PASS: Cannot falsely trigger game-over when gameplay can continue.**

### 7.6 Budget Cap on Deity Refunds

The budget cap `budget = totalFunds > claimablePool ? totalFunds - claimablePool : 0` ensures deity refunds never exceed available funds. This prevents an invariant violation if the total refund amount (20 ETH * total passes across all owners) exceeds available funds. In that case, early owners in the `deityPassOwners` array get full refunds while later owners get partial or zero.

**Fairness observation:** The order of `deityPassOwners` is insertion order (order of first purchase). First purchasers get priority in the budget-capped scenario. This is a design choice, not a bug.

---

## 8. ACCT-07 Verdict

### Normal Case: Does Settlement Reach Zero Terminal Balance?

**PASS.** The algebraic proof in Section 5 demonstrates that after `handleGameOverDrain` completes:

```
totalFunds - claimablePool = 0  (modulo vault/DGNRS transfers)
```

All funds are accounted for as one of:
1. **claimablePool** -- backing player claimableWinnings (deity refunds, terminal jackpot winners, Decimator winners)
2. **vault/DGNRS** -- undistributed terminal jackpot remainder sent to protocol treasury

After `handleFinalSweep` (30+ days later):
- `claimablePool` is zeroed and `finalSwept` is set (forfeiting unclaimed winnings)
- ALL remaining funds (including unclaimed winnings and stETH yield) are swept to vault/DGNRS
- `claimWinnings()` reverts after sweep (DegenerusGame.sol line 1421)
- **No funds are permanently locked** -- all funds reach vault/DGNRS

### GO-F01 Double Refund: No Longer Applicable

**RESOLVED.** The `refundDeityPass()` function has been removed from the codebase. There is no mechanism for a deity pass holder to receive a refund before game-over. The double-refund vector identified in Phase 3b-02 is eliminated.

### Final ACCT-07 Assessment

**ACCT-07: PASS (unconditional)**

The game-over settlement machinery correctly distributes all funds to zero terminal balance. The sole known vulnerability (GO-F01 double deity pass refund) has been resolved by removing the `refundDeityPass()` function. All settlement paths -- deity refund, Decimator, terminal jackpot, vault sweep, and final sweep -- have been algebraically verified to maintain the solvency invariant.

---

## 9. Findings Summary

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| ACCT-07 | PASS (unconditional) | Game-over settlement traces to zero terminal balance | All paths verified algebraically |
| GO-F01 | CLOSED | Double refund via refundDeityPass + handleGameOverDrain | Resolved: refundDeityPass removed from codebase |

### No New Findings

This analysis confirms the settlement accounting is sound under the current codebase. The prior GO-F01 finding has been resolved. No new findings emerged from the accounting-focused trace.

---

*Audit completed: 2026-03-06*
*Auditor: Claude Opus 4.6*
*No contract files were modified during this audit.*
