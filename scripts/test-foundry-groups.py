#!/usr/bin/env python3
"""Run Foundry tests in small compile batches, record evidence, and restore pins."""

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
import uuid


ROOT = Path(__file__).resolve().parents[1]
# Count selected source roots, not transitive imports. Imported helpers remain available.
# Twenty roots leaves headroom below the former 89-source integration/gas compilation.
DEFAULT_BATCH_SOURCES = 20
TOTALS = re.compile(
    r"Ran (\d+) test suites? in .*?: (\d+) tests? passed, (\d+) failed, (\d+) skipped"
)
ENV_KEYS = (
    "FOUNDRY_PROFILE", "FOUNDRY_ISOLATE", "FOUNDRY_FUZZ_RUNS", "FOUNDRY_FUZZ_SEED",
    "FOUNDRY_INVARIANT_RUNS", "FOUNDRY_INVARIANT_DEPTH", "FOUNDRY_INVARIANT_FAIL_ON_REVERT",
    "FOUNDRY_SOLC", "FOUNDRY_SOLC_VERSION", "FOUNDRY_VIA_IR", "FOUNDRY_OPTIMIZER",
    "FOUNDRY_OPTIMIZER_RUNS", "FOUNDRY_EVM_VERSION", "FOUNDRY_CACHE_PATH", "FOUNDRY_OUT",
    "FOUNDRY_GAS_LIMIT", "FOUNDRY_BLOCK_GAS_LIMIT",
)


def groups():
    files = sorted(Path("test").rglob("*.sol"))
    # Every non-test source stays compiled: a skipped helper still compiles as an import, but
    # its artifact is not emitted, so forge cannot identify the contract an invariant targets.
    support = {p for p in files if not p.name.endswith(".t.sol")}
    fuzz = sorted(Path("test/fuzz").glob("*.t.sol"))
    result = {
        "integration-gas": {p for p in files if p.parts[1] in {
            "craps", "differential", "economics", "gas", "mutation", "invariant"}},
        "repro-symbolic": {p for p in files if p.parts[1] in {"repro", "halmos"}},
    }
    chunk = max(1, (len(fuzz) + 3) // 4)
    for i in range(4):
        result[f"fuzz-{i + 1}"] = set(fuzz[i * chunk:(i + 1) * chunk])
    result["invariants"] = set(Path("test/fuzz/invariant").rglob("*.sol"))
    missing = set(files) - support - set().union(*result.values())
    if missing:
        raise ValueError("Unassigned Solidity test sources: " + ", ".join(map(str, sorted(missing))))
    return files, support, result


def split_batches(selected, maximum):
    for group, sources in selected.items():
        ordered = sorted(sources)
        # Only integration-gas has demonstrated compiler memory exhaustion. Keep the
        # other established groups intact unless the caller explicitly asks for a cap.
        cap = maximum if maximum is not None else (
            DEFAULT_BATCH_SOURCES if group == "integration-gas" else len(ordered))
        for offset in range(0, len(ordered), cap):
            number = offset // cap + 1
            yield group, f"{group}-{number:02d}", set(ordered[offset:offset + cap])


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def source_identity():
    # Include the complete source tree, imported Solidity libraries, and build/pin inputs.
    # The manifest is captured AFTER patchForFoundry, so its addresses match compilation.
    paths = set()
    for directory in ("contracts", "test", "lib", "node_modules"):
        paths.update(p for p in Path(directory).rglob("*.sol") if p.is_file())
    # Gas/reference tests deploy checked-in bytecode read through vm.readFile.
    # These blobs affect execution even though solc never imports them.
    for directory in ("contracts", "test"):
        paths.update(p for p in Path(directory).rglob("*.hex") if p.is_file())
    paths.update(p for p in Path("scripts/lib").glob("*.js") if p.is_file())
    paths.add(Path("scripts/test-foundry-groups.py"))
    for name in ("foundry.toml", "remappings.txt", "package.json", "package-lock.json", "yarn.lock"):
        if Path(name).is_file():
            paths.add(Path(name))
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def command_output(command):
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        return result.stdout.strip() if result.returncode == 0 else None
    except OSError:
        return None


def validate_source_layout(arguments):
    """The batching/discovery contract owns this checkout's captured source roots."""
    redirects = {"--root", "--contracts", "--lib-paths", "--remappings",
                 "--remappings-env", "--config-path"}
    for argument in arguments:
        if argument.split("=", 1)[0] in redirects or argument.startswith(("-C", "-R")):
            raise ValueError("Source/config relocation is not supported; run the driver in its isolated checkout")
    if any(os.environ.get(key) for key in ("FOUNDRY_ROOT", "DAPP_ROOT", "FOUNDRY_CONFIG", "DAPP_CONFIG")):
        raise ValueError("Source/config relocation environment is not supported")
    # Check effective configuration, so profile and legacy environment overrides
    # cannot silently move inputs outside the trees source_identity captures.
    result = subprocess.run(["forge", "config", "--json"], capture_output=True, text=True)
    if result.returncode:
        raise ValueError("Unable to validate effective Forge source configuration")
    config = json.loads(result.stdout)
    paths = {key: config.get(key, [] if key not in {"src", "test"} else None)
             for key in ("src", "test", "libs", "remappings", "include_paths", "allow_paths")}
    def local(path):
        # Keep lexical paths: snapshot dependency roots may intentionally be symlinks.
        return Path(os.path.abspath(path))
    if local(paths["src"]) != ROOT / "contracts" or local(paths["test"]) != ROOT / "test":
        raise ValueError("Effective Forge src/test must use captured contracts/ and test/ roots")
    allowed = [ROOT / name for name in ("contracts", "test", "lib", "node_modules")]
    targets = [*paths["libs"], *paths["include_paths"], *paths["allow_paths"]]
    for mapping in paths["remappings"]:
        if "=" not in mapping:
            raise ValueError("Malformed effective Forge remapping")
        targets.append(mapping.split("=", 1)[1])
    if any(not any(local(target).is_relative_to(root) for root in allowed) for target in targets):
        raise ValueError("Effective Forge dependency path is outside captured source roots")
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--group", action="append", help="Run this logical group, in bounded batches (repeatable)")
    parser.add_argument("--file", action="append", help="Run only these test sources (repeatable)")
    parser.add_argument("--max-sources-per-batch", "--max-files", type=int,
                        help="Cap roots in every selected group; default splits only integration-gas at 20")
    parser.add_argument("--log-dir", default=".audit-test-logs/foundry")
    parser.add_argument("--list", action="store_true", help="List groups/batches without building or patching")
    args, forge_args = parser.parse_known_args()
    if args.max_sources_per_batch is not None and args.max_sources_per_batch < 1:
        parser.error("--max-sources-per-batch must be positive")
    os.chdir(ROOT)
    try:
        source_layout = validate_source_layout(forge_args)
        files, support, selected = groups()
    except (ValueError, OSError, TypeError) as error:
        parser.error(str(error))
    if args.file:
        keep = {Path(p) for p in args.file}
        if not keep <= set(files):
            parser.error("Unknown test source")
        selected = {"focused": keep}
    if args.group:
        unknown = set(args.group) - selected.keys()
        if unknown:
            parser.error("Unknown groups: " + ", ".join(sorted(unknown)))
        selected = {name: keep for name, keep in selected.items() if name in args.group}
    # Empty groups can occur in small fixtures or after sources are moved. An explicitly
    # requested empty selection is an error; a full-tree run ignores unused group names.
    if args.group and any(not keep for keep in selected.values()):
        parser.error("Selected group contains no Solidity test sources")
    selected = {name: keep for name, keep in selected.items() if keep}
    if not selected:
        parser.error("No Solidity test sources selected")
    batches = list(split_batches(selected, args.max_sources_per_batch))
    if args.list:
        for name, keep in selected.items():
            count = sum(group == name for group, _, _ in batches)
            label = "batch" if count == 1 else "batches"
            print(f"{name}: {len(keep)} source files, {count} {label}")
        print(f"Total: {len(batches)} physical batches")
        return 0

    log_dir = Path(args.log_dir).resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    summary_path = log_dir / "summary.json"
    try:
        history = json.loads(summary_path.read_text()) if summary_path.exists() else []
        if not isinstance(history, list):
            raise ValueError("summary must be a JSON array")
    except (OSError, ValueError) as error:
        parser.error(f"Cannot preserve existing summary: {error}")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + "-" + uuid.uuid4().hex[:8]
    run_dir = log_dir / run_id
    run_dir.mkdir()
    env = dict(os.environ)
    env.setdefault("FOUNDRY_CACHE_PATH", str(ROOT / ".foundry-cache"))
    env.setdefault("FOUNDRY_DISABLE_NIGHTLY_WARNING", "1")
    pins = ROOT / "contracts/ContractAddresses.sol"
    original_pins = pins.read_bytes()
    current = []
    metadata = {
        "run_id": run_id, "cwd": str(ROOT), "base_commit": command_output(["git", "rev-parse", "HEAD"]),
        "forge_version": command_output(["forge", "--version"]),
        "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "effective_source_layout": source_layout,
        "environment": {key: env[key] for key in ENV_KEYS if key in env},
        "forge_arguments": forge_args, "max_sources_per_batch": args.max_sources_per_batch,
        "default_group_caps": {"integration-gas": DEFAULT_BATCH_SOURCES},
        "physical_batches": len(batches),
        "test_count_semantics": "execution counts; imported helper suites may repeat between batches",
        "selected_sources": {name: list(map(str, sorted(keep))) for name, keep in selected.items()},
        "original_pins_sha256": hashlib.sha256(original_pins).hexdigest(),
        "patch_command": ["node", "scripts/lib/patchForFoundry.js"],
    }
    write_json(run_dir / "run.json", metadata)

    def record(row):
        row["run_id"] = run_id
        current.append(row)
        # Different isolated checkouts may share a log directory. Serialize the
        # read/append/replace so one writer cannot discard another run's evidence.
        with (log_dir / "summary.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            rows = json.loads(summary_path.read_text()) if summary_path.exists() else []
            if not isinstance(rows, list):
                raise ValueError("summary must be a JSON array")
            write_json(summary_path, [*rows, row])
        write_json(run_dir / "summary.json", current)
        print(json.dumps({key: value for key, value in row.items() if key in {
            "run_id", "group", "batch", "exit_code", "source_files", "suites", "passed",
            "failed", "skipped", "errors", "log"}}), flush=True)

    class RunnerInterrupted(Exception):
        pass

    def terminate(signum, _frame):
        # Do not reenter Popen.wait/poll from a signal handler: its wait lock may
        # already be held. run_child unwinds that wait before stopping the group.
        raise RunnerInterrupted(f"received {signal.Signals(signum).name}")

    def run_child(command, **kwargs):
        child = subprocess.Popen(command, start_new_session=True, **kwargs)
        try:
            return child.wait()
        except BaseException:
            # Stop Forge and solc before restoring their compile inputs. Ignore
            # repeated interrupts only while performing this bounded cleanup.
            handlers = {sig: signal.signal(sig, signal.SIG_IGN)
                        for sig in (signal.SIGTERM, signal.SIGINT)}
            try:
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
            finally:
                for sig, handler in handlers.items():
                    signal.signal(sig, handler)
            raise

    pending_row = None
    previous_handlers = {sig: signal.signal(sig, terminate) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        with (run_dir / "address-patch.log").open("w") as log:
            patch_code = run_child(metadata["patch_command"], stdout=log, stderr=subprocess.STDOUT)
        if patch_code:
            raise subprocess.CalledProcessError(patch_code, metadata["patch_command"])
        for group, name, keep in batches:
            (run_dir / f"{name}-files.txt").write_text("".join(f"{p}\n" for p in sorted(keep)))
            skip = [arg for p in files if p not in keep | support for arg in ("--skip", str(p))]
            command = ["forge", "test", "-vv", *skip, *forge_args]
            identity = source_identity()
            input_path = run_dir / f"{name}-inputs.json"
            write_json(input_path, identity)
            log_path = run_dir / f"{name}.log"
            evidence = {"command": command, "cwd": str(ROOT), "environment": metadata["environment"],
                        "selected_sources": list(map(str, sorted(keep))),
                        "input_manifest": str(input_path.relative_to(log_dir)),
                        "input_manifest_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest()}
            write_json(run_dir / f"{name}-command.json", evidence)
            print(f"Running {name} ({group}); log: {log_path}", flush=True)
            row = {"group": group, "batch": name, "source_files": len(keep),
                   "log": str(log_path.relative_to(log_dir)), **evidence}
            pending_row = row
            with log_path.open("w") as log:
                forge_code = run_child(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            output = log_path.read_text(errors="replace")
            totals = TOTALS.findall(output)
            errors = []
            row["forge_exit_code"] = forge_code
            if forge_code:
                errors.append(f"forge exited {forge_code}")
            if not totals:
                errors.append("missing final Forge test totals")
            else:
                suites, passed, failed, skipped = map(int, totals[-1])
                row.update(suites=suites, passed=passed, failed=failed, skipped=skipped)
                # Skipped cases are evidence of omission, not executed tests.
                if suites == 0 or passed + failed == 0:
                    errors.append("zero test suites or tests executed")
                if failed:
                    errors.append(f"Forge reported {failed} failed tests")
            if source_identity() != identity:
                errors.append("source/build inputs changed during this batch")
            row["exit_code"] = 1 if errors else 0
            if errors:
                row["errors"] = errors
            record(row)
            pending_row = None
            if errors:
                print("\n".join(output.splitlines()[-60:]), flush=True)
    except (OSError, subprocess.CalledProcessError, KeyboardInterrupt, RunnerInterrupted) as error:
        failure = pending_row if pending_row is not None else {"group": "runner", "batch": "runner"}
        failure.update(exit_code=1, errors=[f"{type(error).__name__}: {error}"])
        record(failure)
    finally:
        pins.write_bytes(original_pins)
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)
    return int(not current or any(row["exit_code"] for row in current))


if __name__ == "__main__":
    sys.exit(main())
