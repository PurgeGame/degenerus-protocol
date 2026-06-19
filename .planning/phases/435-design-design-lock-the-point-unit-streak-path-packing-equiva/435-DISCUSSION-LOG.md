# Phase 435: DESIGN — Design-Lock the Point Unit, Streak Path, Packing & Equivalence - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 435-DESIGN — Design-Lock the Point Unit, Streak Path, Packing & Equivalence
**Areas discussed:** Pre-streak cap rework, Quest-streak floor rule, Equivalence posture, pendingFlip cap & width

---

## Pre-streak cap rework (DESIGN-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Widen latch to uint16, drop clamp+hack | Use the 8 bits freed by narrowing pendingFlip to widen subStreakLatch uint8→uint16, matching state.streak. Carried-in pre-streak snapshots exactly; the 255 clamp AND the finalize floor-hack (DegenerusQuests:546-551) are deleted. | ✓ |
| Cap at activity-relevant ceiling | Keep a narrower int but cap only where extra streak can no longer raise the score (~1310 at 0.5pt/quest under the 65534 hard cap); keeps the finalize restore-logic in some form. | |
| Let me describe it | USER describes a specific shape. | |

**User's choice:** Widen latch to uint16, drop clamp+hack.
**Notes:** The grievance is the uint8/255 clamp + the compensating finalize floor-hack — a width mismatch papered over twice. Widening to match the uint16 manual streak removes both band-aids. Directly enabled by the pendingFlip narrowing (8 freed bits).

---

## Quest-streak floor rule (DESIGN-01)

| Option | Description | Selected |
|--------|-------------|----------|
| floor(questStreak / 2) | 1 pt per 2 quests; odd quests' trailing 0.5 pt dropped. Simplest exact-integer rule, matches the seed. | ✓ |
| round-half-up (q+1)/2 | Preserves the half-point by rounding up at odd streaks. | |
| Keep half-point granularity | Represent the score in half-points internally (×2). | |

**User's choice:** floor(questStreak / 2).
**Notes:** Quest streak is the sole sub-point contributor (50 bps each). This is the only place precision is intentionally lost.

---

## Equivalence posture (DESIGN-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Accept + document the boundary shift | The only affected actor sits exactly at threshold−0.5 pt with an odd quest; flooring drops that single tip; document it. | ✓ |
| Nudge thresholds to preserve tips | Adjust point-domain threshold constants so the exact pre-change boundary behaviour is preserved. | |
| Require exact equivalence everywhere | Choose floor rule + thresholds so NO reachable score changes any outcome. | |

**User's choice:** Accept + document the boundary shift.
**Notes:** The equivalence argument rests on scale-invariance of the linear interpolations (score·Δ/range, ÷100 of score and range preserves the ratio); the only divergence is this accepted odd-half-point de-minimis case.

---

## pendingFlip cap & width (DESIGN-03)

| Option | Description | Selected |
|--------|-------------|----------|
| uint24 (~16.7M FLIP clamp) | Frees exactly 8 bits to widen the latch to uint16; 16.7M is far above any realistic per-sub bank. | ✓ |
| Tighter (uint20 / uint16) | Narrow further if the realistic max bank is much smaller; leaves uneven bits for the latch. | |
| You derive the ceiling | Compute the realistic max from per-day reward × run length. | |

**User's choice:** uint24 (~16.7M FLIP clamp).
**Notes:** Pairs exactly with the latch widening — accumulator stays affiliateBase(32)+pendingFlip(24)+subStreakLatch(16)=72 bits, the Sub struct stays one 256-bit slot.

## Claude's Discretion

- Exact constant naming / where the floor + point cap live in source (436 IMPL detail).
- The precise uint24 clamp constant value (exact uint24 ceiling vs rounded ~16.7M).

## Deferred Ideas

- `:1843`/`:1850` `== 0` fulfill-write guard + the 423 rotation-timer hardening — USER-deferred LOW defense-in-depth (REQUIREMENTS.md v2); out of scope unless folded into the 436 IMPL diff.
