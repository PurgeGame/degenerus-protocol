#!/usr/bin/env python3
"""Partition expensive deep suites without dropping undiscovered/inherited tests."""

import argparse
import hashlib
import json
from pathlib import Path
import re


HEAVY = {
    "CrapsConservation.inv.t.sol",
    "CrapsRealWiringConservation.inv.t.sol",
    "CrapsRngSeal.inv.t.sol",
}
ADVANCE_FILE = "AdvanceLiveness.inv.t.sol"
ADVANCE_PROPERTY = "invariant_advanceLiveness"
ADVANCE_PARTITIONS = 10
ADVANCE_RUNS = 100
ADVANCE_DEPTH = 256
ADVANCE_PROFILE = "deep_advance_ci"


def partition_seed(run_id, run_attempt, partition):
    """Keep existing seeds except for the independently seeded Advance partitions."""
    if not run_id or not run_attempt:
        raise ValueError("Run identity and attempt are required")
    if partition == "":
        return run_id
    if partition not in {str(i) for i in range(ADVANCE_PARTITIONS)}:
        raise ValueError("Unknown AdvanceLiveness seed partition")
    identity = f"deep-invariants:AdvanceLiveness:{run_id}:{run_attempt}:{partition}"
    return "0x" + hashlib.sha256(identity.encode()).hexdigest()


def matrix(root):
    files = sorted(root.glob("test/fuzz/invariant/**/*.sol"))
    if not files:
        raise ValueError("No invariant sources discovered")
    result = []
    for path in files:
        source = path.relative_to(root).as_posix()
        common = {"file": source, "profile": "deep", "seed_partition": ""}
        if path.name == ADVANCE_FILE:
            text = re.sub(r"/\*.*?\*/|//[^\n]*", "", path.read_text(), flags=re.S)
            if not re.search(r"\bfunction\s+" + ADVANCE_PROPERTY + r"\s*\(", text):
                raise ValueError(f"Missing partitioned property in {source}")
            target = "^" + ADVANCE_PROPERTY + r"(?:\(|$)"
            for partition in range(ADVANCE_PARTITIONS):
                result.append({**common, "label": f"advance-{partition:02d}",
                               "match": target, "exclude": "^$", "profile": ADVANCE_PROFILE,
                               "seed_partition": str(partition), "runs": ADVANCE_RUNS,
                               "depth": ADVANCE_DEPTH})
            # Every other present or future test still runs once at the usual
            # deep budget, including inherited properties and imported helpers.
            result.append({**common, "label": "other-tests", "match": ".*", "exclude": target})
            continue
        if path.name not in HEAVY:
            result.append({**common, "label": "all", "match": ".*", "exclude": "^$"})
            continue
        # This is only a scheduling hint, not the authority on which tests exist.
        # The complementary job below retains EVERY test not selected by name,
        # including inherited properties, new tests and imported helper tests.
        text = re.sub(r"/\*.*?\*/|//[^\n]*", "", path.read_text(), flags=re.S)
        names = sorted(set(re.findall(r"^\s*function\s+(invariant[A-Za-z0-9_$]*)\s*\(", text, re.M)))
        if not names:
            raise ValueError(f"No named invariant properties in heavy suite {source}")
        for name in names:
            result.append({**common, "label": name,
                           "match": "^" + re.escape(name) + r"(?:\(|$)", "exclude": "^$"})
        exclude = "^(?:" + "|".join(map(re.escape, names)) + r")(?:\(|$)"
        result.append({**common, "label": "other-tests", "match": ".*", "exclude": exclude})
    if len(result) > 256:
        raise ValueError("Deep matrix exceeds the CI matrix limit; repartition without omitting tests")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", nargs=3, metavar=("RUN_ID", "RUN_ATTEMPT", "PARTITION"))
    args = parser.parse_args()
    if args.seed is not None:
        print(partition_seed(*args.seed))
    else:
        print(json.dumps(matrix(Path(__file__).resolve().parents[1]), separators=(",", ":")))
