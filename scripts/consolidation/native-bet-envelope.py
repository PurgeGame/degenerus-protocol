#!/usr/bin/env python3
"""Repeat the original forced winning-bet/recirculation gas envelope natively."""
import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path

spec = importlib.util.spec_from_file_location("human", Path(__file__).with_name("native-human-envelope.py"))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
c, b = h.c, h.b


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--production", type=Path, required=True)
    p.add_argument("--fixtures", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--rpc", required=True)
    p.add_argument("--reuse-build", action="store_true", help="Replay only; require an exact successful cached build")
    p.add_argument("--solc", type=Path, default=Path.home() / ".svm/0.8.38/solc-0.8.38")
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    assert int(b.rpc(a.rpc, "eth_chainId", []), 16) in (1337, 31337)
    source = "contracts/modules/DegenerusGameDegeneretteModule.sol"
    manual = "            SpinResult memory spin = _rollBetSpin(rngWord, index, c.symbol, spinIdx, c.currency);"
    survival = "            if (EntropyLib.hash3(RngTags.BET_SURVIVAL, rngWord, betId) & 1 == 1) {"
    variant = h.build(a, [
        (source, manual, manual + """
            {
                uint256 f;
                assembly ("memory-safe") { f := sload(0x4c334f31534f4f52) }
                if (f != 0 && spin.score < f) spin.score = uint8(f);
            }"""),
        (source, survival, """            uint256 survivalWord = EntropyLib.hash3(RngTags.BET_SURVIVAL, rngWord, betId);
            {
                uint256 f;
                assembly ("memory-safe") { f := sload(0x4c334f31534f4f52) }
                if (f != 0) survivalWord |= 1;
            }
            if (survivalWord & 1 == 1) {""")])
    original = json.loads((a.production / "output.json").read_text())["contracts"][h.BOX]["DegenerusGameBoxModule"]["evm"]["deployedBytecode"]["object"]
    pins = json.loads((a.production / "input.json").read_text())["sources"]["contracts/ContractAddresses.sol"]["content"]
    box = re.search(r"GAME_LOOTBOX_MODULE\s*=\s*address\((0x[0-9A-Fa-f]{40})\)", pins)[1].lower()
    resolved_topic = b.topic("DegeneretteResolved(uint32,uint32,uint64,uint256,uint32,bytes)")
    output = {"client": b.rpc(a.rpc, "web3_clientVersion", []), "cases": [],
        "method": "Original forced winning-bet branch envelope: preserve all RNG computation; force every score to at least seven/eight, FLIP survival and every ETH win-box branch. This artificial envelope is not a reachable RNG transcript."}
    files = sorted(a.fixtures.glob("bet-forced-prestate-*.call.json"))
    assert len(files) == 6
    for file in files:
        call = json.loads(file.read_text()); label = file.name.removesuffix(".call.json")
        dump = file.with_name(label + ".complete.json")
        state = h.accounts(json.loads(dump.read_text()))
        for addr, account in h.accounts(json.loads(file.with_name(label + ".state.json").read_text())).items():
            if addr not in state:
                state[addr] = account
                continue
            target = state[addr]
            assert target["code"] in ("0x", account["code"]) or account["code"] == "0x"
            if account["code"] != "0x": target["code"] = account["code"]
            for slot, value in account["state"].items():
                assert slot not in target["state"] or int(target["state"][slot], 16) == int(value, 16)
                target["state"][slot] = value
        assert h.runtime_without_metadata(state[box]["code"]) == h.runtime_without_metadata(original)
        state[box]["code"] = "0x" + variant
        host = call["to"].lower()
        bo = {"time": hex(call["timestamp"]), "baseFeePerGas": "0x0"}
        if call.get("number"): bo["number"] = hex(call["number"])
        eth = call["currency"] == 0; spins = call["spins"]
        bound = (1_200_000 + 14_000 * spins if eth else 400_000 + 5_000 * spins) + 150_000
        if call["record"]: bound += 350_000
        for score in (7, 8):
            for roll in (range(20) if eth else [0]):
                state[host]["state"][b.word(h.ROLL_KNOB)] = b.word(1 + ((roll + 1) << 8))
                state[host]["state"][b.word(h.SCORE_KNOB)] = b.word(score)
                row = {"label": label, "currency": call["currency"], "spins": spins, "stake": call["stake"],
                    "record": call["record"], "scoreFloor": score, "recirculationRoll": roll, "boundWithTail": bound,
                    "prestateSha256": h.digest(state), "completeDumpSha256": hashlib.sha256(dump.read_bytes()).hexdigest(), "profiles": {}}
                fingerprints = []
                for profile, limit in [("no-reservoir", 16_777_216), ("reservoir", 500_000_000)]:
                    try:
                        tx = {"from": call["from"], "to": call["to"], "data": call["input"], "gas": hex(limit), "gasPrice": "0x0"}
                        opts = {"stateOverrides": state, "blockOverrides": bo, "timeout": "60s"}
                        block = b.rpc(a.rpc, "eth_simulateV1", [{"blockStateCalls": [{"blockOverrides": bo,
                            "stateOverrides": state, "calls": [tx]}], "validation": False}, "0x0"])[0]
                        result = block["calls"][0]
                        assert result["status"] == "0x1", result.get("error")
                        words = c.result_words(result["returnData"])
                        assert words[:3] == [1, 1, 1], ("one whole bet completed", words)
                        logs = c.events(result["logs"])
                        resolved = [e for e in logs if e[0] == host and e[1][0] == resolved_topic]
                        assert len(resolved) == 1
                        raw = bytes.fromhex(resolved[0][2][2:])
                        assert int.from_bytes(raw[:32]) > 0, "positive winning payout"
                        offset = int.from_bytes(raw[64:96]); size = int.from_bytes(raw[offset:offset + 32])
                        packed = raw[offset + 32:offset + 32 + size]
                        assert size == spins * 5 and all((packed[i * 5 + 4] & 15) >= score for i in range(spins)), "all forced spins ran"
                        observed = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer="prestateTracer")])
                        missing = c.missing_prestate(observed, state, complete=True)
                        assert not missing, ("prestate", missing[:8])
                        delta = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer="prestateTracer", tracerConfig={"diffMode": True})])
                        meter = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer=c.gas_meter.METER)])
                        gas = c.gas_meter.measured_gas(meter, limit)
                        frame = gas["grossFrameUpperBound"] if profile == "no-reservoir" else gas["frameExecutionBudgetConsumed"]
                        fingerprint = h.digest({"logs": logs, "state": c.apply_delta(state, delta), "return": result["returnData"]})
                        fingerprints.append(fingerprint)
                        row["profiles"][profile] = {"pass": frame <= bound, "gas": frame, "nativeGasMeter": gas,
                            "completeAccessedPrestate": True, "transcriptAndPoststateSha256": fingerprint, "measuredHeadroom": bound - frame}
                    except Exception as error:
                        row["profiles"][profile] = {"pass": False, "error": str(error)[:1500]}
                row["sameOutcomeBothProfiles"] = len(fingerprints) == 2 and fingerprints[0] == fingerprints[1]
                output["cases"].append(row)
                (a.out / "paired.json").write_text(json.dumps(output, indent=2) + "\n")
                print(label, score, roll, {p: v["pass"] for p, v in row["profiles"].items()}, flush=True)
    assert all(r["sameOutcomeBothProfiles"] and all(v["pass"] for v in r["profiles"].values()) for r in output["cases"])


if __name__ == "__main__":
    main()
