#!/usr/bin/env bash
# RNG-window consumer drift gate.
#
# Enforces that every read/write of a VRF-word storage variable in the contract
# tree is registered and classified in scripts/rng-window-manifest.tsv. The
# manifest is the reviewed source-of-truth for "which sites touch a VRF word and
# why each is safe for the [request -> unlock] freeze window" (the v45 north-star).
#
# The gate FAILS when:
#   RNGW-01  a live source access (identifier|function|file|mode) is NOT in the
#            manifest  — a new/moved VRF-word consumer that must be classified AND
#            checked against RngWindowFreezeHandler's enumerated slot set.
#   RNGW-02  a manifest row no longer matches any live source access — a stale
#            entry to remove (the site was deleted or renamed).
#   RNGW-03  a FROZEN_SET identifier the manifest declares is not referenced by the
#            runtime freeze net (RngWindowFreezeHandler) — the static registry and
#            the runtime enumeration have diverged.
#
# The manifest classification is human judgement; this gate does not re-derive it.
# It guarantees the registry stays in exact correspondence with source, so the
# hand-enumerated runtime freeze net can never silently miss a newly-added consumer.
#
# Usage:
#   scripts/check-rng-window.sh            # gate the real tree (default)
#   scripts/check-rng-window.sh --self-test # prove the gate catches both drift modes
#
# Env overrides (used by --self-test and gate self-checks):
#   CONTRACTS_DIR   source tree to scan          (default: contracts)
#   MANIFEST_FILE   manifest path                 (default: scripts/rng-window-manifest.tsv)
#   HANDLER_FILE    runtime freeze net to cross-check (default: the RngWindowFreezeHandler)
#   SKIP_HANDLER_XCHECK=1  skip RNGW-03 (used by fixture self-tests with no handler)
#
# Exit code: 0 if the registry matches source and the cross-check holds, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
MANIFEST_FILE="${MANIFEST_FILE:-scripts/rng-window-manifest.tsv}"
HANDLER_FILE="${HANDLER_FILE:-test/fuzz/handlers/RngWindowFreezeHandler.sol}"
EXTRACT="scripts/lib/rng_window_extract.py"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

# ---------------------------------------------------------------------------
# Core gate: compare the live access set to the manifest, run the cross-check.
# Prints findings; returns 0 (pass) / 1 (fail). Reads the env vars above.
# ---------------------------------------------------------------------------
run_gate() {
  [[ -d "$CONTRACTS_DIR" ]] || { printf "ERROR: CONTRACTS_DIR does not exist: %s\n" "$CONTRACTS_DIR" >&2; return 2; }
  [[ -f "$MANIFEST_FILE" ]] || { printf "ERROR: MANIFEST_FILE does not exist: %s\n" "$MANIFEST_FILE" >&2; return 2; }

  local live_keys manifest_keys
  live_keys="$(mktemp)"; manifest_keys="$(mktemp)"

  # Live access set -> canonical key: identifier|function|file|mode
  # Extractor columns: file(1) function(2) identifier(3) mode(4) lineno(5) code(6)
  CONTRACTS_DIR="$CONTRACTS_DIR" python3 "$EXTRACT" \
    | awk -F'\t' '{print $3"|"$2"|"$1"|"$4}' | sort -u > "$live_keys"

  # Manifest set -> same key. Skip comment (#) and blank lines and the column header.
  # Manifest columns: class(1) identifier(2) function(3) file(4) mode(5)
  awk -F'\t' '
    /^#/ {next} /^[[:space:]]*$/ {next}
    $1=="CLASS" {next}
    {print $2"|"$3"|"$4"|"$5}
  ' "$MANIFEST_FILE" | sort -u > "$manifest_keys"

  local fails=0

  # RNGW-01: live access absent from manifest.
  local unregistered
  unregistered="$(comm -23 "$live_keys" "$manifest_keys" || true)"
  if [[ -n "$unregistered" ]]; then
    while IFS='|' read -r ident fn file mode; do
      [[ -z "$ident" ]] && continue
      printf "%bFAIL%b RNGW-01 unregistered VRF-word access: %s %s in %s (%s)\n" \
        "$RED" "$NC" "$mode" "$ident" "$fn" "$file"
      fails=$((fails+1))
    done <<< "$unregistered"
  fi

  # RNGW-02: manifest row with no matching live access (stale).
  local stale
  stale="$(comm -13 "$live_keys" "$manifest_keys" || true)"
  if [[ -n "$stale" ]]; then
    while IFS='|' read -r ident fn file mode; do
      [[ -z "$ident" ]] && continue
      printf "%bFAIL%b RNGW-02 stale manifest row (no source match): %s %s in %s (%s)\n" \
        "$RED" "$NC" "$mode" "$ident" "$fn" "$file"
      fails=$((fails+1))
    done <<< "$stale"
  fi

  # RNGW-03: FROZEN_SET identifiers must be referenced by the runtime freeze net.
  if [[ "${SKIP_HANDLER_XCHECK:-0}" != "1" ]]; then
    local frozen_line
    frozen_line="$(grep -E '^# FROZEN_SET:' "$MANIFEST_FILE" | head -1 | sed 's/^# FROZEN_SET:[[:space:]]*//')"
    if [[ -z "$frozen_line" ]]; then
      printf "%bFAIL%b RNGW-03 manifest declares no FROZEN_SET line\n" "$RED" "$NC"
      fails=$((fails+1))
    elif [[ ! -f "$HANDLER_FILE" ]]; then
      printf "%bFAIL%b RNGW-03 runtime freeze net not found: %s\n" "$RED" "$NC" "$HANDLER_FILE"
      fails=$((fails+1))
    else
      local id
      for id in $frozen_line; do
        if ! grep -q "$id" "$HANDLER_FILE"; then
          printf "%bFAIL%b RNGW-03 FROZEN_SET id '%s' not referenced by %s (runtime net does not enumerate it)\n" \
            "$RED" "$NC" "$id" "$HANDLER_FILE"
          fails=$((fails+1))
        fi
      done
    fi
  fi

  # Class-count summary (diagnostic).
  if [[ "${QUIET:-0}" != "1" ]]; then
    printf "manifest classes: "
    awk -F'\t' '/^#/||/^[[:space:]]*$/{next} $1=="CLASS"{next} {c[$1]++} END{n=0; for(k in c){printf "%s%s=%d", (n++? ", ":""), k, c[k]}; print ""}' "$MANIFEST_FILE"
    printf "live accesses: %d   manifest rows: %d\n" "$(wc -l < "$live_keys")" "$(wc -l < "$manifest_keys")"
  fi

  rm -f "$live_keys" "$manifest_keys"
  return $(( fails > 0 ? 1 : 0 ))
}

# ---------------------------------------------------------------------------
# Self-test: build throwaway fixtures and prove the gate catches both drift
# modes and the cross-check. No real files are touched.
# ---------------------------------------------------------------------------
self_test() {
  local pass=0 fail=0
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # Fixture contract: one registered read + one UNregistered read of a tracked var.
  mkdir -p "$tmp/src"
  cat > "$tmp/src/Fixture.sol" <<'SOL'
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
contract Fixture {
    mapping(uint24 => uint256) internal rngWordByDay;
    function registeredConsumer(uint24 d) external view returns (uint256) {
        return rngWordByDay[d];
    }
    function sneakyNewConsumer(uint24 d) external view returns (uint256) {
        return rngWordByDay[d] + 1;
    }
}
SOL

  # (T1) manifest registers only ONE of the two reads -> RNGW-01 must FAIL.
  cat > "$tmp/manifest_missing.tsv" <<'MAN'
# FROZEN_SET: rngWordByDay
CLASS	IDENTIFIER	FUNCTION	FILE	MODE
DECL	rngWordByDay	<file-scope>	Fixture.sol	DECL
CONSUMER-SEALED	rngWordByDay	registeredConsumer	Fixture.sol	READ
MAN
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/manifest_missing.tsv" SKIP_HANDLER_XCHECK=1 QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bSELF-TEST FAIL%b T1: gate PASSED with an unregistered access (RNGW-01 not enforced)\n" "$RED" "$NC"; fail=$((fail+1))
  else
    printf "%bok%b T1: RNGW-01 fires on an unregistered VRF-word read\n" "$GREEN" "$NC"; pass=$((pass+1))
  fi

  # (T2) manifest registers BOTH reads -> gate must PASS.
  cat > "$tmp/manifest_full.tsv" <<'MAN'
# FROZEN_SET: rngWordByDay
CLASS	IDENTIFIER	FUNCTION	FILE	MODE
DECL	rngWordByDay	<file-scope>	Fixture.sol	DECL
CONSUMER-SEALED	rngWordByDay	registeredConsumer	Fixture.sol	READ
CONSUMER-SEALED	rngWordByDay	sneakyNewConsumer	Fixture.sol	READ
MAN
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/manifest_full.tsv" SKIP_HANDLER_XCHECK=1 QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bok%b T2: gate passes when every access is registered\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bSELF-TEST FAIL%b T2: gate FAILED on a fully-registered fixture (false positive)\n" "$RED" "$NC"; fail=$((fail+1))
  fi

  # (T3) manifest has an extra row with no source match -> RNGW-02 must FAIL.
  cat > "$tmp/manifest_stale.tsv" <<'MAN'
# FROZEN_SET: rngWordByDay
CLASS	IDENTIFIER	FUNCTION	FILE	MODE
DECL	rngWordByDay	<file-scope>	Fixture.sol	DECL
CONSUMER-SEALED	rngWordByDay	registeredConsumer	Fixture.sol	READ
CONSUMER-SEALED	rngWordByDay	sneakyNewConsumer	Fixture.sol	READ
CONSUMER-SEALED	rngWordByDay	deletedConsumer	Fixture.sol	READ
MAN
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/manifest_stale.tsv" SKIP_HANDLER_XCHECK=1 QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bSELF-TEST FAIL%b T3: gate PASSED with a stale manifest row (RNGW-02 not enforced)\n" "$RED" "$NC"; fail=$((fail+1))
  else
    printf "%bok%b T3: RNGW-02 fires on a stale manifest row\n" "$GREEN" "$NC"; pass=$((pass+1))
  fi

  # (T4) FROZEN_SET id not referenced by a stub handler -> RNGW-03 must FAIL.
  printf 'contract H { uint256 unrelated; }\n' > "$tmp/StubHandler.sol"
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/manifest_full.tsv" HANDLER_FILE="$tmp/StubHandler.sol" QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bSELF-TEST FAIL%b T4: gate PASSED though the handler omits a FROZEN_SET id (RNGW-03 not enforced)\n" "$RED" "$NC"; fail=$((fail+1))
  else
    printf "%bok%b T4: RNGW-03 fires when the runtime net omits a FROZEN_SET id\n" "$GREEN" "$NC"; pass=$((pass+1))
  fi

  echo
  if (( fail == 0 )); then
    printf "%bSELF-TEST PASS%b %d/%d gate behaviours verified\n" "$GREEN" "$NC" "$pass" "$((pass+fail))"
    return 0
  fi
  printf "%bSELF-TEST FAIL%b %d/%d behaviours broken\n" "$RED" "$NC" "$fail" "$((pass+fail))"
  return 1
}

printf "RNG-window consumer drift gate\n"
printf "==============================\n"

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

printf "scanning: %s\n" "$CONTRACTS_DIR"
printf "manifest: %s\n\n" "$MANIFEST_FILE"

if run_gate; then
  echo
  printf "%bPASS%b every VRF-word access is registered; runtime freeze net enumerates the FROZEN_SET\n" "$GREEN" "$NC"
  exit 0
fi
echo
printf "%bFAIL%b VRF-word access registry drifted from source — classify new sites in %s and confirm RngWindowFreezeHandler covers them\n" \
  "$RED" "$NC" "$MANIFEST_FILE"
exit 1
