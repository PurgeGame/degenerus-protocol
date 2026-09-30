#!/usr/bin/env python3
"""Run Hardhat in file batches, retain compiler inputs and history, and restore pins."""

import argparse
import ast
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
PIN = Path("contracts/ContractAddresses.sol")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
TOTAL = re.compile(r"^\s*(\d+) (passing|failing|pending)\b", re.MULTILINE)
ENV_KEYS = ("NODE_OPTIONS", "HARDHAT_NETWORK", "HARDHAT_MAX_MEMORY", "CI")
VALUE_FLAGS = {"--grep", "--network", "--config", "--max-memory", "--tsconfig", "--reporter", "--timeout"}
BOOLEAN_FLAGS = {"--no-compile", "--parallel", "--bail", "--show-stack-traces", "--version", "--help",
                 "--emoji", "--verbose", "--flamegraph", "--typecheck"}

# Hardhat 2 calls these methods with the actual standard-json input BEFORE starting
# solc. Capturing only final build-info misses failed compiles and fixture clean/rebuilds.
# This hook deliberately fails closed if the installed compiler API is incompatible.
CAPTURE_HOOK = r'''"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const Module = require("node:module");
const root = process.env.DEGENERUS_HARDHAT_EVIDENCE;
if (root) {
  const append = (entry) => fs.appendFileSync(path.join(root, "events.jsonl"),
    JSON.stringify({pid: process.pid, ...entry}) + "\n");
  append({event: "preload", node: process.version});
  const load = Module._load;
  const wrapped = Symbol.for("degenerus.audit.compiler-input");
  const binaryHashes = new Map();
  Module._load = function(request, parent, isMain) {
    const result = load.apply(this, arguments);
    if (result && (result.Compiler || result.NativeCompiler)) {
      const filename = Module._resolveFilename(request, parent);
      if (/[\\/]hardhat[\\/]internal[\\/]solidity[\\/]compiler[\\/]index\.js$/.test(filename)) {
        for (const kind of ["Compiler", "NativeCompiler"]) {
          const prototype = result[kind] && result[kind].prototype;
          if (!prototype || typeof prototype.compile !== "function")
            throw new Error("Unsupported Hardhat compiler API: " + kind);
          if (prototype[wrapped]) continue;
          const compile = prototype.compile;
          prototype.compile = function(input) {
            const raw = JSON.stringify(input);
            const digest = crypto.createHash("sha256").update(raw).digest("hex");
            const target = path.join(root, "compiler-inputs", digest + ".json");
            try { fs.writeFileSync(target, raw, {flag: "wx"}); }
            catch (error) { if (error.code !== "EEXIST") throw error; }
            const compiler = this._pathToSolc || this._pathToSolcJs;
            if (compiler && !binaryHashes.has(compiler))
              binaryHashes.set(compiler, crypto.createHash("sha256")
                .update(fs.readFileSync(compiler)).digest("hex"));
            append({event: "compiler-input", kind, input_sha256: digest,
              compiler, compiler_sha256: binaryHashes.get(compiler),
              solc_version: this._solcVersion || null});
            return compile.apply(this, arguments);
          };
          prototype[wrapped] = true;
          append({event: "compiler-api", kind, module: filename,
            module_sha256: crypto.createHash("sha256").update(fs.readFileSync(filename)).digest("hex")});
        }
      }
    }
    return result;
  };
}
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, data):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)


def discover(config):
    """Read the same literal order used by Hardhat; never maintain a second list."""
    source = config.read_text()
    match = re.search(r"\bconst\s+TEST_DIR_ORDER\s*=\s*(\[[\s\S]*?\])\s*;", source)
    if not match:
        raise ValueError(f"No literal TEST_DIR_ORDER found in {config}")
    try:
        order = ast.literal_eval(match[1])
    except (ValueError, SyntaxError) as error:
        raise ValueError("TEST_DIR_ORDER must be a literal string array") from error
    if (not isinstance(order, list) or not order or
            any(not isinstance(p, str) or not p or Path(p).is_absolute() or ".." in Path(p).parts
                for p in order) or len(set(order)) != len(order)):
        raise ValueError("Invalid or duplicate TEST_DIR_ORDER entries")
    tests = Path("test")
    paths = re.search(r"\bpaths\s*:\s*\{([^}]*)\}", source)
    if paths and re.search(r"\btests\s*:", paths[1]):
        value = re.search(r"\btests\s*:\s*(['\"])(.*?)\1\s*[,}]?", paths[1])
        if not value:
            raise ValueError("Hardhat paths.tests must be a literal path")
        tests = Path(value[2])
    files = [p for folder in order for p in sorted((tests / folder).rglob("*.test.js"))]
    unassigned = set(tests.rglob("*.test.js")) - set(files)
    if unassigned:
        raise ValueError("Unassigned Hardhat test sources: " + ", ".join(map(str, sorted(unassigned))))
    return order, files


def split_forwarded(arguments):
    """Legacy positional test paths select files, rather than joining every batch."""
    files, flags = [], []
    index = 0
    while index < len(arguments):
        token = arguments[index]
        if token.startswith("--"):
            flags.append(token)
            if "=" not in token and token not in BOOLEAN_FLAGS:
                if index + 1 < len(arguments) and not arguments[index + 1].startswith("--"):
                    value = arguments[index + 1]
                    if token not in VALUE_FLAGS and Path(value).suffix in {".js", ".cjs", ".mjs", ".ts"}:
                        raise ValueError(f"Ambiguous path after {token}; select tests with --file, or use {token}=VALUE")
                    flags.append(value)
                    index += 1
                elif token in VALUE_FLAGS:
                    raise ValueError(f"Missing value for {token}")
        elif Path(token).suffix in {".js", ".cjs", ".mjs", ".ts"}:
            files.append(token)
        else:
            raise ValueError(f"Unexpected positional argument {token!r}; select test paths with --file")
        index += 1
    return files, flags


def source_identity(config):
    paths = {config, Path(__file__).relative_to(ROOT)}
    for folder, suffixes in (("contracts", {".sol"}), ("test", {".sol", ".js", ".cjs", ".mjs", ".ts"}),
                             ("scripts", {".js", ".cjs", ".mjs", ".py", ".json", ".tsv", ".sh"}),
                             ("lib", {".sol"}), ("node_modules", {".sol"})):
        paths.update(p for p in Path(folder).rglob("*") if p.is_file() and p.suffix in suffixes)
    for name in ("package.json", "package-lock.json", "yarn.lock", "foundry.toml", "tsconfig.json", "docs/AUDIT.md",
                 "docs/audit/snapshot.json", "scope.txt",
                 "node_modules/hardhat/package.json", "node_modules/hardhat/internal/solidity/compiler/index.js"):
        if Path(name).is_file():
            paths.add(Path(name))
    return {str(p): digest(p.read_bytes()) for p in sorted(paths) if p != PIN}


def build_info_input(path):
    """Read only the input prefix; build-info outputs can be hundreds of megabytes."""
    text = ""
    decoder = json.JSONDecoder()
    with path.open() as stream:
        while chunk := stream.read(65536):
            text += chunk
            match = re.search(r'"input"\s*:\s*', text)
            if match:
                try:
                    value, _ = decoder.raw_decode(text, match.end())
                    header = json.loads(text[:match.end()] + "null}")
                    return value, {key: header.get(key) for key in ("solcVersion", "solcLongVersion")}
                except json.JSONDecodeError:
                    continue
    raise ValueError(f"Missing or malformed compiler input: {path}")


def capture_cached_inputs(destination, phase):
    records = []
    for path in sorted(Path("artifacts/build-info").glob("*.json")):
        value, versions = build_info_input(path)
        raw = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode()
        sha = digest(raw)
        target = destination / "compiler-inputs" / f"{sha}.json"
        if not target.exists():
            target.write_bytes(raw)
        records.append({"origin": f"{phase}-available-build-info", "path": str(path),
                        "input_sha256": sha, **versions})
    return records


class Interrupted(Exception):
    pass


def run_child(command, **kwargs):
    child = subprocess.Popen(command, start_new_session=True, **kwargs)
    try:
        code = child.wait()
        # A crashed wrapper must not leave solc running against pins we restore.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        return code
    except BaseException:
        handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGTERM, signal.SIGINT)}
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
            # A wrapper can exit before its compiler/grandchild; clean the whole group.
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--file", action="append", help="Only this test file (repeatable, in supplied order)")
    parser.add_argument("--max-files", type=int, default=1, help="Files per process (default: 1)")
    parser.add_argument("--log-dir", default=".audit-test-logs/hardhat")
    parser.add_argument("--list", action="store_true", help="Show selected files/batches without running tools")
    args, forwarded = parser.parse_known_args()
    if forwarded[:1] == ["--"]:
        forwarded = forwarded[1:]
    if args.max_files < 1:
        parser.error("--max-files must be positive")
    os.chdir(ROOT)
    try:
        positional, forwarded = split_forwarded(forwarded)
    except ValueError as error:
        parser.error(str(error))
    config = Path("hardhat.config.js")
    for i, value in enumerate(forwarded):
        if value == "--config" and i + 1 < len(forwarded):
            config = Path(forwarded[i + 1])
        elif value.startswith("--config="):
            config = Path(value.split("=", 1)[1])
    try:
        config = config.resolve().relative_to(ROOT)
        if config != Path("hardhat.config.js"):
            raise ValueError("Custom config layouts are not captured; use hardhat.config.js in an isolated checkout")
        if any(flag.split("=", 1)[0] == "--tsconfig" for flag in forwarded):
            raise ValueError("Custom --tsconfig inputs are not captured; use the checkout's tsconfig.json")
        for key, default in (("HARDHAT_CONFIG", "hardhat.config.js"), ("TS_NODE_PROJECT", "tsconfig.json")):
            if os.environ.get(key) and Path(os.environ[key]).resolve() != ROOT / default:
                raise ValueError(f"Custom {key} inputs are not captured")
        order, discovered = discover(config)
        explicit = (args.file or []) + positional
        selected = [Path(p).resolve().relative_to(ROOT) for p in (explicit or discovered)]
        if not selected or any(not p.is_file() or p.suffix not in {".js", ".cjs", ".mjs", ".ts"}
                               for p in selected):
            raise ValueError("No test files selected, or an explicit file is missing/unsupported")
        if any(p.parts[0] not in {"test", "scripts"} for p in selected):
            raise ValueError("Selected tests must be inside captured test/ or scripts/ source roots")
        if len(set(selected)) != len(selected):
            raise ValueError("Duplicate selected test files")
    except (ValueError, OSError) as error:
        parser.error(str(error))
    batches = [selected[i:i + args.max_files] for i in range(0, len(selected), args.max_files)]
    if args.list:
        print(f"{len(selected)} test files, {len(batches)} physical batches (max {args.max_files} files)")
        for i, batch in enumerate(batches, 1):
            print(f"batch-{i:03d}: " + ", ".join(map(str, batch)))
        return 0

    log_dir = Path(args.log_dir).resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    summary_path = log_dir / "summary.json"
    try:
        if summary_path.exists() and not isinstance(json.loads(summary_path.read_text()), list):
            raise ValueError("summary must be a JSON array")
    except (ValueError, OSError) as error:
        parser.error(f"Cannot preserve existing summary: {error}")
    # Concurrent runners in one checkout cannot safely own the same mutable pins.
    lock_path = ROOT / ".audit-test-logs/hardhat-checkout.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    checkout_lock = lock_path.open("a")
    try:
        fcntl.flock(checkout_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error("Another Hardhat runner owns this checkout; use an isolated copy")

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + "-" + uuid.uuid4().hex[:8]
    run_dir = log_dir / run_id
    run_dir.mkdir()
    original_pins = PIN.read_bytes()
    (run_dir / "ContractAddresses.original.sol").write_bytes(original_pins)
    hook = run_dir / "capture-compiler.cjs"
    hook.write_text(CAPTURE_HOOK)
    current = []
    pending = None
    metadata = {"run_id": run_id, "cwd": str(ROOT), "selected_files": list(map(str, selected)),
                "discovery_config": str(config), "test_dir_order": order,
                "physical_batches": len(batches), "max_files": args.max_files,
                "forwarded_arguments": forwarded, "runner_sha256": digest(Path(__file__).read_bytes()),
                "capture_hook_sha256": digest(hook.read_bytes()),
                "original_pins_sha256": digest(original_pins),
                "environment": {key: os.environ[key] for key in ENV_KEYS if key in os.environ},
                "count_semantics": "Mocha execution counts, not unique test identities",
                "compiler_capture": "Live pre-solc inputs plus available build-info inventories; cached inputs are not claimed as freshly compiled"}
    write_json(run_dir / "run.json", metadata)

    def record(row):
        row["run_id"] = run_id
        current.append(row)
        with (log_dir / "summary.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            history = json.loads(summary_path.read_text()) if summary_path.exists() else []
            if not isinstance(history, list):
                raise ValueError("summary must be a JSON array")
            write_json(summary_path, [*history, row])
        write_json(run_dir / "summary.json", current)
        print(json.dumps(row), flush=True)

    def on_signal(signum, _frame):
        raise Interrupted(f"received {signal.Signals(signum).name}")

    handlers = {sig: signal.signal(sig, on_signal) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        versions = {}
        for name, command in (("node", ["node", "--version"]), ("npm", ["npm", "--version"]),
                              ("hardhat", ["npx", "hardhat", "--version"]),
                              ("base_commit", ["git", "rev-parse", "HEAD"])):
            with (run_dir / f"version-{name}.log").open("w") as output:
                code = run_child(command, stdout=output, stderr=subprocess.STDOUT)
            versions[name] = {"command": command, "exit_code": code,
                              "output": (run_dir / f"version-{name}.log").read_text().strip()}
        metadata["versions"] = versions
        write_json(run_dir / "run.json", metadata)
        baseline = source_identity(config)
        write_json(run_dir / "sources.json", baseline)
        (run_dir / "hardhat.config.js").write_bytes(config.read_bytes())
        for number, files in enumerate(batches, 1):
            name = f"batch-{number:03d}"
            folder = run_dir / name
            (folder / "compiler-inputs").mkdir(parents=True)
            command = ["npx", "hardhat", "test", *map(str, files), *forwarded]
            env = {**os.environ, "NO_COLOR": "1", "FORCE_COLOR": "0",
                   "DEGENERUS_HARDHAT_EVIDENCE": str(folder)}
            env["NODE_OPTIONS"] = (env.get("NODE_OPTIONS", "") + " --require=" + json.dumps(str(hook))).strip()
            row = {"batch": name, "selected_files": list(map(str, files)), "command": command,
                   "environment": {key: env[key] for key in (*ENV_KEYS, "DEGENERUS_HARDHAT_EVIDENCE") if key in env},
                   "log": str((folder / "test.log").relative_to(log_dir)),
                   "source_manifest": str((run_dir / "sources.json").relative_to(log_dir))}
            pending = row
            write_json(folder / "command.json", row)
            if source_identity(config) != baseline:
                raise ValueError("source/config inputs changed before this batch")
            (folder / "ContractAddresses.before.sol").write_bytes(PIN.read_bytes())
            cached = capture_cached_inputs(folder, "before")
            write_json(folder / "cached-inputs-before.json", cached)
            print(f"Running {name}: {', '.join(map(str, files))}; log: {folder / 'test.log'}", flush=True)
            with (folder / "test.log").open("w") as log:
                code = run_child(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            (folder / "ContractAddresses.after.sol").write_bytes(PIN.read_bytes())
            output = ANSI.sub("", (folder / "test.log").read_text(errors="replace"))
            counts = {kind: [] for kind in ("passing", "failing", "pending")}
            for value, kind in TOTAL.findall(output):
                counts[kind].append(int(value))
            errors = []
            if code:
                errors.append(f"Hardhat exited {code}")
            if len(counts["passing"]) != 1:
                errors.append("missing or ambiguous final Mocha passing total")
            if not counts["passing"] or sum(counts["passing"]) + sum(counts["failing"]) == 0:
                errors.append("zero executed Mocha tests")
            if any(counts["failing"]):
                errors.append("Mocha reported failing tests")
            events_path = folder / "events.jsonl"
            events = [json.loads(line) for line in events_path.read_text().splitlines()] if events_path.exists() else []
            if not any(event["event"] == "compiler-api" for event in events):
                errors.append("Hardhat compiler capture API was not installed; compiler evidence is incomplete")
            live = [event for event in events if event["event"] == "compiler-input"]
            compiler_drift = set()
            for event in live:
                target = folder / "compiler-inputs" / (event["input_sha256"] + ".json")
                if not target.is_file() or digest(target.read_bytes()) != event["input_sha256"]:
                    errors.append("missing or corrupt live compiler input")
                    continue
                # Catch a fixture that changes source, compiles, then restores it before
                # our final filesystem check. Only the expected address pins may vary.
                for source, data in json.loads(target.read_text()).get("sources", {}).items():
                    normalized = str(Path(source))
                    if normalized == str(PIN):
                        continue
                    candidates = (normalized, "node_modules/" + normalized)
                    key = next((name for name in candidates if name in baseline), None)
                    if key is not None:
                        if not isinstance(data.get("content"), str) or digest(data["content"].encode()) != baseline[key]:
                            compiler_drift.add(key)
                    else:
                        # Unknown namespaces can contain real custom-source code too.
                        # Never silently exempt them from the live source comparison.
                        compiler_drift.add(normalized)
            write_json(folder / "cached-inputs-after.json", capture_cached_inputs(folder, "after"))
            final_identity = source_identity(config)
            drift = sorted(compiler_drift | {key for key in baseline.keys() | final_identity.keys()
                                            if baseline.get(key) != final_identity.get(key)})
            if drift:
                errors.append("source/config inputs changed during this batch")
            row.update(hardhat_exit_code=code, counts=counts, passed=sum(counts["passing"]),
                       failed=sum(counts["failing"]), pending=sum(counts["pending"]),
                       live_compiler_invocations=len(live), compiler_source_drift=sorted(compiler_drift), source_drift=drift,
                       exit_code=int(bool(errors)), errors=errors)
            record(row)
            pending = None
            if drift:
                break
    except (OSError, ValueError, KeyboardInterrupt, Interrupted) as error:
        failure = pending if pending is not None else {"batch": "runner"}
        failure.update(exit_code=1, errors=[f"{type(error).__name__}: {error}"])
        record(failure)
    finally:
        for sig in handlers:
            signal.signal(sig, signal.SIG_IGN)
        PIN.write_bytes(original_pins)
        metadata["pins_restored_sha256"] = digest(PIN.read_bytes())
        metadata["completed_batches"] = sum(row["batch"].startswith("batch-") and "hardhat_exit_code" in row for row in current)
        metadata["finished_utc"] = datetime.now(timezone.utc).isoformat()
        write_json(run_dir / "run.json", metadata)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
        checkout_lock.close()
    return int(len(current) != len(batches) or any(row["exit_code"] for row in current))


if __name__ == "__main__":
    sys.exit(main())
