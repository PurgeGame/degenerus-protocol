# Degenerette v73.0 — How It Works Now + Design Intent

**Shipped:** 2026-06-21 · contract commit `64ec993e` · v73 byte-frozen subject `contracts/` tree `d6615306`
**Scope:** one batched diff to `contracts/modules/DegenerusGameDegeneretteModule.sol`. Generator
of record: `.planning/notes/degenerette-recalibration/derive_5_tables.py`.

---

## Part 1 — How it works now

### 1. The ticket & Variant-2 scoring (`_score`)
A ticket is 4 quadrants; each quadrant has a COLOR (1 of 8) and a SYMBOL (1 of 8). One quadrant is
the **hero** (player-chosen on manual bets; RNG-derived on box/claim spins).

**Variant-2 rule, per quadrant:**
- a SYMBOL match scores **+1** (the hero quadrant's symbol scores **+2**);
- that quadrant's COLOR scores **+1 only if the same quadrant's symbol also matched** (color is
  "gated behind" the symbol — it never scores on its own).

Score `S ∈ {0..9}`. Max 9 = hero quad (symbol 2 + color 1 = 3) + three ordinary quads (2 each).

**Pay floor S≥2** (DEC-03): S=0 and S=1 pay nothing. A lone ordinary symbol = S=1 → 0. The hero
symbol alone = S=2 → pays. A full symbol+color double on one quadrant = S=2 → pays. ("A bare
ordinary symbol wins nothing; you need the hero or a full double.")

**Net effect vs the old `S = A + 2H` (independent color+symbol axes):** the main paying slot moves
from ~1-in-3 (≈32%) to **~1-in-5 (≈19.5%)** at roughly **2× the multipliers**, at **identical EV**.
Rarer wins, bigger numbers, same house edge.

### 2. Gold-count N and the per-N payout tables
Each quadrant's color is "gold" (the rare color) with probability **1/15**, common with 14/15. Gold
colors are harder to match (gold 1/15 vs common 2/15 per axis), so a ticket's gold-quadrant count
`N ∈ {0..4}` shifts its score distribution. Payout tables are indexed by N and calibrated so each is
**neutral-or-just-under 100% EV** (house edge ≥ 0).

**DEC-02 Option B (honest ETH/FLIP lane):** Variant-2 couples color to symbol, so the *hero*
quadrant's gold-ness shifts P(S) within a fixed N. To keep **every pick exactly EV-equal**, the
honest family is split per **(N, hero-is-gold)** → 8 base tables (N0, N1/2/3 × {hero-gold,
hero-common}, N4) + matching ETH-bonus-factor tables, each solved against its own sub-case. This
**closes a ~+2.24% player-selectable edge** (a manual bettor could pick N=3 hero-common to go
EV-positive). The contract derives `heroIsGold = ((ticket >> (heroQuadrant*8+3)) & 7) == 7` and
indexes the honest table by (N, heroIsGold).

### 3. Currencies and where spins come from
Spins resolve in three currencies. **ETH and FLIP use the honest tables; WWXRP uses the rigged
tables.** v73 did NOT change the currency mechanism — only the score distributions/tables.
- **Manual ETH bets:** player builds a custom ticket + picks the hero quadrant; increments the
  daily hero tracker (`dailyHeroWagers`) and influences the hero jackpot.
- **Box/lootbox spins (RNG):** a `% 20` roll → 15% one WWXRP spin · 10% three FLIP spins (under one
  survival flip) · 5% one ETH spin (direct boxes; recirc boxes give tickets) · else tickets/DGNRS/
  FLIP-reward. Hero + gold are RNG-derived per spin.
- **Foil-pack claim spins:** a `% 100` roll → 40% ETH · 40% FLIP (×3) · 20% WWXRP.

### 4. The WWXRP rig (`_rigWwxrpResult`) — DEC-01 R2 "+2 unlock, never a 9"
WWXRP reels are nudged toward near-wins. When a roll has ≥2 unmatched axes (`M ≤ 6`), with **60%**
probability the rig forces **one score-bearing cell** to match:
- **Eligible pool (R2):** an unmatched **non-hero symbol**, OR an unmatched **color on a quadrant
  whose symbol already matched** (the color "unlocks"). **Excluded:** no-op colors (a color on a
  symbol-unmatched quad buys nothing under Variant-2) and the hero symbol. Empty pool → no lift.
- **The +2 unlock (USER ruling):** forcing a symbol onto a quad whose color already matched unlocks
  both → **+2** (not +1). Allowed — it makes the reel more exciting. **But the `m≥7` cap** (the rig
  only fires at M≤6 → post-force M≤7 → S≤8) means the rig can **NEVER** produce the S=9 jackpot.
- Result: WWXRP win-rate rises to **~37%** (vs ~19.5% honest), concentrated in the mid-high scores.
  Net WWXRP RTP is still governed by the separate ROI curve (70%→120%), held fixed.

### 5. The jackpot and the held-fixed invariants
**S=9 = all-eight-axes matched = the jackpot.** P(S=9) per N (1/12.96M at N0 → 1/207M at N4) and the
jackpot payout pins are **byte-identical to pre-v73** — the rig can't reach S=9, and the Variant-2
relabel preserves the all-match event. Also held byte-fixed: the **WWXRP RTP curve**
(70→115→118→120%), the **activity ROI curve** (90→99.9%), and the **S=9 whale-pass bracket**. v73 is
a deliberately **bounded** recalibration, not a jackpot restructure.

### 6. Currency-mix-by-score (a consequence, not a new mechanic)
Because WWXRP is rigged (lifted) and ETH/FLIP are not, among high-scoring spins WWXRP is heavily
over-represented (e.g. ~81–91% of S=8 box spins are WWXRP). But the **S=9 jackpot's currency mix
equals the base spin weights** (currency-neutral) precisely because P(S=9) is identical across
currencies. For foil claims, ETH and FLIP are *triggered* equally (40/40) but FLIP yields 3 spins
vs ETH's 1, so FLIP *results* outnumber ETH 3:1.

---

## Part 2 — Your design intent (the decisions you made)

- **Core intent:** port the color-gated-by-symbol rule already shipped+audited on the foil match
  (`16225de6`) into the *core Degenerette betting engine* — a "feels more like a slot" rescore:
  **rarer wins (~1-in-5), ~2× multipliers, identical EV**.
- **Keep the hero as a score multiplier.** You considered a hero-free version (hero only for manual
  ETH tracker/jackpot) but chose to **ship the hero-ful design**: the hero symbol scores double, it
  enables the S=9 jackpot, and manual ETH bets pick it + feed the daily hero tracker/jackpot.
- **DEC-01 = R2, "+2 unlock, never a 9":** the WWXRP rig forces only *score-bearing* cells; you
  allowed the +2 color-unlock (stronger near-win reel) with a hard guarantee the rig never fabricates
  the jackpot.
- **DEC-02 = Option B (exact EV-equality):** you closed the player-selectable hero-placement edge on
  the real-money (honest) lane by splitting the honest tables per (N, hero-gold). You accepted the
  residual drift on the **WWXRP** lane by-design ("worthless shitcoin, don't-care").
- **DEC-03 = pay floor stays S≥2:** a lone ordinary symbol wins nothing; you need the hero symbol or
  a full double.
- **Held byte-fixed (bounded scope):** P(S=9)/jackpot pins, the WWXRP RTP curve, the S=9 whale-pass
  bracket, and the activity ROI curve are unchanged vs HEAD — the change is a recalibration + the
  re-audit it forces, not a jackpot redesign.
- **Process intent:** generator-first (verify the math + tables before any `.sol`), the contract diff
  as the single approval gate, then thorough testing + a fresh re-audit because core scoring moved.

---

## Status & what's next
- ✅ 452 GEN (generator + tables + EV-drift measurement + pre-proof) — shipped.
- ✅ 453 IMPL (this contract diff) — shipped + USER-approved (`64ec993e`).
- ▶ 454 TST — byte-reproduce gate, **contract-vs-generator rig-parity test** (run the real
  `_rigWwxrpResult` over many seeds, confirm its score distribution matches
  `p_score_distribution_rigged`), invariant proofs (P(S=9)/RTP/whale-pass unchanged), Degenerette
  unit + invariant + stat oracles, full-suite parity (forge + Hardhat).
- ▶ 455 REAUDIT (solvency · RNG-freeze · liveness on the new scoring) · 456 TERMINAL (evidence pack
  + closure signal `MILESTONE_V73_AT_HEAD_<sha>`).
