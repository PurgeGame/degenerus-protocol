---
phase: 318-tst-subscription-crank-correctness-removal-proofs-tst
plan: 04
subsystem: keeper
tags: [afking, keeper, sweep, concurrency, cursor, tombstone, funding-waterfall, two-tier-skip-kill, pinned-identity, SAFE-03, foundry]
requires:
  - "318-01: repaired DeployProtocol fixture (AfKing live at AF_KING; SUB-09 VAULT+SDGNRS self-subscribes in the set)"
  - "317-04: contracts/AfKing.sol parameterless cursor sweep + funding waterfall + two-tier pinned-identity skip-kill"
provides:
  - "test/fuzz/AfKingConcurrency.t.sol: SAFE-03 same-block cursor self-partition + tombstone-on-cancel no-miss coverage"
  - "test/fuzz/AfKingFundingWaterfall.t.sol: SUB-05 funding waterfall + SUB-06 two-tier pinned-identity skip-kill coverage"
affects: []
tech-stack:
  added: []
  patterns:
    - "single-drain log capture (vm.getRecordedLogs consumes the buffer; drain ONCE into a member array, count per-player from the snapshot)"
    - "Swept-cost (msgValue) decode to assert the chosen waterfall mode (DirectEth/Claimable/Combined) from the event payload"
    - "NORMAL control sub in the exempts' EXACT funding state to isolate the exemption to the pinned address"
    - "vm.readFile grep-clean assertion complementing the runtime spoof-resistance test"
key-files:
  created:
    - "test/fuzz/AfKingConcurrency.t.sol"
    - "test/fuzz/AfKingFundingWaterfall.t.sol"
  modified: []
decisions:
  - "Tasks 1+2 share AfKingConcurrency.t.sol and a single verify gate; committed as one atomic test commit (the per-task split is internal to the file, the gate is per-file)."
  - "Self-partition / exactly-once is proven by per-player lastSweptDay storage reads + per-player Swept event counts (not raw subscriberCount), so the 2 deploy-time SUB-09 subs (VAULT/SDGNRS, skipped reason 5 NotApproved) do not perturb the N-sub invariants."
  - "Waterfall mode is asserted from the Swept event's cost (msgValue) field: DirectEth==cost, Claimable==0, Combined==cost-(cred-1) -- a black-box read of the contract's per-player payment decision."
  - "The renewal-lapse-still-cancels-exempt test clears VAULT's permanent deity bit (mintPacked_ slot 9 shift 184) so the renewal hits the PAID all-or-nothing burnForKeeper path; without that, hasAnyLazyPass(VAULT) free-extends and there is no lapse."
metrics:
  duration: ~40m
  completed: 2026-05-23
  tasks: 3
  files: 2
---

# Phase 318 Plan 04: SAFE-03 Concurrency + Funding Waterfall + Two-Tier Skip-Kill Summary

Proved SAFE-03 (the sweep concurrency-correctness floor) and the SUB-05/SUB-06 funding waterfall + two-tier pinned-identity skip-kill empirically against the live `contracts/AfKing.sol`, on the 318-01-repaired Foundry fixture: two same-block sweeps self-partition via the advancing cursor with exactly-once buys, tombstone-on-cancel leaves no dead-slot buildup, and the funding-skip kill cancels NORMAL subs while VAULT/sDGNRS are exempt by un-spoofable pinned identity. Test-only — zero `contracts/*.sol` mutation.

## What Was Built

### Task 1 — Same-block cursor self-partition (`AfKingConcurrency.t.sol`)
- `testSameBlockTwoSweepsExactlyOnce`: N=6 healthy subs, two `sweep(4)` calls in the SAME block (no warp between); asserts the cursor advanced monotonically (B resumed from A's advanced position via `sweepProgress`) and **every sub was bought EXACTLY ONCE** (`lastSweptDay == today` and exactly one `Swept` per sub — no double-buy, no miss).
- `testSameBlockNoOverlapBetweenChunks`: a chunk-1 `sweep(3)` then a same-block chunk-2 `sweep(10)`; asserts a chunk-1 sub is NOT re-swept in chunk 2 (no overlap) and the union covers every sub once.
- `testCursorResetsPerDayAndEachSubBuysOncePerDay`: after a full day-1 sweep, `vm.warp(+1 days)` resets the cursor (the `sweepProgress` day-stamp tracks the new day) and each sub gets exactly one fresh buy.
- `testLastSweptDayBackstopBlocksRepeatBuyOnCursorRevisit`: forces the cursor back to 0 (slot-4 write) so the next sweep RE-VISITS an already-bought index; asserts the `lastSweptDay >= today` backstop blocks the second buy **independent of cursor position**.
- `testFuzzSameBlockSplitExactlyOnce` (1000 runs): over an arbitrary same-block split `(k, rest)`, `sum(buys) == N` and `max-per-player buys <= 1` — exactly-once across any interleaving.

### Task 2 — Tombstone-on-cancel no-miss + no dead-slot buildup (`AfKingConcurrency.t.sol`)
- `testCancelSwapPopOccupantStillProcessed`: cancel an early sub (`setDailyQuantity(0)` swap-pop), then sweep; asserts the still-active mover occupant is bought this sweep (the swap-pop did not strand it) and the cancelled sub is not processed.
- `testNoDeadSlotBuildupAcrossCancels`: cancels across two days; asserts `subscriberCount` shrinks by exactly the number of cancels (true swap-pop, no logical-delete hole) and every remaining index dereferences to a live, consistently back-pointed in-set address.
- `testCancelledSubPoolEthWithdrawable`: a cancelled sub's stranded `_poolOf` ETH is preserved through the cancel and fully withdrawable.
- `testCancelPreservesPaidUnexpiredWindow` / `testCancelReclaimsUnpaidWindow`: the SUB-07 windowPaid-gated reclaim — a PAID+unexpired window is preserved (dailyQuantity zeroed, flags+paidThroughDay kept) while an UNPAID window is fully deleted.

### Task 3 — Funding waterfall + two-tier pinned-identity skip-kill (`AfKingFundingWaterfall.t.sol`)
- SUB-05 waterfall, asserted from the `Swept` event's `cost` (msgValue) field:
  - `testWaterfallDirectEthWhenNotDraining`: `drainFirst=false` → DirectEth `msgValue==cost` (claimable ignored).
  - `testWaterfallClaimableOnlyWhenCredExceedsCost`: drain-first, `cred>cost` → Claimable `msgValue==0`, **empty pool still buys** (claimable-only is emergent, no new flag).
  - `testWaterfallCombinedTopsUpFromPool`: `1<cred<=cost` → Combined `msgValue==cost-(cred-1)`, pool covers exactly the shortfall.
  - `testWaterfallSentinelClaimableDegradesToDirectEth`: `cred<=1` sentinel → DirectEth `msgValue==cost`.
  - `testWaterfallInsufficientPoolWhenClaimablePlusPoolBelowCost`: `claimable+pool<cost` → InsufficientPool skip (under-funded sub not bought; a co-resident healthy sub still buys).
- SUB-06 two-tier skip-kill:
  - `testNormalSubFundingSkipCancelsViaSwapPop`: a NORMAL sub on a funding skip → `SubscriptionExpired(.,1)`, swap-popped out, dailyQuantity zeroed, windowPaid cleared.
  - `testVaultAndSdgnrsExemptFromFundingSkipKill`: VAULT + SDGNRS in the IDENTICAL funding-skip state → `PlayerSkipped(.,3)`, retained in the set, NOT expired; a NORMAL **control** sub in the same state IS cancelled — isolating the exemption to the pinned `ContractAddresses.VAULT`/`SDGNRS` identity (net set change −1, exempts retained).
  - `testRenewalLapseStillCancelsExemptSubs`: a renewal LAPSE (day-31 `burnForKeeper` shortfall, deity bit cleared, ample pool so it is NOT a funding skip) still cancels VAULT — the pinned-identity exemption guards ONLY the funding-skip branch.
  - `testNoSettableExemptionFlagSymbol`: `vm.readFile` grep-clean — zero `isExempt`/`exemptFlag`/`skipKillExempt`/`_exempt` symbols; the only exemption surface is the pinned-address equality branch (`ContractAddresses.VAULT`/`SDGNRS` present).

## Assertions Proving the Must-Haves

| Must-have | Proving assertion(s) | Suite |
|-----------|----------------------|-------|
| Same-block self-partition (exactly-once, no double-buy, no miss) | `sum(buys)==N`, `max-per<=1`, monotonic `sweepProgress` cursor | Concurrency (1000-run fuzz + direct) |
| lastSweptDay idempotency backstop | re-visit forced (cursor→0), no second `Swept`, `lastSweptDay` unchanged | Concurrency |
| Per-day cursor reset | `sweepProgress` day-stamp tracks the new day, one fresh buy per sub | Concurrency |
| Tombstone no-miss / no dead-slot buildup | swap-pop occupant bought; `subscriberCount` shrinks by exactly cancels; index back-pointers consistent | Concurrency |
| windowPaid-gated reclaim | paid+unexpired preserved; unpaid deleted | Concurrency |
| Waterfall DirectEth/Claimable/Combined/sentinel | `Swept` cost == cost / 0 / cost−(cred−1) / cost | Waterfall |
| InsufficientPool skip | under-funded sub not in `Swept`; co-resident healthy sub bought | Waterfall |
| NORMAL funding-skip cancel | `SubscriptionExpired(.,1)`, index→0, qty 0, windowPaid cleared | Waterfall |
| Vault/sDGNRS exempt by pinned identity | `PlayerSkipped(.,3)`, retained, NOT expired; NORMAL control cancelled | Waterfall |
| Renewal lapse cancels even exempts | VAULT `SubscriptionExpired(.,1)` on a burn shortfall | Waterfall |
| No settable exemption flag | grep-clean of 4 symbols; pinned-address branch present | Waterfall |

## Suite Pass Counts

- `AfKingConcurrency` — **10 passed, 0 failed** (40 assertions; one 1000-run fuzz).
- `AfKingFundingWaterfall` — **9 passed, 0 failed** (33 assertions; `vm.readFile` grep-clean).
- Combined this plan: **19 passed, 0 failed** (`--match-contract "AfKingConcurrency|AfKingFundingWaterfall"`).
- All AfKing suites (incl. 318-03 `AfKingSubscription`): **26 passed, 0 failed**.
- Zero NEW failures outside the owned suites: the new suites pass in isolation; the repo's ~44 pre-existing failures (zero AfKing involvement, unrelated baseline) were not touched or chased.
- `git diff --name-only -- contracts/` is **empty** after each gate (the patched `ContractAddresses.sol` restored via `git checkout -- contracts/ContractAddresses.sol` per plan, not the stale restore script).

## Deviations from Plan

None of the Rule-1/2/3 auto-fix kind on production contracts (test-only plan; contracts/ untouched). Two in-scope test-harness corrections during authoring (both bugs in the FIRST draft of the test files, not contract findings):

**1. [Test-harness bug] Single-drain log capture.** First-draft `_countSweptFor` called `vm.getRecordedLogs()` per player; the cheatcode CONSUMES the buffer, so only the first count saw events (the rest read 0), producing 3 spurious failures. Fixed by draining the recorded logs ONCE into a member array immediately after the sweep(s), then counting per-player from the snapshot. (Found during Task 1; commit `81a42dc7`.)

**2. [Test-harness bug] Renewal-lapse needs the deity bit cleared.** First-draft `testRenewalLapseStillCancelsExemptSubs` starved VAULT of BURNIE but VAULT carries the permanent deity pass seeded in the game constructor (`DegenerusGame :214`), so `hasAnyLazyPass(VAULT)` free-extends — there was no lapse and VAULT was bought, not cancelled. Fixed by clearing the deity bit (`mintPacked_` slot 9, shift 184) so the renewal hits the PAID all-or-nothing `burnForKeeper` path. (Found during Task 3; commit `615317df`.)

## Known Stubs

None. Both suites drive real subscription/sweep flows against the live contract; no hardcoded empty values flow to assertions, no placeholder/TODO logic, no unwired data source. Every assertion reads either live AfKing storage (via slot reads matching the pinned layout) or decoded AfKing events.

## Threat Flags

None beyond the plan's `<threat_model>` register. The new test surface is exactly the modeled surface: T-318-04-01 (double-buy under concurrent sweeps) mitigated by the exactly-once same-block fuzz + lastSweptDay backstop; T-318-04-02 (NORMAL sub spoofing the Vault/sDGNRS exemption) mitigated by the NORMAL-control-in-identical-state test + the grep-clean of any settable flag; T-318-04-03 (funding-margin grief) bounded by the waterfall skip-vs-cancel boundary + exempt persistence; T-318-04-04 (dead-slot buildup) mitigated by the swap-pop no-buildup test. Deeper griefing review remains routed to 320 AUDIT per the register.

## Commit Status

Both suites committed (test-only, autonomous):
- `81a42dc7` — Tasks 1+2 (`AfKingConcurrency.t.sol`)
- `615317df` — Task 3 (`AfKingFundingWaterfall.t.sol`)

`contracts/` is clean (no production mutation). The patched `ContractAddresses.sol` is restored after every forge run via `git checkout`.

## Self-Check: PASSED

- `test/fuzz/AfKingConcurrency.t.sol` exists — FOUND.
- `test/fuzz/AfKingFundingWaterfall.t.sol` exists — FOUND.
- Commit `81a42dc7` exists — FOUND.
- Commit `615317df` exists — FOUND.
- Both verify gates emit their markers (`SAFE03_CONCURRENCY_PASS`, `WATERFALL_SKIPKILL_PASS`); 19/19 owned tests pass; `git diff --name-only -- contracts/` empty.
