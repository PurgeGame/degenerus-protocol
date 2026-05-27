---
phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
plan: 04
subsystem: interfaces
tags: [solidity, interface, advance-return]

requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "330-01 module return + 330-02 wrapper decode — the interface must match both"
provides:
  - "IDegenerusGameAdvanceModule.advanceGame() declares the (uint8 mult) return so the wrapper abi.decode type-matches"
affects: [330-09]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - contracts/interfaces/IDegenerusGameModules.sol

key-decisions:
  - "DEVIATION (USER-approved): the interface declares `returns (uint8 mult)` (single value), matching the collapsed advance return — not the planned (uint8 mult, bool rewardable)."
  - "The 4-byte selector is unchanged by the return clause, so delegatecall dispatch is identical; the clause only documents the decode shape."
  - "contracts/interfaces/IDegenerusGame.sol left byte-unchanged — the router surface the keeper uses lives in AfKing's local IGame (330-06), not the global interface."
  - "No degeneretteResolve/autoResolve row added anywhere (ABSENT from all interface files)."

patterns-established: []

requirements-completed: [ADV-02]

duration: part of BATCH-02
completed: 2026-05-27
---

# Phase 330 Plan 04: advance-module interface return — Summary

**The advance-module interface is brought into lock-step with the new `(uint8 mult)` return so the game wrapper's `abi.decode` type-matches — the only global-interface change the redesign requires.**

## Performance
- **Mode:** applied as part of the single USER-approved BATCH-02 diff (commit `63bc16ca`)
- **Completed:** 2026-05-27
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- `interface IDegenerusGameAdvanceModule`: `function advanceGame() external;` → `function advanceGame() external returns (uint8 mult);` (`:12`).
- `contracts/interfaces/IDegenerusGame.sol` confirmed byte-unchanged (router surface is AfKing-local).
- No `degeneretteResolve`/`autoResolve` interface row added (correctly ABSENT).

## Task Commits
Applied + committed as part of the single USER-approved batched diff `63bc16ca`, per [[feedback_batch_contract_approval]].

## Files Created/Modified
- `contracts/interfaces/IDegenerusGameModules.sol` — advance return signature updated to `(uint8 mult)`.

## Deviations
- Single-value `(uint8 mult)` return (see 330-01) instead of the planned tuple.

## Self-Check: PASSED
- `function advanceGame() external returns (uint8 mult);` present; no spurious interface rows; `IDegenerusGame.sol` unchanged. Compiles within BATCH-02 (`forge build` exit 0).
