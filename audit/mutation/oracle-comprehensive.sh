#!/usr/bin/env bash
# COMPREHENSIVE mutation oracle for the v63 subject a8b702a7.
#
# WHY comprehensive (vs the prior narrow mistake):
#   The prior harness wrote a per-file oracle as `forge test --match-contract <one regex>`
#   (run-campaign.sh:26). That oracle frequently never executed the mutated line, so it
#   reported FALSE survivors (the documented mutation-oracle mistake: DegenerusVault
#   uncaught=418, BitPackingLib uncaught=63 — the oracle never ran most of the file).
#
#   This oracle is the UNION of the 388-02 ORACLE-HOLES EXERCISED green-baseline tests
#   across all four fix-site/spine target groups (see TARGETS-v63.md). Each target line in
#   every group is executed by at least one test below, so a survivor under THIS oracle is a
#   genuine blind spot, not an artifact of an oracle that skipped the code.
#
# Profile: via_ir is INHERITED from foundry.toml [profile.default] (via_ir=true,
#   evm_version="osaka"). This script does NOT set FOUNDRY_PROFILE and must NOT be run under
#   the `lite` profile (lite drops via_ir). `--no-match-contract VRFPath` excludes the
#   bucket-A run-variance suite (per the v63 green baseline).
#
# Bounded per-mutant runs (FOUNDRY_FUZZ_RUNS / FOUNDRY_INVARIANT_*) are exported by the
#   campaign runner; survivors are re-verified at full runs in Plan 02.
#
# exec's forge so slither-mutate's --test-cmd receives the correct exit code.
set -uo pipefail
cd /home/zak/Dev/PurgeGame/degenerus-audit

exec forge test \
  --no-match-contract VRFPath \
  --match-path 'test/invariant/RedemptionAccounting.t.sol' \
  --match-path 'test/fuzz/RedemptionStethFallback.t.sol' \
  --match-path 'test/fuzz/StakedStonkRedemption.t.sol' \
  --match-path 'test/fuzz/invariant/EthSolvency.inv.t.sol' \
  --match-path 'test/fuzz/invariant/PoolConservation.inv.t.sol' \
  --match-path 'test/fuzz/StorageFoundation.t.sol' \
  --match-path 'test/fuzz/V61Pack.t.sol' \
  --match-path 'test/fuzz/PrecisionBoundary.t.sol' \
  --match-path 'test/fuzz/BurnieEmissionSeeds.t.sol' \
  --match-path 'test/fuzz/CoinflipCarryClaim.t.sol' \
  --match-path 'test/repro/DecimatorOffsetIsolation.t.sol' \
  --match-path 'test/fuzz/invariant/RngWindowFreeze.inv.t.sol'
