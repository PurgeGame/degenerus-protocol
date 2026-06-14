---
phase: 388-foundation-subject-freeze-green-baseline
plan: 01
subsystem: testing
tags: [storage-layout, forge-inspect, slot-recalibration, regression-oracle, vm.store, packing]

# Dependency graph
requires:
  - phase: v62.0-380-foundation-test-fix-green-baseline
    provides: the c4d48008 layout key (the per-harness reconciliation template + the StorageFoundation canary)
provides:
  - Authoritative a8b702a7 storage layout for the 4 post-v62-reshuffled contracts (DegenerusGame tail, StakedDegenerusStonk, BurnieCoinflip, DegenerusAdmin), captured verbatim from forge inspect
  - Per-harness slot-poke reconciliation ledger (every moved-field poke confirmed correct against the inspected layout)
  - StorageFoundation canary extended to pin the levelDgnrsPacked@26 consolidated tail pack
affects: [388-02, 388-03, 389, 390, 391, 392, 393, 394]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tail-pack canary: vm.store a sentinel into the keccak-derived mapping element of a hardcoded slot, read both packed halves back through the contract's own getter, assert the split — catches a future re-pack that moves the field"

key-files:
  created:
    - .planning/phases/388-foundation-subject-freeze-green-baseline/388-01-LAYOUT-KEY.md
  modified:
    - test/fuzz/StorageFoundation.t.sol

key-decisions:
  - "Verify-confirm-and-record (not mass-repair): the full forge suite runs green at the subject, so every moved-field slot poke was checked literal-by-literal against forge inspect and confirmed correct — no slot literal needed re-derivation"
  - "Pinned levelDgnrsPacked@26 (an alloc/claimed two-half tail pack) as the canary's new tail assertion, reading through the contract's _getLevelDgnrs getter so the assertion breaks on a real re-pack, not on a test-side encoding choice"

patterns-established:
  - "Region-dependent shift verification: never assume a uniform -1; capture each of the 4 contracts' authoritative slots from forge inspect and diff field-by-field vs the prior key"

requirements-completed: [FND-02]

# Metrics
duration: 18min
completed: 2026-06-14
---

# Phase 388 Plan 01: Authoritative a8b702a7 Storage Layout + Slot-Poke Reconciliation Summary

**Re-derived the byte-frozen a8b702a7 storage layout for the 4 post-v62-reshuffled contracts from `forge inspect storageLayout`, reconciled every slot-hardcoded harness poke against it (all confirmed correct), and pinned the levelDgnrsPacked@26 tail pack in the StorageFoundation canary.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-06-14T21:03Z
- **Completed:** 2026-06-14
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- Captured the authoritative a8b702a7 layout for DegenerusGame (tail packs levelDgnrsPacked@26, deityBoonPacked@36, lootboxEvCapPacked@40, decBurn@41, decClaimRounds@43 [1-slot u96/u128/u32], decBucketOffsetPacked@44, terminalDecBucketBurnTotal@49, bingoFirsts@53; max slot 59), StakedDegenerusStonk (slot-0 pack `_totalSupply`u128/`_pendingRedemptionEthValue`u96/`_pendingResolveDay`u24 + poolBalances u128[5]@2), BurnieCoinflip (coinflipStakePacked@0, coinflipDayResultPacked@1, sdgnrsAutoRebuyArmed@4-off23), DegenerusAdmin (voterRecords@5, feedVoterRecords@10).
- Confirmed the slot-0 roots (off 24/26/27) + balancesPacked@7 + prizePoolsPacked@2 + prizePoolPendingPacked@11 are UNCHANGED vs the v62 380-01 key, and flagged every tail row the post-v62 packing moved with a delta column.
- Built a per-harness reconciliation ledger covering 13 slot-poke harnesses (~20 poke sites) — every moved-field poke confirmed correct @ its inspected slot; ZERO re-derivations needed.
- Extended the StorageFoundation canary with `testLevelDgnrsPackedTailSlot` (suite 25/25 green).

## Task Commits

1. **Task 1: Capture the authoritative a8b702a7 storage layout (4 reshuffled contracts)** - `2bcb4d3e` (docs)
2. **Task 2: Pin levelDgnrsPacked tail pack in StorageFoundation canary** - `4e7223f5` (test)

**Plan metadata:** (this SUMMARY + STATE.md + ROADMAP.md commit follows)

## Files Created/Modified
- `.planning/phases/388-foundation-subject-freeze-green-baseline/388-01-LAYOUT-KEY.md` - authoritative 4-contract layout + delta vs v62 key + per-harness reconciliation ledger
- `test/fuzz/StorageFoundation.t.sol` - exposed `_getLevelDgnrs` on StorageHarness + `testLevelDgnrsPackedTailSlot` canary assertion pinning slot 26

## Decisions Made
- **Verify-confirm-and-record** rather than mass repair: because the full forge suite is green at the subject, the slot literals were already correct; the task value is the authoritative record + the per-harness proof that each poke hits the right field under the new layout, plus the canary that locks in a tail pack.
- **Pinned `levelDgnrsPacked@26`** (chosen over `lootboxEvCapPacked@40`) because the storage base exposes a clean `_getLevelDgnrs` getter that unpacks both halves, letting the canary read back through the contract rather than re-deriving the encoding test-side.
- **Reconciliation insight:** `SLOT_DEC_BURN=41` in DecimatorBountyRegression targets `decBurn` (slot 41), NOT the adjacent `decBucketBurnTotal` (slot 42) — distinct fields; the literal is correct.

## Deviations from Plan

None - plan executed exactly as written. No contract-source edit was required or made; the subject stayed byte-frozen throughout.

## Issues Encountered
None. The subject is byte-frozen (`git diff a8b702a7 -- contract-source` empty before/after both tasks); `git status --porcelain` on the subject tree empty (ContractAddresses.sol not regenerated — hardhat never invoked). Note: HEAD is `aeb7c0b5` (docs(388) commits sit on top of the subject), but the subject tree is verified byte-identical to `a8b702a7`.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The green baseline (Plan 03) is now trustworthy on the slot-poke front: every moved-field harness poke is proven to hit the right field, and the canary catches a future tail drift.
- FND-02 satisfied: authoritative `forge inspect` layout captured + every slot-hardcoded poke reconciled + StorageFoundation canary passes (25/25) at the subject.
- Ready for 388-02 / 388-03 (the green-baseline oracle) and the 389+ sweeps that reproduce findings against these harnesses.

## Self-Check: PASSED
- FOUND: `.planning/phases/388-foundation-subject-freeze-green-baseline/388-01-LAYOUT-KEY.md`
- FOUND: `test/fuzz/StorageFoundation.t.sol`
- FOUND commit: `2bcb4d3e` (Task 1)
- FOUND commit: `4e7223f5` (Task 2)

---
*Phase: 388-foundation-subject-freeze-green-baseline*
*Completed: 2026-06-14*
