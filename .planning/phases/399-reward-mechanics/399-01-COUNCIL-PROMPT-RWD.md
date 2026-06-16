# Reward-Mechanics Correctness Review — Degenerus Protocol (cross-model council, NET-1)

Review the reward overhaul for EV-consistency, value conservation, freeze-safety, and money-pump resistance. Frozen subject: the `contracts/` tree at this checkout (read-only; do not modify any file). The stated design is documented in `.planning/PAPER-REWARD-CHANGES-BRIEF.md` — VERIFY the code matches those claims; do not re-litigate intent.

## Design claims to verify (from the paper brief)
- **Lootbox EV multiplier:** floor 90% (score 0), neutral 100% (score 6,000), ceiling 145%, ceiling reached at score 40,000; linear between breakpoints.
- **Lootbox reward split (per roll):** Tickets 40% · DGNRS 15% · WWXRP spin 15% · BURNIE flat 15% · BURNIE spins ×3 10% · ETH spin 5%. Claimed EV-neutral redistribution (only the EV-multiplier lift + the recycle relaxation change EV).
- **Degenerette spins (3 outcomes):** WWXRP spin (1-WWXRP stake, ROI bonus, rare jackpot whale-half-pass S=9); BURNIE spins ×3 then a survival double-or-nothing flip (EV-neutral) before minting; ETH spin (5%, direct boxes only) split via the 3-tier rule into claimable ETH + a recirculated bonus box (depth 1, allowEthSpin=false; recirc awards tickets not ETH).
- **Ticket-roll budget:** per-ticket-hit budget ×11/9 (~197%) so aggregate ticket ETH value is unchanged despite tickets dropping 55%→45%→40%.
- **Far-future:** 20% far / 80% near; far rolls 1.5× budget, near 0.875× → 30% of ticket budget to the 20% far rolls (0.8×0.875 + 0.2×1.5 = 1.0, EV-neutral).
- **Variance tiers:** chances 1/4/20/45/30%, each a symmetric range centered on the old fixed value; overall variance EV unchanged ≈0.786×.
- **Mint recycle bonus:** 10% BURNIE flip-credit on recycled (claimable) value; new gate = any buy spending ≥3 whole tickets' worth of claimable (drain-detection removed).
- **BURNIE emission rework:** coinflip-seeded stake (200k/day × 20d) replaces the 2M+2M lumps; day-20 sDGNRS rebuy latch; degenerette survival flip; carry claim.
- **Quest streak:** halved + uncapped quest streak (0.5%/completion), afking-secondary parity, unified activity score.

## Focus questions (the highest-value checks)
1. **EV-neutrality in code:** does the split sum to 100% and reconstruct the claimed per-category EV? Does ×11/9 preserve aggregate ticket value? Does far/near 0.2×1.5 + 0.8×0.875 = 1.0? Does the variance-tier midpoint sum ≈0.786? Confirm against the actual constants/formulas.
2. **Money pump:** is there any closed positive-EV loop across recycle (10% kicker), spins/recirc, carry, or affiliate — accounting for flip-credit illiquidity (must survive a 50/50 flip), sub-100% direct-box EV, claimable-won-first, and the 10-ETH/(player,level) EV-cap?
3. **Degenerette spins freeze-safety + one-shot:** are the spin seeds NOT player-knowable at commitment (the RNG-freeze invariant)? Are the resolvers one-shot / replay-safe? Is the ETH-spin recirc bounded (depth 1, no cascade)?
4. **BURNIE emission conservation:** is BURNIE minted only after a survival gate (survive-before-mint)? Does total emission stay conserved (8M stake / ~4M EV vs the removed 2M+2M)? Is the day-20 rebuy latch monotonic?
5. **Quest-streak double-channel:** can a player accrue streak on BOTH the afking and manual channels for the same day? Is the activity-score hard cap enforced?

PRIOR DISPOSITIONS (v63, carried — do NOT re-litigate, but flag if the NEW delta breaks them): the money-pump and streak-pump were REFUTED; survive-before-mint, emission conservation, and auto-rebuy latch monotonicity were attested; the whale-half-pass (P(S=9)≈6.74e-8, one per bracket) is by-design.

Report any divergence between the code and the stated design, or any positive-EV loop / freeze violation / emission leak, with `file:line`, the claim vs the code, and the concrete effect. A clean result is a valid outcome.
