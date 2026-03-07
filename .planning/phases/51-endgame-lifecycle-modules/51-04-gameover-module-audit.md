# DegenerusGameGameOverModule.sol -- Function-Level Audit

**Contract:** DegenerusGameGameOverModule
**File:** contracts/modules/DegenerusGameGameOverModule.sol
**Lines:** 220
**Solidity:** 0.8.34
**Inherits:** DegenerusGameStorage
**Called via:** delegatecall from DegenerusGame (routed through AdvanceModule liveness guard)
**Audit date:** 2026-03-07

## Summary

DegenerusGameGameOverModule handles the terminal game-over state: deity pass refunds (flat 20 ETH/pass, budget-capped, FIFO), prize pool distribution via Decimator and terminal jackpots, and final sweep of remaining ETH/stETH to the Vault and DGNRS contracts. The module has 2 external functions and 1 private helper, totalling ~150 lines of logic. All external entry points are reached exclusively via delegatecall from the AdvanceModule's liveness guard (`_checkLiveness`).

## Function Audit

### `handleGameOverDrain(uint48 day)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleGameOverDrain(uint48 day) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `day` (uint48): Day index for RNG word lookup from `rngWordByDay` mapping |
| **Returns** | none |

**State Reads:**
- `gameOverFinalJackpotPaid` -- early-exit guard (idempotency)
- `level` -- current game level, used for deity refund eligibility (< 10) and jackpot target level
- `claimablePool` -- existing claimable liability, used to compute available budget
- `deityPassOwners` (array length + elements) -- iteration for deity refund distribution
- `deityPassPurchasedCount[owner]` -- per-owner purchased pass count for refund calculation
- `rngWordByDay[day]` -- RNG word for jackpot selection

**State Writes:**
- `claimableWinnings[owner] += refund` -- credit deity pass refunds (unchecked, inside loop)
- `claimablePool += totalRefunded` -- increase liability by total deity refunds
- `gameOver = true` -- set terminal state flag
- `gameOverTime = uint48(block.timestamp)` -- record game-over timestamp
- `gameOverFinalJackpotPaid = true` -- prevent re-entry / duplicate payouts
- `claimablePool += decSpend` -- increase liability by decimator jackpot credits (via self-call return)

**Callers:**
- `DegenerusGameAdvanceModule._checkLiveness()` via delegatecall through `GAME_GAMEOVER_MODULE` (line 369-375 of AdvanceModule)

**Callees:**
- `steth.balanceOf(address(this))` -- external view call to get stETH balance
- `IDegenerusGame(address(this)).runDecimatorJackpot(decPool, lvl, rngWord)` -- self-call to DegenerusGame which delegatecalls DecimatorModule
- `IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl + 1, rngWord)` -- self-call to DegenerusGame which delegatecalls JackpotModule
- `_sendToVault(remaining, stBal)` -- private helper for any undistributed remainder

**ETH Flow:**
1. **Deity refunds** (level < 10 only): 20 ETH/pass credited to `claimableWinnings[owner]`, funded from `totalFunds - claimablePool` budget. These are pull-pattern credits, not actual transfers.
2. **Decimator jackpot** (10% of available): `available / 10` sent to `runDecimatorJackpot`. Returns `decRefund` (unallocated portion). `decSpend = decPool - decRefund` added to `claimablePool`.
3. **Terminal jackpot** (90% + decimator refund): Remainder sent to `runTerminalJackpot` (Day-5-style bucket distribution to next-level ticketholders). `claimablePool` updated internally by JackpotModule.
4. **Vault sweep**: Any undistributed remainder (`remaining -= termPaid`) sent to vault/DGNRS via `_sendToVault`.

**Invariants:**
- `gameOverFinalJackpotPaid` prevents duplicate execution (idempotent on re-call)
- `claimablePool` is always increased to cover newly credited amounts, preserving the solvency invariant `contract.balance + steth.balanceOf >= claimablePool`
- Deity refund budget is `totalFunds - claimablePool`, ensuring existing claimable liabilities are never touched
- `gameOver = true` is set BEFORE jackpot distribution, ensuring `_addClaimableEth` inside JackpotModule does not trigger auto-rebuy (tickets worthless post-game)
- Level 0 is mapped to `lvl = 1` for jackpot distribution, preventing underflow on `lvl + 1` for terminal jackpot target

**NatSpec Accuracy:**
- NatSpec states "liveness guards trigger (2.5yr deploy timeout or 365-day inactivity)" -- the actual code in AdvanceModule uses `DEPLOY_IDLE_TIMEOUT_DAYS` which is 912 days (~2.5 years) for level 0, and 365 days for level > 0. NatSpec is accurate.
- NatSpec mentions "10% to Decimator, 90% to next-level ticketholders" -- matches code exactly (`remaining / 10` for decimator, rest to terminal jackpot).
- NatSpec mentions "VRF fallback: Uses rngWordByDay" -- accurate. The `_gameOverEntropy` function in AdvanceModule populates `rngWordByDay[day]` before calling this function, with a 3-day timeout historical VRF fallback.
- NatSpec says "FIFO by purchase order" -- correct, iteration is over `deityPassOwners` array which preserves insertion order.
- `@custom:reverts E When stETH transfer fails` -- this function itself does not directly call stETH transfer (only `_sendToVault` does as a callee), but reverting within `_sendToVault` would propagate. Slightly imprecise but not misleading.

**Gas Flags:**
- The `deityPassOwners` loop is unbounded in theory, but deity passes are capped at 32 total (symbol IDs 0-31), so worst case is 32 iterations. Acceptable.
- `steth.balanceOf(address(this))` is an external call even though the balance may be zero in most cases. However, the call is necessary and inexpensive (view function).
- `unchecked` blocks inside the deity refund loop are safe: `claimableWinnings` grows from zero per player (overflow would require > 2^256 wei); `totalRefunded` bounded by `totalFunds`; `budget` decremented by `refund <= budget`.
- `stBal` is captured before deity refunds and jackpot distribution but passed to `_sendToVault` at the end. Since `_sendToVault` calls `steth.balanceOf` is NOT re-queried, stale `stBal` could theoretically be wrong if stETH rebased during execution. However, within a single transaction, stETH balance does not rebase (rebases happen once per day via oracle report), so this is safe.

**Verdict:** CORRECT

---

### `handleFinalSweep()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function handleFinalSweep() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | none |
| **Returns** | none |

**State Reads:**
- `gameOverTime` -- timestamp when game over was set (0 if game not over)
- `claimablePool` -- existing claimable liability to preserve

**State Writes:**
- None directly. `_sendToVault` does not write storage; it only performs external transfers.
- `admin.shutdownVrf()` writes to DegenerusAdmin storage (cancels VRF subscription, sets subscriptionId to 0, sweeps LINK to vault).

**Callers:**
- `DegenerusGameAdvanceModule._checkLiveness()` via delegatecall through `GAME_GAMEOVER_MODULE` (line 347-352 of AdvanceModule). Called when `gameOver == true` and liveness guard fires.

**Callees:**
- `admin.shutdownVrf()` -- external call to DegenerusAdmin, wrapped in try/catch (fire-and-forget). Cancels VRF subscription and sweeps LINK to vault.
- `steth.balanceOf(address(this))` -- external view call
- `_sendToVault(available, stBal)` -- private helper for ETH/stETH distribution

**ETH Flow:**
- All excess funds (`totalFunds - claimablePool`) transferred to Vault (50%) and DGNRS (50%) via `_sendToVault`. The `claimablePool` reserve is preserved for player withdrawals.
- LINK tokens (if any) swept from Admin to Vault via `shutdownVrf()`.

**Invariants:**
- `gameOverTime != 0` ensures game-over has occurred
- `block.timestamp >= gameOverTime + 30 days` enforces 30-day waiting period
- `claimablePool` is preserved -- only excess funds are swept, maintaining solvency for pending player claims
- `shutdownVrf()` is fire-and-forget: failure does not block the sweep, preventing VRF issues from locking funds permanently

**NatSpec Accuracy:**
- "Final sweep of all remaining funds to vault after 30 days post-gameover" -- accurate
- "Preserves claimablePool for player withdrawals" -- accurate, `available = totalFunds > claimablePool ? totalFunds - claimablePool : 0`
- "Funds are split 50/50 between vault and DGNRS contract" -- accurate, handled by `_sendToVault`
- "Also shuts down the VRF subscription and sweeps LINK to vault" -- accurate
- `@custom:reverts E When ETH or stETH transfer fails` -- accurate, `_sendToVault` reverts with `E()` on transfer failure

**Gas Flags:**
- `handleFinalSweep` can be called repeatedly (no guard flag). Each call after the first will find `available == 0` and return early, so re-entrancy/re-call is harmless but wastes gas. Not a bug -- just a soft no-op pattern.
- The `admin.shutdownVrf()` call will succeed on first invocation but subsequent calls will either no-op (subscriptionId already 0) or revert inside try/catch. The try/catch ensures this is safe.

**Verdict:** CORRECT

---

### `_sendToVault(uint256 amount, uint256 stethBal)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _sendToVault(uint256 amount, uint256 stethBal) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `amount` (uint256): Total amount to send (combined ETH + stETH value); `stethBal` (uint256): Available stETH balance for transfers |
| **Returns** | none |

**State Reads:**
- None (operates purely on parameters and external calls)

**State Writes:**
- None (no storage writes; only external transfers)

**Callers:**
- `handleGameOverDrain` -- for undistributed remainder after jackpot distribution
- `handleFinalSweep` -- for all excess funds after 30-day waiting period

**Callees:**
- `steth.transfer(ContractAddresses.VAULT, ...)` -- transfer stETH to Vault
- `steth.approve(ContractAddresses.DGNRS, ...)` -- approve DGNRS to pull stETH
- `dgnrs.depositSteth(...)` -- deposit stETH into DGNRS contract
- `payable(ContractAddresses.VAULT).call{value: ethAmount}("")` -- send raw ETH to Vault
- `payable(ContractAddresses.DGNRS).call{value: ethAmount}("")` -- send raw ETH to DGNRS

**ETH Flow:**
Split `amount` 50/50 between Vault and DGNRS, prioritizing stETH transfers:

1. **Vault share** (`vaultAmount = amount - amount/2`):
   - If `vaultAmount <= stethBal`: transfer entire vault share as stETH
   - Else: transfer all available stETH to vault, then send remaining as raw ETH
2. **DGNRS share** (`dgnrsAmount = amount/2`):
   - If `dgnrsAmount <= stethBal` (remaining after vault): approve + depositSteth
   - Else: approve + depositSteth for remaining stETH, then send remaining as raw ETH

The stETH-first priority means: vault gets stETH first, DGNRS gets whatever stETH remains, and any shortfall is covered by raw ETH.

**Invariants:**
- `dgnrsAmount + vaultAmount == amount` (guaranteed by `amount - amount/2` rounding)
- Every transfer is checked: stETH transfer/approve returns bool (reverts with `E()` on false), raw ETH call checked for success
- `stethBal` is decremented locally to track remaining stETH availability across the vault and DGNRS splits

**NatSpec Accuracy:**
- "Send funds to vault (50%) and DGNRS (50%), prioritizing stETH transfers over ETH" -- accurate
- "Total amount to send (combined ETH + stETH value)" -- accurate
- `@custom:reverts E When stETH transfer, approval, or ETH transfer fails` -- accurate

**Gas Flags:**
- The `stethBal` parameter is tracked locally (decremented in-function) rather than re-querying `steth.balanceOf`. This is correct within a single transaction but relies on the caller providing an accurate initial balance. Both callers (`handleGameOverDrain` and `handleFinalSweep`) read `steth.balanceOf(address(this))` immediately before calling this function, so the value is accurate.
- In `handleGameOverDrain`, `stBal` is read before deity refunds and jackpot distribution. Jackpot distribution does not move stETH (only credits `claimableWinnings`), so `stBal` remains valid when passed to `_sendToVault`. However, the decimator and terminal jackpot self-calls could theoretically trigger stETH operations in other modules. In practice, neither DecimatorModule nor JackpotModule touch stETH, so this is safe.
- Minor: `stethBal = 0` assignment on line 195 is unnecessary since the variable is only read in the DGNRS block which re-checks `dgnrsAmount <= stethBal`. After vault takes all stETH and sets `stethBal = 0`, DGNRS correctly falls through to the pure-ETH path. The assignment is redundant but not harmful.

**Verdict:** CORRECT

---

## Game-Over Terminal State Machine

### Overview

The game-over state is a permanent, irreversible terminal condition triggered by liveness guards (inactivity timeouts). Once entered, the system transitions through a multi-phase shutdown sequence: drain (jackpot distribution + vault transfer), waiting period (30 days for player claims), and final sweep (remaining dust to vault).

### Pre-GameOver State

Game-over is triggered by `DegenerusGameAdvanceModule._checkLiveness()` when:

- **Level 0:** `block.timestamp - levelStartTime > 912 days` (~2.5 years since deploy with no level advancement)
- **Level > 0:** `block.timestamp - levelStartTime > 365 days` (1 year of inactivity at any level)

The liveness guard fires during any `advanceGame()` call. Before invoking `handleGameOverDrain`, the AdvanceModule:

1. Checks if `nextPrizePool >= levelPrizePool[level]` -- if yes, the game is not actually stalled (safety check prevents false game-over)
2. Acquires RNG via `_gameOverEntropy()`:
   - Requests Chainlink VRF (returns 1 = request sent, wait for fulfillment)
   - After 3-day VRF timeout: falls back to earliest historical VRF word from `rngWordByDay`
   - Stores the word in `rngWordByDay[dailyIdx]`
3. Calls `handleGameOverDrain(dailyIdx)` via delegatecall

### handleGameOverDrain Phase

On entry, `gameOverFinalJackpotPaid == false` (first and only execution):

```
Step 1: Snapshot balances
  ethBal = address(this).balance
  stBal  = steth.balanceOf(address(this))
  totalFunds = ethBal + stBal

Step 2: Deity pass refunds (level < 10 only)
  budget = totalFunds - claimablePool  (protect existing liabilities)
  For each deityPassOwners[i] (FIFO order):
    refund = 20 ETH * purchasedCount
    refund = min(refund, budget)
    if refund != 0:
      claimableWinnings[owner] += refund
      totalRefunded += refund
      budget -= refund
    if budget == 0: break
  claimablePool += totalRefunded

Step 3: Recalculate available (after deity refunds may have increased claimablePool)
  available = totalFunds - claimablePool
  if available == 0: return (all funds reserved for claims)

Step 4: Set terminal flags
  gameOver = true
  gameOverTime = block.timestamp
  gameOverFinalJackpotPaid = true

Step 5: Fetch RNG
  rngWord = rngWordByDay[day]
  if rngWord == 0: return (RNG not ready, wait)

Step 6: Decimator jackpot (10%)
  decPool = available / 10
  decRefund = runDecimatorJackpot(decPool, lvl, rngWord)
  claimablePool += (decPool - decRefund)
  remaining = available - decPool + decRefund

Step 7: Terminal jackpot (remaining 90% + decimator refund)
  termPaid = runTerminalJackpot(remaining, lvl+1, rngWord)
  remaining -= termPaid

Step 8: Vault sweep (undistributed remainder)
  if remaining > 0: _sendToVault(remaining, stBal)
```

### 30-Day Waiting Period

After `handleGameOverDrain` completes:
- `gameOver == true`, `gameOverTime` is set, `gameOverFinalJackpotPaid == true`
- Players can still call `claimWinnings()` to withdraw their credited balances
- `claimablePool` tracks the aggregate liability
- The system holds ETH/stETH >= `claimablePool` to cover all pending claims
- No new purchases or game actions are possible (game logic checks `gameOver` flag)

### handleFinalSweep Phase

After `block.timestamp >= gameOverTime + 30 days`:
- Triggered by any `advanceGame()` call (liveness guard routes to `handleFinalSweep` when `gameOver == true`)
- Shuts down VRF subscription via `admin.shutdownVrf()` (fire-and-forget)
- Sweeps excess funds: `totalFunds - claimablePool` to Vault (50%) and DGNRS (50%)
- `claimablePool` reserve is preserved for ongoing player withdrawals
- Can be called multiple times safely (no-ops after first sweep)

### Post-Sweep Terminal State

After final sweep:
- All excess ETH/stETH transferred to Vault and DGNRS
- Only `claimablePool` ETH remains in the game contract
- Players can still claim their `claimableWinnings` indefinitely (no expiry on claims)
- VRF subscription cancelled, LINK swept to vault
- System is fully drained and inert

### State Transition Diagram

```
[Normal Game]
    |
    | advanceGame() -> _checkLiveness() fires
    | (912d level-0 timeout OR 365d inactivity)
    v
[Liveness Triggered]
    |
    | Safety check: nextPrizePool < levelPrizePool[level]
    | Acquire RNG via _gameOverEntropy()
    v
[RNG Acquired] ------rngWord==0/1------> [Wait for VRF/Fallback]
    |                                          |
    | rngWord ready                            | (re-call advanceGame)
    v                                          |
[handleGameOverDrain]  <-----------------------+
    |
    | gameOver=true, gameOverTime=now, gameOverFinalJackpotPaid=true
    | Deity refunds credited (level<10)
    | Decimator jackpot (10%)
    | Terminal jackpot (90%+refund)
    | Remainder -> vault/DGNRS
    v
[Drain Complete, Pools Zeroed]
    |
    | 30 days pass...
    | (players claim winnings during this period)
    v
[handleFinalSweep]
    |
    | VRF shutdown (fire-and-forget)
    | Excess funds -> vault (50%) + DGNRS (50%)
    | claimablePool preserved
    v
[Fully Swept, Terminal]
    |
    | Players claim remaining winnings indefinitely
    v
[Inert Contract]
```

## Deity Pass Refund Logic

### Refund Calculation

- **Eligibility:** Only for early game over (levels 0-9, i.e., `currentLevel < 10`)
- **Rate:** Flat `DEITY_PASS_EARLY_GAMEOVER_REFUND = 20 ether` per deity pass purchased
- **Count source:** `deityPassPurchasedCount[owner]` (excludes non-purchased passes like grants)
- **Per-owner refund:** `20 ETH * purchasedCount`

### Budget Constraint

- **Budget:** `totalFunds - claimablePool` (total contract ETH+stETH minus existing claim liabilities)
- If budget < total refunds needed, passes are refunded FIFO until budget exhausted
- Remaining pass holders receive zero or partial refund

### FIFO Ordering

- Iteration follows `deityPassOwners[]` array, which preserves insertion order
- First-purchased (earliest array index) gets refunded first
- If budget runs out mid-iteration, the loop breaks with `if (budget == 0) break`
- Later purchasers may receive nothing if budget is exhausted

### Budget Exhaustion Example

With 3 deity pass owners (each purchased 1 pass) and budget = 45 ETH:
- Owner A: refund = 20 ETH, budget = 25 ETH remaining
- Owner B: refund = 20 ETH, budget = 5 ETH remaining
- Owner C: refund = min(20, 5) = 5 ETH, budget = 0 ETH -- loop breaks

### Accounting

- Refunds credited to `claimableWinnings[owner]` (pull pattern, not direct transfer)
- `claimablePool += totalRefunded` after loop (single update, not per-iteration)
- Deity refunds reduce the "available" pool for subsequent jackpot distribution

## ETH Mutation Path Map

| # | Path | Source | Destination | Trigger | Function | Amount |
|---|------|--------|-------------|---------|----------|--------|
| 1 | Deity refund credit | Available balance (totalFunds - claimablePool) | claimableWinnings[owner] (pull-pattern credit) | Game over, level < 10 | handleGameOverDrain | 20 ETH/pass, budget-capped |
| 2 | Decimator jackpot | Available balance (10%) | DecimatorModule snapshot (deferred claims) | Game over drain | handleGameOverDrain -> runDecimatorJackpot | available / 10 |
| 3 | Decimator refund return | DecimatorModule (unallocated) | Terminal jackpot pool | Decimator has no winners | handleGameOverDrain | decRefund (returned to remaining) |
| 4 | Terminal jackpot | Remaining (90% + dec refund) | claimableWinnings via JackpotModule | Game over drain | handleGameOverDrain -> runTerminalJackpot | remaining after decimator |
| 5 | Undistributed vault sweep | Remainder after terminal jackpot | Vault (50%) + DGNRS (50%) | Terminal jackpot underpays | handleGameOverDrain -> _sendToVault | remaining - termPaid |
| 6 | stETH to Vault | Contract stETH balance | DegenerusVault (stETH transfer) | Game over drain or final sweep | _sendToVault | min(vaultAmount, stethBal) |
| 7 | stETH to DGNRS | Contract stETH balance (after vault) | DegenerusStonk (approve+depositSteth) | Game over drain or final sweep | _sendToVault | min(dgnrsAmount, remaining stethBal) |
| 8 | ETH to Vault | Contract ETH balance | DegenerusVault (raw ETH call) | stETH insufficient for vault share | _sendToVault | vaultAmount - stethBal |
| 9 | ETH to DGNRS | Contract ETH balance | DegenerusStonk (raw ETH call) | stETH insufficient for DGNRS share | _sendToVault | dgnrsAmount - remaining stethBal |
| 10 | Final sweep excess | All excess (totalFunds - claimablePool) | Vault (50%) + DGNRS (50%) | 30 days post-gameover | handleFinalSweep -> _sendToVault | totalFunds - claimablePool |
| 11 | VRF shutdown + LINK sweep | Admin VRF subscription LINK | DegenerusVault | 30 days post-gameover | handleFinalSweep -> admin.shutdownVrf() | All subscription LINK |

### ETH Flow Ordering Within handleGameOverDrain

```
totalFunds (ETH + stETH)
    |
    +--> claimablePool reserved (existing liabilities)
    |
    +--> Deity refunds (level<10): credited to claimableWinnings, claimablePool increased
    |
    +--> available = totalFunds - claimablePool (recalculated after deity refunds)
    |
    +--> 10% to Decimator jackpot
    |       |
    |       +--> decSpend -> claimablePool (winners credited)
    |       +--> decRefund -> returned to remaining
    |
    +--> remaining to Terminal jackpot (next-level ticketholders)
    |       |
    |       +--> termPaid -> claimablePool (via JackpotModule internally)
    |       +--> undistributed -> _sendToVault (50% vault, 50% DGNRS)
    |
    +--> [30 days later] handleFinalSweep: excess -> _sendToVault
```

## Findings Summary

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | None found |
| CONCERN | 0 | None found |
| GAS (informational) | 1 | `handleFinalSweep` has no guard flag; re-calls cost gas for no-op (harmless, negligible lifetime impact) |
| CORRECT | 3 | All 3 functions verified correct |

### Overall Assessment

All 3 functions in DegenerusGameGameOverModule are **CORRECT**. The module implements a clean, irreversible terminal state machine with proper accounting invariants. Key strengths:

- Idempotency via `gameOverFinalJackpotPaid` flag (drain runs exactly once)
- Solvency preservation: `claimablePool` always reserved before any distribution
- Pull pattern for deity refunds (no direct transfers to external addresses during drain)
- Fire-and-forget VRF shutdown (cannot block fund recovery)
- 30-day waiting period provides ample time for player claim withdrawals
- stETH-first priority in `_sendToVault` maximizes yield-bearing asset flow to permanent reserves
