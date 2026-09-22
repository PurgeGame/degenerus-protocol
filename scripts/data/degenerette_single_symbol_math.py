"""Exact production model: one-symbol Degenerette, independent colors, matched-gold bonus.

Run from any directory with Python 3. No dependencies; no contracts are modified.
All probability and payout calculations use exact rational arithmetic. The constants are checked against the implemented shared payout table.

Rig assumption: when 2 <= raw matched axes <= 6, force one uniformly selected
unmatched axis, excluding the hero symbol. Colors are independently score-bearing.
Enumerate both no rig and always-help-when-eligible; any help probability is their
mixture. Gold is counted AFTER the result modification.
"""

from collections import defaultdict
from fractions import Fraction as F
from itertools import product
from math import comb, lcm
from pathlib import Path
import json
import re


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "contracts/modules/DegenerusGameDegeneretteModule.sol"
GOLD_INCREMENT = F(1, 4)
# Multipliers in hundredths of stake. S8 absorbs the calibration residual;
# every other tier is deliberately a simple number. S0/S1 pay nothing.
PROPOSED_CENTIX = [0, 0, 50, 300, 1000, 2500, 12500, 62500, 2347036, 10000000]
WWXRP_RIG_RATE = F(1, 20)
WWXRP_CURVE_BPS = [(0, 7000), (305, 12400), (500, 12760), (30000, 13000)]
BONUS_SHARES = {6: F(1, 10), 7: F(3, 10), 8: F(3, 10), 9: F(3, 10)}


def distributions():
    """Exact P(score, matched gold) via 256 match masks x 16 ticket-gold masks.

    Bits 0..3 are symbols (0 is hero); 4..7 are colors. With independent
    uniform tickets/result, every equality indicator is Bernoulli(1/8).
    Ticket gold indicators are also Bernoulli(1/8), independent of equalities.
    This representation retains everything used by scoring, gold, and the rig.
    """
    plain = defaultdict(F)
    helped = defaultdict(F)
    for mask in range(256):
        matches = mask.bit_count()
        score = matches + (mask & 1)
        match_p = F(7 ** (8 - matches), 8**8)
        colors = mask >> 4
        eligible = [i for i in range(1, 8) if not (mask >> i) & 1]
        helpable = 2 <= matches <= 6
        if helpable:
            assert eligible
        for gold_mask in range(16):
            p = match_p * F(7 ** (4 - gold_mask.bit_count()), 8**4)
            gold = (colors & gold_mask).bit_count()
            plain[score, gold] += p
            if not helpable:
                helped[score, gold] += p
                continue
            for axis in eligible:
                extra_gold = int(axis >= 4 and bool(gold_mask & (1 << (axis - 4))))
                helped[score + 1, gold + extra_gold] += p / len(eligible)
    return dict(plain), dict(helped)


def score_moments(joint):
    probabilities = [F(0)] * 10
    weighted = [F(0)] * 10
    for (score, gold), p in joint.items():
        probabilities[score] += p
        weighted[score] += p * (1 + GOLD_INCREMENT * gold)
    return probabilities, weighted


def analytic_moments(force):
    """Independent cross-check: 16 (hero hit, other-axis count) states.

    H~Bernoulli(1/8), K~Binomial(7,1/8); S=2H+K, raw matches=H+K.
    Four of the seven ordinary axes are colors; one eighth of matched colors
    are gold. Thus E[gold|K]=K/14 and E[gold boost|K]=1+K/56.
    A uniformly selected unmatched ordinary axis adds expected gold boost 1/56.
    """
    ps, ws = [F(0)] * 10, [F(0)] * 10
    for hero, k in product(range(2), range(8)):
        p = F(comb(7, k) * 7 ** (8 - hero - k), 8**8)
        score = 2 * hero + k
        boost = 1 + F(k, 56)
        if force and 2 <= hero + k <= 6:
            score += 1
            boost += F(1, 56)
        ps[score] += p
        ws[score] += p * boost
    return ps, ws


def dot(a, b):
    return sum((x * y for x, y in zip(a, b)), F(0))


def convolve(a, b):
    out = [F(0)] * (len(a) + len(b) - 1)
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            out[i + j] += x * y
    return out


def current_tables():
    """Historical N0 baseline retained only to explain the redesigned payout shape."""
    payouts = [F(x, 100) for x in [0, 0, 195, 487, 1534, 4355, 19988, 102490, 5124517, 10756411]]
    pc = F(2, 15)
    ps = [F(7, 8), F(0), (1-pc)/8, pc/8]
    for _ in range(3):
        ps = convolve(ps, [F(7, 8), (1-pc)/8, pc/8])
    return {"N0": (payouts, ps)}


def verify_contract(factors, ww_floor, ww_factors):
    """Bind the exact model to the literals actually compiled into production."""
    constants = {name: int(value.replace("_", ""), 0) for name, value in re.findall(
        r"uint(?:8|16|256)\s+private\s+constant\s+([A-Z0-9_]+)\s*=\s*(0x[0-9a-fA-F_]+|[0-9_]+);", SOURCE.read_text())}
    packed = constants["QUICK_PLAY_PAYOUTS_PACKED"]
    actual = [(packed >> (32*s)) & 0xFFFFFFFF for s in range(8)]
    actual += [constants["QUICK_PLAY_PAYOUT_S8"], constants["QUICK_PLAY_PAYOUT_S9"]]
    assert actual == PROPOSED_CENTIX, "production payout constants differ from exact model"
    actual_factors = constants["ETH_BONUS_FACTORS_PACKED"]
    assert factors == {s: (actual_factors >> ((s-6)*64)) & (2**64-1) for s in range(6,10)}
    assert constants["BONUS_FACTOR_SCALE"] == 1_000_000
    assert constants["WWXRP_RIG_DENOMINATOR"] == WWXRP_RIG_RATE.denominator
    assert constants["WWXRP_FLOOR_SCALED"] == ww_floor
    packed = constants["WWXRP_BONUS_FACTORS_PACKED"]
    assert ww_factors == {s: (packed >> ((s-6)*64)) & (2**64-1) for s in range(6,10)}
    assert [constants["WWXRP_ROI_" + k + "_BPS"] for k in ["MIN", "VA", "VB", "MAX"]] == [v for _,v in WWXRP_CURVE_BPS]



def wwxrp_target_bps(activity):
    for (lo, a), (hi, b) in zip(WWXRP_CURVE_BPS, WWXRP_CURVE_BPS[1:]):
        if activity <= hi:
            return a + (activity - lo) * (b - a) // (hi - lo)
    return WWXRP_CURVE_BPS[-1][1]


def main():
    plain, helped = distributions()
    ps, ws = score_moments(plain)
    pr, wr = score_moments(helped)
    assert (ps, ws) == analytic_moments(False)
    assert (pr, wr) == analytic_moments(True)
    assert sum(plain.values()) == sum(helped.values()) == 1
    assert all(0 <= g <= 4 and g <= s <= 9 for s, g in set(plain) | set(helped))
    assert ps[9] == pr[9] == F(1, 8**8)
    assert {g: plain.get((9, g), F(0)) for g in range(5)} == {
        g: helped.get((9, g), F(0)) for g in range(5)
    }
    assert sum(ps[2:]) == sum(pr[2:])
    assert sum(ws) == F(65, 64)
    assert sum(p for (s, g), p in plain.items() if g > 0) == 1 - F(63, 64)**4

    payouts = [F(x, 100) for x in PROPOSED_CENTIX]
    fixed_ev = sum(payouts[s] * ws[s] for s in range(10) if s != 8)
    exact_s8 = (1 - fixed_ev) / ws[8]
    assert PROPOSED_CENTIX[8] == int(exact_s8 * 100)
    base_ev, forced_ev = dot(payouts, ws), dot(payouts, wr)
    assert base_ev <= 1 < base_ev + F(1, 10_000_000)
    assert all(payouts[s + 1] >= payouts[s] for s in range(9))
    assert forced_ev > base_ev
    assert all(sum(pr[s:]) >= sum(ps[s:]) for s in range(10))

    # Preserve the existing ETH +5 percentage points, with its current
    # 10/30/30/30 EV allocation to score 6/7/8/9. Floor fixed-point factors.
    factors = {s: int(share / (ws[s] * payouts[s]) * 1_000_000)
               for s, share in BONUS_SHARES.items()}
    bonus_ev = sum(ws[s] * payouts[s] * F(f, 1_000_000) / 20
                   for s, f in factors.items())
    assert F(0) <= F(1, 20) - bonus_ev < F(1, 100_000_000)
    legacy_floor_bonus_ev = sum(ws[s] * payouts[s] * F(500 * f // 1_000_000, 10000)
                                for s, f in factors.items())

    ww_weights = [a * (1-WWXRP_RIG_RATE) + b * WWXRP_RIG_RATE for a,b in zip(ws,wr)]
    ww_ev = dot(payouts, ww_weights)
    ww_joint = {k: plain.get(k,F(0))*(1-WWXRP_RIG_RATE)+helped.get(k,F(0))*WWXRP_RIG_RATE
                for k in set(plain)|set(helped)}
    ww_denominator = lcm(*(p.denominator for p in ww_joint.values()))
    ww_floor = int(F(7000) * 1_000_000 / ww_ev)
    ww_factors = {s: int(share / (ww_weights[s] * payouts[s]) * 1_000_000)
                  for s,share in BONUS_SHARES.items()}
    def ww_return(activity):
        bonus = wwxrp_target_bps(activity) - 7000
        return ww_ev * F(ww_floor, 10_000_000_000) + sum(
            payouts[s] * ww_weights[s] * F(bonus * f, 10_000_000_000) for s,f in ww_factors.items())
    ww_first_profitable = next(s for s in range(30001) if ww_return(s) >= 1)
    for score in range(65536):
        value = ww_return(score)
        assert 0 <= F(wwxrp_target_bps(score),10000) - value < F(1,5_000_000)
        if score:
            assert value >= previous
        previous = value
    assert ww_return(0) < 1 < ww_return(30000)
    assert ww_return(100) < 1
    verify_contract(factors, ww_floor, ww_factors)
    old = current_tables()
    for table, old_ps in old.values():
        assert sum(old_ps) == 1
        assert F(9999, 10000) < dot(table, old_ps) <= 1

    rates = [F(0), F(1, 20), F(3, 5)]
    rig_evs = {rate: base_ev + rate * (forced_ev - base_ev) for rate in rates}
    activity = [(0, 9000), (100, 9000+100*891//305), (169, 9000+169*891//305), (170, 9000+170*891//305), (305, 9891), (500, 9970), (30000, 9990)]
    sdgnrs_rates = {7: F(4, 100), 8: F(8, 100), 9: F(15, 100)}
    sdgnrs_new = sum(ps[s] * rate for s, rate in sdgnrs_rates.items())
    sdgnrs_old = sum(old['N0'][1][s] * rate for s, rate in sdgnrs_rates.items())
    data = {
        "checks": "PASS: contract constants, full enumeration and independent 16-state calculation agree",
        "assumptions": {
            "gold_bonus": "1 + 0.25 * matchedGold (after rig)",
            "scoring": "2*heroSymbol + 3 ordinary symbols + 4 independent colors",
            "rig": "force one uniformly selected unmatched non-hero axis if 2 <= rawMatches <= 6",
            "WWXRP_scaling": "rig-calibrated 70% base; activity raises total to 130%, with all added EV on scores 6-9; one shared score table",
        },
        "wwxrp": {
            "probability_denominator": str(ww_denominator),
            "score_gold_weights": [[s,g,str(p*ww_denominator)] for (s,g),p in sorted(ww_joint.items()) if p],
            "floor_scaled_1e6_bps": ww_floor,
            "bonus_factors_scale_1e6": ww_factors,
            "rigged_table_ev_fraction": str(ww_ev),
            "target_curve_bps": WWXRP_CURVE_BPS,
            "first_nonnegative_activity": ww_first_profitable,
            "low_score_max_activity": ww_first_profitable-1,
            "base_ev_percent": float(ww_return(0)*100),
            "max_ev_percent": float(ww_return(30000)*100),
            "activity_bonus_ev_by_winning_score_pp": {
                s: float(payouts[s]*ww_weights[s]*F(6000*f,100_000_000)) for s,f in ww_factors.items()
            },
        },
        "base_ev_fraction": str(base_ev),
        "base_ev_percent": float(base_ev * 100),
        "gold_extra_base_ev_pp": float((base_ev - dot(payouts, ps)) * 100),
        "exact_s8": str(exact_s8),
        "exact_s8_decimal": float(exact_s8),
        "eth_bonus_factors_scale_1e6": factors,
        "eth_bonus_ev_pp": float(bonus_ev * 100),
        "eth_bonus_ev_pp_if_legacy_intermediate_bps_floor_retained": float(legacy_floor_bonus_ev * 100),
        "any_gold_match_percent": float((1 - F(63, 64)**4) * 100),
        "paying_score_percent": float(sum(ps[2:]) * 100),
        "current_n0_paying_score_percent": float(sum(old['N0'][1][2:]) * 100),
        "sdgnrs_pool_award_frequency_effect_at_1ETH": {
            "new_expected_pool_fraction": float(sdgnrs_new),
            "current_n0_expected_pool_fraction": float(sdgnrs_old),
            "new_over_current_n0": float(sdgnrs_new / sdgnrs_old),
        },
        "rig_gate_for_120pct_at_max_activity": float((F(12000, 9990) - base_ev) / (forced_ev - base_ev)),
        "score_table": [
            {"score": s, "probability_fraction": str(ps[s]), "probability_percent": float(ps[s] * 100),
             "one_in": float(1 / ps[s]), "payout_x": float(payouts[s]),
             "old_n0_payout_x": float(old['N0'][0][s]),
             "base_ev_contribution_pp": float(payouts[s] * ws[s] * 100),
             "rig5_probability_percent": float((ps[s] * F(19, 20) + pr[s] / 20) * 100)}
            for s in range(10)
        ],
        "rig_rates": [
            {"gate_percent": float(rate * 100), "base_ev_percent": float(rig_evs[rate] * 100),
             "bonus_ev_pp": float((rig_evs[rate] - base_ev) * 100),
             "score_at_least_3_percent": float(sum(ps[3:]) * (1 - rate) * 100 + sum(pr[3:]) * rate * 100),
             "score_at_least_6_percent": float(sum(ps[6:]) * (1 - rate) * 100 + sum(pr[6:]) * rate * 100)}
            for rate in rates
        ],
        "activity_returns_percent": [
            {"activity_score": score, "ordinary": float(base_ev * F(bps, 100)),
             "ETH_with_5pp": float(base_ev * F(bps, 100) + bonus_ev * 100),
             "WWXRP": float(ww_return(score)*100),
             "WWXRP_target": wwxrp_target_bps(score)/100,
             "WWXRP_uncalibrated_rig5": float(rig_evs[F(1, 20)] * F(bps, 100)),
             "WWXRP_rig60": float(rig_evs[F(3, 5)] * F(bps, 100))}
            for score, bps in activity
        ],
        "current_table_new_rules_ev_percent": {
            name: float(dot(table, ws) * 100) for name, (table, old_ps) in old.items()
        },
    }
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
