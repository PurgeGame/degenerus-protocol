"""
5-table EV-equal Degenerette payout derivation — 10-bucket S in {0..9} design.

DESIGN VARIANT (v48 HERO 2-point rescale)
------------------------------------------
The Degenerette hero quadrant's SYMBOL match now scores 2 points (was a separate
EV-neutral multiplier). The composite score is

    S = A + 2*H        (S in {0..9}, pay floor S >= 2)

where
    A = the ordinary-axis match count over the 7 ordinary axes
        = 4 color axes (one per quadrant, including the hero quadrant's color)
        + 3 non-hero symbol axes,
    H = 1 iff the hero quadrant's SYMBOL matches (Bernoulli 1/8).

The standalone hero multiplier (HERO_BOOST / HERO_PENALTY / HERO_SCALE) is GONE —
the hero is folded directly into S. S = 9 is the jackpot and is exactly the
all-7-ordinary-match + hero-symbol-match event, which is BYTE-FOR-BYTE the same
physical event (and the same odds) as the old M = 8 all-8-axes-match jackpot — so
the S = 9 payout is a RELABEL of the old M = 8 value (values unchanged, pinned).

Player ticket has N gold quadrants (N in {0, 1, 2, 3, 4}). Use one of 5 separate
payout tables, each calibrated so basePayoutEV = 100 centi-x against THAT N-value's
score distribution P_N(S). No runtime normalizer needed.

Per-axis Bernoulli match probabilities (producer: color [16,16,16,16,16,16,16,8]/120,
symbol uniform 1/8):
  color axis:  P(match) = 2/15  (common, w=16)   |  1/15  (gold, w=8)
  symbol axis: P(match) = 1/8   (uniform, all quadrants)

P_N(S) = convolution over:
  - N gold color axes (Bernoulli 1/15) + (4-N) common color axes (Bernoulli 2/15),
  - 3 non-hero symbol axes (Bernoulli 1/8, contributing 0 or 1),
  - 1 hero symbol axis (Bernoulli 1/8, contributing 0 or 2).

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

    DEC-02 Option A (EV-equality wrinkle): because color is gated behind symbol, the
    hero quadrant's gold-ness now shifts P_N(S). For a fixed N this returns ONE
    averaged distribution over hero placement — the hero quadrant is gold with prob
    n_gold/4 and common with prob (4-n_gold)/4 — matching the HEAD per-N convention
    consumed by P_N_TABLE / the S9_PIN loop. (Plan 02 reports the hero-gold vs
    hero-common worst-case drift; the m>=7-cap / S=9 invariant is unaffected because
    S=9 only depends on the gold/common COUNT, not which quadrant is the hero.)

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


tables = []
for N in range(5):
    PN = P_N_TABLE[N]
    # Fixed contribution of the pinned S = 9 tier.
    ev_fixed = Fraction(S9_PIN[N]) * PN[9]
    # Shape EV for the solvable S = 2..8 tiers.
    shape_ev_N = sum(Fraction(SHAPE[k]) * PN[k] for k in range(2, 9))
    scale = (Fraction(TARGET_EV) - ev_fixed) / shape_ev_N
    payouts = (
        [0, 0]
        + [round(Fraction(SHAPE[k]) * scale) for k in range(2, 9)]
        + [S9_PIN[N]]
    )
    # Residual-absorption refine (coarse S=4, fine S=5, ultra-fine S=6) to drive
    # |drift| well under 0.5 centi-x — same approach as the 9-bucket design.
    for adj in (4, 5, 6):
        residual = Fraction(TARGET_EV) - total_ev(payouts, PN)
        payouts[adj] += round(residual / PN[adj])
    # Neutral-or-just-under guarantee: the baseline basePayoutEV (before the
    # activity-score ROI scaling and the ETH/WWXRP bonus) must never exceed
    # TARGET_EV — the house is never EV-negative on the base table. If integer
    # rounding overshot above 100 centi-x, nudge the ultra-fine S=6 tier down by
    # the minimal amount that brings EV back to <= 100 (lands fractionally under).
    while total_ev(payouts, PN) > Fraction(TARGET_EV):
        payouts[6] -= 1
    tables.append((scale, payouts))

# --- Print the solved per-N payout tables ---
print(f"{'S':>3} | {'shape':>10} | " + " | ".join(f"N={n} payout".rjust(13) for n in range(5)))
print(f"{'':>3} | {'(relative)':>10} | " + " | ".join(f"  centi-x   ".rjust(13) for _ in range(5)))
print("-" * 105)
for S in range(10):
    shape_label = "PINNED(S9)" if S == 9 else (str(SHAPE[S]) if SHAPE[S] is not None else "-")
    cells = " | ".join(f"{tables[n][1][S]:>13,}" for n in range(5))
    print(f"{S:>3} | {shape_label:>10} | {cells}")
print()

print("Scale factors + per-N basePayoutEV:")
for N in range(5):
    ev = float(total_ev(tables[N][1], P_N_TABLE[N]))
    print(f"  N={N}:  ×{float(tables[N][0]):.6f}  → basePayoutEV = {ev:.5f} centi-x")
print()

# --- Top-bucket multipliers per table ---
print(f"Top-bucket multipliers per table (× the bet amount, at 100% ROI):")
print(f"{'N':>3} | {'S=5':>11} | {'S=6':>11} | {'S=7':>11} | {'S=8':>13} | {'S=9 jackpot':>15}")
for N in range(5):
    p = tables[N][1]
    print(
        f"{N:>3} | {p[5]/100:>10.2f}x | {p[6]/100:>10.2f}x | {p[7]/100:>10.2f}x | "
        f"{p[8]/100:>11,.2f}x | {p[9]/100:>13,.2f}x"
    )
print()

# --- Probability of any positive payout (S >= 2) per table ---
print(f"P(any payout, S >= 2) per table:")
for N in range(5):
    p_pay = sum(P_N_TABLE[N][k] for k in range(2, 10))
    print(f"  N={N}: {float(p_pay)*100:.4f}%   (1 in {1/float(p_pay):.2f} tickets)")
print()

# -------------------------------------------------------------------------
# WWXRP factor tables (per-N, B = 6..9, the rescaled floor).
# 10/30/30/30 split across B = 6/7/8/9; total ETH bonus EV = 5.000% per N.
# -------------------------------------------------------------------------
WWXRP_SCALE = 1_000_000
SPLITS = {6: Fraction(10, 100), 7: Fraction(30, 100), 8: Fraction(30, 100), 9: Fraction(30, 100)}
ETH_BONUS_BPS = 500


def wwxrp_factors(N):
    payouts = tables[N][1]
    factors = {}
    for B in (6, 7, 8, 9):
        f = SPLITS[B] * 100 * WWXRP_SCALE / (P_N_TABLE[N][B] * payouts[B])
        factors[B] = round(float(f))
    return factors


print(f"WWXRP_BONUS_FACTOR (per-N) at 10/30/30/30 split over B=6..9, ETH_BONUS_BPS=500:")
print(f"{'N':>3} | " + " | ".join(f"BUCKET{B} factor".rjust(20) for B in (6, 7, 8, 9)))
print("-" * 100)
for N in range(5):
    factors = wwxrp_factors(N)
    cells = " | ".join(f"{factors[B]:>20,}" for B in (6, 7, 8, 9))
    print(f"{N:>3} | {cells}")
    for B in (6, 7, 8, 9):
        assert factors[B] < (1 << 64), f"WWXRP factor N={N} B={B} exceeds 64 bits"
print()

# ===================================================================
# FINAL PASTE-READY CONSTANTS — 10-bucket S in {0..9} design.
# The hero is scored into S; the standalone hero multiplier is GONE
# (no HERO_BOOST / HERO_PENALTY / HERO_SCALE). S = 9 is the M = 8 relabel.
# The PASS_ALL byte-reproduce gate parses this section and diffs vs the
# contract source — constants are NEVER hand-typed.
# ===================================================================

print("=" * 70)
print("FINAL PASTE-READY CONSTANTS")
print("=" * 70)

# Payouts (per-N base table S = 0..7 packed; S = 8 + S = 9 separate uint256s).
print("\n// Payout tables (per-N): basePayoutEV = 100 centi-x ± rounding")
for N in range(5):
    p = tables[N][1]
    packed = 0
    for S in range(8):
        packed |= (p[S] & 0xFFFFFFFF) << (S * 32)
    actual_ev = float(total_ev(p, P_N_TABLE[N]))
    print(
        f"uint256 private constant QUICK_PLAY_PAYOUTS_N{N}_PACKED = 0x{packed:064x};  // EV={actual_ev:.4f}"
    )
print()
for N in range(5):
    p_S8 = tables[N][1][8]
    print(
        f"uint256 private constant QUICK_PLAY_PAYOUT_N{N}_S8 = {p_S8:>11};  // {p_S8/100:>12,.2f}x bet"
    )
print()
for N in range(5):
    p_S9 = tables[N][1][9]
    print(
        f"uint256 private constant QUICK_PLAY_PAYOUT_N{N}_S9 = {p_S9:>11};  // {p_S9/100:>12,.2f}x bet"
    )

# WWXRP factors (per-N, B = 6..9 packed; B = 6 in the low 64 bits).
print("\n// WWXRP factors (per-N) at 10/30/30/30 split over B=6..9, basePayoutEV=100, ETH_BONUS_BPS=500")
for N in range(5):
    factors = wwxrp_factors(N)
    packed = 0
    for i, B in enumerate((6, 7, 8, 9)):
        packed |= (factors[B] & ((1 << 64) - 1)) << (i * 64)
    print(f"uint256 private constant WWXRP_FACTORS_N{N}_PACKED = 0x{packed:064x};")

# Per-pick EV verification
print("\n// Per-pick basePayoutEV verification (centi-x):")
print(f"// {'N':>3} | basePayoutEV | drift from 100")
for N in range(5):
    ev_frac = total_ev(tables[N][1], P_N_TABLE[N])
    ev = float(ev_frac)
    drift_bps = (ev - 100) * 100
    # Baseline must be neutral-or-just-under: <= 100 centi-x (never EV-positive)
    # and within 0.5 centi-x of neutral (so it is ~100%, not a slack house edge).
    assert ev_frac <= Fraction(TARGET_EV), (
        f"N={N} basePayoutEV {ev} exceeds 100 centi-x — baseline must be neutral or just under"
    )
    assert ev_frac > Fraction(TARGET_EV) - 1, (
        f"N={N} basePayoutEV {ev} drifts more than 0.5 centi-x below neutral"
    )
    print(f"// {N:>3} |  {ev:>9.5f}   |  {drift_bps:+.4f} bps")

# ETH-bonus EV verification
print("\n// ETH-bonus EV verification (target = 5.0000%):")
for N in range(5):
    payouts = tables[N][1]
    factors = wwxrp_factors(N)
    total_bonus = sum(
        P_N_TABLE[N][B] * payouts[B] / 100 *
        (ETH_BONUS_BPS * Fraction(factors[B], WWXRP_SCALE)) / 10000
        for B in (6, 7, 8, 9)
    )
    drift_bps = (float(total_bonus) - 0.05) * 10000
    assert abs(float(total_bonus) - 0.05) < 0.05 * 0.01, (
        f"N={N} ETH bonus EV {float(total_bonus)} outside ±1% of 5%"
    )
    print(f"//   N={N}: bonus EV = {float(total_bonus)*100:.6f}%   drift {drift_bps:+.4f} bps")

# Total ticket EV at MAX activity for ETH player
print("\n// Total ETH player RTP @ MAX activity (9990 bps + 5% bonus):")
for N in range(5):
    base_ev = float(total_ev(tables[N][1], P_N_TABLE[N])) / 100
    base_rtp = base_ev * 0.999
    bonus = 0.05
    total = base_rtp + bonus
    print(f"//   N={N}: total RTP = {total*100:.4f}%")


# ===================================================================
# WWXRP RIG FAMILY — variant-B rig (ordinary-only +1, 60%, M<=6 gate).
# WWXRP spins force one unmatched ORDINARY cell to a real match w.p.
# 3/5 when M<=6 (never the hero; caps at M=7 so P(S=9) is INVARIANT).
# WWXRP gets its OWN per-N base tables (EV=100 centi-x under the RIGGED
# dist, EV-equality across picks preserved) + its OWN factors. S=9 reuses
# the honest QUICK_PLAY_PAYOUT_N{N}_S9 pin (P(S=9) unchanged by the rig).
# ETH/FLIP keep the honest tables above. Names carry a _RIG_ infix.
# The byte-reproduce gate parses these from the SAME FINAL block.
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
        (a) an unmatched NON-HERO symbol cell  -> forcing it scores +1;
        (b) an unmatched COLOR on a quadrant whose symbol ALREADY matched
            (sm==1, cm==0; the color "unlocks" -> +1; includes the hero quadrant's
             COLOR, which is an ordinary axis — only the hero SYMBOL is excluded).
    EXCLUDED from the pool: the hero symbol cell (never rigged) and *no-op* colors
    (a color on a quadrant whose symbol is still unmatched buys nothing under
    Variant-2). Whichever eligible cell the rig picks, the modeled lift is exactly +1.

    Explicit EMPTY-ELIGIBLE-POOL case: when M <= 6 but every unmatched cell is an
    excluded one (the hero symbol and/or no-op colors), the score-bearing pool is
    empty (e == 0) -> NO lift that round; the mass stays at baseS even though the
    3/5 gate would otherwise fire.

    DEC-02 Option A (same as the honest dist): the per-N rigged distribution is
    averaged over hero placement (hero gold w.p. n_gold/4, common w.p. (4-n_gold)/4).
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
        partials = {(0, 0, 0): weight}
        for states, is_hero in quads:
            nxt = {}
            for (S, M, e), pacc in partials.items():
                for sm, cm, pp in states:
                    dS = 0
                    if sm == 1:
                        dS += 2 if is_hero else 1
                        if cm == 1:
                            dS += 1
                    dM = sm + cm
                    de = 0
                    if (not is_hero) and sm == 0:
                        de += 1  # (a) unmatched non-hero symbol
                    if sm == 1 and cm == 0:
                        de += 1  # (b) unmatched color on a symbol-matched quadrant
                    key = (S + dS, M + dM, e + de)
                    nxt[key] = nxt.get(key, Fraction(0)) + pacc * pp
            partials = nxt
        # Apply the rig per full-roll outcome.
        for (S, M, e), p in partials.items():
            if M >= 7:
                out[S] += p  # m>=7 cap: untouched -> P(S=9) invariant
            elif e == 0:
                out[S] += p  # empty eligible pool: no lift this round
            else:
                out[S] += p * (1 - pf)
                out[S + 1] += p * pf
    assert sum(out) == 1, f"rigged P_N(S) N={n_gold} != 1"
    assert len(out) == 10
    return out


# Rigged distribution per N + S=9 invariance vs honest.
P_N_RIG = []
for N in range(5):
    rig = p_score_distribution_rigged(N)
    assert rig[9] == P_N_TABLE[N][9], f"rig must not change P(S=9) for N={N}"
    P_N_RIG.append(rig)


def _solve_table(pS, N):
    """Identical SHAPE+S9-pin solve as the honest tables, against pS."""
    ev_fixed = Fraction(S9_PIN[N]) * pS[9]
    shape_ev_N = sum(Fraction(SHAPE[k]) * pS[k] for k in range(2, 9))
    scale = (Fraction(TARGET_EV) - ev_fixed) / shape_ev_N
    payouts = (
        [0, 0]
        + [round(Fraction(SHAPE[k]) * scale) for k in range(2, 9)]
        + [S9_PIN[N]]
    )
    for adj in (4, 5, 6):
        residual = Fraction(TARGET_EV) - total_ev(payouts, pS)
        payouts[adj] += round(residual / pS[adj])
    while total_ev(payouts, pS) > Fraction(TARGET_EV):
        payouts[6] -= 1
    return payouts


tables_rig = [_solve_table(P_N_RIG[N], N) for N in range(5)]


def wwxrp_factors_rig(N):
    payouts = tables_rig[N]
    factors = {}
    for B in (6, 7, 8, 9):
        f = SPLITS[B] * 100 * WWXRP_SCALE / (P_N_RIG[N][B] * payouts[B])
        factors[B] = round(float(f))
    return factors


print("\n" + "=" * 70)
print("WWXRP RIG FAMILY — FINAL PASTE-READY CONSTANTS (variant B)")
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
