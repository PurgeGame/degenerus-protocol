"""Planning model: one-symbol Degenerette, independent colors, matched-gold bonus.

Run from any directory with Python 3. No dependencies; no contracts are modified.
All probability and payout calculations use exact rational arithmetic. This is
a proposed model, not a replacement for the deployed/current table generator.

Rig assumption: when 2 <= raw matched axes <= 6, force one uniformly selected
unmatched axis, excluding the hero symbol. Colors are independently score-bearing.
Enumerate both no rig and always-help-when-eligible; any help probability is their
mixture. Gold is counted AFTER the result modification.
"""

from collections import defaultdict
from fractions import Fraction as F
from itertools import product
from math import comb
from pathlib import Path
import json
import re


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "contracts/modules/DegenerusGameDegeneretteModule.sol"
GOLD_INCREMENT = F(1, 4)
# Multipliers in hundredths of stake. S8 absorbs the calibration residual;
# every other tier is deliberately a simple number. S0/S1 pay nothing.
PROPOSED_CENTIX = [0, 0, 100, 250, 800, 2400, 12000, 62500, 2552701, 10000000]
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
    constants = {
        name: int(value.replace("_", ""), 0)
        for name, value in re.findall(
            r"uint256\s+private\s+constant\s+([A-Z0-9_]+)\s*=\s*"
            r"(0x[0-9a-fA-F_]+|[0-9_]+);", SOURCE.read_text()
        )
    }
    out = {}
    for n in range(5):
        for hero_gold in ((False,) if n == 0 else (True,) if n == 4 else (False, True)):
            suffix = f"N{n}" if n in (0, 4) else f"N{n}_HERO{'GOLD' if hero_gold else 'COMMON'}"
            packed = constants[f"QUICK_PLAY_PAYOUTS_{suffix}_PACKED"]
            payouts = [F((packed >> (32 * s)) & 0xFFFFFFFF, 100) for s in range(8)]
            payouts += [F(constants[f"QUICK_PLAY_PAYOUT_{suffix}_S8"], 100),
                        F(constants[f"QUICK_PLAY_PAYOUT_N{n}_S9"], 100)]
            pc = F(1 if hero_gold else 2, 15)
            ps = [F(7, 8), F(0), (1 - pc) / 8, pc / 8]
            colors = [F(1, 15)] * (n - int(hero_gold)) + [F(2, 15)] * (3 - n + int(hero_gold))
            for pc in colors:
                ps = convolve(ps, [F(7, 8), (1 - pc) / 8, pc / 8])
            out[suffix] = (payouts, ps)
    return out


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
    assert base_ev <= 1 < base_ev + F(1, 100_000_000)
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

    old = current_tables()
    for table, old_ps in old.values():
        assert sum(old_ps) == 1
        assert F(9999, 10000) < dot(table, old_ps) <= 1

    rates = [F(0), F(1, 20), F(3, 5)]
    rig_evs = {rate: base_ev + rate * (forced_ev - base_ev) for rate in rates}
    activity = [(0, 9000), (305, 9891), (500, 9970), (30000, 9990)]
    sdgnrs_rates = {7: F(4, 100), 8: F(8, 100), 9: F(15, 100)}
    sdgnrs_new = sum(ps[s] * rate for s, rate in sdgnrs_rates.items())
    sdgnrs_old = sum(old['N0'][1][s] * rate for s, rate in sdgnrs_rates.items())
    data = {
        "checks": "PASS: exact full enumeration and independent 16-state calculation agree",
        "assumptions": {
            "gold_bonus": "1 + 0.25 * matchedGold (after rig)",
            "scoring": "2*heroSymbol + 3 ordinary symbols + 4 independent colors",
            "rig": "force one uniformly selected unmatched non-hero axis if 2 <= rawMatches <= 6",
            "WWXRP_scaling": "shared 90-99.9% activity curve; rig is extra EV; no legacy 70% floor or 70-120% redistribution",
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
             "WWXRP_rig5": float(rig_evs[F(1, 20)] * F(bps, 100)),
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
