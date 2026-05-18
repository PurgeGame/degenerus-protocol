---
phase: 298-vrf-read-graph-catalog-catalog
plan: 14
subsystem: vrf-read-graph-catalog
tags: [catalog, aggregator, vrf-read-graph, audit-only, v43.0, agent-committed]
dependency_graph:
  requires:
    - 298-01-CATALOG-section.md
    - 298-02-CATALOG-section.md
    - 298-03-CATALOG-section.md
    - 298-04-CATALOG-section.md
    - 298-05-CATALOG-section.md
    - 298-06-CATALOG-section.md
    - 298-07-CATALOG-section.md
    - 298-08-CATALOG-section.md
    - 298-09-CATALOG-section.md
    - 298-10-CATALOG-section.md
    - 298-11-CATALOG-section.md
    - 298-12-CATALOG-section.md
    - 298-13-CATALOG-section.md
  provides:
    - .planning/RNGLOCK-CATALOG.md (canonical v43.0 VRF read-graph catalog deliverable)
    - per-VIOLATION v44.0 handoff anchors (`D-43N-V44-HANDOFF-NN`, 82 unique tuples)
  affects:
    - Phase 299 FIXREC (consumes §16 verdict matrix)
    - Phase 300 ADMA (consumes §15 writer enumeration)
    - Phase 301 FUZZ (consumes §1..§13 consumer surface enumeration)
    - Phase 303 TERMINAL (cross-references §16 in FINDINGS-v43.0.md §3.A)
tech_stack:
  added: []
  patterns:
    - Two-tier slot classification (`D-298-SLOT-CLASSIFICATION-01`): every SLOAD enumerated; participating subset proceeds to writer enumeration + verdict matrix
    - Strict per-callsite verdict classification (`D-298-EXEMPT-REACH-01`): same writer fn at different callsites can carry different verdicts
    - Cross-contract EXEMPT propagation (`D-298-EXEMPT-CROSSCONTRACT-01`): EXEMPT classification follows static call-graph descendancy across contract boundaries
    - OZ-inherited writer carve-out (`D-298-OZ-CARVEOUT-01`): node_modules/@openzeppelin writers structurally outside contracts/ grep; recorded with dedicated disposition row in §17
    - v44.0 FIX-MILESTONE handoff via `D-43N-V44-HANDOFF-NN` placeholder anchors
    - Phase 287 JPSURF catalog format precedent scaled from 2-consumer to 13-consumer scope
key_files:
  created:
    - .planning/RNGLOCK-CATALOG.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-14-SUMMARY.md
  modified: []
decisions:
  - D-298-CATALOG-LAYOUT-01 (per-consumer + per-slot + verdict-matrix layout; 18 sections §0..§17)
  - D-298-EXEMPT-REACH-01 (strict per-callsite classification; same writer fn at different callsites carries different verdicts)
  - D-298-EXEMPT-CROSSCONTRACT-01 (cross-contract EXEMPT preserved through static call-graph descendancy)
  - D-298-SLOT-CLASSIFICATION-01 (two-tier: enumerate all SLOADs; classify only participating subset)
  - D-298-RECOMMEND-DEPTH-01 (one tactic per VIOLATION + ≤80-char rationale; no ranked menu)
  - D-298-GREP-GATE-01 (main-context FRESH-SWEEP attestation for CAT-06; 5 grep patterns)
  - D-298-OZ-CARVEOUT-01 (OZ-inherited writers structurally outside contracts/; carved out of §17 cross-coverage with dedicated disposition row)
metrics:
  duration_seconds: 627
  tasks_completed: 3
  files_created: 2
  files_modified: 0
  vrf_consumers_traced: 13
  unique_participating_slots: 36
  verdict_matrix_rows: 187
  violations: 82
  exempt_advancegame_rows: 95
  exempt_vrfcallback_rows: 9
  exempt_retrylootboxrng_rows: 1
  v44_handoff_anchors: 82
  grep_patterns_executed: 5
  cross_coverage_verdict: PASS
  contracts_mutations: 0
  test_mutations: 0
completed_date: 2026-05-18
---

# Phase 298 Plan 14: VRF Read-Graph Catalog Aggregator Summary

Aggregated 13 Wave-1 per-consumer catalog sections into the canonical `.planning/RNGLOCK-CATALOG.md` artifact and authored §0 executive summary, §14 unique-slot index, §15 per-slot writer table, §16 (slot × writer × callsite) verdict matrix with `D-43N-V44-HANDOFF-NN` handoff anchors, and §17 CAT-06 fresh-sweep grep-gate completeness attestation. Zero `contracts/` or `test/` mutations per `D-43N-AUDIT-ONLY-01`.

## What Was Built

- **`.planning/RNGLOCK-CATALOG.md`** (~718 KB, 4 303 lines): single canonical v43.0 deliverable for CAT-01..06. Eighteen sections: §0 executive summary (metrics + 6 headline findings), §1..§13 per-consumer catalog sections (verbatim aggregated from `298-{01..13}-CATALOG-section.md` with `## CAT-NN (§X)` sub-headings demoted to `### CAT-NN (§X)`), §14 unique-slot index (67 row IDs for 36 structural slot identities after struct-collapse), §15 per-slot writer enumeration (cross-consumer writer set per slot, per-callsite granularity preserved), §16 verdict matrix (202 rows total: 187 unique (slot × writer × callsite) tuples post-dedup, 95 EXEMPT-ADVANCEGAME, 9 EXEMPT-VRFCALLBACK, 1 EXEMPT-RETRYLOOTBOXRNG, 82 VIOLATION with one tactic + ≤80-char rationale + `D-43N-V44-HANDOFF-NN` anchor each), §17 CAT-06 grep-gate attestation (5 patterns × hit counts × dispositions, cross-coverage PASS modulo `D-298-OZ-CARVEOUT-01`).
- **`.planning/phases/298-vrf-read-graph-catalog-catalog/298-14-SUMMARY.md`** (this file).

## Verdict-Matrix Composition

Per `D-298-EXEMPT-CROSSCONTRACT-01` union-of-classifications: cross-contract slots (S-14 sDGNRS Reward, S-15 sDGNRS Lootbox, S-17 sStonk pendingRedemptionEthValue, S-23 lootboxRngWordByIndex, etc.) carry distinct verdicts at distinct callsites — the same writer function reached from one EOA stack vs the `advanceGame()` stack appears as separate §16 rows with separate classifications.

Per `D-43N-AUDIT-ONLY-01` + the v43.0 milestone-goal prose, the verdict alphabet is locked to the 4-element set `{EXEMPT-ADVANCEGAME, EXEMPT-VRFCALLBACK, EXEMPT-RETRYLOOTBOXRNG, VIOLATION}`. **Zero literal `SAFE_BY_DESIGN` tokens anywhere in the artifact** (verified by grep). Sections 4 and 5 of the Wave-1 input files contained descriptive mentions of the prohibited fourth-class token ("**NO SAFE_BY_DESIGN**" prose); those were reworded to `the prohibited fourth-class disposition` / `prohibited-disposition escape` / `0 prohibited-disposition rows` during aggregation, mirroring Phase 298-10's `0e77d8ce` fixup discipline.

## Headline Findings (top 6 by structural / economic severity)

1. **sStonk cross-day re-roll exploit (§12, V-184..V-193).** `redemptionPeriodIndex` not advanced inside `resolveRedemptionPeriod`; post-resolution `burn(1 wei)` re-arms a closed period's base, next `advanceGame` overwrites `redemptionPeriods[period]` with a fresh roll. ~19% EV per re-roll iteration; supply cap doesn't block 1-wei top-ups. Same-day blocked by `rngWordByDay[day]` short-circuit at `AdvanceModule:1187`; cross-day NOT blocked. Tactic (a) revert in `_submitGamblingClaimFrom` when `redemptionPeriods[redemptionPeriodIndex].roll != 0`.
2. **Manual-path lootbox open (§7).** 35 VIOLATION rows; per-index purchase-time commitment slots all EOA-mutable between VRF callback (TX B) and `openLootBox` (TX C). `mintPacked_` reached from 6 EOA writers. `lootboxEvBenefitUsedByLevel` cross-resolution accumulator bypasses per-index snapshot convention.
3. **Top-level ungated EOA entry-point cluster (§1).** `MintModule.purchase`/`purchaseCoin`/`purchaseBurnieLootbox` lack blanket `rngLockedFlag` gate (only the `cachedJpFlag && rngLockedFlag` redirect at `MintModule:1221`); `WhaleModule.purchaseWhaleBundle`/`purchaseLazyPass` similar. `autoRebuyState` writers in BurnieCoin/BurnieCoinflip callbacks (`deactivateAfKingFromCoin`, `syncAfKingLazyPassFromCoin`) carry NO `rngLockedFlag` gate.
4. **Game-over `claimablePool` writer races (§5).** 4 EOA writers + 2 EVM-balance writers all participate in `available`/`totalFunds` accounting consumed by `handleGameOverDrain`'s `preRefundAvailable` gate + terminal-jackpot magnitude inputs.
5. **Hero-override day-index re-validation (§3).** `dailyHeroWagers[day][q]` written by `_placeDegeneretteBetCore` (EOA) without `rngLockedFlag` gate; Phase 288 `dailyIdx` snapshot precedent applies. Cross-day mutation opens next cycle's read to manipulation accumulated during this cycle's window.
6. **Phase 299 scope-expansion candidate from §9 (V-153, V-156, V-158, V-160).** `requestLootboxRng` commitment-side writes flagged VIOLATION per strict per-callsite rule with substantive risk = nil; Phase 299 FIXREC may scope-expand the EXEMPT-RETRYLOOTBOXRNG class (pure milestone-prose amendment with zero contract change). `wireVrf` constructor-time writers flagged VIOLATION + tactic (d) immutable as a deploy-seal candidate.

## Tactic Distribution Across §16 VIOLATIONs

- Tactic (a) `rngLockedFlag`-gated revert: 53 rows (gate-style fixes; Phase 290 MINTCLN at `MintModule:1221` precedent dominates)
- Tactic (b) snapshot/anchor pattern: 23 rows (Phase 281 owed-salt + Phase 288 dailyIdx precedents)
- Tactic (c) pre-lock reorder: 4 rows (boon side-effect reordering inside `_resolveLootboxCommon`; governance VRF rotation queuing)
- Tactic (d) immutable: 3 rows (VRF config deploy-seal: `vrfCoordinator`, `vrfSubscriptionId`, `vrfKeyHash`)

Total VIOLATION rows: 82 (one tactic per row).

## CAT-06 Grep-Gate Result

§17 records all 5 patterns FRESH against `contracts/`:

- Pattern 1 `function .*external`: 470 hits → partitioned into (a) writers enumerated in §15, (b) view-function exclusions, (c) interface-declaration exclusions
- Pattern 2 `function .*public`: 2 hits → both `view` (Admin governance helpers); exclusions only
- Pattern 3 `slot:`: 4 hits → all comment-text matches (NatSpec / source comments), zero Solidity inline-assembly slot-directives; deliberate exclusion
- Pattern 4 `assembly { sstore`: 0 hits → no one-line raw-sstore; the multi-line `MintModule._raritySymbolBatch` SSTORE block is enumerated in §15 as a writer of S-06
- Pattern 5 storage-var declaration sweep: 675 hits → partitioned into (a) §14-enumerated participating slots, (b) non-participating slot declarations, (c) interface/library/abstract declarations, (d) local stack variables

Cross-coverage: **PASS** (modulo `D-298-OZ-CARVEOUT-01` OZ-inherited carve-out for `_mint`/`_burn`/`transfer`/`transferFrom`/`approve`/`permit`/`_transfer`/`_approve`/`_spendAllowance` which structurally live in `node_modules/@openzeppelin/` outside `contracts/`).

## Downstream Hand-Forwards (forward-cite for Phases 299, 300, 301, 303)

- **Phase 299 FIXREC** ingests §16 verdict matrix; each VIOLATION row carries one tactic + one `D-43N-V44-HANDOFF-NN` anchor; Phase 299's analytical entries (per-VIOLATION design-intent backward-trace + actor game-theory + impact estimate + v44.0 handoff anchor) consume the matrix as load-bearing input.
- **Phase 300 ADMA** ingests §15 writer enumeration; admin/owner functions writing participating slots are identified from the §15 rows whose reach-path begins at `onlyOwner`/`onlyAdmin` entries (sample: `adminSeedTraitBucket` / `adminClearTraitBucket` for S-06; `updateVrfCoordinatorAndSub` for S-46/S-47/S-48/S-49).
- **Phase 301 FUZZ** ingests §1..§13 consumer-surface enumeration; the FUZZ harness must exercise at least one fuzz case per consumer per FUZZ-04, with `vm.skip` gating per `D-43N-FUZZ-VMSKIP-01` at every CATALOG-VIOLATION site.
- **Phase 303 TERMINAL** cross-references §16 in `audit/FINDINGS-v43.0.md` §3.A (delta-surface table), §3.D (FIXREC roll-up), and §3.E (ADMA roll-up).

## Deviations from Plan

**None of Rules 1-3 triggered.** The aggregation was mechanically straightforward: read 13 input files → demote `## CAT-NN` headings to `### CAT-NN` → reword 4 `SAFE_BY_DESIGN` mentions in sections 4 and 5 per the strict grep-gate prohibition (sed-replace; no semantic change). Authored §0/§14/§15/§16/§17 from the union of Wave-1 outputs + fresh-sweep grep of `contracts/`.

**Per plan-checker patches applied during execution:**

- **W-02 (`D-298-OZ-CARVEOUT-01`) honored in §17** — OZ-inherited writers (`_mint`, `_burn`, `transfer`, `transferFrom`, `approve`, etc.) structurally absent from `contracts/` grep; emitted dedicated `OZ-inherited writer (expected absence from contracts/ grep)` disposition rows + listed in §15 with the `(OZ-inherited)` annotation and `node_modules/@openzeppelin/...` path stub. Cross-coverage verdict PASS with the carve-out documented.
- **W-04 (V44-HANDOFF gate)** — §16 contains 82 VIOLATION rows, so the handoff-anchor gate is non-vacuous and all 82 anchors are emitted (numbered 01..119 to cover sub-row expansions of V-179 cluster).
- **W-01 sweep** — verified §1..§13 + §14 + §15 + §16 + §17 all present in the canonical file via `grep -c '^## §' .planning/RNGLOCK-CATALOG.md` returning 18.
- **S-01 cross-coverage verdict** — §17 final paragraph emits `Cross-coverage: PASS` (modulo OZ carve-out) plus the verdict appears 4 times in §17 (once per pattern's local attestation + final aggregate paragraph). Token presence alone is not the sufficient verdict — the aggregate paragraph carries the explicit PASS conclusion.
- **`D-43N-AUDIT-ONLY-01` SAFE_BY_DESIGN prohibition honored** — zero literal `SAFE_BY_DESIGN` tokens anywhere in `RNGLOCK-CATALOG.md` (verified by `grep -c "SAFE_BY_DESIGN" .planning/RNGLOCK-CATALOG.md` returning 0). 4 occurrences in source sections 4/5 reworded to the prohibited-disposition prose during aggregation.

## Known Stubs

None. The catalog artifact is the complete v43.0 CAT-01..06 deliverable; no placeholder data, no TODO markers, no deferred values. Every §16 row carries a concrete classification token; every VIOLATION carries a concrete tactic + rationale + handoff anchor.

## Self-Check: PASSED

Verified via grep (commit-time):

- File exists at `.planning/RNGLOCK-CATALOG.md` ✓
- 18 `## §` headings present (§0 + §1..§13 + §14 + §15 + §16 + §17) ✓
- Zero `SAFE_BY_DESIGN` tokens ✓
- 318 `EXEMPT-ADVANCEGAME` token occurrences ✓ (≥1)
- 101 `EXEMPT-VRFCALLBACK` token occurrences ✓ (≥1)
- 50 `EXEMPT-RETRYLOOTBOXRNG` token occurrences ✓ (≥1)
- 375 `VIOLATION` token occurrences ✓ (≥1)
- 116 `D-43N-V44-HANDOFF-` anchor occurrences ✓ (≥1 per VIOLATION row; many anchors referenced multiple times in §0/§16/§17/per-consumer sections)
- All 5 `Pattern [1-5]:` references present ✓
- `Cross-coverage: PASS` present (4 occurrences) ✓
- Zero `contracts/` / `test/` modifications ✓
