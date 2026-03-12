# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Always-Open Purchases

**Shipped:** 2026-03-11
**Phases:** 5 | **Plans:** 8

### What Was Built
- Double-buffered ticket queue (bit-23 key encoding) so purchases never block during RNG
- Packed prize pools (uint128+uint128) saving 1 SSTORE per purchase
- Prize pool freeze/unfreeze with pending accumulators across 5 jackpot days
- advanceGame rewritten with mid-day swap path and pre-RNG drain gate
- 6 rngLockedFlag purchase-path guards removed — always-open purchases live
- 66 milestone-specific tests across 5 harness contracts

### What Worked
- Bottom-up phase ordering (storage → queue → freeze → orchestration → removal) meant each phase had stable foundations
- Building-block test harnesses (StorageHarness, QueueHarness, FreezeHarness, AdvanceHarness, LockRemovalHarness) avoided complex delegatecall mocking
- Legacy shim pattern allowed incremental migration without breaking compilation at any intermediate step
- Tight 2-hour execution window for all 8 plans — minimal context switching

### What Was Inefficient
- REQUIREMENTS.md documented "9 purchase-path pool addition sites" but correct count was 7 — caused brief confusion during Phase 3 planning
- Some summary one-liners not populated by the CLI tooling (null returns from summary-extract)

### Patterns Established
- `prizePoolFrozen` branch pattern: `if (frozen) → pending pools, else → live pools` — consistent across all 7 sites
- Single freeze entry point (`_swapAndFreeze` at RNG break), triple unfreeze exits — auditable by grep
- Test harness per phase, each extending `DegenerusGameStorage` directly for clean isolation

### Key Lessons
1. In delegatecall module architectures, storage changes must come first — all modules compile storage into their bytecode
2. Compatibility shims (marked DEPRECATED) are cheap insurance during multi-phase migrations — remove them in a dedicated cleanup phase, not mid-flight
3. Counting invariants in requirements docs should be verified against code before planning begins — "9 sites" vs "7 sites" confusion was avoidable

### Cost Observations
- Model mix: 100% opus (quality profile)
- Sessions: ~4 (planning + 2 execution + audit)
- Notable: All 5 phases executed in a single session (~2 hours wall clock)

---

## Milestone: v1.1 — Economic Flow Analysis

**Shipped:** 2026-03-12
**Phases:** 6 | **Plans:** 15

### What Was Built
- 13 reference documents (8,511 lines) covering every economic flow in the protocol
- ETH inflows mapped across all 9 purchase paths with exact Solidity cost formulas
- Complete jackpot mechanics — purchase-phase drip, 5-day draws, BAF/Decimator transitions with worked examples
- BURNIE token economy — coinflip house edge derivation, supply invariant, all earning/burning paths
- Full price curve, activity scores, death clock, and terminal distribution
- All reward modifiers — DGNRS tokenomics, deity boons, affiliates, stETH yield, quests
- Master parameter reference consolidating ~200+ protocol constants

### What Worked
- Research-then-document pattern: each phase started with contract source research, then produced a focused reference doc — no backtracking
- Constant cross-reference tables with exact file:line citations — caught 3 research-note errors during documentation (lazy pass cost, lootbox max BPS, cumulative deity pass price)
- Parallel execution of Phase 10's 5 plans — independent subsystems (DGNRS, deity, affiliate, stETH, quests) had zero cross-plan dependencies
- Pitfall callout boxes and worked examples proved their value during audit — every "critical pitfall" mapped to a must-have truth

### What Was Inefficient
- ROADMAP.md plan checkboxes not auto-updated by executor — phases 7-11 all showed `[ ]` despite completed plans (cosmetic tech debt flagged by audit)
- Phase 11 Nyquist validation incomplete — rushed to finish without running `/gsd:validate-phase 11`
- Summary one-liner extraction still returning null from CLI tooling (same issue as v1.0)

### Patterns Established
- Agent-consumable doc format: section per mechanic → formula box → pitfall callouts → worked example → constant cross-reference
- 3-scenario probability columns (all boons / no-decimator / no-decimator-no-deity) for complete agent coverage
- Explicit unit disambiguation: BPS vs PPM vs ETH vs BURNIE in all tables, with scale notes on adjacent rows

### Key Lessons
1. Research notes are drafts, not source of truth — 3 formula corrections caught during documentation prove the write-up phase itself is a verification step
2. Documentation milestones execute ~4x faster per plan than code milestones (~4min vs ~15min avg) — plan accordingly
3. Auto-chain execution is ideal for documentation phases with no cross-plan dependencies — Phase 10 (5 plans) completed in ~14 minutes total

### Cost Observations
- Model mix: 100% opus (quality profile)
- Sessions: ~6 (research + planning + 3 execution + audit)
- Notable: 15 plans in ~1 hour wall clock; research phases were the bottleneck, not documentation

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 5 | 8 | Bottom-up phase ordering with harness-per-phase testing |
| v1.1 | 6 | 15 | Research-then-document pattern, auto-chain execution for independent plans |

### Cumulative Quality

| Milestone | Output | Audit Score | Tech Debt Items |
|-----------|--------|-------------|-----------------|
| v1.0 | 66 tests, +1,921 LOC | 8/8 requirements | 54 legacy shims |
| v1.1 | 13 docs, 8,511 lines | 44/44 reqs, 51/51 truths | 3 readability + 8 cosmetic |

### Top Lessons (Verified Across Milestones)

1. Storage-first in delegatecall architectures — validated by zero compilation failures across 5 phases
2. The documentation pass is itself a verification step — formula errors caught during v1.1 write-up, counting errors caught during v1.0 planning
3. Summary one-liner extraction from CLI still broken — needs investigation before v1.2
