# Permissionless-Composition & Indexer-Event Correctness Review — Degenerus Protocol (cross-model council, NET-1)

Review the permissionless / keeper entrypoints, the decimator offset-key isolation, the redemption RNG gates, and the new indexer-parity events for access-correctness, composition-safety, and emission-only correctness. Frozen subject: the `contracts/` tree at this checkout (read-only; do not modify any file). Report any divergence with `file:line`, the invariant vs the code, and the concrete effect. A clean result is a valid outcome.

## The invariants to verify

- **PERM-01 — permissionless access + composition + offset-key isolation.** The permissionless decimator + redemption batch-claim entrypoints (`4547b387`, `a6b3e2fd`) must be access-correct (no privilege escalation — a permissionless caller can only advance state that is meant to be public, never act AS another player or mint to themselves) and composition-safe (no cross-call reentrancy / ordering break / griefing that bricks another player's claim). The decimator **offset-key isolation** (`d8778c3e`: terminal decimator keyed at `decBucketOffsetPacked[lvl+1]`) must prevent a lagged-gameover decimator round from overwriting a live regular round's bucket state. Verify the access modifier on each entrypoint, the reentrancy posture, and that the offset key cannot collide with a live round.
- **PERM-02 — keeper box-bounty is not a faucet.** The keeper box-bounties (decimator + redemption batch) must be net-negative-or-neutral against REAL prevailing gas (5–50+ gwei) + flip-credit illiquidity — not farmable. Compute reward vs realistic gas; do NOT use the 0.5-gwei AUTO_GAS_PRICE_REF peg.
- **PERM-03 — redemption RNG gates hold against a grindable zero-word.** The redemption **pre-draw RNG gate** (`d8778c3e`) and the **mid-day RNG threshold gate** must hold the freeze invariant: a caller must not be able to read a zero / not-yet-fulfilled VRF word (`rngWordForDay(day+1) == 0`) and grind a favorable outcome, nor act in the window between request and fulfillment. Confirm the gate blocks the burn/claim before the relevant word exists.
- **PERM-04 — indexer-parity events emission-only correctness.** The 3 new indexer-parity events — `AffiliateEarningsRecorded` (reused in `claim`), `MintStreakRecorded` (new), `AfkingDelivered` (new) — must emit at the CORRECT site with CORRECT args, fire exactly ONCE per logical event (no double-emit, no missing emit), and be **emission-only** (adding the emit changed no state, control flow, or value). Confirm each event reconstructs the off-chain state the indexer needs (the contract↔indexer reconstruction contract).

## Focus questions (highest value)

1. **Privilege escalation:** can a permissionless caller of the decimator/redemption batch entrypoints act AS another player, redirect a payout, mint to themselves, or claim someone else's value? Walk the `msg.sender` vs `player` handling.
2. **Composition / griefing:** can a permissionless call reenter or be ordered to brick/grief another player's pending claim, or to double-process a batch entry?
3. **Offset-key collision:** can a lagged-gameover decimator round (keyed `lvl+1`) ever write the same bucket slot a live regular round reads/writes? Re-derive the key isolation.
4. **Grindable zero-word:** is there any path where a redemption burn/claim proceeds while `rngWordForDay(day+1)` is still zero/unfulfilled, letting the caller retry until favorable?
5. **Event correctness:** does each of the 3 events fire once-per-event with correct args, purely additively (no state/flow change)? Any double-emit or emit on a reverting path?

PRIOR CONTEXT (carried — re-verify, don't re-litigate): the decimator DEC-ALIAS terminal-offset fix keyed terminal at `lvl+1` (the prior M-01 dismissal was wrong; fixed `d8778c3e`); the REDEMPTION-ZERO-SEED grindable-zero-word was fixed by a burn-side gate `BurnsBlockedBeforeDailyRng` + local GameTimeLib day calc; the indexer events were added per the reconstruction Task #8 (`78eb3dd2`, +18 lines / 0 logic). These are re-verify targets.

Report each invariant with `file:line` + a verdict (holds / diverges), and list any divergence as a finding with the concrete effect.
