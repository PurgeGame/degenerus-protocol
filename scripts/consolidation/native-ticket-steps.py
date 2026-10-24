#!/usr/bin/env python3
"""Repeat RoundDrainChunkGas's cold admission/marginal probes on Amsterdam.

Each trial starts from the same exported prestate. The original first complete
solo event, changed round counter, or progress bit defines the admitted step.
This is separate from exact replay: a recorder-warmed Osaka allowance is not a
native admission boundary. No execution outcome from a search trial is accepted
as calibration evidence until its accessed prestate has been checked.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("native_calibration", Path(__file__).with_name("native-calibration.py"))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
b = c.b


def run(rpc, file, profile, schedule="amsterdam"):
    call = json.loads(file.read_text())
    label = file.name.removesuffix(".call.json")
    dump = json.loads(file.with_name(label + ".state.json").read_text())
    state = {}
    for address, value in c.dumped_accounts(dump).items():
        nonce = value.get("nonce", 0)
        state[address] = {"code": value.get("code", "0x"),
            "nonce": hex(int(nonce, 16) if isinstance(nonce, str) else nonce),
            "balance": hex(int(value.get("balance", "0x0"), 16)),
            "state": {b.word(int(k, 16)): b.word(int(v, 16)) for k, v in value.get("storage", {}).items()}}
    limit = 16_777_216 if profile == "no-reservoir" else 500_000_000
    tx = {"from": call["from"], "to": call["to"], "data": call["input"], "gas": hex(limit), "gasPrice": "0x0"}
    bo = {"time": hex(call["timestamp"]), "baseFeePerGas": "0x0"}
    if call.get("number"): bo["number"] = hex(call["number"])
    opts = {"stateOverrides": state, "blockOverrides": bo, "timeout": "60s"}
    target = call["to"].lower()
    step = int(label.split("-")[2])
    # Slot and byte offset are independently pinned by GameSlots/storage-layout.
    round_slot = b.word(12)
    before_round = (int(state[target]["state"].get(round_slot, "0x0"), 16) >> 96) & 0xffffffff
    expected = c.events(c.json_value(call["expectedLogs"]))
    first = next((e for e in expected if e[0] == target and e[1] and e[1][0] == c.TRAITS_GENERATED), None)
    cache = {}

    def trial(allowance, measured=False):
        tx["data"] = call["input"][:74] + f"{allowance:064x}" + call["input"][138:]
        if allowance not in cache:
            block = b.rpc(rpc, "eth_simulateV1", [{"blockStateCalls": [{"blockOverrides": bo,
                "stateOverrides": state, "calls": [tx]}], "validation": False}, "0x0"])[0]
            result = block["calls"][0]
            assert result["status"] == "0x1", (label, profile, allowance, result.get("error"))
            logs = c.events(result["logs"])
            solo = [e for e in logs if e[0] == target and e[1] and e[1][0] == c.TRAITS_GENERATED]
            assert all(int(e[2][-64:], 16) <= 32 for e in solo), "solo entry cap"
            delta = b.rpc(rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer="prestateTracer", tracerConfig={"diffMode": True})])
            post = c.apply_delta(state, delta)
            after_round = (int(post[target]["state"].get(round_slot, "0x0"), 16) >> 96) & 0xffffffff
            hit = after_round != before_round if step == 0 else (
                bool(c.result_words(result["returnData"])[0]) if step == 2 else bool(solo and first and solo[0] == first))
            cache[allowance] = {"allowance": allowance, "hit": hit, "roundBefore": before_round,
                "roundAfter": after_round, "soloRuns": len(solo), "firstSoloEntries": int(solo[0][2][-64:], 16) if solo else 0,
                "result": result["returnData"], "logsSha256": hashlib.sha256(json.dumps(logs, sort_keys=True).encode()).hexdigest(),
                "poststateSha256": hashlib.sha256(json.dumps(post, sort_keys=True).encode()).hexdigest()}
        row = cache[allowance]
        if measured and "gas" not in row:
            observed = b.rpc(rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer="prestateTracer")])
            missing = c.missing_prestate(observed, state)
            assert not missing, (label, profile, allowance, "missing prestate", missing[:8])
            meter = b.rpc(rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer=c.gas_meter.METER)])
            row["nativeGasMeter"] = c.gas_meter.measured_gas(meter, limit, schedule=schedule)
            row["gas"] = row["nativeGasMeter"]["grossFrameUpperBound" if profile == "no-reservoir" else "frameExecutionBudgetConsumed"]
            row["completeAccessedPrestate"] = True
        return row

    out = {"profile": profile, "step": step, "fixture": str(file),
        "fixtureSha256": hashlib.sha256(file.read_bytes()).hexdigest(), "method": "original cold admission binary search, tolerance 100 gas"}
    if (step == 1 and first is None) or (step == 0 and call["workerAllowance"] == 382_000):
        # Original selection/refusal pair has no solo event. Measure the same
        # allowances directly; its control persistence belongs to TICKET_TAIL.
        out["originalAllowance"] = trial(call["workerAllowance"], True)
    else:
        lo, hi = 372_000, 16_777_216
        assert not trial(lo)["hit"], "lower search endpoint already admits step"
        assert trial(hi)["hit"], "original first step absent at upper endpoint"
        while hi - lo > 100:
            mid = (hi + lo) // 2
            if trial(mid)["hit"]: hi = mid
            else: lo = mid
        out["admitted"] = trial(hi, True)
        out["refused"] = trial(lo, True)
        out["marginalGas"] = out["admitted"]["gas"] - out["refused"]["gas"]
        out["checkpointUnder10M"] = hi < 10_000_000 and out["admitted"]["gas"] < 10_000_000
        out["withinReservation"] = out["admitted"]["gas"] <= hi + 50_000
        assert out["checkpointUnder10M"] and out["withinReservation"], out
        if step == 0:
            out["selectOnly"] = trial(382_000, True)
            out["reloadAndPrefixGas"] = out["refused"]["gas"] - out["selectOnly"]["gas"]
    out["pass"] = True
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schedule", choices=("osaka", "amsterdam"), default="amsterdam")
    parser.add_argument("--rpc", required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    assert int(b.rpc(args.rpc, "eth_chainId", []), 16) in (1337, 31337), "local replay only"
    output = {"client": b.rpc(args.rpc, "web3_clientVersion", []), "cases": []}
    for file in sorted(args.fixtures.glob("ticket-*.call.json")):
        row = {"label": file.name.removesuffix(".call.json"), "profiles": {}}
        for profile in ("no-reservoir", "reservoir"):
            try: row["profiles"][profile] = run(args.rpc, file, profile, args.schedule)
            except Exception as error: row["profiles"][profile] = {"pass": False, "error": str(error)}
        output["cases"].append(row)
        temp = args.output.with_suffix(".tmp")
        temp.write_text(json.dumps(output, indent=2) + "\n")
        temp.replace(args.output)
        print(row["label"], {p: v["pass"] for p, v in row["profiles"].items()}, flush=True)
    assert all(v["pass"] for r in output["cases"] for v in r["profiles"].values()), "native ticket probe failed"


if __name__ == "__main__": main()
