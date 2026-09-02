#!/usr/bin/env bash
# Advance-chain external-call drift gate (ADVX).
#
# The daily crank (`advanceGame`) is the one transaction the game cannot live without: a
# revert or an over-cap tx on any path it reaches stops the protocol for good. Every
# external call on those paths is therefore either wrapped in try/catch or made bare on
# the argument that the callee cannot revert. This gate keeps that argument from going
# stale: every external call site in the crank's file set (scripts/lib/external_call_extract.py)
# must be registered and classified in scripts/advance-call-manifest.tsv, and every bare
# crank-reachable call must name the test that pins its callee's revert-freedom.
#
# The gate FAILS when:
#   ADVX-01  a live call site (callee|function|file|mode) is NOT in the manifest — a
#            new/moved external call that must be classified for crank reachability.
#   ADVX-02  a manifest row no longer matches any live call site — a stale entry.
#   ADVX-03  a CRANK-PINNED row's pin is missing: the pin column is empty, a named test
#            file does not exist, or the file never mentions the callee function — the
#            revert-freedom argument has no test behind it.
#   ADVX-04  a row is classified CRANK-UNPINNED — a bare crank call with no pin yet. The
#            class exists so the manifest can record the gap honestly; the gate refuses it.
#
# Classes (column 1):
#   CRANK-PINNED   bare call on a crank-reachable path; `pin` names the test(s) that drive
#                  the callee under adversarial state (semicolon-separated paths).
#   CRANK-TRY      call on a crank-reachable path wrapped in try/catch (fail-soft by design).
#   CRANK-SELF     delegatecall/self-call into the game's own module code on the crank; the
#                  callee is own storage, bubbled on purpose, bounded by the advance gas suites.
#   CRANK-CAUGHT   bare at the site, but every crank path to it crosses an upstream try/catch
#                  (the rationale names the catching site); a revert there is fail-soft.
#   CRANK-POLICY   bare crank call whose revert is an INTENTIONAL, documented halt (e.g. the
#                  daily VRF request when Chainlink refuses — KNOWN-ISSUES §1); the rationale
#                  must cite the document. Accepted, never silently.
#   OFF-CRANK      the enclosing function is not reachable from advanceGame, the VRF
#                  fulfilment, or the keeper router (player, owner or view entry points).
#   CRANK-UNPINNED bare crank call whose callee has no revert-freedom pin (refused, ADVX-04).
#
# The classification is human judgement; this gate does not re-derive reachability. It
# guarantees the registry stays in exact correspondence with source and that every bare
# crank call is backed by a named test.
#
# Usage:
#   scripts/check-advance-calls.sh             # gate the real tree
#   scripts/check-advance-calls.sh --self-test # prove the gate catches every failure mode
#
# Env overrides (used by --self-test):
#   CONTRACTS_DIR   source tree to scan            (default: contracts)
#   MANIFEST_FILE   manifest path                   (default: scripts/advance-call-manifest.tsv)
#   SCOPE_FILES     comma-separated scope override  (default: the extractor's crank set)
#   TEST_ROOT       where pin paths resolve         (default: repo root)
#
# Exit code: 0 if the registry matches source and every pin resolves, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
MANIFEST_FILE="${MANIFEST_FILE:-scripts/advance-call-manifest.tsv}"
TEST_ROOT="${TEST_ROOT:-.}"
EXTRACT="scripts/lib/external_call_extract.py"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

run_gate() {
  [[ -d "$CONTRACTS_DIR" ]] || { printf "ERROR: CONTRACTS_DIR does not exist: %s\n" "$CONTRACTS_DIR" >&2; return 2; }
  [[ -f "$MANIFEST_FILE" ]] || { printf "ERROR: MANIFEST_FILE does not exist: %s\n" "$MANIFEST_FILE" >&2; return 2; }

  local live_keys manifest_keys
  live_keys="$(mktemp)"; manifest_keys="$(mktemp)"

  # Live call set -> canonical key: callee|function|file|mode
  # Extractor columns: file(1) function(2) callee(3) mode(4) lineno(5) code(6)
  CONTRACTS_DIR="$CONTRACTS_DIR" SCOPE_FILES="${SCOPE_FILES:-}" python3 "$EXTRACT" \
    | awk -F'\t' '{print $3"|"$2"|"$1"|"$4}' | sort -u > "$live_keys"

  # Manifest columns: class(1) callee(2) function(3) file(4) mode(5) pin(6) rationale(7)
  awk -F'\t' '
    /^#/ {next} /^[[:space:]]*$/ {next}
    $1=="CLASS" {next}
    {print $2"|"$3"|"$4"|"$5}
  ' "$MANIFEST_FILE" | sort -u > "$manifest_keys"

  local fails=0

  local unregistered
  unregistered="$(comm -23 "$live_keys" "$manifest_keys" || true)"
  if [[ -n "$unregistered" ]]; then
    while IFS='|' read -r callee fn file mode; do
      [[ -z "$callee" ]] && continue
      printf "%bFAIL%b ADVX-01 unregistered external call: %s %s in %s (%s)\n" \
        "$RED" "$NC" "$mode" "$callee" "$fn" "$file"
      fails=$((fails+1))
    done <<< "$unregistered"
  fi

  local stale
  stale="$(comm -13 "$live_keys" "$manifest_keys" || true)"
  if [[ -n "$stale" ]]; then
    while IFS='|' read -r callee fn file mode; do
      [[ -z "$callee" ]] && continue
      printf "%bFAIL%b ADVX-02 stale manifest row (no source match): %s %s in %s (%s)\n" \
        "$RED" "$NC" "$mode" "$callee" "$fn" "$file"
      fails=$((fails+1))
    done <<< "$stale"
  fi

  # ADVX-03 / ADVX-04: pin resolution for bare crank calls. Tabs are whitespace to `read`, so
  # consecutive tabs (an empty pin cell) would collapse and shift the rationale into `pin`;
  # the row is re-delimited with a unit separator first so empty cells survive.
  while IFS=$'\037' read -r cls callee fn file mode pin rationale; do
    [[ -z "$cls" || "$cls" == \#* || "$cls" == "CLASS" ]] && continue
    case "$cls" in
      CRANK-UNPINNED)
        printf "%bFAIL%b ADVX-04 bare crank call without a revert-freedom pin: %s in %s (%s)\n" \
          "$RED" "$NC" "$callee" "$fn" "$file"
        fails=$((fails+1))
        ;;
      CRANK-PINNED)
        if [[ -z "${pin:-}" ]]; then
          printf "%bFAIL%b ADVX-03 CRANK-PINNED row has an empty pin: %s in %s (%s)\n" \
            "$RED" "$NC" "$callee" "$fn" "$file"
          fails=$((fails+1))
          continue
        fi
        # The needle a pin must mention: the callee's function name (last dotted component,
        # delegatecall:Iface.fn -> fn). A raw low-level or yul call has no callee name, so the
        # ENCLOSING function is the needle instead (the pin drives that function).
        local fname
        if [[ "$callee" == *.* ]]; then fname="${callee##*.}"; else fname="$fn"; fi
        local p
        IFS=';' read -ra pins <<< "$pin"
        for p in "${pins[@]}"; do
          p="${p## }"; p="${p%% }"
          [[ -z "$p" ]] && continue
          if [[ ! -f "$TEST_ROOT/$p" ]]; then
            printf "%bFAIL%b ADVX-03 pin file not found for %s in %s: %s\n" "$RED" "$NC" "$callee" "$fn" "$p"
            fails=$((fails+1))
          elif ! grep -q -- "$fname" "$TEST_ROOT/$p"; then
            printf "%bFAIL%b ADVX-03 pin %s never mentions callee function '%s' (%s in %s)\n" \
              "$RED" "$NC" "$p" "$fname" "$callee" "$fn"
            fails=$((fails+1))
          fi
        done
        ;;
      CRANK-POLICY)
        if [[ -z "${rationale:-}" ]]; then
          printf "%bFAIL%b ADVX-03 CRANK-POLICY row must cite its document in the rationale: %s in %s\n" "$RED" "$NC" "$callee" "$fn"
          fails=$((fails+1))
        fi
        ;;
      CRANK-CAUGHT)
        if [[ -z "${rationale:-}" ]]; then
          printf "%bFAIL%b ADVX-03 CRANK-CAUGHT row must name the catching site in the rationale: %s in %s\n" "$RED" "$NC" "$callee" "$fn"
          fails=$((fails+1))
        fi
        ;;
      CRANK-TRY|CRANK-SELF|OFF-CRANK) ;;
      *)
        printf "%bFAIL%b ADVX-01 unknown class '%s' on row %s in %s\n" "$RED" "$NC" "$cls" "$callee" "$fn"
        fails=$((fails+1))
        ;;
    esac
  done < <(tr '\t' '\037' < "$MANIFEST_FILE")

  if [[ "${QUIET:-0}" != "1" ]]; then
    printf "manifest classes: "
    awk -F'\t' '/^#/||/^[[:space:]]*$/{next} $1=="CLASS"{next} {c[$1]++} END{n=0; for(k in c){printf "%s%s=%d", (n++? ", ":""), k, c[k]}; print ""}' "$MANIFEST_FILE"
    printf "live call sites: %d   manifest rows: %d\n" "$(wc -l < "$live_keys")" "$(wc -l < "$manifest_keys")"
  fi

  rm -f "$live_keys" "$manifest_keys"
  return $(( fails > 0 ? 1 : 0 ))
}

self_test() {
  local pass=0 fail=0
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/src" "$tmp/test"
  cat > "$tmp/src/Fixture.sol" <<'SOL'
pragma solidity ^0.8.26;
interface IThing { function ping() external; function pong() external view returns (uint256); }
contract Fixture {
    IThing internal constant thing = IThing(address(1));
    function advanceGame() external {
        thing.ping();                       // bare crank call
        try thing.pong() returns (uint256) {} catch {}   // wrapped crank call
        // IThing(address(2)).pong(); prose mention must not count
    }
    function playerDoor() external view returns (uint256) {
        return IThing(address(3)).pong();   // off-crank
    }
}
SOL
  printf 'contract PinTest { function test_pingNeverReverts() public {} }\n' > "$tmp/test/Pin.t.sol"

  local base_manifest="$tmp/manifest.tsv"
  cat > "$base_manifest" <<'TSV'
CLASS	callee	function	file	mode	pin	rationale
CRANK-PINNED	IThing.ping	advanceGame	Fixture.sol	BARE	test/Pin.t.sol	callee is revert-free past its gate
CRANK-TRY	IThing.pong	advanceGame	Fixture.sol	TRY		fail-soft by design
OFF-CRANK	IThing.pong	playerDoor	Fixture.sol	BARE		player view, not on the crank
TSV

  # Case 1: exact correspondence + resolving pin -> PASS.
  if CONTRACTS_DIR="$tmp/src" SCOPE_FILES="Fixture.sol" MANIFEST_FILE="$base_manifest" TEST_ROOT="$tmp" QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bPASS%b self-test 1: matching registry passes\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 1: matching registry should pass\n" "$RED" "$NC"; fail=$((fail+1))
  fi

  # Case 2: unregistered call (ADVX-01).
  grep -v 'playerDoor' "$base_manifest" > "$tmp/m2.tsv"
  local out
  out="$(CONTRACTS_DIR="$tmp/src" SCOPE_FILES="Fixture.sol" MANIFEST_FILE="$tmp/m2.tsv" TEST_ROOT="$tmp" QUIET=1 run_gate 2>&1 || true)"
  if grep -q 'ADVX-01' <<< "$out"; then
    printf "%bPASS%b self-test 2: unregistered call caught (ADVX-01)\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 2: unregistered call not caught\n" "$RED" "$NC"; fail=$((fail+1))
  fi

  # Case 3: stale row (ADVX-02).
  { cat "$base_manifest"; printf 'OFF-CRANK\tIThing.gone\tplayerDoor\tFixture.sol\tBARE\t\tstale\n'; } > "$tmp/m3.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" SCOPE_FILES="Fixture.sol" MANIFEST_FILE="$tmp/m3.tsv" TEST_ROOT="$tmp" QUIET=1 run_gate 2>&1 || true)"
  if grep -q 'ADVX-02' <<< "$out"; then
    printf "%bPASS%b self-test 3: stale row caught (ADVX-02)\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 3: stale row not caught\n" "$RED" "$NC"; fail=$((fail+1))
  fi

  # Case 4: pin names a file that never mentions the callee (ADVX-03).
  printf 'contract Other { function test_nothing() public {} }\n' > "$tmp/test/Other.t.sol"
  sed 's#test/Pin.t.sol#test/Other.t.sol#' "$base_manifest" > "$tmp/m4.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" SCOPE_FILES="Fixture.sol" MANIFEST_FILE="$tmp/m4.tsv" TEST_ROOT="$tmp" QUIET=1 run_gate 2>&1 || true)"
  if grep -q 'ADVX-03' <<< "$out"; then
    printf "%bPASS%b self-test 4: pin without the callee caught (ADVX-03)\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 4: unresolving pin not caught\n" "$RED" "$NC"; fail=$((fail+1))
  fi

  # Case 5: CRANK-UNPINNED refused (ADVX-04).
  sed 's#^CRANK-PINNED\(.*\)test/Pin.t.sol#CRANK-UNPINNED\1#' "$base_manifest" > "$tmp/m5.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" SCOPE_FILES="Fixture.sol" MANIFEST_FILE="$tmp/m5.tsv" TEST_ROOT="$tmp" QUIET=1 run_gate 2>&1 || true)"
  if grep -q 'ADVX-04' <<< "$out"; then
    printf "%bPASS%b self-test 5: unpinned crank call refused (ADVX-04)\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 5: unpinned crank call not refused\n" "$RED" "$NC"; fail=$((fail+1))
  fi

  # Case 6: an empty pin cell must not swallow the rationale (CRANK-CAUGHT with rationale passes,
  # without it fails ADVX-03).
  { cat "$base_manifest"; printf 'CRANK-CAUGHT\tIThing.pong\tplayerDoor\tFixture.sol\tBARE\t\tcaught by the router try\n'; } | grep -v $'^OFF-CRANK\tIThing.pong' > "$tmp/m6.tsv"
  if CONTRACTS_DIR="$tmp/src" SCOPE_FILES="Fixture.sol" MANIFEST_FILE="$tmp/m6.tsv" TEST_ROOT="$tmp" QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bPASS%b self-test 6a: empty pin cell keeps the rationale column\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 6a: empty pin cell shifted the columns\n" "$RED" "$NC"; fail=$((fail+1))
  fi
  sed 's#caught by the router try##' "$tmp/m6.tsv" > "$tmp/m6b.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" SCOPE_FILES="Fixture.sol" MANIFEST_FILE="$tmp/m6b.tsv" TEST_ROOT="$tmp" QUIET=1 run_gate 2>&1 || true)"
  if grep -q 'ADVX-03 CRANK-CAUGHT' <<< "$out"; then
    printf "%bPASS%b self-test 6b: CRANK-CAUGHT without a rationale refused\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 6b: CRANK-CAUGHT without a rationale accepted\n" "$RED" "$NC"; fail=$((fail+1))
  fi

  printf "self-tests: %d passed, %d failed\n" "$pass" "$fail"
  return $(( fail > 0 ? 1 : 0 ))
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

if run_gate; then
  printf "%bPASS%b advance-chain external-call registry matches source; every bare crank call is pinned\n" "$GREEN" "$NC"
  exit 0
else
  printf "%bFAIL%b advance-chain external-call registry drift (see above)\n" "$RED" "$NC"
  exit 1
fi
