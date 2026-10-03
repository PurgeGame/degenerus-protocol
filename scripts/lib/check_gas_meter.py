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
    ("CrapsBattle.sol", "_delegateJackpot"): [
        "let ok := delegatecall(gas(), target, 0, calldatasize(), 0, 0)"],
    ("DegenerusGame.sol", "minerAction"): [
        "let ok := delegatecall(gas(), target, ptr, calldatasize(), 0, 0)"],
    ("JackpotBattle.sol", "keepRngCohortBudgeted"): [
        "uint256 start = gasleft();",
        "return (result.progressed, result.rewardBasis != 0, uint64(start - gasleft()));"],
    ("JackpotBattle.sol", "_scheduledWork"): [
        "uint256 start = gasleft();", "used = start - gasleft();"],
    ("sDGNRS.sol", "processRedemptionSettlement"): [
        "uint256 start = gasleft();", "return (result.done, start - gasleft(), result.rewardBasis);"],
    ("libraries/MineFlipGas.sol", "available"): ["return gasleft();"],
    ("libraries/MineFlipGas.sol", "start"): [
        "meter = Meter({start: gasleft(), allowance: allowance});"],
    ("libraries/MineFlipGas.sol", "spent"): ["return meter.start - gasleft();"],
    ("libraries/MineFlipGas.sol", "canRun"): ["return gasleft() >= required;"],
    ("libraries/MineFlipGas.sol", "forwardable"): ["uint256 available = gasleft();"],
    ("libraries/MineFlipGas.sol", "requireStipend"): [
        "if (gasleft() < stipend + stipend / 63 + 2 * CALL_RESERVE) revert InsufficientExecutionGas();"],
    ("modules/DegenerusGameAdvanceModule.sol", "_runJackpotWork"): [
        "gas: MineFlipGas.forwardable(gasleft(), 150_000)"],
    ("modules/DegenerusGameDecimatorModule.sol", "settleDecimatorWinners"): [
        "uint256 beforeGas = gasleft();", "return (result.rewardBasis, beforeGas - gasleft(), result.progressed);"],
    ("modules/DegenerusGameLootboxModule.sol", "openHumanBoxes"): [
        "uint256 beforeGas = gasleft();", "return (result.rewardBasis, beforeGas - gasleft());"],
    ("modules/DegenerusGameMinerModule.sol", "mineFlip"): [
        "uint256 rewardStart = gasleft();",
        # Entry admission occurs before work or state writes; insufficient gas reverts.
        "if (gasleft() < WORKER_BOUNDARY + RETURN_RESERVE + MineFlipGas.CHECK_RESERVE) {",
        "uint256 beforeCall = gasleft();",
        # Separate caught-refusal and successful-no-progress exits exclude their cost.
        "unpaidAttemptGas = beforeCall - gasleft();",
        "unpaidAttemptGas = beforeCall - gasleft();",
        "uint256 used = rewardStart - gasleft() - unpaidAttemptGas;"],
    ("modules/DegenerusGameTicketModule.sol", "_solo"): ["uint256 actual = gasleft();"],
    ("modules/GameAfkingModule.sol", "processSubscriberStageBudgeted"): [
        "uint256 beforeGas = gasleft();", "return (result.rewardBasis, beforeGas - gasleft());"],
    ("modules/GameAfkingModule.sol", "_autoOpen"): [
        "uint256 beforeGas = gasleft();", "return (result.rewardBasis, beforeGas - gasleft(), !result.done);"],
    ("modules/GameAfkingModule.sol", "drainAfkingBoxes"): [
        "uint256 beforeGas = gasleft();", "return (result.rewardBasis, beforeGas - gasleft());"],
}
GAS_READ = re.compile(r"\b(?:gasleft|gas)\s*\(")
AMBIENT = re.compile(r"\b(?:msg\s*\.\s*sender|tx\s*\.|block\s*\.|blockhash\s*\()")
DRAINS = set("""processTicketBatch processFutureTicketBatch _processOneTicketEntry
_raritySymbolBatch _drainSeatedSurvivors _drainRounds drainRounds _fillSeats
_seatEntry _runRound _processFoilDrain _resolveFoilBuyer _bucketAppendRun
_bucketAppendLanes _resolveZeroOwedRemainder _rollRemainder""".split())


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
