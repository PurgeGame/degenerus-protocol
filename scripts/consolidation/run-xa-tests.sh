#!/usr/bin/env bash
# Run the shared memory-capped Foundry lane while preserving this lane's address aliases.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
runner="${XA_FORGE_SLOT:-../degenerus-audit/.planning/pin-tests-2026-10-21/forge-slot.sh}"
saved="$(mktemp)"
cp contracts/ContractAddresses.sol "$saved"
before="$(sha256sum contracts/ContractAddresses.sol | cut -d' ' -f1)"
restore() {
  cp "$saved" contracts/ContractAddresses.sol
  rm -f "$saved"
  test "$(sha256sum contracts/ContractAddresses.sol | cut -d' ' -f1)" = "$before"
  echo 'contracts/ContractAddresses.sol: OK'
}
trap restore EXIT
export FOUNDRY_PROFILE=consolidation CONSOLIDATION_CANDIDATE=true
export FOUNDRY_FUZZ_RUNS="${FOUNDRY_FUZZ_RUNS:-256}"
"$runner" "$PWD" "$@"
