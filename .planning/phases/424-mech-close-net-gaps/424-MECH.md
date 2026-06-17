# Phase 424 — MECH (Close the Mechanical-Net Gaps) — Coverage Map

**Phase:** 424 MECH (test-only, commits autonomously) · **Date:** 2026-06-17 · **Reqs:** MECH-01..04
**Subject:** `4970ba5b` @ `73eb242a` (incl. the MIDRNG-02 fix). Test additions only; no contract change.

## Verdict: mechanical-net gaps closed — the one real defect is captured + the deferred candidate reconciled; gas/solvency/layout covered by existing + targeted regressions.

The v67 hunt surfaced exactly **one real contract defect (MIDRNG-02, MEDIUM, fixed `73eb242a`)**; everything else HOLDS / INFO / by-design. MECH therefore focuses on (a) capturing that defect as a pass-with-fix/fail-without regression, (b) reconciling the one deferred finding-candidate, and (c) confirming the standing gas / solvency / layout nets cover the BRICK-04 / CORRUPT invariants.

## Requirement coverage

### MECH-01 — worst-case gas harness (< 16.78M, derived not sampled) — ✅ COVERED (existing + 418)
- `test/gas/AdvanceGasCeilingFuzz.t.sol` + `AdvanceGasCeiling.sol` — advance-chain ceiling.
- `test/gas/GameOverCompositionAdvanceGas.t.sol` — terminal composition; **422 measured the 305-winner terminal jackpot at 6.25M, composite ~7.2M < 16.78M** (real `advanceGame` bytecode).
- `test/gas/AdvanceStageWorstCaseGas.t.sol`, `RouterWorstCaseGas`, `SweepPerPlayerWorstCaseGas`, `KeeperOpenBoxWorstCaseGas`, `KeeperResolveBetWorstCaseGas`, `CoinflipDeepClaimWorstCaseGas`, `V56AfkingGasMarginal`.
- 418 added `test_AllEvictSaturatedChunk_LIVE_Measured` (the binding all-evict chunk, live-cranked, post-reweight 9.71M). The BRICK-04 worst-case branch is the binding figure and is asserted under the cap.

### MECH-02 — delegatecall storage-layout regression oracle — ✅ PARTIAL (critical slots pinned) + recommendation
- `test/fuzz/StorageFoundation.t.sol` pins the load-bearing packed slots via `vm.load`/`vm.store` + the contract's own getters: slot 0 flag offsets (`ticketWriteSlot`@25, `prizePoolFrozen`@26, `ticketsFullyProcessed`@24), slots 2/11 `prizePools*Packed` next|future halves, slot 26 `levelDgnrsPacked` alloc|claimed halves (post-v62 fold). A layout fold that moves any of these trips the test.
- `LR_MID_DAY` (slot 34 bit 224) position is asserted by the new VRFCore latch regressions (`_lrMidDay()` reader).
- **Recommendation (carried):** a full `forge inspect DegenerusGame storageLayout` snapshot fixture + a diff check would cover the *entire* packed set (the 420 critic showed the COLMAP-04 flag-list under-counted the surface by 8). `.planning/phases/417-.../417-game-storage-layout.json` is the authoritative snapshot to diff against in CI. Not blocking (all packed slots independently verified clean in 420 r1+r2), recorded for a future CI gate.

### MECH-03 — state-invariant test (BRICK liveness + CORRUPT solvency) — ✅ COVERED (existing + per-phase proofs)
- Solvency: `test/fuzz/V56FreezeSolvency.t.sol`, `YieldSurplusSolvency.t.sol`, `ShareMathInvariants.t.sol`, `FLIPInvariants.t.sol` — the `claimablePool == Σ(claimable+afking)` family (with the documented decimator reserve-superset exception, CORRUPT-05 / INFO-01) and the stETH-fallback CEI.
- Liveness: the advance/rotation suites (`VRFCore`, `RngLockRotationDeterminism` @1000 runs, `VrfRotationLiveness`, `StallResilience`, `RngRetryLootboxStall`) exercise the BRICK liveness + MIDRNG recovery paths.
- The 420 CORRUPT solvency identity + the 418 BRICK liveness were each proven by council + NET-2 against the frozen source.

### MECH-04 — capture brick/corruption mutants surfaced in 417-423 — ✅ DONE
- **MIDRNG-02 (the one real defect):** `test_midDayLatch_clearsOnCrossDayDrain` (VRFCore) — pass-with-fix / **fail-without (`NotTimeYet`)** negative control. Committed with the fix `73eb242a`.
- **DEF-380-04-FC1 (deferred finding-candidate):** reconciled from `vm.skip` into the passing `test_midDayTicketRequest_gatesNextAdvanceUntilWordLands` (VRFCore) — asserts the adjudicated by-design gating + permissionless retry recovery + latch release. Committed `4617a4a1`. VRFCore now **23/0/0** (was 22/0/1).

## Validation
- VRFCore suite: **23 passed / 0 failed / 0 skipped**.
- **Full forge suite (milestone-close, post-fix tree `4970ba5b`): 903 passed / 0 failed / 108 skipped** (127 suites, exit 0). Zero regressions from fix A. Skips 109→108 (the reconciled `DEF-380-04-FC1` moved from skipped to passing). This is the v67 regression-GREEN floor (baseline 416 was 900/0/109).

## Carried recommendations (non-blocking → 425 / future)
- Full `forge inspect` layout-snapshot CI oracle (MECH-02 completion).
- Optional `:1843`/`:1850` `== 0` fulfill-write guard (the re-roll LOW; USER-deferred).
- Codex backfill for 423 when the usage cap resets.
