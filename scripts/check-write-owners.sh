#!/usr/bin/env bash
# Storage write-ownership gate (WOWN).
#
# Twelve modules delegatecall onto one storage base. The layout oracle proves the slots do not
# move; nothing proved WHICH module may write WHICH variable. This gate registers every
# (variable, file) write pairing across the game facade, the storage base and the modules —
# re-derived from source by scripts/lib/rng_window_extract.py over the storage layout's labels
# (scripts/layout/golden/DegenerusGame.json) — in scripts/write-owners-manifest.tsv, and fails
# when a module starts writing a variable it did not own.
#
#   WOWN-01  a live (identifier|file) write pairing is not in the manifest — a new writer.
#   WOWN-02  a manifest row no longer matches any live write — stale.
#   WOWN-03  unknown class.
#
# Classes: OWNER (this file is an intended writer of the variable; rationale names the role) ·
#          HELPER (the storage base's own mutator helper, called by owners) · INIT (constructor /
#          one-shot initialisation only).
#
# Usage: scripts/check-write-owners.sh [--self-test]
set -euo pipefail
cd "$(dirname "$0")/.."
CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
MANIFEST_FILE="${MANIFEST_FILE:-scripts/write-owners-manifest.tsv}"
LAYOUT="${LAYOUT:-scripts/layout/golden/DegenerusGame.json}"
EXTRACT="scripts/lib/rng_window_extract.py"
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'

labels() {
  python3 - "$LAYOUT" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1])); st=d.get('storage',d) if isinstance(d,dict) else d
print(",".join(sorted({e['label'] for e in (st if isinstance(st,list) else st.get('storage',[]))})))
EOF
}

run_gate() {
  [[ -f "$MANIFEST_FILE" ]] || { printf "ERROR: no manifest %s\n" "$MANIFEST_FILE" >&2; return 2; }
  local live man ids; live="$(mktemp)"; man="$(mktemp)"
  ids="${IDS_OVERRIDE:-$(labels)}"
  IDENTIFIERS="$ids" EXCLUDE_DIRS="interfaces,mocks,test" CONTRACTS_DIR="$CONTRACTS_DIR" python3 "$EXTRACT" \
    | awk -F'\t' -v scope="${SCOPE_RE:-^(DegenerusGame\\.sol|storage/|modules/)}" '$4=="WRITE" && $1 ~ scope {print $3"|"$1}' | sort -u > "$live"
  awk -F'\t' '/^#/||/^[[:space:]]*$/{next} $1=="CLASS"{next} {print $2"|"$3}' "$MANIFEST_FILE" | sort -u > "$man"
  local fails=0 line
  while IFS= read -r line; do [[ -z "$line" ]] && continue; printf "%bFAIL%b WOWN-01 unregistered writer: %s\n" "$RED" "$NC" "$line"; fails=$((fails+1)); done < <(comm -23 "$live" "$man")
  while IFS= read -r line; do [[ -z "$line" ]] && continue; printf "%bFAIL%b WOWN-02 stale row: %s\n" "$RED" "$NC" "$line"; fails=$((fails+1)); done < <(comm -13 "$live" "$man")
  while IFS=$'\037' read -r cls id file rationale; do
    [[ -z "$cls" || "$cls" == \#* || "$cls" == "CLASS" ]] && continue
    case "$cls" in OWNER|HELPER|INIT) ;; *) printf "%bFAIL%b WOWN-03 unknown class %s: %s %s\n" "$RED" "$NC" "$cls" "$id" "$file"; fails=$((fails+1));; esac
  done < <(tr '\t' '\037' < "$MANIFEST_FILE")
  [[ "${QUIET:-0}" == "1" ]] || printf "live pairings: %d   manifest rows: %d\n" "$(wc -l < "$live")" "$(wc -l < "$man")"
  rm -f "$live" "$man"; return $(( fails > 0 ? 1 : 0 ))
}

self_test() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/src/modules"
  printf 'pragma solidity ^0.8.26;\ncontract S { uint256 internal level; uint256 internal cursor; }\n' > "$tmp/src/Storage.sol"
  printf 'pragma solidity ^0.8.26;\nimport "../Storage.sol";\ncontract A is S { function f() external { level = 1; } }\n' > "$tmp/src/modules/A.sol"
  printf 'pragma solidity ^0.8.26;\nimport "../Storage.sol";\ncontract B is S { function g() external { cursor = 2; } }\n' > "$tmp/src/modules/B.sol"
  printf 'CLASS\tidentifier\tfile\trationale\nOWNER\tlevel\tmodules/A.sol\tA owns level\nOWNER\tcursor\tmodules/B.sol\tB owns cursor\n' > "$tmp/m.tsv"
  local pass=0 fail=0 out
  if CONTRACTS_DIR="$tmp/src" IDS_OVERRIDE="level,cursor" SCOPE_RE="^(Storage\\.sol|modules/)" MANIFEST_FILE="$tmp/m.tsv" QUIET=1 run_gate >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "self-test 1 FAIL"; fi
  grep -v cursor "$tmp/m.tsv" > "$tmp/m2.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" IDS_OVERRIDE="level,cursor" SCOPE_RE="^(Storage\\.sol|modules/)" MANIFEST_FILE="$tmp/m2.tsv" QUIET=1 run_gate 2>&1 || true)"
  grep -q WOWN-01 <<<"$out" && pass=$((pass+1)) || { fail=$((fail+1)); echo "self-test 2 FAIL"; }
  printf "self-tests: %d passed, %d failed\n" "$pass" "$fail"; return $(( fail > 0 ? 1 : 0 ))
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; exit $?; fi
if run_gate; then printf "%bPASS%b every shared-storage writer is registered\n" "$GREEN" "$NC"; exit 0
else printf "%bFAIL%b storage write-ownership drift (see above)\n" "$RED" "$NC"; exit 1; fi
