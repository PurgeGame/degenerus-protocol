# P0/P1 verification

Use `FOUNDRY_PROFILE=consolidation` and `CONSOLIDATION_CANDIDATE=true` for the candidate. These permit larger logic-test contracts; they do not select a native Glamsterdam execution schedule. The default profiles retain Osaka limits. `check-deployment-sizes.js --schedule glamsterdam` checks production runtime and constructor initcode, including ABI-encoded arguments.

`deploymentManifest.js` supplies the ordered CREATE list and explicit semantic aliases. `generate-fixtures.js --check` rejects Foundry/production fixture drift. The Mint adapter remains deployed for Foil's explicit-value call.

Baseline production and Foundry-pin artifacts are stored under `.planning/consolidation/baseline/`. `ConsolidationReplay.t.sol` installs baseline Game and all 17 module runtimes when `DIFFERENTIAL_BASELINE=true`; constructors/bootstrap use the common deployment fixture. Run baseline and candidate with the grouped runner, then compare logs with `compare-replay.js`. The comparison covers recorded written slots, ETH/token balances, events (including anonymous events and indexed-layout variants), and return/revert payloads. At basefee zero only `MinerWork.executionGas` is normalized; a nonzero miner reward fails. Self-comparison and injected slot, payout, event and revert mutations exercise the comparator. Different work chunk counts remain strict unless an explicitly checked checkpoint normalization is added.

`testFocusedPurchases` and `testWarmPurchases` cover the purchase/account slice and actual Affiliate/Quests callbacks. `testLongRunCensus` runs the deterministic storage census. Gas totals are instrumented Osaka execution measurements, not native transaction bills: account/storage warmth is controlled, but SSTORE original values are not reset as independent transactions. `reconcile-gas.py` applies the separate call-traffic model to P1's eliminated edges and retains the Foil adapter and Degenesis delegate boundary.

Use one compile at a time, four Foundry threads, and the required 20G memory/1G swap scope. Do not edit source inputs while a runner is active. Verify `ContractAddresses.sol` is restored after every run or interruption.

Native validation uses an unlocked signer on local chain ID 1337 only. Start Geth with `--dev --dev.period 1 --dev.gaslimit 1000000000 --miner.gaslimit 1000000000 --override.amsterdam 0`, HTTP on 127.0.0.1:18548, then:

```sh
node scripts/consolidation/native-deploy.js prepare http://127.0.0.1:18548 .planning/consolidation/native/deployment
systemd-run --user --scope -q -p MemoryMax=20G -p MemorySwapMax=1G /home/zak/.svm/0.8.34/solc-0.8.34 --base-path . --include-path node_modules --standard-json < .planning/consolidation/native/deployment/input.json > .planning/consolidation/native/deployment/output.json
node scripts/consolidation/native-deploy.js deploy http://127.0.0.1:18548 .planning/consolidation/native/deployment
```

The script records client identity, predicted addresses, runtime/initcode sizes, per-contract receipts, deity bootstrap and four purchases. Production contracts use local VRF/stETH/LINK mocks. Live integrations require the fork group. `liveness-variant-gas.js` compares compiled inline/helper Game variants via read-only native state overrides, with cold storage and an explicit warm access list; access-list intrinsic overhead is included equally in each pair.

For native baseline/candidate purchase gas, run `native-paired-gas.js LOCAL_RPC DEPLOYMENT_DIRECTORY BASELINE_ROOT` to prepare `baseline-input.json`, compile that standard JSON to `baseline-output.json` under the same resource scope, then rerun the script without `BASELINE_ROOT`. It replaces Game and all 17 module runtimes through read-only Geth state overrides at one fixed block. Each cold/warm pair shares storage, balances, input and context; warm probes use the union of both access lists. First registration and Foil use a fresh buyer, since the deployment signer already owns that level's Foil pack. The earlier deployment purchase receipts represent different state and are reported separately. This supplements the long-run instrumented totals; it is not a native lifetime replay.

When comparing a log containing all three replay tests, pass `--run-index 1` to `reconcile-gas.py` to select the long-run scenario. Cold focused, long run and warm focused are indices 0, 1 and 2 respectively.

Run the fork budget probes with `FOUNDRY_ISOLATE=true` and `-vvv`. Their cold/warm cross-check requires fresh transaction warmth; the non-isolated invocation fails three calibration assertions on both baseline and candidate. All 40 fork tests pass in isolated mode. The instrumented consolidation replay remains non-isolated; native paired probes demonstrate cold-account savings that its cooling/warming setup does not reproduce. Keep those gas results distinct.
