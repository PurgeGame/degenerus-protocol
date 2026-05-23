---
phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst
plan: 04
subsystem: test
tags: [solidity, foundry, chainlink-vrf, wirevrf, vrf-rotation, access-control, one-shot, degenerus]

# Dependency graph
requires:
  - phase: 312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl
    provides: "VRF-04 deviation (no init-lock; wireVrf one-shot by construction) — the assertion shape this test must use"
provides:
  - "VTST-04 regression: test/fuzz/VrfWireOneShot.t.sol — non-ADMIN wireVrf + updateVrfCoordinatorAndSub revert (direct routed reach) + structural one-shot-by-construction attestation"
affects: [313-tst-vrf-rotation, 314-sweep, vrf, rng-lock, wirevrf]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Access-guard revert proof via low-level call + assertFalse(ok) (CoverageGap222 pattern) — robust to the exact revert selector"
    - "vm.readFile grep-count source attestation with try/catch fallback to embedded attestation + lastVrfProcessed()!=0 when fs_permissions are absent"

key-files:
  created:
    - test/fuzz/VrfWireOneShot.t.sol
  modified: []

key-decisions:
  - "Asserted the :503 / :1717 ContractAddresses.ADMIN access-guard revert (NOT a non-existent vrfCoordinator!=address(0) init-lock) — the one-shot property in the form that actually exists post-Phase-312 per 312-01-SUMMARY Deviations §1."
  - "Structural one-shot attestation uses vm.readFile grep-count (gameAdmin.wireVrf( == 1) wrapped in try/catch; foundry.toml has no fs_permissions so the read reverts here and the documented fallback (embedded attestation + lastVrfProcessed()!=0) runs. NO foundry.toml change made."
  - "Non-admin actor is makeAddr(\"nonAdmin\"), explicitly asserted != ContractAddresses.ADMIN, so the revert is the genuine guard rejecting an unauthorized caller (not a setup artifact)."

requirements-completed: [VTST-04]

# Metrics
duration: ~10min
completed: 2026-05-23
---

# Phase 313 Plan 04: VTST-04 wireVrf One-Shot Lock Summary

**`test/fuzz/VrfWireOneShot.t.sol` proves VRF wiring is one-shot in the form that actually exists post-Phase-312: a non-ADMIN `wireVrf` and `updateVrfCoordinatorAndSub` both revert through the routed delegatecall reach (the `:503` / `:1717` ContractAddresses.ADMIN guards), plus a structural attestation that DegenerusAdmin reaches `wireVrf` only from its constructor — proving VRF-04 + VRF-05 without asserting the deliberately-omitted init-lock.**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-05-23T10:40:20Z
- **Tasks:** 2 (both `type="auto"`)
- **Files created:** 1 test file (`test/fuzz/VrfWireOneShot.t.sol`, 162 lines, 4 test functions)

## Accomplishments

- **VTST-04 (VRF-04 access-guard form):** `test_nonAdminWireVrf_reverts` — a low-level `wireVrf` call from a freshly-made non-ADMIN prank returns `ok == false`. The routed reach (DegenerusGame.wireVrf `:308` → delegatecall → AdvanceModule impl `:498` → `:503` `msg.sender != ContractAddresses.ADMIN`) rejects the caller. This is the "a second wire from an unauthorized caller reverts" provable shape.
- **VTST-04 (VRF-05 routed-reach companion):** `test_nonAdminUpdateVrf_reverts` — the routed coordinator-rotation entry (`:1874` → delegatecall → impl `:1712` → `:1717` ADMIN guard) reverts for the same non-ADMIN sender, proving the routed admin dispatch is guarded.
- **Deploy-wire confirmation:** `test_wiringHappenedAtDeploy` — `game.lastVrfProcessed() != 0` confirms the constructor wire ran exactly once, establishing that any further wire is the "second wire" the access guard blocks.
- **Structural one-shot attestation:** `test_structuralOneShot_wireVrfOnlyFromConstructor` — attests the user-approved VRF-04 deviation (one-shot by construction, no init-lock). Prefers a `vm.readFile` source-level grep asserting exactly one `gameAdmin.wireVrf(` call site; with `foundry.toml` lacking `fs_permissions`, the try/catch falls back to the documented embedded attestation + `lastVrfProcessed() != 0`.
- **Landmine avoided:** The test asserts NONE of a `vrfCoordinator != address(0)` init-lock revert (no such guard exists in the contract — Phase 312 deliberately omitted it, user-approved). `grep -n "vrfCoordinator != address(0)"` in `DegenerusGameAdvanceModule.sol` returns zero matches, confirming the omission.

## Source-Anchor Verification (grep-confirmed live at HEAD)

- `contracts/modules/DegenerusGameAdvanceModule.sol`: `wireVrf` at `:498`, ADMIN guard `if (msg.sender != ContractAddresses.ADMIN) revert E();` at `:503`; `updateVrfCoordinatorAndSub` at `:1712`, ADMIN guard at `:1717`. NO `vrfCoordinator != address(0)` init-lock present.
- `contracts/DegenerusGame.sol`: routed `wireVrf` `:308`, `updateVrfCoordinatorAndSub` `:1874`, `lastVrfProcessed()` view `:2202`.
- `contracts/DegenerusAdmin.sol`: the only `gameAdmin.wireVrf(` call site is at `:458` inside the constructor (`:445`); the `:109` `function wireVrf(...)` is an interface declaration (`external;` no body), not a forwarder. No post-construction forwarder/multicall/delegatecall re-emits wireVrf.
- `contracts/ContractAddresses.sol`: `address internal constant ADMIN` at `:51`.

Note vs plan/interfaces text: the `updateVrfCoordinatorAndSub` ADMIN guard is at `:1717` (the plan/interfaces noted ~:1693). The test asserts the guard behavior (low-level `ok == false`), not a hardcoded line, so the off-by-line note is documentation-only with no test impact.

## Build / Test / Scope Attestation

- **`forge build` → exit 0** (pre-existing `unsafe-typecast` / shadow-declaration lint notes in `DegenerusGameJackpotModule.sol` unchanged — out of scope, not introduced here).
- **`forge test --match-contract VrfWireOneShot` → 4 passed, 0 failed, 0 skipped.**
- **Scope:** `git diff --name-only` per task = ONLY `test/fuzz/VrfWireOneShot.t.sol`. ZERO `contracts/` mutation (verified `git diff --stat -- contracts/` empty after both tasks). No `foundry.toml` change (the fs_permissions fallback path was used instead).

## Task Commits

1. **Task 1 (access-guard form):** `4d45107d` — `test(313-04): VTST-04 non-ADMIN wireVrf + updateVrf revert (access-guard form)` — 3 tests (non-ADMIN wireVrf revert, non-ADMIN updateVrf revert, lastVrfProcessed!=0).
2. **Task 2 (structural attestation):** `b4a63ac7` — `test(313-04): VTST-04 structural one-shot attestation (wireVrf constructor-only)` — adds `test_structuralOneShot_wireVrfOnlyFromConstructor` + `_countOccurrences` helper (4 tests total PASS).

## Deviations from Plan

None — plan executed as written. The plan anticipated the `fs_permissions` gap and the `:1693` vs `:1717` line discrepancy was absorbed by the behavior-based (selector-robust) assertion shape. Both pre-anticipated conditions were handled via the plan's documented fallback / pattern; neither is a scope deviation.

## Known Stubs

None. The structural-attestation fallback (`lastVrfProcessed() != 0`) is a substantive on-chain assertion of the one-shot wire, not a placeholder; the preferred `vm.readFile` grep-count path activates automatically if `fs_permissions` are ever granted.

## Issues Encountered

- `vm.readFile` reverts under the repo's default (restrictive) `foundry.toml` (no `fs_permissions`). Anticipated by the plan; resolved via the documented try/catch fallback rather than touching shared config. Confirmed empirically with a throwaway probe test (created and removed; no leftover untracked file).

## Self-Check: PASSED

- `test/fuzz/VrfWireOneShot.t.sol` — FOUND (162 lines, 4 test functions).
- Commit `4d45107d` — FOUND in `git log`.
- Commit `b4a63ac7` — FOUND in `git log`.
- `forge test --match-contract VrfWireOneShot` — 4 passed, 0 failed.
- `git diff --stat -- contracts/` — empty (ZERO contracts mutation).

---
*Phase: 313-tst-vrf-regression-freeze-invariant-fuzz-under-rotation-tst Plan 04*
*Completed: 2026-05-23*
