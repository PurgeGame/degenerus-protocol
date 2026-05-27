---
phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
plan: 05
subsystem: testing
tags: [foundry, non-widening-regression, deferred-red-deletion, de-crank-rename, git-mv, 42-name-gate, reward-rehoming, SAFE-03, H-CANCEL-SWAP, frozen-subject, by-name-gate]

# Dependency graph
requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the v49 keeper-router source (63bc16ca) that flipped the 17 reward-rehoming reds green->red (unified-bounty RD-4, dropped batchPurchase rngLock guard RD-2, autoOpen entry-gate RD-5, AutoBought-event retirement GASOPT-04)"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    provides: "the GAS-calibrated constants (BUY_BATCH/OPEN_BATCH/OPEN_KNEE/RESOLVE_FLAT_BURNIE/ratios) + the 331 CrankFaucetResistance/CrankNonBrick extensions that made the count 17 (not 16) at HEAD"
  - phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
    provides: "the v49 re-author homes the 17 deletions point at — KeeperRouterOneCategory (332-02, 9 GREEN), KeeperRewardRoutingSameResults (332-03, 7 GREEN), DegeneretteResolveRepeg (332-04, 7 GREEN)"
provides:
  - "TST-04 part A: the 17 premise-retired reward-rehoming reds DELETED (not repaired) — v49 invariants re-authored fresh at 332-02/03/04, so the deletion loses zero coverage"
  - "the forge test failing set restored to EXACTLY the 42 v48.0-baseline reds BY NAME (59 -> 42), proven pre- and post-delete against test/REGRESSION-BASELINE-v48.md §2 with zero new regression and zero baseline-red drop"
  - "the 5 Crank*-named test files git mv'd (history preserved, R094-R098) to Keeper*-prefixed names with internal contract-decl + @title + header-NatSpec de-crank — pure rename, behavior-neutral (post-rename failing set byte-identical to post-delete: 666/42)"
  - "SAFE-03 / H-CANCEL-SWAP preserved (the no-double-buy / cancel-tombstone / reentrancy-rollback cases in KeeperNonBrick + AfKingConcurrency stay GREEN, never the retired AutoBought event); testCrankBoxOpenStaysPostUnlock preserved GREEN"
affects: [332-06-v49-regression-ledger, 333-terminal-delta-audit-3-skill-adversarial-sweep-closure]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "BY-NAME non-widening gate (T-332-05-WIDEN mitigation): parse forge test --json, build the live failing (file-basename, testName) set, assert `failing - the-17-set == the 42 v48 union` EXACTLY — a bare count gate would mask a NEW regression that coincidentally offsets a deletion. Ran the gate both PRE-delete (59 - 17 == 42) and POST-delete (== 42) and POST-rename (== 42, byte-identical)."
    - "Surgical brace-depth function deletion: a Python pass extracts each named function (leading /// NatSpec block through the brace-matched closing }) and removes EXACTLY the 17 named functions interspersed among survivors, plus any helper/constant transitively orphaned ONLY by the deleted set (grep-verified outside-deleted use == 0 before removal) and the now-dead section-divider headers whose every test was deleted."
    - "git mv + internal-symbol rename keeping git rename-detection (R094-R098 similarity): the contract decl + @title are the only code-level identifiers; cross-file references to the old names are all provenance COMMENT prose (Foundry test contracts do not import each other), so the rename has no code-level dependency to update."
    - "Behavior-neutrality proof for a pure rename = the post-rename forge failing NAME set is byte-identical to the post-delete set (666 passed / 42 failed both runs); a rename that perturbed any test would shift a name in/out of the 42-union."

key-files:
  created: []
  modified:
    - "test/fuzz/CrankFaucetResistance.t.sol -> test/fuzz/KeeperFaucetResistance.t.sol (9 reds deleted + 3 orphaned helpers + 3 orphaned constants + 1 dead header removed; git mv'd; 5 survivor test names de-cranked; 13 GREEN tests remain)"
    - "test/gas/CrankLeversAndPacking.t.sol -> test/gas/KeeperLeversAndPacking.t.sol (2 reds deleted + dead GAS-02-behavioral header + 3 orphaned reward constants removed; git mv'd; 5 GREEN source-presence/guard tests remain)"
    - "test/fuzz/CrankNonBrick.t.sol -> test/fuzz/KeeperNonBrick.t.sol (4 reds deleted + 2 dead headers removed; git mv'd; 14 GREEN tests remain incl. all SAFE-02/SAFE-03 isolation + cancel-tombstone + reentrancy-rollback cases)"
    - "test/gas/CrankOpenBoxWorstCaseGas.t.sol -> test/gas/KeeperOpenBoxWorstCaseGas.t.sol (no deletions; pure git mv + decl/title/header de-crank; 2 GREEN tests)"
    - "test/gas/CrankResolveBetWorstCaseGas.t.sol -> test/gas/KeeperResolveBetWorstCaseGas.t.sol (no deletions; pure git mv + decl/title/header de-crank; 4 GREEN tests)"
    - "test/fuzz/RngFreezeAndRemovalProofs.t.sol (NOT renamed; 2 reds deleted; testCrankBoxOpenStaysPostUnlock preserved GREEN)"

key-decisions:
  - "RE-CONFIRMED the count is 17 (not 16) at the actual execution HEAD via a live forge test --json: 666 passed / 59 failed; 59 - the-17-named-set == the 42 v48 union by NAME, zero failing name outside (17-set union 42-union). The pre-delete gate is the binding correctness check, not a bare count (T-332-05-WIDEN)."
  - "Deleted EXACTLY the 17 enumerated functions (9 KeeperFaucetResistance + 2 KeeperLeversAndPacking + 4 KeeperNonBrick + 2 RngFreezeAndRemovalProofs) plus only the helpers/constants used SOLELY by them (CRANK_RESOLVE_BET_GAS_UNITS / CRANK_OPEN_BOX_GAS_UNITS / CRANK_GAS_PRICE_REF in both files + _placeWinningBet / _winningTicketFor / _countCoinflipStakeUpdatedWithAmount in KeeperFaucetResistance), grep-verified zero outside-use before removal. Survivor-shared helpers were left intact."
  - "PRESERVED the survivors the plan flagged: testReCrankResolvedBetRevertsNoSecondReward + testCrankBoxesBeforeRngWordEmitsNoReward (KeeperFaucetResistance, NOT in 17-set), testBatchPurchaseGameOverRejectsWholeBatchAtEntry + all SAFE-02/SAFE-03/cancel-tombstone/reentrancy cases (KeeperNonBrick), and testCrankBoxOpenStaysPostUnlock (RngFreezeAndRemovalProofs)."
  - "De-cranked 5 GREEN survivor test-function names inside KeeperFaucetResistance (SelfCrank->SelfKeeper, ReCrank->ReResolve, CrankBoxesBeforeRngWord->AutoOpenBoxesBeforeRngWord, WwxrpCrank->WwxrpKeeper) — none are in the 42-red union (all GREEN), so the by-name gate is unaffected; this completes the de-crank inside the renamed files without touching test logic."
  - "Left testCrankBoxOpenStaysPostUnlock in the NOT-renamed RngFreezeAndRemovalProofs.t.sol UNCHANGED: D-07's de-crank scope is the 5 named files; the plan explicitly flags this green test DO-NOT-DELETE and `do not edit test logic`. It is the single deliberate code-level Crank residual; all other Crank tokens across test/ are provenance comment prose."
  - "Header NatSpec in each renamed file was de-cranked AND refreshed to describe the post-deletion survivor set (the stale 'summed per-item reward / REW-02 / one WINNING bet' prose that described the deleted tests was removed) — comment-only edits, zero behavioral change; the post-rename gate confirms byte-identical behavior."

patterns-established:
  - "Pattern 1: pre-AND-post BY-NAME non-widening gate around a destructive test edit — assert `failing - deleted-set == carried-forward-union` before deleting (proves the deletion target is exactly the premise-retired set) and `failing == carried-forward-union` after (proves net-zero new regression); the count is a derived sanity check, never the gate."
  - "Pattern 2: rename-as-no-op verification — a pure git mv + symbol rename is proven behavior-neutral by re-running the full forge tree and asserting the failing NAME set is byte-identical to the pre-rename run (666/42 both), not merely that it still compiles."

requirements-completed: [TST-04]

# Metrics
duration: 38min
completed: 2026-05-27
---

# Phase 332 Plan 05: TST-04 Part A — Delete the 17 Premise-Retired Reds + De-Crank Rename 5 Files Summary

**Restored a clean NON-WIDENING v49 red-set: DELETED the 17 enumerated premise-retired reward-rehoming reds (their v49 invariants re-authored fresh at 332-02/03/04 — not repaired in place, per D-04) and `git mv`-renamed the 5 `Crank*` test files to `Keeper*` with internal contract/`@title`/header de-crank (D-07, pure rename). The `forge test` failing set returns to EXACTLY the 42 v48.0-baseline reds BY NAME — proven pre-delete (59 − 17 == 42), post-delete (== 42), and post-rename (== 42, byte-identical 666/42) — with zero new regression, zero baseline-red drop, SAFE-03 / H-CANCEL-SWAP and `testCrankBoxOpenStaysPostUnlock` preserved GREEN, and ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~38 min
- **Tasks:** 2 (both `type=auto`)
- **Files modified:** 6 (5 renamed Crank->Keeper + RngFreezeAndRemovalProofs in place)
- **Net:** 736 deletions (the 17 reds + orphaned helpers/constants/headers) + a behavior-neutral 5-file rename

## Accomplishments

### Task 1 — Re-confirm the live red-set, then delete the 17 premise-retired reds (`8041451d`)

- **Pre-delete BY-NAME gate (binding):** ran `forge test --json` at HEAD `1318372d` → **666 passed / 59 failed**. Built the live failing `(file-basename, testName)` set and the 42-name v48 union from `test/REGRESSION-BASELINE-v48.md §2` (Buckets A/B/C + the B13 `DegeneretteFreezeResolution::testDgnrsAwardStaysPerSpin` note). Result: `failing − the-17-set == the 42 v48 union EXACTLY`, **zero failing name outside `17-union-42`**, all 17 present, all 42 present. The count is 17 (NOT 16) — confirmed live, per RESEARCH Pitfall 1.
- **Deleted EXACTLY the 17 functions** (with their leading NatSpec, brace-depth extracted):
  - `KeeperFaucetResistance` (9): `testBatchEmitsExactlyOneCreditFlipWithSum`, `testCrankBeforeRngWordSkipsAndDoesNotReward`, `testDuplicateInBatchRewardsOnce`, `testFuzz_MultiBoxRoundTripNonPositiveAcrossGasPrices`, `testFuzz_RoundTripNonPositiveAcrossGasPrices`, `testMultiBoxSelfCrankRoundTripNonPositive`, `testSelfCrankRoundTripNonPositive`, `testWinningBetFullResolvePathStillPegsReward`, `testZeroSuccessBatchEmitsNoCreditFlip`
  - `KeeperLeversAndPacking` (2): `testCrankBetsEmitsExactlyOneCreditFlipForManyItems`, `testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes`
  - `KeeperNonBrick` (4): `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry`, `testCrankBetsSkipsPoisonedMiddleItem`, `testCrankBoxesSkipsPoisonedEntryViaTryCatch`, `testFuzz_CrankBetsPoisonPositionNeverBricks`
  - `RngFreezeAndRemovalProofs` (2): `testCrankBetResolutionStaysPostUnlock`, `testFuzz_CrankResolvesIffWordLanded`
- **Removed only the orphaned helpers/constants used SOLELY by deleted tests** (grep-verified zero outside-use first): the `CRANK_RESOLVE_BET_GAS_UNITS` / `CRANK_OPEN_BOX_GAS_UNITS` / `CRANK_GAS_PRICE_REF` summed-reward constants in both `Crank{FaucetResistance,LeversAndPacking}`, plus `_placeWinningBet` / `_winningTicketFor` / `_countCoinflipStakeUpdatedWithAmount` in `KeeperFaucetResistance`, plus the 3 now-dead section-divider headers whose every test was deleted.
- **Preserved** `testCrankBoxOpenStaysPostUnlock` (green, not in 17-set) and every SAFE-02/SAFE-03/cancel-tombstone/reentrancy survivor.
- **Post-delete gate:** **666 passed / 42 failed**; `failing == the 42 v48 union by NAME` EXACTLY — net-zero new regression.

### Task 2 — De-crank rename the 5 `Crank*` files to `Keeper*` (`52452fe1`)

- **`git mv` (history preserved, R094-R098)** + internal `contract` decl + `@title` rename:
  - `test/fuzz/CrankFaucetResistance.t.sol` → `test/fuzz/KeeperFaucetResistance.t.sol` (`contract CrankFaucetResistance` → `KeeperFaucetResistance`)
  - `test/fuzz/CrankNonBrick.t.sol` → `test/fuzz/KeeperNonBrick.t.sol` (`CrankNonBrick` → `KeeperNonBrick`)
  - `test/gas/CrankLeversAndPacking.t.sol` → `test/gas/KeeperLeversAndPacking.t.sol` (`CrankLeversAndPacking` → `KeeperLeversAndPacking`)
  - `test/gas/CrankOpenBoxWorstCaseGas.t.sol` → `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` (`CrankOpenBoxWorstCaseGas` → `KeeperOpenBoxWorstCaseGas`)
  - `test/gas/CrankResolveBetWorstCaseGas.t.sol` → `test/gas/KeeperResolveBetWorstCaseGas.t.sol` (`CrankResolveBetWorstCaseGas` → `KeeperResolveBetWorstCaseGas`)
- **Header NatSpec de-cranked + refreshed** in each file to describe the post-deletion survivor set (removed the stale `summed per-item reward / REW-02 / one WINNING bet / rngLocked-pre-check` prose that described the deleted tests). Comment-only; the `ReentrantWithdrawer` + `interface AfKingLike` helper names (non-"crank") left untouched.
- **De-cranked 5 GREEN survivor test names** in `KeeperFaucetResistance` (`testReCrankResolvedBetRevertsNoSecondReward` → `testReResolveResolvedBetRevertsNoSecondReward`, `testCrankBoxesBeforeRngWordEmitsNoReward` → `testAutoOpenBoxesBeforeRngWordEmitsNoReward`, `testRouterOpenSelfCrankRoundTripNonPositive` → `testRouterOpenSelfKeeperRoundTripNonPositive`, `testRouterBuySelfCrankRoundTripNonPositive` → `testRouterBuySelfKeeperRoundTripNonPositive`, `testWwxrpCrankEarnsZeroReward` → `testWwxrpKeeperEarnsZeroReward`) — none in the 42-red union, gate unaffected.
- **The `degeneretteResolve(` CONTRACT-symbol source-presence greps in `KeeperLeversAndPacking` are UNTOUCHED** (a contract symbol, not a test-file name).
- **Post-rename gate:** **666 passed / 42 failed**, failing NAME set **byte-identical** to the post-delete run — the rename is provably behavior-neutral. `forge build` exit 0.

## Source -> Dest Rename Mapping (for the 332-06 ledger §4)

| Current file | Current contract | git mv target | New contract |
|--------------|------------------|---------------|--------------|
| `test/fuzz/CrankFaucetResistance.t.sol` | `CrankFaucetResistance` | `test/fuzz/KeeperFaucetResistance.t.sol` | `KeeperFaucetResistance` |
| `test/fuzz/CrankNonBrick.t.sol` | `CrankNonBrick` | `test/fuzz/KeeperNonBrick.t.sol` | `KeeperNonBrick` |
| `test/gas/CrankLeversAndPacking.t.sol` | `CrankLeversAndPacking` | `test/gas/KeeperLeversAndPacking.t.sol` | `KeeperLeversAndPacking` |
| `test/gas/CrankOpenBoxWorstCaseGas.t.sol` | `CrankOpenBoxWorstCaseGas` | `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | `KeeperOpenBoxWorstCaseGas` |
| `test/gas/CrankResolveBetWorstCaseGas.t.sol` | `CrankResolveBetWorstCaseGas` | `test/gas/KeeperResolveBetWorstCaseGas.t.sol` | `KeeperResolveBetWorstCaseGas` |

## Task Commits

1. **Task 1 — delete the 17 premise-retired reds** — `8041451d` (test) — 4 files changed, 736 deletions
2. **Task 2 — de-crank rename the 5 Crank* files to Keeper*** — `52452fe1` (test) — 5 files changed, 68 insertions / 78 deletions, 5 renames (94-98% similarity)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) — see the final docs commit.

## Verification

- **Pre-delete gate:** `forge test --json` = 666/59; `failing − 17 == 42 v48 union by NAME` (zero outside, all 17 + all 42 present).
- **Post-delete gate:** `forge test --json` = 666/42; `failing == 42 v48 union by NAME` EXACTLY (zero new regression, zero baseline-red drop).
- **Post-rename gate:** `forge test --json` = 666/42; failing NAME set byte-identical to post-delete (rename behavior-neutral).
- `forge build` exit 0 after both tasks (lint warnings only, no errors).
- `git diff --name-only contracts/` → empty (ZERO mainnet mutation, FROZEN subject honored; `ContractAddresses.sol` unchanged — Hardhat fixture not run this plan).
- No `Crank*`-NAMED test file remains; no `contract Crank*` decl remains; `git mv` rename-detection preserved history.
- `grep -rn Crank test/` code-level (non-comment) residual = ONLY `testCrankBoxOpenStaysPostUnlock` (the plan-flagged DO-NOT-DELETE green survivor in the NOT-renamed `RngFreezeAndRemovalProofs.t.sol`); all other Crank tokens are provenance comment prose.

## Deviations from Plan

None affecting scope. Two execution refinements (test-only, no scope change):

1. **[Refinement — orphan hygiene] Removed the 3 summed-reward constants + 3 orphaned helpers the deletion stranded.** The plan named the `3 * CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF` summed-reward constant as the canonical orphan to grep-and-remove; the deletion of the 9 KeeperFaucetResistance reds also orphaned `_placeWinningBet` / `_winningTicketFor` / `_countCoinflipStakeUpdatedWithAmount` (grep-verified zero surviving caller). All were removed to keep the survivor files clean. Survivor-shared helpers were left intact.
2. **[Refinement — D-07 completion inside the renamed files] De-cranked 5 GREEN survivor test-function names in KeeperFaucetResistance.** D-07 names file + contract/symbol decls; the survivor test names embedding the standalone word "Crank"/"SelfCrank" inside the renamed file were de-cranked too (pure identifier rename of GREEN tests, zero behavioral change, none in the 42-red union). `testCrankBoxOpenStaysPostUnlock` in the NOT-renamed `RngFreezeAndRemovalProofs.t.sol` was left UNCHANGED per the explicit plan directive (DO-NOT-DELETE + do-not-edit-test-logic).

No CLAUDE.md present in the project root (global instructions only).

## Contract Defects Surfaced

None. No deletion or rename surfaced a CONTRACT defect; the subject stayed byte-frozen (zero `contracts/*.sol` mutation).

## Known Stubs

None — this plan only deletes premise-retired tests and renames files. No new code, no placeholders, no unwired data. The surviving tests are unchanged and drive real protocol state; the v49 invariants the deletions retired are fully re-authored at 332-02/03/04 (KeeperRouterOneCategory 9 GREEN / KeeperRewardRoutingSameResults 7 GREEN / DegeneretteResolveRepeg 7 GREEN), so coverage is preserved.

## Self-Check: PASSED

- `test/fuzz/KeeperFaucetResistance.t.sol` — FOUND (13 tests)
- `test/fuzz/KeeperNonBrick.t.sol` — FOUND (14 tests)
- `test/gas/KeeperLeversAndPacking.t.sol` — FOUND (5 tests)
- `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` — FOUND (2 tests)
- `test/gas/KeeperResolveBetWorstCaseGas.t.sol` — FOUND (4 tests)
- commit `8041451d` (deletions) — FOUND
- commit `52452fe1` (renames) — FOUND
- `forge test` post-rename — 666 passed / 42 failed; failing set == the 42 v48 union by NAME (zero new regression)
- `git diff --name-only contracts/` — empty (zero mainnet mutation)
