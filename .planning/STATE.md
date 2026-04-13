---
gsd_state_version: 1.0
milestone: v27.0
milestone_name: Call-Site Integrity Audit
status: verifying
stopped_at: Completed 223-02-PLAN.md — v27.0 Call-Site Integrity Audit SHIPPED
last_updated: "2026-04-13T02:31:51.576Z"
last_activity: 2026-04-13
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 9
  completed_plans: 9
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-12)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 223 — findings-consolidation

## Current Position

Phase: 223 (findings-consolidation) — EXECUTING
Plan: 2 of 2
Milestone: v27.0 — Call-Site Integrity Audit
Status: Phase complete — ready for verification
Last activity: 2026-04-13

Progress: [█████     ] 50% (2/4 phases — Phase 222 still executing)

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
- [Phase 221-raw-selector-calldata-audit]: [Phase 221-01]: Raw selector gate mirrors Phase 220 architecture (bash+awk, CONTRACTS_DIR override, PASS/FAIL stdout) — 194 lines, 5 patterns, sibling of check-interfaces/check-delegatecall.
- [Phase 221-raw-selector-calldata-audit]: [Phase 221-01]: JUSTIFIED_FEEDERS content-based allowlist (entry: DegenerusAdmin.sol:transferAndCall) silences the 2 Chainlink ERC-677 abi.encode feeders at lines 911,997 — no contract edits required. Entry + inline  marker are both diff-visible override paths.
- [Phase 221-raw-selector-calldata-audit]: [Phase 221-02]: 221-01-AUDIT.md (202 lines) enumerates all 5 cataloged sites with 5 JUSTIFIED INFO verdicts (3 Chainlink mocks + 2 DegenerusAdmin transferAndCall feeders); CSI-04/CSI-05 SATISFIED BY ABSENCE with embedded reproduction greps; 6 finding IDs (INFO-221-01-01..06) ready for Phase 223 rollup. Phase 221 closed.
- [Phase 221-raw-selector-calldata-audit]: [Phase 221-02]: Added INFO-221-01-06 as standalone finding ID for the regex-gate coverage limit (T-221-01) — gives Phase 223 a clean INFO row to promote rather than burying the accepted residual risk in Known Limits prose.
- [Phase 221-raw-selector-calldata-audit]: [Phase 221-02]: Pattern E sites recorded with opener-line + payload-line pair (DegenerusAdmin.sol:911 opener / :914 payload) so both gate output (opener-anchored) and source search (abi.encode-anchored) resolve to the same catalog row.
- [Phase 222-external-function-coverage-gap]: [Phase 222-01]: FuturepoolSkim.t.sol rewrite reduced D-02 full-pipeline tests to advanceGame() smoke + pure-math coverage because pre-existing OnlyGame() revert chain (_emitDailyWinningTraits uses .delegatecall instead of IDegenerusGame(address(this)).emitDailyWinningTraits self-call) blocks any integration test from reaching _consolidatePoolsAndRewardJackpots. D-03 forbids the contract fix in Plan 222-01; flagged as user-decision blocker for Plan 222-02.
- [Phase 222-external-function-coverage-gap]: [Phase 222-01]: patchContractAddresses.js regex extended to match multi-line address constant format introduced by "no wxrp" refactor — pre-existing infrastructure bug that broke every DeployProtocol-based test at setUp(). Regex fix is in scripts/ scope (allowed), not in contracts/ (forbidden).
- [Phase 222-external-function-coverage-gap]: [Phase 222-01]: Coverage matrix produced at file-level branch-coverage granularity (--report summary). Per-function lcov granularity deferred to Plan 222-02 because lcov run takes ~45 min per iteration. Matrix classifies 308 external/public functions across 24 deployable contracts: 0 COVERED / 196 CRITICAL_GAP / 112 EXEMPT. CRITICAL_GAP count inflated by pre-existing OnlyGame() issue — Plan 222-02 will need user approval to fix the delegatecall-vs-self-call bug to close gaps honestly.
- [Phase 222-external-function-coverage-gap]: [Phase 222-01]: `forge coverage --report summary --ir-minimum` is the workaround for default profile `via_ir = true` triggering stack-too-deep inside the instrumenter. Per Foundry docs this may produce slightly imprecise source mappings — matrix should be regenerated when via_ir cleanup lands or a dedicated [profile.coverage] block is added.
- [Phase 222-02]: 19 CRITICAL_GAPs promoted to COVERED post-e4064d67 via 50% file-level branch threshold crossing on DegenerusJackpots/AdvanceModule/JackpotModule/MintModule
- [Phase 222-02]: lcov FNDA invocation overlay subdivides 177 remaining gaps into 72 invoked + 105 never-invoked — drives Test Ref column precisely
- [Phase 222-02]: 76 leverage-first integration tests in CoverageGap222.t.sol close 177 CRITICAL_GAPs via natural caller chains — one focused test per guarded-entry group closes multiple gaps per D-13/D-14
- [Phase 222-02]: Standalone coverage-check Makefile target NOT a prereq of test-foundry/test-hardhat (D-16) because forge coverage --ir-minimum is ~8 min wall-clock
- [Phase 223]: [Phase 223-01]: 16 F-27-NN findings consolidated (6 Phase 220 + 5 Phase 221 + 5 Phase 222); fold WR-222-02/04/Gap1 into F-27-13, WR-222-03/Gap2 into F-27-14; resolution SHAs f799da98 + ef83c5cd + e0a1aa3e embedded
- [Phase 223]: [Phase 223-01]: v25.0 regression appendix verified 12 HOLDS + 1 SUPERSEDED (F-25-09 deity-boon fallback moved from AdvanceModule._deityDailySeed to DegenerusGame.deityBoonData; same no-VRF tier-3 semantics); no FIXED or INVALIDATED entries; no v26.0 regression needed (no separate FINDINGS-v26.0.md doc)
- [Phase 223]: [Plan 223-02]: Promoted 3 KNOWN-ISSUES entries — F-27-12 (VRF_KEY_HASH regex), F-27-05 (parallel-make race), and combined F-27-13 + F-27-14 (VERIFICATION gap closures); F-27-15 deferred as forward-looking gate proposal rather than design decision
- [Phase 223]: [Plan 223-02]: Preserved v27.0 Goal/Target-scope/Incident-context narrative verbatim when migrating Current Milestone to Completed Milestone in PROJECT.md; zero substantive content dropped
- [Phase 223]: [Plan 223-02]: CONTEXT D-09 stale counts (4 phases / 7 plans / ~15 tasks) superseded by actuals (4 phases / 9 plans / 23 tasks) derived from plan task-tag counts; D-09 predated the 222-03 gap-closure plan
- [Phase 223]: [Plan 223-02]: v27.0 Call-Site Integrity Audit SHIPPED 2026-04-13 — all 14/14 CSI-NN requirements Complete, all 4 ROADMAP success criteria met, 16 INFO findings consolidated, 3 new KNOWN-ISSUES entries

### Pending Todos

- Plan 222-02: user approval needed to fix `_emitDailyWinningTraits` to use `IDegenerusGame(address(this)).emitDailyWinningTraits` self-call so CRITICAL_GAP integration tests can actually reach the functions. Without this fix, Plan 222-02's gap-closing test queue will be blocked at the same place Plan 222-01 was blocked.

### Blockers/Concerns

- ContractAddresses.sol has unstaged changes (different deploy addresses) — stash before test/tool runs
- **Pre-existing `OnlyGame()` revert chain** in `_emitDailyWinningTraits` delegatecall path blocks integration tests from reaching consolidation. Plan 222-02 needs user approval for the 5-line contract fix (delegatecall → self-call).

## Session Continuity

Last session: 2026-04-13T02:31:51.573Z
Stopped at: Completed 223-02-PLAN.md — v27.0 Call-Site Integrity Audit SHIPPED
