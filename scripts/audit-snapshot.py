#!/usr/bin/env python3
"""Check or refresh one source/build/test hash manifest; this does not certify tests."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from audit_scope import inventory

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "docs/audit"
BUILD_INPUTS = ("package.json", "package-lock.json", "foundry.toml", "foundry.lock",
                "hardhat.config.js", "halmos.toml", ".gitmodules", "Makefile",
                "deployments/eip170.json", ".github/workflows/ci.yml")


def scope_files():
    entries = [line.strip() for line in (ROOT / "scope.txt").read_text().splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    if len(entries) != len(set(entries)):
        raise ValueError("scope.txt contains duplicate sources")
    expected, excluded = inventory(ROOT)
    if set(entries) != expected:
        raise ValueError(f"scope drift: missing={sorted(expected - set(entries))}; "
                         f"unexpected={sorted(set(entries) - expected)}")
    prefixes = [line.strip() for line in (ROOT / "out_of_scope.txt").read_text().splitlines()
                if line.strip() and not line.startswith("#")]
    unclassified = {p for p in excluded if not any(p == q or (q.endswith('/') and p.startswith(q))
                                                 for q in prefixes)}
    if unclassified:
        raise ValueError(f"scope drift: unclassified production sources={sorted(unclassified)}")
    return sorted(entries)


def verification_files(build_inputs=()):
    paths = {"scope.txt", "out_of_scope.txt"}
    tracked = subprocess.check_output(["git", "ls-files", "-z", "scripts", "test", "contracts"],
                                      cwd=ROOT).decode().split("\0")
    paths.update(p for p in tracked if p and (ROOT / p).is_file())
    for directory in ("scripts", "test", "contracts/mocks", "contracts/test"):
        paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / directory).rglob("*")
                     if p.is_file() and "__pycache__" not in p.parts
                     and p.suffix in {".py", ".js", ".mjs", ".sh", ".sol", ".hex"})
    # Unstaged vectors, tables and module helpers are verification inputs too.
    paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / "test").rglob("*")
                 if p.is_file() and "__pycache__" not in p.parts
                 and p.suffix in {".sol", ".js", ".cjs", ".mjs", ".ts", ".py",
                                  ".json", ".hex", ".csv", ".tsv"})
    paths.update(p for p in build_inputs if (ROOT / p).is_file())
    return sorted(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="refresh hashes without running tests")
    args = parser.parse_args()
    sources = scope_files()
    paths = sorted(set(sources) | set(verification_files(BUILD_INPUTS)))
    contents = "".join(f"{hashlib.sha256((ROOT / p).read_bytes()).hexdigest()}  {p}\n" for p in paths)
    target = AUDIT / "source-sha256.txt"
    if args.write:
        target.write_text(contents)
        print(f"Recorded {len(sources)} scoped sources and {len(paths)} total inputs. No test result is inferred.")
        return 0
    if not target.is_file() or target.read_text() != contents:
        print("source-sha256.txt is stale or incomplete; review changes, then refresh with --write.", file=sys.stderr)
        return 1
    print(f"Audit identity matches {len(sources)} scoped sources and {len(paths)} total inputs.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Audit snapshot error: {error}", file=sys.stderr)
        sys.exit(1)
