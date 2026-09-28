#!/usr/bin/env python3
"""Build the craps-only emissions report, data and figures. No downstream EV.

Usage: python3 scripts/craps-emissions-report.py
Requires matplotlib, numpy, markdown and Node.js (calculator parity checks).
Reuses only ledger/jackpot from the
dated analytical model; it neither calls nor models any downstream wager.
Markdown is the maintained report source. HTML embeds every figure and a local
scenario calculator; there are no network dependencies in the resulting file.
"""
from pathlib import Path
from fractions import Fraction as F
import base64
import csv
import hashlib
import importlib.util
from functools import lru_cache
import json
import re
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
import numpy as np
import markdown

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs/CRAPS-EMISSIONS-REPORT.md"
OUT = ROOT / "docs/craps-emissions"
OUT.mkdir(exist_ok=True)
spec = importlib.util.spec_from_file_location("craps_ev", ROOT / "scripts/craps-ev-analysis.py")
ev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ev)
BLUE, ORANGE, GREEN, INK, MUTED = "#82b5ff", "#ffb078", "#6bd3b5", "#e6edf5", "#a4b4c7"
PAPER, LINE = "#111b27", "#34465a"
BALANCE_CMAP = LinearSegmentedColormap.from_list("craps_balance", ["#409c87", "#263646", "#d88754"])
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
    "axes.labelcolor": INK, "text.color": INK, "axes.titleweight": "bold",
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.edgecolor": LINE, "xtick.color": MUTED, "ytick.color": MUTED,
    "grid.color": MUTED, "axes.facecolor": PAPER,
    "savefig.facecolor": PAPER, "figure.facecolor": PAPER})


@lru_cache(maxsize=60000)
def row(added=50000, normal=0, high=0, edge=.18, pricing="retail", house=1):
    return ev.ledger(added, normal, high, house, F(str(edge)), pricing)


def net(**kwargs):
    return float(row(**kwargs)["net"])


def jackpot_only(added, normal=0, high=0, house=1, edge=.18):
    """Isolated event at actual fee funding; future action funding valued at face.

    No allocation of whole-day advance-price discounts or ordinary fixed base.
    Future high bonuses may subsequently ride a sole high's run; that future
    loss is excluded from the gross action funding obligation shown here.
    """
    risk, action, capital = ev.jackpot(added, normal+high+house, min(added//10000,500))
    extra_fees = high*(ev.HIGH_EV-1)*8000
    extra_risk = extra_fees / (1 if high == 1 else 2)
    paid = (normal+high*ev.HIGH_EV)*8000
    direct = capital+extra_fees-F(str(edge))*(risk+extra_risk)-paid
    comps = F(2,100)*action+F(96,1000)*extra_risk
    future = F(12,100)*action
    return {"paid":paid,"engine_risk":risk+extra_risk,"booked_action":action,
            "direct_before_comps":direct,"comps":comps,"direct_total":direct+comps,
            "future_bonus_funding":future,"all_before_comps":direct+future,
            "all_total":direct+comps+future}


def jackpot_growth(days=100, edge=.18):
    """Ten daily players on day one, +3/day; every 50th uses a high entry.

    Accrual attributes the full 12% future funding to the originating event.
    The calendar view distributes it equally over the next seven opened days.
    This is expected funding, not a token mint or player-redemption simulation.
    """
    records, future_funding = [], {}
    totals = {}
    cumulative, cumulative_calendar, cumulative_precomp = F(0), F(0), F(0)
    for day in range(1, days+1):
        players = 10+3*(day-1)
        high = players//50
        normal = players-high
        added = 150000 if day < 20 else 50000
        event = jackpot_only(added,normal,high,edge=edge)
        future_funding[day] = event["future_bonus_funding"]
        maturing = sum((future_funding.get(d,F(0)) for d in range(day-7,day)),F(0))/7
        cumulative += event["all_total"]
        cumulative_precomp += event["all_before_comps"]
        cumulative_calendar += event["direct_total"]+maturing
        pending = sum((future_funding[d]*F(7-(day-d),7) for d in range(max(1,day-6),day+1)),F(0))
        assert cumulative-cumulative_calendar == pending
        assert event["all_total"] == added+8000-F(str(edge))*event["engine_risk"]+event["comps"]+event["future_bonus_funding"]
        values = {"day":day,"players":players,"normal":normal,"high":high,"added":added,**event,
                  "cumulative_total":cumulative,"cumulative_before_comps":cumulative_precomp,
                  "bonus_maturing":maturing,"calendar_net":event["direct_total"]+maturing,
                  "calendar_cumulative":cumulative_calendar,"pending_bonus_funding":pending}
        records.append({k:float(v) if isinstance(v,F) else v for k,v in values.items()})
        for k,v in {"players":players,"normal":normal,"high":high,"added":added,**event}.items():
            totals[k]=totals.get(k,F(0))+v
    gross_loss=F(str(edge))*totals["engine_risk"]
    assert totals["paid"] == 8000*(totals["normal"]+21*totals["high"])
    assert cumulative == totals["added"]+8000*days-gross_loss+totals["comps"]+totals["future_bonus_funding"]
    totals["unfunded_house"] = 8000*days
    totals["engine_loss"] = gross_loss
    return {"edge":edge,"days":records,"totals":{k:float(v) for k,v in totals.items()},
            "first_contractive_day":next((r["day"] for r in records if r["all_total"]<=0),None),
            "cumulative_break_even_day":next((r["day"] for r in records if r["cumulative_total"]<=0),None),
            "peak_day":max(records,key=lambda r:r["cumulative_total"])["day"],
            "peak_cumulative":max(r["cumulative_total"] for r in records)}


def budget_value(r, comp_scale=1, extra=0):
    """Keep comp funding visible as an independent policy allocation."""
    return r["net"] - (1 - F(str(comp_scale))) * r["comps"] + F(extra)


def boundary(added, varying="normal", high=0, edge=.18, pricing="retail",
             comp_scale=1, reward_per_normal=0, limit=50000):
    """First whole-day count that covers this budget, with exact granules.

    None for high-only is proved with a positive lower bound for all contested
    field sizes, rather than inferred from a finite scan. The two smaller fields
    are checked separately. Reward sensitivity is an actual average cost input.
    """
    def value(count):
        n, h = (count, high) if varying == "normal" else (0, count)
        return budget_value(row(added, n, h, edge, pricing), comp_scale, reward_per_normal*n)
    if varying == "high" and value(0) > 0 and value(1) > 0:
        e, c = F(str(edge)), F(str(comp_scale))
        discount = F(21325) if pricing == "retail" else F(0)
        # For >=2 highs: jackpot risk <= half the main pool; jackpot fee action
        # is nonnegative. Dropping that action and maximizing loss gives a lower
        # bound on net issuance, valid even if the bankroll cap binds.
        slope_bound = discount + (F(12,100) + F(2,100)*c)*21*ev.BANK + c*7680 - e*312060
        fixed_bound = 50000 + (1-e/2)*added + ev.DAY_FEE + (F(12,100)+F(2,100)*c-e)*ev.BANK - 4000*e
        if slope_bound >= 0 and fixed_bound > 0:
            return None
    for count in range(limit+1):
        if value(count) <= 0:
            assert count == 0 or value(count-1) > 0
            # Check the near-boundary granule sawtooth as well as the first hit.
            assert all(value(count+i) <= 0 for i in range(1,21))
            return count
    raise AssertionError("Break-even search exhausted; do not label this as no finite crossing")


def components(r, added, normal, high, house, edge=.18):
    nominal_paid = (normal + ev.HIGH_EV * high) * ev.DAY_FEE
    values = {
        "Jackpot Added": F(added), "Ordinary base": F(50000),
        "Unfunded house": house * ev.DAY_FEE,
        "Price versus entry EV": nominal_paid - r["cash_in"],
        "Action bonuses": r["boost_and_progressive"] - 50000,
        "Comp allowance": r["comps"],
        "Engine loss": -F(str(edge)) * (r["ordinary_risk"] + r["jackpot_risk"]),
    }
    assert sum(values.values()) == r["net"], "Funding identity does not reconcile"
    return {k: float(v) for k, v in values.items()}


def decorate(ax, xlabel=None, ylabel=None):
    if xlabel: ax.set_xlabel(xlabel)
    if ylabel: ax.set_ylabel(ylabel)
    ax.grid(axis="y", alpha=.16)
    ax.set_axisbelow(True)


def save(fig, name):
    for ext in ("svg", "png"):
        fig.savefig(OUT / f"{name}.{ext}", dpi=175, bbox_inches="tight")
    plt.close(fig)


def calculate():
    data = {"date": "2026-09-28", "head": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "historical_reference": "6c885d5900e110fde8c277d0be39e396f5c18f3f",
        "basis": "New FLIP claims plus new deferred allowances, less paid funding; craps only",
        "assumptions": {"engine_loss": .18, "unfunded_normal_house_seats": 1,
            "steady_trailing_book_days": 7, "boons_and_quests": "excluded; add separately",
            "awards": "min(floor(Added/10000),500), all eligible and filled",
            "standing": "full", "ordinary_boost_rounding": "excluded"},
        "source_sha256": {}, "break_even": [], "examples": [], "margins": [],
        "thresholds": [], "mixed_thresholds": [], "reward_thresholds": [], "comp_policy": [],
        "jackpot_only": {"examples":[],"thresholds":[],"margins":[]}}
    for name in ["contracts/Craps.sol", "contracts/CrapsBattle.sol", "contracts/JackpotBattle.sol",
                 "contracts/storage/CrapsBattleStorage.sol", "contracts/libraries/CrapsPriceLib.sol",
                 "contracts/modules/DegenerusGameAdvanceModule.sol",
                 "contracts/modules/DegenerusGameJackpotModule.sol", "contracts/FLIP.sol",
                 "contracts/DegenerusQuests.sol", "scripts/craps-ev-analysis.py",
                 "scripts/craps-engine-ev-calibration.py", "docs/CRAPS-ENGINE-EV-2026-09-28.tsv",
                 "scripts/craps-emissions-report.py", "docs/CRAPS-EMISSIONS-REPORT.md"]:
        data["source_sha256"][name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    for added in (50000, 150000):
        for edge in (.14, .16, .18, .20):
            count = ev.crossing(added, F(str(edge)), "retail", 1)
            assert net(added=added, normal=count-1, edge=edge) > 0
            assert net(added=added, normal=count, edge=edge) <= 0
            data["break_even"].append({"added": added, "edge": edge, "normal_future_days": count})
        for n, h, price in [(0,0,"retail"), (100,0,"retail"), (200,0,"retail"),
                             (300,0,"retail"), (100,10,"retail"), (0,1,"retail"),
                             (0,10,"retail"), (0,10,"live")]:
            r = row(added, n, h, pricing=price)
            c = components(r, added, n, h, 1)
            data["examples"].append({"added": added, "normal": n, "high": h,
                "pricing": price, **{k:float(v) for k,v in r.items()}, "components": c})
    for edge in (.14, .16, .18, .20):
        for price in ("retail", "live"):
            for kind in ("normal", "high"):
                before = row(edge=edge, pricing=price, **{kind:1000})
                after = row(edge=edge, pricing=price, **{kind:1001})
                data["margins"].append({"edge":edge, "pricing":price, "kind":kind,
                    "net_per_day_pass":float(after["net"]-before["net"]),
                    "funding_per_pass":float(after["cash_in"]-before["cash_in"])})
    # Retail vs actual-entry pricing changes only the funding side.
    for high in (0, 1, 2, 10):
        assert row(normal=100, high=high)["net"] - row(normal=100, high=high, pricing="live")["net"] == -175*100 + 21325*high
    assert sum(p*m for p,m in ev.MULTIPLIERS) == 1
    assert ev.HIGH_EV == 21
    # Comp funding is a separate policy budget, not a payout to the entrant.
    for item in data["margins"]:
        before = row(edge=item["edge"], pricing=item["pricing"], **{item["kind"]:1000})
        after = row(edge=item["edge"], pricing=item["pricing"], **{item["kind"]:1001})
        item["new_comp_allowance"] = float(after["comps"] - before["comps"])
        item["net_before_comps"] = item["net_per_day_pass"] - item["new_comp_allowance"]
    for item in data["examples"]:
        item["net_before_comps"] = item["net"] - item["comps"]
    for added in (50000,150000):
        for edge in (.14,.16,.18,.20):
            for kind in ("normal","high"):
                for price in ("retail","live"):
                    data["thresholds"].append({"added":added,"edge":edge,"kind":kind,"pricing":price,
                        "before_comps":boundary(added,kind,edge=edge,pricing=price,comp_scale=0),
                        "including_comps":boundary(added,kind,edge=edge,pricing=price)})
        for high in (0,1,2,5,10,20,30,40,50):
            data["mixed_thresholds"].append({"added":added,"high":high,
                "normal_before_comps":boundary(added,high=high,comp_scale=0),
                "normal_including_comps":boundary(added,high=high)})
        for reward in (0,250,500,750,1000):
            data["reward_thresholds"].append({"added":added,"extra_reward_per_normal":reward,
                "normal_including_comps":boundary(added,reward_per_normal=reward)})
        for scale in (0,.5,1,1.5):
            r0,r1=row(added,high=1000),row(added,high=1001)
            data["comp_policy"].append({"added":added,"comp_scale":scale,
                "normal_threshold":boundary(added,comp_scale=scale),
                "high_threshold":boundary(added,"high",comp_scale=scale),
                "marginal_high_net":float(budget_value(r1,scale)-budget_value(r0,scale))})
    data["large_field_approximation"] = []
    for added in (50000,150000):
        base=row(added)
        dn={k:row(added,normal=1001)[k]-row(added,normal=1000)[k] for k in base}
        dh={k:row(added,high=1001)[k]-row(added,high=1000)[k] for k in base}
        data["large_field_approximation"].append({"added":added,"constant_total":float(base["net"]),
            "constant_before_comps":float(base["net"]-base["comps"]),"constant_comps":float(base["comps"]),
            "normal_total":float(dn["net"]),"normal_precomp":float(dn["net"]-dn["comps"]),
            "high_total":float(dh["net"]),"high_precomp":float(dh["net"]-dh["comps"]),
            "normal_comp":float(dn["comps"]),"high_comp":float(dh["comps"])})
        for n,h in ((0,0),(50,0),(100,0),(0,1),(0,2),(0,5),(0,10)):
            event=jackpot_only(added,n,h)
            data["jackpot_only"]["examples"].append({"added":added,"normal":n,"high":h,
                **{k:float(v) for k,v in event.items()}})
            if h != 1:
                ordinary=50000+ev.ORDINARY_FEE+(F(14,100)-F(18,100))*ev.BANK*(n+1+21*h)
                assert event["all_total"]+ordinary == row(added,n,h,pricing="live")["net"]
        for kind in ("normal","high"):
            thresholds={"added":added,"kind":kind}
            for key in ("direct_before_comps","direct_total","all_before_comps","all_total"):
                count=next(i for i in range(2000) if jackpot_only(added,**{kind:i})[key]<=0)
                assert count == 0 or jackpot_only(added,**{kind:count-1})[key]>0
                assert all(jackpot_only(added,**{kind:count+i})[key]<=0 for i in range(1,21))
                thresholds[key]=count
            data["jackpot_only"]["thresholds"].append(thresholds)
            before,after=jackpot_only(added,**{kind:1000}),jackpot_only(added,**{kind:1001})
            data["jackpot_only"]["margins"].append({"added":added,"kind":kind,
                **{k:float(after[k]-before[k]) for k in before}})
    data["growth_100_days"] = {"assumptions":{
        "starting_day":1,"initial_players":10,"new_daily_players":3,"retention":"all return daily",
        "high_players":"floor(total_players/50); high replaces normal, one base seat each",
        "level_2_from_day":20,"added":"150000 days 1-19; 50000 days 20-100; floors stay binding",
        "fee_basis":"actual event fees, not allocated 500k whole-day advance discounts",
        "unfunded_normal_house":1,"earlier_action":0,"boons_quests_external_grants":0},
        "scenarios":[jackpot_growth(edge=e) for e in (.14,.16,.18,.20)]}
    (OUT / "model-data.json").write_text(json.dumps(data, indent=2)+"\n")
    with (OUT / "scenarios.csv").open("w") as f:
        fields = [k for k in data["examples"][0] if k != "components"]
        w = csv.DictWriter(f, fields, extrasaction="ignore")
        w.writeheader(); w.writerows(data["examples"])
    with (OUT / "break-even.csv").open("w") as f:
        w=csv.DictWriter(f,list(data["thresholds"][0]));w.writeheader();w.writerows(data["thresholds"])
    growth=next(s for s in data["growth_100_days"]["scenarios"] if s["edge"]==.18)["days"]
    with (OUT / "growth-100-days.csv").open("w") as f:
        w=csv.DictWriter(f,list(growth[0]));w.writeheader();w.writerows(growth)
    return data


def charts(data):
    # 1. Activity and the full loss-rate sensitivity. Bands are scenarios, not CIs.
    fig, axes = plt.subplots(1, 2, figsize=(11.2, 3.9), layout="constrained")
    x = np.arange(0, 401, 5)
    for ax, added, color in zip(axes, (50000,150000), (BLUE,ORANGE)):
        center = [net(added=added,normal=int(n))/1000 for n in x]
        low = [net(added=added,normal=int(n),edge=.20)/1000 for n in x]
        high = [net(added=added,normal=int(n),edge=.16)/1000 for n in x]
        ax.fill_between(x, low, high, color=color, alpha=.14, label="16–20% loss scenarios")
        ax.plot(x, center, color=color, lw=2.3, label="18% loss estimate")
        ax.plot(x,[float(budget_value(row(added,normal=int(n)),0))/1000 for n in x],
                color=GREEN,ls="--",lw=1.6,label="18% loss, before comp funding")
        root = next(r["normal_future_days"] for r in data["break_even"] if r["added"]==added and r["edge"]==.18)
        ax.scatter([root], [0], color=color, zorder=5)
        ax.annotate(f"Break-even: {root} passes/day", (root,0), xytext=(root+10,65),
                    arrowprops={"arrowstyle":"-", "color":color}, fontsize=9)
        ax.axhline(0, color=INK, lw=.8)
        ax.set_title(f"{'Later floor' if added==50000 else 'Early floor'} · Added {added//1000:,}k", loc="left")
        ax.set_ylim(-450, 290); ax.set_xlim(0,400)
        decorate(ax, "Normal 25k future passes played per day", "Net FLIP/day (thousands)")
        ax.legend(frameon=False, fontsize=8, loc="lower left")
    save(fig, "01-activity")

    # 2. A reconciled waterfall, including unfunded capital and price discounts.
    r = row(normal=100, high=10)
    parts = components(r, 50000, 100, 10, 1)
    labels = ["Jackpot\nAdded", "Ordinary\nbase", "Unfunded\nhouse", "Net price\ndiscount",
              "Action\nbonuses", "Comp\nallowance", "Engine\nloss", "Net new\nFLIP"]
    fig, ax = plt.subplots(figsize=(11.2, 4.0), layout="constrained")
    running = 0
    for i,v in enumerate(parts.values()):
        v /= 1000
        ax.bar(i, abs(v), bottom=min(running,running+v), width=.63, color=ORANGE if v>0 else GREEN)
        top = max(running,running+v)
        ax.text(i, top+12, f"{v:+,.1f}k", ha="center", fontsize=9)
        if i<6: ax.plot([i+.32,i+.68], [running+v]*2, color=MUTED, lw=.8)
        running += v
    ax.bar(7, running, color=BLUE, width=.63)
    ax.text(7,running+(12 if running>=0 else -25),f"{running:+,.1f}k",ha="center",weight="bold")
    ax.set_xticks(range(8),labels)
    ax.set_ylim(min(0,running)-30, 1050)
    ax.set_title("100 normal + 10 high future passes: tracing every net contribution",loc="left")
    decorate(ax, ylabel="FLIP/day (thousands)")
    save(fig,"02-waterfall")

    # 3. Mixed participation. Heatmap intentionally starts at 2 high seats.
    fig, axes = plt.subplots(1,2,figsize=(11.2,4.0),layout="constrained",gridspec_kw={"width_ratios":[1,1.25]})
    vals = [next(r for r in data["margins"] if r["edge"]==.18 and r["kind"]==kind and r["pricing"]==price)
            for kind,price in [("normal","retail"),("normal","live"),("high","retail"),("high","live")]]
    per_million = [r["net_per_day_pass"]*1000000/r["funding_per_pass"]/1000 for r in vals]
    labels=["Normal · future", "Normal · live", "High · future", "High · live"]
    axes[0].barh(labels,per_million,color=[GREEN if v<0 else ORANGE for v in per_million])
    axes[0].invert_yaxis(); axes[0].axvline(0,color=INK,lw=.8)
    for i,v in enumerate(per_million): axes[0].text(v+(.9 if v>0 else -.9),i,f"{v:+.1f}k",va="center",ha="left" if v>0 else "right",fontsize=9)
    axes[0].set_xlim(-55,22); axes[0].set_title("Same 1m FLIP of paid activity",loc="left")
    decorate(axes[0], "Marginal net FLIP (thousands)")
    xs=np.arange(0,501,10); ys=np.arange(2,51,2)
    z=np.array([[net(normal=int(n),high=int(h))/1000 for n in xs] for h in ys])
    im=axes[1].pcolormesh(xs,ys,z,cmap=BALANCE_CMAP,vmin=-400,vmax=400,shading="nearest")
    cs=axes[1].contour(xs,ys,z,levels=[0],colors=INK,linewidths=1.8)
    axes[1].clabel(cs,fmt={0:"break-even"},fontsize=9)
    axes[1].set_title("Future-pass mix · Added 50k",loc="left")
    axes[1].set(xlabel="Normal future passes/day",ylabel="High future passes/day")
    fig.colorbar(im,ax=axes[1],label="Net FLIP/day (thousands)",shrink=.88)
    save(fig,"03-mix")

    # 4. Retired jackpot budget only. Do not ascribe the old 50k craps budget anew.
    fig,axes=plt.subplots(1,2,figsize=(11.2,3.9),layout="constrained")
    xs=np.linspace(0,350000,301)
    for ax,floor,factor,label in zip(axes,(150000,50000),(1,.5),("Initial purchase phase · two old draws","Later ordinary day · one old draw")):
        ax.plot(xs/1000,xs*factor/1000,color=MUTED,lw=2,ls="--",label="Old maximum allocated budget")
        ax.plot(xs/1000,.91*np.maximum(xs,floor)/1000,color=BLUE,lw=2.4,label="New Added after estimated engine loss")
        ax.plot(xs/1000,np.maximum(xs,floor)/1000,color=BLUE,lw=1,alpha=.35,label="New Added before engine loss")
        ax.set_title(label,loc="left",fontsize=11)
        decorate(ax,"0.5% of recorded pool, converted to FLIP (thousands)","Jackpot-only FLIP/day (thousands)")
        ax.legend(frameon=False,fontsize=7.5,loc="upper left")
    save(fig,"04-old-versus-new")

    # 5. Marginal sensitivity from a fixed, explicit mixed baseline.
    base = net(normal=100,high=10)
    r = row(normal=100,high=10)
    changes = [
        ("+100 normal future passes",net(normal=200,high=10)-base),
        ("+10 high future passes",net(normal=100,high=20)-base),
        ("+100k Jackpot Added",net(added=150000,normal=100,high=10)-base),
        ("+1 percentage point engine loss",net(normal=100,high=10,edge=.19)-base),
        ("+1 percentage point action rebate",float(r["booked_action"])*.01),
        ("10 highs: live fees instead of 500k",-10*21325),
        ("100 normal passes: live instead of 25k",100*175),
        ("+10k actually paid boon rewards",10000),
    ]
    fig,ax=plt.subplots(figsize=(11.2,4.2),layout="constrained")
    values=[v/1000 for _,v in changes]
    ax.barh([k for k,_ in changes],values,color=[GREEN if v<0 else ORANGE for v in values])
    ax.invert_yaxis();ax.axvline(0,color=INK,lw=.8)
    for i,v in enumerate(values): ax.text(v+(2 if v>0 else -2),i,f"{v:+,.1f}k",va="center",ha="left" if v>0 else "right",fontsize=9)
    ax.set_xlim(-250,135)
    decorate(ax,"Change in net FLIP per day (thousands)")
    ax.set_title("Which levers move emissions?",loc="left")
    save(fig,"05-drivers")
    data["sensitivities"]=[{"change":k,"net_delta":v} for k,v in changes]

    # 6. Decline path: trailing bonuses retain the previous week's paid action.
    days=list(range(-7,11)); ys=[]; counts=[]
    for d in days:
        n=300 if d<0 else 0; current=row(normal=n)
        prior=sum(row(normal=300 if t<0 else 0)["booked_action"] for t in range(d-7,d))/7
        ys.append(float(current["net"]+F(12,100)*(prior-current["booked_action"]))/1000)
        counts.append(n)
    fig,ax=plt.subplots(figsize=(11.2,3.8),layout="constrained")
    ax.fill_between(days,0,ys,where=np.array(ys)>0,color=ORANGE,alpha=.14,step="post")
    ax.step(days,ys,where="post",color=BLUE,lw=2.5)
    ax.axhline(0,color=INK,lw=.8);ax.axvline(0,color=MUTED,ls=":")
    ax.annotate(f"First quiet day: +{ys[7]:,.0f}k",(0,ys[7]),xytext=(1,ys[7]+25),fontsize=10)
    ax.annotate(f"After seven days: +{ys[-1]:,.0f}k",(7,ys[-1]),xytext=(5,ys[-1]+105),arrowprops={"arrowstyle":"-","color":MUTED},fontsize=10)
    ax.text(-6.7,-115,"300 normal future passes/day",fontsize=9)
    ax.set_ylim(-240,700)
    decorate(ax,"Days relative to all outside paid activity stopping", "Net FLIP/day (thousands)")
    ax.set_title("Activity stops immediately; action bonuses take seven days to fall",loc="left")
    save(fig,"06-decline")
    data["decline"]=[{"relative_day":d,"normal":n,"net":v*1000} for d,n,v in zip(days,counts,ys)]

    # 7. Mean-one does not mean a typical day's capital equals the mean.
    fig,axes=plt.subplots(1,2,figsize=(11.2,3.5),layout="constrained")
    labels=["0.5×","3×","20×","100×"]
    for ax,values,title in zip(axes,([90,9,.9,.1],[45,27,18,10]),
                               ("Probability of each jackpot roll","Share of long-run expected capital")):
        bars=ax.bar(labels,values,color=[BLUE,"#5d91cb",ORANGE,"#d88754"],width=.6)
        for b,v in zip(bars,values): ax.text(b.get_x()+b.get_width()/2,v+2,f"{v:g}%",ha="center")
        ax.set_ylim(0,105);ax.set_title(title,loc="left",fontsize=11)
        decorate(ax,"Jackpot multiplier", "Percent")
    save(fig,"07-variance")

    # 8. Comp funding changes the system total without becoming buyer cashback.
    fig,axes=plt.subplots(1,2,figsize=(11.2,3.9),layout="constrained")
    for ax,kind,title in zip(axes,("normal","high"),("Normal future pass · 25k","Contested high future pass · 500k")):
        items=[r for r in data["margins"] if r["kind"]==kind and r["pricing"]=="retail"]
        x=np.arange(len(items)); pre=[r["net_before_comps"]/1000 for r in items];total=[r["net_per_day_pass"]/1000 for r in items]
        ax.bar(x-.18,pre,.34,color=GREEN,label="Before comp funding")
        ax.bar(x+.18,total,.34,color=ORANGE,label="Including comp funding")
        ax.axhline(0,color=INK,lw=.8)
        ax.set_xticks(x,[f'{r["edge"]*100:.0f}%' for r in items]);ax.set_title(title,loc="left")
        decorate(ax,"Engine bankroll loss assumption","Marginal net FLIP (thousands)")
        ax.legend(frameon=False,fontsize=8)
    save(fig,"08-comp-separation")

    # 9. Exact whole-day boundaries for fixed high counts; one high is a special case.
    fig,axes=plt.subplots(1,2,figsize=(11.2,3.8),layout="constrained")
    for ax,added in zip(axes,(50000,150000)):
        items=[r for r in data["mixed_thresholds"] if r["added"]==added]
        xs=[r["high"] for r in items]
        ax.plot(xs,[r["normal_including_comps"] for r in items],color=BLUE,lw=2.3,marker="o",ms=3,label="Cover all issuance, including comps")
        ax.plot(xs,[r["normal_before_comps"] for r in items],color=GREEN,lw=2,ls="--",marker="o",ms=3,label="Cover rewards before comps")
        ax.set_ylim(0,500);ax.set_xlim(0,50);ax.set_title(f"Added {added//1000}k · 18% engine loss",loc="left")
        decorate(ax,"High future passes played per day","Normal future days needed per day")
        ax.legend(frameon=False,fontsize=7.5)
    save(fig,"09-break-even-mix")

    # 10. Only the jackpot event: fee-funded entries, no whole-day price discount.
    fig,axes=plt.subplots(1,2,figsize=(11.2,3.9),layout="constrained")
    for ax,kind,limit in zip(axes,("normal","high"),(450,30)):
        xs=np.arange(0,limit+1,5 if kind=="normal" else 1)
        for added,color in ((50000,BLUE),(150000,ORANGE)):
            values=[float(jackpot_only(added,**{kind:int(n)})["all_total"])/1000 for n in xs]
            ax.plot(xs,values,color=color,lw=2.3,label=f"Added {added//1000}k")
            root=next(r["all_total"] for r in data["jackpot_only"]["thresholds"] if r["added"]==added and r["kind"]==kind)
            ax.scatter([root],[0],color=color,zorder=4)
            ax.annotate(f"{root} entries",(root,0),xytext=(8,16),textcoords="offset points",color=color,fontsize=9)
        ax.axhline(0,color=INK,lw=.8);ax.set_xlim(0,limit);ax.set_ylim(-140,165)
        ax.set_title("Normal · 8k event fee" if kind=="normal" else "High · 168k mean event fees",loc="left")
        decorate(ax,f"Paid {kind} entries in the jackpot event","Net FLIP/event (thousands)")
        ax.legend(frameon=False,fontsize=8,loc="lower left")
    save(fig,"10-jackpot-only")

    # 11. Requested population path; fees, action obligations, and comps counted once.
    growth={s["edge"]:s for s in data["growth_100_days"]["scenarios"]}
    days=[r["day"] for r in growth[.18]["days"]]
    fig,axes=plt.subplots(1,2,figsize=(11.2,4.0),layout="constrained")
    for ax,key,scale,title,ylabel in zip(axes,("all_total","cumulative_total"),(1000,1000000),
            ("Daily jackpot net issuance","Cumulative net issuance"),
            ("FLIP/event (thousands)","FLIP since day 1 (millions)")):
        lower=[r[key]/scale for r in growth[.20]["days"]]
        upper=[r[key]/scale for r in growth[.16]["days"]]
        center=[r[key]/scale for r in growth[.18]["days"]]
        ax.fill_between(days,lower,upper,color=BLUE,alpha=.14,label="16–20% loss scenarios")
        ax.plot(days,center,color=BLUE,lw=2.4,label="18% loss estimate")
        ax.axhline(0,color=INK,lw=.8);ax.axvline(20,color=ORANGE,ls=":",lw=1)
        ax.axvspan(1,19.5,color=ORANGE,alpha=.065)
        ax.set_title(title,loc="left");ax.set_xlim(1,100)
        decorate(ax,"Day · 10 initial players, +3/day",ylabel)
        ax.legend(frameon=False,fontsize=8,loc="lower left")
    axes[0].annotate("Level 2 · Added drops to 50k",(20,13.0349),xytext=(29,110),
                     arrowprops={"arrowstyle":"-","color":ORANGE},color=ORANGE,fontsize=8.5)
    axes[0].annotate("Contracts from day 31",(31,-.3005),xytext=(44,40),
                     arrowprops={"arrowstyle":"-","color":MUTED},fontsize=8.5)
    axes[0].annotate("Day 100: −110.9k",(100,-110.9099),xytext=(-8,16),textcoords="offset points",ha="right",fontsize=9)
    axes[1].annotate("Peak: +2.47m · day 30",(30,2.4666),xytext=(37,3.3),
                     arrowprops={"arrowstyle":"-","color":MUTED},fontsize=8.5)
    axes[1].annotate("Earlier issuance offset by day 88",(88,0),xytext=(40,1.1),
                     arrowprops={"arrowstyle":"-","color":MUTED},fontsize=8.5)
    axes[1].annotate("Day 100: −1.24m",(100,-1.2392),xytext=(-8,15),textcoords="offset points",ha="right",fontsize=9)
    axes[0].set_ylim(-180,160);axes[1].set_ylim(-3.35,3.8)
    save(fig,"11-growth-100-days")
    (OUT/"model-data.json").write_text(json.dumps(data,indent=2)+"\n")


CALCULATOR = r'''
<div class="calculator screen-only" id="calculator">
<h2>Try your own activity mix</h2>
<p>Same model as the charts. Counts are full days of play. A single high seat has additional bounty risk.</p>
<div class="inputs">
<label>Normal future days <input id="nf" type="number" min="0" max="10000" value="100" step="1"></label>
<label>Normal live days <input id="nl" type="number" min="0" max="10000" value="0" step="1"></label>
<label>High future days <input id="hf" type="number" min="0" max="1000" value="10" step="1"></label>
<label>High live days <input id="hl" type="number" min="0" max="1000" value="0" step="1"></label>
<label>Jackpot Added <input id="added" type="number" min="50000" max="10000000" value="50000" step="10000"></label>
<label>Engine loss, % <input id="edge" type="number" min="0" max="50" value="18" step="0.5"></label>
<label>Unfunded house seats <select id="house"><option value="1">1: conservative baseline</option><option value="0">0: no unfunded house cost</option></select></label>
<label>Fixed other new rewards/day <input id="extra" type="number" min="0" max="10000000" value="0" step="1000"></label>
<label>Comp budget, % of current <input id="comp" type="number" min="0" max="200" value="100" step="10"></label>
<label>Extra reward/normal day <input id="pernormal" type="number" min="0" max="100000" value="0" step="50"></label>
</div>
<div class="calc-result" aria-live="polite"><strong id="result"></strong><span id="funding"></span></div>
<p class="small">Positive = total system emission; negative = contraction. Comp allowance is not a return to the buyer. Seven-day steady state, full standing, filled award field. Player EV also depends on actual prize shares, standing and boons. The house switch removes the unfunded seat; it does not simulate a reserve balance. Comp scaling changes all modeled comp allocations together, as a policy counterfactual. Other reward costs equal the fixed amount plus the per-normal amount times paid normal days; enter each grant once.</p>
</div>
<script>
function crapsLedger(nf,nl,hf,hl,added,edge,house,extra,compScale=1,perNormal=0) {
  const n=nf+nl,h=hf+hl,b=n+h+house,awards=Math.min(Math.floor(added/10000),500),seats=b+awards;
  let jr=0,ja=0,jc=0;
  if(seats>0) for(const [p,m] of [[.9,.5],[.09,3],[.009,20],[.001,100]]) {
    const pool=(b*8000+added)*m, bank=Math.min(Math.floor(pool/(seats*600))*300,83886000);
    jr+=p*seats*bank; jc+=p*pool;
    if(b>0) ja+=p*b*8000*Math.min(m,1)*seats*bank/pool;
  }
  let net=0,funding=0,compBudget=0;
  for(const [p,H] of [[79/90,10],[11/90,100]]) {
    const copies=n+house+h*H, bank=copies*10860, sole=h===1?(H-1)*5965:0;
    const fees=h*(H-1)*8000, risk=h===1?fees:fees/2;
    let boost=50000+.12*(bank+sole+ja);
    if(h===1) boost-=edge*.072*(H*10860+sole+ja/b);
    const comps=.02*(bank+ja)+.096*risk;
    const gross=copies*16825+jc+fees-edge*(bank+sole+jr+risk);
    const paid=nf*25000+hf*500000+(nl+hl*H)*24825;
    net+=p*(gross+boost+comps-paid);funding+=p*paid;compBudget+=p*comps;
  }
  const beforeComps=net-compBudget+extra+perNormal*n;
  compBudget*=compScale;
  return {net:beforeComps+compBudget,funding,compBudget,beforeComps};
}
const money=x=>Math.round(x).toLocaleString('en-US');
function refresh() {
  const ids=['nf','nl','hf','hl','added','edge','house','extra','comp','pernormal'];
  const fields=ids.map(id=>document.getElementById(id));
  if(fields.some(el=>!el.checkValidity())){document.getElementById('result').textContent='Enter values within the displayed limits.';document.getElementById('funding').textContent='';return;}
  const v=fields.map(el=>Number(el.value));v[5]/=100;v[8]/=100;
  const r=crapsLedger(...v);
  const output=document.getElementById('result');
  output.textContent=(r.net>=0?'+':'−')+money(Math.abs(r.net))+' FLIP/day '+(r.net>=0?'emission':'contraction');
  output.style.color=r.net>=0?'var(--emission)':'var(--contraction)';
  document.getElementById('funding').textContent='Before comps: '+money(r.beforeComps)+' FLIP/day · New comp allowance: '+money(r.compBudget)+' · Paid funding: '+money(r.funding);
}
document.querySelectorAll('.calculator input,.calculator select').forEach(el=>el.addEventListener('input',refresh));refresh();
</script>
'''

CSS = '''
:root{color-scheme:dark;--ink:#e6edf5;--muted:#a4b4c7;--blue:#82b5ff;--paper:#111b27;--line:#34465a;--surface:#192738;--input:#0d1621;--emission:#ffb078;--contraction:#6bd3b5}
*{box-sizing:border-box} body{margin:0;background:#090f17;color:var(--ink);font:16px/1.53 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1120px;margin:30px auto;background:var(--paper);padding:44px 64px;box-shadow:0 10px 50px #0005}
h1{font-size:42px;line-height:1.08;letter-spacing:-1.4px;margin:6px 0 16px}h2{font-size:27px;line-height:1.2;letter-spacing:-.5px;margin:10px 0 18px}
h3{font-size:18px;line-height:1.3;margin:20px 0 8px}p{margin:10px 0 14px}a{color:var(--blue);text-decoration-thickness:1px;text-underline-offset:2px}
.page{padding:28px 0 32px;border-top:1px solid var(--line)}.page:first-child{border:0;padding-top:0}img{width:100%;height:auto;margin:8px 0;display:block}
table{border-collapse:collapse;width:100%;font-size:14px;margin:18px 0}th{background:var(--surface);color:var(--ink);text-align:left}th,td{padding:9px 11px;border-bottom:1px solid var(--line);vertical-align:top}tr{break-inside:avoid}
blockquote{border-left:4px solid var(--blue);background:var(--surface);padding:8px 18px;margin:20px 0}blockquote p{margin:6px 0}
code{background:var(--surface);padding:2px 5px;border-radius:3px;font-size:.88em}pre{white-space:pre-wrap;background:var(--surface);padding:14px;font-size:13px;line-height:1.4;break-inside:avoid}pre code{padding:0}
li{margin:6px 0}ul,ol{padding-left:23px}.small{font-size:13px;color:var(--muted)}.subtitle{color:var(--muted);font-size:14px;letter-spacing:.3px}
.calculator{border:1px solid var(--line);background:var(--surface);padding:24px;border-radius:8px;margin:22px 0 32px}.calculator h2{font-size:23px}.inputs{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
label{font-size:12px;color:var(--muted);font-weight:600}input,select{width:100%;border:1px solid #50657d;border-radius:4px;padding:10px;margin-top:4px;background:var(--input);color:var(--ink);font-size:15px}input:focus-visible,select:focus-visible,a:focus-visible{outline:2px solid var(--blue);outline-offset:3px}::selection{background:#315882;color:#fff}
.calc-result{margin-top:22px;display:flex;flex-direction:column}.calc-result strong{font-size:26px}.calc-result span{font-size:14px;color:var(--muted)}
@media(max-width:760px){main{padding:22px 18px;margin:0}h1{font-size:34px}.inputs{grid-template-columns:repeat(2,1fr)}table{font-size:12px}td,th{padding:7px 5px}}
@page{size:A4;margin:13mm 14mm 13mm;background:#111b27}
@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}body{background:var(--paper);font-size:10px;line-height:1.39}main{max-width:none;margin:0;padding:0;box-shadow:none}.screen-only{display:none!important}.page{break-before:page;border:0;padding:0}.page:first-child{break-before:auto}h1{font-size:30px}h2{font-size:22px;margin:3px 0 12px}h3{font-size:13px;margin:13px 0 6px}p{margin:7px 0 9px}table{font-size:9px;margin:10px 0}td,th{padding:6px 7px}img{margin:7px 0;max-height:90mm;object-fit:contain}blockquote{margin:10px 0;padding:5px 12px}li{margin:4px 0}pre{font-size:9px;padding:10px}.small,.subtitle{font-size:9px}a{color:var(--ink);text-decoration:none}}
'''


def render():
    source=DOC.read_text()
    # Each H2 begins a print page; h3 stays within its parent page.
    sections=re.split(r"(?=^## )",source,flags=re.M)
    content=[]
    for section in sections:
        if not section.strip():continue
        html=markdown.markdown(section,extensions=["tables","fenced_code","sane_lists"])
        def embed(match):
            path=DOC.parent/match[1]
            if path.suffix.lower() not in (".svg",".png"):return match[0]
            mime="image/svg+xml" if path.suffix==".svg" else "image/png"
            return 'src="data:'+mime+';base64,'+base64.b64encode(path.read_bytes()).decode()+'"'
        html=re.sub(r'src="([^"]+)"',embed,html)
        content.append('<section class="page">'+html+'</section>')
    content.insert(1,CALCULATOR)
    output='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Craps · FLIP emissions report</title><style>'+CSS+'</style></head><body><main>'+''.join(content)+'</main></body></html>'
    target=DOC.with_suffix('.html');target.write_text(output)
    print(target)


def verify_calculator():
    """Compare the portable JS calculator with exact-Fraction analytical cases."""
    js = CALCULATOR.split("<script>")[1].split("const money=")[0]
    cases, expected = [], []
    for added in (50000, 150000, 10000000):
        for edge in (.14, .18, .20):
            for normal, high in ((0, 0), (1, 1), (100, 2), (300, 10)):
                for house in (0, 1):
                    for mixed in (False, True):
                        nf = normal // 2 if mixed else normal
                        hf = high // 2 if mixed else high
                        nl, hl = normal - nf, high - hf
                        for comp_scale in (0, 1, 1.5):
                            for reward in (0, 500):
                                cases.append([nf, nl, hf, hl, added, edge, house, 1234, comp_scale, reward])
                                r = row(added, normal, high, edge, house=house)
                                # Switching normal future to live removes its 175 premium;
                                # switching high future to live removes its 21,325 discount.
                                pre = r["net"] - r["comps"] + 175*nl - 21325*hl + 1234 + reward*normal
                                comp = r["comps"] * F(str(comp_scale))
                                paid = r["cash_in"] - 175*nl + 21325*hl
                                expected.append({"net":float(pre+comp), "beforeComps":float(pre),
                                                 "compBudget":float(comp), "funding":float(paid)})
    command = js + "console.log(JSON.stringify(" + json.dumps(cases) + ".map(v=>crapsLedger(...v))))"
    results = json.loads(subprocess.check_output(["node", "-e", command], text=True))
    errors = [abs(r[key] - target[key]) for r, target in zip(results, expected) for key in target]
    assert len(results) == len(cases) and max(errors) < .00001
    print(f"Calculator parity verified on {len(cases)} cases; maximum difference {max(errors):.2g} FLIP.")


if __name__=="__main__":
    result=calculate()
    verify_calculator()
    charts(result)
    if DOC.exists():render()
    checked = len(result['thresholds'])*2 + len(result['mixed_thresholds'])*2 + len(result['reward_thresholds']) + len(result['comp_policy'])*2
    print(f"Accounting identities and {checked} whole-system plus 16 jackpot-only break-even/crossing cases verified.")
    print("100-day projection reconciled across four loss scenarios, including pending seven-day bonus funding.")
    print(OUT/"model-data.json")
