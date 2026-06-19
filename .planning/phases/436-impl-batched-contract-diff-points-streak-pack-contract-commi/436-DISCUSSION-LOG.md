# Phase 436: IMPL — Batched Contract Diff (POINTS + STREAK + PACK) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 436-IMPL — Batched Contract Diff (POINTS + STREAK + PACK) [contract-commit gate]
**Areas discussed:** Constant naming (`_BPS`→`_POINTS`), Defensive clamps after widening

---

## Gray-area selection

The 435 DESIGN-LOCK fully specifies the substance (DESIGN-01..04 + the consolidated 436 edit surface + DO-NOT-TOUCH list). Four residual IMPL-discretion knobs were offered.

| Option | Description | Selected |
|--------|-------------|----------|
| Constant naming (`_BPS`→`_POINTS`) | Rename the migrated input anchors, or keep `_BPS` on point values | ✓ |
| Defensive clamps after widening | `_setStreakBase` clamp + the `pendingFlip` uint24 clamp form | ✓ |
| Pre-approval empirical gate | What runs before presenting the diff for hand-review | (left to Claude) |
| Diff review presentation | Grouped-by-track + per-file map vs raw git diff | (left to Claude) |

---

## Constant naming (`_BPS` → `_POINTS`)

| Option | Description | Selected |
|--------|-------------|----------|
| Rename `_BPS`→`_POINTS` (all input anchors) | Identifier matches domain, matches in-file `PASS_*_POINTS`; bigger diff, anchors shift (438 recaptures anyway) | ✓ |
| Keep `_BPS` names, point values | Smallest diff, but `_BPS` on a point value is a stale/misleading name | |
| Rename only the hard cap | Middle ground; leaves most of the `_BPS`-lie in place — inconsistent | |

**User's choice:** Rename `_BPS`→`_POINTS` (all input anchors).
**Notes:** Scope is the score-INPUT anchors only; genuine output-bps constants (ROI, EV-multiplier output, `BPS_DENOMINATOR`, DGNRS reward bps) keep `_BPS` and are not converted (TABLE B / DO-NOT-TOUCH).

### Comment treatment (asked as a follow-up; the answer opened the cap question below)

| Option | Description | Selected |
|--------|-------------|----------|
| Reword to point-domain truth | Rewrite each comment to point reality; drop the false uint16-overflow rationale | |
| Keep the cap reason, drop only the overflow line | Conservative; keeps a sentinel breadcrumb | |
| Minimal — just fix the (bps) tokens | Smallest churn; leaves stale rationale | |

**User's choice:** *Other (free text):* "can we uncap things (leave caps on the things that consume activity score, but uncap streak and score)".
**Notes:** This reframed the comment question into a design question. Source trace (the consumer clamps + the uint16 frozen-stamp storage) showed the hard cap is gameplay-inert and exists only to bound the uint16 store — see the Score cap area. The comment treatment then resolved to D-436-03 (reword unit tokens; keep the overflow rationale because, at cap = 65_534, it becomes true verbatim).

---

## Score cap (raised from the comment follow-up — amends design-lock D-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Cap = `65_534` pts (uint16 storage limit) | Don't floor to 655; keep the storage-guard numeral. Behaviourally identical (consumers clamp ≤400), storage-safe, original comment true | ✓ |
| Keep cap = 655 (design-lock D-03 as written) | Faithful ÷100; imposes an artificial 655-pt ceiling that can clamp dedicated players | |
| Remove the cap entirely | NOT safe — `uint16(score)+1` would wrap past the sentinel; would break the 0-free packing | |

**User's choice:** Cap = `65_534` pts (uint16 storage limit).
**Notes:** Amends D-03. Streak is already effectively uncapped via the locked uint16 latch widening (uint16 source ceiling; further widening breaks the 0-free packing). Planner must reconcile the "655" in `435-DESIGN-LOCK.md` + the 436 edit surface to `65_534` (D-436-09).

---

## Defensive clamps after widening

### `_setStreakBase` clamp

| Option | Description | Selected |
|--------|-------------|----------|
| Keep saturating clamp, re-pin `255`→`type(uint16).max` | Load-bearing for the `recordAfkingSecondary` +1 bump (stops 65536→0 wrap) | ✓ |
| Drop the clamp, bare `uint16(value)` cast | Treats it as dead code; the +1 path can wrap to 0 at the ceiling | |

**User's choice:** Keep saturating clamp, re-pin `255`→`type(uint16).max`.
**Notes:** Source confirmed `recordAfkingSecondary` writes `_setStreakBase(s, _streakBaseOf(s) + 1)` — the clamp guards a live increment path, not future-proofing.

### `pendingFlip` uint24 clamp value

| Option | Description | Selected |
|--------|-------------|----------|
| `type(uint24).max` (16_777_215) | Lossless cast by construction; self-documenting; ~16.7M whole FLIP | ✓ |
| Rounded 16_000_000 (~16M) | Cleaner literal; leaves a sliver of range unused; losslessness no longer by-construction | |

**User's choice:** `type(uint24).max` (16_777_215).
**Notes:** Applies to both accrue sites in `GameAfkingModule` (ticket buyer-bonus + slot-0 quest-reward). `affiliateBase` stays uint32 with its own 100M clamp (untouched).

---

## Claude's Discretion

- **Pre-approval empirical gate:** `forge build` + EIP-170 ceiling check + storage-layout-slot sanity (`Sub` stays one 256-bit slot, 0 free) + baseline-parity smoke before presenting the diff; full behavioural proof in 437/438.
- **Diff presentation:** grouped by POINTS / STREAK / PACK with a per-file change map + TABLE-A/B annotations; one atomic contract commit.
- Exact constant placement / helper naming for the `floor(questStreak/2)` leg; literal-vs-mask choice where equivalent.

## Deferred Ideas

- Truly uncapping streak/score beyond uint16 (would break the 0-free packing + the +1 sentinel; no gameplay benefit since consumers clamp ≤400).
- `:1843`/`:1850` fulfill-write guard + 423 rotation-timer hardening — USER-deferred LOW defense-in-depth (carried from 435).
