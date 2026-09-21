# Build and verification

## Reproduce in a clean checkout

Use the lockfiles, pinned compiler configuration and submodules. CI pins Node 20
(`.github/workflows/ci.yml`); local recorded evidence ran on Node 24.18.0. Record
`node --version`, `forge --version` and `git rev-parse HEAD` with results. Verify the
snapshot hashes first, before anything patches addresses. The submodule step fetches
`lib/forge-std` from GitHub at the revision pinned in `foundry.lock`.

```sh
sha256sum -c docs/audit/source-sha256.txt
npm ci
git submodule update --init --recursive
```

Both test fixtures rewrite `contracts/ContractAddresses.sol`. The grouped Foundry
runner saves the exact original bytes and restores them in `finally`, including on
failure or Ctrl-C. Hardhat still requires a disposable checkout. Do not run both
runners against the same source directory or overwrite another runner's pins.

### Foundry

The full test tree exceeds the practical memory budget of a single compilation.
The committed runner discovers all Solidity tests, rejects unassigned test files,
and runs seven bounded compile units with a separate Foundry cache. Helper sources
remain available to every group. It preserves the configured 1,000 fuzz runs and
256 invariant runs at depth 128; splitting compilation does not lower those limits.

```sh
make test-foundry
# Inspect or select compile groups:
python3 scripts/test-foundry-groups.py --list
python3 scripts/test-foundry-groups.py --group integration-gas
# A focused compile rather than just a post-compilation test filter:
python3 scripts/test-foundry-groups.py --file test/repro/TerminalAffiliateKnownWord.t.sol
```

Raw logs and exact file lists default to `.audit-test-logs/foundry`; `summary.json`
records each exit code and result. `--log-dir` changes the evidence directory.
Unknown options are forwarded to `forge test`. CI uses the same grouped runner.

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

The current local Slither run explicitly selected `--compile-force-framework hardhat
--ignore-compile` after compilation; this avoids auto-selecting Foundry without its
required build-info output.

CI runs Slither through `crytic/slither-action` with `--exclude-informational
--exclude-optimization` and Aderyn with the same `aderyn . -o aderyn-report.md`; the evidence
row counts come from `npm run slither` with the flags above.

### Size table

```sh
forge build --skip test
node scripts/check-deployment-sizes.js
```

The size gate reads the exact `DEPLOY_ORDER` name map plus `DegenerusVaultShare`,
rejects missing/unlinked bytecode and stale source hashes, and requires every
runtime to fit 24,576 bytes. It does not classify deployments by test-helper name
suffixes. Build failures are fatal. `FOUNDRY_OUT` or a positional artifact directory
selects a nondefault output. Address pins affect optimizer output; check the actual
deployment pins as well as each test fixture.

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

## Current evidence — 2026-09-21

The source is the working-tree snapshot based on `1a4d06d08aa1c5e2a15575039dd66e9c8cc1e0b3`.
See [the readiness review](audit/AUDIT-READINESS-2026-09-21.md) and
[the evidence archive](audit/evidence-2026-09-21.tar.gz). Exact test identities and
which rerun supplies each result are in `foundry-reconciliation.json` inside the archive.

| Check | Result |
| --- | --- |
| Foundry full seven-group sweep | 2,608 passes, 45 initial failures, 103 skips; every initial failure resolved by the affected-suite reruns |
| Reconciled Foundry identities, including new regressions | 2,550 unique passing tests, 0 unresolved failures, 103 skipped; duplicate imported test executions counted once |
| Final decimator/claim/freeze/golden/gas rerun | 58 passed, 0 failed, 7 skipped; includes 1,000 full-width entropy fuzz cases and the century stress variants |
| Final Hardhat full suite | 1,658 passed, 0 failed, 23 pending |
| Final statistical suite | 191 passed, 20 pending, 2 previously disclosed failures: obsolete v36 protected-source baseline and STAT-03 empty-bucket expectation |
| Eleven source/interface gates | All pass; 245 RNG taint sites, 91 registered RNG storage accesses and 223 advance external-call sites |
| Storage layout oracle | All 27 top-level goldens and delegatecall slot alignment pass; the packed one-slot decimator snapshot and its tagged claim seed are separately checked by `DecimatorEntropy.t.sol` |
| Runtime size | All 32 deployment entries fit EIP-170 with checked-in and test pins; smallest measured headroom is 16 bytes under Hardhat fixture pins |
| Static analysis | Current counts and triage context in the readiness review; analyzer output is not a clean-bill-of-health assertion |

Fuzz tests retain the configured 1,000 cases (some existing tests request 10,000);
invariants retain 256 runs at depth 128. The full sweep ran during fixture repairs.
The final decimator full-word storage change followed that sweep and was checked
with the 58-test affected suite, a fresh production build, layout/source gates,
full Hardhat rerun and refreshed analyzers. The archive preserves the earlier
contract hashes and initial failed logs; it does not present this as a single
uninterrupted green Foundry invocation. Current discovery splits 193 top-level
fuzz sources into 49/49/49/46 groups; the earlier sweep had 48 in each group.

Cold full-transaction gas measurements (including intrinsic gas where named):

| Path | Gas |
| --- | ---: |
| Century consolidation + failed/rolled-back 365-day vault settlement, final decimator storage | 13,339,416 |
| Same century case, successful vault settlement | 13,302,484 |
| Terminal fresh-word settlement + deity refunds | 10,418,873 |
| Terminal recorded-word settlement + deity refunds | 10,330,161 |
| Early-bird 128-recipient, hero and partial-source-word pressure (call gas, excluding intrinsic) | 7,895,877 |
| Genesis initialization, both protocol deities | 16,378,197 |

The largest measured cold advance has 1,660,584 gas below the 15M review target
and 3,437,800 below the 16,777,216 transaction cap. Genesis is a separate
initialization transaction with only 399,019 gas spare. Stress fixtures retain
explicit capped calls and their non-vacuity assertions. These measurements are
not a mathematical maximum over all reachable states. Summing two separate
advance stages does not describe a single transaction.

## Historical evidence — 2026-09-18

These results precede the current source snapshot and are retained as a baseline.
Recorded on 2026-09-18 (Node 24.18.0, Foundry 1.6.0-nightly, solc 0.8.34) at the manifest's
base revision `2d350e4f9`. The whole-tree Foundry rows were measured on that revision's
sources before they were committed; the far-future suites were re-run after the last
working-tree change to `DegenerusGameMintModule.sol` was reverted to the committed text.
Gates, oracle, sizes and the static-analysis rows were run at the committed revision.

| Check | Result |
| --- | --- |
| Foundry, whole `test/` tree in the seven compile units above | 2,460 passed, 0 failed, 104 skipped, 313 suites |
| Foundry unit 1 (craps, gas, economics, mutation) | 631 passed, 0 failed, 13 skipped |
| Hardhat `make test-hardhat` | 1,656 passing, 22 pending, 0 failing |
| Hardhat `npm run test:stat` | 191 passing, 20 pending, 2 failing: the `v36.0 SURF-01..04` byte-identical baseline check and `STAT-03`, both pre-disclosed reds |
| Eleven `make check-*` gates and the storage layout oracle | all pass |
| Slither 0.11.5, 182 contracts, rescanned at the base revision | 4,120 results, 187 High; High and Medium composition identical to the prior scan (one `uninitialized-state` key re-keyed by the new early-bird latch helper, the shared-storage class) |
| Aderyn 0.6.8 | 10 High, 22 Low, unchanged |
| Worst-case advance stages, cold state, word applied in the same transaction | jackpot-phase day one 10,424,211 (ETH leg) and 8,076,401 (early-bird leg, its own stage); purchase-phase daily 13,837,513; all under 16,777,216 (`test/gas/JackpotDayOneWorstCase.t.sol`, `PurchaseDailyWorstCase.t.sol`) |
| EIP-170 runtime size, checked-in pins | largest 24,559 bytes (`DegenerusGameAdvanceModule`, 17 spare); `DegenerusGameMintModule` 24,444 (132 spare); `CrapsBattle` 23,930 (646 spare); none over |


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
