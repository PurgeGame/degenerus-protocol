---
gsd_state_version: 1.0
milestone: v27.0
milestone_name: Call-Site Integrity Audit
status: executing
stopped_at: Completed 220-01-PLAN.md — CSI-01 & CSI-03 satisfied; script at 170 lines, gate passes clean tree (43/43 ALIGNED), negative test proven via /tmp fixture. Ready for 220-02 endgame-dead-constant plan.
last_updated: "2026-04-12T10:16:47.342Z"
last_activity: 2026-04-12
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 2
  completed_plans: 1
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-12)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 220 — delegatecall-target-alignment

## Current Position

Phase: 220 (delegatecall-target-alignment) — EXECUTING
Plan: 2 of 2
Milestone: v27.0 — Call-Site Integrity Audit
Status: Ready to execute
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
- [Phase 220]: [220-01]: Single naming exception GameOverModule -> GAMEOVER_MODULE. All 8 other interfaces conform to CamelCase -> UPPER_SNAKE. Exception map keyed by stripped suffix is the source of truth for both directions (iface_to_constant and 220-02's reverse).
- [Phase 220]: [220-01]: check-delegatecall gate operates on source text (no forge build prereq). Runs under 1s vs check-interfaces ~10s. Exit 0 on clean, exit 1 on any FAIL or WARN. Orphan selectors also block to catch dead code.
- [Phase 220]: [220-01]: CONTRACTS_DIR env var pattern established for future gates — scripts must support overriding target tree so negative tests run in /tmp without touching contracts/. Honors feedback_no_contract_commits.

### Pending Todos

None.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test/tool runs
- `test/fuzz/FuturepoolSkim.t.sol` has a known compile error (`_applyTimeBasedFutureTake` undeclared identifier) that blocks `forge coverage`; fix is scheduled in Phase 222 (CSI-08)

## Session Continuity

Last session: 2026-04-12T10:16:47.338Z
Stopped at: Completed 220-01-PLAN.md — CSI-01 & CSI-03 satisfied; script at 170 lines, gate passes clean tree (43/43 ALIGNED), negative test proven via /tmp fixture. Ready for 220-02 endgame-dead-constant plan.
