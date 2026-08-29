#!/usr/bin/env bash
# ── Craps progressive parity gate ───────────────────────────────────────
# The progressive's funding rule and its four HIGH-POINT cutoffs live in TWO places
# by necessity: the contract that pays them and the C++ model the economics are
# calibrated on. Neither can read the other, so this holds them together on
# source text — a cutoff moved in one and not the other is a model that no longer
# describes the chain, and that is exactly the drift a reader would never see.
#
# The model is the HIGH-WATER system simulation. The cutoffs are inclusive score
# basis points — the winner's high point over its own starting bankroll, 10,000
# being 1x — and there are four of them because the scheduled format is two
# targets, not nine depth/target pairs.
#
# Checked:
#   1. `_BASE_MAIN_BUDGET` (ether)  == `kDefaultMainBase` (whole FLIP)
#   2. `_PROG_COMMON_5X`  == `kGoal5CommonPeakBps`   `_PROG_RARE_5X`  == `kGoal5RarePeakBps`
#      `_PROG_COMMON_20X` == `kGoal20CommonPeakBps`  `_PROG_RARE_20X` == `kGoal20RarePeakBps`
#   3. the four RUNG shares (routine/event x common/rare, in bps of the live pool)
#      == `kProgRoutineCommonBps` / `kProgRoutineRareBps` / `kProgEventCommonBps` /
#         `kProgEventRareBps`. The event's repeat double is a `x2` on the event rungs in both
#         files and carries no constant of its own.
#   4. the escalator and bounds == `gEscHands` / `gEscCap` / `kMaxHands` / `kRollBudget`
set -uo pipefail
cd "$(dirname "$0")/.."

SOL=contracts/CrapsBattle.sol
ENGINE=contracts/Craps.sol
CPP=scripts/craps-high-water-system-sim.cpp
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; OFF=$'\033[0m'
fail=0

note() { echo "${RED}FAIL${OFF} $1"; fail=1; }

python3 - "$SOL" "$ENGINE" "$CPP" <<'PY'
import re, sys
# The wrapper picks the format and the engine holds the escalator, so the contract side of
# this gate is BOTH files: a constant moved from one to the other must not slip the check.
sol = open(sys.argv[1]).read() + open(sys.argv[2]).read()
cpp = open(sys.argv[3]).read()
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

def num(text, pattern, what):
    v = one(pattern, text, what)
    return None if v is None else int(v.replace('_', '').replace("'", ''))

for label, sol_name, cpp_name in (
    ("5x common", "_PROG_COMMON_5X", "kGoal5CommonPeakBps"),
    ("5x rare", "_PROG_RARE_5X", "kGoal5RarePeakBps"),
    ("20x common", "_PROG_COMMON_20X", "kGoal20CommonPeakBps"),
    ("20x rare", "_PROG_RARE_20X", "kGoal20RarePeakBps"),
):
    a = num(sol, rf'{sol_name}\s*=\s*([0-9_]+)\s*;', sol_name)
    b = num(cpp, rf'{cpp_name}\s*=\s*([0-9\']+)\s*;', cpp_name)
    if a is not None and b is not None and a != b:
        bad.append(f"{label} cutoff: contract {a} bps vs model {b} bps")

# The escalator and the hard bounds the calibration was measured under. ONE rule set: customs
# and scheduled days run the same escalator, so there is one constant apiece to hold.
for label, sol_pat, sol_name, cpp_pat, cpp_name in (
    ("doubling period", r'_ESC_HANDS\s*=\s*([0-9_]+)\s*;', '_ESC_HANDS',
     r'gEscHands\s*=\s*([0-9\']+)\s*;', 'gEscHands'),
    ("shooter cap", r'_MAX_SLIP_HANDS\s*=\s*([0-9_]+)\s*;', '_MAX_SLIP_HANDS',
     r'kMaxHands\s*=\s*([0-9\']+)\s*;', 'kMaxHands'),
    ("roll budget", r'_SLIP_ROLL_BUDGET\s*=\s*([0-9_]+)\s*;', '_SLIP_ROLL_BUDGET',
     r'kRollBudget\s*=\s*([0-9\']+)\s*;', 'kRollBudget'),
):
    a = num(sol, sol_pat, sol_name)
    b = num(cpp, cpp_pat, cpp_name)
    if a is not None and b is not None and a != b:
        bad.append(f"{label}: contract {a} vs model {b}")

# The escalator ceiling is `type(uint32).max` in the contract and a literal in the model.
esc_cpp = one(r"gEscCap\s*=\s*(0x[0-9A-Fa-f]+)LL\s*;", cpp, 'gEscCap')
if esc_cpp is not None and int(esc_cpp, 16) != 0xFFFFFFFF:
    bad.append(f"escalator ceiling: contract uint32.max vs model {esc_cpp}")
if 'uint32' not in (one(r'_ESC_CAP\s*=\s*([^;]+);', sol, '_ESC_CAP') or ''):
    bad.append("escalator ceiling: the contract no longer names uint32.max")

for label, sol_name, cpp_name in (
    ("routine common", "_PROG_ROUTINE_COMMON_BPS", "kProgRoutineCommonBps"),
    ("routine rare", "_PROG_ROUTINE_RARE_BPS", "kProgRoutineRareBps"),
    ("event common", "_PROG_EVENT_COMMON_BPS", "kProgEventCommonBps"),
    ("event rare", "_PROG_EVENT_RARE_BPS", "kProgEventRareBps"),
):
    a = num(sol, rf'{sol_name}\s*=\s*([0-9_]+)\s*;', sol_name)
    b = num(cpp, rf"{cpp_name}\s*=\s*([0-9']+)\s*;", cpp_name)
    if a is not None and b is not None and a != b:
        bad.append(f"{label} rung: contract {a} bps vs model {b} bps")

# THE CONTRACT PAYS BY DOUBLINGS of the routine common rung, and the four named rungs above are
# the same table written out. Hold them together: without this a rung could be retuned in the
# names — which is all this gate and the model compare — while the award kept paying the old
# figure, and the gate would stay green through it.
base = num(sol, r'_PROG_ROUTINE_COMMON_BPS\s*=\s*([0-9_]+)\s*;', '_PROG_ROUTINE_COMMON_BPS')
rd = num(sol, r'_PROG_RARE_DOUBLINGS\s*=\s*([0-9_]+)\s*;', '_PROG_RARE_DOUBLINGS')
ed = num(sol, r'_PROG_EVENT_DOUBLINGS\s*=\s*([0-9_]+)\s*;', '_PROG_EVENT_DOUBLINGS')
if None not in (base, rd, ed):
    for name, want in (
        ('_PROG_ROUTINE_RARE_BPS', base << rd),
        ('_PROG_EVENT_COMMON_BPS', base << ed),
        ('_PROG_EVENT_RARE_BPS', base << (rd + ed)),
    ):
        got = num(sol, rf'{name}\s*=\s*([0-9_]+)\s*;', name)
        if got is not None and got != want:
            bad.append(f"{name}: named {got} bps, but the award's doublings pay {want}")

# THE REPEAT DOUBLE carries no constant — it is a doubling of the event rung, written the same way
# in both files. Hold the two SHAPES together, so a rule that silently stops doubling on one side
# cannot pass.
if '++shift;' not in sol:
    bad.append("the contract no longer doubles the event rung on a repeat victory")
if '++shift;' not in cpp:
    bad.append("the model no longer doubles the event rung on a repeat victory")
# ...and the model counts its doublings the same way the contract does.
for label, sol_name, cpp_name in (
    ("rare", "_PROG_RARE_DOUBLINGS", "kProgRareDoublings"),
    ("event", "_PROG_EVENT_DOUBLINGS", "kProgEventDoublings"),
):
    a = num(sol, rf'{sol_name}\s*=\s*([0-9_]+)\s*;', sol_name)
    b = num(cpp, rf"{cpp_name}\s*=\s*([0-9']+)\s*;", cpp_name)
    if a is not None and b is not None and a != b:
        bad.append(f"{label} doublings: contract {a} vs model {b}")

for line in bad:
    print(f"MISMATCH {line}")
sys.exit(1 if bad else 0)
PY
rc=$?
if [ $rc -ne 0 ]; then
  note "the craps progressive drifted between the contract and its economic model"
fi

if [ $fail -eq 0 ]; then
  echo "${GREEN}PASS${OFF} craps progressive: base subsidy, all four rungs and the repeat double, all four high-point cutoffs and the escalator agree with the model"
fi
exit $fail
