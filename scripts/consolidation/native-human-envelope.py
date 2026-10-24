#!/usr/bin/env python3
"""Repeat G7's forced 100-box envelope using native Amsterdam gas schedules.

The production input is copied; two outcome knobs are inserted only in the
measurement build. All original RNG, accounting and external calls still run.
This is a conservative branch envelope, not a reachable random transcript.
Run compilation through the repository's shared forge-slot wrapper.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path

spec = importlib.util.spec_from_file_location("calibration", Path(__file__).with_name("native-calibration.py"))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
b = c.b
BOX = "contracts/modules/DegenerusGameBoxModule.sol"
ROLL_KNOB = 0x4C334F314C4F4F54
SCORE_KNOB = 0x4C334F31534F4F52


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def runtime_without_metadata(code):
    code = code.removeprefix("0x")
    return code[:-(int(code[-4:], 16) + 2) * 2]


def build(args, extra_changes=()):
    original = json.loads((args.production / "input.json").read_text())
    request = copy.deepcopy(original)
    changes = [
        ("contracts/modules/DegenerusGameLootboxModule.sol",
         "        uint256 roll = uint16(seed >> 40) % 20;",
         """        uint256 roll = uint16(seed >> 40) % 20;
        {
            uint256 f;
            assembly ("memory-safe") { f := sload(0x4c334f314c4f4f54) }
            if (f != 0) roll = allowEthSpin ? (f & 0xFF != 0 ? 19 : roll) : (f >> 8 != 0 ? (f >> 8) - 1 : roll);
        }"""),
        ("contracts/modules/DegenerusGameDegeneretteModule.sol",
         "        SpinResult memory spin = _rollSpin(seed, EntropyLib.hash2(RngTags.SPIN_HOUSE, seed), symbol, CURRENCY_ETH);\n        uint8 s = spin.score;",
         """        SpinResult memory spin = _rollSpin(seed, EntropyLib.hash2(RngTags.SPIN_HOUSE, seed), symbol, CURRENCY_ETH);
        {
            uint256 f;
            assembly ("memory-safe") { f := sload(0x4c334f31534f4f52) }
            if (f != 0 && spin.score < f) spin.score = uint8(f);
        }
        uint8 s = spin.score;""")]
    changes.extend(extra_changes)
    for source, old, new in changes:
        text = request["sources"][source]["content"]
        assert text.count(old) == 1, (source, "unique forcing site")
        request["sources"][source]["content"] = text.replace(old, new)
    request["settings"]["outputSelection"] = {BOX: {"DegenerusGameBoxModule": ["evm.deployedBytecode.object"]}}
    previous_input = args.out / "input.json"
    previous_output = args.out / "output.json"
    if previous_input.exists() and previous_output.exists() and json.loads(previous_input.read_text()) == request:
        cached = json.loads(previous_output.read_text())
        if not any(e["severity"] == "error" for e in cached.get("errors", [])):
            return cached["contracts"][BOX]["DegenerusGameBoxModule"]["evm"]["deployedBytecode"]["object"]
    if getattr(args, "reuse_build", False):
        raise RuntimeError("No matching successful measurement build; compilation requires forge-slot.sh")
    (args.out / "input.json").write_text(json.dumps(request))
    with (args.out / "input.json").open() as inp, (args.out / "output.json").open("w") as out:
        subprocess.run([str(args.solc), "--base-path", str(Path(__file__).resolve().parents[2]), "--include-path", str(Path(__file__).resolve().parents[2] / "node_modules"), "--standard-json"], stdin=inp, stdout=out, check=True)
    output = json.loads((args.out / "output.json").read_text())
    errors = [e for e in output.get("errors", []) if e["severity"] == "error"]
    assert not errors, errors
    manifest = {"productionInputSha256": hashlib.sha256((args.production / "input.json").read_bytes()).hexdigest(),
        "testOnlyChanges": [{"source": s, "old": o, "new": n} for s, o, n in changes],
        "testInputSha256": hashlib.sha256((args.out / "input.json").read_bytes()).hexdigest(),
        "method": "G7 Appendix B: direct roll 19, minimum ETH score 7, all twenty recirculation rolls; forcing SLOADs retained in measured gas"}
    (args.out / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return output["contracts"][BOX]["DegenerusGameBoxModule"]["evm"]["deployedBytecode"]["object"]


def accounts(dump):
    out = {}
    for address, value in c.dumped_accounts(dump).items():
        nonce = value.get("nonce", 0)
        out[address] = {"code": value.get("code", "0x"),
            "nonce": hex(int(nonce, 16) if isinstance(nonce, str) else nonce),
            "balance": hex(int(value.get("balance", "0x0"), 16)),
            "state": {b.word(int(k, 16)): b.word(int(v, 16)) for k, v in value.get("storage", {}).items()}}
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--production", type=Path, required=True)
    p.add_argument("--fixtures", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--rpc", required=True)
    p.add_argument("--boxes", type=int, choices=[20, 100], default=100)
    p.add_argument("--prefix", default="human-forced-prestate-")
    p.add_argument("--reuse-build", action="store_true", help="Replay only; fail rather than invoke solc if the exact build is absent")
    p.add_argument("--solc", type=Path, default=Path.home() / ".svm/0.8.38/solc-0.8.38")
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    assert int(b.rpc(args.rpc, "eth_chainId", []), 16) in (1337, 31337)
    variant = build(args)
    original = json.loads((args.production / "output.json").read_text())["contracts"][BOX]["DegenerusGameBoxModule"]["evm"]["deployedBytecode"]["object"]
    source = json.loads((args.production / "input.json").read_text())["sources"]["contracts/ContractAddresses.sol"]["content"]
    address = re.search(r"GAME_LOOTBOX_MODULE\s*=\s*address\((0x[0-9A-Fa-f]{40})\)", source)[1].lower()
    spin_topic = b.topic("BoxSpin(uint32,uint64,uint256,uint256,uint256)")
    rows = []
    files = sorted(args.fixtures.glob(args.prefix + "*.call.json"))
    assert len(files) == 4, "all four original order shapes required"
    output = {"client": b.rpc(args.rpc, "web3_clientVersion", []), "cases": rows,
        "boxes": args.boxes, "bound": 3_200_000 + args.boxes * 125_000,
        "acceptedException": "The original 100-box atomic order is the documented exception to the 10M checkpoint target."}
    for file in files:
        call = json.loads(file.read_text())
        label = file.name.removesuffix(".call.json")
        complete = file.with_name(label + ".complete.json")
        state = accounts(json.loads(complete.read_text()))
        # The recorder additionally materializes cold values accessed naturally.
        # Merge only values consistent with the actual pre-call complete dump.
        for addr, account in accounts(json.loads(file.with_name(label + ".state.json").read_text())).items():
            if addr not in state:
                state[addr] = account
                continue
            target = state[addr]
            assert target["code"] in ("0x", account["code"]) or account["code"] == "0x", (addr, "code disagreement")
            if account["code"] != "0x": target["code"] = account["code"]
            for slot, value in account["state"].items():
                assert slot not in target["state"] or int(target["state"][slot], 16) == int(value, 16), (addr, slot)
                target["state"][slot] = value
        assert runtime_without_metadata(state[address]["code"]) == runtime_without_metadata(original), "fixture must contain final production Box runtime"
        state[address]["code"] = "0x" + variant
        host = call["to"].lower()
        bo = {"time": hex(call["timestamp"]), "baseFeePerGas": "0x0"}
        if call.get("number"): bo["number"] = hex(call["number"])
        for roll in range(20):
            state[host]["state"][b.word(ROLL_KNOB)] = b.word(1 + ((roll + 1) << 8))
            state[host]["state"][b.word(SCORE_KNOB)] = b.word(7)
            row = {"label": label, "recirculationRoll": roll, "prestateSha256": digest(state),
                "completeDumpSha256": hashlib.sha256(complete.read_bytes()).hexdigest(), "profiles": {}}
            fingerprints = []
            for profile, limit in [("no-reservoir", 16_777_216), ("reservoir", 500_000_000)]:
                try:
                    tx = {"from": call["from"], "to": call["to"], "data": call["input"], "gas": hex(limit), "gasPrice": "0x0"}
                    opts = {"stateOverrides": state, "blockOverrides": bo, "timeout": "60s"}
                    block = b.rpc(args.rpc, "eth_simulateV1", [{"blockStateCalls": [{"blockOverrides": bo,
                        "stateOverrides": state, "calls": [tx]}], "validation": False}, "0x0"])[0]
                    result = block["calls"][0]
                    assert result["status"] == "0x1" and int(result["returnData"], 16) == args.boxes, result.get("error", result)
                    logs = c.events(result["logs"])
                    spins = [[int(e[2][i:i + 64], 16) for i in range(2, len(e[2]), 64)]
                        for e in logs if e[0] == host and e[1] and e[1][0] == spin_topic]
                    eth = [s for s in spins if ((s[0] >> 60) & 7) == 2]
                    assert len(eth) == args.boxes, ("every direct box takes the forced ETH spin", len(eth))
                    assert all(((s[1] >> 64) & 255) >= 7 and s[2] > s[3] > 0 for s in eth), "every ETH spin awards and recirculates"
                    observed = b.rpc(args.rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer="prestateTracer")])
                    missing = c.missing_prestate(observed, state, complete=True)
                    assert not missing, ("prestate", missing[:8])
                    delta = b.rpc(args.rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer="prestateTracer", tracerConfig={"diffMode": True})])
                    meter = b.rpc(args.rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer=c.gas_meter.METER)])
                    measured = c.gas_meter.measured_gas(meter, limit)
                    gas = measured["grossFrameUpperBound"] if profile == "no-reservoir" else measured["frameExecutionBudgetConsumed"]
                    fingerprint = digest({"logs": logs, "state": c.apply_delta(state, delta), "return": result["returnData"]})
                    fingerprints.append(fingerprint)
                    assert gas <= output["bound"], ("whole-order admission bound", gas, output["bound"])
                    row["profiles"][profile] = {"pass": True, "gas": gas, "nativeGasMeter": measured,
                        "ethSpins": len(eth), "allSpinEvents": len(spins), "eventCount": len(logs),
                        "completeAccessedPrestate": True, "transcriptAndPoststateSha256": fingerprint}
                except Exception as error:
                    row["profiles"][profile] = {"pass": False, "error": str(error)[:1500]}
            row["sameOutcomeBothProfiles"] = len(fingerprints) == 2 and fingerprints[0] == fingerprints[1]
            rows.append(row)
            (args.out / "paired.json").write_text(json.dumps(output, indent=2) + "\n")
            print(label, roll, {p: r["pass"] for p, r in row["profiles"].items()}, flush=True)
    assert all(r["sameOutcomeBothProfiles"] and all(p["pass"] for p in r["profiles"].values()) for r in rows)


if __name__ == "__main__":
    main()
