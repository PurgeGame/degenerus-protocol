---
phase: 73-boon-storage-packing
plan: 01
subsystem: storage
tags: [solidity, bit-packing, gas-optimization, evm-storage, delegatecall]

# Dependency graph
requires: []
provides:
  - BoonPacked struct definition (2-slot packed layout) in DegenerusGameStorage.sol
  - boonPacked mapping at storage slot 107
  - 23 shift constants + 2 masks + 8 clear masks for packed field access
  - 12 tier encode/decode helpers (6 tierToBps + 6 bpsToTier)
  - Rewritten BoonModule with 2-SLOAD read-modify-write pattern
affects: [73-02 (LootboxModule/WhaleModule packed rewrite), 73-03 (MintModule packed rewrite)]

# Tech tracking
tech-stack:
  added: []
  patterns: [BoonPacked 2-slot struct with shift/mask constants, read-modify-write pattern, category clear masks]

key-files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/modules/DegenerusGameBoonModule.sol

key-decisions:
  - "Used // @deprecated comments instead of NatSpec /// @deprecated (Solidity 0.8.34 rejects @deprecated on non-public state variables)"
  - "Expiry day constants narrowed from uint48 to uint24 to match packed day field width"

patterns-established:
  - "BoonPacked read-modify-write: load slot once, extract via shift+mask, modify in memory, write back via clear mask + OR"
  - "Category clear masks: precomputed ~uint256 masks for zeroing all fields in a boon category with single AND"
  - "Tier encoding: uint8 0-3 tiers with pure decode/encode helpers at storage boundary, uint16 BPS at interface boundary"

requirements-completed: [BOON-01, BOON-02, BOON-04]

# Metrics
duration: 12min
completed: 2026-03-22
---

# Phase 73 Plan 01: Boon Packed Storage Foundation Summary

**BoonPacked 2-slot struct with 14 day fields + 7 tier fields in DegenerusGameStorage, all 5 BoonModule functions rewritten from 29 SLOADs to 2 SLOADs per checkAndClearExpiredBoon call**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-22T21:01:51Z
- **Completed:** 2026-03-22T21:13:51Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- BoonPacked struct with documented 2-slot bit layout (256 + 184 bits used of 512) added to DegenerusGameStorage.sol at slot 107
- All 29 old boon mappings preserved as slot placeholders with deprecation comments (slots 25-41, 75-82, 85-87, 93-95 unchanged via forge inspect)
- All 5 BoonModule functions (consumeCoinflipBoon, consumePurchaseBoost, consumeDecimatorBoost, checkAndClearExpiredBoon, consumeActivityBoon) rewritten for packed read-modify-write
- Decimator correctly has no award-day expiry (only deity day check)
- checkAndClearExpiredBoon uses 2 SLOADs + at most 2 SSTOREs with changed0/changed1 optimization
- Stale deity day clearing for inactive lootbox boons preserved (matching original behavior)
- External function signatures completely unchanged

## Task Commits

Each task was committed atomically:

1. **Task 1: Add BoonPacked struct, mapping, constants, and decode helpers** - `89563694` (feat)
2. **Task 2: Rewrite DegenerusGameBoonModule for packed struct** - `13d48ecb` (feat)

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` - BoonPacked struct, boonPacked mapping, 23 shift constants, 2 masks, 8 clear masks, 12 tier encode/decode helpers, 29 deprecation comments on old mappings
- `contracts/modules/DegenerusGameBoonModule.sol` - All 5 functions rewritten from individual mapping reads to packed struct read-modify-write (164 insertions, 196 deletions)

## Decisions Made
- Used `// @deprecated` instead of NatSpec `/// @deprecated` because Solidity 0.8.34 rejects `@deprecated` tags on non-public state variables (compilation error)
- Narrowed expiry day constants from uint48 to uint24 to match the packed day field width (uint24 provides 45,000+ year range)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Changed @deprecated from NatSpec to regular comment**
- **Found during:** Task 1 (deprecation comments on old mappings)
- **Issue:** Plan specified `/// @deprecated` NatSpec doc tags, but Solidity 0.8.34 raises `Error (6546): Documentation tag @deprecated not valid for non-public state variables`
- **Fix:** Changed all 29 instances from `/// @deprecated` to `// @deprecated`
- **Files modified:** contracts/storage/DegenerusGameStorage.sol
- **Verification:** forge build compiles without errors
- **Committed in:** 89563694 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** NatSpec syntax adjustment only. Same deprecation intent preserved with regular comments. No scope creep.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- BoonPacked struct and all constants are available via DegenerusGameStorage inheritance for Plans 02 and 03
- Plan 02 (LootboxModule + WhaleModule) can now use the packed struct for _applyBoon, _activeBoonCategory, lootbox boost consumption, whale/lazy pass boon reads
- Plan 03 (MintModule) can now use the packed struct for purchase boost consumption
- forge build passes cleanly; storage layout verified via forge inspect (boonPacked at slot 107, all old slots unchanged)

## Self-Check: PASSED

- FOUND: contracts/storage/DegenerusGameStorage.sol
- FOUND: contracts/modules/DegenerusGameBoonModule.sol
- FOUND: commit 89563694
- FOUND: commit 13d48ecb

---
*Phase: 73-boon-storage-packing*
*Completed: 2026-03-22*
