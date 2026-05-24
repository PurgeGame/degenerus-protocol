# v47.0 — AfKing Cancel-Tombstone Restore (SUB-07) — fixes H-CANCEL-SWAP-MISS

**Status:** QUEUED for v47.0. Added 2026-05-24 from the v46.0 Phase 320 TERMINAL adversarial sweep (`/zero-day-hunter` Tier-1 FINDING_CANDIDATE **H-CANCEL-SWAP-MISS**), USER-adjudicated to DEFER-with-fix-locked (do NOT break v46.0 SOURCE-TREE FROZEN; fix lands in the v47.0 batched diff).
**Type:** SECURITY / CORRECTNESS (subscription liveness; protects the mint-streak the auto-buy exists to maintain).
**Hard prerequisite:** v46.0 must CLOSE first (Phase 320 TERMINAL). NO `contracts/` edits before v46.0 closure. This finding is RECORDED in `audit/FINDINGS-v46.0.md` §4 as deferred-to-v47.0.
**Posture:** pre-launch redeploy-fresh; security floor over gas (`feedback_security_over_gas`). Restores a design the user already LOCKED at v46.0 SPEC — this is revert-to-spec, not new design (`feedback_design_intent_before_deletion` satisfied by the SUB-07 trace below).
**Approval model:** part of the ONE batched USER-APPROVED v47.0 contract diff (`feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push`).

---

## 1. The finding (H-CANCEL-SWAP-MISS)

**Severity:** MEDIUM (arguably HIGH depending on the activity-score multiplier's economic weight). Not LOW — the original LOW tag was revised once the streak impact was understood.

**Mechanism.** External cancel `setDailyQuantity(0)` (`contracts/AfKing.sol:455-468`) immediately calls `_removeFromSet(msg.sender)` (`:459`), which is an unconditional swap-and-pop (`:825-837`): it moves the **tail** subscriber (`_subscribers[last]`) into the canceller's vacated slot. The sweep is chunked — `sweep(maxCount)` persists `_sweepCursor` (slot 4, `:215`) mid-day across calls. When:
1. a chunked sweep has persisted its cursor at some index `c > 0` (positions `[0,c)` already bought today, `[c,len)` pending), AND
2. a subscriber **behind** the cursor (index `< c`, already-processed-today) cancels,

the swap-pop relocates the **pending tail** (index `len-1 ≥ c`) down into the canceller's slot (index `< c`) — i.e. **behind the cursor**. The resuming sweep continues from `c` and never revisits the relocated subscriber, so that innocent, fully-funded subscriber **misses one day's auto-buy**.

**Why it matters (the streak).** The miss is NOT cosmetic. The mint streak (`contracts/modules/DegenerusGameMintStreakUtils.sol`) is **per-consecutive-level**: `_mintStreakEffective` (`:51-63`) **resets to 0 if a level is skipped** (`currentMintLevel > lastCompleted + 1 → return 0`), and it feeds `_playerActivityScore` at **1% per consecutive level, capped at +50%** (`:114-115`). A skipped daily auto-buy = a skipped level mint = **the entire accumulated streak resets to 0 = up to a +50% activity-score multiplier permanently lost** for the victim. The sweep *cursor* self-heals on the next-day reset (`:579`, `cursor = _sweepDay == today ? _sweepCursor : 0`); the *streak* does not. Reliable streak maintenance is the entire value proposition of the auto-buy subscription.

**Reachability.** Triggers on **any** mid-day cancel behind a persisted chunked-sweep cursor — including a fully legitimate cancel, no attacker required. As a deliberate grief it is weak (the attacker cannot target a chosen victim — the swap moves whoever is the tail — and forfeits its own sub), but the normal-operation correctness break is the real exposure.

**The locked-spec divergence.** SUB-07 was LOCKED at v46.0 SPEC to prevent exactly this:
- `316-SPEC.md:152` — *"Tombstone-on-cancel — external cancel (`setDailyQuantity(0)`) only sets `dailyQuantity = 0` and **moves nothing**, so it can never relocate an unprocessed entry behind the cursor (the one miss case a swap-pop-on-cancel would cause)."*
- `316-SPEC.md:153` — *"In-sweep swap-pop reclaim — on auto-pause OR on reaching a tombstone, the sweep removes the entry, moves the tail into the slot, and processes it there WITHOUT `++i`."*
- `REQUIREMENTS.md:52` (SUB-07) — *"tombstone-on-cancel (no move), in-sweep swap-pop reclaim."*

The IMPL regressed to an immediate swap-pop on cancel (the rejected approach) AND omitted the in-sweep tombstone-reclaim branch (because it assumed in-set tombstones never exist). The NatSpec at `AfKing.sol:449` even mislabels the swap-pop as "SUB-07 tombstone-on-cancel," conflating the two distinct mechanisms.

**Was known-deferred to this audit.** `318-04-SUMMARY.md:108` — *"Deeper griefing review remains routed to 320 AUDIT per the register."* The sweep found it; v46.0 records it; v47.0 fixes it.

---

## 2. The fix — USER-LOCKED 2026-05-24: "don't move anyone, let the next sweep handle it"

Restore the locked SUB-07 in-place tombstone. Two coordinated edits in `contracts/AfKing.sol`, both revert-to-spec:

### Edit 1 — `setDailyQuantity(0)` becomes a true in-place tombstone (`:455-468`)
- Do **NOT** call `_removeFromSet`. Leave the entry in `_subscribers` (no relocation of anyone).
- Set `s.dailyQuantity = 0` in place (the tombstone sentinel; `dailyQuantity == 0` already means "paused", `:70`).
- **Defer** the `_subOf` delete-vs-preserve decision (currently at `:460-467`) to the in-sweep reclaim — the `Sub` record must stay readable so the reclaim can apply the preserve-paid-window-vs-delete branch. The cancel tx just sets the sentinel + emits `SubscriptionUpdated(…, 0, …)` (preserve the existing event shape; `:156` notes manual pause emits `dailyQuantity == 0`).
- Stranded `_poolOf` ETH stays withdrawable (unchanged).
- **Re-activation stays cheap:** a tombstoned-but-in-set sub reactivates via `setDailyQuantity(q>0)` (`:470`) with no set churn (it never left the set). Confirm `subscribe()` (`:375`) does not double-add an already-in-set tombstoned address (it is still in `_subscriberIndex`), or route re-activation through `setDailyQuantity` — preserve idempotent set membership.

### Edit 2 — add the in-sweep tombstone-reclaim branch to the sweep loop (`~:609-745`)
The loop currently swap-pops only on auto-pause (`:642-644`) and funding-kill (`:737-739`), both in-iteration. It has **no loop-top `dailyQuantity == 0` reclaim** — add it:
- At loop-top, on reaching an entry with `sub.dailyQuantity == 0` (an externally-cancelled tombstone): apply the deferred `_subOf` delete-vs-preserve decision (paid-unexpired-window → keep `_subOf`, set sentinel preserved; else `delete _subOf`), then `_removeFromSet(player)`, emit the appropriate event, and **do NOT advance the cursor** (`continue` without `++cursor`) — the swap-pop occupant (mover, came from ahead → pending) is processed at this same index this sweep. Mirror the existing no-`++i` pattern at `:644`.
- Ordering vs the `lastSweptDay >= today` skip (`:613-621`): a tombstone must be reclaimed regardless of `lastSweptDay` — place/branch the tombstone check so a dead tombstone is reclaimed, not left as a permanent dead slot.
- Behind-cursor tombstones (cancelled after the cursor passed them this day) are simply never reached this day; they reclaim on the next-day cursor reset. Crucially **nothing was relocated**, so no pending entry is ever pushed behind the cursor → **no miss** (the SUB-07 guarantee restored).

### Invariant after the fix
External cancel never relocates an entry → the only swap-pops are in-loop (auto-pause, funding-kill, tombstone-reclaim), all with the no-cursor-advance guarantee → no subscriber is ever skipped for the day because of someone else's cancel → **streaks are not collaterally broken.**

---

## 3. Test plan (`test/fuzz/AfKingConcurrency.t.sol` — the 318-04 gap)
The existing `testCancelSwapPopOccupantStillProcessed` only covers cancel-at-cursor=0. Add:
- **`testCancelBehindCursorDoesNotStrandPendingTail`** — N healthy subs; `sweep(k)` to persist the cursor at `c>0`; a sub at index `< c` cancels; resume the sweep; assert the former-tail (and every pending sub) is still bought this day (no miss), and the cancelled sub's tombstone is reclaimed (removed) with no cursor-advance side effect.
- **`testCancelTombstoneReclaimedByNextSweep`** — cancel behind the cursor; assert the tombstone sits as a no-op until the sweep reaches it (this day if ahead of cursor, else next-day reset), then is swap-popped + reclaimed; `subscriberCount` shrinks by exactly the cancels; no dead-slot buildup.
- **`testCancelPreservesPaidWindowThroughDeferredReclaim`** — cancel a paid-unexpired-window sub; assert `_subOf` is preserved (not deleted) through the deferred in-sweep reclaim, matching the current preserve-paid-window semantics.
- **`testReactivateTombstonedSubNoDoubleAdd`** — cancel (tombstone) then `setDailyQuantity(q>0)`; assert single set membership, normal resumption, no double-add.
- Re-confirm the existing 318-04 guarantees still hold (exactly-once same-block, `lastSweptDay` backstop, no double-buy, no dead-slot buildup, two-tier skip-kill identity).

**Also fix the stale gas test (surfaced by the v46.0 Phase 320 regression pass):** `test/gas/CrankLeversAndPacking.t.sol::testGas04PackingAndNoNewHotPathStorageSourcePresence` asserts the **pre-OPEN-E `Sub` layout** (it looks for standalone `bool drainGameCreditFirst;` / `bool useTickets;` fields and a 7-field/13-byte sum) and panics 0x11 at HEAD because OPENE-01 (319.1) collapsed those bools into `flags` and added `address fundingSource` (HEAD `Sub` = `{uint8 dailyQuantity; uint32 lastSweptDay; uint32 paidThroughDay; uint8 reinvestPct; uint8 flags; address fundingSource;}`, 6 fields, 31 used bytes, one slot). This is a test-only staleness (contract is correct — 320-01 SWP-OPENE NEGATIVE-VERIFIED). Update `testGas04` to the post-OPENE-01 `Sub` shape (drop the two standalone-bool field checks, add the `address fundingSource` field, fix the byte-sum assertion 13→31 and the field-list). It is the 45th of the 565/45 v46.0 HEAD suite count (the documented baseline is 44) — fixing it restores a clean 44-fail baseline for the v47.0 regression gate.

---

## 4. Scope / coordination
- **Files:** `contracts/AfKing.sol` (Edit 1 + Edit 2) + `test/fuzz/AfKingConcurrency.t.sol`.
- **Isolation:** `AfKing.sol` is NOT in the v47.0 §2 shared-surface coordination map (LootboxModule / DegenerusGame / MintModule / Degenerette / claimable accounting). This fix is an **independent surface** — it adds `AfKing.sol` to the batched diff without entangling the other six items. No cross-plan signature reconciliation needed.
- **Belongs in v47.0** because v46.0 is SOURCE-TREE FROZEN at closure; this is the next contract milestone and the natural home for the queued fix.

---

*Source-of-truth for the v47.0 AfKing cancel-tombstone fix. Cross-ref: `audit/FINDINGS-v46.0.md` §4 (H-CANCEL-SWAP-MISS deferred-to-v47.0), `.planning/PLAN-V47-MILESTONE-SCOPE.md` §1 item 7. All `AfKing.sol` line anchors re-grep-verified against the v46.0 closure HEAD; re-grep again at v47.0 plan-time (the v47 batched diff will shift lines).*
