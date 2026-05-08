# Phase 254: GNRUS Allowlist Storage, Admin Op & Storage Repack — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 254-gnrus-allowlist-storage-admin-op-storage-repack
**Areas discussed:** Current slate storage shape, Pending edit queue layout, setCharity event shape, Active-count tracking + repack target, hasVoted refactor timing, Error pruning boundary, View helper return shape, vote/pickCharity Phase 254 fate

---

## Initial gray area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Current slate storage shape | address[20] vs mapping+bitmap; affects Phase 255 vote/pickCharity gas + storage repack | ✓ |
| Pending edit queue layout | Three options: shadow array+diff list, mapping+sentinel, packed bytes32[] | ✓ |
| setCharity event shape | One event with applied flag vs two distinct events | ✓ |
| Active-count tracking + repack target | Counters vs computed-on-demand; repack target for vacated slot | ✓ |

**User's choice:** All four areas selected for discussion.

---

## Current slate storage shape

| Option | Description | Selected |
|--------|-------------|----------|
| address[20] fixed array (Recommended) | Statically-allocated 20-slot array; one SLOAD per index; deterministic gas; no bitmap drift | ✓ |
| mapping(uint8 => address) + uint32 activeBitmap | Sparse mapping + parallel bitmap; cheaper if sparse but bitmap drift risk | |
| Defer to plan-phase with gas comparison | Per PROJECT.md item 5; plan produces gas table across candidates | |
| You decide | Claude picks | |

**User's choice:** address[20] fixed array.
**Notes:** Pairs naturally with separate `currentActiveBitmap` in the hot-pack slot for cap-accounting (D-254-COUNT-01); avoids conflating slate storage with bookkeeping.

---

## Pending edit queue layout

| Option | Description | Selected |
|--------|-------------|----------|
| mapping + uint32 pendingEditSet bitmap (Recommended) | mapping(uint8=>address) pendingEdit + bitmap; bit set = pending exists; mapping=0 with bit set = pending-remove | ✓ |
| Shadow address[20] pendingSlate + uint32 pendingEditSet | Mirrors current slate shape; persistent storage state across levels; cold-write penalty per pending entry | |
| Packed bytes32[] diff list (slot+address) | Densest storage if many edits; worst for 0-1-edit common case; complex pending-overwrite | |
| Defer to plan-phase with gas comparison | Plan benches all three with worst-case gas | |

**User's choice:** mapping + uint32 pendingEditSet bitmap.
**Notes:** Solves the "pending remove (recipient=0)" sentinel cleanly. Cheap for 0-1-edit common case. Flush iterates set bits + clears bitmap with one SSTORE.

---

## setCharity event shape

| Option | Description | Selected |
|--------|-------------|----------|
| Two events: CharityApplied / CharityQueued (Recommended) | Distinct topic[0] hashes; instant-apply vs queued; aligns with Phase 255 per-edit flush event | ✓ |
| One event with applied flag | event CharitySet(slot, recipient, applied: bool); single ABI; couples branch semantics | |
| You decide | Claude picks | |

**User's choice:** Two events.
**Notes:** Clearer indexer filtering; cleaner three-event lifecycle (CharityQueued → flush → applied). Per-event payload: `(uint8 indexed slot, address indexed recipient)`.

---

## Active-count tracking

| Option | Description | Selected |
|--------|-------------|----------|
| Derive from bitmap popcount (Recommended) | currentActiveBitmap + popcount; activeCountAfterFlush walks bitmap modified by pendingEditSet; single source of truth | ✓ |
| Two uint8 counters | currentActiveCount + activeCountAfterFlush; cheap reads, +/- accounting at every write, drift risk | |
| Compute on-demand (no counters, no bitmap) | activeCount walks address[20]; expensive view, cheap writes | |

**User's choice:** Derive from bitmap popcount.
**Notes:** Zero drift risk by construction; structurally kills Phase 257 AUDIT-02-(f) "active-count accounting drift" attack class. Popcount of uint32 is small/constant gas (~30 gas via inline assembly).

---

## Storage repack target

| Option | Description | Selected |
|--------|-------------|----------|
| currentLevel + finalized + currentActiveBitmap + pendingEditSet (Recommended) | uint24+bool+uint32+uint32 = 12 bytes single hot slot; pairs with bitmap-popcount choice | ✓ |
| currentLevel + finalized + two uint8 counters | uint24+bool+uint8+uint8 = 7 bytes; pairs with two-counters choice | |
| Defer to plan-phase with layout diagram | Required output regardless; plan produces before/after diagram | |

**User's choice:** Single hot-pack slot with bitmaps.
**Notes:** All four hot fields touched by setCharity + view helpers; one cold SLOAD warms the whole pack.

---

## hasVoted refactor timing

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 254 — redeclare during repack (Recommended) | Single coherent storage layout from 254 onward; no second repack in 255 | ✓ |
| Phase 255 — along with vote() rewrite | Phase 254 leaves legacy untouched; risk of two repacks | |
| Defer to plan-phase | Plan decides based on storage-layout diff | |

**User's choice:** Phase 254 redeclare.
**Notes:** New shape `mapping(uint24 => address => uint8 => bool)`. Unread between Phase 254 close and Phase 255 open; storage definition stable.

---

## Error pruning boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 254 deletes ONLY propose()-exclusive errors (Recommended) | Delete ProposalLimitReached, AlreadyProposed; keep InsufficientStake/AlreadyVoted/etc for vote() | ✓ |
| Phase 254 deletes everything propose/vote-flow-related at once | Nuke ALL old errors immediately; vote/pickCharity get stub bodies | |
| Defer to plan-phase | Plan enumerates every error + reference site + classifies | |

**User's choice:** Phase 254 deletes ONLY propose()-exclusive errors.
**Notes:** Updated mechanically by D-254-VOTEPICK-01 — once vote()/pickCharity() are also deleted in Phase 254, the orphaned set EXPANDS to include InsufficientStake, AlreadyVoted, InvalidProposal, LevelAlreadyResolved, LevelNotActive (all deleted in Phase 254 per D-254-ERROR-PRUNE-01). Phase 255 re-adds whatever vote()/pickCharity() need from scratch.

---

## View helper return shape

| Option | Description | Selected |
|--------|-------------|----------|
| Paired arrays: (uint8[] slots, address[] recipients) (Recommended) | Length = popcount; full snapshot in one call; ergonomic for indexers | ✓ |
| Sparse uint8[] indices + caller does getCharity per slot | Cheaper view but two round-trips for full state | |
| Raw bitmap exposure: uint32 currentActiveBitmap() / uint32 pendingEditSet() | Cheapest possible; conflicts with ALW-04 wording | |

**User's choice:** Paired arrays.
**Notes:** Both `getActiveSlots()` and `getPendingEdits()` use this shape. Memory-only allocation, gas bounded by 20 slots.

---

## vote() / pickCharity() Phase 254 fate

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 254 deletes vote() + pickCharity() too; Phase 255 re-adds in new shape (Recommended) | Required for compile after Proposal struct deletion; cleanest separation | ✓ |
| Phase 254 partially rewrites vote() + pickCharity() to consume new slate | Just enough to compile; messy intermediate state; two rewrites | |
| Phase 254 stubs with revert Unimplemented | Compiles but conflicts with feedback_no_dead_guards.md; game halts on advance | |

**User's choice:** Phase 254 deletes vote() + pickCharity() entirely.
**Notes:** Also deletes getProposal() and getLevelProposals() (reference deleted Proposal/levelProposalStart/levelProposalCount). Functional governance non-functional between Phase 254 close and Phase 255 open — acceptable since protocol is pre-launch and Phase 256 tests run end-of-milestone. Downstream caller `charityResolve.pickCharity` at AdvanceModule:1634 will revert if exercised between phases (non-blocking).

---

## Claude's Discretion

- Popcount implementation (inline assembly Hamming-weight vs library helper) for activeCount/activeCountAfterFlush — plan-phase or executor picks based on gas bench
- Internal helper-function decomposition of setCharity (monolithic vs `_applyInstant` / `_queueEdit` / `_lockedSlotGuard`) — code-clarity call
- `setCharity` return value (`bool applied`) — default to no return; plan/executor may add if call-site ergonomics favor it

## Deferred Ideas

- Phase 255 — vote/pickCharity rewrite, event signature rewrite, CLEAN-02/03
- Phase 256 — Hardhat test coverage for setCharity branches + edit-queue boundary semantics + vote/pickCharity surface
- Phase 257 — Delta audit + FINDINGS-v33.0.md consolidation; Phase 254 plan output feeds AUDIT-01 + AUDIT-02-(e/f/g/h)
- v34.0+ — Audit of post-v32.0 commits (002bde55 presale auto-deactivate, 2713ce61 setDecimatorAutoRebuy removal)
