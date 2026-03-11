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

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 5 | 8 | Bottom-up phase ordering with harness-per-phase testing |

### Cumulative Quality

| Milestone | Tests | Milestone-Specific | Pre-existing Failures |
|-----------|-------|-------------------|----------------------|
| v1.0 | 109 pass | 66 | 12 (deploy-dependent) |

### Top Lessons (Verified Across Milestones)

1. Storage-first in delegatecall architectures — validated by zero compilation failures across 5 phases
