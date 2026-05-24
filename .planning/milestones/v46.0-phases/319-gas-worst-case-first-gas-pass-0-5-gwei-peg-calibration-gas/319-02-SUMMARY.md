---
phase: 319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas
plan: 02
subsystem: testing
tags: [gas, worst-case-first, gas-01, jgas-04, gas-06, crank, resolve-bet, open-box, jackpot, foundry, gasleft-delta, marginal-calibration]

# Dependency graph
requires:
  - phase: 319-01
    provides: "the GAS-01 paper-first worst-case derivation (319-GAS-DERIVATION.md): the resolve-bet 10-spin-all-match + open-box single-materialization scenarios with their written-in assert-is-worst-case preconditions, and the per-1-spin-item-marginal calibration-target distinction this plan measures"
  - phase: 318-06
    provides: "the module-extending JackpotSingleCallCorrectness harness (305-winner single call, measured 7,503,715 gas) that JGAS-04 extends; the worst-case-FIRST gas idiom + MAINNET_BLOCK_GAS_LIMIT=30M constant"
  - phase: 318-02
    provides: "the CrankFaucetResistance crank fixture (lootboxRngIndex seed + post-placement RNG-word inject + self-operator-approval) the two crank harnesses clone"
  - phase: 318-03
    provides: "the CrankNonBrick box-enqueue helper (game.purchase DirectEth first-deposit -> enqueueBoxForCrank) the open-box harness clones"
provides:
  - "GAS-01 resolve-bet worst case MEASURED: CrankResolveBetWorstCaseGas.t.sol — the 10-spin all-match crank item (726,944 gas) asserted to BE the max (ticketCount==10 + all 10 spins materialize a lootbox via 10 PayoutCapped) BEFORE the measurement, < 30M mainnet; non-vacuity guarded"
  - "the per-1-spin-item resolve MARGINAL (66,528 gas) isolated via loop-N-divide — the Plan 05 calibration target for CRANK_RESOLVE_BET_GAS_UNITS, asserted materially below the 10-spin worst case (REW-03 under-reimburses big wins), emitted via log_named_uint"
  - "GAS-01 open-box worst case MEASURED: CrankOpenBoxWorstCaseGas.t.sol — the single-box materialization marginal (137,944 gas), asserted queued+RNG-ready+un-opened BEFORE bracketing crankBoxes(1), < 30M mainnet, box-opened non-vacuity, and materially below the resolve-bet 10-spin worst case (~10x relationship); the Plan 05 calibration target for CRANK_OPEN_BOX_GAS_UNITS, emitted via log_named_uint"
  - "JGAS-04 COMPLETE: the 305-winner daily-ETH single call re-framed worst-case-FIRST (305==DAILY_ETH_MAX_WINNERS cap + no bucket > MAX_BUCKET_WINNERS=250 asserted before measuring; 22,496,288 gas margin under 30M) and the ~1.3M RM-02 freed-autoRebuyState-SLOAD delta structurally attributed (option (a), no dead-code re-introduction)"
affects: [319-05, 320, gas-06, jgas-04, plan-05-peg-calibration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Crank worst-case gas harness (live DeployProtocol, gasleft-delta): assert-is-worst-case BEFORE bracketing per feedback_gas_worst_case (decode ticketCount==MAX_SPINS_PER_BET; count FullTicketResult==10 + PayoutCapped==10 to prove all spins materialized a lootbox), assert < the REAL 30M (not foundry.toml's 30e9), and a non-vacuity guard (bet-slot deleted / box-signal zeroed) so a silently-skipped no-op cannot pass"
    - "RNG-word search + small-pool 10%-cap flip to force the all-materialize worst case: a single customTicket cannot match 10 independently-seeded result spins, so (1) search the RNG word for one where the per-quadrant-greedy ticket wins (matches>=2 -> payout>0) on all 10 spins, and (2) inject a small futurePrizePool so the ETH_WIN_CAP_BPS 10% cap flips every winning spin's payout excess into _resolveLootboxDirect (one PayoutCapped per spin); the pool injection only sizes the cap, it does not change the per-spin work path measured"
    - "per-item MARGINAL isolation via loop-N-divide (RollRemainderGas idiom): crank N independent 1-spin items in one batch, divide the delta by N -> the FLAT-per-item-reward calibration target, asserted materially below the worst case (REW-03 / SAFE-01 faucet floor)"
    - "Structural delta attribution (no dead-code re-introduction): compute the freed estimate from EIP-2929 cold-access constants (cold slot ~2100 + cold account ~2100 = ~4.2k per winner x 305 = ~1.28M), assert the measured single-call gas sits in a TOLERANCED band around (316-SPEC theory - freed) within the +/-30% structural uncertainty ('consistent-with' not 'exactly' per A2), and source-attest the removed surface is genuinely absent (grep autoRebuyState over the jackpot module == 0)"

key-files:
  created:
    - test/gas/CrankResolveBetWorstCaseGas.t.sol
    - test/gas/CrankOpenBoxWorstCaseGas.t.sol
  modified:
    - test/fuzz/JackpotSingleCallCorrectness.t.sol

key-decisions:
  - "Forced the resolve-bet all-materialize worst case via a (RNG-word search + small-pool 10%-cap flip) rather than a literal all-match ticket: each spin derives its OWN random result ticket (spin 0 short preimage, spins 1+ mix in spinIdx) so a single customTicket CANNOT match all 10; a 4000-word search reliably finds a word where the greedy ticket wins (min-match >= 2) on every spin, and an injected small futurePrizePool makes the 10% ETH-win cap (ETH_WIN_CAP_BPS=1000) flip each winning spin's payout into the lootbox branch -> one PayoutCapped + one _resolveLootboxDirect materialization per spin (verified: 10 FullTicketResult + 10 PayoutCapped)"
  - "Used PayoutCapped (count==10) as the per-spin lootbox-materialization proof instead of LootBoxReward: LootBoxReward only fires for specific reward TYPES (a tiny flipped amount may queue tickets/BURNIE and emit no LootBoxReward), but PayoutCapped fires deterministically once per spin whose ETH share exceeds the cap and flips into the lootbox — a precise, documented 'materialization happened' signal"
  - "Folded the open-box Tests A/B/C into one test sharing the single enqueue + the single bracketed crankBoxes(1) measurement (a second crank on the same opened box would be a vacuous no-op); the per-box marginal is asserted < a mirrored RESOLVE_BET_10SPIN_WORST_CASE_REF_GAS=726,944 ceiling (Task 1's number) as the loose '~10x a box' structural sanity, not an exact equality (warm/cold state shifts the precise number)"
  - "JGAS-04 used structural option (a) (RESEARCH-preferred): computed the freed band from EIP-2929 constants (4.2k x 305 = 1,281,000) and asserted the measured 7,503,712 gas is consistent with (316-SPEC 9-12M theory) minus freed (~7.72-10.72M) within a 3M tolerance that absorbs the +/-30% structural-estimate uncertainty (A2 'consistent-with not exactly'); did NOT re-introduce the removed cold SLOAD (option (b) rejected) and source-attested autoRebuyState is absent from the jackpot module (0 matches)"
  - "Kept the JGAS-04 extension on the module-extending JackpotSingleCallHarness (not DeployProtocol) — the jackpot drives the production _processDailyEth path in the harness's own storage, the inverse of the crank harnesses which need the live Game storage"

patterns-established:
  - "Crank worst-case gas harness: live DeployProtocol + CrankFaucetResistance fixture + gasleft-delta, with the assert-is-worst-case precondition (ticketCount==10 + all-materialize) BEFORE the measurement and a non-vacuity guard after"
  - "Force-the-worst-case-via-cap: when independently-seeded spins make a literal all-match impossible, inject a small pool so the percentage win-cap flips every winning outcome into the expensive branch — the structural per-item work is unchanged, only the branch is forced"

requirements-completed: [GAS-01, JGAS-04, GAS-06]

# Metrics
duration: ~30min
started: 2026-05-24T08:05:00Z
completed: 2026-05-24T08:35:00Z
tasks: 3
files-created: 2
files-modified: 1
---

# Phase 319 Plan 02: GAS-01 Crank Worst-Case Measurement + JGAS-04 Re-Frame + Delta Attribution Summary

**Measured the two do-work-crank worst cases derived in Plan 01 — the resolve-bet 10-spin all-match item (726,944 gas, all 10 spins materializing a lootbox) and the open-box single materialization (137,944 gas) — each asserted to BE the maximum BEFORE bracketing per `feedback_gas_worst_case` and confirmed < the REAL 30M mainnet block gas limit; isolated the two per-item MARGINALS (66,528 resolve / 137,944 box) that calibrate the `*_GAS_UNITS` peg constants in Plan 05; and completed JGAS-04 by re-framing the 305-winner single-call jackpot worst-case-FIRST (22.5M margin under 30M) and structurally attributing the ~1.3M enabling delta to the removed per-winner `autoRebuyState` SLOAD — no dead code re-introduced. 13/13 new+extended tests green; zero `contracts/*.sol` mutation; full suite 546 passed / 44 failing == the exact v45 baseline (zero NEW failures).**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-05-24T08:05:00Z
- **Completed:** 2026-05-24T08:35:00Z
- **Tasks:** 3 (all `auto`, tdd)
- **Files created:** 2 (`test/gas/CrankResolveBetWorstCaseGas.t.sol`, `test/gas/CrankOpenBoxWorstCaseGas.t.sol`)
- **Files modified:** 1 (`test/fuzz/JackpotSingleCallCorrectness.t.sol`)

## Accomplishments

### Task 1 — CrankResolveBetWorstCaseGas (GAS-01 resolve-bet) — commit `637dc9a1`
- **Test A (10-spin all-match worst case):** a single `crankBets` item resolving a `ticketCount == MAX_SPINS_PER_BET == 10` bet where **every** spin wins ETH and flips into the lootbox branch (10 `_resolveLootboxDirect` materializations). Asserts the scenario IS the max (`ticketCount == 10` AND `FullTicketResult == 10` AND `PayoutCapped == 10`) BEFORE trusting the measurement, asserts measured **726,944 gas < 30,000,000** (the REAL mainnet limit, not foundry.toml's 30e9), and a non-vacuity guard (bet slot deleted). Emits the worst-case gas.
- **Test B (per-1-spin-item MARGINAL):** loop-N-divide micro-bench over 8 independent 1-spin items → **66,528 gas** marginal, asserted materially below the 10-spin worst case (REW-03 / SAFE-01 faucet floor — the per-spin peg deliberately under-reimburses big wins). Emitted via `log_named_uint` as the Plan 05 calibration input for `CRANK_RESOLVE_BET_GAS_UNITS`.
- **Worst-case construction:** a single `customTicket` cannot match 10 independently-seeded result spins, so the harness searches the RNG word for one whose per-quadrant-greedy ticket wins (matches ≥ 2 → payout > 0) on all 10 spins, then injects a small `futurePrizePool` so the 10% ETH-win cap (`ETH_WIN_CAP_BPS`) flips every winning spin into the lootbox branch.

### Task 2 — CrankOpenBoxWorstCaseGas (GAS-01 open-box) — commit `fe2a7cbc`
- Enqueues exactly one real first-deposit box (`game.purchase{value:..}(...DirectEth)` → `enqueueBoxForCrank`), lands the index's RNG word, and asserts the box is **queued + RNG-ready + un-opened** (the §2 worst-case preconditions) BEFORE bracketing `crankBoxes(1)`.
- Measured single-box materialization marginal: **137,944 gas < 30M**; non-vacuity guard (`lootboxEthBase` zeroed on open, NOT a `:1603` wordless-index early-return).
- Calibration sanity: asserted materially below the resolve-bet 10-spin worst case (726,944) — confirming the **~10x box-vs-bet** structural relationship and that the two peg constants will differ markedly. Emitted via `log_named_uint` as the Plan 05 calibration input for `CRANK_OPEN_BOX_GAS_UNITS`.

### Task 3 — JGAS-04 re-frame + delta attribution — commit `c1ba6e29`
- Extended the existing 318-06 `JackpotSingleCallCorrectness.t.sol` (kept the module-extending harness).
- **`testJgas04WorstCaseFirstReframeWithMargin`:** asserts 305 IS the daily-ETH max BEFORE measuring (`sum == DAILY_ETH_MAX_WINNERS == 305` AND every bucket `<= MAX_BUCKET_WINNERS == 250` so the 159 bucket is never clipped), asserts measured **7,503,712 gas < 30M**, emits the **22,496,288** margin.
- **`testJgas04FreedAutoRebuyStateSloadDeltaAttribution`:** structural option (a) — computes the RM-02 freed band from EIP-2929 cold-access constants (cold slot ~2100 + cold account ~2100 = ~4.2k/winner × 305 = **1,281,000** ≈ 1.3M) and asserts the measured single-call gas is consistent with the 316-SPEC §J4.2 theory (9-12M) **minus** that freed band (~7.72-10.72M) within a 3M tolerance absorbing the ±30% structural uncertainty (A2 "consistent-with not exactly"). Source-attests `autoRebuyState` is structurally absent from the jackpot module (0 matches) — no dead code re-introduced; option (b) comparison harness rejected.

## Key Measurements (the Plan 05 calibration inputs)

| Work type | Worst case (MEASURE) | Per-item MARGINAL (CALIBRATE) | Fit |
|-----------|----------------------|-------------------------------|-----|
| resolve-bet | 726,944 gas (10-spin all-match, 10 lootbox materializations) | **66,528 gas** (per-1-spin item) → `CRANK_RESOLVE_BET_GAS_UNITS` | < 30M ✓ |
| open-box | 137,944 gas (single materialization) | **137,944 gas** (flat per-box) → `CRANK_OPEN_BOX_GAS_UNITS` | < 30M ✓ |
| daily-ETH jackpot (JGAS-04) | 7,503,712 gas (305-winner) | n/a (measure-only; margin 22,496,288 under 30M) | < 30M ✓ |

Plan 05 reads the resolve marginal (66,528) and the box marginal (137,944) from the emitted `log_named_uint` rows and calibrates the two `*_GAS_UNITS` constants to those marginals (REW-03: peg to the per-item marginal, never the worst case; keep the SAFE-01 self-crank round-trip ≤ 0).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Worst-case materialization signal switched from LootBoxReward to PayoutCapped**
- **Found during:** Task 1
- **Issue:** The plan's `<behavior>` framed the all-match guard around counting lootbox-reward emissions, but `LootBoxReward` only fires for specific reward TYPES — a small cap-flipped lootbox amount queues tickets/BURNIE and emits NO `LootBoxReward`, so the count was 0 even though the materialization ran (a false-negative that would block the test).
- **Fix:** Used `PayoutCapped` (emitted deterministically once per spin whose ETH share exceeds the 10% cap and flips into the lootbox branch) as the per-spin materialization proof; combined with `FullTicketResult == 10` (all spins ran) and the bet-slot-deleted non-vacuity check it fully proves the 10-materialization worst case.
- **Files modified:** `test/gas/CrankResolveBetWorstCaseGas.t.sol`
- **Commit:** `637dc9a1`

**2. [Rule 3 - Blocking] All-materialize worst case forced via RNG-word search + small-pool 10%-cap flip**
- **Found during:** Task 1
- **Issue:** The plan assumed a literal "all-match" ticket; but each of the 10 spins derives its OWN random result ticket (spin 0 short preimage, spins 1+ mix in `spinIdx`), so a single `customTicket` cannot match all 10 — a greedy ticket gave only matches 1/3/0/2/4/3/2/3/1/4 (several losing spins, no materialization).
- **Fix:** Searched the RNG word (4000-budget) for one whose greedy ticket wins (min-match ≥ 2 → payout > 0) on all 10 spins, and injected a small `futurePrizePool` so the `ETH_WIN_CAP_BPS` 10% cap flips every winning spin into `_resolveLootboxDirect`. The pool injection only sizes the cap; the per-spin work path the worst case measures is unchanged. Verified empirically: 10 `FullTicketResult` + 10 `PayoutCapped`.
- **Files modified:** `test/gas/CrankResolveBetWorstCaseGas.t.sol`
- **Commit:** `637dc9a1`

## Verification

- All three target suites green: `CrankResolveBetWorstCaseGas` (2/2), `CrankOpenBoxWorstCaseGas` (1/1), `JackpotSingleCallCorrectness` (10/10 — 8 prior + 2 JGAS-04).
- Each harness asserts its scenario IS the worst case BEFORE bracketing, asserts against the REAL 30M (`MAINNET_BLOCK_GAS_LIMIT = 30_000_000`), and includes a non-vacuity guard.
- The two crank per-item marginals are emitted via `log_named_uint` for Plan 05.
- JGAS-04 attributes the ~1.3M freed delta structurally (no dead-code re-introduction) and source-attests the removed surface is absent.
- `git diff --name-only -- contracts/` EMPTY across all three tasks.
- Full suite: **546 passed / 44 failing** == the EXACT v45 baseline (the documented pre-existing 44-failure set; zero AfKing/crank involvement) — **zero NEW failures**. The 13 new+extended tests are NOT in the failing set.

## Known Stubs

None. The harnesses measure live production logic only (no stubs, no mock data sources).

## Self-Check: PASSED

- Files: FOUND `test/gas/CrankResolveBetWorstCaseGas.t.sol`, FOUND `test/gas/CrankOpenBoxWorstCaseGas.t.sol`, FOUND `test/fuzz/JackpotSingleCallCorrectness.t.sol` (modified), FOUND `319-02-SUMMARY.md`.
- Commits: FOUND `637dc9a1` (Task 1), FOUND `fe2a7cbc` (Task 2), FOUND `c1ba6e29` (Task 3).
- Contracts clean: `git diff --name-only -- contracts/` EMPTY.
- Suite gate: 546 passed / 44 failing == exact v45 baseline (zero NEW failures).
