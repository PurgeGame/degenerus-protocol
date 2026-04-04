# Phase 172 Continuation: 3 Remaining Foundry Failures

**Current state:** 375 passing, 3 failing (Foundry) | 1309 passing, 0 failing (Hardhat)

---

## Failure 1: TicketLifecycle — `testJackpotPhaseTicketsProcessedFromReadSlot`

**Error:** `EDGE-04: read queue at jackpot level must be empty after processing: 3 != 0`

**Root cause:** The test drives the game through multiple level transitions, then asserts the read queue is empty at the jackpot level. The `_readKeyForLevel(jLvl)` helper reads the *current* `ticketWriteSlot` from storage, but by assertion time the slot has been toggled by subsequent level transitions. This returns the wrong queue key — it checks the write queue (which has 3 entries: buyer3 + sDGNRS + VAULT) instead of the read queue.

**Fix approach:** Capture `ticketWriteSlot` at the exact moment jackpot phase is detected (before any `_swapAndFreeze` call). The read key at assertion time is `tqWriteKey(jLvl, wsAtJackpot)` — the OLD write key becomes the read slot after the first swap.

**File:** `test/fuzz/TicketLifecycle.t.sol`
**Difficulty:** Medium — requires understanding the double-buffer swap mechanics

---

## Failure 2: VRFPathInvariants — `invariant_allGapDaysBackfilled`

**Error:** `VRFPath: gap day missing rngWordForDay after recovery: 4 != 0`

**Root cause:** The VRFPathHandler's `warpTime` can accumulate multiple 30-day warps during a VRF stall. When recovery happens, `_backfillGapDays` caps at 120 days — but the handler's ghost tracking was checking all gap days. The 120-day cap fix reduced failures from 13→4, but 4 gap days within the 120-window are still not backfilled.

**Investigation needed:** The remaining 4 unfilled days could be:
1. Days that fall in the gap between the last processed day and the stall start (before VRF was locked)
2. An off-by-one in the gap range calculation (`gapStart` vs `ghost_dayBeforeSwap`)
3. A genuine backfill bug where certain day ranges are skipped

**Fix approach:** Add logging in the handler to capture exactly which 4 days are missing and what `dailyIdx` / `gapStart` / `gapEnd` values were at recovery time. Compare with the contract's actual `_backfillGapDays(startDay, endDay)` parameters.

**File:** `test/fuzz/handlers/VRFPathHandler.sol`, `test/fuzz/invariant/VRFPathInvariants.inv.t.sol`
**Difficulty:** Medium — needs trace analysis of the fuzzer's call sequence

---

## Failure 3: RedemptionInvariants (CoinSupply) — `invariant_supplyConsistency`

**Error:** `INV-04: totalSupply != initialSupply - totalBurned: 200003097... != 999998097...`

**Root cause:** The invariant formula `totalSupply == initialSupply - totalBurned` doesn't account for mints that happen during fuzzer execution. The `initialSupply` is captured at setUp, but `mintForGame`, `vaultMintTo`, quest rewards, and other mint paths increase `totalSupply` beyond what `initialSupply - totalBurned` predicts.

**Fix approach:** Update the invariant to: `totalSupply == initialSupply + totalMinted - totalBurned`. Add a `ghost_totalMinted` counter in the handler that tracks all mint calls.

**File:** `test/fuzz/invariant/CoinSupply.inv.t.sol`, handler that calls mint paths
**Difficulty:** Easy — add ghost tracking for mints

---

## Execution Order

1. **CoinSupply** (easiest — add ghost counter)
2. **TicketLifecycle** (medium — write slot capture timing)
3. **VRFPathInvariants** (medium — needs trace analysis)
