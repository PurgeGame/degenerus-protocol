---
phase: 254-gnrus-allowlist-storage-admin-op-storage-repack
plan: 01
subsystem: contracts/governance
tags: [solidity, storage-layout, gnrus, charity-allowlist]

requires:
  - phase: 253-and-prior
    provides: v32.0 GNRUS baseline at HEAD acd88512
provides:
  - v33.0 storage skeleton (currentSlate, pendingEdit, currentActiveBitmap, pendingEditSet)
  - hot-pack slot 2 (currentLevel + finalized + currentActiveBitmap + pendingEditSet)
  - hasVoted redeclared with uint8 inner key
  - 4 new errors (InvalidSlot, SlotAlreadyEmpty, SlotLocked, CapExceeded)
  - 2 new events (CharityApplied, CharityQueued)
  - 2 new constants (LOCKED_SLOTS, MAX_ACTIVE_SLOTS)
  - functional removal of v32 propose/vote/pickCharity/getProposal/getLevelProposals + 7 propose-exclusive errors + 3 governance constants + 9 governance state items
affects: [255-vote-pickcharity-rewrite, 256-test-coverage, 257-audit]

tech-stack:
  added: []
  patterns: [bitmap-as-active-count-source-of-truth, hot-pack-slot]

key-files:
  created: []
  modified: [contracts/GNRUS.sol]

key-decisions:
  - "ProposalCreated/Voted/LevelResolved event TYPE declarations intentionally LEFT INTACT — Phase 255 CLEAN-02 owns deletion + signature rewrite per REQUIREMENTS.md"
  - "currentSlate declared private — auto-getter would clash with the named getCharity(uint8) view (Plan 03)"
  - "Hot-pack slot ordering: currentLevel (3) → finalized (1) → currentActiveBitmap (4) → pendingEditSet (4) = 12 bytes, 20 bytes free"

patterns-established:
  - "Bitmap as single source of truth for active count (D-254-COUNT-01) — drift impossible by construction"
  - "Sparse mapping + bitmap sentinel for pending edit queue (D-254-PENDING-01)"

requirements-completed: [CLEAN-01]

duration: combined-with-plans-02-03
completed: 2026-05-06
---

# Phase 254-01: Demolish v32 governance + lay v33.0 storage skeleton — Summary

**v32-shape proposal/vote/resolve governance state functionally removed from `contracts/GNRUS.sol`; v33.0 storage skeleton declared and ready for setCharity (Plan 02) + view helpers (Plan 03) consumption.**

## Performance

- **Duration:** ~5 min (Plan 01 portion of bundled execution)
- **Started:** 2026-05-06
- **Completed:** 2026-05-06
- **Tasks:** 1 of 1
- **Files modified:** 1 (contracts/GNRUS.sol)

## Accomplishments

- Demolished v32 governance: `Proposal` struct, 8 governance state mappings/counters, 5 governance functions (propose/vote/pickCharity/getProposal/getLevelProposals), 7 propose/vote-exclusive errors, 3 governance constants — all functionally removed (no commented-out residue per `feedback_no_history_in_comments.md`)
- Laid v33.0 storage skeleton: `currentSlate[20]` private, `pendingEdit` mapping, `currentActiveBitmap`, `pendingEditSet`, hot-pack slot at slot 2
- Redeclared `hasVoted` with `uint8` inner slot key (was `uint48` proposalId)
- Added 4 new errors, 2 new events, 2 new constants
- `npx hardhat compile` exits 0

## Storage Layout Diagram (post-Plan-01, on-disk)

| Slot | Field | Bytes | Notes |
|------|-------|-------|-------|
| 0 | `totalSupply` | 32 | UNCHANGED |
| 1 | `balanceOf` mapping root | 32 | UNCHANGED |
| 2 | `currentLevel` (3) + `finalized` (1) + `currentActiveBitmap` (4) + `pendingEditSet` (4) + 20 free | 32 | **hot-pack (D-254-REPACK-01)** |
| 3 | `levelResolved` mapping root | 32 | UNCHANGED (Phase 255 wires) |
| 4 | `hasVoted` mapping root (uint8 inner key) | 32 | **REDECLARED inner-key uint48 → uint8 (D-254-HASVOTED-01)** |
| 5–24 | `currentSlate[0]` … `currentSlate[19]` | 32 each | NEW (D-254-SLATE-01) |
| 25 | `pendingEdit` mapping root | 32 | NEW (D-254-PENDING-01) |

26 storage slots total. Net delta from v32 baseline: 9 slots deleted, 21 slots added (1 redeclared in-place, 20 new currentSlate entries, 1 new pendingEdit mapping root, hot-pack repacked in-place at slot 2).

## Files Modified

- `contracts/GNRUS.sol` — structural rewrite of governance state, errors, events, constants; v32 functions deleted

## Decisions Made

None beyond what's locked in 254-CONTEXT.md and 254-01-PLAN.md.

## Deviations from Plan

**1. Top-of-file NatSpec phrase update (cosmetic)** — Plan did not explicitly require this. Changed `@dev` line "the winning governance proposal's recipient receives 2%" → "the winning charity slot's recipient receives 2%" to match v33.0 mechanism (per `feedback_no_history_in_comments.md` — describes what IS). Functional behavior unaffected.

**2. `error RecipientIsContract()` removed downstream** — Plan 01 KEPT this error per the canonical KEEP list (it was held over for Plan 02 setCharity to consume). At Plan 02 review, the user instructed removing the EOA-only guard on `setCharity` (charities legitimately use multisigs/DAOs); the error declaration was removed alongside the check per `feedback_no_dead_guards.md`. End-state in this commit reflects the removal — see 254-02-SUMMARY.md for the full rationale.

## Issues Encountered

None.

## Next Phase Readiness

Plans 02 + 03 ready to consume the storage skeleton, errors, events, and constants. Phase 255 ready to consume `hasVoted[level][voter][slot]`, `currentSlate`, `pendingEdit`, `pendingEditSet`, `currentActiveBitmap` for `vote(uint8 slot)` + `pickCharity(uint24)` rewrite.

---
*Phase: 254-gnrus-allowlist-storage-admin-op-storage-repack*
*Completed: 2026-05-06*
