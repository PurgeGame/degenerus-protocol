#!/usr/bin/env python3
"""Render the shared-dice EV experiment as a report and standalone figure."""
import csv
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
rows = list(csv.DictReader((DOCS / "DECIMATOR-SHARED-EV.csv").open()))
meta = json.loads((DOCS / "DECIMATOR-SHARED-EV-METADATA.json").read_text())
engine = json.loads((DOCS / "DECIMATOR-SHARED-ENGINE-CHECK.json").read_text())
for data in (meta, engine):
    for path, expected in data["source_sha256"].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected, path
assert len(rows) == 543


def get(weight, n=100, field="equal", experiment="topheavy_coin", boost=3200, rotation=0):
    selected = [r for r in rows if r["experiment"] == experiment and int(r["n"]) == n
                and r["field"] == field and int(r["boost_bps"]) == boost
                and int(r["rotation"]) == rotation and float(r["weight"]) == weight]
    assert len(selected) == 1, (weight, n, field, experiment, boost, rotation)
    return {k: float(v) if k not in ("experiment", "field") else v for k, v in selected[0].items()}


baseline = [get(float(r["weight"])) for r in rows if r["experiment"] == "topheavy_coin"
            and r["field"] == "equal" and r["n"] == "100"
            and r["boost_bps"] == "3200" and r["rotation"] == "0"]
assert all(a["ev_pool"] <= b["ev_pool"] for a, b in zip(baseline, baseline[1:]))
assert abs(get(1)["ev_pool"] - 0.01) < 3 * get(1)["ci95_half_pool"]
for r in baseline:
    assert 0 <= r["cash_probability"] <= 0.5
    assert 0 <= r["first_probability"] <= r["cash_probability"]
    assert 0 <= r["ev_pool"] <= 0.5

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10})
fig, axes = plt.subplots(1, 2, figsize=(12, 4.8), constrained_layout=True)
visible = [r for r in baseline if r["weight"] <= 256]
x = [r["weight"] for r in visible]
y = [100 * r["ev_pool"] for r in visible]
target = [100 * r["weight"] / r["total_weight"] for r in visible]
axes[0].plot(x, y, "o-", color="#007c91", label="Simulated prize expectation")
axes[0].plot(x, target, "--", color="#777777", label="Proportional stack share")
axes[0].fill_between(x, [100*(r["ev_pool"]-r["ci95_half_pool"]) for r in visible],
                     [100*(r["ev_pool"]+r["ci95_half_pool"]) for r in visible], color="#007c91", alpha=.2)
axes[0].set_yscale("log")
axes[0].set_ylabel("Expected prize (% of fixed ETH pool)")
axes[0].set_title("Large entries eventually saturate")
axes[0].legend(frameon=False, fontsize=9)
axes[1].plot(x, [r["relative_proportional_ev"] for r in visible], "o-", color="#b34529")
axes[1].axhline(1, color="#777777", linestyle="--", label="Proportional value")
axes[1].set_ylabel("EV / proportional stack entitlement")
axes[1].set_title("Ordinary buy-ins are strongly distorted")
axes[1].legend(frameon=False)
for ax in axes:
    ax.set_xscale("log", base=2)
    ax.set_xticks([.125, .5, 1, 2, 4, 16, 64, 256], ["⅛", "½", "1", "2", "4", "16", "64", "256"])
    ax.set_xlabel("Your starting stack / each opponent's stack")
    ax.grid(alpha=.15)
    ax.spines[["top", "right"]].set_visible(False)
fig.suptitle("Shared dice, 20% opening bet, peak ranking, final coin\n99 equal opponents · 10 winners · 34/22/16/4…% ladder · 150,000 fields", fontsize=12)
fig.savefig(DOCS / "DECIMATOR-SHARED-EV.svg")
fig.savefig(DOCS / "DECIMATOR-SHARED-EV.png", dpi=180)
plt.close(fig)

lines = ["""# Shared-dice Decimator: first EV study

29 September 2026. Design experiment only; production contracts are unchanged.

**Subsequent design decision:** after reviewing these results and the distinction between total EV, ETH per FLIP and proportional stack share, the user accepted the medium-stack efficiency advantage as a sensible incentive. The analysis below records the comparison with the original proportionality objective; that objective is no longer a requirement to flatten the curve. See the updated [design notes](DECIMATOR-BATTLE-SCALING.md) and [Claude prompt](DECIMATOR-CLAUDE-PROMPT.md).

**Later payout revision:** the selected payout is now a 5% first-place bonus plus a 95% equal split across all actual winners, including first, capped at 100. This report and its graph retain the historical top-three-heavy ladder. Its prize expectations, efficiency peak and split-wallet payoffs must not be presented as the new ladder's results. See the [updated focal-entry payout calculation](DECIMATOR-FIRST-BONUS-EV.md).

**Later timing addition:** the user also requested a cumulative 0.9x factor for each game-day offset after opening, locked separately on each burn. These samples have no relative entry-time differences and do not evaluate strategic timing or mixed-day top-ups. The measured distribution still applies to any fixed set of resulting starting stacks under the same game rules.

**Later degen-curve revision:** the proposed multiplier now keeps 1.7049x at 235 points, reaches 1.9x at 500 and caps at 2x, retaining 30,000 points as the working cap location. Degen-specific and split-wallet results below still use the former 1.7833x maximum. Generic stack-ratio results remain valid for their stated fields, but do not constitute recalibration of the updated degen population.

## Executive summary

**The one-fifth opening-bet rule equalizes normalized bankroll depth, but does not deliver reasonably proportional ETH EV for ordinary entries.** Shared dice plus absolute-peak ranking creates a strong advantage for entries somewhat larger than their opponents. Very large entries do reach diminishing returns under the final coin and fixed placement prizes, but only after the ordinary-entry curve has become highly uneven.

Against 99 identical-sized opponents, doubling the focal starting stack raises its expected pool share from approximately 1% to 8.42%, while proportional allocation would give it 1.98%. Half-sized entries receive approximately 0.175%, versus a proportional 0.503%. A mixed field changes the curve substantially: there is no universal FLIP threshold or universal burn-to-ETH exchange rate.

Recommendation: keep this as a measured baseline, not a calibrated final design. Full starting stacks, shared dice and the final coin are preserved throughout the principal experiment. Flatter prizes and existing boost variants reduce some distortion but do not fix the ordinary-entry shortfall. Large-entry wallet splitting is a significant additional incentive.

## Model and interpretation

- Starting stack is full burn multiplied by degen standing; opening total board wager is one-fifth of that stack. The initial board wager doubles every three completed shooters.
- The field shares each shooter's dice. Each entry receives ten independently scattered board chips, its own existing survival draws, and a natural 15% chance of +32% eligible shooter profit. There is no rotating bonus in the principal baseline; rotation is tested separately.
- No goal, protected reserve or cash-out. Peak includes starting bankroll and is sampled at completed-shooter boundaries. The engine's 1,000-roll between-shooter budget, 512-roll shooter cap, and 512-shooter cap remain active.
- Tails on a separate final fair coin is omitted. Heads entries rank by absolute peak, with a separate random tie order. `K=min(100,ceil(N/10))` uses original entries. Winner places are refilled from eligible heads entries.
- The candidate payout is 40% equally across winners, plus 30%/18%/12% podium bonuses. Underfilled podium bonuses use the same 5:3:2 proportions across available places. All-tails events award nothing; production carry/return policy is not selected here.
- The ETH pool is fixed. Outputs are **gross expected prizes**, not net return after FLIP cost or gas. No ETH/FLIP price or pool-funding assumption is invented.
- A normalized run starts at 3,000 and wagers 600. Since the baseline scales every wager and bankroll proportionally, the experiment reuses its peak across starting-stack counterfactuals. This is an evaluation optimization, not a proposed score discount or different game rule.

For a focal stack `w` against opponents totaling `T`, the proportional reference is `P × w/(T+w)`. Divide measured ETH expectation by that reference to obtain the relative-EV column. This differs from dividing EV by burn: the proportional denominator also changes when the focal player adds burn.

The focal final coin is integrated analytically as a 50% eligibility probability; opponent coins are sampled before ranking. This gives the same expectation with lower sampling noise. The multi-wallet experiment samples every coin. Reported intervals are approximate 95% Monte Carlo intervals and exclude model error.

## Equal-opponent results

150,000 fields of 100 entries. Opponents each have starting stack 1. With equal degen multipliers, the first column is also the raw-buy-in multiple. The pool percentages can be multiplied by any proposed ETH pool.

| Your stack | Expected pool share | 95% half-width, percentage points | Proportional share | EV / proportional | Chance of a prize |
|---:|---:|---:|---:|---:|---:|"""]
for w in [.1, .25, .5, .75, 1, 1.25, 1.5, 1.7833, 2, 3, 4, 8, 16, 32, 64, 256]:
    r = get(w)
    lines.append(f"| {w:g}× | {100*r['ev_pool']:.3f}% | ±{100*r['ci95_half_pool']:.3f} | {100*w/r['total_weight']:.3f}% | {r['relative_proportional_ev']:.3f}× | {100*r['cash_probability']:.2f}% |")
lines.append("""
[Standalone EV figure](DECIMATOR-SHARED-EV.svg) · [PNG](DECIMATOR-SHARED-EV.png)

The transition around stack 1 is consequential: adding 25% to a normal entry increases expected winnings from about 0.99% to 3.74% of the pool. Doubling raises it to 8.42%. In this particular field, tested stacks around 1.8–2× produce roughly 4.2 times as much ETH expectation per raw unit as a 1× entry. This is a field-dependent best-response incentive, not a stable-equilibrium proof or a universal optimal buy-in.

At the extreme, a heads entry that almost always takes first earns approximately half the 34% first prize, or 17% of the pool in expectation. Underfilled eligible fields can technically pay a larger first prize, but are negligible at N=100. This explains the eventual saturation; it does not rescue proportionality around normal entry sizes.

## Why the curve bends this way

Equal opening bankroll depth controls survival behavior under proportional scaling. It does not control rank. Shared dice correlate profitable and unprofitable table conditions across players; a slightly larger starting stack can outrank many similar results simultaneously. The peak retains the initial bankroll floor, so a bad run does not remove that initial ranking advantage. Random board scatter, survival coins and boosts create some differences, but the measured differences are insufficient to yield proportional placement EV.

The final coin reduces dominance and redistributes places, but cannot be priced by halving the old no-coin EV. With equal entries, symmetry still allocates approximately 1/N of the pool to each, subject to the all-tails event. Losing flips promote other heads entries into prizes.

## Degen multiplier

At equal raw burn against 99 multiplier-1 opponents, a focal multiplier of 1.7049 gives approximately 7.12% of the pool; 1.7833 gives 7.51%. The degen benefit is therefore much stronger than a proportional 1.7–1.8× improvement in this field. If everyone has the same higher multiplier, their relative ordering returns to the equal-stack case.

Under the baseline, an extra 78.33% of burn and a 1.7833× degen multiplier are mechanically interchangeable: both scale bankroll and wagers. The game cannot distinguish their source without an additional rule that explicitly uses raw burn or degen standing.

## Field dependence and scale

| Field | Your stack | Expected pool share | Proportional share | EV / proportional |
|---|---:|---:|---:|---:|""")
for n, field, weights in [(100, "mixed", [.5, 1, 2, 4, 8, 16, 64]),
                           (100, "other_whale_16", [1, 2, 4, 16]),
                           (1000, "equal", [1, 2, 4, 16, 64]),
                           (10000, "equal", [2, 4, 16, 64])]:
    for w in weights:
        r = get(w, n=n, field=field)
        lines.append(f"| N={n:,}, {field} | {w:g}× | {100*r['ev_pool']:.3f}% | {100*w/r['total_weight']:.3f}% | {r['relative_proportional_ev']:.2f}× |")
lines.append("""
Mixed opponents repeat stacks 0.25, 0.5, 1, 2 and 4 across 99 seats: 20 of each except 19 at 4. Their total is 151. Another scenario has 98 opponents at 1 and one at 16. Each of those scenarios uses 60,000 fields. N=1,000 uses 30,000 fields; N=10,000 uses 3,000, so rare short-stack payouts there are poorly resolved and are not reported in this table.

At N=1,000, a 2× entry gets about 12 times its proportional entitlement; at N=10,000, the 4× entry gets about 53 times, with estimated pool-share interval 2.135% ±0.171 percentage points. This concerns an outlier among equal opponents; it does not mean all entries can earn those shares. The 60% podium budget stays large while the proportional entitlement of one ordinary participant shrinks. The 100-winner cap also reduces the paid fraction above 1,000 entrants.

## Diagnostic alternatives

All-flat prizes and removal of the final coin are diagnostic controls, not recommended replacements for the user's constraints. A lighter podium illustration retains differentiated top-three prizes by making the base 70%, with bonuses 15%/9%/6%; its expectation is exactly the midpoint of the 40%-base and all-flat observations for the same samples.

| Your stack | Current top-heavy + coin | Lighter podium + coin | All-flat + coin | Current top-heavy, no coin |
|---:|---:|---:|---:|---:|""")
for w in [.5, 1, 1.25, 2, 4, 16, 64]:
    a, b, c = get(w), get(w, experiment="flat_coin"), get(w, experiment="topheavy_no_coin")
    lines.append(f"| {w:g}× | {100*a['ev_pool']:.3f}% | {50*(a['ev_pool']+b['ev_pool']):.3f}% | {100*b['ev_pool']:.3f}% | {100*c['ev_pool']:.3f}% |")
lines.append("""
Even equal prizes leave the 2× entry at about 4.10% of the pool, more than twice its 1.98% proportional share. The half-sized entry remains around 0.175%, far below 0.503%. Moving money from the podium alone does not solve the baseline.

50,000-field sensitivity runs also tested zero natural boost, the prior experimental +72% boost at 15% chance, and the existing single rotating +5% shooter bonus. The 2× entry's expected pool shares are respectively 9.17%, 7.08%, and 8.40%, compared with the main 8.42%. None demonstrates the requested proportionality. The +72% choice is a sensitivity experiment, not an approved game change.

## Wallet splitting and actor incentives

100,000 fields per split configuration; all share 99 outside opponents at stack 1. Total actor burn stays fixed. Each actor wallet receives its own board, player-specific draws, final coin and potential paid place. Original-entry counts and K change with the number of wallets, exactly as proposed. Creating/developing wallets, gas and entry minimums are not priced.

| Total actor burn | Wallets | Multiplier per actor wallet | Actor's combined expected pool share |
|---:|---:|---:|---:|""")
for burn in [4, 16, 64]:
    for count, mult in [(1, 1.7833), (4, 1), (4, 1.7833), (16, 1)]:
        r = next(r for r in rows if r["experiment"] == "split_actor" and float(r["raw_burn"]) == burn
                 and int(r["split_count"]) == count and float(r["degen_multiplier"]) == mult)
        lines.append(f"| {burn}× | {count} | {mult:g}× | {100*float(r['ev_pool']):.3f}% |")
lines.append("""
Splitting is not always good: spreading a 4× burn into four fresh normal-sized wallets loses the concentration advantage. But a 16× burn in one maximum-degen wallet earns about 16.13%; four fresh wallets at 4× each earn about 36.96%, despite losing the multiplier. Four already-developed wallets earn about 42.35%. The final coin and multiple podium opportunities reinforce this effect.

| Actor | Relevant incentive / response |
|---|---|
| Variance-seeking player | Strong podium prizes and the final coin provide drama; small-stack prize value is much worse than a proportional explanation would imply. |
| EV maximizer | Choose a stack above the dense part of the current field; compare multiple competitive entries against one saturated entry. |
| Whale | Large single-wallet burns eventually saturate, but fresh-wallet splitting can recover multiple places despite losing degen standing. |
| Affiliate | No special affiliate payout is modeled; do not assume an affiliate channel changes entry economics. |
| Griefer | Extra entries add on-chain work and can increase K before its cap. Funding and minimum-burn constraints need integrated testing. |
| Competitor / coordinated group | Already-developed wallets can retain multipliers across coordinated entries. One-wallet limits do not bound group participation. |
| Late entrant | A visible field allows informed burn sizing before the freeze. This is a statistical advantage in choosing a buy-in, distinct from seeing the random word. |

No Nash equilibrium is established: participation costs, outside FLIP value, heterogeneous standing, late entry and pool funding are not specified. The measured incentives suggest competition to sit above common entry sizes and then split as a single entry saturates. In a growing field, fixed podium fractions can amplify outlier value; in a small or declining field, rounding, underfilled paid places and all-tails policy become more important.

## Solidity cross-check and reproducibility

The fast experiment evaluates **117.5 million normalized craps runs**: 106 million across focal-field scenarios plus 11.5 million for split-wallet scenarios. Scaling counterfactuals reuse these runs. Another 200,000 calls execute the actual Solidity `CrapsEngine.settleSlip` in 2,000 independent 100-entry fields. The latter uses keccak, shared event seeds, independent board scatter/ties/final coins, no goal, and the +32% baseline.

| Focal stack | Fast model expected share | Actual Solidity expected share | Solidity 95% half-width, percentage points |
|---:|---:|---:|---:|""")
for r in engine["rows"]:
    lines.append(f"| {r['weight']:g}× | {100*get(r['weight'])['ev_pool']:.3f}% | {100*r['ev_pool']:.3f}% | ±{100*r['ci95_half_pool']:.3f} |")
lines.append("""
The observed differences are consistent with sampling error. This is a distribution-level corroboration, not a proof of full engine parity or a replacement audit. In particular, normalized scaling does not certify production overflow bounds, small-amount rounding or final contract integration. Manual-board strategies are not calibrated in this study.

The fast runner extracts the relevant part of the existing C++ economic replica, fixes its stale 8,192-roll budget to the current 1,000 and adds the engine's explicit `goal != 0` guard. It checks source constants, records hashes, verifies normalized scale invariance over 2,000 seeds per invocation and checks payout conservation. Final-flip and rank logic use separate random domains. Rare-event estimates for the largest fields need more sampling before precise short-stack claims.

```sh
python3 scripts/decimator-shared-ev.py
python3 scripts/decimator-shared-engine-check.py
python3 scripts/decimator-shared-report.py
```

[Raw CSV](DECIMATOR-SHARED-EV.csv) · [Model metadata and source hashes](DECIMATOR-SHARED-EV-METADATA.json) · [Solidity results](DECIMATOR-SHARED-ENGINE-CHECK.json) · [Solidity log](DECIMATOR-SHARED-ENGINE-CHECK.txt)

## Risks and next decisions

| Issue | Evidence / likelihood | Impact | Next action |
|---|---|---|---|
| Ordinary-entry EV distortion | Reproduced in large Monte Carlo and actual Solidity samples | High: current baseline misses the stated proportionality objective | Treat as unresolved before selecting production rules |
| Multiple-wallet advantage | Quantified for both fresh and developed wallets | High for large burns | Decide the tolerated degree of splitting, then include it in every candidate comparison |
| Field-dependent incentives | Equal, mixed and multi-whale fields have different curves | High for parameter tuning | Use a distribution of realistic fields, not one equal-entry calibration |
| Podium concentration at scale | Large-field simulations | High for capped-winner economics | Test podium budgets as well as game rules across N |
| RNG / keeper / arithmetic integration | Not exercised by an economic replica | Unresolved production risk | Freeze all inputs; bound arithmetic and work; test keeper progress and pool conservation in the real router |

The measured heap architecture remains compatible with this baseline: retain at most 100 eligible peaks in bounded batches, then credit the winners. The full-score baseline needs no median or live-field statistic. Shared outcomes do not automatically mean a single dice calculation can settle every bankroll; common shooter-summary reuse could be a later gas experiment. Existing component measurements are not an integrated worst-case bound, and total settlement work still grows with entries.

There is no validated repair in this report. A useful next study would vary the common escalation schedule or board mechanics while preserving full starting stacks, shared dice and absolute peak ranking. A field-relative wager adjustment is another possibility, but must be tested for both smaller-entry opportunity and large-entry prize EV: extra risk can help a top-heavy competitor. The measured failure cannot be corrected by assuming equal bust odds imply equal value.

[Self-contained prompt for Claude](DECIMATOR-CLAUDE-PROMPT.md)
""")
(DOCS / "DECIMATOR-SHARED-EV-REPORT.md").write_text("\n".join(lines).strip() + "\n")
print("Wrote report, SVG and PNG; source hashes and primary sanity checks passed.")
