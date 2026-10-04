#!/usr/bin/env python3
"""Benchmark the production Coinflip stake codec against the pinned baseline commit.

Production files are never edited. External dependencies are no-op stubs, so
numbers compare Coinflip execution, not complete protocol transaction receipts.
Uses repository compiler settings and --isolate for committed/cold transactions.

Variants:
  baseline  - contracts/Coinflip.sol as of BASELINE_COMMIT (two 128-bit wei lanes per word),
              loaded with `git show`, never from the working tree.
  current   - the working tree's contracts/Coinflip.sol (eight 32-bit whole-FLIP lanes).
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASELINE_COMMIT = "387dd5d964f231349e37687f785a11e9a0313824"
# variant -> (lane bits for the fixture's unit/cap constants, source loader)
VARIANTS = {
    "baseline": (128, lambda: subprocess.run(["git", "-C", str(ROOT), "show", f"{BASELINE_COMMIT}:contracts/Coinflip.sol"],
                                             text=True, capture_output=True, check=True).stdout),
    "current": (32, lambda: (ROOT / "contracts/Coinflip.sol").read_text()),
}


def copy_imports(path, destination, seen=None):
    seen = set() if seen is None else seen
    path = path.resolve()
    if path in seen:
        return
    seen.add(path)
    target = destination / path.relative_to(ROOT)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target)
    for imported in re.findall(r'import\s+(?:[^;]*?from\s+)?["\']([^"\']+)["\']', path.read_text()):
        assert imported.startswith("."), imported
        copy_imports(path.parent / imported, destination, seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variants", nargs="+", choices=VARIANTS, default=["baseline", "current"])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    results = {
        "baseline_commit": BASELINE_COMMIT,
        "compiler": "0.8.34, via-IR, optimizer runs 1000, Osaka",
        "measurement": "Isolated transactions, intrinsic gas included, external dependency calls stubbed. Net includes capped refunds; gross adds refunds back.",
        "scope": "Production Coinflip.sol at the baseline commit versus the working tree; whole-FLIP lanes floor per addition and saturate at the per-day cap.",
        "variants": {},
    }
    for variant in args.variants:
        bits, load = VARIANTS[variant]
        source = load()
        results.setdefault("source_sha256", {})[variant] = hashlib.sha256(source.encode()).hexdigest()
        with tempfile.TemporaryDirectory(prefix=f"coinflip-{variant}-") as directory:
            work = Path(directory)
            copy_imports(ROOT / "contracts/Coinflip.sol", work)
            (work / "contracts/Coinflip.sol").write_text(source)
            (work / "test").mkdir()
            fixture = (ROOT / "scripts/audit/fixtures/CoinflipPacking.t.sol").read_text()
            if bits != 128:
                fixture = fixture.replace("1007 ether + 0.5 ether", "1007 ether")
                fixture = fixture.replace("constant UNIT = 1;", "constant UNIT = 1 ether;")
                fixture = fixture.replace("constant LANE_MAX = type(uint128).max;", f"constant LANE_MAX = type(uint{bits}).max;")
            (work / "test/CoinflipPacking.t.sol").write_text(fixture)
            (work / "foundry.toml").write_text(f'''[profile.default]
src = "contracts"
test = "test"
solc_version = "0.8.34"
via_ir = true
optimizer = true
optimizer_runs = 1000
evm_version = "osaka"
gas_limit = 30000000000
block_gas_limit = 30000000000
remappings = ["forge-std/={ROOT / 'lib/forge-std/src'}/"]
[fuzz]
runs = 1000
seed = "0xdeadbeef"
''')
            print(f"Benchmarking {variant}...", flush=True)
            run = subprocess.run(["forge", "test", "--root", str(work), "--isolate", "-vv"], text=True, capture_output=True)
            if run.returncode:
                raise RuntimeError(f"{variant}\n{run.stdout}\n{run.stderr}")
            metrics = {name: int(value) for name, value in re.findall(r"^\s+([a-z0-9_]+_(?:gross|net|refund)): (-?\d+)$", run.stdout, re.M)}
            assert len(metrics) == 39, run.stdout
            summary = re.search(r"Suite result:.*", run.stdout)
            print(summary.group(0) if summary else run.stdout, flush=True)
            results["variants"][variant] = metrics
            print(json.dumps(metrics, sort_keys=True), flush=True)
    if args.output:
        args.output.write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
