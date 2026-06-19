#!/usr/bin/env bash
# Bytecode-equivalence proof for the v68.0 phase-433 comment trim.
# Precondition: the trim is APPLIED in the working tree (14 contracts dirty).
# Builds trimmed (working tree) vs clean HEAD with metadata hash stripped
# (FOUNDRY_BYTECODE_HASH=none) and diffs deployedBytecode for every artifact.
# Identical deployedBytecode across all artifacts => the trim is logic-inert.
set -euo pipefail
cd /home/zak/Dev/PurgeGame/degenerus-audit
export FOUNDRY_BYTECODE_HASH=none FOUNDRY_DISABLE_NIGHTLY_WARNING=1

STASHED=0
restore() {
  if [ "$STASHED" = "1" ]; then
    echo "=== restoring trim (stash pop) ==="
    git stash pop >/dev/null 2>&1 || echo "!! stash pop failed — recover by hand: git stash list"
  fi
}
trap restore EXIT

snapshot() {
  local dest="/tmp/bc-proof/$1"; rm -rf "$dest"; mkdir -p "$dest"
  python3 - "$dest" <<'PY'
import json, os, sys
dest = sys.argv[1]; root = "forge-out"
for dp, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".json"): continue
        try: data = json.load(open(os.path.join(dp, f)))
        except Exception: continue
        obj = (data.get("deployedBytecode") or {}).get("object")
        if not obj: continue
        key = os.path.relpath(os.path.join(dp, f), root).replace("/", "__")
        open(os.path.join(dest, key), "w").write(obj)
PY
}

echo "=== [1/4] precondition: trim applied in working tree ==="
if git diff --quiet -- contracts; then
  echo "!! no contract changes in working tree; expected trim applied. abort."; exit 1
fi
git diff --stat -- contracts | tail -1

echo "=== [2/4] build TRIMMED (working tree) ==="
forge build >/dev/null
snapshot trim

echo "=== [3/4] stash trim -> build clean HEAD ==="
git stash push -m "v68-433-trim-proof" -- contracts >/dev/null
STASHED=1
forge build >/dev/null
snapshot head

echo "=== [4/4] diff deployedBytecode across all artifacts ==="
python3 - <<'PY'
import os, sys
h="/tmp/bc-proof/head"; t="/tmp/bc-proof/trim"
hk=set(os.listdir(h)); tk=set(os.listdir(t))
diffs=[k for k in sorted(hk&tk) if open(os.path.join(h,k)).read()!=open(os.path.join(t,k)).read()]
print(f"artifacts head={len(hk)} trim={len(tk)} common={len(hk&tk)}")
if hk-tk: print("ONLY IN HEAD:", sorted(hk-tk))
if tk-hk: print("ONLY IN TRIM:", sorted(tk-hk))
if diffs:
    print("!! DEPLOYEDBYTECODE DIFFERS in", len(diffs), "artifact(s):")
    for d in diffs: print("   -", d)
    sys.exit(3)
print("✅ BYTECODE IDENTICAL across all", len(hk&tk), "artifacts — trim is provably logic-inert")
PY
