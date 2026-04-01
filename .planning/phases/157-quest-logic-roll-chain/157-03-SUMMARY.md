---
phase: 157-quest-logic-roll-chain
plan: 03
title: "Gap Closure: MINT_BURNIE sentinel fix + levelQuestGlobal packing + ROLL-01 docs"
subsystem: quests
tags: [gap-closure, gas-optimization, sentinel-fix, storage-packing]
dependency_graph:
  requires: [157-01, 157-02]
  provides: [sentinel-safe-quest-types, packed-level-quest-global]
  affects: [DegenerusQuests.sol, REQUIREMENTS.md]
tech_stack:
  added: []
  patterns: [packed-slot-for-level+type, sentinel-value-avoidance]
key_files:
  created: []
  modified:
    - contracts/DegenerusQuests.sol
    - .planning/REQUIREMENTS.md
decisions:
  - "QUEST_TYPE_MINT_BURNIE moved from 0 to 9 -- value 0 now unambiguously means unrolled"
  - "levelQuestType mapping replaced with levelQuestGlobal uint256 packed slot (level bits 0-23, type bits 24-31)"
  - "_bonusQuestType loop skips candidate 0 to prevent orphan type selection"
  - "_isLevelQuestEligible receives currentLevel as parameter instead of calling questGame.level()"
  - "ROLL-01 superseded by D-12 direct call pattern"
metrics:
  duration: 4min
  completed: "2026-04-01T17:19:55Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 157 Plan 03: Gap Closure Summary

MINT_BURNIE sentinel collision fixed, level quest global state packed into single slot saving ~2,600 gas per handler call, eligibility function threaded with level parameter, REQUIREMENTS.md updated for direct roll pattern.

## Tasks Completed

### Task 1: MINT_BURNIE sentinel fix + levelQuestGlobal packing

- **QUEST_TYPE_MINT_BURNIE** moved from value 0 to value 9; QUEST_TYPE_COUNT updated from 9 to 10
- **levelQuestType mapping** replaced with **levelQuestGlobal uint256** packed slot (bits 0-23: questLevel, bits 24-31: questType)
- **rollLevelQuest** writes packed `uint256(lvl) | (uint256(selectedType) << 24)` instead of mapping write
- **_handleLevelQuestProgress** reads single `levelQuestGlobal` SLOAD instead of cross-contract `questGame.level()` + mapping SLOAD
- **_isLevelQuestEligible** signature changed to accept `(address player, uint24 currentLevel)` -- eliminates redundant `questGame.level()` call
- **getPlayerLevelQuestView** reads from packed global slot, passes level to eligibility check
- **_bonusQuestType** loop now skips candidate 0 (sentinel) alongside existing QUEST_TYPE_RESERVED skip
- NatSpec updated: `_levelQuestTargetValue` param doc corrected from "(0-8)" to "(1-9, 0 reserved as unrolled sentinel)"
- All 62 Solidity files compile cleanly

### Task 2: Update REQUIREMENTS.md for ROLL-01/ROLL-02

- ROLL-01 marked as superseded by D-12 (direct AdvanceModule -> DegenerusQuests call, no BurnieCoin hop)
- ROLL-02 wording updated: `coin.rollLevelQuest` changed to `quests.rollLevelQuest`
- Traceability table: ROLL-01 and ROLL-02 status changed from Pending to Complete

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] _bonusQuestType orphan type 0 selection**
- **Found during:** Task 1, Step A
- **Issue:** Moving MINT_BURNIE from 0 to 9 left type 0 as an orphan in the weighted selection loop. The loop would assign weight=1 to candidate 0, allowing it to be selected as a quest type despite having no semantic meaning.
- **Fix:** Added `candidate == 0` to the skip condition alongside QUEST_TYPE_RESERVED in the first selection loop of `_bonusQuestType`
- **Files modified:** contracts/DegenerusQuests.sol

## Verification Results

| Check | Result |
|-------|--------|
| `QUEST_TYPE_MINT_BURNIE = 9` | 1 match |
| `QUEST_TYPE_COUNT = 10` | 1 match |
| `levelQuestGlobal` references | 7 matches |
| `levelQuestType` references | 0 matches (eliminated) |
| `questGame.level()` references | 0 matches (eliminated) |
| `_isLevelQuestEligible(player, currentLevel)` | 2 matches |
| `npx hardhat compile --force` | 62 files, 0 errors |

## Gas Impact

| Path | Before | After | Savings |
|------|--------|-------|---------|
| Type mismatch (62.5%) | ~4,730 | ~2,130 | ~2,600 |
| Type match, ineligible | ~9,530 | ~6,930 | ~2,600 |
| Type match, eligible | ~12,130+ | ~9,530+ | ~2,600 |

## Known Stubs

None -- all code paths are fully wired.

## Self-Check: PASSED

- contracts/DegenerusQuests.sol: EXISTS, contains all expected changes
- .planning/REQUIREMENTS.md: EXISTS, ROLL-01 superseded, ROLL-02 updated, traceability table updated
- No commits expected (contracts/ not committed per project rules, .planning/ is gitignored)
