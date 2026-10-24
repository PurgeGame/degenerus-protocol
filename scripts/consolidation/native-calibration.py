#!/usr/bin/env python3
"""Replay original cold-call calibration prestates on native Amsterdam.

This records measured cases, not universal worst-case claims. The bound inventory
must associate each case with its operation, marginal differences and reserves.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "benchmark", Path(__file__).resolve().parents[1] / "audit/benchmark-storage-reuse.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


meter_spec = importlib.util.spec_from_file_location("native_meter", Path(__file__).with_name("native-gas-meter.py"))
gas_meter = importlib.util.module_from_spec(meter_spec)
meter_spec.loader.exec_module(gas_meter)


MINER_WORK = b.topic("MinerWork(address,uint8,uint256,uint256)")
TRAITS_GENERATED = b.topic("TraitsGenerated(uint32,uint256,uint32)")
GROWTH_WINNERS_PAID = b.topic("GrowthWinnersPaid(uint24,uint8,uint256,uint256,uint256)")


def events(logs):
    # Native-value transfer logs are RPC annotations rather than EVM LOG opcodes.
    out = []
    for entry in logs:
        if entry["address"].lower() == "0xfffffffffffffffffffffffffffffffffffffffe":
            continue
        data = entry["data"].lower()
        topics = [t.lower() for t in entry["topics"]]
        if topics and topics[0] == MINER_WORK:
            # These calibration fixtures use basefee zero. Their measured-gas
            # field changes across schedules; the action and zero reward must match.
            assert int(data[-64:], 16) == 0, "paid miner case needs the dedicated reward oracle"
            data = data[:66] + "<measured-gas>" + data[130:]
        out.append((entry["address"].lower(), topics, data))
    return out


def check_storage(expected, state, delta):
    mismatches = []
    pre = {a.lower(): v for a, v in delta.get("pre", {}).items()}
    post = {a.lower(): v for a, v in delta.get("post", {}).items()}
    for address, slots in expected.items():
        address = address.lower()
        for slot, value in slots.items():
            key = b.word(int(slot, 16))
            if key in post.get(address, {}).get("storage", {}):
                actual = post[address]["storage"][key]
            elif key in pre.get(address, {}).get("storage", {}):
                actual = "0x0"  # a modified slot omitted from post was cleared
            else:
                actual = state.get(address, {}).get("state", {}).get(key, "0x0")
            if int(actual, 16) != int(value, 16):
                mismatches.append([address, key, value, actual])
    return mismatches


def missing_prestate(observed, state, complete=False):
    missing = []
    for address, account in observed.items():
        exported = state.get(address.lower(), {})
        if account.get("code", "0x").lower() != exported.get("code", "0x").lower():
            missing.append([address, "code"])
        for slot, value in account.get("storage", {}).items():
            present = slot in exported.get("state", {})
            if (not present and not (complete and int(value, 16) == 0)) or (
                    present and int(value, 16) != int(exported["state"][slot], 16)):
                missing.append([address, slot])
    return missing


def event_lanes(entries):
    lanes = {}
    for entry in entries:
        key = (entry[0], entry[1][0] if entry[1] else "")
        if key[1] == GROWTH_WINNERS_PAID:
            raw = entry[2].removeprefix("0x")
            assert len(raw) == 256, "growth event shape"
            outcome, first, count, payout = [int(raw[i:i + 64], 16) for i in range(0, 256, 64)]
            assert 0 < count <= 32, "canonical growth credit batch"
            for index in range(first, first + count):
                expanded = "0x" + "".join(f"{v:064x}" for v in (outcome, index, 1, payout))
                lanes.setdefault(key, []).append((entry[0], entry[1], expanded))
        else:
            lanes.setdefault(key, []).append(entry)
    return lanes


def result_words(data):
    raw = data.removeprefix("0x")
    assert len(raw) == 192, "resumable worker must return MineFlipGas.Result"
    return [int(raw[i:i + 64], 16) for i in range(0, len(raw), 64)]


def apply_delta(state, delta):
    """Apply a verified native diff to the complete next-call state override."""
    state = copy.deepcopy(state)
    before, after = delta.get("pre", {}), delta.get("post", {})
    for address in before.keys() | after.keys():
        old, new = before.get(address, {}), after.get(address, {})
        account = state.setdefault(address.lower(), {"code": "0x", "nonce": "0x0", "balance": "0x0", "state": {}})
        for field in ("code", "nonce", "balance"):
            if field in new:
                account[field] = hex(new[field]) if isinstance(new[field], int) else new[field]
        for slot in old.get("storage", {}):
            if slot not in new.get("storage", {}): account["state"][slot] = b.word(0)
        account["state"].update(new.get("storage", {}))
    return state


def json_value(value):
    """Foundry serializers may preserve JSON as a string or embed the parsed value."""
    return json.loads(value) if isinstance(value, str) else value


def dumped_accounts(dump):
    accounts = dump.get("accounts", dump.get("alloc", dump))
    return {(address if address.startswith("0x") else "0x" + address).lower(): value
            for address, value in accounts.items()}


def dumped_storage(dump):
    return {address: {b.word(int(slot, 16)): b.word(int(value, 16))
                      for slot, value in account.get("storage", {}).items()}
            for address, account in dumped_accounts(dump).items()}


def complete_storage_changes(before, after):
    expected = {}
    for address in before.keys() | after.keys():
        old, new = before.get(address, {}), after.get(address, {})
        for slot in old.keys() | new.keys():
            value = new.get(slot, b.word(0))
            if int(value, 16) != int(old.get(slot, "0x0"), 16):
                expected.setdefault(address, {})[slot] = value
    return expected


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--rpc", required=True)
    p.add_argument("--fixtures", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--schedule", choices=("osaka", "amsterdam"), default="amsterdam")
    p.add_argument("--resume", action="store_true", help="Reuse passing cases with identical input and prestate hashes")
    a = p.parse_args()
    assert int(b.rpc(a.rpc, "eth_chainId", []), 16) in (1337, 31337), "local replay only"


    rows = []
    previous = {}
    if a.resume and a.output.exists():
        saved = json.loads(a.output.read_text())
        assert saved["schedule"] == a.schedule, "Cannot resume a different gas schedule"
        previous = {row["label"]: row for row in saved["cases"]}
    def publish():
        a.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = a.output.with_suffix(a.output.suffix + ".tmp")
        temporary.write_text(json.dumps({"schedule": a.schedule, "client": b.rpc(a.rpc, "web3_clientVersion", []),
            "method": "Cold native replay from original calibration prestates. Atomic cases require exact returns, ordered events and exported poststorage. Ticket admission searches preserve the original exact first-full-run criterion; later resumable work is reported but excluded from that probe's oracle. Resumable full-cohort cases require ordered events in each emitter/event lane (growth runs expanded to their exact winner indices and per-winner payouts), aggregated work count and exact final poststorage. All cases require complete accessed code/storage. Gas reports separate refunded receipts, gross state-inclusive gas, measured root execution-budget consumption and block max(execution,state) gas.",
            "cases": rows}, indent=2) + "\n")
        temporary.replace(a.output)

    for file in sorted(a.fixtures.glob("*.call.json")):
        label = file.name.removesuffix(".call.json")
        call = json.loads(file.read_text())
        state_file = file.with_name(label + ".state.json")
        if not state_file.exists():
            rows.append({"label": label, "profiles": {profile: {"pass": False, "error": "export did not complete"}
                for profile in ("no-reservoir", "reservoir")}})
            continue
        dump = json.loads(state_file.read_text())
        state = {}
        for address, value in dumped_accounts(dump).items():
            nonce = value.get("nonce", 0)
            state[address.lower()] = {
                "code": value.get("code", "0x"), "nonce": hex(int(nonce, 16) if isinstance(nonce, str) else nonce),
                "balance": hex(int(value.get("balance", "0x0"), 16)),
                "state": {b.word(int(k, 16)): b.word(int(v, 16)) for k, v in value.get("storage", {}).items()}}
        complete_post = None
        if call.get("completeStateDump"):
            post_file = file.with_name(label + ".post.json")
            complete_post = dumped_storage(json.loads(post_file.read_text()))
            call["expectedStorage"] = complete_storage_changes(dumped_storage(dump), complete_post)
        sender = call["from"].lower()
        state.setdefault(sender, {"code": "0x", "state": {}, "nonce": "0x1", "balance": "0x0"})
        bo = {"time": hex(call["timestamp"]), "baseFeePerGas": hex(call.get("baseFee", 0))}
        if call.get("number", 0):
            bo["number"] = hex(call["number"])
        row = {"label": label, "target": call["to"], "selector": call["input"][:10],
               "fixtureSha256": hashlib.sha256(file.read_bytes()).hexdigest(),
               "prestateSha256": hashlib.sha256(json.dumps(state, sort_keys=True).encode()).hexdigest(), "profiles": {}}
        if complete_post is not None:
            row["completeStateDump"] = True
            row["poststateSha256"] = hashlib.sha256(post_file.read_bytes()).hexdigest()
        saved = previous.get(label)
        if (saved and all(saved.get(key) == row.get(key) for key in
                         ("fixtureSha256", "prestateSha256", "poststateSha256"))
                and all(profile["pass"] for profile in saved["profiles"].values())):
            rows.append(saved)
            continue
        expected_events = events(json_value(call["expectedLogs"]))
        for profile, limit in [("no-reservoir", 16_777_216), ("reservoir", 500_000_000)]:
            tx = {"from": sender, "to": call["to"], "data": call["input"], "gas": hex(limit),
                  "gasPrice": hex(call.get("baseFee", 0)), "value": hex(int(str(call.get("value", 0)), 0))}
            try:
                opts = {"blockOverrides": bo, "stateOverrides": state, "tracer": "prestateTracer", "timeout": "60s"}
                admission = None
                checkpoint_match = False
                if "workerAllowance" in call:
                    # Repeat the original ticket calibration's admission search on the
                    # native schedule. Its Osaka minimum is not a native minimum.
                    # The exact original committed transcript and result define the unit.
                    offset = 10 + 64 * call.get("allowanceWord", 1)
                    original = tx["data"]
                    def trial(allowance):
                        tx["data"] = original[:offset] + f"{allowance:064x}" + original[offset + 64:]
                        block = b.rpc(a.rpc, "eth_simulateV1", [{"blockStateCalls": [{"blockOverrides": bo,
                            "stateOverrides": state, "calls": [tx]}], "validation": False}, "0x0"])[0]
                        result = block["calls"][0]
                        exact = (result["status"] == "0x1" and result["returnData"] == call["expectedReturn"]
                                 and events(result["logs"]) == expected_events)
                        if exact and call.get("expectedStorage"):
                            wanted = json_value(call["expectedStorage"])
                            diff = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts,
                                tracerConfig={"diffMode": True})])
                            mismatches = check_storage(wanted, state, diff)
                            if mismatches:
                                exact = False
                                # A no-event selection checkpoint can return the same
                                # Result before its control writes happen. Count actual
                                # changes to distinguish that refusal from extra work.
                                required = sum(int(value, 16) != int(state.get(address.lower(), {}).get("state", {}).get(slot, "0x0"), 16)
                                    for address, slots in wanted.items() for slot, value in slots.items())
                                changed = sum(len(account.get("storage", {})) for account in diff.get("pre", {}).values())
                                changed += sum(slot not in diff.get("pre", {}).get(address, {}).get("storage", {})
                                    for address, account in diff.get("post", {}).items() for slot in account.get("storage", {}))
                                result["_checkpointNotReached"] = changed < required
                                if label.startswith("ticket-") and label.rsplit("-", 3)[-3] == "2":
                                    # Dust-seat skips can commit the same Result and no
                                    # events at many different cursors. Counting changed
                                    # slots is not monotone (cleared lanes are omitted).
                                    # Use the declared cursor only to direct the search;
                                    # acceptance still requires the entire exact poststate.
                                    layout = json.loads((Path(__file__).resolve().parents[1]
                                        / "layout/golden/DegenerusGame.json").read_text())
                                    field = next(r for r in layout if r["label"] == "ticketCursor")
                                    key = b.word(int(field["slot"]))
                                    mask = (1 << (8 * int(field["bytes"]))) - 1
                                    shift = 8 * int(field["offset"])
                                    cursor = next((m for m in mismatches if m[0] == call["to"].lower() and m[1] == key), None)
                                    if cursor is not None:
                                        done = result_words(result["returnData"])[1]
                                        result["_checkpointNotReached"] = not done and (
                                            (int(cursor[3], 16) >> shift) & mask) < ((int(cursor[2], 16) >> shift) & mask)
                        return result, exact
                    _, exact = trial(call["workerAllowance"])
                    low, high = 0, 16_777_216
                    best = call["workerAllowance"] if exact else None
                    for _ in range(25):
                        if high - low <= 1: break
                        mid = (low + high) // 2
                        probe, match = trial(mid)
                        actual_events = events(probe["logs"])
                        if match:
                            best = mid
                            high = mid
                        elif probe["status"] != "0x1" or probe.get("_checkpointNotReached", False) or (
                            len(probe.get("returnData", "")) == 194 and len(call["expectedReturn"]) == 194
                            and (result_words(probe["returnData"])[0] < result_words(call["expectedReturn"])[0]
                                 or result_words(probe["returnData"])[2] < result_words(call["expectedReturn"])[2])
                        ) or len(actual_events) < len(expected_events):
                            low = mid
                        else:
                            high = mid
                    mode = "exact committed transcript, return and poststate"
                    if best is None and label.startswith("ticket-") and label.rsplit("-", 3)[-3] == "1":
                        # The original Solo probe intentionally tests only the first
                        # full aligned run. Its remaining reservation may admit more
                        # runs. Preserve that method when native throughput differs.
                        wanted = next((e for e in expected_events if e[0] == call["to"].lower()
                                       and e[1] and e[1][0] == TRAITS_GENERATED), None)
                        low, high = 0, 16_777_216
                        for _ in range(25):
                            if high - low <= 1: break
                            mid = (low + high) // 2
                            probe, _ = trial(mid)
                            actual = events(probe["logs"])
                            first = next((e for e in actual if e[0] == call["to"].lower()
                                          and e[1] and e[1][0] == TRAITS_GENERATED), None)
                            if probe["status"] == "0x1" and wanted is not None and first == wanted:
                                best, high = mid, mid
                            else:
                                low = mid
                        if best is not None:
                            probe, _ = trial(best)
                            actual = events(probe["logs"])
                            first = next((e for e in actual if e[0] == call["to"].lower()
                                          and e[1] and e[1][0] == TRAITS_GENERATED), None)
                            checkpoint_match = wanted is not None and first == wanted
                            mode = "original Solo probe: exact first full aligned run; later resumable work may vary, so full-call poststate is not this probe's oracle"
                    if best is None:
                        tx["data"] = original
                    else:
                        trial(best)
                    admission = {"originalOsakaAllowance": call["workerAllowance"],
                                 "nativeMatchingAllowance": best, "lowerSearchEdge": low,
                                 "method": mode}
                observed = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", opts])
                missing = missing_prestate(observed, state, call.get("completeStateDump", False))
                block = b.rpc(a.rpc, "eth_simulateV1", [{"blockStateCalls": [{"blockOverrides": bo,
                    "stateOverrides": state, "calls": [tx]}], "validation": False}, "0x0"])[0]
                result = block["calls"][0]
                trace = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer="callTracer")])
                meter = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts, tracer=gas_meter.METER)])
                native_gas = gas_meter.measured_gas(meter, limit, schedule=a.schedule)
                same = (int(result["status"], 16) == 1 and result["returnData"] == call["expectedReturn"]
                        and events(result["logs"]) == expected_events)
                continuation = None
                if not same and call.get("expectedStorage") and call["input"][:10] in ("0x6cf8a815", "0xc3510b73") and profile == "no-reservoir":
                    # The original full-cohort probe can exceed the native per-call
                    # execution cap. Continue its resumable worker from each committed
                    # poststate, requiring the exact complete original transcript.
                    next_state = state
                    accumulated = events(result["logs"])
                    pieces = []
                    basis = 0
                    target_lanes = event_lanes(expected_events)
                    last = result
                    piece_block = block
                    for _ in range(8):
                        lanes = event_lanes(accumulated)
                        if last["status"] != "0x1" or any(v != target_lanes.get(k, [])[:len(v)] for k, v in lanes.items()): break
                        words = result_words(last["returnData"])
                        basis += words[2]
                        combined_return = "0x" + "".join(f"{n:064x}" for n in (1, words[1], basis))
                        pieces.append({"receiptGas": int(last["gasUsed"], 16),
                                       "grossGas": int(last["maxUsedGas"], 16),
                                       "blockGasUsedMaxDimension": int(piece_block["gasUsed"], 16), "logs": len(events(last["logs"]))})
                        piece_pre = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts, stateOverrides=next_state)])
                        missing.extend(missing_prestate(piece_pre, next_state, call.get("completeStateDump", False)))
                        diff = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts, stateOverrides=next_state,
                                     tracerConfig={"diffMode": True})])
                        next_state = apply_delta(next_state, diff)
                        if lanes == target_lanes and combined_return == call["expectedReturn"]:
                            continuation = {"pass": True, "calls": pieces, "finalState": next_state,
                                            "method": "cold resumable native calls; exact ordered events within each emitter/event lane, aggregated reward basis, final completion and full exported poststorage"}
                            break
                        if not events(last["logs"]): break
                        piece_block = b.rpc(a.rpc, "eth_simulateV1", [{"blockStateCalls": [{"blockOverrides": bo,
                            "stateOverrides": next_state, "calls": [tx]}], "validation": False}, "0x0"])[0]
                        last = piece_block["calls"][0]
                        accumulated += events(last["logs"])
                if not same and label.startswith("terminal_tally_") and call.get("expectedStorage"):
                    # The original backlog probe permits as many checkpoints as the
                    # gas schedule needs. Match its complete tally, not its Osaka
                    # number of records per call. Every native call keeps the exact
                    # original allowance, preserves event order and stays below 10M.
                    next_state = state
                    accumulated = []
                    pieces = []
                    target_storage = json_value(call["expectedStorage"])
                    for _ in range(8):
                        piece_opts = dict(opts, stateOverrides=next_state)
                        piece_block = b.rpc(a.rpc, "eth_simulateV1", [{"blockStateCalls": [{"blockOverrides": bo,
                            "stateOverrides": next_state, "calls": [tx]}], "validation": False}, "0x0"])[0]
                        last = piece_block["calls"][0]
                        if last["status"] != "0x1": break
                        accumulated += events(last["logs"])
                        if accumulated != expected_events[:len(accumulated)]: break
                        observed_piece = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", piece_opts])
                        missing.extend(missing_prestate(observed_piece, next_state, call.get("completeStateDump", False)))
                        diff = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(piece_opts,
                            tracerConfig={"diffMode": True})])
                        piece_meter = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(piece_opts, tracer=gas_meter.METER)])
                        metrics = gas_meter.measured_gas(piece_meter, limit, schedule=a.schedule)
                        pieces.append(metrics)
                        if metrics["grossGasUpperBound"] >= 10_000_000: break
                        post = apply_delta(next_state, diff)
                        if (last["returnData"] == call["expectedReturn"] and accumulated == expected_events
                                and not check_storage(target_storage, post, {})):
                            continuation = {"pass": True, "calls": pieces, "finalState": post,
                                "method": "cold original-allowance tally checkpoints below 10M; exact ordered events, final return and complete exported poststorage"}
                            break
                        if post == next_state: break
                        next_state = post
                expected_storage = json_value(call.get("expectedStorage", {})) if not checkpoint_match else {}
                delta = b.rpc(a.rpc, "debug_traceCall", [tx, "0x0", dict(opts,
                    tracerConfig={"diffMode": True})]) if expected_storage else {}
                if complete_post is not None:
                    # A complete world-state dump also proves untouched/absent keys.
                    # Check every native storage change, including any unexpected write.
                    expected_storage = copy.deepcopy(expected_storage)
                    for side in ("pre", "post"):
                        for account, fields in delta.get(side, {}).items():
                            for slot in fields.get("storage", {}):
                                expected_storage.setdefault(account.lower(), {})[slot] = complete_post.get(account.lower(), {}).get(slot, b.word(0))
                storage_mismatches = check_storage(expected_storage, state, delta)
                if continuation:
                    storage_mismatches = check_storage(expected_storage, continuation.pop("finalState"), {})
                intrinsic = native_gas["intrinsicGas"]
                fixed_frame = int(result["maxUsedGas"], 16) - intrinsic if profile == "no-reservoir" else native_gas["frameExecutionBudgetConsumed"]
                fixed_ok = not call.get("enforceBudget", False) or fixed_frame <= call["fixedCalleeBudget"]
                checkpoint_gas = int(result["maxUsedGas"], 16) if profile == "no-reservoir" else native_gas["frameExecutionBudgetConsumed"]
                checkpoint_bound = not checkpoint_match or (checkpoint_gas < 10_000_000
                                                           and admission["nativeMatchingAllowance"] < 10_000_000)
                meter_checks = []
                for event in result["logs"]:
                    if event["topics"] and event["topics"][0] == MINER_WORK:
                        used = int(event["data"][66:130], 16)
                        charged = native_gas["frameExecutionBudgetConsumed"]
                        meter_checks.append({"used": used, "charged": charged, "pass": used <= charged})
                row["profiles"][profile] = {"gasUsed": int(result["gasUsed"], 16),
                    "maxUsedGas": int(result["maxUsedGas"], 16), "blockGasUsedMaxDimension": int(block["gasUsed"], 16), "nativeGasMeter": native_gas,
                    "callTracerGasUsed": int(trace["gasUsed"], 16), "status": result["status"],
                    "sameReturnAndOrderedLogs": same, "originalFirstCheckpointMatches": checkpoint_match, "checkpointUnder10M": checkpoint_bound, "continuation": continuation, "missingPrestate": missing, "trace": trace,
                    "result": result, "expectedStorageChecked": bool(expected_storage),
                    "storageMismatches": storage_mismatches, "minerUndercount": meter_checks, "admissionSearch": admission, "calibratedInput": tx["data"], "fixedCalleeBudget": call.get("fixedCalleeBudget"),
                    "nativeFrameGas": fixed_frame, "fixedBudgetPass": fixed_ok,
                    "pass": (same or checkpoint_match or bool(continuation)) and checkpoint_bound and fixed_ok and not missing and not storage_mismatches and all(m["pass"] for m in meter_checks)}
            except Exception as exc:
                row["profiles"][profile] = {"pass": False, "error": str(exc)}
        rows.append(row)
        print(label, {k: v["pass"] for k, v in row["profiles"].items()}, flush=True)
        # Persist bounded batches atomically; serializing the complete growing
        # trace archive after every case made the oracle quadratic in disk I/O.
        if len(rows) % 25 == 0:
            publish()
    publish()
    assert rows and all(v["pass"] for r in rows for v in r["profiles"].values()), "native calibration cases require review"


if __name__ == "__main__":
    main()
