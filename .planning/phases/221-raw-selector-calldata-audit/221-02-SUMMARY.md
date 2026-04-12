---
phase: 221-raw-selector-calldata-audit
plan: 02
subsystem: audit
tags: [audit, catalog, csi-04, csi-05, csi-06, csi-07, chainlink, vrf, erc-677]
dependency_graph:
  requires:
    - phase: 221-01
      provides: check-raw-selectors.sh gate with EXCLUDE_PATHS (mocks, interfaces) and JUSTIFIED_FEEDERS (DegenerusAdmin.sol:transferAndCall) — Plan 02 consumes the gate output and assigns verdicts to each cataloged site
    - phase: 220-01
      provides: reference catalog format (summary -> per-site table -> findings -> cross-reference) that Plan 221-02 mirrors
  provides:
    - "221-01-AUDIT.md — the single Phase 221 findings catalog feeding Phase 223 rollup"
    - "6 INFO finding IDs (INFO-221-01-01 .. INFO-221-01-06) ready for audit/FINDINGS-v27.0.md promotion"
    - "Verdict layer for CSI-04 (SATISFIED by absence) and CSI-05 (SATISFIED by absence)"
    - "Verdict layer for CSI-06: 5 JUSTIFIED sites (3 mocks + 2 DegenerusAdmin), 0 FLAGGED"
    - "CSI-07 verdict summary table (6-column format per D-11)"
  affects:
    - 223-findings-consolidation
tech-stack:
  added: []
  patterns:
    - "Audit artifact as enforcement-snapshot pair with the gate script (JUSTIFIED_FEEDERS <-> JUSTIFIED rows invariant)"
    - "Completeness enumeration of path-excluded mocks in the catalog even when the gate silences them"
    - "Reproduction commands embedded beside every SATISFIED section so a reader can re-verify absence in one command"
key-files:
  created:
    - .planning/phases/221-raw-selector-calldata-audit/221-01-AUDIT.md
  modified: []
key-decisions:
  - "[221-02]: Added INFO-221-01-06 as a standalone finding ID for the regex-gate coverage limit (T-221-01) so Phase 223 can promote the accepted residual risk as its own INFO entry instead of folding it into the T-221-01 Known Limit prose"
  - "[221-02]: DegenerusAdmin.sol:911 labeled opener-line and :914 labeled payload-line per D-11 spec; both line numbers surface in the verdict table so a reader can resolve the site from either the gate output (911, opener-anchored) or a text search for abi.encode( (914)"
  - "[221-02]: Enclosing function names recorded per site (_executeSwap / onTokenTransfer for DegenerusAdmin; transferAndCall / fulfillRandomWords / fulfillRandomWordsRaw for the mocks) to give Phase 223 reviewers immediate call-context without re-reading source"
patterns-established:
  - "Audit catalog format: Summary -> CSI-04 -> CSI-05 -> CSI-06 (Patterns C/D/E subsections) -> CSI-07 rollup -> Findings (one entry per INFO-ID) -> Known Limits -> Regression Gate Cross-Reference"
  - "Reproduction command embedded in every SATISFIED section (absence provable by a reader without re-running the whole gate)"
  - "Opener-vs-payload column pair in multi-line Pattern E rows (records both line numbers so gate output and source search resolve to the same row)"
requirements-completed:
  - CSI-04
  - CSI-05
  - CSI-06
  - CSI-07

# Metrics
duration: 4min
completed: 2026-04-12
---

# Phase 221 Plan 02: Raw Selector & Calldata Audit Summary

**Wrote `221-01-AUDIT.md` (202 lines) — the Phase 221 verdict catalog: 5 JUSTIFIED INFO sites (3 Chainlink-mocks VRF/ERC-677 wire-format mimics + 2 DegenerusAdmin ERC-677 transferAndCall feeders), 0 FLAGGED, 0 HIGH; CSI-04 and CSI-05 SATISFIED BY ABSENCE with embedded reproduction greps; 6 finding IDs (INFO-221-01-01..06) ready for Phase 223 rollup.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-12T18:07:50Z
- **Completed:** 2026-04-12T18:12:07Z
- **Tasks:** 1 of 1
- **Files modified:** 1 (audit catalog created)

## Accomplishments

- Re-ran `scripts/check-raw-selectors.sh` at execution time; confirmed exit 0 and 2 `JUST` lines at DegenerusAdmin.sol:911 and :997 — Plan 221-01 baseline still holds
- Re-verified all four scout grep counts match the Plan 221-01 baseline: CSI-04=0, CSI-05=0, `abi.encodeCall`=0, `abi.encodeWithSignature` outside mocks=0; 3 inside mocks; 2 `abi.encode` feeders in DegenerusAdmin.sol (lines 914, 997). Zero divergence
- Wrote `.planning/phases/221-raw-selector-calldata-audit/221-01-AUDIT.md` with 202 lines, 5 cataloged sites, 22 `JUSTIFIED` mentions (22 includes table rows + tally rows + prose; 5 is the per-site verdict count), 0 FLAGGED verdicts (the 4 literal `FLAGGED` occurrences in the doc are all tally/summary rows showing `0 FLAGGED`)
- Finding IDs INFO-221-01-01 through INFO-221-01-06 established (5 per-site JUSTIFIED + 1 accepted residual risk from T-221-01 regex-gate limit)
- All three sibling gates (`check-raw-selectors`, `check-delegatecall`, `check-interfaces`) exit 0 post-plan
- No contracts/ or test/ writes introduced by this plan (verified via `find . -newermt` filter — only the audit file appeared)

## Verdict Distribution

| Verdict | Count |
|---------|------:|
| JUSTIFIED | 5 |
| REPLACED | 0 |
| FLAGGED | 0 |
| DOCUMENTED | 0 |

## Severity Distribution

| Severity | Count |
|----------|------:|
| HIGH | 0 |
| MEDIUM | 0 |
| INFO | 5 |

## Cataloged Sites

| # | file:line | construct | verdict | severity | finding ID |
|---|-----------|-----------|---------|----------|------------|
| 1 | contracts/mocks/MockVRFCoordinator.sol:88 | abi.encodeWithSignature | JUSTIFIED | INFO | INFO-221-01-01 |
| 2 | contracts/mocks/MockVRFCoordinator.sol:111 | abi.encodeWithSignature | JUSTIFIED | INFO | INFO-221-01-02 |
| 3 | contracts/mocks/MockLinkToken.sol:51 | abi.encodeWithSignature | JUSTIFIED | INFO | INFO-221-01-03 |
| 4 | contracts/DegenerusAdmin.sol:911 (opener) / :914 (payload) | abi.encode | JUSTIFIED | INFO | INFO-221-01-04 |
| 5 | contracts/DegenerusAdmin.sol:997 | abi.encode | JUSTIFIED | INFO | INFO-221-01-05 |

Plus INFO-221-01-06 — accepted residual risk for regex-gate indirection blind spot (Known Limit T-221-01).

## Baseline Re-Verification

Counts at Plan 221-02 execution time matched Plan 221-01 Task 1 scout exactly:

| Scan | Expected | Observed | Match |
|------|---------:|---------:|:-----:|
| CSI-04 `bytes4(0x...)` outside mocks/interfaces | 0 | 0 | yes |
| CSI-05 `bytes4(keccak256)` outside mocks/interfaces | 0 | 0 | yes |
| CSI-06a `abi.encodeCall` outside mocks/interfaces | 0 | 0 | yes |
| CSI-06b `abi.encodeWithSignature` outside mocks | 0 | 0 | yes |
| CSI-06c `abi.encodeWithSignature` inside mocks | 3 | 3 | yes |
| CSI-06d `abi.encode(` in DegenerusAdmin.sol | 2 | 2 (lines 914, 997) | yes |
| Gate output: JUST lines | 2 | 2 (lines 911, 997) | yes |

No divergence. No FLAGGED sites surfaced. No code change required.

## Known Limits Documented

- **T-221-01 (ACCEPTED):** `check-raw-selectors.sh` is a pattern-matcher; variable indirection and intermediate casts can slip past. Mitigation: Phase 222 external-coverage audit exercises all entry points at runtime so masked selectors cannot hide on unexercised paths. Tracked as INFO-221-01-06 for Phase 223 INFO-tier promotion.
- **T-221-04 (MITIGATED by the gate):** catalog staleness is prevented by the gate itself — any new `abi.encode*` feeder, hex literal, or keccak selector fails `make test` before merge unless an explicit override is added, and both override paths (inline marker + `JUSTIFIED_FEEDERS`) are visible-diff PR-reviewed (T-221-02 mitigation from Plan 221-01 threat model).

## Gate Runs Clean (Post-Plan Verification)

- `make check-raw-selectors`: **exit 0** — 2 JUST lines (DegenerusAdmin.sol:911, :997), PASS summary
- `make check-delegatecall`: **exit 0** — 43/43 delegatecall sites aligned (Phase 220 gate unaffected)
- `make check-interfaces`: **exit 0** — all interface functions have matching implementations (pre-existing gate unaffected)

## Task Commits

Each task was committed atomically:

1. **Task 1: Write 221-01-AUDIT.md with verdicts** — `80e3b1c5` (docs)

## Files Created/Modified

- `.planning/phases/221-raw-selector-calldata-audit/221-01-AUDIT.md` — CREATED, 202 lines. Phase 221 findings catalog (summary + CSI-04/CSI-05/CSI-06/CSI-07 sections + Findings + Known Limits + Regression Gate Cross-Reference). Feeds Phase 223 `audit/FINDINGS-v27.0.md`.

## Decisions Made

- Added INFO-221-01-06 as a standalone finding ID for the regex-gate coverage limit (T-221-01). Reason: gives Phase 223 a clean INFO entry to promote instead of forcing it to cite the prose-only Known Limits section. The finding ID is anchored on the accepted-residual-risk disposition per D-12/D-13 (residual risks documented in the catalog are INFO by default).
- Per-site rows for Pattern E (DegenerusAdmin lines 911/914 and 997) include enclosing function context (`_executeSwap` / `onTokenTransfer`) and both the opener-line and the payload-line. Reason: the gate output anchors on the opener (911), but a text search for `abi.encode(` lands on the payload (914) — recording both means either entry point resolves to the same catalog row.
- For the 3 mocks rows, the `target_context` column records the exact `.call("<signature>", ...)` receiver.method form so a reader can reconstruct the on-wire selector without re-reading the mock source.

## Deviations from Plan

None — plan executed exactly as written. The `<interfaces>` block in the plan specified 5 INFO findings (INFO-221-01-01..05); I added a sixth INFO-221-01-06 for the T-221-01 residual-risk case to match the plan's success-criterion #3 which states "Phase 223 has concrete content to promote as INFO" (promoting the accepted risk as its own row is cleaner than burying it in Known Limits prose). This addition is additive and covered by the plan's wording about "Plus optional INFO-221-01-06 for known limit" in the orchestrator's project_constraints block.

## Issues Encountered

- Pre-existing unstaged changes in `contracts/ContractAddresses.sol` (deploy addresses — flagged in STATE.md blockers) and in three `test/fuzz/` and `test/helpers/` files (Phase 222 pre-work). Confirmed via `find -newermt "@<plan_start_epoch>"` that these were all pre-existing (mtimes predate plan start) and not introduced by this plan. The project's pre-commit hook would normally reject a commit while `contracts/` is dirty, but the orchestrator authorized `CONTRACTS_COMMIT_APPROVED=1` prefixing for Phase 221 commits (this plan writes only to `.planning/phases/...`). Commit went through cleanly.
- The `.planning/` directory is gitignored, but prior planning commits (e.g., `8c7e0a79`, `891f61f6`) used `git add -f` to force-stage planning artifacts. Followed the same pattern for this plan's audit file.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 222 (External Function Coverage Gap) can start. Its first task — fixing the `test/fuzz/FuturepoolSkim.t.sol` compile error for CSI-08 — is unblocked. The test/ tree's pre-existing unstaged changes in `test/fuzz/DeployCanary.t.sol`, `test/fuzz/helpers/DeployProtocol.sol`, and `test/helpers/deployFixture.js` appear to be Phase 222 pre-work; they should feed naturally into Phase 222 Task 1.
- Phase 223 (Findings Consolidation) has its Phase 221 input ready: `.planning/phases/221-raw-selector-calldata-audit/221-01-AUDIT.md` with 6 INFO finding IDs, verdict-severity table, and the CSI-07 rollup formatted identically to the Phase 220 pattern. Schema-compatible with `audit/FINDINGS-v25.0.md` style.
- CSI-04, CSI-05, CSI-06, CSI-07 all now complete at both the gate layer (Plan 221-01) and the verdict layer (Plan 221-02). Phase 221 is ready for phase-level close-out.

## Self-Check: PASSED

- `.planning/phases/221-raw-selector-calldata-audit/221-01-AUDIT.md` exists and is 202 lines (>= 120 min): FOUND
- `## CSI-04`, `## CSI-05`, `## CSI-06`, `## CSI-07`, `## Summary`, `## Findings`, `## Known Limits`, `## Regression Gate Cross-Reference`: all present (verified via grep)
- `SATISFIED` framing in CSI-04 and CSI-05 sections: present
- All 5 file:line references present (`MockVRFCoordinator.sol:88`, `:111`, `MockLinkToken.sol:51`, `DegenerusAdmin.sol:911`/`:914`, `DegenerusAdmin.sol:997`): verified
- `JUSTIFIED` occurrences: 22 (well above >= 5 threshold; includes table cells + tally rows + prose)
- `FLAGGED` occurrences: 4 — all in tally/summary rows (`FLAGGED | 0`, `0 FLAGGED`, etc.), zero per-site FLAGGED verdicts
- Finding IDs `INFO-221-01-0` present: 6 (INFO-221-01-01..06)
- `check-raw-selectors` cross-reference present: verified
- `T-221-01` and `T-221-04` Known Limits referenced: verified
- Commit `80e3b1c5` exists in git log: FOUND
- `git diff --quiet contracts/` / `git diff --quiet test/` reflect ONLY pre-existing unstaged changes (mtimes predate plan start): verified via `find -newermt`
- `make check-raw-selectors`, `make check-delegatecall`, `make check-interfaces` all exit 0 post-plan: verified

---
*Phase: 221-raw-selector-calldata-audit*
*Completed: 2026-04-12*
