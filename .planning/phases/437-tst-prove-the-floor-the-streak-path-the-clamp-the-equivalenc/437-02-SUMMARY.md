---
phase: 437-tst-prove-the-floor-the-streak-path-the-clamp-the-equivalenc
plan: 02
subsystem: testing
tags: [foundry, storage-packing, saturating-clamp, afking-streak, pendingFlip, vm-store, source-grep-oracle]

# Dependency graph
requires:
  - phase: 436-impl-batched-contract-diff-points-streak-pack-contract-commi
    provides: "the v69 byte-frozen subject (contracts/ tree 2eeed005 @ c4b09267): subStreakLatch uint8->uint16, finalizeAfking floor-hack deleted, pendingFlip uint32->uint24 with the clamp re-pinned to type(uint24).max, net-zero 72-bit accumulator repack"
provides:
  - "StreakSnapshotAndPendingFlipClamp.t.sol: pre-streak >255 snapshot-exactness proof, <=255 regression-safety, the kept type(uint16).max latch clamp saturation, and the pendingFlip type(uint24).max saturating clamp (clamps, never wraps) + settle round-trip"
  - "testGas04 source-grep packing golden updated to the post-PACK field widths (uint24 pendingFlip / uint16 subStreakLatch); Sub byte-sum stays exactly 32"
affects: [438-reaudit, mutation-campaign, storage-layout-golden-recapture]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "post-PACK Sub slot access via raw vm.store/vm.load at the re-derived offsets (affiliateBase u32 off23, pendingFlip u24 off27, subStreakLatch u16 off30)"
    - "saturation proof shape: explicit `read != wrapValue` assertion so a wrap-to-small-value regression fails (not just `read == ceiling`)"

key-files:
  created:
    - test/fuzz/StreakSnapshotAndPendingFlipClamp.t.sol
  modified:
    - test/gas/KeeperLeversAndPacking.t.sol

key-decisions:
  - "Both Task 1 and Task 2 share one test contract (the plan files_modified lists one new .sol for both); committed as one test(...) commit since the file is green for both proofs at once."
  - "The finalize hand-back is asserted against the LIVE earned run streak read just before cancel (base + funded delivered days), not the bare snapshot — the delivered day advances the covered span by 1, so the earned value is snapshot+1. For a >255 base this is still >255, which proves no truncation through both the snapshot and the finalize."
  - "recordAfkingSecondary is QUESTS-gated; the live +1 bump is driven by vm.prank as ContractAddresses.QUESTS rather than via the full quest flow."

patterns-established:
  - "Saturation proofs assert read != wrapValue (the small value a wrap would produce), pinning the clamp not just the ceiling."

requirements-completed: [TST-02]

# Metrics
duration: 6min
completed: 2026-06-19
---

# Phase 437 Plan 02: Prove the Streak Path, the Latch Clamp & the pendingFlip Clamp Summary

**uint16 latch snapshots a carried-in manual streak >255 exactly (old uint8/255 truncation + finalize floor-hack gone), the kept latch clamp saturates the +1 bump at 65535, and pendingFlip saturates at type(uint24).max = 16,777,215 never wrapping — plus the testGas04 packing golden repointed to the post-PACK widths.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-06-19T06:36:50Z
- **Completed:** 2026-06-19T06:43:05Z
- **Tasks:** 3 (2 share one test file)
- **Files modified:** 2 (1 created, 1 edited)

## Accomplishments
- Proved the v69 single-integer streak path: a manual quest streak above 255 (300 / 1000 / 60000) carried into an afking run is snapshotted EXACTLY into the widened uint16 latch (the run-start snapshot reads the true value, never 255), and on finalize the manual streak is handed back exactly the earned run streak — no floor-hack restore, no uint8 truncation.
- Proved <=255 carried-in streaks (200 / 255 / 1) stay byte-identical (the regression-safety arm; the clamp never bound for these).
- Proved the KEPT `_setStreakBase` clamp saturates the live `recordAfkingSecondary` +1 bump at `type(uint16).max` (65535, never wraps 65536 -> 0), with a one-below case showing it is a true clamp not a stuck value, and a 255->256 case showing the latch carries past the old uint8 ceiling.
- Proved the `pendingFlip` uint24 saturating clamp at exactly 16,777,215: one-below + accrue clamps to the ceiling, at-ceiling stays, over-ceiling reads the ceiling and explicitly NOT the wrap value k=49 (so a wrap-to-small regression fails); settle/claim round-trips the clamped value (credits 16,777,215 x 1e18, zeroes the field) and leaves affiliateBase untouched.
- Repaired the previously-red `testGas04PackingAndNoNewHotPathStorageSourcePresence` source-grep golden: the two greps now read `uint24 pendingFlip;` (width 3) and `uint16 subStreakLatch;` (width 2); the Sub byte-sum stays exactly 32 (one full slot, 0 free); the stale v55 doc-comment shape was replaced with the post-PACK accumulator description.

## Task Commits

1. **Task 1 + Task 2: pre-streak >255 snapshot exactness + pendingFlip uint24 saturation** - `a0bd9c2a` (test)
2. **Task 3: testGas04 packing golden -> post-PACK field widths** - `447bd5aa` (test)

_TDD note: the subject behaviour already shipped at `c4b09267`, so the proofs are GREEN against the frozen subject on first run; the fails-without arms (the old uint8/255 truncation, the wrap value k) are documented in-test and asserted so the old shapes would fail._

## Files Created/Modified
- `test/fuzz/StreakSnapshotAndPendingFlipClamp.t.sol` (created) - 5 tests: the >255 snapshot exactness, the <=255 byte-identical regression arm, the uint16-max latch clamp saturation, the uint24 pendingFlip saturation (one-below/at/over-ceiling with `read != k`), and the settle round-trip under clamp. Uses the post-PACK Sub offsets (pendingFlip u24 off27, subStreakLatch u16 off30) re-derived from the v69 layout, reusing the 437-01 afking-run drive pattern.
- `test/gas/KeeperLeversAndPacking.t.sol` (edited) - `testGas04...` grep widths repointed (uint32 pendingFlip->uint24, uint8 subStreakLatch->uint16); the test's preceding doc-comment + the contract-level Sub-layout doc-clause updated to the post-PACK 13-field/32-byte shape. No other test touched; no `forge inspect storageLayout` recapture added (that is 438 REAUDIT-01).

## Decisions Made
- Tasks 1 and 2 write the same file (the plan's `files_modified` lists one new `.sol` for both, and the file is green for both proofs at once), so they are one `test(...)` commit rather than two.
- The finalize property is asserted against the live earned run streak (read just before cancel) rather than the bare snapshot, because a delivered funded day advances the covered span by one — see Issues Encountered.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test correctness] Finalize hand-back asserts the earned run streak, not the bare snapshot**
- **Found during:** Task 1 (snapshot/finalize proof)
- **Issue:** The initial draft asserted the finalize hands back exactly the carried-in `streakValue`. The shipped `finalizeAfking` hands back the EARNED run streak (`base + funded delivered days`); `_deliverDay` advances the covered span by 1, so the value is `streakValue + 1` (observed 301 != 300, 201 != 200). This is correct contract behaviour, not a bug — the run genuinely earned a day.
- **Fix:** Read the live afking streak (`_streakBaseOf + (covered - afkingStartDay)`) just before the cancel and assert the finalize hand-back equals it exactly, plus `earned >= streakValue`. For a >255 base the earned value is still >255, so the no-truncation claim is proven through both the snapshot and the finalize.
- **Files modified:** test/fuzz/StreakSnapshotAndPendingFlipClamp.t.sol
- **Verification:** all 5 tests pass.
- **Committed in:** a0bd9c2a (Task 1/2 commit)

**2. [Rule 3 - Blocking] recordAfkingSecondary is QUESTS-gated**
- **Found during:** Task 1 (latch clamp proof)
- **Issue:** Calling `game.recordAfkingSecondary(p)` directly reverted `NotApproved()` — it requires `msg.sender == ContractAddresses.QUESTS`.
- **Fix:** `vm.prank(ContractAddresses.QUESTS)` before each `recordAfkingSecondary` call (added the QUESTS address as a local constant with a lean comment).
- **Files modified:** test/fuzz/StreakSnapshotAndPendingFlipClamp.t.sol
- **Verification:** the clamp test passes.
- **Committed in:** a0bd9c2a (Task 1/2 commit)

**3. [Rule 1 - Stale comment] Contract-level Sub-layout doc-clause cited the v55 8-field/29-byte shape**
- **Found during:** Task 3 (gas golden)
- **Issue:** Beyond the testGas04 preceding doc-comment, the file's contract-level `@notice` block (line ~20) described the Sub layout gate as "8 fields summing to 29 bytes", contradicting the gate I had just corrected (13 fields, 32 bytes).
- **Fix:** Updated that single clause to "13 fields summing to 32 bytes, one full slot 0 free" (lean-comment rule: describe what IS). No logic touched; the test stayed green (comment-only).
- **Files modified:** test/gas/KeeperLeversAndPacking.t.sol
- **Verification:** testGas04 still green; no stale shape strings remain.
- **Committed in:** 447bd5aa (Task 3 commit)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 test/comment correctness, 1 Rule 3 blocking-gate)
**Impact on plan:** All within the test files; no scope creep, no contract change. The finalize-property correction strengthens the proof (it now asserts against the contract's actual earned value while still proving no truncation for >255).

## Issues Encountered
- The afking finalize hands back the earned run streak (snapshot + funded delivered days), not the bare snapshot — resolved by asserting against the live earned value read pre-cancel (deviation 1).
- Pre-existing solc warnings (shadowed `level` declaration, a mutability advisory) are out of scope and unchanged.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- TST-02 is proven against the frozen subject `c4b09267` (contracts/ tree `2eeed005`).
- Both gates green: `forge test --match-contract StreakSnapshotAndPendingFlipClampTest` (5/5) and `forge test --match-test testGas04PackingAndNoNewHotPathStorageSourcePresence` (1/1).
- Deferred to 438 REAUDIT-01 (NOT done here, by plan): the `forge inspect ... storageLayout` snapshot recapture. This plan updated only the SOURCE-GREP oracle.
- No `contracts/*.sol`, `.planning/STATE.md`, or `.planning/ROADMAP.md` modified (orchestrator owns the latter two).

## Self-Check: PASSED

- FOUND: test/fuzz/StreakSnapshotAndPendingFlipClamp.t.sol
- FOUND: 437-02-SUMMARY.md
- FOUND commits: a0bd9c2a (test), 447bd5aa (test), 08fc7c78 (docs)
- Both gates green: StreakSnapshotAndPendingFlipClampTest 5/5, testGas04 1/1
- contracts/ byte-frozen vs c4b09267 (empty diff); my commits touched only the two test files + this SUMMARY (STATE.md / ROADMAP.md untouched by this plan)

---
*Phase: 437-tst-prove-the-floor-the-streak-path-the-clamp-the-equivalenc*
*Completed: 2026-06-19*
