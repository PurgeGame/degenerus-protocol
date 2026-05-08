---
phase: 254-gnrus-allowlist-storage-admin-op-storage-repack
plan: 02
subsystem: contracts/governance
tags: [solidity, gnrus, charity-allowlist, admin-op, popcount, bitmap]

requires:
  - phase: 254-01
    provides: v33.0 storage skeleton + new errors + new events
provides:
  - setCharity(uint8 slot, address recipient) admin entry point (vault-owner-gated)
  - _futureBitmapAfter private view helper (cap-check support)
  - _popcount32 private pure helper (Hamming-weight inline-asm)
affects: [254-03-view-helpers, 256-test-coverage, 257-audit]

tech-stack:
  added: []
  patterns: [inline-asm-popcount, two-branch-instant-or-queue-dispatch, locked-slot-guard-before-branch-dispatch]

key-files:
  created: []
  modified: [contracts/GNRUS.sol]

key-decisions:
  - "_futureBitmapAfter computes the would-be future bitmap by treating the proposed write as a pending entry, then iterating (pendingEditSet ∪ {slot})"
  - "Cancel-pending-via-zero is a documented mechanism: setCharity(slot, 0) on empty current with pending set clears pendingEdit[slot] and the bitmap bit, emitting CharityQueued(slot, 0)"
  - "DEVIATION: RecipientIsContract guard removed at user diff-review per protocol-design call — multisig/DAO charity recipients should be permitted"

patterns-established:
  - "Single-monolithic setCharity (no _applyInstant/_queueEdit subhelpers) — clearer revert ordering, explicit branch logic"
  - "Locked-slot guard placed BEFORE branch dispatch — no code path can mutate locked slots through queue or instant-apply"

requirements-completed: [ALW-01, ALW-02, ALW-03]

duration: combined-with-plans-01-03
completed: 2026-05-06
---

# Phase 254-02: setCharity admin op + helpers — Summary

**Single vault-owner-gated `setCharity(uint8, address)` admin entry point implemented with two-branch dispatch (instant-apply / queue), locked-slot guard before branch dispatch, cap check via popcount of would-be future bitmap, and event-driven indexer signals.**

## Performance

- **Duration:** ~5 min (Plan 02 portion of bundled execution)
- **Started:** 2026-05-06
- **Completed:** 2026-05-06
- **Tasks:** 1 of 1
- **Files modified:** 1 (contracts/GNRUS.sol)

## Accomplishments

- Implemented `setCharity(uint8 slot, address recipient) external` per ALW-03 (with deviation noted below)
- Implemented `_futureBitmapAfter(uint8 slot, address recipient, uint32 slotMask) private view` cap-check helper
- Implemented `_popcount32(uint32 x) private pure` inline-asm Hamming-weight helper
- Added `// GOVERNANCE -- ADMIN OPS` section banner
- `npx hardhat compile` exits 0

## Final Revert Order in `setCharity` (post-deviation)

```
Unauthorized → InvalidSlot → SlotLocked → SlotAlreadyEmpty → CapExceeded × 2
```

(7 revert sites; CapExceeded appears in both branches.)

## Files Modified

- `contracts/GNRUS.sol` — added `// GOVERNANCE -- ADMIN OPS` section with `setCharity` + 2 private helpers; removed `error RecipientIsContract()` declaration (orphaned by the deviation below)

## Decisions Made

- `_futureBitmapAfter` parameter list dropped the unused `address current` from the plan's pseudocode — the helper iterates `pSet = pendingEditSet | slotMask` and only consults `recipient` directly when `i == slot`. Functionally identical; cleaner signature.
- Cancel-pending-via-zero path: when `current == 0 && recipient == 0 && pendingEditSet[slot] is set`, the call clears `pendingEdit[slot]` and the bitmap bit, then emits `CharityQueued(slot, 0)`. This is the cancel mechanism for queued adds (no separate cancel API per D-254-PENDING-01).

## Deviations from Plan

### Deviation 1: `RecipientIsContract` EOA-only guard removed

- **Found during:** User diff-review at Plan 02 acceptance gate
- **Issue:** Plan + REQUIREMENTS.md ALW-03 specified `if (recipient != address(0) && recipient.code.length != 0) revert RecipientIsContract();` as step 3 of the revert order. User overrode this requirement at review time.
- **Rationale:** Many charity recipients legitimately use multisig wallets (Gnosis Safe) or DAO treasuries — both are contracts. EOA-only restriction would exclude these valid use cases.
- **Fix:** Removed the guard line from `setCharity` AND removed `error RecipientIsContract()` declaration (orphaned per `feedback_no_dead_guards.md` — was only consumed by this guard in v33).
- **Files modified:** `contracts/GNRUS.sol`
- **Verification:** `grep -c "RecipientIsContract"` returns 0; `grep -c "recipient.code.length"` returns 0; revert order grep produces the new sequence.
- **Action item for downstream phases:**
  - **REQUIREMENTS.md ALW-03:** revert-order spec needs updating to drop the RecipientIsContract step (skip-renumber from 3 to elide).
  - **Phase 256:** drop the RecipientIsContract sad-path test from the planned setCharity revert-path coverage.
  - **Phase 257 audit:** flag the contract-recipient acceptance — recipients can be malicious/upgradeable contracts; trust model now relies on the vault-owner curating only safe recipient addresses. Acceptable trade for multisig support but should be documented in `audit/FINDINGS-v33.0.md` as a trust-asymmetry note.

### Deviation 2: `_futureBitmapAfter` parameter cleanup (cosmetic)

- **Found during:** Plan 02 implementation
- **Issue:** Plan pseudocode declared an `address current` parameter that was never read inside the helper body.
- **Fix:** Dropped the unused parameter. Helper signature is now `(uint8 slot, address recipient, uint32 slotMask)`.
- **Verification:** Compile clean; `grep -c "function _futureBitmapAfter("` still returns 1.

**Total deviations:** 2 (1 functional per user instruction, 1 cosmetic)
**Impact on plan:** Functional deviation requires REQUIREMENTS.md + Phase 256 test plan + Phase 257 audit updates as noted above. Cosmetic deviation has no impact.

## Issues Encountered

None.

## Theoretical Worst-Case Gas (for Phase 256 measurement budget)

`setCharity` ≈ 95k gas all-cold (20 pending-edit bits set + instant-apply branch + cap-check via `_futureBitmapAfter` iteration of 20 cold `pendingEdit[i]` SLOADs). See 254-02-PLAN.md `<gas_table>` for full decomposition. Phase 256 measurement should target this ceiling.

## Next Phase Readiness

Plan 03 ready to consume `_popcount32` (used by 4 of the 5 view helpers). Phase 255 `pickCharity` flush logic ready to mirror `_futureBitmapAfter`'s iterate-pending-and-apply pattern.

---
*Phase: 254-gnrus-allowlist-storage-admin-op-storage-repack*
*Completed: 2026-05-06*
