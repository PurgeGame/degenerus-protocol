---
phase: 02-core-state-machine-vrf-lifecycle
plan: "06"
subsystem: rng
tags: [xorshift, prng, entropy, vrf, chainlink, randomness-audit]

requires:
  - phase: 02-core-state-machine-vrf-lifecycle
    provides: "VRF lifecycle and rngLockedFlag coverage from 02-01 through 02-05"
provides:
  - "RNG-09 verdict: entropyStep xorshift (7,9,8) on 256-bit not exploitable with VRF seed"
  - "RNG-10 verdict: VRF is sole randomness source, no block data used for entropy"
  - "Complete entropyStep call site enumeration (19 sites across 6 files)"
  - "Full block.timestamp inventory (27 usages, all timing/gating)"
  - "End-to-end RNG derivation chain trace (VRF -> nudge -> entropyStep -> consumer)"
affects: [fuzzing-campaigns, economic-analysis]

tech-stack:
  added: []
  patterns:
    - "entropyStep threading pattern: entropy = EntropyLib.entropyStep(entropy); value = entropy % range"
    - "XOR domain separation: entropyStep(entropy ^ (traitIdx << 64) ^ contextValue)"
    - "keccak256 seed mixing: keccak256(abi.encode(rngWord, player, day, amount))"

key-files:
  created:
    - ".planning/phases/02-core-state-machine-vrf-lifecycle/02-06-FINDINGS-entropy-lib-analysis.md"
  modified: []

key-decisions:
  - "Non-standard xorshift constants (7,9,8) accepted as safe because VRF seed quality dominates and <30 iterations used per word"
  - "Affiliate payout non-VRF seed classified as Informational (minor economic mechanism, cost of manipulation exceeds payout)"
  - "Deity boon deterministic fallback classified as Informational (edge case only, no ETH at stake)"

patterns-established:
  - "Randomness source classification: TIMING vs RANDOMNESS for block.timestamp"
  - "keccak256 classification: storage keys, constant tags, VRF-derived mixing, deterministic derivation"

requirements-completed: [RNG-09, RNG-10]

duration: 5min
completed: 2026-02-28
---

# Phase 02 Plan 06: EntropyLib Analysis Summary

**XorShift PRNG (7,9,8) on 256-bit state verified non-exploitable with VRF seed; all 27 block.timestamp usages confirmed timing-only; zero block-data randomness sources found across entire protocol**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-01T03:19:21Z
- **Completed:** 2026-03-01T03:24:51Z
- **Tasks:** 2
- **Files created:** 1

## Accomplishments

- Analyzed entropyStep() for fixed points (only zero, mitigated by VRF 0->1 mapping), period (unknown but sufficient for <30 iterations), and output distribution (negligible bias for protocol ranges)
- Enumerated all 19 entropyStep call sites across 6 files with purpose, modular range, and entropy threading verification -- no reuse of same entropy state, no user-controlled inputs
- Audited every block.timestamp usage (27 total) -- all timing/gating, zero randomness
- Confirmed zero usage of blockhash, block.prevrandao, block.difficulty, block.number
- Classified all keccak256 usages: storage keys, compile-time tags, VRF-derived mixing, deterministic derivation
- Traced complete RNG derivation chain from VRF fulfillment through nudge application through entropyStep iterations to consumer modular reduction
- Identified 3 informational findings (affiliate non-VRF seed, deity boon fallback, NatSpec inaccuracy)

## Task Commits

Each task was committed atomically:

1. **Task 1+2: EntropyLib analysis, call site enumeration, randomness audit, RNG chain trace, verdicts** - `c5c9552` (feat)

## Files Created/Modified

- `.planning/phases/02-core-state-machine-vrf-lifecycle/02-06-FINDINGS-entropy-lib-analysis.md` - Complete EntropyLib analysis, randomness source audit, RNG chain trace, RNG-09/RNG-10 verdicts

## Decisions Made

- Non-standard xorshift constants (7,9,8) accepted as safe: the security model depends on VRF seed unpredictability, not PRNG cryptographic strength. With <30 iterations per seed on 256-bit state, even a suboptimal xorshift is more than adequate.
- Affiliate payout roll using `keccak256(tag, day, sender, code)` without VRF: classified as Informational rather than a finding because affiliate payouts are minor economic mechanism and manipulation cost exceeds payout value.
- Deity boon deterministic fallback `keccak256(day, address(this))`: classified as Informational because it only activates before first VRF or during catastrophic failure, and deity boons are free perks with no ETH at stake.

## Deviations from Plan

None - plan executed exactly as written. Tasks 1 and 2 were combined into a single commit since they both produce the same output file.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- RNG-09 and RNG-10 requirements satisfied
- EntropyLib analysis complete; xorshift properties documented for reference by future fuzzing campaigns
- 3 informational findings documented for project awareness (no action required)

## Self-Check: PASSED

- FOUND: 02-06-FINDINGS-entropy-lib-analysis.md
- FOUND: 02-06-SUMMARY.md
- FOUND: commit c5c9552

---
*Phase: 02-core-state-machine-vrf-lifecycle*
*Completed: 2026-02-28*
