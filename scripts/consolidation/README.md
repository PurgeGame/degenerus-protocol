# Profile verification tools

The current profiles are `eip170` (37 deployment entries, primary audit target) and
`glamsterdam` (21 entries, alternate). Their shared logic is compiled into different hosts.
The authoritative deployment order and aliases are in `scripts/lib/deploymentProfiles.js`;
`deployments/<profile>.json` contains the generated tables. Start with
[build and verification](../../docs/VERIFICATION.md) for toolchain setup, source identity,
structural checks and ordinary tests.

These tools contain both current profile checks and historical consolidation experiments.
The older P0/P1/P2–P6 names describe development stages, not additional supported profiles.
Untracked `.planning/` inputs are not part of an auditor's checkout.

## Build the alternate profile

Run this in a separate, disposable checkout with dependencies installed. Profile generation
changes facade sources, helpers and address pins; preserve the supplied audit snapshot in the
original checkout. Run one compile at a time; the via-IR build can require about 20 GB of memory.

```sh
PROFILE=glamsterdam node scripts/select-profile.js
PROFILE=glamsterdam node scripts/select-profile.js --check
FOUNDRY_PROFILE=consolidation forge build --skip test \
  --out forge-out-production --cache-path .foundry-cache-production
PROFILE=glamsterdam node scripts/check-deployment-sizes.js \
  --schedule glamsterdam forge-out-production
```

For alternate-profile tests, set `PROFILE=glamsterdam` and
`FOUNDRY_PROFILE=consolidation` for the Foundry runner, or `PROFILE=glamsterdam` and
`CONSOLIDATION_CANDIDATE=true` for the Hardhat runner. The relaxed test size limits permit
larger fixture contracts; they do not activate a native Glamsterdam gas schedule. Both use
Osaka execution settings. The alternate production size gate checks 65,536-byte runtime and
131,072-byte initcode limits, including constructor arguments; it does not establish that
those limits are available on a deployment network. Repeat size checks with production pins.

## Compare the current profiles

`profile-differential.py` copies current `contracts/`, `test/`, `scripts/` and `foundry.toml`
into isolated worktrees, then runs all 11 `ConsolidationReplayTest` scenarios for each profile.
The comparison covers recorded slots, ETH/token balances, events and return/revert payloads.
It aligns state-owner addresses by adapting deployment nonces in the test copies. Only
`MinerWork.executionGas` is normalized; the basefee-zero miner reward must remain zero.
Self-comparison and injected slot, payout, event and revert mutations check the comparator.
This is bounded scenario evidence, not a proof of profile equivalence or a production deployment.

The tool requires a runner with the interface `RUNNER WORKTREE TEST_FILE...` and retained
`.pin-logs/<run>/summary.json` output. The following adapter uses the maintained runner and
needs no private `forge-slot.sh`. From the repository root, after setup, with profile and
Foundry overrides cleared:

```sh
mkdir -p .audit-test-logs/profile-comparison
cat > .audit-test-logs/profile-comparison/run-forge.sh <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
cd "$1"
shift
sources=()
for source in "$@"; do sources+=(--file "$source"); done
exec python3 scripts/test-foundry-groups.py "${sources[@]}" \
  --log-dir .pin-logs --threads 1
RUNNER
chmod +x .audit-test-logs/profile-comparison/run-forge.sh
unset DIFFERENTIAL_BASELINE DIFFERENTIAL_OVERRIDES DIFFERENTIAL_DAILY_BASELINE
python3 scripts/consolidation/profile-differential.py \
  --out .audit-test-logs/profile-comparison/results \
  --work-root .audit-test-logs/profile-comparison/worktrees \
  --forge-runner .audit-test-logs/profile-comparison/run-forge.sh
```

The driver sets `PROFILE`, `FOUNDRY_PROFILE=consolidation` and `FOUNDRY_ISOLATE=false` for each
run. Do not edit the source or dependency tree during capture. Preserve `differential.json`,
`comparison-command.json`, driver logs, ABIs and each worktree's `.pin-logs/` evidence, including
input hashes. The script leaves its worktrees available for inspection. A failed or missing
scenario is not a successful comparison. The commands above describe the current tool interface;
new runs must retain their own results rather than inheriting the readiness record's totals.

## Native census replay: separate evidence archive

The readiness record reports a local Osaka Geth replay of 7,819 calls per profile. That result
requires recorder logs, an initial world dump and matching runtime artifacts retained outside
this checkout. `parse-profile-native.py` expects `NATCALL`, `NATCRANK`, `NATSLOT` and related
records; the tracked `ConsolidationReplay.t.sol` does not emit that complete capture format.
The recovered recorder and captured inputs are packaged separately as
`native-evidence-2026-10-28.tar.gz`; [the readiness record](../../docs/audit/freeze.json)
records its SHA-256 and size. Supply it alongside the checkout. The archive includes a portable
path guide, original inputs/results and a per-file hash manifest; assembly verified those hashes
and source/runtime provenance, without rerunning the native replay. Ordinary
profile comparison output alone is insufficient, and the historical call count is not a gate
for a newly generated dataset.

Given the original inputs, these are the parser and replay interfaces (replace uppercase paths):

```sh
python3 scripts/consolidation/parse-profile-native.py \
  --log CAPTURE_LOG --initial INITIAL_WORLD_JSON --out DATASET_DIRECTORY
python3 scripts/consolidation/native-profile-census.py \
  --dataset DATASET_DIRECTORY --artifacts MATCHING_FORGE_ARTIFACT_DIRECTORY \
  --out REPLAY_OUTPUT_DIRECTORY --rpc http://127.0.0.1:18548
```

The replay requires a local Geth endpoint on chain ID **31337**, with the applicable execution
rules, `eth`/`debug` RPC support and sufficient debug-call gas allowance. Record its version and
chain configuration. Artifacts must come from the matching capture checkout; the tool also reads
that checkout's sibling `contracts/ContractAddresses.sol` and derives common fixture pins from
this repository's deployment profile table. The parser requires a completed level-31 long-run
export with contiguous calls and no census mining reverts.

Preserve the input logs, initial dump, parser summary, runtime artifacts, source hashes,
`metadata.json` and replay output. The default replay gas allowance is 500,000,000: it compares
identical recorded work, including batches above a transaction cap. It does not prove that those
batches fit a deployable transaction. `native-multiplier-sweep.py` separately repartitions
that work under a transaction cap, as described below. VRF and stETH in these fixtures are mocks; external integration
evidence comes from the fork suites.

### Capped native replay

Install `pycryptodome` in the replay environment. Use the unpacked evidence archive's
profile dataset and its matching `capture/forge-out` directory; preserve the archive's
directory layout and `SHA256SUMS`. The runner checks the complete recorded call/action
counts, member hashes, current source identity, runtime provenance and declared profile.
The private loopback Geth endpoint must also expose `admin_nodeInfo` so the runner can
authenticate its chain rules, for example with `--http.api eth,net,web3,debug,admin`.

```sh
python3 scripts/consolidation/native-multiplier-sweep.py \
  --dataset PROFILE_DATASET --artifacts MATCHING_CAPTURE_FORGE_OUT \
  --out CAPPED_REPLAY_OUTPUT --rpc http://127.0.0.1:19351 \
  --schedule osaka --profile eip170 --multiplier 0 --limit 16777216
```

Repeat with `--multiplier 2500` and `--multiplier 4294967295` for the minimum calibration
and maximum accepted argument, and with matching inputs plus `--profile glamsterdam` for
the alternate deployment. Both deployment profiles can be exercised under Osaka execution
rules; the profile name does not select the node's rules. The default consumes the entire
level-31 capture. `--through-level` and `--max-groups` explicitly produce partial evidence.
Large calibrations can take substantially longer because more mining transactions are needed,
and can refuse nested-call admission. At this revision the constant maximum runs stop at
level 23 with `InsufficientExecutionGas` during subscriber funding, before any stETH call.
The failed attempts commit no protocol state or logs; normal calibration from an unrelated
caller recovers. These are retained incomplete runs, not constant-maximum passes. Any
continuation with a fallback calibration must be separately labelled and preserve the refusal
records and checked prefix provenance. See `testing_gap_closure` in
[the readiness record](../../docs/audit/freeze.json) for completed and incomplete campaigns.

The candidate state is carried forward after every native call. Only independently recorded
fixture changes are applied; reference poststates never replace candidate state. Rejected
player calls execute and must preserve state with the expected revert. ETH balances,
including the recorder fixture's balance, remain in the comparison. Recorder bookkeeping
storage and transaction-sender nonces are excluded.

One reviewed equivalence applies to sDGNRS: the high 96 bits of slot 7
(`_settlingReserveLeft`) are ignored only when both worlds have no active settling batch.
The exact source hash and slot/offset/type coordinates are pinned. A fresh resolution
bypasses the old cache and a resumable batch stores fresh residue before any later read;
active cache differences and neighboring fields still fail. Raw state and gas measurements
retain the actual value. Results therefore establish equality under this specific inactive
cache equivalence, not byte-for-byte storage equality. Unit tests exercise those boundaries.

This replay uses the zero-fee reference lifecycle. Paid mining is checked separately by
`test/gas/NativePaidLifecycle.t.sol`, with actual reward and supply reconciliation through
level 31; see [verification](../../docs/VERIFICATION.md#composed-and-paid-lifecycle-checks).

## Historical and specialized tools

- `compare-replay.js` also accepts older P1, `--integrated` and `--compiler-only` modes. Their
  semantic adapters are specific to historical revisions. Use `--profiles` for the current
  two-profile comparison, as the driver does; do not reuse allocation/event migration adapters
  in an equivalence claim.
- `DIFFERENTIAL_BASELINE=true` loads runtimes from `.planning/consolidation/baseline/`. Those
  historical artifacts are not shipped. `ConsolidationAutoWhaleGas.t.sol` also depends on that
  baseline; results need the exact original revision and artifact hashes.
- `native-deploy.js` and `native-paired-gas.js` are separate local deployment/state-override
  studies, not the census replay above. Their unlocked-signer guard uses chain ID **1337**.
  Do not confuse their RPC setup, fixtures or receipt totals with the 31337 census evidence.
- `reconcile-gas.py` applies a historical call-traffic model to instrumented Foundry results;
  those modeled totals are not native transaction bills. `compile_sizes.py` compiles the current
  sources; historical saved outputs retain their original compiler provenance.
- The other native, grouping, optimization and XA scripts require the fixtures/variant artifacts
  named by their individual CLI interfaces. A reference to a local `.planning/` path does not
  establish that the artifact is included or current.

For cold fork budget probes use `FOUNDRY_ISOLATE=true`; ordinary instrumented profile replay
uses `FOUNDRY_ISOLATE=false`. Keep those evidence classes separate. Current tested revisions and
remaining release checks belong in [the readiness record](../../docs/audit/freeze.json), not in
historical experiment totals.
