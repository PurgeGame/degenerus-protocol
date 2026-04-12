---
gsd_state_version: 1.0
milestone: v27.0
milestone_name: Call-Site Integrity Audit
status: active
stopped_at: Phase 220 — Delegatecall Target Alignment (Not started)
last_updated: "2026-04-12T12:00:00.000Z"
last_activity: 2026-04-12 -- v27.0 roadmap locked, 4 phases defined (220-223)
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-12)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** v27.0 Call-Site Integrity Audit — surface runtime call-site-to-implementation mismatches (mintPackedFor-class bugs)

## Current Position

Phase: Phase 220 — Delegatecall Target Alignment (Not started)
Plan: —
Milestone: v27.0 — Call-Site Integrity Audit
Status: Not started
Last activity: 2026-04-12

Progress: [          ] 0% (0/4 phases)

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v26.0]: Jackpot split into main (ETH, current-level tickets, main traits) and bonus (BURNIE, future-level tickets, independent trait roll)
- [v26.0]: Bonus near-future range [lvl+1, lvl+4] — lvl parameter IS purchaseLevel in both phases (level already incremented at RNG request time during jackpot transition)
- [v26.0]: No storage for bonus traits — derive inline from randWord via keccak256, emit event only
- [v26.0]: Carryover uses bonus traits (draws from future-level tickets)
- [v26.0]: Early-bird lootbox unchanged (own per-winner trait selection, already draws from lvl+1)
- [v26.0]: Reuse existing JackpotBurnieWin event for individual bonus winners
- [v26.0]: DailyWinningTraits event (richer than spec) replaces BonusWinningTraits — includes both main and bonus trait sets
- [v26.0]: Level-1 branch skips payDailyJackpot, runs double payDailyCoinJackpot with salted rngWord for entropy independence
- [v27.0]: Scope bounded to call-site integrity — storage layout (done v25.0), deployed bytecode (requires RPC infra), and revert specificity (debuggability) are explicitly out of scope
- [v27.0]: `is IDegenerusGame` compile-time inheritance not adopted — high mechanical cost (~57 `override` additions) against existing `check-interfaces` Makefile gate that catches the same class; reconsider only if the gate ever produces false negatives

### Pending Todos

None.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test/tool runs
- `test/fuzz/FuturepoolSkim.t.sol` has a known compile error (`_applyTimeBasedFutureTake` undeclared identifier) that blocks `forge coverage`; fix is scheduled in Phase 222 (CSI-08)

## Session Continuity

Last session: 2026-04-12
Stopped at: v27.0 roadmap locked — 4 phases (220-223), 14 CSI requirements mapped, all 14/14 coverage validated. Ready to plan Phase 220.
