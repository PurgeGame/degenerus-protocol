---
phase: 08-burnie-economics
plan: 02
subsystem: documentation
tags: [burnie, erc20, supply-dynamics, vault, decimator, coinflip, lootbox]

requires:
  - phase: 08-burnie-economics
    provides: "Research on BURNIE earning paths, burn sinks, vault mechanics (BURN-02 through BURN-04)"
provides:
  - "Complete BURNIE supply dynamics reference for game theory agents"
  - "Supply invariant operation impact table"
  - "Earning path vs burn sink classification with delivery methods"
  - "Vault DGVB share redemption mechanics"
affects: [09-dgnrs-token, 10-advanced-mechanics, 11-parameter-reference]

tech-stack:
  added: []
  patterns: [supply-flow-diagram, operation-impact-table, worked-example-tracing]

key-files:
  created:
    - audit/v1.1-burnie-supply.md
  modified: []

key-decisions:
  - "Documented lootbox BURNIE low-path max as 129.63% (roll=15), correcting research note of 130.43%"
  - "Included vault transfer as a non-permanent burn sink (returns to reserve) distinct from permanent burns"
  - "Added Step 5 (vaultEscrow) to worked example to demonstrate reserve growth mechanism"

patterns-established:
  - "Supply variable tracking: trace totalSupply, vaultAllowance, supplyIncUncirculated through every operation"
  - "Delivery method classification: mint (creates supply) vs creditFlip (virtual only) vs vault return"

requirements-completed: [BURN-02, BURN-03, BURN-04]

duration: 4min
completed: 2026-03-12
---

# Phase 8 Plan 02: BURNIE Supply Dynamics Summary

**Complete BURNIE supply model with 7 earning paths, 4 burn sinks, vault invariant operation table, and DGVB share redemption mechanics**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-12T15:06:44Z
- **Completed:** 2026-03-12T15:10:41Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Documented supply invariant (totalSupply + vaultAllowance = supplyIncUncirculated) with 9-operation impact table verified against BurnieCoin.sol source
- Classified all 7 earning paths by delivery method (mint vs creditFlip virtual) with exact Solidity and line references
- Documented all 4 burn sinks with permanence flags, conditions, and minimum amounts
- Provided vault claim mechanics with DGVB reserve formula and three-source fulfillment priority
- Created worked example tracing 5 operations through all supply variables with arithmetic verification
- Built 27-entry constants reference table with source file and line numbers

## Task Commits

Each task was committed atomically:

1. **Task 1: Document BURNIE supply dynamics** - `e1dd00a2` (feat)

## Files Created/Modified
- `audit/v1.1-burnie-supply.md` - Complete BURNIE supply dynamics reference (810 lines)

## Decisions Made
- Documented lootbox low-path max BPS at 129.63% (varianceRoll=15, 5808 + 15*477 = 12963), correcting the research note's 130.43% which assumed roll value 15.2
- Included vault-bound transfers as a distinct "non-permanent" sink category since they return BURNIE to the reserve rather than destroying it
- Extended worked example to 5 steps (adding vaultEscrow) to demonstrate the full spectrum of supply operations

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- BURNIE supply dynamics complete, ready for BURN-01 (coinflip mechanics) if not already covered
- Cross-references to v1.1-burnie-coinflip.md and v1.1-transition-jackpots.md are in place
- Constants table provides foundation for Phase 11 parameter reference consolidation

---
*Phase: 08-burnie-economics*
*Completed: 2026-03-12*
