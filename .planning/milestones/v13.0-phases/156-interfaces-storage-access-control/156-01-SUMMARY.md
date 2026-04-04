---
phase: 156-interfaces-storage-access-control
plan: 01
subsystem: contracts
tags: [solidity, interfaces, storage, access-control, level-quests]

requires:
  - phase: 153-core-design
    provides: "Level quest design spec (eligibility, mechanics, storage layout, completion flow)"
  - phase: 154-integration-mapping
    provides: "Contract touchpoint map with exact modification sites and line numbers"
provides:
  - "IDegenerusQuests interface with LevelQuestCompleted event, rollLevelQuest, getPlayerLevelQuestView"
  - "IDegenerusCoinModule interface with rollLevelQuest forwarding declaration"
  - "DegenerusQuests storage: levelQuestType and levelQuestPlayerState mappings"
  - "DegenerusQuests stub functions: rollLevelQuest (onlyCoin), getPlayerLevelQuestView (view)"
  - "BurnieCoinflip onlyFlipCreditors expanded with QUESTS address"
  - "BurnieCoin.rollLevelQuest forwarding function (onlyDegenerusGameContract)"
affects: [157-quest-logic, 158-handler-integration]

tech-stack:
  added: []
  patterns:
    - "Level quest storage appended after questVersionCounter following global-before-per-player ordering"
    - "rollLevelQuest routing mirrors existing rollDailyQuest pattern through BurnieCoin -> DegenerusQuests"

key-files:
  created: []
  modified:
    - contracts/interfaces/IDegenerusQuests.sol
    - contracts/interfaces/DegenerusGameModuleInterfaces.sol
    - contracts/DegenerusQuests.sol
    - contracts/BurnieCoinflip.sol
    - contracts/BurnieCoin.sol

key-decisions:
  - "Stub functions use existing onlyCoin modifier matching rollDailyQuest access pattern"
  - "BurnieCoin.rollLevelQuest is a complete 1-line forward (not a stub) since it just routes to questModule"
  - "Contract changes staged but not committed per contract commit guard policy -- user reviews diff first"

patterns-established:
  - "Level quest interface follows same NatSpec style as existing daily quest declarations"
  - "Storage ordering: global mapping (levelQuestType) before per-player mapping (levelQuestPlayerState)"

requirements-completed: [INTF-01, INTF-02, QUEST-01, ACL-01]

duration: 3min
completed: 2026-04-01
---

# Phase 156 Plan 01: Interfaces, Storage & Access Control Summary

**Level quest interface declarations, storage mappings, access control expansion, and routing stub across 5 Solidity files -- all compiling cleanly**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-01T02:16:21Z
- **Completed:** 2026-04-01T02:19:22Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- IDegenerusQuests.sol extended with LevelQuestCompleted event, rollLevelQuest function, and getPlayerLevelQuestView function
- IDegenerusCoinModule extended with rollLevelQuest declaration for BurnieCoin forwarding
- DegenerusQuests.sol storage section extended with levelQuestType and levelQuestPlayerState mappings after questVersionCounter
- BurnieCoinflip onlyFlipCreditors modifier expanded from 4 to 5 creditor addresses (added QUESTS)
- BurnieCoin.rollLevelQuest forwarding function added mirroring existing rollDailyQuest pattern
- All 62 Solidity files compile successfully with no errors

## Task Commits

Contract changes staged but not committed -- user reviews diff first per contract commit guard policy.

1. **Task 1: Add level quest declarations to interface files** - staged (contracts/interfaces/)
2. **Task 2: Add storage, access control, and routing function** - staged (contracts/)

**Plan metadata:** see final docs commit

## Files Modified
- `contracts/interfaces/IDegenerusQuests.sol` - Added LevelQuestCompleted event, rollLevelQuest and getPlayerLevelQuestView function signatures
- `contracts/interfaces/DegenerusGameModuleInterfaces.sol` - Added rollLevelQuest to IDegenerusCoinModule interface
- `contracts/DegenerusQuests.sol` - Added levelQuestType and levelQuestPlayerState storage mappings, rollLevelQuest and getPlayerLevelQuestView stub functions
- `contracts/BurnieCoinflip.sol` - Expanded onlyFlipCreditors modifier to include ContractAddresses.QUESTS
- `contracts/BurnieCoin.sol` - Added rollLevelQuest forwarding function with onlyDegenerusGameContract guard

## Decisions Made
- Stub functions in DegenerusQuests.sol use existing `onlyCoin` modifier, matching the rollDailyQuest access control pattern
- BurnieCoin.rollLevelQuest implemented as a complete 1-line forwarding function (not a stub) since it only routes to questModule
- Contract changes staged but not committed per contract commit guard policy

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

| File | Function | Reason | Resolving Phase |
|------|----------|--------|-----------------|
| contracts/DegenerusQuests.sol | rollLevelQuest | Empty body -- quest selection logic | Phase 157 |
| contracts/DegenerusQuests.sol | getPlayerLevelQuestView | Empty body -- view logic | Phase 158 |

These stubs are intentional scaffolding per plan design. The function signatures and access control are the deliverables of this plan.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All interface signatures locked -- Phase 157 (quest logic) and Phase 158 (handler integration) can build on stable types
- Storage slots declared -- Phase 157 can write to levelQuestType and levelQuestPlayerState
- Access control expanded -- DegenerusQuests can credit BURNIE rewards via BurnieCoinflip
- Routing wired -- AdvanceModule -> BurnieCoin -> DegenerusQuests call chain ready

## Self-Check: PASSED

- 6/6 files FOUND
- 6/6 must-have truths PASS
- Compilation: 62 Solidity files successfully compiled (0 errors)

---
*Phase: 156-interfaces-storage-access-control*
*Completed: 2026-04-01*
