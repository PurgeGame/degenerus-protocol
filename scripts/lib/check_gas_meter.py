#!/usr/bin/env python3
"""Pin gas reads to reviewed statements; reject ambient ticket entropy inputs.

This text-level drift gate does not prove dataflow or gas bounds. Runtime parity
tests remain mandatory when an admitted checkpoint or its caller changes.
"""
from collections import Counter
from pathlib import Path
import re
import sys

from rng_window_extract import enclosing_functions, strip_comments_and_strings

# Each statement is pinned, rather than allowing arbitrary new uses in a function.
# Accounting reads measure deltas, including the minimum work needed for a reward.
# Admission reads select deterministic checkpoints/forwarding.
REVIEWED = {
    ("libraries/MineFlipGas.sol", "start"): [
        "uint256 entry = gasleft();"],
    ("libraries/MineFlipGas.sol", "remaining"): ["uint256 current = gasleft();"],
    ("libraries/MineFlipGas.sol", "finish"): ["if (meter.bounded && gasleft() < meter.floor) revert WorkGasBound();"],
    ("libraries/MineFlipGas.sol", "forwardable"): ["if (meter.mustProgress) return gasleft();"],
    # Pre-call minimum and tail reservation; never classifies a callee failure.
    ("libraries/BoundedCall.sol", "_remaining"): [
        # The first mandatory checkpoint forwards all remaining gas, regardless of estimates.
        # mustProgress is a deterministic checkpoint flag, never a gas-dependent outcome branch.
        "if (meter.mustProgress) return gasleft();", "available = gasleft();"],
    # Pre-call admission of the mandatory first unit; never classifies a callee failure.
    ("libraries/BoundedCall.sol", "admitFirst"): [
        "if (meter.mustProgress && gasleft() < minimum + reserve) revert MineFlipGas.InsufficientExecutionGas();"],
    ("modules/GameMiner.sol", "_mineFlip"): [
        "uint256 rewardStart = gasleft();",
        "MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.budget(gasleft(), gasMultiplierBps, true));",
        "uint256 beforeCall = gasleft();",
        # Separate caught-refusal and successful-no-progress exits exclude their cost.
        "unpaidAttemptGas = MineFlipGas.consumed(beforeCall, gasleft());",
        "unpaidAttemptGas = MineFlipGas.consumed(beforeCall, gasleft());",
        "uint256 used = MineFlipGas.consumed(rewardStart, gasleft());"],
    ("libraries/MineFlipGas.sol", "available"): ["uint256 actual = gasleft();"],
    # Pinned lifecycle worker: uncapped forwarding, with exact return/revert propagation.
    ("modules/CrapsLifecycleRouter.sol", "_delegateLifecycle"): [
        "let ok := delegatecall(gas(), target, data, calldatasize(), 0, 0)"],
}
GAS_READ = re.compile(r"\b(?:gasleft|gas)\s*\(")
AMBIENT = re.compile(r"\b(?:msg\s*\.\s*sender|tx\s*\.|block\s*\.|blockhash\s*\()")
DRAINS = set("""_seatEntry _runRound _resolveFoilBuyer _bucketAppendRun _bucketAppendLanes
""".split())

# Ticket worker code has no ambient caller exceptions.
TICKET_AUTH_GUARDS = set()


def compact(code):
    return re.sub(r"\s+", "", code)


def scan_source(path, source):
    masked = strip_comments_and_strings(source)
    functions = enclosing_functions(masked)
    reads, bad = Counter(), []
    all_ticket = path in {"modules/DegenerusGameTicketModule.sol", "libraries/TicketEntropy.sol"}
    for index, line in enumerate(masked.splitlines()):
        fn = functions[index]
        if GAS_READ.search(line):
            reads[(path, fn, compact(line))] += 1
        if (all_ticket or fn in DRAINS) and AMBIENT.search(line):
            if (path, fn, compact(line)) not in TICKET_AUTH_GUARDS:
                bad.append(f"{path}:{index + 1} ambient input in {fn}: {line.strip()}")
    return reads, bad


def main():
    expected = Counter((path, fn, compact(code)) for (path, fn), lines in REVIEWED.items() for code in lines)
    actual, bad = Counter(), []
    for path in sorted(Path("contracts").rglob("*.sol")):
        rel = path.relative_to("contracts")
        if set(rel.parts) & {"interfaces", "mocks", "test"}:
            continue
        reads, errors = scan_source(rel.as_posix(), path.read_text())
        actual.update(reads)
        bad.extend(errors)
    for label, difference in (("unreviewed gas read", actual - expected), ("stale gas pin", expected - actual)):
        for (path, fn, code), count in sorted(difference.items()):
            bad.append(f"{label}: {path} {fn}: {code} ({count} sites)")
    if bad:
        print("\n".join("FAIL " + error for error in bad))
        return 1
    print(f"PASS {sum(actual.values())} reviewed gas reads; no ambient ticket entropy inputs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
