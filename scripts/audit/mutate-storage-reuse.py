#!/usr/bin/env python3
"""Run deliberate production mutations in a separate disposable checkout.

Each mutant must compile and fail the named assertion test. Compiler failures do
not count as kills. Original sources and address pins are restored in finally.
Never run this against the checkout containing this script.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "contracts/Coinflip.sol"
TEST = "test/fuzz/CoinflipStorageReuse.t.sol"
VAULT_TEST = "test/fuzz/VaultFlipBackstop.t.sol"


def mutations():
    return [
        ("missing_overflow_read", TEST, "test_claimsKeepPagesAndSpillHomeSurvivesRecovery",
         "if (uint24(word >> 224) != page + 1) word = coinflipStakeOverflow[id][page];",
         "if (uint24(word >> 224) != page + 1) word = 0;"),
        ("missing_exact_tag", TEST, "test_readerRejectsStaleRingGeneration",
         "if (uint24(word >> 224) != page + 1) word = coinflipStakeOverflow[id][page];\n        if (uint24(word >> 224) != page + 1) return 0;",
         "return word;"),
        ("destroy_marker_on_spill_merge", TEST, "test_spillMergePreservesMarkerThroughLaterRecovery",
         "word = existing;\n                spill = true;",
         "word = existing;\n                coinflipStakeRing[id][index] &= type(uint248).max;\n                spill = true;"),
        ("duplicate_home_after_recovery", TEST, "test_claimsKeepPagesAndSpillHomeSurvivesRecovery",
         "if (uint24(existing >> 224) == page + 1) {", "if (false) {"),
        ("early_live_page_reuse", TEST, "test_liveCollisionKeepsBothPages",
         "if (word != 0 && !_flipStakePageReusable(id, word)) {", "if (false) {"),
        ("claim_stale_page_writeback", TEST, "test_claimsKeepPagesAndSpillHomeSurvivesRecovery",
         "uint256 storedStake = uint32(cachedStakes >> ((cursor % 7) * 32));",
         "uint256 storedStake = uint32(cachedStakes >> ((cursor % 7) * 32));\n"
         "            coinflipStakeRing[id][stakeKey % 15] = cachedStakes & ~(uint256(type(uint32).max) << ((cursor % 7) * 32));"),
        ("discard_vault_mintable", VAULT_TEST, "test_checkpointPrecedesEveryDailyBranchAndBanksExactlyOnce",
         "storedAfter = _toUint128Sat(uint256(storedAfter) + mintable);",
         "storedAfter = storedAfter;"),
        ("double_bank_vault_mintable", VAULT_TEST, "test_checkpointPrecedesEveryDailyBranchAndBanksExactlyOnce",
         "storedAfter = _toUint128Sat(uint256(storedAfter) + mintable);",
         "storedAfter = _toUint128Sat(uint256(storedAfter) + mintable * 2);"),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worktree", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    work = args.worktree.resolve()
    if work == ROOT or not (work / ".git").is_file():
        parser.error("use a separate disposable git worktree")
    target = work / SOURCE
    pins = work / "contracts/ContractAddresses.sol"
    original = target.read_text()
    original_pins = pins.read_bytes()
    if original != (ROOT / SOURCE).read_text():
        parser.error("worktree Coinflip must match the reviewed source")
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    logdir = work / ".audit-test-logs/storage-reuse/mutations"
    logdir.mkdir(parents=True, exist_ok=True)
    report = {"created_utc": datetime.now(timezone.utc).isoformat(),
              "source": SOURCE, "source_sha256": hashlib.sha256(original.encode()).hexdigest(),
              "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "worktree": str(work), "runs": [], "restored": False}
    lock = (work / ".storage-reuse-mutation.lock").open("a")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    env = dict(os.environ, FOUNDRY_DISABLE_NIGHTLY_WARNING="1")
    # This campaign compiles only the selected test and its imports. It is not
    # a substitute for the repository-wide production build or test runner.
    env["FOUNDRY_TEST"] = ".audit-test-logs/storage-reuse/mutation-test"
    selected = work / env["FOUNDRY_TEST"]
    selected.mkdir(parents=True, exist_ok=True)
    source_dir = ".audit-test-logs/storage-reuse/mutation-src"
    (work / source_dir).mkdir(parents=True, exist_ok=True)
    command = ["forge", "test", "-vv", "--contracts", source_dir,
               "--out", "forge-out-mutations", "--cache-path", ".foundry-cache-mutations"]

    def run(label, source_test, test_name, old=None, new=None):
        for path in selected.glob("*.sol"):
            path.unlink()
        # Forge discovers tests within its test root. Copy the actual assertion
        # source, rewriting relative import paths without altering test bodies.
        test_source = work / source_test
        def absolute_import(match):
            path = match.group(2)
            if path.startswith("."):
                path = (test_source.parent / path).resolve().relative_to(work).as_posix()
            return match.group(1) + path + match.group(1)
        content = re.sub(r'([\"\x27])([^\"\x27]+\.sol)\1', absolute_import, test_source.read_text())
        (selected / "Selected.t.sol").write_text(content)
        if old is not None:
            if original.count(old) != 1:
                raise RuntimeError(f"{label}: mutation anchor is not unique")
            target.write_text(original.replace(old, new))
        else:
            target.write_text(original)
        argv = [*command, "--match-test", f"^{test_name}\\("]
        logpath = logdir / f"{label}.log"
        with logpath.open("w") as log:
            result = subprocess.run(argv, cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT)
        text = logpath.read_text()
        passed = result.returncode == 0 and "[PASS]" in text
        killed = result.returncode != 0 and bool(re.search(
            r"\[FAIL: [^\n]*(?:assertion failed|!=)[^\n]*\] " + re.escape(test_name) + r"\(\)", text))
        row = {"name": label, "test": source_test, "test_name": test_name,
               "exit_code": result.returncode, "baseline": old is None,
               "passed": passed, "killed": killed, "log": str(logpath),
               "log_sha256": hashlib.sha256(logpath.read_bytes()).hexdigest(),
               "mutated_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
               "old": old, "new": new, "command": argv}
        report["runs"].append(row)
        output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({k: row[k] for k in ["name", "passed", "killed", "exit_code"]}), flush=True)
        return passed if old is None else killed

    try:
        subprocess.run(["node", "scripts/lib/patchForFoundry.js"], cwd=work, check=True,
                       stdout=subprocess.DEVNULL)
        baselines = set()
        ok = True
        for label, source_test, test_name, old, new in mutations():
            if test_name not in baselines:
                if not run("baseline_" + test_name, source_test, test_name):
                    raise RuntimeError("mutation campaign baseline failed")
                baselines.add(test_name)
            ok = run(label, source_test, test_name, old, new) and ok
        report["all_killed"] = ok
        return 0 if ok else 1
    finally:
        target.write_text(original)
        pins.write_bytes(original_pins)
        report["restored"] = target.read_text() == original and pins.read_bytes() == original_pins
        output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
