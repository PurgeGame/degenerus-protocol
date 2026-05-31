---
phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
plan: 03
subsystem: testing
tags: [foundry, fuzz, afking, game-resident, mintBurnie, router, faucet-resistance, differential, one-category, vm-readfile, storage-slots]

# Dependency graph
requires:
  - phase: 351-01
    provides: "the compiling DeployProtocol fixture (GameAfkingModule at GAME_AFKING_MODULE) the Keeper* corpus adaptation builds on"
  - phase: 351-02
    provides: "the RE-DERIVED game storage slots (SUBOF=66, _subscribers=68, mintPacked_=10, claimablePool=slot1:off16, afkingFunding=8) + the validated game-resident driving harness (advanceGame STAGE buy / mintBurnie open leg / _settleGame VRF drain / _grantDeityPass / _fundPool) + the tandem-claimablePool-credit test-infra reality"
  - phase: 349.2
    provides: "the frozen 453f8073 contract subject (game-resident mintBurnie router + the restored LOOTBOX quest/affiliate side-effects)"
provides:
  - "Three adapted Keeper* reward/router/faucet fuzz files running against the game-resident mintBurnie() router"
  - "The PRESERVED-VERBATIM differential same-results scaffolding (the CoinflipStakeUpdated recipient-isolated topic-decode + the _settleGame VRF-drain) that 351-04/05/08 port for the box differential"
  - "The two vm.readFile runtime traps cleared (AFKING_SRC repointed to GameAfkingModule.sol; the source-grep reentrancy attest re-derived onto the relocated mintBurnie() body)"
  - "RE-DERIVED downstream slots: lootboxRngPacked=38, lootboxRngWordByIndex=39, lootboxEthBase=23, ticketQueue=13, ticketsOwedPacked=14, degeneretteBets=46, degeneretteBetNonce=47"
affects: [351-04, 351-05, 351-08, 351-09, "TST-02 (the funded/revert-free corners feed the KeeperNonBrick full proof)", "REGRESSION-BASELINE-v55.md (the rewrite map for these 3 files)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Router reframe: the v55 mintBurnie() is a structural one-category early-return `if(advanceDue){advance leg}else{open leg}` — TWO categories (advance / afking-box open), the buy folded into advanceGame's STAGE so it rides the advance bounty (there is NO separate router buy leg to pin)"
    - "Faucet open-leg reframe: the afking open leg opens STAGE-stamped afking boxes (reachable ONLY via mintBurnie — the module standalone autoOpen selector collides with the human autoOpen(uint256)); the reward is OBSERVED off the mintBurnie credit delta, not modeled"
    - "afkingSnapshot (the v55 rename of the removed keeperSnapshot) carries a 4th afkingFundings column — the batched-read same-results reframes onto it (an OFF-hot-path Game view, not a GAS-02 STATICCALL violation)"
    - "vm.readFile source-grep repointing: AFKING_SRC -> contracts/modules/GameAfkingModule.sol + every grepped token re-derived for the relocated mintBurnie() body (the deleted AfKing.sol THROWS at runtime)"
    - "One new-day STAGE cycle per fixture: multiple _runStageNewDay calls in a single test cross the level-0 365-day liveness timeout (gameOver), so multi-k open-corner loops split into per-k tests + the fuzz sweeps the range"

key-files:
  created:
    - ".planning/phases/351-.../351-03-SUMMARY.md"
  modified:
    - "test/fuzz/KeeperRewardRoutingSameResults.t.sol"
    - "test/fuzz/KeeperRouterOneCategory.t.sol"
    - "test/fuzz/KeeperFaucetResistance.t.sol"

key-decisions:
  - "Marked NEITHER TST-02 nor TST-05 complete. This plan FEEDS TST-02 (the one-category-no-stack + faucet-resistance + the gameover-advance-no-revert class-C touch reframed onto mintBurnie) but the FULL TST-02 proof (the _resolveBuy REVERT-01 invariants, class-B solvency fail-loud, class-C gameover-unblocked) is owned by 351-05 (KeeperNonBrick). TST-05 = the REGRESSION-BASELINE-v55.md BY-NAME ledger (a downstream deliverable); this plan only makes its 3 files COMPILE+RUN for the reconciliation, it does not author the ledger. Marking either complete would over-claim (the same honesty 351-01/351-02 applied)."
  - "keeperSnapshot is a REMOVED surface (the v49 batched read) RENAMED to afkingSnapshot (D-351-01: renamed/relocated, NOT a removed-surface drop) — the GASOPT-03 same-results reframes onto afkingSnapshot (now returning a 4th afkingFundings column), not dropped per D-351-02."
  - "The autoBuy-consumes-keeperSnapshot identical-outcome test (testKeeperSnapshotDrivenAutoBuyIdenticalOutcome) reframed: in v55 the per-sub buy folded into advanceGame's STAGE (the standalone autoBuy that consumed keeperSnapshot is GONE), so the claim 'the autoBuy reads keeperSnapshot' is no longer true — reframed to testStageDrivenAutoBuyStampsSubBoughtToday (the STAGE-driven buy stamps the sub bought-today, the actual surviving outcome)."
  - "The faucet BUY-leg round-trip (the v49 flat-1.5x buy bounty BUY_RATIO_NUM/DEN=3/2) reframed onto the ADVANCE-leg bounty (unit*ADVANCE_RATIO_NUM*mult): in v55 there is NO separate router buy bounty — the buy folded into advanceGame's STAGE so the buy reward IS the advance bounty. BUY_RATIO_NUM/DEN are gone; OPEN_KNEE=5/ADVANCE_RATIO_NUM=2 mirrored; BOUNTY_ETH_TARGET is now a hardcoded module constant (885_000_000, no game getter) mirrored directly (the old afKing.BOUNTY_ETH_TARGET() live-read is gone)."
  - "The standalone-autoBuy-unrewarded escape (no v55 successor) DROPPED; the standalone-autoOpen-unrewarded escape reframed onto the HUMAN game.autoOpen (the afking standalone autoOpen is not re-exposed on the Game — selector collision)."

patterns-established:
  - "Re-derive EVERY pinned slot via forge inspect storage DegenerusGame before trusting an inherited constant — the v55 afking append shifted lootboxEthBase 22->23, ticketQueue 12->13, ticketsOwedPacked 13->14, degeneretteBets 45->46, degeneretteBetNonce 46->47, lootboxRngPacked 37->38, lootboxRngWordByIndex 38->39 (a silent off-by-one breakage if carried)"

requirements-completed: []  # TST-02 partial-contributor (full proof = 351-05); TST-05 = downstream ledger — see key-decisions

# Metrics
duration: 55min
completed: 2026-05-31
---

# Phase 351 Plan 03: Keeper* Reward/Router/Faucet Adaptation to mintBurnie Summary

**Adapted the three `Keeper*` reward/router/faucet fuzz files to the game-resident `mintBurnie()` router — the advance-reward routing, the one-category-no-stack structural early-return, and the bounty-bounded faucet-resistance corners all reframed onto `mintBurnie`'s `if(advanceDue){advance}else{open}` split, the two `vm.readFile` traps repointed to `GameAfkingModule.sol`, the differential `_settleGame`/topic-decode scaffolding PRESERVED VERBATIM for the downstream box differential — 28 tests green in isolation, ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~55 min
- **Completed:** 2026-05-31
- **Tasks:** 3
- **Files modified:** 3 adapted fuzz files
- **Tests:** 28 owned (7 KeeperRewardRoutingSameResults + 7 KeeperRouterOneCategory + 14 KeeperFaucetResistance), all passing in isolation; 74/74 in the combined run alongside the already-adapted AfKing*/V55/DeployCanary corpus

## Accomplishments

- **The three `Keeper*` fuzz files are adapted to `game.mintBurnie()`** — every `afKing.`/`doWork()` call-site rewritten (Δ3); the v49 advance-reward / one-category / faucet-resistance properties reframed onto the v55 structural early-return; both `vm.readFile("contracts/AfKing.sol")` runtime traps repointed.
- **The PRIMARY differential same-results scaffolding is PRESERVED VERBATIM** — `KeeperRewardRoutingSameResults` keeps the `CoinflipStakeUpdated` recipient-isolated topic-decode (`COINFLIP_STAKE_UPDATED_SIG` + `_countCoinflipStakeUpdatedFor`/`_keeperCreditCountAndAmount`) and the `_settleGame` VRF-drain helper byte-intact — the exact instruments 351-04/05/08 port for the box stamp→open differential.
- **The one-category-no-stack property is reframed + asserted non-vacuously** — `testOneCategoryEarlyReturnNoStack` stages BOTH a pending afking box AND a due advance, then proves the single `mintBurnie()` credits exactly once (the advance arm) AND leaves the pending box unopened (the `else` open arm never ran — the XOR holds).
- **The faucet-resistance corners hold on the game-resident router** — the OPEN hot corner (k stamped afking boxes opened via `mintBurnie`, reward OBSERVED off the credit delta, below-knee + at/above-knee + fuzzed 1..2*KNEE) and the ADVANCE-leg bounty (the buy rides it) each stay strictly below the real gas at the >=1 gwei floor; the degenerette-resolve faucet corners preserved verbatim.
- **The source-grep reentrancy attestation re-derived onto the relocated `mintBurnie()` body** — `testMintBurnieReentrancyStructurallySafeSourceAttest` reads `GameAfkingModule.sol` (no runtime throw), proves the single CEI-last `creditFlip(msg.sender, bountyEarned)`, and pins the module's file-wide ETH-push count at ZERO (the funding self-send moved to `DegenerusGame.withdrawAfkingFunding`).
- **ZERO `contracts/*.sol` mutation** — `git diff --name-only 453f8073 HEAD -- contracts/` is EMPTY; `ContractAddresses.sol` restored byte-identical after every `patchForFoundry` round-trip.

## Task Commits

Each task was committed atomically (test/ only — no contracts/):

1. **Task 1: Adapt KeeperRewardRoutingSameResults (the differential donor)** — `440c2e0a` (test)
2. **Task 2: Adapt KeeperRouterOneCategory + repoint AFKING_SRC** — `6ace62a5` (test)
3. **Task 3: Adapt KeeperFaucetResistance (bounty-bounded faucet resistance)** — `a4e77e98` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) committed separately.

## Files Created/Modified

- `test/fuzz/KeeperRewardRoutingSameResults.t.sol` — the PRIMARY differential donor. PRESERVED the topic-decode + `_settleGame` VERBATIM. Advance-reward routing reframed onto `mintBurnie` (standalone-advance-unrewarded vs mintBurnie-rewarded-multiplier-honored, mid-day-partial-drain rewarded, gameover-advance unrewarded-no-revert); `keeperSnapshot` (removed) → `afkingSnapshot` (4-return) same-results; the autoBuy-consumes-snapshot test reframed to a STAGE-driven buy stamp; the owedMap pointer-hoist same-results preserved with re-derived ticket slots. 7 tests.
- `test/fuzz/KeeperRouterOneCategory.t.sol` — the one-category-no-stack TST-02 charge. `AFKING_SRC` repointed to `GameAfkingModule.sol` (both the constant + the doc comment); the source-grep reentrancy attest re-derived onto the `mintBurnie()` body; the branch tests collapsed to the v55 TWO categories (advance / open) + the structural-early-return no-stack assertion + the `bountyEarned==0` gameover-skip (category ran, no revert) + NoWork + the human-autoOpen unrewarded escape. 7 tests.
- `test/fuzz/KeeperFaucetResistance.t.sol` — bounty-bounded faucet resistance. The BUY-leg round-trip reframed onto the ADVANCE-leg bounty; the OPEN-leg onto the afking open leg (split below-knee/above-knee + fuzz); the bounty math repointed to the `GameAfkingModule` constants; the whole degenerette-resolve corpus (one-reward-per-item / >=3-gate / WWXRP-excluded / pre-RNG-word block / round-trip guards) preserved verbatim with re-derived slots. 14 tests.

## Decisions Made

- **TST-02 marked NEITHER complete (partial contributor); TST-05 left Pending (downstream ledger).** This plan FEEDS TST-02 — the one-category-no-stack + faucet-resistance + the gameover-advance-no-revert (a class-C touch) reframed onto `mintBurnie` — but the FULL TST-02 proof (the `_resolveBuy` REVERT-01 invariants, the class-B solvency fail-loud, the class-C gameover-unblocked) is owned by 351-05 (`KeeperNonBrick`, PATTERNS §6). TST-05 = the `REGRESSION-BASELINE-v55.md` BY-NAME ledger, a downstream deliverable; this plan only makes its 3 files COMPILE+RUN for the non-widening reconciliation. Marking either complete would over-claim (consistent with 351-01's TST-05 / 351-02's TST-02 honesty).
- **`keeperSnapshot` → `afkingSnapshot` is a rename (D-351-01), not a removed-surface drop (D-351-02).** The batched-read role survives — the v55 `afkingSnapshot` adds a 4th `afkingFundings` column. The GASOPT-03 same-results test reframes onto it (asserting all 4 fields == the individual accessors), it is not dropped.
- **The faucet BUY-leg bounty (v49 flat 1.5x, `BUY_RATIO_NUM/DEN=3/2`) has NO v55 successor.** In v55 the per-sub buy folded into `advanceGame()`'s STAGE, so there is no separate router buy bounty — the buy reward IS the advance bounty (`unit * ADVANCE_RATIO_NUM * mult`). The faucet buy round-trip reframes onto the advance leg; `BUY_RATIO_NUM/DEN` are gone (`ADVANCE_RATIO_NUM=2`/`OPEN_KNEE=5` mirrored). `BOUNTY_ETH_TARGET` is now a hardcoded module constant (`885_000_000`, no game getter), mirrored directly (the old `afKing.BOUNTY_ETH_TARGET()` live-read is gone).
- **The afking open is reachable ONLY via `mintBurnie`** (the module standalone `autoOpen` selector collides with the human `autoOpen(uint256)` so it is not re-exposed on the Game). So the faucet/router OPEN-leg gas is measured via `mintBurnie`'s open branch (reward OBSERVED off the credit delta), and the standalone-unrewarded-escape test reframes onto the HUMAN `game.autoOpen`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stale inherited storage-slot constants (the v55 afking append shifted ~7 slots)**
- **Found during:** Task 2 + Task 3 (first run failures: `lootboxEthBase` read 0, all degenerette tests `BatchAlreadyTaken()`)
- **Issue:** The files carried the pre-v55 slot constants. The v55 game-resident afking append shifted several mappings by 1: `lootboxEthBase` 22→23, `ticketQueue` 12→13, `ticketsOwedPacked` 13→14, `degeneretteBets` 45→46, `degeneretteBetNonce` 46→47, `lootboxRngPacked` 37→38, `lootboxRngWordByIndex` 38→39. A stale slot reads garbage (the `_betNonce` returned a wrong betId → the resolve saw a zero slot → `BatchAlreadyTaken`; `_lootboxEthBase` read 0).
- **Fix:** RE-DERIVED every slot via `forge inspect storage DegenerusGame` and corrected all constants.
- **Files modified:** test/fuzz/KeeperRouterOneCategory.t.sol, test/fuzz/KeeperFaucetResistance.t.sol
- **Commit:** 6ace62a5, a4e77e98

**2. [Rule 1 - Bug] The multi-k open-corner loop crosses the level-0 liveness timeout (gameOver) on the 2nd+ STAGE cycle**
- **Found during:** Task 3 (`testRouterOpenSelfKeeperRoundTripNonPositive` failed `stampK: the STAGE stamped a box` on iteration 2, while the single-cycle fuzz passed)
- **Issue:** Each `_stampKAfkingBoxes` does a `_runStageNewDay` (warp +1 day + settle). Looping k in {1,2,3,4,5,12} in one fixture accumulates warps; at level 0 the 365-day deploy-idle liveness timeout (`_livenessTriggered`) eventually fires → gameOver → the STAGE/open leg no-ops, so the new subs never stamp.
- **Fix:** Split the looping non-fuzz test into two per-k tests (below-knee k=3, at/above-knee k=12), each with its OWN `setUp` (one new-day STAGE cycle per fixture); the fuzz test already sweeps the full 1..2*KNEE range in single-cycle runs.
- **Files modified:** test/fuzz/KeeperFaucetResistance.t.sol
- **Commit:** a4e77e98

**3. [Rule 1 - Bug] testOneCategoryEarlyReturnNoStack could not drive advanceDue via a warp (day saturation after the STAGE day) and a small ticket backlog fully-drained to NotTimeYet**
- **Found during:** Task 2 (the test failed `pre: advance is due`, then `NotTimeYet()`)
- **Issue:** After a STAGE day + settle, a further warp did not reliably re-trigger `advanceDue` (the 351-02 idle-day-saturation reality), and a small read-slot backlog (1 player) fully drained in the mid-day branch → fell through to `NotTimeYet`.
- **Fix:** Force `advanceDue` via a LARGE multi-player read-slot backlog (200 players × 3 tickets) that exceeds the per-batch write budget so the mid-day partial-drain advance WORKS but does not finish (mult==1, no `NotTimeYet`) — the same idiom as the mid-day-partial-drain reward test.
- **Files modified:** test/fuzz/KeeperRouterOneCategory.t.sol
- **Commit:** 6ace62a5

**Total deviations:** 3 auto-fixed (all Rule 1 fixture-correctness bugs — stale slots + test-driving realities). No architectural changes; no contract edits.

## Authentication Gates

None.

## Known Stubs

None. Every test asserts a non-vacuous outcome (the box actually opened / the sub actually bought / the credit delta is positive before valuing it / the pending box demonstrably stayed unopened). No hardcoded empty value flows to an assertion.

## Removed-Surface Notes (for the TST-05 ledger / 351-09)

These v49-era surfaces have NO v55 successor and were reframed (NOT silent-deleted) — to be recorded in `REGRESSION-BASELINE-v55.md`:
- `afKing.autoBuy(count)` standalone keeper buy + its mid-block cursor → the per-sub buy folded into `advanceGame()`'s STAGE (D-351-01 semantic remap). The standalone-autoBuy-unrewarded-escape test (`testStandaloneAutoBuyEscapeUnrewarded`) has no successor and was dropped (the buy is single-shot in the STAGE).
- The v49 flat-1.5x buy-leg router bounty (`BUY_RATIO_NUM/DEN`) → folded into the advance bounty (`unit*ADVANCE_RATIO_NUM*mult`). The faucet buy round-trip reframed onto the advance leg.
- `keeperSnapshot` → `afkingSnapshot` (renamed + a 4th `afkingFundings` column; a rename, not a removed surface).
- `afKing.BOUNTY_ETH_TARGET()` external getter → the value is now a hardcoded module `internal constant` (no game getter; mirrored as the literal `885_000_000`).
- `afKing.SUB_COST_ETH_TARGET()` + the subscribe-time BURNIE charge → GONE (no subscribe-time charge in v55).

## Sibling Files NOT Compile-Verified Here (Wave-3 charge)

Per the Wave-2 isolation note, the not-yet-adapted sibling files (owned by OTHER 351 plans) still reference the dissolved standalone AfKing and were sidelined for the isolation run, NOT compiled/run here — the whole-tree compile + full run is Wave 3 (351-09)'s charge: `KeeperNonBrick`, `RngLockDeterminism`, `KeeperBatchAffiliateDeltaAudit`, `RedemptionStethFallback` (test/fuzz/) and `KeeperOpenBoxWorstCaseGas`, `KeeperLeversAndPacking`, `RouterWorstCaseGas`, `SweepPerPlayerWorstCaseGas` (test/gas/). This is expected, not a failure. (The already-adapted `AfKingConcurrency`/`AfKingSubscription`/`AfKingFundingWaterfall`/`V55SetMutationOpenE`/`DeployProtocol`/`DeployCanary` compile + ran green alongside my 3 files: 74/74.)

## Issues Encountered

- **No pretest patch hook** — `patchForFoundry.js` is not auto-invoked. Each isolation run requires `node scripts/lib/patchForFoundry.js` first (predict the CREATE addresses), then `restoreContractAddresses()` + `cleanupBackup()` to keep `contracts/ContractAddresses.sol` frozen (the `.bak` round-trip). The not-yet-adapted siblings must be sidelined (forge compiles the WHOLE tree before any test) and restored after.
- **The idle fixture's day saturation + the level-0 liveness timeout** constrain multi-day STAGE driving (see Deviations 2+3). Downstream plans driving multi-day afking flows should drive real purchases or poke the gate fields / cap the warp count.

## User Setup Required

None.

## Self-Check: PASSED

Created/modified files exist:
- FOUND: `test/fuzz/KeeperRewardRoutingSameResults.t.sol`
- FOUND: `test/fuzz/KeeperRouterOneCategory.t.sol`
- FOUND: `test/fuzz/KeeperFaucetResistance.t.sol`
- FOUND: `.planning/phases/351-.../351-03-SUMMARY.md`

Task commits exist:
- FOUND: `440c2e0a` (Task 1 — KeeperRewardRoutingSameResults)
- FOUND: `6ace62a5` (Task 2 — KeeperRouterOneCategory)
- FOUND: `a4e77e98` (Task 3 — KeeperFaucetResistance)

Scope guard: `git diff --name-only 453f8073 HEAD -- contracts/` = EMPTY (committed AND working-tree); all 3 owned files compile + 28/28 tests pass in isolation (74/74 combined with the adapted corpus); `afKing.`/`doWork()` non-comment count == 0 in all 3; `contracts/AfKing.sol` ref count == 0 in all 3; `_settleGame` + the CoinflipStakeUpdated decode preserved in KeeperRewardRoutingSameResults.

---
*Phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat*
*Completed: 2026-05-31*
