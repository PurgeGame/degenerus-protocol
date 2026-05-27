# Phase 329: SPEC — Design-Lock + Call-Graph Attestation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-26 (RE-SPEC after the v49.0 keeper-router pivot)
**Phase:** 329-spec-design-lock-call-graph-attestation-4-structural-invaria
**Areas discussed:** autoBuy-first vs advance liveness, Unified bounty + ROUTER-07 (→ flat-per-tx redesign), New keeper-gas DOs scope

> Context handling: **Update in place** (the prior CONTEXT/SPEC/ATTEST docs reflect the superseded
> original router design). The 5 redesign changes (RD-1..RD-5) were carried forward from
> `330-ROUTER-REDESIGN-INTENT.md` as already-locked and were NOT re-asked.

---

## autoBuy-first vs advance liveness

| Option | Description | Selected |
|--------|-------------|----------|
| Accept invariant (c), no carve-out | Re-attest (c) under the new order; no advance-preemption (would conflict with same-cycle-reveal); buys bounded so advance only briefly delayed; 30-min permissionless fallback + wrappers + 120d death-clock cover the worst case | ✓ |
| Add advance-overdue preemption | Advance jumps ahead of autoBuy once stale past a threshold; more robust but conflicts with same-cycle-reveal + adds a frozen-contract constant | |

**User's choice:** Accept invariant (c), no carve-out.
**Notes:** Consequence recorded — D-04 amended: under autoBuy-first, first-30-min advance during a buy
backlog relies on the participant/pass/DGVE-majority bypass tiers + (at 30 min) the permissionless
fallback, NOT the router bounty. Worst-case advance delay is bounded and accepted.

---

## Unified bounty + ROUTER-07 (→ simplified flat-per-tx redesign)

| Option | Description | Selected |
|--------|-------------|----------|
| Leg returns final BURNIE-wei | Legs return computed reward; doWork does one creditFlip; advance returns (mult, rewardable) | (superseded) |
| Leg returns raw work-count | Legs return counts; doWork centralizes all peg math | (folded into the simplification) |

**User's choice:** "can we simplify the bounty system a little?" → then "make doWork parameterless …
flat per tx. maybe 1x for open 1.5x for buy and 2x for advance (scaled with the multiplier for
advance) … 1x is an average max-laden tx at .5 gwei worth of burnie flip" → then "also no multi for
mid day ticket batches."

**Resolved model (D-07):** `doWork()` parameterless (D-06 sentinel superseded); standalone
`autoOpen(count)`/`autoBuy(count)` parametered + unrewarded (emergency). Flat per-tx: advance `2×·mult`
(stall NEW-DAY only; mid-day partial-drain `mult=1`), buy `1.5×`, open `1×` pro-rated below ~5 boxes.
One base unit, `×PRICE_COIN_UNIT/mp`, one creditFlip, one-category early-return. GAS-03/D-03 dissolved
(advance is the sole stall epoch; delete AfKing autoBuy stall ladder + epoch + the open-leg gas-units
machinery). Per-leg faucet doctrine: advance/buy no gate (real-work-bounded + once/day/sub + protocol
auto-subs); open pro-rated (frequent small mid-day opens).

**Follow-up locks:**
| Question | Options | Selected |
|---|---|---|
| 1×/1.5×/2× ratios | GAS-331 starting estimates / Lock now | GAS-331 starting estimates |
| Open knee | ~5 calibrate at GAS-331 / Lock literal 5 | ~5, calibrate at GAS-331 |

Confirmed: "those numbers are fine to start with."

**ROUTER-07:** NO guard (D-01 carries forward, stronger under the unified single-creditFlip).

---

## New keeper-gas DOs scope

| Option (multiSelect) | Description | Selected |
|--------|-------------|----------|
| Batched keeper read | NEW batchPurchaseForKeeper/keeperSnapshot; collapses claimableWinningsOf STATICCALLs; subsumes GASOPT-02 | ✓ |
| Remove :838 isOperatorApproved | Drop per-iteration check (~2.8k/player); SUB is the consent unit; keep :443; gated on 333 SWEEP OPEN-E re-attestation | ✓ |
| Drop AutoBought event | ~1.5k/player; BUT tests heavily key on it — requires storage/balance-oracle test migration | ✓ |

| Phasing | Options | Selected |
|---|---|---|
| Register | New GASOPT-03+ in 330 IMPL / Handle in 331 GAS / Defer | New GASOPT-03+ in 330 IMPL |

**User's choice:** all 3 in scope as GASOPT-03/04/05 in Phase 330 IMPL.
**Notes:** GASOPT-04 (drop AutoBought) — the event-removal + test-oracle migration land together in 330
(suite breaks immediately); the no-double-buy invariant must be re-expressed in `lastAutoBoughtDay`
storage + pool/balance deltas without weakening SAFE-03. GASOPT-05 (:838) carries a blocking 333-SWEEP
OPEN-E re-attestation. GASOPT-02 folds into GASOPT-03.

---

## Claude's Discretion

- Attestation baseline + held-diff disposition (user delegated): attest against frozen `0cc5d10f`
  (line-drift noted vs the held tree); 330 re-IMPL keeps the survivors (advance re-home tuple,
  `degeneretteResolve` rename, GASOPT-01, interfaces) and reworks the now-superseded bounty
  implementation.
- All `file:line` grep-attestations; advanceGame return encoding; the 3 creditFlip site classification;
  discovery-view forms; the D-07/D-03 deletion surface; KEEP-04 passthrough survival; CEI anchors; the
  SPEC section structure + survivors-vs-reworked edit-order map + plan/wave decomposition.

## Deferred Ideas

- `degeneretteResolve` folded into the on-chain router (architecturally blocked; frontend "one button").
- Keeper off-chain indexer / webpage (separate frontend track).
- Milestone-level out-of-scope items (see REQUIREMENTS.md § Out of Scope).
