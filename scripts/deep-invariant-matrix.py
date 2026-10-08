#!/usr/bin/env python3
"""Partition expensive deep suites without dropping undiscovered/inherited tests."""

import json
from pathlib import Path
import re


HEAVY = {
    "CrapsConservation.inv.t.sol",
    "CrapsRealWiringConservation.inv.t.sol",
    "CrapsRngSeal.inv.t.sol",
}


def matrix(root):
    files = sorted(root.glob("test/fuzz/invariant/**/*.sol"))
    if not files:
        raise ValueError("No invariant sources discovered")
    result = []
    for path in files:
        source = path.relative_to(root).as_posix()
        if path.name not in HEAVY:
            result.append({"file": source, "label": "all", "match": ".*", "exclude": "^$"})
            continue
        # This is only a scheduling hint, not the authority on which tests exist.
        # The complementary job below retains EVERY test not selected by name,
        # including inherited properties, new tests and imported helper tests.
        text = re.sub(r"/\*.*?\*/|//[^\n]*", "", path.read_text(), flags=re.S)
        names = sorted(set(re.findall(r"^\s*function\s+(invariant[A-Za-z0-9_$]*)\s*\(", text, re.M)))
        if not names:
            raise ValueError(f"No named invariant properties in heavy suite {source}")
        for name in names:
            result.append({"file": source, "label": name,
                           "match": "^" + re.escape(name) + r"(?:\(|$)", "exclude": "^$"})
        exclude = "^(?:" + "|".join(map(re.escape, names)) + r")(?:\(|$)"
        result.append({"file": source, "label": "other-tests", "match": ".*", "exclude": exclude})
    if len(result) > 256:
        raise ValueError("Deep matrix exceeds the CI matrix limit; repartition without omitting tests")
    return result


if __name__ == "__main__":
    print(json.dumps(matrix(Path(__file__).resolve().parents[1]), separators=(",", ":")))
