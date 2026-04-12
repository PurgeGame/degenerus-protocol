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

# Reverse of NAMING_EXCEPTIONS for constant_to_iface(). Keyed by the post-`GAME_`
# pre-`_MODULE` fragment, value is the CamelCase fragment that sits between
# `IDegenerusGame` and `Module`. Mirrors NAMING_EXCEPTIONS on the opposite end
# so both directions stay in sync. Only needed for CamelCase anomalies the
# default UPPER_SNAKE -> CamelCase transform can't derive (compound English
# words where the internal capital differs from the first letter of a
# `_`-delimited segment).
declare -A REVERSE_NAMING_EXCEPTIONS=( [GAMEOVER]=GameOver )

# Known dead constants — declared in ContractAddresses.sol but not expected to
# have a matching interface or any call sites. Remove entries here only when
# the constant itself is removed (Phase 223 consolidation will decide).
# Appending to this list silences the preflight for a specific constant and is
# a visible diff in PR review (threat T-220-07 mitigation).
DEAD_CONSTANTS=(
  GAME_ENDGAME_MODULE
)

is_dead_constant() {
  local c="$1" dead
  for dead in "${DEAD_CONSTANTS[@]}"; do
    [[ "$c" == "$dead" ]] && return 0
  done
  return 1
}

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

# Reverse: GAME_XXX_MODULE -> IDegenerusGameXxxModule. Used by the mapping
# preflight to derive each constant's expected interface.
constant_to_iface() {
  local c="$1" stripped="${1#GAME_}" camel
  stripped="${stripped%_MODULE}"
  if [[ -n "${REVERSE_NAMING_EXCEPTIONS[$stripped]:-}" ]]; then
    printf 'IDegenerusGame%sModule\n' "${REVERSE_NAMING_EXCEPTIONS[$stripped]}"
    return
  fi
  # Default: UPPER_SNAKE -> CamelCase (lowercase all, uppercase first letter
  # of each `_`-delimited word, concat).
  camel=$(printf '%s' "$stripped" | awk 'BEGIN{FS="_"; OFS=""}
    { for (i = 1; i <= NF; i++) $i = toupper(substr($i,1,1)) tolower(substr($i,2)); print }')
  printf 'IDegenerusGame%sModule\n' "$camel"
}

# Preflight: walk the universe of GAME_*_MODULE constants and Iface declarations
# and prove every LIVE constant has a matching interface AND every interface has
# a matching constant. Catches the drift that per-site checks can't see — e.g.,
# a new interface is added but no caller exists yet, so no per-site row is ever
# produced. Runs BEFORE the per-site loop; exits 1 on any mismatch.
validate_mapping() {
  local addr="${CONTRACTS_DIR}/ContractAddresses.sol"
  local ifaces="${CONTRACTS_DIR}/interfaces/IDegenerusGameModules.sol"
  local constants interfaces live_count=0 mapping_fails=0 c i expected
  [[ -f "$addr" ]] || { printf "%bFAIL%b %s missing\n" "$RED" "$NC" "$addr"; return 1; }
  [[ -f "$ifaces" ]] || { printf "%bFAIL%b %s missing\n" "$RED" "$NC" "$ifaces"; return 1; }
  constants=$(grep -oE 'GAME_[A-Z_]+_MODULE' "$addr" | sort -u)
  interfaces=$(grep -oE 'interface IDegenerusGame[A-Za-z]+Module' "$ifaces" \
    | awk '{print $2}' | sort -u)

  # Every LIVE constant must resolve to a declared interface.
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if is_dead_constant "$c"; then
      printf "%bDEAD%b %-30s known-dead constant (no interface expected)\n" \
        "$YELLOW" "$NC" "$c"
      continue
    fi
    expected=$(constant_to_iface "$c")
    if printf '%s\n' "$interfaces" | grep -qx "$expected"; then
      live_count=$((live_count + 1))
    else
      printf "%bMAP_FAIL%b %-30s expected interface %s not found in IDegenerusGameModules.sol\n" \
        "$RED" "$NC" "$c" "$expected"
      mapping_fails=$((mapping_fails + 1))
    fi
  done <<< "$constants"

  # Every interface must resolve to a declared constant.
  while IFS= read -r i; do
    [[ -z "$i" ]] && continue
    expected=$(iface_to_constant "$i")
    if printf '%s\n' "$constants" | grep -qx "$expected"; then
      :
    else
      printf "%bMAP_FAIL%b %-40s expected constant %s not found in ContractAddresses.sol\n" \
        "$RED" "$NC" "$i" "$expected"
      mapping_fails=$((mapping_fails + 1))
    fi
  done <<< "$interfaces"

  if (( mapping_fails > 0 )); then
    printf "%bFAIL%b interface <-> address map has %d mismatch(es) — universe is inconsistent\n" \
      "$RED" "$NC" "$mapping_fails"
    return 1
  fi
  printf "%bOK%b   interface <-> address map: %d LIVE pair(s) validated, %d known-dead constant(s) skipped\n" \
    "$GREEN" "$NC" "$live_count" "${#DEAD_CONSTANTS[@]}"
  return 0
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

# Universe-level 1:1 mapping preflight. Runs before the per-site loop so that
# if the constant <-> interface universe is inconsistent, we fail fast with a
# precise error rather than misleading per-site output. See 220-02-MAPPING.md.
validate_mapping || {
  printf "\n%bFAIL%b mapping-preflight failed — fix the universe (add missing interface/constant or extend DEAD_CONSTANTS / NAMING_EXCEPTIONS)\n" "$RED" "$NC"
  exit 1
}
printf "\n"

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
