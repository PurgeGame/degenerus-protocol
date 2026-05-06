---
phase: 254-gnrus-allowlist-storage-admin-op-storage-repack
plan: 03
subsystem: contracts/governance
tags: [solidity, gnrus, charity-allowlist, view-helpers, paired-arrays]

requires:
  - phase: 254-01
    provides: storage skeleton + InvalidSlot error + MAX_ACTIVE_SLOTS constant
  - phase: 254-02
    provides: _popcount32 helper
provides:
  - getCharity(uint8) returns (address) — single-slot read
  - getActiveSlots() returns (uint8[], address[]) — paired-array enumerator
  - getPendingEdits() returns (uint8[], address[]) — paired-array enumerator with pending-remove sentinel
  - activeCount() returns (uint8) — popcount(currentActiveBitmap)
  - activeCountAfterFlush() returns (uint8) — popcount of would-be future bitmap
  - _flushedBitmap() private view helper (consumed by activeCountAfterFlush; reusable by Phase 255 pickCharity flush logic)
affects: [255-pickcharity-flush-reuse, 256-test-coverage, 257-audit]

tech-stack:
  added: []
  patterns: [paired-array-enumerator-over-bitmap]

key-files:
  created: []
  modified: [contracts/GNRUS.sol]

key-decisions:
  - "_flushedBitmap is a separate helper (not an overload of _futureBitmapAfter) — cleaner than passing a sentinel arg for the no-proposed-write case"
  - "Recipients[i] == address(0) in getPendingEdits is meaningful — signals pending-remove per D-254-PENDING-01 sentinel semantics"

patterns-established:
  - "Paired-array enumerator over bitmap: length = _popcount32(bitmap); iterate slots 0..MAX_ACTIVE_SLOTS-1; push (slot, value) for each set bit"

requirements-completed: [ALW-04]

duration: combined-with-plans-01-02
completed: 2026-05-06
---

# Phase 254-03: v33.0 view helpers — Summary

**Five v33.0 view helpers implemented (`getCharity`, `getActiveSlots`, `getPendingEdits`, `activeCount`, `activeCountAfterFlush`); `_flushedBitmap` private helper added for activeCountAfterFlush and reusable by Phase 255 pickCharity flush logic.**

## Performance

- **Duration:** ~3 min (Plan 03 portion of bundled execution)
- **Started:** 2026-05-06
- **Completed:** 2026-05-06
- **Tasks:** 1 of 1
- **Files modified:** 1 (contracts/GNRUS.sol)

## Accomplishments

- Implemented all 5 view helpers per ALW-04 + D-254-VIEW-01 + D-254-COUNT-01
- Implemented `_flushedBitmap()` private helper (positioned in `// GOVERNANCE -- ADMIN OPS` section under `_futureBitmapAfter` for helper co-location)
- Added `// VIEW HELPERS` section banner
- `npx hardhat compile` exits 0

## Files Modified

- `contracts/GNRUS.sol` — added `// VIEW HELPERS` section with 5 external view functions; added `_flushedBitmap` private helper

## Decisions Made

None beyond what's locked in the plan and 254-CONTEXT.md.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Phase 254 Close Attestation

All 5 ROADMAP success criteria functionally satisfied:

| # | Criterion | Satisfied by |
|---|-----------|--------------|
| 1 | `setCharity` exposed + 5 view helpers | Plans 02 + 03 |
| 2 | Vault-owner gating + InvalidSlot + ~~RecipientIsContract~~ + SlotAlreadyEmpty | Plan 02 (RecipientIsContract removed per Plan 02 deviation 1) |
| 3 | Locked-slot rule before branch dispatch | Plan 02 (locked-slot guard at step 4) |
| 4 | Two-branch + pending-overwrite + CapExceeded | Plan 02 |
| 5 | Dead-state functionally removed + storage repacked | Plan 01 |

## Storage Layout (post-Phase-254 close, on-disk cross-check)

Confirmed identical to the diagram in 254-01-SUMMARY.md. 26 storage slots total. Hot-pack slot 2 carries 12 bytes (currentLevel + finalized + currentActiveBitmap + pendingEditSet) with 20 bytes free for future v34.0+ expansion.

## Theoretical Worst-Case View Helper Gas

| Helper | Worst-case (cold, 20 active/pending) | Phase 256 measurement target |
|--------|--------------------------------------|-------------------------------|
| `getCharity(slot)` | ~2.5k | < 5k |
| `activeCount()` | ~2.5k | < 5k |
| `activeCountAfterFlush()` | ~45k (20 cold pendingEdit SLOADs + popcount) | < 50k |
| `getActiveSlots()` at 20 active | ~50k (20 cold currentSlate SLOADs + array allocation) | < 55k |
| `getPendingEdits()` at 20 pending | ~50k | < 55k |

## Next Phase Readiness

- Phase 255 `pickCharity` can reuse `_flushedBitmap()` for its flush-then-iterate logic (the helper composes the future bitmap; pickCharity then walks the slate against the future bitmap to pick a winner and clears the pending state).
- Phase 256 test coverage ready to plan against the locked v33.0 surface (setCharity + 5 view helpers + storage skeleton).
- Phase 257 audit inputs: storage layout diagram + revert order + theoretical gas tables all pre-positioned in 254-01/02/03 SUMMARYs for delta extraction.

---
*Phase: 254-gnrus-allowlist-storage-admin-op-storage-repack*
*Completed: 2026-05-06*
