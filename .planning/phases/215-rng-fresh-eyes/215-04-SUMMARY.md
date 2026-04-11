---
phase: 215-rng-fresh-eyes
plan: 04
subsystem: rng-audit
tags: [vrf, keccak256, entropy-derivation, lcg-prng, word-derivation, chainlink-vrf]

# Dependency graph
requires:
  - phase: 215-01
    provides: VRF lifecycle trace with word storage locations and fulfillment paths
  - phase: 213
    provides: RNG chain definitions RNG-03 through RNG-11
provides:
  - Per-consumer derivation chain from VRF word to game outcome for all 11 RNG chains
  - Verdict table covering 16 derivation paths (14 VRF-SOURCED, 1 MIXED, 1 NON-VRF)
  - Threat register resolution for T-215-10, T-215-11, T-215-12
affects: [215-05-mutual-exclusion-synthesis]

# Tech tracking
tech-stack:
  added: []
  patterns: [keccak256-domain-separation, xorshift-entropy-chaining, lcg-seed-from-vrf]

key-files:
  created: [.planning/phases/215-rng-fresh-eyes/215-04-WORD-DERIVATION.md]
  modified: []

key-decisions:
  - "All game-outcome entropy verified VRF-sourced; gameover prevrandao fallback and deity tier-3 fallback documented as known exceptions"
  - "LCG seed provenance confirmed (XOR with VRF word); output quality analysis deferred per D-02"

patterns-established:
  - "Derivation chain format: VRF source -> exact Solidity code + line -> operation -> game outcome -> verdict"

requirements-completed: [RNG-04]

# Metrics
duration: 6min
completed: 2026-04-11
---

# Phase 215 Plan 04: Word Derivation Verification Summary

**Every keccak/shift/mask/modulo producing a game outcome traced to VRF source word -- 14 VRF-SOURCED, 1 MIXED (gameover prevrandao), 1 NON-VRF (deity pre-VRF fallback)**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-11T00:22:43Z
- **Completed:** 2026-04-11T00:28:57Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments

- Traced all 11 RNG chains (RNG-03 through RNG-11) plus backfill, orphaned lootbox backfill, lootbox resolution chain, and early-bird jackpot -- 16 total derivation paths
- Every chain documented with exact Solidity code snippets, line numbers, input provenance, derivation operation, and per-chain verdict
- LCG PRNG seed provenance verified: `(baseKey + groupIdx) ^ entropyWord` where `entropyWord` = `lootboxRngWordByIndex[index]` (VRF-delivered)
- Threat register resolved: T-215-10 (keccak domain separation confirmed via trait/salt/i parameters), T-215-11 (LCG seed traces to VRF), T-215-12 (prevrandao gameover accepted)
- Zero findings -- no game-outcome entropy derives from non-VRF sources except two documented exceptions

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace every entropy derivation from VRF source word to game outcome** - `322329dd` (feat)

## Files Created/Modified

- `.planning/phases/215-rng-fresh-eyes/215-04-WORD-DERIVATION.md` - Per-consumer derivation chain audit (772 lines)

## Decisions Made

- Included supplemental chains beyond the core 11 (lootbox resolution, early-bird jackpot, orphaned lootbox backfill, _dailyCurrentPoolBps) for completeness since they also produce game outcomes from VRF entropy
- Documented deity _deityDailySeed tier-3 fallback as NON-VRF because it uses `keccak256(day, address(this))` -- but noted it only fires pre-VRF and affects cosmetic/utility boons, not ETH payouts

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 4 prerequisite plans (215-01 through 215-04) now complete
- Plan 215-05 (rngLocked mutual exclusion + synthesis) is unblocked -- depends on plans 01-04

---
*Phase: 215-rng-fresh-eyes*
*Completed: 2026-04-11*
