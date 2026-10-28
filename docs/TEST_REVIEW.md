# Test suite usefulness notes

These notes say which tests in `test/` are execution evidence for production behavior
and which are not. They do **not** establish that every assertion is correct or that
all protocol behavior is covered. Passing a model or source-text guard is not a
production execution proof. Run commands and results are in
[VERIFICATION.md](VERIFICATION.md).

## Discovery

`npm test` runs `scripts/test-hardhat-groups.py`, which assigns every
`test/**/*.test.js` file to a Hardhat batch and fails on any unassigned file
(`test/unit/test_hardhat_groups.py` covers the runner; `test/unit/test_foundry_groups.py`
covers the Foundry grouping). The statistical suites in `test/stat` are part of the
default selection.

## What is not a production execution proof

- **Arithmetic and statistical models.** `test/fuzz/DustAccumulation.t.sol` and most
  of `test/fuzz/PrecisionBoundary.t.sol` exercise local arithmetic models (both files
  say so in their headers), as do parts of the statistical suites. They are useful
  for distributions and bounds but can drift from production. Pair a protocol claim
  with a test that calls the implementation or a checked differential harness.
- **Source-text guards** check structure, not runtime semantics.
- **Gas benchmarks.** Tests that only print gas measurements are benchmarks, not
  ceiling gates. Small helper gas checks such as `test/gas/Phase261GasRegression.test.js`
  do not establish transaction-level ceilings; the Foundry cold gas gates run
  separately.
- **Halmos** `check_*` functions are not executed as proofs by ordinary Forge runs.
  The Halmos job, the deep invariant campaign and their limits are recorded in
  [VERIFICATION.md](VERIFICATION.md) and [AUDIT-READINESS.md](AUDIT-READINESS.md).

## Opt-in cases

The suite has no unconditionally skipped cases. Two tests skip unless an
environment variable is set, and report SKIP, never PASS, without it:

| Test | Variable | Purpose |
| --- | --- | --- |
| `test/gas/AfkingRepricingFixtures.t.sol` `test_ExportRepricingFixtures` | `AFKING_REPRICING_STATE_DIR` | Exports repricing fixture state; not a check. |
| `test/fuzz/GrowthFoilStorage.t.sol` `testFuzz_FoilMatchesArchivedRuntime` | `CUSTOMER_GROWTH_FOIL_REFERENCE` | Optional differential oracle against an archived runtime; the file's independent policy/lane tests always run. |

## Redemption batch coverage

Common deployment and worker fixtures live in `test/fuzz/helpers/RedemptionFixture.sol`
and `test/fuzz/helpers/RedemptionCloseTools.sol`. The latter exposes the production
close/funding hook (`_closeRedemptionBatch`) without a whole VRF session; real request
integration is covered by `RedemptionForwardBatches` and the session suites.

| Property | Regression coverage |
| --- | --- |
| A burn leaves supply at once and records raw token weight and the first activity score; escrow keeps the holder's share of the base until a daily or mid-day request closes and prices the batch. | `RedemptionForwardBatches`, `StakedStonkRedemption`, `RedemptionEdgeCases` |
| Exact batch token conservation; no daily or supply cap (burns accumulate across days and a batch can exceed half the supply); exact reserves including cursor rounding dust and parked claims. | `RedemptionAccounting` (invariant), `RedemptionEdgeCases` |
| The batch's FLIP leg pays on a tagged synthetic flip, independent of the daily coinflip bit. | `RedemptionForwardBatches`, `StakedStonkRedemption`, `RedemptionBatching` |
| The lootbox leg resolves as one box order of at most 20 boxes, with cold gas bounds. | `RedemptionForwardBatches`, `RedemptionBatchGas`, `RandomnessSeedInputs` |
| The close moves the batch's maximum (175%) payout, capped at free backing, from sDGNRS's Game claimable into the redemption reserve; live legs pay only from that reserve, a stETH transfer failure cannot block the close or settlement, and token donations wait for the ending. | `RedemptionStethFallback` |
| Open escrow stays in the holder base until its batch closes; pending and resolved claims survive century refills. | `SdgnrsCenturyRecycle` |
| Both endings resolve an unrolled settling batch at 100; a batch resolved live keeps its roll; the open batch unwinds at the terminal burn price. | `RedemptionForwardBatches`, `DeadVrfEnding` |

The redemption suites also cover real payable forwarding, stETH-before-ETH reentrancy,
protection of other claims' reserves, settlement order, parked retries, operator
authorization and terminal claims without an expiry.

## Rules for new or changed tests

Require a specific observable failure when the claimed behavior breaks. Assert the
fixture reached the intended state before checking it. Do not catch assertion
failures, silently skip fixture errors, compare an unsigned value with zero, or count
a setup-only check as a protocol property. Use `afterInvariant` and focused success
cases to establish meaningful activity; use a deliberate bad state or mutation where
an invariant's detector is subtle. Keep shared handler changes under the campaigns
that consume those handlers.
