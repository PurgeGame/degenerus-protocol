# Phase 452: GEN (generator-first; NO contract edit) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-21
**Phase:** 452-GEN (generator-first; NO contract edit)
**Areas discussed:** DEC-01 rig mechanism, DEC-02 EV-equality, DEC-03 pay floor

---

## DEC-01 — WWXRP rig mechanism (`_rigWwxrpResult`)

| Option | Description | Selected |
|--------|-------------|----------|
| R2 — score-bearing rig | Force only cells that raise S under Variant-2 (unmatched non-hero symbol, or unmatched color on a symbol-matched quadrant); keeps display==score honest + ~60% near-win lift; m≥7 cap → P(S=9) invariant | ✓ |
| R1 — leave rig, accept no-op forces | Keep the existing any-unmatched-ordinary-cell pool; some forces give +0 to S; breaks display==score honesty, dilutes the lift; rigged dist must be re-derived anyway | |

**User's choice:** R2 ("do r2")
**Notes:** Both options require re-deriving the rigged distribution for Variant-2, so R1 is not actually simpler — R2 is cleaner AND honest. Generator's `p_score_distribution_rigged` re-derived to force only score-bearing cells, with an explicit empty-eligible-pool case (no lift when the only unmatched cells are the excluded hero symbol + no-op colors).

---

## DEC-02 — EV-equality across picks (the Variant-2 wrinkle)

| Option | Description | Selected |
|--------|-------------|----------|
| A — 5 per-N tables, averaged over hero placement | Keep the current dispatch; GEN measures the hero-gold vs hero-common drift and reports it; accept residual drift | ✓ |
| B — index by (N, hero-is-gold) | ~8–9 tables + a `_getBasePayoutBps` dispatch tweak for exact EV-equality; more constants, more contract surface to audit | |

**User's choice:** Option A — and relaxed the escalation trigger.
**Notes:** USER: "if the gold-payout is slightly different for wwxrp I don't care it's a worthless shitcoin, dont worry about it." → residual gold-payout drift is a don't-care; do NOT escalate to Option B for ordinary drift. GEN still measures + reports the number (free, EVEQ-01). Option A is solvency-safe regardless: every per-N table is asserted neutral-or-just-under 100 centi-x, so hero-gold vs hero-common differ only by a hair of RTP and both stay ≤100. Consistent with the standing WWXRP-by-design ruling.

---

## DEC-03 — Pay floor stays S≥2

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — keep S≥2 | A lone ordinary symbol = S=1 pays 0; hero symbol alone (S=2) or a full color+symbol double (S=2) pays | ✓ |
| Change the floor | Pay a lone ordinary symbol, or raise the floor | |

**User's choice:** Yes ("payout stays min >=s2")
**Notes:** Matches the foil precedent's "double matters"; consistent with SCORE-02.

---

## Claude's Discretion

- Internal form of the re-derived `p_score_distribution_rigged` (enumeration order, empty-pool expression), provided the self-asserts hold.
- Doc-comment wording refresh on `_score` / `_rigWwxrpResult` / constant blocks.

## Deferred Ideas

None — discussion stayed within phase scope.
