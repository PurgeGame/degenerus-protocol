#!/usr/bin/env python3
"""Run the storage-census suites through the focused Foundry runner.

scripts/test-foundry-groups.py refuses Solidity test sources that none of its logical groups owns,
and test/census/ is not one of them. This wrapper loads that runner unchanged and replaces only its
source grouping: every test source stays known (so every other suite is passed to forge as --skip),
test/census/*.t.sol becomes the "census" group, and the always-compiled support set is narrowed to
the census helpers (whatever a census suite imports still compiles). Address patching, restoring
contracts/ContractAddresses.sol, logs and evidence remain the runner's own.

Usage (from the repository root):
  systemd-run --user --scope -q -p MemoryMax=20G -p MemorySwapMax=1G nice -n 10 \\
    python3 scripts/audit/storage-census/run.py --file test/census/StorageCensusLongRun.t.sol \\
    --log-dir .audit-test-logs/storage-census [extra forge args, e.g. --match-test ...]
"""

import importlib.util
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("foundry_groups", ROOT / "scripts/test-foundry-groups.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

CENSUS = Path("test/census")


def census_groups():
    files = sorted(Path("test").rglob("*.sol"))
    census = {p for p in files if p.is_relative_to(CENSUS)}
    tests = {p for p in census if p.name.endswith(".t.sol")}
    return files, census - tests, {"census": tests}


runner.groups = census_groups
# A per-checkout compiler cache, unless the caller chose one.
os.environ.setdefault("FOUNDRY_CACHE_PATH", str(ROOT / ".foundry-cache-census"))

if __name__ == "__main__":
    sys.exit(runner.main())
