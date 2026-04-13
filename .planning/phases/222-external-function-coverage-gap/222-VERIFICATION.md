---
phase: 222-external-function-coverage-gap
verified: 2026-04-12T00:00:00Z
status: resolved
score: 4/4 success criteria verified (all gaps closed by 222-03-PLAN)
overrides_applied: 0
gaps:
  - truth: "Every CRITICAL_GAP function has at least one new test exercising it on a realistic path (conditional entry points where the real bug would manifest, not just direct invocation with happy-path args)"
    status: resolved
    resolved_by: 222-03-PLAN
    resolved_at: 2026-04-12
    resolution_commits:
      - sha: ef83c5cd
        message: "test(222-03): strengthen CoverageGap222.t.sol tests (close VERIFICATION Gap 1)"
    resolution_notes: "62 reachability-only tests rewritten to assert guard-rejection (assertFalse(ok, ...) minimum) or observable state change. test_gap_lifecycle_purchase_then_advanceGame now uses pre/post snapshot with assertGt instead of the tautological uint32 >= 0 check (WR-04). Four orphan silence-unused comment lines removed from kept tests. 9 tests adjusted to use assertTrue for calls that legitimately succeed on the happy path (self-service setters, standard ERC20 approve, open propose/createAffiliateCode, no-op whale-pass claim). Final count: 76 tests still pass (same as pre-edit), zero assertTrue(true, ...), zero // silence unused comments."
    reason: "62 of 76 tests in CoverageGap222.t.sol use assertTrue(true, '...reachable') as their sole assertion — the call result is discarded. These tests fire the guard-revert branch and will cause forge coverage to register a branch hit, but they do not assert that the guard rejects for the correct reason, accepts when it should, or produces a specific observable state change. A guard that silently no-ops, accepts unauthorized callers, or reverts with the wrong selector would pass all 62 of these tests undetected. The 14 tests with real behavioral assertions (icons32 write/lock tests, setOperatorApproval, admin onlyOwner reversal, deityPass owner-gate) show the correct pattern. WR-04 also applies: test_gap_lifecycle_purchase_then_advanceGame asserts `ticketsOwedView(lvl0, buyer) >= 0`, which is always true for a uint32, making it vacuous."
    artifacts:
      - path: "test/fuzz/CoverageGap222.t.sol"
        issue: "62 of 76 tests (lines: 128, 160, 183, 193, 204, 221, 238, 246, 260, 278, 295, 311, 321, 347, 362, 425, 482, 505, 520, 546, and others) end in assertTrue(true, '...') with the call-result variable silenced as unused. Also: test_gap_lifecycle_purchase_then_advanceGame line 60 asserts `uint32 >= 0` (always true)."
    missing:
      - "For guarded mutators (onlyGame / onlyVault / onlyOwner / onlyFlipCreditors etc.): replace assertTrue(true, ...) with assertFalse(ok, ...) to verify the guard actually rejected — this is the minimum change that makes the test meaningful. Preferred: vm.prank + vm.expectRevert(ContractName.ErrorSelector.selector) so the exact revert reason is enforced."
      - "For test_gap_lifecycle_purchase_then_advanceGame: snapshot ticketsOwedView before the purchase and assert the post-purchase value is strictly greater (assertGt), or assert the return value of ticketsOwedView == qty if the purchase succeeded."
  - truth: "coverage-check.sh drift check is contract-scoped (a drifted function in one contract cannot be masked by a same-named function in another contract)"
    status: resolved
    resolved_by: 222-03-PLAN
    resolved_at: 2026-04-12
    resolution_commits:
      - sha: e0a1aa3e
        message: "feat(222-03): scope coverage-check drift mode to contract sections (close VERIFICATION Gap 2)"
    resolution_notes: "Preflight parser populates contract_fns[<section-key>] from the matrix ### Contract: headers; check_matrix_drift uses a scoped `;fn;` membership test instead of the global grep. Negative tests verified: existing DegenerusStonk __pokeCoverageGate injection still fires FAIL_DRIFT with exit 1, and NEW DeityBoonViewer transfer injection now fires FAIL_DRIFT (pre-fix it would have PASSED because BurnieCoin's section already anchors `transfer(`). The fix also surfaced a real matrix drift that the pre-fix global grep was masking: DegenerusGame.sol's external self-call wrapper emitDailyWinningTraits (added in commit e4064d67) was only rowed under the JackpotModule section. Added a CRITICAL_GAP row to the DegenerusGame.sol section to close that drift. Script length 285 lines (<= 300 budget). check_uncured_gaps and check_regressed_coverage preserved verbatim."
    reason: "check_matrix_drift in scripts/coverage-check.sh uses a global grep across the entire matrix for the function-name anchor `fn(`. Multiple deployed contracts export identical names (approve, transfer, transferFrom, burn, mint, etc.). If a new deployable contract adds transfer() without a matrix row, the drift check passes because BurnieCoin's `transfer(` row satisfies the grep. WR-03 from code review. The enforcement is weaker than D-16 'no uncategorized externals' requires."
    artifacts:
      - path: "scripts/coverage-check.sh"
        issue: "Line 104: `grep -qF \"`${name}(\" \"$MATRIX_FILE\"` searches the entire file for the function name, not within the section for the source contract. Any contract with a same-named function anywhere in the matrix will mask the drift."
    missing:
      - "Scope the drift grep to the `### Contract: \\`<basename>\\`` section of the matrix for the source file being checked. Build a per-contract function set from the matrix (one pass over the matrix before the source scan loop), then test membership against the relevant section."
human_verification: []
---

# Phase 222: External Function Coverage Gap — Verification Report

**Phase Goal:** Every external/public function on a deployed contract is classified as COVERED, CRITICAL_GAP, or EXEMPT — and every CRITICAL_GAP has at least one new test exercising it on a realistic path, so a future `mintPackedFor`-class bug cannot hide in unexercised surface.
**Verified:** 2026-04-12
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `test/fuzz/FuturepoolSkim.t.sol` compile error (`_applyTimeBasedFutureTake` undeclared identifier) is fixed so `forge coverage` runs to completion | VERIFIED | Zero occurrences of `_applyTimeBasedFutureTake` or `setLevelStartTime` anywhere under `test/` (grep confirmed). `FuturepoolSkim.t.sol` retains `SkimHarness is DegenerusGameAdvanceModule` for exposed getters per D-03. `SkimHarness` compiles. `222-01-COVERAGE-SUMMARY.txt` (155KB) exists as evidence forge ran to completion on post-fix tree. |
| 2 | `forge coverage --report summary` produces per-function line and branch coverage data for every deployed contract | VERIFIED | `222-01-COVERAGE-SUMMARY.txt` (155KB) contains a per-file `| File | % Lines | % Statements | % Branches | % Funcs |` table. `222-02-COVERAGE-SUMMARY.txt` (143KB) is the post-`e4064d67` refresh. `222-02-lcov.info` (232KB, 982 `FNDA:` entries) provides the per-function invocation counts used for the lcov overlay in the matrix. Both files committed. `--ir-minimum` workaround documented in Method Notes. |
| 3 | Every external/public function on a deployed contract has a recorded classification (COVERED / CRITICAL_GAP / EXEMPT) with documented rationale for EXEMPTions | VERIFIED | `222-01-COVERAGE-MATRIX.md` contains 308 function rows: 19 COVERED / 177 CRITICAL_GAP / 112 EXEMPT. Row counts confirmed by grep (`\| COVERED \|` = 19 function rows + 1 summary-table row = 20 raw; `\| CRITICAL_GAP \|` = 177 + 1 = 178 raw; `\| EXEMPT \|` = 112 + 1 = 113 raw). All EXEMPT rows carry D-11 (view/pure) or D-12 (callback) rationale. Zero empty-verdict cells. Zero `(none)` Test Ref cells on CRITICAL_GAP rows. Phase 223 Handoff Preview section present with final totals. |
| 4 | Every CRITICAL_GAP function has at least one new test exercising it on a realistic path (conditional entry points where the real bug would manifest, not just direct invocation with happy-path args) | PARTIAL | `test/fuzz/CoverageGap222.t.sol` exists with 76 tests (confirmed by `grep -c 'function test_'`). Every CRITICAL_GAP row carries a Test Ref. However, 62 of 76 tests end in `assertTrue(true, '...')` with the call result silenced. Tests DO fire conditional-entry guard-revert branches (EOA calling gated functions), so forge coverage registers branch hits. But test assertions do not enforce that the guard rejects (vs. accepts silently) or that the revert carries the correct selector. See Gap 1 below for full analysis. |

**Score:** 3/4 success criteria fully verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/fuzz/FuturepoolSkim.t.sol` | Rewritten skim test with no `_applyTimeBasedFutureTake` reference; `SkimHarness` retained | VERIFIED | File contains `contract SkimHarness is DegenerusGameAdvanceModule`, exposes `exposed_nextToFutureBps`, `exposed_setPrizePools`, `exposed_getPrizePools`. Zero stale references. |
| `.planning/phases/222-external-function-coverage-gap/222-01-COVERAGE-MATRIX.md` | 308-row classification matrix, COVERED/CRITICAL_GAP/EXEMPT verdicts, Phase 223 Handoff section | VERIFIED | 308 rows, correct verdict counts, Handoff Preview at line 558, zero empty Test Ref cells. |
| `.planning/phases/222-external-function-coverage-gap/222-01-COVERAGE-SUMMARY.txt` | Verbatim `forge coverage --report summary` output | VERIFIED | 155KB file containing per-file coverage table header `| File |`. |
| `scripts/coverage-check.sh` | Standalone gate with three failure modes (DRIFT/GAP/REGRESS), bash+awk, CONTRACTS_DIR env override, PASS/FAIL output, colored constants | VERIFIED with caveat | Exists, executable (`-rwxr-xr-x`), 255 lines (under 300-line target). `set -euo pipefail` + `cd "$(dirname "$0")/.."` + `CONTRACTS_DIR` env override + `RED`/`GREEN`/`YELLOW`/`NC` constants + `PASS`/`FAIL_DRIFT`/`FAIL_GAP`/`FAIL_REGRESS` output present. Does NOT invoke `forge coverage`. All three failure-mode functions (`check_matrix_drift`, `check_uncured_gaps`, `check_regressed_coverage`) implemented. Caveat: DRIFT mode is not contract-scoped — see Gap 2. |
| `Makefile` | `coverage-check:` target as STANDALONE, NOT prereq of `test-foundry`/`test-hardhat` | VERIFIED | Line 43: `coverage-check:` target exists. Line 1: `coverage-check` in `.PHONY`. `test-foundry:` and `test-hardhat:` prereqs are `check-interfaces check-delegatecall check-raw-selectors` only — `coverage-check` not present. D-16 satisfied. |
| `test/fuzz/CoverageGap222.t.sol` | New test file with integration-style CRITICAL_GAP tests via natural caller chains | VERIFIED with caveat | Exists, 1711 lines, 76 test functions confirmed by grep. `contract CoverageGap222 is DeployProtocol` with `setUp` calling `_deployProtocol()`. 15 sections A–O organized by target contract. Caveat: 62 of 76 tests use reachability-only assertions. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `test/fuzz/FuturepoolSkim.t.sol` | `contracts/modules/DegenerusGameAdvanceModule.sol` | `contract SkimHarness is DegenerusGameAdvanceModule` | VERIFIED | Pattern confirmed at line 38 of FuturepoolSkim.t.sol |
| `222-01-COVERAGE-MATRIX.md` | `222-02-lcov.info` | Branch-coverage numbers from `forge coverage --report lcov` | VERIFIED | `222-02-lcov.info` (232KB, 982 FNDA entries) exists. Matrix Method Notes document lcov as data source and reference both `222-01-COVERAGE-SUMMARY.txt` and `222-02-COVERAGE-SUMMARY.txt`. |
| `222-01-COVERAGE-MATRIX.md` | Phase 223 findings rollup | `## Phase 223 Handoff Preview` section with concrete row counts | VERIFIED | Section present at line 558 with final post-Plan-222-02 totals: 24 contracts / 308 functions / 19 COVERED / 177 CRITICAL_GAP / 112 EXEMPT |
| `scripts/coverage-check.sh` | `222-01-COVERAGE-MATRIX.md` | awk parse of `### Contract:` sections and verdict/test-ref columns | VERIFIED | `MATRIX_FILE` env var defaults to matrix path; `check_uncured_gaps` parses `| CRITICAL_GAP |` rows; `check_regressed_coverage` parses `### Contract:` headers |
| `scripts/coverage-check.sh` | `lcov.info` | awk parse of `BRF:` / `BRH:` / `SF:` lines | VERIFIED | Mode C implemented: `brf[]`/`brh[]` associative arrays keyed by `SF:` path; `section_pct` calculated as `h * 100 / f` |
| `Makefile coverage-check` | `scripts/coverage-check.sh` | make target shell invocation | VERIFIED | Line 44: `@scripts/coverage-check.sh` |
| `test/fuzz/CoverageGap222.t.sol` | `contracts/*.sol` + `contracts/modules/*.sol` | natural caller chains: `game.xxx` / `coin.xxx` / `coinflip.xxx` etc. via EOA prank | VERIFIED | Tests use `address(game).call(...)`, `address(coin).call(...)`, `address(coinflip).call(...)`, `address(vault).call(...)`, etc. — all production entry points. |

### Data-Flow Trace (Level 4)

Not applicable for this phase. Deliverables are audit documents, test files, a bash script, and a Makefile target — no dynamic-data-rendering components.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `coverage-check.sh` exits 0 on clean tree (negative-test evidence) | `bash scripts/coverage-check.sh \| tail -1` | Summary documents `PASS coverage-check clean (matrix drift=0, uncured gaps=0, regressed rows=0)` after fixture restore | PASS (documented in 222-02-SUMMARY.md lines 165–179) |
| `coverage-check.sh` exits 1 with `FAIL_DRIFT` when new external function injected | python3 fixture injection of `__pokeCoverageGate() external` into DegenerusStonk.sol | `FAIL_DRIFT contracts/DegenerusStonk.sol:45 __pokeCoverageGate(...) not in coverage matrix`, exit=1 | PASS (documented in 222-02-SUMMARY.md) |
| `coverage-check.sh` exits 1 with `FAIL_REGRESS` when COVERED row has 0% branch cov | `/tmp` fixture matrix with fake COVERED row at 0% | exit=1, `FAIL_REGRESS` emitted | PASS (documented in 222-02-SUMMARY.md line 182) |
| FuturepoolSkim.t.sol has zero `_applyTimeBasedFutureTake` references | `grep -r _applyTimeBasedFutureTake test/` | No matches | PASS (confirmed in verification) |
| CoverageGap222.t.sol has 76 tests all passing | `forge test --match-path test/fuzz/CoverageGap222.t.sol` | 76/76 passed in 6.19ms (per 222-02-SUMMARY.md) | PASS (cannot re-run forge in verification, but evidence documented) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CSI-08 | Plan 222-01 | FuturepoolSkim.t.sol compile error fixed so forge coverage can run | SATISFIED | Zero `_applyTimeBasedFutureTake` references in test/; `222-01-COVERAGE-SUMMARY.txt` exists as evidence forge ran |
| CSI-09 | Plan 222-01 | `forge coverage --report summary` runs to completion and produces per-function branch data | SATISFIED | `222-01-COVERAGE-SUMMARY.txt` (155KB) + `222-02-COVERAGE-SUMMARY.txt` (143KB) + `222-02-lcov.info` (232KB) committed. Note: REQUIREMENTS.md checkbox still shows `[ ]` for CSI-08/09/10 — these should be marked `[x]` in Phase 223 during findings consolidation. |
| CSI-10 | Plan 222-01 | Every external/public function classified COVERED / CRITICAL_GAP / EXEMPT | SATISFIED | 308 rows in matrix, zero blank verdicts, zero blank Test Ref cells |
| CSI-11 | Plan 222-02 | All CRITICAL_GAP functions have ≥1 new test on a realistic path | PARTIALLY SATISFIED | 76 tests present, all 177 CRITICAL_GAP rows have Test Ref cells. 62 of 76 tests are reachability-only (assertTrue(true)). Tests fire conditional branches via guard-revert paths, satisfying the coverage-instrumentation goal, but provide weak regression safety. REQUIREMENTS.md correctly marks CSI-11 `[x]` complete (the tests exist and exercise entry paths); the quality gap is tracked as Gap 1 in this verification. |

**Note on REQUIREMENTS.md state:** CSI-08, CSI-09, and CSI-10 checkboxes remain `[ ]` (Pending) and the traceability table shows them as "Pending" despite Phase 222 satisfying all three. CSI-11 is correctly marked `[x]`. Phase 223 should update CSI-08/09/10 to `[x]` / "Complete" during findings consolidation.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/fuzz/CoverageGap222.t.sol` | 62 of 76 tests | `assertTrue(true, '...')` with call result silenced as `ok; // silence unused` | Warning | Forge coverage will register branch hits, but tests provide no regression safety. A guard that silently accepts unauthorized callers, or reverts with the wrong selector, passes undetected. |
| `test/fuzz/CoverageGap222.t.sol` | 60 | `assertTrue(game.ticketsOwedView(lvl0, buyer) >= 0, "tickets recorded")` — uint32 >= 0 is always true | Warning | Vacuous assertion; purchase recording is not verified |
| `scripts/coverage-check.sh` | 104 | `grep -qF "\`${name}(" "$MATRIX_FILE"` — global matrix search, not contract-scoped | Warning | Drift check can be masked by a same-named function in another contract (WR-03). Does not guarantee every function in every contract is classified — only that the function NAME appears somewhere in the file. |
| `test/fuzz/FuturepoolSkim.t.sol` | 7–27 | Historical context comments referencing `_applyTimeBasedFutureTake`, `v20.0`, `commit d8dbd9e3`, `D-01/D-02/D-03` labels | Info | Violates project convention (`feedback_no_history_in_comments.md`): comments should describe current state, not changelog entries. Not a correctness issue. |
| `scripts/lib/patchContractAddresses.js` | 59–62 | VRF_KEY_HASH regex `bytes32 internal constant VRF_KEY_HASH = 0x[0-9a-fA-F]+;` fails on multi-line format | Warning | Silent deploy-time failure: if `ContractAddresses.sol` has `VRF_KEY_HASH` on two lines (as WR-01 documents), the replace() call no-ops and the dummy 0xabab... key hash is left in place. Not a test correctness issue but a deployment pipeline risk. |

### Gaps Summary

**Gap 1 — CSI-11 test quality (62 of 76 tests use reachability-only assertions)**

The phase goal requires tests on "conditional entry points where the real bug would manifest." The 62 reachability-only tests DO fire the first conditional branch (the guard-revert path), so forge coverage registers a branch hit — this closes the coverage gap that the mintPackedFor incident exploited. However, none of these 62 tests assert the guard fires (assertFalse on the call result), the correct revert selector fires (vm.expectRevert), or any observable state change occurs. The `test_gap_icons32_*` and `test_gap_deityPass_set*` tests show the correct pattern for guard-revert verification.

The 14 tests with real assertions are: `test_gap_setOperatorApproval_observable`, six `test_gap_icons32_*` tests, `test_gap_admin_swapGameEthForStEth_nonOwner_reverts`, two `test_gap_deityPass_*` tests, `test_gap_burnieCoin_approve`, `test_gap_lifecycle_purchase_then_advanceGame` (partially — `code.length > 0` is real but `ticketsOwedView >= 0` is tautological), `test_gap_purchaseCoin_path` (contract-alive assertion only), `test_gap_claimWinnings_zeroBalance` (contract-alive assertion only).

The minimum fix is replacing `ok; // silence unused; assertTrue(true, ...)` with `assertFalse(ok, "guard rejected")` for every gated mutator test. The stronger fix is `vm.expectRevert(Contract.ErrorSelector.selector)`.

This gap is assessed as a **warning** rather than a blocker because: (a) forge coverage WILL register the branch hit — the primary anti-mintPackedFor goal (unexercised surface detection) is satisfied; (b) the test presence satisfies the matrix Test Ref column, which the `coverage-check` gate enforces; (c) the 14 behavioral tests demonstrate correct patterns for the highest-risk functions.

**Gap 2 — coverage-check.sh drift mode not contract-scoped**

`check_matrix_drift` performs a global function-name search across the entire matrix. Multiple deployed contracts export `approve`, `transfer`, `transferFrom`, `burn`, `mint`, `burnAtGameOver`, `gameAdvance`, etc. If a new external function is added to `ContractX.sol` with the same name as an existing function in `ContractY.sol`, the drift check PASSES — it finds the name somewhere in the matrix and does not report drift. This is the WR-03 finding from code review.

This gap is assessed as a **warning** because: the drift check DOES catch brand-new function names (no contract anywhere exports that name yet). It only fails for same-name additions. The matrix currently has 308 rows; adding a new contract or a novel function name will still fail DRIFT correctly. The scoping fix should land before new contracts are added.

---

_Verified: 2026-04-12_
_Verifier: Claude (gsd-verifier)_

---

## Re-verification — 2026-04-12 (post-222-03)

Both gaps closed by Plan 222-03. Evidence:

- `222-03-COVERAGE-CHECK-PASS.txt` — clean-tree `bash scripts/coverage-check.sh` output with `PASS coverage-check clean (matrix drift=0, uncured gaps=0, regressed rows=0)` + `exit=0` marker.
- Task 1 commit `ef83c5cd` — strengthened `test/fuzz/CoverageGap222.t.sol` (76 tests, all passing, zero tautological / reachability-only assertions).
- Task 2 commit `e0a1aa3e` — scoped `scripts/coverage-check.sh` drift mode; added missing `emitDailyWinningTraits` row to DegenerusGame.sol section of the matrix (drift surfaced by the Gap-2 fix itself).

Final count: **4/4 success criteria verified**; phase 222 ready for Phase 223 findings rollup.

_Re-verified: 2026-04-12_
_Re-verifier: Claude (gsd-executor via 222-03-PLAN)_
