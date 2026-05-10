---
date: "2026-05-10 00:00"
promoted: false
target-milestone: v37.0
phase-title: resolveLootboxRoll-dead-burnie-conversion-branch-cleanup
subsystem: lootbox-resolution
tags: [lootbox, dead-code, gas-optimization, feedback_no_dead_guards, maintenance]
discovered-by: contract-auditor adversarial pass (Phase 266 Task 14)
discovered-at: HEAD post-Wave-1 commit df6345cc (v36.0 lootbox-entropy-refactor)
---

# Phase Seed: `_resolveLootboxRoll` Dead BURNIE-Conversion Branch Cleanup

**Target milestone:** v37.0 (separate maintenance scope; not pulled into v36.0 because the
dead branch is pre-existing — present at the v35.0 baseline `5db8682b` AND survives the
Phase 266 lootbox-entropy refactor unchanged. Pulling cleanup into v36.0 would inflate the
delta-surface beyond ENT-01..06 scope).

**Status:** Pre-existing dead code surfaced during Phase 266 adversarial pass. NOT a security
finding (no exploit; defensive code that was already neutralized by caller-side normalization).
~50 g/open savings + bytecode shrink + violates `feedback_no_dead_guards.md`.

## Discovery context

Surfaced by `/contract-auditor` adversarial pass at Phase 266 Task 14 as Hypothesis (m).
Logged in `.planning/phases/266-lootbox-entropy-refactor/266-01-ADVERSARIAL-LOG.md` under
`## /contract-auditor` → `### 7th-surface novel-composition candidates investigated`. The
auditor explicitly classified it as a forward-looking defensive observation, NOT a Phase 266
finding, because the dead branch existed at the v35.0 baseline (same code at the equivalent
pre-refactor line ~L1559) and survived the refactor untouched.

User disposition (2026-05-10): defer cleanup to v37.0 maintenance scope.

## The dead branch

`contracts/modules/DegenerusGameLootboxModule.sol` `_resolveLootboxRoll` tickets path at
live HEAD L1568-1581:

```solidity
if (roll < 11) {
    // 55% chance: tickets (returned as scaled × TICKET_SCALE)
    uint256 ticketBudget = (amount * LOOTBOX_TICKET_ROLL_BPS) / 10_000;
    uint32 ticketsScaled =
        _lootboxTicketCount(ticketBudget, targetPrice, seed);
    if (ticketsScaled != 0) {
        if (targetLevel < currentLevel) {                              // ← L1574: DEAD
            // Convert to BURNIE if target level already passed
            burnieOut = (uint256(ticketsScaled) * PRICE_COIN_UNIT) / TICKET_SCALE;
        } else {
            ticketsOut = ticketsScaled;                                // ← always taken
        }
    }
    applyPresaleMultiplier = false;
}
```

## Why it's structurally unreachable

`_resolveLootboxRoll` is `private` and called only from `_resolveLootboxCommon`, which
clamps `targetLevel >= currentLevel` BEFORE invoking `_resolveLootboxRoll` at L882-884:

```solidity
function _resolveLootboxCommon(
    address player,
    uint32 day,
    uint256 amount,
    uint24 targetLevel,
    uint24 currentLevel,
    ...
) private returns (...) {
    if (targetLevel < currentLevel) {
        targetLevel = currentLevel;        // ← clamps up to current
    }
    ...
    _resolveLootboxRoll(..., targetLevel, ..., seed);  // targetLevel ≥ currentLevel guaranteed
}
```

Because the only caller normalizes `targetLevel`, the `if (targetLevel < currentLevel)`
check inside `_resolveLootboxRoll` ALWAYS evaluates false. The BURNIE-conversion fallback
can never fire. Verified by grep — `_resolveLootboxRoll` has zero callers outside
`_resolveLootboxCommon` (`grep -rn "_resolveLootboxRoll" contracts/` returns only the
definition + the single caller).

## Cost

- **Per-call gas:** ~50 g per tickets-path open (LT comparison opcode + JUMPI on a branch
  that always falls through to the else). At 55% tickets-path probability, amortized
  ~27 g per lootbox open across all paths.
- **Bytecode bloat:** the dead-branch arithmetic
  `burnieOut = (uint256(ticketsScaled) * PRICE_COIN_UNIT) / TICKET_SCALE` adds bytecode that
  ships with the contract — small but non-zero deployment cost contribution.
- **Maintenance cost:** future readers of `_resolveLootboxRoll` must reason about a
  branch that can never execute, slowing audit / onboarding velocity.
- Violates `feedback_no_dead_guards.md` — "Remove unreachable safety caps; don't waste
  gas on dead branches".

## Proposed cleanup

Single-task plan; trivial diff. Replace L1573-1580 with the unconditional assignment:

```solidity
if (ticketsScaled != 0) {
    ticketsOut = ticketsScaled;
}
```

Compile + run the v37 SURF-XX byte-identity tests; confirm GAS-XX delta within ~−27 g/open
amortized; ship as a single batched USER-APPROVED contract commit per
`feedback_batch_contract_approval.md`.

## Why deferred to v37.0 (not bundled into v36.0)

Three reasons:

1. **Pre-existing scope.** The dead branch is present at the v35.0 baseline `5db8682b`.
   Phase 266's delta-surface is "lootbox-entropy refactor" (ENT-01..06) — the dead branch
   is orthogonal to entropy mechanics. Bundling it into the v36.0 audit deliverable would
   widen the §3d AUDIT-01 delta-surface table beyond the chartered scope and require
   re-running the adversarial pass against an expanded change set.

2. **AUDIT-04 zero-new-state attestation cleanliness.** v36.0's §3d Part C asserts
   "0 new public/external mutation entry points; 0 new modifiers; ..." against a tight
   delta. Adding an unrelated dead-code cleanup in the same commit muddies the attestation.

3. **User disposition (per Wave 2 closure context):** v36.0 was scoped as a single-phase
   patch shape per CONTEXT.md `<domain>` (mirroring lightweight v3.x patch pattern).
   Maintenance cleanups belong to a separate next-milestone scope.

## Forward-cite to v37.0

When v37.0 opens, this note feeds into:

- `.planning/ROADMAP.md` — add a phase line for "lootbox dead-code cleanup" (or bundle
  with other lootbox-area maintenance items if the milestone aggregates them)
- `audit/FINDINGS-v37.0.md` §3a per-phase section — cite this note as the discovery
  source + reference Phase 266 adversarial-log Hypothesis (m) for the structural argument
- `KNOWN-ISSUES.md` — no entry needed (defensive cleanup, not a published-behavior item)

## Cross-references

- `.planning/phases/266-lootbox-entropy-refactor/266-01-ADVERSARIAL-LOG.md` `## /contract-auditor` → Hypothesis (m)
- `audit/FINDINGS-v36.0.md` §4 (no F-36-NN finding — defensive note only)
- `feedback_no_dead_guards.md` (governing memory)
- Phase 266 Wave 1 commit `df6345cc` (refactor that surfaced the observation)
