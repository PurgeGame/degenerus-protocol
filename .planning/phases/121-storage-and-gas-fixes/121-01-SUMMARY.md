---
phase: 121-storage-and-gas-fixes
plan: 01
subsystem: contracts
tags: [solidity, storage-optimization, gas-savings, natspec, delta-audit]

# Dependency graph
requires: []
provides:
  - "lastLootboxRngWord redundant storage variable deleted (saves ~20K gas/write x3 paths)"
  - "advanceBounty computed at payout time with bountyMultiplier pattern (stale-price fix)"
  - "BitPackingLib NatSpec corrected: bits 152-153 (was 152-154)"
  - "FIX-08 delta audit: all 5 RNG paths proven equivalent, storage layout safe, forge test green"
affects: [121-02, 121-03, 125-test-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "bountyMultiplier pattern: compute multiplier separately, apply at each payout site inline"
    - "View function testing: use lootboxRngWord(index) view instead of raw vm.load slot reads"

key-files:
  created: []
  modified:
    - "contracts/storage/DegenerusGameStorage.sol"
    - "contracts/modules/DegenerusGameAdvanceModule.sol"
    - "contracts/modules/DegenerusGameJackpotModule.sol"
    - "contracts/libraries/BitPackingLib.sol"
    - "test/fuzz/VRFStallEdgeCases.t.sol"

key-decisions:
  - "Full deletion of lastLootboxRngWord (not deprecation) per user decision D-01"
  - "Mid-day creditFlip uses 1x base bounty (no escalation applies to same-day paths)"
  - "SLOT_MID_DAY_PENDING updated from 56 to 55 to track storage layout shift"
  - "Stall backfill path identified as latent bug fix: mapping read is more correct than lastLootboxRngWord"

patterns-established:
  - "bountyMultiplier: declare before escalation block, apply inline at each payout call"
  - "Storage deletion safety: forge inspect + path enumeration + underflow check"

requirements-completed: [FIX-01, FIX-05, FIX-07, FIX-08]

# Metrics
duration: 13min
completed: 2026-03-26
---

# Phase 121 Plan 01: Storage & Gas Fixes Summary

**Deleted lastLootboxRngWord redundant storage (3 SSTOREs saved), rewrote advanceBounty to payout-time computation with bountyMultiplier pattern, corrected BitPackingLib NatSpec, and proved deletion safe via 5-path delta audit**

## Performance

- **Duration:** 13 min
- **Started:** 2026-03-26T02:31:37Z
- **Completed:** 2026-03-26T02:44:15Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Deleted lastLootboxRngWord storage variable and all 3 write sites, redirected 1 read site to lootboxRngWordByIndex mapping
- Rewrote advanceBounty from eager computation at function entry to inline payout-time computation using bountyMultiplier
- Corrected BitPackingLib NatSpec from "bits 152-154" to "bits 152-153" (zero bytecode change)
- Completed FIX-08 delta audit: storage layout verified via forge inspect, all 5 RNG paths proven equivalent, lootboxRngIndex underflow impossible, 369/369 forge tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete lastLootboxRngWord -- storage, writes, and read redirect (FIX-01)** - `ca2e43b2` (fix)
2. **Task 2: Rewrite advanceBounty to payout-time computation (FIX-07) + BitPackingLib NatSpec (FIX-05)** - `068057d9` (fix)
3. **Task 3: FIX-08 delta audit -- verification only** - No commit (verification-only task, no file changes)

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` - Deleted lastLootboxRngWord declaration (4 lines removed)
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Deleted 3 write sites, deleted eager advanceBounty, added bountyMultiplier pattern, inline payout computation at 3 creditFlip sites
- `contracts/modules/DegenerusGameJackpotModule.sol` - Redirected entropy read from lastLootboxRngWord to lootboxRngWordByIndex[lootboxRngIndex - 1]
- `contracts/libraries/BitPackingLib.sol` - NatSpec correction: "bits 152-154" to "bits 152-153"
- `test/fuzz/VRFStallEdgeCases.t.sol` - Replaced raw slot-55 vm.load reads with lootboxRngWord() view function, updated SLOT_MID_DAY_PENDING from 56 to 55, removed SLOT_LAST_LOOTBOX_RNG_WORD constant

## Decisions Made
- **Full deletion over deprecation:** User decision D-01 explicitly chose delete over deprecation comment. Safe because all modules are deployed fresh (not upgraded via proxy).
- **Mid-day 1x bounty:** The pre-escalation creditFlip at L174 uses `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / price` without bountyMultiplier because escalation applies only to new-day paths.
- **Stall backfill latent bug fix:** Path 3 (backfill loop) analysis revealed that lastLootboxRngWord held the word for the OLDEST backfilled index (last loop iteration), while processTicketBatch needs the CURRENT index word. The mapping read `lootboxRngWordByIndex[lootboxRngIndex - 1]` is more correct -- this deletion is a latent bug fix.
- **Storage slot shift documented:** midDayTicketRngPending shifted from slot 56 to 55; SLOT_MID_DAY_PENDING constant updated accordingly. All downstream mappings shifted by -1 (safe for fresh deploy).

## FIX-08 Delta Audit Results

### Part A: Storage Layout Verification
- `lastLootboxRngWord` confirmed absent from `forge inspect DegenerusGameStorage storage-layout`
- `midDayTicketRngPending` moved from slot 56 to slot 55 (expected compaction)
- `lootboxRngPendingBurnie` remains at slot 54
- All mappings (deityBoonDay at 56, deityBoonUsedMask at 57, etc.) shifted down by 1 -- safe for fresh deploy

### Part B: Path-by-Path Value Equivalence
1. **Normal VRF path** (_finalizeLootboxRng): Both wrote same `rngWord`. EQUIVALENT.
2. **Mid-day path** (advanceGame L158): L162 wrote value already in mapping. EQUIVALENT.
3. **Stall backfill path** (_backfillOrphanedLootboxIndices): lastLootboxRngWord held OLDEST index word; mapping read returns CURRENT index word. Mapping read is MORE CORRECT (latent bug fix).
4. **Coordinator swap path**: Does not write to either variable. Covered by path 1 after resume. EQUIVALENT.
5. **Game-over single-word fallback**: Both wrote same fallbackWord at same index. EQUIVALENT.

### Part C: Underflow Check
- `lootboxRngIndex` initialized to 1 (DegenerusGameStorage.sol:1186)
- Only incremented, never decremented
- Read site in processTicketBatch executes only after VRF fulfillment, meaning lootboxRngIndex >= 2
- Therefore `lootboxRngIndex - 1 >= 1` -- underflow impossible

### Part D: Regression Gate
- `forge test`: 369 tests passed, 0 failed, 0 skipped

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None - all changes are complete with no placeholder code.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Contract changes from this plan are stable and tested
- Plans 121-02 and 121-03 can proceed (double SLOAD fix, event emission fix, deity boon downgrade prevention)
- Storage layout shift (-1 for all variables after slot 54) documented for any future slot-dependent tests

---
*Phase: 121-storage-and-gas-fixes*
*Completed: 2026-03-26*

## Self-Check: PASSED
- SUMMARY.md: FOUND
- Commit ca2e43b2: FOUND
- Commit 068057d9: FOUND
- All 5 modified files: FOUND
