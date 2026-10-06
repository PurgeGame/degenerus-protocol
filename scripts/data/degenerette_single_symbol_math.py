"""Exact production model: one-symbol Degenerette with wild colors.

Run from any directory with Python 3. No dependencies; no contracts are modified.
All probability and payout calculations use exact rational arithmetic, and every
constant is checked against the literals compiled into the Degenerette module.

Rules: the hero lane's player color is wild; each house lane is wild with
probability 1/16, otherwise a uniform ordinary color. A symbol match scores 1; a
color scores 1 for equal ordinary colors or one wild, 2 for two wilds. Payouts
multiply by 1 + W/4 for W house wilds. ETH adds flat S6..S9 additions.

WWXRP rig: with probability 1/20, when S >= 3 and matched axes M <= 6 (M = S minus
the hero lane's house wild), copy one uniformly selected missed non-hero symbol or
missed non-wild color into the house lane. Enumerate both no rig and always-help;
the rig is their 19/20 : 1/20 mixture.
"""

from collections import defaultdict
from fractions import Fraction as F
from itertools import product
from math import lcm
from pathlib import Path
import json
import re


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "contracts/modules/DegenerusGameDegeneretteModule.sol"
WILD_RATE = F(1, 16)
BASE_CENTIX = [0, 0, 0, 50, 300, 1000, 10000, 62500, 1817328, 23000000]
ETH_ADD_CENTIX = [0, 0, 0, 0, 0, 0, 240, 4600, 105000, 22408400]
WWXRP_CENTIX = BASE_CENTIX[:8] + [480677, 100000000]
WWXRP_RIG_RATE = F(1, 20)
WWXRP_CURVE_BPS = [(0, 7000), (305, 12400), (500, 12760), (30000, 13000)]
ORDINARY_CURVE_BPS = [(0, 9000), (305, 9891), (500, 9970), (30000, 9990)]
BONUS_SHARES = {6: F(1, 10), 7: F(3, 10), 8: F(3, 10), 9: F(3, 10)}
MAX_BOON = F(28, 25)

# Side rewards: normalized to the previous gold-rule game's expected value.
OLD_BASE_CENTIX = [0, 0, 50, 300, 1000, 2500, 12500, 62500, 2035457, 25025025]
OLD_ETH_FACTORS = {6: 1013556, 7: 7134497, 8: 4558054, 9: 17877801}
OLD_DGNRS_BPS = {7: 400, 8: 800, 9: 1500}
OLD_AFFILIATE_BPS = 700


def convolve(a, b):
    out = defaultdict(F)
    for (s, w), p in a.items():
        for (t, v), q in b.items():
            out[s + t, w + v] += p * q
    return dict(out)


def convolution_joint():
    """Per-lane generating functions: (score, house wilds)."""
    joint = {(1, 0): 1 - WILD_RATE, (2, 1): WILD_RATE}  # hero color: wild vs ordinary/wild
    for _ in range(4):  # symbols
        joint = convolve(joint, {(0, 0): F(7, 8), (1, 0): F(1, 8)})
    for _ in range(3):  # non-hero colors
        joint = convolve(joint, {(0, 0): (1 - WILD_RATE) * F(7, 8),
                                 (1, 0): (1 - WILD_RATE) / 8, (1, 1): WILD_RATE})
    return joint


def lane_score(sym_hits, house_wild, color_eq):
    """Score and wilds for explicit lane states; lane 0 is the hero lane."""
    score = sum(sym_hits) + (2 if house_wild[0] else 1)
    for q in range(1, 4):
        score += 1 if house_wild[q] or color_eq[q] else 0
    return score, sum(house_wild)


def enumeration_joint():
    """Explicit lane states, plain and always-helped, with the help applied axis by axis."""
    plain, helped = defaultdict(F), defaultdict(F)
    for sym_mask, wild_mask, color_mask in product(range(16), range(16), range(8)):
        sym = [bool(sym_mask >> q & 1) for q in range(4)]
        wild = [bool(wild_mask >> q & 1) for q in range(4)]
        eq = [False] + [bool(color_mask >> (q - 1) & 1) for q in range(1, 4)]
        p = (F(1, 8) ** sum(sym) * F(7, 8) ** (4 - sum(sym))
             * WILD_RATE ** sum(wild) * (1 - WILD_RATE) ** (4 - sum(wild))
             * F(1, 8) ** sum(eq) * F(7, 8) ** (3 - sum(eq)))
        score, wilds = lane_score(sym, wild, eq)
        plain[score, wilds] += p
        matches = score - wild[0]
        axes = [("sym", q) for q in range(1, 4) if not sym[q]]
        axes += [("color", q) for q in range(1, 4) if not wild[q] and not eq[q]]
        if score < 3 or matches > 6:
            helped[score, wilds] += p
            continue
        assert axes, "an eligible axis always exists"
        for kind, q in axes:
            s2, e2 = sym[:], eq[:]
            if kind == "sym":
                s2[q] = True
            else:
                e2[q] = True
            new_score, new_wilds = lane_score(s2, wild, e2)
            assert new_score == score + 1 and new_wilds == wilds
            helped[new_score, new_wilds] += p / len(axes)
    return dict(plain), dict(helped)


def old_joint():
    """Previous rules: hero symbol +2, other symbols +1, each color +1, gold = player color 7."""
    joint = {(0, 0): F(1)}
    for q in range(4):
        joint = convolve(joint, {(0, 0): F(7, 8), (2 if q == 0 else 1, 0): F(1, 8)})
        joint = convolve(joint, {(0, 0): F(7, 8), (1, 0): F(7, 64), (1, 1): F(1, 64)})
    return joint


def weights(joint):
    w = [F(0)] * 10
    for (s, k), p in joint.items():
        w[s] += p * (1 + F(k, 4))
    return w


def probabilities(joint):
    out = [F(0)] * 10
    for (s, _), p in joint.items():
        out[s] += p
    return out


def curve_bps(curve, activity):
    for (lo, a), (hi, b) in zip(curve, curve[1:]):
        if activity <= hi:
            return a + (activity - lo) * (b - a) // (hi - lo)
    return curve[-1][1]


def eth_payout(s, w, roi_bps):
    return (F(BASE_CENTIX[s], 100) * F(roi_bps, 10_000) + F(ETH_ADD_CENTIX[s], 100)) * F(4 + w, 4)


def old_eth_payout(s, g, roi_bps):
    scaled = F(roi_bps) * 1_000_000 + (500 * OLD_ETH_FACTORS[s] if s >= 6 else 0)
    return F(OLD_BASE_CENTIX[s], 100) * F(4 + g, 4) * scaled / 10**10


def box_share(x):
    """_distributePayout with a nonbinding cash cap: lootbox part of a gross multiple."""
    return F(0) if x <= 3 else x - max(F(5, 2), x / 4)


def source_constants():
    return {name: int(value.replace("_", ""), 0) for name, value in re.findall(
        r"uint(?:8|16|256)\s+private\s+constant\s+([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F_]+|[0-9_]+);",
        SOURCE.read_text())}


def verify_contract(c, ww_floor, ww_factors, dgnrs_bps, affiliate_bps):
    """Bind the exact model to the literals actually compiled into production."""
    lanes = lambda word, n, bits: [(word >> (bits * i)) & ((1 << bits) - 1) for i in range(n)]
    assert [0, 0, 0] + lanes(c["BASE_CENTIX_PACKED"], 7, 32) == BASE_CENTIX
    assert c["BASE_CENTIX_PACKED"] >> (7 * 32) == 0
    assert [0] * 6 + lanes(c["ETH_ADD_CENTIX_PACKED"], 4, 32) == ETH_ADD_CENTIX
    assert c["ETH_ADD_CENTIX_PACKED"] >> (4 * 32) == 0
    assert [c["WWXRP_PAYOUT_S8"], c["WWXRP_PAYOUT_S9"]] == WWXRP_CENTIX[8:]
    assert c["WWXRP_RIG_DENOMINATOR"] == WWXRP_RIG_RATE.denominator
    assert c["WWXRP_FLOOR_SCALED"] == ww_floor
    assert lanes(c["WWXRP_BONUS_FACTORS_PACKED"], 4, 64) == [ww_factors[s] for s in range(6, 10)]
    assert [c["WWXRP_ROI_" + k + "_BPS"] for k in ["MIN", "VA", "VB", "MAX"]] == [v for _, v in WWXRP_CURVE_BPS]
    assert [c[k] for k in ["ROI_MIN_BPS", "ROI_VA_BPS", "ROI_VB_BPS", "ROI_MAX_BPS"]] == [v for _, v in ORDINARY_CURVE_BPS]
    assert {s: c[f"DEGEN_DGNRS_{s}_BPS"] for s in (7, 8, 9)} == dgnrs_bps
    assert c["AFFILIATE_BOX_BPS"] == affiliate_bps


def main():
    plain, helped = enumeration_joint()
    assert plain == convolution_joint()
    assert sum(plain.values()) == sum(helped.values()) == 1
    assert all(1 <= s <= 9 and 0 <= w <= 4 for s, w in set(plain) | set(helped))
    ps, ws = probabilities(plain), weights(plain)
    pr, wr = probabilities(helped), weights(helped)
    assert ps[9] == pr[9] == WILD_RATE * F(1, 8) ** 4 * (F(1, 8) + F(7, 8) * WILD_RATE) ** 3
    assert {w: plain.get((9, w), F(0)) for w in range(5)} == {w: helped.get((9, w), F(0)) for w in range(5)}
    assert plain[9, 4] == F(1, 268_435_456)
    assert sum(ps[3:]) == sum(pr[3:])
    assert sum(ws) == 1 + WILD_RATE
    assert all(sum(pr[s:]) >= sum(ps[s:]) for s in range(10))

    payouts = [F(x, 100) for x in BASE_CENTIX]
    base_ev = sum(payouts[s] * ws[s] for s in range(10))
    eth_extra = sum(F(ETH_ADD_CENTIX[s], 100) * ws[s] for s in range(10))
    assert 0 <= 1 - base_ev < F(1, 10_000_000)
    assert 0 <= F(1, 20) - eth_extra < F(1, 10_000_000)
    assert all(payouts[s + 1] >= payouts[s] for s in range(9))

    # Paid maxima: full activity, +12% boon, S9 with four house wilds.
    max_act = F(999, 1000)
    flip_max = max((payouts[s] * max_act * F(4 + w, 4) * MAX_BOON * 2) for s, w in plain)
    eth_max = max(eth_payout(s, w, 9990) * MAX_BOON for s, w in plain)
    assert flip_max == F("1029369.6") and eth_max == F("1016632.96")

    # WWXRP: rigged mixture, separate S8/S9 prizes, 70% floor plus 10/30/30/30 surplus.
    ww_joint = {k: plain.get(k, F(0)) * (1 - WWXRP_RIG_RATE) + helped.get(k, F(0)) * WWXRP_RIG_RATE
                for k in set(plain) | set(helped)}
    ww_weights = weights(ww_joint)
    ww_payouts = [F(x, 100) for x in WWXRP_CENTIX]
    ww_ev = sum(a * b for a, b in zip(ww_payouts, ww_weights))
    ww_floor = int(F(7000) * 1_000_000 / ww_ev)
    ww_factors = {s: int(share / (ww_weights[s] * ww_payouts[s]) * 1_000_000)
                  for s, share in BONUS_SHARES.items()}

    def ww_return(activity):
        bonus = curve_bps(WWXRP_CURVE_BPS, activity) - 7000
        return ww_ev * F(ww_floor, 10_000_000_000) + sum(
            ww_payouts[s] * ww_weights[s] * F(bonus * f, 10_000_000_000) for s, f in ww_factors.items())

    previous = F(0)
    for activity in range(65536):
        value = ww_return(activity)
        assert 0 <= F(curve_bps(WWXRP_CURVE_BPS, activity), 10000) - value < F(1, 5_000_000)
        assert value >= previous
        previous = value
    ww_first_profitable = next(a for a in range(30001) if ww_return(a) >= 1)

    # Side rewards keep the previous game's expected value per ETH staked.
    old = old_joint()
    po = probabilities(old)
    dgnrs_exact = {s: bps * po[s] / ps[s] for s, bps in OLD_DGNRS_BPS.items()}
    dgnrs_bps = {s: round(v) for s, v in dgnrs_exact.items()}
    dgnrs_old = sum(po[s] * b for s, b in OLD_DGNRS_BPS.items())
    dgnrs_new = sum(ps[s] * b for s, b in dgnrs_bps.items())
    assert abs(dgnrs_new / dgnrs_old - 1) < F(1, 500)
    affiliate_rows = []
    for activity, roi in ORDINARY_CURVE_BPS:
        assert abs(sum(p * old_eth_payout(s, g, roi) for (s, g), p in old.items())
                   - sum(p * eth_payout(s, w, roi) for (s, w), p in plain.items())) < F(1, 10**6)
        old_box = sum(p * box_share(old_eth_payout(s, g, roi)) for (s, g), p in old.items() if s >= 5)
        new_box = sum(p * box_share(eth_payout(s, w, roi)) for (s, w), p in plain.items() if s >= 5)
        affiliate_rows.append((activity, OLD_AFFILIATE_BPS * old_box / new_box, new_box))
    affiliate_bps = 426
    assert all(abs(exact - affiliate_bps) < 4 for _, exact, _ in affiliate_rows)

    verify_contract(source_constants(), ww_floor, ww_factors, dgnrs_bps, affiliate_bps)

    ordinary_denominator = lcm(*(p.denominator for p in plain.values()))
    ww_denominator = lcm(*(p.denominator for p in ww_joint.values()))
    data = {
        "checks": "PASS: contract constants, explicit lane enumeration and independent convolution agree",
        "assumptions": {
            "wild_bonus": "1 + 0.25 * house wilds (after rig)",
            "scoring": "4 symbols + hero color (1, or 2 vs a house wild) + 3 colors (equal ordinary or any wild)",
            "rig": "1/20: if S >= 3 and M <= 6, copy one uniform missed non-hero symbol or missed non-wild color",
            "WWXRP_scaling": "shared S0..7, own S8/S9; rig-calibrated 70% base and 130% max activity",
        },
        "base_ev_fraction": str(base_ev),
        "base_ev_percent": float(base_ev * 100),
        "eth_extra_pp": float(eth_extra * 100),
        "paying_score_percent": float(sum(ps[3:]) * 100),
        "paid_maxima_x": {"FLIP_after_survival": float(flip_max), "ETH_gross": float(eth_max)},
        "score_table": [
            {"score": s, "probability_fraction": str(ps[s]), "probability_percent": float(ps[s] * 100),
             "one_in": float(1 / ps[s]) if ps[s] else None, "payout_x": float(payouts[s]),
             "eth_add_x": ETH_ADD_CENTIX[s] / 100,
             "rig5_probability_percent": float((ps[s] * (1 - WWXRP_RIG_RATE) + pr[s] * WWXRP_RIG_RATE) * 100)}
            for s in range(10)
        ],
        "ordinary": {
            "probability_denominator": str(ordinary_denominator),
            "score_wild_weights": [[s, w, str(p * ordinary_denominator)] for (s, w), p in sorted(plain.items()) if p],
        },
        "wwxrp": {
            "probability_denominator": str(ww_denominator),
            "score_wild_weights": [[s, w, str(p * ww_denominator)] for (s, w), p in sorted(ww_joint.items()) if p],
            "floor_scaled_1e6_bps": ww_floor,
            "bonus_factors_scale_1e6": ww_factors,
            "rigged_table_ev_fraction": str(ww_ev),
            "target_curve_bps": WWXRP_CURVE_BPS,
            "first_nonnegative_activity": ww_first_profitable,
            "base_ev_percent": float(ww_return(0) * 100),
            "max_ev_percent": float(ww_return(30000) * 100),
            "activity_bonus_ev_by_winning_score_pp": {
                s: float(ww_payouts[s] * ww_weights[s] * F(6000 * f, 100_000_000)) for s, f in ww_factors.items()
            },
        },
        "activity_returns_percent": [
            {"activity_score": a, "ordinary": float(base_ev * F(curve_bps(ORDINARY_CURVE_BPS, a), 100)),
             "ETH": float((base_ev * F(curve_bps(ORDINARY_CURVE_BPS, a), 10000) + eth_extra) * 100),
             "WWXRP": float(ww_return(a) * 100),
             "WWXRP_target": curve_bps(WWXRP_CURVE_BPS, a) / 100}
            for a in [0, 100, 169, 170, 305, 500, 30000]
        ],
        "side_rewards": {
            "dgnrs_bps": dgnrs_bps,
            "dgnrs_bps_exact": {s: float(v) for s, v in dgnrs_exact.items()},
            "dgnrs_new_over_old": float(dgnrs_new / dgnrs_old),
            "affiliate_bps": affiliate_bps,
            "affiliate_by_activity": [
                {"activity_score": a, "exact_bps": float(exact),
                 "new_over_old": float(affiliate_bps / exact)}
                for a, exact, _ in affiliate_rows
            ],
        },
    }
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
