#!/usr/bin/env python3
"""Run all Foundry tests in bounded compile units and restore deployment pins."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def groups():
    files = sorted(Path("test").rglob("*.sol"))
    support = {p for p in files if any(str(p).startswith(prefix) for prefix in (
        "test/fuzz/helpers/", "test/fuzz/handlers/", "test/helpers/"))}
    fuzz = sorted(Path("test/fuzz").glob("*.t.sol"))
    result = {
        "integration-gas": {p for p in files if p.parts[1] in {
            "craps", "differential", "economics", "gas", "mutation", "invariant"}},
        "repro-symbolic": {p for p in files if p.parts[1] in {"repro", "halmos"}},
    }
    chunk = (len(fuzz) + 3) // 4
    for i in range(4):
        result[f"fuzz-{i + 1}"] = set(fuzz[i * chunk:(i + 1) * chunk])
    result["invariants"] = set(Path("test/fuzz/invariant").rglob("*.sol"))
    missing = set(files) - support - set().union(*result.values())
    if missing:
        raise SystemExit("Unassigned Solidity test sources: " + ", ".join(map(str, sorted(missing))))
    return files, support, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", action="append", help="Run only this group (repeatable)")
    parser.add_argument("--file", action="append", help="Run only these test sources as one group")
    parser.add_argument("--log-dir", default=".audit-test-logs/foundry")
    parser.add_argument("--list", action="store_true", help="List groups without building or patching")
    args, forge_args = parser.parse_known_args()
    os.chdir(ROOT)
    files, support, batches = groups()
    if args.file:
        keep = {Path(p) for p in args.file}
        if not keep <= set(files):
            parser.error("Unknown test source")
        batches = {"focused": keep}
    if args.group:
        unknown = set(args.group) - batches.keys()
        if unknown:
            parser.error("Unknown groups: " + ", ".join(sorted(unknown)))
        batches = {name: keep for name, keep in batches.items() if name in args.group}
    if args.list:
        for name, keep in batches.items():
            print(f"{name}: {len(keep)} source files")
        return 0
    log_dir = Path(args.log_dir).resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.setdefault("FOUNDRY_CACHE_PATH", str(ROOT / ".foundry-cache"))
    env.setdefault("FOUNDRY_DISABLE_NIGHTLY_WARNING", "1")
    pins = ROOT / "contracts/ContractAddresses.sol"
    original_pins = pins.read_bytes()
    summary = []
    try:
        with (log_dir / "address-patch.log").open("w") as log:
            subprocess.run(["node", "scripts/lib/patchForFoundry.js"], check=True,
                           stdout=log, stderr=subprocess.STDOUT)
        for name, keep in batches.items():
            (log_dir / f"{name}-files.txt").write_text("".join(f"{p}\n" for p in sorted(keep)))
            skip = [arg for p in files if p not in keep | support for arg in ("--skip", str(p))]
            command = ["forge", "test", "-vv", *skip, *forge_args]
            print(f"Running {name}; log: {log_dir / (name + '.log')}", flush=True)
            with (log_dir / f"{name}.log").open("w") as log:
                result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            output = (log_dir / f"{name}.log").read_text()
            totals = re.findall(r"Ran \d+ test suites? in .*?: (\d+) tests? passed, (\d+) failed, (\d+) skipped", output)
            row = {"group": name, "exit_code": result.returncode, "source_files": len(keep)}
            if totals:
                row.update(zip(("passed", "failed", "skipped"), map(int, totals[-1])))
            summary.append(row)
            (log_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
            print(json.dumps(row), flush=True)
            if result.returncode:
                print("\n".join(output.splitlines()[-60:]), flush=True)
    finally:
        pins.write_bytes(original_pins)
    return int(any(row["exit_code"] for row in summary))


if __name__ == "__main__":
    sys.exit(main())
