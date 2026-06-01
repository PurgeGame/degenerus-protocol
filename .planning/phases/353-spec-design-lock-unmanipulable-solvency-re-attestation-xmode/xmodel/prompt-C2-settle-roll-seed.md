# XMODEL Design Review — Concern C2: Settle-Timing / Roll-Seed Selection

You are an adversarial smart-contract security auditor reviewing a **design** (pre-launch, frozen contracts). Your single job: determine whether a player (or a keeper acting for a player) can **select a favorable affiliate-roll seed by timing the settle/flush**. Find a seed-grinding vector OR confirm there is none.

## The mechanism

The v56 aggregator defers a per-buy "affiliate distribution" to a once-per-window settle. The affiliate distribution is a **winner-takes-all roll** among the buyer's own upline chain:

- **Scheduled flush (~10-day epoch):** the roll is
  `keccak256(AFFILIATE_ROLL_TAG, windowBoundaryDay, sender, storedCode) % 20`
  where **`windowBoundaryDay` is the FIXED window-boundary day** — a deterministic function of the sub's own subscribe day (`windowStartDay + WINDOW_LEN`-equivalent), **NOT** the live settle-call `currentDayIndex()`. The roll outcome: 0–14 → the buyer's affiliate (75%), 15–18 → upline1 (20%), 19 → upline2 (5%).
- **Player-triggered flush** (sub/unsub/param-change): a **DETERMINISTIC 75/20/5 split, NO roll at all** — so a player who flushes early cannot select a roll seed.

## The asserted defenses (try to break these)

1. The only mutable input to the scheduled roll seed is `windowBoundaryDay`, which is **fixed at subscribe time** (a pure function of the subscribe day). It is NOT the live call day. So a keeper cannot nudge the seed by choosing WHEN within a day to call the scheduled flush.
2. Even if `currentDayIndex()` WERE used: `currentDayIndex()` is a pure function of `block.timestamp` (`GameTimeLib.sol:21-34`, `currentDayIndexAt(uint48(block.timestamp))`) — it only changes at the ~24h wall-clock boundary (≈22:57 UTC). A player **cannot select a day index within a transaction**; "choosing a favorable roll" would require waiting a full wall-clock day, over which the roll is EV-neutral anyway.
3. **Buyer-never-wins** (`DegenerusAffiliate.sol:579`): the buyer (`sender`) NEVER receives the roll — when the roll would pay them, the whole reward (incl. quest credit) is SKIPPED. So `sender` has **zero EV** from the roll regardless of seed.
4. The roll is **intra-upline-chain-only**: it only redistributes among the buyer's own affiliate/upline1/upline2; it never creates or destroys protocol value.
5. The player-flush path has **no roll** (deterministic split) — there is nothing to grind.

## Your task

Determine whether there is ANY way for a player or keeper to choose a settle TIME (block, day, or path) that yields a more-favorable roll seed or a higher buyer EV. Consider:
- Can a player choose the scheduled-flush block to land a favorable `keccak256` output? (The seed inputs are `windowBoundaryDay`, `sender`, `storedCode` — are any of these attacker-controllable at settle time?)
- Could a player register a `storedCode` (affiliate code) chosen to bias the roll for a known `windowBoundaryDay`?
- Does the buyer-never-wins guard fully neutralize buyer EV even if the seed WERE grindable?
- Is there any path where the player-triggered flush (deterministic split) pays the buyer MORE than the scheduled roll's expected value, creating a timing arbitrage between the two paths?

## Required structured answer

End your response with EXACTLY this block:

```
VERDICT: [EXPLOITABLE | NOT-EXPLOITABLE | NEEDS-DESIGN-CHANGE]
RATIONALE: <one paragraph>
SEED-GRIND-VECTOR: <the concrete seed-selection / timing-arbitrage construction, OR "none — the seed inputs are fixed-at-subscribe and the buyer never receives the roll">
```
