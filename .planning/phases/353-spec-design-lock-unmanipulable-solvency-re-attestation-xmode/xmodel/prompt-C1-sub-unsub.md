# XMODEL Design Review — Concern C1: Strategic Sub/Unsub Churn (PRIMARY)

You are an adversarial smart-contract economic auditor. You are reviewing a **design** (not code — the contracts are pre-launch and frozen). Your single job for this prompt: try to find a **positive-EV churn loop** in the mechanism below, OR confirm there is none. Show arithmetic.

## The mechanism (v56 "AfKing" everyday-gas-minimization aggregator)

A player can SUBSCRIBE to an automated daily-buy service ("afking"). While subscribed, each daily buy:
- Debits the player's pre-funded ETH balance (a ledger move; full ETH cut, unchanged from today).
- Stamps a per-subscriber accumulator in ONE warm storage slot (the re-packed `Sub` struct). The accumulator holds: `affiliateBase` (the player's accrued affiliate reward base, denominated in **whole BURNIE**, stored as uint32 with a **saturating clamp at 100,000,000 whole BURNIE**), `lastSettledDay` (uint24, the settle-window marker), and `questProgress` (uint8).
- The affiliate base is computed per-buy with an **immutable, monotone-DOWN taper** (`_applyLootboxTaper`, `DegenerusAffiliate.sol:787-795`): as the player's activity score rises, each buy's affiliate base is reduced (100% → 25%). The taper is applied **per-buy at accrue** on the activity score frozen at that buy's box stamp — it can only ever reduce, never increase.

The cross-contract "storm" (affiliate distribution + quest credit + per-buy BURNIE `creditFlip`) that runs today **per-buy** is DEFERRED to a once-per-window **settle**:
- **Scheduled flush** (~10-day epoch elapsed, `currentDay - lastSettledDay >= 10`): runs the deferred affiliate distribution via a **winner-takes-all daily-seeded roll** + the deferred quest credit + ONE batched leaderboard write, then advances `lastSettledDay`.
- **Player-triggered flush** (any sub/unsub/param-change FIRST flushes the pending window, THEN applies the mutation): uses a **DETERMINISTIC 75/20/5 split with NO roll** at locked params. The mutating player **pays the settle gas**.

## The asserted defenses (you must try to break these)

1. **Buyer-never-wins** (`DegenerusAffiliate.sol:579`, `if (winner != sender)`): when the roll would pay the buyer (`sender`) themselves, the **entire reward — including the quest credit — is SKIPPED, not redirected**. The subscriber/their funding wallet has **zero EV** from the roll outcome.
2. **Roll is intra-upline-chain-only** (`:569-576`): the roll picks among the buyer's own affiliate (75%, roll 0–14), upline1 (20%, roll 15–18), upline2 (5%, roll 19). Manipulation only moves value among the buyer's own chain; it never creates or destroys protocol value.
3. **Per-buy immutable taper**: clustering many buys into one settle cannot dodge a higher-score taper — each buy is tapered at its OWN score, taper-only-reduces.
4. **Double-settle gate**: `lastSettledDay` (in the warm slot) gates a second scheduled flush in the same window to a no-op; a player-flush resets the window.
5. **100M whole-BURNIE saturating clamp** on `affiliateBase`: the clamp can only ever UNDER-credit (cap the extreme reinvest-whale `effectiveQty` edge), never over-credit — so it cannot be a positive-EV lever.
6. All affiliate + quest credits are **BURNIE flip-credit OFF the ETH/`claimablePool` solvency path** — the ETH debit is byte-unchanged. So this is a BURNIE-emission-timing change, not an ETH-cut change.

## Your task

Attempt to construct a concrete **positive-EV CHURN loop**: a player who repeatedly `subscribe → accrue some buys → unsubscribe (deterministic-75/20/5 flush, player pays gas) → re-subscribe` and thereby extracts MORE value (in BURNIE credit, affiliate reward, quest streak, or any in-game benefit) than a steady subscriber who never churns. Consider in particular:
- Can churn re-rate the taper (reset the activity score to dodge a higher taper)?
- Can churn re-roll or pick a favorable affiliate-distribution outcome?
- Can churn double-settle a window (get paid twice for the same accrual)?
- Can churn harvest a settlement the steady sub would not get, or dodge a streak penalty?
- Does the player-pays-the-settle-gas requirement bound the churn (self-limiting)?

If a positive-EV loop exists, **show the arithmetic** (the per-cycle gain vs the per-cycle gas/opportunity cost, and the net). If none exists, explain precisely why each candidate vector nets ≤ 0.

## Required structured answer

End your response with EXACTLY this block:

```
VERDICT: [EXPLOITABLE | NOT-EXPLOITABLE | NEEDS-DESIGN-CHANGE]
RATIONALE: <one paragraph>
CHURN-LOOP: <the concrete positive-EV loop with arithmetic, OR "none — every candidate nets ≤ 0 because ...">
```
