# Build and verification

This page explains how to build the contracts, run the checks and read their results. The
[readiness record](audit/freeze.json) holds the measured results for the reviewed revision, and
[audit readiness](AUDIT-READINESS.md) summarizes them. Analyzer output is triaged in
[analyzer triage](audit/ANALYZER-TRIAGE.md). Generated logs and analyzer reports stay in local
output directories or CI artifacts.

## Setup

Use Node 20 and Python 3.12 to match CI, plus Bash, Git and Foundry. Install local Python
packages in a virtual environment. Solidity 0.8.38, via IR, 1,000 optimizer runs and EVM Osaka
are set in both compiler configurations. The npm dependencies and forge-std revision are locked
in the repository. Foundry CI pins `nightly-c07d504b4ae67754584f4e05ff0c547a43c50f7b`; use the
same build for comparable gas and invariant evidence and record the version you ran.

Two deployment profiles exist. `eip170` is the default, the deployment target and the primary
audit target: 37 deployment entries, checked against the 24,576-byte runtime and 49,152-byte
initcode limits (`contracts/profiles/eip170/`, `deployments/eip170.json`). `glamsterdam` is the
alternate: 21 entries checked against 65,536 / 131,072 bytes with `--schedule glamsterdam`
(`contracts/profiles/glamsterdam/`, `deployments/glamsterdam.json`). Both profiles share every
storage layout and all behavior; `scripts/consolidation/profile-differential.py` replays the same scenarios on
both and compares slots, payouts, events and reverts.

The `PROFILE` environment variable selects the profile (unset means `eip170`).
`node scripts/select-profile.js` regenerates the selected-profile sources
(`contracts/profiles/Selected.sol`, and `contracts/DegenerusGame.sol`, `contracts/Coinflip.sol`
and `contracts/CrapsBattle.sol`, which inherit the selected profile's bases directly), both
`deployments/<profile>.json` files and the profile deploy scripts, then writes fixture address
pins; `--no-pins` skips the pins and `--check` fails if a generated file is stale. The maintained
Foundry and Hardhat runners honor `PROFILE` and restore the generated files they touch. For the
alternate profile, Hardhat also needs `CONSOLIDATION_CANDIDATE=true` (`allowUnlimitedContractSize`
in `hardhat.config.js`) and Foundry needs `FOUNDRY_PROFILE=consolidation` so fixtures can embed
the larger deployment code (see `scripts/consolidation/README.md`).

```sh
git rev-parse HEAD
node --version
forge --version
python3 scripts/audit-snapshot.py
npm ci
python3 -m pip install safe-pysha3==1.0.5
git submodule update --init --recursive
```

The Python dependency supplies Keccak for the independent wild-color vector generator; the
Hardhat suite checks that the committed vectors match it.

The snapshot check verifies the scope and hashes of source, build and verification inputs. It
does not attest that tests pass. `python3 scripts/audit-snapshot.py --write` refreshes the hashes.

Foundry and Hardhat fixtures patch `contracts/ContractAddresses.sol` to their predicted
deployment addresses. The maintained runners restore its original bytes on completion, failure
or handled interruption; raw `forge test` / `npx hardhat test` commands do not. Run concurrent
campaigns in separate checkouts.

## Build and structural checks

```sh
forge build --skip test --out forge-out-production --cache-path .foundry-cache-production
node scripts/check-deployment-sizes.js forge-out-production
FOUNDRY_OUT=forge-out-production FOUNDRY_CACHE_PATH=.foundry-cache-production \
  bash scripts/layout/storage_layout_oracle.sh
python3 scripts/layout/check_recursive_layout.py --out forge-out-production \
  --report .audit-test-logs/recursive-layout.json
node scripts/check-owner-actions.js forge-out-production
node scripts/check-owner-governance-layout.js forge-out-production
node scripts/check-vault-player-actions.js forge-out-production
make CHECK_ARTIFACTS=forge-out-production check-interfaces check-delegatecall \
  check-raw-selectors check-rng-window check-pool-writes check-array-delete \
  check-advance-calls check-rng-taint check-rng-shape check-unchecked \
  check-write-owners check-gasleft check-memory-guard check-recipient-calls
make check-audit-snapshot test-assurance-tools
```

The size gate checks every deployment entry of the selected profile (plus the vault share tokens
and the two lens contracts) against the limits of its schedule, runs the memory-guard check, and
rejects stale, missing or unlinked artifacts. Address pins affect compiled output, so repeat
deployment checks with the intended production pins. Keep production artifacts and their cache
separate from test builds: a test runner may overwrite the default artifacts with fixture pins
while an unrelated build cache still considers them current. The size gate rejects that mismatch.

The storage oracle compares top-level slots, offsets and types against `scripts/layout/golden`.
The recursive comparison checks every Game module and the CrapsBattle/JackpotBattle pair against
their shared storage, including nested struct members. The `check-*` source gates enforce
repository rules (interface coverage, delegatecall pairing, RNG window and taint, pool-write
owners, gas reads, unchecked blocks, recipient calls); their manifests are review aids, not proofs
of the annotations they hold.

## Tests

The grouped runners bound compilation memory, reject empty or failed batches and record commands
and inputs under the ignored `.audit-test-logs/` directory. `--list` prints the selected files and
`--file` selects a focused source root. Foundry uses eight logical groups (`integration-gas`,
`repro-symbolic`, `census`, `fuzz-1` to `fuzz-4`, `invariants`) plus `fork`, which runs only when
named and needs an archive RPC in `MAINNET_RPC_URL`. Hardhat runs one test file per process by default.

```sh
make test-foundry
make test-hardhat
python3 scripts/test-foundry-groups.py --list
python3 scripts/test-hardhat-groups.py --list
python3 scripts/test-foundry-groups.py --file test/repro/TerminalPayoutCheckpoints.t.sol
python3 scripts/test-hardhat-groups.py --file test/edge/BackfillIdempotency.test.js
```

Cold-path gas tests run with transaction isolation, as in CI:

```sh
FOUNDRY_ISOLATE=true python3 scripts/test-foundry-groups.py \
  --group integration-gas --max-files 5 --threads 1
```

CI runs seven Foundry groups (all but `census` and `fork`) in separate jobs, plus a separate fork
job. The other six groups run without isolation, at most five roots per batch and one thread. The
default fuzz campaign uses 1,000 runs; default invariants use 256 runs at depth 128, with
per-suite overrides visible in source. `npm test` runs the maintained Hardhat runner, including
all statistical files; discovery fails if a JavaScript test is outside the configured
directories. Focused `npm run test:*` commands use raw Hardhat and bypass pin restoration.

[The test review](TEST_REVIEW.md) separates model, structural and runtime coverage.

### Gas admission evidence

Every mining checkpoint admits its next chunk only when the chunk's proven cold worst case and
the complete call/return/flush tail fit both the remaining worker allowance and the gas actually
available; the bounds are the constants in `contracts/libraries/MineFlipGasBounds.sol`, and the
rules are in [the audit scope](AUDIT.md). A protocol path with no internal checkpoint is one
indivisible chunk. The gas suites under `test/gas/` and `test/repro/` measure each bound's worst
case on Osaka and under the repository's Glamsterdam repricing model with no state reservoir
(`GlamsterdamReprice`), and pin the bound against it. Fixture gas limits do not establish cold
bounds, and gas only selects whether to continue, never an outcome.

## Deep and symbolic checks

```sh
FOUNDRY_PROFILE=deep FOUNDRY_ISOLATE=false python3 scripts/test-foundry-groups.py \
  --group invariants --max-files 5 --threads 1
```

The deep invariant profile uses 1,000 runs at depth 256. CI runs it on scheduled or manual
dispatch, one job per invariant source, splitting the three expensive Craps suites by named
property, with a complementary job for every other test so that partition discovery cannot omit
one (`python3 scripts/deep-invariant-matrix.py` prints the partition). The Halmos job uses
version 0.3.3, the `halmos` Foundry profile and the bounds in [CI](../.github/workflows/ci.yml).

The two multiway split models use exact nonnegative integer arithmetic with separate proofs that
the admitted products, sums and subtractions fit checked `uint256` semantics. Their Solidity fuzz
carriers stay in the ordinary test selection, and the bucket carrier calls the production
library. A source fingerprint requires reviewing the model when its production routine or carrier
files change. This is an arithmetic model proof, not a bytecode-equivalence claim.

```sh
pip install halmos==0.3.3
python3 scripts/test-split-arithmetic.py
python3 scripts/check-split-arithmetic.py --json-output .audit-test-logs/split-arithmetic.json
```

Limits:

- A solver timeout establishes neither a counterexample nor a proof.
- Halmos 0.3.3's unconstrained GAS model cannot establish gas-metered FSM liveness. The
  production transition carriers are real-EVM fuzz tests with explicit boundary scenarios; the
  accounting models are symbolic. Liveness evidence comes from the invariant and gas campaigns.
- Imported helper suites can repeat across batches, so execution totals are not counts of unique
  properties. A bounded campaign does not cover every reachable state.

## Static analysis

CI requires Slither to parse the complete production source; detector findings are reported for
review and do not fail the job, while parsing crashes, omitted IR and stale compiler inputs do.
Aderyn is a non-blocking report. The current output is triaged in
[analyzer triage](audit/ANALYZER-TRIAGE.md).

```sh
python3 -m pip install slither-analyzer==0.11.5
forge build --skip test --build-info --force --out forge-out-slither --cache-path .foundry-cache-slither
python3 scripts/check-slither.py forge-out-slither
slither . --compile-force-framework foundry --ignore-compile \
  --foundry-out-directory forge-out-slither --fail-none \
  --exclude-informational --exclude-optimization --json slither-report.json
```

`check-slither.py` compares every compiler input with the current files, requires an AST for every
scoped source, and rejects partial construction or IR errors. It generates SlithIR and storage
layouts through the pinned 0.11.5 analysis hook, skipping only the transitive dependency closure
that the detector command computes. Use a fresh output directory; old incremental build-info is
rejected. A detector run that times out is incomplete coverage, not a clean report.

CI pins Aderyn 0.6.8 through its npm distribution (the crates.io 0.1.9 release rejects
`evm_version = "osaka"`):

```sh
npm install --global @cyfrin/aderyn@0.6.8
aderyn . -o aderyn-report.md
```

## Focused suites by area

| Area | Suites | Structural gates |
| --- | --- | --- |
| DGVE owner governance ([guide](OWNER_GOVERNANCE.md)) | `test/governance/OwnerGovernance*.t.sol`, `test/fuzz/DegenesisVaultSpend.t.sol`, `test/unit/OwnerGovernance.test.js` | `check-owner-actions.js`, `check-owner-governance-layout.js`, `check-vault-player-actions.js` |
| Lootbox orders and EV allowance | `test/fuzz/Lootbox*.t.sol`, `test/fuzz/OrdinaryLootbox*.t.sol`, `test/gas/LootboxEvLifecycleGas.t.sol`, `test/gas/HumanOrderNativeGas.t.sol`, `test/gas/LootboxOpenGas.test.js`, `test/fuzz/invariant/BoxEnqueue*.inv.t.sol` | layout goldens, `check-pool-writes` |
| Degenesis sale ([review questions](AUDIT-READINESS.md#degenesis-sale--review-scope)) | `test/fuzz/Degenesis*.t.sol`, `test/fuzz/CombinedDegenesisBoxFunding.t.sol`, `test/fuzz/invariant/*Degenesis*.inv.t.sol`, `test/craps/CrapsPasses.t.sol`, `test/craps/JackpotBattle.t.sol`, `test/gas/DegenesisGas.t.sol` | delegatecall pairs, layout goldens (`degenesis*`, `_firstWindowDay`) |
| AFKing subscriptions and quests | `test/fuzz/Afking*.t.sol`, `test/gas/AfkingStartDayQuestGas.t.sol` | `check-rng-shape` |
| Terminal and holder exit | `test/repro/TerminalPayoutCheckpoints.t.sol`, `test/repro/V08StethDeadSweep.t.sol`, fork suite `test/fork/` | `check-recipient-calls` |
| Ticket and jackpot rounds | `test/repro/DirectJackpotTickets.t.sol`, `test/repro/DegradeDirectTicketFallback.t.sol` | `check-gasleft` |
| Solvency, FSM and RNG freeze | `test/fuzz/invariant/` (EthSolvency, PoolConservation, GameFSM, RngWindowFreeze, VRFPathInvariants, AdvanceLiveness and their Degenesis variants) | `check-rng-window`, `check-rng-taint` |

Run any row with `python3 scripts/test-foundry-groups.py --file <path>` (repeatable); add
`FOUNDRY_ISOLATE=true` for files under `test/gas/`.
