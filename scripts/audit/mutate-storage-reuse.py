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
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "contracts/modules/CoinflipCore.sol"
TEST = "test/fuzz/CoinflipStorageReuse.t.sol"
VAULT_TEST = "test/fuzz/VaultFlipBackstop.t.sol"
EXPECTED_ASSERTIONS = {
    "missing_overflow_read": "assertion failed",
    "missing_exact_tag": "new page cannot masquerade as old generation",
    "destroy_marker_on_spill_merge": "spill marker survives merge",
    "duplicate_home_after_recovery": "assertion failed",
    "early_live_page_reuse": "unresolved old page remains live",
    "claim_stale_page_writeback": "claim wrote stake storage",
    "discard_vault_mintable": "assertion failed",
    "double_bank_vault_mintable": "assertion failed",
}


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
         "totals.cachedStakeKey = stakeKey;\n            }\n            uint256 stake = uint32(cachedStakes >> ((cursor % 7) * 32));",
         "totals.cachedStakeKey = stakeKey;\n            }\n            uint256 stake = uint32(cachedStakes >> ((cursor % 7) * 32));\n"
         "            coinflipStakeRing[id][stakeKey % 15] = cachedStakes & ~(uint256(type(uint32).max) << ((cursor % 7) * 32));"),
        ("discard_vault_mintable", VAULT_TEST, "test_checkpointPrecedesEveryDailyBranchAndBanksExactlyOnce",
         "storedAfter = _toUint128Sat(uint256(storedAfter) + mintable);",
         "storedAfter = storedAfter;"),
        ("double_bank_vault_mintable", VAULT_TEST, "test_checkpointPrecedesEveryDailyBranchAndBanksExactlyOnce",
         "storedAfter = _toUint128Sat(uint256(storedAfter) + mintable);",
         "storedAfter = _toUint128Sat(uint256(storedAfter) + mintable * 2);"),
    ]


def validate_anchors(source, entries):
    """Reject drift before patching pins or invoking the compiler."""
    names = set()
    for label, _, _, old, new in entries:
        if label in names or source.count(old) != 1 or old == new:
            raise ValueError(f"{label}: mutation name/anchor must be unique and change the source")
        names.add(label)


def validate_tests(root, entries):
    for label, path, test_name, _, _ in entries:
        pattern = r"\bfunction\s+" + re.escape(test_name) + r"\s*\(\s*\)"
        if len(re.findall(pattern, (root / path).read_text())) != 1:
            raise ValueError(f"{path}: named zero-argument test {test_name} must exist exactly once")
        prefix = EXPECTED_ASSERTIONS.get(label, "assertion failed")
        if prefix != "assertion failed" and json.dumps(prefix) not in (root / path).read_text():
            raise ValueError(f"{label}: expected custom assertion label disappeared")


def classify_result(stdout, test_name, returncode, assertion_prefix="assertion failed"):
    """Only the exact test's structured assertion failure is a mutation kill.

    Compile errors, setup failures, empty selection, unrelated failing tests and
    arbitrary reverts are errors, even if stderr mentions an assertion.
    """
    invalid = {"passed": False, "killed": False, "status": "invalid-result"}
    try:
        suites = json.loads(stdout)
        results = [(suite, name, result) for suite, data in suites.items()
                   for name, result in data["test_results"].items()]
    except (ValueError, KeyError, TypeError, AttributeError):
        return invalid
    if len(results) != 1 or results[0][1] != test_name + "()":
        return invalid
    suite, _, result = results[0]
    status, reason = result.get("status"), result.get("reason") or ""
    if not isinstance(reason, str):
        return invalid
    passed = returncode == 0 and status == "Success"
    killed = returncode == 1 and status == "Failure" and bool(
        re.fullmatch(re.escape(assertion_prefix) + r": [0-9]+ != [0-9]+", reason))
    return {"passed": passed, "killed": killed, "status": status,
            "reason": reason, "suite": suite}


def run_child(argv, *, cwd, env, stdout, stderr, timeout):
    """Stop the entire compiler process group before a caller restores sources."""
    child = subprocess.Popen(argv, cwd=cwd, env=env, stdout=stdout, stderr=stderr,
                             start_new_session=True)
    try:
        code = child.wait(timeout=timeout)
        # Wrapper exit does not establish that its compiler descendants stopped.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        while process_group_running(child.pid):
            time.sleep(0.02)
        return code
    except BaseException:
        previous = {sig: signal.signal(sig, signal.SIG_IGN)
                    for sig in (signal.SIGINT, signal.SIGTERM)}
        try:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            # Waiting only for the forge parent leaves a race with its solc
            # children: the parent can exit before they process SIGTERM.
            deadline = time.monotonic() + 3
            while process_group_running(child.pid) and time.monotonic() < deadline:
                time.sleep(0.02)
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
            # Non-child descendants cannot be waitpid()'d. On this Linux runner,
            # wait until all group members have exited (zombies cannot read files)
            # before the caller restores the production inputs they were reading.
            while process_group_running(child.pid):
                time.sleep(0.02)
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)
        raise


def process_group_running(group):
    proc = Path('/proc')
    if not proc.is_dir():
        return False  # Other Unix platforms still receive the process-group SIGKILL.
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            fields = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if int(fields[2]) == group and fields[0] not in ('Z', 'X'):
            return True
    return False


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mutation_configuration(text):
    # Dynamic deployment fixtures read creation code from the selected artifact
    # directory. Grant only that directory read access in the disposable config;
    # compiler settings and the reviewed config itself remain unchanged.
    original = 'fs_permissions = [{ access = "read", path = "./contracts" }]'
    replacement = ('fs_permissions = [{ access = "read", path = "./contracts" }, '
                   '{ access = "read", path = "./forge-out-mutations" }]')
    if text.count(original) != 1:
        raise ValueError("review mutation artifact read permission after Foundry config changes")
    return text.replace(original, replacement)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-anchors", action="store_true", help="check current mutation/test anchors without writes or builds")
    parser.add_argument("--worktree", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=int, default=1800,
                        help="maximum seconds for each compiler/test process")
    args = parser.parse_args()
    if args.check_anchors:
        validate_anchors((ROOT / SOURCE).read_text(), mutations())
        validate_tests(ROOT, mutations())
        mutation_configuration((ROOT / "foundry.toml").read_text())
        print(json.dumps({"source": SOURCE, "mutations": len(mutations()), "status": "PASS"}))
        return 0
    if args.worktree is None or args.output is None:
        parser.error("--worktree and --output are required unless --check-anchors is selected")
    work = args.worktree.resolve()
    if work == ROOT or not (work / ".git").is_file() or args.timeout <= 0:
        parser.error("use a separate disposable git worktree and a positive timeout")
    def git(directory, *argv):
        return subprocess.check_output(["git", *argv], cwd=directory, text=True).strip()
    if Path(git(work, "rev-parse", "--show-toplevel")).resolve() != work:
        parser.error("worktree must be its own Git root")
    common = lambda directory: (directory / git(directory, "rev-parse", "--git-common-dir")).resolve()
    if common(work) != common(ROOT):
        parser.error("worktree must belong to this repository")
    target, pins = work / SOURCE, work / "contracts/ContractAddresses.sol"
    if any(not path.resolve().is_relative_to(work) for path in (target, pins)):
        parser.error("mutable sources must not link outside the disposable worktree")
    # Acquire before reading backup bytes; a second campaign must never back up
    # another run's in-flight mutation as its supposed original source.
    lock = (work / ".storage-reuse-mutation.lock").open("a")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    original_bytes, original_pins = target.read_bytes(), pins.read_bytes()
    original = original_bytes.decode()
    entries = mutations()
    validate_anchors(original, entries)
    validate_tests(work, entries)
    inputs = sorted({str(p.relative_to(ROOT)) for p in (ROOT / "contracts").rglob("*.sol")}
                    | {str(p.relative_to(work)) for p in (work / "test").rglob("*.sol")}
                    | {str(p.relative_to(ROOT)) for base in ("node_modules/@openzeppelin", "lib/forge-std/src")
                       for p in (ROOT / base).rglob("*.sol")}
                    | {TEST, VAULT_TEST, "foundry.toml", "foundry.lock", "package-lock.json", "package.json", "remappings.txt",
                       "scripts/lib/patchForFoundry.js", "scripts/lib/patchContractAddresses.js",
                       "scripts/lib/deploymentProfiles.js", "scripts/lib/deploymentManifest.js"})
    mismatch = [path for path in inputs if not (work / path).is_file()
                or (work / path).read_bytes() != (ROOT / path).read_bytes()]
    if mismatch:
        parser.error("worktree inputs differ from reviewed sources: " + ", ".join(mismatch))
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    logdir = work / ".audit-test-logs/storage-reuse/mutations"
    logdir.mkdir(parents=True, exist_ok=True)
    report = {"created_utc": datetime.now(timezone.utc).isoformat(), "source": SOURCE,
              "source_sha256": sha(target), "runner_sha256": sha(Path(__file__)),
              "root_head": git(ROOT, "rev-parse", "HEAD"), "worktree_head": git(work, "rev-parse", "HEAD"),
              "input_sha256": {path: sha(work / path) for path in inputs},
              "worktree": str(work), "runs": [], "restored": False, "all_killed": False}
    # Do not inherit profile/source/test overrides from the caller's shell.
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("FOUNDRY_") and k not in ("PROFILE", "CONSOLIDATION_CANDIDATE")}
    env.update(PROFILE="eip170", FOUNDRY_PROFILE="default", FOUNDRY_ISOLATE="false",
               FOUNDRY_DISABLE_NIGHTLY_WARNING="1",
               FOUNDRY_TEST=".audit-test-logs/storage-reuse/mutation-test")
    selected = work / env["FOUNDRY_TEST"]
    selected.mkdir(parents=True, exist_ok=True)
    source_dir = ".audit-test-logs/storage-reuse/mutation-src"
    (work / source_dir).mkdir(parents=True, exist_ok=True)
    config = work / ".audit-test-logs/storage-reuse/mutation-config/foundry.toml"
    config.parent.mkdir(parents=True, exist_ok=True)
    original_config = (work / "foundry.toml").read_bytes()
    config.write_text(mutation_configuration(original_config.decode()))
    report["disposable_config"] = {"path": str(config), "sha256": sha(config),
                                  "difference": "read-only permission for forge-out-mutations artifacts"}
    command = ["forge", "test", "--json", "--threads", "1", "--force", "--build-info", "--contracts", source_dir,
               "--out", "forge-out-mutations", "--cache-path", ".foundry-cache-mutations"]
    report["forge_version"] = subprocess.check_output(["forge", "--version"], env=env, text=True).strip()
    report["environment"] = {k: v for k, v in env.items() if k.startswith("FOUNDRY_") or k == "PROFILE"}

    def save():
        output.write_text(json.dumps(report, indent=2) + "\n")

    def run(label, source_test, test_name, old=None, new=None):
        for path in selected.glob("*.sol"):
            path.unlink()
        test_source = work / source_test
        def absolute_import(match):
            path = match.group(2)
            if path.startswith("."):
                path = (test_source.parent / path).resolve().relative_to(work).as_posix()
            return match.group(1) + path + match.group(1)
        content = re.sub(r'(["\x27])([^"\x27]+\.sol)\1', absolute_import, test_source.read_text())
        (selected / "Selected.t.sol").write_text(content)
        if source_test == VAULT_TEST:
            # DeployProtocol creates profile shells by artifact name; importing
            # its Solidity helpers alone no longer builds all dynamic targets.
            shells = sorted((work / "contracts/profiles/eip170").glob("*.sol"))
            (selected / "ProfileDeployables.sol").write_text(
                'pragma solidity 0.8.38;\n' + ''.join(
                    f'import * as Profile{i} from "{path.relative_to(work).as_posix()}";\n'
                    for i, path in enumerate(shells)))
            # Non-test .sol files in the test root are not standalone compile
            # roots. Import this adapter explicitly so dynamic deployCode()
            # targets exist in this freshly built artifact set.
            (selected / "Selected.t.sol").write_text(content + '\nimport "./ProfileDeployables.sol";\n')
        target.write_bytes(original_bytes if old is None else original.replace(old, new).encode())
        argv = [*command, "--match-test", f"^{re.escape(test_name)}\\(\\)$"]
        logpath, resultpath = logdir / f"{label}.log", logdir / f"{label}.json"
        with resultpath.open("w") as stdout, logpath.open("w") as stderr:
            code = run_child(argv, cwd=work, env=env, stdout=stdout, stderr=stderr, timeout=args.timeout)
        prefix = EXPECTED_ASSERTIONS.get(label, "assertion failed")
        outcome = classify_result(resultpath.read_text(), test_name, code, prefix)
        compiler_path = logdir / f"{label}-compiler-inputs.json"
        compiler_inputs = []
        for info in sorted((work / "forge-out-mutations/build-info").glob("*.json")):
            data = json.loads(info.read_text())
            request = data.get("input", {})
            sources = {}
            for path, body in request.get("sources", {}).items():
                content = body["content"].encode()
                source_file = work / path
                if not source_file.is_file():
                    source_file = work / "node_modules" / path
                if not source_file.is_file() or source_file.read_bytes() != content:
                    raise RuntimeError(f"compiler input does not match current source: {path}")
                sources[path] = hashlib.sha256(content).hexdigest()
            if not sources:
                raise RuntimeError("compiler evidence has no source inputs")
            compiler_inputs.append({"solc_version": data.get("solcLongVersion"),
                                    "settings": request.get("settings"), "sources_sha256": sources})
        compiler_path.write_text(json.dumps(compiler_inputs, indent=2) + "\n")
        if not compiler_inputs:
            outcome = {"passed": False, "killed": False, "status": "missing-compiler-inputs"}
        row = {"name": label, "test": source_test, "test_name": test_name,
               "exit_code": code, "baseline": old is None, **outcome,
               "log": str(logpath), "log_sha256": sha(logpath),
               "result_json": str(resultpath), "result_sha256": sha(resultpath),
               "expected_assertion_prefix": prefix,
               "compiler_inputs": str(compiler_path), "compiler_inputs_sha256": sha(compiler_path),
               "test_sha256": sha(test_source), "compiled_test_sha256": sha(selected / "Selected.t.sol"),
               "mutated_sha256": sha(target), "pins_sha256": sha(pins),
               "old": old, "new": new, "command": argv}
        report["runs"].append(row)
        save()
        print(json.dumps({k: row[k] for k in ("name", "passed", "killed", "exit_code", "status")}), flush=True)
        return outcome["passed"] if old is None else outcome["killed"]

    def interrupt(signum, _frame):
        raise InterruptedError(f"received {signal.Signals(signum).name}")
    handlers = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGINT, signal.SIGTERM)}
    save()
    try:
        # Foundry resolves relative paths from the config directory, so install
        # the read-only test permission at the disposable root and restore it.
        (work / "foundry.toml").write_bytes(config.read_bytes())
        with (logdir / "patch-pins.log").open("w") as log:
            code = run_child(["node", "scripts/lib/patchForFoundry.js"], cwd=work, env=env,
                             stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
        if code:
            raise RuntimeError("address-pin setup failed")
        baselines = set()
        ok = True
        for label, source_test, test_name, old, new in entries:
            key = (source_test, test_name)
            if key not in baselines:
                if not run("baseline_" + test_name, source_test, test_name):
                    raise RuntimeError("mutation campaign baseline failed")
                baselines.add(key)
            ok = run(label, source_test, test_name, old, new) and ok
        report["all_killed"] = ok
        return 0 if ok else 1
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
        print(report["error"], file=sys.stderr)
        return 1
    finally:
        target.write_bytes(original_bytes)
        pins.write_bytes(original_pins)
        (work / "foundry.toml").write_bytes(original_config)
        report["restored"] = (target.read_bytes() == original_bytes and pins.read_bytes() == original_pins
                              and (work / "foundry.toml").read_bytes() == original_config)
        report["completed_utc"] = datetime.now(timezone.utc).isoformat()
        save()
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


if __name__ == "__main__":
    raise SystemExit(main())
