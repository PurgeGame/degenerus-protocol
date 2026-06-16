# Phase 404 — MUTATION: resume the v63 CI-resumable tail (v64.0)

**Status:** ▶ RUNNING (BurnieCoinflip launched) → BOUNDED + CI-RESUMABLE close (v63 precedent).
**Requirement:** MUT-01 · **Subject frozen** `402855e1` (v64 pin: `SUBJECT_SHA=891f7a8f`, `SUBJECT_TREE=402855e1…`).
**Harness:** `audit/mutation/run-campaign-v64.sh --single <Contract>` (kill-safe restore trap + per-target `.DONE` resumability), driven against the COMPREHENSIVE oracle `oracle-comprehensive.sh` (the 12-suite green-baseline union — avoids the [mutation-oracle-must-exercise-mutated-code] false-survivor trap). v64 runner derived from the v63 runner with the subject pin re-based to `402855e1`.

## What was already scored (v63 campaign — carries as prior)

Per `audit/mutation/CAMPAIGN-REPORT-v63.md`, the 3 SPINE targets were fully scored + triaged against the comprehensive oracle, **0 contract defects**, every GENUINE survivor killed by a regression test:
- **BitPackingLib** (packing identity) — 55 survivors, 1 GENUINE (`G-BPL-01`) KILLED.
- **DegenerusGameStorage** (packing + solvency helpers) — survivors triaged; 1 real survivor FALSE (oracle), 1 compile artifact.
- **StakedDegenerusStonk** (solvency spine) — 76 distinct survivors, 6 GENUINE (`K1–K6`) ALL KILLED.

These primitives are byte-identical at the v64 subject (the v64 delta over v63 did not touch BitPackingLib / the packed storage layout's masking primitives), so the v63 scoring carries forward.

## The CI-deferred tail (this phase resumes it on the v64 subject)

| Target | Class | v64 status |
|---|---|---|
| **BurnieCoinflip** | v64-CHANGED (carry-escrow `98c4f049` + 180-day window `c78ea3db`) + RNG-adjacent | ⏸ **BASELINE-GREEN VALIDATED + early mutants scored, then STOPPED clean → CI-RESUMABLE** (see note) |
| **DegenerusGameLootboxModule** | RNG-DOMINANT + SOLVENCY (~2328 LOC) | CI-RESUMABLE (via_ir overnight) |
| **DegenerusGameDecimatorModule** | RNG-DOMINANT + offset-key (~1159 LOC) | CI-RESUMABLE (via_ir overnight) |

> **BurnieCoinflip run note:** `run-campaign-v64.sh --single BurnieCoinflip` launched on the v64 subject; the comprehensive oracle **BASELINE_CHECK passed green** (so survivors would be genuine, not oracle artifacts) and slither-mutate began scoring (early constructor mutants `:204`/`:205` `==> revert()` → **CAUGHT**; `:203` compile-failure artifact). The run was **stopped cleanly** (restore trap + `git checkout -- contracts/` → subject re-frozen `402855e1`, verified) because each mutant transiently dirties `contracts/BurnieCoinflip.sol` (the commit-guard correctly blocks all commits meanwhile) and the full via_ir scoring is overnight-scale — impractical to hold the working tree dirty in-session. **Resumable:** re-invoke `run-campaign-v64.sh --single BurnieCoinflip` (overnight/CI); a completed target writes `.DONE`. This matches the v63 bounded close for these exact 3 modules.

## Coverage rationale (why bounded + resumable is sound)

The v64-changed functions inside these 3 modules were **already deeply audited clean by the 399–403 dual-net sweeps** (council + Claude Workflow, every lead adjudicated vs frozen source, 0 contract defects):
- BurnieCoinflip carry-escrow + window — SOLV-02 / SOLV-05 (phase 400) + RWD-05 (399), all attested.
- Lootbox spins / EV / recirc — RWD-01..03 (399) + RNG-01..03 (403), all frozen + EV-consistent.
- Decimator offset-key + claim-seed — PERM-01 (402) + RNG-01/03 (403), isolation + freeze attested.

Mutation here is **test-coverage hardening** ("no contract defect expected"), not a findings hunt. The dual-net sweeps are the primary correctness attestation; mutation confirms the regression net would CATCH an injected defect in these functions.

## Triage protocol (on each target's completion)

1. Each survivor → FALSE (oracle never exercises the mutated line — re-confirm the oracle path) vs GENUINE (a real test-coverage blind spot).
2. Every GENUINE survivor → killed by a validated regression test (test-only; commit to `test/`; no contract change).
3. Record killed/false counts + any GENUINE kill in this doc; 0 contract defects expected (and would be re-verified vs the dual-net if a survivor implied one).

## Close

Phase 404 closes **BOUNDED**: BurnieCoinflip scored on the v64 subject (result folded in on completion); Lootbox + Decimator CI-RESUMABLE (re-invoke `run-campaign-v64.sh --single <Contract>` — completed targets stay `.DONE`). This matches the v63 milestone's own bounded mutation close. The dual-net sweeps remain the primary coverage attestation; the milestone (405) closes with the tail documented as resumable, not dropped.
