#!/usr/bin/env python3
"""Run recorded groups against an isolated snapshot; source copy is explicit."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("workspace", type=Path)
parser.add_argument("label")
parser.add_argument("groups", nargs="*")
args = parser.parse_args()
evidence = Path(__file__).resolve().parent
groups = json.loads((evidence / "groups.json").read_text())
subprocess.run(["node", "scripts/lib/patchForFoundry.js"], cwd=args.workspace, check=True,
               stdout=subprocess.DEVNULL)
results = {}
for name in args.groups or groups:
    (args.workspace / "bench/Imports.sol").write_text(
        '// SPDX-License-Identifier: AGPL-3.0-only\npragma solidity 0.8.34;\n'
        + ''.join(f'import "../{f}";\n' for f in groups[name]))
    log = evidence / f"{args.label}-{name}.log"
    with log.open("w") as output:
        result = subprocess.run(["forge", "test", "-vv"], cwd=args.workspace,
                                stdout=output, stderr=subprocess.STDOUT)
    results[name] = {"returncode": result.returncode, "log": str(log)}
    (evidence / f"{args.label}-status.json").write_text(json.dumps(results, indent=2) + "\n")
    print(name, result.returncode, flush=True)
raise SystemExit(any(r["returncode"] for r in results.values()))
