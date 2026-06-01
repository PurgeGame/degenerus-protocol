---
phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
plan: 07
subsystem: testing
tags: [foundry, gas, afking, game-resident, 16.7M-ceiling, marginal, loop-n-divide, sub-stage, mintBurnie, source-grep, packing, storage-slots]

# Dependency graph
requires:
  - phase: 351-01
    provides: "the compiling DeployProtocol fixture (GameAfkingModule at GAME_AFKING_MODULE) the gas corpus builds on"
  - phase: 351-05
    provides: "the validated game-resident driving harness ported here (the _settleGame/_settleClean VRF drain, _setupFundedLootboxSubs, depositAfkingFunding funding, _grantDeityPass, the Sub-stamp slot reads, the tandem claimablePool credit SOLVENCY-01) + the RE-DERIVED slots (_subOf=66, _subscribers=68, _subscriberIndex=69, claimablePool=1:16, claimableWinnings=7, rngWordByDay=11)"
  - phase: 350
    provides: "the 350-TST06-MEASUREMENT-SPEC §0 (the loop-N-divide MARGINAL rule), §1/§2 (the per-buy/per-open instruments + oracles), §5 (the 16.7M HARD per-tx ceiling at SUB_STAGE_BATCH=50)"
  - phase: 349.2
    provides: "the frozen 453f8073 contract subject (the per-sub BURNIE quest/affiliate/creditFlip side-effects the per-sub marginal INCLUDES; SUB_STAGE_BATCH=50; mintBurnie router)"
provides:
  - "RouterWorstCaseGas adapted — the PRIMARY 16.7M-per-tx-ceiling corpus: a 50-chunk processSubscriberStage(50) (via a new-day advanceGame()) AND the afking open leg (via mintBurnie()) each assert < 16_700_000 on the funded-lootbox-sub mix (6 tests; STAGE-50 whole=3.01M, 50x per-sub marginal projection=10.92M, OPEN_BATCH x open marginal=14.90M)"
  - "KeeperLeversAndPacking adapted — AFKING_SRC repointed to GameAfkingModule.sol (no vm.readFile throw), the packed-Sub layout RE-DERIVED against DegenerusGameStorage.sol (8 fields=29 bytes, one slot), the GAS-02 read-once/one-reward reframed onto mintBurnie's _mintPriceInContext()+single CEI-last bounty, G9 auth->operatorApprovals consent gate, G10 swap-pop->_removeFromSet; the v49 batchPurchase grep gates DROPPED BY NAME (D-351-02 removed surface, asserted ABSENT) (5 tests)"
  - "KeeperResolveBetWorstCaseGas — the v55-shifted slots RE-DERIVED (lootboxRngPacked 37->38, lootboxRngWordByIndex 38->39, degeneretteBets 45->46, degeneretteBetNonce 46->47); confirmed afking-DECOUPLED, the loop-N-divide donor idiom :197-242 intact (4 tests)"
  - "SweepPerPlayerWorstCaseGas adapted — the v49 per-player autoBuy sweep reframed onto the per-sub STAGE marginal (loop-N-divide, 50x=15.74M < 16.7M ticket-mode worst case), with the reinvest-vs-typical shape-insensitivity measured from one clean baseline via vm.snapshotState/revertToState (3 tests)"
affects: [351-08, "351-09 (the REGRESSION-BASELINE-v55 ledger: the gas-corpus rewrite map + the dropped removed-surface tests BY NAME)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "The 16.7M-ceiling STAGE measurement: seed exactly SUB_STAGE_BATCH(50) funded lootbox subs (+ the 2 deploy subs), drive ONE new-day advanceGame() — the STAGE block runs processSubscriberStage(50) PRE-RNG over the first 50 cursor positions, then partial-drains — and bracket the whole advance (a conservative over-estimate of the 50-chunk; if the whole advance < 16.7M the chunk certainly is). Non-vacuity = the cursor advanced a full SUB_STAGE_BATCH (_subCursor slot 70:0) AND >= 48 of mine got a NEW stamp (the 2 deploy subs occupy cursor 0..1)"
    - "The afking open leg is reached ONLY via game.mintBurnie() (_autoOpen(OPEN_BATCH)), NOT game.autoOpen(uint256) — the latter is the HUMAN boxPlayers open path (a different selector that returns 0 with no human boxes queued). The open-leg gas is the bracketed mintBurnie() after a _settleClean (so it routes to OPEN, not advance)"
    - "The loop-N-divide MARGINAL in a SINGLE robust fixture (whole-leg gas / N at N=32), NEVER a fragile two-near-N cross-fixture difference (the idle-day-saturation reality makes a second linear new-day cycle trip RngNotReady / the level-0 liveness timeout). The CR-01 'never a single-item total' is honored by construction (divide by N). The 16.7M claim is the projection 50 x the per-sub marginal / OPEN_BATCH x the per-box marginal"
    - "Two independent STAGE measurements in one test = vm.snapshotState() the clean baseline, measure shape A, vm.revertToState(snap), measure shape B — each runs from the identical clean state, dodging the day-index saturation + warm/cold drift that a linear two-cycle run incurs"
    - "Source-grep gate re-derivation: repoint the afking-LOGIC gates to GameAfkingModule.sol (AFKING_SRC) + the packed-Sub LAYOUT gate to DegenerusGameStorage.sol (STORAGE_SRC, the struct lives in storage not the module); re-derive every grepped token for the renamed/relocated/removed symbols; assert REMOVED surfaces ABSENT (count==0) so a regression that re-introduces them flips RED"

key-files:
  created:
    - ".planning/phases/351-.../351-07-SUMMARY.md"
  modified:
    - "test/gas/RouterWorstCaseGas.t.sol"
    - "test/gas/KeeperLeversAndPacking.t.sol"
    - "test/gas/KeeperResolveBetWorstCaseGas.t.sol"
    - "test/gas/SweepPerPlayerWorstCaseGas.t.sol"

key-decisions:
  - "game.autoOpen(uint256) is the HUMAN boxPlayers open path, NOT the afking open — the afking open leg (_autoOpen) is reached ONLY via mintBurnie() (the afking standalone autoOpen selector collides with the human autoOpen(uint256), as V55RevertFreeEvCap noted). So ALL open-leg gas tests drive mintBurnie() after a _settleClean (it routes to OPEN, advance not due). A first attempt with game.autoOpen() returned 0 boxes (no human boxes queued) — caught + corrected."
  - "The STAGE non-vacuity reads the ACTUAL stamp day from the Sub (assert > pre-state) + the cursor (slot 70:0 advanced a full 50-chunk), NEVER a recomputed _simDay() == lastAutoBoughtDay (the contract's process day is the level-aware _simulatedDayIndexAt, NOT (block.timestamp-82620)/1d — a naive recompute mismatched 3 != 2). The 2 deploy subs (VAULT+SDGNRS) occupy cursor 0..1, so a full 50-chunk over 52 subs stamps my first 48 — the non-vacuity asserts >= 48 of mine newly stamped + the cursor at 50."
  - "The loop-N-divide marginal is a SINGLE-fixture whole/N at N=32 (the donor KeeperOpenBoxWorstCaseGas:184 idiom), NOT a two-near-N (gasN - gasNm1) difference. The two-near-N form FAILED two ways: (a) cross-fixture warm/cold noise made gasN <= gasNm1 for the uniform-O(1) open; (b) the second measurement's advance hit RngNotReady from the first cycle's unsettled RNG + the idle-day saturation (351-05's documented single-STAGE-per-fixture reality). The 16.7M claim is the projection (50 x marginal / OPEN_BATCH x marginal), which is the load-bearing bar."
  - "KeeperLeversAndPacking: the packed-Sub layout gate greps DegenerusGameStorage.sol (STORAGE_SRC), NOT GameAfkingModule.sol — the struct Sub is DEFINED in storage; only the afking LOGIC (mintBurnie, _removeFromSet, operatorApprovals, the stamp writes) lives in the module. The v55 Sub is 8 fields = 29 bytes (vs the old AfKing-standalone 6 fields = 31 bytes — the box-redesign added scorePlus1+amount+lastOpenedDay, relocated fundingSource to the sparse _fundingSourceOf map)."
  - "D-351-02 REMOVED-SURFACE DROP (BY NAME, for the 351-09 ledger): the v49 keeper batchPurchase is GONE from contracts (grep -rn 'function batchPurchase' contracts/ == EMPTY, no successor — the per-buy work folded into advanceGame()'s required-path STAGE, which fires NO batched value transfer). In RouterWorstCaseGas the 7 AfKing cursor/bounty-calibration tests were dropped (the standalone autoBuy/autoBuyProgress/subscriberCount/doWork cursor surface has no v55 successor); in KeeperLeversAndPacking the batchPurchase grep gates (G6 one-refund, the GAS-03 parallel-array signature, the G9 AF_KING keeper gate) were dropped and asserted ABSENT (count==0)."
  - "KeeperResolveBetWorstCaseGas is afking-DECOUPLED (0 afKing./doWork() refs — it is the degenerette resolve-bet per-spin marginal donor), but its pinned slots were STALE for v55 (the append shifted them +1). RE-DERIVED via forge inspect (lootboxRngPacked 37->38, lootboxRngWordByIndex 38->39, degeneretteBets 45->46, degeneretteBetNonce 46->47) — else the vm.store/load pokes silently corrupt and the bet-resolve tests vacuously pass; the corrected slots restore real non-vacuity (the 'bet resolved (slot deleted)' asserts pass against the right leaf)."

patterns-established:
  - "To assert a chunked-loop fits a per-tx gas ceiling: seed exactly the chunk size of funded subjects, drive ONE invocation that runs the chunk, bracket the WHOLE call (a conservative over-estimate), assert < the ceiling, and prove non-vacuity via the cursor advance + a per-subject NEW state-stamp (never a recomputed clock that may diverge from the contract's internal index)."
  - "When a per-item marginal must be loop-N-divide but the fixture cannot host two independent measurement cycles (idle-day saturation / VRF re-lock), use a single whole/N at large N (the fixed overhead amortizes) and PROJECT the ceiling (chunk x marginal), OR snapshot/revert to measure two shapes from one clean baseline — never a fragile linear two-cycle difference."

requirements-completed: [TST-06, TST-05]

# Metrics
duration: 21min
completed: 2026-05-31
---

# Phase 351 Plan 07: The `*Gas` Worst-Case Corpus → the v55 STAGE / `mintBurnie` / game-resident Sub (TST-06 + TST-05) Summary

**Adapted the four `*Gas` worst-case files to the v55 AfKing-in-Game game-resident model: `RouterWorstCaseGas` reframes the v49 `AfKing.doWork()` router worst case onto the 16.7M HARD per-tx ceiling — a 50-chunk `processSubscriberStage(50)` (driven by a new-day `advanceGame()`, whole=3.01M) AND the afking open leg (driven by `mintBurnie()`, the open path the HUMAN `game.autoOpen(uint256)` does NOT reach) each assert `< 16_700_000`, with the loop-N-divide MARGINAL projecting 50× the per-sub = 10.92M / OPEN_BATCH× the per-box = 14.90M under the ceiling; `KeeperLeversAndPacking` repoints `AFKING_SRC` → `GameAfkingModule.sol` (killing the `vm.readFile` throw), re-derives the packed-`Sub` layout gate against `DegenerusGameStorage.sol` (8 fields = 29 bytes, one slot), reframes the GAS-02 read-once/one-reward onto `mintBurnie`'s `_mintPriceInContext()` + the single CEI-last bounty + the `operatorApprovals` consent gate, and DROPS the removed-surface v49 `batchPurchase` grep gates BY NAME (asserted ABSENT); `KeeperResolveBetWorstCaseGas` re-derives the v55-shifted slots (the degenerette resolve-bet donor, afking-decoupled); and `SweepPerPlayerWorstCaseGas` reframes the per-player autoBuy sweep onto the per-sub STAGE marginal (50× = 15.74M ticket-mode worst case) with reinvest-vs-typical shape-insensitivity measured via snapshot/revert. 18 tests green in isolation, ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~21 min
- **Completed:** 2026-05-31
- **Tasks:** 3
- **Files:** 4 modified (RouterWorstCaseGas 533 lines, KeeperLeversAndPacking 440, KeeperResolveBetWorstCaseGas 660, SweepPerPlayerWorstCaseGas 319) + 1 SUMMARY created
- **Tests:** RouterWorstCaseGas 6/6 + KeeperLeversAndPacking 5/5 + KeeperResolveBetWorstCaseGas 4/4 + SweepPerPlayerWorstCaseGas 3/3 = 18 green in isolation (the only sibling failures in the whole-`test/gas` run are KeeperOpenBoxWorstCaseGas — 351-08's stale-slot charge)

## Accomplishments

- **RouterWorstCaseGas — the PRIMARY 16.7M ceiling corpus (TST-06).** Reframed the v49 `doWork()` router worst case onto the v55 game-resident STAGE + open leg:
  - **`testStage50ChunkFundedLootboxSubsFitsUnderHardCeiling`** — 50 funded lootbox subs + a new-day `advanceGame()` runs the STAGE `processSubscriberStage(50)` PRE-RNG over the first 50 cursor positions (partial-drains the rest); the whole advance = **3,011,736 < 16,700,000**. Non-vacuity: the cursor advanced a full SUB_STAGE_BATCH AND >= 48 of mine got a NEW stamp.
  - **`testStagePerSubMarginalIsLoopNDivideUnderCeiling`** — the loop-N-divide per-sub marginal (whole/N at N=32) = 218,435; **50× = 10,921,750 < 16.7M**.
  - **`testOpenLegPerBoxMarginalAndWholeLegFitsCeiling`** + **`testOpenLegPerBoxMarginalLoopNDivideUnderCeiling`** — the afking open leg via `mintBurnie()` over N=32 ready boxes; per-box marginal = 74,493 (uniform O(1)); **OPEN_BATCH × = 14,898,600 < 16.7M**.
  - **`testMintBurnieOpenLegRouterFitsCeiling`** (2.51M) + **`testMintBurnieAdvanceLegRouterFitsCeiling`** (0.22M) — the rewarded `mintBurnie()` router's open + advance legs each < 16.7M.
- **KeeperLeversAndPacking — AFKING_SRC repointed + Sub layout re-derived (TST-05).** `AFKING_SRC` = `contracts/modules/GameAfkingModule.sol` (the `vm.readFile` no longer throws); a new `STORAGE_SRC` = `DegenerusGameStorage.sol` for the packed-`Sub` layout gate (8 fields summing to **29 bytes**, one slot — re-derived, not the old AfKing-standalone 31). GAS-02 read-once/one-reward reframed onto `mintBurnie`'s `_mintPriceInContext()` (read-once) + the single `coinflip.creditFlip(msg.sender, bountyEarned)` (CEI-last, one-per-tx) + the one-category early-return; G9 auth → the `operatorApprovals` subscribe-time consent gate; G10 swap-pop → `_removeFromSet`/`_subscribers.pop()`; G11 → the STAGE same-day idempotency. The surviving GAME/DEGENERETTE/LOOTBOX gates (G1-G5/G7/G12/G13, degeneretteResolve reward, enqueueBoxForAutoOpen, boxCursor) kept verbatim.
- **KeeperResolveBetWorstCaseGas — v55-shifted slots re-derived (TST-05).** The degenerette resolve-bet per-spin marginal donor (`:197-242` loop-N-divide intact); ZERO afking coupling confirmed; the stale slots re-derived (lootboxRngPacked 37→38, lootboxRngWordByIndex 38→39, degeneretteBets 45→46, degeneretteBetNonce 46→47; prizePoolsPacked=2 unchanged) so the bet-resolve pokes hit the right leaves (real non-vacuity restored).
- **SweepPerPlayerWorstCaseGas — per-player sweep → per-sub STAGE marginal (TST-06).** The v49 caller-bounded autoBuy per-player worst case reframed onto the per-sub STAGE marginal: `testPerSubStageMarginalAndChunkFitsCeiling` (loop-N-divide whole/N at N=32 = 314,837; **50× = 15,741,850 < 16.7M** ticket-mode worst case, INCLUDING the 349.2-restored per-sub BURNIE side-effects); `testReinvestAndTypicalPerSubMarginalsMatchWithinTolerance` (315k vs 340k, shape-insensitive — measured from one clean baseline via `vm.snapshotState`/`revertToState`); `testStageActuallyStampedNonVacuity` (every funded sub STAMPED).
- **ZERO `contracts/*.sol` mutation** — `git diff --name-only 453f8073 HEAD -- contracts/` is EMPTY (committed AND working-tree); `ContractAddresses.sol` restored byte-identical after every `patchForFoundry` round-trip.

## Task Commits

Each task committed atomically (test/ only — no contracts/):

1. **Task 1: adapt RouterWorstCaseGas — 16.7M ceiling on STAGE-50 + open leg** — `e334a91a` (test)
2. **Task 2: adapt KeeperLeversAndPacking + KeeperResolveBetWorstCaseGas** — `6c69e627` (test)
3. **Task 3: adapt SweepPerPlayerWorstCaseGas — per-player sweep -> per-sub STAGE marginal** — `24e856ee` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) committed separately.

## Files Created/Modified

- `test/gas/RouterWorstCaseGas.t.sol` (MODIFIED, 533 lines) — the PRIMARY 16.7M-ceiling corpus. 6 tests; the STAGE-50 + open-leg under-16.7M asserts; the loop-N-divide marginals; the mintBurnie router legs. RE-DERIVED slots: `rngWordByDay=11`, `lootboxEthBase=23`, `lootboxRngPacked=38`, `lootboxRngWordByIndex=39`, `_subOf=66`, `_subscribers=68`, `_subscriberIndex=69`, `_subCursor=70:0`. Non-comment `afKing.`/`doWork()` count == 0.
- `test/gas/KeeperLeversAndPacking.t.sol` (MODIFIED, 440 lines) — AFKING_SRC repointed + STORAGE_SRC added + the Sub layout re-derived (29 bytes); the GAS-02/03/04 + G1-G13 gates reframed/kept/dropped. `vm.readFile("contracts/AfKing.sol")` count == 0 (the throw eliminated). 5 tests.
- `test/gas/KeeperResolveBetWorstCaseGas.t.sol` (MODIFIED, 660 lines) — the 4 v55-shifted slot constants re-derived; the loop-N-divide donor idiom intact; afking-decoupled. 4 tests.
- `test/gas/SweepPerPlayerWorstCaseGas.t.sol` (MODIFIED, 319 lines) — the per-sub STAGE marginal (loop-N-divide + 50x projection), the reinvest shape-insensitivity (snapshot/revert), the non-vacuity. RE-DERIVED slots (`_subscribers=68`, `_subOf=66`, `claimableWinnings=7`, the Sub offset 21). 3 tests.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The open-leg tests drove `game.autoOpen(uint256)` (the HUMAN boxPlayers path), opening 0 afking boxes**
- **Found during:** Task 1 (the first run failed `open non-vacuity: at least N boxes materialized: 0 < 32`).
- **Issue:** `game.autoOpen(uint256)` walks `boxPlayers[index]` (the HUMAN lootbox open queue, `DegenerusGame.sol:1787`), NOT the afking `_autoOpen` (which is internal, reached only via `mintBurnie()`). With no human boxes queued, `game.autoOpen` returned 0. (The afking standalone `autoOpen` selector collides with the human one — the same trap V55RevertFreeEvCap documented.)
- **Fix:** All open-leg tests drive `game.mintBurnie()` (which calls `_autoOpen(OPEN_BATCH)` over the ready afking boxes) after a `_settleClean` so it routes to the OPEN leg (advance not due). N < OPEN_BATCH so one `mintBurnie()` opens all N.
- **Files modified:** test/gas/RouterWorstCaseGas.t.sol
- **Commit:** e334a91a

**2. [Rule 1 - Bug] The STAGE non-vacuity recomputed `_simDay()` (3 != 2) instead of reading the contract's process day**
- **Found during:** Task 1 (the STAGE test failed `STAGE non-vacuity: each funded sub STAMPED this cycle: 3 != 2`).
- **Issue:** The non-vacuity asserted `_lastBoughtDayOf(sub) == _simDay()` where `_simDay()` = `(block.timestamp-82620)/1d`. But the contract stamps on its LEVEL-AWARE `_simulatedDayIndexAt` process day (AdvanceModule:169), which diverges from the naive recompute. Also the 2 deploy subs (VAULT+SDGNRS) occupy cursor 0..1, so a full 50-chunk over 52 subs stamps only my first 48.
- **Fix:** Read the ACTUAL stamp day from the Sub (assert it advanced > the captured pre-state), assert the cursor advanced a full SUB_STAGE_BATCH (slot 70:0), and assert >= 48 of mine newly stamped (the validated 351-04/05 `stampDay = _lastBoughtDayOf(x)` idiom, never a recomputed clock).
- **Files modified:** test/gas/RouterWorstCaseGas.t.sol
- **Commit:** e334a91a

**3. [Rule 1 - Bug] The loop-N-divide marginal as a two-near-N (gasN - gasNm1) difference was non-monotonic AND tripped RngNotReady**
- **Found during:** Task 1 + Task 3 (the open marginal failed `gasN <= gasNm1` for the uniform-O(1) open; the STAGE marginal + the SweepPerPlayer reinvest test failed `RngNotReady()` on the second measurement cycle).
- **Issue:** (a) For a uniform-O(1) leg there is no per-tx fixed overhead to amortize, so the cross-fixture warm/cold noise dominated the (gasN - gasNm1) difference (gasN < gasNm1). (b) A second linear new-day measurement cycle in one test hit `RngNotReady` — the first cycle's unfulfilled RNG + the idle-day saturation (351-05's single-STAGE-per-fixture reality).
- **Fix:** Use the donor `KeeperOpenBoxWorstCaseGas:184` idiom — a SINGLE-fixture whole-leg/N at N=32 (the CR-01 'never a single-item total' is honored by dividing by N), and assert the 16.7M claim as the projection (50× the per-sub marginal / OPEN_BATCH× the per-box marginal). For SweepPerPlayer's two-shape reinvest test, snapshot the clean baseline via `vm.snapshotState()`, measure typical, `vm.revertToState(snap)`, measure reinvest — each from the identical clean state (no day saturation across them).
- **Files modified:** test/gas/RouterWorstCaseGas.t.sol, test/gas/SweepPerPlayerWorstCaseGas.t.sol
- **Commit:** e334a91a, 24e856ee

**4. [Rule 3 - Blocking] Unicode `×`/`—` characters inside Solidity string literals broke the compile**
- **Found during:** Task 1 + Task 2 (the first compiles failed `Invalid character in string`).
- **Issue:** `×` (in two RouterWorstCaseGas assertion messages) and `—` (in one KeeperLeversAndPacking message) are non-ASCII; Solidity rejects them in a regular `"..."` literal (they are allowed in comments — Unicode in NatSpec compiles).
- **Fix:** Replaced `×` → `x` and `—` → `-` in the string literals only (comments left intact).
- **Files modified:** test/gas/RouterWorstCaseGas.t.sol, test/gas/KeeperLeversAndPacking.t.sol
- **Commit:** e334a91a, 6c69e627

**Total deviations:** 4 auto-fixed (3 Rule-1 — the human-vs-afking open path, the recomputed-clock non-vacuity, the fragile two-near-N marginal; 1 Rule-3 blocking — the Unicode-in-string compile break). No architectural changes; no contract edits.

## Authentication Gates

None.

## Known Stubs

None. Every test asserts a non-vacuous outcome: each funded sub is demonstrably STAMPED (lastAutoBoughtDay advanced) / the cursor advanced a full 50-chunk / each box demonstrably materialized (lastOpenedDay advanced) / the source-grep gates assert a known code symbol IS present + a comment-only sentinel is STRIPPED (the harness-live backstop) + the removed surfaces are ABSENT (count==0). No hardcoded empty value flows to an assertion; the gas asserts compare a bracketed gasleft-delta against the 16.7M literal.

## Removed-Surface / Reframe Notes (for the 351-09 REGRESSION-BASELINE-v55 ledger)

- **D-351-02 REMOVED-SURFACE DROP (BY NAME + reason):** the v49 keeper `batchPurchase` is GONE from contracts (`grep -rn "function batchPurchase" contracts/` == EMPTY) with NO behavioral successor — the per-buy work folded into `advanceGame()`'s required-path STAGE, which fires NO batched value transfer. Two files drop its tests:
  - **RouterWorstCaseGas** — the 7 AfKing cursor/bounty-calibration tests dropped (the standalone `autoBuy`/`autoBuyProgress`/`subscriberCount`/`doWork` cursor surface has no v55 successor; the per-buy/per-open work reframed onto the STAGE + the mintBurnie open leg under 16.7M):
    - `testBuyLegPerPlayerMarginalAndWholeLegFitsBlockGasLimit`
    - `testBuyLegAmortizationGradientConvergesAtN32`
    - `testOpenLegAmortizationGradientBelowSingleBoxTotal`
    - `testTypicalOpenBatchAveragesNineMillion`
    - `testBuyBatchFiftyLandsUnderHardCeiling`
    - `testAdvanceLegMarginalRoutedThroughDoWorkFitsBlockGasLimit`
    - `testDispatchOverheadIsBoundedAndFitsBlockGasLimit`
    - (REFRAMED into the new STAGE-50 / per-sub-marginal / open-leg / mintBurnie-router tests — the property [a buy/open leg fits the per-tx ceiling] is preserved, the mechanism relocated.)
  - **KeeperLeversAndPacking** — the `batchPurchase` source-grep gates dropped + asserted ABSENT (count==0) so a regression that re-introduces the removed surface flips RED: the GAS-02 AfKing `batchPurchase{value: totalValue}` one-transfer + `_batchPurchaseUnit{value: slice}` one-refund (G6), the GAS-03 `function batchPurchase(`/`amounts`/`modes` parallel-array signature, the G9 `if (msg.sender != ContractAddresses.AF_KING) revert E();` keeper gate.
- **Reframes (renamed/relocated, NOT removed — kept):** RouterWorstCaseGas's buy/open legs → the STAGE-50 ceiling + the mintBurnie open leg; KeeperLeversAndPacking's GAS-02 read-once/one-reward → `mintBurnie`'s `_mintPriceInContext()` + the single CEI-last bounty + the one-category early-return; G9 auth → the `operatorApprovals` consent gate; G10 swap-pop → `_removeFromSet`; G11 → the STAGE same-day idempotency; SweepPerPlayer's per-player sweep → the per-sub STAGE marginal.
- **No removed-surface gas test lacks a successor unrecorded:** every dropped Router test maps to a reframed STAGE/open/router test; the KeeperLeversAndPacking drops are removed surfaces asserted ABSENT.

## Sibling Files NOT Compile-Verified Here (Wave-3 charge)

The only still-unadapted gas sibling is `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` (the per-open marginal donor, owned by **351-08**). In the whole-`test/gas` run it FAILS 3 tests on its STALE `lootboxEthBase` slot (22, now 23 in v55) — its re-derivation + reframe onto the afking open is 351-08's charge, NOT this plan's. My 4 files pass 18/18 with `KeeperOpenBoxWorstCaseGas` skipped (`--no-match-contract KeeperOpenBoxWorstCaseGas`). The whole-tree compile + full run is Wave 3 (351-09)'s charge.

## Issues Encountered

- **No pretest patch hook** — `patchForFoundry.js` is not auto-invoked. Each isolation run requires `node scripts/lib/patchForFoundry.js` first (predict the CREATE addresses), then `git checkout -- contracts/ContractAddresses.sol` to restore it byte-identical (keeping `contracts/` frozen).
- **The idle-fixture day saturation + the level-0 liveness timeout** (the 351-02/03/05 reality) — a second linear new-day STAGE measurement in one test trips `RngNotReady`; measure two shapes via `vm.snapshotState`/`revertToState` from one clean baseline, and use the single-fixture whole/N marginal (not a two-near-N difference).
- **`game.autoOpen(uint256)` is the HUMAN box path, not afking** — a real foot-gun; the afking open is `mintBurnie()`-only.

## User Setup Required

None.

## Self-Check: PASSED

Created/modified files exist:
- FOUND: `test/gas/RouterWorstCaseGas.t.sol`
- FOUND: `test/gas/KeeperLeversAndPacking.t.sol`
- FOUND: `test/gas/KeeperResolveBetWorstCaseGas.t.sol`
- FOUND: `test/gas/SweepPerPlayerWorstCaseGas.t.sol`
- FOUND: `.planning/phases/351-.../351-07-SUMMARY.md`

Task commits exist:
- FOUND: `e334a91a` (Task 1 — RouterWorstCaseGas)
- FOUND: `6c69e627` (Task 2 — KeeperLeversAndPacking + KeeperResolveBetWorstCaseGas)
- FOUND: `24e856ee` (Task 3 — SweepPerPlayerWorstCaseGas)

Scope guard: `git diff --name-only 453f8073 HEAD -- contracts/` = EMPTY (committed AND working-tree); the 4 files 18/18 green in isolation; `grep -c "16_700_000" RouterWorstCaseGas.t.sol` >= 1; the STAGE-50 + open leg each assert < 16_700_000; non-comment `afKing.`/`doWork()` count == 0 in RouterWorstCaseGas + SweepPerPlayer; `vm.readFile("contracts/AfKing.sol")` count == 0 in KeeperLeversAndPacking (AFKING_SRC repointed); the packed-Sub layout asserts 29 bytes (re-derived game-resident); KeeperResolveBetWorstCaseGas has 0 afKing./doWork() refs; the 7 dropped Router tests + the KeeperLeversAndPacking batchPurchase gates recorded BY NAME for 351-09.

---
*Phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat*
*Completed: 2026-05-31*
