---
phase: 319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas
plan: 05
subsystem: testing
tags: [foundry, gas-calibration, crank, reward-peg, faucet-floor, REW-03, SAFE-01]

# Dependency graph
requires:
  - phase: 319-02
    provides: per-1-spin-item resolve marginal (66,528 gas) + per-box marginal (137,944 gas) — the two calibration inputs
  - phase: 319-03
    provides: per-successful-player sweep marginal (309,007 gas) — the BOUNTY_ETH_TARGET faucet-ceiling input
  - phase: 319-04
    provides: GAS-05 verdict + the SCAV-319-01 GAS-02 hoist disposition (ship-iff-real-saving)
provides:
  - GAS-06 calibration CLOSED — the two CRANK_*_GAS_UNITS reward-peg constants are recalibrated from the measured per-item marginals (resolve 120_000->66_528, box 120_000->137_944)
  - the four CrankFaucetResistance/CrankNonBrick/CrankLeversAndPacking/RngFreezeAndRemovalProofs test mirrors synced in the same batched diff
  - placement +0% re-verified after the edit (zero .gas-snapshot row delta; zero forge snapshot --check Diff line)
  - the SAFE-01 self-crank round-trip <= 0 faucet floor preserved at both new values (= 0 at the 0.5 gwei reference, < 0 at every market price >= 1 gwei)
  - the BOUNTY_ETH_TARGET production deploy note (degenerus-utilities repo) for the AfKing keeper
affects: [320-AUDIT-terminal, 319.1-OPEN-E, degenerus-utilities-keeper-deploy]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Reward-peg constants are FIXED compile-time constants pegged to the measured per-item MARGINAL (never the worst case, never gasleft()/tx.gasprice) — REW-03 + A4 + SAFE-01"
    - "Any contract-constant edit syncs ALL test mirrors that declare it in the SAME batched diff (four mirrors here, three of them live in peg-equality assertEqs)"

key-files:
  created:
    - .planning/phases/319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas/319-05-SUMMARY.md
  modified:
    - contracts/DegenerusGame.sol
    - test/fuzz/CrankFaucetResistance.t.sol
    - test/fuzz/CrankNonBrick.t.sol
    - test/gas/CrankLeversAndPacking.t.sol
    - test/fuzz/RngFreezeAndRemovalProofs.t.sol

key-decisions:
  - "OUTCOME B (USER-APPROVED): both *_GAS_UNITS constants edited to their exact measured marginal — resolve 66_528 (down: tightens the reference-price faucet floor + REW-03 accuracy), box 137_944 (up: REW-03 accuracy, still <= marginal)"
  - "CRANK_GAS_PRICE_REF (:1495, 0.5 gwei) left UNTOUCHED — FINAL/locked"
  - "GAS-02 hoist (SCAV-319-01) dropped as a NO-OP — the optimizer (viaIR, runs=200) already does the CSE; zero measured runtime saving"
  - "BOUNTY_ETH_TARGET (DeployProtocol.sol:126 arg2 = 885_000_000) left AS-IS per USER — it is a test fixture, ~177,000x below the sweep faucet floor (under-incentivizes, no faucet risk); production target is an economic choice owned by the paired degenerus-utilities keeper deploy"

patterns-established:
  - "Faucet-floor calibration: peg = measured marginal; round-trip = 0 at the 0.5 gwei reference, < 0 at any realistic >= 1 gwei market price (SAFE-01 hard floor preserved by construction at equality)"

requirements-completed: [GAS-06]

# Metrics
duration: ~16min
completed: 2026-05-24
---

# Phase 319 Plan 05: GAS-06 Peg Calibration Summary

**Recalibrated the two crank reward-peg gas-unit constants to their exact measured per-item marginals (resolve 120_000->66_528, box 120_000->137_944) behind the USER-approved frozen-contract gate, synced all four test mirrors in the same batched diff, and re-verified placement +0% with the SAFE-01 self-crank faucet floor preserved.**

## Performance

- **Duration:** ~16 min (Task 3 only; this is a continuation agent — Task 1 calibration `e7775d6e` and the Task 2 blocking-human gate were already complete)
- **Started:** 2026-05-24T08:53Z (continuation spawn)
- **Completed:** 2026-05-24T09:10Z
- **Tasks:** 1 (Task 3 — apply + sync + verify; Tasks 1-2 done in prior agents)
- **Files modified:** 5 (1 frozen contract + 4 test mirrors)

## Accomplishments
- Applied the USER-APPROVED OUTCOME-B calibration: `DegenerusGame.sol:1501` `CRANK_RESOLVE_BET_GAS_UNITS` `120_000`→`66_528`, `:1502` `CRANK_OPEN_BOX_GAS_UNITS` `120_000`→`137_944` (`:1495` `CRANK_GAS_PRICE_REF` 0.5 gwei UNTOUCHED).
- Synced all four test mirrors (`CrankFaucetResistance.t.sol:74-75`, `CrankNonBrick.t.sol:72-73`, `CrankLeversAndPacking.t.sol:69-70`, `RngFreezeAndRemovalProofs.t.sol:59-60`) in the SAME batched diff — three carry live peg-equality `assertEq`s.
- `CrankFaucetResistance` GREEN 10/10 — the SAFE-01 round-trip ≤ 0 (`testSelfCrankRoundTripNonPositive` + `testFuzz_RoundTripNonPositiveAcrossGasPrices` @ 1000 runs) and the peg-equality assertions hold with the new mirror values.
- Plan-02/03 gas harnesses GREEN 13/13 (`CrankResolveBetWorstCaseGas` 2/2, `CrankOpenBoxWorstCaseGas` 1/1, `SweepPerPlayerWorstCaseGas` 3/3, `CrankLeversAndPacking` 7/7).
- Placement +0% re-verified two ways: `forge snapshot --check` produced ZERO `Diff in` lines (the exit-1 is driven solely by the unrelated pre-existing baseline test failures), and `forge snapshot` regeneration left `.gas-snapshot` byte-identical (no row delta).
- Full suite: **556 passed / 44 failed** — EXACTLY the v45 baseline; zero NEW failures. The 44-fail set is the documented pre-existing baseline (QueueDoubleBuffer / RngGuard-routing / FreezeLifecycle / MidDaySwap / Degenerette-freeze arithmetic-underflow + replayed WhaleSybil/VaultShareMath/EthSolvency invariants). No crank/faucet/placement test is in the set.

## Task Commits

1. **Task 1: GAS-06 placement +0% verification + calibration decision** — `e7775d6e` (docs, prior agent; produced `319-GAS-06-CALIBRATION.md`, no contract touched)
2. **Task 2: USER-APPROVED contract gate (blocking-human)** — checkpoint, no commit; USER approved the OUTCOME-B batched diff
3. **Task 3: apply + sync + verify** — `e4014f91` (feat — batched contract + 4 test mirrors, landed via `CONTRACTS_COMMIT_APPROVED=1`)

**Plan metadata:** this SUMMARY + STATE/ROADMAP/REQUIREMENTS (docs)

## Files Created/Modified
- `contracts/DegenerusGame.sol` — `:1501-1502` the two `CRANK_*_GAS_UNITS` reward-peg constants recalibrated to `66_528` / `137_944` (the ONLY frozen-contract mutation; `:1495` `CRANK_GAS_PRICE_REF` untouched)
- `test/fuzz/CrankFaucetResistance.t.sol` — `:74-75` mirror synced (drives the SAFE-01 round-trip ≤ 0 + peg-equality `:177-182`)
- `test/fuzz/CrankNonBrick.t.sol` — `:72-73` mirror synced (`2 * GAS_UNITS * PRICE_REF` peg assertions)
- `test/gas/CrankLeversAndPacking.t.sol` — `:69-70` mirror synced (`3 * GAS_UNITS * PRICE_REF` peg assertions)
- `test/fuzz/RngFreezeAndRemovalProofs.t.sol` — `:59-60` mirror synced (declared-not-consumed; synced for consistency)

## Decisions Made
- **OUTCOME B both constants (USER-APPROVED):** peg each constant to its exact measured marginal. Resolve moves DOWN `120_000`→`66_528` (the `120_000` placeholder over-reimbursed the `66,528` marginal by 1.80× at the 0.5 gwei reference — closing that tightens the faucet floor AND improves REW-03 accuracy). Box moves UP `120_000`→`137_944` (the placeholder under-reimbursed by ~13%; raising to the marginal is a pure accuracy refinement, still ≤ marginal). At equality the round-trip is = 0 at the 0.5 gwei reference and strictly < 0 at every realistic ≥ 1 gwei market price — SAFE-01 preserved by construction.
- **`CRANK_GAS_PRICE_REF` (:1495) untouched** — 0.5 gwei is FINAL/locked.
- **GAS-02 hoist (SCAV-319-01) dropped** — NO-OP; the viaIR/runs=200 optimizer already hoists the loop-invariant pure recomputation, so the source edit yields zero measured runtime saving. Not in the diff.
- **`.gas-snapshot` not re-committed** — regeneration produced no change. The reward-peg constants are consumed only in the RESOLVE reward-credit path (`crankBets:1568`/`crankBoxes:1622`); they do not alter any recorded snapshot row's gas (the credit operation's gas cost is independent of the numeric reward value). This is the third independent confirmation of placement +0%.

## Deviations from Plan
None - plan executed exactly as the USER-approved decision specified. The plan anticipated the four-mirror sync (CALIBRATION §6), the GAS-02 no-op drop (§5), and the no-DeployProtocol-change posture (§4); all were applied verbatim.

## BOUNTY_ETH_TARGET production deploy note (USER decision: leave the fixture AS-IS)
Per the USER decision, `DeployProtocol.sol:126` arg2 (`_bountyEthTarget = 885_000_000` wei) is LEFT AS-IS — no edit. Recorded for the production AfKing deploy (paired `degenerus-utilities` repo, NOT this repo):
- The keeper bounty `885,000,000` wei is **~177,000× BELOW** the sweep faucet floor. Even at the SUB-03 6× stall peak (`5,310,000,000` wei) it is ~58,000× below the keeper's ≥1 gwei market gas cost for the `309,007`-gas per-player sweep. It **under-incentivizes** the keeper (no third party recovers its gas) and is **NOT a faucet risk**.
- **Production round-trip-≤0 ceiling (hard faucet floor):** `BOUNTY_ETH_TARGET ≤ 51,501,166,666,666` wei (the 6×-stall, ≥1 gwei-market bound: `309,007 · 1 gwei / 6`). The production keeper target is an economic choice (it should at least cover the keeper's market gas to incentivize the sweep) bounded above by this ceiling — set it in the `degenerus-utilities` deploy, not here.

## Issues Encountered
- `forge snapshot --check` exits 1, which initially looks like a placement regression. Resolved by isolating the signal: zero `Diff in` lines means zero recorded-row gas delta; the exit-1 is driven entirely by the unrelated pre-existing baseline test FAILURES (the same 44 the suite reports). Cross-checked with a clean `forge snapshot` regeneration → `.gas-snapshot` byte-identical → placement definitively +0%.

## Verification Summary
| Check | Result |
|-------|--------|
| Diff scope | ONLY `DegenerusGame.sol:1501-1502` in contracts/; `:1495` untouched; 4 test mirrors synced; `ContractAddresses.sol` + `DeployProtocol.sol` clean |
| `CrankFaucetResistance` | GREEN 10/10 (SAFE-01 round-trip ≤ 0 + peg-equality hold) |
| Plan-02/03 gas harnesses | GREEN 13/13 |
| Placement +0% | CONFIRMED (zero `forge snapshot --check Diff in` line; zero `.gas-snapshot` row delta) |
| Full suite | 556 pass / 44 fail = EXACT v45 baseline; zero NEW failures |
| Faucet floor (SAFE-01) | PRESERVED — round-trip = 0 @ 0.5 gwei ref, < 0 @ every market price ≥ 1 gwei |
| `ContractAddresses.sol` | CLEAN |
| Post-commit deletion check | none |

## Next Phase Readiness
- GAS-06 CLOSED; Phase 319 GAS deliverables complete (placement +0% bound + the calibrated reward-peg constants + the synced mirrors + the production bounty note).
- Phase 319 was the LAST gas plan; next in the v46.0 milestone is Phase 319.1 (OPEN-E shared funding source, a separate batched USER-APPROVED `AfKing.sol` IMPL) then Phase 320 TERMINAL (adversarial sweep + delta audit + closure).
- The two recalibrated constants are part of the v46.0 batched contract subject — the Phase 320 delta audit re-attests them.

## Self-Check: PASSED
- `319-05-SUMMARY.md` exists.
- Contract commit `e4014f91` exists in history.
- `DegenerusGame.sol:1501-1502` = `66_528` / `137_944`; `:1495` `CRANK_GAS_PRICE_REF` = `0.5 gwei` (untouched).

---
*Phase: 319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas*
*Completed: 2026-05-24*
