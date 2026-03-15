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

## Milestone: v1.2 — RNG Security Audit

**Shipped:** 2026-03-14
**Phases:** 4 | **Plans:** 10

### What Was Built
- 8 RNG audit documents (3,502 lines) covering every VRF-related variable, function, and manipulation window
- Complete inventory: 9 direct RNG variables, 22 influencing variables, 60+ functions, 27 entry points, 7 guard types
- Delta verification: all 8 v1.0 attack scenarios re-verified (all PASS), 88 hunks across 11 files assessed
- Adversarial analysis: 13 manipulation windows analyzed — 4 BLOCKED, 9 SAFE BY DESIGN, 0 EXPLOITABLE
- Deep-dive: ticket creation end-to-end trace, mid-day RNG flow, coinflip lock timing alignment

### What Worked
- Foundation-first phase ordering (inventory → delta → windows → deep-dive) meant each phase consumed the previous as input with zero backtracking
- 8-field per-consumption-point template created consistent analysis structure across all 17 RNG points — enabled clean verdict consolidation
- Auto-chain execution across all 10 plans — 4 phases completed in ~2 hours with no manual intervention between plans
- Phase 12's cross-reference matrix (27 entry points x variables) directly fed Phase 14's window analysis without re-reading contracts

### What Was Inefficient
- Summary one-liner extraction still returning null from CLI tooling (third milestone with this issue)
- Phase 15 ROADMAP plan checkboxes still showing `[ ]` despite completed plans (same cosmetic issue as v1.1)
- Integration checker flagged cosmetic "findings" (missing advisory labels, conservative variable counts) that were noise, not substance

### Patterns Established
- Adversarial analysis template: per-consumption-point window → block builder timeline → inter-block gaps → consolidated verdict table
- "Structural commit-reveal" framing for buffer-based RNG isolation — security argument based on buffer isolation, not entropy secrecy
- Three-source requirement verification: VERIFICATION.md + SUMMARY frontmatter + REQUIREMENTS.md traceability

### Key Lessons
1. Audit documentation phases execute fastest of all milestone types (~3-5min per plan avg) — inventory and analysis are parallel-friendly
2. Integration checker severity calibration needs work — "cosmetic" findings create noise that the user has to manually dismiss
3. For RNG security specifically, structural protections (locks, buffers, atomic operations) are more convincing than probabilistic arguments — lead with mechanism, not math

### Cost Observations
- Model mix: 100% opus (quality profile)
- Sessions: ~4 (planning + 2 execution + audit/completion)
- Notable: 10 plans in ~2 hours; research was the bottleneck for Phases 14-15

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 5 | 8 | Bottom-up phase ordering with harness-per-phase testing |
| v1.1 | 6 | 15 | Research-then-document pattern, auto-chain execution for independent plans |
| v1.2 | 4 | 10 | Foundation-first audit ordering, 8-field per-consumption-point template |

### Cumulative Quality

| Milestone | Output | Audit Score | Tech Debt Items |
|-----------|--------|-------------|-----------------|
| v1.0 | 66 tests, +1,921 LOC | 8/8 requirements | 54 legacy shims |
| v1.1 | 13 docs, 8,511 lines | 44/44 reqs, 51/51 truths | 3 readability + 8 cosmetic |
| v1.2 | 8 docs, 3,502 lines | 20/20 reqs, 39/39 truths | 0 |

### Top Lessons (Verified Across Milestones)

1. Storage-first / foundation-first ordering pays off across all milestone types — code (v1.0), docs (v1.1), and audit (v1.2) all benefited
2. The documentation pass is itself a verification step — formula errors caught during v1.1 write-up, counting errors during v1.0 planning, code references verified during v1.2 audit
3. Summary one-liner extraction from CLI still broken — 3 milestones running, still returns null
4. Integration checker cosmetic findings are noise — user dismissed all non-substantive findings in v1.2; calibrate severity threshold
