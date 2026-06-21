"""
5-table EV-equal Degenerette payout derivation — 10-bucket S in {0..9} design.

DESIGN VARIANT (v73.0 "Variant-2" color-gated-by-symbol rescore)
---------------------------------------------------------------
Variant-2 GATES color behind symbol on a per-quadrant basis. Per quadrant a SYMBOL
match scores +1 (the hero quadrant's symbol scores +2), and that quadrant's COLOR
scores +1 ONLY IF that quadrant's symbol also matched. The composite score is the
sum of the four per-quadrant contributions:

    S = (hero quadrant {0, +2, +3}) + sum of 3 ordinary quadrants {0, +1, +2}
        (S in {0..9}, pay floor S >= 2)

where each per-quadrant contribution is:
    ordinary quadrant:  +0 symbol miss; +1 symbol match & color miss;
                        +2 symbol match & color match (a full quadrant double),
    hero quadrant:      +0 hero-symbol miss; +2 hero-symbol match & color miss;
                        +3 hero-symbol match & color match (the hero quadrant maxed).

This REPLACES the old independent-axis model (S = A + 2H, where the 4 colors and 4
symbols were counted independently). The four quadrants are therefore no longer
independent axes — each contributes a joint (symbol, color) score. The standalone
hero multiplier (HERO_BOOST / HERO_PENALTY / HERO_SCALE) is GONE — the hero is
folded directly into S.

S = 9 is the jackpot and remains EXACTLY the all-8-axes event (every quadrant a full
symbol+color double), which is BYTE-FOR-BYTE the same physical event (and the same
odds) as the old M = 8 all-8-axes-match jackpot — so the S = 9 payout is a RELABEL of
the old M = 8 value (values unchanged, pinned). Variant-2 leaves P(S=9) byte-identical
to HEAD; only the intermediate S distribution moves (main slot ~1-in-3 / 32% -> ~1-in-5
at ~2x multipliers at IDENTICAL EV).

DEC-03 floor S>=2: a lone ordinary (non-hero) symbol match = S=1 (SHAPE pays 0 there);
the hero symbol alone = S=2 and a full quadrant double = S=2 (both pay).

Player ticket has N gold quadrants (N in {0, 1, 2, 3, 4}).

DEC-02 Option B (EV-equality wrinkle — RESOLVED 2026-06-21): because color is gated
behind symbol, the hero quadrant's gold-ness now shifts P_N(S) — within a fixed N a
hero-gold ticket and a hero-common ticket have meaningfully different score
distributions. The 452-02 GEN run MEASURED the resulting hero-placement EV drift on
the HONEST (ETH/FLIP) lane at max 2.9923 centi-x (N=3), with the hero-COMMON sub-case
EV-POSITIVE (>100 centi-x) at N=1..3 — grossly outside the ~0.5 centi-x tolerance, and
PLAYER-SELECTABLE via the custom-ticket heroQuadrant param. The USER resolved DEC-02 to
**Option B (exact EV-equality)**:
  - The HONEST family is split per (N, hero-is-gold). Each structurally-valid sub-case
    (N0 hero-common; N1/N2/N3 hero-gold|hero-common; N4 hero-gold => ~8 base tables) is
    calibrated so basePayoutEV = 100 centi-x against THAT sub-case's OWN Variant-2 score
    distribution. Each pick is then exactly EV-equal (no player-selectable edge) and the
    honest +5% ETH bonus EV is exactly 5.000% within EACH sub-case.
  - The WWXRP `_RIG_` family stays AVERAGED at 5 per-N tables — WWXRP hero-placement
    drift is accepted by-design per the USER don't-care ruling ("worthless shitcoin").
  - 453 IMPL's `_getBasePayoutBps` gains a `heroIsGold` selector used ONLY when
    `!isWwxrp` (the honest table is indexed by (N, heroIsGold); the _RIG_ table by N
    only). N0 (always hero-common) and N4 (always hero-gold) collapse to one table each.
The generator emits the per-(N,hero-gold) honest constant family, RE-VERIFIES the drift
is now ~0 (within _solve_table rounding), and PRINTS the exact 453 dispatch shape. The
averaged honest P_N(S) is retained ONLY for the placement-independent P(S=9) invariant
checks and the rigged-dist P(S=9) equality (S=9 depends on the gold/common COUNT, not
which quadrant is the hero).

Per-axis Bernoulli match probabilities (producer: color [16,16,16,16,16,16,16,8]/120,
symbol uniform 1/8):
  color axis:  P(match) = 2/15  (common, w=16)   |  1/15  (gold, w=8)
  symbol axis: P(match) = 1/8   (uniform, all quadrants)

P_N(S) = convolution over the four per-quadrant joint (symbol, color) contributions:
  - 1 hero quadrant   over {0, +2, +3} (hero symbol 1/8; its color gated behind it),
  - 3 ordinary quadrants, each over {0, +1, +2} (symbol 1/8; color gated behind it),
  averaged over hero placement at P(hero gold | N) = N/4 (DEC-02 Option A).

PAYOUT SHAPE (S = 2..9; S = 0, 1 pay 0):
  SHAPE[2..8] = [190, 475, 1500, 4250, 19500, 100000, 5_000_000] (relative ratios,
  scaled per-N to hit EV = 100), and S = 9 is PINNED to the old M = 8 relabel
  constants (10_756_411 .. 20_916_435; strictly monotone in N). The shape preserves
  the proven frequent-small / juicy-top profile of the 9-bucket design, inserting a
  near-jackpot S = 8 tier (~2.6M..5.0M centi-x) below the S = 9 jackpot.

Packing (matches the FROZEN contract dispatch, DegenerusGameDegeneretteModule.sol
_getBasePayoutBps): S = 0..7 are packed 32 bits each into
QUICK_PLAY_PAYOUTS_N{N}_PACKED (read `(packed >> (s*32)) & 0xFFFFFFFF`); S = 8 and
S = 9 are each a SEPARATE per-N uint256 (QUICK_PLAY_PAYOUT_N{N}_S8 / _S9),
dispatched ahead of the packed path (`if (s>=9) S9; if (s==8) S8;`).

WWXRP factor buckets shift to B = 6..9 (shift-by-one from the old 5..8 floor),
packed 64 bits each (B = 6 in the low 64 bits): read
`(packed >> ((bucket-6)*64)) & 0xFFFFFFFFFFFFFFFF`. Total ETH bonus EV = exactly
5.000% per N at the 10/30/30/30 split across B = 6/7/8/9 with ETH_BONUS_BPS = 500.

This script is the CANONICAL byte-reproduce source of truth for the contract
constants (Phase 267-style PASS_ALL gate at TST). Constants are NEVER hand-typed —
the gate regenerates them from this stdout and diffs against the contract source.
"""

from fractions import Fraction

# -------------------------------------------------------------------------
# Per-axis Bernoulli distributions
# -------------------------------------------------------------------------

# Color per-axis: [P(miss), P(match)].  common w=16 -> 2/15 ; gold w=8 -> 1/15.
P_COLOR_COMMON = [Fraction(13, 15), Fraction(2, 15)]
P_COLOR_GOLD = [Fraction(14, 15), Fraction(1, 15)]
# Symbol per-axis (uniform 1/8): contributes 0 or 1.
P_SYM = [Fraction(7, 8), Fraction(1, 8)]
# Hero symbol axis (Bernoulli 1/8): contributes 0 or 2 (note the gap at index 1).
P_HERO = [Fraction(7, 8), Fraction(0), Fraction(1, 8)]

assert sum(P_COLOR_COMMON) == 1
assert sum(P_COLOR_GOLD) == 1
assert sum(P_SYM) == 1
assert sum(P_HERO) == 1


def convolve(a, b):
    out = [Fraction(0)] * (len(a) + len(b) - 1)
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            out[i + j] += x * y
    return out


def _ordinary_quadrant_dist(p_color_match):
    """Variant-2 per-(ordinary)-quadrant score over {0, +1, +2}.

    Color is GATED behind the same quadrant's symbol: the color scores +1 ONLY IF
    that quadrant's symbol also matched. So with symbol match prob ps = 1/8 and
    color match prob pc:
        +0  symbol miss            (pc is a no-op when the symbol misses)
        +1  symbol match, color miss
        +2  symbol match, color match  (a full quadrant double)
    """
    ps = P_SYM[1]  # 1/8
    return [1 - ps, ps * (1 - p_color_match), ps * p_color_match]


def _hero_quadrant_dist(p_color_match):
    """Variant-2 hero-quadrant score over {0, _, +2, +3}.

    The hero quadrant's SYMBOL scores +2 (Bernoulli 1/8); its color scores +1 ONLY
    IF the hero symbol also matched (same color-gated-by-symbol rule). Index 1 is
    structurally zero (the hero symbol alone is +2, never +1):
        +0  hero symbol miss
        +2  hero symbol match, color miss   (hero alone -> S=2 win, pays per DEC-03)
        +3  hero symbol match, color match  (the hero quadrant maxed)
    """
    ps = P_SYM[1]  # 1/8
    return [1 - ps, Fraction(0), ps * (1 - p_color_match), ps * p_color_match]


def p_score_distribution(n_gold):
    """Variant-2 P(S = k) for a ticket with n_gold gold quadrants, S in {0..9}.

    Variant-2 (color-gated-by-symbol): per quadrant a SYMBOL match scores +1 (the
    hero quadrant's symbol scores +2), and that quadrant's COLOR scores +1 ONLY IF
    that quadrant's symbol also matched. The four quadrants are therefore no longer
    independent axes — each quadrant contributes a joint (symbol, color) score, and
    the ticket score is the convolution of the four per-quadrant contributions:
        - 3 ordinary quadrants, each over {0, +1 (symbol only), +2 (symbol+color)},
        - 1 hero quadrant, over {0, +2 (hero symbol only), +3 (hero symbol+color)}.
    Max S = 9 = hero quad (3) + three ordinary quads (2 each).

    DEC-03 floor S>=2: a lone ordinary (non-hero) symbol match = S=1 (SHAPE pays 0
    there); the hero symbol alone = S=2 and a full quadrant double = S=2 (both pay).

    DEC-02 Option B (EV-equality wrinkle): under Option B the HONEST PAYOUT family is
    split per (N, hero-is-gold) (see `_hero_placement_subcase` + the honest sub-case
    solve below). This averaged per-N distribution is RETAINED ONLY for the
    placement-independent invariant checks: it feeds P_N_TABLE, whose index 9
    (P(S=9)) is used for the S9_PIN relabel, the rigged-dist `rig[9] == honest[9]`
    assert, and the numeric pre-proof. P(S=9) is placement-independent (it depends on
    the gold/common COUNT N, not which quadrant is the hero), so the averaged P_N(S=9)
    equals every sub-case's P(S=9) — the honest PAYOUT tables themselves are solved
    against the per-sub-case distributions, NOT this averaged one.

    CRITICAL: S=9 stays exactly the all-8-axes event (every quadrant a full double),
    so honest P_N(S=9) = product of all eight per-axis match probabilities, BYTE-
    IDENTICAL to HEAD — the S9_PIN reproduction loop below must still pass unchanged.
    """
    dist = [Fraction(0)] * 10
    # Average over hero placement (DEC-02 Option A) within a fixed gold count N.
    #   hero gold  (weight n_gold/4):   ordinary colors = (n_gold-1) gold + (4-n_gold) common
    #   hero common(weight (4-n_gold)/4): ordinary colors =  n_gold    gold + (3-n_gold) common
    for hero_is_gold, weight, ord_gold, ord_common in (
        (True, Fraction(n_gold, 4), n_gold - 1, 4 - n_gold),
        (False, Fraction(4 - n_gold, 4), n_gold, 3 - n_gold),
    ):
        if weight == 0:
            continue
        hero_color = P_COLOR_GOLD[1] if hero_is_gold else P_COLOR_COMMON[1]
        sub = _hero_quadrant_dist(hero_color)
        for _ in range(ord_gold):
            sub = convolve(sub, _ordinary_quadrant_dist(P_COLOR_GOLD[1]))
        for _ in range(ord_common):
            sub = convolve(sub, _ordinary_quadrant_dist(P_COLOR_COMMON[1]))
        while len(sub) < 10:
            sub.append(Fraction(0))
        for k in range(10):
            dist[k] += weight * sub[k]
    assert len(dist) == 10, f"S distribution length {len(dist)} != 10"
    return dist


# --- Print P_N(S) for each N ---
print(f"{'N':>3} | {'E[S]':>7} | " + " | ".join(f"S={k:<2}P(S)".rjust(11) for k in range(10)))
print("-" * 145)
P_N_TABLE = []
for N in range(5):
    dist = p_score_distribution(N)
    P_N_TABLE.append(dist)
    expected = sum(k * p for k, p in enumerate(dist))
    cells = " | ".join(f"{float(p):>10.7f}" for p in dist)
    print(f"{N:>3} | {float(expected):>7.4f} | {cells}")
    assert sum(dist) == 1, f"P_N(S) for N={N} does not sum to 1"
print()

# -------------------------------------------------------------------------
# S = 9 relabel pin (== old M = 8 jackpot; values unchanged, monotone in N).
# These are FINAL in the contract; the script reproduces them so the relabel
# stays consistent with the old 9-bucket M = 8 scaling.
# -------------------------------------------------------------------------
S9_PIN = [10_756_411, 12_583_037, 14_792_939, 17_512_324, 20_916_435]

# Verify S = 9 reproduces the old M = 8 scaling (relabel consistency).
# Old design: SHAPE_OLD[8] = 10_000_000 scaled so basePayoutEV(old) = 100 against
# the old P_N(M) (8-axis match distribution). The old M = 8 event == new S = 9 event,
# so the old M = 8 scaled value is the pin.
_P_COMMON_OLD = [Fraction(91, 120), Fraction(27, 120), Fraction(2, 120)]
_P_GOLD_OLD = [Fraction(98, 120), Fraction(21, 120), Fraction(1, 120)]
_SHAPE_OLD = [0, 0, 190, 475, 1500, 4250, 19500, 100000, 10_000_000]


def _p_old(n_gold):
    d = [Fraction(1)]
    for _ in range(4 - n_gold):
        d = convolve(d, _P_COMMON_OLD)
    for _ in range(n_gold):
        d = convolve(d, _P_GOLD_OLD)
    return d


for N in range(5):
    PM = _p_old(N)
    shape_ev_old = sum(_SHAPE_OLD[k] * PM[k] for k in range(9))
    scale_old = Fraction(100) / shape_ev_old
    m8_reproduced = round(_SHAPE_OLD[8] * scale_old)
    assert m8_reproduced == S9_PIN[N], (
        f"S=9 relabel pin mismatch N={N}: reproduced {m8_reproduced} != pin {S9_PIN[N]}"
    )
print("S=9 relabel pin reproduced from the old M=8 scaling for all N (consistent).")
print()

# -------------------------------------------------------------------------
# Payout SHAPE over S = 2..8 (S = 0, 1 pay 0; S = 9 pinned).
# Frequent-small / juicy-top profile carried from the 9-bucket design, with a
# near-jackpot S = 8 tier inserted below the S = 9 jackpot.
# -------------------------------------------------------------------------
SHAPE = [0, 0, 190, 475, 1500, 4250, 19500, 100000, 5_000_000, None]  # S=9 pinned
TARGET_EV = 100  # centi-x

print(f"Payout SHAPE (relative, S=2..8): {SHAPE[2:9]}  (S=9 pinned to the M=8 relabel)\n")


def total_ev(payouts, p_S):
    return sum(payouts[k] * p_S[k] for k in range(10))


def _hero_placement_subcase(n_gold, hero_is_gold):
    """Variant-2 P(S) for a fixed N and a FIXED hero placement (no averaging).

    Reuses the exact per-quadrant convolution of `p_score_distribution`, but for a
    single hero-placement branch:
      hero gold   : hero color = gold;   ordinary colors = (N-1) gold + (4-N) common
      hero common : hero color = common; ordinary colors =  N    gold + (3-N) common
    Returns a length-10 distribution (sums to 1). Returns None when the requested
    placement is impossible for this N (hero gold needs N>=1; hero common needs N<=3).

    This is the per-sub-case distribution Option B solves each honest table against —
    fixing the hero quadrant's gold-ness removes the averaging that hid the EV drift."""
    if hero_is_gold:
        if n_gold < 1:
            return None
        ord_gold, ord_common = n_gold - 1, 4 - n_gold
        hero_color = P_COLOR_GOLD[1]
    else:
        if n_gold > 3:
            return None
        ord_gold, ord_common = n_gold, 3 - n_gold
        hero_color = P_COLOR_COMMON[1]
    sub = _hero_quadrant_dist(hero_color)
    for _ in range(ord_gold):
        sub = convolve(sub, _ordinary_quadrant_dist(P_COLOR_GOLD[1]))
    for _ in range(ord_common):
        sub = convolve(sub, _ordinary_quadrant_dist(P_COLOR_COMMON[1]))
    while len(sub) < 10:
        sub.append(Fraction(0))
    assert sum(sub) == 1, f"hero-placement sub-case N={n_gold} gold={hero_is_gold} != 1"
    return sub


def _solve_table(pS, N):
    """SHAPE + S9-pin solve against an arbitrary score distribution pS.

    Currency-/sub-case-agnostic and reused UNCHANGED by the honest per-(N,heroGold)
    sub-cases (Option B) and the averaged WWXRP _RIG_ family. Calibrates the S=2..8
    SHAPE so basePayoutEV = 100 centi-x against pS, with the residual-absorption
    refine (coarse S=4 / fine S=5 / ultra-fine S=6) and the neutral-or-just-under
    nudge (never EV-positive)."""
    ev_fixed = Fraction(S9_PIN[N]) * pS[9]
    shape_ev_N = sum(Fraction(SHAPE[k]) * pS[k] for k in range(2, 9))
    scale = (Fraction(TARGET_EV) - ev_fixed) / shape_ev_N
    payouts = (
        [0, 0]
        + [round(Fraction(SHAPE[k]) * scale) for k in range(2, 9)]
        + [S9_PIN[N]]
    )
    # Residual-absorption refine (coarse S=4, fine S=5, ultra-fine S=6) to drive
    # |drift| well under 0.5 centi-x — same approach as the 9-bucket design.
    for adj in (4, 5, 6):
        residual = Fraction(TARGET_EV) - total_ev(payouts, pS)
        payouts[adj] += round(residual / pS[adj])
    # Neutral-or-just-under guarantee: the baseline basePayoutEV (before the
    # activity-score ROI scaling and the ETH/WWXRP bonus) must never exceed
    # TARGET_EV — the house is never EV-negative on the base table. If integer
    # rounding overshot above 100 centi-x, nudge the ultra-fine S=6 tier down by
    # the minimal amount that brings EV back to <= 100 (lands fractionally under).
    while total_ev(payouts, pS) > Fraction(TARGET_EV):
        payouts[6] -= 1
    return payouts


# -------------------------------------------------------------------------
# DEC-02 Option B — HONEST family split per (N, hero-is-gold).
# Each structurally-valid sub-case is solved against its OWN Variant-2
# distribution (not the N/4-averaged one), so each pick is EXACTLY EV-equal
# (the 2.99 centi-x hero-placement edge measured in 452-02 is closed). Valid
# sub-cases: N0->{common}; N1/N2/N3->{gold, common}; N4->{gold} = 8 tables.
# `hero_is_gold` means the hero quadrant's color is gold (1/15) and N-1 of the
# other 3 quadrants are gold; `hero common` means the hero color is common
# (2/15) and all N gold quads are among the other 3 (requires N<=3).
# -------------------------------------------------------------------------

# Enumerate the structurally-valid honest sub-cases as (N, hero_is_gold).
HONEST_SUBCASES = []
for N in range(5):
    for hero_is_gold in (True, False):
        if _hero_placement_subcase(N, hero_is_gold) is not None:
            HONEST_SUBCASES.append((N, hero_is_gold))

# Solve each honest sub-case against its OWN distribution.
# honest_tables[(N, hero_is_gold)] = (dist, payouts)
honest_tables = {}
for (N, hero_is_gold) in HONEST_SUBCASES:
    dist = _hero_placement_subcase(N, hero_is_gold)
    payouts = _solve_table(dist, N)
    honest_tables[(N, hero_is_gold)] = (dist, payouts)


def _sub_label(N, hero_is_gold):
    return f"N{N}/" + ("heroGOLD" if hero_is_gold else "heroCOMMON")


# --- Print the solved per-(N, hero-gold) honest payout tables ---
print(f"{'S':>3} | {'shape':>10} | " + " | ".join(_sub_label(N, g).rjust(13) for (N, g) in HONEST_SUBCASES))
print("-" * (16 + 16 * len(HONEST_SUBCASES)))
for S in range(10):
    shape_label = "PINNED(S9)" if S == 9 else (str(SHAPE[S]) if SHAPE[S] is not None else "-")
    cells = " | ".join(f"{honest_tables[(N, g)][1][S]:>13,}" for (N, g) in HONEST_SUBCASES)
    print(f"{S:>3} | {shape_label:>10} | {cells}")
print()

print("Per-(N, hero-gold) honest basePayoutEV (each vs its OWN sub-case dist):")
for (N, g) in HONEST_SUBCASES:
    dist, payouts = honest_tables[(N, g)]
    ev = float(total_ev(payouts, dist))
    print(f"  {_sub_label(N, g):>16}:  basePayoutEV = {ev:.5f} centi-x")
print()

# --- Top-bucket multipliers per honest sub-case table ---
print(f"Top-bucket multipliers per honest sub-case (× the bet amount, at 100% ROI):")
print(f"{'sub-case':>16} | {'S=5':>11} | {'S=6':>11} | {'S=7':>11} | {'S=8':>13} | {'S=9 jackpot':>15}")
for (N, g) in HONEST_SUBCASES:
    p = honest_tables[(N, g)][1]
    print(
        f"{_sub_label(N, g):>16} | {p[5]/100:>10.2f}x | {p[6]/100:>10.2f}x | {p[7]/100:>10.2f}x | "
        f"{p[8]/100:>11,.2f}x | {p[9]/100:>13,.2f}x"
    )
print()

# --- Probability of any positive payout (S >= 2) per honest sub-case ---
print(f"P(any payout, S >= 2) per honest sub-case:")
for (N, g) in HONEST_SUBCASES:
    dist = honest_tables[(N, g)][0]
    p_pay = sum(dist[k] for k in range(2, 10))
    print(f"  {_sub_label(N, g):>16}: {float(p_pay)*100:.4f}%   (1 in {1/float(p_pay):.2f} tickets)")
print()

# -------------------------------------------------------------------------
# WWXRP factor tables (per-N, B = 6..9, the rescaled floor).
# 10/30/30/30 split across B = 6/7/8/9; total ETH bonus EV = 5.000% per N.
# -------------------------------------------------------------------------
WWXRP_SCALE = 1_000_000
SPLITS = {6: Fraction(10, 100), 7: Fraction(30, 100), 8: Fraction(30, 100), 9: Fraction(30, 100)}
ETH_BONUS_BPS = 500


def wwxrp_factors_honest(N, hero_is_gold):
    """Honest (ETH/FLIP) ETH-bonus factors for a fixed (N, hero-is-gold) sub-case.

    Option B: split the same way as the base table so the honest +5% ETH bonus EV is
    exactly 5.000% WITHIN each sub-case (not just on the average). Built off the
    sub-case's own solved table + its own distribution."""
    dist, payouts = honest_tables[(N, hero_is_gold)]
    factors = {}
    for B in (6, 7, 8, 9):
        f = SPLITS[B] * 100 * WWXRP_SCALE / (dist[B] * payouts[B])
        factors[B] = round(float(f))
    return factors


print(f"WWXRP_BONUS_FACTOR (honest, per-(N,hero-gold)) at 10/30/30/30 split over B=6..9, ETH_BONUS_BPS=500:")
print(f"{'sub-case':>16} | " + " | ".join(f"BUCKET{B} factor".rjust(20) for B in (6, 7, 8, 9)))
print("-" * 110)
for (N, g) in HONEST_SUBCASES:
    factors = wwxrp_factors_honest(N, g)
    cells = " | ".join(f"{factors[B]:>20,}" for B in (6, 7, 8, 9))
    print(f"{_sub_label(N, g):>16} | {cells}")
    for B in (6, 7, 8, 9):
        assert factors[B] < (1 << 64), f"honest factor {_sub_label(N, g)} B={B} exceeds 64 bits"
print()

# ===================================================================
# FINAL PASTE-READY CONSTANTS — 10-bucket S in {0..9} design (Variant-2).
# Variant-2 color-gated-by-symbol scoring: per quadrant a symbol match
# scores +1 (hero +2), and the color scores +1 only if that quadrant's
# symbol also matched. The hero is scored into S; the standalone hero
# multiplier is GONE (no HERO_BOOST / HERO_PENALTY / HERO_SCALE). S = 9
# is still the all-8-axes event = the M = 8 relabel (P(S=9) + pin
# byte-identical to HEAD).
#
# DEC-02 Option B: the HONEST payout + ETH-bonus family is split per
# (N, hero-is-gold) — names carry a _HEROGOLD_ / _HEROCOMMON_ infix, except
# N0 (always hero-common) and N4 (always hero-gold) which collapse to one
# table each (named QUICK_PLAY_PAYOUTS_N0_PACKED / _N4_PACKED, no infix). The
# WWXRP _RIG_ family below stays AVERAGED at 5 per-N tables (WWXRP drift is
# by-design don't-care). 453's _getBasePayoutBps gains a heroIsGold selector
# used ONLY when !isWwxrp (see the dispatch-shape print at the very end).
#
# The PASS_ALL byte-reproduce gate parses this section and diffs vs the
# contract source — constants are NEVER hand-typed.
# ===================================================================

# Per-(N, hero-gold) constant-name suffix. N0/N4 have a single structurally
# valid placement, so they collapse to one table each (no HEROGOLD/HEROCOMMON
# infix); N1/N2/N3 emit both. The contract's _getBasePayoutBps reproduces this
# collapse: it only consults heroIsGold for N in {1,2,3}.
def _const_suffix(N, hero_is_gold):
    if N == 0 or N == 4:
        return f"N{N}"
    return f"N{N}_" + ("HEROGOLD" if hero_is_gold else "HEROCOMMON")


print("=" * 70)
print("FINAL PASTE-READY CONSTANTS")
print("=" * 70)

# Honest payouts split per (N, hero-gold): S = 0..7 packed; S = 8 + S = 9 separate.
print("\n// HONEST payout tables (per-(N,hero-gold), Option B): basePayoutEV = 100 centi-x ± rounding")
print("// N0 (always hero-common) and N4 (always hero-gold) collapse to one table each.")
for (N, g) in HONEST_SUBCASES:
    dist, p = honest_tables[(N, g)]
    packed = 0
    for S in range(8):
        packed |= (p[S] & 0xFFFFFFFF) << (S * 32)
    actual_ev = float(total_ev(p, dist))
    print(
        f"uint256 private constant QUICK_PLAY_PAYOUTS_{_const_suffix(N, g)}_PACKED = "
        f"0x{packed:064x};  // {_sub_label(N, g)} EV={actual_ev:.4f}"
    )
print()
for (N, g) in HONEST_SUBCASES:
    p_S8 = honest_tables[(N, g)][1][8]
    print(
        f"uint256 private constant QUICK_PLAY_PAYOUT_{_const_suffix(N, g)}_S8 = "
        f"{p_S8:>11};  // {_sub_label(N, g)} {p_S8/100:>12,.2f}x bet"
    )
print()
# S=9 pins are placement-independent (P(S=9) depends only on the gold COUNT N),
# so the five per-N S9 pins are UNCHANGED vs HEAD and emitted by N only.
for N in range(5):
    p_S9 = S9_PIN[N]
    print(
        f"uint256 private constant QUICK_PLAY_PAYOUT_N{N}_S9 = {p_S9:>11};  // {p_S9/100:>12,.2f}x bet"
    )

# Honest WWXRP/ETH-bonus factors split per (N, hero-gold): B = 6..9 packed; B = 6 low.
print("\n// HONEST WWXRP factors (per-(N,hero-gold)) at 10/30/30/30 over B=6..9, basePayoutEV=100, ETH_BONUS_BPS=500")
for (N, g) in HONEST_SUBCASES:
    factors = wwxrp_factors_honest(N, g)
    packed = 0
    for i, B in enumerate((6, 7, 8, 9)):
        packed |= (factors[B] & ((1 << 64) - 1)) << (i * 64)
    print(f"uint256 private constant WWXRP_FACTORS_{_const_suffix(N, g)}_PACKED = 0x{packed:064x};")

# Per-pick EV verification (Option B: each sub-case vs its OWN dist)
print("\n// Per-(N,hero-gold) honest basePayoutEV verification (centi-x):")
print(f"// {'sub-case':>16} | basePayoutEV | drift from 100")
for (N, g) in HONEST_SUBCASES:
    dist, payouts = honest_tables[(N, g)]
    ev_frac = total_ev(payouts, dist)
    ev = float(ev_frac)
    drift_bps = (ev - 100) * 100
    # Baseline must be neutral-or-just-under: <= 100 centi-x (never EV-positive)
    # and within 0.5 centi-x of neutral (so it is ~100%, not a slack house edge).
    # Under Option B this holds PER sub-case (each table is EV-exact for its own
    # placement), so the hero-common EV>100 edge measured in 452-02 is closed.
    assert ev_frac <= Fraction(TARGET_EV), (
        f"{_sub_label(N, g)} basePayoutEV {ev} exceeds 100 centi-x — baseline must be neutral or just under"
    )
    assert ev_frac > Fraction(TARGET_EV) - 1, (
        f"{_sub_label(N, g)} basePayoutEV {ev} drifts more than 0.5 centi-x below neutral"
    )
    print(f"// {_sub_label(N, g):>16} |  {ev:>9.5f}   |  {drift_bps:+.4f} bps")

# ETH-bonus EV verification (per sub-case)
print("\n// Per-(N,hero-gold) honest ETH-bonus EV verification (target = 5.0000%):")
for (N, g) in HONEST_SUBCASES:
    dist, payouts = honest_tables[(N, g)]
    factors = wwxrp_factors_honest(N, g)
    total_bonus = sum(
        dist[B] * payouts[B] / 100 *
        (ETH_BONUS_BPS * Fraction(factors[B], WWXRP_SCALE)) / 10000
        for B in (6, 7, 8, 9)
    )
    drift_bps = (float(total_bonus) - 0.05) * 10000
    assert abs(float(total_bonus) - 0.05) < 0.05 * 0.01, (
        f"{_sub_label(N, g)} ETH bonus EV {float(total_bonus)} outside ±1% of 5%"
    )
    print(f"//   {_sub_label(N, g):>16}: bonus EV = {float(total_bonus)*100:.6f}%   drift {drift_bps:+.4f} bps")

# Total ticket EV at MAX activity for ETH player (per sub-case)
print("\n// Per-(N,hero-gold) honest total ETH player RTP @ MAX activity (9990 bps + 5% bonus):")
for (N, g) in HONEST_SUBCASES:
    dist, payouts = honest_tables[(N, g)]
    base_ev = float(total_ev(payouts, dist)) / 100
    base_rtp = base_ev * 0.999
    bonus = 0.05
    total = base_rtp + bonus
    print(f"//   {_sub_label(N, g):>16}: total RTP = {total*100:.4f}%")


# ===================================================================
# WWXRP RIG FAMILY — DEC-01 R2 score-bearing rig (+1, 60%, M<=6 gate).
# Under Variant-2 the WWXRP rig forces ONE *score-bearing* cell to a real
# match w.p. 3/5 when M<=6: an unmatched NON-HERO symbol (+1), or an
# unmatched COLOR on a quadrant whose symbol ALREADY matched (+1, the
# color "unlocks"; incl. the hero quadrant's color — only the hero SYMBOL
# is excluded). No-op colors and the hero symbol are excluded; when the
# eligible pool is empty there is no lift that round. Caps at M=7 so the
# rig can NEVER manufacture S=9 -> P(S=9) is INVARIANT (RIG-02), and
# display==score stays honest (RIG-03). WWXRP gets its OWN 5 per-N base
# tables (EV=100 centi-x under the RIGGED dist) + its OWN factors. Per
# DEC-02 Option B the rigged family stays AVERAGED at 5 per-N tables — it is
# NOT split per (N, hero-is-gold) like the honest lane, because WWXRP
# hero-placement drift is accepted by-design (USER don't-care ruling). S=9
# reuses the honest QUICK_PLAY_PAYOUT_N{N}_S9 pin (P(S=9) unchanged by the
# rig). ETH/FLIP keep the per-(N,hero-gold) honest tables above. Names carry
# a _RIG_ infix. The byte-reproduce gate parses these from the SAME FINAL block.
# ===================================================================

_HERO_BERN = [Fraction(7, 8), Fraction(1, 8)]  # hero matched 0/1


def _quad_states(p_color_match):
    """The four per-quadrant joint (symbol-matched, color-matched) states with their
    probabilities, for a quadrant with color match prob `p_color_match` and the
    uniform 1/8 symbol match prob. Returns [(sm, cm, prob), ...]."""
    ps = P_SYM[1]  # 1/8
    states = []
    for sm in (0, 1):
        p_sm = ps if sm == 1 else (1 - ps)
        for cm in (0, 1):
            p_cm = p_color_match if cm == 1 else (1 - p_color_match)
            states.append((sm, cm, p_sm * p_cm))
    return states


def p_score_distribution_rigged(n_gold):
    """DEC-01 R2 rigged P_N(S), consistent with the Variant-2 honest rule (Task 1).

    The WWXRP rig forces ONE *score-bearing* cell to a real match w.p. 3/5 when the
    roll has M <= 6 matched axes; M >= 7 (full match / single miss) is untouched so
    the rig can NEVER manufacture (or destroy) S=9 -> P(S=9) is invariant (RIG-02).

    Per-quadrant we enumerate the joint (symbol-matched sm, color-matched cm) state
    under Variant-2 and compute (a) the base score S (color counts only when that
    quadrant's symbol matched; hero symbol +2), (b) the total matched-axis count
    M = sum of all eight per-axis matches, and (c) the SCORE-BEARING eligible-cell
    count e — the cells whose forced match RAISES S under Variant-2 (DEC-01 R2):
        (a) an unmatched NON-HERO symbol cell -> forcing the symbol scores +1 if that
            quadrant's color is ALSO unmatched, or +2 if the color already matched (the
            forced symbol UNLOCKS the gated color — USER ruling: allow the +2 unlock);
        (b) an unmatched COLOR on a quadrant whose symbol ALREADY matched
            (sm==1, cm==0; the color "unlocks" -> +1; includes the hero quadrant's
             COLOR, which is an ordinary axis — only the hero SYMBOL is excluded).
    EXCLUDED from the pool: the hero symbol cell (never rigged) and *no-op* colors
    (a color on a quadrant whose symbol is still unmatched buys nothing under
    Variant-2). The rig picks ONE eligible cell uniformly; the lift is +1 (most cells)
    or +2 (forcing a symbol onto an already-color-matched quad). The m>=7 cap means a
    fired roll has M<=6 -> post-force M<=7 -> S<=8, so a +2 can NEVER reach S=9
    ("not if it makes a 9/9"); the rig[9]==honest[9] assert is the hard proof.

    Explicit EMPTY-ELIGIBLE-POOL case: when M <= 6 but every unmatched cell is an
    excluded one (the hero symbol and/or no-op colors), the score-bearing pool is
    empty (e == 0) -> NO lift that round; the mass stays at baseS even though the
    3/5 gate would otherwise fire.

    DEC-02 Option B (WWXRP stays averaged by-design): the HONEST family is split per
    (N, hero-is-gold) for exact EV-equality, but the rigged WWXRP family is kept
    AVERAGED over hero placement (hero gold w.p. n_gold/4, common w.p. (4-n_gold)/4) —
    WWXRP hero-placement drift is accepted by-design per the USER don't-care ruling
    ("worthless shitcoin"). So this rigged distribution stays a single averaged per-N
    table; only the honest lane splits.
    """
    pf = Fraction(3, 5)
    out = [Fraction(0)] * 10
    for hero_is_gold, weight, ord_gold, ord_common in (
        (True, Fraction(n_gold, 4), n_gold - 1, 4 - n_gold),
        (False, Fraction(4 - n_gold, 4), n_gold, 3 - n_gold),
    ):
        if weight == 0:
            continue
        hero_color = P_COLOR_GOLD[1] if hero_is_gold else P_COLOR_COMMON[1]
        # quad spec list: (state_list, is_hero) — quad 0 is the hero quadrant.
        quads = [(_quad_states(hero_color), True)]
        for _ in range(ord_gold):
            quads.append((_quad_states(P_COLOR_GOLD[1]), False))
        for _ in range(ord_common):
            quads.append((_quad_states(P_COLOR_COMMON[1]), False))
        # Fold the four quadrants into a joint distribution over (S, M, e).
        # partials maps (S, M, e) -> probability of reaching that partial state.
        # Track score-bearing eligible cells split by the lift they yield when forced:
        # e1 = cells that lift +1, e2 = cells that lift +2 (the color-unlock). The rig
        # picks ONE eligible cell uniformly, so the realized lift is +1 w.p. e1/(e1+e2)
        # and +2 w.p. e2/(e1+e2). partials key = (S, M, e1, e2).
        partials = {(0, 0, 0, 0): weight}
        for states, is_hero in quads:
            nxt = {}
            for (S, M, e1, e2), pacc in partials.items():
                for sm, cm, pp in states:
                    dS = 0
                    if sm == 1:
                        dS += 2 if is_hero else 1
                        if cm == 1:
                            dS += 1
                    dM = sm + cm
                    de1 = 0
                    de2 = 0
                    if (not is_hero) and sm == 0:
                        # (a) unmatched non-hero symbol -> force the symbol.
                        #   color also unmatched (cm==0) -> +1; color already matched
                        #   (cm==1, a gated no-op color) -> the force UNLOCKS it -> +2.
                        if cm == 0:
                            de1 += 1
                        else:
                            de2 += 1
                    if sm == 1 and cm == 0:
                        de1 += 1  # (b) unmatched color on a symbol-matched quad -> +1
                    key = (S + dS, M + dM, e1 + de1, e2 + de2)
                    nxt[key] = nxt.get(key, Fraction(0)) + pacc * pp
            partials = nxt
        # Apply the rig per full-roll outcome. When the 3/5 gate fires the rig picks one
        # score-bearing cell uniformly: lift +1 (e1 cells) or +2 (e2 unlock cells). The
        # m>=7 cap means a fired roll has M<=6 -> post-force M<=7 -> S<=8, so a +2 can
        # NEVER reach S=9 (USER: "allow +2 but not if it makes a 9/9"); the
        # rig[9]==honest[9] assert below is the hard proof of the P(S=9) invariant.
        for (S, M, e1, e2), p in partials.items():
            etot = e1 + e2
            if M >= 7:
                out[S] += p  # m>=7 cap: untouched -> P(S=9) invariant
            elif etot == 0:
                out[S] += p  # empty eligible pool: no lift this round
            else:
                out[S] += p * (1 - pf)                      # 40% gate no-op
                out[S + 1] += p * pf * Fraction(e1, etot)   # picked a +1 cell
                if e2:
                    out[S + 2] += p * pf * Fraction(e2, etot)  # picked a +2 unlock cell
    assert sum(out) == 1, f"rigged P_N(S) N={n_gold} != 1"
    assert len(out) == 10
    return out


# Rigged distribution per N + S=9 invariance vs honest.
P_N_RIG = []
for N in range(5):
    rig = p_score_distribution_rigged(N)
    assert rig[9] == P_N_TABLE[N][9], f"rig must not change P(S=9) for N={N}"
    P_N_RIG.append(rig)


# `_solve_table` (defined above, shared with the honest Option-B sub-cases) is reused
# UNCHANGED for the averaged WWXRP _RIG_ family — same SHAPE / S9 pin / residual solve.
tables_rig = [_solve_table(P_N_RIG[N], N) for N in range(5)]


def wwxrp_factors_rig(N):
    payouts = tables_rig[N]
    factors = {}
    for B in (6, 7, 8, 9):
        f = SPLITS[B] * 100 * WWXRP_SCALE / (P_N_RIG[N][B] * payouts[B])
        factors[B] = round(float(f))
    return factors


print("\n" + "=" * 70)
print("WWXRP RIG FAMILY — FINAL PASTE-READY CONSTANTS (DEC-01 R2 score-bearing rig)")
print("=" * 70)
print("\n// Rigged WWXRP base tables (per-N): basePayoutEV = 100 centi-x under the rigged dist")
for N in range(5):
    p = tables_rig[N]
    packed = 0
    for S in range(8):
        packed |= (p[S] & 0xFFFFFFFF) << (S * 32)
    ev = float(total_ev(p, P_N_RIG[N]))
    print(f"uint256 private constant QUICK_PLAY_PAYOUTS_RIG_N{N}_PACKED = 0x{packed:064x};  // EV={ev:.4f}")
print()
for N in range(5):
    p_S8 = tables_rig[N][8]
    print(f"uint256 private constant QUICK_PLAY_PAYOUT_RIG_N{N}_S8 = {p_S8:>11};  // {p_S8/100:>12,.2f}x bet")
print("\n// Rigged WWXRP factors (per-N, B=6..9 packed, B=6 low): 10/30/30/30, bonus EV=5%/500bps")
for N in range(5):
    factors = wwxrp_factors_rig(N)
    packed = 0
    for i, B in enumerate((6, 7, 8, 9)):
        packed |= (factors[B] & ((1 << 64) - 1)) << (i * 64)
    print(f"uint256 private constant WWXRP_FACTORS_RIG_N{N}_PACKED = 0x{packed:064x};")

# Verification: rigged base EV neutral-or-just-under; factors fit 64-bit; bonus EV=5%.
print("\n// Rigged-table verification:")
for N in range(5):
    ev_frac = total_ev(tables_rig[N], P_N_RIG[N])
    assert ev_frac <= Fraction(TARGET_EV), f"rigged N={N} EV-positive"
    assert ev_frac > Fraction(TARGET_EV) - 1, f"rigged N={N} EV drifts >0.5 under"
    factors = wwxrp_factors_rig(N)
    for B in (6, 7, 8, 9):
        assert factors[B] < (1 << 64), f"rigged factor N={N} B={B} exceeds 64 bits"
    total_bonus = sum(
        P_N_RIG[N][B] * tables_rig[N][B] / 100 *
        (ETH_BONUS_BPS * Fraction(factors[B], WWXRP_SCALE)) / 10000
        for B in (6, 7, 8, 9)
    )
    assert abs(float(total_bonus) - 0.05) < 0.05 * 0.01, f"rigged N={N} bonus EV off"
    print(f"//   N={N}: rigged EV={float(ev_frac):.5f} centi-x | bonus EV={float(total_bonus)*100:.5f}% | factors<2^64 OK")


# ===================================================================
# EVEQ-01 / DEC-02 Option B — exact EV-equality CONFIRMATION.
# Under Option B each honest sub-case has its OWN payout table, solved against
# its OWN Variant-2 hero-placement distribution. So the EV a player realizes is
# basePayoutEV of THAT sub-case's own table — and every honest sub-case is
# calibrated to 100 centi-x (the per-sub-case EV-<=100 + >99 asserts in the
# FINAL block above). This section CONFIRMS the residual hero-placement edge is
# now ~0: it reports, per N, EV(hero gold | gold's OWN table) vs EV(hero common
# | common's OWN table) and the cross-placement |drift|; the max must be within
# the _solve_table integer-rounding granularity (<< the old 2.99 centi-x
# averaged-table edge), and it is hard-asserted below. The 2.99 centi-x
# player-selectable hero-common edge (EV-positive at N=1..3 in 452-02) is CLOSED.
#
# The WWXRP _RIG_ lane keeps its averaged-table drift by-design (USER don't-care
# ruling: "worthless shitcoin") — only the honest ETH/FLIP lane is made exactly
# EV-equal here.
# ===================================================================

print("\n" + "=" * 70)
print("EVEQ-01 / DEC-02 Option B — exact EV-equality CONFIRMATION (centi-x), each vs OWN table")
print("=" * 70)
print(f"// {'N':>3} | {'EV(hero gold)':>14} | {'EV(hero common)':>16} | {'|drift|':>10}")
max_drift = Fraction(0)
max_drift_N = None
for N in range(5):
    sub_gold = _hero_placement_subcase(N, True)
    sub_common = _hero_placement_subcase(N, False)
    # Option B: evaluate each sub-case against its OWN solved table — that IS the
    # EV a player on that pick realizes, so the cross-placement drift is the
    # residual selectable edge after the split.
    ev_gold = total_ev(honest_tables[(N, True)][1], sub_gold) if sub_gold is not None else None
    ev_common = total_ev(honest_tables[(N, False)][1], sub_common) if sub_common is not None else None
    if ev_gold is not None and ev_common is not None:
        drift = abs(ev_gold - ev_common)
        gold_s = f"{float(ev_gold):>14.5f}"
        common_s = f"{float(ev_common):>16.5f}"
    else:
        drift = Fraction(0)  # only one placement exists -> no cross-placement drift
        gold_s = (f"{float(ev_gold):>14.5f}" if ev_gold is not None else f"{'n/a':>14}")
        common_s = (f"{float(ev_common):>16.5f}" if ev_common is not None else f"{'n/a':>16}")
    if drift > max_drift:
        max_drift = drift
        max_drift_N = N
    print(f"// {N:>3} | {gold_s} | {common_s} | {float(drift):>10.5f}")
print(
    f"// MAX hero-placement EV drift across N = {float(max_drift):.5f} centi-x"
    + (f" (at N={max_drift_N})" if max_drift_N is not None else "")
)
# Hard-assert exact EV-equality: the residual must be within the _solve_table
# integer-rounding granularity (a few centi-x THOUSANDTHS), orders of magnitude
# below the old 2.99 centi-x averaged-table edge. Bound at 0.01 centi-x (the old
# edge / ~300) — anything larger means a sub-case was not solved against its own dist.
EVEQ_RESIDUAL_TOL = Fraction(1, 100)  # 0.01 centi-x
assert max_drift <= EVEQ_RESIDUAL_TOL, (
    f"Option B FAIL: residual hero-placement drift {float(max_drift):.5f} centi-x exceeds "
    f"the {float(EVEQ_RESIDUAL_TOL)} centi-x rounding bound — a sub-case is not EV-exact"
)
print(
    f"// Option B: honest lane exactly EV-equal across hero placement "
    f"(residual <= {float(max_drift):.5f} centi-x, within _solve_table rounding)."
)
print(
    "//   The 2.99 centi-x player-selectable hero-common edge (EV-positive at N=1..3 in"
)
print(
    "//   452-02) is CLOSED — no heroQuadrant pick is now EV-positive on the honest lane."
)
print(
    "//   NOTE: the WWXRP _RIG_ lane retains its averaged-table hero-placement drift"
)
print(
    "//   BY-DESIGN (USER don't-care ruling: 'worthless shitcoin'); only the honest"
)
print(
    "//   ETH/FLIP lane is split per (N, hero-is-gold) and made exactly EV-equal here."
)


# ===================================================================
# NUMERIC PRE-PROOF (INV-03 / ROADMAP success criterion 5) —
# P(S=9) and the WWXRP RTP curve are UNCHANGED vs HEAD under Variant-2 +
# the R2 rig, proven BEFORE any contract edit. We show, per N, the honest
# Variant-2 P_N(S=9), the rigged P_N(S=9), and the HEAD all-8-match
# probability (the old M=8 event) side by side and assert all three are
# EQUAL (Fraction-exact). Under Option B we ALSO recompute P(S=9) from each
# new honest sub-case distribution (hero gold AND hero common) and assert it
# equals the same value — proving S=9 is placement-independent (it depends
# only on the gold/common COUNT N, not which quadrant is the hero), so the
# honest split does NOT move P(S=9). The WWXRP_ROI_* RTP curve
# (70->115->118->120%) and the S=9 whale-pass bracket are NOT recomputed by
# this script — they live in the contract ROI machinery (INV-02 / INV-04),
# held fixed; since the rig leaves P(S=9) and its pinned payout intact
# (m>=7 cap), the realized WWXRP RTP curve is byte-identical to HEAD.
# ===================================================================
print("\n" + "=" * 70)
print("NUMERIC PRE-PROOF — P(S=9) + WWXRP RTP curve unchanged vs HEAD")
print("=" * 70)
print(f"// {'N':>3} | {'honest P(S=9)':>26} | {'rigged P(S=9)':>26} | {'HEAD all-8-match P':>26} | eq")
for N in range(5):
    honest_ps9 = P_N_TABLE[N][9]              # Variant-2 honest P(S=9) (averaged; placement-indep at 9)
    rigged_ps9 = P_N_RIG[N][9]                # R2-rigged P(S=9)
    head_m8 = _p_old(N)[8]                    # HEAD all-8-axes (old M=8) probability
    eq = (honest_ps9 == rigged_ps9 == head_m8)
    assert eq, (
        f"PRE-PROOF FAIL N={N}: honest {honest_ps9} / rigged {rigged_ps9} / HEAD {head_m8} differ"
    )
    # Option B: each new honest sub-case distribution must give the SAME P(S=9)
    # (S=9 is the all-8-axes event — placement-independent, only the COUNT N matters).
    for (NN, g), (dist, _payouts) in honest_tables.items():
        if NN == N:
            assert dist[9] == honest_ps9, (
                f"PRE-PROOF FAIL N={N} {_sub_label(NN, g)}: sub-case P(S=9) {dist[9]} "
                f"!= averaged P(S=9) {honest_ps9} — S=9 must be placement-independent"
            )
    print(
        f"// {N:>3} | {str(honest_ps9):>26} | {str(rigged_ps9):>26} | "
        f"{str(head_m8):>26} | {'OK' if eq else 'XX'}"
    )
print("// Option B sub-case check: every honest (N, hero-is-gold) sub-case P(S=9) ==")
print("//   the per-N value above (Fraction-exact) — the honest split does NOT move P(S=9).")
# WWXRP RTP curve: held fixed in the contract (not recomputed here). State + confirm.
print("// WWXRP_ROI_* RTP curve (70->115->118->120%) + the S=9 whale-pass bracket are")
print("//   NOT recomputed by this script — held fixed in the contract ROI machinery")
print("//   (INV-02 / INV-04). The R2 rig's m>=7 cap leaves P(S=9) and its pinned")
print("//   QUICK_PLAY_PAYOUT_N{N}_S9 payout intact, so the realized WWXRP RTP curve is")
print("//   byte-identical to HEAD.")
print("PRE-PROOF: P(S=9) and WWXRP RTP curve unchanged vs HEAD under Variant-2 + R2 rig")


# ===================================================================
# 453 IMPL DISPATCH SHAPE — _getBasePayoutBps(N, isWwxrp, heroIsGold).
# Printed (NOT applied) for the 453 contract paste. This is the ONLY dispatch
# change Option B requires: a heroIsGold selector consulted ONLY when !isWwxrp.
# No .sol is edited in Phase 452 — 453 IMPL is the sole approval gate.
# ===================================================================
print("\n" + "=" * 70)
print("453 IMPL DISPATCH SHAPE — _getBasePayoutBps(N, isWwxrp, heroIsGold)")
print("=" * 70)
print("// PRINTED FOR 453 PASTE — no .sol is edited in Phase 452.")
print("//")
print("// heroIsGold is a READ-ONLY fact derived in-contract from whether the player's")
print("// hero quadrant carries a GOLD color (an existing trait of the ticket; on the")
print("// quick-play / RNG paths it is fixed by the seed, not player-selectable). The")
print("// selector is consulted ONLY on the honest lane (!isWwxrp). On the WWXRP lane the")
print("// _RIG_ table is indexed by N only (heroIsGold ignored) — averaged by-design.")
print("// N0 (always hero-common) and N4 (always hero-gold) collapse to one table each,")
print("// so heroIsGold is only consulted for N in {1, 2, 3}.")
print("//")
print("// function _getBasePayoutBps(uint256 n, bool isWwxrp, bool heroIsGold)")
print("//     internal pure returns (uint256 packed, uint256 s8, uint256 s9) {")
print("//     s9 = QUICK_PLAY_PAYOUT_N{n}_S9;          // pin, by N only (P(S=9) placement-indep)")
print("//     if (isWwxrp) {                            // WWXRP rigged lane: by N only")
print("//         packed = QUICK_PLAY_PAYOUTS_RIG_N{n}_PACKED;")
print("//         s8     = QUICK_PLAY_PAYOUT_RIG_N{n}_S8;")
print("//         return (packed, s8, s9);             // heroIsGold IGNORED (averaged by-design)")
print("//     }")
print("//     // Honest ETH/FLIP lane: index by (n, heroIsGold), Option B exact EV-equality.")
print("//     if (n == 0) {                            // N0 always hero-common -> one table")
print("//         packed = QUICK_PLAY_PAYOUTS_N0_PACKED;          s8 = QUICK_PLAY_PAYOUT_N0_S8;")
print("//     } else if (n == 4) {                     // N4 always hero-gold  -> one table")
print("//         packed = QUICK_PLAY_PAYOUTS_N4_PACKED;          s8 = QUICK_PLAY_PAYOUT_N4_S8;")
print("//     } else if (heroIsGold) {                 // N in {1,2,3}, hero gold")
print("//         packed = QUICK_PLAY_PAYOUTS_N{n}_HEROGOLD_PACKED;   s8 = QUICK_PLAY_PAYOUT_N{n}_HEROGOLD_S8;")
print("//     } else {                                 // N in {1,2,3}, hero common")
print("//         packed = QUICK_PLAY_PAYOUTS_N{n}_HEROCOMMON_PACKED; s8 = QUICK_PLAY_PAYOUT_N{n}_HEROCOMMON_S8;")
print("//     }")
print("// }")
print("//")
print("// The same (n, isWwxrp, heroIsGold) selector applies to the ETH-bonus factor")
print("// dispatch (WWXRP_FACTORS_*): honest -> WWXRP_FACTORS_N{n}[_HEROGOLD|_HEROCOMMON]_PACKED")
print("// (N0/N4 collapse to WWXRP_FACTORS_N0/N4_PACKED); WWXRP -> WWXRP_FACTORS_RIG_N{n}_PACKED.")
print("DISPATCH-SHAPE: _getBasePayoutBps heroIsGold selector (honest lane only) printed for 453 IMPL")
