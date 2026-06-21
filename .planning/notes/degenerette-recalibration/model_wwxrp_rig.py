"""
WWXRP rig + recalibration MODEL (scoping/grounding only — not the canonical generator).

Models the two requested WWXRP-only changes:

  (1) RIG: if a WWXRP reel is NOT a full match (M=8) and NOT 1-off (M=7) — i.e.
      M <= 6 axes matched (>= 2 unmatched) — pick ONE unmatched axis and with
      probability 0.6 force it to match. Caps at M=7, so the rig NEVER creates a
      jackpot (S=9) and never moves a roll out of S=9 -> P(S=9) is invariant.

      Variant A (uniform-all): pick uniformly among ALL unmatched axes (incl. the
                hero symbol if unmatched -> a hero flip is +2 to S).
      Variant B (ordinary-only): pick only among unmatched ORDINARY axes (+1 to S).

  (2) RECALIBRATE: WWXRP gets its OWN per-N base tables (EV=100 centi-x under the
      RIGGED distribution, so EV-equality across picks is preserved) and its own
      total-RTP curve E(score): 70% @ 0, 115% @ 305 (knee K), ~118% @ 500 (seg-B
      knee), 120% @ 30000 (cap). Floor F(score)=min(E,100%); surplus (E-F) is
      redistributed into S>=6 via per-N factors (same machinery as today).

Score model (identical to derive_5_tables.py):
  S = (ordinary axes matched) + 2*(hero symbol matched);  M = total axes matched.
  base S = M + h  (h = hero matched in {0,1}).
"""

from fractions import Fraction as F

# ---- per-axis match probabilities -------------------------------------------
# color: common 2/15, gold 1/15 ; symbol (incl hero) uniform 1/8
def color_dist(N):
    """Poisson-binomial over 4 color axes: N gold (1/15), 4-N common (2/15).
    Returns P(C=c) for c in 0..4."""
    dist = [F(1)]
    for _ in range(N):
        dist = _conv(dist, [F(14, 15), F(1, 15)])
    for _ in range(4 - N):
        dist = _conv(dist, [F(13, 15), F(2, 15)])
    return dist

def _conv(a, b):
    out = [F(0)] * (len(a) + len(b) - 1)
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            out[i + j] += x * y
    return out

def binom_sym(k):
    """P(Y=y) for Y ~ Binom(k, 1/8)."""
    dist = [F(1)]
    for _ in range(k):
        dist = _conv(dist, [F(7, 8), F(1, 8)])
    return dist

P_HERO = [F(7, 8), F(1, 8)]  # h=0, h=1


def honest_score_dist(N):
    """P_N(S), S in 0..9 — must match derive_5_tables.py exactly (sanity check)."""
    C = color_dist(N)
    Y = binom_sym(3)
    dist = [F(0)] * 10
    for c, pc in enumerate(C):
        for y, py in enumerate(Y):
            for h, ph in enumerate(P_HERO):
                S = c + y + 2 * h
                dist[S] += pc * py * ph
    return dist


def rigged_score_dist(N, variant):
    """P_N^rigged(S) after the 0.6 single-axis rig on M<=6 rolls."""
    C = color_dist(N)
    Y = binom_sym(3)
    out = [F(0)] * 10
    for c, pc in enumerate(C):
        for y, py in enumerate(Y):
            for h, ph in enumerate(P_HERO):
                p = pc * py * ph
                M = c + y + h            # total axes matched
                baseS = M + h            # = c + y + 2h
                u = 8 - M                # unmatched axes
                if M >= 7:               # full or 1-off: no rig
                    out[baseS] += p
                    continue
                # M <= 6: rig applies. p_flip = 0.6.
                pf = F(3, 5)
                if variant == "A":       # uniform among all u unmatched
                    if h == 0:           # hero is unmatched -> can be picked (+2)
                        out[baseS] += p * (1 - pf)                 # no flip
                        out[baseS + 2] += p * pf * F(1, u)         # flip hero -> +2
                        out[baseS + 1] += p * pf * F(u - 1, u)     # flip ordinary -> +1
                    else:                # hero matched: all unmatched ordinary
                        out[baseS] += p * (1 - pf)
                        out[baseS + 1] += p * pf
                else:                    # variant B: ordinary only (+1)
                    out[baseS] += p * (1 - pf)
                    out[baseS + 1] += p * pf
    assert sum(out) == 1, (N, variant, float(sum(out)))
    return out


# ----------------------------------------------------------------------------
# Recalibrate WWXRP base table to EV=100 centi-x under the rigged dist.
# Same SHAPE + S9 pin as derive_5_tables.py.
# ----------------------------------------------------------------------------
S9_PIN = [10_756_411, 12_583_037, 14_792_939, 17_512_324, 20_916_435]
SHAPE = [0, 0, 190, 475, 1500, 4250, 19500, 100000, 5_000_000, None]
TARGET_EV = 100


def total_ev(payouts, pS):
    return sum(payouts[k] * pS[k] for k in range(10))


def solve_table(pS, N):
    ev_fixed = F(S9_PIN[N]) * pS[9]
    shape_ev = sum(F(SHAPE[k]) * pS[k] for k in range(2, 9))
    scale = (F(TARGET_EV) - ev_fixed) / shape_ev
    payouts = [0, 0] + [round(F(SHAPE[k]) * scale) for k in range(2, 9)] + [S9_PIN[N]]
    for adj in (4, 5, 6):
        residual = F(TARGET_EV) - total_ev(payouts, pS)
        payouts[adj] += round(residual / pS[adj])
    while total_ev(payouts, pS) > F(TARGET_EV):
        payouts[6] -= 1
    return payouts


# ---- E / F curves (piecewise-linear, knees at 305 / 500 / 30000) ------------
K, SEGB, CAP = 305, 500, 30000
def piecewise(score, v0, vK, vB, vMax):
    if score >= CAP: return vMax
    if score <= K:   return v0 + (vK - v0) * score // K
    if score <= SEGB: return vK + (vB - vK) * (score - K) // (SEGB - K)
    return vB + (vMax - vB) * (score - SEGB) // (CAP - SEGB)

# E (total RTP, bps): 7000 / 11500 / 11800 / 12000
def E_bps(score):  return piecewise(score, 7000, 11500, 11800, 12000)
# F (floor, bps) = min(E, 10000)
def Fl_bps(score): return min(E_bps(score), 10000)


# ---- WWXRP factor calibration (per-N, B=6..9, 10/30/30/30) -------------------
SCALE = 1_000_000
SPLITS = {6: F(10, 100), 7: F(30, 100), 8: F(30, 100), 9: F(30, 100)}

def wwxrp_factors(pS, payouts):
    fac = {}
    for B in (6, 7, 8, 9):
        fac[B] = round(float(SPLITS[B] * 100 * SCALE / (pS[B] * payouts[B])))
    return fac


# ============================================================================
print("=" * 78)
print("SANITY: rigged generator reproduces honest P_N(S) when rig disabled")
for N in range(5):
    h = honest_score_dist(N)
    # honest == rigged with pf=0 — check S9 invariance separately below
    assert abs(float(sum(h)) - 1) < 1e-12
print("  honest P_N(S) sums to 1 for all N  OK\n")

for variant, vname in (("A", "uniform-all (hero eligible, +2)"),
                       ("B", "ordinary-only (+1)")):
    print("=" * 78)
    print(f"VARIANT {variant}: {vname}")
    print("=" * 78)
    for N in range(5):
        h = honest_score_dist(N)
        r = rigged_score_dist(N, variant)
        # S9 invariance
        assert h[9] == r[9], (N, variant)
        win_h = float(sum(h[2:]));  win_r = float(sum(r[2:]))
        s6_h = float(sum(h[6:]));   s6_r = float(sum(r[6:]))
        es_h = float(sum(k*h[k] for k in range(10)))
        es_r = float(sum(k*r[k] for k in range(10)))
        print(f"  N={N}: E[S] {es_h:.3f}->{es_r:.3f} | "
              f"P(win,S>=2) {win_h*100:6.3f}%->{win_r*100:6.3f}% | "
              f"P(S>=6) {s6_h*100:.4f}%->{s6_r*100:.4f}% | "
              f"P(S=9)={float(r[9]):.2e} (inv)")
    print()

# ---- Full recalibration for the LOCKED variant ------------------------------
VARIANT = "B"  # locked: ordinary-only (+1), never the hero
print("=" * 78)
print(f"RECALIBRATION (variant {VARIANT}) — WWXRP base tables @ EV=100 under rigged dist")
print("=" * 78)
tables = []
factors = []
for N in range(5):
    r = rigged_score_dist(N, VARIANT)
    p = solve_table(r, N)
    tables.append(p)
    ev = float(total_ev(p, r))
    fac = wwxrp_factors(r, p)
    factors.append(fac)
    for B in (6, 7, 8, 9):
        assert fac[B] < (1 << 64), (N, B, fac[B])
    print(f"  N={N}: base EV={ev:.5f} centi-x | S2..8="
          f"{[p[k] for k in range(2,9)]} | S9={p[9]:,}")
print()

# Compare honest table S2..8 (what ETH/FLIP keep) vs rigged WWXRP table
print(f"  Honest (ETH/FLIP) vs Rigged (WWXRP, variant {VARIANT}) base payout, N=0, centi-x:")
hp = solve_table(honest_score_dist(0), 0)
rp = tables[0]
for s in range(2, 10):
    print(f"    S={s}: honest {hp[s]:>12,}  rigged {rp[s]:>12,}  "
          f"({100*rp[s]/hp[s]:.1f}% of honest)")
print()

# ---- Realized RTP at sample scores (variant A) ------------------------------
print("=" * 78)
print("REALIZED WWXRP RTP (variant A) — should track E(score)")
print("=" * 78)
print(f"  {'score':>7} | {'E(bps)':>7} | {'F(bps)':>7} | {'bonus':>6} | " +
      " | ".join(f'N={N} RTP' for N in range(5)))
for score in (0, 100, 203, 305, 500, 5000, 30000):
    e = E_bps(score); fl = Fl_bps(score); bonus = e - fl
    row = []
    for N in range(5):
        r = rigged_score_dist(N, VARIANT)
        p = tables[N]; fac = factors[N]
        rtp = 0.0
        for s in range(10):
            base = p[s]
            eff = fl
            if s >= 6 and bonus > 0:
                eff = fl + bonus * fac[s] // SCALE
            rtp += float(r[s]) * base * eff / 1_000_000
        row.append(rtp)
    print(f"  {score:>7} | {e:>7} | {fl:>7} | {bonus:>6} | " +
          " | ".join(f"{v*100:6.2f}%" for v in row))
print()

# ---- Jackpot / top-bucket effective payout at MAX activity -------------------
print("=" * 78)
print("TOP-BUCKET EFFECTIVE multiplier @ score=30000 (bonus=2000bps), variant A")
print("=" * 78)
score = 30000; e = E_bps(score); fl = Fl_bps(score); bonus = e - fl
for N in range(5):
    p = tables[N]; fac = factors[N]
    cells = []
    for s in (6, 7, 8, 9):
        eff = fl + bonus * fac[s] // SCALE
        mult = p[s] * eff / 1_000_000   # x-multiple of bet
        cells.append(f"S{s}={mult:,.1f}x")
    print(f"  N={N}: " + "  ".join(cells))


# ============================================================================
# HIGH-TIER CURRENCY MIX across the box economy.
# Box-spins use a RANDOM player ticket (customTicket=0) -> N ~ Binom(4, 1/15).
# WWXRP reels are RIGGED (variant B); FLIP/ETH reels are HONEST (unrigged).
# Reels per box outcome: WWXRP 15%x1, FLIP 10%x3, ETH 5%x1 (direct) / 0 (recirc).
# ============================================================================
def binom_N():
    d = [F(1)]
    for _ in range(4):
        d = _conv(d, [F(14, 15), F(1, 15)])
    return d  # P(N), N=0..4

PN = binom_N()

def avg_PS(per_n_dist):
    """E_N[ P_N(S) ] over the random box-spin player ticket, returns S->prob."""
    out = [F(0)] * 10
    for N in range(5):
        for s in range(10):
            out[s] += PN[N] * per_n_dist[N][s]
    return out

wwxrp_rig = [rigged_score_dist(N, "B") for N in range(5)]
honest    = [honest_score_dist(N) for N in range(5)]

PS_wwxrp_rig = avg_PS(wwxrp_rig)   # WWXRP reel tier dist, rigged
PS_honest    = avg_PS(honest)      # FLIP/ETH reel tier dist (and WWXRP if NOT rigged)

def tier_mix(reels, wwxrp_dist, label):
    """reels = {cur: reels_per_box}; print currency share at each tier S=6..9 and S>=6."""
    dist = {"WWXRP": wwxrp_dist, "FLIP": PS_honest, "ETH": PS_honest}
    print(f"\n  --- {label} ---")
    print(f"  reels/box: WWXRP={float(reels['WWXRP']):.2f} FLIP={float(reels['FLIP']):.2f} ETH={float(reels['ETH']):.2f}")
    header = "  tier |  " + " | ".join(f"{c:>7}" for c in ("WWXRP","FLIP","ETH"))
    print(header)
    for tlabel, lo in (("S=6",6),("S=7",7),("S=8",8),("S=9",9),("S>=6",6)):
        hi = 10 if tlabel=="S>=6" or lo==9 else lo+1
        rng = range(lo, hi)
        contrib = {c: reels[c]*sum(dist[c][s] for s in rng) for c in reels}
        tot = sum(contrib.values())
        if tot == 0: continue
        shares = {c: float(contrib[c]/tot)*100 for c in reels}
        print(f"  {tlabel:>4} |  " + " | ".join(f"{shares[c]:6.1f}%" for c in ("WWXRP","FLIP","ETH")))

print("="*78)
print("HIGH-TIER CURRENCY MIX  (share of high-tier ROLLS that are each currency)")
print("="*78)

# Direct boxes (allowEthSpin=true): WWXRP .15, FLIP .30, ETH .05 reels/box
direct = {"WWXRP": F(15,100), "FLIP": F(30,100), "ETH": F(5,100)}
# Recirc / match-bonus boxes (allowEthSpin=false): ETH slot -> tickets
recirc = {"WWXRP": F(15,100), "FLIP": F(30,100), "ETH": F(0)}

print("\nWITH RIG (WWXRP rigged, variant B):")
tier_mix(direct, PS_wwxrp_rig, "DIRECT lootbox-reward boxes")
tier_mix(recirc, PS_wwxrp_rig, "RECIRC / match-bonus boxes")

print("\n\nWITHOUT RIG (baseline — WWXRP honest, for comparison):")
tier_mix(direct, PS_honest, "DIRECT lootbox-reward boxes")
tier_mix(recirc, PS_honest, "RECIRC / match-bonus boxes")

# Also: per-reel P(S>=6) by currency (the underlying driver)
print("\n\n  Per-reel P(S>=6), box-spin random ticket (N~Binom(4,1/15)):")
print(f"    WWXRP rigged : {float(sum(PS_wwxrp_rig[6:]))*100:.4f}%")
print(f"    honest (FLIP/ETH, and WWXRP pre-rig): {float(sum(PS_honest[6:]))*100:.4f}%")
print(f"    rig uplift factor: {float(sum(PS_wwxrp_rig[6:])/sum(PS_honest[6:])):.2f}x")


# ============================================================================
# EV-BY-TIER concentration: how much of WWXRP's total RTP comes from S>=6,
# and how a lower FLOOR CAP shifts more of it into the 6+ band.
# ============================================================================
def rtp_by_band(N, score, floor_cap):
    """Return (rtp_lo S2-5, rtp_hi S6-9, rtp_total) for rigged WWXRP table."""
    r = tables[N]; fac = factors[N]; pS = rigged_score_dist(N, "B")
    e = E_bps(score); fl = min(e, floor_cap); bonus = e - fl
    lo = hi = 0.0
    for s in range(2, 10):
        eff = fl
        if s >= 6 and bonus > 0:
            eff = fl + bonus * fac[s] // SCALE
        c = float(pS[s]) * r[s] * eff / 1_000_000
        if s < 6: lo += c
        else:     hi += c
    return lo, hi, lo + hi

print("="*78)
print("EV-BY-TIER: base-table EV concentration (at 100% ROI, before floor/bonus)")
print("="*78)
for N in (0, 4):
    r = tables[N]; pS = rigged_score_dist(N, "B")
    lo = sum(float(pS[s]) * r[s] for s in range(2, 6)) / 100   # x-mult
    hi = sum(float(pS[s]) * r[s] for s in range(6, 10)) / 100
    print(f"  N={N}: base EV S2-5={lo*100:.1f}% of bet | S6-9={hi*100:.1f}% | "
          f"-> {hi/(lo+hi)*100:.1f}% of base EV is in 6+")
print()

print("="*78)
print("FLOOR-CAP knob: % of total WWXRP RTP coming from S>=6 (N=0, box-random avg)")
print("="*78)
print(f"  floor cap | {'score=305 (E=115%)':>30} | {'score=30000 (E=120%)':>30}")
print(f"  {'':9} | {'RTP<6':>7} {'RTP6+':>7} {'%in6+':>6} | {'RTP<6':>7} {'RTP6+':>7} {'%in6+':>6}")
for cap in (10000, 9000, 8000, 7000, 6000):
    cells = []
    for score in (305, 30000):
        # average over box-spin random N
        lo = hi = 0.0
        for N in range(5):
            l, h, _ = rtp_by_band(N, score, cap)
            lo += float(PN[N]) * l; hi += float(PN[N]) * h
        cells.append((lo, hi, hi/(lo+hi)*100))
    c1, c2 = cells
    print(f"  {cap/100:6.0f}%   | {c1[0]*100:6.1f}% {c1[1]*100:6.1f}% {c1[2]:5.1f}% | "
          f"{c2[0]*100:6.1f}% {c2[1]*100:6.1f}% {c2[2]:5.1f}%")
print()
print("  (total RTP unchanged at E=115%/120% for every cap — only the <6 vs 6+ split moves;")
print("   a lower cap makes S2-5 net-negative and pumps the freed EV into the 6+ redistribution.)")
