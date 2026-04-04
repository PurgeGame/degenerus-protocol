---
phase: 157-quest-logic-roll-chain
plan: 02
subsystem: contracts
tags: [solidity, quests, level-quest, advance-module, roll-chain, vrf-entropy]

requires:
  - phase: 157-quest-logic-roll-chain
    plan: 01
    provides: rollLevelQuest body in DegenerusQuests.sol, IDegenerusQuests interface declaration

provides:
  - AdvanceModule roll trigger calling quests.rollLevelQuest at level transition
  - IDegenerusQuests import and quests constant in AdvanceModule
  - VRF-derived entropy with LEVEL_QUEST salt for statistical independence

affects: [158 handler integration]

tech-stack:
  added: []
  patterns:
    - "keccak256(abi.encodePacked(rngWordByDay[day], 'LEVEL_QUEST')) for independent entropy stream"
    - "External call before phaseTransitionActive = false, after FF drain completion"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameAdvanceModule.sol

key-decisions:
  - "Import placed after IVRFCoordinator, before IStETH -- alphabetical among interface imports"
  - "quests constant placed after charityResolve in the PRECOMPUTED ADDRESSES section"
  - "Roll trigger placed after FF drain completion, before phaseTransitionActive = false -- earliest safe point after level transition is fully committed"

requirements-completed: [ROLL-01, ROLL-02]

duration: 2min
completed: 2026-04-01
---

# Phase 157 Plan 02: AdvanceModule Roll Trigger Summary

**AdvanceModule wired to call quests.rollLevelQuest(purchaseLevel, questEntropy) at every level transition, using keccak256(rngWordByDay[day], "LEVEL_QUEST") entropy**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-01T16:55:31Z
- **Completed:** 2026-04-01T16:57:11Z
- **Tasks:** 1 completed
- **Files modified:** 1

## Accomplishments

- Added IDegenerusQuests import to AdvanceModule (line 16)
- Added quests constant using ContractAddresses.QUESTS (lines 93-94)
- Inserted 3-line roll trigger (comment + entropy derivation + call) at line 286-289
- Roll trigger fires after FF drain completion, before phaseTransitionActive = false
- Entropy uses rngWordByDay[day] (warm from rngGate) with "LEVEL_QUEST" salt for independence from coinflip/redemption consumers
- All 62 Solidity files compile cleanly (npx hardhat compile --force)
- All 5 verification checks pass

## Task Commits

Contract changes are unstaged modifications awaiting user review per project policy (CLAUDE.md: never commit contracts/ without explicit user approval).

1. **Task 1: Add IDegenerusQuests import, quests constant, and roll trigger** - No commit (contract changes require user approval)

## Files Created/Modified

- `contracts/modules/DegenerusGameAdvanceModule.sol` - +6 lines: IDegenerusQuests import, quests constant, roll trigger (comment + entropy + call)

## Decisions Made

- Roll trigger placement: after FF drain completion guard, before phaseTransitionActive = false. This is the earliest safe point where the level transition is fully committed (processPhaseTransition and processFutureTicketBatch both complete).
- Entropy derivation follows existing pattern of keccak256 with domain-specific salt, matching coinflip and redemption roll entropy independence.

## Deviations from Plan

### [Rule 3 - Blocking] Worktree missing Phase 156 contract changes

- **Found during:** Task 1 compilation
- **Issue:** Worktree had pre-Phase-156 contracts. IDegenerusQuests interface lacked rollLevelQuest declaration, causing compilation failure.
- **Fix:** Copied Phase 156's updated contract files from main repo working tree to worktree (IDegenerusQuests.sol, DegenerusQuests.sol, and other modified contracts).
- **Impact:** None on plan output -- these are pre-existing changes from the dependency chain, not new modifications.

## Issues Encountered

- Contract commit guard (CLAUDE.md policy) prevents git add/commit of contracts/ files. Contract changes remain as unstaged modifications for user review.

## Known Stubs

None -- the roll trigger is fully wired with no placeholder logic.

## Verification Results

1. `npx hardhat compile --force` -- 62 files compiled successfully
2. `quests.rollLevelQuest(purchaseLevel, questEntropy)` appears exactly 1 time
3. `IDegenerusQuests` appears 3 times (import + constant type + constant initializer)
4. `LEVEL_QUEST` appears exactly 1 time
5. rollLevelQuest (line 289) appears before phaseTransitionActive = false (line 290) -- correct ordering confirmed

## Self-Check: PASSED

- contracts/modules/DegenerusGameAdvanceModule.sol: FOUND (contains all 3 changes)
- No commits to verify (contract changes unstaged per policy)
- All 5 acceptance criteria verified

---
*Phase: 157-quest-logic-roll-chain*
*Completed: 2026-04-01*
