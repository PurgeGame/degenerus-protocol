#!/usr/bin/env python3
"""Reproducible economic Monte Carlo for full stacks, shared dice, and a final coin.

Uses the repo's economic replica with explicit no-goal and current-roll-budget fixes.
No production contracts are changed. This is not a same-seed Solidity parity test.
"""
import argparse
import csv
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HEADER = "experiment,field,n,worlds,boost_bps,rotation,weight,total_weight,ev_pool,ci95_half_pool,cash_probability,first_probability,relative_proportional_ev,split_count,raw_burn,degen_multiplier\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scale", type=float, default=1.0)
    args = parser.parse_args()
    if args.scale <= 0:
        parser.error("scale must be positive")
    model = (ROOT / "scripts/craps-high-water-system-sim.cpp").read_text()
    model = model.split("struct ScoredRun {", 1)[0]
    if "int main(" in model:
        raise RuntimeError("model extraction boundary changed")
    fixes = {
        "constexpr int kRollBudget = 8192;": "constexpr int kRollBudget = 1000;",
        "if (!qualified && bankrollMoney >= goalMoney)": "if (!qualified && goalMoney != 0 && bankrollMoney >= goalMoney)",
    }
    for old, new in fixes.items():
        if model.count(old) != 1:
            raise RuntimeError(f"replica source changed: {old}")
        model = model.replace(old, new)
    engine = (ROOT / "contracts/Craps.sol").read_text()
    for name, value in {"_SLIP_ROLL_BUDGET": 1000, "_MAX_SLIP_HANDS": 512,
                        "_MAX_ROLLS": 512, "_ESC_HANDS": 3}.items():
        found = re.search(rf"constant {name} = ([\d_]+);", engine)
        if not found or int(found[1].replace("_", "")) != value:
            raise RuntimeError(f"engine constant changed: {name}")
    jobs = [
        (100, 150000, "equal", 3200, 0),
        (40, 100000, "equal", 3200, 0),
        (1000, 30000, "equal", 3200, 0),
        (10000, 3000, "equal", 3200, 0),
        (100, 60000, "mixed", 3200, 0),
        (100, 60000, "other_whale_16", 3200, 0),
        (100, 50000, "equal", 0, 0),
        (100, 50000, "equal", 7200, 0),
        (100, 50000, "equal", 3200, 1),
    ]
    output = ROOT / "docs/DECIMATOR-SHARED-EV.csv"
    with tempfile.TemporaryDirectory(prefix="decimator-shared-ev-") as temp:
        temp = Path(temp)
        (temp / "decimator-model.inc").write_text(model + "\n} // namespace\n")
        binary = temp / "ev"
        subprocess.run(["g++", "-O3", "-std=c++20", "-I", str(temp),
                        str(ROOT / "scripts/decimator-shared-ev.cpp"), "-o", str(binary)], check=True)
        with output.open("w") as file:
            file.write(HEADER)
            file.flush()
            for n, worlds, field, boost, rotation in jobs:
                samples = max(100, round(worlds * args.scale))
                print(f"n={n} worlds={samples} field={field} boost={boost} rotation={rotation}", flush=True)
                subprocess.run([str(binary), str(n), str(samples), field, str(boost), str(rotation), "20260929"],
                               stdout=file, check=True)
                file.flush()
            samples = max(100, round(100000 * args.scale))
            print(f"split worlds={samples}", flush=True)
            subprocess.run([str(binary), "split", str(samples)], stdout=file, check=True)
    with output.open() as file:
        rows = list(csv.DictReader(file))
    sources = ["scripts/craps-high-water-system-sim.cpp", "scripts/decimator-shared-ev.cpp",
               "scripts/decimator-shared-ev.py", "contracts/Craps.sol", "contracts/CrapsEngine.sol",
               "contracts/libraries/ActivityCurveLib.sol"]
    metadata = {
        "date": "2026-09-29", "seed": 20260929, "scale": args.scale, "rows": len(rows),
        "jobs": jobs, "replica_patches": fixes,
        "assumptions": [
            "Economic replica uses counter-based 64-bit random mixer in place of EVM keccak",
            "All players share shooter dice; ten random board chips per entry; no manual placement",
            "Normalized bankroll 3000, opening board 600, no goal, every-three-shooters doubling",
            "Main baseline: 15% chance of +32% eligible shooter profit; no rotating bonus",
            "Separate sensitivity runs use zero boost, +72% boost, or existing rotation",
            "Rank by absolute completed-shooter peak, including initial stack; independent random ties",
            "Final coin independently excludes tails; K=min(100,ceil(N/10)) based on original entries",
            "Topheavy: 40% equal base plus 30/18/12 bonuses, redistributed 5:3:2 for underfilled podium",
            "Focal final coin analytically integrated; opponents sampled; split study samples all coins",
            "95% normal Monte Carlo intervals quantify sampling error, not model error",
            "FLIP cost, pool funding, ETH market value, and gas excluded; outputs are gross shares of fixed ETH pool",
            "Weights rescale normalized peaks exactly in replica, without simulating production integer bounds",
        ],
        "source_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources},
    }
    (ROOT / "docs/DECIMATOR-SHARED-EV-METADATA.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Wrote {len(rows)} rows to {output}", flush=True)


if __name__ == "__main__":
    main()
