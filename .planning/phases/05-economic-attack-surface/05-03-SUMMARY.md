---
phase: 05-economic-attack-surface
plan: 03
subsystem: security-audit
tags: [affiliate, referral, BURNIE, circular-referral, weighted-winner-roll, extraction]

# Dependency graph
requires:
  - phase: 03a-arithmetic-verification
    provides: "Ticket cost formula, BPS split verification, affiliate rakeback confirmed BURNIE-only"
  - phase: 03b-state-mutation-safety
    provides: "Activity score bounds (30500 BPS max), lootbox EV model (80-135%)"
provides:
  - "ECON-03 PASS: affiliate referral system cannot create positive-sum extraction"
  - "Circular referral model: pair loses 1.50 ETH per 2.00 ETH deposited even at 1:1 BURNIE/ETH"
  - "Weighted winner roll determinism analysis: EV-preserving, max single-tx variance +24%"
  - "BURNIE value model: inflationary mint with no direct ETH redemption"
affects: [05-economic-attack-surface]

# Tech tracking
tech-stack:
  added: []
  patterns: ["affiliate reward denomination tracing", "circular referral pair EV modeling"]

key-files:
  created:
    - ".planning/phases/05-economic-attack-surface/05-03-FINDINGS-affiliate-extraction.md"
  modified: []

key-decisions:
  - "ECON-03 PASS: affiliate rewards are BURNIE mints (not ETH transfers), making circular referrals structurally negative-sum"
  - "Weighted winner roll determinism classified Informational: EV-preserving over multiple transactions, max +24% single-tx variance"
  - "Affiliate bonus points (50 max) trivially saturated with 0.02 ETH volume; circular referrals add no advantage"

patterns-established:
  - "BURNIE denomination barrier: any reward pathway using creditFlip/creditCoin is inflationary mint, not prize pool drainage"

requirements-completed: [ECON-03]

# Metrics
duration: 4min
completed: 2026-03-01
---

# Phase 5 Plan 3: Affiliate Extraction Analysis Summary

**ECON-03 PASS: affiliate rewards are inflationary BURNIE mints, circular referral pairs lose 75%+ of deposit even at theoretical 1:1 BURNIE/ETH, weighted winner roll is EV-preserving with bounded variance**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-01T12:43:27Z
- **Completed:** 2026-03-01T12:47:40Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Verified affiliate reward denomination as BURNIE minting (creditFlip/creditCoin -> _mint) with specific line numbers from DegenerusAffiliate.sol, BurnieCoin.sol, and BurnieCoinflip.sol
- Modeled circular referral structures: A->B, B->A depositing 2 ETH total yields 50,000 BURNIE (0.50 ETH equivalent at mint rate), net loss 1.50 ETH
- Analyzed weighted winner roll: keccak256(tag, day, sender, code) is deterministic/precomputable but EV-preserving by construction; day-alignment yields max +24% single-transaction variance, irrelevant for sybil-controlled recipient sets
- Quantified fresh vs recycled rate impact: 25%/5% rates cannot enable extraction since fresh ETH costs real deposits
- Confirmed affiliate bonus points (50 max) saturated at 0.02 ETH referral volume -- circular referrals provide zero advantage over legitimate play
- Mapped all 3 payout modes (Coinflip/Degenerette/SplitCoinflipCoin): none provide ETH redemption path

## Task Commits

Each task was committed atomically:

1. **Task 1: Trace affiliate reward flow, model circular structures, write ECON-03 verdict** - `e26ce99` (feat)

## Files Created/Modified

- `.planning/phases/05-economic-attack-surface/05-03-FINDINGS-affiliate-extraction.md` - Complete affiliate extraction model with 9 sections covering denomination verification, circular referral modeling, weighted winner roll analysis, fresh/recycled rates, activity score interaction, BURNIE value model, quest amplification, payout mode analysis, and ECON-03 verdict

## Decisions Made

- ECON-03 rated unconditional PASS: five structural defenses (BURNIE denomination barrier, 25% rate cap, redistribution-not-creation, BURNIE discount, bonus point saturation) make positive-sum extraction impossible
- Weighted winner roll determinism classified Informational: not exploitable because (a) circular sybils control all recipients anyway, (b) EV converges over multiple transactions, (c) single-tx uplift bounded at +24% of scaledAmount
- BURNIE value conservatively bounded at mint-time conversion rate for worst-case analysis; in practice BURNIE trades below this due to continuous inflation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ECON-03 resolved: affiliate system confirmed non-extractive
- BURNIE denomination insight available for ECON-02 (activity score) and ECON-06 (whale bundle) analyses
- Weighted winner roll analysis complete; no further VRF-related concerns for affiliate subsystem

## Self-Check: PASSED

- FOUND: 05-03-FINDINGS-affiliate-extraction.md
- FOUND: 05-03-SUMMARY.md
- FOUND: commit e26ce99

---
*Phase: 05-economic-attack-surface*
*Completed: 2026-03-01*
