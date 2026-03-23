---
phase: 72-ticket-queue-deep-dive-pattern-scan
plan: 01
subsystem: audit
tags: [vrf, commitment-window, ticket-queue, double-buffer, jackpot, burnie]

requires:
  - phase: 69-commitment-window-mutation-verdicts
    provides: per-variable binary verdicts for all 51 VRF-touched variables
  - phase: 71-advancegame-day-rng-window
    provides: daily VRF word consumer trace and commitment window analysis
provides:
  - TQ-01 exploitation scenario for _awardFarFutureCoinJackpot _tqWriteKey bug
  - Phase 69 verdict correction for ticketQueue slot 15
  - TQ-02 fix recommendation (Fix Option A) with global swap proof
affects: [72-02, fix-verification]

tech-stack:
  added: []
  patterns: [double-buffer lifecycle tracing, entropy precomputation attack modeling]

key-files:
  created: []
  modified:
    - audit/v3.8-commitment-window-inventory.md

key-decisions:
  - "Severity MEDIUM not HIGH: stolen asset is BURNIE (flipCredit) not ETH, limiting direct economic impact"
  - "Fix Option A (_tqWriteKey -> _tqReadKey) recommended over Fix Option B (rngLockedFlag guard): root cause fix, one-line change, aligns with processTicketBatch pattern"
  - "purchaseCoin() equally exploitable: COIN_PURCHASE_CUTOFF is a liveness guard (90 days) not a commitment window guard"
  - "Both call paths affected: payDailyJackpotCoinAndTickets (jackpot phase) and payDailyCoinJackpot (purchase phase)"

patterns-established:
  - "Double-buffer vulnerability analysis: always verify which buffer key (_tqWriteKey vs _tqReadKey) each consumer uses"
  - "Global vs per-level swap verification: _swapTicketSlot flips a single global bit affecting all levels simultaneously"

requirements-completed: [TQ-01, TQ-02]

duration: 3min
completed: 2026-03-23
---

# Phase 72 Plan 01: Ticket Queue Exploitation Scenario + Fix Analysis Summary

**Complete exploitation scenario for _awardFarFutureCoinJackpot _tqWriteKey bug (MEDIUM severity) with 5-step attack sequence, Phase 69 verdict correction, and Fix Option A recommendation backed by global swap proof**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-23T00:19:00Z
- **Completed:** 2026-03-23T00:22:46Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Documented full exploitation scenario (TQ-01) for _awardFarFutureCoinJackpot reading from write buffer at JackpotModule:2544, including preconditions, 5-step attack sequence with entropy precomputation code, outcome manipulation analysis, and MEDIUM severity assessment
- Corrected Phase 69 verdict for ticketQueue (slot 15): SAFE for processTicketBatch but VULNERABLE for _awardFarFutureCoinJackpot
- Identified both call paths affected: payDailyJackpotCoinAndTickets (JackpotModule:707) and payDailyCoinJackpot (JackpotModule:2370)
- Verified purchaseCoin() equally exploitable (no rngLockedFlag, COIN_PURCHASE_CUTOFF is irrelevant to commitment window)
- Confirmed mid-day VRF path is not exploitable (stores to lootboxRngWordByIndex only, no jackpot calls)
- Recommended Fix Option A (_tqWriteKey -> _tqReadKey) with full global swap lifecycle proof demonstrating correctness
- Documented Fix Option B tradeoffs (overly broad, UX impact, symptom-not-cause)

## Task Commits

Each task was committed atomically:

1. **Task 1: Ticket Queue Exploitation Scenario + Fix Analysis (TQ-01, TQ-02)** - `9ec1e85d` (feat)

## Files Created/Modified

- `audit/v3.8-commitment-window-inventory.md` - Appended Phase 72 Sections 1-2: TQ-01 exploitation scenario (1.1-1.8) and TQ-02 fix analysis (2.1-2.4)

## Decisions Made

- **Severity MEDIUM not HIGH:** The stolen asset is BURNIE (flipCredit), not ETH. While the attack is repeatable and low-cost, the direct economic impact is limited to game-token redistribution. HIGH would require direct ETH theft or protocol insolvency risk.
- **Fix Option A recommended:** Root cause fix (change _tqWriteKey to _tqReadKey) over symptom fix (add rngLockedFlag to purchases). One-line change, aligns with processTicketBatch pattern, no UX impact.
- **Both call paths affected:** payDailyJackpotCoinAndTickets (jackpot phase, JackpotModule:707) AND payDailyCoinJackpot (purchase phase, JackpotModule:2370) both invoke _awardFarFutureCoinJackpot with the same bug.
- **purchaseCoin() equally exploitable:** COIN_PURCHASE_CUTOFF (90 days) is a liveness guard checking elapsed time since level start, not a commitment window guard. It does not block purchases during VRF fulfillment-to-advanceGame window.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Next Phase Readiness

- Phase 72 Section 1 (TQ-01) and Section 2 (TQ-02) appended to audit artifact
- Ready for Plan 02 to append Section 3 (TQ-03: pattern scan for similar write-buffer bugs)

## Self-Check: PASSED

- audit/v3.8-commitment-window-inventory.md: FOUND
- 72-01-SUMMARY.md: FOUND
- Commit 9ec1e85d: FOUND
- Phase 72 section header count: 1 (correct)

---
*Phase: 72-ticket-queue-deep-dive-pattern-scan*
*Completed: 2026-03-23*
