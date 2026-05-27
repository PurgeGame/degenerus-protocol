---
phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
plan: 01
subsystem: keeper-router
tags: [solidity, advance, bounty-rehome, vrf-freeze]

requires:
  - phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
    provides: "the locked (mult) advance return shape + the U1/U2/U3/U6 creditFlip classification (329-ATTEST §D)"
provides:
  - "advanceGame() with the 3 in-callee advance-bounty creditFlip sites deleted (standalone advance now pays NO bounty)"
  - "advanceGame() returns the canonical day-epoch stall multiplier as a typed return the router pays from"
  - "the dead ADVANCE_BOUNTY_ETH constant removed; the SDGNRS gameover creditFlip (U6) preserved verbatim"
affects: [330-02, 330-04, 330-06, 330-07]

tech-stack:
  added: []
  patterns:
    - "Re-home a bounty into the router by returning the multiplier the consumer pays from — never recompute reward in a money path"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "DEVIATION (USER-approved): advanceGame() returns (uint8 mult) ONLY — the planned bool `rewardable` was collapsed into the mult==0 sentinel (mult==0 = advance ran but earns nothing). One return value, simpler ABI, same semantics."
  - "New-day exit returns mult = the kept GAME-day stall ladder (1/2/4/6); mid-day partial-drain returns mult=1 (ADV-05/D-07 no escalation); gameover partial-drain returns mult=1; gameover non-rewardable paths return mult=0."
  - "The U6 SDGNRS creditFlip (now ~:860) is a game-economic credit to ContractAddresses.SDGNRS, NOT a keeper bounty — preserved verbatim."

patterns-established:
  - "mult==0 as the unrewarded sentinel: removes the need for a parallel bool while keeping standalone advance fully functional + unrewarded"

requirements-completed: [ADV-01, ADV-02, ADV-03, ADV-05]

duration: part of BATCH-02
completed: 2026-05-27
---

# Phase 330 Plan 01: AdvanceModule advance-bounty removal + (mult) return — Summary

**The advance bounty is severed from the advance callee and surfaced as a typed `(uint8 mult)` return so the unified router pays it once — standalone `advanceGame()` is now fully functional and unrewarded.**

## Performance
- **Mode:** applied as part of the single USER-approved BATCH-02 diff (commit `63bc16ca`)
- **Completed:** 2026-05-27
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Deleted the 3 caller-paying `creditFlip(caller, …)` sites (U1 gameover partial-drain, U2 mid-day partial-drain, U3 new-day) and their reward arithmetic; preserved every surrounding emit / `_lrWrite` / early `return` / `_unlockRng` / RNG-consume statement byte-faithfully.
- Removed the now-dead `ADVANCE_BOUNTY_ETH` constant (0 remaining references); left the KEPT GAME-day stall epoch block (1/2/4/6) in place as the source of `mult`.
- Changed `advanceGame()` to `returns (uint8 mult)` — new-day = stall ladder, mid-day/gameover-rewardable = 1, gameover-non-rewardable = 0 (the unrewarded sentinel).
- Preserved the U6 `coinflip.creditFlip(ContractAddresses.SDGNRS, …)` game-economic credit (NOT a keeper bounty).
- ADV-04 honored: no new player-controllable SLOAD added to the advance-consume window — `mult` reads the already-present `block.timestamp`-derived epoch block.

## Task Commits
Per the project's batched-contract-approval policy ([[feedback_batch_contract_approval]]), this plan's production edits were applied to the working tree and committed — together with all 8 other plans in the phase — as the single USER-approved batched diff:

1. **Task 1 + Task 2: delete the 3 advance creditFlips + add the (uint8 mult) return** — landed in `63bc16ca` (`feat(330): v49.0 keeper-router redesign (BATCH-02, user-approved)`)

_The per-plan atomic-commit model was superseded by the single-batched-diff contract rule for this phase; this SUMMARY is the per-plan closeout record._

## Files Created/Modified
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 3 caller creditFlips removed, `ADVANCE_BOUNTY_ETH` deleted, `advanceGame()` returns `(uint8 mult)`, U6 SDGNRS credit preserved.

## Deviations
- **`rewardable` bool dropped → `mult==0` sentinel** (USER-approved). Plan 330-01 specified `(uint8 mult, bool rewardable)`; the delivered shape is `(uint8 mult)` with `mult==0` meaning "advance ran, no bounty." Propagated consistently to the wrapper (330-02), interface (330-04), and the router's `if (mult > 0)` gate (330-07).

## Self-Check: PASSED
- `function advanceGame() external returns (uint8 mult)` present; 0 caller creditFlips; 1 SDGNRS creditFlip survives; `ADVANCE_BOUNTY_ETH` gone. Compiles within BATCH-02 (`forge build` exit 0).
