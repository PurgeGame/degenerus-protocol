#!/usr/bin/env bash
# Raw selector & hand-rolled calldata check.
#
# For every production .sol file in contracts/ (excluding paths listed in
# EXCLUDE_PATHS), flags:
#   CSI-04: bytes4(0x...) hex literal selectors
#   CSI-05: bytes4(keccak256("...")) string-derived selectors
#   CSI-06: abi.encodeWithSignature(...) calls anywhere in production
#   CSI-06: abi.encodeCall(...) calls anywhere in production
#   CSI-06: abi.encode(...) / abi.encodePacked(...) whose result is passed to
#           .call / .delegatecall / .staticcall / .transferAndCall
#
# Sites may be silenced by:
#   1. Placing a `// raw-selectors: justified — <reason>` comment on the same
#      line or within the two preceding lines (inline per-site override).
#   2. Adding a "<file_basename>:<receiver_or_method>" entry to
#      JUSTIFIED_FEEDERS (content-based allowlist for Pattern E only).
#
# Usage: scripts/check-raw-selectors.sh
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

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

# Path-level exclusion list. contracts/mocks/ intentionally mimics Chainlink
# v2 coordinator wire format and the ERC-677 onTokenTransfer callback; the
# raw abi.encodeWithSignature there is the required form, not a smell.
# contracts/interfaces/ contains no executable code. Adding new entries is a
# visible diff in PR review — abusing this list to hide a raw selector in a
# file under a fake-named "mocks/" subtree is mitigated by diff visibility.
EXCLUDE_PATHS=(
  "${CONTRACTS_DIR}/mocks"
  "${CONTRACTS_DIR}/interfaces"
)

EXCLUDE_GREP_ARGS=()
for p in "${EXCLUDE_PATHS[@]}"; do
  EXCLUDE_GREP_ARGS+=( --exclude-dir="${p##*/}" )
done

# Content-based allowlist for Pattern E (abi.encode* feeding low-level call).
# Entries are "<file_basename>:<call_receiver_or_method>" pairs — if Pattern E
# matches a site whose opener line contains the listed receiver/method AND
# the file basename matches, the site is treated as JUSTIFIED instead of FAIL.
# Every entry MUST have a corresponding row in 221-01-AUDIT.md with the
# JUSTIFIED verdict and the rationale. Adding an entry without updating the
# audit is a visible diff in PR review.
JUSTIFIED_FEEDERS=(
  "DegenerusAdmin.sol:transferAndCall"
)

# Returns 0 (true) if the source line OR either of the two preceding lines
# carries the `raw-selectors: justified` marker. Keep the window small (2
# lines) so the marker stays visibly tied to the site it excuses.
is_justified() {
  local file="$1" lineno="$2"
  local start=$(( lineno > 2 ? lineno - 2 : 1 ))
  awk -v s="$start" -v e="$lineno" 'NR >= s && NR <= e' "$file" \
    | grep -q 'raw-selectors: justified'
}

# Returns 0 (true) if <file_basename>:<opener_content> matches any entry in
# JUSTIFIED_FEEDERS. Used only by Pattern E.
is_justified_feeder() {
  local file="$1" opener_content="$2" base="${1##*/}"
  local entry entry_file entry_match
  for entry in "${JUSTIFIED_FEEDERS[@]}"; do
    entry_file="${entry%%:*}"
    entry_match="${entry#*:}"
    if [[ "$base" == "$entry_file" && "$opener_content" == *"$entry_match"* ]]; then
      return 0
    fi
  done
  return 1
}

fail_total=0
justified_total=0

# Run a single-line grep-based scan over CONTRACTS_DIR for $2 (regex), printing
# FAIL/JUST lines labelled $3 (description) and tagged $4 (CSI-NN). Updates
# the outer fail_total / justified_total counters.
scan_simple() {
  local regex="$1" label="$2" csi="$3"
  while IFS=: read -r file lineno _rest; do
    [[ -z "${file:-}" ]] && continue
    if is_justified "$file" "$lineno"; then
      printf "%bJUST%b %s:%s  %s — justified by marker\n" \
        "$YELLOW" "$NC" "$file" "$lineno" "$label"
      justified_total=$((justified_total + 1))
    else
      printf "%bFAIL%b %s:%s  %s — %s violation\n" \
        "$RED" "$NC" "$file" "$lineno" "$label" "$csi"
      fail_total=$((fail_total + 1))
    fi
  done < <(grep -rnE "$regex" \
             --include='*.sol' "${EXCLUDE_GREP_ARGS[@]}" \
             "$CONTRACTS_DIR" 2>/dev/null || true)
}

printf "Raw selector & calldata check\n"
printf "=============================\n"
printf "scanning: %s\n" "$CONTRACTS_DIR"
printf "excluded paths: %s\n\n" "${EXCLUDE_PATHS[*]}"

# Pattern A — bytes4(0x...) hex literals (CSI-04).
scan_simple 'bytes4\s*\(\s*0x[0-9a-fA-F]+' 'bytes4(0x...) hex literal' 'CSI-04'

# Pattern B — bytes4(keccak256(...)) string-derived selectors (CSI-05).
scan_simple 'bytes4\s*\(\s*keccak256' 'bytes4(keccak256(...)) selector' 'CSI-05'

# Pattern C — abi.encodeWithSignature anywhere in production (CSI-06).
scan_simple 'abi\.encodeWithSignature' 'abi.encodeWithSignature' 'CSI-06'

# Pattern D — abi.encodeCall anywhere in production (CSI-06). Phase 220's
# abi.encodeWithSelector covers the interface-bound case; keeping this gate
# strict nudges future authors toward the audited form.
scan_simple 'abi\.encodeCall' 'abi.encodeCall' 'CSI-06'

# Pattern E — abi.encode(...) / abi.encodePacked(...) feeding a low-level call
# (CSI-06, multi-line). Two-pass awk per file: slurp lines into an array, then
# scan every line as a potential opener so back-to-back openers within the
# 4-line window are each evaluated. gsub-strip the three already-handled
# encode forms before the bare abi.encode*(...) match so they do not double-FAIL.
while IFS=: read -r file lineno; do
  [[ -z "${file:-}" ]] && continue

  opener_content=$(awk -v n="$lineno" 'NR == n' "$file")

  if is_justified "$file" "$lineno"; then
    printf "%bJUST%b %s:%s  abi.encode*(...) payload of low-level call — justified by marker\n" \
      "$YELLOW" "$NC" "$file" "$lineno"
    justified_total=$((justified_total + 1))
  elif is_justified_feeder "$file" "$opener_content"; then
    printf "%bJUST%b %s:%s  abi.encode*(...) payload of low-level call — justified by allowlist\n" \
      "$YELLOW" "$NC" "$file" "$lineno"
    justified_total=$((justified_total + 1))
  else
    printf "%bFAIL%b %s:%s  abi.encode*(...) payload of low-level call — CSI-06 violation (interface-bound form required)\n" \
      "$RED" "$NC" "$file" "$lineno"
    fail_total=$((fail_total + 1))
  fi
done < <(
  find "$CONTRACTS_DIR" -name '*.sol' -type f 2>/dev/null | while read -r file; do
    skip=0
    for excl in "${EXCLUDE_PATHS[@]}"; do
      if [[ "$file" == "$excl"/* ]]; then skip=1; break; fi
    done
    (( skip )) && continue

    awk -v file="$file" '
      { lines[NR] = $0 }
      END {
        for (n = 1; n <= NR; n++) {
          if (lines[n] !~ /\.(call|delegatecall|staticcall|transferAndCall)[[:space:]]*(\{[^}]*\})?[[:space:]]*\(/) continue
          window = lines[n]
          for (j = 1; j <= 3 && (n + j) <= NR; j++) {
            window = window "\n" lines[n + j]
          }
          stripped = window
          gsub(/abi\.encodeWithSelector[[:space:]]*\(/, "HANDLED_EWS(", stripped)
          gsub(/abi\.encodeWithSignature[[:space:]]*\(/, "HANDLED_EWSIG(", stripped)
          gsub(/abi\.encodeCall[[:space:]]*\(/, "HANDLED_ECALL(", stripped)
          if (stripped ~ /abi\.encode(Packed)?[[:space:]]*\(/) {
            print file ":" n
          }
        }
      }
    ' "$file"
  done | sort -u
)

echo
if (( fail_total == 0 )); then
  if (( justified_total == 0 )); then
    printf "%bPASS%b no raw selectors or hand-rolled calldata encoders in %s (excluding %s)\n" \
      "$GREEN" "$NC" "$CONTRACTS_DIR" "${EXCLUDE_PATHS[*]}"
  else
    printf "%bPASS%b %d justified site(s) acknowledged, no unjustified raw selectors or hand-rolled encoders\n" \
      "$GREEN" "$NC" "$justified_total"
  fi
  exit 0
fi
printf "%bFAIL%b %d site(s) with raw selector or hand-rolled encoding — replace with interface-bound form or add \`// raw-selectors: justified — <reason>\` marker\n" \
  "$RED" "$NC" "$fail_total"
exit 1
