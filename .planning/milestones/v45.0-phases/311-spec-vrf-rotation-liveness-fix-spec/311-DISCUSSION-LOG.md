# Phase 311: SPEC — VRF-Rotation Liveness Fix - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-22
**Phase:** 311-spec-vrf-rotation-liveness-fix-spec
**Areas discussed:** Fix shape, Unlock policy, wireVrf lock + dedup, Orphan-recovery breadth (all 4 selected)

---

## Fix shape

| Option | Description | Selected |
|--------|-------------|----------|
| Re-issue in-flight | Re-fire VRF on the new coordinator for the same index; existing callback fills it; retryLootboxRng failsafe. Fastest recovery, minimal code, freeze-safe (old word abandoned, new word unpredictable). | ✓ |
| Queue + apply split | queueVrfRotation stores pending config; applyVrfRotation swaps in after resolve/timeout. Cleanest no-mid-window-mutation narrative but two-step UX + adds recovery latency when the old coordinator is dead. | |
| You decide at SPEC | Defer the shape to the design-intent trace. | |

**User's choice:** Re-issue in-flight (D-01).
**Notes:** The emergency procedure exists because the old coordinator is dead, so waiting for the in-flight word (queue+apply) is futile. Re-issue re-points to the live new coordinator immediately. Freeze-safe because admin rotation is EXEMPT-class and the §9d governance rows are maximalist-catalog, not live player vectors.

---

## Unlock policy

| Option | Description | Selected |
|--------|-------------|----------|
| Surgical preserve+re-issue, both paths | Drop the unconditional force-unlock; preserve whichever flag is in flight (rngLockedFlag daily / LR_MID_DAY mid-day) and re-issue; re-point config only when nothing's pending. Uniform behavior, no orphan either path. | ✓ |
| Minimal: fix mid-day only | preserve+re-issue only for mid-day; keep daily force-unlock. Smallest diff, two rotation behaviors. | |
| You decide at SPEC | Defer to the design-intent trace. | |

**User's choice:** Surgical preserve+re-issue, both paths (D-02).
**Notes:** Clarified that the daily path self-heals under the current force-unlock; uniform treatment chosen for a single coherent rotation behavior, not because daily is independently broken. Also avoids zeroing a just-delivered-but-unprocessed word.

---

## wireVrf lock + dedup

| Option | Description | Selected |
|--------|-------------|----------|
| Lock + dedup into shared helper | wireVrf init-only (reverts once wired); both functions call a shared internal _setVrfConfig; updateVrf is sole post-init mutator. Closes HANDOFF-86/88/90 + ADMA-01. | ✓ |
| Lock only, no dedup | Add the init-only revert but leave config-writes inline/separate. Smaller diff, mild duplication remains. | |
| You decide at SPEC | Defer. | |

**User's choice:** Lock + dedup into shared helper (D-03 lock + D-04 dedup).
**Notes:** Consistent with the Phase 310 D-01/D-02 single-source-of-truth preference. Wired-detection mechanism (vrfWired flag vs address check) left to SPEC discretion.

---

## Orphan-recovery breadth

| Option | Description | Selected |
|--------|-------------|----------|
| Narrow + verify gate-reachability | Re-issue fills the in-flight index AND un-blocks the drain gate, restoring the existing _backfillOrphanedLootboxIndices (:1208) for any residual orphans. SPEC verifies that reachability. No new wiring; LR_MID_DAY single-in-flight gate bounds orphans to one per rotation. | ✓ |
| Belt-and-suspenders no-orphan guarantee | Additionally make orphan-backfill reachable independent of the drain gate / add a recovery entry point so NO index can ever be orphaned. More surface, stronger structural invariant. | |
| You decide at SPEC | Defer based on whether a residual orphan path survives. | |

**User's choice:** Narrow + verify gate-reachability (D-05).
**Notes:** SPEC obligation — explicitly trace and confirm re-issue restores the :1208 backfill path; escalate to belt-and-suspenders only if a residual orphan path survives.

---

## Claude's Discretion

- Exact re-issue mechanics (`requestRandomWords` on the new coordinator, `rngRequestTime = block.timestamp`, daily-vs-mid-day branch structure).
- `wireVrf` wired-detection mechanism + `_setVrfConfig` signature/visibility.
- Preserve existing `totalFlipReversals` carry-over behavior on rotation (`:1711-1714`).

## Deferred Ideas

- Belt-and-suspenders gate-independent orphan backfill — deferred unless the SPEC reachability trace finds a residual orphan path.
- Queue+apply rotation (`pendingVrfRotationPacked`) — rejected fix shape; recorded as the SPEC's documented alternative.
- Non-VRF v44 backlog (~115 anchors), V-081 dedicated regression, jackpot pending-pool new work — out of scope for v45.0.
