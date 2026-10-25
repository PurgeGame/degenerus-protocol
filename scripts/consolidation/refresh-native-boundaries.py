#!/usr/bin/env python3
"""Rebind reviewed rollback-event expectations to freshly deployed test probes.

Production callee/selector/gas boundaries and rollback selectors are preserved.
Only the fixture probe address and the unpaid measured-gas field may differ.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--baseline", type=Path, required=True)
    p.add_argument("--fixtures", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    boundaries = json.loads(a.baseline.read_text())
    assert set(boundaries) == {f.stem for f in a.fixtures.glob("*.call.json")}
    changes = []
    for name, boundary in boundaries.items():
        if "revertedWorker" not in boundary or boundary.get("wholeStepRollback"):
            continue
        expected = boundary["committedLogs"]
        assert len(expected) == 1
        file = a.fixtures / (name + ".json")
        call = json.loads(file.read_text())
        actual = json.loads(call["expectedLogs"])[-1]
        if actual == expected[0]:
            continue
        # These five reviewed cases call Game.mineRun through NativeFailureProbe.
        assert name in {"game-0-1.call", "game-0-2.call", "game-0-5.call", "game-0-9.call", "game-0-10.call"}, name
        assert call["input"].startswith("0x9e976db1"), "NativeFailureProbe.invoke(address,bytes,uint256)"
        emitter = "0x" + call["input"][34:74]
        old = expected[0]
        assert actual["address"].lower() == old["address"].lower() == emitter.lower()
        assert len(actual["topics"]) == len(old["topics"]) == 2
        assert actual["topics"][0] == old["topics"][0] == "0x262e948990ec5a9d0344efa68099b0b216cc808ea8d62d5607e3ef9866b1a8ec"
        assert actual["topics"][1].lower() == "0x" + call["to"][2:].lower().rjust(64, "0")
        def words(event):
            raw = event["data"].removeprefix("0x")
            assert len(raw) == 192
            return [int(raw[i:i + 64], 16) for i in range(0, 192, 64)]
        before, after = words(old), words(actual)
        assert before[0] == after[0] == 14 and before[2] == after[2] == 0
        assert before[1] > 0 and after[1] > 0
        boundary["committedLogs"] = [copy.deepcopy(actual)]
        changes.append({"fixture": name, "previous": old, "current": actual,
            "reason": "Caller is independently derived from the fresh probe target; unpaid measured-gas field is schedule-dependent and normalized by native-opt-failures."})
    a.output.write_text(json.dumps(boundaries, indent=2) + "\n")
    a.output.with_suffix(".changes.json").write_text(json.dumps({
        "baselineSha256": hashlib.sha256(a.baseline.read_bytes()).hexdigest(),
        "changes": changes}, indent=2) + "\n")
    print(f"Preserved {len(boundaries)} reviewed boundaries; rebound {len(changes)} probe events")


if __name__ == "__main__":
    main()
