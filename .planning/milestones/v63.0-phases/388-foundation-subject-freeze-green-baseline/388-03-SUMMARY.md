---
phase: 388-foundation-subject-freeze-green-baseline
plan: 03
subsystem: testing
tags: [forge, hardhat, foundry, regression-baseline, byte-freeze, audit-oracle, vrf-invariants, solvency]

# Dependency graph
requires:
  - phase: 388-01
    provides: authoritative a8b702a7 storage layout key + per-harness slot reconciliation (so a green run is trustworthy, not stale-slot-masked)
  - phase: 388-02
    provides: verifier oracle-hole audit (so green means invariants ran, not vacuous passes) + the routed legacy-RedemptionInvariants HOLE
provides:
  - subject byte-freeze pin (a8b702a7 contract-source tree hash 2934d3d8 + deterministic content sha256) with empty-diff assertion
  - the 77580320->a8b702a7 audit-delta surface (40 files +4322/-3489) with per-family characterization (packing/BURNIE/gas-identity/permissionless/redemption/rewards)
  - the GREEN v63 forge regression baseline (854/0/110, 0 deterministic failures, ZERO carried bucket-A reds) superseding the v62 carried-red ledger
  - the Hardhat corroborating disposition (1105/121/5, carried gameover-VRF-drive harness drift, no hard-floor breach)
affects: [389-packing-identity, 390-solvency-spine, 391-rng-spine, 392-burnie, 393-permissionless-entrypoints, 394-reward-game-theory, 395-mutation, 396-terminal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "byte-freeze pin = git tree-hash (content-addressed) + deterministic content sha256 + HEAD:contracts == subject:contracts assertion"
    - "GREEN baseline as the audit oracle: regressions caught by '0 deterministic failures BY NAME', not a non-widening raw-count diff"
    - "forge PRIMARY / Hardhat corroborating; JS reds characterized against documented carried harness-drift families with a genuine-breach grep gate"

key-files:
  created:
    - .planning/phases/388-foundation-subject-freeze-green-baseline/388-03-BASELINE-DIFF.md
    - test/REGRESSION-BASELINE-v63.md
  modified: []

key-decisions:
  - "ZERO permitted residual reds at a8b702a7 — the 3 v62 carried bucket-A VRF-path invariants now pass 7/7 (the VRFPath suite was also strengthened: rngUnlockedAfterSwap -> swapPreservesLockState), so the bucket-A exception list is now empty"
  - "Hardhat subset declared corroborating-only: 121 failures are the documented carried gameover-VRF-drive harness-drift families; the one solvency-titled red (ACCT-08) fails on gameOver-never-latches (precondition not reached, identity not violated) and the one RNG-titled red (RngStall) reverts on a CONTRACT GUARD RngNotReady() = correct defensive behavior, not a freeze breach"
  - "PLAYER-PURCHASE-REWARDS.html ruled OUT of scope (player-facing doc, not a contract source)"

patterns-established:
  - "Pattern: per-family characterization of the audit delta maps each changed file to its owning sweep phase (389-394) so sweep planners see their slice"
  - "Pattern: landmine guard — forge captured FIRST on clean fixture, hardhat after, ContractAddresses.sol restored + status re-verified empty + forge build re-confirmed clean before trusting the baseline"

requirements-completed: [FND-01, FND-03]

# Metrics
duration: 22min
completed: 2026-06-14
---

# Phase 388 Plan 03: Subject Freeze & GREEN v63 Regression Baseline Summary

**Byte-freeze pin for subject `a8b702a7` (tree-hash `2934d3d8` + content sha256 `0c684378`) + the 40-file audit-delta surface, plus the GREEN forge baseline 854/0/110 with ZERO carried reds — the v62 VRF-path bucket-A exceptions now pass 7/7 — superseding the carried-red ledger; Hardhat 1105/121/5 corroborating with no hard-floor breach.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-06-14T22:10:00Z (approx)
- **Completed:** 2026-06-14T22:32:00Z (approx)
- **Tasks:** 2
- **Files modified:** 2 (both created)

## Accomplishments

- **FND-01 satisfied:** recorded the subject byte-freeze pin (git tree-hash `2934d3d8987a09c5f073549a0cb499f6c5f28620` == `HEAD:contracts` == `a8b702a7:contracts`; deterministic content sha256 `0c684378df8d12f339af54e39de7df55971643f69e6b68f02332e918c20d15b3`; `git diff a8b702a7 -- contracts/` EMPTY) and the `77580320 → a8b702a7` audit-delta surface (40 files, +4322/−3489) with a per-family characterization mapping each changed file to its owning v63 sweep phase.
- **FND-03 satisfied:** established + recorded the GREEN forge baseline — `854 passed / 0 failed / 110 skipped` across 122 suites, ALL green, on a clean fixture — and the Hardhat corroborating disposition (`1105 passing / 121 failing / 5 pending`), in `test/REGRESSION-BASELINE-v63.md`, superseding the carried-red v62 ledger.
- **Stronger than the prior baseline:** the 3 v62 carried bucket-A VRF-path invariants (`invariant_allGapDaysBackfilled`, `invariant_stallRecoveryValid`, and the superseded `invariant_rngUnlockedAfterSwap` → `invariant_swapPreservesLockState`) now ALL pass (`runs: 256, calls: 32768, reverts: 0`). The permitted-residual-reds set is now EMPTY — the audit signal is "0 deterministic failures BY NAME" with no carried exceptions.
- **Verified no hard-floor breach in the JS subset:** the one solvency-titled red is `gameOver` never latching (precondition not reached, ACCT-08 identity untouched); the one RNG-titled red reverts on the contract guard `RngNotReady()` (selector `0xbb3e844f` decoded via `cast sig`) — correct defensive behavior. A genuine-breach grep over all 121 failure blocks returned none.
- **Subject byte-frozen throughout:** the landmine was guarded (forge first on a clean fixture, hardhat after, `ContractAddresses.sol` restored — a no-op this run — `git status --porcelain contracts/` empty + `forge build` clean exit 0 re-confirmed before recording).

## Task Commits

Each task was committed atomically:

1. **Task 1: Record byte-freeze pin + audit-delta surface (FND-01)** — `a631e02e` (docs)
2. **Task 2: Re-run forge clean + Hardhat subset, record GREEN v63 baseline (FND-03)** — `222d87dd` (test)

**Plan metadata:** (final docs commit — SUMMARY + STATE + ROADMAP)

## Files Created/Modified

- `.planning/phases/388-foundation-subject-freeze-green-baseline/388-03-BASELINE-DIFF.md` — the byte-freeze fingerprint pin (tree-hash + content sha256 + empty-diff assertion) and the `77580320 → a8b702a7` audit-delta stat with per-family characterization (storage packing · BURNIE emission · gas-identity · permissionless/keeper entrypoints · redemption rework · reward rebalances).
- `test/REGRESSION-BASELINE-v63.md` — the GREEN full-suite baseline record for subject `a8b702a7`: §0 the supersession discipline (0 failures by name; empty bucket-A set), §1 the GREEN forge counts table + the now-green VRFPath suite, §2 the RNG-freeze + solvency floor exercised-not-vacuous note, §3 the Hardhat corroborating disposition with breach scan, §4 the 388-01/388-02 dependence, §5 the byte-frozen attestation, §6 the skip census.

## Decisions Made

- **The bucket-A exception list is now empty.** v62 permitted 3 carried non-deterministic VRF-path reds; at `a8b702a7` they pass green and the suite was strengthened. Recorded explicitly so a future run showing ANY failing name is a candidate regression.
- **Forge is PRIMARY; Hardhat corroborating.** The 121 JS failures match the documented v62 §5 carried gameover-VRF-drive harness-drift families exactly (SecurityEconHardening 16, RngStall 13, AffiliateHardening 11, BafCreditRouting 8, GameOver 7, etc.). Decoding the `RngStall` revert selector confirmed it is the contract's `RngNotReady()` guard firing (correct defensive behavior under an outdated multi-step drive shape), not a freeze breach. The forge `RngWindowFreeze` falsifiable invariant + the 7/7 GREEN VRFPath suite are the authoritative freeze oracle.
- **`PLAYER-PURCHASE-REWARDS.html` is OUT of scope** — a player-facing document, not a contract source; excluded from all fingerprints and the audit subject.

## Deviations from Plan

None - plan executed exactly as written. No contract-source edits (audit-only posture honored); both deliverables created with the exact paths and content the plan specified; the forge GREEN reproduced the freeze-validation expectation (853/0/110 → observed 854/0/110, the +1 a run/harness-count delta, still 0 failures and 0 carried reds). The plan's contingency ("if any deterministic test* red caused by a slot/semantics miss, fix in the owning test file") was NOT triggered — the suite was already 0-failed.

## Issues Encountered

- The Hardhat subset exits with code 1 due to a trailing `MODULE_NOT_FOUND` for a stray `test/unit/AffiliateHardening.test.js` reference printed AFTER all specs run (the documented v62 §5 trailing-error, not a pre-load abort). Resolved by parsing the Mocha summary (`1105 passing / 121 failing / 5 pending`) rather than relying on the exit code, and characterizing the failures against the documented carried families. The `npm test` adversarial-glob `MODULE_NOT_FOUND` (a true pre-load abort) was avoided by running the explicit `test/unit + test/edge` subset, per plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The audit foundation is complete: subject byte-frozen + pinned, a GREEN forge oracle recorded, the slot layout reconciled (388-01), and the oracle holes audited (388-02). Every later sweep (389–396) can now assert `git diff a8b702a7 -- contracts/` empty and reproduce leads against the recorded GREEN counts.
- One routed coverage item for **390 SOLVENCY-SPINE**: the legacy `RedemptionInvariants.inv.t.sol` 7-INV harness is a confirmed oracle HOLE (un-wired claim/resolve + stETH leg, stale slots) — superseded by `RedemptionAccounting.t.sol` + `RedemptionStethFallback.t.sol`; do not rely on its green for SOLV-03/05/06.
- NEXT: `/gsd-plan-phase 389` PACKING-IDENTITY (intake = the 9 FC-389-* candidates from the 388-02 ledger).

## Self-Check: PASSED

- FOUND: `.planning/phases/388-foundation-subject-freeze-green-baseline/388-03-BASELINE-DIFF.md`
- FOUND: `test/REGRESSION-BASELINE-v63.md`
- FOUND: `.planning/phases/388-foundation-subject-freeze-green-baseline/388-03-SUMMARY.md`
- FOUND commit: `a631e02e` (Task 1, FND-01)
- FOUND commit: `222d87dd` (Task 2, FND-03)
- Subject byte-frozen: `git diff a8b702a7 -- contracts/` empty + `git status --porcelain contracts/` empty (FROZEN_OK)

---
*Phase: 388-foundation-subject-freeze-green-baseline*
*Completed: 2026-06-14*
