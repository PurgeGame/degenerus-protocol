# Phase 255: Vote Rewrite, Resolve Flush & Event/Error Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-06
**Phase:** 255-vote-rewrite-resolve-flush-event-error-cleanup
**Areas discussed:** Vote sad-path error shape, pickCharity flush event shape, per-(level, slot) approve weight storage, ROADMAP cleanup

---

## Vote Sad-Path Error Shape

| Option | Description | Selected |
|--------|-------------|----------|
| EmptySlot + ZeroWeight (Recommended) | Two new errors with descriptive vote-specific names. Clear sad-path semantics, no overloading. | |
| EmptySlot + reuse InsufficientStake | Add EmptySlot for empty slot; reuse v32 InsufficientStake (deleted in Phase 254) for zero-weight. Continuity with v32 mental model. | |
| VoteRejected (single error with reason code) | One error with a uint8 reason arg. Tighter bytecode, single selector for three sad paths. | ✓ |
| EmptySlot + InsufficientBalance | Add EmptySlot + InsufficientBalance. More literal than ZeroWeight. | |

**User's choice:** VoteRejected (single error with reason code)
**Notes:** Folded into D-255-VOTEREJECT-01 with three reason constants: REJECT_EMPTY_SLOT (0), REJECT_ALREADY_VOTED (1), REJECT_ZERO_WEIGHT (2). Same pattern extended to PickCharityRejected for level-not-active / level-already-resolved (D-255-PICKCHARITY-ERROR-01).

---

## pickCharity Flush Event Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Per-edit CharityFlushed (Recommended) | `event CharityFlushed(uint8 indexed slot, address indexed recipient)` once per applied pending edit (up to 20 emits worst case). Mirrors Phase 254 single-event style. | ✓ |
| Aggregate CharityFlushBatch | Single emit per pickCharity with paired uint8[] / address[] arrays. One log entry but encoding overhead. | |
| No flush event — indexers reconstruct from CharityQueued + level boundary | Don't emit on flush. Cheapest gas; brittle indexer state. | |
| Reuse CharityApplied for flush emits | Reuse the existing event from Phase 254. Loses ability to distinguish admin-instant from flush-time apply via topic[0]. | |

**User's choice:** Per-edit CharityFlushed
**Notes:** Three-event lifecycle for indexers: `CharityQueued` (Phase 254 setCharity queue branch) → `CharityFlushed` (Phase 255 pickCharity flush) → optionally `LevelResolved` if winner is at the same slot.

---

## Per-(Level, Slot) Approve Weight Storage

| Option | Description | Selected |
|--------|-------------|----------|
| mapping(uint24 => mapping(uint8 => uint256)) slotApproveWeight (Recommended) | Standard nested mapping. Two cold SLOADs per vote. Auto-getter exposed for indexers/tests. | ✓ |
| Packed-key mapping(uint256 => uint256) with key = (level << 8) \| slot | Single mapping with packed key. One cold SLOAD per vote (saves ~2.1k gas). Loses auto-getter ergonomics. | |
| Per-level static array mapping(uint24 => uint256[20]) | Array per level. Single SLOAD-per-slot in winner loop. But 20 cold SSTOREs zero-init on first vote of each level (~440k gas spike). | |
| Smaller weight type (uint96 inside packed mapping) | Pack as uint96 (sDGNRS supply ~1e12 fits with 16M× headroom). Premature packing if no second weight ever lands. | |

**User's choice:** mapping(uint24 => mapping(uint8 => uint256)) slotApproveWeight
**Notes:** Old-level entries persist in storage post-pickCharity (deliberate per `feedback_no_dead_guards.md`; wiping 20 cold SSTOREs per level burns ~110k gas for no functional benefit, and historical query is a free side-benefit for indexers).

---

## ROADMAP Cleanup (RecipientIsContract reference inconsistency)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix in this CONTEXT.md commit (Recommended) | Update ROADMAP.md success criteria in the same commit that captures CONTEXT.md. | ✓ |
| Defer to Phase 257 audit-prep | Leave ROADMAP wording; flag as known inconsistency in CONTEXT.md `<deferred>`. | |
| Fix in a separate docs commit before Phase 255 plan-phase | Standalone docs commit. | |

**User's choice:** Fix in this CONTEXT.md commit
**Notes:** Updated three lines in ROADMAP.md:
- Phase 254 success criterion 2 (line 140) — dropped the `RecipientIsContract` revert clause; added a note that contract recipients are accepted by design
- Phase 255 success criterion 5 (line 159) — replaced the stale `RecipientIsContract`/`InsufficientStake` cleanup wording with the Phase 254 deletion summary + the new `VoteRejected(uint8 reason)` error addition for Phase 255
- Phase 256 success criterion 1 (line 168) — dropped `RecipientIsContract` from the sad-path test list

## Claude's Discretion

- Storage-slot ordering of new `slotApproveWeight` mapping (planner picks)
- Inline flush loop vs `_flushPending()` private helper (planner picks)
- Reason-code shape: `uint8 private constant` vs Solidity `enum` (defaulted to constants for gas + test ergonomics)
- Whether to add an aggregate `CharityFlushBatch(uint24 indexed level, uint8 count)` checksum event in addition to per-edit CharityFlushed (planner can add if cost justified; default = no)

## Deferred Ideas

- Phase 256 — Hardhat test coverage for full v33.0 surface
- Phase 257 — Adversarial audit + `audit/FINDINGS-v33.0.md` (AUDIT-02 (a..i) sweep)
- Aggregate `CharityFlushBatch` event (planner discretion)
- Old-level `slotApproveWeight` cleanup (deliberately deferred indefinitely)
- `InsufficientStake` REQUIREMENTS.md wording cleanup (stale hint; not blocking; cleaned up at v33.0 milestone close)
