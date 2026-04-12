---
gsd_state_version: 1.0
milestone: v27.0
milestone_name: Call-Site Integrity Audit
status: verifying
stopped_at: Completed 220-02-PLAN.md — CSI-02 satisfied. Phase 220 is done (CSI-01/CSI-02/CSI-03 all Complete). validate_mapping preflight added, 10-row mapping table proves 9 LIVE + 1 DEAD split. Ready for Phase 221 (raw selector audit) or 222 (coverage gap).
last_updated: "2026-04-12T10:43:09.813Z"
last_activity: 2026-04-12
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-12)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 220 — delegatecall-target-alignment

## Current Position

Phase: 221
Plan: Not started
Milestone: v27.0 — Call-Site Integrity Audit
Status: Phase complete — ready for verification
Last activity: 2026-04-12

Progress: [██▌       ] 25% (1/4 phases)

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
- [Phase 220-02]: Paired exception maps keyed on opposite ends (NAMING_EXCEPTIONS + REVERSE_NAMING_EXCEPTIONS) handle the GameOver CamelCase corner case in both directions with O(1) lookups and a symmetric diff visible in a single script.
- [Phase 220-02]: DEAD_CONSTANTS=(GAME_ENDGAME_MODULE) allowlist instead of removing the dead constant. Per feedback_no_contract_commits; Phase 223 will surface the INFO finding for user review. Visible-diff property mitigates allowlist abuse (T-220-07).
- [Phase 220-02]: Preflight-then-per-site gate architecture: validate_mapping runs BEFORE collect_sites so universe-level drift fails fast with precise error instead of misleading per-site output. Pattern published for future CSI-* phases (221, 222).

### Pending Todos

None.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test/tool runs
- `test/fuzz/FuturepoolSkim.t.sol` has a known compile error (`_applyTimeBasedFutureTake` undeclared identifier) that blocks `forge coverage`; fix is scheduled in Phase 222 (CSI-08)

## Session Continuity

Last session: 2026-04-12T10:29:21.060Z
Stopped at: Completed 220-02-PLAN.md — CSI-02 satisfied. Phase 220 is done (CSI-01/CSI-02/CSI-03 all Complete). validate_mapping preflight added, 10-row mapping table proves 9 LIVE + 1 DEAD split. Ready for Phase 221 (raw selector audit) or 222 (coverage gap).
