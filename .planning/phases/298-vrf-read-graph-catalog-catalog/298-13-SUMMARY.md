---
phase: 298-vrf-read-graph-catalog-catalog
plan: 13
subsystem: vrf-read-graph-catalog
tags: [catalog, vrf, decimator, lootbox, cross-call-sload, freshness]
dependency_graph:
  requires:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-CONTEXT.md
    - contracts/modules/DegenerusGameDecimatorModule.sol
    - contracts/modules/DegenerusGameLootboxModule.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/modules/DegenerusGamePayoutUtils.sol
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/DegenerusGame.sol
    - contracts/DegenerusVault.sol
  provides:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-13-CATALOG-section.md
  affects: []
tech-stack:
  added: []
  patterns: ["cross-call SLOAD freshness", "per-callsite verdict matrix", "snapshot-anchor tactic (b)", "gated-revert tactic (a)"]
key-files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-13-CATALOG-section.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-13-SUMMARY.md
  modified: []
decisions:
  - "Reinterpret PLAN line :771 as the conceptual cross-call rngWord re-read pattern; current source has the actual SLOAD at DecimatorModule.sol:338 (inside claimDecimatorJackpot). Documented in §13 catalog header."
  - "decClaimRounds[lvl].rngWord itself is freshness-safe (single EXEMPT-ADVANCEGAME writer, set-once per lvl). The F-41-02/03-class concern recurs at the CO-LOADED slots (level, mintPacked_, lootboxEvBenefitUsedByLevel, decBurn[lvl][player].burn)."
  - "Cluster reach is EOA-callable via claimDecimatorJackpot — NOT EXEMPT-{ADVANCEGAME,VRFCALLBACK,RETRYLOOTBOXRNG}. All non-EXEMPT writers reaching this consumer surface to VIOLATION verdicts."
  - "D-4 (decBurn[lvl][player].burn writer reach) is flagged VIOLATION pending burn-window-semantics verification at Phase 299 FIX-phase per feedback_design_intent_before_deletion.md."
metrics:
  duration_minutes: ~25
  completed: 2026-05-18
---

# Phase 298 Plan 13: VRF Read-Graph Catalog — DecimatorModule._awardDecimatorLootbox cluster Summary

Backward-traced VRF-derived entropy through the `_awardDecimatorLootbox` callsite cluster (consumer §13 of the 13-entry D-298-CONSUMER-LIST-01) — both the in-stack `rngWord` parameter consumer at signature line `:573` AND the cross-call SLOAD re-read of `decClaimRounds[lvl].rngWord` (PLAN-noted as line :771; resolved to actual current-source line `:338` inside `claimDecimatorJackpot`). Produced the §13 catalog section with 32 traced functions, 29 enumerated SLOADs (9 participating), 12 verdict rows (6 VIOLATION + 6 EXEMPT), and 6 §E recommended-tactic rows. The F-41-02/03 cross-call read-freshness precedent is satisfied: the rngWord SLOAD itself is freshness-safe (single EXEMPT writer), but co-loaded participating slots (`mintPacked_`, streak fields, `level`, `lootboxEvBenefitUsedByLevel`, `decBurn[lvl][player].burn`) carry the freshness-class concern and surface as VIOLATIONs.

## Tasks Completed

### Task 13.1: Backward-trace from _awardDecimatorLootbox callsite cluster

**Goal:** Produce the §13 catalog section (§A trace + §B SLOAD table + §C writer enumeration + §D verdict matrix + §E recommended tactic) for the DecimatorModule lootbox-award cluster including the cross-call `decClaimRounds[lvl].rngWord` SLOAD re-read pattern.

**Output:** `.planning/phases/298-vrf-read-graph-catalog-catalog/298-13-CATALOG-section.md`

**Key sections in the catalog:**

- **Header** — Reconciles the PLAN-noted line `:771` (which in current source is `decSeed = rngWord;` inside `runTerminalDecimatorJackpot` consumer §4) with the actual cross-call re-read site at `DecimatorModule.sol:338` inside `claimDecimatorJackpot`. The cluster comprises callsite α (`_awardDecimatorLootbox` body line `:573` rngWord parameter) and callsite β (`:338` cross-call SLOAD).
- **Caller chain** — Full call graph from EOA / `DegenerusVault.jackpotsClaimDecimator` down through `claimDecimatorJackpot` → `_consumeDecClaim` + `_creditDecJackpotClaimCore` → `_awardDecimatorLootbox` → Path A (whale-pass + ticket queue) OR Path B (delegatecall to `LootboxModule.resolveLootboxDirect` → `_resolveLootboxCommon`). Cluster is reach-restricted to player-EOA stack — **NOT EXEMPT**.
- **§A traced function set** — 32 functions enumerated with file:line citations per `feedback_verify_call_graph_against_source.md`. No "by construction" claims.
- **§B SLOAD table** — 29 SLOADs (B-1..B-29) classified Participating? YES/NO with explicit attestation per `D-298-SLOT-CLASSIFICATION-01` two-tier scheme. The cross-call re-read at B-10 (`decClaimRounds[lvl].rngWord` at `:338`) is enumerated explicitly and analyzed for freshness per F-41-02/03 precedent. §B-W (auxiliary) lists 13 cross-check SSTOREs.
- **§C writer enumeration** — Each participating slot's writer set enumerated with callsite file:line and EXEMPT-stack reachability analysis. Covers `decClaimRounds[lvl].rngWord` writer set (single EXEMPT writer), `level` (single EXEMPT writer), `mintPacked_[player]` writers (4+ non-EXEMPT paths), `lootboxEvBenefitUsedByLevel` writers (1 non-EXEMPT path), `decBurn[lvl][player].burn` writers (1 candidate-VIOLATION pending burn-window verification).
- **§D verdict matrix** — 12 per-(slot × writer × callsite) rows. 6 VIOLATION (D-4, D-8, D-9, D-10, D-11, D-12). 6 EXEMPT (5 EXEMPT-ADVANCEGAME + 1 EXEMPT-VRFCALLBACK).
- **§E recommended tactics** — 6 VIOLATION rows each get one tactic from `(a|b|c|d)` + ≤80-char rationale per `D-298-RECOMMEND-DEPTH-01`. E-4 → (a), E-8/E-9/E-10/E-11 → (b) snapshot-anchor for activity-score, E-12 → (a).

**Files modified:** `.planning/phases/298-vrf-read-graph-catalog-catalog/298-13-CATALOG-section.md` (created)
**Commit:** see git log.

## Cross-call SLOAD re-read pattern (F-41-02/03 precedent compliance)

The PLAN flagged `decClaimRounds[lvl].rngWord` cross-call re-read as a distinct participating-SLOAD class per `feedback_rng_window_storage_read_freshness.md`. The catalog enumerates this explicitly at §B row B-10 with `Participating? = YES` and a freshness analysis:

- **Writer-set:** Single SSTORE at `DecimatorModule.sol:258` inside `runDecimatorJackpot`, reach-restricted to `advanceGame()` (EXEMPT-ADVANCEGAME stack via `AdvanceModule.sol:853`). Set-once-per-`lvl` (`runDecimatorJackpot:217` short-circuits subsequent calls). No non-EXEMPT writer can mutate the slot.
- **Read-set:** Two reads of the struct's `.rngWord` field across the codebase — the write at `:258` and the consumer read at `:338`.
- **Conclusion:** The rngWord SLOAD itself is freshness-safe.

**The F-41-02/03 concern recurs at the CO-LOADED slots inside the same player-EOA stack frame:**
- `level` (B-13/B-15/B-25) — single EXEMPT writer, monotonic forward; classified EXEMPT.
- `mintPacked_[player]` (B-23) — multiple non-EXEMPT writers (mint, boon, whale, streak paths); classified VIOLATION at 4 distinct (slot × writer) tuples.
- `streakState[player]` (B-24) — non-EXEMPT writers; VIOLATION.
- `lootboxEvBenefitUsedByLevel[player][lvl]` (B-26) — peer-lootbox-open writers; VIOLATION.
- `decBurn[lvl][player].burn` (B-8) — candidate VIOLATION pending burn-window-semantics verification at Phase 299 FIX-phase.

This matches the literal F-41-02/03 pattern: VRF-derived word reaches the consumer ALONGSIDE other SLOADs that an attacker can mutate between RNG publish and consumer execution.

## Deviations from Plan

**1. [PLAN line-number reconciliation]** PLAN specified line `:771` for the cross-call re-read pattern. Current 2026-05-18 source has `:771` as `uint256 decSeed = rngWord;` inside `runTerminalDecimatorJackpot` — that's consumer §4's terminal-decimator entry (separate VRF consumer with its own catalog section). The actual cross-call SLOAD `decClaimRounds[lvl].rngWord` lives at `DecimatorModule.sol:338` inside `claimDecimatorJackpot`. Documented in the catalog header; treated `:338` as the authoritative callsite β line for this section. **No code change; documentation-only reconciliation.** Per `feedback_no_contract_commits.md`: zero `contracts/` + zero `test/` mutations.

**2. [Burn-window verification deferred]** §C C-3 / §D D-4 / §E E-4 covers `decBurn[lvl][player].burn` reach. The catalog flags D-4 as VIOLATION pending Phase 299 verification of burn-window semantics (whether `BurnieCoin.decimatorBurn` can write `decBurn[lvl][player]` for a `lvl` that has ALREADY been snapshotted by `runDecimatorJackpot`). Per `feedback_design_intent_before_deletion.md`: trace original design intent + actor game-theory at fix time, not at catalog time. Default classification: VIOLATION (conservative).

## Files Modified

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-13-CATALOG-section.md` (CREATED)
- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-13-SUMMARY.md` (CREATED — this file)

## Self-Check: PASSED

- File `.planning/phases/298-vrf-read-graph-catalog-catalog/298-13-CATALOG-section.md` exists.
- All five required `## CAT-01` / `## CAT-02` / `## CAT-03` / `## CAT-04` / `## CAT-06` headings present.
- Zero occurrences of `SAFE_BY_DESIGN` token (milestone-goal prohibition satisfied).
- Zero `contracts/` + zero `test/` modifications (per `D-43N-AUDIT-ONLY-01`).
- B-10 row (`decClaimRounds[lvl].rngWord` cross-call SLOAD) explicitly enumerated with `Participating? = YES`.
- C-5 row (writer enumeration for `decClaimRounds[lvl].rngWord`) explicitly enumerated.
- Every §D VIOLATION row has a corresponding §E tactic + rationale ≤80 chars.

## Decisions Made

1. **Reinterpret PLAN line :771 as conceptual cross-call SLOAD pattern.** Actual current-source line is `:338`; documented prominently in catalog header. Rationale: `feedback_verify_call_graph_against_source.md` requires file:line precision; PLAN line numbers may drift across source revisions.
2. **`decClaimRounds[lvl].rngWord` is freshness-safe; F-41-02/03 concern recurs at co-loaded slots.** Rationale: writer-set analysis (single EXEMPT writer, set-once-per-`lvl`) eliminates the slot itself as a freshness vector. The audit value is at the co-loaded slots in the same EOA-stack frame.
3. **D-4 (decBurn burn) classified VIOLATION conservatively, pending Phase 299 burn-window verification.** Rationale: cannot prove EXEMPT without verifying burn-window timing semantics; default to VIOLATION per Phase 298's no-discretionary-safe-class rule.
4. **E-8/E-9/E-10/E-11 all converge on snapshot-anchor tactic (b).** Rationale: four distinct non-EXEMPT writers all feed `_playerActivityScore`; one snapshot at advanceGame jackpot-phase entry closes all four window simultaneously. Mirrors Phase 288 dailyIdx-snapshot precedent.
