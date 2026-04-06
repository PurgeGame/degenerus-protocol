---
phase: 197-payout-reference-event-catalog
plan: 01
subsystem: documentation
tags: [jackpot, payout, events, audit-reference, post-split]
dependency_graph:
  requires: []
  provides: [DOC-01, DOC-02]
  affects: []
tech_stack:
  added: []
  patterns: [markdown-reference-docs]
key_files:
  created:
    - docs/JACKPOT-PAYOUT-REFERENCE.md
    - docs/JACKPOT-EVENT-CATALOG.md
  modified: []
decisions:
  - Corrected event names to match actual contract code (JackpotTicketWinner, not plan-hypothesized JackpotEthWin/JackpotBurnieWin/JackpotDgnrsWin)
  - Corrected max winner constants (DAILY_ETH_MAX_WINNERS=321, JACKPOT_MAX_WINNERS=300, DAILY_JACKPOT_SCALE_MAX_BPS=66667) from plan values (305, 160, 63600)
  - Documented that decimator resolution has no event (silent snapshot, claim-based)
  - Documented that DGNRS reward has no dedicated jackpot event (uses token Transfer)
  - Documented 9 actual events instead of plan's 12 hypothetical events
metrics:
  duration_seconds: 593
  completed: 2026-04-06T23:58:09Z
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 197 Plan 01: Payout Reference & Event Catalog Summary

Documentation-only phase creating two standalone reference documents for jackpot payouts and events, verified against post-split contract source at commit f0dc4c99.

## Commits

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Create jackpot payout reference (DOC-01) | `ccde4c2f` | docs/JACKPOT-PAYOUT-REFERENCE.md |
| 2 | Create jackpot event catalog (DOC-02) | `0e24baaa` | docs/JACKPOT-EVENT-CATALOG.md |

## What Was Built

**docs/JACKPOT-PAYOUT-REFERENCE.md** (18.7 KB) -- Complete payout reference for all 7 jackpot types:
- Daily Normal (1-4), Daily Final (5), x10/x100 multiplied, Trait (early-burn), Early-Bird Lootbox (day 1), Terminal (game over), Decimator, BAF, BURNIE Coin
- Each type includes: trigger, pool source, winner selection, payout formula, and events emitted
- Constants table with all 19 payout-affecting values
- Pool flow summary table mapping source pools to payout paths
- Two-call split architecture section with stage machine flow and inter-call state

**docs/JACKPOT-EVENT-CATALOG.md** (13.9 KB) -- Event catalog for 9 jackpot-related events:
- JackpotTicketWinner, FarFutureCoinJackpotWinner, AutoRebuyProcessed (2 declarations), RewardJackpotsSettled (2 declarations), Advance, DecBurnRecorded, TerminalDecBurnRecorded
- Each event: full Solidity signature, field description table, emitting paths with function names and line numbers
- Event-to-Path Matrix cross-referencing all 7 jackpot types
- Cross-consistency check confirming all events in payout reference appear in catalog

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected event names to match actual contract**
- **Found during:** Task 1
- **Issue:** Plan referenced events that do not exist in the contract: `JackpotEthWin`, `JackpotWhalePassWin`, `JackpotBurnieWin`, `JackpotDgnrsWin`, `JackpotTicketWin`, `DecimatorResolved`. The actual contract uses a unified `JackpotTicketWinner` event for both ETH and BURNIE payouts. There are no dedicated events for whale pass awards, DGNRS transfers, or decimator resolution.
- **Fix:** Documented the 9 actual events from contract source instead of the 12 hypothetical events from the plan. Added notes explaining which plan-expected events don't exist and why.
- **Files modified:** docs/JACKPOT-PAYOUT-REFERENCE.md, docs/JACKPOT-EVENT-CATALOG.md

**2. [Rule 1 - Bug] Corrected constant values to match actual contract**
- **Found during:** Task 1
- **Issue:** Plan stated DAILY_ETH_MAX_WINNERS=305, JACKPOT_MAX_WINNERS=160, DAILY_JACKPOT_SCALE_MAX_BPS=63600. Actual contract values: 321, 300, 66667.
- **Fix:** Used actual contract constant values throughout both documents.
- **Files modified:** docs/JACKPOT-PAYOUT-REFERENCE.md

**3. [Rule 1 - Bug] Corrected two-call split architecture description**
- **Found during:** Task 1
- **Issue:** Plan described `STAGE_JACKPOT_ETH_RESUME` (stage 8) and `resumeEthPool` for a two-call ETH split. These don't exist. The actual split is ETH (Call 1) + Coin/Tickets (Call 2), not ETH-part1 + ETH-part2.
- **Fix:** Documented the actual split architecture: `payDailyJackpot` handles all ETH in one call, `payDailyJackpotCoinAndTickets` handles coin+tickets in Call 2.
- **Files modified:** docs/JACKPOT-PAYOUT-REFERENCE.md

## Known Stubs

None -- both documents are complete and self-contained.

## Verification Results

All 5 verification criteria pass:
1. Both files exist in docs/ directory
2. Payout reference covers all 7 jackpot types with trigger, pool source, winners, formula, events
3. Event catalog covers all 9 actual events (7 unique signatures) with signatures, fields, paths, line numbers
4. Cross-reference: every event named in payout reference appears in catalog
5. Constants match current contract source (DAILY_ETH_MAX_WINNERS=321, JACKPOT_MAX_WINNERS=300, DAILY_JACKPOT_SCALE_MAX_BPS=66667)
