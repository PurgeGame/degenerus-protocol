---
phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-
plan: 01
subsystem: test-fuzz-rnglock-determinism
tags: [tst-01, freeze-fuzz, whale-04, claimWhalePass, rnglock, freeze-safety, foundry-deep]
dependency_graph:
  requires:
    - 335-07 (BATCH-02 IMPL HEAD `e756a6f3` — the deferred `whalePassClaims +=` writer at LootboxModule:1253 + the `claimWhalePass` materialization endpoint at WhaleModule:1018; the WHALE-01/02/04 contract surface this test re-attests)
    - 334-WHALE04-FREEZE-PROOF.md — the paper proof empirically re-attested by this test
  provides:
    - TST-01 freeze leg empirical proof (the deferred whale-pass-claim path is freeze-safe under rngLock)
  affects:
    - test/fuzz/RngLockDeterminism.t.sol (extended in place per D-TST01-01 ROADMAP-LOCKED home)
tech_stack:
  added: []
  patterns:
    - Foundry `vm.snapshot`/`vm.revertTo` two-env byte-identity oracle (existing harness pattern)
    - `try/catch` perturbation absorption for structurally-expected reverts (mirrors cls 9/10)
    - `FOUNDRY_PROFILE=deep` 10000-run gate (existing v44/v49 332 D-precedent)
key_files:
  created: []
  modified:
    - test/fuzz/RngLockDeterminism.t.sol
decisions:
  - 'D-TST01-01 honored: extended `test/fuzz/RngLockDeterminism.t.sol` IN PLACE — NO parallel harness authored'
  - 'D-TST01-02 honored: deep proof gated via `FOUNDRY_PROFILE=deep`; default profile gets the routine 1000-run sample'
  - 'D-TST04-04 honored: zero `contracts/*.sol` mutation (`git diff e756a6f3 -- contracts/` empty)'
  - 'D-CC-01 honored: per-plan atomic commit for the test/ + SUMMARY.md changes'
  - 'D-CC-02 honored: sequential-on-main, no-worktrees'
  - 'T-336-01-03 STRIDE mitigated: `_revertToPreLock(preLockSnap)` called BEFORE re-staging the non-vacuity (B) second env'
  - 'T-336-01-02 STRIDE mitigated: non-vacuity (B) control run zeroes `totalFlipReversals` and asserts the captured word DIFFERS from baseline — the freeze-byte-identity oracle is empirically non-vacuous'
  - 'WHALE-04 sec4 corollary empirically attested: `whalePassClaims[claimant]` is UNCHANGED across the locked-window claim attempt (the revert at Storage:661 / WhaleModule:1019 rolls back the zero-out at WhaleModule:1024 — the grant is claimable-eventually, never marooned)'
metrics:
  duration_minutes: ~19
  completed_at: 2026-05-28T12:04:50Z
  fuzz_runs_default: 1000
  fuzz_runs_deep: 10000
  file_lines_added: 213
requirements: [TST-01]
---

# Phase 336 Plan 01: TST-01 Freeze Leg — `claimWhalePass` During rngLock Byte-Identity Summary

WHALE-04 paper proof empirically re-attested: a same-tx `claimWhalePass()` perturbation inside the rngLock window does NOT alter the consumed per-index VRF-derived word.

## What Was Built

`test/fuzz/RngLockDeterminism.t.sol` extended in place (the ROADMAP-LOCKED freeze-fuzz home per D-TST01-01) with two narrow additions:

1. **Perturbation library extension — `cls == 11` branch + `N_PERTURB_ACTIONS` bumped 11→12.** The `_perturb(uint256 seed)` library at `test/fuzz/RngLockDeterminism.t.sol:160-251` gained a 12th perturbation class that pranks `actor` and `try`s `game.claimWhalePass(actor)` — mirrors the cls 9 (`afKing.doWork()`) and cls 10 (`afKing.autoBuy(0)`) shapes verbatim. The `try/catch` absorbs the structurally-expected revert per WHALE-04 §2 (the far-future band at `_queueTicketRange:661` reverts `RngLocked()` and the function entry at `WhaleModule:1019` reverts `E()` under `_livenessTriggered()`).

2. **New fuzz function — `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe(uint256 seed)`.** Mirrors the `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` template (at `:1839-1928`) verbatim with three substitutions: pre-load `whalePassClaims[claimant] > 0` so the claim has work to do (otherwise the perturbation is vacuous via the `halfPasses == 0` short-circuit at `WhaleModule:1021`); the in-lock perturbation is `claimWhalePass(claimant)` instead of `doWork()/autoBuy(0)`; an extra `WHALE-04 sec4` corollary attestation that `whalePassClaims[claimant]` survives the locked-window claim attempt (the counter is untouched across the rngLock revert — claim-is-claimable-eventually).

Two new helpers added: `_preloadWhalePassClaims(address claimant, uint256 halfPasses)` and `_readWhalePassClaims(address claimant)` — both ride the verified storage slot 21 (`whalePassClaims` mapping; confirmed via `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout`).

## Test Results

| Profile                       | Runs   | Result | Mean Gas    | Duration |
| ----------------------------- | ------ | ------ | ----------- | -------- |
| default (`forge test`)        | 1000   | PASS   | 11_751_160  | 429 ms   |
| `FOUNDRY_PROFILE=deep`        | 10000  | PASS   | 11_752_679  | 2.51 s   |

The 10000-run deep proof was the binding empirical re-attestation of WHALE-04. No fuzz reductions (`runs: 10000` ran to completion on the same `Fuzz seed: 0xdeadbeef`).

Pre-existing tests in the same file are unaffected:
- `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` — PASS (1000 runs)
- `testFuzz_RngLockDeterminism_RetryLootboxRng` — PASS (1000 runs)
- `testAutoOpenBlockedDuringRngLockNoOps` — PASS
- `testAutoOpenNoMaroonedBoxesAfterUnlock` — PASS
- `testFuzz_RngLockDeterminism_StakedStonkRedemption` — FAIL (`vm.assume rejected too many inputs`) — this is a PRE-EXISTING baseline red verified by `git stash`+test+`git stash pop` against the working tree at `60da5747` BEFORE my changes; matches v49 §2 baseline carry. NOT a regression introduced by this plan.
- 16 SKIP cases (carried baseline `vm.skip` block markers from the v43/v44 harness aggregator) — unchanged.

## Verification

```bash
# Default profile — the TST-01 freeze leg passes at 1000 runs
forge test --match-path test/fuzz/RngLockDeterminism.t.sol \
  --match-test ClaimWhalePassDuringLockSafe -vv

# Deep profile — the binding empirical re-attestation at 10000 runs
FOUNDRY_PROFILE=deep forge test --match-path test/fuzz/RngLockDeterminism.t.sol \
  --match-test ClaimWhalePassDuringLockSafe

# Zero contracts/ mutation gate (D-TST04-04)
git diff e756a6f3 -- contracts/   # empty

# Grep-acceptance criteria
grep -c "cls == 11" test/fuzz/RngLockDeterminism.t.sol             # 1
grep -c "claimWhalePass" test/fuzz/RngLockDeterminism.t.sol        # 18
grep -n "N_PERTURB_ACTIONS = 12" test/fuzz/RngLockDeterminism.t.sol # 1 match (line 169)
grep -c "testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe" \
  test/fuzz/RngLockDeterminism.t.sol                                # 1
```

All grep oracles report the expected counts. `forge build` exits 0; suite at default profile shows the single pre-existing baseline red (StakedStonkRedemption) and zero new failures.

## Deviations from Plan

None — the plan executed exactly as written. The two TDD tasks (1 = cls 11 perturbation extension + N_PERTURB_ACTIONS bump; 2 = new fuzz function) landed as a single atomic patch to honor D-CC-01 (per-plan atomic commit, not per-task); both task-level acceptance criteria are independently satisfied within the single commit. No Rule 1/2/3 auto-fixes triggered (no bugs found, no missing critical functionality, no blocking issues). No Rule 4 architectural decisions required.

Minor in-flight nit: the initial draft of the new function's string literal contained a Unicode `§` character (`WHALE-04 §4`) which `solc 0.8.34` rejected with `Invalid character in string`. Substituted `§` → `sec` (the file's existing convention at line 23 `secN cross-reference`) and the build went green. Not a deviation — a one-character source-fixup absorbed within Task 2.

## Known Stubs

None. The new fuzz function and its two helpers (`_preloadWhalePassClaims` / `_readWhalePassClaims`) are fully wired against the verified storage slot 21 (`whalePassClaims` mapping) and the live `DegenerusGame.claimWhalePass(address)` external (the facade at `DegenerusGame.sol:1864` that delegatecalls into `WhaleModule:1018`). No placeholder values, no hardcoded mocks, no TODO/FIXME.

## Threat Surface

No new contract surface introduced (test-only plan; D-TST04-04 hard constraint honored — `contracts/*.sol` byte-identical to `e756a6f3`). The two STRIDE rows from the plan's `<threat_model>`:

| Threat ID    | Disposition | Empirical Status |
| ------------ | ----------- | ---------------- |
| T-336-01-01  | accept      | Verified — `git diff e756a6f3 -- contracts/` is empty. State-forging via `_preloadWhalePassClaims` only loads the perturbation source; the assertion is byte-identity of the consumed VRF word, which holds independent of the staging shape. |
| T-336-01-02  | mitigate    | Non-vacuity (B) control run present at `:2125-2137` — zeroes `totalFlipReversals` via `vm.store` and asserts `controlWord != baselineWord`, proving the freeze-byte-identity oracle empirically detects a change to the consumed word formula (i.e., the byte-identity above did not pass vacuously). |
| T-336-01-03  | mitigate    | Snapshot revert before re-stage honored — `_revertToPreLock(preLockSnap)` is called on line `:2125` BEFORE the non-vacuity (B) re-staging. The helper at `:130-144` enforces revert-before-re-stage by construction (single `vm.revertTo(snapshotId)` call body). |

## Self-Check: PASSED

- File modified: `test/fuzz/RngLockDeterminism.t.sol` — FOUND.
- New fuzz function `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe` — FOUND (grep returns 1 match).
- New perturbation class `cls == 11` — FOUND (grep returns 1 match).
- `N_PERTURB_ACTIONS = 12` literal — FOUND (line 169).
- `claimWhalePass` references — FOUND (18 matches; includes the new fn, the new cls 11 branch, the docstring blocks).
- `contracts/*.sol` byte-identical to `e756a6f3` — VERIFIED (`git diff e756a6f3 -- contracts/` empty).
- Default-profile fuzz run (1000) — PASS.
- `FOUNDRY_PROFILE=deep` fuzz run (10000) — PASS.
- Pre-existing tests in this file (AutoBuy / RetryLootboxRng / autoOpen pair) — PASS.
- `testFuzz_RngLockDeterminism_StakedStonkRedemption` failure — confirmed pre-existing baseline (verified via `git stash`/`git stash pop` round-trip) — NOT a new regression.
