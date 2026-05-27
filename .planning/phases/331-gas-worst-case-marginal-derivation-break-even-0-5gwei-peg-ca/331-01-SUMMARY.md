---
phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
plan: 01
subsystem: testing
tags: [gas, keeper-router, doWork, autoBuy, autoOpen, advanceGame, foundry, worst-case-marginal, CR-01]

# Dependency graph
requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the committed keeper-router diff 63bc16ca (doWork/_autoBuy/autoOpen/advanceGame) — the subject this harness measures"
  - phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
    provides: "the D-07 flat-per-tx model + ratios + OPEN_KNEE the marginals will calibrate"
provides:
  - "test/gas/RouterWorstCaseGas.t.sol — the GAS-01 router worst-case marginal harness (buy/open/advance/dispatch)"
  - "331-GAS-DERIVATION.md — theory-first per-category worst case + the measured marginals table"
  - "the four measured calibration inputs (buy 40,224 / open 89,287 / advance 210,689 / dispatch 228,084 gas) for 331-04"
affects: [331-04-peg-calibration, 331-05-contract-gate, 332-TST, 333-TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "gasleft()-bracket + loop-N-divide per-item marginal at N>=32 (the live *WorstCaseGas.t.sol idiom; NOT vm.snapshotGas)"
    - "assert-is-worst-case (cap) + non-vacuity (real work) + 30M mainnet bar + log_named_uint emission per test"
    - "route-through-doWork() advance measurement: park the buy cursor so doWork falls through to the advance leg"

key-files:
  created:
    - "test/gas/RouterWorstCaseGas.t.sol"
    - ".planning/phases/331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca/331-GAS-DERIVATION.md"
  modified: []

key-decisions:
  - "Buy-leg marginal measured via the standalone autoBuy(N) body (== the doWork buy leg's _autoBuy); doWork dispatch overhead measured separately as a conservative ceiling"
  - "Dispatch overhead emitted as the FULL doWork-with-minimal-buy-leg number (conservative ceiling, never under-stating the once-per-tx floor); 331-04 recovers the pure routing+creditFlip cost by subtracting the §1 single-player buy marginal"
  - "keeperSnapshot cost lives in the BUY-LEG per-player marginal (called inside _resolveBuy per buying sub), NOT the dispatch overhead — reconciled the PLAN §4 'keeperSnapshot mintPrice read' to the dispatch path's mintPrice() STATICCALL"
  - "Confirmed CR-01 empirically: buy gradient N1/N32 ~3.06x, open gradient ~2.10x — pegging to the single-item total would over-pay and open the Sybil faucet; calibrate from the N>=32 converged column"

patterns-established:
  - "Router-leg worst-case harness: one test per category, each emitting the 331-04 calibration input"
  - "CR-01 amortization-gradient test (N=1/8/32) as standing convergence evidence"

requirements-completed: [GAS-01]

# Metrics
duration: ~35min
completed: 2026-05-27
---

# Phase 331 Plan 01: Keeper-Router Worst-Case Marginal Gas Derivation + Measurement Summary

**Theory-first worst-case derivation for all four v49 keeper-router measurement targets, then a new `RouterWorstCaseGas.t.sol` harness measuring the per-item MARGINAL at N>=32 — buy 40,224 / open 89,287 gas per item, advance 210,689 / dispatch 228,084 gas per call — all under the 30M mainnet bar, emitted as the 331-04 break-even-peg calibration input.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-05-27 (Phase 331 execution start)
- **Completed:** 2026-05-27
- **Tasks:** 2
- **Files modified:** 2 (both created; zero `contracts/*.sol`)

## Accomplishments
- Authored `331-GAS-DERIVATION.md`: the theoretical worst case in WRITING FIRST for the buy leg, open leg, advance leg, and the `doWork()` dispatch overhead — each stating the cap it runs to (`DOWORK_BATCH=100` per leg; per-sub/per-box single-iteration max; single advance step) and WHY it is the maximum, plus the 0.5 gwei break-even target and the N>=32 CR-01 rule.
- Built `test/gas/RouterWorstCaseGas.t.sol` (6 tests, `--isolate`, all PASS): measured the four marginals via the established `gasleft()`-bracket + loop-N-divide idiom, each with an assert-is-worst-case (cap) assertion, a non-vacuity assertion (real work happened), a < 30M mainnet assertion, and a `log_named_uint` calibration emit.
- Recorded the CR-01 amortization gradient (buy N1=116,437→N32=37,986 ~3.06x; open N1=180,221→N32=85,967 ~2.10x), empirically re-confirming that the per-item peg MUST use the N>=32 converged marginal, never the single-item total.
- Re-attested every `vm.store`/`vm.load` slot constant via `forge inspect ... storage` against the live `63bc16ca` layout (the 330 diff put `boxCursor`/`boxCursorIndex` at slot 62 and `boxPlayers` at slot 63 — NOT the `:1548-1559` the PATTERNS comment guessed).

## Task Commits

Each task was committed atomically:

1. **Task 1: Derive the theoretical worst case per keeper category (writing-first)** — `739ee2af` (docs)
2. **Task 2: Build RouterWorstCaseGas.t.sol and measure the per-item marginals** — `acac8285` (test)

_Note: Task 2 is a measurement harness (the established gas-harness idiom); the assertions ARE the test. The derivation-doc back-fill rode in the Task 2 commit alongside the harness, since the measured numbers come from running it._

## Files Created/Modified
- `test/gas/RouterWorstCaseGas.t.sol` — GAS-01 router worst-case marginal harness; 6 tests measuring `doWork()` buy/open/advance legs + dispatch overhead, N>=32 per-item marginals + the CR-01 gradient.
- `.planning/phases/331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca/331-GAS-DERIVATION.md` — theory-first per-category derivation (§1-4), the measured-marginals table (§5), the slot attestation (§6), and the out-of-scope fence (§7).

## Measured Calibration Inputs (the 331-04 break-even-peg input)

| Calibration input | Measured gas | N | < 30M | Non-vacuity oracle |
|-------------------|--------------|---|-------|--------------------|
| `router_dowork_buy_per_player_marginal_gas` | 40,224 | 32 | yes (leg 1.29M) | each sub `lastAutoBoughtDay == today` |
| `router_dowork_open_per_box_marginal_gas` | 89,287 | 32 | yes (leg 2.86M) | each box first-deposit signal zeroed |
| `router_dowork_advance_marginal_gas` | 210,689 | 1 step | yes | game entered rngLock / day moved |
| `router_dowork_dispatch_overhead_gas` | 228,084 | 1 call | yes | doWork ran the buy leg (sub bought) |

## Decisions Made
- **Buy leg measured via standalone `autoBuy(N)`** — its body IS the `doWork` buy leg's `_autoBuy(DOWORK_BATCH)`; the standalone wrapper is unrewarded but gas-identical, giving a clean per-player marginal. Dispatch overhead measured separately through `doWork()`.
- **Dispatch overhead is a conservative ceiling** — `doWork()` with the cheapest non-reverting leg (one healthy buy + one `creditFlip`), so the emitted 228,084 over-states the pure routing+creditFlip cost (it folds in one real buy + the two standing deploy subs' fresh-day re-walk). This never under-states the once-per-tx floor (the safe direction for a break-even peg — under-stating would starve keepers). 331-04 recovers the pure overhead by subtracting the §1 single-player buy marginal.
- **`keeperSnapshot` cost is buy-leg, not dispatch** — it is called per buying subscriber inside `_resolveBuy` (`AfKing.sol:807`), so its cost is captured in the buy per-player marginal; the dispatch path's only GAME read is `mintPrice()` + the routing predicate views + the one `creditFlip`. The PLAN §4 "keeperSnapshot mintPrice read" reconciles to the dispatch `mintPrice()` STATICCALL (documented in 331-GAS-DERIVATION.md §4(a)).

## Deviations from Plan

None - plan executed exactly as written. Two small in-line reconciliations (not behavior deviations):
- The PLAN/PATTERNS doc described the `doWork()` routing priority as "advance → open → buy"; the actual committed `63bc16ca` dispatch order is **buy → advance → open** (`AfKing.sol:875-896`). The harness measures against the COMMITTED contract (the advance test parks the buy cursor so `doWork` falls through to advance). Documented in 331-GAS-DERIVATION.md §0/§3.
- The NatSpec `@0` token in an offset comment was parsed by solc as a doc tag (`Documentation tag @0`); rewrote `off0/off1/...` to compile. Test-file-only, no semantic change.

## Issues Encountered
- First `forge test` run failed compilation on the `@0`/`@1` packed-offset NatSpec being read as solc doc tags — fixed by rewording to `off0`/`off1`. Re-ran clean: 6/6 PASS under `--isolate`.

## User Setup Required
None - no external service configuration required. This plan is test + doc only; no `contracts/*.sol` touched and no constant landed (that is 331-04/05 under the second USER-approved gate).

## Next Phase Readiness
- The four measured marginals are recorded as the 331-04 calibration input. 331-04 sizes `BOUNTY_ETH_TARGET` (deploy-param) + the `BUY_RATIO`/`ADVANCE_RATIO`/`OPEN_KNEE` ratio constants from these numbers, peg AT-or-BELOW the marginal (the CR-01/faucet floor), under the SECOND USER-approved contract gate.
- **Contract-boundary HARD STOP reminder:** 331-04 lands `AfKing.sol`/`DegenerusGame.sol` constants and 331-05 is the `autonomous:false` USER-approval gate — those are NOT this plan and were not touched here.
- No blockers.

## Self-Check: PASSED

- `test/gas/RouterWorstCaseGas.t.sol` — FOUND
- `331-GAS-DERIVATION.md` — FOUND
- `331-01-SUMMARY.md` — FOUND
- Commit `739ee2af` (Task 1 docs) — FOUND
- Commit `acac8285` (Task 2 test) — FOUND
- `forge test --match-path test/gas/RouterWorstCaseGas.t.sol --isolate` — 6/6 PASS
- `git diff --name-only -- contracts/` for this plan's changes — EMPTY (no contract mutation)

---
*Phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca*
*Completed: 2026-05-27*
