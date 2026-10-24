#!/usr/bin/env python3
"""Replay fixed-budget fork fixtures at their exact block number on native Amsterdam.

eth_simulateV1 cannot bridge millions of blocks from a local genesis. Trace calls
support the original block number directly. A small opcode tracer measures the
root execution budget before refunds; receipt gas plus the refund cap gives a
conservative upper bound on gross gas when no state reservoir is supplied.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("calibration", Path(__file__).with_name("native-calibration.py"))
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)

meter_spec = importlib.util.spec_from_file_location("native_meter", Path(__file__).with_name("native-gas-meter.py"))
gas_meter = importlib.util.module_from_spec(meter_spec)
meter_spec.loader.exec_module(gas_meter)
METER, measured_gas = gas_meter.METER, gas_meter.measured_gas

def ordered_logs(frame):
    """callTracer log.position counts preceding child calls in the same frame."""
    if "error" in frame:
        return []
    out = []
    children = frame.get("calls", [])
    for position in range(len(children) + 1):
        out.extend(log for log in frame.get("logs", []) if int(str(log["position"]), 0) == position)
        if position < len(children):
            out.extend(ordered_logs(children[position]))
    return out




def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rpc", required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    rpc = lambda method, params: n.b.rpc(args.rpc, method, params)
    assert int(rpc("eth_chainId", []), 16) in (1337, 31337), "local replay only"
    rows = []
    for file in sorted(args.fixtures.glob("*.call.json")):
        call = json.loads(file.read_text())
        dump_file = file.with_name(file.name.replace(".call.json", ".state.json"))
        dump = json.loads(dump_file.read_text())
        state = {}
        for address, value in dump.get("accounts", dump).items():
            nonce = value.get("nonce", 0)
            state[address.lower()] = {"code": value.get("code", "0x"),
                "nonce": hex(int(nonce, 16) if isinstance(nonce, str) else nonce),
                "balance": hex(int(value.get("balance", "0x0"), 16)),
                "state": {n.b.word(int(k, 16)): n.b.word(int(v, 16)) for k, v in value.get("storage", {}).items()}}
        overrides = {"time": hex(call["timestamp"]), "number": hex(call["number"]),
                     "baseFeePerGas": hex(call.get("baseFee", 0))}
        row = {"label": file.name.removesuffix(".call.json"), "name": call.get("budgetName"),
               "fixtureSha256": hashlib.sha256(file.read_bytes()).hexdigest(),
               "prestateSha256": hashlib.sha256(dump_file.read_bytes()).hexdigest(),
               "blockOverrides": overrides, "budget": call.get("fixedCalleeBudget"),
               "enforceBudget": call.get("enforceBudget", False), "profiles": {}}
        for profile, limit in [("no-reservoir", 16_777_216), ("reservoir", 500_000_000)]:
            tx = {"from": call["from"], "to": call["to"], "data": call["input"], "gas": hex(limit),
                  "gasPrice": hex(call.get("baseFee", 0)), "value": hex(int(str(call.get("value", 0)), 0))}
            def trace(tracer, config=None):
                opts = {"blockOverrides": overrides, "stateOverrides": state, "tracer": tracer, "timeout": "60s"}
                if config is not None: opts["tracerConfig"] = config
                return rpc("debug_traceCall", [tx, "0x0", opts])
            try:
                observed = trace("prestateTracer")
                missing = n.missing_prestate(observed, state)
                calls = trace("callTracer", {"withLog": True})
                meter = trace(METER)
                gas = measured_gas(meter, limit)
                logs = ordered_logs(calls)
                same = ("error" not in calls and calls.get("output", "0x") == call["expectedReturn"]
                        and n.events(logs) == n.events(n.json_value(call["expectedLogs"])))
                delta = trace("prestateTracer", {"diffMode": True})
                mismatches = n.check_storage(n.json_value(call.get("expectedStorage", {})), state, delta)
                cost = gas["grossFrameUpperBound"] if profile == "no-reservoir" else gas["frameExecutionBudgetConsumed"]
                budget_ok = not row["enforceBudget"] or cost <= row["budget"]
                row["profiles"][profile] = dict(gas, meter=meter, trace=calls, sameReturnAndOrderedLogs=same,
                    missingPrestate=missing, storageMismatches=mismatches, budgetPass=budget_ok,
                    **{"pass": same and not missing and not mismatches and budget_ok})
            except Exception as error:
                row["profiles"][profile] = {"pass": False, "error": str(error)}
        rows.append(row)
        print(row["label"], {k: v["pass"] for k, v in row["profiles"].items()}, flush=True)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({"client": rpc("web3_clientVersion", []),
            "method": "Exact fork block number, cold prestate, returns, ordered logs and poststorage. No-reservoir budget uses conservative gross frame gas before refunds; reservoir budget uses measured root execution-budget consumption. Receipt gas and the gross upper bound are reported separately.",
            "cases": rows}, indent=2) + "\n")
    assert rows and all(v["pass"] for r in rows for v in r["profiles"].values()), "native fork budgets require review"


if __name__ == "__main__":
    main()
