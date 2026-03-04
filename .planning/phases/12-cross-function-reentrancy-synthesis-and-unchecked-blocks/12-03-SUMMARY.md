---
phase: 12-cross-function-reentrancy-synthesis-and-unchecked-blocks
plan: "03"
subsystem: security-audit
tags: [reentrancy, CEI, operator-proxy, cursor-mutation, pool-accounting, delegatecall]

# Dependency graph
requires:
  - phase: 12-cross-function-reentrancy-synthesis-and-unchecked-blocks
    provides: RESEARCH.md analysis, REENT-01 through REENT-07 full finding set
provides:
  - REENT-03 PASS verdict: operator-proxy delegation no re-entry vector
  - REENT-05 PASS verdict: ticketCursor mutual exclusion formally proved
  - REENT-06 PASS verdict: claimDecimatorJackpot CEI correct
  - REENT-07 PASS verdict: adminSwapEthForStEth pool invariant preserved
affects: [13-final-report]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/phases/12-cross-function-reentrancy-synthesis-and-unchecked-blocks/12-03-SUMMARY.md
  modified: []

key-decisions:
  - "REENT-03 PASS: _resolvePlayer is a pure view function (SLOAD only), no external call or callback — operator approval chain has no re-entry surface"
  - "REENT-05 PASS: In the purchase-phase path, processFutureTicketBatch uses lvl=purchaseLevel+1 and processTicketBatch uses lvl=purchaseLevel — the one-level difference guarantees the ticketLevel != lvl guard always resets the cursor; in the final-jackpot-day path the two code paths are mutually exclusive by the do-while conditional structure"
  - "REENT-06 PASS: e.claimed=1 is written at DecimatorModule line 391 inside _consumeDecClaim, which is called at line 417 before _creditDecJackpotClaimCore (line 424) and before the auto-rebuy path — CEI is correct"
  - "REENT-07 PASS: adminSwapEthForStEth is value-neutral (ETH +amount, stETH -amount); amount==0 guard at line 1860 blocks zero-amount calls; steth.transfer() is ERC-20 with no callback; claimablePool and futurePrizePool are never read or written in the function"

patterns-established: []

requirements-completed: [REENT-03, REENT-05, REENT-06, REENT-07]

# Metrics
duration: 12min
completed: 2026-03-04
---

# Phase 12 Plan 03: REENT-03, REENT-05, REENT-06, REENT-07 Verdicts Summary

**Four reentrancy/accounting verdicts delivered: operator-proxy (PASS), cursor mutual exclusion (PASS with formal proof), decimator CEI (PASS), stETH swap invariant (PASS)**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-04T23:38:14Z
- **Completed:** 2026-03-04T23:50:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- REENT-03 PASS: Confirmed _resolvePlayer is a pure storage read with no callback, no external call, no multicall interface in DegenerusGame
- REENT-05 PASS: Formally proved cursor mutual exclusion via level-offset argument — processFutureTicketBatch always uses a different lvl than processTicketBatch in both code paths where they appear
- REENT-06 PASS: Confirmed CEI ordering — e.claimed=1 at line 391 inside _consumeDecClaim precedes _creditDecJackpotClaimCore at line 424 and all auto-rebuy storage paths
- REENT-07 PASS: Confirmed value-neutral stETH swap with amount==0 guard, no claimablePool access, stETH ERC-20 standard (no callback)

---

## Verdict Detail

### REENT-03 — Operator-Proxy Delegation Re-entry

**REENT-03 VERDICT: PASS**

**Claim:** An operator approved by a player (via `setOperatorApproval`) cannot trigger re-entry through the delegation chain.

**Evidence:**

`DegenerusGame.sol` lines 492-503:
```solidity
function _requireApproved(address player) private view {
    if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
        revert NotApproved();
    }
}

function _resolvePlayer(address player) private view returns (address resolved) {
    if (player == address(0)) return msg.sender;
    if (player != msg.sender) _requireApproved(player);
    return player;
}
```

Analysis:
- `_resolvePlayer` is a `private view` function — it reads `operatorApprovals[player][msg.sender]` (one SLOAD) and either returns the player address or reverts.
- No external call is made inside `_resolvePlayer` or `_requireApproved`.
- No callback is triggered — `operatorApprovals` is a plain `mapping(address => mapping(address => bool))` in `DegenerusGameStorage`. A boolean mapping read cannot trigger code execution.
- There is no `multicall` function in `DegenerusGame.sol` (confirmed: grep finds no matches for "multicall").
- The delegatecall game modules are invoked from within DegenerusGame (e.g., lines 592-596 for `purchaseCoin`), not as a public multicall interface.
- `_resolvePlayer` is called at the entry of external functions (e.g., `purchase`, `purchaseCoin`, `openLootBox`) to resolve the beneficiary address. The call fully completes before any module delegatecall fires. No re-entry surface exists through the operator chain.

**Severity if finding:** N/A — PASS.

---

### REENT-05 — ticketCursor/ticketLevel Mutual Exclusion

**REENT-05 VERDICT: PASS**

**Claim:** `processTicketBatch` (JackpotModule) and `processFutureTicketBatch` (MintModule) share `ticketCursor` and `ticketLevel` storage. A cursor collision would occur if both functions were called with the same `lvl` argument in the same advance lifecycle, causing processTicketBatch to inherit a mid-batch cursor offset from processFutureTicketBatch.

**Stage constant values** (`DegenerusGameAdvanceModule.sol` lines 42-53):
```
STAGE_GAMEOVER               = 0
STAGE_RNG_REQUESTED          = 1
STAGE_TRANSITION_WORKING     = 2
STAGE_TRANSITION_DONE        = 3
STAGE_FUTURE_TICKETS_WORKING = 4   // processFutureTicketBatch
STAGE_TICKETS_WORKING        = 5   // processTicketBatch
STAGE_PURCHASE_DAILY         = 6
STAGE_ENTERED_JACKPOT        = 7
STAGE_JACKPOT_ETH_RESUME     = 8
STAGE_JACKPOT_COIN_TICKETS   = 9
STAGE_JACKPOT_PHASE_ENDED    = 10
STAGE_JACKPOT_DAILY_STARTED  = 11
```

`STAGE_FUTURE_TICKETS_WORKING (4) < STAGE_TICKETS_WORKING (5)` — future-ticket processing always precedes ticket batch processing in the advance lifecycle.

**Lvl argument analysis** (AdvanceModule `advanceGame()` lines 111-285):

Local variables at function entry:
- `uint24 lvl = level`
- `uint24 purchaseLevel = (lastPurchase && rngLockedFlag) ? lvl : lvl + 1` (typically `lvl + 1`)

**Purchase-phase path (lines 178-213):**
```
// Step 1: processTicketBatch
_runProcessTicketBatch(purchaseLevel)     // lvl = purchaseLevel (e.g., N+1)
  → if still working: stage = STAGE_TICKETS_WORKING; break

// Step 2 (after tickets finish): processFutureTicketBatch
uint24 nextLevel = purchaseLevel + 1;     // N+2
_processFutureTicketBatch(nextLevel)      // lvl = purchaseLevel + 1 (e.g., N+2)
  → if still working: stage = STAGE_FUTURE_TICKETS_WORKING; break
```

Wait — the ordering in the actual do-while loop (lines 178-213) is:
1. `_runProcessTicketBatch(purchaseLevel)` is called FIRST (lines 179-185)
2. Only after tickets finish does execution proceed to the FUTURE_TICKETS block (lines 202-213) with `nextLevel = purchaseLevel + 1`

So `processTicketBatch` uses `purchaseLevel` (e.g., N+1) and `processFutureTicketBatch` uses `purchaseLevel + 1` (e.g., N+2). These differ by 1. The cursor reset condition `if (ticketLevel != lvl) { ticketCursor = 0; ticketLevel = lvl; }` fires in MintModule when switching from level N+1 to N+2. No cursor collision possible.

**Final-jackpot-day path (lines 161-185):**
```solidity
if (inJackpot && jackpotCounter == JACKPOT_LEVEL_CAP - 1 && ...) {
    if (!_prepareFinalDayFutureTickets(lvl)) {     // lvl = level (e.g., N)
        stage = STAGE_FUTURE_TICKETS_WORKING;
        break;   // <-- RETURNS HERE if still working
    }
}
// Only reaches here if prepareFinalDayFutureTickets returned true (finished)
_runProcessTicketBatch(purchaseLevel);             // lvl = purchaseLevel (N or N+1)
```

`_prepareFinalDayFutureTickets(lvl)` processes levels `lvl+2` through `lvl+5` (lines 903-928). So future-ticket levels are N+2..N+5, while processTicketBatch uses `purchaseLevel` (N or N+1). These never overlap. Moreover, the `break` ensures that if future-ticket work is still in progress, processTicketBatch is never called in that same invocation.

**Formal mutual exclusion proof:**

In all paths through `advanceGame()`, the `lvl` argument to `processFutureTicketBatch` is always strictly greater than the `lvl` argument to `processTicketBatch`:
- Purchase phase: future uses `purchaseLevel + 1`, tickets uses `purchaseLevel` → delta = +1
- Final jackpot day: future uses `lvl + 2..lvl + 5`, tickets uses `purchaseLevel` (= `lvl` or `lvl + 1`) → delta >= +1

Therefore, when `processTicketBatch` is called after any `processFutureTicketBatch` call that set `ticketLevel = K`, the invariant `K > purchaseLevel` holds. Since `processTicketBatch` is called with `purchaseLevel < K`, the condition `ticketLevel != lvl` evaluates to `K != purchaseLevel = true`, triggering a cursor reset. No cursor state is ever inherited between the two functions.

**Severity if finding:** N/A — PASS.

---

### REENT-06 — claimDecimatorJackpot CEI Ordering

**REENT-06 VERDICT: PASS**

**Claim:** `claimDecimatorJackpot` follows Checks-Effects-Interactions — the `e.claimed = 1` effect precedes all interactions including the auto-rebuy delegatecall path.

**Evidence** (`DegenerusGameDecimatorModule.sol`):

```
Line 416: function claimDecimatorJackpot(uint24 lvl) external {
Line 417:     uint256 amountWei = _consumeDecClaim(msg.sender, lvl);  // CHECK + EFFECT
                                   // → internally calls _consumeDecClaim which:
                                   //   line 377: if (e.claimed != 0) revert DecAlreadyClaimed(); [CHECK]
                                   //   line 391: e.claimed = 1;  [EFFECT — anti-replay written here]
                                   //   returns amountWei
Line 418:
Line 419:     if (gameOver) {
Line 420:         _addClaimableEth(msg.sender, amountWei, lastDecClaimRound.rngWord);  [INTERACTION - gameOver path]
Line 421:         return;
Line 422:     }
Line 423:
Line 424:     uint256 lootboxPortion = _creditDecJackpotClaimCore(  [INTERACTION - normal path]
```

CEI breakdown:
- **CHECK (line 374):** `if (lastDecClaimRound.lvl != lvl) revert DecClaimInactive()`
- **CHECK (line 377):** `if (e.claimed != 0) revert DecAlreadyClaimed()`
- **EFFECT (line 391):** `e.claimed = 1` — written to `DecEntry` storage before any external interaction
- **INTERACTION (line 417 → line 420/424):** `_addClaimableEth` → `_processAutoRebuy` → `_queueTickets`; `_creditDecJackpotClaimCore` → `_addClaimableEth` → `_processAutoRebuy`

Auto-rebuy path trace:
`_creditDecJackpotClaimCore` (line 527) → `_addClaimableEth` (line 536) → `_processAutoRebuy` (line 514) → `_queueTickets` (line 485) — this is internal storage mutation only (`_queueTickets` writes to the ticket queue in game storage, no external call). The DecimatorModule has no `_callTicketPurchase` delegatecall inside the auto-rebuy path — `_processAutoRebuy` calls `_queueTickets` directly (line 485 of DecimatorModule), not via external call.

There is a delegatecall at line 733-735 of DecimatorModule (in `_resolveDecimatorLootbox`), but this code path is NOT reachable from `claimDecimatorJackpot`. It is only triggered from the advance-game decimator resolution code.

If a reentrant caller could re-enter `claimDecimatorJackpot` at any point after line 417, the `e.claimed != 0` check at line 377 would revert — the re-entry guard is already in place.

**Severity if finding:** N/A — PASS.

---

### REENT-07 — adminSwapEthForStEth Pool Accounting Invariant

**REENT-07 VERDICT: PASS**

**Claim:** `adminSwapEthForStEth` preserves the ETH solvency invariant `address(this).balance + steth.balanceOf(this) >= claimablePool`.

**Evidence** (`DegenerusGame.sol` lines 1854-1865):

```solidity
function adminSwapEthForStEth(address recipient, uint256 amount) external payable {
    if (msg.sender != ContractAddresses.ADMIN) revert E();     // access control
    if (recipient == address(0)) revert E();                   // zero-address guard
    if (amount == 0 || msg.value != amount) revert E();        // amount==0 guard + exact match
    uint256 stBal = steth.balanceOf(address(this));
    if (stBal < amount) revert E();                            // sufficiency guard (>=)
    if (!steth.transfer(recipient, amount)) revert E();        // ERC-20 transfer out
}
```

Analysis point-by-point:

**(a) amount==0 guard:** `if (amount == 0 || msg.value != amount) revert E()` at line 1860 — zero-amount calls revert. The combined guard also requires `msg.value == amount` exactly, preventing gas griefing where caller sends 0 ETH but claims any stETH.

**(b) Sufficiency guard strictness:** `stBal < amount` uses strict less-than, so the revert fires when `stBal < amount`. Equivalently this allows `stBal >= amount` — a non-strict greater-or-equal. Swapping exactly the full stETH balance (`stBal == amount`) succeeds. This is correct — a swap that reduces stETH to zero while receiving equal ETH is value-neutral.

**(c) claimablePool and futurePrizePool:** Reading the full function body (lines 1854-1865): neither `claimablePool` nor `futurePrizePool` appears anywhere in `adminSwapEthForStEth`. The invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` has both sides affected symmetrically: ETH balance increases by `msg.value = amount`, stETH balance decreases by `amount`. The left side is unchanged. The right side (`claimablePool`) is unchanged. Invariant preserved.

**(d) stETH ERC-20 interface — no callback:** The `IStETH` interface used in DegenerusGame.sol (line 165, imported from `contracts/interfaces/IStETH.sol`) exposes: `submit`, `balanceOf`, `transfer`, `approve`. There is no `onTokenTransfer` hook, no ERC-777 `tokensToSend`/`tokensReceived` hooks, no flash loan callback. Lido stETH is ERC-20 only. Phase 8-02 previously confirmed this. The `steth.transfer()` call at line 1864 completes without invoking any code on the game contract.

**(e) Net accounting proof:**
```
Before: ETH_bal = E, stETH_bal = S, claimablePool = C
Call:   msg.value = amount = A
After:  ETH_bal = E + A, stETH_bal = S - A (ERC-20 transfer out), claimablePool = C
Net:    (E + A) + (S - A) = E + S = unchanged total
Invariant: E + S >= C → (E + A) + (S - A) = E + S >= C ✓
```

**Note on stETH rebasing:** Lido stETH is a rebasing token — `balanceOf(address)` may increase slightly over time due to staking rewards. This only improves the solvency invariant. The `stBal >= amount` check uses the current share-adjusted balance at the time of the call, which is correct.

**Severity if finding:** N/A — PASS.

---

## Task Commits

Each task was committed atomically:

1. **Task 1: REENT-03 + REENT-06 + REENT-07 confirmed PASS** - (docs: analysis commit)
2. **Task 2: REENT-05 formal mutual exclusion proof** - (docs: analysis commit)

**Plan metadata:** (docs: phase 12-03 complete)

## Files Created/Modified
- `.planning/phases/12-cross-function-reentrancy-synthesis-and-unchecked-blocks/12-03-SUMMARY.md` — This file; all four REENT verdicts

## Decisions Made
- REENT-03 PASS: operator chain is a pure view SLOAD with no external call — confirmed no multicall interface in DegenerusGame
- REENT-05 PASS: Formal proof established via level-offset argument — future tickets always use lvl N+k (k>=1) relative to current-level tickets; ticketLevel != lvl guard always resets cursor at boundary
- REENT-06 PASS: e.claimed=1 written at _consumeDecClaim line 391 before _creditDecJackpotClaimCore line 424; auto-rebuy path is internal storage only (no external call from DecimatorModule during normal claim)
- REENT-07 PASS: stETH swap is value-neutral by construction; amount==0 guard confirmed; stETH is ERC-20 only; claimablePool untouched

## Deviations from Plan
None — plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- All four REENT verdicts complete: REENT-03, REENT-05, REENT-06, REENT-07 all PASS
- Combined with 12-01 and 12-02 results, Phase 12 full coverage is delivered
- Phase 13 (final report synthesis) can now collate all Phase 12 findings: REENT-01 through REENT-07 complete

---
*Phase: 12-cross-function-reentrancy-synthesis-and-unchecked-blocks*
*Completed: 2026-03-04*
