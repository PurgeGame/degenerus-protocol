# Ordered-resolution cleanup

Implemented on top of `99611785d` (account liquidation), following the audit in `REPORT.md`.

## Changes

- Craps derives pending fields from FIFO length minus cursor. Removed the separate pending counter, completed-head skipping, head-match conditional, and redundant cursor writes in the outer worker. Final settlement and expiry advance the cursor before notifying Game. Custom-field capacity release remains in the completion path.
- Removed the trailing counter from both shared Craps storage snapshots. No retained field changes slot, offset, or type.
- Degenerette resolves its dense queue without erased-bet skipping or a skip gas allowance. Record-bounty values remain stored; the cursor retires them, unflagged bets ignore them, and later flagged placements overwrite them.
- Removed redundant zero-word checks immediately after successful worker stage checks. Stage gates, transient callback protection, expiry, and partial-resolution cursors remain.
- Removed `_lrAdd`, unused constants, three unused error declarations, and stale resolution comments. Moved the test-only `_walletKey` decoder into test helpers. Updated static-check manifests. The unused Coinflip local noted in the original audit had already been removed by the intervening liquidation commit.
- Replaced the forged-hole and impersonated out-of-order tests with dense-buffer reuse and rejected external resolution coverage. Added a flagged → unflagged → flagged bounty-reuse regression, including an assertion that resolution never writes the bounty slot.
- Fixed the shooter replay helper's old address-width decode of a compact bet. Its three failing comparisons reproduced unchanged on the baseline. It now uses the wallet ID for paid entries and the existing award identity for awarded entries. Production dice and payout calculations were not changed.

## Validation

**746 unique tests passed**, comprising 118 game-side tests, 627 Craps tests, and the optional historical-runtime subscription differential test enabled with the baseline runtime. Fuzz run counts are recorded in `cleanup-verification.json`; configured fuzz properties ran 1,000 cases each.

All 690 production/test Solidity source files typechecked. The production build, 11 static gates, storage goldens, recursive layout comparison across all 16 Game modules, and deployment-size checks passed. The recursive comparison confirms that only the trailing Craps counter was removed.

Tests ran in isolated source copies with Foundry address pins. Production source hashes match the root workspace except those test pins. Craps functional tests use the repository's default non-isolated mode; transaction benchmarks use isolated calls. Initial blanket isolation exposed harness deployment and warm-gas assumptions, so it is not used for the legacy functional suite.

## Measured gas

Compared identical fixtures against the pre-cleanup commit, with Solidity 0.8.34, optimizer 1,000 runs, via-IR, Osaka.

| Workload | Before | After | Saved |
| --- | ---: | ---: | ---: |
| Five Craps arming calls | 536,627 | 500,972 | 35,655 |
| Five complete `mineFlip` transactions, one paid ticket per field | 1,989,930 | 1,960,076 | 29,854 |
| Five complete `mineFlip` transactions, three paid tickets per field | 2,520,956 | 2,490,884 | 30,072 |
| Resolve one Degenerette bet | 111,972 | 111,686 | 286 |
| Resolve three Degenerette bets | 130,088 | 129,310 | 778 |
| Resolve 32 Degenerette bets | 392,108 | 384,194 | 7,914 |

Craps values are execution gas, including full miner dispatch in the resolution rows. Arming is driven through the fixture's window-close door into production registration. Fields also contain the normal protocol-body seats. Degenerette uses the existing lifecycle benchmark's charged-gas output; fresh and reused buffers produced the same resolution values. These Degenerette cases have no record bounty, so they do not include the additional avoided bounty write.

Reproduction: `test/gas/ResolutionCleanupGas.t.sol` under `--isolate` measures the full Craps miner path. Raw results and comparison are in `cleanup-baseline-fifo-gas.log`, `cleanup-game-tests.log`, and `cleanup-gas-comparison.json`. `cleanup-verification.json` records source hashes and final check counts.
