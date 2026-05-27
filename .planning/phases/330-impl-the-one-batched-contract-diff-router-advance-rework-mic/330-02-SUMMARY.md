---
phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
plan: 02
subsystem: keeper-router
tags: [solidity, router-views, autoopen, rnglock, gas-batched-read]

requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "330-01 — the (uint8 mult) advance return the wrapper decodes"
provides:
  - "advanceGame() wrapper that decodes + forwards the (uint8 mult) delegatecall return (no longer discards data on success)"
  - "advanceDue() + boxesPending() O(1) discovery views (boxesPending rngLock-aware)"
  - "autoOpen reworked: rngLock||liveness entry-gate, try/catch dropped, _autoOpenBox internal, returns raw open count, no in-callee bounty"
  - "batchPurchase :1737 rngLock pre-check removed (gameOver :1738 kept) — the game-side RD-2 freeze-safety half"
  - "keeperSnapshot batched read (GASOPT-03, SUBSUMES GASOPT-02)"
affects: [330-03, 330-06, 330-07, 331, 332]

tech-stack:
  added: []
  patterns:
    - "rngLock-aware O(1) discovery predicate (boxesPending ANDs !rngLockedFlag) so the router never routes to a leg that would revert"
    - "entry-gate replaces per-item try/catch when the loop body is provably non-reverting under the gate"

key-files:
  created: []
  modified:
    - contracts/DegenerusGame.sol

key-decisions:
  - "DEVIATION (USER-approved): the wrapper returns (uint8 mult) and abi.decode(data,(uint8)) — matching the collapsed single-value advance return (rewardable folded into mult==0)."
  - "autoOpen entry-gate is `if (rngLockedFlag || _livenessTriggered()) return 0;` — replicates BOTH open-path revert sources pre-loop, making the cursor-advance-first loop brick-proof without try/catch (RD-5)."
  - "_autoOpenBox made internal (self-guard dropped — dead under internal visibility); AUTO_OPEN_BOX_GAS_UNITS deleted (open-leg gas-peg reward removed)."
  - "batchPurchase :1737 `if (rngLockedFlag) revert RngLocked();` removed; `if (gameOver) revert E();` (:1738) kept; the far-future compound revert at _queueTickets is untouched. (ROUTER-08 attributed to 330-06; physical edit lands here per single-editor-per-file.)"

patterns-established:
  - "keeperSnapshot(address[]) → (mintPriceWei, rngLocked_, claimables[]): one STATICCALL per chunk replacing mintPrice + rngLocked + N×claimableWinningsOf"

requirements-completed: [ADV-02, ROUTER-04, ROUTER-09, ROUTER-10, GASOPT-03]

duration: part of BATCH-02
completed: 2026-05-27
---

# Phase 330 Plan 02: DegenerusGame router surface — Summary

**The game side of the router is settled: the advance wrapper now forwards the stall multiplier, two O(1) rngLock-aware discovery views tell the router what work is pending, `autoOpen` is brick-proof via an entry-gate instead of try/catch, and the keeper reads game state in one batched call.**

## Performance
- **Mode:** applied as part of the single USER-approved BATCH-02 diff (commit `63bc16ca`)
- **Completed:** 2026-05-27
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- **Wrapper tuple decode (ADV-02):** `advanceGame()` (`:278`) now `returns (uint8 mult)` and `abi.decode(data, (uint8))` on the delegatecall success path (was discarding `data`).
- **Discovery views (ROUTER-04):** `advanceDue()` (`:1627`, true regardless of rngLock) and `boxesPending()` (`:1645`, ANDs `!rngLockedFlag` + the word-gate) — both O(1), no unbounded scan.
- **autoOpen rework (ROUTER-09/10):** `autoOpen(uint256 maxCount) returns (uint256 opened)` (`:1666`) with the `rngLockedFlag || _livenessTriggered()` entry-gate, the per-item `try this._autoOpenBox/catch` replaced by a direct internal `_autoOpenBox` (`:1732`), the in-callee `creditFlip` + `AUTO_OPEN_BOX_GAS_UNITS` deleted; returns the raw open count.
- **batchPurchase RD-2 half (ROUTER-08 / Q5):** the bare `if (rngLockedFlag) revert RngLocked();` pre-check removed; `if (gameOver) revert E();` kept; the far-future `_queueTickets` compound revert untouched.
- **keeperSnapshot (GASOPT-03):** `keeperSnapshot(address[])` (`:2595`) returns `(mintPriceWei, rngLocked_, claimables[])` from the same accessors — purely call-count reduction; single-value views retained.

## Task Commits
Applied + committed as part of the single USER-approved batched diff `63bc16ca` (`feat(330): v49.0 keeper-router redesign (BATCH-02, user-approved)`), per [[feedback_batch_contract_approval]]. Per-plan atomic commits superseded by the contract-batch rule for this phase.

## Files Created/Modified
- `contracts/DegenerusGame.sol` — wrapper decode, `advanceDue`/`boxesPending`, reworked `autoOpen` + internal `_autoOpenBox`, `batchPurchase :1737` removal, `keeperSnapshot`.

## Deviations
- Advance return is single-value `(uint8 mult)` (see 330-01) — the wrapper decode matches.

## Cross-plan reconciliation
- The `batchPurchase :1737` removal recorded here is the edit 330-06 Task 4 verifies (ROUTER-08 buy-path freeze-safety = AfKing `:568` + this game-side half, both dropped).

## Self-Check: PASSED
- Wrapper decodes `(uint8 mult)`; `advanceDue`/`boxesPending` present; `autoOpen` entry-gated, no try/catch, `_autoOpenBox` internal, returns count; bare `batchPurchase` rngLock pre-check count 0, far-future compound revert intact, `gameOver` kept; `keeperSnapshot` present. Compiles within BATCH-02 (`forge build` exit 0).
