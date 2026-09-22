# sDGNRS century recycling implementation verification

Date: 2026-09-22. Base commit: `a5d4d2cdcfb9eb1febfaa99e84c75954a9fe74de` plus
the existing working-tree changes. Implementation remains local; no deployment.

## Implemented behavior

At the final transition close after levels 100, 200, etc., the Game calls
`sDGNRS.recycleCentury`. The token computes the supply decrease since its previous
post-refill checkpoint, mints half (rounded down), and adds that inventory to
Whale/Affiliate/Lootbox/Reward in a 1:3:2:1 ratio. Lootbox receives allocation dust;
PresaleBox and the wrapper receive no new allocation. The first checkpoint is
the initial supply, so launch burns are included. Supply reductions from live
redemptions, wrapped redemptions and automatic self-awards all count once.

Repeated/older boundaries and calls after closure are no-ops. A later boundary
consumes the accumulated delta once without a catch-up loop. There is no
`UnexpectedCentury` or `SupplyCapExceeded` error. The supply ceiling follows from
`S_after = S + floor((checkpoint - S)/2) <= checkpoint <= INITIAL_SUPPLY` and is
tested directly. The private mint helper documents that bound before narrowing.

Terminal pool destruction permanently closes recycling, including its
zero-inventory early return. Existing claims, reservation fields, daily burn caps,
backing balances and voting supply have zero delta from the refill itself.
Existing live-pool reward pricing and permissionless settlement remain intact.

## Final validation

Solidity 0.8.34, optimizer 1,000 runs, via IR, Osaka target. Node v24.18.0.
Foundry 1.6.0-nightly, commit `c07d504b4ae67754584f4e05ff0c547a43c50f7b`.

| Check | Result |
| --- | --- |
| Foundry regression batch, 17 selected source files | **121 passed, 0 failed, 0 skipped**. Includes token accounting, both real century transitions through level 200, wrapper paths, redemption reservations and reentrancy repros, automatic whale/decimator awards, affiliate claims, seed windows and boundary gas. |
| Foundry invariant/targeted batch, 3 selected source files | **41 passed, 0 failed, 0 skipped**, including the new permissionless before/after-refill box test. The known failing older box fixture described below was explicitly excluded from this batch. |
| Redemption invariant configuration | 256 runs, depth 128; invariant reports record 32,768 handler calls each. Expected handler reverts remain allowed by the existing configuration. These existing handlers do not force century refills; new refill/claim interaction tests supply that coverage separately. |
| New allocation and repeated-century fuzzing | 1,000 allocation/rounding cases and 1,000 sequences of 25 centuries; explicit burn-event totals reconcile with checkpoint-derived mints and supply. |
| Existing redemption fuzzing | Eight selected `StakedStonkRedemption` fuzz tests ran 10,000 cases each under their existing test configuration. |
| Hardhat token/wrapper/governance/compression suites | **139 passed** after both redundant errors were removed. |
| Storage layout oracle | All goldens match; all shared Game/module slots agree. Only three token fields were appended in slot 8, at offsets 0, 16 and 19. Existing token slots 0–7 are unchanged. |
| Interface coverage | Every interface function has a matching implementation. |
| Source structural gates | Delegatecalls, raw selectors, RNG windows, RNG taint, advance calls, unchecked arithmetic, write owners, pool writes, array deletion and gas-state checks passed. |
| Fresh deployment-size gates | All **32** deployment entries fit and match source hashes under both production and Hardhat fixture address pins. |
| Diff checks | No whitespace errors. |

Counts are per invocation and include the runner's shared helper tests; they are
not a count of distinct new tests. This was targeted verification, not a rerun of
every repository test.

## Measured cold boundary gas

These execute the production `advanceGame` after setup in a separate test
transaction, with a nonzero recycle mint, the existing 20-day century seed,
32 deity renewals, and staking housekeeping. The first two figures include
21,064 intrinsic gas and assert both the recycle and seed actually executed.

| State | Gas |
| --- | ---: |
| Nonempty ongoing pools | 2,566,620 |
| Empty ongoing pools and zero token inventory | 2,617,920 |
| Existing cold 32-deity renewal plus full FF drain chunk, including intrinsic | 5,657,322 |

All are below the 10M comfort target and 16,777,216 hard transaction limit. The
chunked-transition test proves recycling waits until FF work finishes. Separate
tests cover ordinary, compressed and turbo completion, a real VRF retry, a
recorded transition carried across three calendar days, and deadman interruption.

## Runtime bytecode

| Contract | Production pins | Spare | Hardhat fixture pins | Spare |
| --- | ---: | ---: | ---: | ---: |
| sDGNRS | 16,714 | 7,862 | 16,724 | 7,852 |
| DegenerusGameAdvanceModule | 24,526 | 50 | 24,543 | 33 |

Address pins affect optimizer output. AdvanceModule still has very little room;
subsequent changes require another fresh deployment-size check. No size-limit
override or gas-limit relaxation was introduced.

## Existing failure isolated from this change

`LootboxNestedDgnrsOrdering.testParentDgnrsIsSettledAndSnapshotReloadedAcrossNestedEthSpin`
fails with `parent/child/parent DGNRS must settle as three batches: 2 != 3`.
The same failure reproduces in a separate workspace with `sDGNRS.sol`,
`IsDGNRS.sol`, `DegenerusGameAdvanceModule.sol` and that test restored to the base
commit, while retaining the other existing working-tree edits. The fixed seed no
longer exercises its expected three-award arrangement. This old assertion was
neither weakened nor skipped in source.

The new `testPermissionlessKnownWinnerBeforeAndAfterCenturyRefill` passes on the
final implementation. It checks real third-party box opening, larger awards from
a refilled live pool, exact pool debit and no duplicate payment. It does not
replace the older test's three-batch recursion claim.

The RNG-taint gate initially also reported three pre-existing unregistered
`maxWords` parameters in the modified lens. Their source was inspected: they are
bounded pagination counts, not entropy. Three `NOT-RNG` registry rows were added;
the lens implementation was not changed by this task.

## Reproduction and local evidence

Use the grouped Foundry runner from [VERIFICATION.md](../VERIFICATION.md); it
restores `ContractAddresses.sol` after each run. The exact 17-file regression
selection and the three-file invariant selection are in:

```text
.audit-test-logs/sdgnrs-century/regressions/focused-files.txt
.audit-test-logs/sdgnrs-century/regressions/focused.log
.audit-test-logs/sdgnrs-century/regressions/summary.json
.audit-test-logs/sdgnrs-century/invariants/focused-files.txt
.audit-test-logs/sdgnrs-century/invariants/focused.log
.audit-test-logs/sdgnrs-century/invariants/summary.json
```

The second batch used
`--no-match-test testParentDgnrsIsSettledAndSnapshotReloadedAcrossNestedEthSpin`
for the independently reproduced existing failure above. To run just the new
tests:

```sh
python3 scripts/test-foundry-groups.py \
  --file test/economics/SdgnrsCenturyRecycle.t.sol \
  --file test/economics/SdgnrsCenturyTransition.t.sol \
  --file test/gas/SdgnrsCenturyRecycleGas.t.sol
```

Hardhat ran in a disposable copy so its address patcher did not affect the shared
workspace:

```sh
npx hardhat test test/unit/DGNRS.test.js test/unit/DGNRSLiquid.test.js \
  test/unit/VRFGovernance.test.js test/edge/CompressedJackpot.test.js
```

The local paths of the disposable Hardhat, pre-change comparison, and production
build workspaces are recorded in `.audit-test-logs/sdgnrs-century/*-workspace.txt`.
The production workspace contains `production-build.log`, `production-sizes.json`,
`storage-layout.log`, and `interfaces.log`; the Hardhat workspace contains
`hardhat-century-final.log` and `forge-century-sizes.json`. Structural-gate output
is `/tmp/sdgnrs-century-structural.log`. These logs are local artifacts.

## Source hashes

SHA-256 of the final core implementation and intentional storage baseline:

```text
1d1bff09b1f73f12930b8551d2c3f2c3f836db758a8757be9d173c293f920fc4  contracts/sDGNRS.sol
eb66d14dd8383e47de136a42d39c78f0d0c12d00ed5d9fdd37fb98338be5ca49  contracts/interfaces/IsDGNRS.sol
f0a1969fec2672652bd677d1f1218dde76999dfa43a62de2b568a06655c4d8a0  contracts/modules/DegenerusGameAdvanceModule.sol
2b182c3fd96324fda275156bfadc43483318d447611a12c0a77e52102133444a  scripts/layout/golden/sDGNRS.json
e41115c53f44c415fdb10879a560892d71730ce9cef79eb708f22583bbb1ea92  contracts/FLIP.sol
```

`contracts/FLIP.sol` is listed because the same commit also raised
`SDGNRS_DECIMATOR_CAP` from 150,000 to 500,000 FLIP - an unrelated economic
change that rides this one. It triples the sDGNRS FLIP backing spent per
decimator opening, and it is not covered by the recycling analysis above.

This is supplemental verification for the recycling change. It does not replace
the repository's earlier audit snapshot or claim those older source hashes still
describe the modified contracts.
