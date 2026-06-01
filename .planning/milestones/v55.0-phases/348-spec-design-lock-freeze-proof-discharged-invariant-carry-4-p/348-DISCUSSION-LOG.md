# Phase 348: SPEC — Design-Lock + Freeze Proof + Discharged-Invariant Carry + §4 Placement Decision + Code-Size/GAS Inventories + Call-Graph Attestation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-30
**Phase:** 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p
**Areas discussed:** §4 placement (PLACE-01), FREEZE-proof red-team depth, Code-size + GAS rigor (ARCH-04)
**Area NOT selected:** SPEC deliverable shape (carried forward as 343's D-08 multi-doc default)

---

## §4 placement (PLACE-01)

### Headline — placement choice

| Option | Description | Selected |
|--------|-------------|----------|
| Lock separate legs | Process pre-RNG cursor-chunked (BUY_BATCH), open post-_unlockRng (OPEN_BATCH); no advance-liveness coupling; doc §4/§9 recommendation | |
| Lock required-path | New STAGE in advanceGame before rngGate; guaranteed every-sub-every-day + uniform index epoch; per-sub isolation + mint-gate standing | ✓ |
| Decide legs, document req-path | SPEC decision-matrix, pick separate-legs, document required-path as a ready alternative | |

**User's choice:** Lock required-path (their original instinct; the REVERT-FREE-CHAIN proof made it VIABLE, so chosen on guaranteed-every-day grounds, not forced by revert-safety). Diverges from the doc recommendation.

### FREEZE-02 index binding under chunked drain

| Option | Description | Selected |
|--------|-------------|----------|
| Uniform epoch per day | All subs stamped to the same LR_INDEX; requestLootboxRng cannot interleave while !subsFullyProcessed | ✓ |
| Per-sub bind-at-moment | Each sub binds to current index when processed; freeze-safe but non-uniform epochs if requestLootboxRng fires mid-drain | |
| You decide | Pick based on what source permits | |

**User's choice:** Uniform epoch per day. **Notes:** creates a load-bearing proof obligation — prove the no-interleave guard holds (block requestLootboxRng while !subsFullyProcessed, or order the STAGE to own the index until rngGate).

### Mint-gate standing

| Option | Description | Selected |
|--------|-------------|----------|
| Inherit the gate | STAGE rides advanceGame's existing _enforceDailyMintGate (mint standing OR 15-30min ladder); zero new gate logic | ✓ |
| Decouple from gate | Process STAGE reachable without minting standing; re-introduces separate-leg surface | |
| You decide | Resolve against source | |

**User's choice:** Inherit the gate. **Notes:** day advances daily regardless → afking processing guaranteed-every-day in practice with no new code.

### try/catch valve (user-prompted: "didnt we get rid of try/catch?")

| Option | Description | Selected |
|--------|-------------|----------|
| Drop it — no try/catch | Healthy path revert-free by construction (obl 1); class B fails loud (never mask solvency); class C terminal (verify game-over routing unblocked) | ✓ |
| Keep the thin valve | Per-sub try/catch on both legs absorbing B/C (docs as written); masks class-B solvency, adds gas | |
| You decide | Resolve against source | |

**User's choice:** Drop it — no try/catch. **Notes:** rewrites REVERT-02 (349-owned) + proof §5 obligation 4; SPEC records as a correction (parallel to 343's AUTOBUY-02→b.funder). Proof burden concentrates on obligation 1.

---

## FREEZE-proof red-team depth

### Initial scope question — REJECTED/clarified by user

| Option | Description | Selected |
|--------|-------------|----------|
| Both claims | /economic-analyst on the −EV freeze-completeness claim + /contract-auditor on obligation-1 | (rejected) |
| −EV claim only | /economic-analyst on the −EV claim only | |
| Self-attest only | Paper-prove, no adversarial subagent; defer to 352 | |

**User's clarification:** "there really isn't an attack vector here. these players already have passes. there is no real way to quickly and easily increase your score on demand (in the 5 minutes between buying and opening especially) ... if someone buys a deity pass because they see they have a good afking box, that's fine. maybe we could slot the afking open early on in the post-rng chain" → the −EV economic red-team is unnecessary; the early-slot was proposed as a structural tightener.

### Reformulated scope (+ user follow-up: "file under known issues as acceptable tradeoff")

| Option | Description | Selected |
|--------|-------------|----------|
| Self-attest, defer to 352 | No adversarial subagent at SPEC; all probing at 352 on the real folded code | |
| Light contract-auditor pass | /contract-auditor on obligation-1 only; no economic red-team | ✓ |

**User's choice:** Light contract-auditor pass — then follow-up clarified the freeze tradeoff itself ("file under known issues as acceptable tradeoff").

### Pinning the interpretation

| Option | Description | Selected |
|--------|-------------|----------|
| Both — issue + contract pass | Live-read window = accepted-by-design known issue (no economic red-team, no early-slot defense) AND the light /contract-auditor pass on obligation-1 still runs | ✓ |
| Issue covers it all | Also drop the contract-auditor pass; self-attest obligation-1; all probing at 352 | |

**User's choice:** Both. **Notes:** the live-read window (score/baseLevel/EV-cap read live) = accepted-by-design known issue (339-01 D-03 shape), documented + dispositioned for 352/v52; FREEZE-01 splits stamped-vs-live-read; early-slot DROPPED as a defense → afking open stays a normal post-RNG leg (resolves PLACE-02 drift); obligation-1 gets the one light /contract-auditor pass.

---

## Code-size + GAS rigor (ARCH-04)

### Code-size reclaim plan rigor

| Option | Description | Selected |
|--------|-------------|----------|
| Measure + edit-order arithmetic | forge build --sizes live tree + per-target sizes + running-total edit-order map proving < 24,576 at every step | (Claude's call) |
| Trust the doc's figures | Restate 218B headroom + per-symbol sizes without re-measuring | |
| You decide | Set the depth | ✓ |

**User's choice:** You decide → locked recommendation: Measure + edit-order arithmetic (218B is too thin to take on faith; ARCH-04 mandates "measured"; CLI forge needs no ffi).

### GAS-opportunity inventory

| Option | Description | Selected |
|--------|-------------|----------|
| Enumerate-only, defer to 350 | Restate §6 scorecard + GAS-03 SAFE-WITH-CONDITIONS; no scavenger run at SPEC (dedicated 350 phase) | |
| Run gas-scavenger at SPEC too | Mirror 343 D-02: front-load advisory candidate list now; 350 runs gas-skeptic | ✓ |
| You decide | Set it | |

**User's choice:** Run gas-scavenger at SPEC too. **Notes:** front-load despite the dedicated 350 phase — more candidates for 349 to build in = fewer post-hoc gas diffs.

---

## Claude's Discretion
- SPEC deliverable shape — carried as 343's D-08 multi-doc set (this gray area was not selected).
- Code-size rigor (D-348-08) — user said "you decide" → measure-and-verify.
- Whether the /contract-auditor obligation-1 result is recorded inline or in a scratch attestation.
- The downstream plan posture (skip-research, plan-directly off the v55 PLAN docs + this CONTEXT) — planner may confirm.

## Deferred Ideas
- Early-slot post-RNG window-closure — proposed then dropped (window ACCEPTED as a known issue, not closed).
- Downstream v55 phases (not scope creep): /gas-skeptic application → 350; the IMPL diff → 349; TST-01..06 → 351; the 3-skill sweep + FINDINGS + closure → 352.
- Generalized operator-spend of claimableWinnings + a bingo/afking progress view → out of v55 (Future Requirements).
