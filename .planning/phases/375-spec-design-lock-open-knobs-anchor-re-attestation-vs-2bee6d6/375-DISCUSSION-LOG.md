# Phase 375: SPEC — Design-Lock (open knobs) + Anchor Re-Attestation vs `2bee6d6f` + Edit-Order Map - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-06
**Phase:** 375-spec-design-lock-open-knobs-anchor-re-attestation-vs-2bee6d6
**Areas discussed:** AFPAY/PACK sequencing, AfkingSpent emission breadth, CURSE counter cap, SMITE protocol-addr skip

---

## AFPAY / PACK sequencing

| Option | Description | Selected |
|--------|-------------|----------|
| Feature-first *(Claude recommended)* | Land the AFPAY waterfall on today's two raw mappings first (small, independently auditable), then add the accessor layer + repack as a separated follow-on in the same diff. Best for the contract-boundary hand-review. | |
| Accessor-first | Introduce the accessor layer (+ packed slot) first, route all refs through it, then write the waterfall against accessors once. Cleanest end-state, no waterfall churn — but the feature delta is harder to isolate in review. | ✓ |

**User's choice:** Accessor-first (overrode Claude's feature-first recommendation).
**Notes:** SPEC-01 explicitly left "feature-first vs accessor-first" open to decide here, so this is the intended lock, not a conflict with the docs' "feature-first" phrasing. Edit order becomes PACK-01 → PACK-02 → AFPAY-01…07; the `claimablePool == Σ` solvency invariant is centralized in the accessor layer before the new spend path exists.

---

## AfkingSpent emission breadth

| Option | Description | Selected |
|--------|-------------|----------|
| Every afking debit *(Claude recommended)* | Emit at each afking draw — ticket mint (`_processMintPayment`) AND whale/presale/lootbox (shared `_settleShortfall` helper). Full observability of the headline feature; marginal gas (one LOG, off the advanceGame hot path). | ✓ |
| Ticket mint only | Emit only from `_processMintPayment`; whale/presale/lootbox afking draws stay silent, mirroring how claimable spends are silent outside `_processMintPayment`. Less gas, more consistent with existing convention. | |

**User's choice:** Every afking debit.
**Notes:** Deliberate departure from claimable's silence-outside-`_processMintPayment` — flag as intentional in the SPEC.

---

## CURSE counter cap

| Option | Description | Selected |
|--------|-------------|----------|
| 20 points *(Claude recommended)* | 10 ghost-cashouts / 10 stacks to max; −2000 bps max penalty; clean headroom above the 10-pt smite ceiling; uint8-safe. The plan's recommended value. | ✓ |
| Saturate at 254 | Effectively uncapped — just prevents the uint8 wrap. Max penalty far beyond any real score. | |

**User's choice:** 20 points (`CURSE_COUNT_CAP = 20`).
**Notes:** Doubles as the mandatory uint8-wrap guard.

---

## SMITE protocol-addr skip

| Option | Description | Selected |
|--------|-------------|----------|
| Keep the skip *(Claude recommended)* | VAULT/SDGNRS/GNRUS can't be cursed or smited. Protects the sDGNRS redemption-snapshot score (`StakedDegenerusStonk:942`) and keeps smite consistent with the cashout-curse SET. | ✓ |
| Literal anyone-non-afker | Honor "anyone who isn't an active afker is smittable" literally — protocol addrs included. Simpler rule, but risks corrupting sDGNRS redemption accounting + wastes deity BURNIE on non-players. | |

**User's choice:** Keep the skip (both `smite()` and the cashout-curse SET).
**Notes:** Correctness/safety driven (sDGNRS redemption snapshot).

---

## Claude's Discretion

- **Staleness day-basis → `_currentMintDay()`** for the `_maybeCurse` compare (matches the plan's §3 sketch + the ticket cure-stamp; ≤1-day skew vs `_simulatedDayIndex()` is immaterial against a 5-day window). User did not object.
- **SPEC-execution items (not user decisions):** anchor re-attestation vs `2bee6d6f`; `purchaseWith` dead-confirm; self-smite sanity; the producer-before-consumer edit-order map; the SOLVENCY accessor-invariant location.

## Deferred Ideas

None — discussion stayed within the SPEC phase scope.
