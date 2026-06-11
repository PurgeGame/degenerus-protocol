#!/usr/bin/env bash
# Bytecode-identity validation: hash every production contract's runtime bytecode.
#
#   ./scripts/bytecode-manifest.sh save     # snapshot after a fully-validated build
#   ./scripts/bytecode-manifest.sh check    # diff current build against the snapshot
#
# Identical hashes mean zero behavioral delta — no test run can distinguish the
# builds — so config flips, comment edits, and already-pruned dead-code removals
# validate in seconds instead of a full suite run. Any hash mismatch means the
# change DOES alter codegen: run the appropriate test tier instead.
set -euo pipefail
cd "$(dirname "$0")/.."

MANIFEST=".bytecode-manifest"
CONTRACTS=(
  BurnieCoin BurnieCoinflip DegenerusAdmin DegenerusAffiliate DegenerusDeityPass
  DegenerusGame DegenerusJackpots DegenerusQuests DegenerusStonk DegenerusTraitUtils
  DegenerusVault DeityBoonViewer GNRUS Icons32Data StakedDegenerusStonk
  WrappedWrappedXRP DegenerusGameAdvanceModule DegenerusGameBingoModule
  DegenerusGameBoonModule DegenerusGameDecimatorModule DegenerusGameDegeneretteModule
  DegenerusGameGameOverModule DegenerusGameJackpotModule DegenerusGameLootboxModule
  DegenerusGameMintModule DegenerusGameWhaleModule GameAfkingModule
)

forge build > /dev/null 2>&1

# Hash the executable code only: solc appends a CBOR metadata trailer (length in
# the final 2 bytes) whose ipfs hash covers source text and compiler settings —
# it changes on comment edits and evm_version flips that leave codegen untouched.
# Stripping it keeps the manifest keyed to behavior alone.
strip_metadata() {
  python3 -c '
import sys
h = sys.stdin.read().strip().removeprefix("0x")
b = bytes.fromhex(h)
mlen = int.from_bytes(b[-2:], "big")
print(b[: len(b) - (mlen + 2)].hex())'
}

current() {
  for c in "${CONTRACTS[@]}"; do
    h=$(forge inspect "$c" deployedBytecode 2>/dev/null | strip_metadata | sha256sum | cut -c1-16)
    echo "$h  $c"
  done
}

case "${1:-check}" in
  save)
    current > "$MANIFEST"
    echo "saved $(wc -l < "$MANIFEST") contract hashes to $MANIFEST"
    ;;
  check)
    if [[ ! -f "$MANIFEST" ]]; then echo "no $MANIFEST — run 'save' after a validated build" >&2; exit 2; fi
    if diff <(current) "$MANIFEST" > /tmp/manifest-diff.txt; then
      echo "IDENTICAL — zero behavioral delta vs validated build; no test run required"
    else
      echo "CHANGED — codegen differs; run the appropriate test tier:"
      grep '^[<>]' /tmp/manifest-diff.txt | awk '{print $1, $3}' | sort -u -k2 | awk '{print "  " $2}' | sort -u
      exit 1
    fi
    ;;
  *) echo "usage: $0 [save|check]" >&2; exit 2 ;;
esac
