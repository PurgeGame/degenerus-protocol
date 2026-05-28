---
phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-
plan: 03
subsystem: test-gas-keeper-open-box-uniform-o1
tags: [tst-01, d-tst01-04, whale-03, uniform-o1, gas-equivalence, foundry-gas]
dependency_graph:
  requires:
    - 335-07 (BATCH-02 IMPL HEAD `e756a6f3` — the O(1) `whalePassClaims[player] += 1` accumulator at LootboxModule:1253; the WHALE-01/03 contract surface this test re-attests)
    - 335-06 (D-IMPL-04 — the existing `KeeperOpenBoxWorstCaseGas.t.sol` harness reporting per-box marginal = 74_756; the OPEN_BATCH=200 picker that anchors the WHALE-03 acceptance)
    - 336-01 + 336-02 (closed TST-01 freeze leg + equivalence/grant-correctness oracle; this plan closes the uniform-O(1) gas-equivalence one-liner — the last TST-01 leg)
    - 334-CONTEXT.md D-21 + 334-WHALE04-FREEZE-PROOF.md (the WHALE-01..03 design context)
  provides:
    - TST-01 D-TST01-04 empirical uniform-O(1) attestation — autoOpen per-box gas independent of opener's whale-pass-claims state
    - WHALE-03 carve-out-retired empirical evidence (the 331 whale-pass-weighted autoOpen budget is mooted)
  affects:
    - 336-04 (TST-02 D-TST02-02 no-pass-SLOAD oracle in `AfKingSubscription.t.sol`)
    - 338 (TERMINAL — the FINDINGS-v50.0 deliverable cites this oracle as the WHALE-03 evidence)
tech_stack:
  added: []
  patterns:
    - Foundry `gasleft()` bracketing for per-call gas measurement (existing harness idiom at `testPerBoxMarginalAmortizesFixedOverhead:187-191`)
    - Direct storage forge via `vm.store` on `whalePassClaims` mapping (slot 21 root; mirrors 336-02's verified probe + the existing `_grantDeityPass` pattern at line 9)
    - Warm-up `autoOpen(1)` call before measurement to neutralize cross-call cold-warming asymmetry on the `autoOpen` machinery (the per-tx fixed overhead the harness docstring at lines 142-150 already calls out)
    - WIDE-tolerance equivalence assertion (~25_000 gas; cold-SSTORE worst-case bound per RESEARCH §A1) — empirically holds at delta = 4_636 gas after warm-up
key_files:
  created:
    - .planning/phases/336-tst-equivalence-freeze-safety-divergence-repro-non-widening-/336-03-SUMMARY.md
  modified:
    - test/gas/KeeperOpenBoxWorstCaseGas.t.sol
decisions:
  - 'D-TST01-04 honored: extended `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` IN PLACE per PATTERNS.md "EXTEND in place" recommendation — no new harness authored'
  - 'D-TST04-04 honored: zero `contracts/*.sol` mutation (`git diff e756a6f3 -- contracts/` empty)'
  - 'D-CC-01 honored: per-plan atomic commit for the test/ + SUMMARY.md changes'
  - 'D-CC-02 honored: sequential-on-main, no-worktrees'
  - 'D-CC-04 honored: no `git push` (push gate at v50.0 closure / Phase 338)'
  - 'Tolerance choice: WIDE (~25_000 gas) per RESEARCH §A1 + PLAN <action> step 2 alternative — covers the worst-case cold-SSTORE penalty if the BOON_WHALE_PASS branch fires (LootboxModule:1253 `+= 1` cold = ~22_100 gas). The empirically observed delta after warm-up is 4_636 gas, well within the bound. T-336-03-02 cap (≤25_000) honored.'
  - 'Warm-up call added (Rule 3 auto-fix during execution): first execution with two raw autoOpen(1) calls measured delta = 26_398 (> 25K threshold) due to per-call cold-warming asymmetry on the autoOpen machinery (the `boxCursor` / `coinflip` facade / active-ticket-level SLOAD cluster). Adding a third throwaway `warmupOpener` whose autoOpen(1) burns the cold reads first dropped the measured delta to 4_636 — the load-bearing equivalence quantity isolated from cross-call asymmetry. This is the intended isolation pattern (mirrors the harness docstring at lines 142-150 about per-tx fixed overhead). Documented inline in the new test.'
  - 'Pre-seeded `whalePassClaims[whaleOpener] = 3` via `vm.store` on slot 21 — the SECOND structural property of WHALE-03: even when the opener already has pending whale-pass claims (a non-zero accumulator state), the box-open gas does NOT depend on that state (the box-open path does NOT SLOAD whalePassClaims absent the boon branch). Reuses the slot-21 probe verified in 336-02 SUMMARY.'
  - 'Existing tests in the file (`testPerBoxMarginalAmortizesFixedOverhead`, `testWorstCaseOpenBoxSingleMaterializationFitsBlockGasLimit`) are byte-untouched — only the new test + closing-brace neighborhood inserted. Per-box marginal stays = 74_756 (335-06 figure unchanged).'
metrics:
  duration_minutes: ~15
  completed_at: 2026-05-28T13:15:00Z
  file_lines_added: ~115
  file_lines_removed: 0
  empirical_delta_gas: 4_636
  empirical_tolerance_gas: 25_000
  gas_whale_opener: 89_110
  gas_non_whale_opener: 93_746
requirements: [TST-01]
---

# Phase 336 Plan 03: TST-01 D-TST01-04 Uniform-O(1) Gas-Equivalence Summary

**WHALE-03 empirically attested: the worst-case per-box `autoOpen(1)` gas is independent of the opener's pre-existing whale-pass-claims state — the 331 whale-pass-weighted autoOpen carve-out is RETIRED. Measured delta = 4_636 gas / tolerance = 25_000 gas; passes within ~19% of the cold-SSTORE worst-case bound.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-05-28T13:00:00Z (approx.)
- **Completed:** 2026-05-28T13:15:00Z
- **Tasks:** 1/1 completed
- **Files modified:** 1 (test/gas/KeeperOpenBoxWorstCaseGas.t.sol)
- **Lines added:** ~115 (new test function + inline docstrings + insertion-point comment)
- **Lines removed:** 0

## Accomplishments

- **TST-01 D-TST01-04 oracle GREEN.** The new `testWhaleOpenerEqualsNonWhaleOpenerGas` test PASSES against the FROZEN v50.0 IMPL HEAD `e756a6f3` with empirical delta = 4_636 gas, well within the 25_000-gas cold-SSTORE bound.
- **WHALE-03 empirically attested.** Two distinct openers (one with pre-seeded `whalePassClaims = 3`, one with `whalePassClaims = 0`) drive `autoOpen(1)` against the same FIXED_WORD; the measured gas delta is 4_636 gas (≈5% of the per-call gas total ~90K) — confirming the box-open path is uniform O(1) regardless of the opener's pre-existing accumulator state.
- **335-06 OPEN_BATCH=200 picker preserved.** The existing `testPerBoxMarginalAmortizesFixedOverhead` still reports `per_box_marginal_gas: 74_756` — byte-identical to the 335-06 LOCAL-VERIFICATION figure. No regression on the WHALE-03 acceptance criterion.
- **Existing harness preserved.** `testWorstCaseOpenBoxSingleMaterializationFitsBlockGasLimit` still reports the same `worst_case_open_box_single_materialization_gas: 113_875`. The existing helpers (`_buyBox`, `_activeLootboxIndex`, `_injectLootboxRngWord`, `_lootboxRngWord`, `_lootboxEthBase`) are reused verbatim from the existing harness — zero new helpers introduced (only the slot-21 inline `keccak256(abi.encode(whaleOpener, uint256(21)))` for the `whalePassClaims` write, mirroring 336-02's verified probe).
- **NON-WIDENING preserved.** The full file `forge test --match-path test/gas/KeeperOpenBoxWorstCaseGas.t.sol` shows 3/3 PASS (2 pre-existing + 1 new). Zero new failures introduced.

## Task Commits

1. **Task 1: Add `testWhaleOpenerEqualsNonWhaleOpenerGas` — whale-vs-non-whale opener uniform-O(1) attestation** — committed atomically with this SUMMARY per D-CC-01 (`test(336-03): ...`).

## Files Modified

- `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` — appended:
  - 1 new test function `testWhaleOpenerEqualsNonWhaleOpenerGas` (the load-bearing D-TST01-04 oracle).
  - Inline natspec docstring documenting the tolerance choice (WIDE ~25_000 gas per RESEARCH §A1), the warm-up rationale, and the structural property under test (whale-pass-claims-state independence).
  - 4 new `emit log_named_uint` calls (`gas_whale_opener`, `gas_non_whale_opener`, `gas_delta`, `gas_tolerance`) for audit-trace numbers.

## Decisions Made

- **WIDE tolerance (~25_000 gas) over tight (~500):** Per RESEARCH §A1 + PLAN `<action>` step 2 alternative + PATTERNS.md lines 211-219, the wide bound is the durable choice that holds across future cold/warm state shifts. The tight 500-gas bound would require pre-warming BOTH openers' `whalePassClaims` slots AND would still face address-keyed cold/warm asymmetries on player-state slots (mintPacked_, ticketsOwedPacked, etc.) — a brittle pre-warm regime. The wide bound covers the worst-case cold SSTORE penalty if a future fixture toggles the BOON_WHALE_PASS branch firing. T-336-03-02's cap (≤25_000 gas) is honored.

- **Warm-up `autoOpen(1)` call added during execution (Rule 3 auto-fix):** First execution measured delta = 26_398 gas (`gNonWhale = 119_774`, `gWhale = 93_390`) — `> 25K` threshold by ~1.4K. Investigation via `forge test -vvvv` traced the asymmetry to per-tx fixed overhead the FIRST `autoOpen` call pays (cold-warming the `boxCursor` packed slot, the `coinflip` facade address, the active-ticket-level SLOAD, the `boxPlayers` walk) that the SECOND call benefits from. The harness docstring at lines 142-150 already calls this out as the "per-tx fixed overhead paid ONLY ONCE per call regardless of N" property of `autoOpen` — sequential single-box calls amplify the asymmetry. Adding a third `warmupOpener` whose `autoOpen(1)` burns the cold reads first dropped the measured delta to 4_636 gas (`gNonWhale = 93_746`, `gWhale = 89_110`) — the load-bearing equivalence quantity isolated from cross-call asymmetry. This is the intended isolation pattern, not a regression-masking maneuver: the warm-up exercises the IDENTICAL `autoOpen` code path the measurements use, just with a third opener whose box was queued in setup.

- **Pre-seeded `whalePassClaims[whaleOpener] = 3` via `vm.store`:** Establishes the SECOND structural property of WHALE-03 — gas independence from the opener's pre-existing accumulator state. Slot 21 is the verified `whalePassClaims` mapping root (DegenerusGame storage layout; cross-checked against 336-02 SUMMARY which independently derived it). The whale opener's box-open does NOT SLOAD `whalePassClaims` (the slot is read only inside the rare BOON_WHALE_PASS branch at LootboxModule:1628-1629 → 1253 `+= 1`); the pre-seeding is a witness that the path is invariant to that state.

- **Inline slot computation vs. extracted helper:** Wrote `keccak256(abi.encode(whaleOpener, uint256(21)))` inline rather than extracting `_whalePassClaimsSlot(address)` like 336-02's pattern at `RngFreezeAndRemovalProofs.t.sol:531-534`. Rationale: the existing harness style uses inline `keccak256` for one-off slot probes (e.g., `_injectLootboxRngWord` at line 240-243); a single-site inline matches the file's existing convention without introducing a helper used only once.

## Deviations from Plan

- **[Rule 3 - Blocking issue] Warm-up call added to neutralize cross-call cold-warming asymmetry.** Found during: Task 1 (first test execution). Issue: raw measurement of two sequential `autoOpen(1)` calls produced delta = 26_398 gas, exceeding the 25_000 cap. Investigation showed the asymmetry was the first-call per-tx cold-warming penalty (already documented in the harness docstring at lines 142-150), not a WHALE-03 violation. Fix: added a third `warmupOpener` whose `autoOpen(1)` burns the cold reads BEFORE the two measured calls — both real measurements then see the SAME warm state. Files modified: test/gas/KeeperOpenBoxWorstCaseGas.t.sol (added `warmupOpener` address staging + `_buyBox(warmupOpener, ...)` + a single `vm.prank(warmupOpener); game.autoOpen(1);` warm-up call between the precondition asserts and the measurement). Inline rationale documented in the test natspec. This is a Rule 3 deviation (blocking issue with the measurement methodology, fixed in-task) — not a Rule 4 architectural change.

- **[Rule 2 - Critical functionality] Pre-condition asserts on the new test scaffold.** The plan's `<action>` outline did not explicitly call for `assertGt(_lootboxEthBase(...), 0, ...)` + `assertTrue(_lootboxRngWord(index) != 0, ...)` preconditions, but the surrounding tests in the same file enforce them (the harness's "assert-is-worst-case preconditions" pattern at lines 100-101 and 180-182). Added them to the new test for parity with the harness's existing standard — guards against silently-vacuous measurements where a box was somehow not queued / not RNG-ready. This is a Rule 2 (auto-add missing critical functionality) deviation aligned with the file's existing convention.

All other plan elements executed exactly as written.

## Issues Encountered

**1. First-run measurement exceeded tolerance by ~1.4K gas.** Diagnosed via `forge test -vvvv` showing the asymmetry was `creditFlip` cold/warm state plus internal `autoOpen` machinery cold-warming. The standard isolation pattern (warm-up burn) was the correct fix; no further iteration was needed once the warm-up call was inserted.

No other issues. `forge build` exits 0 on first try. No Solidity em-dash-in-string-literal errors (lessons from 336-01/02 SUMMARYs applied preemptively — only ASCII hyphens in `assertLe` / `emit log_named_uint` message strings). No stack-too-deep under `via_ir`. No `NotApproved()` reverts (the opener calls `autoOpen` themselves; no operator-approval gate on `autoOpen` per the harness's existing usage).

## Verification

- **`forge build`:** EXIT 0 (verified inline).
- **`forge test --match-path test/gas/KeeperOpenBoxWorstCaseGas.t.sol -vv`:** EXIT 0. **3/3 tests PASS:**
  - `testWhaleOpenerEqualsNonWhaleOpenerGas` — **NEW, PASS** (gas 1_405_990). Logs: `gas_whale_opener: 89_110`, `gas_non_whale_opener: 93_746`, `gas_delta: 4_636`, `gas_tolerance: 25_000`.
  - `testPerBoxMarginalAmortizesFixedOverhead` — pre-existing, PASS (gas 12_111_943). Logs UNCHANGED: `per_box_marginal_gas: 74_756`, `per_box_batch_total_gas: 2_392_221`, `single_box_total_ref_gas: 137_944`. **Confirms the 335-06 OPEN_BATCH=200 picker figure is preserved byte-identical.**
  - `testWorstCaseOpenBoxSingleMaterializationFitsBlockGasLimit` — pre-existing, PASS (gas 614_903). Logs UNCHANGED: `worst_case_open_box_single_materialization_gas: 113_875`.
- **`git diff e756a6f3 -- contracts/`:** EMPTY (verified via `git diff e756a6f3 -- contracts/ | wc -l` → `0`). D-TST04-04 honored.
- **`git diff --name-only HEAD`:** shows ONLY `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` modified.

## Plan acceptance criteria (per 336-03-PLAN.md `<acceptance_criteria>`)

| Criterion | Status |
|-----------|--------|
| `grep -c "testWhaleOpenerEqualsNonWhaleOpenerGas" test/gas/KeeperOpenBoxWorstCaseGas.t.sol` returns ≥ 1 | PASS — 1 match (function definition) |
| `forge test --match-test testWhaleOpenerEqualsNonWhaleOpenerGas -vvv` EXITS 0 with the emitted gas numbers visible in the log | PASS — exits 0; logs `gas_whale_opener: 89_110`, `gas_non_whale_opener: 93_746`, `gas_delta: 4_636`, `gas_tolerance: 25_000` |
| The pre-existing `testPerBoxMarginalAmortizesFixedOverhead` still PASSES (no regression) | PASS — green; `per_box_marginal_gas: 74_756` unchanged from 335-06 |
| `git diff e756a6f3 -- contracts/` returns empty (zero contracts mutation per D-TST04-04) | PASS — empty |
| The new test contains exactly one `assertLe(delta, TOLERANCE, ...)` assertion (the equivalence gate) | PASS — 1 `assertLe(delta, TOLERANCE, ...)` at the equivalence gate (other assertions are `assertEq` / `assertGt` / `assertTrue` preconditions) |
| The new test contains at least 3 `emit log_named_uint(...)` calls | PASS — 4 `emit log_named_uint` calls (gas_whale_opener / gas_non_whale_opener / gas_delta / gas_tolerance) |
| If TOLERANCE is set to 500, BOTH slots are pre-warmed via vm.store in setup; otherwise TOLERANCE is at least 25_000 with an inline comment explaining the cold-SSTORE choice | PASS — TOLERANCE = 25_000 with inline `@dev TOLERANCE CHOICE` natspec block explaining the cold-SSTORE worst-case justification per RESEARCH §A1 |

## Self-Check: PASSED

Created file exists:
- `.planning/phases/336-tst-equivalence-freeze-safety-divergence-repro-non-widening-/336-03-SUMMARY.md` — FOUND (this file).

Modified file exists with expected new symbol:
- `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` — FOUND; `grep -c "testWhaleOpenerEqualsNonWhaleOpenerGas"` = 1.

Empirical attestation numbers preserved:
- `per_box_marginal_gas: 74_756` (unchanged from 335-06 — OPEN_BATCH=200 picker preserved).
- `gas_delta: 4_636 < 25_000 = gas_tolerance` (WHALE-03 attestation green).

Contracts byte-identity:
- `git diff e756a6f3 -- contracts/` empty.

Commit will be verified post-commit by the orchestrator's bookkeeping pass.

## Known Stubs

None. The new test function is fully wired against the live `DegenerusGame.autoOpen` external (the facade at `DegenerusGame.sol:1592` that delegatecalls into LootboxModule), the verified `whalePassClaims` storage slot 21, and the existing harness helpers (`_buyBox`, `_activeLootboxIndex`, `_injectLootboxRngWord`, `_lootboxRngWord`, `_lootboxEthBase`). No placeholder values, no hardcoded mocks, no TODO/FIXME.

## Threat Surface

No new contract surface introduced (test-only plan; D-TST04-04 hard constraint honored — `contracts/*.sol` byte-identical to `e756a6f3`). The two STRIDE rows from the plan's `<threat_model>`:

| Threat ID    | Disposition | Empirical Status |
| ------------ | ----------- | ---------------- |
| T-336-03-01  | accept      | Verified — `git diff e756a6f3 -- contracts/` is empty. The `vm.store` pre-seed on slot 21 only normalizes the SETUP-side state; the load-bearing CLAIM-side measurement (`gasleft()` bracketing around `game.autoOpen(1)`) still measures live contract behavior. The phase commits ONLY to `test/` + `.planning/` per D-TST04-04. |
| T-336-03-02  | mitigate    | TOLERANCE = 25_000 (the maximum allowed by the threat-model cap). The empirical delta = 4_636 gas is logged via `emit log_named_uint("gas_delta", delta)` — USER + audit can inspect the actual number is far below the threshold, confirming the assertion is non-vacuous and the WHALE-03 attestation is real. A tolerance >25_000 is rejected by acceptance criteria; this plan honors the cap. |

## Next Phase Readiness

**TST-01 fully closed.** The three TST-01 legs are now landed:
- **336-01:** freeze leg (`testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe`)
- **336-02:** equivalence / grant-correctness oracle (`testClaimWhalePassMaterializesFutureWindowAndAppliesStats`)
- **336-03 (this plan):** uniform-O(1) gas-equivalence (`testWhaleOpenerEqualsNonWhaleOpenerGas`)

**Wave 4 (Plan 336-04):** TST-02 D-TST02-02 `vm.expectCall(IGame.lazyPassHorizon.selector, count: 0)` no-pass-SLOAD oracle in `test/fuzz/AfKingSubscription.t.sol`. The TST-02 surfaces sweep/evict/refresh/OPEN-E/swap-pop already landed at 335 D-IMPL-02; 336-04 closes only the explicit `vm.expectCall(count: 0)` no-SLOAD gap.

**Phase-level posture (re-attested at this plan boundary):**
- `feedback_no_contract_commits` honored — only `test/` + `.planning/` touched.
- `feedback_security_over_gas` honored — the WHALE-01..03 floor is empirically re-attested by this plan (alongside 336-01, 336-02); no gas knob was negotiated against the freeze-or-equivalence invariants.
- `feedback_wait_for_approval` / `feedback_manual_review_before_push` — no push performed (D-CC-04). Push gate at v50.0 closure / Phase 338.
- v50.0 audit subject HEAD `e756a6f3` still FROZEN (zero contracts diff).

---
*Phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-*
*Completed: 2026-05-28*
