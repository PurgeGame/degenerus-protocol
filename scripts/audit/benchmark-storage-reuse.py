#!/usr/bin/env python3
"""Read-only Glamsterdam replay of StorageReuseNative fixtures; never sends a transaction.

Export fixtures with STORAGE_REUSE_EXPORT and an explicit Foundry filesystem permission.
The dump contains complete locally seeded storage. Old-code comparisons translate that
storage, rather than interpreting retained ring/history words as the old layout.
"""
import argparse
import copy
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.request

from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parents[2]
PUBLIC_RPC = "https://ethereum-sepolia-rpc.publicnode.com"


def word(n):
    return "0x" + format(n, "064x")


def hashed(key, root):
    h = keccak.new(digest_bits=256)
    h.update(key.to_bytes(32, "big") + root.to_bytes(32, "big"))
    return int.from_bytes(h.digest(), "big")


def topic(signature):
    h = keccak.new(digest_bits=256)
    h.update(signature.encode())
    return "0x" + h.hexdigest()


def compare_logs(actual, expected, label, variant):
    """Normalize only declared economic/gas differences, keeping raw logs in the report."""
    notes = []
    ignored = set()
    if label == "affiliate_capped" and variant == "Current90":
        ignored = {topic("AffiliateEarningsRecorded(uint32,uint256)"), topic("AffiliateTopUpdated(uint24,uint32,uint96)")}
        notes.append("approved affiliate score cap: compare payout logs, retain differing score logs")
    gas_fields = {}
    if label == "vault_miner_checkpoint_76":
        gas_fields = {topic("MinerWork(address,uint8,uint256,uint256)"): 32,
            topic("MinerBounty(uint8,address,uint256)"): 32,
            topic("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)"): 0}
        notes.append("miner executionGas/reward and its stake amount depend on native gas; compare other fields/events exactly")

    def normalized(logs):
        out = []
        for log in logs:
            entry = {k: log[k] for k in ["address", "data", "topics"]}
            t = entry["topics"][0].lower() if entry["topics"] else ""
            if t in ignored:
                continue
            if t in gas_fields:
                entry["data"] = entry["data"][:2 + 2 * gas_fields[t]]
            out.append(entry)
        return json.dumps(out, sort_keys=True).lower()

    return normalized(actual) == normalized(expected), notes


def rpc(url, method, params):
    if method not in {"eth_chainId", "eth_getBlockByNumber", "web3_clientVersion", "eth_simulateV1", "eth_estimateGas", "debug_traceCall"}:
        raise ValueError("not a read-only benchmark method")
    req = urllib.request.Request(url, data=json.dumps({"jsonrpc": "2.0", "id": 1,
        "method": method, "params": params}).encode(), headers={"Content-Type": "application/json",
        "User-Agent": "storage-reuse-readonly-benchmark/1.0"})
    with urllib.request.urlopen(req, timeout=60) as response:
        result = json.load(response)
    if "error" in result:
        raise RuntimeError(json.dumps(result["error"]))
    return result["result"]


def compile_baseline(destination, solc, address_pins):
    pin = json.loads((ROOT / "scripts/audit/storage-reuse/baseline.json").read_text())["source_head"]
    names = ["Coinflip", "DegenerusAffiliate", "DegenerusJackpots"]
    sources = {str(p.relative_to(ROOT)): {"content": p.read_text()} for p in (ROOT / "contracts").rglob("*.sol")}
    sources["contracts/ContractAddresses.sol"] = {"content": re.sub(
        r"pragma solidity [^;]+;", "pragma solidity 0.8.38;", address_pins.read_text(), count=1)}
    for name in names:
        path = f"contracts/{name}.sol"
        content = subprocess.check_output(["git", "show", f"{pin}:{path}"], cwd=ROOT, text=True)
        if name == "Coinflip":
            assert content.count("COIN_CLAIM_DAYS = 730;") == 1
            content = content.replace("COIN_CLAIM_DAYS = 730;", "COIN_CLAIM_DAYS = 90;")
        # Adapt only the compiler directive in the in-memory historical input.
        # Frozen source evidence remains unchanged.
        content = re.sub(r"pragma solidity [^;]+;", "pragma solidity 0.8.38;", content, count=1)
        sources[path] = {"content": content}
    settings = {"optimizer": {"enabled": True, "runs": 1000}, "viaIR": True, "evmVersion": "osaka",
        "remappings": ["@openzeppelin/=node_modules/@openzeppelin/"],
        "outputSelection": {f"contracts/{name}.sol": {name: ["evm.deployedBytecode.object", "storageLayout", "metadata"]} for name in names}}
    request = {"language": "Solidity", "sources": sources, "settings": settings}
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "compiler-input.json").write_text(json.dumps(request))
    version = subprocess.check_output([solc, "--version"], text=True)
    if "0.8.38+" not in version:
        raise RuntimeError("benchmark requires pinned solc 0.8.38")
    result = subprocess.run([solc, "--base-path", str(ROOT), "--allow-paths", str(ROOT), "--standard-json"],
        input=json.dumps(request), text=True, capture_output=True, check=True)
    output = json.loads(result.stdout)
    errors = [e for e in output.get("errors", []) if e["severity"] == "error"]
    if errors:
        raise RuntimeError(json.dumps(errors))
    for name in names:
        artifact = output["contracts"][f"contracts/{name}.sol"][name]
        (destination / f"{name}.json").write_text(json.dumps(artifact, indent=2) + "\n")
    (destination / "identity.json").write_text(json.dumps({"source_head": pin, "solc": version,
        "settings": settings, "input_sha256": hashlib.sha256(json.dumps(request).encode()).hexdigest()}, indent=2) + "\n")


def pins(address_pins):
    text = address_pins.read_text()
    return {name: address.lower() for name, address in re.findall(
        r"address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]{40})\)", text)}


def old_state(overrides, addresses, artifacts):
    """Decode all seeded new-layout words independently, then encode the old roots."""
    result = copy.deepcopy(overrides)
    # Explicit native-fixture domain: registered protocol/player IDs and 1000..1031.
    # This is not a migration tool for arbitrary deployed state.
    candidates = range(0, 1100)
    cf = result.get(addresses["COINFLIP"])
    if cf:
        state = cf["state"]
        old = dict(state)
        for who in candidates:
            ring = hashed(who, 0)
            pages = []
            for index in range(15):
                value = int(state.get(word(ring + index), "0x0"), 16)
                old.pop(word(ring + index), None)
                tag = (value >> 224) & ((1 << 24) - 1)
                if tag:
                    pages.append((tag - 1, value))
            # Only a few pages are seeded by the fixture. Overflow's exact key can be
            # recovered from its full tag, then checked against the account-specific root.
            root = hashed(who, 9)
            for slot, raw in state.items():
                value = int(raw, 16)
                tag = (value >> 224) & ((1 << 24) - 1)
                if tag and slot == word(hashed(tag - 1, root)):
                    pages.append((tag - 1, value))
                    old.pop(slot, None)
            for page, value in pages:
                for lane in range(7):
                    amount = (value >> (32 * lane)) & ((1 << 32) - 1)
                    if not amount:
                        continue
                    day = page * 7 + lane
                    slot = word(hashed(who, hashed(day >> 3, 0)))
                    shift = (day & 7) * 32
                    previous = int(old.get(slot, "0x0"), 16)
                    assert ((previous >> shift) & ((1 << 32) - 1)) == 0, "duplicate logical stake"
                    old[slot] = word(previous | amount << shift)
        cf["state"] = old
        cf["code"] = "0x" + artifacts["Coinflip"]["evm"]["deployedBytecode"]["object"]
    baf = result.get(addresses["JACKPOTS"])
    if baf:
        state = baf["state"]
        old = dict(state)
        for who in candidates:
            base = hashed(who, 0)
            for index in range(2):
                value = int(state.get(word(base + index), "0x0"), 16)
                old.pop(word(base + index), None)
                bracket = value >> 232
                if bracket:
                    total = value & ((1 << 168) - 1)
                    epoch = (value >> 168) & ((1 << 64) - 1)
                    old[word(hashed(who, hashed(bracket, 0)))] = word(total | epoch << 192)
        baf["state"] = old
        baf["code"] = "0x" + artifacts["DegenerusJackpots"]["evm"]["deployedBytecode"]["object"]
    af = result.get(addresses["AFFILIATE"])
    if af:
        state = af["state"]
        old = dict(state)
        for who in candidates:
            slot = word(hashed(who, 1))
            value = int(state.get(slot, "0x0"), 16)
            old.pop(slot, None)
            latest = (value >> 165) & ((1 << 24) - 1)
            cache = (value >> 189) & ((1 << 66) - 1)
            for age in range(min(7, latest)):
                amount = (value >> (age * 35)) & ((1 << 35) - 1) if age < 2 else (value >> (70 + (age - 2) * 19)) & ((1 << 19) - 1)
                if amount or cache:
                    old[word(hashed(who, hashed(latest - age, 1)))] = word(amount | cache << 128)
        af["state"] = old
        af["code"] = "0x" + artifacts["DegenerusAffiliate"]["evm"]["deployedBytecode"]["object"]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compile-baseline", type=Path)
    parser.add_argument("--solc", default=str(Path.home() / ".svm/0.8.38/solc-0.8.38"))
    parser.add_argument("--fixtures", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--pins", type=Path, required=True, help="Exact ContractAddresses source used to compile the fixtures")
    parser.add_argument("--rpc", default=PUBLIC_RPC)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--case", action="append")
    args = parser.parse_args()
    if args.compile_baseline:
        compile_baseline(args.compile_baseline, args.solc, args.pins)
        return
    if not args.fixtures or not args.output:
        parser.error("--fixtures and --output are required for replay")
    if rpc(args.rpc, "eth_chainId", []) != "0xaa36a7":
        raise RuntimeError("endpoint is not Ethereum Sepolia")
    block = rpc(args.rpc, "eth_getBlockByNumber", ["latest", False])
    artifacts = {name: json.loads((args.baseline / f"{name}.json").read_text()) for name in
        ["Coinflip", "DegenerusAffiliate", "DegenerusJackpots"]} if args.baseline else None
    addresses = pins(args.pins)
    report = {"endpoint": args.rpc, "client": rpc(args.rpc, "web3_clientVersion", []),
        "block": {k: block[k] for k in ["number", "hash", "timestamp"]},
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "pins_sha256": hashlib.sha256(args.pins.read_bytes()).hexdigest(), "cases": []}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    for path in sorted(args.fixtures.glob("*.call.json")):
        label = path.name.removesuffix(".call.json")
        if args.case and label not in args.case:
            continue
        call = json.loads(path.read_text())
        dump = json.loads((args.fixtures / f"{label}.state.json").read_text())
        accounts = dump.get("accounts", dump)
        selected = {a.lower() for a in call["accounts"]}
        overrides = {}
        for address, account in accounts.items():
            if address.lower() not in selected:
                continue
            overrides[address.lower()] = {"code": account.get("code", "0x"),
                "balance": hex(int(account.get("balance", "0x0"), 16)), "nonce": hex(int(account.get("nonce", 0))),
                "state": {word(int(k, 16)): word(int(v, 16)) for k, v in account.get("storage", {}).items()}}
        # Missing EOAs are explicit, existing and funded. Calls use validation=false;
        # no signature, private key, nonce mutation on-chain or funded wallet is involved.
        sender = call["from"].lower()
        overrides.setdefault(sender, {"code": "0x", "state": {}, "nonce": "0x1"})["balance"] = hex(10**30)
        for variant in ["R90", "Current90"] if artifacts else ["R90"]:
            state = old_state(overrides, addresses, artifacts) if variant == "Current90" else overrides
            transaction = {"from": sender, "to": call["to"], "input": call["input"], "gas": hex(16_000_000)}
            params = [{"blockStateCalls": [{"blockOverrides": {"time": hex(call["timestamp"]), "baseFeePerGas": hex(call.get("baseFee", 0))},
                "stateOverrides": state, "calls": [transaction]}], "validation": False}, block["number"]]
            row = {"case": label, "variant": variant, "request_sha256": hashlib.sha256(json.dumps(params, sort_keys=True).encode()).hexdigest()}
            request_dir = args.output.parent / "native-requests"
            request_dir.mkdir(exist_ok=True)
            request_path = request_dir / f"{label}-{variant}.json.gz"
            request_path.write_bytes(gzip.compress(json.dumps(params, sort_keys=True).encode(), mtime=0))
            row["request_file"] = str(request_path.relative_to(args.output.parent))
            row["runtime_sha256"] = {a: hashlib.sha256(bytes.fromhex(s["code"][2:])).hexdigest()
                for a, s in state.items() if s["code"] != "0x"}
            try:
                result = rpc(args.rpc, "eth_simulateV1", params)[0]
                response = result["calls"][0]
                expected_logs = json.loads(call["expectedLogs"])
                actual_logs = [{k: log[k] for k in ["address", "data", "topics"]} for log in response["logs"]]
                logs_match, notes = compare_logs(actual_logs, expected_logs, label, variant)
                row.update({"status": int(response["status"], 16), "gas_used": int(response["gasUsed"], 16),
                    "max_used_gas": int(response.get("maxUsedGas", response["gasUsed"]), 16),
                    "return_matches": response["returnData"] == call["expectedReturn"], "logs_match": logs_match,
                    "comparison_notes": notes, "block_resource_gas": int(result["gasUsed"], 16), "response": response})
            except Exception as error:
                row["error"] = str(error)
            report["cases"].append(row)
            args.output.write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps({k: v for k, v in row.items() if k not in {"response", "runtime_sha256"}}), flush=True)
            time.sleep(0.15)
    if not report["cases"] or any(r.get("status") != 1 or not r.get("return_matches") or not r.get("logs_match") for r in report["cases"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
