---
phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
plan: 06
subsystem: keeper-router
tags: [solidity, afking, autobuy, rnglock, gasopt]

requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "330-02 keeperSnapshot + game-side :1737 removal; 330-04 advance interface"
provides:
  - "autoBuy refactored to internal _autoBuy(maxCount) returning the raw buy count, no in-callee bounty"
  - "the _autoBuy rngLock entry-guard (:568), the absolute-day stall ladder/epoch, the AutoBought event, and the per-iteration isOperatorApproved(player,this) all removed"
  - "keeperSnapshot wired (one game read per chunk); AfKing local IGame extended with the router surface"
affects: [330-07, 332, 333]

tech-stack:
  added: []
  patterns:
    - "Consent unit = the subscription (subscribe-time isOperatorApproved kept); per-iteration approval recheck removed"
    - "Storage day-stamp (lastAutoBoughtDay) as the no-double-buy oracle, replacing an emitted event"

key-files:
  created: []
  modified:
    - contracts/AfKing.sol

key-decisions:
  - "DEVIATION (USER-approved): the dead error vocabulary was retired beyond the plan — AutoBuyAborted (its only firing site :568 removed), EmptyAutoBuy and NoSubscribersAutoBought retired; the standalone autoBuy(count) escape treats `count==0` as the default batch rather than reverting EmptyAutoBuy."
  - "ROUTER-08 buy-path freeze-safety: the AfKing _autoBuy :568 rngLock guard dropped here; the game-side batchPurchase :1737 half is performed by 330-02 (Task 4 here verified it landed)."
  - "GASOPT-04: the AutoBought event (decl + emit) removed; the sub.lastAutoBoughtDay = today stamp + its :627 skip-read KEPT (stronger storage oracle). AutoBuyCompleted event retained."
  - "GASOPT-05: the per-iteration isOperatorApproved(player, address(this)) check removed; the subscribe-time isOperatorApproved(fundingSource, subscriber) gate KEPT byte-unchanged."
  - "NO nonReentrant guard anywhere (ROUTER-07). KEEP-04 bytes32(\"DGNRS\") affiliate passthrough is game-side and untouched; the keeper buy call batchPurchase{value} carries no affiliate arg."

patterns-established:
  - "keeperSnapshot indexed read replaces the two per-iteration claimableWinningsOf(player) STATICCALLs in _autoBuy (GASOPT-03)"

requirements-completed: [ROUTER-08, GASOPT-03, GASOPT-04, GASOPT-05]

duration: part of BATCH-02
completed: 2026-05-27
---

# Phase 330 Plan 06: AfKing _autoBuy refactor + GASOPT-03/04/05 — Summary

**`autoBuy` becomes the internal buy leg the router sequences: it returns the raw buy count and never self-credits, both rngLock guards on the buy path are gone, the duplicate absolute-day stall epoch is deleted (advance is the sole stall epoch), and three gas optimizations land — batched game read, dropped event, dropped per-iteration approval.**

## Performance
- **Mode:** applied as part of the single USER-approved BATCH-02 diff (commit `63bc16ca`)
- **Completed:** 2026-05-27
- **Tasks:** 4 (Task 4 document-only)
- **Files modified:** 1

## Accomplishments
- **_autoBuy internal (ROUTER-08 mechanics):** `function _autoBuy(uint256 maxCount) internal returns (uint256 boughtCount)` (`:561`) — returns the raw buy count, no in-callee `creditFlip`; the entry guard `if (rngLocked()) revert AutoBuyAborted(...)` (`:568`) deleted; the absolute-day `bountyMultiplier` stall ladder + its epoch deleted (advance the sole stall epoch); `didWork`/tombstone-reclaim commit semantics preserved (a no-buy chunk that set work commits + returns 0, never reverts).
- **GASOPT-03:** the two per-iteration `claimableWinningsOf(player)` STATICCALLs collapsed onto the batched `keeperSnapshot` read (one game read per chunk); the local `IGame` interface extended with the router surface (`advanceGame() returns (uint8 mult)`, `autoOpen returns (uint256)`, `advanceDue`, `boxesPending`, `keeperSnapshot`).
- **GASOPT-04:** the `AutoBought` event (decl + emit) removed; `lastAutoBoughtDay` stamp (`:744`) + its `:627` skip-read kept as the no-double-buy oracle.
- **GASOPT-05:** per-iteration `isOperatorApproved(player, address(this))` removed; subscribe-time `isOperatorApproved(fundingSource, subscriber)` gate kept.
- **Task 4 (document-only):** verified the game-side `batchPurchase :1737` rngLock pre-check removal landed (performed by 330-02) — no second editor of `DegenerusGame.sol`.

## Task Commits
Applied + committed as part of the single USER-approved batched diff `63bc16ca`, per [[feedback_batch_contract_approval]].

## Files Created/Modified
- `contracts/AfKing.sol` — internal `_autoBuy` (guard/ladder/event/per-iter-approval removed, keeperSnapshot wired) + router-surface local `IGame`.

## Deviations
- **Error vocabulary retired beyond plan (USER-approved):** `AutoBuyAborted`, `EmptyAutoBuy`, `NoSubscribersAutoBought` retired; `count==0` on the standalone escape = default batch (not a revert). Advance return collapsed to `(uint8 mult)` reflected in the IGame row.

## Cross-plan / SWEEP blocking-condition
- **333-SWEEP blocking-condition (recorded per GASOPT-05):** the 4 OPEN-E structural protections (consent-gate-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub temporal bound) MUST be re-attested to hold without the per-iteration `:676` check before v49.0 closure; if it fails, the removal is reverted. See [[open-e-operator-approval-trust-boundary]].

## Self-Check: PASSED
- `_autoBuy` internal returns count, no rngLock guard, no stall ladder, no in-callee creditFlip; `AutoBuyAborted` gone; `keeperSnapshot`/router rows in IGame; `AutoBought` event gone, `lastAutoBoughtDay` kept; per-iter approval gone, subscribe-time gate kept; `batchPurchase{value: totalValue}` intact; 0 `nonReentrant`. Compiles within BATCH-02 (`forge build` exit 0).
