#!/usr/bin/env python3
"""Check or refresh the audit source identity; this does not certify test results."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "docs/audit"
SUPPORTING_SOLIDITY = {"contracts/ContractAddresses.sol", "contracts/DeityPassCustomizationRenderer.sol",
                       "contracts/Icons32Data.sol"}


def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def scope_files():
    entries = [line.strip() for line in (ROOT / "scope.txt").read_text().splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    if len(entries) != len(set(entries)):
        raise ValueError("scope.txt contains duplicate sources")
    production = {p.relative_to(ROOT).as_posix() for p in (ROOT / "contracts").rglob("*.sol")
                  if p.relative_to(ROOT).parts[1] not in {"mocks", "test"}}
    expected = production - SUPPORTING_SOLIDITY
    if set(entries) != expected:
        raise ValueError(f"scope drift: missing={sorted(expected - set(entries))}; "
                         f"unexpected={sorted(set(entries) - expected)}")
    return sorted(entries)


def verification_files(build_inputs):
    # Include tracked assurance tooling and every current test, including newly
    # written tests that have not been staged. Unrelated local simulation scripts
    # and old logs are not silently promoted into the public verification pack.
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z", "scripts"], cwd=ROOT
    ).decode().split("\0")
    paths = {p for p in tracked if p and (ROOT / p).is_file()}
    paths.add("scripts/audit-snapshot.py")
    paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / "test").rglob("*")
                 if p.is_file() and p.suffix in {".sol", ".js", ".py"})
    # Deployed test harnesses and vm.readFile bytecode are verification inputs,
    # not additions to the explicitly scoped production logic contracts.
    for directory in ("contracts/mocks", "contracts/test"):
        paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / directory).rglob("*")
                     if p.is_file() and p.suffix in {".sol", ".hex"})
    paths.update(p for p in build_inputs if not p.startswith("contracts/"))
    paths.update({"scope.txt", "out_of_scope.txt"})
    return sorted(paths)


def hash_text(paths):
    return "".join(f"{digest(p)}  {p}\n" for p in sorted(set(paths)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="refresh hashes; does not run verification")
    args = parser.parse_args()
    manifest_path = AUDIT / "snapshot.json"
    manifest = json.loads(manifest_path.read_text())
    sources = scope_files()
    build_inputs = manifest["build_and_deployment_inputs"]
    if not SUPPORTING_SOLIDITY <= set(build_inputs):
        raise ValueError("snapshot omits supporting Solidity build inputs")
    # Paths come from the repository's manifest, never from the shell.
    for path in [*sources, *build_inputs]:
        if Path(path).is_absolute() or ".." in Path(path).parts:
            raise ValueError(f"invalid snapshot path: {path}")
    expected = {
        "source-sha256.txt": hash_text([*sources, *build_inputs]),
        "verification-sha256.txt": hash_text(verification_files(build_inputs)),
    }
    if args.write:
        manifest.update(
            date=datetime.now(timezone.utc).date().isoformat(),
            status="working-tree source identity; verification status is recorded separately",
            base_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
            source_file_count=len(sources),
            source_files=sources,
        )
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        for name, contents in expected.items():
            (AUDIT / name).write_text(contents)
        print(f"Recorded {len(sources)} scoped sources. No test or audit result is inferred.")
        return 0

    errors = []
    if manifest["source_files"] != sources or manifest["source_file_count"] != len(sources):
        errors.append("snapshot source list/count does not match scope.txt")
    for name, contents in expected.items():
        if not (AUDIT / name).is_file() or (AUDIT / name).read_text() != contents:
            errors.append(f"{name} is stale or incomplete")
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print("Refresh with --write only after recording the changed revision's verification status.", file=sys.stderr)
        return 1
    print(f"Audit identity matches {len(sources)} scoped sources and the current verification inputs.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Audit snapshot error: {error}", file=sys.stderr)
        sys.exit(1)
