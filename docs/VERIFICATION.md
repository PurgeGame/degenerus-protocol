# Build and verification

Run checks against the exact revision supplied for review. The repository contains
source, tests and reproduction tooling; generated logs and analyzer reports stay in
local output directories or CI artifacts.

## Setup

Use Node 20 (as in CI), Python 3, Bash, Git and Foundry. Solidity 0.8.34, via IR,
1,000 optimizer runs and EVM Osaka are set in both compiler configurations.
The npm dependencies and forge-std revision are locked in the repository. Foundry
CI currently follows nightly; record the actual version when reproducing a run.

```sh
git rev-parse HEAD
node --version
forge --version
python3 scripts/audit-snapshot.py
npm ci
git submodule update --init --recursive
```

The snapshot check verifies the scope and hashes of source, build and verification
inputs. It does not attest that tests pass. Maintainers refresh those hashes with
`python3 scripts/audit-snapshot.py --write` after finalizing changes.

Foundry and Hardhat fixtures patch `contracts/ContractAddresses.sol` to their
predicted deployment addresses. The maintained runners restore its original bytes
on completion, failure or handled interruption. Run concurrent campaigns in
separate disposable checkouts. Raw test commands bypass this restoration.

## Build and structural checks

```sh
forge build --skip test
node scripts/check-deployment-sizes.js
bash scripts/layout/storage_layout_oracle.sh
make check-interfaces check-delegatecall check-raw-selectors check-rng-window \
  check-rng-taint check-advance-calls check-unchecked check-write-owners \
  check-pool-writes check-array-delete check-gasleft
make test-assurance-tools
```

The size gate checks deployment entries against the 24,576-byte runtime limit and
rejects stale, missing or unlinked artifacts. Address pins affect compiled output;
repeat deployment checks with the intended production pins. The storage oracle
compares top-level slots, offsets and types; it does not recursively verify nested
struct members. Source manifests are review aids, not proofs of their annotations.

## Tests

The grouped runners bound compilation memory, reject empty or failed batches and
record commands and inputs under the ignored `.audit-test-logs/` directory.
`--list` prints the selected files; `--file` selects a focused source root. Foundry
uses seven logical groups, while Hardhat defaults to one test file per process.

```sh
make test-foundry
make test-hardhat
# Inspect selections or run a focused regression:
python3 scripts/test-foundry-groups.py --list
python3 scripts/test-hardhat-groups.py --list
python3 scripts/test-foundry-groups.py --file test/repro/TerminalAffiliateKnownWord.t.sol
python3 scripts/test-hardhat-groups.py --file test/edge/BackfillIdempotency.test.js
```

For CI-equivalent cold integration and gas checks:

```sh
FOUNDRY_ISOLATE=true python3 scripts/test-foundry-groups.py \
  --group integration-gas --max-files 5 --threads 1
```

CI runs the other six Foundry groups with isolation disabled, at most ten roots
per batch and one thread. The default fuzz campaign uses 1,000 runs; default
invariants use 256 runs at depth 128, with per-suite overrides visible in source.
`npm test` selects fewer files than the maintained Hardhat runner.

Gas expectations, including transaction intrinsic gas, are <=10M for ordinary
calls, <=11M for unusual calls and <=11.5M for extreme cases. No transaction may
exceed 11.5M. Fixture gas limits permit setup and multiple transactions; they are
not the production ceiling. Lower gas usage is acceptable. Do not raise a ceiling
to make a regression pass.

## Deep and symbolic checks

```sh
FOUNDRY_PROFILE=deep FOUNDRY_ISOLATE=false python3 scripts/test-foundry-groups.py \
  --group invariants --max-files 5 --threads 1
```

The deep invariant profile uses 1,000 runs at depth 256. The separate Halmos job
uses version 0.3.3, the `halmos` Foundry profile and the bounds recorded in
[CI](../.github/workflows/ci.yml). Both jobs run on scheduled or manual dispatch.
Use that job's command in a disposable checkout to reproduce symbolic checks.

Known verification limits:

- The last local full Halmos campaign left five properties timed out. A timeout
  establishes neither a counterexample nor a proof; the campaign is not all green.
  These are `check_cost_no_overflow`, `check_autorebuy_ethspent_bounded` and
  `check_takeprofit_multiple` in `test/halmos/Arithmetic.t.sol`, plus
  `check_bps_split_exact` and `check_affiliate_reward_bounded` in
  `test/halmos/NewProperties.t.sol`.
- The last local deep invariant campaign did not finish. Ordinary test passes
  do not substitute for a completed deep run.
- Existing skipped/pending tests and harness assumptions remain visible in test
  source. Imported helper suites can repeat across batches, so execution totals
  are not counts of unique properties.
- A full remote CI run of the supplied revision has not been confirmed. Consult
  that revision's CI results rather than historical local pass counts.

## Static analysis

Optional Slither and Aderyn jobs are configured in CI and are non-blocking.
To run Slither against a fresh Hardhat build in a disposable checkout:

```sh
pip install slither-analyzer==0.11.5
npx hardhat compile
slither . --compile-force-framework hardhat --ignore-compile
```

Analyzer output requires independent triage. Reports and test logs are generated
on demand and are not part of the source handoff.
