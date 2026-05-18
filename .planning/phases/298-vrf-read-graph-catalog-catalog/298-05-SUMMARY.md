---
phase: 298-vrf-read-graph-catalog-catalog
plan: 05
subsystem: vrf-read-graph-catalog
tags:
  - audit
  - vrf
  - catalog
  - gameover-rng-substitution
dependency_graph:
  requires:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-CONTEXT.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-05-PLAN.md
    - contracts/modules/DegenerusGameGameOverModule.sol
  provides:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-05-CATALOG-section.md
  affects: []
tech_stack:
  added: []
  patterns:
    - vrf-backward-trace
    - per-tuple-verdict-matrix
    - participating-vs-non-participating-sload-enumeration
key_files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-05-CATALOG-section.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-05-SUMMARY.md
  modified: []
decisions:
  - "Scope §5 to SLOADs inside the handleGameOverDrain body (lines 79-184) — cross-call to runTerminalDecimatorJackpot (line 168) is covered in §4 and cross-call to runTerminalJackpot (line 182) is covered in §3; §5 does NOT re-enumerate their internals (per D-298-TRACE-DEPTH-01 honored at the trace-stop boundaries §3/§4 own)."
  - "Treat address(this).balance and stETH.balanceOf(game) as participating non-SLOAD state reads — they directly drive available which scales every downstream payout magnitude. Per feedback_rng_window_storage_read_freshness.md (\"freshly-read storage value alongside RNG\" doctrine), balance reads consumed alongside the substituted RNG word are in scope."
  - "Classify writers that are gated by rngLockedFlag / _livenessTriggered() reverts as EXEMPT-ADVANCEGAME (by gate) — the gate is a structural block during the multi-tx drain window and matches the Phase 290 MINTCLN precedent."
  - "Per-callsite classification per D-298-EXEMPT-REACH-01 — claimablePool has 14 distinct writer-callsites; classified individually rather than by writer-function."
metrics:
  duration_minutes: 35
  completed: 2026-05-18
  tasks_completed: 1
  files_modified: 0
  files_created: 2
---

# Phase 298 Plan 05: GameOverModule rngWordByDay substitution catalog Summary

VRF read-graph catalog for the §5 consumer (`handleGameOverDrain` reading `rngWordByDay[day]` at `DegenerusGameGameOverModule.sol:100`) — backward-traces upstream write at `AdvanceModule._applyDailyRng:1841`, enumerates 18 SLOADs (8 participating, 10 non-participating with attestations), and classifies 29 writer-callsite tuples (21 EXEMPT-ADVANCEGAME / 7 VIOLATION / 0 EXEMPT-VRFCALLBACK / 0 EXEMPT-RETRYLOOTBOXRNG / 0 SAFE_BY_DESIGN).

## What was done

- Read `298-05-PLAN.md`, `298-CONTEXT.md`, and the consumer source at `DegenerusGameGameOverModule.sol`.
- Read sibling catalog precedents (`298-01-CATALOG-section.md` `payDailyJackpot`, `298-03-CATALOG-section.md` `runTerminalJackpot`, `298-04-CATALOG-section.md` `runTerminalDecimatorJackpot`) to anchor the §A..§E format conventions.
- Walked backward from the substitution point at line `:100` (`rngWord = rngWordByDay[day];`) to identify the upstream writer (`AdvanceModule._applyDailyRng` at `:1841` and `_backfillGapDays` at `:1793` — confirmed by grep on `rngWordByDay[\w*] *=`). Documented the §D-A pre-flight attestation that the substituted word is monotonically pinned across the consumer's body.
- Walked forward through the `handleGameOverDrain` body (lines 79-184), enumerating every SLOAD with file:line citation per `feedback_verify_call_graph_against_source.md`. Cross-call delegations at `:168` (to §4) and `:182` (to §3) are marked as trace-stop boundaries to avoid duplicate enumeration.
- Authored §A traced-function-set table covering 18 reached functions / storage-helper invocations / EVM-native balance reads / cross-call boundaries.
- Authored §B SLOAD table with `Participating?` column per `D-298-SLOT-CLASSIFICATION-01`: 8 participating slots (`level`, `claimablePool`, `pendingRedemptionEthValue`, `deityPassOwners.length`, `deityPassOwners[i]`, `deityPassPurchasedCount`, `address(this).balance`, `stETH.balanceOf(game)`) and 10 non-participating slots (mostly RMW preservation reads for packed slots) with explicit attestations.
- Authored §C writer enumeration for the 8 participating slots — full grep-verified writer sets across `contracts/`, including OZ-inheritance check (zero hits), admin/owner check (zero hits), inline-assembly check (zero hits).
- Authored §D verdict matrix with 29 per-(slot × writer × callsite) tuples classified, identifying 7 VIOLATIONs:
  - **D-3** `_awardDecimatorLootbox` writes `claimablePool` from EOA-reach during drain
  - **D-7** `_resolveLootboxDirect` (EOA branch) writes `claimablePool` during drain
  - **D-13** `claimWinnings` writes `claimablePool -=` during drain (no liveness gate)
  - **D-15** `sweepSdgnrsClaim` writes `claimablePool -=` during drain (no liveness gate)
  - **D-20** External `receive()` inflates `address(this).balance` (no gate possible)
  - **D-22** `claimWinnings` outflow deflates `address(this).balance` during drain
  - **D-27** External stETH transfer-in inflates `stETH.balanceOf(game)` (no gate possible)
- Authored §E remediation-tactic recommendations per `D-298-RECOMMEND-DEPTH-01`: 5× tactic (a) gated-revert + 2× tactic (b) snapshot/anchor. Each tactic carries ≤80-char rationale; out-of-table rationale expansion for Phase 299 design-intent context.

## Deviations from Plan

None — plan executed exactly as written. Single auto task with explicit-enumeration discipline; no auto-fixed bugs, no architectural changes, no auth gates. Zero `contracts/` + zero `test/` mutations.

## Files

- **Created:** `.planning/phases/298-vrf-read-graph-catalog-catalog/298-05-CATALOG-section.md` (§5 catalog content for GameOverModule rngWordByDay substitution; ~470 lines)
- **Created:** `.planning/phases/298-vrf-read-graph-catalog-catalog/298-05-SUMMARY.md` (this file)
- **Modified:** none
- **Contract changes:** none (AUDIT-ONLY per D-43N-AUDIT-ONLY-01)
- **Test changes:** none (AUDIT-ONLY per D-43N-AUDIT-ONLY-01)

## Key Decisions

- **Scope boundary at §3/§4 cross-call sites:** `handleGameOverDrain` calls `runTerminalDecimatorJackpot` (`:168`) and `runTerminalJackpot` (`:182`). Per `D-298-EXEC-SHAPE-01`'s per-consumer decomposition, the downstream SLOADs reached inside those functions are documented under §3 and §4, NOT re-duplicated under §5. §5 owns ONLY the SLOADs inside `handleGameOverDrain`'s own body (lines 79-184). The cross-call leaves are listed in §A row 16/17 as trace-stop boundaries with explicit pointers to the sibling catalog sections.
- **Balance reads (ETH + stETH) as participating non-SLOAD state:** `address(this).balance` (line 84) and `IStETH.balanceOf(address(this))` (line 84) are not formal SLOADs on the game's own storage, but they are EVM/cross-contract state reads consumed alongside the substituted RNG word at `:100`. They directly drive `totalFunds` → `reserved` → `preRefundAvailable` → `available` → downstream payout magnitudes. Classified as YES Participating, with writer enumeration treating "anyone who can move ETH/stETH in or out of the game" as a writer. This honors `feedback_rng_window_storage_read_freshness.md`'s "freshly-read storage value alongside RNG" doctrine even when the read uses an EVM opcode rather than `SLOAD`.
- **By-gate EXEMPT classifications:** writers that are reachable from EOA in principle but blocked by `rngLockedFlag` / `_livenessTriggered()` reverts during the multi-tx drain window (e.g., `_purchaseDeityPass` for D-19, `mintBatch` family for D-21, `beginRedemption` for D-16) are classified `EXEMPT-ADVANCEGAME (by gate)` rather than `VIOLATION`. The gate is the structural block; this matches the Phase 290 MINTCLN precedent at `DegenerusGameMintModule.sol:1221`. The verdict-matrix labels include the "(by gate)" qualifier so the Phase 299 FIX sub-phase planner can distinguish gate-protected EXEMPTs from stack-rooted EXEMPTs.
- **No SAFE_BY_DESIGN escape:** per the v43.0 milestone-goal prohibition, the verdict matrix uses only `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION` — no game-theoretic exemptions for participating slots. Even the `claimWinnings` / `sweepSdgnrsClaim` paths (which arguably have benign-intent design rationale for being callable during drain) are classified VIOLATION per the strict structural rule.

## Authentication Gates

None.

## Self-Check: PASSED

- `[ -f .planning/phases/298-vrf-read-graph-catalog-catalog/298-05-CATALOG-section.md ]` → FOUND.
- `grep -c "## CAT-01\|## CAT-02\|## CAT-03\|## CAT-04\|## CAT-06" 298-05-CATALOG-section.md` → 5 (all 5 sub-headings present).
- `! grep -q "SAFE_BY_DESIGN" 298-05-CATALOG-section.md` → no SAFE_BY_DESIGN.
- `git diff --name-only HEAD | grep -E '^(contracts|test)/' | wc -l` → 0 (zero source-tree modifications).
- Every §B `Participating? = YES` row has corresponding §C writer enumeration (B-2 → §C.B-2; B-3 → §C.B-3; B-4 → §C.B-4; B-5/B-6/B-7 → §C.B-5/6/7; B-17 → §C.B-17; B-18 → §C.B-18).
- Every §D VIOLATION row (D-3, D-7, D-13, D-15, D-20, D-22, D-27) has a corresponding §E tactic row (E-1..E-7) with ≤80-char rationale.
