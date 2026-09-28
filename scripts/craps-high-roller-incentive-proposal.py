#!/usr/bin/env python3
"""Model the implemented 5%-of-Added high-roller reserve against its pre-reserve baseline.

The reserve receives unrolled Added, pays in full on a 10% field-wide draw when
at least one eligible high entry other than sDGNRS exists, and carries over otherwise.
The vault is eligible, including as the sole eligible entry; no additional vault
high seat is assumed in the specified growth path.
Award counts still derive from gross Added. Every high in the growth scenario is
assumed eligible. The reserve expectation recursion is exact because the draw is
independent of its balance; a realized balance instead follows discrete wins.
"""
from fractions import Fraction as F
from pathlib import Path
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("report", ROOT / "scripts/craps-emissions-report.py")
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def whole_day_with_reserve(added, normal=0, high=0):
    """New reserve liability is funded once; later draws release it."""
    contribution = F(added, 20)
    row = report.ev.ledger(F(added)-contribution, normal=normal, high=high,
                           free_house=1, awards=min(added//10000,500))
    row["reserve_funding"] = contribution
    row["net"] += contribution
    assert row["net"] == (row["engine_and_pots"] + row["boost_and_progressive"]
                          + row["comps"] + contribution - row["cash_in"])
    return row


def current_metrics():
    rows=[]
    for added in (50000,150000):
        quiet=whole_day_with_reserve(added)
        thresholds={}
        for name, include_comps in (("normal_before_comps",False),("normal_including_comps",True)):
            for count in range(1000):
                r=whole_day_with_reserve(added,normal=count)
                if r["net"]-(0 if include_comps else r["comps"]) <= 0:
                    thresholds[name]=count
                    break
            assert name in thresholds
        rows.append({"added":added,"quiet_daily_net":float(quiet["net"]),**thresholds})
    return rows


def chart(data):
    import matplotlib.pyplot as plt
    days=data["days"]
    xs=[r["day"] for r in days]
    balances=[r["reserve_expected_closing"] for r in days]
    cumulative=[]
    total=0
    for r in days:
        total+=r["reserve_credit"]
        cumulative.append(total)
    fig,axes=plt.subplots(1,2,figsize=(11,4.8),constrained_layout=True)
    axes[0].plot(xs,cumulative,color=report.BLUE,label="No eligible entries: reserve grows")
    axes[0].plot(xs,balances,color=report.ORANGE,label="Growing-field scenario: expected reserve")
    axes[0].set(xlabel="Day",ylabel="Reserve balance (FLIP)",title="5% of Added accumulates until won")
    prizes=[r*10000 for r in range(51)]
    for n,color in ((1,report.BLUE),(2,report.ORANGE),(5,report.GREEN)):
        axes[1].plot(prizes,[p/10/n for p in prizes],color=color,label=f"{n} eligible: per-entry EV")
    axes[1].set(xlabel="Reserve on offer (FLIP)",ylabel="Expected extra prize per entry (FLIP)",title="One field-wide 10% draw")
    for ax in axes:
        ax.grid(alpha=.15)
        ax.legend(facecolor=report.PAPER,edgecolor=report.LINE,labelcolor=report.INK,fontsize=8)
    fig.savefig(ROOT/"docs/craps-emissions/high-reserve.svg")
    fig.savefig(ROOT/"docs/craps-emissions/high-reserve.png",dpi=160)


def project():
    edge, allocation, probability = F(18,100), F(5,100), F(1,10)
    reserve, awards = F(0), F(0)
    totals = {}
    days = []
    for day in range(1,101):
        players = 10+3*(day-1)
        high = players//50
        normal = players-high
        gross_added = 150000 if day<20 else 50000
        deposit = gross_added*allocation
        main_added = gross_added-deposit
        risk, action, _ = report.ev.jackpot(main_added,players+1,min(gross_added//10000,500))
        extra_risk = F(high*160000,1 if high==1 else 2)
        comps = action*F(2,100)+extra_risk*F(96,1000)
        future = action*F(12,100)
        baseline = report.jackpot_only(gross_added,normal,high)
        loss = edge*(risk+extra_risk)
        # Reserve credit is a new claim now; its later award is not counted twice.
        new_net = gross_added+8000-loss+comps+future
        reserve += deposit
        award = probability*reserve if high else F(0)
        reserve -= award
        awards += award
        values = {"day":day,"players":players,"high":high,"gross_added":gross_added,
            "main_added":main_added,"reserve_credit":deposit,"reserve_expected_award":award,
            "reserve_expected_closing":reserve,"engine_loss":loss,"comps":comps,
            "future_bonus_funding":future,"baseline_net":baseline["all_total"],"proposed_net":new_net}
        days.append({k:float(v) if isinstance(v,F) else v for k,v in values.items()})
        for k in ("gross_added","main_added","reserve_credit","reserve_expected_award",
                  "engine_loss","comps","future_bonus_funding","baseline_net","proposed_net"):
            totals[k]=totals.get(k,F(0))+values[k]
        assert totals["reserve_credit"] == awards+reserve
        assert totals["gross_added"] == totals["main_added"]+totals["reserve_credit"]
        assert totals["proposed_net"] == totals["gross_added"]+8000*day-totals["engine_loss"]+totals["comps"]+totals["future_bonus_funding"]
    totals["reserve_expected_closing"] = reserve
    totals["net_difference"] = totals["proposed_net"]-totals["baseline_net"]
    return {"status":"implemented; current 5%-of-Added reserve", "assumptions":{
        "allocation_of_unrolled_added":float(allocation),"field_draw_probability":float(probability),
        "win":"entire reserve, split by a uniform choice of one eligible high entry",
        "eligibility":"high seat at accepted entry terms; no activity-score gate; exclude only sDGNRS; vault eligible; locked before RNG",
        "vault":"can trigger and win alone; no additional vault high seat modeled in this growth path",
        "no_eligible_entries":"no draw; carry over", "free_award_count":"from gross Added, unchanged",
        "players":"10 on day 1, +3/day, all return; floor(players/50) high, all assumed eligible",
        "added":"150k days 1-19, 50k days 20-100; floors binding",
        "engine_loss":float(edge),"house":"one unfunded normal seat",
        "valuation":"reserve and future bonus funding charged once when generated",
        "excluded":"boons, quests, ordinary activity, startup grants, downstream Coinflip"},
        "source_sha256":{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (Path(__file__).resolve(),ROOT/"scripts/craps-emissions-report.py",
                      ROOT/"scripts/craps-ev-analysis.py",ROOT/"contracts/JackpotBattle.sol")},
        "current_whole_day_metrics":current_metrics(),
        "totals":{k:float(v) for k,v in totals.items()},"days":days}


if __name__ == "__main__":
    data=project()
    target=ROOT/"docs/craps-emissions/high-incentive-proposal.json"
    target.write_text(json.dumps(data,indent=2)+"\n")
    chart(data)
    print(json.dumps(data["current_whole_day_metrics"],indent=2))
    print(json.dumps(data["totals"],indent=2))
    print("Verified reserve conservation, Added allocation, and issuance identity on all 100 days.")
    print(target)
