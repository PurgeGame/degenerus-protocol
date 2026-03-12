---
phase: 10-reward-systems-and-modifiers
plan: 01
subsystem: tokenomics
tags: [dgnrs, erc20, soulbound, earlybird, burn-for-backing, ppm, bps, pool-decay]

# Dependency graph
requires:
  - phase: 06-eth-inflows-and-pool-architecture
    provides: Pool lifecycle, prize pool targets, bootstrap pool value
provides:
  - DGNRS 6-pool supply distribution with exact BPS and token amounts
  - Earlybird quadratic emission curve with worked examples
  - Per-purchase DGNRS reward rates (PPM/BPS) for whale and deity purchases
  - claimAffiliateDgnrs formula with eligibility and deity bonus
  - Soulbound transfer ACL documentation
  - Burn-for-backing proportional payout mechanics
affects: [10-reward-systems-and-modifiers, 11-parameter-reference]

# Tech tracking
tech-stack:
  added: []
  patterns: [pool-decay-geometric-series, ppm-vs-bps-dual-unit-system]

key-files:
  created: [audit/v1.1-dgnrs-tokenomics.md]
  modified: []

key-decisions:
  - "Included whale bundle quantity loop decay as explicit pitfall -- each unit in a multi-buy reads decreasing pool balance"
  - "Documented claimAffiliateDgnrs 5% as non-reserved per-level share with sequential depletion warning"

patterns-established:
  - "PPM/BPS dual-unit labeling: every percentage includes both the raw constant and its unit system"
  - "Pool decay worked examples: show geometric series for agent consumption"

requirements-completed: [DGNR-01, DGNR-02, DGNR-03, DGNR-04]

# Metrics
duration: 3min
completed: 2026-03-12
---

# Phase 10 Plan 01: DGNRS Tokenomics Summary

**DGNRS soulbound token economics with 6-pool supply distribution, quadratic earlybird curve, PPM/BPS per-purchase rewards, affiliate claim formula, and burn-for-backing mechanics**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-12T16:09:02Z
- **Completed:** 2026-03-12T16:12:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Complete 6-pool supply distribution table with BPS values, token amounts, enum indices, and dust handling
- Earlybird quadratic emission curve documented with two worked examples showing 2x reward decay from ETH=0 to ETH=500
- Per-purchase DGNRS reward tables with explicit PPM vs BPS unit labeling for whale bundle and deity pass
- Pool balance decay worked example showing geometric depletion over 100 whale bundle purchases
- claimAffiliateDgnrs formula with eligibility rules, deity pass FLIP credit bonus, and sequential depletion warning
- Soulbound _transfer ACL with exact Solidity showing only address(this) and CREATOR can send
- Burn-for-backing with ETH-preferential payout ordering and BURNIE coinflip-claim-on-demand
- 7 agent pitfalls covering PPM/BPS confusion, pool decay, earlybird cutoffs, and burn supply effects

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DGNRS tokenomics reference document** - `10250f21` (feat)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `audit/v1.1-dgnrs-tokenomics.md` - DGNRS tokenomics reference document with 9 sections covering supply, earlybird, rewards, soulbound, burn, constants, and pitfalls

## Decisions Made
- Included whale bundle quantity loop decay as explicit pitfall: each unit in a multi-buy reads decreasing pool balance, preventing naive multiplication
- Documented claimAffiliateDgnrs "5% per level" as non-reserved share with sequential depletion warning
- Used geometric decay formula `pool * (1 - rate)^n` for agent-friendly pool depletion modeling

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- DGNRS tokenomics fully documented, ready for Phase 10 Plan 02 (lootbox boon modifiers) and Plan 03 (affiliate scoring)
- Constants reference table provides foundation for Phase 11 parameter consolidation

---
*Phase: 10-reward-systems-and-modifiers*
*Completed: 2026-03-12*
