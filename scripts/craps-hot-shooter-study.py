#!/usr/bin/env python3
"""Reproduce the hot-shooter economic experiment without changing contracts.

python3 scripts/craps-hot-shooter-study.py --output /tmp/craps-hot-shooter
Outputs raw TSVs, the independently selected refinement IDs, and source hashes.
This is a Monte Carlo economic replica, not a same-seed Solidity replay or solvency proof.
"""
import argparse
import concurrent.futures
import csv
import hashlib
import json
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIGS = {
    0: "0,0,0,0,0,0,0,0",
    8: "15,13,11,10,8,6,4,3",
    10: "21,17,15,13,11,8,5,3",
    12: "29,24,20,18,14,10,7,5",
    16: "54,45,37,33,26,19,13,8",
    20: "101,83,68,61,48,35,24,15",
}
CANDIDATE = "30,25,20,18,14,10,7,5"


def source_guard():
    engine = (ROOT / "contracts/Craps.sol").read_text()
    for name, expected in {
        "_MAX_ROLLS": 512, "_MAX_SLIP_HANDS": 512, "_SLIP_ROLL_BUDGET": 600,
        "_ESC_HANDS": 3, "_ESC_FAST_FROM": 30, "_ROTATION_UPLIFT": 5,
    }.items():
        match = re.search(rf"constant {name}\s*=\s*([\d_]+)", engine)
        if not match or int(match[1].replace("_", "")) != expected:
            raise RuntimeError(f"Engine changed: {name}; review the economic replica")
    if "0x1205170618081D091D0B1D0C1D0E200F" not in engine:
        raise RuntimeError("Natural bonus table changed")
    storage = (ROOT / "contracts/storage/CrapsBattleStorage.sol").read_text()
    for name in ["_SCHED_GOAL", "_SCHED_BANK_MULT"]:
        match = re.search(rf"constant {name}\s*=\s*(\d+)", storage)
        if not match or int(match[1]) != 5:
            raise RuntimeError(f"Scheduled format changed: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/craps-hot-shooter"))
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("workers must be positive")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source_guard()
    binary = out / "sim"
    subprocess.run(["g++", "-O3", "-std=c++20", str(ROOT / "scripts/craps-hot-shooter-sim.cpp"), "-o", str(binary)], check=True)
    jobs = []

    def run(name, arguments):
        start = time.monotonic()
        with (out / name).open("w") as f:
            subprocess.run([str(binary), *map(str, arguments)], stdout=f, check=True)
        print(f"{name}: {time.monotonic() - start:.1f}s", flush=True)
        return {"output": name, "arguments": list(map(str, arguments))}

    def batch(items):
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            jobs.extend(pool.map(lambda item: run(*item), items))

    jobs.append(run("validation.txt", ["validate", 20000, 20261001]))
    jobs.append(run("profiles.tsv", ["profiles", 1000000, 20261001]))
    batch([(f"sweep-{x}.tsv", ["evaluate", 100000, 20261002, x, p, "probes", int(x == 0), 0, 40]) for x, p in CONFIGS.items()])
    batch([(f"screen-{x}.tsv", ["evaluate", 20000, 20261003, x, CANDIDATE if x == 12 else CONFIGS[x], "all", int(x == 0), 1, 40]) for x in [0, 10, 12, 16]])
    keep = set()
    # Prespecified four-field screen. Two additional field types are holdout probes in refinement.
    metrics = ["win_blank_pct", "win_sharp_pct", "win_mix_pct", "win_dark_pct", "rtp_pct", "goal_pct"]
    for x in [0, 10, 12, 16]:
        with (out / f"screen-{x}.tsv").open() as f:
            rows = list(csv.DictReader(f, delimiter="\t"))
        for placed in range(8):
            tier = [r for r in rows if int(r["placed"]) == placed]
            for metric in metrics:
                keep.update(int(r["id"]) for r in sorted(tier, key=lambda r: float(r[metric]), reverse=True)[:3])
        keep.update(int(r["id"]) for r in sorted(rows, key=lambda r: float(r["rtp_pct"]), reverse=True)[:24])
    with (out / "sweep-12.tsv").open() as f:
        keep.update(int(r["id"]) for r in csv.DictReader(f, delimiter="\t"))
    ids = out / "refine.ids"
    ids.write_text("".join(f"{i}\n" for i in sorted(keep)))
    batch([(f"refine-{x}-{seed}.tsv", ["evaluate", 500000, seed, x, CANDIDATE, ids, int(x == 0), 1, 40]) for x in [0, 12] for seed in [20261004, 20261005]])
    batch([(f"size-{x}-{heads}.tsv", ["evaluate", 200000, 20261006, x, CANDIDATE, ids, int(x == 0), 1, heads]) for x in [0, 12] for heads in [2, 10, 100]])
    batch([(f"jitter{'-control' if not jitter else ''}.tsv", ["evaluate", 1000000, 20261007, 12, CANDIDATE, ids, 0, 1, 40, jitter]) for jitter in [0, 1]])
    files = ["scripts/craps-hot-shooter-sim.cpp", "scripts/craps-hot-shooter-study.py", "scripts/craps-high-water-system-sim.cpp", "contracts/Craps.sol", "contracts/CrapsEngine.sol", "contracts/storage/CrapsBattleStorage.sol"]
    metadata = {
        "date": "2026-10-01", "candidate_percentages_by_placed": CANDIDATE,
        "threshold": 12, "refinement_candidates": len(keep), "jobs": jobs,
        "source_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in files},
        "assumptions": [
            "Economic RNG mixer replaces keccak; dice shared across seats; scatter and survival keyed per seat",
            "Survive X rolls; profit on X+1 onward qualifies, including a late Don't Pass win on the terminal roll",
            "Rotation remains +5% on full-hand profit; returned principal and cap refunds excluded from all boosts",
            "3000 FLIP starting bankroll, 600 opening wager, 5x protected goal; live engine escalator and bounds",
            "Production bust comparator used: hands, nonzero whole-FLIP remainder, peak, remainder, random tie",
            "RTP includes Goal bankroll only, before bounty entry cost, field prize, boon, progressive and external rewards",
            "Field score experiment has equal stakes and standing; no coalitions, entry splitting or adaptive equilibrium solver",
            "Board search uses common random numbers; refinement seeds are independent of screening seeds",
            "Normal 95% Monte Carlo intervals describe sampled variability, not unobserved tails or model error",
        ],
    }
    (out / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")


if __name__ == "__main__":
    main()
