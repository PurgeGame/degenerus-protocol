#!/usr/bin/env bash
# Corrected mutation campaign for the v64 frozen subject 891f7a8f.
#
# Fix-site/spine-scoped (TARGETS-v64.md), driven against the COMPREHENSIVE oracle
# (oracle-comprehensive.sh — the union of the 388-02 EXERCISED green-baseline tests),
# NOT the prior narrow per-file --match-contract oracle that produced false survivors.
#
# Measures whether the regression net CATCHES injected defects in the highest-value
# functions, with no false survivors caused by an oracle that skips the mutated code.
#
# KILL-SAFE: an EXIT/INT/TERM trap restores contracts/ (git checkout) so a crash/kill
#   never strands a mutant. RESUMABLE: per-target <name>.DONE checkpoints. The runner
#   NEVER commits; it asserts the subject byte-freeze before AND after every target.
#
# Usage:
#   run-campaign-v64.sh                       # full campaign, fix-site order, resumable
#   run-campaign-v64.sh --single <ContractName>  # run/resume ONE target (paced background)
set -uo pipefail

REPO=/home/zak/Dev/PurgeGame/degenerus-audit
cd "$REPO"
OUT="$REPO/audit/mutation"
mkdir -p "$OUT"
PROG="$OUT/PROGRESS-v64.log"
ORACLE="$OUT/oracle-comprehensive.sh"

# ----- Subject pin (the byte-freeze the campaign must never violate) -----
SUBJECT_SHA="891f7a8f"
SUBJECT_TREE="402855e171168ff4f653eb1434de4ff045a4e28f"
SRC="contracts"

# ----- Kill-safe restore trap (mirror run-campaign.sh:12-13) -----
# Restores the byte-frozen source so a crash/kill never strands a mutant.
restore() { cd "$REPO" && git checkout -- contracts/ 2>/dev/null || true; }
trap 'restore; echo "campaign TRAP_EXIT $(date -u +%FT%TZ)" >> "'"$PROG"'"' EXIT INT TERM

# ----- Assert the frozen subject before ANY mutation -----
assert_frozen() {
  local where="$1" tree diff
  tree=$(git rev-parse "HEAD:$SRC" 2>/dev/null || echo "NONE")
  if [ "$tree" != "$SUBJECT_TREE" ]; then
    echo "FATAL ($where): source tree-hash $tree != pinned $SUBJECT_TREE" | tee -a "$PROG" >&2
    exit 1
  fi
  diff=$(git diff "$SUBJECT_SHA" -- "$SRC/" 2>/dev/null)
  if [ -n "$diff" ]; then
    echo "FATAL ($where): git diff $SUBJECT_SHA -- $SRC/ is NON-EMPTY (mutant stranded?)" | tee -a "$PROG" >&2
    exit 1
  fi
}
assert_frozen "startup"

# ----- Bounded per-mutant oracle (survivors re-verified at full runs in Plan 02) -----
export FOUNDRY_FUZZ_RUNS=64 FOUNDRY_INVARIANT_RUNS=12 FOUNDRY_INVARIANT_DEPTH=48

echo "campaign-v64 START $(date -u +%FT%TZ) HEAD=$(git rev-parse --short HEAD) subject=$SUBJECT_SHA" >> "$PROG"

# run_target <ContractName> <relative-source-path>
run_target() {
  local name="$1" relpath="$2"
  if [ -f "$OUT/$name.DONE" ]; then
    echo "$name SKIP(done) $(date -u +%FT%TZ)" >> "$PROG"
    return 0
  fi
  assert_frozen "before $name"

  # Baseline-green gate: never mutate against a red oracle (a red baseline would
  # make every mutant "killed" spuriously — the inverse false signal).
  echo "$name BASELINE_CHECK $(date -u +%FT%TZ)" >> "$PROG"
  local out
  out=$(bash "$ORACLE" 2>&1)
  # Here-strings (not `echo | grep -q`): grep -q exits on first match and closes the
  # pipe; under `pipefail` echo then takes SIGPIPE (141) and the pipeline reports
  # failure even though the oracle was green, falsely tripping the baseline gate.
  if grep -qE 'No tests to run' <<<"$out" || ! grep -qE 'Suite result: ok' <<<"$out"; then
    echo "$name BASELINE_BAD(no-tests-or-red) abort-target $(date -u +%FT%TZ)" >> "$PROG"
    echo "$out" | grep -E 'Suite result|No tests|FAIL' | tail -8 >> "$PROG"
    return 1
  fi

  local t0 t1 unc kil
  t0=$(date +%s)
  echo "$name MUTATE_START $(date -u +%FT%TZ) src=$relpath" >> "$PROG"
  slither-mutate "$REPO/$relpath" \
    --contract-names "$name" \
    --test-cmd "$ORACLE" `# ORACLE=oracle-comprehensive.sh (the comprehensive union)` \
    --timeout 600 \
    --output-dir "$OUT/$name-mut-v64" \
    -v > "$OUT/$name-v64.log" 2>&1 || true
  restore
  assert_frozen "after $name"
  t1=$(date +%s)
  unc=$(grep -ciE 'UNCAUGHT' "$OUT/$name-v64.log" 2>/dev/null || true)
  kil=$(grep -ciE 'CAUGHT' "$OUT/$name-v64.log" 2>/dev/null || true)
  echo "$name DONE killed=$kil uncaught=$unc elapsed=$((t1-t0))s $(date -u +%FT%TZ)" >> "$PROG"
  touch "$OUT/$name.DONE"
  return 0
}

# Fix-site target list (ContractName, relative source path). Smallest / highest-signal
# first so results land early and a 5h cap never strands the whole campaign.
declare -a TARGETS=(
  "BitPackingLib|$SRC/libraries/BitPackingLib.sol"
  "DegenerusGameStorage|$SRC/storage/DegenerusGameStorage.sol"
  "StakedDegenerusStonk|$SRC/StakedDegenerusStonk.sol"
  "BurnieCoinflip|$SRC/BurnieCoinflip.sol"
  "DegenerusGameLootboxModule|$SRC/modules/DegenerusGameLootboxModule.sol"
  "DegenerusGameDecimatorModule|$SRC/modules/DegenerusGameDecimatorModule.sol"
)

# ----- argv: --single <ContractName> runs/resumes exactly one target -----
if [ "${1:-}" = "--single" ]; then
  want="${2:-}"
  if [ -z "$want" ]; then echo "usage: $0 --single <ContractName>" >&2; exit 2; fi
  for entry in "${TARGETS[@]}"; do
    name="${entry%%|*}"; relpath="${entry#*|}"
    if [ "$name" = "$want" ]; then
      run_target "$name" "$relpath"
      echo "campaign-v64 SINGLE-END $name $(date -u +%FT%TZ)" >> "$PROG"
      exit 0
    fi
  done
  echo "FATAL: unknown target '$want' (known: ${TARGETS[*]%%|*})" >&2
  exit 2
fi

# ----- full campaign (resumable; re-running after a kill resumes at the first non-.DONE) -----
for entry in "${TARGETS[@]}"; do
  name="${entry%%|*}"; relpath="${entry#*|}"
  run_target "$name" "$relpath"
done

echo "campaign-v64 END $(date -u +%FT%TZ)" >> "$PROG"
