#!/usr/bin/env bash
# Delegatecall target alignment check.
#
# For every interface-bound `abi.encodeWithSelector(IXxx.fn.selector, ...)` call
# site in contracts/ (excluding interfaces/ and mocks/), verifies that the
# preceding `<ADDR>.delegatecall(` target address constant matches the
# interface name per the D-03 naming convention. Catches the class of bug
# where a call compiles (selector exists on SOME module) but targets the
# wrong module's address, reverting at runtime on selector mismatch —
# adjacent to the mintPackedFor incident.
#
# Usage: scripts/check-delegatecall-alignment.sh
# Exit code: 0 if every call site is ALIGNED, 1 otherwise.
#
# CONTRACTS_DIR env var overrides the target source tree (used for gate self-tests).

set -euo pipefail

cd "$(dirname "$0")/.."
CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

# Known naming exceptions where the ContractAddresses constant does NOT follow
# pure CamelCase -> UPPER_SNAKE of the interface suffix. Keyed by the stripped
# suffix (post-`I` and post-`DegenerusGame`), value is the post-`GAME_` portion.
declare -A NAMING_EXCEPTIONS=( [GameOverModule]=GAMEOVER_MODULE )

# Translate IDegenerusGameXxxModule -> GAME_XXX_MODULE.
iface_to_constant() {
  local iface="$1" stripped="${1#I}" snake
  stripped="${stripped#DegenerusGame}"
  if [[ -n "${NAMING_EXCEPTIONS[$stripped]:-}" ]]; then
    printf 'GAME_%s\n' "${NAMING_EXCEPTIONS[$stripped]}"; return
  fi
  snake=$(printf '%s' "$stripped" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:lower:]' '[:upper:]')
  [[ "$snake" == *_MODULE ]] || snake="${snake}_MODULE"
  printf 'GAME_%s\n' "$snake"
}

# Fail fast if iface_to_constant produces a constant not in ContractAddresses.sol.
self_test_transform() {
  local addr="${CONTRACTS_DIR}/ContractAddresses.sol" known failed=0 iface expected
  [[ -f "$addr" ]] || { printf "%bFAIL%b %s missing\n" "$RED" "$NC" "$addr"; return 1; }
  known=$(grep -oE 'GAME_[A-Z_]+_MODULE' "$addr" | sort -u)
  for iface in IDegenerusGameAdvanceModule IDegenerusGameGameOverModule \
               IDegenerusGameJackpotModule IDegenerusGameDecimatorModule \
               IDegenerusGameWhaleModule IDegenerusGameMintModule \
               IDegenerusGameLootboxModule IDegenerusGameBoonModule \
               IDegenerusGameDegeneretteModule; do
    expected=$(iface_to_constant "$iface")
    grep -qx "$expected" <<< "$known" || {
      printf "%bFAIL%b self-test: %s -> %s (not in ContractAddresses.sol)\n" \
        "$RED" "$NC" "$iface" "$expected"; failed=1; }
  done
  return $failed
}

# Collect anchor lines: emit "file<TAB>line" tuples where `line` carries the
# `.selector` token. Two passes — Pass A single-line; Pass B split-line with
# the interface alone on a line and `.selector` within 5 lines.
collect_sites() {
  local dir="$1" file lineno sel_line
  grep -rn --include='*.sol' -E 'IDegenerusGame[A-Za-z]+Module\.[a-zA-Z_]+\.selector' "$dir" 2>/dev/null \
    | grep -v "^${dir}/interfaces/" | grep -v "^${dir}/mocks/" \
    | awk -F: '{ print $1 "\t" $2 }'
  grep -rn --include='*.sol' -E '^[[:space:]]*IDegenerusGame[A-Za-z]+Module[[:space:]]*$' "$dir" 2>/dev/null \
    | grep -v "^${dir}/interfaces/" | grep -v "^${dir}/mocks/" \
    | while IFS=: read -r file lineno _; do
        sel_line=$(awk -v n="$lineno" 'NR > n && NR <= n + 5 && /\.selector/ { print NR; exit }' "$file")
        if [[ -n "$sel_line" ]]; then
          printf '%s\t%s\n' "$file" "$sel_line"
        fi
      done
  return 0
}

# Extract interface name at a site. Try the anchor line first; if absent,
# walk back up to 5 lines for a lone `IDegenerusGameXxxModule` token.
extract_interface() {
  local file="$1" line="$2" iface
  iface=$(awk -v n="$line" 'NR == n' "$file" | grep -oE 'IDegenerusGame[A-Za-z]+Module' | head -1)
  [[ -n "$iface" ]] && { printf '%s\n' "$iface"; return; }
  awk -v n="$line" 'NR < n && NR >= n - 5' "$file" | grep -oE 'IDegenerusGame[A-Za-z]+Module' | tail -1
}

fail_total=0; warn_total=0; pass_total=0

printf "Delegatecall target alignment check\n"
printf "===================================\n"
printf "scanning: %s\n\n" "$CONTRACTS_DIR"

self_test_transform || {
  printf "\n%bFAIL%b naming-convention self-test failed — fix transform or exceptions table\n" "$RED" "$NC"
  exit 1
}

sites=$(collect_sites "$CONTRACTS_DIR" | sort -u)
site_count=$(printf '%s\n' "$sites" | grep -c . || true)
printf "sites discovered: %d\n\n" "$site_count"

while IFS=$'\t' read -r file lineno; do
  [[ -z "${file:-}" ]] && continue
  # 10-line window preceding + including the selector anchor.
  window=$(awk -v n="$lineno" 'NR >= n - 10 && NR <= n' "$file")

  # Observed target constant: the canonical form is
  #     <something>.GAME_XXX_MODULE.delegatecall( ... )
  # often split across lines. Require `.delegatecall(` somewhere in the window
  # (anchors this as a real delegatecall site) and take the LAST `.GAME_XXX_MODULE`
  # as the target.
  if printf '%s\n' "$window" | grep -q '\.delegatecall('; then
    target=$(printf '%s\n' "$window" | grep -oE '\.GAME_[A-Z_]+_MODULE' | tail -1 | sed -E 's/^\.//')
  else
    target=""
  fi
  iface=$(extract_interface "$file" "$lineno")

  if [[ -z "$iface" ]]; then
    printf "%bWARN%b %s:%s  could not extract interface name\n" "$YELLOW" "$NC" "$file" "$lineno"
    warn_total=$((warn_total + 1)); continue
  fi
  if [[ ! "$iface" =~ ^IDegenerusGame[A-Za-z]+Module$ ]]; then
    printf "%bWARN%b %s:%s  non-conventional interface name %s\n" "$YELLOW" "$NC" "$file" "$lineno" "$iface"
    warn_total=$((warn_total + 1)); continue
  fi

  expected=$(iface_to_constant "$iface")
  if [[ ! "$expected" =~ ^[A-Z0-9_]+$ ]]; then
    printf "%bWARN%b %s:%s  non-conventional derived constant %s (from %s)\n" \
      "$YELLOW" "$NC" "$file" "$lineno" "$expected" "$iface"
    warn_total=$((warn_total + 1)); continue
  fi

  justified=0
  printf '%s\n' "$window" | grep -q 'delegatecall-alignment: justified' && justified=1

  if [[ -z "$target" ]]; then
    if [[ $justified -eq 1 ]]; then
      printf "%bWARN%b %s:%s  orphan selector (justified): %s\n" "$YELLOW" "$NC" "$file" "$lineno" "$iface"
    else
      printf "%bWARN%b %s:%s  orphan selector (no delegatecall target in 10-line window): %s\n" \
        "$YELLOW" "$NC" "$file" "$lineno" "$iface"
    fi
    warn_total=$((warn_total + 1)); continue
  fi

  if [[ "$target" == "$expected" ]]; then
    printf "%bOK%b   %s:%s  %s -> %s\n" "$GREEN" "$NC" "$file" "$lineno" "$iface" "$target"
    pass_total=$((pass_total + 1))
  elif [[ $justified -eq 1 ]]; then
    printf "%bWARN%b %s:%s  JUSTIFIED mismatch: %s expects %s but targets %s\n" \
      "$YELLOW" "$NC" "$file" "$lineno" "$iface" "$expected" "$target"
    warn_total=$((warn_total + 1))
  else
    printf "%bFAIL%b %s:%s  %s expects %s but targets %s\n" \
      "$RED" "$NC" "$file" "$lineno" "$iface" "$expected" "$target"
    fail_total=$((fail_total + 1))
  fi
done <<< "$sites"

echo
if [[ $fail_total -eq 0 && $warn_total -eq 0 ]]; then
  printf "%bPASS%b %d/%d delegatecall sites aligned\n" "$GREEN" "$NC" "$pass_total" "$site_count"
  exit 0
fi
(( fail_total > 0 )) && printf "%bFAIL%b %d site(s) misaligned\n" "$RED" "$NC" "$fail_total"
(( warn_total > 0 )) && printf "%bWARN%b %d site(s) flagged (orphan / non-conventional / justified)\n" \
  "$YELLOW" "$NC" "$warn_total"
exit 1
