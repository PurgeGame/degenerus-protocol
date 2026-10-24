#!/usr/bin/env python3
"""Check the original G7 seat envelope using paired native calibration outputs."""
import argparse
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--callees", type=Path, required=True)
    parser.add_argument("--shared-payouts", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    rows = {}
    for path in (args.engine, args.callees, args.shared_payouts):
        for case in json.loads(path.read_text())["cases"]:
            rows[case["label"]] = case
    source = Path(__file__).resolve().parents[2] / "contracts/libraries/MineFlipGasBounds.sol"
    bound = int(re.search(r"CRAPS_SEAT_GAS_MAX\s*=\s*([\d_]+)", source.read_text())[1].replace("_", ""))
    profiles = {}
    for profile in ("no-reservoir", "reservoir"):
        def gas(label):
            value = rows[label]["profiles"][profile]
            assert value["pass"], (label, profile, "native replay failed")
            return value["nativeFrameGas"]

        body = gas("craps-final-seat-stubbed-callees")
        engine = max(gas(f"craps-engine-ceiling-{i}") for i in range(8))
        fresh = max(gas(f"craps-real-callee-{i}") for i in range(4))
        callees = 4 * fresh + sum(gas(f"craps-real-callee-{i}") for i in (5, 6, 7))
        composite = body + engine + callees
        shared = body + engine + gas("craps-final-seat-real-payout-sequence")
        profiles[profile] = {
            "body": body, "engine": engine, "coldCallees": callees,
            "originalComponentEnvelope": composite,
            "sharedPayoutEnvelope": shared,
            "requiredWith20PercentMargin": (composite * 12 + 9) // 10,
            "bound": bound, "pass": composite * 12 <= bound * 10,
        }
    report = {"method": "Original G7 cold component sum; natural engine and cold-call overhead deliberately remain in the body. Engine overshoot is retained conservatively.", "profiles": profiles}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if all(p["pass"] for p in profiles.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
