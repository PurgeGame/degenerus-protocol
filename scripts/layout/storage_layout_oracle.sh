#!/usr/bin/env bash
# Compare compiler storage layouts with the checked-in goldens and each delegate host.
# --capture refreshes goldens; --check (default) reports slot, offset and type changes.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
DIR="scripts/layout"
GOLD="$DIR/golden"
NORM=("python3" "$DIR/normalize_layout.py")
MODE="${1:---check}"
mkdir -p "$GOLD"
DIFF_DIR="${AUDIT_LOG_DIR:-${TMPDIR:-/tmp}/degenerus-layout}"
mkdir -p "$DIFF_DIR"

# Deployable contracts that own storage (DegenerusGame = the canonical delegatecall context).
CONTRACTS=(
  DegenerusGame
  Coinflip sDGNRS DGNRS DegenerusVaultShare DegenerusAffiliate DegenerusQuests DegenerusParimutuel
  FLIP GNRUS WWXRP DegenerusDeityPass DegenerusJackpots DegenerusAdmin
  DegenerusRecordBounty
  # Craps table. CrapsBattle is the only one of the three craps contracts with storage; Craps and
  # LootboxCraps are stateless and inherited, so pinning CrapsBattle pins the whole table.
  CrapsBattle JackpotBattle
)
# Delegatecall modules — must share DegenerusGame's storage layout exactly (run in its context).
MODULES=(
  DegenerusGameDailyModule
  DegenerusGameAdvanceModule DegenerusGameMintModule DegenerusGameLootboxModule
  DegenerusGameJackpotModule DegenerusGameDecimatorModule DegenerusGameDegeneretteModule
  DegenerusGameWhaleModule GameAfkingModule DegenerusGameBoonModule
  DegenerusGameGameOverModule DegenerusGameFoilPackModule
  DegenerusGameTicketModule DegenerusGameRngModule
  DegenerusGameJackpotDrawModule DegenerusGameDegenesisModule DegenerusGameBoxModule
  DegenerusGamePassModule DegenerusGameEndgameModule
)

inspect_norm() {
  if [[ -n "${CHECK_ARTIFACTS:-}" ]]; then
    python3 - "$CHECK_ARTIFACTS" "$1" <<'PY' | "${NORM[@]}"
import json, pathlib, sys
matches = list(pathlib.Path(sys.argv[1]).glob('*/' + sys.argv[2] + '.json'))
if len(matches) != 1:
    raise SystemExit(f'Expected one layout artifact for {sys.argv[2]}, found {len(matches)}')
print(json.dumps(json.loads(matches[0].read_text())['storageLayout']))
PY
  else
    forge inspect "$1" storageLayout --json --skip test 2>/dev/null | "${NORM[@]}"
  fi
}

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
  if ! diff -u "$GOLD/$c.json" <(inspect_norm "$c") > "$DIFF_DIR/layout-$c.diff" 2>&1; then
    echo "::error:: STORAGE LAYOUT CHANGED for $c (slot/offset/type move):"
    cat "$DIFF_DIR/layout-$c.diff"
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

# JackpotBattle delegates in CrapsBattle's context, never in the Game's context.
if ! diff -u <(inspect_norm CrapsBattle) <(inspect_norm JackpotBattle); then
  echo "::error:: JackpotBattle delegate layout differs from CrapsBattle"; fail=1
fi

# Check the concrete deployed groups as well as the component goldens. A shell
# can add storage even when every component's layout remains unchanged.
mapfile -t SELECTED_MODULES < <(node --input-type=module -e '
import {DEPLOYMENTS} from "./scripts/lib/deploymentManifest.js";
for (const row of DEPLOYMENTS)
  if (row.aliases.some(k => k.startsWith("GAME_") && k.endsWith("_MODULE")) && !row.aliases.includes("GAME"))
    console.log(row.contract);
')
if [ "${#SELECTED_MODULES[@]}" -eq 0 ]; then
  echo "::error:: no selected deployment modules"; fail=1
fi
for c in "${SELECTED_MODULES[@]}"; do
  if ! diff -u "$GOLD/DegenerusGame.json" <(inspect_norm "$c"); then
    echo "::error:: selected module $c differs from Game storage"; fail=1
  fi
done

if [ $fail -eq 0 ]; then echo "STORAGE LAYOUT ORACLE: all goldens match ✓"; fi
exit $fail
