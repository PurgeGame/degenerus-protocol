#!/usr/bin/env bash
# MECH-02 storage-layout snapshot oracle (v68.0).
#
# Deterministically catches ANY storage-slot move in DegenerusGame (the delegatecall
# storage context shared by the 13 modules — whole-protocol blast radius) and in every
# standalone state contract, PLUS any delegatecall module whose layout diverges from the
# Game's shared DegenerusGameStorage layout (the "module writes a slot the Game uses for a
# different variable" corruption class the v67 CORRUPT phase reasoned about by hand).
#
# astId-normalized (see normalize_layout.py) so only a REAL layout change trips it — not a
# recompile. Closes the carried v67 MECH-02 gap (v67 shipped only PARTIAL: critical slots
# pinned by hand-written StorageFoundation asserts; this is the complete forge-inspect diff).
#
#   storage_layout_oracle.sh --capture   # (re)write goldens — run intentionally after an approved layout change
#   storage_layout_oracle.sh             # --check (default): diff live vs golden, exit 1 on any move (CI gate)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
DIR="scripts/layout"
GOLD="$DIR/golden"
NORM=("python3" "$DIR/normalize_layout.py")
MODE="${1:---check}"
mkdir -p "$GOLD"

# Deployable contracts that own storage (DegenerusGame = the canonical delegatecall context).
CONTRACTS=(
  DegenerusGame
  Coinflip sDGNRS DGNRS DegenerusVaultShare DegenerusAffiliate DegenerusQuests
  FLIP GNRUS WWXRP DegenerusDeityPass DegenerusJackpots DegenerusAdmin
)
# Delegatecall modules — must share DegenerusGame's storage layout exactly (run in its context).
MODULES=(
  DegenerusGameAdvanceModule DegenerusGameMintModule DegenerusGameLootboxModule
  DegenerusGameJackpotModule DegenerusGameDecimatorModule DegenerusGameDegeneretteModule
  DegenerusGameWhaleModule GameAfkingModule DegenerusGameBoonModule
  DegenerusGameBingoModule DegenerusGameGameOverModule DegenerusGameFoilPackModule
)

inspect_norm() { forge inspect "$1" storageLayout --json 2>/dev/null | "${NORM[@]}"; }

fail=0

if [ "$MODE" = "--capture" ]; then
  for c in "${CONTRACTS[@]}" "${MODULES[@]}"; do
    if inspect_norm "$c" > "$GOLD/$c.json"; then
      n=$(python3 -c "import json;print(len(json.load(open('$GOLD/$c.json'))))" 2>/dev/null || echo "?")
      echo "captured $c ($n slots)"
    else
      echo "CAPTURE FAIL: $c"; fail=1
    fi
  done
  echo "goldens written to $GOLD/"
  exit $fail
fi

# ----- --check (default) -----
for c in "${CONTRACTS[@]}" "${MODULES[@]}"; do
  if [ ! -f "$GOLD/$c.json" ]; then
    echo "::error:: no golden for $c (run: $0 --capture)"; fail=1; continue
  fi
  if ! diff -u "$GOLD/$c.json" <(inspect_norm "$c") > "/tmp/layout-$c.diff" 2>&1; then
    echo "::error:: STORAGE LAYOUT CHANGED for $c (slot/offset/type move):"
    cat "/tmp/layout-$c.diff"
    fail=1
  fi
done

# Delegatecall corruption gate: every label a module shares with the Game must sit at the
# SAME slot+offset as in the Game (else a module write lands on a different Game variable).
python3 - "$GOLD" "${MODULES[@]}" <<'PY' || fail=1
import json, sys
gold = sys.argv[1]; mods = sys.argv[2:]
game = {e["label"]: (e["slot"], e["offset"]) for e in json.load(open(f"{gold}/DegenerusGame.json"))}
bad = 0
for m in mods:
    try:
        ml = json.load(open(f"{gold}/{m}.json"))
    except FileNotFoundError:
        continue
    for e in ml:
        l = e["label"]
        if l in game and (e["slot"], e["offset"]) != game[l]:
            print(f"::error:: {m}.{l} @ slot {e['slot']}/off {e['offset']} != Game slot {game[l][0]}/off {game[l][1]}")
            bad = 1
print("delegatecall shared-slot consistency (modules vs Game): " + ("FAIL" if bad else "OK"))
sys.exit(bad)
PY

if [ $fail -eq 0 ]; then echo "STORAGE LAYOUT ORACLE: all goldens match ✓"; fi
exit $fail
