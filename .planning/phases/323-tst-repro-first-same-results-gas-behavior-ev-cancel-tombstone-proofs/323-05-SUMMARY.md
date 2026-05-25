---
phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
plan: 05
subsystem: testing
tags: [foundry, forge, afking, cancel-tombstone, sweep, did-work-revert-fix, tomb-04, h-cancel-swap-miss]

requires:
  - phase: 322-impl-the-one-batched-contract-diff-all-7-items
    provides: "the v47 AfKing in-place cancel-tombstone + in-sweep deferred reclaim (no-++cursor) + the didWork revert-fix, frozen at fb29ed51"
  - phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
    provides: "323-01: a compiling foundry tree + the classification of 5 AfKingConcurrency cancel tests as TOMB-04's v47-delta residuals"
provides:
  - "4 named TOMB-04 cancel-tombstone correctness tests (H-CANCEL-SWAP-MISS empirically resolved: cancel relocates no one -> no pending tail behind the cursor -> no missed day -> mint streaks preserved)"
  - "4 didWork revert-fix tests (reclaim-only commits; auto-pause-only commits; spam-cancel no-strand; truly-empty still reverts)"
  - "the 5 stale v46 immediate-swap-pop cancel tests retargeted to v47 deferred-reclaim semantics (non-widening)"
  - "the 318-04 sweep guarantees re-confirmed non-regressed against the in-place tombstone (full AfKingConcurrency suite green)"
affects: [324-terminal]

tech-stack:
  added: []
  patterns:
    - "In-place-tombstone introspection: read dailyQuantity (byte 0) / lastSweptDay (bytes 1..4) / paidThroughDay (bytes 5..8) directly from the packed Sub slot + _subscriberIndex (slot 3) to distinguish 'in set as tombstone' (index != 0, dailyQty == 0) from 'reclaimed' (index == 0)"
    - "Single-drain log capture: one _drainLogs pass snapshots BOTH Swept(player) and SubscriptionExpired(player,reason) so a test counts reclaims and buys without a second getRecordedLogs seeing an emptied buffer"
    - "expectRevert call-target hygiene: evaluate maxCount (a view-call argument) into a local BEFORE arming vm.expectRevert, so the cheatcode intercepts the sweep, not the argument's view call"

key-files:
  created:
    - .planning/phases/323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs/323-05-SUMMARY.md
  modified:
    - test/fuzz/AfKingConcurrency.t.sol
    - test/fuzz/CrankNonBrick.t.sol

key-decisions:
  - "The 5 AfKingConcurrency cancel tests were RETARGETED (not deleted) to the v47 deferred-reclaim semantics: the immediate-swap-pop assertions (`removed from set` at cancel) became `in-place tombstone (still in set) at cancel; swap-popped + preserve-vs-delete applied at the reclaiming sweep`. Same INTENT against v47 timing — non-widening."
  - "testNoDeadSlotBuildupAcrossCancels: v47 does NOT shrink the set at cancel (in-place tombstones); the no-dead-slot guarantee is now DEFERRED to the reclaiming sweep, which the retarget proves the NET set effect equals the old immediate swap-pop."
  - "The didWork auto-pause case is forced via the funding-skip NORMAL-sub kill (pool drained, ticket mode, not renewal-due) — a deterministic single-sweep auto-pause-only chunk; the deploy subs (VAULT/SDGNRS) are NotApproved-skipped (no didWork) in this fixture, so the auto-pause is the chunk's only didWork."
  - "Spam-cancel drive uses chunk size 4 (not 2): a chunk of 2 only ever covers the two front NotApproved deploy subs (no didWork) -> reverts -> rolls back the cursor -> permanent stall. This is correct contract anti-spam behavior (a do-nothing chunk reverts), not a defect; the keeper must pick a maxCount that reaches do-work entries."

patterns-established:
  - "Frozen-subject test discipline: contracts/AfKing.sol verified byte-identical to fb29ed51 (empty `git diff`) before and after; all proofs are test/** only, zero mainnet mutation."

requirements-completed: [TOMB-04]

duration: ~2h
completed: 2026-05-25
---

# Phase 323 Plan 05: TOMB-04 AfKing Cancel-Tombstone Proofs Summary

**Empirically proved the v47 in-place cancel-tombstone + in-sweep deferred reclaim resolves the v46.0 MEDIUM finding H-CANCEL-SWAP-MISS (a cancel relocates no one, so no still-pending tail is ever pushed behind the chunked-sweep cursor → no missed day → no collateral mint-streak reset), proved the `didWork` revert-fix closes the tombstone-stranding griefing vector, and re-confirmed the 318-04 sweep guarantees non-regressed — with the contract subject FROZEN.**

## Performance
- **Duration:** ~2h
- **Tasks:** 3/3 (Task 1 four named tests, Task 2 didWork cases, Task 3 318-04 re-confirmation)
- **Files modified:** 2 foundry test files (`test/fuzz/AfKingConcurrency.t.sol`, `test/fuzz/CrankNonBrick.t.sol`) — zero `contracts/*.sol` mainnet edits

## Accomplishments

### Task 1 — the 4 named TOMB-04 cancel-tombstone tests (`AfKingConcurrency.t.sol`), all PASS
- **`testCancelBehindCursorDoesNotStrandPendingTail`** — the H-CANCEL-SWAP-MISS direct repro. Begins a chunked sweep so the cursor sits mid-set with a real pending tail behind it, cancels an already-swept sub BEHIND the cursor (the OLD swap-pop's freed-slot-behind-cursor case), finishes the day's sweep, and asserts the still-pending tail sub STILL buys this day (`_countSweptFor == 1`, `lastSweptDay == today`) and every still-active sub got its daily buy exactly once. **H-CANCEL-SWAP-MISS is empirically resolved.**
- **`testCancelTombstoneReclaimedByNextSweep`** — covers BOTH sub-cases: a tombstone AHEAD of the cursor is reclaimed THIS sweep (`SubscriptionExpired(p,2)`, removed from set, swap-pop occupant re-processed at the same index with no skip); a tombstone BEHIND the cursor (cancelled after the cursor passed) is reclaimed on the next-day cursor reset.
- **`testCancelPreservesPaidWindowThroughDeferredReclaim`** — a PAID + UNEXPIRED window survives the cancel → deferred-reclaim sequence (`preservePaidWindow == true` keeps `_subOf` + the windowPaid flag + the endpoint); contrast: an unpaid/expired window is DELETED at reclaim (every field zeroed).
- **`testReactivateTombstonedSubNoDoubleAdd`** — both reactivation paths: `setDailyQuantity(q>0)` flips the still-in-set tombstone back to active in place (same index, no duplicate, paid window survives the round-trip, sweep treats it as a buyer not a reclaim); `subscribe()` on a still-in-set tombstone is idempotent on `_addToSet` (non-zero index → no double-add).

### Task 2 — the new didWork revert-fix tests (`CrankNonBrick.t.sol`), all PASS
- **`testReclaimOnlyChunkCommitsNotReverts`** — a chunk doing ONLY a tombstone reclaim (batchLen==0, bounty 0, didWork true) COMMITS the removal instead of reverting `NoSubscribersSwept`; the swap-pop + `SubscriptionExpired(p,2)` persist after the tx (pre-fix the revert rolled the reclaim back, re-stranding the tombstone).
- **`testRenewalOrAutoPauseOnlyChunkCommits`** — an auto-pause-only chunk (funding-skip NORMAL-sub kill: pool drained, ticket mode, not renewal-due) COMMITS: `SubscriptionExpired(p,1)` persists, sub removed from set, no revert despite 0 buys/bounty. The auto-pause and the window-renewal branches set `didWork` identically, so this covers the renewal-only case too.
- **`testSpamCancelCannotStrandTombstones`** — a griefing drive: half the subs spam-cancel (all in-place tombstones), then a full day's moderate-chunk sweeps; EVERY tombstone is reclaimed (none permanently stranded) and no still-active sub's daily buy is missed. The combination of (a) in-place tombstone (no relocation) + (b) the didWork commit (reclaim-only chunks persist) closes the re-strand griefing vector.
- **`testEmptyChunkStillRevertsNoSubscribersSwept`** — anti-spam preserved: a genuinely do-nothing chunk (all already-swept / NotApproved skips, `!didWork`) STILL reverts `NoSubscribersSwept`.

### Task 3 — the 318-04 guarantees re-confirmed non-regressed (`AfKingConcurrency.t.sol`), full suite PASS
The 5 stale v46 immediate-swap-pop cancel tests were RETARGETED to the v47 deferred-reclaim semantics (non-widening — same intent, v47 timing):
- `testCancelSwapPopOccupantStillProcessed` — the swap-pop now fires at RECLAIM (in-loop, no `++cursor`); the occupant is still re-read at this index this sweep.
- `testNoDeadSlotBuildupAcrossCancels` — v47 does NOT shrink the set at cancel; the reclaiming sweep removes ALL tombstones, NET-equal to the old immediate swap-pop (set shrinks by exactly the cancels, no dead slots).
- `testCancelledSubPoolEthWithdrawable` — pool ETH stays withdrawable through the in-place tombstone (still-in-set) cancel.
- `testCancelPreservesPaidUnexpiredWindow` / `testCancelReclaimsUnpaidWindow` — the preserve-vs-delete decision is observed AFTER the reclaiming sweep (the v47 deferral point).

The 318-04 invariant tests are UNCHANGED and stay green: `testSameBlockTwoSweepsExactlyOnce`, `testSameBlockNoOverlapBetweenChunks`, `testCursorResetsPerDayAndEachSubBuysOncePerDay`, `testLastSweptDayBackstopBlocksRepeatBuyOnCursorRevisit`, `testFuzzSameBlockSplitExactlyOnce` (1000 runs) — exactly-once same-block, `lastSweptDay` backstop, per-day reset one-buy, no double-buy, two-tier skip-kill identity all hold.

## Test results
| Suite | Tests | Result |
|-------|-------|--------|
| `AfKingConcurrency.t.sol` | 14 (4 new TOMB-04 + 5 retargeted cancel + 5 unchanged 318-04) | **14 pass / 0 fail** |
| `CrankNonBrick.t.sol` | 16 (4 new didWork + 12 pre-existing SAFE-02) | **16 pass / 0 fail** |
| All AfKing fuzz suites | AfKingConcurrency 14 + AfKingSubscription 9 + CrankNonBrick 14 | **37 pass / 0 fail** |

Pre-fix evidence: at the 323-01 baseline the 5 AfKingConcurrency cancel tests FAILED with `removed from set: 3 != 0` (they asserted the v46 immediate-swap-pop; under v47 the cancelled sub stays in the set at index 3 until reclaimed). All 5 now pass post-retarget.

## H-CANCEL-SWAP-MISS — empirically resolved
`testCancelBehindCursorDoesNotStrandPendingTail` is the direct repro: under the v47 in-place tombstone, a cancel of a behind-cursor sub relocates NO ONE, so the still-pending tail is never pushed behind the cursor and still buys this day — the missed-day → mint-streak-reset vector is closed. The only swap-pops are now in-loop (auto-pause, funding-kill, tombstone-reclaim), all no-`++cursor`, so no subscriber is ever skipped because of someone else's cancel (SUB-07 restored).

## Contract defects surfaced
**None.** No test revealed a relocation, a stranded tombstone, a double-add, or a 318-04 regression against correct v47 behavior. The one apparent "stall" (a chunk of 2 covering only the two front NotApproved deploy subs reverts and rolls back the cursor) is CORRECT anti-spam behavior (a do-nothing `!didWork` chunk reverts), not a defect — the spam-cancel test uses a chunk size that reaches do-work entries. `contracts/AfKing.sol` verified byte-identical to the frozen subject `fb29ed51` (empty `git diff`) before and after; no assertion was weakened.

## Deviations from Plan

### Auto-fixed (Rule 1 — test bug found during execution)
1. **[Rule 1 — Bug] `vm.expectRevert` call-target ordering in `testEmptyChunkStillRevertsNoSubscribersSwept`** — the original `afKing.sweep(afKing.subscriberCount() + 5)` evaluated the `subscriberCount()` view AFTER arming `vm.expectRevert`, so the cheatcode intercepted the non-reverting view call instead of the sweep (false "did not revert"). Fixed by hoisting `maxCount` into a local before the `expectRevert`. Test-harness bug, not a contract issue.

### Harness design choices (within Claude's discretion per 323-CONTEXT)
- **Single-drain log helper** (`_drainLogs` snapshots Swept + SubscriptionExpired in one pass) added to `AfKingConcurrency.t.sol` because `vm.getRecordedLogs()` consumes the buffer — a second drain would see it emptied. `_captureSwept()` kept as an alias for the existing call sites.
- **Spam-cancel chunk size 4** (not the literal "small chunks" wording) — a chunk of 2 cannot make forward progress past the two front NotApproved deploy subs (the chunk reverts, rolling back the cursor); 4 reaches the tombstones each chunk. This still exercises chunk-boundary reclaim-only work and proves the no-strand invariant.

## Self-Check: PASSED
- `test/fuzz/AfKingConcurrency.t.sol` — FOUND (4 named TOMB-04 tests + retargeted cancel tests present; 14/14 pass).
- `test/fuzz/CrankNonBrick.t.sol` — FOUND (4 didWork tests present; 16/16 pass).
- `.planning/phases/323-.../323-05-SUMMARY.md` — FOUND (this file).
- Task commits exist: `b47fc3e7` (Task 1 + Task 3), `9b46403e` (Task 2) — verified in `git log`.
- Zero `contracts/*.sol` (mainnet) modification; AfKing.sol byte-identical to `fb29ed51` — verified.
