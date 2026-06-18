# Cross-model verification of the RNG-freeze-at-commitment proof — Degenerus Protocol

You are independently verifying a machine-generated proof that every VRF/RNG-derived outcome in this Solidity codebase is frozen-at-commitment. Read the CURRENT source under `contracts/` (frozen tree `4970ba5b`). Your job is to REFUTE, not rubber-stamp.

## Inputs (read these)

- `audit/rng-freeze-proof-v68.index.json` — 79 freeze claims, each `{id, name, consumptionSite (file:line), commitmentPoint (file:line), freezeClass, freezeHolds, severityIfBroken, verificationRecipe}`.
- `audit/RNG-FREEZE-PROOF-v68.0.md` — the full per-consumer detail (formal invariant, frozen-input enumeration, verification recipe).

## The freeze invariant (what each claim asserts)

For a consumer, the VRF word/seed it consumes is fully determined at its commitment point `P`, and **no actor-controllable input on any reachable path between `P` and the consumption site `C` can change which word is used or how the outcome is derived.** (A live input that only *scores against* a result, or is monotonically down-clamped, or is snapshotted at `P`, does not break the freeze. An input that *steers which word/index is used*, or *re-arms a magnitude after the word becomes knowable*, does.)

## What to do

1. Prioritize the **40 non-trivially-frozen claims** — `freezeClass` of CROSS-CONTRACT-SEAM (33), NEEDS-PROOF (5), MUTABLE-INPUT (2) — these are where a break would live. Spot-check a sample of the 39 FROZEN-AT-COMMIT claims too.
2. For each, independently re-run its `verificationRecipe` against `contracts/` source and try to find ONE actor-controllable input between `P` and `C` that biases the outcome (seed-grinding, index selection of a revealed word, re-arming a redemption/jackpot magnitude after the word is knowable, a live read that actually steers selection rather than scoring).
3. Explicitly adjudicate these three flagged claims and say whether you AGREE or DISAGREE with the proof's verdict, with source reasoning:
   - `RNGF-SEAM-RESOLVE` (the proof's only `freezeHolds=false`, LOW) — gameover prevrandao-fallback redemption-roll *magnitude* bias.
   - `RNGF-REDEEMSEAM-08` (HIGH-if-broken, proof says HOLDS) — sDGNRS day+1 redemption word at submit.
   - `RNGF-FLIPESCROW-09` (HIGH-if-broken, proof says HOLDS) — Coinflip day+1 result at submit.

## Report

For every claim you can REFUTE (a real freeze break the proof missed or mis-classified): the `id`, the exact `file:line`, the reachable biasing path, and a severity. For the three flagged claims: AGREE / DISAGREE + reasoning. If you cannot refute a claim, do not list it. End with: do you concur with the proof's headline result (78/79 freeze-holds, the one exception being the LOW gameover-prevrandao magnitude bias), or do you find additional breaks? Source-anchored only.
