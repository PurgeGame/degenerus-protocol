#!/usr/bin/env bash
# Unbounded-storage-clear check.
#
# `delete` on a dynamic storage array (or on a struct containing one) compiles
# into a loop zeroing EVERY element slot (~5k gas each against committed
# storage). The explicit batch loops are write-budgeted, but this
# compiler-generated clear is not — a long array turns the deleting call into
# an out-of-gas brick (measured: 15.16M gas at 3,000 elements; past the 16.7M
# ceiling near ~3,300). Release a dynamic array in O(1) instead: zero only the
# length slot (see DegenerusGameStorage._releaseTicketQueue) or advance a
# cursor past the data.
#
# Detection (source text, two passes over production contracts/):
#   ADC-01: `delete <name>` / `delete <name>[...]` where <name> is a declared
#           dynamic-array storage variable or a mapping whose value type is a
#           dynamic array (declaration scan across all production files).
#   ADC-02: `delete <ident>;` where <ident> is a local `T[] storage` pointer
#           (alias-delete of a dynamic array; same-file scan).
#
# Sites may be silenced by a `// array-delete: justified — <reason>` comment
# on the same line or within the two preceding lines (e.g. a compile-time
# bounded array proven small).
#
# LIMITATION: the declaration scan sees direct dynamic-array variables and
# mappings only — it does not resolve struct types, so `delete` on a struct
# variable whose MEMBERS include a dynamic array compiles into the same
# unbounded clear but is not flagged. No production struct currently nests a
# dynamic member; verify against optimized IR (no clear_storage helpers)
# before trusting this gate across a change that adds one.
#
# Usage: scripts/check-array-delete.sh
# Exit code: 0 if no unjustified sites found, 1 otherwise.
#
# CONTRACTS_DIR env var overrides the target source tree (used for gate self-tests).

set -euo pipefail

cd "$(dirname "$0")/.."
CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"

[[ -d "$CONTRACTS_DIR" ]] || {
  printf "ERROR: CONTRACTS_DIR does not exist: %s\n" "$CONTRACTS_DIR" >&2
  exit 1
}

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'

# contracts/mocks/ mimics external wire formats and never runs in production;
# contracts/interfaces/ contains no executable code.
EXCLUDE_PATHS=("$CONTRACTS_DIR/mocks/" "$CONTRACTS_DIR/interfaces/")

is_excluded() {
  local f="$1" p
  for p in "${EXCLUDE_PATHS[@]}"; do [[ "$f" == "$p"* ]] && return 0; done
  return 1
}

# Collect production files.
FILES=()
while IFS= read -r f; do
  is_excluded "$f" || FILES+=("$f")
done < <(find "$CONTRACTS_DIR" -name '*.sol' | sort)

# Pass 0: names of every dynamic-array storage variable across production
# files — bare declarations (`T[] visibility name;`) and mappings whose value
# type contains a dynamic array (`mapping(K => T[]...)` at any nesting depth).
DYN_ARRAY_NAMES=()
while IFS= read -r name; do
  [[ -n "$name" ]] && DYN_ARRAY_NAMES+=("$name")
done < <(
  cat "${FILES[@]}" | grep -hoE \
    '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\[\][[:space:]]+(internal|private|public)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|mapping\([^;]*=>[^;]*\[\][^;]*\)[[:space:]]+(internal|private|public)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
    | grep -oE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$' | sort -u
)

# A site is silenced when the line itself or either of the two preceding lines
# carries the justification marker.
justified() {
  local file="$1" lineno="$2"
  local from=$(( lineno > 2 ? lineno - 2 : 1 ))
  sed -n "${from},${lineno}p" "$file" | grep -q 'array-delete: justified' && return 0
  return 1
}

FAIL=0

report() {
  printf "%sFAIL%s %s: %s:%s: %s\n" "$RED" "$NC" "$1" "$2" "$3" "$4"
  FAIL=1
}

for f in "${FILES[@]}"; do
  # ADC-01: delete of a known dynamic-array storage variable (direct or any
  # mapping-indexed form ending at the array, e.g. `delete ticketQueue[rk]`).
  if [[ ${#DYN_ARRAY_NAMES[@]} -gt 0 ]]; then
    for name in "${DYN_ARRAY_NAMES[@]}"; do
      while IFS=: read -r ln text; do
        [[ -z "$ln" ]] && continue
        justified "$f" "$ln" && continue
        report "ADC-01 delete of dynamic storage array" "$f" "$ln" "$(echo "$text" | sed 's/^[[:space:]]*//')"
      done < <(sed 's|//.*||' "$f" | grep -nE "\bdelete[[:space:]]+${name}\b" || true)
    done
  fi

  # ADC-02: delete of a local `T[] storage` pointer (alias-delete). Collect the
  # file's storage-pointer identifiers, then flag `delete <ident>` on them.
  while IFS= read -r ident; do
    [[ -z "$ident" ]] && continue
    while IFS=: read -r ln text; do
      [[ -z "$ln" ]] && continue
      justified "$f" "$ln" && continue
      report "ADC-02 delete via storage-array pointer" "$f" "$ln" "$(echo "$text" | sed 's/^[[:space:]]*//')"
    done < <(sed 's|//.*||' "$f" | grep -nE "\bdelete[[:space:]]+${ident}[[:space:]]*;" || true)
  done < <(grep -hoE '\[\][[:space:]]+storage[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' | sort -u)
done

if [[ $FAIL -eq 0 ]]; then
  printf "%sPASS%s no unbounded dynamic-array delete in production contracts\n" "$GREEN" "$NC"
  exit 0
fi
printf "%sFAIL%s dynamic-array delete compiles to an unbounded element-clearing loop — release the length slot in O(1) instead (see DegenerusGameStorage._releaseTicketQueue)\n" "$RED" "$NC"
exit 1
