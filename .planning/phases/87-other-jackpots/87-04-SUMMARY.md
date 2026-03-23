---
phase: 87-other-jackpots
plan: 04
subsystem: audit
tags: [solidity, jackpot, degenerette, symbol-match, lootbox-rng, addClaimableEth, consolation, sdgnrs-reward]

# Dependency graph
requires:
  - phase: 81-ticket-creation-queue
    provides: lootbox RNG flow context for degenerette bet resolution
  - phase: 87-01-earlybird-finaldgnrs
    provides: _randTraitTicket baseline for comparison (degenerette uses different RNG)
  - phase: 87-02-baf
    provides: _addClaimableEth auto-rebuy pattern for comparison
provides:
  - Degenerette full lifecycle trace (bet placement, lootbox RNG binding, per-spin resolution, 8-attribute match counting, payout distribution)
  - _addClaimableEth comparison across 4 contract versions: degenerette (NO auto-rebuy) vs JM/EM/DM (WITH auto-rebuy)
  - 25/75 ETH/lootbox payout split with 10% pool cap documented
  - sDGNRS rewards (4%/8%/15% BPS for 6/7/8 matches, 1 ETH cap) documented
  - Consolation prize (1 WWXRP for qualifying losers) documented
  - topDegeneretteByLevel confirmed view-only (not consumed by any jackpot logic)
  - DGN-01 off-by-one analyzed and withdrawn as FALSE POSITIVE (1-wei sentinel design); 6 Informational findings (DGN-02 through DGN-07)
affects: [88-rng-variable-reverification, 89-consolidated-findings]

# Tech tracking
tech-stack:
  added: []
  patterns: [lootbox-rng-resolution-audit, cross-contract-function-comparison, view-only-state-identification]

key-files:
  created:
    - audit/v4.0-other-jackpots-degenerette.md
  modified: []

key-decisions:
  - "Degenerette _addClaimableEth (DDM:1153-1159) intentionally does NOT implement auto-rebuy, unlike JM (JM:957-978), EM (EM:256-276), and DM (DM:414-424) versions"
  - "topDegeneretteByLevel is view-only decorative state -- written during bet placement, exposed via DG:2814-2820 view function, but not consumed by any jackpot or game logic"
  - "DGN-01 off-by-one in claimable balance check (DDM:552 uses <= instead of <) is a FALSE POSITIVE -- claimableWinnings uses a 1-wei sentinel to keep slot warm (DG:1367), so <= correctly preserves the sentinel"

patterns-established:
  - "Lootbox RNG resolution (not advanceGame RNG) for player-initiated bet mechanics"
  - "Per-spin payout with decreasing futurePrizePool pool: each spin within a multi-spin bet reads a progressively smaller pool"
  - "_addClaimableEth function comparison methodology across 4 module implementations"

requirements-completed: [OJCK-04, OJCK-06]

# Metrics
duration: 10min
completed: 2026-03-23
---

# Phase 87 Plan 04: Degenerette Jackpot Audit Summary

**Degenerette bet/resolve/payout lifecycle traced with 133 file:line citations: 3 currency types, lootbox RNG binding, 8-attribute match counting, 25/75 ETH/lootbox split with 10% pool cap, _addClaimableEth confirmed NO auto-rebuy (vs JM/EM/DM versions), sDGNRS rewards for 6+ matches, consolation WWXRP; DGN-01 off-by-one withdrawn as FALSE POSITIVE; 6 Informational findings (DGN-02 through DGN-07)**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-23T10:14:37Z
- **Completed:** 2026-03-23T10:14:47Z
- **Tasks:** 2/2
- **Files created:** 1 (audit/v4.0-other-jackpots-degenerette.md, 440 lines)

## Accomplishments

- Traced bet placement (placeFullTicketBets): 3 currency types (ETH/BURNIE/WWXRP), minimum bets (0.005 ETH/100 BURNIE/1 WWXRP), max 10 spins, packed bet storage, lootboxRngIndex RNG binding, ETH fund flow (futurePrizePool normal, pending pools when frozen)
- Traced bet resolution (_resolveFullTicketBet): lootbox RNG requirement, per-spin deterministic derivation via keccak256, 8-attribute match counting (4 quadrants x color + symbol), hero quadrant boost/penalty
- Documented payout multiplier table: 0-1 match (0x), 2 (1.90x), 3 (4.75x), 4 (15x), 5 (42.5x), 6 (195x), 7 (1000x), 8 (100,000x)
- Traced ETH payout distribution: 25/75 split (ethPortion = payout/4), 10% pool cap (ETH_WIN_CAP_BPS = 1000), excess from cap added to lootbox portion, prizePoolFrozen guard
- Compared _addClaimableEth across 4 implementations: degenerette (DDM:1153-1159, NO auto-rebuy) vs JackpotModule (JM:957-978), EndgameModule (EM:256-276), and DecimatorModule (DM:414-424) which all include auto-rebuy
- Documented sDGNRS rewards: ETH-only, 6+ matches, BPS rates (4%/8%/15% for 6/7/8 matches), 1 ETH bet cap, Reward pool source
- Documented consolation prize: qualifying losers (all spins zero payout) above minimum (0.01 ETH/500 BURNIE/20 WWXRP) receive 1 WWXRP
- Confirmed topDegeneretteByLevel is view-only -- written at DDM:518-523, exposed at DG:2814-2820, but not consumed by any jackpot, reward, or game state logic
- Analyzed DGN-01 off-by-one (DDM:552 uses <= instead of <): withdrawn as FALSE POSITIVE after discovering 1-wei sentinel pattern at DG:1367

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit degenerette bet placement, resolution, and match mechanics** - `fce52ab0` (docs)
2. **Task 2: Audit degenerette payout distribution, sDGNRS rewards, consolation, and _addClaimableEth comparison** - `fce52ab0` (docs, same commit -- both sections in single audit document)

## Files Created/Modified

- `audit/v4.0-other-jackpots-degenerette.md` - Degenerette jackpot audit with 10 sections (overview, bet placement, resolution, payout distribution, _addClaimableEth comparison, sDGNRS rewards, consolation, topDegeneretteByLevel analysis, activity score/ROI, findings summary), 133 file:line citations (120 DDM, 6 GS, 7 DG)

## Decisions Made

- Degenerette _addClaimableEth intentionally does NOT auto-rebuy: degenerette payouts are player-resolved (not system-awarded like daily jackpots), so auto-rebuy would create unexpected ticket purchases on bet resolution
- topDegeneretteByLevel is purely decorative state (DGN-03 INFO) -- could be removed for gas optimization but provides frontend display value
- DGN-01 off-by-one is a FALSE POSITIVE: the 1-wei sentinel pattern in claimableWinnings (DG:1367) means the <= check correctly prevents zeroing the slot, preserving gas optimization

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all sections contain verified code citations, no placeholder data.

## Next Phase Readiness

- _addClaimableEth cross-contract comparison provides complete picture for consolidated findings (Phase 89)
- Activity score and ROI calculation documented for any future economic analysis
- 6 Informational findings documented (DGN-02 through DGN-07); DGN-01 withdrawn; none blocking

## Self-Check: PASSED

- audit/v4.0-other-jackpots-degenerette.md: FOUND (440 lines, 133 citations)
- Commit fce52ab0: FOUND

---
*Phase: 87-other-jackpots*
*Completed: 2026-03-23*
