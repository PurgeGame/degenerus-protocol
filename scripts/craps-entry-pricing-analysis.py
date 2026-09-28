#!/usr/bin/env python3
"""Equal-entry player EV before comps/Coinflip, with the 5% newcomer premium.

Jackpot payout is calculated from the existing exact multiplier/granule model.
Whole-day estimates bound the allocation of steady-state progressive funding
between ordinary and jackpot fields. These are model bounds, not confidence
intervals or guarantees about optimized boards or a currently accumulated pot.
"""
import importlib.util
import json
from fractions import Fraction as F
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ev', ROOT / 'scripts/craps-ev-analysis.py')
ev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ev)


def estimate(players, added=50000, edge=F(18, 100)):
    ordinary_seats = players + 1  # one normal house seat
    awards = min(added // 10000, 500)
    jackpot_seats = ordinary_seats + awards
    main_added = F(added) * F(95, 100)
    risk, action, capital = ev.jackpot(main_added, ordinary_seats, awards)
    jackpot_return = (capital - edge * risk) / jackpot_seats
    ordinary_return = ev.ORDINARY_FEE - edge * ev.BANK
    main = F(50000) + F(12, 100) * (ordinary_seats * ev.BANK + action)
    # Half the ordinary budget goes directly to ordinary fields, half to the
    # progressive. In this equal-seat steady-state model the latter can return
    # through either field size. Funding is counted once, never plus its payout.
    direct = ordinary_return + jackpot_return + main / (2 * ordinary_seats)
    lower = direct + main / (2 * jackpot_seats)
    upper = direct + main / (2 * ordinary_seats)
    premium = F(105, 100)
    result = {'paid_players': players, 'added': added,
              'jackpot_expected_return': float(jackpot_return),
              'jackpot_qualified_roi_pct': float(100 * (jackpot_return / 8000 - 1)),
              'jackpot_newcomer_roi_pct': float(100 * (jackpot_return / 8400 - 1)),
              'day_expected_return_min': float(lower), 'day_expected_return_max': float(upper)}
    for label, price in [('qualified', F(25000)), ('newcomer', F(26250))]:
        result['day_' + label + '_roi_pct'] = [float(100 * (v / price - 1)) for v in (lower, upper)]
    assert 8400 - 8000 == 400 and 26250 - 25000 == 1250
    assert (jackpot_return / 8000) / premium == jackpot_return / 8400
    assert lower <= upper
    # Reconcile all engine payouts and all reward funding, before comp allowance.
    ledger = ev.ledger(main_added, normal=players, free_house=1, edge=edge, awards=awards)
    gross = ordinary_seats * ordinary_return + jackpot_seats * jackpot_return
    assert gross == ledger['engine_and_pots']
    assert main == ledger['boost_and_progressive']
    return result


def main():
    counts = [1, 5, 10, 25, 50, 100, 200, 500]
    data = [estimate(n, a) for a in (50000, 150000) for n in counts]
    out = ROOT / 'docs/craps-emissions'
    out.mkdir(exist_ok=True)
    (out / 'entry-pricing-ev.json').write_text(json.dumps(data, indent=2) + '\n')
    doc = ['# Player EV with a 5% newcomer premium', '',
           'A newcomer receives the same entry and rewards but pays 5% more. For an otherwise equivalent entry, qualified accounts retain exactly the surcharge as an expected-net-return advantage: **400 FLIP for the 8k main event; 1,250 for a 25k normal future day; 25,000 for a 500k high future day**.', '',
           '```text', 'newcomer ROI = (1 + qualified ROI) / 1.05 - 1', '```', '',
           'A qualified-player ROI above +5% therefore still leaves positive newcomer EV. That is intentional under the accepted design.', '',
           '## Assumptions', '',
           '18% expected engine loss on exposed bankroll; one normal house seat; filled free-seat draws (5 at 50k Added, 15 at 150k); identical normal entry distributions and no score tie-breaks or payout cuts. Counts include the paid entrant being evaluated. Paid entrants do not also own the modeled free seats. Comps, quests, boons, donations, shared record awards and downstream Coinflip are excluded. Actual engine loss and board competitiveness can change the figures.', '',
           'Five percent of gross Added now funds the high-roller reserve; normal entries compete for the other 95%. Free-seat counts still use gross Added. These normal-only scenarios receive no reserve prizes. The newcomer surcharge is a separate burn and creates no additional reward/action/comp basis.', '']
    for added in (50000, 150000):
        rows = [r for r in data if r['added'] == added]
        doc += [f'## Main jackpot event: Added {added:,}', '',
                'Direct event return only; separate progressive awards and future action rewards are excluded.', '',
                '| Paid normal entrants | Expected return | ROI at 8,000 | ROI at 8,400 |',
                '|---:|---:|---:|---:|']
        for r in rows:
            doc.append(f"| {r['paid_players']} | {r['jackpot_expected_return']:,.0f} | {r['jackpot_qualified_roi_pct']:+.1f}% | {r['jackpot_newcomer_roi_pct']:+.1f}% |")
        doc += ['', f'## Entire normal future day: Added {added:,}', '',
                'Steady participation and a filled seven-day action book. Ranges allocate the daily progressive funding between the two eligible field sizes; they are not statistical confidence intervals. They value pass awards at face and include reward funding once. They do not price a particular live progressive balance or predict same-day liquid receipts. Ordinary bonus payout rounding is omitted.', '',
                '| Paid normal day players | ROI at 25,000 | ROI at 26,250 |',
                '|---:|---:|---:|']
        for r in rows:
            q = r['day_qualified_roi_pct']; n = r['day_newcomer_roi_pct']
            doc.append(f"| {r['paid_players']} | {q[0]:+.1f}% to {q[1]:+.1f}% | {n[0]:+.1f}% to {n[1]:+.1f}% |")
        doc.append('')
    doc += ['## What moves the edge', '',
            'Fewer competing seats and larger accumulated prizes improve player EV. More competing seats dilute fixed prizes. Greater bankroll loss reduces EV; earned boons and quests can improve it. High-roller participation also changes shared ordinary reward funding, so the normal-only table is not a universal mixed-field estimate. System emission thresholds differ because house/free-seat awards and vault comp funding also count toward system emissions.', '',
            'The aggregate emissions report preserves the pre-reserve baseline; the high-roller reserve report gives the current allocation and its effect on system emissions. Each newcomer purchase adds a separate 5%-of-base burn; it does not multiply the prize budget.', '',
            '![Normal entry EV versus participation](craps-emissions/entry-pricing-ev.svg)', '',
            'Reproduce with `python3 scripts/craps-entry-pricing-analysis.py`.', '']
    (ROOT / 'docs/CRAPS-ENTRY-PRICING-EV.md').write_text('\n'.join(doc))
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    plt.rcParams.update({'figure.facecolor':'#111b27','axes.facecolor':'#111b27','savefig.facecolor':'#111b27',
                         'text.color':'#e6edf5','axes.labelcolor':'#e6edf5','xtick.color':'#a4b4c7','ytick.color':'#a4b4c7',
                         'axes.edgecolor':'#34465a','font.size':10})
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.8), constrained_layout=True)
    xs = list(range(1, 301))
    series = [estimate(n) for n in xs]
    for label, color in [('qualified','#82b5ff'), ('newcomer','#ffb078')]:
        axes[0].plot(xs, [r['jackpot_' + label + '_roi_pct'] for r in series], color=color, label=label.title())
        lo = [r['day_' + label + '_roi_pct'][0] for r in series]
        hi = [r['day_' + label + '_roi_pct'][1] for r in series]
        axes[1].fill_between(xs, lo, hi, color=color, alpha=.22)
        axes[1].plot(xs, [(a+b)/2 for a,b in zip(lo,hi)], color=color, label=label.title())
    for ax, title in zip(axes, ['Main jackpot event · 8k / 8.4k', 'Whole normal future day · 25k / 26.25k']):
        ax.set(xscale='log', xlabel='Paid normal players', ylabel='Expected player ROI (%)', title=title)
        ax.axhline(0, color='#a4b4c7', lw=.8)
        ax.grid(alpha=.15)
        ax.legend(facecolor='#111b27', edgecolor='#34465a', labelcolor='#e6edf5')
    fig.suptitle('50k gross Added · 5% to high reserve · 18% engine loss · before comps/Coinflip')
    fig.savefig(out / 'entry-pricing-ev.svg')
    fig.savefig(out / 'entry-pricing-ev.png', dpi=160)
    print('Generated entry pricing EV report, data, and dark-mode charts; ledger reconciliation passed.')


if __name__ == '__main__':
    main()
