#!/usr/bin/env python3
"""Run the ETH helper proofs without compiling or modifying the active checkout.

Creates a small, retained project containing copies of production contracts and
the three audit harnesses. Requires forge, Halmos 0.3.3 and its Yices solver.
This verifies local transitions; it is not a whole-protocol verification command.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TESTS = (
    "test/halmos/EthLedgerProductionProof.t.sol",
    "test/unit/EthLedgerProductionReplay.t.sol",
    "test/unit/EthLoanBootstrap.t.sol",
)
CONFIG = '''[profile.default]
src = "proofsrc"
test = "test"
out = "out"
libs = ["node_modules", "lib"]
solc_version = "0.8.38"
auto_detect_solc = false
via_ir = true
optimizer = true
optimizer_runs = 1000
evm_version = "osaka"
remappings = ["@openzeppelin/=node_modules/@openzeppelin/", "forge-std/=lib/forge-std/src/"]

[fuzz]
runs = 1000
seed = "0xdeadbeef"
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New directory to retain build and evidence")
    args = parser.parse_args()
    if args.output:
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix="degenerus-eth-ledgers-"))
    shutil.copytree(ROOT / "contracts", output / "contracts")
    (output / "proofsrc").mkdir()
    for name in TESTS:
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    for name in ("node_modules", "lib"):
        (output / name).symlink_to(ROOT / name, target_is_directory=True)
    (output / "foundry.toml").write_text(CONFIG)
    hashes = {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((output / "contracts").rglob("*.sol"))}
    hashes.update({name: hashlib.sha256((output / name).read_bytes()).hexdigest() for name in TESTS})
    (output / "source-sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
    commands = [
        ["halmos", "--contract", "EthLedgerProductionProof", "--loop", "2",
         "--panic-error-codes", "*", "--solver", "yices", "--solver-timeout-assertion", "60000",
         "--solver-threads", "2", "--json-output", "symbolic-results.json"],
        ["forge", "test", "--match-contract", "EthLedgerProductionReplay|EthLoanBootstrapTest",
         "--threads", "1", "-vv"],
    ]
    # The explicit isolated config is the verification configuration. Do not
    # accidentally inherit a caller's Foundry profile, output path or run limits.
    env = {k: v for k, v in os.environ.items() if not k.startswith("FOUNDRY_") and k != "DAPP_PROFILE"}
    env["PYTHONUNBUFFERED"] = "1"
    results = []
    print(f"Evidence: {output}", flush=True)
    for command, log_name in zip(commands, ("symbolic.log", "concrete.log")):
        with (output / log_name).open("w") as log:
            run = subprocess.run(command, cwd=output, env=env, stdout=log, stderr=subprocess.STDOUT)
        results.append(dict(command=command, log=log_name, exitcode=run.returncode))
        print(f"{log_name}: exit {run.returncode}", flush=True)
    metadata = dict(utc=datetime.now(timezone.utc).isoformat(), configuration=CONFIG,
                    commands=results, scope="local production helpers and whale-ticket bootstrap parity")
    (output / "run.json").write_text(json.dumps(metadata, indent=2) + "\n")
    raise SystemExit(0 if all(r["exitcode"] == 0 for r in results) else 1)


if __name__ == "__main__":
    main()
