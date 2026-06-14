# Reward-structure changes — integration brief for the paper

Captures the committed reward-structure changes for whitepaper parity. Source commits (local, unpushed):
lootbox rebalance `dae8e775`, recycle bonus `a85c61b3`, **lootbox→Degenerette spins `a8b702a7`** (now
SHIPPED — see §2b; design in `.planning/LOOTBOX-DEGENERETTE-SPINS-PLAN.md`).

**Framing rule for the paper:** most of these are **EV-neutral redistributions** (same expected value,
different shape). Only two change EV: the lootbox EV-multiplier lift, and the recycle-bonus relaxation
(more buyers qualify). Flag that distinction wherever the paper makes RTP claims.

## 1. Lootbox EV multiplier (activity-score → expected value)
| | Old | New |
|---|---|---|
| Floor (score 0) | 80% | **90%** |
| Neutral (score 6,000) | 100% | 100% |
| Ceiling | 135% | **145%** |
| Score to reach ceiling | 25,500 | **40,000** |
Floor and ceiling both lifted (genuine RTP increase). Ceiling now needs a higher score because the
quest-streak component of activity score is now uncapped (see quest/streak brief). Linear between breakpoints.

## 2. Lootbox reward-component split (per roll)
Two steps. The `dae8e775` rebalance set Tickets 55%→45%, DGNRS 10%→15%, WWXRP 10%→15%, BURNIE 25%.
Then `a8b702a7` (spins) carved the **final** split — ticket value still preserved (see #3):

| Outcome | Share | Notes |
|---|---|---|
| Tickets | **40%** | was 45% — 5% carved for the ETH spin (EV-equal: the spin stakes the tickets it replaced) |
| DGNRS | 15% | unchanged |
| **WWXRP spin** | 15% | was a flat 1-WWXRP mint → now a 1-WWXRP Degenerette spin (§2b) |
| BURNIE (flat) | **15%** | was 25% — 10% carved for the BURNIE spins (EV-equal: spins stake the would-be BURNIE) |
| **BURNIE spins ×3** | **10%** | new (§2b) |
| **ETH spin** | **5%** | new (§2b) |

## 2b. Degenerette-spin lootbox outcomes (new — `a8b702a7`)
Three of the rolls now play out as **Degenerette spins** instead of flat awards — same expected value per
category (EV-neutral redistribution), with added variance and the spin-reel feel. Each is a real
Degenerette spin scored by the player's activity score, just sourced from the box instead of a placed bet.
- **WWXRP spin (15%):** one WWXRP Degenerette spin staking the 1-WWXRP prize, with the high-value ROI
  bonus and the rare jackpot **whale-half-pass** (S=9), exactly like a normal WWXRP bet.
- **BURNIE spins ×3 (10%):** the would-be flat BURNIE is split across three BURNIE spins; the summed
  payout then **double-or-nothings on one survival coinflip** (EV-neutral) before minting.
- **ETH spin (5%, directly-opened boxes):** one ETH Degenerette spin; the win splits via the standard
  3-tier rule into claimable ETH + a **recirculated bonus box** (the leftover rolls again). On recirc
  boxes this slot awards tickets instead (no cascade).

## 3. Lootbox ticket-roll budget (value preserved)
Per-ticket-hit budget 161%→**~197%** (×11/9), so despite tickets dropping 55%→45%, aggregate ticket ETH
value is unchanged. Net: fewer ticket hits, each worth proportionally more.

## 4. Lootbox far-future ticket distribution
Far-future share 10%→**20%** (near 90%→80%). More tickets seeded into future levels.

## 5. Lootbox far-future budget weighting (new mechanic)
Far rolls get **1.5×** budget, near **0.875×** → 30% of aggregate ticket budget goes to the 20% far rolls.
EV-neutral (0.8×0.875 + 0.2×1.5 = 1.0). (We trialed 40%/2.0×/0.75× first, settled on 30%.)

## 6. Lootbox variance tiers — ranges instead of fixed steps
Same tier probabilities (1/4/20/45/30%), but each draws a multiplier from a symmetric range centered on
the old value (overall variance EV unchanged at 0.786×):
| Tier | Chance | Old | New range |
|---|---|---|---|
| 1 | 1% | 4.6× | 3.20×–6.00× |
| 2 | 4% | 2.3× | 1.60×–3.00× |
| 3 | 20% | 1.1× | 0.80×–1.40× |
| 4 | 45% | 0.651× | 0.451×–0.851× |
| 5 | 30% | 0.45× | 0.300×–0.600× |

## 7. Mint recycle bonus (relaxed)
Spending claimable winnings ("recycled ETH") earns a 10% BURNIE flip-credit bonus on the recycled value.
- Old gate: spend essentially ALL claimable AND ≥3 tickets' worth.
- New gate: any buy spending **≥3 whole tickets' worth of claimable**, regardless of remaining balance.
- Bonus size unchanged. Effect: many more buys qualify; keep a claimable buffer and still earn it.

## Net narrative
- Lootboxes more rewarding & more engagement-gated: higher floor (90%) and ceiling (145%), top reserved
  for relentless questers (uncapped quest streak → score up to 40,000).
- Smoother payouts: continuous multiplier ranges; more DGNRS variety; fewer-but-bigger ticket hits.
- Spin-reel outcomes (§2b): WWXRP, BURNIE, and a slice of ETH/ticket value now play out as Degenerette
  spins from the box — same EV per category, more variance and engagement (survival flips, recirc bonus
  boxes, the WWXRP jackpot half-pass). Pure reshaping of value already in those rolls.
- Future-weighted tickets: 20% of ticket rolls (30% of ticket value) seed far-up levels.
- Recycling claimable friendlier: the 10% bonus no longer punishes keeping a balance.
- Everything except the EV-multiplier lift and the recycle-bonus relaxation is pure reshaping — same money, better feel.

## Reference data (from this session, verified)
- BURNIE:tickets ETH-value ratio from lootboxes ≈ **0.59 : 1** (tickets ≈ 1.69× BURNIE); tickets ≈ 63% /
  BURNIE ≈ 37% of combined ticket+BURNIE value. Level/size/activity-invariant. BURNIE valued at the
  protocol peg (1000 BURNIE = 1 whole-ticket price); realizable value lower (illiquid flip-credit).
