#!/usr/bin/env bash
# ── Craps system-model parity gate ──────────────────────────────────────
# The progressive rules and scheduled shooter terms live in TWO places
# by necessity: the contract that pays them and the C++ model the economics are
# calibrated on. Neither can read the other, so this holds them together on
# source text — a cutoff moved in one and not the other is a model that no longer
# describes the chain, and that is exactly the drift a reader would never see.
#
# The model is the HIGH-WATER system simulation. The cutoffs are inclusive score
# basis points — the winner's high point over its own starting bankroll, 10,000
# being 1x. The contract has one scheduled target, so only the model's 5x pair
# describes live chain behavior.
#
# Checked:
#   1. `_BASE_MAIN_BUDGET` (ether)  == `kDefaultMainBase` (whole FLIP)
#   2. `_PROG_COMMON` == `kGoal5CommonPeakBps`; `_PROG_RARE` == `kGoal5RarePeakBps`
#   3. the four RUNG shares (routine/event x common/rare, in bps of the live pool)
#      == `kProgRoutineCommonBps` / `kProgRoutineRareBps` / `kProgEventCommonBps` /
#         `kProgEventRareBps`. The event's repeat double is a `x2` on the event rungs in both
#         files and carries no constant of its own.
#   4. the escalator and bounds == `gEscHands` / `gEscCap` / `kMaxHands` / `kRollBudget`
#   5. the packed Hot Shooter table == `kBoostChancePct` / `kBoostUpliftBps`
#   6. `_ROTATION_UPLIFT` and `ROTATING_SHOOTER_TAG` == the model's production defaults
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
    ("scheduled common", "_PROG_COMMON", "kGoal5CommonPeakBps"),
    ("scheduled rare", "_PROG_RARE", "kGoal5RarePeakBps"),
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

# Scheduled Hot Shooter and rotating-shooter economics. Decode the contract's packed rows rather
# than comparing its prose table, then compare those rows with the production (not legacy
# counterfactual) arrays in the model.
packed_hex = one(
    r'_shooterBoostTerms\s*\([^)]*\)[\s\S]*?return\s*\(\s*(0x[0-9A-Fa-f]+)\s*>>',
    sol,
    '_shooterBoostTerms packed table',
)

def cpp_array(name):
    body = one(rf'{name}\s*\{{([^}}]+)\}}\s*;', cpp, name)
    if body is None:
        return None
    return [int(x.replace("'", '')) for x in re.findall(r"[0-9][0-9']*", body)]

chances = cpp_array('kBoostChancePct')
uplifts_bps = cpp_array('kBoostUpliftBps')
if packed_hex is not None and chances is not None and uplifts_bps is not None:
    packed = int(packed_hex, 16)
    contract_chances = [((packed >> (16 * i)) & 0xFFFF) & 0xFF for i in range(8)]
    contract_uplifts_bps = [(((packed >> (16 * i)) & 0xFFFF) >> 8) * 100 for i in range(8)]
    if len(chances) != 8 or chances != contract_chances:
        bad.append(f"Hot Shooter chances: contract {contract_chances} vs model {chances}")
    if len(uplifts_bps) != 8 or uplifts_bps != contract_uplifts_bps:
        bad.append(f"Hot Shooter uplifts: contract {contract_uplifts_bps} bps vs model {uplifts_bps} bps")

rotation_sol = num(sol, r'_ROTATION_UPLIFT\s*=\s*([0-9_]+)\s*;', '_ROTATION_UPLIFT')
rotation_cpp = num(cpp, r'kRotationUpliftPct\s*=\s*([0-9\']+)\s*;', 'kRotationUpliftPct')
if rotation_sol is not None and rotation_cpp is not None and rotation_sol != rotation_cpp:
    bad.append(f"rotating-shooter uplift: contract {rotation_sol}% vs model {rotation_cpp}%")

tag_hex = one(r'ROTATING_SHOOTER_TAG\s*=\s*(0x[0-9A-Fa-f]+)\s*;', sol, 'ROTATING_SHOOTER_TAG')
tag_cpp = one(r'kRotatingShooterTag\s*=\s*"([^"]+)"\s*;', cpp, 'kRotatingShooterTag')
if tag_hex is not None and tag_cpp is not None:
    tag_int = int(tag_hex, 16)
    tag_bytes = tag_int.to_bytes(max(1, (tag_int.bit_length() + 7) // 8), 'big')
    try:
        tag_sol = tag_bytes.decode('ascii')
    except UnicodeDecodeError:
        tag_sol = repr(tag_bytes)
    if tag_sol != tag_cpp:
        bad.append(f"rotating-shooter domain: contract {tag_sol!r} vs model {tag_cpp!r}")
    hi = one(r'kRotatingShooterDomainHi\s*=\s*(0x[0-9A-Fa-f]+)ULL\s*;', cpp,
             'kRotatingShooterDomainHi')
    lo = one(r'kRotatingShooterDomainLo\s*=\s*(0x[0-9A-Fa-f]+)ULL\s*;', cpp,
             'kRotatingShooterDomainLo')
    if hi is not None and lo is not None:
        model_bytes = int(hi, 16).to_bytes(8, 'big')
        lo_int = int(lo, 16)
        model_bytes += lo_int.to_bytes(max(1, (lo_int.bit_length() + 7) // 8), 'big')
        try:
            model_tag = model_bytes.decode('ascii')
        except UnicodeDecodeError:
            model_tag = repr(model_bytes)
        if model_tag != tag_sol:
            bad.append(f"rotating-shooter mixer domain: contract {tag_sol!r} vs model {model_tag!r}")

if 'gShooterBoostMode = ShooterBoostMode::Rotating' not in cpp:
    bad.append("the model's default shooter mode is no longer production rotating")

for line in bad:
    print(f"MISMATCH {line}")
sys.exit(1 if bad else 0)
PY
rc=$?
if [ $rc -ne 0 ]; then
  note "the craps progressive drifted between the contract and its economic model"
fi

if [ $fail -eq 0 ]; then
  echo "${GREEN}PASS${OFF} craps system model: funding, progressive, engine bounds, Hot Shooter table, and rotating-shooter terms agree with the contracts"
fi
exit $fail
