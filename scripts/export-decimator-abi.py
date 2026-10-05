#!/usr/bin/env python3
"""Export the Decimator client/replay ABI from freshly compiled Foundry artifacts."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/abi/Decimator.json"
MEMBERS = {
    "FLIP": {"decimatorBurn", "coinDecimatorBurn", "autoDecimatorBurn", "DecimatorBurn"},
    "DegenerusGame": {"recordDecBurn", "runDecimatorJackpot", "decWindow"},
    "DegenerusGameDecimatorModule": {"runDecimatorJackpotAwards", "runDecimatorWork", "DecBurnRecorded"},
    "DegenerusGameLens": set(),
}


def render():
    contracts = {}
    for name, names in MEMBERS.items():
        artifact = ROOT / "forge-out" / f"{name}.sol" / f"{name}.json"
        abi = json.loads(artifact.read_text())["abi"]
        selected = [entry for entry in abi if entry.get("name") in names
                    or (name == "DegenerusGameLens" and entry.get("name", "").startswith("dec"))
                    or (name == "DegenerusGameDecimatorModule" and entry.get("name", "").startswith("Decimator"))]
        if not selected:
            raise ValueError(f"No Decimator ABI entries found for {name}; build first")
        contracts[name] = selected
    return json.dumps({"format": 1, "contracts": contracts}, indent=2) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the checked-in export differs")
    args = parser.parse_args()
    output = render()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != output:
            raise SystemExit("Decimator ABI drift: build, then run scripts/export-decimator-abi.py")
        print("Decimator ABI matches compiled artifacts")
    else:
        OUTPUT.write_text(output)
        print(f"Wrote {OUTPUT.relative_to(ROOT)}")
