---
phase: 07-jackpot-distribution-mechanics
plan: 01
subsystem: audit
tags: [jackpot, eth-drip, burnie, lootbox, purchase-phase, distribution]

requires:
  - phase: 06-eth-inflows-pool-architecture
    provides: Pool lifecycle and futurePrizePool drawdown context
provides:
  - Purchase-phase daily ETH drip formula with exact constants
  - Purchase-phase daily BURNIE jackpot budget and distribution mechanics
  - Lootbox over-collateralization documentation (2x backing ratio)
affects: [07-02-jackpot-phase-draws, 07-03-transition-jackpots, 11-parameter-reference]

tech-stack:
  added: []
  patterns: [worked-example-per-section, over-collateralization-documentation]

key-files:
  created:
    - audit/v1.1-purchase-phase-distribution.md
  modified: []

key-decisions:
  - "Documented lootbox over-collateralization as explicit design property (2x backing ratio from 50% ticket conversion of 75% lootbox budget)"
  - "Included worked examples with concrete ETH/BURNIE numbers for agent consumption"

patterns-established:
  - "Pitfall sections at end of each distribution document for agent edge-case awareness"

requirements-completed: [JACK-01, JACK-02, JACK-06]

duration: 3min
completed: 2026-03-12
---

# Phase 7 Plan 1: Purchase-Phase Distribution Summary

**Daily ETH drip (1% futurePrizePool, 75/25 lootbox/ETH split) and BURNIE jackpot (0.5% of prev level target, 75/25 near/far split) with over-collateralization mechanics**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-12T14:42:34Z
- **Completed:** 2026-03-12T14:45:34Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Complete purchase-phase ETH drip documentation with trigger conditions, pool slice formula, lootbox conversion, and ticket count derivation
- Complete purchase-phase BURNIE jackpot documentation with budget formula, 75/25 near/far split, winner selection mechanics, and coinflip credit payment
- Lootbox over-collateralization explicitly documented (2x backing ratio from ticketConversionBps=5000)
- Constants reference table with 15 entries verified against contract source with file and line numbers

## Task Commits

Each task was committed atomically:

1. **Task 1: Document purchase-phase daily ETH drip and BURNIE jackpots** - `06501a3f` (feat)

## Files Created/Modified
- `audit/v1.1-purchase-phase-distribution.md` - Complete purchase-phase distribution reference document with 5 sections, worked examples, and constants table

## Decisions Made
- Documented the lootbox over-collateralization as an explicit design property rather than a side effect, making the 2x backing ratio computable by agents
- Included worked examples with concrete numbers (100 ETH futurePrizePool, 80 ETH levelPrizePool) to demonstrate formula application

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Purchase-phase distribution fully documented, ready for Plan 07-02 (jackpot-phase 5-day draws)
- Pool lifecycle context from 06-pool-architecture.md correctly cross-referenced
- Lootbox ratio comparison table ready for expansion in 07-02

---
*Phase: 07-jackpot-distribution-mechanics*
*Completed: 2026-03-12*
