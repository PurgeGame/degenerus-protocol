"""Read-only RPC helpers used by retained replay-parser tests and tools."""
import json
import urllib.request

def word(n):
    return "0x" + format(n, "064x")


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


