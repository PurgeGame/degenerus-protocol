#!/usr/bin/env bash
# v68.0 mutation campaign — the RNG/payout TAIL never scored across v63/v64/v66/v67.
#
# Targets the three modules that hosted every prior real finding and have NO measured
# kill-rate: Coinflip (post-rename of BurnieCoinflip), DegenerusGameLootboxModule,
# DegenerusGameDecimatorModule. Driven against the COMPREHENSIVE oracle
# (oracle-comprehensive.sh — the union of the EXERCISED green-baseline suites, with the
# v65 rename corrected: BurnieEmissionSeeds -> FlipEmissionSeeds).
#
# Measures whether the regression net CATCHES injected defects in the highest-value
# RNG/payout functions. A survivor under THIS oracle is either a genuine test-coverage
# hole (close it with a MutationKills regression — MUT-03) or an equivalent mutant.
# COMPILATION-FAILURE mutants are invalid (cannot compile) and are counted separately,
# excluded from the kill-rate denominator — they never abort the run (the mutate call is
# `|| true` and the script does not `set -e`).
#
# KILL-SAFE: an EXIT/INT/TERM trap restores contracts/ (git checkout) so a crash/kill
#   never strands a mutant. RESUMABLE: per-target <name>.v68.DONE checkpoints. The runner
#   NEVER commits; it asserts the subject byte-freeze before AND after every target.
#
# Usage:
#   run-campaign-v68.sh                          # full tail campaign, resumable
#   run-campaign-v68.sh --single <ContractName>  # run/resume ONE target (paced background)
set -uo pipefail

REPO=/home/zak/Dev/PurgeGame/degenerus-audit
cd "$REPO"
OUT="$REPO/audit/mutation"
mkdir -p "$OUT"
PROG="$OUT/PROGRESS-v68.log"
ORACLE="$OUT/oracle-comprehensive.sh"

# ----- Subject pin (the v68 byte-freeze the campaign must never violate) -----
SUBJECT_SHA="65b70821"
SUBJECT_TREE="2494153f206f5aaedd2873e3dcc0d65ad1000336"
SRC="contracts"

# ----- Kill-safe restore trap -----
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

# ----- Bounded per-mutant oracle (survivors re-verified at full runs in triage) -----
export FOUNDRY_FUZZ_RUNS=64 FOUNDRY_INVARIANT_RUNS=12 FOUNDRY_INVARIANT_DEPTH=48

echo "campaign-v68 START $(date -u +%FT%TZ) HEAD=$(git rev-parse --short HEAD) subject=$SUBJECT_SHA" >> "$PROG"

# run_target <ContractName> <relative-source-path>
run_target() {
  local name="$1" relpath="$2"
  if [ -f "$OUT/$name.v68.DONE" ]; then
    echo "$name SKIP(done) $(date -u +%FT%TZ)" >> "$PROG"
    return 0
  fi
  assert_frozen "before $name"

  # Baseline-green gate: never mutate against a red oracle (a red baseline would
  # make every mutant "killed" spuriously — the inverse false signal). Here-strings,
  # not `echo | grep -q`, to avoid SIGPIPE tripping pipefail on a green oracle.
  echo "$name BASELINE_CHECK $(date -u +%FT%TZ)" >> "$PROG"
  local out
  out=$(bash "$ORACLE" 2>&1)
  if grep -qE 'No tests to run' <<<"$out" || ! grep -qE 'Suite result: ok' <<<"$out"; then
    echo "$name BASELINE_BAD(no-tests-or-red) abort-target $(date -u +%FT%TZ)" >> "$PROG"
    echo "$out" | grep -E 'Suite result|No tests|FAIL' | tail -8 >> "$PROG"
    return 1
  fi

  local t0 t1 unc kil cf
  t0=$(date +%s)
  echo "$name MUTATE_START $(date -u +%FT%TZ) src=$relpath" >> "$PROG"
  slither-mutate "$REPO/$relpath" \
    --contract-names "$name" \
    --test-cmd "$ORACLE" \
    --timeout 600 \
    --output-dir "$OUT/$name-mut-v68" \
    -v > "$OUT/$name-v68.log" 2>&1 || true
  restore
  assert_frozen "after $name"
  t1=$(date +%s)
  unc=$(grep -ciE 'UNCAUGHT' "$OUT/$name-v68.log" 2>/dev/null || true)
  kil=$(grep -ciE 'CAUGHT' "$OUT/$name-v68.log" 2>/dev/null || true)
  cf=$(grep -ciE 'COMPILATION FAILURE' "$OUT/$name-v68.log" 2>/dev/null || true)
  echo "$name DONE killed=$kil uncaught=$unc compfail=$cf elapsed=$((t1-t0))s $(date -u +%FT%TZ)" >> "$PROG"
  touch "$OUT/$name.v68.DONE"
  return 0
}

# RNG/payout tail (ContractName, relative source path). Smallest first so results land
# early and a 5h cap never strands the whole campaign. Decimator (49KB) < Coinflip (57KB)
# < Lootbox (122KB).
declare -a TARGETS=(
  "DegenerusGameDecimatorModule|$SRC/modules/DegenerusGameDecimatorModule.sol"
  "Coinflip|$SRC/Coinflip.sol"
  "DegenerusGameLootboxModule|$SRC/modules/DegenerusGameLootboxModule.sol"
)

# ----- argv: --single <ContractName> runs/resumes exactly one target -----
if [ "${1:-}" = "--single" ]; then
  want="${2:-}"
  if [ -z "$want" ]; then echo "usage: $0 --single <ContractName>" >&2; exit 2; fi
  for entry in "${TARGETS[@]}"; do
    name="${entry%%|*}"; relpath="${entry#*|}"
    if [ "$name" = "$want" ]; then
      run_target "$name" "$relpath"
      echo "campaign-v68 SINGLE-END $name $(date -u +%FT%TZ)" >> "$PROG"
      exit 0
    fi
  done
  echo "FATAL: unknown target '$want' (known: ${TARGETS[*]%%|*})" >&2
  exit 2
fi

# ----- full tail campaign (resumable; re-running after a kill resumes at first non-.DONE) -----
for entry in "${TARGETS[@]}"; do
  name="${entry%%|*}"; relpath="${entry#*|}"
  run_target "$name" "$relpath"
done

echo "campaign-v68 END $(date -u +%FT%TZ)" >> "$PROG"
