# Phase 157: Quest Logic & Roll Chain - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 157-quest-logic-roll-chain
**Areas discussed:** Quest type selection approach, Eligibility data access, Phase 156 stub cleanup
**Mode:** --auto (all decisions auto-selected)

---

## Quest Type Selection Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse with type(uint8).max sentinel | Call `_bonusQuestType(entropy, type(uint8).max, decAllowed)` — sentinel never matches any candidate | ✓ |
| Reuse with QUEST_TYPE_RESERVED | Call `_bonusQuestType(entropy, QUEST_TYPE_RESERVED, decAllowed)` — RESERVED already skipped separately | |
| New _levelQuestType function | Separate function without exclusion parameter; cleaner but duplicates weight table | |

**User's choice:** [auto] Reuse with type(uint8).max sentinel (recommended by integration map Section 6.4)
**Notes:** type(uint8).max (255) never matches any QUEST_TYPE_* constant (0-8), so no type is excluded from selection. This is the integration map's explicit recommendation.

---

## Eligibility Data Access

| Option | Description | Selected |
|--------|-------------|----------|
| New view function on DegenerusGame | Add function returning mintPacked_ fields needed for eligibility | ✓ |
| Pass eligibility from caller | Have game modules pass bool to quest handlers | |
| Individual getter functions | Add levelStreak(), levelUnits(), etc. to IDegenerusGame | |

**User's choice:** [auto] New view function on DegenerusGame (recommended default)
**Notes:** DegenerusQuests is standalone (not delegatecall) so cannot read mintPacked_ directly. A single view function returning the needed fields is most gas-efficient (1 external call vs. multiple). Exact interface shape deferred to Claude's discretion. `deityPassCountFor(address)` already exists on IDegenerusGame for the deity pass fallback.

---

## Phase 156 Stub Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Clean up when filling bodies | Replace phase-referencing comments during Phase 157 implementation | ✓ |
| Leave as-is | Let Phase 158 or separate cleanup handle it | |

**User's choice:** [auto] Clean up when filling bodies (recommended default)
**Notes:** Phase 156 verification noted 3 comments referencing phase numbers (lines 1610, 1614, 1618). Per `feedback_no_history_in_comments`, these must describe what the function IS, not what phase added it. Natural cleanup point is when the TODO stubs are replaced with actual implementations.

---

## Claude's Discretion

- Interface design for mintPacked_ view function (struct vs. raw uint256 vs. individual getters)
- Whether _handleLevelQuestProgress returns reward or handles internally
- Internal helper naming and code organization
- NatSpec detail level on new functions

## Deferred Ideas

None -- all discussion stayed within phase scope.
