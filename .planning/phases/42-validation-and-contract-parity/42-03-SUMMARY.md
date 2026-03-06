---
phase: 42-validation-and-contract-parity
plan: 03
subsystem: testing
tags: [hardhat, cross-validation, sim-bridge, contract-parity, integration]

requires:
  - phase: 42-validation-and-contract-parity
    provides: validated simulator formulas (plans 01+02)
provides:
  - End-to-end sim-contract parity proof via Hardhat integration tests
  - SimBridge module for formula comparison in Hardhat context
affects: []

tech-stack:
  added: []
  patterns: [sim-bridge-inline-reimplementation, cross-validation-pool-delta-comparison]

key-files:
  created:
    - test/validation/simBridge.js
    - test/validation/SimContractParity.test.js
  modified: []

key-decisions:
  - "Used inline re-implementation in simBridge (no cross-project TS import) to avoid build dependency"
  - "Pool ratio verification uses BPS cross-multiplication to avoid floating point"
  - "Tolerance band of +-10 BPS for pool ratio accounts for fee skims"

patterns-established:
  - "Cross-validation pattern: run same scenario on sim bridge + real contracts, compare pool deltas"
  - "Whale pricing parity: contract accepts sim-calculated price as proof of correctness"

requirements-completed: [VAL-06]

duration: 8min
completed: 2026-03-05
---

# Plan 42-03: Hardhat Cross-Validation Summary

**6 Hardhat integration tests proving end-to-end sim-contract parity for prices, pool routing, and whale pricing**

## Performance

- **Duration:** 8 min
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- SimBridge module exports 5 formula functions matching simulator's TypeScript logic
- Price parity confirmed: sim priceForLevel(0) matches contract purchaseInfo().priceWei
- Pool routing parity: 90/10 BPS split verified after ticket purchase via pool delta comparison
- Whale bundle pricing: contract accepts purchase at sim-calculated 2.4 ETH price
- Multi-purchase accumulation: cumulative pool balances track correctly across 3 buyers
- End-to-end scenario demonstrates full sim-contract parity

## Task Commits

1. **Task 1: Sim bridge module** - `e27e5ac` (feat)
2. **Task 2: Cross-validation test** - `e27e5ac` (same commit)

## Files Created/Modified
- `test/validation/simBridge.js` - 5 formula functions (priceForLevel, routeTicketSplit, routeLootboxSplit, calculateWhaleBundlePrice, calculateDeityPassPrice)
- `test/validation/SimContractParity.test.js` - 6 cross-validation tests using loadFixture(deployFullProtocol)

## Decisions Made
- Used `git add -f` for test files since `test/` is in .gitignore (intentional repo pattern)
- Pool ratio checks use BPS tolerance (8990-9010) to account for affiliate/DGNRS fee skims

## Deviations from Plan
None - plan executed as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All validation complete, phase ready for verification

---
*Phase: 42-validation-and-contract-parity*
*Completed: 2026-03-05*
