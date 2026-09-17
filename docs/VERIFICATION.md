# Build and verification

## Reproduce in separate clean checkouts

Use the lockfiles, pinned compiler configuration and submodules. Node 20 matches CI.
Record `node --version`, `forge --version` and `git rev-parse HEAD` with results.
Verify the snapshot hashes BEFORE patching addresses.

```sh
npm ci
git submodule update --init --recursive
node scripts/lib/patchForFoundry.js
forge build --skip test --sizes
forge test
```

For memory-constrained machines, use targeted paths without changing the optimizer:

```sh
forge test --match-path 'test/craps/*.t.sol'
forge test --match-path 'test/fuzz/*Comp*.t.sol'
forge test --match-path 'test/fuzz/invariant/Craps*.t.sol'
```

In a separate checkout for Hardhat:

```sh
npm ci
npm test
npm run test:stat
```

Foundry/Hardhat fixtures can patch `ContractAddresses.sol`. The Makefile Foundry target
also restores that file from Git; use clean disposable checkouts so a local deployment
configuration or uncommitted source pin is not lost.

## Structural and gas checks

```sh
make check-interfaces check-delegatecall check-raw-selectors check-rng-window \
  check-rng-taint check-advance-calls check-unchecked check-write-owners \
  check-pool-writes check-array-delete check-craps-progressive check-gasleft
bash scripts/layout/storage_layout_oracle.sh
```

Inspect the runtime sizes for EVERY deployment entry, with actual deployment pins as
well as test pins; require <=24,576 bytes. `forge build --sizes` also reports test/utility
artifacts when included, so identify deployable code explicitly. Verify the engine pin
has code and is appended without shifting earlier addresses. Check initcode/deployment
gas independently of runtime size.

Use `CrapsGas`, `CrapsKeeperBudgetGas`, `RoundDrainChunkGas` and the advance-stage gas
suites for reachable worst cases. Include finalizing seats, cold state and combined
advance calls. Test gas caps must not be raised simply to make a regression pass.

## Evidence status

Recorded on 2026-09-17 at the manifest's base revision (Node 24.18.0, Foundry 1.6.0-nightly,
solc 0.8.34); re-run against the exact delivery revision if it differs.

| Check | Result |
| --- | --- |
| Foundry, whole `test/` tree in seven compile units | 2,422 passed, 0 failed, 104 skipped, 294 suites |
| Hardhat `make test-hardhat` | 1,656 passing, 22 pending, 0 failing |
| Hardhat `npm run test:stat` | 191 passing, 20 pending, 2 failing: the accepted byte-identical baseline check and the empty-bucket skip-rate bound, both pre-disclosed reds |
| Twelve `make check-*` gates and the storage layout oracle | all pass |
| Slither 0.11.5, 182 contracts | 4,119 results, 188 High; composition identical to the prior scan |
| Aderyn 0.6.8 | 10 High, 22 Low, unchanged |
| EIP-170 runtime size, checked-in pins | largest 24,444 bytes (`DegenerusGameMintModule`, 132 spare); none over |


Some `test/repro` tests deliberately assert an undesirable current behavior: a passing
witness confirms the behavior, not a fix. Inspect test intent, skips and failures.
Slither/Aderyn output requires source-specific triage; the per-class triage of the High tier
(dominated by `uninitialized-state` on the shared-storage delegatecall modules) is in the
[archived known-issues register, section 5](archive/pre-audit-2026-09-05/KNOWN-ISSUES.md#5-automated-tool-findings-pre-disclosed),
measured at the prior tree; the composition is unchanged at this one. Symbolic proofs and deep
invariants are separate runs, not implied by `npm test` or an ordinary Foundry pass.
