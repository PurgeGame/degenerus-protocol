---
phase: 279-whole-burnie-floor-bur
plan: 02
subsystem: testing
tags: [hardhat, mocha, source-structural-proof, extractBody, surface-regression, invariant-sweep, whole-burnie-floor]

# Dependency graph
requires:
  - phase: 279-01
    provides: "Wave-1 contract commit 8ef4a010 — the whole-BURNIE floor landed at all 3 BUR sites (_resolveLootboxCommon, _awardDailyCoinToTraitWinners, _awardFarFutureCoinJackpot); the post-floor source the tests assert against"
provides:
  - "TST-BUR-01..04 — the Phase 279 test wave: 4 new test files (35 new tests) proving the whole-BURNIE floor landed at all 3 RNG-amount sites with correct ordering, the extra/cursor dead-var removal left zero residue, the budget-evaporation paths route through existing guards, and the mint-boost path stayed status-quo fractional"
  - "SURF_01_PROTECTED_RANGES_V40 re-cut so the v40.0 byte-identity drift gate passes against the post-Wave-1 JackpotModule source"
  - "test:stat tier coverage of WholeBurnieFloorInvariant.test.js via the package.json file-list wiring"
affects: [phase-279-closure, v40.0-milestone-audit, surface-regression-baseline]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Source-structural proof as load-bearing test evidence for fixture-gapped functions (extractBody brace-matcher + stripLineComments + regex + index-ordering), per the JackpotTicketRollSilentColdBust.test.js precedent — no on-chain tester contract added"
    - "Deterministic makeRng keccak-counter PRNG sweep for a non-probabilistic FLOOR invariant (amount % 1 ether == 0) — no chi-square / Wilson-Hilferty"
    - "Negative cross-site assertion pinned with a positive call-site pin (assert creditFlip(buyer, lootboxFlipCredit) IS present before asserting the floor is NOT)"

key-files:
  created:
    - test/unit/LootboxWholeBurnieFloor.test.js
    - test/unit/JackpotNearFutureCoinFloor.test.js
    - test/unit/JackpotFarFutureCoinFloor.test.js
    - test/stat/WholeBurnieFloorInvariant.test.js
  modified:
    - test/stat/SurfaceRegression.test.js
    - package.json

key-decisions:
  - "TST-BUR-01/02/03 placed in test/unit/; TST-BUR-04 placed in test/stat/ (the heavy invariant-sweep shape) — REQUIREMENTS.md's suggested test/lootbox/ and test/jackpot/ dirs do not exist on disk"
  - "Source-structural extractBody proof is the load-bearing evidence (the 3 BUR sites have a documented fixture-coverage gap); JS boundary math is confirmation only; no on-chain BurnieFloorTester.sol added"
  - "The 3 pre-existing superseded-baseline SURF failures were surfaced rather than silently edited — committed 279-02 as-is per user approval; an it.skip cleanup is left for a separate follow-up"

patterns-established:
  - "extractBody + stripLineComments infra copied per-file (matches existing per-file-copy precedent) rather than extracted to a shared helper"
  - "SURF_01 protected-range re-cut as the exact complement of the OLD-side modified-line set from git diff 6a7455d1 HEAD — single L1014-2177 range split into 7 sub-ranges around the Phase 279 delta lines; walkAndAssertV40 + it bodies byte-identical"

requirements-completed: [TST-BUR-01, TST-BUR-02, TST-BUR-03, TST-BUR-04]

# Metrics
duration: ~50min (across original + continuation agent)
completed: 2026-05-14
---

# Phase 279 Plan 02: Whole-BURNIE Floor Test Wave (BUR) Summary

**Four new test files (35 tests) prove the whole-BURNIE floor landed at all 3 RNG-amount sites with correct ordering and zero dead-var residue, the mint-boost path stayed status-quo fractional, and the v40.0 surface-regression byte-identity gate is re-cut green against the post-Wave-1 source — all in one user-approved batched commit.**

## Performance

- **Duration:** ~50 min (Tasks 1-2 by original agent; test wave + Task 3 commit + summary by continuation agent)
- **Completed:** 2026-05-14
- **Tasks:** 3 (Task 1, Task 2, Task 3 checkpoint)
- **Files modified:** 6 (4 created, 2 modified)

## Accomplishments

- **TST-BUR-01** — `test/unit/LootboxWholeBurnieFloor.test.js` (11 its): source-structural `extractBody` proof that `_resolveLootboxCommon` floors `burnieAmount` before the `if (burnieAmount != 0)` guard and the `coinflip.creditFlip(player, burnieAmount)` call, `LootBoxOpened` reads the floored value, plus JS boundary math (0.99→0, 1.99→1, 2.00→2, 0→0).
- **TST-BUR-02** — `test/unit/JackpotNearFutureCoinFloor.test.js` (9 its): proves `_awardDailyCoinToTraitWinners` floors `baseAmount`, contains zero `extra`/`cursor` residue, no `amount += 1`, `randomWord` survives, and the `JackpotBurnieWin` emit + `creditFlip` sit inside the `winner != address(0) && amount != 0` guard.
- **TST-BUR-03** — `test/unit/JackpotFarFutureCoinFloor.test.js` (7 its): proves `_awardFarFutureCoinJackpot` floors `perWinner` before the `if (perWinner == 0) return` early-bail and before `creditFlipBatch`.
- **TST-BUR-04** — `test/stat/WholeBurnieFloorInvariant.test.js` (8 its): deterministic `makeRng` floor-invariant sweep (N=20000 per site) asserting `amount % 1 ether == 0` across all 3 BUR sites, plus the mint-boost negative cross-site assertion proving `DegenerusGameMintModule.sol`'s `lootboxFlipCredit` path has NO whole-BURNIE floor (D-40N-BUR-MINTBOOST-OUT-01).
- **`package.json`** — `test:stat` script file list extended with `test/stat/WholeBurnieFloorInvariant.test.js` so the sweep runs under the `test:stat` tier (the script is a hand-maintained file list, not a directory glob).
- **`test/stat/SurfaceRegression.test.js`** — `SURF_01_PROTECTED_RANGES_V40` re-cut to exclude the Phase 279 BUR-02/BUR-03 OLD-side delta lines (the single `JackpotModule L1014-2177` range split into 7 sub-ranges); header comment updated; `walkAndAssertV40` + all `it` bodies untouched. The re-cut FIXED the previously-failing v40.0 SURF-01 block.

## Task Commits

1. **Task 1 + Task 2: TST-BUR-01..04 test files + test:stat wiring + SURF-01 re-cut** — `37207743` (test) — batched into one commit per the plan's checkpoint design
2. **Task 3: checkpoint:human-verify** — user reviewed the batched test diff and explicitly approved; the commit above is the Task 3 deliverable

**Plan metadata:** `docs(279-02): plan summary — BUR test wave` (this file) + `docs(279-02): mark plan 02 complete — STATE + ROADMAP progress`

## Files Created/Modified

- `test/unit/LootboxWholeBurnieFloor.test.js` (created, 241 lines) — TST-BUR-01 LootboxModule floor regression
- `test/unit/JackpotNearFutureCoinFloor.test.js` (created, 236 lines) — TST-BUR-02 near-future coin jackpot floor + dead-var removal
- `test/unit/JackpotFarFutureCoinFloor.test.js` (created, 169 lines) — TST-BUR-03 far-future coin jackpot floor + early-bail
- `test/stat/WholeBurnieFloorInvariant.test.js` (created, 262 lines) — TST-BUR-04 invariant sweep + mint-boost negative assertion
- `test/stat/SurfaceRegression.test.js` (modified, +31/-11) — `SURF_01_PROTECTED_RANGES_V40` re-cut + header comment
- `package.json` (modified, +1/-1) — `test:stat` script file list extended

## Test Results

`npx hardhat test` on the 5 Phase 279 test files → **46 passing, 3 failing**.

- All 4 new TST-BUR files pass (35 new tests green).
- The v40.0 SURF-01..05 block all pass — the `SURF_01_PROTECTED_RANGES_V40` re-cut FIXED the previously-failing v40.0 SURF-01.
- `npm run test:stat` confirmed to execute `WholeBurnieFloorInvariant.test.js`.
- The 3 failures are PRE-EXISTING in older superseded-baseline SURF blocks (v35/v34, v37/v36, v38/v37) — see Deviation 2.

## Decisions Made

See `key-decisions` in frontmatter. The load-bearing call: source-structural `extractBody` proof is primary evidence for the 3 fixture-gapped BUR functions (the `JackpotTicketRollSilentColdBust.test.js` precedent), with JS boundary math as confirmation — no on-chain tester contract.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Non-hex char in `makeRng` seed strings crashed `keccak256`**
- **Found during:** Task 2 (`test/stat/WholeBurnieFloorInvariant.test.js`)
- **Issue:** The `makeRng` seed strings originally contained a non-hex character (`u`) that crashed `keccak256` when the seeded PRNG was instantiated.
- **Fix:** Corrected to valid-hex seeds (`"279b04a01"` etc.).
- **Files modified:** `test/stat/WholeBurnieFloorInvariant.test.js`
- **Verification:** 8/8 `it`s pass after the fix.
- **Committed in:** `37207743` (part of the batched test commit)

### Surfaced, NOT Fixed (out of scope, user-acknowledged)

**2. 3 pre-existing superseded-baseline SURF block failures**
- **Found during:** Task 3 (full test wave run)
- **Issue:** `npx hardhat test` on the 5 Phase 279 files shows 3 failures in older superseded-baseline SURF blocks (v35/v34, v37/v36, v38/v37 byte-identity assertions).
- **Root cause:** Tripped by the Wave-1 contract commit `8ef4a010` (the whole-BURNIE floor edits to `DegenerusGameJackpotModule.sol`), NOT by plan 279-02. Verified by stashing the test edits and re-running against the pre-279-02 tree — identical 3 failures.
- **Disposition:** The plan explicitly directed surfacing rather than silently editing superseded SURF blocks. User reviewed the batched diff and approved committing 279-02 as-is.
- **Recommended follow-up:** `it.skip` the 3 pre-existing superseded-baseline SURF blocks (v35/v34, v37/v36, v38/v37) in a separate follow-up — they assert byte-identity against baselines that are now superseded by the Phase 279 Wave-1 contract delta and will not pass against the post-Wave-1 tree.

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug), 1 surfaced-not-fixed (out of scope, user-acknowledged).
**Impact on plan:** The auto-fix was necessary for TST-BUR-04 to run at all. The surfaced SURF failures are pre-existing and unrelated to this plan's scope — no scope creep. Plan executed as written; the batched single-commit shape was followed exactly.

## Issues Encountered

None beyond the deviations above. The mocha file-unloader `MODULE_NOT_FOUND` line at the tail of the `hardhat test` output is a known harmless hardhat/mocha disposal quirk — it does not affect the pass/fail tally.

## Self-Check: PASSED

- All 4 created test files exist on disk.
- Test commit `37207743` exists in git history.
- `279-02-SUMMARY.md` exists.
