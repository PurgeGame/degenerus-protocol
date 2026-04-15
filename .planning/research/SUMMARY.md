# Research Summary: v26.0 Bonus Jackpot Split

## Executive Summary

The bonus jackpot split adds an independent trait roll for BURNIE coin + carryover distributions, derived from the same VRF word via keccak256 domain separation. The two-call gas split is preserved by packing bonus traits into bits [144:175] of the existing `dailyTicketBudgetsPacked` word (144/256 bits used, 112 free). Total marginal gas: ~1,175. No new storage slots.

## Stack Additions

- `BONUS_TRAIT_TAG = keccak256("bonus-traits")` — domain separator (existing pattern: COIN_JACKPOT_TAG)
- keccak256 domain separation required (not XOR) — `getRandomTraits` consumes same bit positions [0:23], XOR preserves correlation
- Bonus traits packed into `dailyTicketBudgetsPacked` bits [144:175] — zero marginal SSTORE cost
- `BonusWinningTraits(uint24 indexed level, uint32 traitsPacked)` — one per drawing, ~800 gas

## Feature Table Stakes

| Feature | Status | Complexity |
|---------|--------|------------|
| Independent bonus trait roll (keccak domain separation) | Must have | Low |
| Pack bonus traits into dailyTicketBudgetsPacked | Must have | Low |
| Coin target range [lvl+1, lvl+4] | Must have | Trivial |
| Carryover uses bonus traits | Must have | Low |
| BonusWinningTraits event | Must have | Low |
| BonusBurnieWin event (distinct from JackpotBurnieWin) | Should have | Low |
| Purchase-phase payDailyCoinJackpot uses bonus traits | Must have | Low |

## Architecture

**Two-call split preservation:**
- Call 1 (payDailyJackpot): Roll main traits (as today) + roll bonus traits + pack bonus into dailyTicketBudgetsPacked
- Call 2 (payDailyJackpotCoinAndTickets): Unpack bonus traits; coin + carryover use bonus; daily ticket lootbox uses main

**Critical constraint:** Do NOT write bonus traits to `dailyJackpotTraitsPacked` — `_resumeDailyEth` reads that slot for the ETH resume path.

**Purchase-phase path (payDailyCoinJackpot):** Standalone — rolls bonus traits inline (no cross-call bridging needed).

## Watch Out For

1. **Entropy correlation** — `_rollWinningTraits(randWord)` twice = identical traits. Must use keccak256-derived seed.
2. **Stale main traits in carryover** — `payDailyJackpotCoinAndTickets` L562 loads main traits; carryover must use unpacked bonus traits instead.
3. **dailyJackpotTraitsPacked contamination** — bonus traits here would corrupt ETH resume path.
4. **Off-by-one** — `entropy % 4 + 1` is correct; `entropy % 4` (wrong base) and `entropy % 5` (old range) are both wrong.
5. **Event ambiguity** — existing `JackpotBurnieWin` for both main+bonus leaves logs uninterpretable.
6. **Gas regression** — ~250K worst-case from 50 additional creditFlip calls; within 1.99x margin but must measure.
7. **Level 0 edge case** — bonus range [1, 4] may find zero ticket holders; safe (no winners = no payouts) but no-op.

## Gas Impact

| Component | Gas |
|-----------|-----|
| keccak256 domain separation | ~42 |
| Second trait roll (warm hero SLOAD) | ~350 |
| BonusWinningTraits event (LOG2) | ~800 |
| Pack/unpack overhead | ~0 (existing SSTORE) |
| **Total per-drawing** | **~1,175** |
| creditFlip loop (50 winners worst-case) | ~250,000 |

---
*Research completed: 2026-04-11*
