#!/usr/bin/env python3
"""Pre-reserve craps funding/EV baseline and reusable main-pool arithmetic, 2026-09-28.

For current reserve-inclusive accounting use craps-high-roller-incentive-proposal.py.
The low-level jackpot() helper takes NET main-pool Added, not the reserve contribution.

All values are FLIP, BEFORE the downstream Coinflip wager. The engine loss rate
is an explicit input, not a theorem. Counts are steady daily participation; the
7-day action book has filled. Book progressive funding and comp allowance once
at face value. Do not add their later releases a second time.

Jackpot allocation uses exact discrete multipliers, bankroll granules and caps.
Ordinary preset means are exact. Ordinary boost granule/nearest-thousand rounding,
boons, quests, external pass grants and shared record funding are excluded and
must be itemized separately. Equal engine loss is assumed across bankrolls/boards.
"""

from fractions import Fraction as F
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MULTIPLIERS = [(F(9, 10), F(1, 2)), (F(9, 100), F(3)),
               (F(9, 1000), F(20)), (F(1, 1000), F(100))]
HIGHS = [(F(79, 90), 10), (F(11, 90), 100)]
HIGH_EV = sum(p * h for p, h in HIGHS)
BANK = F(2 * (20 * 600 + 30 * 1800 + 50 * 4500)
         + 3 * (55 * 600 + 25 * 1800 + 20 * 4500), 100)
ORDINARY_FEE = F(2 * 4520 + 3 * 2595)
BOUNTY = ORDINARY_FEE - BANK
DAY_FEE = ORDINARY_FEE + 8000
MAX_BANK = (0xFFFFFF // 10 // 6) * 6 * 50


def jackpot(added, paid, awards):
    """Expected base bankroll, fee action, and total base capital."""
    n = paid + awards
    risk, action, capital = F(0), F(0), F(0)
    if n == 0:
        return risk, action, capital
    for probability, multiple in MULTIPLIERS:
        pool = (paid * 8000 + added) * multiple
        bank = min(pool // (n * 600) * 300, MAX_BANK)
        risk += probability * n * bank
        if paid:
            action += probability * paid * 8000 * min(multiple, 1) * (n * bank) / pool
        capital += probability * pool
    return risk, action, capital


def ledger(added, normal=0, high=0, free_house=0, edge=F(18, 100),
           pricing="retail", awards=None, highs=None):
    """Positive net = new FLIP-value commitments; negative = net retirement.

    free_house assumes a normal unfunded body seat. It is a conservative funding
    scenario, not a prediction that automatic bodies remain unfunded every day.
    One high seat also risks its ordinary and jackpot extra bounties. Its future
    ordinary high boost rides the engine, so its expected payout is reduced too.
    """
    added, edge = F(added), F(edge)
    if awards is None:
        awards = min(int(added // 10000), 500)
    base_seats = normal + free_house + high
    jack_risk, jack_action, jack_capital = jackpot(added, base_seats, awards)
    result = {key: F(0) for key in (
        "cash_in", "ordinary_risk", "jackpot_risk", "booked_action",
        "engine_and_pots", "boost_and_progressive", "comps", "net")}
    for probability, h in HIGHS if highs is None else highs:
        copies = normal + free_house + high * h
        ordinary_capital = copies * ORDINARY_FEE
        ordinary_bank = copies * BANK
        sole_bounty = (h - 1) * BOUNTY if high == 1 else F(0)
        ordinary_risk = ordinary_bank + sole_bounty
        extra_fees = high * (h - 1) * 8000
        extra_risk = F(extra_fees, 1 if high == 1 else 2)
        high_comps = extra_risk * F(12, 100) * F(80, 100)
        booked = ordinary_risk + jack_action
        boost = 50000 + F(12, 100) * booked
        if high == 1:
            high_action = h * BANK + sole_bounty + jack_action / base_seats
            # 60% of the 12% high action allocation goes to the high lane.
            boost -= edge * F(72, 1000) * high_action
        comps = (ordinary_bank + jack_action) * F(2, 100) + high_comps
        gross = (ordinary_capital + jack_capital + extra_fees
                 - edge * (ordinary_risk + jack_risk + extra_risk))
        cash = (normal * 25000 + high * 500000 if pricing == "retail"
                else (normal + high * h) * DAY_FEE)
        row = {"cash_in": cash, "ordinary_risk": ordinary_risk,
               "jackpot_risk": jack_risk + extra_risk, "booked_action": booked,
               "engine_and_pots": gross, "boost_and_progressive": boost,
               "comps": comps, "net": gross + boost + comps - cash}
        for key, value in row.items():
            result[key] += probability * value
    return result


def as_float(row):
    return {key: round(float(value), 6) for key, value in row.items()}


def after_coinflip(row, return_factor, liquid_boost_share):
    """Mark the engine/pot credits through one Coinflip; keep passes/comps at face.

    Between half and all of the protocol boost/progressive awards is liquid.
    Their future settlement-day mix is unknown, so this is a scenario, not an
    unconditional whole-protocol supply forecast.
    """
    return row["net"] + (return_factor - 1) * (
        row["engine_and_pots"] + liquid_boost_share * row["boost_and_progressive"])


def crossing(added, edge, pricing, free_house=0, return_factor=None, liquid_share=F(1)):
    # The displayed result is the first whole seat count that retires value.
    # A local scan handles the bankroll-granule sawtooth at the crossing.
    for n in range(1, 10001):
        row = ledger(added, n, free_house=free_house, edge=edge, pricing=pricing)
        net = row["net"] if return_factor is None else after_coinflip(row, return_factor, liquid_share)
        if net <= 0:
            return n
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/CRAPS-EV-2026-09-28.json")
    parser.add_argument("--plot", action="store_true")
    args = parser.parse_args()
    assert sum(p * m for p, m in MULTIPLIERS) == 1
    assert HIGH_EV == 21
    assert BANK == 10860 and BOUNTY == 5965 and DAY_FEE == 24825
    assert sum(p * min(m, 1) for p, m in MULTIPLIERS) == F(55, 100)
    results = {"assumptions": {
        "basis": "FLIP commitments before Coinflip, steady state, full-standing awards",
        "ordinary_bankroll_per_normal_day": float(BANK),
        "ordinary_bounty_per_normal_day": float(BOUNTY),
        "nominal_day_entry_ev": float(DAY_FEE),
        "high_day_entry_ev": float(DAY_FEE * HIGH_EV),
        "mean_retained_jackpot_multiplier_for_base_action": .55,
        "unmodeled": ["ordinary boost payout rounding", "boons", "quests",
                      "external pass grants", "shared record funding", "downstream Coinflip"]},
        "break_even": [], "zero_outside_play": [], "high_marginal": [], "examples": [],
        "coinflip_sensitivity": [], "coinflip_break_even": []}
    for added in (50000, 150000):
        for edge in (F(14, 100), F(16, 100), F(18, 100), F(20, 100)):
            for pricing in ("live", "retail"):
                for free in (0, 1):
                    n = crossing(added, edge, pricing, free)
                    results["break_even"].append({"added": added, "engine_loss_pct": float(edge * 100),
                        "pricing": pricing, "unfunded_house": free, "normal_days": n,
                        "paid_volume": n * (25000 if pricing == "retail" else 24825) if n else None})
            for free in (0, 1, 2):
                results["zero_outside_play"].append({"added": added, "engine_loss_pct": float(edge * 100),
                    "unfunded_normal_bodies": free, **as_float(ledger(added, free_house=free, edge=edge))})
            # Large contested high field: marginal cost to add one more high day.
            for pricing in ("live", "retail"):
                before = ledger(added, high=1000, edge=edge, pricing=pricing)
                after = ledger(added, high=1001, edge=edge, pricing=pricing)
                results["high_marginal"].append({"added": added, "engine_loss_pct": float(edge * 100),
                    "pricing": pricing, "net_issuance_per_additional_high_day": float(after["net"] - before["net"])})
                if pricing == "retail" and added == 50000:
                    delta = {key: after[key] - before[key] for key in before}
                    for bonus, factor in ((0, F(98425, 100000)), (2, F(99425, 100000)), (6, F(101425, 100000))):
                        ends = [after_coinflip(delta, factor, fraction) for fraction in (F(1,2), F(1))]
                        results["coinflip_sensitivity"].append({"engine_loss_pct": float(edge * 100),
                            "coinflip_bonus_percent": bonus, "net_per_retail_high_min": float(min(ends)),
                            "net_per_retail_high_max": float(max(ends))})
            if edge in (F(16,100), F(18,100)):
                for bonus, factor in ((0, F(98425,100000)), (2, F(99425,100000))):
                    ends = [crossing(added, edge, "retail", 1, factor, fraction) for fraction in (F(1,2), F(1))]
                    results["coinflip_break_even"].append({"added": added, "engine_loss_pct": float(edge*100),
                        "coinflip_bonus_percent": bonus, "normal_future_days_min": min(ends),
                        "normal_future_days_max": max(ends)})
        for n, h, mode in ((0, 0, "live"), (100, 0, "retail"), (200, 0, "retail"),
                           (300, 0, "retail"), (0, 1, "retail"), (0, 10, "retail"), (0, 10, "live")):
            results["examples"].append({"added": added, "normal": n, "high": h, "pricing": mode,
                "unfunded_house": 1, "engine_loss_pct": 18,
                **as_float(ledger(added, normal=n, high=h, free_house=1, pricing=mode))})
    args.output.write_text(json.dumps(results, indent=2) + "\n")
    print(args.output)
    if args.plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, axes = plt.subplots(1, 2, figsize=(12, 4.8), constrained_layout=True)
        for added, color in ((150000, "#a44728"), (50000, "#287693")):
            for edge, style in ((F(18, 100), "-"), (F(16, 100), "--")):
                x = list(range(0, 501, 5))
                y = [float(ledger(added, normal=n, free_house=1, edge=edge)["net"]) / 1000 for n in x]
                axes[0].plot(x, y, color=color, linestyle=style,
                    label=f"Added {added/1000:.0f}k; loss {float(edge)*100:.0f}%")
        axes[0].set(xlabel="Paid normal future day passes per day (25,000 each)",
                    ylabel="Net new FLIP commitments per day (thousands)", title="Normal activity can cover the fixed subsidy")
        x = list(range(2, 31))
        for mode, color in (("retail", "#a44728"), ("live", "#287693")):
            y = [float(ledger(50000, high=n, free_house=1, pricing=mode)["net"]) / 1000 for n in x]
            axes[1].plot(x, y, color=color,
                label="500k future price" if mode == "retail" else "Actual live entry fees")
        axes[1].set(xlabel="Paid high day passes per day", title="High future and live pricing at 21× mean exposure")
        for ax in axes:
            ax.axhline(0, color="#444", linewidth=1)
            ax.grid(alpha=.2)
            ax.legend(fontsize=8)
        fig.suptitle("Current craps EV model — one unfunded house seat; steady state; before Coinflip", fontsize=12)
        axes[1].text(.02, .02, "Added 50k; engine loss 18%", transform=axes[1].transAxes, fontsize=9)
        for extension in ("png", "svg"):
            target = args.output.with_suffix("." + extension)
            fig.savefig(target, dpi=180)
            print(target)


if __name__ == "__main__":
    main()
