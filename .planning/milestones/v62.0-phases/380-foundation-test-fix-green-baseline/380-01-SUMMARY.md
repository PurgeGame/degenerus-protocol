---
phase: 380-foundation-test-fix-green-baseline
plan: 01
subsystem: testing
tags: [forge, storage-layout, slot-recalibration, vm-store, regression-baseline, c4d48008]

requires:
  - phase: 378-tst-proving-tests-rng-freeze-solvency
    provides: "378-01-RECALIBRATION-KEY.md (v61-HEAD authoritative layout) + REGRESSION-BASELINE-v61.md (the carried-red non-widening union)"
provides:
  - "380-01-LAYOUT-KEY.md — authoritative c4d48008 DegenerusGame storage layout (storage byte-identical to v61 HEAD; forgiving-funding added accessors, no new slot)"
  - "QueueDoubleBuffer.t.sol green (10/10) — fixture warp fix turned 9 carried Panic(0x11) reds green"
  - "KeeperNonBrick.t.sol storage slots recalibrated v54-era -> c4d48008 authoritative (stays 2/0/13)"
  - "Root-cause classification of all 10 c4d48008 reds in the named slot-hardcoded set: 9 fixable-fixture + 5 carried-behavioral (overlapping count across 11 suites)"
affects: [381-invariant-fuzz, 382-prime, 384-compo, 385-loop, council-sweeps]

tech-stack:
  added: []
  patterns:
    - "forge inspect DegenerusGame storageLayout --json is THE slot authority; re-derive every vm.store/vm.load constant from it (never assume a uniform shift)"
    - "Harness setUp that extends DegenerusGameStorage and calls a queue/liveness path MUST vm.warp past JACKPOT_RESET_TIME (82620s) or GameTimeLib.currentDayIndexAt(default ts=1) underflows"
    - "Carried-red discipline: a red whose code path is byte-identical baseline->subject AND is in the v61 non-widening union is documented as carried, not forced green by editing tests/contracts"

key-files:
  created:
    - ".planning/phases/380-foundation-test-fix-green-baseline/380-01-LAYOUT-KEY.md"
  modified:
    - "test/fuzz/QueueDoubleBuffer.t.sol"
    - "test/fuzz/KeeperNonBrick.t.sol"

key-decisions:
  - "Storage at c4d48008 is byte-identical to v61 HEAD — the forgiving-funding feat added accessor functions + an event (+15 lines), zero new storage variable, so no slot moved."
  - "The 5 residual behavioral reds (VRFCore midday, VRFStall gap x3, V56Sub churn) are CARRIED (in the v61 non-widening union, code paths in the byte-identical AdvanceModule/subscribe path, untouched by the c4d48008 delta) — NOT this plan's slot-recalibration target."
  - "QueueDoubleBuffer Panic(0x11) is a fixture defect (missing setUp warp), not slot-drift and not a contract bug — fixed in test only."
  - "Removed the dead KeeperNonBrick AFKING_FUNDING_SLOT=8 constant (the mapping was folded into balancesPacked by the v61 PACK; slot 8 is now traitBurnTicket)."

patterns-established:
  - "Per-harness ledger marks Game-resident (recalibrate) vs sDGNRS-resident (leave) pokes against the authoritative layout"

requirements-completed: [FOUND-01]

duration: 30min
completed: 2026-06-07
---

# Phase 380 Plan 01: Foundation Test-Fix & Green Baseline Summary

**Authoritative c4d48008 storage-layout key (storage byte-identical to v61 HEAD) + QueueDoubleBuffer fixture-warp fix (9 carried Panic(0x11) reds -> green) + KeeperNonBrick v54-era slot recalibration; the 5 residual reds proven CARRIED, contracts byte-frozen.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-06-07T18:12:43Z
- **Completed:** 2026-06-07T18:41Z
- **Tasks:** 3
- **Files modified:** 3 (1 created, 2 edited) — all test/planning; ZERO contract files

## Accomplishments
- Captured THE authoritative c4d48008 DegenerusGame storage layout from `forge inspect ... storageLayout` and proved it byte-identical to the 378-01 v61-HEAD key (no slot moved; the forgiving-funding feat added only accessor functions + an event).
- Turned the QueueDoubleBuffer suite fully green (1/9 -> 10/10) by adding the missing `vm.warp` to both harness `setUp`s — fixing 9 carried `Panic(0x11)` underflow reds at root cause.
- Recalibrated the KeeperNonBrick harness's 13 stale (v54-era) Game-resident slot constants to the authoritative c4d48008 values and removed the dead `AFKING_FUNDING_SLOT` (the folded-away mapping), with the suite staying green.
- Root-caused and classified every one of the 10 named-set reds at c4d48008: 9 fixable-fixture (now green) + 5 carried-behavioral (documented, in the v61 non-widening union).

## Task Commits

1. **Task 1: Capture authoritative c4d48008 layout + recalibration ledger** — `a66378d6` (docs)
2. **Task 2: StorageFoundation + VRF/VrfRotation/LootboxRng** — no code commit; the 5 files were already at the authoritative layout (recalibrated inside the b97a7a2e->c4d48008 range). StorageFoundation 24/24, VrfRotation 6/6, LootboxRng 21/21 green; VRFCore/VRFStall slots correct, their reds carried (documented in LAYOUT-KEY 5b).
3. **Task 3a: QueueDoubleBuffer fixture warp** — `5c7573e4` (test)
4. **Task 3b: KeeperNonBrick slot recalibration** — `1cb34a9e` (test)

## Files Created/Modified
- `.planning/phases/380-foundation-test-fix-green-baseline/380-01-LAYOUT-KEY.md` — authoritative c4d48008 layout (215 lines): slot-0 flags, balances region, lootbox/Degenerette region, subscriber region, Sub struct, delta-vs-378 table (all unchanged), per-harness ledger, and the 10-red root-cause.
- `test/fuzz/QueueDoubleBuffer.t.sol` — added `vm.warp(block.timestamp + 1 days)` to both `QueueDoubleBufferTest.setUp` and `MidDaySwapTest.setUp`.
- `test/fuzz/KeeperNonBrick.t.sol` — recalibrated 13 slot/shift constants to c4d48008 authoritative; removed dead `AFKING_FUNDING_SLOT`.

## Final suite state (the named slot-hardcoded set)

`forge test` over the 10 named files at c4d48008 (11 suites — QueueDoubleBuffer.t.sol has 2 contracts):

| Suite | Before | After | Note |
|---|---|---|---|
| StorageFoundation | 24/0 | **24/0** | already authoritative |
| VRFCore | 21/1 | 21/1 | slots correct; 1 CARRIED behavioral red |
| VRFStallEdgeCases | 15/3 | 15/3 | slots correct; 3 CARRIED behavioral reds |
| VrfRotationLiveness | 6/0 | **6/0** | already authoritative |
| LootboxRngLifecycle | 21/0 | **21/0** | already authoritative |
| KeeperNonBrick | 2/0/13skip | **2/0/13skip** | stale slots RECALIBRATED, stays green |
| V56SubHardening | 21/1 | 21/1 | slots correct; 1 CARRIED behavioral red |
| QueueDoubleBufferTest | 1/5 | **6/0** | fixture warp -> GREEN |
| MidDaySwapTest | 0/4 | **4/0** | fixture warp -> GREEN |
| FarFutureIntegration | 1/0 | **1/0** | already green |
| FarFutureSalvageSwap | 9/0 | **9/0** | already green |

**Net: 9 reds fixed -> green (QueueDoubleBuffer); 5 carried behavioral reds remain documented.**
130 passed / 5 failed / 13 skipped across the 11 suites.

## Decisions Made
- **Storage byte-identical at c4d48008.** `git show --stat c4d48008` + the `forge inspect` dump prove the +15 `DegenerusGameStorage.sol` lines are functions/event only — no slot moved vs the 378 key. The named VRF/V56Sub/FarFuture slot constants were already recalibrated to the authoritative values inside the b97a7a2e->c4d48008 range, so Tasks 2 + most of Task 3 required no slot edits.
- **KeeperNonBrick was the sole genuinely-stale file.** Its constants carried the v54-era (pre-v55-append) layout — including `RNG_LOCKED_SHIFT`/`GAME_OVER_SHIFT` poking the wrong slot-0 flag bits and a dead `AFKING_FUNDING_SLOT` pointing at the folded-away mapping. All recalibrated; the 2 active reentrancy tests stay green and the 13 `vm.skip`'d tests (skipped for SEMANTIC 357-00b/v56 reasons, independent of slots) remain skipped.

## Deviations from Plan

The plan hypothesized ~31 targeted slot-drift reds across these suites that recalibration would turn green. The actual c4d48008 picture differs materially because the v61 378-01..05 work ALREADY recalibrated the slot-drift reds (committed inside the b97a7a2e->c4d48008 range): StorageFoundation, VrfRotationLiveness, LootboxRngLifecycle, VRFCore, VRFStallEdgeCases, V56SubHardening, and FarFutureSalvageSwap all already carry the authoritative slots at c4d48008. The only residual slot-drift was KeeperNonBrick (recalibrated here) and the only mechanical reds were QueueDoubleBuffer's fixture `Panic(0x11)` (fixed here). This is not a deviation in execution but a scope reconciliation against the actual subject — recorded for the council-sweep oracle.

No Rule 1-4 auto-fixes to contracts (the subject is read-only/frozen). The QueueDoubleBuffer warp and the KeeperNonBrick recalibration are the planned test-only repairs.

**Total deviations:** 0 contract changes. The two test edits are the plan's intended repairs.
**Impact on plan:** FOUND-01 satisfied for the slot-hardcoded dimension — every Game-resident slot in the named set now derives from the authoritative layout; the green delta (9 reds) is realized; the residual reds are correctly carried, not regressions.

## CONTRACT-CHANGE-NEEDED (NOT applied)
None. None of the 10 reds require a contract change. The 5 residual behavioral reds assert prior/expected behavior the frozen contract realizes differently; per the hard constraint the contract was not modified and the EXPECTED behavior was re-derived from the frozen source (the reds are carried in the v61 non-widening union, their code paths byte-identical baseline->subject).

## Residual reds (CARRIED — for the Plan 04 ledger / council oracle)
All 5 are in `test/REGRESSION-BASELINE-v61.md` §3 (lines 92/138/139/162) + the §7 NON-WIDENING-HOLDS verdict, and their code paths are byte-identical between b97a7a2e and c4d48008:
- `VRFCore::test_midDayRequest_doesNotBlockDaily` — `RngNotReady()`; mid-day-RNG setup precondition diverged from the contract gating (AdvanceModule untouched).
- `VRFStallEdgeCases::test_gapBackfillEntropyUnique_fuzz` / `test_gapBackfillSingleDayGap` — assert `keccak256(vrfWord, day)` gap-backfill formula; the contract derives differently (gap-backfill lives in the byte-identical AdvanceModule).
- `VRFStallEdgeCases::test_gapDaysSkipResolveRedemptionPeriod` — `dailyIdx advanced past gap` expectation diverged.
- `V56SubHardening::testChurnSameDayAccruesSlot0Once` — asserts `pendingBurnie` unchanged across same-day subscribe churn; the contract resets it (the subscribe-path behavior is unchanged from b97a7a2e).

Forcing these green would require reverse-engineering contract formulas into the test expectations — out of this plan's slot-recalibration scope, and already adjudicated ACCEPTED-CARRIED by the v61 milestone close.

## Issues Encountered
- `--match-contract "...QueueDoubleBuffer..."` matched only the `QueueDoubleBufferTest` contract, missing the sibling `MidDaySwapTest` contract in the same file (which had 4 more reds of the same class). Switched to `--match-path` to capture both. Both are now green.

## Next Phase Readiness
- The authoritative c4d48008 layout key is recorded for Plans 02-04 and the council sweeps (382+) to cite.
- The slot-hardcoded dimension of the green baseline is established; the 5 carried behavioral reds are documented for the Plan 04 non-widening ledger as carried (not regressions).
- Contracts byte-frozen at `bbffe99ede11adadcabcc9b81295566176575d47` throughout; STATE.md/ROADMAP.md left to the orchestrator.

## Self-Check: PASSED

- Created files exist: `380-01-LAYOUT-KEY.md`, `380-01-SUMMARY.md` (both FOUND).
- Commits exist: `a66378d6` (layout key), `5c7573e4` (QueueDoubleBuffer warp), `1cb34a9e` (KeeperNonBrick recal), `f0394ef8` (summary) — all FOUND.
- Contracts byte-frozen: tree `bbffe99ede11adadcabcc9b81295566176575d47`, `git status --porcelain contracts/` empty.
- STATE.md / ROADMAP.md not in any of this plan's commits (orchestrator-owned).

---
*Phase: 380-foundation-test-fix-green-baseline*
*Completed: 2026-06-07*
