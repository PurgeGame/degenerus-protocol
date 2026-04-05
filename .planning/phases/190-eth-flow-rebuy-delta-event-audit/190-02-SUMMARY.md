---
phase: 190-eth-flow-rebuy-delta-event-audit
plan: 02
subsystem: audit
tags: [solidity, delta-audit, prize-pool, auto-rebuy, SSTORE, event-emission]

requires:
  - phase: 190-eth-flow-rebuy-delta-event-audit/01
    provides: "ETH flow equivalence proof for all BAF winner paths"
provides:
  - "Proof that removed rebuy delta reconciliation is safe (storage writes overwritten by _setPrizePools)"
  - "Enumeration of all _setFuturePrizePool call sites in BAF/decimator self-call chains"
  - "Consumer search confirming unconditional RewardJackpotsSettled emission is behaviorally neutral"
affects: []

tech-stack:
  added: []
  patterns: [per-requirement-verdict-table, storage-write-chain-trace, event-consumer-search]

key-files:
  created:
    - ".planning/phases/190-eth-flow-rebuy-delta-event-audit/190-02-SUMMARY.md"
  modified: []

key-decisions:
  - "Old rebuy delta reconciliation was compensating for over-deduction in multi-step BAF accounting -- new single-deduction makes it redundant"
  - "No on-chain consumer can depend on event emission conditionality (events are log-only)"

patterns-established:
  - "Storage write chain trace: snapshot load -> sub-call writes -> final SSTORE overwrite"

requirements-completed: [DELTA-01, DELTA-02, EVT-01]

duration: 8min
completed: 2026-04-05
---

# Phase 190 Plan 02: Rebuy Delta Removal + Event Audit Summary

**Proved _setPrizePools overwrite safety for auto-rebuy storage writes, enumerated all futurePool write sites in self-call chains (1 in BAF, 0 in decimator), confirmed no consumer depends on conditional RewardJackpotsSettled emission**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-05T23:46:12Z
- **Completed:** 2026-04-05T23:54:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Traced full storage write chain proving `memFuture -= claimed` + `_setPrizePools` overwrite is equivalent to old multi-step deduction + rebuy delta reconciliation
- Enumerated all `_setFuturePrizePool` call sites reachable from BAF and decimator self-call paths: only `_processAutoRebuy` line 839 during BAF, none during decimator
- Confirmed `RewardJackpotsSettled` has zero on-chain consumers and no test assertions on conditionality

## Verdict Table

| Requirement | Verdict | Rationale |
|-------------|---------|-----------|
| DELTA-01 | **EQUIVALENT** | Old rebuy delta reconciliation compensated for over-deduction in multi-step accounting; new `memFuture -= claimed` does not over-deduct, making reconciliation redundant; `_setPrizePools` overwrites the interim storage write |
| DELTA-02 | **EQUIVALENT** | Only `_processAutoRebuy` (line 839) writes to futurePool during BAF self-call; `_processSoloBucketWinner` is unreachable from `runBafJackpot`; `runDecimatorJackpot` only snapshots to `decClaimRounds`, no futurePool write |
| EVT-01 | **EQUIVALENT** | Events are log-only (not readable on-chain); no test asserts on emission conditionality; off-chain indexer code out of scope per D-04; unconditional emit adds at most a few extra log entries on non-jackpot levels |

---

## DELTA-01: Auto-rebuy storage write safely overwritten by _setPrizePools

**Verdict: EQUIVALENT**

### Storage Write Chain Trace

**Step 1: Memory snapshot at entry**

`_consolidatePoolsAndRewardJackpots` (AdvanceModule line 625):
```
uint256 memFuture = _getFuturePrizePool();   // loads from prizePoolsPacked STORAGE
```

**Step 2: BAF self-call path (lines 713-724)**

When `lvl % 10 == 0`:
```
uint256 bafPoolWei = (baseMemFuture * bafPct) / 100;
uint256 claimed = IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord);
memFuture -= claimed;
claimableDelta += claimed;
```

**Step 3: Inside runBafJackpot (JackpotModule lines 2484-2553)**

For each winner, `_addClaimableEth` is called. When auto-rebuy is enabled, it delegates to `_processAutoRebuy` (line 798), which at line 839 writes:
```
_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent);   // STORAGE write during execution
```
This modifies `prizePoolsPacked` in storage while the caller's `memFuture` is stale (loaded before the self-call).

`_addClaimableEth` returns `calc.reserved` (take-profit portion only), NOT the full `weiAmount`. The ticket conversion ETH (`calc.ethSpent`) is NOT included in `claimableDelta`.

**Step 4: Return to caller**

Control returns to `_consolidatePoolsAndRewardJackpots`. The `claimed` value is the sum of all `_addClaimableEth` return values = sum of take-profit portions. `memFuture -= claimed` deducts only the take-profit ETH.

**Step 5: Final overwrite (line 788)**
```
_setPrizePools(uint128(memNext), uint128(memFuture));   // overwrites prizePoolsPacked
```
This clobbers the storage write made by `_processAutoRebuy` in step 3.

### Why the old reconciliation was needed (and why it is now redundant)

**OLD code had a multi-step deduction:**
```
memFuture -= bafPoolWei;                              // deduct full pool allocation
// ... runBafJackpot returns (netSpend, claimed, lootboxToFuture) ...
if (netSpend != bafPoolWei) memFuture += (bafPoolWei - netSpend);   // add back refund
if (lootboxToFuture != 0)  memFuture += lootboxToFuture;            // add back lootbox
```

This netted to: `memFuture -= netSpend - lootboxToFuture`.

Where `netSpend = poolWei - refund` (total consumed from pool). This included the ETH that went to auto-rebuy tickets (`calc.ethSpent`), because that ETH was spent from the pool. But `lootboxToFuture` only tracked `_awardJackpotTickets` calls, NOT auto-rebuy ticket purchases. So the multi-step deduction over-deducted by `calc.ethSpent` (the auto-rebuy ticket ETH).

The old reconciliation line compensated:
```
memFuture += _getFuturePrizePool() - storageBaseFuture;
```
This re-read storage (which now contained the auto-rebuy write from step 3) and added back the delta = `calc.ethSpent`. This corrected the over-deduction.

**NEW code has a single-step deduction:**
```
memFuture -= claimed;
```

Where `claimed` = sum of `_addClaimableEth` returns = sum of take-profit portions only. The ticket ETH (`calc.ethSpent`) is never deducted from `memFuture` in the first place. It remains in `memFuture` (correct, because the ETH is still economically in the future pool -- it was converted to tickets).

The `_processAutoRebuy` storage write (step 3) is an interim write that gets overwritten by `_setPrizePools` at step 5. Since `memFuture` already correctly includes the ticket ETH (by never deducting it), the final `_setPrizePools` write is correct.

### Algebraic proof

Let:
- `F` = initial `memFuture` at function entry
- `T` = total take-profit ETH (sum of `calc.reserved` across all auto-rebuy winners + direct claimable amounts)
- `R` = auto-rebuy ticket ETH (sum of `calc.ethSpent` across all auto-rebuy winners)

**OLD path:** `memFuture_final = F - netSpend + lootboxToFuture + R`
- `netSpend` included `T + R + lootbox + whalePass`, minus refund
- `lootboxToFuture` added back lootbox portion
- `+R` from the reconciliation line
- After cancellation: `memFuture_final = F - T` (refund, lootbox, whale pass, and ticket ETH all cancel out)

**NEW path:** `memFuture_final = F - T` (only `claimed = T` is deducted)

Both produce `F - T`. The new code is correct.

---

## DELTA-02: No other futurePool storage writes in BAF/decimator self-call chain depend on removed delta

**Verdict: EQUIVALENT**

### All _setFuturePrizePool call sites in JackpotModule

| Line | Function | Context | Reachable from runBafJackpot? |
|------|----------|---------|-------------------------------|
| 839 | `_processAutoRebuy` | `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` -- auto-rebuy ticket ETH | **YES** -- via `_addClaimableEth` -> `_processAutoRebuy` |
| 1557 | `_processSoloBucketWinner` | `_setFuturePrizePool(_getFuturePrizePool() + whalePassCost)` -- whale pass ETH | **NO** -- only reachable from trait jackpot path: `_executeJackpot` -> `_distributeJackpotEth` -> `_processOneBucket` -> `_resolveTraitWinners` -> `_processSoloBucketWinner` |
| 401 | (daily jackpot reserve) | `_setFuturePrizePool(futurePoolBal - reserveSlice)` | **NO** -- daily jackpot execution path |
| 460 | (unpaid daily ETH) | `_setFuturePrizePool(_getFuturePrizePool() + unpaidDailyEth)` | **NO** -- daily jackpot execution path |
| 504 | (lootbox budget) | `_setFuturePrizePool(_getFuturePrizePool() - lootboxBudget - paidEth)` | **NO** -- daily jackpot execution path |
| 665 | (reserve contribution) | `_setFuturePrizePool(futurePoolLocal - reserveContribution)` | **NO** -- yield distribution path |

### All _setFuturePrizePool call sites in DecimatorModule

| Line | Function | Context | Reachable from runDecimatorJackpot? |
|------|----------|---------|-------------------------------------|
| 347 | `claimDecJackpot` (deferred claim) | `_setFuturePrizePool(_getFuturePrizePool() + lootboxPortion)` | **NO** -- this is the deferred CLAIM path, called by players after the jackpot is snapshotted, not during the self-call |
| 398 | `_processAutoRebuy` (decimator variant) | `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` | **NO** -- this is in the decimator's deferred claim path (`claimDecJackpot` -> `_creditDecJackpotClaimCore` -> `_processAutoRebuy`), not during the self-call |

### runBafJackpot call chain verification

`runBafJackpot` (line 2484) calls:
- `jackpots.runBafJackpot()` -- external call to DegenerusJackpots, returns winners/amounts/refund (no storage write to game)
- `_addClaimableEth()` -- may call `_processAutoRebuy` which writes line 839 (**the one futurePool write**)
- `_awardJackpotTickets()` -- calls `_jackpotTicketRoll` -> `_queueLootboxTickets` -> `_queueTicketsScaled` (ticket storage only, **no futurePool write**)
- `_queueWhalePassClaimCore()` -- writes to `whalePassClaims` and optionally `claimableWinnings`/`claimablePool` (**no futurePool write**)

None of these call `_processSoloBucketWinner`. Confirmed: `_processSoloBucketWinner` is only reachable from the trait jackpot path (`_resolveTraitWinners`, called from `_processOneBucket`, called from `_distributeJackpotEth`, called from `_executeJackpot`).

### runDecimatorJackpot call chain verification

`runDecimatorJackpot` (DecimatorModule line 215):
- Checks for double-snapshot (`decClaimRounds[lvl].poolWei != 0`)
- Iterates denominators 2-12, selects winning subbuckets, accumulates burn totals
- Writes: `decBucketOffsetPacked[lvl]`, `decClaimRounds[lvl].poolWei`, `.totalBurn`, `.rngWord`
- Returns 0 (all funds held) or `poolWei` (no winners)
- **Does NOT call `_setFuturePrizePool`, `_addClaimableEth`, or any payout function**
- Payouts happen later when players call `claimDecJackpot` (separate transaction)

**Conclusion:** The only futurePool storage write during the BAF self-call is `_processAutoRebuy` line 839, which is safely overwritten by `_setPrizePools` at line 788 of `_consolidatePoolsAndRewardJackpots`. The decimator self-call writes zero futurePool state. No writes in either chain depended on the removed rebuy delta reconciliation.

---

## EVT-01: Unconditional RewardJackpotsSettled emission has no conditional consumers

**Verdict: EQUIVALENT**

### On-chain consumer search

Events in Solidity are EVM LOG opcodes -- they write to the transaction receipt log, NOT to contract storage. No on-chain contract can read whether an event was emitted or conditionally branch on emission history. Therefore, no on-chain consumer can depend on the old conditional emission pattern.

`RewardJackpotsSettled` is defined in:
- `DegenerusGameAdvanceModule.sol` line 52 (event declaration)
- `DegenerusGameJackpotModule.sol` line 94 (event declaration, same signature via delegatecall shared context)
- `DegenerusGameAdvanceModule.sol` line 794 (sole emission site)

### Test consumer search

```
grep -rn "RewardJackpotsSettled" test/
```

Result: Single reference at `test/fuzz/BafRebuyReconciliation.t.sol` line 27, in a comment:
> "The RewardJackpotsSettled event (captured in -vvvv traces) confirms the post-reconciliation pool value exceeds the naive stale-overwrite value."

This is a trace-level observation note, **not** an assertion. No `vm.expectEmit`, no `assertEq` on emission count, no conditional test logic based on whether the event fired.

### Off-chain consumer assessment

Per decision D-04: off-chain indexer code is not in this repository. Any external indexer consuming `RewardJackpotsSettled` would:
1. See the same event signature and parameter types (unchanged)
2. Receive additional emissions on non-jackpot levels (where `claimableDelta == 0` and `memFuture` equals the pre-jackpot value)
3. These additional entries are informationally benign -- they report the current pool state on every advance

### Old conditional vs new unconditional

**Old condition:** `if (memFuture != storageBaseFuture || claimableDelta != 0)` -- emitted only when a jackpot fired or the pool changed.

**New behavior:** Emitted on every level advance (unconditional).

**Impact:** On non-jackpot levels (where `lvl % 10 != 0` and `lvl % 5 != 0`), there is no BAF or decimator call. But the time-based future take (lines 630-696) modifies `memFuture` on virtually every advance. So `memFuture != storageBaseFuture` was true on almost every call anyway (as noted in the commit message: "time-take ensures it fires on virtually every advance"). The unconditional emit adds at most a few extra LOG2 entries on edge cases where the time take happened to be zero, costing minimal extra gas (~375 gas per LOG2 with 3 topics + data).

**Conclusion:** No behavioral difference for any on-chain or known off-chain consumer.

---

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace auto-rebuy storage write chain and prove _setPrizePools overwrite safety** - `f40b2a25` (docs)

## Files Created/Modified

- `.planning/phases/190-eth-flow-rebuy-delta-event-audit/190-02-SUMMARY.md` - Rebuy delta + event audit with 3 requirement verdicts

## Decisions Made

- Old rebuy delta reconciliation (`memFuture += _getFuturePrizePool() - storageBaseFuture`) was compensating for over-deduction in the multi-step BAF accounting. The new single-deduction (`memFuture -= claimed`) never over-deducts, making reconciliation redundant.
- Unconditional event emission is safe because events are log-only (not on-chain readable) and no test asserts on conditionality.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 190 audit complete (both plans): all 8 requirements (FLOW-01 through FLOW-05, DELTA-01, DELTA-02, EVT-01) have verdicts
- No findings requiring code changes

## Self-Check: PASSED

- 190-02-SUMMARY.md: FOUND
- Commit f40b2a25: FOUND
- DELTA-01 sections: 4 references
- DELTA-02 sections: 4 references
- EVT-01 sections: 4 references

---
*Phase: 190-eth-flow-rebuy-delta-event-audit*
*Completed: 2026-04-05*
