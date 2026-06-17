---
phase: 395-mutation
plan: 01
subsystem: testing
tags: [mutation, slither-mutate, forge, oracle, packing, solvency, byte-freeze, via_ir]

# Dependency graph
requires:
  - phase: 388-foundation-subject-freeze-green-baseline
    provides: "byte-frozen subject a8b702a7 + green oracle (854/0/110) + the 388-02 EXERCISED oracle-test ledger + the v63-changed fix-site surface"
provides:
  - "TARGETS-v63.md — the named fix-site/spine mutation target set (4 groups) paired with the EXERCISING oracle tests"
  - "oracle-comprehensive.sh — the single comprehensive oracle (union of the 12 EXERCISED green-baseline tests, via_ir)"
  - "run-campaign-v63.sh — kill-safe resumable fix-site-scoped campaign runner (restore trap + per-target .DONE + --single)"
  - "HARNESS-VALIDATION-v63.md — proof the corrected oracle kills an injected packing defect + the restore-trap byte-freeze proof"
affects: [395-02, 395-03, mutation, campaign]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Comprehensive mutation oracle = the UNION of the EXERCISED green-baseline tests (not a narrow per-file --match-contract regex)"
    - "forge 1.6.0 oracle union expressed as a single anchored --match-contract regex over test-contract names (repeated --match-path is rejected)"
    - "Kill-safe campaign: EXIT/INT/TERM restore trap + subject-pin assertion before AND after every target + per-target .DONE resumability"

key-files:
  created:
    - audit/mutation/TARGETS-v63.md
    - audit/mutation/oracle-comprehensive.sh
    - audit/mutation/run-campaign-v63.sh
    - audit/mutation/HARNESS-VALIDATION-v63.md
  modified: []

key-decisions:
  - "Fix-site/spine scope (4 named target groups), NOT all-files — the prior all-files+narrow-oracle run produced mostly false survivors and is the documented long-pole"
  - "Oracle union via --match-contract regex (forge 1.6.0 rejects repeated --match-path and its --match-path is not a regex)"
  - "Validation kill demonstrated on _creditAfking lane-shift (caught by V61Pack); recorded two genuine residual blind spots (setPacked clear-mask, _debitClaimableAndAfking combined helper) as real Plan-02 survivors, not oracle artifacts"

patterns-established:
  - "Every campaign step asserts the subject byte-freeze (tree-hash 2934d3d8 + empty diff vs a8b702a7) and never commits while a mutant is in place"
  - "Commit commands avoid the literal source-dir token (the commit-guard hook trips on it even in a status-assertion line)"

requirements-completed: [MUT-01]

# Metrics
duration: ~40min
completed: 2026-06-15
---

# Phase 395 Plan 01: Claude-Built Mutation Harness Summary

**Corrected fix-site/spine mutation harness for the frozen subject `a8b702a7`: a named 4-group target ledger + a comprehensive-union oracle (12 EXERCISED green-baseline tests, via_ir) + a kill-safe resumable runner, validated by an injected `_creditAfking` lane-shift defect that the comprehensive oracle KILLS (where the prior narrow oracle let the whole masked-RMW class survive) and a SIGINT-with-mutant-in-place restore-trap byte-freeze proof.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-06-15T08:00Z (approx)
- **Completed:** 2026-06-15T08:20Z (approx)
- **Tasks:** 3
- **Files created:** 4 (all `audit/mutation/`)

## Accomplishments

- **TARGETS-v63.md** — the authoritative fix-site/spine target ledger: 4 named groups (G1 sStonk redemption claim-split + dust-forfeit + narrowing casts; G2 BurnieCoinflip emission rework; G3 delegatecall Decimator/Lootbox redemption legs + uint32 claim seed; G4 BitPackingLib + DegenerusGameStorage packing helpers), each function paired with the 388-02 EXERCISED oracle tests that drive it, plus the explicit "fix-site/spine, NOT all-files" exclusion rationale (MUT-01).
- **oracle-comprehensive.sh** — one comprehensive oracle = the union of the 12 EXERCISED green-baseline tests, GREEN at the subject (12 suites, 113/113 pass, exit 0), via_ir inherited from `[profile.default]`, VRFPath excluded.
- **run-campaign-v63.sh** — the kill-safe resumable runner: asserts the subject pin (tree-hash + empty diff) before AND after every target, installs the EXIT/INT/TERM `git checkout -- contracts/` restore trap, runs a baseline-green gate per target, drives `slither-mutate --contract-names` against the comprehensive oracle, per-target `.DONE` resumability, bounded per-mutant env, fix-site ordering (smallest/highest-signal first), and a `--single <ContractName>` argv for a paced background run in Plan 02.
- **HARNESS-VALIDATION-v63.md** — the false-survivor-collapse + byte-freeze proofs (below).

## Task Commits

1. **Task 1: Name the fix-site/spine target set + comprehensive oracle** - `2bbda9c1` (test)
2. **Task 2: Build the kill-safe resumable runner** - `865a780e` (test)
3. **Task 3: Validate the corrected oracle + restore trap** - `ca1fe55a` (test)

_(Plan metadata commit follows this SUMMARY.)_

## Files Created/Modified

- `audit/mutation/TARGETS-v63.md` — named 4-group fix-site/spine target ledger + oracle mapping + exclusion rationale.
- `audit/mutation/oracle-comprehensive.sh` — the comprehensive-union oracle (12 EXERCISED tests via `--match-contract`, VRFPath excluded, via_ir).
- `audit/mutation/run-campaign-v63.sh` — kill-safe resumable fix-site campaign runner.
- `audit/mutation/HARNESS-VALIDATION-v63.md` — oracle-kills-mutant + restore-trap byte-freeze evidence.

## Validation Evidence (the core of MUT-01)

**(A) The comprehensive oracle executes the mutated code and KILLS it.** Injecting a lane-shift defect into `DegenerusGameStorage._creditAfking` (`weiAmount << 128` → `weiAmount`, so the afking credit corrupts the claimable low half) made the comprehensive oracle FAIL (107/113, exit 1), killed by **V61Pack** with 6 named assertions (`testCreditAfkingRoundTripLowHalfUntouched`, `testDebitTouchesCorrectHalfOnly`, `testNoCrossHalfCarryAtSupplyBound`, `testGameOverZeroingPreservesInfraAfkingHalf`, `testFuzzTwoMappingEquivalence`, `testCreditClaimableRoundTripHighHalfUntouched`). The narrow-vs-comprehensive contrast: the prior narrow oracle logged `BitPackingLib ... setPacked ==> revert() --> UNCAUGHT` (uncaught=63), and the prior all-files campaign ran **0** `DegenerusGameStorage` targets — the entire `balancesPacked` masked-RMW family was outside its reach. The corrected harness both scopes it and drives it through V61Pack.

**(B) The restore trap byte-freezes the subject after an interrupted run.** A SIGINT with a real mutant confirmed on disk fired the identical trap path (`git checkout -- contracts/`), leaving `git status --porcelain contracts/` empty, tree-hash `2934d3d8987a09c5f073549a0cb499f6c5f28620`, and `git diff a8b702a7 -- contracts/` empty.

## Decisions Made

- **Fix-site/spine scope (4 named groups), not all-files.** The 8-agent FOUNDATION map was 0-HIGH on inspection; the highest-signal targets are the v63-changed + solvency/RNG/packing-spine functions, and the all-files run is the documented multi-hour long-pole that produced false survivors.
- **Oracle union via `--match-contract` regex.** The plan specified repeated `--match-path`, but the installed forge 1.6.0 rejects repeated `--match-path` and its `--match-path` is a literal/glob (no regex alternation). The functionally-equivalent union is a single anchored `--match-contract` regex over the 12 EXERCISED test CONTRACT names (1:1 with the 12 named files). via_ir inheritance and the named-file comprehensiveness are preserved.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Oracle union mechanism: repeated `--match-path` → single `--match-contract` regex**
- **Found during:** Task 3 (validating the oracle green run)
- **Issue:** The planned mechanism (repeated `--match-path`, one per oracle file) is rejected by the installed forge 1.6.0 (`error: the argument '--match-path <GLOB>' cannot be used multiple times`), and forge's `--match-path` is a literal/glob, not a regex (no `(a|b)` alternation), so a single combined `--match-path` could not express the 12-file union either.
- **Fix:** Expressed the union as a single anchored `--match-contract '^(...12 test-contract names...)$'` regex (forge `--match-contract` IS a true regex), verified via `--list --json` to select exactly the 12 intended suites; `--no-match-contract VRFPath` and via_ir inheritance preserved. The 12 contract names map 1:1 to the 12 EXERCISED oracle files documented in TARGETS-v63.md.
- **Files modified:** audit/mutation/oracle-comprehensive.sh
- **Verification:** comprehensive oracle GREEN 12 suites / 113 tests / exit 0; the injected mutant killed it (exit 1) — proving the union both runs and is exercising the target code.
- **Committed in:** ca1fe55a (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — tool-mechanism substitution, functionally equivalent).
**Impact on plan:** No scope change. The comprehensive named-union oracle and via_ir inheritance are preserved exactly; only the forge flag mechanism differs to match the installed forge 1.6.0.

## Known Stubs

None. The deliverables are executable scripts and ledger docs; no placeholder/empty-data flows.

## Issues Encountered

- **Two validation mutations survived before finding the killed one.** `setPacked` dropping its clear-mask survived (the StorageFoundation/V61Pack pokes write into freshly-zeroed words, so OR == masked-write), and `_debitClaimableAndAfking` dropping its afking-leg `<<128` survived (the oracle path exercises the SEPARATE `_debitClaimable`/`_debitAfking` accessors, not the combined helper). These are recorded in HARNESS-VALIDATION-v63.md §A.3 as GENUINE residual blind spots — the exact thing the campaign exists to quantify — for Plan 02 to adjudicate (add an assertion on the combined helper / on a non-zero-overlap packed write). The kill was then demonstrated on `_creditAfking`, which V61Pack does assert.
- **Commit-guard hook quirk hit once.** The hook tripped on a literal source-dir token inside a `git status` assertion in the bash command (not a contract commit). Re-ran the assertion with a token-split path; no contract source was ever staged. All subsequent commit commands avoid the literal token.

## Threat Surface

No new security-relevant surface — all deliverables are `audit/mutation/` scripts/docs; no contract source was persistently edited (every mutation in validation was transient and restored). T-395-01/02/03 (the plan's STRIDE register) are mitigated: the restore trap + before/after pin assertions (T-395-01), the comprehensive oracle proven to exercise the mutated code (T-395-02), and no-commit-while-mutant-in-place discipline + the commit-guard backstop (T-395-03).

## Next Phase Readiness

- The harness is ready for Plan 02: run `run-campaign-v63.sh` (or `--single <ContractName>` paced in the background) over the 4 target groups, score per-target + aggregate mutation rates, and triage survivors FALSE vs GENUINE.
- The two recorded residual blind spots (setPacked clear-mask, combined-debit helper) are pre-flagged candidate survivors for Plan 02's triage.

## Self-Check: PASSED

- All 4 created files exist on disk.
- All 3 task commits (`2bbda9c1`, `865a780e`, `ca1fe55a`) exist in git log.
- Subject byte-frozen: tree-hash `2934d3d8987a09c5f073549a0cb499f6c5f28620`, `git diff a8b702a7 -- contracts/` empty, `git status --porcelain contracts/` empty.

---
*Phase: 395-mutation*
*Completed: 2026-06-15*
