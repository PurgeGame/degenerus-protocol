# Phase 334: SPEC — Design-Lock + MINTDIV Reachability Proof + RNGAUDIT Structure + Call-Graph Attestation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-27
**Phase:** 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu
**Areas discussed:** Whale-pass claim shape, Whale-pass stats timing, AfKing scope + BURNIE sink, MINTDIV-02 fix posture

---

## Whale-pass claim shape

### Access model for claimWhalePass()

| Option | Description | Selected |
|--------|-------------|----------|
| Caller-is-beneficiary | claimWhalePass() for msg.sender only; holder claims + pays own gas; matches seed rationale; zero griefing surface (Claude recommended) | |
| Permissionless with beneficiary arg | claimWhalePass(address beneficiary); anyone triggers, caller pays gas; fits the 'crank others' work' idiom | ✓ |

**User's choice:** Permissionless with beneficiary arg.
**Notes:** Coherent because claim is decoupled from open (open is O(1), nothing forced to claim). HARD CONSTRAINT recorded: claim must never be auto-triggered by open/autoOpen, or the open-time gas misallocation returns.

### Multi-roll / anchoring (user asked "what does startLevel really matter here?")

| Option | Description | Selected |
|--------|-------------|----------|
| Accumulate list/queue of startLevels | Push each roll's startLevel; preserves roll-time absolute levels exactly | |
| Single slot, materialize-old-on-new-roll | O(1) storage but re-introduces an inline 100-loop on the rare double-roll | |
| Single slot, overwrite | Drops the first jackpot; breaks equivalence | |

**User's choice (free text):** *"what does startlevel really matter here?"* → then *"whale passes (after the very beginning) always give 100 levels of tickets which is worth the same whenever, I don't think this matters. whenever they claim the whale pass is fine."*
**Notes:** Resolved to **claim-time anchoring** — pending = a plain COUNT (no startLevel), multi-roll = increment, grant anchored at claim-time currentLevel+1, freeze-safe by construction. TST-01 equivalence reinterpreted to "correct claim-time grant" (not byte-identical to old). Worth-the-same economics → re-attest at SWEEP economic-analyst. Early-game ≤level-10 bonus band is the noted exception.

---

## Whale-pass stats timing

| Option | Description | Selected |
|--------|-------------|----------|
| At claim | Stats + tickets both anchor at claim-time currentLevel+1; box-open is a pure O(1) count increment; other two _applyWhalePassStats callers untouched (Claude recommended) | ✓ |
| At open (roll-time), only tickets defer | Inconsistent anchors; box-open not fully O(1); needs a separate freeze proof | |

**User's choice:** At claim.
**Notes:** Forced by the claim-time-anchoring choice — stats need the claim-time anchor, so they must run in claimWhalePass. Only the LootboxModule box-open caller changes; WhaleModule:1032 + DecimatorModule:588 keep immediate-apply.

---

## AfKing scope + BURNIE sink

### Pass-gating scope (architecture-resolved, not a multiple-choice)

**Resolution:** autoBuy sub window ONLY. The subscription window only gates autoBuy (cursor-driven daily box-buy leg); autoOpen is permissionless (no window to gate), unchanged. Design note: a new level-horizon pass view is needed (hasAnyLazyPass is boolean-only) — deity = type.max sentinel, lazy/whale = covered level.

### burnForKeeper removal scope

| Option | Description | Selected |
|--------|-------------|----------|
| Remove entirely, both contracts | Delete from AfKing + the dead BurnieCoin.sol:472 impl; batched diff touches BurnieCoin (Claude recommended) | ✓ |
| Remove from AfKing only, leave BurnieCoin dead | Avoids touching BurnieCoin but leaves dead code | |
| Repurpose | No stated use; against simplification | |

**User's choice:** Remove entirely, both contracts.
**Notes:** AfKing is BurnieCoin.burnForKeeper's only (onlyAfKing-gated) caller. The IMPL-335 batched diff therefore touches BurnieCoin.sol.

### Proactive refreshPass()?

| Option | Description | Selected |
|--------|-------------|----------|
| Lazy-only, no refreshPass() | Crossing re-check already catches upgrades; refreshPass() is pure convenience (Claude recommended) | ✓ |
| Add a cheap refreshPass() | Lets an upgrader bump validThroughLevel immediately; convenience only | |

**User's choice:** Lazy-only, no refreshPass().

---

## MINTDIV-02 fix posture

### Fix shape if reachable (user asked "what is this exactly?" → explained the LCG startIndex divergence, then re-posed)

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal one-liner: >>1 → += take | Align processTicketBatch:716 to the correct processFutureTicketBatch:502 contiguous advance; smallest blast radius (Claude recommended) | ✓ |
| Full dedup onto a shared loop body | Permanently kills the duplication class; larger risk surface on the trait-critical path | |

**User's choice:** Minimal one-liner: >>1 → += take.

### If refuted (split unreachable)

| Option | Description | Selected |
|--------|-------------|----------|
| No change, documented NEGATIVE | Matches MINTDIV-02 as written; frozen path untouched (Claude recommended) | ✓ |
| Still apply the defensive += take one-liner | Defense-in-depth on a latent landmine; cuts against frozen-contracts ethos | |

**User's choice:** No change, documented NEGATIVE.

---

## Claude's Discretion

- `claimWhalePass` entrypoint home (Game vs module-direct), pending-counter slot, the level-horizon pass-view name/signature, and `validThroughLevel` placement in the `Sub` layout — left to planner/researcher within the locked decisions.

## Deferred Ideas

- gameOver-forfeit rule for unclaimed whale passes — SPEC to record the explicit rule (forfeit vs auto-claim).
- Full dedup of the two MintModule loops — standing maintenance idea for a future cycle.
- Running the external RNG-audit protocol through Gemini/ChatGPT + triaging — out of v50 (RNGAUDIT is package-only).
