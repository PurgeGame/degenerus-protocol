# Phase 156: Interfaces, Storage & Access Control - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 156-interfaces-storage-access-control
**Areas discussed:** BurnieCoin interface location, rollLevelQuest access control, storage declaration order
**Mode:** Auto (--auto flag active)

---

## BurnieCoin Interface Location

| Option | Description | Selected |
|--------|-------------|----------|
| Add to IDegenerusCoinModule | Add rollLevelQuest to existing DegenerusGameModuleInterfaces.sol -- mirrors rollDailyQuest pattern | [auto] |
| Create IBurnieCoin.sol | New interface file for BurnieCoin | |
| Inline interface in caller | Define inline interface in AdvanceModule (like IBurnieCoinflip in BurnieCoin.sol) | |

**User's choice:** [auto] Add to IDegenerusCoinModule (recommended default)
**Notes:** IDegenerusCoinModule already has rollDailyQuest; adding rollLevelQuest maintains the pattern. No IBurnieCoin.sol exists in the codebase and creating one would be inconsistent.

---

## rollLevelQuest Access Control

| Option | Description | Selected |
|--------|-------------|----------|
| onlyCoin modifier | Same modifier as rollDailyQuest -- BurnieCoin is the caller | [auto] |
| onlyGame modifier | Game contract calls directly, skipping BurnieCoin | |
| New onlyCoinOrGame | Allow both callers | |

**User's choice:** [auto] onlyCoin modifier (recommended default)
**Notes:** The roll chain is AdvanceModule -> BurnieCoin -> DegenerusQuests, mirroring daily quests. BurnieCoin is the direct caller, so onlyCoin is correct.

---

## Storage Declaration Order

| Option | Description | Selected |
|--------|-------------|----------|
| levelQuestType first | Global mapping before per-player mapping -- mirrors activeQuests/questPlayerState order | [auto] |
| levelQuestPlayerState first | Per-player mapping before global mapping | |

**User's choice:** [auto] levelQuestType first (recommended default)
**Notes:** Existing storage follows global-before-per-player: activeQuests (global) at line 268, questPlayerState (per-player) at line 271. New level quest storage mirrors this.

---

## Claude's Discretion

- NatSpec documentation style for new declarations
- Exact positioning of new interface declarations within IDegenerusQuests.sol
- Whether getPlayerLevelQuestView gets full implementation or stub in Phase 156

## Deferred Ideas

None -- all discussion stayed within phase scope
