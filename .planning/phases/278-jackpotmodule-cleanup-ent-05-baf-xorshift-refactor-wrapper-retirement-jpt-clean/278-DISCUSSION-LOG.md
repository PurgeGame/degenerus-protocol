# Phase 278: JackpotModule Cleanup + ENT-05 BAF Xorshift Refactor + Wrapper Retirement (JPT-CLEAN) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean
**Areas discussed:** ENT-05 xorshift refactor shape, xTICKET_SCALE cleanup meaning, TST-CROSS-01 assertion strategy, entropyStep deletion scope

---

## ENT-05 BAF Xorshift Refactor Shape

First pass — user responded "Other": "what is the practical effect of this" — answered in plain text (distribution-quality fix, not security; ~sub-percentage-point chi-square-detectable skew; audit-cleanliness value; near-zero cost) then re-asked.

| Option | Description | Selected |
|--------|-------------|----------|
| Swap to keccak hash2 | Replace entropyStep with hash2 so path/level rolls consume a full-diffusion keccak word; demotes EXC-04, enables deleting entropyStep, NET-NEGATIVE bytecode; outputs change vs v39 | ✓ |
| Document xorshift as locally-required | Keep entropyStep, add justifying NatSpec; EXC-04 stays NARROWS; byte-equivalent | |
| Narrower bit-discipline fix | Keep entropyStep for evolution, re-derive only path/level bits from a keccak chunk | |

**User's choice:** Swap to keccak hash2
**Notes:** User asked for the practical effect before deciding; chose the swap after understanding it is a distribution-quality / audit-cleanliness fix at near-zero cost.

### Follow-up: chain evolution mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Chain on returned word | _jackpotTicketRoll does entropy = hash2(entropy, ...) and returns it; roll 2 input = roll 1 output | ✓ |
| Explicit roll counter salt | Pass a roll index as hash2's 2nd arg; adds a threaded parameter | |
| Plan-phase decides | Lock only that per-roll uniqueness is preserved + tested | |

**User's choice:** Chain on returned word

### Follow-up: test strategy

| Option | Description | Selected |
|--------|-------------|----------|
| New post-refactor invariant | Assert chi-square uniformity + seed-uniqueness + bits[200..215] independence | ✓ |
| Byte-equivalence | Not applicable — keccak swap changes outputs intentionally | |
| Both — new invariant + v39 divergence proof | New invariant plus a test confirming deliberate divergence | |

**User's choice:** New post-refactor invariant

---

## xTICKET_SCALE Cleanup Meaning

First pass — user responded "Other": "can we try to unify things as best we can so it is clear that other than purchases (and whale passes) we always award one ticket when awarding entries" — reflected back, flagged the D-276/D-277 supersession tension, then re-asked.

| Option | Description | Selected |
|--------|-------------|----------|
| Comment + cast hygiene only | Keep synthetic ×100 emit, normalize casts + comments; zero output change | |
| Drop synthetic ×100 on trait-matched sites | Trait-matched emits whole; changes output, leaves BAF inconsistent | |
| Unify all 3 sites on one semantic | Reopen the event surface to one consistent meaning | (intent) |

### Re-ask: unification scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full unify on whole tickets | All 3 JackpotTicketWin sites emit whole counts; roundedUp carries Bernoulli direction; supersedes D-276-EVT-STATUSQUO-01 + D-277-NO-PREROLL-01; needs roadmap correction | ✓ |
| Keep scaled, make consistency explicit | Leave all 3 emitting scaled, document via NatSpec; preserves D-276/D-277 | |
| Full unify + keep pre-roll via roundedUp only | Same as full unify with explicit info-loss acknowledgment | |

**User's choice:** Full unify on whole tickets
**Notes:** User wants the whole-ticket award model legible in the event surface. Accepted consequences: supersedes D-276-EVT-STATUSQUO-01 + D-277-NO-PREROLL-01; loses the exact pre-Bernoulli fraction on the BAF site (roundedUp retained as sole Bernoulli signal); roadmap SC1 + REQUIREMENTS text correction needed (docs follow-up); Phase 276/277 jackpot-event test assertions updated in this phase's test wave.

---

## TST-CROSS-01 Assertion Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Direct rem-byte snapshot | Snapshot ticketsOwedPacked low-8-bits before/after each surface family; rem stays 0 through all whole-ticket opens, flips only after mint-boost | ✓ |
| EV aggregation / cross-correlation | Many-seed mean/correlation check; doesn't directly assert the rem byte | |
| Per-surface isolation + combined equality | Run isolated + combined, assert sum equality; heavier, rem still needs a direct check | |

**User's choice:** Direct rem-byte snapshot

### Follow-up: test depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full-stack invocation | Call real openLootBox / resolveLootboxDirect / _awardJackpotTickets etc. so the shared slot is genuinely exercised | ✓ |
| Direct-call helpers | Reuse JackpotBernoulliTester-style direct entry; may bypass the shared slot | |
| Plan-phase decides | Lock only that the shared slot must be exercised | |

**User's choice:** Full-stack invocation

---

## entropyStep Deletion Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Delete it, in this phase | Remove entropyStep from EntropyLib; update NatSpec + MintModule:649 comment + JackpotBernoulliTester.sol; EntropyLib keeps only hash2 | ✓ |
| Keep entropyStep | Leave as dead-but-harmless library code | |
| Delete, but defer to Phase 280 | Land the swap now, delete in the terminal phase | |

**User's choice:** Delete it, in this phase
**Notes:** Aligns with feedback_no_dead_guards.md + feedback_frozen_contracts_no_future_proofing.md. MintModule:649 is a design-rationale comment — drop the dead-function name, keep the keccak-over-XOR rationale.

---

## Claude's Discretion

- Exact `hash2` second argument (self-mix vs fixed salt) in `_jackpotTicketRoll`, provided per-roll uniqueness holds.
- Whether the bits[200..215] Bernoulli sub-roll slice offset stays at 200 under the full keccak word.
- Exact NatSpec / comment rewrites per `feedback_no_history_in_comments.md`.
- Storage-layout byte-identity proof recipe.
- Theoretical worst-case gas path derivation per `feedback_gas_worst_case.md`.
- Exact test filenames + placement.

## Deferred Ideas

- ROADMAP.md + REQUIREMENTS.md text correction for the D-278-EVT-UNIFY-01 supersession (SC1 "no behavior change" no longer holds) — docs-only follow-up.
- Whole-BURNIE floor — Phase 279 (BUR).
- Terminal delta audit + EXC-04 RE_VERIFICATION + findings consolidation — Phase 280.
- MintModule's own xorshift / `_queueTicketsScaled` / `_rollRemainder` / `rem` byte — out of scope per D-40N-MINTBOOST-OUT-01.
