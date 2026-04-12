#!/usr/bin/env bash
# External-function coverage classification gate (CSI-11 / Phase 222).
#
# Enforces the classification contract published in 222-01-COVERAGE-MATRIX.md
# against (a) the live source tree under $CONTRACTS_DIR and (b) a cached
# lcov.info report. Fires on three failure modes:
#   FAIL_DRIFT    external/public function in source has no matrix row
#                 (the mintPackedFor-adjacent regression: dev adds fn w/o
#                 classifying it).
#   FAIL_GAP      matrix row verdict is CRITICAL_GAP but Test Ref is empty
#                 (uncured gap — CSI-11 violation).
#   FAIL_REGRESS  matrix row verdict is COVERED but lcov.info shows
#                 file-level branch coverage < 50% (coverage regressed).
#
# Usage: scripts/coverage-check.sh
# Exit: 0 clean, 1 on any failure.
#
# Env overrides (fixture-friendly):
#   CONTRACTS_DIR  source tree (default: contracts)
#   MATRIX_FILE    coverage matrix (default: Phase 222-01 matrix)
#   LCOV_FILE      cached lcov.info (default: lcov.info in repo root)
#
# IMPORTANT: does NOT invoke `forge coverage` (minutes-long, D-16/D-18).
# Caller produces lcov.info via `forge coverage --report lcov --ir-minimum`
# before running this gate. Missing lcov.info → YELLOW warn, not a failure.

set -euo pipefail

cd "$(dirname "$0")/.."
CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
MATRIX_FILE="${MATRIX_FILE:-.planning/phases/222-external-function-coverage-gap/222-01-COVERAGE-MATRIX.md}"
LCOV_FILE="${LCOV_FILE:-lcov.info}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
BRANCH_THRESHOLD_PCT=50

[[ -f "$MATRIX_FILE" ]] || {
  printf "%bERROR%b coverage matrix not found: %s\n" "$RED" "$NC" "$MATRIX_FILE" >&2
  exit 1
}
[[ -d "$CONTRACTS_DIR" ]] || {
  printf "%bERROR%b CONTRACTS_DIR does not exist: %s\n" "$RED" "$NC" "$CONTRACTS_DIR" >&2
  exit 1
}

# Deployable universe per 222-01 Method Notes: mocks, interfaces, libraries,
# storage, and the top-level test tree are out of scope.
EXCLUDE_PATHS=(
  "${CONTRACTS_DIR}/mocks"
  "${CONTRACTS_DIR}/interfaces"
  "${CONTRACTS_DIR}/libraries"
  "${CONTRACTS_DIR}/storage"
  "${CONTRACTS_DIR}/test"
)

# Top-level data / library files that compile but don't deploy as standalone
# contracts. Matrix excludes these per D-05/D-06. Adding new entries is a
# visible diff in PR review.
NON_DEPLOYABLE_TOP_LEVEL=("ContractAddresses.sol" "DegenerusTraitUtils.sol")
# Abstract-contract utilities: module code ends up deployed via inheritance,
# not as its own address. Excluded per 222-01 Method Notes.
NON_DEPLOYABLE_MODULES=("DegenerusGameMintStreakUtils.sol" "DegenerusGamePayoutUtils.sol")

fail_drift=0
fail_gap=0
fail_regress=0

is_in_list() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$needle" == "$item" ]] && return 0
  done
  return 1
}
is_excluded_path() {
  local f="$1" exc
  for exc in "${EXCLUDE_PATHS[@]}"; do
    [[ "$f" == "$exc"/* ]] && return 0
  done
  return 1
}

# ── Mode A: MATRIX_DRIFT ────────────────────────────────────────────────
# Enumerate external/public functions inside the deployable contract's
# outermost `contract <name>` block (name = basename - .sol). For every
# function, confirm a row exists in the matrix by literal grep of the
# leading backtick+name+`(` anchor. Missing → FAIL_DRIFT.
check_matrix_drift() {
  local file base target
  while IFS= read -r file; do
    base="${file##*/}"
    is_excluded_path "$file" && continue
    if [[ "$file" == "$CONTRACTS_DIR"/*.sol ]]; then
      is_in_list "$base" "${NON_DEPLOYABLE_TOP_LEVEL[@]}" && continue
    fi
    if [[ "$file" == "$CONTRACTS_DIR/modules"/*.sol ]]; then
      is_in_list "$base" "${NON_DEPLOYABLE_MODULES[@]}" && continue
    fi
    target="${base%.sol}"

    while IFS=: read -r lineno name; do
      [[ -z "${lineno:-}" ]] && continue
      if ! grep -qF "\`${name}(" "$MATRIX_FILE"; then
        printf "%bFAIL_DRIFT%b    %s:%s  %s(...) not in coverage matrix\n" \
          "$RED" "$NC" "$file" "$lineno" "$name"
        fail_drift=$((fail_drift + 1))
      fi
    done < <(
      awk -v target="$target" '
        { src[NR] = $0 }
        END {
          in_target = 0; brace = 0; fn_inside = 0
          for (n = 1; n <= NR; n++) {
            line = src[n]
            if (!in_target && match(line, /(^|[[:space:]])contract[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
              tail = substr(line, RSTART, RLENGTH)
              sub(/^[[:space:]]*/, "", tail); sub(/^contract[[:space:]]+/, "", tail)
              if (tail == target) { in_target = 1; brace = 0 }
            }
            if (in_target) {
              ob = gsub(/\{/, "{", line); cb = gsub(/\}/, "}", line)
              orig = src[n]
              if (brace == 0 && ob > 0) brace = ob - cb
              else brace += ob - cb
              if (brace >= 1) {
                if (!fn_inside && match(orig, /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/)) {
                  text = substr(orig, RSTART, RLENGTH)
                  sub(/^[[:space:]]*function[[:space:]]+/, "", text); sub(/[[:space:]]*\(.*/, "", text)
                  nm = text; joined = orig; start = n; depth = 0
                  for (i = 1; i <= length(orig); i++) {
                    c = substr(orig, i, 1)
                    if (c == "(") depth++
                    else if (c == ")") depth--
                  }
                  if (depth <= 0) {
                    # POSIX awk lacks \b; wrap+match on [^alnum_].
                    padded = " " joined " "
                    if (padded ~ /[^[:alnum:]_](external|public)[^[:alnum:]_]/) printf "%d:%s\n", start, nm
                  } else { fn_inside = 1 }
                } else if (fn_inside) {
                  joined = joined " " orig
                  for (i = 1; i <= length(orig); i++) {
                    c = substr(orig, i, 1)
                    if (c == "(") depth++
                    else if (c == ")") depth--
                  }
                  if (depth <= 0) {
                    # Visibility may appear past the `)` — scan next 3 lines too.
                    for (j = 0; j <= 3 && (n + j) <= NR; j++) joined = joined " " src[n + j]
                    padded = " " joined " "
                    if (padded ~ /[^[:alnum:]_](external|public)[^[:alnum:]_]/) printf "%d:%s\n", start, nm
                    fn_inside = 0
                  }
                }
              }
              if (brace == 0 && ob == 0 && cb > 0) { in_target = 0; fn_inside = 0 }
            }
          }
        }
      ' "$file"
    )
  done < <(find "$CONTRACTS_DIR" -maxdepth 2 -name '*.sol' -type f | sort)
}

# Helper: strip leading/trailing whitespace from a named variable.
gsub_trim() {
  local __n="$1"
  local __v="${!__n}"
  __v="${__v#"${__v%%[![:space:]]*}"}"
  __v="${__v%"${__v##*[![:space:]]}"}"
  printf -v "$__n" '%s' "$__v"
}

# ── Mode B: UNCURED_GAP ─────────────────────────────────────────────────
# Every CRITICAL_GAP row must have a non-empty Test Ref cell. Empty /
# `(none)` / `-` rows fire FAIL_GAP.
check_uncured_gaps() {
  local _lead f1 f2 f3 f4 f5 f6 _rest v ref name
  while IFS='|' read -r _lead f1 f2 f3 f4 f5 f6 _rest; do
    v="$f3"; gsub_trim v
    if [[ "$v" == "CRITICAL_GAP" ]]; then
      ref="$f5"; gsub_trim ref
      name="$f1"; gsub_trim name
      if [[ -z "$ref" || "$ref" == "(none)" || "$ref" == "-" ]]; then
        printf "%bFAIL_GAP%b      %s  verdict=CRITICAL_GAP but Test Ref is empty\n" \
          "$RED" "$NC" "$name"
        fail_gap=$((fail_gap + 1))
      fi
    fi
  done < <(grep -E '^\| `[^`]+` \|' "$MATRIX_FILE")
}

# ── Mode C: REGRESSED_COVERAGE ──────────────────────────────────────────
# Every COVERED row must still have file-level branch coverage ≥ 50%
# in the live lcov. Parse lcov once into brf[]/brh[] per SF, then walk
# the matrix by `### Contract:` section and flag any COVERED row whose
# section pct fell below threshold.
check_regressed_coverage() {
  if [[ ! -f "$LCOV_FILE" ]]; then
    printf "%bWARN%b         lcov.info not found at %s — skipping REGRESSED_COVERAGE check (run \`forge coverage --report lcov --ir-minimum\` first)\n" \
      "$YELLOW" "$NC" "$LCOV_FILE"
    return
  fi

  declare -A brf brh
  local cur="" line
  while IFS= read -r line; do
    case "$line" in
      SF:*)          cur="${line#SF:}" ;;
      BRF:*)         brf["$cur"]="${line#BRF:}" ;;
      BRH:*)         brh["$cur"]="${line#BRH:}" ;;
      end_of_record) cur="" ;;
    esac
  done < "$LCOV_FILE"

  local section="" section_pct="" f h
  while IFS= read -r line; do
    if [[ "$line" =~ ^###\ Contract:\ \`([^\`]+)\` ]]; then
      section="${BASH_REMATCH[1]}"
      f="${brf[$section]:-0}"; h="${brh[$section]:-0}"
      if (( f > 0 )); then section_pct=$(( h * 100 / f )); else section_pct="-"; fi
      continue
    fi
    if [[ -n "$section" && "$line" =~ ^\|\ \`([^\`]+)\`\ \|[^|]*\|\ COVERED\ \| ]]; then
      if [[ "$section_pct" != "-" && "$section_pct" -lt "$BRANCH_THRESHOLD_PCT" ]]; then
        printf "%bFAIL_REGRESS%b  %s:%s  verdict=COVERED but branch_cov=%d%% < %d%%\n" \
          "$RED" "$NC" "$section" "${BASH_REMATCH[1]}" "$section_pct" "$BRANCH_THRESHOLD_PCT"
        fail_regress=$((fail_regress + 1))
      fi
    fi
  done < "$MATRIX_FILE"
}

printf "External function coverage-classification check\n"
printf "================================================\n"
printf "matrix: %s\n" "$MATRIX_FILE"
printf "source: %s\n" "$CONTRACTS_DIR"
printf "lcov:   %s\n\n" "$LCOV_FILE"

check_matrix_drift
check_uncured_gaps
check_regressed_coverage

echo
total_fails=$((fail_drift + fail_gap + fail_regress))
if (( total_fails == 0 )); then
  printf "%bPASS%b coverage-check clean (matrix drift=0, uncured gaps=0, regressed rows=0)\n" \
    "$GREEN" "$NC"
  exit 0
fi
printf "%bFAIL%b coverage-check: %d drift, %d uncured gap(s), %d regressed row(s)\n" \
  "$RED" "$NC" "$fail_drift" "$fail_gap" "$fail_regress"
printf "  remediation: add matrix rows for drifted signatures, populate Test Ref for CRITICAL_GAP rows, or re-run forge coverage to refresh lcov.info\n"
exit 1
