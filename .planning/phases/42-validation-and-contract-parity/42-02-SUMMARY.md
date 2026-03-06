---
phase: 42-validation-and-contract-parity
plan: 02
subsystem: testing
tags: [vitest, validation, pass-pricing, vault-math, coinflip, degenerette]

requires:
  - phase: 38-extended-mechanics
    provides: simulator mechanics modules (passPricing, vaultShareMath, coinflip, degenerette)
provides:
  - Whale/lazy/deity pass pricing validation across all levels and boon tiers
  - Vault burn math validation with floor division
  - Coinflip payout constant and statistical distribution validation
  - Degenerette ROI curve, match counting, hero mechanics, and ETH win split validation
affects: [42-03-cross-validation]

tech-stack:
  added: []
  patterns: [statistical-distribution-testing, seeded-prng-for-deterministic-tests]

key-files:
  created:
    - ../simulator/src/mechanics/__tests__/validation-pass-vault.test.ts
    - ../simulator/src/mechanics/__tests__/validation-coinflip-degenerette.test.ts
  modified: []

key-decisions:
  - "Degenerette module exists (created in Phase 38), so tests run directly without .skip"
  - "Used simple LCG PRNG for deterministic statistical coinflip distribution test"

patterns-established:
  - "Statistical validation: 10k simulated flips with tolerance bands for win rate and mean payout"
  - "Triangular pricing exhaustive loop: T(n) for n=0..31 verified algorithmically"

requirements-completed: [VAL-07, VAL-08, VAL-09, VAL-10]

duration: 8min
completed: 2026-03-05
---

# Plan 42-02: Pass/Vault/Coinflip/Degenerette Validation Summary

**114 Vitest assertions proving pass pricing, vault burns, coinflip distribution, and degenerette mechanics match Solidity contracts**

## Performance

- **Duration:** 8 min
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- Whale bundle pricing verified at all level/boon combos (levels 0-3 early, 4+ standard with discounts)
- Lazy pass pricing verified for flat (levels 0-2) and sum-of-10 (levels 3+) with boon discounts
- Deity pass T(n) triangular pricing verified exhaustively for n=0..31
- Vault burn math verified: floor division for DGVB coins, ETH-first preference for DGVE, refill trigger
- Coinflip: constants match exactly, 10k statistical simulation confirms ~50% win rate and mean payout in tolerance
- Degenerette: ROI curve interpolation, match counting, hero boost/penalty, ETH win cap/split all verified

## Task Commits

1. **Task 1: Pass pricing and vault share math** - `d522430` (feat)
2. **Task 2: Coinflip and degenerette validation** - `d522430` (same commit, bundled)

## Files Created/Modified
- `../simulator/src/mechanics/__tests__/validation-pass-vault.test.ts` - 57 tests: pass pricing + vault math
- `../simulator/src/mechanics/__tests__/validation-coinflip-degenerette.test.ts` - 57 tests: coinflip + degenerette

## Decisions Made
- Degenerette module already exists (Phase 38), so all tests run without .skip
- Used inline seeded LCG PRNG rather than importing simulator's Prng for statistical test isolation

## Deviations from Plan
None - plan executed as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All formula-level validation complete, ready for cross-validation test (Plan 42-03)

---
*Phase: 42-validation-and-contract-parity*
*Completed: 2026-03-05*
