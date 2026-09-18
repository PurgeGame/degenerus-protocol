# Build and verification

## Reproduce in a clean checkout

Use the lockfiles, pinned compiler configuration and submodules. CI pins Node 20
(`.github/workflows/ci.yml`); the recorded evidence ran on Node 24.18.0. Record
`node --version`, `forge --version` and `git rev-parse HEAD` with results. Verify the
snapshot hashes first, before anything patches addresses. The submodule step fetches
`lib/forge-std` from GitHub at the revision pinned in `foundry.lock`.

```sh
sha256sum -c docs/audit/source-sha256.txt
npm ci
git submodule update --init --recursive
```

Both test fixtures rewrite `contracts/ContractAddresses.sol`: `scripts/lib/patchForFoundry.js`
before Foundry, and the Hardhat deployment fixture during `hardhat test`. Only `make test-foundry`
restores the file. Run in a disposable checkout, and restore with
`git checkout -- contracts/ContractAddresses.sol` before switching between the two runners
or reading a size table.

### Foundry

The whole `test/` tree is one compile unit for a bare `forge test`; that unit does not
finish compiling on a 64 GB machine. Run the tree as seven compile units instead: give
Foundry its own cache with `FOUNDRY_CACHE_PATH` (the Hardhat and Foundry caches otherwise
collide in `cache/`), and for each unit pass `--skip <path>` for every `test/**/*.sol` file
outside that unit, never skipping `test/fuzz/helpers/` or `test/fuzz/handlers/`. The seven
keep-sets used for the evidence row:

1. `test/craps`, `test/differential`, `test/economics`, `test/gas`, `test/helpers`, `test/mutation`, `test/invariant`
2. `test/repro`, `test/halmos`
3-6. `test/fuzz/*.t.sol` (top level only) split into four roughly equal file lists
7. `test/fuzz/invariant`

```sh
export FOUNDRY_CACHE_PATH="$PWD/.fcache"
node scripts/lib/patchForFoundry.js
ALL=$(find test -name '*.sol' | grep -v '/fuzz/handlers/\|/fuzz/helpers/' | sort)
# unit 1 (the craps, gas, economics and mutation slice in the evidence table)
KEEP=$(find test/craps test/differential test/economics test/gas test/helpers test/mutation test/invariant -name '*.sol' | sort)
SKIP=(); for f in $ALL; do grep -qxF "$f" <<< "$KEEP" || SKIP+=(--skip "$f"); done
forge test "${SKIP[@]}"
# repeat with the keep-set of each remaining unit
git checkout -- contracts/ContractAddresses.sol
```

For a quick targeted pass without the unit split:

```sh
forge test --match-path 'test/craps/*.t.sol'
forge test --match-path 'test/fuzz/*Comp*.t.sol'
forge test --match-path 'test/fuzz/invariant/Craps*.t.sol'
```

### Hardhat

```sh
make test-hardhat
npm run test:stat
git checkout -- contracts/ContractAddresses.sol
```

`make test-hardhat` runs the eleven `check-*` gates and then `npx hardhat test` over the
whole tree; that is the figure in the evidence table. `npm test` runs only the
unit/integration/deploy/access/edge globs plus three gas files and reports fewer tests.
`npm run test:stat` needs `python3` on PATH: two of its suites spawn
`scripts/data/derive_5_tables.py` (stdlib-only) as the canonical generator of the
Degenerette payout constants. Its two expected reds are the `v36.0 SURF-01..04` protected-range
byte-identical baseline check and `STAT-03` (empty-bucket skip rate); both are accepted.

### Static analysis

Slither 0.11.5 and Aderyn 0.6.8 produced the evidence rows. Compile with Hardhat first so
Slither reuses that build:

```sh
pip install slither-analyzer==0.11.5
npx hardhat compile
npm run slither      # slither . --filter-paths 'node_modules|mocks' --exclude naming-convention,solc-version,low-level-calls,assembly,too-many-digits,similar-names,dead-code
cargo install aderyn   # or: npm install -g @cyfrin/aderyn
aderyn . -o aderyn-report.md
```

CI runs Slither through `crytic/slither-action` with `--exclude-informational
--exclude-optimization` and Aderyn with the same `aderyn . -o aderyn-report.md`; the evidence
row counts come from `npm run slither` with the flags above.

### Size table

```sh
forge build --sizes
```

The command exits non-zero on this tree: test helpers that are not `.t.sol` files
(`CrapsViews`, `GameSeeder`) exceed 24,576 bytes and `--skip test` does not exclude them.
Deployable code is the `DEPLOY_ORDER` name map in `scripts/lib/predictAddresses.js`
(what `scripts/deploy.js` deploys) plus the Vault's two share tokens; read only those rows.
CI parses `forge build --sizes --json` and skips names ending in `Harness`, `Tester` or
`Seeder` or starting with `Mock`.

## Structural and gas checks

```sh
make check-interfaces check-delegatecall check-raw-selectors check-rng-window \
  check-rng-taint check-advance-calls check-unchecked check-write-owners \
  check-pool-writes check-array-delete check-gasleft
bash scripts/layout/storage_layout_oracle.sh
```

Inspect the runtime sizes for EVERY deployment entry, with actual deployment pins as
well as test pins; require <=24,576 bytes. `forge build --sizes` also reports test/utility
artifacts when included, so identify deployable code explicitly. Verify the engine pin
has code and is appended without shifting earlier addresses. Check initcode/deployment
gas independently of runtime size.

Use the `CrapsGasTest`, `CrapsKeeperBudgetGasTest`, `RoundDrainChunkGas` and
`test/gas/Advance*Gas` suites for reachable worst cases. Include finalizing seats, cold state and combined
advance calls. Test gas caps must not be raised simply to make a regression pass.

## Evidence status

Recorded on 2026-09-18 (Node 24.18.0, Foundry 1.6.0-nightly, solc 0.8.34) at the manifest's
base revision `1df5f574c`. The whole-tree Foundry rows were measured one commit earlier, at
`1190f44a4`; the only source difference is the removal of a dead internal helper from
`CrapsBattle.sol` (runtime bytecode identical), covered by the craps slice, the gates, the size
row and the Slither rescan, all of which were run at the base revision itself.

| Check | Result |
| --- | --- |
| Foundry, whole `test/` tree in the seven compile units above | 2,435 passed, 0 failed, 104 skipped, 297 suites |
| Foundry unit 1 (craps, gas, economics, mutation) at the base revision | 613 passed, 0 failed, 13 skipped |
| Hardhat `make test-hardhat` | 1,656 passing, 22 pending, 0 failing |
| Hardhat `npm run test:stat` | 191 passing, 20 pending, 2 failing: the `v36.0 SURF-01..04` byte-identical baseline check and `STAT-03` (empty-bucket skip rate), both accepted reds; needs `python3` and `scripts/data/derive_5_tables.py` |
| Eleven `make check-*` gates and the storage layout oracle | all pass |
| Slither 0.11.5, 182 contracts, rescanned at the base revision | 4,118 results, 187 High; zero new High or Medium versus the prior scan; one High gone (`uninitialized-state` on the decimator's removed price helper, the shared-storage class) and one Low gone (`timestamp` on the removed craps settlement preview) |
| Aderyn 0.6.8 | 10 High, 22 Low, unchanged |
| EIP-170 runtime size, checked-in pins | largest 24,444 bytes (`DegenerusGameMintModule`, 132 spare); `CrapsBattle` 23,884 (692 spare); none over |


Some `test/repro` tests deliberately assert an undesirable current behavior: a passing
witness confirms the behavior, not a fix. Inspect test intent, skips and failures.
Slither/Aderyn output requires source-specific triage. The 187 Slither Highs by class, as
the project reads them; each remains open to the auditor's own judgment:

- 141 `uninitialized-state`: variables of the shared `DegenerusGameStorage` layout read in one
  module's compilation unit and written in another's. The modules delegatecall against one
  storage, so no unit is a deployment on its own.
- 21 `weak-prng`: day-index and time-of-day gates on `block.timestamp`, and a modulo over an
  already-hashed VRF word; nothing a caller can steer is drawn from them.
- 6 `arbitrary-send-eth`: two in mocks; the rest are the ETH/stETH payout doors of the Game,
  the Vault and sDGNRS paying a recipient computed from the contract's own claim state.
- 6 `reentrancy-balance` and 3 `reentrancy-eth`, all on the advance chain: external calls
  into protocol contracts pinned at deployment.
- 4 `delegatecall-loop`: the lootbox module's spin dispatch to pinned modules.
- 2 `encode-packed-collision`: SVG string assembly in the subscription token renderer.
- 2 `incorrect-exp`: `^` used as bitwise XOR, in OpenZeppelin `mulDiv` and a quest pairing hash.
- 2 `incorrect-shift`: Yul shifts in the bucket-lane packing whose operand order the detector
  misreads; the packing tests pin the layout.

Symbolic proofs and deep invariants are separate runs, not implied by `make test-hardhat` or an
ordinary Foundry pass.
