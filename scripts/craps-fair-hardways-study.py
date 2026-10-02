#!/usr/bin/env python3
"""Fair Hard 4/8 economic counterfactual; does not change production contracts.

Builds a temporary copy of the previous hot-shooter replica with exactly one payout
replacement (7/9 -> 8/10). Original-model source files remain unchanged.
Run with --stage sweep, then --stage search/refine after choosing a schedule.
"""
import argparse
import concurrent.futures
import csv
import hashlib
import json
import runpy
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OLD = [30, 25, 20, 18, 14, 10, 7, 5]

VALIDATE = r'''
void validateFair(int n, u64 seed) {
    for (int i=0;i<n;++i) {
        ShooterCache dice(keyed(seed,i)); const auto& s=dice.get(0);
        auto h=hot::profile(s,i%25);
        Shooter prefix=s; prefix.rolls.resize(std::min(prefix.rolls.size(),std::size_t(i%25)));
        for (int j=0;j<10;++j) {
            BoardMoney b{}; b[j]=1200;
            i64 raw=runHandMoney(b,s,false,0), profit=runHandMoney(b,s,true,100)-raw;
            i64 before=runHandMoney(b,prefix,true,100)-runHandMoney(b,prefix,false,0);
            int num=j==7?8:j==8?10:1, den=j==7?7:j==8?9:1;
            assert(h.profit[j]==profit*num/den);
            assert(h.returned[j]==raw-profit+profit*num/den);
            assert(h.suffix[j]==(profit-before)*num/den);
        }
    }
    Shooter hard4{{{3,3},{2,2},{1,3},{3,4}},true};
    Shooter hard8{{{3,3},{4,4},{2,6},{3,4}},true};
    assert(hot::profile(hard4,1).profit[7]==9600);
    assert(hot::profile(hard8,1).profit[8]==12000);
    assert(hot::profile(hard4,2).suffix[7]==0);
    assert(hot::profile(hard8,2).suffix[8]==0);
    std::cout << "Fair payouts: " << n << " hands x 10 legs match independently rescaled legacy profit; principal, suffix and scripted checks passed\n";
}
'''


def build(out):
    runpy.run_path(str(ROOT / "scripts/craps-hot-shooter-study.py"))["source_guard"]()
    source = (ROOT / "scripts/craps-hot-shooter-sim.cpp").read_text()
    old = "pay(j,j==7?8400:10800)"
    assert source.count(old) == 1, "Hardway payout source changed"
    fair = source.replace(old, "pay(j,j==7?9600:12000)")
    fair = fair.replace("int main(int argc,char**argv)", VALIDATE + "\nint main(int argc,char**argv)")
    fair = fair.replace('if(command=="validate")hot::validate(n,seed);', 'if(command=="validate")validateFair(n,seed);')
    (out / "fair.cpp").write_text(fair)
    for name, path in [("original", ROOT / "scripts/craps-hot-shooter-sim.cpp"), ("fair", out / "fair.cpp")]:
        subprocess.run(["g++", "-O3", "-std=c++20", "-I", str(ROOT / "scripts"), str(path), "-o", str(out / name)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/craps-fair-hardways"))
    parser.add_argument("--stage", choices=["sweep", "search", "refine"], default="sweep")
    parser.add_argument("--schedule", default="15,13,10,9,7,5,4,3")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    build(out)
    jobs = []
    def run(name, binary, params):
        with (out / name).open("w") as f:
            subprocess.run([str(out / binary), *map(str, params)], stdout=f, check=True)
        print(name, flush=True)
        return {"file": name, "binary": binary, "parameters": list(map(str, params))}
    def batch(tasks):
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            jobs.extend(pool.map(lambda t: run(*t), tasks))
    if args.stage == "sweep":
        jobs.append(run("validation.txt", "fair", ["validate", 20000, 20261010]))
        tasks = [("sweep-original.tsv", "original", ["evaluate", 500000, 20261011, 12, ",".join(map(str, OLD)), "probes", 0, 0, 40])]
        for pct in [0, 5, 10, 12, 15, 18, 20, 25, 30]:
            schedule = ",".join(str((v*pct+15)//30) for v in OLD)
            tasks.append((f"sweep-fair-{pct}.tsv", "fair", ["evaluate", 500000, 20261011, 12, schedule, "probes", 0, 0, 40]))
        batch(tasks)
    elif args.stage == "search":
        batch([(f"screen-{kind}.tsv", kind, ["evaluate", 30000, 20261012, 12, args.schedule if kind=="fair" else ",".join(map(str, OLD)), "all", 0, 1, 40]) for kind in ["original", "fair"]])
        keep = set()
        for kind in ["original", "fair"]:
            with (out / f"screen-{kind}.tsv").open() as f:
                rows = list(csv.DictReader(f, delimiter="\t"))
            for placed in range(8):
                tier = [r for r in rows if int(r["placed"]) == placed]
                for metric in ["rtp_pct", "goal_pct", *[k for k in rows[0] if k.startswith("win_")]]:
                    keep.update(int(r["id"]) for r in sorted(tier, key=lambda r: float(r[metric]), reverse=True)[:3])
        with (out / "sweep-original.tsv").open() as f:
            keep.update(int(r["id"]) for r in csv.DictReader(f, delimiter="\t"))
        (out / "refine.ids").write_text("".join(f"{i}\n" for i in sorted(keep)))
    elif args.stage == "refine":
        ids = out / "refine.ids"
        batch([(f"refine-{kind}-{seed}.tsv", kind, ["evaluate", 1000000, seed, 12, args.schedule if kind=="fair" else ",".join(map(str, OLD)), ids, 0, 1, 40]) for kind in ["original", "fair"] for seed in [20261013, 20261014]])
    files = ["scripts/craps-fair-hardways-study.py", "scripts/craps-hot-shooter-sim.cpp", "scripts/craps-high-water-system-sim.cpp", "contracts/Craps.sol", "contracts/CrapsEngine.sol"]
    metadata = {
        "stage": args.stage, "schedule_by_placed": args.schedule, "jobs": jobs,
        "fair_payouts": {"hard4": 8, "hard8": 10}, "threshold": 12,
        "target": "previous 12-roll hot candidate with casino 7:1/9:1 hardways",
        "source_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in files},
        "assumptions": ["Economic replica, not EVM same-seed parity", "3000 bankroll, 600 opening wager, protected 5x goal", "Rotation remains +5%, with fair hardway profit also eligible", "All chips and field populations fixed before randomness", "RTP is engine bankroll return; excludes bounty entry cost, field prizes and outside rewards", "Whole-population edge depends on board-selection mix; no single percentage preserves every board's EV"],
    }
    (out / f"metadata-{args.stage}.json").write_text(json.dumps(metadata, indent=2)+"\n")


if __name__ == "__main__":
    main()
