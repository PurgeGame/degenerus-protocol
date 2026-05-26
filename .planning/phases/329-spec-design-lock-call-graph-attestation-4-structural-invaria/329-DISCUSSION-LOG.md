# Phase 329: SPEC — Design-Lock + Call-Graph Attestation + 4 Structural Invariants - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-26
**Phase:** 329-spec-design-lock-call-graph-attestation-4-structural-invaria
**Areas discussed:** ROUTER-07 reentrancy, ROUTER-06 no-work signal, GAS-03 day-start epoch, Invariant-(c) free-fallback caller, NEW autoResolve sub-gas re-peg

---

## ROUTER-07 — router reentrancy disposition

| Option | Description | Selected |
|--------|-------------|----------|
| nonReentrant guard on doWork | Guard on doWork only; security floor; one-function deviation from AfKing's CEI-everywhere ethos. The roadmap default. | |
| Composed-CEI proof, no guard | Preserve AfKing's no-guard invariant; prove CEI-clean + keeper-never-a-payee blocks double-pay. | |
| Guard + keep CEI proof | Belt-and-suspenders. | |

**User's choice:** Free-text — *"dowork is never going to send eth to the caller and all contracts it touches are trusted so I dont see how it matters"* → **NO guard** (the composed-CEI / no-untrusted-send disposition).
**Notes:** Reflected back: doWork pays bounty as `creditFlip` flip-credit (keeper never a payee) and sends ETH only to pinned `ContractAddresses.*`, never to an untrusted address (pull-pattern `claimableWinnings`). The user confirmed: "this will not send eth to any address that is untrusted." SPEC author must grep-attest the no-untrusted-send claim per leg vs `0cc5d10f`; TST-02 double-pay regression stays as empirical backstop regardless. (D-01/01a/01b.)

---

## ROUTER-06 — doWork no-work signal

| Option | Description | Selected |
|--------|-------------|----------|
| Revert (NoWork error) | Dedicated error when no leg has work — consistent with EmptyAutoBuy/NoSubscribersAutoBought. | ✓ |
| Return bool/sentinel | Keeper-friendly multicall-bundling; breaks the established revert idiom. | |
| Revert, views are the real probe | Revert + treat discovery views as the canonical pre-call check. | |

**User's choice:** Revert (NoWork error).
**Notes:** Fires only when all three O(1) predicates are empty; a routed leg only enters when its predicate has work, so the leg's own revert never trips. (D-02.)

---

## GAS-03 — day-start epoch

| Option | Description | Selected |
|--------|-------------|----------|
| Design-1 satisfies it | Advance multiplier single-sourced in AdvanceModule + returned; router never recomputes; AfKing autoBuy epoch left as-is (different category). | ✓ |
| Physically unify both formulas | One shared epoch helper; risks shifting AfKing's tested autoBuy timing; conflates two semantics. | |
| Unify only the shared constant | Factor out the 82620/DEPLOY_DAY_BOUNDARY constants without changing elapsed semantics. | |

**User's choice:** Design-1 satisfies it (recommended).
**Notes:** The two formulas measure different things (AfKing autoBuy = elapsed since current absolute day, resets at midnight; AdvanceModule advance = elapsed since the lagging game-day, grows across a multi-day stall) — both correct, not a duplicated computation. SPEC author grep-attests both vs `0cc5d10f` and records why they differ. (D-03/03a.)

---

## Invariant (c) — guaranteed free-fallback advanceGame() caller

| Option | Description | Selected |
|--------|-------------|----------|
| Rely on existing paths, no new code | 30-min universal bypass makes standalone advance permissionless to all; router bounty covers first 30 min; VAULT/sDGNRS wrappers; 120d death-clock. | ✓ |
| Designate VAULT/sDGNRS as explicit backstop | Name them THE backstop + wire a recurring trigger. More mechanism. | |
| Add a new always-callable unrewarded fallback | New code path; unnecessary given the 30-min universal bypass. | |

**User's choice:** Rely on existing paths, no new code (recommended).
**Notes:** PRIMARY = router advance leg (rewarded/stall-escalating, re-homed) — primary incentive preserved, just moved. SECONDARY = `advanceGame()` permissionless to anyone 30+ min after the boundary (`_enforceDailyMintGate` tier-2 `~:1008`) + `DegenerusVault.gameAdvance()`/`StakedDegenerusStonk.gameAdvance()`; first-30-min window covered by the router bounty + participants/VAULT (no gap). TERTIARY = 120d death-clock. (D-04.)

---

## NEW — autoResolve sub-gas "lose" re-peg (mid-discussion user request)

> User asked to "make the degenerette resolver pay 1 burnie per tx flat if you resolve 5+ rolls
> (or something like that)… a 'lose'… swap into the same button as the main auto-work button…
> but not in a way that could ever be remotely exploitable."

| Option | Description | Selected |
|--------|-------------|----------|
| Defer — it already works; unify at frontend | autoResolve already safe (break-even, WWXRP-excluded, self-resolve-neutral); the "one button" is a frontend concern. | |
| Re-peg autoResolve to a sub-gas "lose" — keep it separate | Recalibrate the bounty to a sub-gas flat-per-tx lose; no router change; "one button" via frontend. | ✓ |
| Fold into doWork on-chain — extend the signature | doWork(maxCount, players[], betIds[]); reverses ROUTER-05; expands all 5 phases. | |

**User's choice:** Re-peg autoResolve to a sub-gas "lose" — keep it separate.
**Notes:** Surfaced two obstacles to the on-chain "same button": (1) autoResolve needs caller-supplied `(players[], betIds[])` — no O(1) discovery, can't join doWork without an unbounded scan (ROUTER-04 violation) — almost certainly why it was excluded; (2) a literal "1 BURNIE" drifts, so peg ETH-equivalent. Anti-exploit proof: flat reward pegged STRICTLY below the gas to resolve the ≥5 gate-minimum → every qualifying tx net-negative, splitting only multiplies the loss → no positive EV anywhere. WWXRP stays excluded (gate counts non-WWXRP). Registered as GAS-06 (Phase 331) + TST-05 (Phase 332); code rides BATCH-02 (Phase 330); ROUTER-05 reworded. SPEC (D-05d) must verify no invariant requires losing-bet resolution before dropping the break-even incentive. (D-05.)

---

## Claude's Discretion

The remainder of phase 329 is grep-attestation resolved from source vs `0cc5d10f` (NOT user
decisions): the `advanceGame` `(uint8 mult, bool rewardable)` encoding + whether `rewardable`
covers all three `:189/:225/:468` sites; the discovery-view signatures + location; the `maxCount`
semantics across legs; the v48 KEEP-04 affiliate-code passthrough survival; the AfKing CEI/cursor
anchors; the producer-before-consumer edit-order map; and the plan/wave decomposition. (See
329-CONTEXT.md § Claude's Discretion.)

## Deferred Ideas

- **`autoResolve` FOLDED INTO the on-chain router** — deferred (architecturally blocked by the
  caller-supplied-arrays requirement); the unified "one button" lives at the frontend. NOTE: the
  autoResolve *bounty re-peg* is NOT deferred — it is the in-scope GAS-06/TST-05 addition.
