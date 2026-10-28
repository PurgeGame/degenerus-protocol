# P0/P1 verification

Use `FOUNDRY_PROFILE=consolidation` and `CONSOLIDATION_CANDIDATE=true` for the candidate. These permit larger logic-test contracts; they do not select a native Glamsterdam execution schedule. The default profiles retain Osaka limits. `check-deployment-sizes.js --schedule glamsterdam` checks production runtime and constructor initcode, including ABI-encoded arguments.

`deploymentManifest.js` supplies the ordered CREATE list and explicit semantic aliases. `generate-fixtures.js --check` rejects Foundry/production fixture drift. The Mint adapter remains deployed for Foil's explicit-value call.

Baseline production and Foundry-pin artifacts are stored under `.planning/consolidation/baseline/`. `ConsolidationReplay.t.sol` installs baseline Game and all 17 module runtimes when `DIFFERENTIAL_BASELINE=true`; constructors/bootstrap use the common deployment fixture. Run baseline and candidate with the grouped runner, then compare logs with `compare-replay.js`. The comparison covers recorded written slots, ETH/token balances, events (including anonymous events and indexed-layout variants), and return/revert payloads. At basefee zero only `MinerWork.executionGas` is normalized; a nonzero miner reward fails. Self-comparison and injected slot, payout, event and revert mutations exercise the comparator. Different work chunk counts remain strict unless an explicitly checked checkpoint normalization is added.

`testFocusedPurchases` and `testWarmPurchases` cover the purchase/account slice and actual Affiliate/Quests callbacks. `testLongRunCensus` runs the deterministic storage census. Gas totals are instrumented Osaka execution measurements, not native transaction bills: account/storage warmth is controlled, but SSTORE original values are not reset as independent transactions. `reconcile-gas.py` applies the separate call-traffic model to P1's eliminated edges and retains the Foil adapter and Degenesis delegate boundary.

Use one compile at a time, four Foundry threads, and a memory limit (a via-IR build needs about 20 GB). Do not edit source inputs while a runner is active. Verify `ContractAddresses.sol` is restored after every run or interruption.

Native validation uses an unlocked signer on local chain ID 1337 only. Start Geth with `--dev --dev.period 1 --dev.gaslimit 1000000000 --miner.gaslimit 1000000000 --override.amsterdam 0`, HTTP on 127.0.0.1:18548, then:

```sh
node scripts/consolidation/native-deploy.js prepare http://127.0.0.1:18548 .planning/consolidation/native/deployment
solc-0.8.38 --base-path . --include-path node_modules --standard-json < .planning/consolidation/native/deployment/input.json > .planning/consolidation/native/deployment/output.json
node scripts/consolidation/native-deploy.js deploy http://127.0.0.1:18548 .planning/consolidation/native/deployment
```

The script records client identity, predicted addresses, runtime/initcode sizes, per-contract receipts, deity bootstrap and four purchases. Production contracts use local VRF and stETH mocks. Live integrations require the fork group. `liveness-variant-gas.js` compares compiled inline/helper Game variants via read-only native state overrides, with cold storage and an explicit warm access list; access-list intrinsic overhead is included equally in each pair.

For native baseline/candidate purchase gas, run `native-paired-gas.js LOCAL_RPC DEPLOYMENT_DIRECTORY BASELINE_ROOT` to prepare `baseline-input.json`, compile that standard JSON to `baseline-output.json` under the same resource scope, then rerun the script without `BASELINE_ROOT`. It replaces Game and all 17 module runtimes through read-only Geth state overrides at one fixed block. Each cold/warm pair shares storage, balances, input and context; warm probes use the union of both access lists. First registration and Foil use a fresh buyer, since the deployment signer already owns that level's Foil pack. The earlier deployment purchase receipts represent different state and are reported separately. This supplements the long-run instrumented totals; it is not a native lifetime replay.

When comparing a log containing all three replay tests, pass `--run-index 1` to `reconcile-gas.py` to select the long-run scenario. Cold focused, long run and warm focused are indices 0, 1 and 2 respectively.

Run the fork budget probes with `FOUNDRY_ISOLATE=true` and `-vvv`. Their cold/warm cross-check requires fresh transaction warmth; the non-isolated invocation fails three calibration assertions on both baseline and candidate. All 40 fork tests pass in isolated mode. The instrumented consolidation replay remains non-isolated; native paired probes demonstrate cold-account savings that its cooling/warming setup does not reproduce. Keep those gas results distinct.

For P1b, use baseline runtimes compiled from `8df041030b961987a1864eaf5e4e3c01184e2662`.
The replay sends the baseline self-purchase its four-argument calldata. At each actual cohort
split it asserts the old half-future allocation or the new quarter-future/quarter-insurance
allocation. It then adjusts only the baseline future/insurance balances and the request's
1% pending seed before later gameplay. The comparator maps only the Vault self-spend event
to the new indexed-recipient form; all other state, events and results remain strict, with
the existing `MinerWork.executionGas` exclusion. Gift behavior is covered by the focused suite.
Use `check-surface.js BASELINE CANDIDATE --degenesis-gift` to allow exactly the replacement
`spendDegenesis` signature while checking the rest of the Game ABI unchanged.

`ConsolidationAutoWhaleGas.t.sol` pairs the existing cold automatic-whale benchmark with
the committed baseline runtimes. Run it with the consolidation profile and the same baseline
artifact directory; this paired test reads the baseline artifacts without an environment toggle.

For a compiler-only comparison, build the same production revision independently with each
compiler and run the same expanded replay on both with `DIFFERENTIAL_BASELINE=false`.
The replay now includes cold/warm purchases, cold/warm box gameplay, and the storage-census
long run. Pass `--compiler-only` as the final comparator argument to keep event signatures
and arguments strict; only `MinerWork.executionGas` is excluded. Do not use the historical
P1b semantic/runtime adapters for a compiler comparison. The long-run scenario is index 2
when all five tests are run in name order. `StackSpillCallbackGas.t.sol` measures execution
without transaction intrinsic gas and must run with `FOUNDRY_ISOLATE=false`.

`compile_sizes.py` is the active copy of the former planning experiment. It uses the current
compiler pin and resolves compiler/dependency paths for the current worktree. Frozen planning
inputs and outputs remain evidence of their original compiler.

## Integrated P2–P6 checks

The combined manifest has 23 ordered protocol deployments. Box, Daily, Pass,
Endgame and Craps each deploy once; Miner and Bingo alias Game. The legacy Mint
key aliases Endgame, whose explicit-value purchase helpers are internal.
Regenerate canonical fixture sections with `generate-fixtures.js` and address
pins with the deployment-specific patcher after changing the manifest.

For the integrated replay, keep `DIFFERENTIAL_BASELINE=false` on both sides.
Install the base revision through `DIFFERENTIAL_OVERRIDES`: compile its original
modules at distinct code addresses, with the same state-owner addresses as the
candidate fixture. Include baseline CrapsViews at the common table address and
its original lifecycle/engine at 0x1006/0x1007. The replay maps all original module
fields before account cooling and census registration. The old
`DIFFERENTIAL_BASELINE=true` P1 adapter is unsuitable for aliased deployments.

The replay combines cold/warm purchases, boxes, hot Game entries, Daily and
Craps scenarios with the storage-census long run. Compare with:

```sh
node --max-old-space-size=10000 scripts/consolidation/compare-replay.js \
  BASELINE_LOG CANDIDATE_LOG BASELINE_ABIS_JSON RESULT_JSON --integrated
```

Integrated mode enables the Box, Game, Pass/Endgame and Craps removed-edge checks
and keeps the retained external engine calls strict. It applies no P1 event or
allocation migration. Only `MinerWork.executionGas` is excluded from comparison;
basefee-zero miner rewards must remain zero.

Production builds used for both layout and call-cycle checks must emit both
`storageLayout` and `irOptimized` when overriding Forge's extra-output setting.
Use fresh production artifacts for size/memory checks and verify address-pin
restoration after every test invocation. Acceptance evidence and the remaining
final-pass checks are listed in `.planning/consolidation/INTEGRATION-REPORT.md`.
