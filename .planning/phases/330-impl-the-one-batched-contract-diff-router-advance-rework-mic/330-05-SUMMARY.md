---
phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
plan: 05
subsystem: mint
tags: [solidity, gas, storage-pointer-hoist]

requires: []
provides:
  - "hoisted loop-invariant ticketsOwedPacked[rk] storage pointer in processFutureTicketBatch + processTicketBatch — behavior-identical, gas-only"
affects: [331, 332]

tech-stack:
  added: []
  patterns:
    - "Loop-invariant storage-pointer hoist: alias the outer mapping slot once, index only the inner key per access"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameMintModule.sol

key-decisions:
  - "GASOPT-01 scope is `[rk]` in the two named functions only — the `[ffk]` accesses in the separate far-future helper are deliberately untouched."
  - "rk confirmed loop-invariant (computed once before the player loop, never reassigned) before hoisting."

patterns-established:
  - "owedMap = ticketsOwedPacked[rk]; then owedMap[player] — collapses the outer slot recompute on every per-player access"

requirements-completed: [GASOPT-01]

duration: part of BATCH-02
completed: 2026-05-27
---

# Phase 330 Plan 05: MintModule GASOPT-01 storage-pointer hoist — Summary

**Both per-ticket mint loops now alias `ticketsOwedPacked[rk]` to a single storage pointer instead of recomputing the outer mapping slot on every per-player access — a no-cost gas win on the mint hot path that also helps normal players.**

## Performance
- **Mode:** applied as part of the single USER-approved BATCH-02 diff (commit `63bc16ca`)
- **Completed:** 2026-05-27
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- `processFutureTicketBatch`: `mapping(address => uint40) storage owedMap = ticketsOwedPacked[rk];` hoisted after `rk` is assigned (`:399`); all `[rk][player]` accesses routed through `owedMap[player]`.
- `processTicketBatch`: same hoist (`:673`); all `[rk][player]` accesses routed through `owedMap[player]`.
- 0 `ticketsOwedPacked[rk][player]` accesses remain; the far-future `[ffk]` accesses are untouched.
- Behavior byte-identical (storage alias to the same slot) — same packed values read/written.

## Task Commits
Applied + committed as part of the single USER-approved batched diff `63bc16ca`, per [[feedback_batch_contract_approval]].

## Files Created/Modified
- `contracts/modules/DegenerusGameMintModule.sol` — hoisted `owedMap` pointer in both per-ticket loops.

## Deviations
- None.

## Self-Check: PASSED
- 2× `= ticketsOwedPacked[rk];` hoists; 0 `[rk][player]` direct accesses; `[ffk]` untouched. Compiles within BATCH-02 (`forge build` exit 0). Same-results to be re-proven empirically at TST-03 (Phase 332).
