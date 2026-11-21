#!/usr/bin/env python3
"""Compiler known-bug gate.

Solidity publishes the bugs known to affect each release in docs/bugs_by_version.json.
This gate pins the reviewed release and the bugs reviewed for it, and re-checks from
source the precondition of each one that the contracts are stated not to meet.

Fails when:
  - foundry.toml, hardhat.config.js or any contracts/ pragma names another release;
  - a reviewed bug's precondition appears in contracts/;
  - with --online, Solidity's published list for the release differs from REVIEWED.
"""

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLISHED = "https://raw.githubusercontent.com/argotorg/solidity/develop/docs/bugs_by_version.json"

# Release -> the published bug names reviewed for it, each with the check that covers it.
REVIEWED = {
    "0.8.38": {
        # SOL-2026-8, fixed in 0.8.39. A storage-to-storage copy whose target contains its
        # source corrupts the source; it needs a struct type that contains a dynamically
        # sized array of its own type, directly or through other structs.
        "OverlappingRecursiveStorageStructCopyCorruption": "recursive_struct_arrays",
        "OverlappingRecursiveStorageStructCopyCorruptionViaIR": "recursive_struct_arrays",
    },
}

COMMENTS = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)
STRUCT = re.compile(r"\bstruct\s+(\w+)\s*\{(.*?)\}", re.S)


def sources():
    return sorted((ROOT / "contracts").rglob("*.sol"))


def pinned_versions():
    found = {}
    toml = (ROOT / "foundry.toml").read_text()
    for value in re.findall(r'^\s*solc_version\s*=\s*"([^"]+)"', toml, re.M):
        found.setdefault(value, []).append("foundry.toml")
    hardhat = (ROOT / "hardhat.config.js").read_text()
    for value in re.findall(r'version:\s*"(\d+\.\d+\.\d+)"', hardhat):
        found.setdefault(value, []).append("hardhat.config.js")
    for path in sources():
        for value in re.findall(r"^pragma solidity\s+([^;]+);", path.read_text(), re.M):
            found.setdefault(value.strip(), []).append(str(path.relative_to(ROOT)))
    return found


def recursive_struct_arrays():
    """Struct types that reach themselves through at least one dynamic array member."""
    members = {}
    where = {}
    for path in sources():
        text = COMMENTS.sub("", path.read_text())
        for name, body in STRUCT.findall(text):
            members.setdefault(name, []).extend(m.strip() for m in body.split(";") if m.strip())
            where.setdefault(name, str(path.relative_to(ROOT)))
    names = set(members)
    edges = {}
    for name, fields in members.items():
        for field in fields:
            declared = field.rsplit(None, 1)[0] if " " in field else field
            for other in names:
                if re.search(r"(?<![\w.])" + re.escape(other) + r"\b", declared):
                    dynamic = bool(re.search(re.escape(other) + r"(\s*\[\d*\])*\s*\[\s*\]", declared))
                    edges.setdefault(name, set()).add((other, dynamic))
    hits = []
    for start in sorted(names):
        stack = [(start, False)]
        seen = set()
        while stack:
            node, through_dynamic = stack.pop()
            for other, dynamic in edges.get(node, ()):
                reached = through_dynamic or dynamic
                if other == start and reached:
                    hits.append(f"{start} ({where[start]})")
                    stack = []
                    break
                if (other, reached) not in seen:
                    seen.add((other, reached))
                    stack.append((other, reached))
    return hits, len(names)


CHECKS = {"recursive_struct_arrays": recursive_struct_arrays}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--online", action="store_true", help="compare REVIEWED with Solidity's published list")
    args = parser.parse_args()
    failures = []

    versions = pinned_versions()
    if len(versions) != 1:
        failures.append("more than one compiler release is named: " + ", ".join(
            f"{v} ({len(files)} files, e.g. {files[0]})" for v, files in sorted(versions.items())))
    version = next(iter(versions)) if versions else ""
    if version not in REVIEWED:
        failures.append(f"release {version or '<none>'} has no reviewed bug list; read {PUBLISHED} and add it to REVIEWED")
    reviewed = REVIEWED.get(version, {})

    for check in sorted(set(reviewed.values())):
        hits, total = CHECKS[check]()
        bugs = ", ".join(sorted(name for name, c in reviewed.items() if c == check))
        if hits:
            failures.append(f"{check}: {', '.join(hits)} meets the precondition of {bugs}")
        else:
            print(f"ok   {check}: none of {total} struct types ({bugs})")

    if args.online and version:
        with urllib.request.urlopen(PUBLISHED, timeout=30) as response:
            published = set(json.load(response).get(version, {}).get("bugs", []))
        if published != set(reviewed):
            failures.append(f"published bugs for {version} differ from REVIEWED: "
                            f"unreviewed {sorted(published - set(reviewed))}, withdrawn {sorted(set(reviewed) - published)}")
        else:
            print(f"ok   published list for {version} equals the reviewed list ({len(published)} entries)")

    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"compiler {version}: {len(reviewed)} published bug entries reviewed, none applicable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
