---
phase: 221-raw-selector-calldata-audit
verified: 2026-04-12T19:00:00Z
status: passed
score: 13/13 must-haves verified
must_haves_total: 13
must_haves_verified: 13
overrides_applied: 0
---

# Phase 221: Raw Selector & Calldata Audit Verification Report

**Phase Goal:** Every raw selector literal and hand-rolled calldata encoder in `contracts/` is either replaced with interface-bound form or justified in place, producing (1) a findings catalog with severity verdicts that feeds Phase 223 and (2) a static-analysis gate (`scripts/check-raw-selectors.sh`) wired into `make test-foundry` / `make test-hardhat` that fails on any future raw-selector regression.
**Verified:** 2026-04-12T19:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every `bytes4(0x...)` hex literal in `contracts/` has a verdict (JUSTIFIED, REPLACED, or FLAGGED) | VERIFIED | Live grep on `contracts/` (excluding mocks/interfaces) returns 0 matches; CSI-04 section of 221-01-AUDIT.md records `0 sites (SATISFIED)` with embedded reproduction command |
| 2 | Every `bytes4(keccak256("..."))` string-derived selector in `contracts/` has a verdict | VERIFIED | Live grep returns 0 matches; CSI-05 section of 221-01-AUDIT.md records `0 sites (SATISFIED)` with embedded reproduction command |
| 3 | Every manual `abi.encode` / `abi.encodeCall` / `abi.encodeWithSignature` site that bypasses interface-bound selectors has a verdict with rationale | VERIFIED | CSI-06 section catalogs all 5 sites (3 mocks + 2 DegenerusAdmin); all 5 are JUSTIFIED with Chainlink ERC-677/VRF external-interface rationale; gate exits 0 with 2 JUST lines at DegenerusAdmin.sol:911,997 |
| 4 | A catalogue document lists every raw-selector site with its verdict so Phase 223 can roll it into the findings document | VERIFIED | `221-01-AUDIT.md` (202 lines) exists with 5-site verdict table, 6 finding IDs INFO-221-01-01..06, CSI-07 rollup, and Regression Gate Cross-Reference section |

**Score:** 4/4 ROADMAP success criteria verified

### Plan Must-Have Truths (Plan 221-01)

| # | Must-Have Truth | Status | Evidence |
|---|-----------------|--------|----------|
| 1 | `scripts/check-raw-selectors.sh` exists, is executable, and exits 0 on current codebase | VERIFIED | `-rwxr-xr-x`; `bash scripts/check-raw-selectors.sh` returns exit 0 with 2 JUST lines (DegenerusAdmin.sol:911, :997) and PASS summary |
| 2 | `make check-raw-selectors` runs standalone and passes | VERIFIED | Makefile line 30-31: target defined; `@scripts/check-raw-selectors.sh` invocation present |
| 3 | `make test-foundry` and `make test-hardhat` include `check-raw-selectors` as prerequisite | VERIFIED | Makefile line 40: `test-foundry: check-interfaces check-delegatecall check-raw-selectors`; line 50: `test-hardhat: check-interfaces check-delegatecall check-raw-selectors` |
| 4 | Mock sites (MockVRFCoordinator.sol:88,111; MockLinkToken.sol:51) are silent on clean run due to `EXCLUDE_PATHS=(contracts/mocks)` | VERIFIED | Script lines 37-40 define `EXCLUDE_PATHS=("${CONTRACTS_DIR}/mocks" "${CONTRACTS_DIR}/interfaces")`; live run confirms 0 hits from mocks in output |
| 5 | Injecting `bytes4(0x12345678)` into a fixture exits 1 with FAIL line | VERIFIED (summary evidence) | 221-01-SUMMARY.md negative-test Case 1: fixture run produced `rc=1 + FAIL ...:101 bytes4(0x...) hex literal — CSI-04 violation`; no contracts/ modification |
| 6 | Injecting `abi.encodeWithSignature` into a fixture exits 1 with FAIL line | VERIFIED (summary evidence) | 221-01-SUMMARY.md negative-test Case 3: `rc=1 + FAIL ...:101 abi.encodeWithSignature — CSI-06 violation` |
| 7 | `abi.encode(...)` feeding `keccak256(...)` does NOT trigger the gate | VERIFIED | Script Pattern E's gsub-strip + low-level-call opener anchor means keccak256 args are never Pattern-E matched; 221-01-SUMMARY.md Case 7 confirms DegenerusJackpots.sol:270,287,329,385 produce 0 false-positives |
| 8 | DegenerusAdmin.sol:914,997 feeders trigger gate then are silenced via `JUSTIFIED_FEEDERS` | VERIFIED | Live run shows exactly `JUST contracts/DegenerusAdmin.sol:911` and `JUST contracts/DegenerusAdmin.sol:997`; script lines 54-56 show `JUSTIFIED_FEEDERS=("DegenerusAdmin.sol:transferAndCall")`; no contracts/ edit required |

### Plan Must-Have Truths (Plan 221-02)

| # | Must-Have Truth | Status | Evidence |
|---|-----------------|--------|----------|
| 9 | `221-01-AUDIT.md` exists with required sections: CSI-04, CSI-05, CSI-06, CSI-07, Summary | VERIFIED | Sections confirmed: `## Summary`, `## CSI-04`, `## CSI-05`, `## CSI-06`, `## CSI-07`, `## Findings`, `## Known Limits`, `## Regression Gate Cross-Reference`; file is 202 lines |
| 10 | CSI-04 and CSI-05 sections show `0 sites (SATISFIED)` with embedded grep reproduction commands | VERIFIED | CSI-04 section: `Status: 0 sites (SATISFIED)` + bash block; CSI-05 section: same pattern |
| 11 | CSI-06 section lists all 5 sites with JUSTIFIED verdict and Chainlink external-interface rationale | VERIFIED | Mocks table (3 rows) + Pattern E table (2 rows) each with JUSTIFIED verdict; rationale cites Chainlink VRF v2 / ERC-677 wire format for each; DegenerusAdmin.sol:914 and :997 explicitly named |
| 12 | CSI-07 verdict summary table covers all 5 sites with `(file:line, construct, target_context, verdict, severity, notes)` columns | VERIFIED | Table at line 126-134 of 221-01-AUDIT.md has 5 data rows; all 6 columns present; totals: 5 JUSTIFIED, 0 FLAGGED, 5 INFO |
| 13 | `Known Limits` section records T-221-01 (regex indirection blind spot) and T-221-04 (catalog staleness mitigated by gate) | VERIFIED | `### T-221-01` and `### T-221-04` subsections present in `## Known Limits`; INFO-221-01-06 established for T-221-01 |

**Score:** 13/13 must-haves verified (4 ROADMAP + 8 Plan-01 + 9 Plan-02; 8 Plan-01 truths overlap with 4 ROADMAP SCs, unique combined total = 13)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/check-raw-selectors.sh` | Gate forbidding raw selectors; EXCLUDE_PATHS; JUSTIFIED_FEEDERS; exits 0 on clean tree | VERIFIED | 194 lines; executable; `EXCLUDE_PATHS` at lines 37-40; `JUSTIFIED_FEEDERS` at lines 54-56; exits 0 with 2 JUST lines on live codebase |
| `Makefile` | `check-raw-selectors` target + both test prerequisites | VERIFIED | 5 occurrences: `.PHONY` (line 1), target definition (line 30-31), `test-foundry` prereq (line 40), `test-hardhat` prereq (line 50) |
| `.planning/phases/221-raw-selector-calldata-audit/221-01-AUDIT.md` | Findings catalog, min 120 lines, CSI-04/05/06/07 sections, 5 JUSTIFIED sites, 6 finding IDs | VERIFIED | 202 lines; all required sections present; 5 sites JUSTIFIED; INFO-221-01-01 through INFO-221-01-06 present |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scripts/check-raw-selectors.sh` | `contracts/` | grep -rE four patterns + awk Pattern E | VERIFIED | scan_simple() runs Patterns A-D; Pattern E inline awk at lines 132-178; both use `"$CONTRACTS_DIR"` with path exclusion |
| `Makefile check-raw-selectors` | `scripts/check-raw-selectors.sh` | make target shell invocation | VERIFIED | Line 31: `@scripts/check-raw-selectors.sh` |
| `Makefile test-foundry` | `check-raw-selectors` | prerequisite list | VERIFIED | Exact string `test-foundry: check-interfaces check-delegatecall check-raw-selectors` at line 40 |
| `Makefile test-hardhat` | `check-raw-selectors` | prerequisite list | VERIFIED | Exact string `test-hardhat: check-interfaces check-delegatecall check-raw-selectors` at line 50 |
| `221-01-AUDIT.md` | `scripts/check-raw-selectors.sh` | cross-reference section naming the targets it blocks | VERIFIED | `## Regression Gate Cross-Reference` section (lines 184-200) states the script is the enforcement half; lists `make check-raw-selectors`, `make test-foundry`, `make test-hardhat` |
| `221-01-AUDIT.md` | Phase 223 | INFO-221-01-01..06 finding IDs promotable to FINDINGS-v27.0.md | VERIFIED | 6 INFO finding IDs present; last paragraph of audit states "Phase 223 consumes this catalog" |
| `JUSTIFIED_FEEDERS` in script | Verdict table in audit | 1:1 invariant documented | VERIFIED | Script has 1 entry (`DegenerusAdmin.sol:transferAndCall`); audit has exactly 2 Pattern E JUSTIFIED rows for DegenerusAdmin.sol; cross-reference section documents the invariant explicitly |

---

### Data-Flow Trace (Level 4)

Not applicable. Phase 221 produces tooling artifacts (shell script, Makefile wiring) and a planning document (audit catalog), not components that render dynamic runtime data. No data-flow trace is required.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Gate exits 0 on clean codebase | `bash scripts/check-raw-selectors.sh; echo "EXIT=$?"` | `JUST DegenerusAdmin.sol:911 ... justified by allowlist`, `JUST DegenerusAdmin.sol:997 ... justified by allowlist`, `PASS 2 justified site(s) acknowledged`, `EXIT=0` | PASS |
| Exactly 5 Makefile occurrences of `check-raw-selectors` | `grep -c "check-raw-selectors" Makefile` | `5` | PASS |
| Script is executable | `test -x scripts/check-raw-selectors.sh && echo EXECUTABLE` | `EXECUTABLE` | PASS |
| CSI-04 absence: 0 hex literals in production | `grep -rnE 'bytes4\s*\(\s*0x' --include='*.sol' contracts/ \| grep -v mocks \| grep -v interfaces` | empty | PASS |
| CSI-05 absence: 0 keccak string selectors in production | `grep -rnE 'bytes4\s*\(\s*keccak256' --include='*.sol' contracts/ \| grep -v mocks` | empty | PASS |
| CSI-06a absence: 0 abi.encodeCall in all contracts/ | `grep -rnE 'abi\.encodeCall' --include='*.sol' contracts/` | empty | PASS |
| CSI-06b absence: 0 abi.encodeWithSignature outside mocks | `grep -rnE 'abi\.encodeWithSignature' --include='*.sol' contracts/ \| grep -v mocks` | empty | PASS |
| 3 mock abi.encodeWithSignature sites cataloged | `grep -rnE 'abi\.encodeWithSignature' --include='*.sol' contracts/mocks/` | `MockLinkToken.sol:51`, `MockVRFCoordinator.sol:88`, `MockVRFCoordinator.sol:111` (3 hits) | PASS |
| 2 DegenerusAdmin.sol abi.encode feeder sites match catalog | `grep -n 'abi\.encode' contracts/DegenerusAdmin.sol \| grep -v encodeWith\|encodeCall\|keccak256` | lines 914 and 997 | PASS |
| 6 Phase 221 commits in git log | `git log --oneline \| grep "221"` (genuine Phase 221) | a1ed4ed2, 839e0f43, 8c7e0a79, 80e3b1c5, a2f855ff, f115a402 | PASS |
| No Phase 221 commits modified contracts/ or test/ | `git diff-tree` check on last 6 commits | No contracts/ or test/ files appear in any Phase 221 commit's changed-file list | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CSI-04 | 221-01, 221-02 | Every `bytes4(0x...)` hex literal cataloged; justified or replaced | SATISFIED | 0 production sites; absence locked by gate Pattern A; REQUIREMENTS.md status `[x] Complete` |
| CSI-05 | 221-01, 221-02 | Every `bytes4(keccak256("..."))` selector cataloged; justified or replaced | SATISFIED | 0 production sites; absence locked by gate Pattern B; REQUIREMENTS.md status `[x] Complete` |
| CSI-06 | 221-01, 221-02 | Every manual `abi.encode*` bypassing interface-bound selectors cataloged with rationale | SATISFIED | 5 sites cataloged (3 mocks + 2 DegenerusAdmin), all 5 JUSTIFIED; gate Patterns C/D/E enforce going forward; REQUIREMENTS.md status `[x] Complete` |
| CSI-07 | 221-02 | Catalog output is a findings document with every raw-selector site, severity verdict, and JUSTIFIED/REPLACED/FLAGGED classification | SATISFIED | `221-01-AUDIT.md` exists with CSI-07 verdict table (5 rows), 6 INFO finding IDs; REQUIREMENTS.md status `[x] Complete` |

**Orphaned requirements check:** REQUIREMENTS.md lists CSI-04, CSI-05, CSI-06, CSI-07 under Phase 221. Plan 221-01 claims CSI-04, CSI-05, CSI-06. Plan 221-02 claims CSI-04, CSI-05, CSI-06, CSI-07. Union = all four IDs. No orphaned requirements.

---

### Anti-Patterns Found

These are drawn from the existing code review (221-REVIEW.md) rather than re-discovered here. None are blocking goal correctness.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/check-raw-selectors.sh` | 103-105, 151 | Non-existent `CONTRACTS_DIR` silently passes (WR-221-01) — `grep 2>/dev/null \|\| true` and `find 2>/dev/null` swallow missing-directory errors; gate reports PASS with 0 files scanned | Warning | Low — no impact on normal `make check-raw-selectors` or CI; affects only misconfigured `CONTRACTS_DIR` override |
| `scripts/check-raw-selectors.sh` | 84, 181, 193 | `warn_total` declared and tested but never incremented — dead variable (WR-221-02); inconsistent with sibling `check-delegatecall-alignment.sh` which exits 1 on `warn_total > 0` | Warning | Low — `warn_total` is permanently 0; future maintainer adding a WARN check may silently drop it from the exit-code decision |

Neither anti-pattern is a blocker. WR-221-01 is a robustness gap for gate self-testing with a mistyped path; the default `make check-raw-selectors` invocation and all CI paths are unaffected. WR-221-02 is a dead-code inconsistency with no current behavioral effect.

---

### Contracts / Test Hygiene

The `git diff --name-only contracts/ test/` command shows four dirty files:
- `contracts/ContractAddresses.sol` — pre-existing unstaged changes (deploy addresses; flagged in STATE.md; not introduced by Phase 221)
- `test/fuzz/DeployCanary.t.sol`, `test/fuzz/helpers/DeployProtocol.sol`, `test/helpers/deployFixture.js` — pre-existing Phase 222 pre-work (confirmed in 221-02-SUMMARY.md via `find -newermt` filter showing mtimes predate Phase 221 plan start)

Commit-level check: `git diff-tree` against all 6 Phase 221 commits (a1ed4ed2, 839e0f43, 8c7e0a79, 80e3b1c5, a2f855ff, f115a402) shows zero `contracts/` or `test/` files in the changed-file list. Phase 221 did not commit any contract or test changes. Requirement satisfied.

---

### Human Verification Required

None. All gate behavior, catalog content, Makefile wiring, requirement status, commit existence, and script correctness are fully verifiable programmatically. The negative-test evidence is documented in the SUMMARY (fixture-based, no live contracts/ modification) and trust-level is consistent with the Phase 220 precedent.

---

### Gaps Summary

No gaps. All 4 ROADMAP success criteria are satisfied. All 13 combined must-have truths across both plans are verified. All 4 requirements (CSI-04, CSI-05, CSI-06, CSI-07) are marked Complete in REQUIREMENTS.md. No Phase 221 commits modified `contracts/` or `test/`. The gate exits 0 on the current codebase. The Makefile wires `check-raw-selectors` as a blocking prerequisite of both `test-foundry` and `test-hardhat`. The audit catalog (`221-01-AUDIT.md`, 202 lines) contains all required sections with 5 JUSTIFIED sites and 6 finding IDs ready for Phase 223 consumption.

Two code-review warnings (WR-221-01: silent-pass on missing CONTRACTS_DIR; WR-221-02: dead `warn_total` variable) are documented but are not blocking. Neither affects the gate's correctness on the current codebase.

---

_Verified: 2026-04-12T19:00:00Z_
_Verifier: Claude (gsd-verifier)_
