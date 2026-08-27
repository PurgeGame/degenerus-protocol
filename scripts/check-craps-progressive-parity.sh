#!/usr/bin/env bash
# ── Craps progressive parity gate ───────────────────────────────────────
# The progressive's funding rule and its nine roll cutoffs live in TWO places by
# necessity: the contract that pays them and the C++ model the economics are
# calibrated on. Neither can read the other, so this holds them together on
# source text — a cutoff moved in one and not the other is a model that no longer
# describes the chain, and that is exactly the drift a reader would never see.
#
# Checked:
#   1. `_BASE_MAIN_BUDGET` (ether)      == `kDefaultMainBase` (whole FLIP)
#   2. `_PROG_COMMON` / `_PROG_RARE`    == `kProgCommon[]` / `kProgRare[]`
#   3. `_PROG_COMMON_DIV` / `_PROG_RARE_DIV` == `kProgCommonDiv` / `kProgRareDiv`
set -uo pipefail
cd "$(dirname "$0")/.."

SOL=contracts/CrapsBattle.sol
CPP=scripts/craps-system-sim.cpp
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; OFF=$'\033[0m'
fail=0

note() { echo "${RED}FAIL${OFF} $1"; fail=1; }

python3 - "$SOL" "$CPP" <<'PY'
import re, sys
sol = open(sys.argv[1]).read()
cpp = open(sys.argv[2]).read()
bad = []

def one(pattern, text, what):
    m = re.search(pattern, text)
    if not m:
        bad.append(f"could not find {what}")
        return None
    return m.group(1)

base_sol = one(r'_BASE_MAIN_BUDGET\s*=\s*([0-9_]+)\s*ether', sol, "_BASE_MAIN_BUDGET")
base_cpp = one(r"kDefaultMainBase\s*=\s*([0-9']+)\s*;", cpp, "kDefaultMainBase")
if base_sol and base_cpp:
    a = int(base_sol.replace('_', ''))
    b = int(base_cpp.replace("'", ''))
    if a != b:
        bad.append(f"base subsidy: contract {a} FLIP vs model {b} FLIP")

def unpack(word):
    return [(word >> (16 * i)) & 0xFFFF for i in range(9)]

for label, sol_name, cpp_name in (
    ("common", "_PROG_COMMON", "kProgCommon"),
    ("rare", "_PROG_RARE", "kProgRare"),
):
    w = one(rf'{sol_name}\s*=\s*(0x[0-9A-Fa-f]+)\s*;', sol, sol_name)
    arr = one(rf'{cpp_name}\[9\]\s*=\s*\{{([^}}]*)\}}', cpp, cpp_name)
    if w is None or arr is None:
        continue
    got = unpack(int(w, 16))
    want = [int(x.strip()) for x in arr.split(',')]
    if got != want:
        bad.append(f"{label} cutoffs: contract {got} vs model {want}")

for label, sol_name, cpp_name in (
    ("common", "_PROG_COMMON_DIV", "kProgCommonDiv"),
    ("rare", "_PROG_RARE_DIV", "kProgRareDiv"),
):
    a = one(rf'{sol_name}\s*=\s*(\d+)\s*;', sol, sol_name)
    b = one(rf'{cpp_name}\s*=\s*(\d+)\s*;', cpp, cpp_name)
    if a and b and a != b:
        bad.append(f"{label} divisor: contract {a} vs model {b}")

for line in bad:
    print(f"MISMATCH {line}")
sys.exit(1 if bad else 0)
PY
rc=$?
if [ $rc -ne 0 ]; then
  note "the craps progressive drifted between the contract and its economic model"
fi

if [ $fail -eq 0 ]; then
  echo "${GREEN}PASS${OFF} craps progressive: base subsidy, both divisors and all nine roll cutoffs agree with the model"
fi
exit $fail
