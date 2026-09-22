# Random sDGNRS century refill verification

Date: 2026-09-22. Base: `0fca5ff3`. Local source change; no deployment.
Supersedes the fixed-half rule in the earlier
[implementation report](SDGNRS-CENTURY-RECYCLE-2026-09-22.md).

## Behavior and bounds

Every completed x00 transition now passes its existing committed `rngWord` into
`recycleCentury(uint24,uint256)`. The token draws:

```text
tag = keccak256("sdgnrs.century.refill")
percent = 25 + keccak256(abi.encode(rngWord, uint256(tag) XOR completedLevel)) % 51
burned = previousPostMintCheckpoint - currentSupply
minted = floor(burned * percent / 100)
```

The 51 whole percentages run from 25 through 75 inclusive, with mean 50%, apart
from negligible modulo bias. Fractional raw-unit rounding is discarded for each
century. The chosen percentage is included in `CenturyRecycled`, including when
the mint rounds to zero. The event ABI and GAME-only entry-point ABI both change.

The word survives `_unlockRng` in the advance function's local variable. No new
request, caller, timestamp, burn amount or pool balance enters the percentage
draw. The roll becomes public with the word; it is not hidden until the refill.
The existing century marker prevents retries from changing or repeating it.
Permissionless reward settlement retains its accepted live-pool pricing.

All live-game burns still count. The pool split remains Whale/Affiliate/Lootbox/
Reward = 1:3:2:1, with allocation dust to Lootbox. PresaleBox and wrapper inventory
receive no refill. Game over closes recycling permanently. No storage fields,
external calls from the token, backing movements, claim changes, or new reverting
guards were added.

Because `minted <= 75% * burned <= burned`, post-mint supply remains at or below
the prior checkpoint and initial supply. At least 25% of each interval's burns
stay removed. `burned * percent <= 75e30`, so the checked multiplication fits
`uint256` before narrowing. No `SupplyCapExceeded` or `UnexpectedCentury` guard
is required.

## Executed checks

- Focused Foundry batch: **49 passed, 0 failed, 1 pre-existing skip** across six
  selected source files and the runner's shared helpers. Includes real progression
  through two centuries, normal/compressed/turbo closes, far-future chunking,
  delayed close, VRF retry and terminal interruption.
- Token coverage: explicit 25% and 75% vectors; replay with changed word and time;
  different century domains for the same word; zero burns and tiny raw-unit dust;
  1,000 random-word/allocation cases; 1,000 sequences of 25 random centuries.
  Existing claims, daily caps, wrapper burns, inventory surplus and terminal
  accounting assertions continue to pass.
- The skipped parent/child/parent lootbox fixture was already skipped at the base
  commit. Its separate permissionless before/after-refill test passes. This change
  does not claim to restore the older nested-award coverage.
- Hardhat token, wrapper, governance and compression suites: **139 passed**.
- Storage layout oracle: all goldens match and shared Game/module slots agree.
  Interface coverage: every interface function has a matching implementation.
  Diff whitespace check passed.
- Structural gates passed: delegatecalls, raw selectors, RNG windows and taint,
  advance calls, unchecked arithmetic, write owners, pool writes, array deletion
  and gas-state checks. The three new RNG argument/parameter sites are registered.

## Cold transition gas

Both measured calls execute the nonzero refill, century seed and 32 deity grants
in production `advanceGame`, after setup in a separate transaction. Figures
include 21,064 intrinsic gas.

| Pool state | Gas |
| --- | ---: |
| Nonempty | 2,566,795 |
| Empty ongoing pools and zero inventory | 2,618,095 |

Both are 175 gas above the fixed-half implementation and below the 10M comfort
target and 16,777,216 transaction limit. No limits were relaxed.

## Deployment size

Fresh Solidity 0.8.34 builds (optimizer 1,000 runs, via IR, Osaka) passed the
source-hash and runtime-size gate for all **32** deployment entries under both
production and Hardhat fixture pins.

| Contract | Production bytes | Spare | Fixture bytes | Spare |
| --- | ---: | ---: | ---: | ---: |
| sDGNRS | 16,798 | 7,778 | 16,808 | 7,768 |
| DegenerusGameAdvanceModule | 24,518 | 58 | 24,535 | 41 |

The advance module remains close to its limit; no size override was added.

## Evidence

Focused logs: `.audit-test-logs/sdgnrs-century-random/focused/`.
Structural log: `/tmp/sdgnrs-random-structural.log`.
Disposable production/fixture build and regression workspace:
`/home/zak/.cache/purgegame-tmp/sdgnrs-century-random-3gqglkyc`.

The grouped Foundry invocation selects `SdgnrsCenturyRecycle.t.sol`,
`SdgnrsCenturyTransition.t.sol`, `SdgnrsCenturyRecycleGas.t.sol`,
`CenturyDrivenTransition.t.sol`, `CenturySeedWindow.t.sol` and
`LootboxNestedDgnrsOrdering.t.sol`. The runner restores deployment address pins.

The disposable workspace contains `production-build.log`, `production-sizes.json`,
`hardhat.log`, `fixture-build.log`, `fixture-sizes.json`, `layout.log` and
`interfaces.log`. Hardhat selected
`test/unit/DGNRS.test.js`, `test/unit/DGNRSLiquid.test.js`,
`test/unit/VRFGovernance.test.js` and `test/edge/CompressedJackpot.test.js`.
The production files in that workspace match the working tree. SHA-256:

```text
cd2709a17016bde7b3c9030917acbe1466ecfcf9522a93c1f2dbdde13ed5e793  contracts/sDGNRS.sol
0155d155e11221f7e35875a9a088b72da5f1d2d50fe644a11cff246af88ac8cc  contracts/interfaces/IsDGNRS.sol
42631aaf0405c8e1d9d00ebdb283620b07040d02743ece1505939080b6c30bac  contracts/modules/DegenerusGameAdvanceModule.sol
```
