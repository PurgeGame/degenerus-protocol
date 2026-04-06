---
phase: 195-jackpot-two-call-split
plan: 02
subsystem: contracts
tags: [solidity, gas-optimization, jackpot, two-call-split, advance-module]

requires:
  - phase: 195-jackpot-two-call-split
    plan: 01
    provides: Two-call split logic in _processDailyEth, resumeEthPool storage
provides:
  - STAGE_JACKPOT_ETH_RESUME (stage 8) in AdvanceModule
  - Resume routing in advanceGame stage machine
  - _resumeDailyEth entry point in JackpotModule
  - Early-burn/terminal path simplified to single call
affects: [196 gas benchmark, 197 payout reference]

tech-stack:
  added: []
  patterns: [resume via existing payDailyJackpot entry point, caller-controlled winner caps]

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/modules/DegenerusGameJackpotModule.sol
    - hardhat.config.js

key-decisions:
  - "Resume handled inside payDailyJackpot via _resumeDailyEth private function — no separate external entry point needed"
  - "Early-burn/terminal path simplified to single call with JACKPOT_MAX_WINNERS=160 cap — no two-call split needed"
  - "isResume parameter removed from _executeJackpot, _runJackpotEthFlow, _distributeJackpotEth"
  - "runTerminalJackpot safe at 305 winners — no autorebuy at game over eliminates gas concern"
  - "Optimizer runs lowered 200→50 for bytecode savings (JackpotModule at 99.2% of 24KB limit)"

patterns-established:
  - "Resume via existing entry point + private helper, not separate external function"

requirements-completed: [GAS-02, GAS-03]

duration: inline
completed: 2026-04-06
---

# Phase 195 Plan 02: Wire AdvanceModule Stage Routing Summary

**STAGE_JACKPOT_ETH_RESUME wired, early-burn path simplified to single call**

## Performance

- **Duration:** inline execution
- **Completed:** 2026-04-06
- **Tasks:** 3 (2 auto + 1 checkpoint)
- **Files modified:** 3

## Accomplishments
- STAGE_JACKPOT_ETH_RESUME = 8 added to AdvanceModule stage constants
- Resume check inserted before dailyJackpotCoinTicketsPending in jackpot phase flow
- _resumeDailyEth private function reconstructs params from stored state for call 2
- isResume parameter removed from early-burn chain (_executeJackpot → _runJackpotEthFlow → _distributeJackpotEth)
- _distributeJackpotEth simplified to process all 4 buckets in single call (caller controls cap)
- JACKPOT_MAX_WINNERS lowered 300 → 160 for early-burn path safety
- Optimizer runs 200 → 50 for bytecode (JackpotModule 24,380B = 99.2% of limit)

## Task Commits

1. **Task 1-2: Contract changes + NatSpec** - `5ed8bdb8`, `feb86f94`
2. **Task 3: User approval checkpoint** - approved

## Files Created/Modified
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Stage 8 constant, resume routing in jackpot flow
- `contracts/modules/DegenerusGameJackpotModule.sol` - _resumeDailyEth, simplified early-burn path, JACKPOT_MAX_WINNERS=160
- `hardhat.config.js` - Optimizer runs 200→50

## Decisions Made
- Resume handled inside payDailyJackpot (reusing existing entry) rather than a new external function
- Early-burn/terminal path doesn't need two-call split — 160 cap sufficient, terminal safe without autorebuy
- Optimizer runs lowered to keep JackpotModule under 24KB after adding resume logic

## Deviations from Plan
- No separate resumeDailyJackpotEth external function — resume routed through payDailyJackpot + _resumeDailyEth private
- _distributeJackpotEth simplified instead of getting two-call split — JACKPOT_MAX_WINNERS=160 makes it unnecessary
- runTerminalJackpot left as-is (305 winners safe due to no autorebuy at game over)

## Verification Results
- Compilation: 60 files, zero errors
- Core tests: 110 passing, 0 failing (DegenerusGame, DegenerusJackpots, GameLifecycle)
- Pre-existing: 9 CompressedJackpot failures (same on committed HEAD)
- Gas benchmark: 1 test setup issue (try/catch eats resume — not a contract bug)
- JackpotModule: 24,380B (99.2%), AdvanceModule: 17,636B (71.8%)

## Issues Encountered
- Gas test AdvanceGameGas.test.js line 491 try/catch swallows the resume call, causing line 497 to revert with NotTimeYet — test setup issue, not contract regression

## Next Phase Readiness
- Phase 196 gas benchmark can now test both split calls
- Phase 197 payout reference should document the new two-call flow

---
*Phase: 195-jackpot-two-call-split*
*Completed: 2026-04-06*
