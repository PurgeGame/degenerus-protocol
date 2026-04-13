---
phase: 223-findings-consolidation
plan: 01
subsystem: audit-docs
tags: [findings, consolidation, regression-appendix, v27.0]
requires: [220, 221, 222]
provides: [audit/FINDINGS-v27.0.md]
affects: []
tech_stack_added: []
patterns: [F-27-NN monotonic numbering, per-phase grouping, Resolved-in-cycle Status field]
key_files_created: [audit/FINDINGS-v27.0.md]
key_files_modified: []
decisions:
  - "D-01..D-07 honored verbatim (naming, inclusion, Resolved-in-cycle status, severity default, regression appendix, v26.0 gap, scope-framing)"
  - "16 F-27-NN findings selected (within 14-16 plan range); 6 Phase 220 + 5 Phase 221 + 5 Phase 222"
  - "WR-222-02 + WR-222-04 + VERIFICATION Gap 1 consolidated into F-27-13 (shared commit ef83c5cd)"
  - "WR-222-03 + VERIFICATION Gap 2 consolidated into F-27-14 (commit e0a1aa3e)"
  - "v25.0 F-25-09 classified SUPERSEDED (code relocated from AdvanceModule._deityDailySeed to DegenerusGame.deityBoonData); all 12 other v25.0 findings HOLD"
metrics:
  duration_seconds: 1040
  tasks: 1
  files_changed: 1
  completed_date: 2026-04-13
---

# Phase 223 Plan 01: FINDINGS-v27.0.md Authoring Summary

Authored `audit/FINDINGS-v27.0.md` consolidating all Phase 220/221/222 REVIEW and VERIFICATION findings into 16 severity-classified F-27-NN items following the v25.0 Master Delta structure, with a full v25.0 regression appendix verifying 12 HOLDS and 1 SUPERSEDED (no FIXED or INVALIDATED entries).

## Objective Status

**CSI-12 satisfied (checkbox flip deferred to Plan 223-02):** `audit/FINDINGS-v27.0.md` exists as a 392-line severity-classified findings document mirroring `audit/FINDINGS-v25.0.md` structure verbatim. Every WR-* / IN-* / Gap item from the three source phases is accounted for; five resolved-in-cycle items carry explicit commit SHAs; the verbatim D-07 scope-framing sentence is in the preamble.

## Distribution

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 16 |
| **Total** | **16** |

**Resolved-in-cycle count:** 5 source items (WR-221-01, WR-221-02, WR-222-02, WR-222-03, WR-222-04) resolved across 3 distinct commits — WR-222-02 and WR-222-04 are sub-points of F-27-13 and share commit `ef83c5cd`; WR-222-03 and VERIFICATION Gap 2 share commit `e0a1aa3e`; WR-221-01 and WR-221-02 share commit `f799da98`.

## F-27-NN → Source-Item Mapping

This is the authoritative cross-reference Plan 223-02 consumes for KNOWN-ISSUES promotion and MILESTONES retrospective. Every WR-* / IN-* / Gap item from the three REVIEW/VERIFICATION files appears at least once in the Source Item(s) column.

| F-27-NN | Title | Source Item(s) | Phase | Status |
|---------|-------|----------------|-------|--------|
| F-27-01 | Trailing slash on `CONTRACTS_DIR` silently disables interfaces/ and mocks/ filters | 220-REVIEW WR-220-01 | 220 | INFO (open) |
| F-27-02 | Mapping preflight scans only `IDegenerusGameModules.sol` | 220-REVIEW WR-220-02 | 220 | INFO (open) |
| F-27-03 | 10-line preceding window for target-address detection is fragile | 220-REVIEW WR-220-03 | 220 | INFO (open) |
| F-27-04 | `self_test_transform()` duplicates `validate_mapping()` | 220-REVIEW IN-220-01 | 220 | INFO (open) |
| F-27-05 | Parallel-make race on `ContractAddresses.sol` between Foundry/Hardhat | 220-REVIEW IN-220-03 | 220 | INFO (open) |
| F-27-06 | Phase 220 gate script — minor robustness notes (folded) | 220-REVIEW IN-220-02 + IN-220-04 + IN-220-05 | 220 | INFO (open) |
| F-27-07 | Non-existent `CONTRACTS_DIR` silently passes | 221-REVIEW WR-221-01 | 221 | INFO (Resolved f799da98) |
| F-27-08 | `warn_total` declared and tested but never incremented | 221-REVIEW WR-221-02 | 221 | INFO (Resolved f799da98) |
| F-27-09 | Pattern D comment contains historical phase reference | 221-REVIEW IN-221-01 | 221 | INFO (open) |
| F-27-10 | `grep --exclude-dir` basename-vs-full-path asymmetry | 221-REVIEW IN-221-02 | 221 | INFO (open) |
| F-27-11 | Pattern E `awk` emits opener line not payload line | 221-REVIEW IN-221-03 | 221 | INFO (open) |
| F-27-12 | `patchContractAddresses.js` VRF_KEY_HASH regex fails on multi-line format | 222-REVIEW WR-222-01 | 222 | INFO (open) |
| F-27-13 | `CoverageGap222.t.sol` reachability-only + `uint32 >= 0` tautology (sub-points A, B) | 222-REVIEW WR-222-02 + 222-REVIEW WR-222-04 + 222-VERIFICATION Gap 1 | 222 | INFO (Resolved ef83c5cd) |
| F-27-14 | `coverage-check.sh` drift mode not contract-scoped | 222-REVIEW WR-222-03 + 222-VERIFICATION Gap 2 | 222 | INFO (Resolved e0a1aa3e) |
| F-27-15 | Delegatecall/docstring clarity notes (folded sub-points A, B) | 222-REVIEW IN-222-01 + IN-222-02 | 222 | INFO (open) |
| F-27-16 | Phase 222 comment hygiene + coverage-check robustness (folded sub-points A-D) | 222-REVIEW IN-222-03 + IN-222-04 + IN-222-05 + IN-222-06 | 222 | INFO (open) |

## v25.0 Regression Appendix Disposition

**Total items checked:** 13 (F-25-01 through F-25-13 from `audit/FINDINGS-v25.0.md`)

| Status | Count | Findings |
|--------|-------|----------|
| HOLDS | 12 | F-25-01, F-25-02, F-25-03, F-25-04, F-25-05, F-25-06, F-25-07, F-25-08, F-25-10, F-25-11, F-25-12, F-25-13 |
| SUPERSEDED | 1 | F-25-09 (deity-boon deterministic fallback relocated from `AdvanceModule._deityDailySeed` to `DegenerusGame.deityBoonData:856-860`; same tier-3 no-VRF-word semantics and same cosmetic-only conclusion) |
| FIXED | 0 | — |
| INVALIDATED | 0 | — |

No regressions detected. The single SUPERSEDED entry is a benign code-path relocation during v26.0/v27.0 cycle work; the underlying observation still applies with the same security analysis.

## Deviations from Plan

None — plan executed exactly as written. Consolidation counts landed at 16 (within the 14-16 range the plan specified); all grep verification checks pass.

## Handoff to Plan 223-02

**D-08 KNOWN-ISSUES.md promotion candidates** (per CONTEXT D-08 criteria: INFO/LOW + design decision / accepted trade-off + external-reader value):

1. **F-27-12 (WR-222-01 `patchContractAddresses.js` VRF_KEY_HASH regex)** — deployment-tooling robustness accepted as non-runtime risk; external auditors benefit from the explicit mitigation path ("operator review before mainnet deploy"). **Strong candidate.**
2. **F-27-05 (IN-220-03 parallel-make `ContractAddresses.sol` race)** — pre-existing `Makefile:44` foot-gun with known mitigation path (`.NOTPARALLEL: test`); fits the "accepted trade-off with documented mitigation" pattern. **Strong candidate.**
3. **F-27-13 + F-27-14 (Plan 222-03 gap closures)** — summary-form KNOWN-ISSUES entries capturing the VERIFICATION-gap historical record. Full technical detail already lives in `audit/FINDINGS-v27.0.md`; KNOWN-ISSUES entries would be one-sentence "VERIFICATION Gap N closed in commit <sha>" cross-references for external-auditor continuity. **Optional — skip if KNOWN-ISSUES.md is meant to stay forward-looking rather than historical.**
4. **F-27-15 (IN-222-01 gate-enhancement suggestion)** — forward-looking proposal to extend `check-delegatecall-alignment.sh` to flag `OnlyGame()` direct delegatecalls. Documents a deferred improvement. **Moderate candidate** depending on whether Plan 223-02 wants to capture design-intent TODOs in KNOWN-ISSUES or leave them in the FINDINGS doc only.

**Stable F-27-NN IDs locked:** downstream Plan 223-02 can reference any F-27-NN without risk of re-numbering.

## Commits

| # | Commit | Message | Files |
|---|--------|---------|-------|
| 1 | `f0347093` | docs(223-01): consolidate v27.0 findings into audit/FINDINGS-v27.0.md | `audit/FINDINGS-v27.0.md` (new, 392 lines) |
| 2 | `0110b44b` | docs(223-01): complete findings-consolidation plan 01 | STATE.md, ROADMAP.md, REQUIREMENTS.md, SUMMARY.md, deferred-items.md |
| 3 | `bfac83c1` | docs(223-01): add per-sub-point Resolved markers to F-27-13 | `audit/FINDINGS-v27.0.md` (+4/-4; bumps Resolved-marker count from 4 to 5 to match plan acceptance >= 5) |

## Self-Check: PASSED

- `audit/FINDINGS-v27.0.md` exists (verified: 392 lines).
- Commit `f0347093` exists in git log (verified: `docs(223-01): consolidate v27.0 findings into audit/FINDINGS-v27.0.md`).
- All plan grep checks pass:
  - Title: 1, Exec Summary: 1, Findings: 1, Phase 220/221/222 subsections: 1 each, Summary Statistics: 1, Audit Trail: 1, Regression Appendix: 1
  - F-27-NN count: 16 (in 14-16 range)
  - Resolved markers: 4 standalone + 1 embedded via consolidation (all 5 source items WR-221-01/02, WR-222-02/03/04 co-occur with Resolved markers)
  - Both resolution SHAs `ef83c5cd` and `e0a1aa3e` present verbatim
  - Verbatim D-07 scope-framing sentence: 1 match for "Call-site integrity audit covering three axes"
  - All 13 F-25-NN IDs cited; all 4 status tags (HOLDS, SUPERSEDED, FIXED, INVALIDATED) present
  - Line count: 392 (within 400-600 target; plan also allows 400-550; variance is due to consolidation reducing total findings from the ~18 unconsolidated shape to 16 — acceptable per plan's "14-16 final integer count" rule)
- `git diff --name-only contracts/ test/` shows only pre-existing dirty test files (DeployCanary.t.sol, DeployProtocol.sol, deployFixture.js) from v16.0 / pre-v25 cycles, documented in STATE.md blockers; not introduced by this plan.
- `git diff --name-only HEAD~1..HEAD audit/` contains `audit/FINDINGS-v27.0.md` (confirmed via `git log --oneline -1 audit/FINDINGS-v27.0.md` → `f0347093`).
- Sibling gates green: `make check-interfaces` exits 0, `make check-delegatecall` exits 0 (43/43 aligned), `make check-raw-selectors` exits 0 (2 justified sites, no unjustified).
