---
phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
plan: 03
subsystem: degenerette-resolve
tags: [solidity, rename, flat-bounty, gas-331-placeholder]

requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "330-02 — the prior DegenerusGame.sol router-surface edits (same file, sequential)"
provides:
  - "autoResolve renamed to degeneretteResolve (+ _degeneretteResolveBet + the self-call site)"
  - "the per-item gas-pegged reward replaced by a flat ≥3-non-WWXRP-resolution RESOLVE_FLAT_BURNIE creditFlip"
  - "NoWork() at zero resolutions; 1-2 resolutions commit unpaid (never strands the tail)"
  - "RESOLVE_FLAT_BURNIE GAS-331 placeholder; dead AUTO_* gas-unit constants removed"
affects: [330-08, 331, 332]

tech-stack:
  added: []
  patterns:
    - "Flat ≥N-success bounty gate with an unpaid-but-committed middle band — lean = do-not-revert, never strand the trailing tail"

key-files:
  created: []
  modified:
    - contracts/DegenerusGame.sol

key-decisions:
  - "degeneretteResolve stays a SEPARATE permissionless caller-supplied-arrays call (NOT a router leg — ROUTER-05); the router-fold is architecturally blocked."
  - "_degeneretteResolveBet stays external onlySelf (the per-item try/catch isolation needs the external `this.` call) — unlike _autoOpenBox, it is NOT internalized."
  - "successCount increments on NON-WWXRP resolutions only; totalResolved increments on ANY resolution so a WWXRP-only batch does not falsely NoWork()."
  - "RESOLVE_FLAT_BURNIE = 1e18 is a GAS-331 PLACEHOLDER — calibrated under the USER-gated GAS phase (331), NOT locked here."

patterns-established:
  - "Bounty-shape change with byte-identical resolution RESULTS (rename + pay-gate only; no payout/RNG change)"

requirements-completed: [ROUTER-05]

duration: part of BATCH-02
completed: 2026-05-27
---

# Phase 330 Plan 03: degeneretteResolve rename + flat ≥3 re-peg — Summary

**The Degenerette resolve helper is renamed off the keeper namespace and re-pegged from a per-item gas bounty to a single flat ~1-BURNIE "lose" paid only at ≥3 non-WWXRP resolutions — all structural protections intact.**

## Performance
- **Mode:** applied as part of the single USER-approved BATCH-02 diff (commit `63bc16ca`)
- **Completed:** 2026-05-27
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- **Rename (D-05a):** `autoResolve` → `degeneretteResolve` (`:1585`), `_autoResolveBet` → `_degeneretteResolveBet`, and the `this._degeneretteResolveBet(...)` self-call site — atomic, 0 residual `autoResolve`/`_autoResolveBet` in the contract. No interface row (ABSENT from `contracts/interfaces/`).
- **Flat ≥3 re-peg (D-05b):** per-item `_ethToBurnieValue(...)` accumulation replaced by `++successCount` (non-WWXRP) + `++totalResolved` (any); post-loop `if (totalResolved == 0) revert NoWork(); if (successCount >= 3) coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE);` (`:1620`).
- **Placeholder + error:** `RESOLVE_FLAT_BURNIE = 1e18` GAS-331 placeholder (`:1543`); `error NoWork();` (`:98`).
- **Dead-constant cleanup:** the per-item `AUTO_RESOLVE_BET_GAS_UNITS` (and the now-orphaned `AUTO_GAS_PRICE_REF` once the open-leg consumer from 330-02 was gone) removed.
- **Preserved:** the AUTO-02 probe, per-item try/catch isolation, the `(betPacked >> 42) & 0x3` currency decode + WWXRP `currency == 3` exclusion, self-resolve, one-creditFlip-CEI-last.

## Task Commits
Applied + committed as part of the single USER-approved batched diff `63bc16ca`, per [[feedback_batch_contract_approval]].

## Files Created/Modified
- `contracts/DegenerusGame.sol` — `degeneretteResolve`/`_degeneretteResolveBet`, flat ≥3 re-peg, `RESOLVE_FLAT_BURNIE`, `NoWork()`.

## Deviations
- None of substance. The flat-`1e18` value is an explicit GAS-331 placeholder (calibrated at Phase 331).

## Self-Check: PASSED
- `degeneretteResolve` present; 0 `autoResolve`/`_autoResolveBet`; `successCount >= 3` flat creditFlip + `totalResolved == 0` NoWork; `RESOLVE_FLAT_BURNIE` GAS-331-marked; dead gas-unit constants gone. Compiles within BATCH-02 (`forge build` exit 0). Test rename mirrors land in 330-08.
