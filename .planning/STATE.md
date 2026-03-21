---
gsd_state_version: 1.0
milestone: v3.4
milestone_name: New Feature Audit — Skim Redesign + Redemption Lootbox
status: unknown
stopped_at: Completed 53-01-PLAN.md (consolidated findings)
last_updated: "2026-03-21T20:55:57.196Z"
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 10
  completed_plans: 10
---

# State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-21)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** Phase 53 — consolidated-findings

## Current Position

Phase: 53 (consolidated-findings) — EXECUTING
Plan: 1 of 1

## Accumulated Context

### Decisions

See PROJECT.md Key Decisions table.

v3.4 context:

- Skim redesign: 5-step pipeline (deterministic bps, additive random, uncapped take, triangular variance, 80% cap + overshoot surcharge)
- Redemption lootbox: 50/50 split with 160 ETH daily cap per wallet (commit 3ebd43b5)
- 22 existing fuzz tests in FuturepoolSkim.t.sol — audit extends beyond existing coverage
- [Phase 50]: SKIM-06 SAFE: ETH conservation proven algebraically via T and I cancellation
- [Phase 50]: SKIM-07 SAFE: Insurance skim floor(N/100) exact above 100 wei, sub-100 unreachable
- [Phase 50]: SKIM-03 bit-field overlap classified INFO: modulo independence, not exploitable
- [Phase 50]: Division-by-zero in ratio calc (L1001) classified SAFE: calling context guarantees nextPoolBefore > 0
- [Phase 51]: REDM-03 SAFE: 160 ETH cumulative cap check before uint96 cast; REDM-05 SAFE: 96+96+48+16=256 bits; INFO-01: burnieOwed lacks explicit cap
- [Phase 51]: REDM-01 SAFE: 50/50 split conservation proven algebraically
- [Phase 51]: REDM-02 SAFE: gameOver bypass confirmed pure ETH/stETH, no lootbox or BURNIE
- [Phase 51]: INFO finding: rounding dust in pendingRedemptionEthValue (negligible, no action)
- [Phase 51]: REDM-04 SAFE: activity score snapshot immutable from write through consumption across 3 contracts
- [Phase 50]: Level-1 overshoot firing classified as acceptable behavior — ETH stays within system per SKIM-06 conservation
- [Phase 50]: F-50-03 INFO: test_level1_overshootDormant uses unreachable lastPool=0; recommend production-realistic test
- [Phase 51]: REDM-06-A classified as MEDIUM: unchecked underflow corrupts accounting but cannot be exploited for direct theft
- [Phase 52]: Extended FuturepoolSkimTest with INV-named tests using property-based fuzz pattern; widened lastPool to 0 for level-1 edge case coverage
- [Phase 52]: INV-03 split conservation: lootboxEth >= ethDirect (floor division gives lootbox the extra wei for odd totals)
- [Phase 53]: Assigned global IDs F-51-01 and F-51-02 to resolve Phase 51 INFO-01 collision; confirmed 6 v3.4 findings (1 MEDIUM + 5 INFO); carried 30 v3.2 findings inline for self-contained deliverable

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-03-21T20:55:57.192Z
Stopped at: Completed 53-01-PLAN.md (consolidated findings)
Resume file: None
