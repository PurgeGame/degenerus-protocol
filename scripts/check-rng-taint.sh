#!/usr/bin/env bash
# RNG-word TAINT drift gate (RNGT) — the parameter-flow companion of check-rng-window.sh.
#
# The RNG-window gate tracks the VRF-word STORAGE identifiers by name. A word that leaves
# storage and travels onward as an ARGUMENT — into Coinflip's payout, the jackpot module's
# `word` parameters, the degenerette resolve, the craps engine's `seed` — is invisible to
# identifier matching. This gate closes that blind spot: every function that declares a
# word-shaped parameter (PARAM) and every cross-contract call that passes a word-shaped
# identifier (ARG), as re-derived from source by scripts/lib/rng_taint_extract.py, must be
# registered and classified in scripts/rng-taint-manifest.tsv.
#
# The gate FAILS when:
#   RNGT-01  a live PARAM/ARG site (kind|subject|function|file) is NOT in the manifest — a
#            new/moved parameter-fed consumer to classify (commitment point + frozen inputs).
#   RNGT-02  a manifest row no longer matches any live site — a stale entry to remove.
#   RNGT-03  a row carries an unknown class.
#
# Classes (column 1):
#   CONSUMER-SEALED  derives an outcome from a word that is already committed and whose
#                    selecting inputs are frozen against actors (rationale names the freeze).
#   EXEMPT-ADVANCE   the crank / fulfilment machinery that produces, applies or backfills words.
#   PURE-DERIVE      a pure helper (library or internal) mapping a committed word to a value; no
#                    actor input joins the derivation.
#   PRODUCER         requests or lands a word (VRF coordinator calls, the fulfilment write).
#   GATE             reads a word only to decide readiness / branch, never to derive an outcome.
#   VIEW             off-chain read surface (lens / preview); no state effect.
#   NOT-RNG          a name collision: the parameter is not a VRF value (e.g. a FLIP `seed`
#                    amount, a `wordSeed` fixture argument).
#
# Usage:
#   scripts/check-rng-taint.sh             # gate the real tree
#   scripts/check-rng-taint.sh --self-test # prove the gate catches both drift modes
#
# Env overrides (used by --self-test): CONTRACTS_DIR, MANIFEST_FILE.
# Exit code: 0 if the registry matches source, 1 otherwise.

set -euo pipefail

cd "$(dirname "$0")/.."

CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
MANIFEST_FILE="${MANIFEST_FILE:-scripts/rng-taint-manifest.tsv}"
EXTRACT="scripts/lib/rng_taint_extract.py"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'
KNOWN_CLASSES="CONSUMER-SEALED EXEMPT-ADVANCE PURE-DERIVE PRODUCER GATE VIEW NOT-RNG"

run_gate() {
  [[ -d "$CONTRACTS_DIR" ]] || { printf "ERROR: CONTRACTS_DIR does not exist: %s\n" "$CONTRACTS_DIR" >&2; return 2; }
  [[ -f "$MANIFEST_FILE" ]] || { printf "ERROR: MANIFEST_FILE does not exist: %s\n" "$MANIFEST_FILE" >&2; return 2; }

  local live_keys manifest_keys
  live_keys="$(mktemp)"; manifest_keys="$(mktemp)"

  # Extractor columns: file(1) function(2) kind(3) subject(4) lineno(5) code(6)
  CONTRACTS_DIR="$CONTRACTS_DIR" python3 "$EXTRACT" \
    | awk -F'\t' '{print $3"|"$4"|"$2"|"$1}' | sort -u > "$live_keys"

  # Manifest columns: class(1) kind(2) subject(3) function(4) file(5) rationale(6)
  awk -F'\t' '
    /^#/ {next} /^[[:space:]]*$/ {next}
    $1=="CLASS" {next}
    {print $2"|"$3"|"$4"|"$5}
  ' "$MANIFEST_FILE" | sort -u > "$manifest_keys"

  local fails=0
  local unregistered stale
  unregistered="$(comm -23 "$live_keys" "$manifest_keys" || true)"
  if [[ -n "$unregistered" ]]; then
    while IFS='|' read -r kind subject fn file; do
      [[ -z "$kind" ]] && continue
      printf "%bFAIL%b RNGT-01 unregistered word-carrying site: %s %s in %s (%s)\n" "$RED" "$NC" "$kind" "$subject" "$fn" "$file"
      fails=$((fails+1))
    done <<< "$unregistered"
  fi
  stale="$(comm -13 "$live_keys" "$manifest_keys" || true)"
  if [[ -n "$stale" ]]; then
    while IFS='|' read -r kind subject fn file; do
      [[ -z "$kind" ]] && continue
      printf "%bFAIL%b RNGT-02 stale manifest row (no source match): %s %s in %s (%s)\n" "$RED" "$NC" "$kind" "$subject" "$fn" "$file"
      fails=$((fails+1))
    done <<< "$stale"
  fi

  while IFS=$'\t' read -r cls kind subject fn file rationale; do
    [[ -z "$cls" || "$cls" == \#* || "$cls" == "CLASS" ]] && continue
    case " $KNOWN_CLASSES " in
      *" $cls "*) ;;
      *) printf "%bFAIL%b RNGT-03 unknown class '%s' on %s %s in %s\n" "$RED" "$NC" "$cls" "$kind" "$subject" "$fn"; fails=$((fails+1)) ;;
    esac
  done < "$MANIFEST_FILE"

  if [[ "${QUIET:-0}" != "1" ]]; then
    printf "manifest classes: "
    awk -F'\t' '/^#/||/^[[:space:]]*$/{next} $1=="CLASS"{next} {c[$1]++} END{n=0; for(k in c){printf "%s%s=%d", (n++? ", ":""), k, c[k]}; print ""}' "$MANIFEST_FILE"
    printf "live sites: %d   manifest rows: %d\n" "$(wc -l < "$live_keys")" "$(wc -l < "$manifest_keys")"
  fi
  rm -f "$live_keys" "$manifest_keys"
  return $(( fails > 0 ? 1 : 0 ))
}

self_test() {
  local pass=0 fail=0
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/src"
  cat > "$tmp/src/Fixture.sol" <<'SOL'
pragma solidity ^0.8.26;
interface ISat { function settle(uint256 word, uint24 day) external; }
contract Fixture {
    ISat internal constant sat = ISat(address(1));
    function apply(uint256 rngWord, uint24 day) internal {
        sat.settle(rngWord, day);          // ARG: cross-contract pass
        // sat.settle(rngWord, day);       prose mention must not count
    }
    function pick(uint256 word) internal pure returns (uint256) { return word % 7; }   // PARAM
    function seedProgressive(uint256 seed) external {}                                  // PARAM (NOT-RNG)
}
SOL
  local base="$tmp/manifest.tsv"
  cat > "$base" <<'TSV'
CLASS	kind	subject	function	file	rationale
EXEMPT-ADVANCE	PARAM	rngWord	apply	Fixture.sol	the apply step
EXEMPT-ADVANCE	ARG	sat.settle	apply	Fixture.sol	hands the committed word to the satellite
PURE-DERIVE	PARAM	word	pick	Fixture.sol	pure modulo
NOT-RNG	PARAM	seed	seedProgressive	Fixture.sol	a FLIP amount, not a word
TSV
  if CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$base" QUIET=1 run_gate >/dev/null 2>&1; then
    printf "%bPASS%b self-test 1: matching registry passes\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 1: matching registry should pass\n" "$RED" "$NC"; fail=$((fail+1))
  fi
  grep -v 'pick' "$base" > "$tmp/m2.tsv"
  local out
  out="$(CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/m2.tsv" QUIET=1 run_gate 2>&1 || true)"
  if grep -q 'RNGT-01' <<< "$out"; then
    printf "%bPASS%b self-test 2: unregistered site caught (RNGT-01)\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 2: unregistered site not caught\n" "$RED" "$NC"; fail=$((fail+1))
  fi
  { cat "$base"; printf 'GATE\tPARAM\tword\tgone\tFixture.sol\tstale\n'; } > "$tmp/m3.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/m3.tsv" QUIET=1 run_gate 2>&1 || true)"
  if grep -q 'RNGT-02' <<< "$out"; then
    printf "%bPASS%b self-test 3: stale row caught (RNGT-02)\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 3: stale row not caught\n" "$RED" "$NC"; fail=$((fail+1))
  fi
  sed 's/^PURE-DERIVE/BOGUS/' "$base" > "$tmp/m4.tsv"
  out="$(CONTRACTS_DIR="$tmp/src" MANIFEST_FILE="$tmp/m4.tsv" QUIET=1 run_gate 2>&1 || true)"
  if grep -q 'RNGT-03' <<< "$out"; then
    printf "%bPASS%b self-test 4: unknown class caught (RNGT-03)\n" "$GREEN" "$NC"; pass=$((pass+1))
  else
    printf "%bFAIL%b self-test 4: unknown class not caught\n" "$RED" "$NC"; fail=$((fail+1))
  fi
  printf "self-tests: %d passed, %d failed\n" "$pass" "$fail"
  return $(( fail > 0 ? 1 : 0 ))
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test; exit $?
fi
if run_gate; then
  printf "%bPASS%b RNG-word taint registry matches source\n" "$GREEN" "$NC"; exit 0
else
  printf "%bFAIL%b RNG-word taint registry drift (see above)\n" "$RED" "$NC"; exit 1
fi
