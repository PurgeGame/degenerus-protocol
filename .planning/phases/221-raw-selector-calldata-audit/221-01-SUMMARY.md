---
phase: 221-raw-selector-calldata-audit
plan: 01
subsystem: tooling
tags: [audit, gate, regression, csi-04, csi-05, csi-06]
dependency_graph:
  requires: [220-01, 220-02]
  provides: [221-02]
  affects: [test-foundry, test-hardhat]
tech_stack:
  added: []
  patterns:
    - "bash + awk source-text gate (Phase 220 architecture)"
    - "Two-pass awk slurp-then-scan to avoid getline NR-advancement bugs"
    - "gsub-strip of already-handled encode forms before bare abi.encode*(...) match"
    - "Content-based allowlist (JUSTIFIED_FEEDERS) paired with path-level exclusion (EXCLUDE_PATHS)"
    - "Inline `// raw-selectors: justified — <reason>` marker override"
key_files:
  created:
    - scripts/check-raw-selectors.sh
  modified:
    - Makefile
decisions:
  - "One scan_simple() helper consolidates Patterns A-D into a single while loop so the four simple grep-based scans share identical FAIL/JUST/counter logic. Kept Pattern E inline because its two-pass awk body does not fit the helper's signature. Delivered script at 194 lines (≤200 target)."
  - "Process substitution `done < <(find ... | awk ... | sort -u)` used across every scan so subshell counters propagate back to the outer shell — prevents silent false-negative where a pipe-fed while loop would increment fail_total in a subshell and lose it."
  - "Opener regex for Pattern E: `\\.(call|delegatecall|staticcall|transferAndCall)[[:space:]]*(\\{[^}]*\\})?[[:space:]]*\\(` — the optional `{...}` block handles `.call{value: x}(` and `.delegatecall{gas: g, value: v}(` which the baseline plan sample did not cover explicitly. Required to avoid missing future call-value forms."
metrics:
  duration_minutes: 10
  completed: "2026-04-12T13:05:00Z"
  line_count: 194
  task_count: 3
  file_count: 2
---

# Phase 221 Plan 01: Raw Selector & Calldata Gate Summary

Installed `scripts/check-raw-selectors.sh` — a bash+awk gate that blocks `bytes4(0x...)` / `bytes4(keccak256("..."))` selector literals, `abi.encodeWithSignature` / `abi.encodeCall` calls, and raw `abi.encode*(...)` payloads feeding `.call`/`.delegatecall`/`.staticcall`/`.transferAndCall` in production `contracts/`; wired as sibling prerequisite of `test-foundry` and `test-hardhat` alongside `check-interfaces` and `check-delegatecall`.

## Baseline (re-verified)

All four CSI counts matched the planner's expected state — nothing new appeared between planning and execution:

| Scan | Command (outside mocks/ + interfaces/) | Expected | Observed |
|------|---------------------------------------|----------|----------|
| CSI-04 | `bytes4\s*\(\s*0x[0-9a-fA-F]+` | 0 | 0 |
| CSI-05 | `bytes4\s*\(\s*keccak256` | 0 | 0 |
| CSI-06 encodeCall | `abi\.encodeCall` | 0 | 0 |
| CSI-06 encodeWithSignature (prod) | `abi\.encodeWithSignature` | 0 | 0 |
| CSI-06 encodeWithSignature (all) | `abi\.encodeWithSignature` (no filter) | 3 | 3 |
| Pattern E transferAndCall feeders | `abi\.encode\(` in DegenerusAdmin.sol | lines 914, 997 | lines 914, 997 |

Mocks sites (path-excluded, silent at the gate): `contracts/mocks/MockVRFCoordinator.sol:88,111`, `contracts/mocks/MockLinkToken.sol:51`.

Pattern E sites (allowlisted via JUSTIFIED_FEEDERS="DegenerusAdmin.sol:transferAndCall"):
- `contracts/DegenerusAdmin.sol:911` — opener for `linkToken.transferAndCall(..., abi.encode(newSubId))` spanning lines 911-915
- `contracts/DegenerusAdmin.sol:997` — single-line `linkToken.transferAndCall(coord, amount, abi.encode(subId))`

Both are ERC-677 Chainlink LINK token calls — the target interface lives outside this repo, so the raw `abi.encode(...)` is the required form. Plan 02 will record the JUSTIFIED verdict in `221-01-AUDIT.md`.

## Deliverables

| File | Change | Purpose |
|------|--------|---------|
| `scripts/check-raw-selectors.sh` | Created (194 lines, executable) | Regression gate for all three CSI-04/05/06 pattern classes |
| `Makefile` | Added `.PHONY`, target block, test-foundry + test-hardhat prerequisites | Block `make test` on any gate failure |

Makefile now lists `check-raw-selectors` five times: `.PHONY` line (1), target definition (2 — header comment + target), and both test-target prerequisite lists.

## Script architecture

Mirrors `scripts/check-delegatecall-alignment.sh` (Phase 220) and `scripts/check-interface-coverage.sh`:

- `#!/usr/bin/env bash` + `set -euo pipefail` + `cd "$(dirname "$0")/.."` + `CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"` override
- Color constants (`RED`, `GREEN`, `YELLOW`, `NC`)
- Visible `EXCLUDE_PATHS` constant array (path-level exclusion)
- Visible `JUSTIFIED_FEEDERS` constant array (content-based allowlist for Pattern E)
- Two helper functions: `is_justified` (inline comment marker check, 2-line window) and `is_justified_feeder` (basename + opener-content match)
- Consolidated `scan_simple()` runs Patterns A-D (4 grep-based single-line scans); Pattern E inlined with its own two-pass awk
- Pattern E uses slurp-into-array + END-block scan to avoid `getline` NR-advancement skipping back-to-back openers
- Pattern E `gsub`-strips `abi.encodeWithSelector(`, `abi.encodeWithSignature(`, `abi.encodeCall(` to placeholder tokens before testing for bare `abi.encode(Packed)?(` — prevents double-FAIL where Patterns C/D already flagged a site
- Process substitution `done < <(...)` on every scan so subshell counter increments propagate to the outer `fail_total` / `justified_total`
- Exit 0 if `fail_total == 0 && warn_total == 0`, exit 1 otherwise

## Negative-test evidence

All 7 cases passed. Fixture lived under `/tmp/gsd-221-01-fixture/` with `CONTRACTS_DIR` override; no `contracts/` or `test/` modification. Evidence log: `/tmp/221-01-negtest.log`.

| Case | Description | Expected | Observed |
|------|-------------|----------|----------|
| 1 | Inject `bytes4(0x12345678)` into DegenerusGame.sol fixture | rc=1 + FAIL for CSI-04 | rc=1 ✓ `FAIL ...:101 bytes4(0x...) hex literal — CSI-04 violation` |
| 2 | Inject `bytes4(keccak256("transfer(...)"))` into DegenerusGame.sol | rc=1 + FAIL for CSI-05 | rc=1 ✓ `FAIL ...:101 bytes4(keccak256(...)) selector — CSI-05 violation` |
| 3 | Inject `foo.call(abi.encodeWithSignature("transfer(...)", ...))` into DegenerusJackpots.sol | rc=1 + FAIL for CSI-06 | rc=1 ✓ `FAIL ...:101 abi.encodeWithSignature — CSI-06 violation` |
| 4 | Inject `foo.call(abi.encode(uint256(42)))` into BurnieCoinflip.sol (Pattern E) | rc=1 + FAIL for Pattern E | rc=1 ✓ `FAIL ...:101 abi.encode*(...) payload of low-level call — CSI-06 violation (interface-bound form required)` |
| 5 | Same as Case 1 plus `// raw-selectors: justified — ...` on preceding line | rc=0 + JUST line | rc=0 ✓ `JUST ...:102 bytes4(0x...) hex literal — justified by marker` |
| 6 | Real-tree run: mocks must NOT appear in output | 0 mock hits | 0 hits ✓ |
| 7 | Real-tree run: keccak256(abi.encode*(...)) at DegenerusJackpots.sol:270,287,329,385 must NOT trigger Pattern E | 0 false-positives | 0 hits ✓ |

Final real-tree run after fixture removal: exit 0 with 2 `JUST` lines (DegenerusAdmin.sol:911, 997) and `PASS` summary — matches the Plan 02 expected baseline.

## Override mechanisms used

- **JUSTIFIED_FEEDERS allowlist:** 1 entry — `DegenerusAdmin.sol:transferAndCall` — silences the 2 Chainlink ERC-677 transferAndCall feeders. Zero contract edits required.
- **Inline `// raw-selectors: justified — <reason>` marker:** defined but not used in production source (reserved for future per-site overrides). Exercised by negative-test Case 5 against a `/tmp` fixture.

## Requirements Completed

- **CSI-04:** gate blocks `bytes4(0x...)` hex literal anywhere in production. Locked in.
- **CSI-05:** gate blocks `bytes4(keccak256("..."))` string-derived selector anywhere in production. Locked in.
- **CSI-06:** gate blocks `abi.encodeWithSignature` / `abi.encodeCall` / `abi.encode*`-feeding-low-level-call in production. Locked in.

All three satisfied by absence plus the regression gate. Plan 02 consumes this gate's output for verdict-assignment in the `221-01-AUDIT.md` catalog.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | `a1ed4ed2` | `feat(221-01): install Makefile wiring and skeleton for check-raw-selectors` |
| 2 | `839e0f43` | `feat(221-01): implement check-raw-selectors scanner (5 patterns, 194 lines)` |
| 3 | (verification-only, no commit) | 7 negative-test cases passed; fixture removed; `git diff contracts/ test/` shows no Plan 221 changes |

## Deviations from Plan

None — plan executed exactly as written. One minor implementation choice documented in decisions: consolidated Patterns A-D into a `scan_simple()` helper to bring the script from 229 lines (raw Plan 2 prose implementation) down to 194 lines (≤200 line target); behaviour identical.

One regex strengthening beyond the planner's sample: Pattern E's opener match now tolerates `\.call{value: x}\(` / `\.delegatecall{gas: g}\(` by accepting an optional `\{[^}]*\}` between the method name and the opening paren. The sample in the plan did not cover call-option blocks explicitly; caught during implementation review. Pre-existing behaviour of the gate remains (the 2 DegenerusAdmin call sites do not use call-options).

## Self-Check: PASSED

- `scripts/check-raw-selectors.sh` exists and is executable: FOUND
- `Makefile` contains 5 mentions of `check-raw-selectors`: VERIFIED
- Commit `a1ed4ed2` exists in `git log`: FOUND
- Commit `839e0f43` exists in `git log`: FOUND
- `bash scripts/check-raw-selectors.sh` exits 0 on clean tree: VERIFIED (rc=0, 2 JUST, PASS)
- `wc -l scripts/check-raw-selectors.sh` ≤ 200: VERIFIED (194 lines)
- 7 negative-test cases recorded in `/tmp/221-01-negtest.log`: FOUND
- No Phase 221 changes under `contracts/` or `test/`: VERIFIED (`git diff --name-only HEAD~2..HEAD` = `Makefile` + `scripts/check-raw-selectors.sh`)
