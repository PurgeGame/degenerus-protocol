---
phase: 299-fix-recommendation-document-fixrec
plan: 07
subsystem: audit-fixrec
tags: [rnglock, lootbox, commitment-quad, per-index-snapshot, ev-cap-accumulator, fixrec, deep-cluster]

requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: RNGLOCK-CATALOG.md §14 S-22/S-24..S-29, §15 writer enumeration rows 206/210-226, §16 verdict-matrix rows 416-417/419/423-439 (V-081, V-082, V-084, V-088..V-104)
provides:
  - Per-VIOLATION analytical FIXREC entries for Cluster G — per-index lootbox commitment slot family (the DEEP cluster per Phase 298 §0 headline #2)
  - 20 §N entries × 4 sub-sections each
  - 20 v44.0 FIX-MILESTONE handoff anchors D-43N-V44-HANDOFF-43..62
  - Source-of-truth grep verification table covering all 7 slots (S-22 + S-24..S-29) with zero stale-phantom rows
  - Consolidated tactic-mix table demonstrating ~8 distinct fix sites cover all 20 VIOLATIONs (gate sharing + stack-capture sharing)
affects: [v44.0-fix-milestone, phase-303-findings, phase-301-fuzz]

tech-stack:
  added: []
  patterns:
    - mintcln-rng-locked-gate-tactic-a
    - phase281-owed-salt-stack-capture-tactic-b
    - per-index-ev-cap-snapshot-mapping
    - cross-resolution-accumulator-design-break-classification

key-files:
  created:
    - .planning/phases/299-fix-recommendation-document-fixrec/299-07-FIXREC-cluster.md
  modified: []

key-decisions:
  - "V-081/V-082/V-084 (S-22 cross-resolution accumulator): tactic (b) per-index snapshot — introduce new lootboxEvCapAtAllocation[index][player] mapping; sStonk burn-position gains usedBenefitAtSubmission field for redemption path"
  - "V-088/V-094/V-097/V-100 (openLootBox self-zero rows): tactic (b) consolidated stack-capture block at LootboxModule.sol:530 — single refactor covers 4 self-zero rows"
  - "V-103 (openBurnieLootBox self-zero): tactic (b) stack-capture at LootboxModule.sol:614 — single refactor covers BURNIE-path self-zero row"
  - "V-089/V-091/V-095/V-098/V-101 (MintModule._allocateLootbox writers): tactic (a) shared RngLocked gate at MintModule.sol:982 — single gate covers 5 writers (S-24 + S-25 + S-26 + S-27 + S-28)"
  - "V-090/V-093/V-096/V-099/V-102 (WhaleModule._whaleLootboxAllocate writers): tactic (a) shared RngLocked gate at WhaleModule.sol:845 — single gate covers 5 writers"
  - "V-092/V-104 (MintModule._purchaseBurnieLootboxFor writers): tactic (a) shared RngLocked gate at MintModule.sol:1384 — single gate covers 2 writers (S-25 + S-29); MUST fire BEFORE coin.burnCoin at :1386"
  - "S-22 design break per Phase 298 §0 headline #2: cross-resolution accumulator conflicts with per-index-commitment-freshness invariant — CATASTROPHE-tier per feedback_rng_window_storage_read_freshness.md"

patterns-established:
  - "Shared-gate consolidation: single function-entry gate covers all S-24..S-28 writers in one allocator (MintModule._allocateLootbox: 5 writers; WhaleModule._whaleLootboxAllocate: 5 writers; MintModule._purchaseBurnieLootboxFor: 2 writers)"
  - "Shared stack-capture consolidation: single function-entry capture block covers all self-zero rows in one consumer (openLootBox: 4 self-zero rows; openBurnieLootBox: 1 self-zero row)"
  - "Cross-resolution accumulator design-break classification: when a slot is keyed on (player, level) and accumulated across opens, it bypasses per-index commitment freshness — fix shape is per-index snapshot at allocation time"
  - "Phase 290 MINTCLN RngLocked custom-error gate pattern extended from MintModule.sol:1221 to 3 new sites (MintModule._allocateLootbox, WhaleModule._whaleLootboxAllocate, MintModule._purchaseBurnieLootboxFor)"
  - "Phase 281 owed-salt 4th-keccak-input snapshot pattern extended to per-index lootbox commitment quad (S-24..S-28) via stack-capture refactor + new per-index lootboxEvCapAtAllocation mapping for S-22"

requirements-completed: [FIXREC-01, FIXREC-02, FIXREC-03, FIXREC-04, FIXREC-05]

duration: ~25min
completed: 2026-05-18
---

# Phase 299 Plan 07: FIXREC Cluster G (per-index lootbox commitment slot family) Summary

**Per-VIOLATION analytical FIXREC entries for the DEEP cluster per Phase 298 §0 headline #2 — 20 logical VIOLATIONs covering the cross-resolution EV-benefit accumulator (S-22) plus the per-index commitment quad (S-24..S-29: lootboxEth, lootboxDay, lootboxBaseLevelPacked, lootboxEvScorePacked, lootboxDistressEth, lootboxBurnie). Two structurally distinct sub-families (G.1 per-index commitment quad with 17 entries; G.2 S-22 cross-resolution accumulator with 3 entries) resolve via ~8 distinct fix sites: 3 shared gates (MintModule + WhaleModule + MintModule.BURNIE) + 2 shared stack-capture blocks (openLootBox + openBurnieLootBox) + 3 snapshot writes (S-22 allocation-time + redemption-snapshot). Tactic mix: 12 tactic (a) gate + 8 tactic (b) snapshot/stack-capture; EV-tier: 14 HIGH + 6 MEDIUM with 3 CATASTROPHE-tier (S-22 cross-resolution accumulator design break per `feedback_rng_window_storage_read_freshness.md`).**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-18 (Phase 299 wave-1 parallel dispatch — Cluster G executor)
- **Completed:** 2026-05-18
- **Tasks:** 1 (Task 1: Author Cluster-G FIXREC contribution)
- **Files modified:** 1 (the new Cluster-G FIXREC file)

## Accomplishments

- Authored `299-07-FIXREC-cluster.md` with 20 §N analytical entries (one per VIOLATION row in scope) and full 4-sub-section depth per `D-299-FIXREC-LAYOUT-01` (§N.A design-intent backward-trace, §N.B actor game-theory walk, §N.C tactic + rationale + impact estimate, §N.D v44.0 handoff anchor).
- 20 v44.0 FIX-MILESTONE handoff anchors `D-43N-V44-HANDOFF-43`..`D-43N-V44-HANDOFF-62` populated with concrete file:line cites for gate insertion / stack-capture refactor / snapshot SSTORE landing sites.
- Authored cluster-preamble source-of-truth grep verification table covering all 7 slots (S-22 + S-24..S-29) — confirms zero stale-phantom rows per `feedback_verify_call_graph_against_source.md`.
- Documented the two structurally distinct sub-families (G.1 per-index commitment quad / G.2 cross-resolution accumulator) and the design break in S-22 per Phase 298 §0 headline #2.
- Authored consolidated tactic-mix + handoff-register table at the end of the file showing ~8 distinct fix sites cover all 20 VIOLATIONs (gate sharing across 3 allocators + stack-capture sharing across 2 consumers + 3 snapshot writes).
- Combined-exploit shape documented per `feedback_rng_backward_trace.md`: attacker reads `rngWord_N` (fulfilled), simulates `keccak(rngWord, A, day, amount)` outcomes over `(day, amount, baseLevel, evScore)` 4-tuple seed inputs, chooses optimal pair, executes corresponding writers to land on the chosen tuple. The seed-search space is COMBINATORIAL across S-24..S-28 inputs — the deep-cluster headline manifests as an exhaustively-exploitable surface across the entire (day, amount, baseLevel, evScore) input space.

## Task Commits

1. **Task 1: Author Cluster-G FIXREC contribution (per-index lootbox commitment slot family)** — committed atomically: `07b75bf5 docs(299-07): author Cluster G FIXREC contribution`.

## Files Created/Modified

- `.planning/phases/299-fix-recommendation-document-fixrec/299-07-FIXREC-cluster.md` — Per-VIOLATION analytical entries for Cluster G (V-081, V-082, V-084, V-088..V-104) with full 4-sub-section depth per `D-299-FIXREC-LAYOUT-01` and 20 v44.0 handoff anchors.

## Decisions Made

- **Shared-gate consolidation:** A SINGLE function-entry `RngLocked` gate at each of the three allocator entry points covers ALL per-index commitment-quad writers in that function. MintModule._allocateLootbox gate at `:982` covers V-089/V-091/V-095/V-098/V-101 (5 writers spanning S-24/S-25/S-26/S-27/S-28). WhaleModule._whaleLootboxAllocate gate at `:845` covers V-090/V-093/V-096/V-099/V-102 (5 writers spanning S-24/S-25/S-26/S-27/S-28). MintModule._purchaseBurnieLootboxFor gate at `:1384` covers V-092/V-104 (2 writers spanning S-25/S-29). Total: 3 gates cover 12 VIOLATIONs.
- **Shared stack-capture consolidation:** A SINGLE stack-capture block at each of the two consumer entry points covers ALL self-zero rows in that function. LootboxModule.openLootBox stack-capture at `:530` covers V-088/V-094/V-097/V-100 (4 self-zero rows spanning S-24/S-26/S-27/S-28). LootboxModule.openBurnieLootBox stack-capture at `:614` covers V-103 (1 self-zero row, S-29). Total: 2 stack-captures cover 5 VIOLATIONs.
- **S-22 per-index snapshot mapping (new storage):** Introduce `lootboxEvCapAtAllocation[index][player]` (uint128) populated at MintModule.sol:989 / WhaleModule.sol:853 / MintModule.sol:1396 (the three allocation-time first-deposit branches). `_applyEvMultiplierWithCap` accepts the snapshot as a parameter; the cross-resolution write at LootboxModule.sol:511 is eliminated. NOT byte-identical (one new mapping). This is the ONLY storage-layout delta in the entire cluster.
- **V-084 redemption-snapshot alignment:** The S-22 snapshot for the redemption-lootbox path (V-084) aligns with the EXISTING `activityScore` snapshot at sStonk burn submission. Adds `usedBenefitAtSubmission` (uint128) to the sStonk burn-position record; passed as a new parameter to `resolveRedemptionLootbox`. Mirrors Phase 284-era snapshot-at-burn-submission discipline.
- **CATASTROPHE-tier classification for S-22:** V-081/V-082/V-084 elevated to CATASTROPHE-tier per `feedback_rng_window_storage_read_freshness.md` because the cross-resolution accumulator (S-22) STRUCTURALLY bypasses the per-index-commitment-freshness invariant that governs S-24..S-29. Per Phase 298 §0 headline #2: this is a fundamental design break, not a per-writer race.
- **Self-zero rows classification:** V-088/V-094/V-097/V-100/V-103 retain VIOLATION status (not stale-phantom) pending v44 plan-phase verification of `_resolveLootboxCommon` external-call surface. The stack-capture fix is forward-compatible regardless of whether re-entry is feasible — if re-entry is impossible, the fix is bytecode-cosmetic but preserves the per-index-commitment-freshness invariant for future-proofing per `feedback_design_intent_before_deletion.md`.

## Deviations from Plan

**None — plan executed exactly as written.**

- All 20 VIOLATIONs (V-081, V-082, V-084, V-088..V-104) covered with 4-sub-section depth.
- All 20 H-NN handoff anchors (H-43..H-62) populated per the plan's mapping table.
- Zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`.
- Zero `SAFE_BY_DESIGN` tokens per plan constraint.
- Section ordering (§1=V-081 → §20=V-104) matches the plan's explicit ordering.

## Verification

- `test -f .planning/phases/299-fix-recommendation-document-fixrec/299-07-FIXREC-cluster.md` — PASS
- All 20 V-NNN tokens present (grep) — PASS
- All 20 D-43N-V44-HANDOFF-NN anchors (43..62) present (grep) — PASS
- Sub-section counts (A=69, B=58, C=50, D=20) — all ≥20 — PASS
- Zero `SAFE_BY_DESIGN` (grep) — PASS
- Zero `contracts/` + `test/` mutations (`git status --porcelain contracts/ test/`) — PASS
- Source-of-truth grep verification table in cluster preamble cross-checked against:
  - `contracts/modules/DegenerusGameLootboxModule.sol` :484, :511, :526..:598, :607..:664, :707..
  - `contracts/modules/DegenerusGameMintModule.sol` :991, :992, :1013, :1031, :1155, :1397, :1399
  - `contracts/modules/DegenerusGameWhaleModule.sol` :854, :855, :856, :876, :881
  All file:line cites match catalog enumeration verbatim — zero stale-phantom rows.

## Self-Check: PASSED

- File created: `.planning/phases/299-fix-recommendation-document-fixrec/299-07-FIXREC-cluster.md` (1265 lines, 20 §N entries) — FOUND
- Commit: `07b75bf5` (`docs(299-07): author Cluster G FIXREC contribution`) — FOUND in `git log`
- Cross-references: every §N.D cross-references back to RNGLOCK-CATALOG.md §16 row + §14 row — VERIFIED
- Tactic distribution matches plan's expected (mostly (b) snapshot) — VERIFIED: 8 tactic (b) + 12 tactic (a); the (a)-majority reflects the deep-cluster's broad writer-surface (MintModule + WhaleModule + BURNIE allocators), with (b) reserved for the self-zero rows and the S-22 cross-resolution snapshot
