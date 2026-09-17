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
  check-pool-writes check-array-delete check-gasleft
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

Recorded on 2026-09-17 (Node 24.18.0, Foundry 1.6.0-nightly, solc 0.8.34). The whole-tree
rows were measured at `67b95c745`; the manifest's base revision differs from it only in
`CrapsBattle.sol` (the reservation upgrade and the slip event's high bits), covered by the
craps slice, the gates, the size row and the Slither rescan below. Re-run against the exact
delivery revision if it differs.

| Check | Result |
| --- | --- |
| Foundry, whole `test/` tree in seven compile units | 2,422 passed, 0 failed, 104 skipped, 294 suites |
| Hardhat `make test-hardhat` | 1,656 passing, 22 pending, 0 failing |
| Hardhat `npm run test:stat` | 191 passing, 20 pending, 2 failing: the accepted byte-identical baseline check and the empty-bucket skip-rate bound, both pre-disclosed reds |
| Eleven `make check-*` gates and the storage layout oracle | all pass |
| Slither 0.11.5, 182 contracts, rescanned at the base revision | 4,120 results, 188 High; High and Medium identical to the prior scan, one new Low (`timestamp` on `upgradeReservedDay`, the day-index gate every reservation door shares) |
| Aderyn 0.6.8 | 10 High, 22 Low, unchanged |
| Craps and gas slice at the base revision, after the reservation upgrade | 658 passed, 13 skipped, 1 failed: the seal suite's amend-vacuity seed guard, a harness artifact |
| EIP-170 runtime size, checked-in pins | largest 24,444 bytes (`DegenerusGameMintModule`, 132 spare); `CrapsBattle` 24,286 (290 spare); none over |


Some `test/repro` tests deliberately assert an undesirable current behavior: a passing
witness confirms the behavior, not a fix. Inspect test intent, skips and failures.
Slither/Aderyn output requires source-specific triage. The 188 Slither Highs by class, as
the project reads them; each remains open to the auditor's own judgment:

- 142 `uninitialized-state`: variables of the shared `DegenerusGameStorage` layout read in one
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

Symbolic proofs and deep invariants are separate runs, not implied by `npm test` or an
ordinary Foundry pass.
