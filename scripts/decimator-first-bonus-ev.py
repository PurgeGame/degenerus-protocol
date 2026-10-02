#!/usr/bin/env python3
"""Reprice existing focal-entry observations for a 5% champion bonus.

Linearity of expectation gives E[new payout] = .95 E[flat payout] + .05 P(first).
This requires no new dice samples and works when eligible winner counts vary.
The stored aggregate data do not suffice to reprice multi-wallet actor payouts.
"""
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
source = DOCS / "DECIMATOR-SHARED-EV.csv"
with source.open() as file:
    rows = list(csv.DictReader(file))
key_fields = ("field", "n", "worlds", "boost_bps", "rotation", "weight", "total_weight")
flat = {tuple(r[k] for k in key_fields): r for r in rows if r["experiment"] == "flat_coin"}
derived = []
for old in rows:
    if old["experiment"] != "topheavy_coin":
        continue
    key = tuple(old[k] for k in key_fields)
    even = flat[key]
    assert old["first_probability"] == even["first_probability"]
    assert old["cash_probability"] == even["cash_probability"]
    ev = .95 * float(even["ev_pool"]) + .05 * float(old["first_probability"])
    weight = float(old["weight"])
    derived.append({**{k: old[k] for k in key_fields},
                    "ev_pool": ev, "old_ev_pool": float(old["ev_pool"]),
                    "cash_probability": float(old["cash_probability"]),
                    "first_probability": float(old["first_probability"]),
                    "relative_proportional_ev": ev / (weight / float(old["total_weight"]))})

with (DOCS / "DECIMATOR-FIRST-BONUS-EV.csv").open("w") as file:
    writer = csv.DictWriter(file, fieldnames=list(derived[0]))
    writer.writeheader()
    writer.writerows(derived)

main = [r for r in derived if r["n"] == "100" and r["field"] == "equal"
        and r["boost_bps"] == "3200" and r["rotation"] == "0"]
normal_ev = next(r["ev_pool"] for r in main if float(r["weight"]) == 1)
best = max(main, key=lambda r: r["ev_pool"] / float(r["weight"]))
lines = ["""# Decimator: 5% first-place bonus, 95% equal split

This updates the payout calculation only. Production contracts are unchanged.

## Selected payout

Freeze `K=min(100,ceil(N/10))` from original entries. After all runs and final eligibility coins, retain the best `W=min(K,headsCount)` entries. First receives `5% + 95%/W` of the pool; each other winner receives `95%/W`. There are no second- or third-place bonuses. The 5% is a fixed fraction of the pool, not a 5% increase to the base prize.

| Actual eligible winners | First | Each other winner |
|---:|---:|---:|
| 1 | 100% | — |
| 2 | 52.5% | 47.5% |
| 10 | 14.5% | 9.5% |
| 50 | 6.9% | 1.9% |
| 100 | 5.95% | 0.95% |

When W=0 nobody is credited and the event's return/carry policy applies. In integer wei: `bonus=pool/20`, `base=(pool-bonus)/W`, and all division dust goes to first. This conserves the pool and makes every non-first prize equal.

## Repriced focal-entry EV

The earlier simulation recorded both all-flat prize expectation and first-place probability on exactly the same shared-dice samples. Therefore the updated sample mean follows directly:

```text
newExpectedPoolShare = 0.95 × oldFlatExpectedPoolShare + 0.05 × probabilityOfFirst
```

Both components already include the final eligibility coin. Do not multiply by another 0.5. The identity also holds in underfilled fields because the all-flat term uses the actual winner count in each event.

The following observations use 150,000 fields of 100 entries, with 99 opponents each at starting stack 1. Shared dice, random ten-chip boards, 20% opening wagers, every-three-shooters escalation, no goal, natural 15%/+32% boost, no rotating bonus and a final coin are unchanged. Equal degen multipliers and equal timing factors make the stack multiple also the raw-burn multiple.

| Your stack | New expected pool share | Former top-three-heavy share | ETH per unit relative to a 1x entry | Chance of a prize |
|---:|---:|---:|---:|---:|"""]
for r in main:
    w = float(r["weight"])
    if w not in [.25, .5, 1, 1.25, 1.5, 1.7833, 2, 4, 8, 16, 64, 256]:
        continue
    efficiency = r["ev_pool"] / w / normal_ev
    lines.append(f"| {w:g}x | {100*r['ev_pool']:.3f}% | {100*r['old_ev_pool']:.3f}% | {efficiency:.3f}x | {100*r['cash_probability']:.2f}% |")
lines.append(f"""
The moderately above-field efficiency advantage remains, but is smaller. Among the sampled weights in this equal-opponent field, the best ETH per unit occurs at **{best['weight']}x**, approximately **{best['ev_pool']/float(best['weight'])/normal_ev:.2f}x** the normal-entry efficiency. This is a sampled maximum, not a precisely optimized threshold, universal recommendation or equilibrium.

A dominant single entry in a full ten-winner field approaches roughly 7.25% expected pool share after its final coin, compared with 17% under the former ladder. With 100 actual winners the corresponding conditional-full-board limit is 2.975%. Underfilled boards can pay a larger first prize. Cash and first-place probabilities are unchanged by repricing because ranking and eligibility rules did not change.

## Scope and reproducibility

This is an algebraic repricing of stored sample means, **not a new simulation or Solidity payout test**. It inherits the sampling and model uncertainty of the original observations. The necessary joint second moments were not retained, so no new confidence intervals are claimed. The CSV contains all original focal field-size, field-composition and boost sensitivities repriced with the same identity.

The historical multi-wallet aggregate outputs do not retain equal-split group expectation, so their new combined payout cannot be recovered by this script. In particular, do not quote the old split-wallet percentages as results for this ladder. The updated degen population, mixed-day entry timing, manual boards, and integrated on-chain payout implementation remain separate work.

```sh
python3 scripts/decimator-first-bonus-ev.py
```

[Repriced observations](DECIMATOR-FIRST-BONUS-EV.csv) · [Source metadata](DECIMATOR-FIRST-BONUS-EV-METADATA.json) · [Current design](DECIMATOR-BATTLE-SCALING.md) · [Claude prompt](DECIMATOR-CLAUDE-PROMPT.md)
""")
(DOCS / "DECIMATOR-FIRST-BONUS-EV.md").write_text("\n".join(lines).strip() + "\n")
(DOCS / "DECIMATOR-FIRST-BONUS-EV-METADATA.json").write_text(json.dumps({
    "method": "0.95 * flat_coin.ev_pool + 0.05 * first_probability; no new random samples",
    "rows": len(derived),
    "source_sha256": {"docs/DECIMATOR-SHARED-EV.csv": hashlib.sha256(source.read_bytes()).hexdigest(),
                      "scripts/decimator-first-bonus-ev.py": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
    "limitations": ["No new confidence intervals", "Does not reprice split-actor aggregates",
                    "No new timing or degen-population scenarios", "Not a Solidity payout test"],
}, indent=2) + "\n")
print(f"Repriced {len(derived)} focal-entry observations; wrote current-payout report and CSV.")
