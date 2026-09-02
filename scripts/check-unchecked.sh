#!/usr/bin/env bash
# Unchecked-arithmetic registry gate (UNCK).
#
# Every `unchecked { ... }` block in the main contract set (scripts/lib/unchecked_extract.py:
# the game facade, its storage base, every module) must be registered in
# scripts/unchecked-manifest.tsv with the invariant that keeps its arithmetic in range. An
# unchecked subtraction with a wrong bound is the canonical critical; this keeps the bound
# argument for every block on record and fails the build when a block is added, moved, or its
# leading statement rewritten, until the record is redone.
#
# The gate FAILS when:
#   UNCK-01  a live block (file|function|ordinal|head) is not in the manifest.
#   UNCK-02  a manifest row matches no live block (stale).
#   UNCK-03  a row's class is unknown, or a BOUNDED row has no rationale.
#
# Classes: BOUNDED (the rationale names the invariant keeping every op in range) ·
#          WRAP-INTENDED (modular arithmetic on purpose; the rationale says why wrap is safe) ·
#          NO-OVERFLOW-OP (the block holds no op that can leave the type's range: counters below
#          a small cap, shifts of masked values, index math under a length check) ·
#          SCALE-BOUNDED (no code guard; the only bound is economic scale — documented design).
#
# Usage: scripts/check-unchecked.sh [--self-test]
# Env: CONTRACTS_DIR, MANIFEST_FILE, SCOPE_FILES.
set -euo pipefail
cd "$(dirname "$0")/.."
CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
MANIFEST_FILE="${MANIFEST_FILE:-scripts/unchecked-manifest.tsv}"
EXTRACT="scripts/lib/unchecked_extract.py"
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'

run_gate() {
  [[ -f "$MANIFEST_FILE" ]] || { printf "ERROR: no manifest %s\n" "$MANIFEST_FILE" >&2; return 2; }
  local live man; live="$(mktemp)"; man="$(mktemp)"
  # Extractor: file(1) function(2) ordinal(3) head(4) lineno(5) ops(6)
  CONTRACTS_DIR="$CONTRACTS_DIR" SCOPE_FILES="${SCOPE_FILES:-}" python3 "$EXTRACT" \
    | awk -F'\t' '{print $1"|"$2"|"$3"|"$4}' | sort -u > "$live"
  # Manifest: class(1) file(2) function(3) ordinal(4) head(5) rationale(6)
  awk -F'\t' '/^#/||/^[[:space:]]*$/{next} $1=="CLASS"{next} {print $2"|"$3"|"$4"|"$5}' "$MANIFEST_FILE" | sort -u > "$man"
  local fails=0 line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf "%bFAIL%b UNCK-01 unregistered unchecked block: %s\n" "$RED" "$NC" "$line"; fails=$((fails+1))
  done < <(comm -23 "$live" "$man")
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf "%bFAIL%b UNCK-02 stale manifest row: %s\n" "$RED" "$NC" "$line"; fails=$((fails+1))
  done < <(comm -13 "$live" "$man")
  while IFS=$'\037' read -r cls file fn ord head rationale; do
    [[ -z "$cls" || "$cls" == \#* || "$cls" == "CLASS" ]] && continue
    case "$cls" in
      BOUNDED|WRAP-INTENDED) [[ -z "${rationale:-}" ]] && { printf "%bFAIL%b UNCK-03 %s row without a rationale: %s %s #%s\n" "$RED" "$NC" "$cls" "$file" "$fn" "$ord"; fails=$((fails+1)); } ;;
      NO-OVERFLOW-OP) ;;
      SCALE-BOUNDED) [[ -z "${rationale:-}" ]] && { printf "%bFAIL%b UNCK-03 SCALE-BOUNDED row without a rationale: %s %s #%s\n" "$RED" "$NC" "$file" "$fn" "$ord"; fails=$((fails+1)); } ;;
      *) printf "%bFAIL%b UNCK-03 unknown class %s: %s %s #%s\n" "$RED" "$NC" "$cls" "$file" "$fn" "$ord"; fails=$((fails+1)) ;;
    esac
  done < <(tr '\t' '\037' < "$MANIFEST_FILE")
  if [[ "${QUIET:-0}" != "1" ]]; then
    printf "manifest classes: "; awk -F'\t' '/^#/||/^[[:space:]]*$/{next} $1=="CLASS"{next} {c[$1]++} END{n=0; for(k in c){printf "%s%s=%d",(n++?", ":""),k,c[k]}; print ""}' "$MANIFEST_FILE"
    printf "live blocks: %d   manifest rows: %d\n" "$(wc -l < "$live")" "$(wc -l < "$man")"
  fi
  rm -f "$live" "$man"; return $(( fails > 0 ? 1 : 0 ))
}

self_test() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/src"
  cat > "$tmp/src/F.sol" <<'SOL'
pragma solidity ^0.8.26;
contract F {
    uint256 public n;
    function a(uint256 x) external { unchecked { n = x - 1; } }   // BOUNDED
    function b() external { unchecked { n++; } }                  // NO-OVERFLOW-OP
}
SOL
  printf 'CLASS\tfile\tfunction\tordinal\thead\trationale\nBOUNDED\tF.sol\ta\t1\tn = x - 1\tcaller passes x >= 1\nNO-OVERFLOW-OP\tF.sol\tb\t1\tn++\t\n' > "$tmp/m.tsv"
  local pass=0 fail=0 out
  if CONTRACTS_DIR="$tmp/src" SCOPE_FILES="F.sol" MANIFEST_FILE="$tmp/m.tsv" QUIET=1 run_gate >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "self-test 1 FAIL"; fi
  grep -v '^NO-OVERFLOW' "$tmp/m.tsv" > "$tmp/m2.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" SCOPE_FILES="F.sol" MANIFEST_FILE="$tmp/m2.tsv" QUIET=1 run_gate 2>&1 || true)"
  grep -q UNCK-01 <<<"$out" && pass=$((pass+1)) || { fail=$((fail+1)); echo "self-test 2 FAIL"; }
  sed 's/caller passes x >= 1//' "$tmp/m.tsv" > "$tmp/m3.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" SCOPE_FILES="F.sol" MANIFEST_FILE="$tmp/m3.tsv" QUIET=1 run_gate 2>&1 || true)"
  grep -q UNCK-03 <<<"$out" && pass=$((pass+1)) || { fail=$((fail+1)); echo "self-test 3 FAIL"; }
  printf "self-tests: %d passed, %d failed\n" "$pass" "$fail"; return $(( fail > 0 ? 1 : 0 ))
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; exit $?; fi
if run_gate; then printf "%bPASS%b every unchecked block is registered with its bound\n" "$GREEN" "$NC"; exit 0
else printf "%bFAIL%b unchecked-arithmetic registry drift (see above)\n" "$RED" "$NC"; exit 1; fi
