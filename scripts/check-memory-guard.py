#!/usr/bin/env python3
"""Reject production runtimes with unreviewed via-IR stack-spill reservations."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def entry_pointer(runtime):
    """Evaluate the constant prologue through its first free-memory-pointer store.

    Fail closed on an unfamiliar prologue instead of searching for a byte pattern
    that could occur in PUSH data, a later function, or compiler metadata.
    """
    if not isinstance(runtime, str):
        raise ValueError("missing runtime bytecode string")
    if runtime.startswith("0x"):
        runtime = runtime[2:]
    try:
        code = bytes.fromhex(runtime)
    except ValueError as exc:
        raise ValueError("invalid or unlinked runtime bytecode") from exc
    if not code:
        raise ValueError("missing runtime bytecode")
    stack = []
    pc = 0
    for _ in range(16):
        if pc >= len(code):
            break
        op = code[pc]
        pc += 1
        if op == 0x5F:  # PUSH0
            stack.append(0)
        elif 0x60 <= op <= 0x7F:
            size = op - 0x5F
            if pc + size > len(code):
                raise ValueError("truncated prologue PUSH")
            stack.append(int.from_bytes(code[pc:pc + size], "big"))
            pc += size
        elif 0x80 <= op <= 0x8F and len(stack) >= op - 0x7F:
            stack.append(stack[-(op - 0x7F)])
        elif 0x90 <= op <= 0x9F and len(stack) > op - 0x8F:
            depth = op - 0x8F
            stack[-1], stack[-1 - depth] = stack[-1 - depth], stack[-1]
        elif op == 0x52 and len(stack) >= 2:  # MSTORE
            offset, value = stack.pop(), stack.pop()
            if offset != 0x40 or value < 0x80 or value % 32:
                raise ValueError("unexpected free-memory-pointer initialization")
            return value
        else:
            raise ValueError(f"unknown prologue opcode 0x{op:02x} at {pc - 1}")
    raise ValueError("no free-memory-pointer initialization in prologue")


def read_allowlist(path):
    exceptions = {}
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t", 2)
        if len(fields) != 3 or not fields[0].strip() or not fields[2].strip():
            raise ValueError(f"{path}:{line_number}: expected contract, pointer, measured reason (TSV)")
        name, limit, reason = fields
        pointer = int(limit, 0)
        if name in exceptions or pointer <= 0x80 or pointer % 32:
            raise ValueError(f"{path}:{line_number}: duplicate contract or invalid pointer")
        exceptions[name] = (pointer, reason)
    return exceptions


def production_entries():
    # Reuse the deployment order so new consolidation bundles enter this gate.
    result = subprocess.run(
        ["node", "--input-type=module", "-e",
         "import {DEPLOYMENTS} from './scripts/lib/deploymentManifest.js';"
         "console.log(JSON.stringify(DEPLOYMENTS));"],
        cwd=ROOT, check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout) + [
        {"key": "DGVF", "contract": "DegenerusVaultShare", "source": "DegenerusVault"},
        {"key": "DGVE", "contract": "DegenerusVaultShare", "source": "DegenerusVault"},
        {"key": "GAME_LENS", "contract": "DegenerusGameLens"},
        {"key": "CRAPS_LENS", "contract": "CrapsLens"},
    ]


def check(entries, artifacts, exceptions):
    rows, errors, used = [], [], set()
    names = {entry["contract"] for entry in entries}
    for name in sorted(exceptions.keys() - names):
        errors.append(f"{name}: allowlist entry is not a production deployment")
    for entry in entries:
        name = entry["contract"]
        file = artifacts / f"{entry.get('source', name)}.sol" / f"{name}.json"
        try:
            artifact = json.loads(file.read_text())
            pointer = entry_pointer(artifact["deployedBytecode"]["object"])
            exception = exceptions.get(name)
            reason = None
            if pointer > 0x80:
                if exception is None:
                    errors.append(f"{name}: entry pointer {pointer:#x} exceeds 0x80 without a measured exception")
                elif pointer > exception[0]:
                    errors.append(f"{name}: entry pointer {pointer:#x} exceeds approved {exception[0]:#x}")
                else:
                    used.add(name)
                    reason = exception[1]
            rows.append({"key": entry["key"], "contract": name, "entry_pointer": pointer,
                         "entry_pointer_hex": hex(pointer), "exception": reason})
        except (OSError, ValueError, KeyError, TypeError) as exc:
            errors.append(f"{name}: {exc}")
    for name in sorted(exceptions.keys() & names - used):
        if any(r["contract"] == name and r["entry_pointer"] == 0x80 for r in rows):
            errors.append(f"{name}: spill removed; delete the stale allowlist entry")
    return {"rows": rows, "errors": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", nargs="?", type=Path,
                        default=Path(os.environ.get("FOUNDRY_OUT", "forge-out")))
    parser.add_argument("--allowlist", type=Path, default=ROOT / "scripts/memory-guard-allowlist.tsv")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        report = check(production_entries(), args.artifacts, read_allowlist(args.allowlist))
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        report = {"rows": [], "errors": [str(exc)]}
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        for error in report["errors"]:
            print(error, file=sys.stderr)
        print(f"Memory guard: {len(report['rows'])} deployment rows, {len(report['errors'])} errors")
    return bool(report["errors"])


if __name__ == "__main__":
    sys.exit(main())
