---
phase: 83-ticket-consumption-winner-selection
plan: 02
subsystem: audit
tags: [solidity, jackpot, winner-selection, rng-derivation, cross-reference, smart-contract-audit]

# Dependency graph
requires:
  - phase: 83-ticket-consumption-winner-selection
    provides: "Plan 01: ticketQueue and traitBurnTicket read enumeration (TCON-01, TCON-02)"
  - phase: 81-ticket-creation-queue-mechanics
    provides: "DSC-01, DSC-02, DSC-03 findings for cross-reference"
provides:
  - "Per-jackpot winner index formula documentation for all 9 jackpot types (TCON-03)"
  - "RNG word derivation chain from VRF callback to per-winner entropy"
  - "Cross-reference of 23 prior audit claims with verification status (TCON-04)"
  - "Updated v4.0-findings-consolidated.md with Phase 83 status"
affects: [84-prize-pool-flow, 85-daily-eth-jackpot, 86-daily-coin-ticket-jackpot, 87-other-jackpots, 88-rng-reaudit]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Per-jackpot subsection format: entry point, RNG derivation chain, winner index formula, pool source, deity behavior, max winners, key Solidity lines"]

key-files:
  created: []
  modified:
    - audit/v4.0-ticket-consumption-winner-selection.md
    - audit/v4.0-findings-consolidated.md

key-decisions:
  - "Far-future coin jackpot uses fundamentally different winner selection (inline (entropy >> 32) % len, no deity virtual entries) compared to all other jackpot types which use _randTraitTicket helpers"
  - "BAF jackpot documented as 9th type despite being external contract -- uses view functions on DegenerusGame, not direct storage reads"
  - "v3.9 proof discrepancies (DSC-01) confirmed as security-neutral: FF-only is strictly simpler than combined pool"
  - "No new findings in Phase 83 -- all winner index formulas verified correct against current Solidity source"

patterns-established:
  - "Cross-reference table format: Claim # | v3.X Reference | Current Code | Status (CONFIRMED/DISCREPANCY/STALE)"

requirements-completed: [TCON-03, TCON-04]

# Metrics
duration: 7min
completed: 2026-03-23
---

# Phase 83 Plan 02: Winner Index Computation and Cross-Reference Summary

**Winner index formulas documented for 9 jackpot types with 200+ file:line citations, 23 prior audit claims cross-referenced (15 CONFIRMED, 6 DISCREPANCY, 2 STALE), 0 new findings**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-23T15:14:13Z
- **Completed:** 2026-03-23T15:22:05Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Documented winner index computation for all 9 jackpot types: daily ETH (Phase 0 and carryover), early-burn ETH, daily coin (near-future), far-future coin, daily ticket, early-bird lootbox, DGNRS final day reward, and BAF
- Created consolidated RNG derivation table showing base entropy formula, per-winner step, salt/tag, and deity behavior for each jackpot type
- Cross-referenced 23 prior audit claims from v3.8 (9 claims), v3.9 (12 claims), and Phase 81 (3 findings): 15 CONFIRMED, 6 DISCREPANCY, 2 STALE
- Independently re-confirmed DSC-01 (stale v3.9 proof) and DSC-02 (wrong key space in sampleFarFutureTickets) from consumption perspective
- Updated v4.0-findings-consolidated.md with Phase 83 completion status

## Task Commits

Each task was committed atomically:

1. **Task 1: Document winner index computation per jackpot type + RNG derivation (TCON-03)** - `1afb2252` (feat)
2. **Task 2: Cross-reference prior audits and tag all discrepancies/findings (TCON-04)** - `2196ea3b` (feat)

## Files Created/Modified
- `audit/v4.0-ticket-consumption-winner-selection.md` - Sections 4-7: winner index computation, RNG derivation summary, cross-reference tables, findings summary
- `audit/v4.0-findings-consolidated.md` - Updated with Phase 83 status, cross-reference rows, source deliverables

## Decisions Made
- Far-future coin jackpot is fundamentally different from all trait-based jackpots: uses inline `(entropy >> 32) % len` with no deity virtual entries, no `_randTraitTicket` helper, and reads from ticketQueue instead of traitBurnTicket
- BAF jackpot included as 9th type despite living in separate contract (DegenerusJackpots.sol) -- documented separately since it uses view functions and leaderboard-based selection, not random index selection
- v3.9 proof discrepancies classified as security-neutral: FF-only read is strictly simpler than the combined pool the proof describes, so the SAFE verdict holds a fortiori
- Salt ranges documented to show non-collision: daily ETH 200-203, coin 252-255, ticket 241-244, lootbox 0-99, DGNRS 254

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- TCON-01 through TCON-04 fully satisfied with independently verified file:line citations
- Phase 83 audit document complete with all 7 sections
- Ready for downstream phases: 84 (prize pool), 85 (daily ETH deep dive), 86 (coin+ticket deep dive)
- DSC-01 and DSC-02 remain the only findings; no new issues discovered

## Self-Check: PASSED

- audit/v4.0-ticket-consumption-winner-selection.md: FOUND
- audit/v4.0-findings-consolidated.md: FOUND
- Commit 1afb2252: FOUND
- Commit 2196ea3b: FOUND

---
*Phase: 83-ticket-consumption-winner-selection*
*Completed: 2026-03-23*
