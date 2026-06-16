# RNG-Freeze Spine Correctness Review — Degenerus Protocol (cross-model council, NET-1)

Review the RNG-freeze invariant across every new/changed RNG consumer in the v64 delta. Frozen subject: the `contracts/` tree at this checkout (read-only; do not modify any file). This is the protocol's DOMINANT invariant: every variable that interacts with a VRF word must be frozen against player manipulation across the window [rng request → unlock]. Report any divergence with `file:line`, the invariant vs the code, and the concrete effect. A clean result is a valid outcome.

## The invariants to verify

- **RNG-01 — backward trace each consumer to its commitment point.** For every NEW or CHANGED RNG consumer in the delta — the Degenerette box-spin seeds (WWXRP / BURNIE×3+survival / ETH), the decimator claim-seed, the redemption lootbox seed — trace BACKWARD from the consumer to confirm the VRF word was UNKNOWN at the moment the player committed the input that the word scores. The outcome must be fixed at VRF fulfillment, not influenceable by anything the player does after they can see (or predict) the word.
- **RNG-02 — enumerate in-window SLOADs.** Enumerate ALL storage reads (not just VRF-derived seeds) consumed inside the rng-window across the changed surface (including the repacked slots). Confirm NO player-controllable non-VRF state can change between VRF request and fulfillment to bias an output (the freeze-window storage-read freshness class). A non-VRF SLOAD consumed alongside the word, that a player can shift in-window, is a distinct bug class.
- **RNG-03 — one-shot + replay-safe resolvers.** The box-spin / decimator / redemption resolvers must be one-shot and replay-safe: the record is cleared BEFORE resolution (no re-entrancy double-resolve), and the delegatecall resolvers are guarded `address(this) != GAME ⇒ revert` (reachable only via the Game's delegatecall, never directly). Confirm no path can resolve the same seed twice or re-enter mid-resolution.

## Focus questions (highest value)

1. **Commitment-vs-reveal:** for each spin/decimator/redemption seed, what is the latest moment a player can change an input that the VRF word scores, and is that strictly BEFORE the word is knowable? Walk the request → commit → fulfill → resolve timeline.
2. **In-window mutable SLOAD:** does any resolver read a storage value (a balance, a level, a packed flag, an activity score, a streak) that a player can mutate in the request→fulfillment window to bias the scored outcome?
3. **Zero-word / not-yet-fulfilled:** can any consumer read a zero / stale / next-day word and grind (the redemption pre-draw + mid-day gate class)? Confirm the gate blocks the consuming action until the word exists.
4. **One-shot:** is the seed record cleared before the external/value effect? Can a reentrant or repeated call resolve the same seed twice?
5. **Delegatecall guard:** is every box-spin/decimator/redemption resolver gated `address(this) != GAME`, so it cannot be called on the deployed module instance directly?

PRIOR CONTEXT (carried — re-verify, don't re-litigate): the v45 VRF-freeze invariant (every VRF-interacting variable frozen [request→unlock] vs players; advanceGame exempt); the Degenerette box-spin seeds derive purely from the frozen rngWord via hash1/hash2 with no live state (attested in phase 399 RWD-02); the REDEMPTION-ZERO-SEED grindable-zero-word was fixed (burn-side gate); the resolvers are guarded `address(this) != GAME`. Re-verify these hold across the repacked slots + the new consumers.

Report each consumer with `file:line` + a verdict (frozen / manipulable), the in-window SLOAD set, and the one-shot/guard status; list any freeze violation or double-resolve as a finding with the concrete effect.
