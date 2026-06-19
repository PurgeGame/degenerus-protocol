# Phase 445: SPEC — Design-Lock the Implementation Contract - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-19
**Phase:** 445-spec-design-lock-the-implementation-contract
**Areas discussed:** `foilBoostBps` curve anchoring, sibling-producer rarity PMF taper

---

## Framing

The v71.0 design is fully locked in `V71-FOILPACK-FINAL-SPEC.md` + the 23 REQ-IDs in `REQUIREMENTS.md`. The discussion did not re-open design; it surfaced the four engineering items 445 must pin and confirmed their dispositions. Three are delegated to SPEC research (PMF taper form, `foilBoostBps` segment bps, module placement under EIP-170); the calibration policy and the two user-facing forks below were resolved here.

---

## `foilBoostBps` mid-anchor — hard breakpoint vs illustrative

| Option | Description | Selected |
|--------|-------------|----------|
| Hard mid-anchor | Curve must pass through ×5 at score 350; 350 written as a pinned segment breakpoint | |
| Illustrative only | ×2 floor → ×6 ceiling, smooth monotone over the existing 500/30000 knees; 350 not a breakpoint; researcher fits the cleanest curve | ✓ |

**User's choice:** Illustrative.
**Notes:** "~×5 @ 350" describes the shape, not a constraint. SPEC writes the exact segment bps fitted on the existing `ActivityCurveLib` knees; 350 is not written as a boundary.

---

## Sibling-producer rarity PMF — how to "lift the rare tail"

| Option | Description | Selected |
|--------|-------------|----------|
| Flat ×M on every rare tier | Multiply colors 3–7 each by M | |
| Tapered tail, funded from commons | Gold takes full ×M; tiers below taper down progressively; fund by shaving the three 25% commons (colors 0/1/2) | ✓ |

**User's choice:** Tapered tail (free-text refinement).
**Notes:** Verbatim — "the less rare traits dont need full weight, just start with 6x for gold and scale down as you go down and reduce the 3 25% ones." Resolves the flat-×M overflow problem (naive ×M on every tier exceeds available probability mass at high M). Gold = baseline(0.781%)×M exactly; symbol stays uniform; the gold-odds anchors are preserved because they depend only on `p_gold`. Exact taper schedule delegated to SPEC research with the conservation/monotonicity/validity acceptance constraints recorded in CONTEXT.md D-03.

---

## Claude's Discretion (delegated to SPEC research, bounded by CONTEXT.md acceptance)

- Exact functional form of the rare-tail taper (geometric / linear-in-rank / per-threshold-bucket reallocation).
- Exact segment bps of `foilBoostBps`.
- Module placement (`GAME_FOILPACK_MODULE` vs roomy existing module + facade stub), driven by the live EIP-170 measurement.
- Calibration policy: hold the locked 5/65-faces table; Monte-Carlo confirms ≈2 faces/30d and flags if materially off (never silently retune).

## Deferred Ideas

- Indexer parity events for the foil buy + match claim (additive; post-feature).
- (carried v70) mutation + Halmos formal on the foil module; `roi`/`wwxrp` direct-body coverage.
