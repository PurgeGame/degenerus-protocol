#!/usr/bin/env python3
"""Rebuild final gas comparison from the retained Foundry logs and Sample events."""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SAMPLE = "0x177e831c99e0030b465308127c68d23b57a2afd20c3e2f46331beb220f5f6355"


def samples(name):
    result = {}
    for suite in json.loads((HERE / name).read_text()).values():
        for test, execution in suite["test_results"].items():
            assert execution["status"] == "Success", test
            for event in execution["logs"]:
                if event["topics"][0] != SAMPLE:
                    continue
                data = bytes.fromhex(event["data"][2:])
                head = [int.from_bytes(data[i:i + 32], "big") for i in range(0, 160, 32)]
                offset, gross, refund, charged, writes = head
                if refund >= 1 << 255:
                    refund -= 1 << 256
                size = int.from_bytes(data[offset:offset + 32], "big")
                key = data[offset + 32:offset + 32 + size].decode()
                result[key] = dict(gross=gross, refund_counter=refund, charged=charged,
                                   target_write_slots=writes)
    return result


def metrics(name):
    return {k: int(v) for k, v in re.findall(r"^  ([\w-]+): (\d+)$", (HERE / name).read_text(), re.M)}


def compare(before, after):
    assert before.keys() == after.keys(), (before.keys() - after.keys(), after.keys() - before.keys())
    return {k: dict(baseline=before[k], candidate=after[k], saved=before[k] - after[k],
                    percent_saved=round(100 * (before[k] - after[k]) / before[k], 4)) for k in before}


baseline = samples("baseline-lifecycle-final.json")
candidate = samples("candidate-lifecycle-final.json")
result = {
    "method": "Isolated production calls, solc 0.8.34, viaIR, optimizer 1000, Osaka. "
              "Lifecycle Sample charged = execution gas minus capped positive refund. "
              "Intrinsic gas and unmeasured fixture/RNG setup excluded. Range metrics use "
              "snapshotGasLastCall for complete public calls, not a synthetic storage loop. "
              "Write slots cover the Sample target contract only, not every callee.",
    "metrics": compare(metrics("baseline-lifecycle-final-lifecycle.log"), metrics("final-c-lifecycle.log")),
    "samples": {k: {"baseline": baseline[k], "candidate": candidate[k]} for k in baseline},
}
assert baseline.keys() == candidate.keys()
(HERE / "final-gas-comparison.json").write_text(json.dumps(result, indent=2) + "\n")
for key, value in result["metrics"].items():
    if "lifecycle" in key or key.startswith(("dec-", "claim-", "deity-", "lazy-")):
        print(f"| {key} | {value['baseline']:,} | {value['candidate']:,} | {value['saved']:,} | {value['percent_saved']:.2f}% |")
