#!/usr/bin/env bash
# SOLV pool-write drift gate.
#
# Enforces that every mutation of a counted ETH-obligation term — and every call
# of a canonical mutator helper — is registered and classified in
# scripts/pool-write-manifest.tsv. The manifest is the reviewed source-of-truth
# for "which sites move obligation value and why each preserves the accounting
# model" (the obligation enumeration was proven complete against source at review
# time; this gate keeps that true against source drift).
#
# The gate FAILS when:
#   SOLV-01  a live scoped access (identifier|function|file|mode) is NOT in the
#            manifest — a new/moved pool mutation that must be classified
#            (paired? backed by value-in? relabel?) before it ships.
#   SOLV-02  a manifest row no longer matches any live scoped access — a stale
#            entry to remove (the site was deleted or renamed).
#   SOLV-03  the manifest's TRACKED_SET differs from this script's identifier
#            list — the scan scope and the reviewed registry have diverged.
#
# Scope: WRITE and DECL rows of the raw counted-term variables (catches any new
# direct write, including one that bypasses the canonical helpers) plus EVERY
# row of the canonical mutator helpers (call sites and definitions — calls carry
# the per-site accounting judgement). Raw-variable READ rows are out of scope:
# accounting reads are not the drift class this gate guards (unlike RNG windows).
#
# Usage:
#   scripts/check-pool-writes.sh             # gate the real tree (default)
#   scripts/check-pool-writes.sh --self-test # prove the gate catches drift
#
# Env overrides (used by --self-test):
#   CONTRACTS_DIR   source tree to scan  (default: contracts)
#   MANIFEST_FILE   manifest path        (default: scripts/pool-write-manifest.tsv)
#
# Exit code: 0 if the registry matches source, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
MANIFEST_FILE="${MANIFEST_FILE:-scripts/pool-write-manifest.tsv}"
EXTRACT="scripts/lib/rng_window_extract.py"

# The counted terms + canonical mutator helpers. Must equal the manifest's
# TRACKED_SET header line (SOLV-03).
TRACKED_IDENTIFIERS="claimablePool,currentPrizePool,prizePoolsPacked,prizePoolPendingPacked,yieldAccumulator,_setPrizePools,_setPendingPools,_setCurrentPrizePool,_setFuturePrizePool,_addPrizeContribution,_creditClaimable,_addNextPrizePool,_addFuturePrizePool"

# contracts/test holds test-only harnesses (not production surface).
SCAN_EXCLUDE_DIRS="interfaces,mocks,test"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'

# ---------------------------------------------------------------------------
# Core gate. Prints findings; returns 0 (pass) / 1 (fail).
# ---------------------------------------------------------------------------
run_gate() {
  [[ -d "$CONTRACTS_DIR" ]] || { printf "ERROR: CONTRACTS_DIR does not exist: %s\n" "$CONTRACTS_DIR" >&2; return 2; }
  [[ -f "$MANIFEST_FILE" ]] || { printf "ERROR: MANIFEST_FILE does not exist: %s\n" "$MANIFEST_FILE" >&2; return 2; }

  local live_keys manifest_keys
  live_keys="$(mktemp)"; manifest_keys="$(mktemp)"

  # Live scoped access set -> canonical key: identifier|function|file|mode.
  # Extractor columns: file(1) function(2) identifier(3) mode(4) lineno(5) code(6).
  # Scope filter: WRITE/DECL rows of the raw terms + every helper (_-prefixed) row.
  CONTRACTS_DIR="$CONTRACTS_DIR" IDENTIFIERS="$TRACKED_IDENTIFIERS" \
    EXCLUDE_DIRS="$SCAN_EXCLUDE_DIRS" python3 "$EXTRACT" \
    | awk -F'\t' '$4=="WRITE" || $4=="DECL" || $3 ~ /^_/ {print $3"|"$2"|"$1"|"$4}' \
    | sort -u > "$live_keys"

  # Manifest set -> same key. Skip comments, blanks, and the column header.
  # Manifest columns: class(1) identifier(2) function(3) file(4) mode(5) rationale(6).
  awk -F'\t' '
    /^#/ {next} /^[[:space:]]*$/ {next}
    $1=="CLASS" {next}
    {print $2"|"$3"|"$4"|"$5}
  ' "$MANIFEST_FILE" | sort -u > "$manifest_keys"

  local fails=0

  # SOLV-01: live scoped access absent from the manifest.
  local unregistered
  unregistered="$(comm -23 "$live_keys" "$manifest_keys" || true)"
  if [[ -n "$unregistered" ]]; then
    while IFS='|' read -r ident fn file mode; do
      [[ -z "$ident" ]] && continue
      printf "%bFAIL%b SOLV-01 unregistered pool mutation: %s %s in %s (%s)\n" \
        "$RED" "$NC" "$mode" "$ident" "$fn" "$file"
      fails=$((fails+1))
    done <<< "$unregistered"
  fi

  # SOLV-02: manifest row with no matching live access (stale).
  local stale
  stale="$(comm -13 "$live_keys" "$manifest_keys" || true)"
  if [[ -n "$stale" ]]; then
    while IFS='|' read -r ident fn file mode; do
      [[ -z "$ident" ]] && continue
      printf "%bFAIL%b SOLV-02 stale manifest row (no source match): %s %s in %s (%s)\n" \
        "$RED" "$NC" "$mode" "$ident" "$fn" "$file"
      fails=$((fails+1))
    done <<< "$stale"
  fi

  # SOLV-03: manifest TRACKED_SET must equal this script's identifier list.
  local tracked_line script_set
  tracked_line="$(grep -E '^# TRACKED_SET:' "$MANIFEST_FILE" | head -1 | sed 's/^# TRACKED_SET:[[:space:]]*//')"
  script_set="$(printf '%s' "$TRACKED_IDENTIFIERS" | tr ',' ' ')"
  if [[ "$(printf '%s\n' $tracked_line | sort)" != "$(printf '%s\n' $script_set | sort)" ]]; then
    printf "%bFAIL%b SOLV-03 manifest TRACKED_SET differs from the gate's identifier list — re-review scope\n" "$RED" "$NC"
    fails=$((fails+1))
  fi

  if [[ "${QUIET:-0}" != "1" ]]; then
    printf "manifest classes: "
    awk -F'\t' '/^#/||/^[[:space:]]*$/{next} $1=="CLASS"{next} {c[$1]++} END{n=0; for(k in c){printf "%s%s=%d", (n++? ", ":""), k, c[k]}; print ""}' "$MANIFEST_FILE"
    printf "live scoped accesses: %d   manifest rows: %d\n" "$(wc -l < "$live_keys")" "$(wc -l < "$manifest_keys")"
  fi

  rm -f "$live_keys" "$manifest_keys"
  return $(( fails > 0 ? 1 : 0 ))
}

# ---------------------------------------------------------------------------
# Self-test: throwaway fixtures prove the gate catches each drift mode.
# ---------------------------------------------------------------------------
self_test() {
  local pass=0 fail=0
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src"
  cat > "$tmp/src/Fixture.sol" <<'SOL'
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
contract Fixture {
    uint128 internal claimablePool;
    function registeredCredit(uint128 x) external {
        claimablePool += x;
    }
    function sneakyNewDebit(uint128 x) external {
        claimablePool -= x;
    }
}
SOL

  # (T1) manifest registers only ONE of the two writes -> SOLV-01 must FAIL.
  cat > "$tmp/manifest_missing.tsv" <<MAN
# TRACKED_SET: $(printf '%s' "$TRACKED_IDENTIFIERS" | tr ',' ' ')
CLASS	IDENTIFIER	FUNCTION	FILE	MODE	RATIONALE
DECL	claimablePool	<file-scope>	Fixture.sol	DECL	fixture decl
VALUE-IN	claimablePool	registeredCredit	Fixture.sol	WRITE	fixture credit
MAN
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/manifest_missing.tsv" QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bSELF-TEST FAIL%b T1: gate PASSED with an unregistered write (SOLV-01 not enforced)\n" "$RED" "$NC"; fail=$((fail+1))
  else
    printf "%bok%b T1: SOLV-01 fires on an unregistered pool write\n" "$GREEN" "$NC"; pass=$((pass+1))
  fi

  # (T2) manifest registers BOTH writes -> gate must PASS.
  cat > "$tmp/manifest_full.tsv" <<MAN
# TRACKED_SET: $(printf '%s' "$TRACKED_IDENTIFIERS" | tr ',' ' ')
CLASS	IDENTIFIER	FUNCTION	FILE	MODE	RATIONALE
DECL	claimablePool	<file-scope>	Fixture.sol	DECL	fixture decl
VALUE-IN	claimablePool	registeredCredit	Fixture.sol	WRITE	fixture credit
VALUE-OUT	claimablePool	sneakyNewDebit	Fixture.sol	WRITE	fixture debit
MAN
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/manifest_full.tsv" QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bok%b T2: gate passes when every scoped access is registered\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bSELF-TEST FAIL%b T2: gate FAILED on a fully-registered fixture (false positive)\n" "$RED" "$NC"; fail=$((fail+1))
  fi

  # (T3) manifest has an extra row with no source match -> SOLV-02 must FAIL.
  cat > "$tmp/manifest_stale.tsv" <<MAN
# TRACKED_SET: $(printf '%s' "$TRACKED_IDENTIFIERS" | tr ',' ' ')
CLASS	IDENTIFIER	FUNCTION	FILE	MODE	RATIONALE
DECL	claimablePool	<file-scope>	Fixture.sol	DECL	fixture decl
VALUE-IN	claimablePool	registeredCredit	Fixture.sol	WRITE	fixture credit
VALUE-OUT	claimablePool	sneakyNewDebit	Fixture.sol	WRITE	fixture debit
VALUE-OUT	claimablePool	deletedDebit	Fixture.sol	WRITE	stale row
MAN
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/manifest_stale.tsv" QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bSELF-TEST FAIL%b T3: gate PASSED with a stale manifest row (SOLV-02 not enforced)\n" "$RED" "$NC"; fail=$((fail+1))
  else
    printf "%bok%b T3: SOLV-02 fires on a stale manifest row\n" "$GREEN" "$NC"; pass=$((pass+1))
  fi

  # (T4) manifest TRACKED_SET drifts from the script's list -> SOLV-03 must FAIL.
  cat > "$tmp/manifest_badset.tsv" <<MAN
# TRACKED_SET: claimablePool somethingElse
CLASS	IDENTIFIER	FUNCTION	FILE	MODE	RATIONALE
DECL	claimablePool	<file-scope>	Fixture.sol	DECL	fixture decl
VALUE-IN	claimablePool	registeredCredit	Fixture.sol	WRITE	fixture credit
VALUE-OUT	claimablePool	sneakyNewDebit	Fixture.sol	WRITE	fixture debit
MAN
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/manifest_badset.tsv" QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bSELF-TEST FAIL%b T4: gate PASSED though TRACKED_SET drifted (SOLV-03 not enforced)\n" "$RED" "$NC"; fail=$((fail+1))
  else
    printf "%bok%b T4: SOLV-03 fires when the manifest TRACKED_SET drifts from the gate\n" "$GREEN" "$NC"; pass=$((pass+1))
  fi

  echo
  if (( fail == 0 )); then
    printf "%bSELF-TEST PASS%b %d/%d gate behaviours verified\n" "$GREEN" "$NC" "$pass" "$((pass+fail))"
    return 0
  fi
  printf "%bSELF-TEST FAIL%b %d/%d behaviours broken\n" "$RED" "$NC" "$fail" "$((pass+fail))"
  return 1
}

printf "SOLV pool-write drift gate\n"
printf "==========================\n"

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

printf "scanning: %s\n" "$CONTRACTS_DIR"
printf "manifest: %s\n\n" "$MANIFEST_FILE"

if run_gate; then
  echo
  printf "%bPASS%b every counted-term mutation is registered and classified\n" "$GREEN" "$NC"
  exit 0
fi
echo
printf "%bFAIL%b pool-write registry drifted from source — classify new sites in %s (see the manifest header for the enumeration method)\n" \
  "$RED" "$NC" "$MANIFEST_FILE"
exit 1
