# Test suite usefulness notes

These notes say which tests in `test/` are execution evidence for production behavior
and which are not. They do **not** establish that every assertion is correct or that
all protocol behavior is covered. Passing a model or source-text guard is not a
production execution proof. Run commands and results are in
[VERIFICATION.md](VERIFICATION.md); critical properties and their assertions are mapped in
[PROPERTIES.md](PROPERTIES.md).

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

The redemption property table, with each property's test functions, is in
[Accounting](ACCOUNTING.md#sdgnrs-redemption-properties). Fixtures are
`test/fuzz/helpers/RedemptionFixture.sol` and `test/fuzz/helpers/RedemptionCloseTools.sol`.

## Additional lifecycle and detector coverage

The multi-level invariant handler targets one `walk` entry. Its first invocation makes
three fuzz-dependent purchases and requires a committed `MinerWork` event after the real
level-10 opening. Later actions retain unrestricted purchases, mining, VRF responses and
time skips. A required-prefix error is stored and checked after the trace, so Foundry's
`fail_on_revert=false` cannot silently discard it; an unrestricted sequence of warps alone does
not guarantee three purchases. The post-opening thresholds remain enforced. Regression tests
check a one-warp trace, failed required calls, successful calls with no work, and later
unrestricted timeouts. The separate composed scenario below requires additional levels.

The whale/sybil handler also requires activity on its first `walk`: four distinct sybil
purchases, a seeded whale pass purchase, real spending and a committed miner step. Required
failures persist for the final assertion; later warps and adversarial actions remain
unrestricted. The original purchase and participation thresholds are preserved. Both
families pass their repaired default and deep campaigns (34 multi-level tests and 21
whale/sybil tests per profile); the original failing coverage traces remain in the evidence.
Other handlers retain their coverage guards. A trace rejected for insufficient activity
is a failed coverage check, not a passing financial safety result.

`test/repro/MatureComposition.t.sol` combines production-driven mature levels, pass-backed
loans, repayment and seizure, live redemption pricing, and the deterministic ending in one
scenario. Setup reaches level 10 through real purchases and mining. Each fuzz case must
then witness two further level transitions, both loan outcomes and a completed live
redemption before entering the ending with unfinished ticket work. Assertions reconcile
actual borrower/lender balances, reserve allocation, the queued holder's terminal claim and
withdrawal, and individual final sweep recipients. The global terminal pot and trait tally
are production quotes; this test does not independently reconstruct every trait's weight.
The expensive composed scenario uses 64 default and 256 deep fuzz cases.

`test/gas/NativePaidLifecycle.t.sol` runs the production level-31 census with cold isolated
calls capped at 16,777,216 gas including calldata intrinsic gas, a nonzero base fee and a
separate priority fee. Reward assertions use pre-call price/time/pass state, bound reported
work gas against an independent call measurement, and reconcile the keeper's actual
coinflip ledger. Actual FLIP holder balances must sum to supply before and after every
action; event amounts are not the supply oracle. Transfer events only discover candidate
holders, so logs retained from reverted child frames cannot create phantom supply.
This is paid Foundry lifecycle evidence; the native Geth comparison uses a zero-fee
reference and does not remove rewards from a paid state to force equality.

`test/gas/SubscriberAdmissionRecovery.t.sol` tests funded subscribers across caller gas
and calibration settings with cold transaction isolation. Refusals must roll back touched
storage, shares, rewards and membership, and an unrelated keeper must recover the pending
work. Accepted funding must spend real shares and retain the subscriber. Every probe must
reach refusal or funding within its call bound; a no-op cannot satisfy the test.
`test/fork/SubscriberAdmissionRecoveryFork.t.sol` repeats this against Lido at mainnet block
26,193,851 using funded shares and finite allowance: 1,028 gas/calibration points produced
537 atomic refusals and 491 funded purchases, with no membership loss. Both files require
`FOUNDRY_ISOLATE=true`. These bounded probes do not prove all future token implementations
or all gas values safe. The implementation's catch-all inner-pull failure policy remains
documented, and a caller-induced expiry with healthy stETH remains in scope.

The eight storage-reuse mutations in `scripts/audit/mutate-storage-reuse.py` target
`CoinflipCore.sol`. They exercise exact page tags, overflow retrieval, live-page reuse,
spill markers, claim writeback, and lost/doubled Vault backstop credit. Each selected
assertion has a clean baseline; a compiler error, setup failure, unrelated revert or
empty test selection cannot count as detecting a mutation. The runner records compiler
inputs and restores its disposable checkout. Its unit tests also check that a timed-out
compiler's descendants stop before source restoration.

See [the verification guide](VERIFICATION.md) for commands and
[the readiness record](audit/freeze.json) for completed campaigns and their limits.

## Rules for new or changed tests

Require a specific observable failure when the claimed behavior breaks. Assert the
fixture reached the intended state before checking it. Do not catch assertion
failures, silently skip fixture errors, compare an unsigned value with zero, or count
a setup-only check as a protocol property. Use `afterInvariant` and focused success
cases to establish meaningful activity; use a deliberate bad state or mutation where
an invariant's detector is subtle. Keep shared handler changes under the campaigns
that consume those handlers.
