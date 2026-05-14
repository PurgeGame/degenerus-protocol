---
phase: 279-whole-burnie-floor-bur
verified: 2026-05-14T12:00:00Z
status: passed
score: 9/9 must-haves verified
overrides_applied: 1
orchestrator_confirmed_human_verification: "2026-05-14 — orchestrator ran both human_verification items directly: (1) 5-file Phase 279 test run = 46 passing / 9 pending / 3 failing, the 3 failures being exactly the expected pre-existing v35/v34, v37/v36, v38/v37 superseded-baseline SURF blocks (not Phase 279 regressions); (2) WholeBurnieFloorInvariant.test.js confirmed wired into the test:stat script file list and passing (8/8 its). Both runner-confirmation items satisfied — status advanced human_needed → passed."
overrides:
  - must_have: "Bytecode delta is NET-NEGATIVE; recorded in 279-01-GAS-WORSTCASE.md + the commit message"
    reason: "Measured delta is +114 bytes (NET-POSITIVE) — LootboxModule +140 bytes due to Solidity stack-depth ceiling forcing less-compact Yul optimizer schedule on _resolveLootboxCommon. JackpotModule is correctly -26 bytes. User explicitly approved at the Task 3 checkpoint. The BUR-01 floor is non-negotiable. GAS-WORSTCASE.md faithfully records the deviation. BUR-05 delivery intent (report gas + bytecode delta) is satisfied; the NET-NEGATIVE prediction did not hold but the reporting obligation is met."
    accepted_by: "Purge (user, explicit approval at checkpoint)"
    accepted_at: "2026-05-14T09:11:16-05:00"
human_verification:
  - test: "Run `npx hardhat test test/unit/LootboxWholeBurnieFloor.test.js test/unit/JackpotNearFutureCoinFloor.test.js test/unit/JackpotFarFutureCoinFloor.test.js test/stat/WholeBurnieFloorInvariant.test.js test/stat/SurfaceRegression.test.js` and confirm 0 failures in the 5 Phase 279 files (46 passing across those files, 3 pre-existing superseded-baseline SURF failures in older blocks are expected and are not Phase 279 regressions)."
    expected: "46 passing, 3 failing (the 3 failures are pre-existing v35/v34, v37/v36, v38/v37 superseded-baseline SURF blocks — not introduced by Phase 279)"
    why_human: "The test runner requires the Hardhat environment to be up. The orchestrator's baseline comparison (controlled A/B isolation at pre-279 commit e6493e59) already proved all 24 full-suite failures are pre-existing, and the 4 new TST-BUR files pass. Human confirmation closes the loop on the 5-file targeted run."
  - test: "Run `npm run test:stat` and confirm `WholeBurnieFloorInvariant.test.js` appears in the run output (the new file is in the test:stat script's explicit file list per package.json line 9)."
    expected: "test:stat executes WholeBurnieFloorInvariant.test.js; all 8 its in that file pass"
    why_human: "Requires the full test:stat suite to run (multiple stat files; takes longer). Verifies the package.json wiring is live in the CI tier."
---

# Phase 279: Whole-BURNIE Floor Verification Report

**Phase Goal:** Apply the A1 floor-per-winner mechanic — inline `(x / 1 ether) * 1 ether` whole-BURNIE integer-division floor — to all 3 RNG-influenced BURNIE-award sites: `_resolveLootboxCommon`'s `burnieAmount` accumulator (BUR-01), `_awardDailyCoinToTraitWinners`'s `baseAmount` (BUR-02, plus full removal of the `extra`/`cursor` cursor-rotation machinery), and `_awardFarFutureCoinJackpot`'s `perWinner` (BUR-03). Each floor sits BEFORE the existing zero-guard/early-bail. Storage layout must be byte-identical to v39 baseline `6a7455d1` for both modules; zero new state vars / events / emit sites / modifiers / entry points (BUR-04). Gas worst-case derived + bytecode delta reported (BUR-05). Plus a test wave: 3 source-structural floor regression tests (TST-BUR-01/02/03), 1 invariant-sweep test with mint-boost negative cross-site assertion wired into `test:stat` (TST-BUR-04), and a `SurfaceRegression.test.js` SURF_01 re-cut.
**Verified:** 2026-05-14
**Status:** human_needed (automated checks fully pass; 2 items need human test-runner confirmation)
**Re-verification:** No — initial verification

## Accepted Deviations

Two user-approved deviations from the original plan were discovered during execution. Both are recorded here and do NOT constitute blockers.

**Deviation 1 — BUR-01 burnie-accumulation reorder (within D-279-BUR01-SITE-01 placement discretion):**
`_resolveLootboxCommon` is at the Solidity stack-depth ceiling. The BUR-01 floor statement at the CONTEXT.md-specified position failed to compile (`YulException: Cannot swap … too deep in the stack by 1 slots`). The `burnieAmount` accumulation block was relocated to immediately after `_accumulateLootboxRolls` returns, shortening the live-range of the `burniePresale` / `burnieNoMultiplier` stack locals. Code review confirmed the reorder is behavior-safe: nothing reads `burnieAmount`, `burnieNoMultiplier`, or `burniePresale` between the old and new positions. All 3 downstream consumers (`creditFlip` arg, `LootBoxOpened.burnie` field, return tuple) still read the bare floored `burnieAmount` local. Within D-279-BUR01-SITE-01 placement discretion.

**Deviation 2 — BUR-05 bytecode delta NET-POSITIVE (+114 bytes):**
The plan's BUR-05 NET-NEGATIVE expectation did not hold. Measured: `DegenerusGameJackpotModule` −26 bytes (net-negative as expected); `DegenerusGameLootboxModule` +140 bytes (the stack-depth-ceiling optimizer stack-spill consequence of the BUR-01 floor); total Phase-279-only delta **+114 bytes**. The `279-01-GAS-WORSTCASE.md` artifact faithfully records this, as does the commit message. User explicitly accepted at the Task 3 checkpoint. For context, the cumulative delta vs v39 baseline `6a7455d1` (Phases 275–279) is −1,792 bytes.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `_resolveLootboxCommon` floors the post-bonus `burnieAmount` accumulator via `(burnieAmount / 1 ether) * 1 ether` before the `if (burnieAmount != 0)` guard; floored value reaches `creditFlip`, `LootBoxOpened.burnie`, and the return tuple | ✓ VERIFIED | `DegenerusGameLootboxModule.sol:1023` — floor statement confirmed; line ordering verified: floor@1023 → guard@1078 → creditFlip@1079 → LootBoxOpened emit@1083 → return@1094; all 3 consumers read bare `burnieAmount` |
| 2 | `_awardDailyCoinToTraitWinners` floors `baseAmount` via `((coinBudget / cap) / 1 ether) * 1 ether`; `extra`/`cursor` declarations, both `++cursor`/wrap blocks, and `amount += 1` fully deleted; `randomWord` and both `++i` preserved; NatSpec rewritten | ✓ VERIFIED | `DegenerusGameJackpotModule.sol:1789` — floor confirmed; `grep -n '\bextra\b|\bcursor\b'` in lines 1762-1846 returns zero results (only lines 996-1021 in out-of-scope region match); `amount += 1` absent; `randomWord` at lines 1797 and 1817; both `++i` at lines 1811 and 1843; NatSpec at 1753-1759 describes current state with no history language |
| 3 | `_awardFarFutureCoinJackpot` floors `perWinner` via `((farBudget / found) / 1 ether) * 1 ether` BEFORE the unchanged `if (perWinner == 0) return` early-bail | ✓ VERIFIED | `DegenerusGameJackpotModule.sol:1896-1897` — floor@1896 immediately followed by `if (perWinner == 0) return;`@1897; unchanged `coinflip.creditFlipBatch` at 1914 is downstream of the bail |
| 4 | The OUT-OF-SCOPE ticket-award cursor-rotation at `DegenerusGameJackpotModule.sol` near `:996`-`:1021` is NOT touched | ✓ VERIFIED | `grep -n '\bextra\b|\bcursor\b'` returns only lines 996, 999, 1003, 1020, 1021 — the out-of-scope ticket-award region; no edits to that block in commit `8ef4a010` |
| 5 | Storage layout for both modules is byte-identical to v39 baseline `6a7455d1`; zero new state variables, events, emit sites, modifiers, admin entry points, or external mutation entry points | ✓ VERIFIED | `279-01-STORAGE-LAYOUT-DIFF.md` PASS verdict — `forge inspect storage-layout` diff empty (exit 0) + sha256 cross-check identical for both modules; layout line count 171/171 for both; commit `8ef4a010` touches only function bodies |
| 6 | Gas worst-case derived BEFORE benchmarking; measured bytecode delta reported in `279-01-GAS-WORSTCASE.md` + commit message | ✓ VERIFIED (override applied) | `279-01-GAS-WORSTCASE.md` contains the theoretical worst-case derivation (BUR-01 flat ~+10-15 gas, BUR-02 net-NEGATIVE per iteration, BUR-03 flat ~+10-15 gas) before the measured delta table; delta reported as +114 bytes NET-POSITIVE; user accepted the NET-POSITIVE outcome explicitly; BUR-05 reporting obligation satisfied |
| 7 | TST-BUR-01/02/03 — three source-structural regression tests prove the 3 BUR floors landed at correct sites with correct ordering | ✓ VERIFIED | `test/unit/LootboxWholeBurnieFloor.test.js` (241 lines, 11 its), `test/unit/JackpotNearFutureCoinFloor.test.js` (236 lines, 9 its), `test/unit/JackpotFarFutureCoinFloor.test.js` (169 lines, 7 its) — all 3 use `extractBody` + `stripLineComments` + regex + index-ordering; JS boundary math included; no on-chain tester contract; per 279-02-SUMMARY.md all 27 its pass |
| 8 | TST-BUR-04 — invariant sweep (N=20000/site) proving every BUR-site amount is a 1-ether multiple, plus mint-boost negative cross-site assertion; wired into `test:stat` script in `package.json` | ✓ VERIFIED | `test/stat/WholeBurnieFloorInvariant.test.js` (262 lines, 8 its); `package.json` line 9 `test:stat` script explicitly includes `test/stat/WholeBurnieFloorInvariant.test.js`; no chi-square (deterministic floor invariant); per 279-02-SUMMARY.md 8/8 pass; mint-boost negative assertion with positive pin on `creditFlip(buyer, lootboxFlipCredit)` call site |
| 9 | `SurfaceRegression.test.js` `SURF_01_PROTECTED_RANGES_V40` re-cut excludes Phase 279 BUR-02/BUR-03 OLD-side delta lines; `walkAndAssertV40` algorithm + `it` bodies byte-identical | ✓ VERIFIED | `test/stat/SurfaceRegression.test.js` line 979 shows Phase 279 BUR-02/BUR-03 sub-bullet in SURF-01 header comment; `SURF_01_PROTECTED_RANGES_V40` at line 1044 is the re-cut array; the single `JackpotModule L1014-2177` range was split into 7 sub-ranges around the Phase 279 delta lines; per 279-02-SUMMARY.md the v40.0 SURF-01 block passes green |

**Score:** 9/9 truths verified (1 with override applied for BUR-05 NET-POSITIVE deviation)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `contracts/modules/DegenerusGameLootboxModule.sol` | BUR-01 whole-BURNIE floor on `_resolveLootboxCommon` burnieAmount accumulator | ✓ VERIFIED | Floor at line 1023; ordering confirmed; commit `8ef4a010` |
| `contracts/modules/DegenerusGameJackpotModule.sol` | BUR-02 baseAmount floor + extra/cursor dead-var removal; BUR-03 perWinner floor | ✓ VERIFIED | baseAmount floor at 1789; extra/cursor absent from function span (996-1021 only); perWinner floor at 1896 before bail at 1897; commit `8ef4a010` |
| `.planning/phases/279-whole-burnie-floor-bur/279-01-STORAGE-LAYOUT-DIFF.md` | BUR-04 storage-layout byte-identity proof vs 6a7455d1 for both modules | ✓ VERIFIED | File exists; PASS verdict with sha256 cross-check; diff empty (exit 0) for both modules |
| `.planning/phases/279-whole-burnie-floor-bur/279-01-GAS-WORSTCASE.md` | BUR-05 theoretical worst-case gas derivation + measured bytecode delta | ✓ VERIFIED | File exists; derivation precedes benchmarking; +114 byte NET-POSITIVE deviation documented with root cause; user-accepted |
| `test/unit/LootboxWholeBurnieFloor.test.js` | TST-BUR-01 LootboxModule floor regression — source-structural + JS boundary math + LootBoxOpened.burnie field-consistency | ✓ VERIFIED | 241 lines; 11 its; extractBody + stripLineComments; floor pattern, index-ordering, field-consistency, boundary math (0.99→0, 1.99→1, 2.00→2, 0→0) |
| `test/unit/JackpotNearFutureCoinFloor.test.js` | TST-BUR-02 near-future coin jackpot floor + dead-var removal + budget-evaporation regression | ✓ VERIFIED | 236 lines; 9 its; floor pattern, extra/cursor absence, amount+=1 absence, randomWord survival, 2x keccak draws, both ++i, emit-guard ordering |
| `test/unit/JackpotFarFutureCoinFloor.test.js` | TST-BUR-03 far-future coin jackpot floor + early-bail-before-creditFlipBatch regression | ✓ VERIFIED | 169 lines; 7 its; floor pattern, index-ordering (floor < bail < creditFlipBatch), JS boundary math |
| `test/stat/WholeBurnieFloorInvariant.test.js` | TST-BUR-04 invariant sweep across all 3 sites + mint-boost negative cross-site assertion | ✓ VERIFIED | 262 lines; 8 its; N=20000/site; `flooredAmount % 1 ether == 0`; 3-site combined structural gate; `_purchaseFor` negative assertion with positive pin |
| `test/stat/SurfaceRegression.test.js` | SURF_01_PROTECTED_RANGES_V40 re-cut to exclude Phase 279 BUR-02/BUR-03 delta lines | ✓ VERIFIED | Phase 279 sub-bullet at line 979; re-cut at line 1044; walkAndAssertV40 + it bodies untouched |
| `package.json` | test:stat script file list extended to include test/stat/WholeBurnieFloorInvariant.test.js | ✓ VERIFIED | Line 9 of package.json confirms `test/stat/WholeBurnieFloorInvariant.test.js` in the explicit file list |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `_resolveLootboxCommon` burnieAmount floor | `coinflip.creditFlip(player, burnieAmount)` + `LootBoxOpened.burnie` + return tuple | In-place reassignment at line 1023, before the guard and all 3 consumers | ✓ WIRED | Confirmed: floor@1023 → guard@1078 → creditFlip@1079 → emit@1083 (burnieAmount is 7th arg) → return@1094 |
| `_awardDailyCoinToTraitWinners` baseAmount | `coinflip.creditFlip(winner, amount)` inside `winner != address(0) && amount != 0` guard | `amount = baseAmount` at line 1829; guard at 1831; creditFlip at 1839 | ✓ WIRED | Confirmed: floor@1789 → amount=baseAmount@1829 → guard@1831 → creditFlip@1839; no amount+=1; extra/cursor absent |
| `_awardFarFutureCoinJackpot` perWinner floor | `if (perWinner == 0) return` early-bail | Floor applied before the bail, bail before creditFlipBatch | ✓ WIRED | Confirmed: floor@1896 → bail@1897 → batch@1914; correct ordering |
| `package.json` test:stat script | `test/stat/WholeBurnieFloorInvariant.test.js` | Explicit file-list entry in the test:stat npm script | ✓ WIRED | Confirmed: line 9 of package.json includes the path in the hardhat test command |
| `test/stat/SurfaceRegression.test.js` SURF_01_PROTECTED_RANGES_V40 | git diff 6a7455d1 HEAD OLD-side delta lines in DegenerusGameJackpotModule.sol | Re-cut protected ranges as complement of Phase 279 OLD-side modified-line set | ✓ WIRED | Confirmed: Phase 279 annotation at line 979; SURF_01_PROTECTED_RANGES_V40 at line 1044; walkAndAssertV40 + it bodies byte-identical |

### Data-Flow Trace (Level 4)

Not applicable — Phase 279 modifies internal `private` functions whose data cannot be directly traced through the contract storage for this class of change. The source-structural proof (Level 3 wiring) is the load-bearing evidence per the documented FIXTURE_COVERAGE_GAP_NOTED precedent. The test suite asserting the floor precedes the downstream consumers and that the downstream consumers reference the same bare `burnieAmount`/`amount`/`perWinner` local (not a pre-floor snapshot) is the equivalent of a data-flow trace.

### Behavioral Spot-Checks

The 3 BUR sites are all `private` functions with no deterministic full-state harness (documented FIXTURE_COVERAGE_GAP_NOTED). Direct behavioral spot-checks via CLI are not possible without running the full contract stack. The 35 new test its across 4 files serve as the behavioral layer, including JS BigInt boundary math confirming the floor direction and the `% 1 ether == 0` invariant. The human verification items below close the live test-runner confirmation loop.

### Probe Execution

No phase-declared probes. This phase does not follow the probe-based verification pattern.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| BUR-01 | 279-01-PLAN.md | Lootbox spin BURNIE floor at `_resolveLootboxCommon` | ✓ SATISFIED | Floor at line 1023; ordering confirmed; commit 8ef4a010 |
| BUR-02 | 279-01-PLAN.md | JackpotModule near-future coin jackpot `baseAmount` floor + `extra`/`cursor` dead-var removal | ✓ SATISFIED | Floor at line 1789; extra/cursor absent from function span; `amount += 1` deleted; randomWord and ++i preserved |
| BUR-03 | 279-01-PLAN.md | JackpotModule far-future coin jackpot `perWinner` floor before `== 0` early-bail | ✓ SATISFIED | Floor at line 1896 immediately before bail at 1897 |
| BUR-04 | 279-01-PLAN.md | Storage layout byte-identical to 6a7455d1; zero new state/events/emit-sites/modifiers/entry-points | ✓ SATISFIED | `279-01-STORAGE-LAYOUT-DIFF.md` PASS; diff empty for both modules; commit touches only function bodies |
| BUR-05 | 279-01-PLAN.md | Gas worst-case derived + bytecode delta reported | ✓ SATISFIED (override) | `279-01-GAS-WORSTCASE.md` exists; derivation precedes benchmarking; delta reported as +114 bytes with root-cause analysis; user accepted NET-POSITIVE outcome |
| TST-BUR-01 | 279-02-PLAN.md | LootboxModule floor regression test | ✓ SATISFIED | `test/unit/LootboxWholeBurnieFloor.test.js` — 11 its, extractBody proof, JS boundary math, LootBoxOpened field-consistency |
| TST-BUR-02 | 279-02-PLAN.md | Near-future coin jackpot floor + dead-var removal + budget-evaporation regression | ✓ SATISFIED | `test/unit/JackpotNearFutureCoinFloor.test.js` — 9 its, floor pattern, extra/cursor absence, randomWord survival, emit-guard ordering |
| TST-BUR-03 | 279-02-PLAN.md | Far-future coin jackpot floor + early-bail-before-creditFlipBatch regression | ✓ SATISFIED | `test/unit/JackpotFarFutureCoinFloor.test.js` — 7 its, floor pattern, ordering proof (floor < bail < batch) |
| TST-BUR-04 | 279-02-PLAN.md | Whole-BURNIE invariant sweep + mint-boost negative assertion + test:stat wiring | ✓ SATISFIED | `test/stat/WholeBurnieFloorInvariant.test.js` — 8 its, N=20000/site, mint-boost negative assertion with positive pin; `package.json` test:stat wiring confirmed |

All 9 Phase 279 requirement IDs (BUR-01..05, TST-BUR-01..04) are satisfied. No orphaned requirements found (the per-phase mapping table in REQUIREMENTS.md lines 217-225 maps all 9 IDs to Phase 279).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | No TBD/FIXME/XXX markers found in any Phase 279 modified file | — | No unreferenced debt markers |

No debt markers found in `DegenerusGameLootboxModule.sol`, `DegenerusGameJackpotModule.sol`, or any of the 4 new test files.

### Human Verification Required

#### 1. Full 5-file Phase 279 test run

**Test:** `npx hardhat test test/unit/LootboxWholeBurnieFloor.test.js test/unit/JackpotNearFutureCoinFloor.test.js test/unit/JackpotFarFutureCoinFloor.test.js test/stat/WholeBurnieFloorInvariant.test.js test/stat/SurfaceRegression.test.js`

**Expected:** 46 passing, 3 failing. The 3 failures are pre-existing v35/v34, v37/v36, v38/v37 superseded-baseline SURF blocks in `SurfaceRegression.test.js` — they were present at the pre-279 commit `e6493e59` (confirmed by the orchestrator's A/B isolation). All 35 new Phase 279 test its should be green.

**Why human:** Requires the Hardhat environment to be running and the full test infrastructure to execute. Cannot be confirmed via file-content inspection alone.

#### 2. test:stat tier confirmation for WholeBurnieFloorInvariant.test.js

**Test:** `npm run test:stat` — verify `WholeBurnieFloorInvariant.test.js` appears in the run output and its 8 its pass.

**Expected:** The `test:stat` tier executes `test/stat/WholeBurnieFloorInvariant.test.js` (it is the last entry in the explicit file list in `package.json` line 9). All 8 its pass. The `test:stat` script is a hand-maintained file list (NOT a directory glob), so the wiring is a code fact but live execution is the final confirmation.

**Why human:** Requires the full `test:stat` suite to run (16 files including heavy Monte-Carlo stat tests). Confirms the package.json wiring is live, not just structurally present.

### Gaps Summary

No blocking gaps. All 9 must-haves are verified against the actual codebase. The 2 human verification items above are runner-confirmation checks for an otherwise fully verified phase — the code facts (test files exist, are substantive, assertions are correct, package.json wiring is present) are all confirmed by inspection.

The BUR-05 deviation (+114 bytes instead of NET-NEGATIVE) is recorded as a user-accepted override, not a gap. The storage layout proof artifact and gas worst-case artifact both exist and contain the required content.

---

_Verified: 2026-05-14_
_Verifier: Claude (gsd-verifier)_
