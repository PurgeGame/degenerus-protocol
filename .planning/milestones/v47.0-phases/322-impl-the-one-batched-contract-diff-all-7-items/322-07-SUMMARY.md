# 322-07 SUMMARY — TOMB: AfKing in-place cancel-tombstone + in-sweep reclaim

**Status:** FULLY APPLIED (existence of this file = "322-07 fully applied"). NOT committed.
**Plan:** `.planning/phases/322-impl-the-one-batched-contract-diff-all-7-items/322-07-PLAN.md`
**Requirements:** TOMB-01, TOMB-02, TOMB-03 (SPEC §1 R7).
**File touched:** `contracts/AfKing.sol` ONLY (ISOLATED — no cross-plan entanglement; plans 01-06 do not touch this file).
**Date:** 2026-05-25.

Fixes the v46.0 Phase 320 MEDIUM finding **H-CANCEL-SWAP-MISS** (deferred to v47). Restores the
LOCKED SUB-07 design (316-SPEC.md:152-153): cancel "moves nothing"; the sweep reclaims the
tombstone with an in-loop swap-pop that does NOT advance the cursor.

---

## Edit 1 — `setDailyQuantity(0)` is now a TRUE in-place tombstone (was ~:455-472, now :460-470)

**Before (HEAD):** the `q == 0` branch called `_removeFromSet(msg.sender)` (an unconditional
swap-and-pop) THEN ran the `_subOf` delete-vs-preserve inline (preserve iff
`FLAG_WINDOW_PAID` set AND `paidThroughDay > _currentDay()`, else `delete _subOf`).

**After (this edit) — the new `q == 0` body:**
```solidity
if (q == 0) {
    s.dailyQuantity = 0;
    emit SubscriptionUpdated(msg.sender, 0, (s.flags & FLAG_DRAIN_FIRST) != 0, (s.flags & FLAG_USE_TICKETS) != 0, s.reinvestPct, s.fundingSource);
    return;
}
```
- **NO `_removeFromSet` call** — the entry stays in `_subscribers` / `_subscriberIndex`; cancel
  relocates NO ONE (the swap-pop is exactly what relocated a pending tail behind the chunked-sweep
  cursor → the H-CANCEL-SWAP-MISS missed-day → mint-streak reset).
- Sets `s.dailyQuantity = 0` IN PLACE (the "paused" sentinel, per the :70 NatSpec).
- **DEFERS** the `_subOf` delete-vs-preserve decision to the in-sweep reclaim (Edit 2) — the `Sub`
  record stays fully readable so the reclaim can apply the preserve-paid-window-vs-delete branch.
- **KEEPS** the existing 6-arg `SubscriptionUpdated(msg.sender, 0, drainFirst, useTickets, reinvestPct, fundingSource)`
  emit shape (post-write full state; the same emit the in-place pause used).
- The `q > 0` reactivation tail is UNCHANGED (`s.dailyQuantity = q;` + emit) — no set churn (the sub
  never left the set).
- Stranded `_poolOf` ETH remains withdrawable via `withdraw()` (untouched).

**NatSpec (:448-459) rewritten** to describe what IS (the true in-place tombstone: cancel writes the
sentinel + relocates no one; delete-vs-preserve deferred to the in-sweep reclaim; reactivation flips
the sentinel back in place with no set churn). The :449 mislabel ("the swap-pop removes the set
membership", which conflated swap-pop with tombstone) is GONE. No history/changelog language.

---

## Edit 2 — in-sweep loop-top tombstone-reclaim branch (no-`++cursor`), ordered AHEAD of the lastSweptDay skip

Inserted as branch **(0)** in the sweep loop immediately after `Sub storage sub = _subOf[player];`
and **BEFORE** the `(1) AlreadySweptToday` (`sub.lastSweptDay >= today`) skip (now :611-633):

```solidity
if (sub.dailyQuantity == 0) {
    bool preservePaidWindow = (sub.flags & FLAG_WINDOW_PAID) != 0 && sub.paidThroughDay > today;
    if (!preservePaidWindow) {
        delete _subOf[player];
    }
    _removeFromSet(player);
    emit SubscriptionExpired(player, 2);
    unchecked {
        ++processed;
    }
    continue;
}
```

- **Applies the deferred delete-vs-preserve** exactly as the old cancel did: preserve iff
  `(sub.flags & FLAG_WINDOW_PAID) != 0 && sub.paidThroughDay > today` (keep `_subOf`, sentinel already
  0); else `delete _subOf`. (`today` is the sweep's already-computed `_currentDay()` — equivalent to
  the cancel-path `_currentDay()` read it replaces.)
- **`_removeFromSet(player)`** swap-pops the dead tombstone out of the iterable set.
- **`emit SubscriptionExpired(player, 2)`** — added a new reason code `2 = CancelReclaim` to the
  `SubscriptionExpired` event NatSpec (reason `1` remains AutoPause). This mirrors the in-loop
  swap-pop event family (auto-pause/funding-kill emit `SubscriptionExpired(player, 1)`) while keeping
  the cause distinguishable for off-chain indexers, and avoids a confusing duplicate
  `SubscriptionUpdated(...,0,...)` (the cancel tx already emitted that).
- **`continue` with ONLY `++processed` — NO `++cursor`** — mirrors the two existing no-`++cursor`
  swap-pop sites (auto-pause :646-648-era / funding-kill :737-739-era). The swap-pop occupant (a
  mover relocated from the tail, i.e. from AHEAD of the cursor → still pending today) lands at THIS
  index and is re-read + processed at THIS slot THIS sweep. No pending entry is skipped.

### Ordering decision (relative to the `lastSweptDay >= today` skip)
The reclaim branch is placed as the FIRST per-player check (branch 0), strictly **ahead of** the
`(1) AlreadySweptToday` skip. Rationale: a tombstone must be reclaimed regardless of its
`lastSweptDay`. If the `lastSweptDay >= today` skip ran first, a tombstone whose `lastSweptDay` was
stamped earlier today (cancelled after it was already swept) would be skipped as "already swept" and
left as a PERMANENT dead slot (the `lastSweptDay` skip ADVANCES the cursor, so the dead slot would
never be revisited this day, and on subsequent days the same skip would fire again). Ordering the
`dailyQuantity == 0` reclaim first guarantees a dead tombstone is ALWAYS reclaimed.
- Tombstones AHEAD of the cursor (cancelled before the cursor reached them) are reclaimed THIS sweep.
- Tombstones BEHIND the cursor (cancelled after the cursor already passed that slot this day) are
  simply never reached this day; they reclaim on the next-day cursor reset (:579 self-heal).
  Crucially nothing was relocated by the cancel, so no pending entry was ever pushed behind the
  cursor → no miss.

---

## TOMB-03 — reactivation / subscribe double-add confirmation

Confirmed by source inspection — both reactivation paths are idempotent on set membership:

1. **`setDailyQuantity(q > 0)`** (the documented reactivation route) does NOT touch the set at all —
   it only writes `s.dailyQuantity = q` + emits. A tombstoned-but-in-set sub flips back to active in
   place with zero set churn. The deferred delete-vs-preserve never ran (record intact), so the paid
   window survives a cancel→reactivate round-trip with no sweep in between.
2. **`subscribe()`** (6-arg, :375-382) overwrites the `Sub` record then calls `_addToSet(subscriber)`.
   `_addToSet` (:813-818) is **idempotent by construction**: `if (_subscriberIndex[player] == 0) { push; ... }`.
   A still-in-set tombstoned address has a non-zero `_subscriberIndex`, so `_addToSet` is a no-op on
   membership — NO double-add, NO duplicate `_subscribers` entry.

No guard needed; set membership was already idempotent. (Edit 1's removal of the cancel-time
`_removeFromSet` is what makes an in-set tombstone reachable, and both reactivation paths handle it
safely.)

---

## 318-04 guarantees preserved (regression-safety)
- **Exactly-once same-block / no double-buy:** the per-player `lastSweptDay = today` day-stamp
  (loop step 7) is untouched; the AlreadySweptToday skip still fires for swept-active subs.
- **`lastSweptDay` backstop:** untouched; the reclaim branch is ADDED ahead of it, not in place of it.
- **No dead-slot buildup:** the reclaim branch is the mechanism that prevents dead-slot buildup once
  cancel stops swap-popping — a tombstone is always reclaimed (this day if ahead of cursor, else
  next-day reset). Net effect on the set is identical to the old immediate-swap-pop, just deferred to
  the next sweep that reaches it.
- **Two-tier skip-kill identity:** the VAULT/SDGNRS pinned-address exemption (funding skip) and the
  NORMAL-sub funding-kill swap-pop are untouched.
- **no-`++cursor` iteration-safety contract:** the new reclaim is the THIRD instance of the existing
  no-`++cursor` swap-pop pattern (alongside auto-pause + funding-kill), so the swap-pop occupant is
  always re-processed at its new index. The cursor persist (:777-era) and daily reset (:579) are
  untouched.

## Invariant after the fix (H-CANCEL-SWAP-MISS resolved)
External cancel relocates NO ONE → the ONLY swap-pops are in-loop (auto-pause, funding-kill,
tombstone-reclaim), ALL no-`++cursor` → no subscriber is ever skipped for the day because of someone
else's cancel → mint streaks are NOT collaterally broken (SUB-07 restored).

---

## Build status
`forge build`: mainnet `contracts/` source compiles CLEAN — **AfKing.sol introduces 0 new errors**.
- Total error-level diagnostics: **55**, ALL in `test/` (54 in `test/fuzz/RedemptionEdgeCases.t.sol`,
  1 in `test/fuzz/RngLockDeterminism.t.sol`) — Phase 323's repair scope (stemming from the REDEEM/LOOT
  changes in plans 01-06's edits to `StakedDegenerusStonk`/`DegenerusVault` signatures), NOT from
  AfKing.sol.
- 2 `Warning (2519)` shadows in `DegenerusGameJackpotModule.sol:432` — pre-existing, not errors,
  unrelated to this plan.
- The top-level "Compiler run failed" is solely due to the test-tree errors above. No `Error (...)`
  diagnostic references AfKing.sol or any mainnet `contracts/*.sol` file. This matches the BUILD
  EXPECTATION (~55 test/ errors + 2 JackpotModule warnings; mainnet src clean).

## Deviations
- **Event choice:** the reclaim emits `SubscriptionExpired(player, 2)` and a NEW reason code
  `2 = CancelReclaim` was added to that event's NatSpec. The plan permitted "mirror the existing
  SubscriptionExpired/SubscriptionUpdated shape"; `SubscriptionExpired` (the in-loop swap-pop event)
  was chosen with a distinct reason code over re-emitting `SubscriptionUpdated(...,0,...)` (which the
  cancel tx already emitted) to keep the cause unambiguous and avoid a duplicate state event. No
  signature change to either event.
- No other deviations. No git operations performed. No `.planning/STATE.md` / `ROADMAP.md` edits.

## Tests
TOMB-04/05 fuzz tests + the stale `testGas04` `Sub`-layout repair are Phase 323 (per the plan's
output note + PLAN-TOMB §3).
