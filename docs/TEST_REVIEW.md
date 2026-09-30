# Test usefulness review — 2026-09-29

Review baseline: `62e950c3c`. The initial `test/` tree contained 466 test files:
365 Foundry roots, 97 JavaScript files and four Python files, totaling about
173,500 lines.

This review inventories the whole tree, checks discovery and runner behavior,
screens assertions, skips, stale interfaces/storage, duplicated properties and
model-only tests, and runs the ordinary suites. It does **not** establish that
every surviving assertion is correct or that all protocol behavior is covered.
Passing a model or source-text guard is not a production execution proof.

## Repairs

| Area | Problem found | Change |
| --- | --- | --- |
| Discovery | All 19 statistical files were outside the default Hardhat selection. Several npm commands passed directory names that Hardhat could not load. | Include `stat`, use the maintained runner for `npm test`, expand focused npm commands to files, and fail discovery on unassigned JavaScript test files. Add an orphan-file regression for the runner. |
| Vault units | Share supply, allowance, authorization and ownership tests often checked proxies or merely that a call returned. | Assert the actual share contracts, genesis balances, strict >50.1% ownership threshold, real ETH/FLIP payouts, remaining reserves and unauthorized share minting. |
| Share fuzzing | `ShareMathInvariants` tested copied arithmetic, including a duplicate function and an unreachable refill sub-branch. | Fuzz the deployed vault: partial burn/preview agreement, two holders exhausting reserves, refill plus a second deposit, and ETH preference before stETH. |
| FLIP fuzzing | `FLIPInvariants` exercised a private mock with an obsolete initial allowance. | Use the deployed token for mint/burn, transfer, supply/escrow accounting and allowance exhaustion. |
| Stateful vault/levels | Nonnegative unsigned values, self-derived supply checks and incomplete deposit accounting passed without checking the advertised property. | Track burns/refills and both deposit sources; reconcile share supply; compare level with its observed high-water mark; include stETH in solvency assets. Add successful-action and deliberate-bad-state checks. |
| Redemption | Invariants read removed scalar storage slots or counters that were never updated. INV-05 duplicated INV-02 to inflate an attestation matrix. | Retain current solvency, wrapper, pool and supply checks. Keep exact per-day reservation/cap checks in `RedemptionAccounting`, with the duplicate removed. |
| Handler accounting | A successful no-op `openBoxes` call counted as a resolved Degenerette bet. | Count resolution only when a known live bet actually disappears. |
| Quest fixtures | A helper expected a return value from a now-void function, swallowed the resulting error and skipped. Constants still used a 200-FLIP reward and quest kind 0. | Read active quests, search deterministic seeds with isolated snapshots, require success, and use the current 100-FLIP reward and kind 9. |
| Ticket mixing | Lootbox fixtures probed removed getters and silently skipped; a second test could return before checking queue changes. | Reuse a daily-ready fixture, drive current box orders/RNG and require a ticket-producing result before checking queue accounting. |
| Other units | Leaderboard setup was reset by reloading its fixture; winner failures were swallowed. Referral, unwrap and post-game-over cases omitted their claimed checks. | Preserve leaderboard state, assert exact leading payout, resolve the default referral, check both token balance changes and require terminal errors. |
| Historical checks | Literal-only paper examples, permanently skipped old harnesses and file-vs-HEAD comparisons inflated the suite. The latter accepted any committed regression. | Retire them; preserve current contract-backed examples and useful structural guards. |
| Diagnostics | Three “exercised” invariants discarded getter results without asserting or printing them. | Remove those functions, preserving the real properties and `afterInvariant` activity requirements. |
| Reproducibility | Governance fixtures used `Math.random`; coinflip seed-search failure skipped a check. | Derive deterministic governance words and fail explicitly if a required coinflip seed is absent. |

The review does not change production contract logic or raise gas ceilings.

## Retired coverage and current counterparts

81 unconditional `vm.skip(true)` cases were removed from 13 Solidity files.
They executed no property before this cleanup. The table identifies current
counterparts, **not** a claim that every historical scenario has an exact modern
replacement. Git history retains the original bodies and skip explanations.

| Historical file | Cases removed | Current coverage / limitation |
| --- | ---: | --- |
| `AfKingFundingWaterfall` | 13 | `V56SubHardening`, `V56FreezeSolvency`: funded subscribe and debit/delivery accounting. |
| `V55SetMutationOpenE` | 9 | `V56SecUnmanipulable`, `V56SubHardening`, `V56AfkingGasMarginal`: current valve, finalize hooks and no-orphan checks. |
| `V56SecUnmanipulable` | 1 | Remaining hooks and grounded-subscription cases in the same family. |
| `AfKingConcurrency` | 9 | Current funded-subscribe/crossing/finalize behavior in the V56 suites. |
| `KeeperRouterOneCategory` | 2 | Current routing and open-leg behavior in `V56SubHardening` / `V56AfkingGasMarginal`. |
| `KeeperRewardRoutingSameResults` | 1 | Subscribe-time stamping replaces the obsolete first STAGE buy. |
| `KeeperNonBrick` | 13 | Current subscription, finalize/no-orphan and solvency suites. |
| `KeeperFaucetResistance` | 5 | Grounded subscription and current marginal gas tests; the retired ungrounded round trip is no longer constructible. |
| `V55FreezeDeterminism` (file removed) | 7 | `V56FreezeSolvency`: stamp-before-resolution and two-block determinism. |
| `RngLockDeterminism` | 14 | Five active legacy cases retained. Current commitment-binding, `RngWindowFreeze` and VRF suites cover related behavior; this is not 14 newly verified replacements. |
| `RouterWorstCaseGas` | 5 | `V56AfkingGasMarginal` and current keeper gas suites. |
| `OpenWalkCompositionGas` | 1 | Removed composition required both afking and human opens in one call, which the current valve excludes. Other measurements retained. |
| `KeeperLeversAndPacking` | 1 | Unified `openBoxes` coverage in `V56AfkingGasMarginal`. |

Also removed: the wholly vacuous `VaultShare.inv.t.sol`, 55 literal-only paper
cases, historical surface/file-identity checks, a permanently skipped obsolete
quick-play gas benchmark, and selected duplicate/no-op invariant functions.
`DustAccumulation` retains two arithmetic models; stale allocation examples,
a literal gas-profit comparison with an unused fuzz input and duplicate division
identities were removed. Model-only redemption/precision files are explicitly
identified as such.

## Remaining limits and maintenance rules

- Some JavaScript gas fixtures still cannot reach their target stages and report
  pending. `Phase261GasRegression` contains two disabled historical comparison
  cases. These are not gas coverage. Current Foundry cold gas gates run separately;
  small helper gas checks do not establish transaction-level ceilings.
- `LastPurchaseDayRace.test.js` retains three disabled historical reproduction
  cases. Its reachability rationale is not independently proved by this review.
  Keep them visible as unresolved coverage, not as passing regressions.
- Pure arithmetic/statistical models remain useful for distributions and bounds,
  but can drift from production. Pair protocol claims with a test calling the
  implementation or a checked differential harness. `PrecisionBoundary`,
  `RedemptionSplit` and some statistical suites belong in this category.
- Source-text guards check structure, not runtime semantics. Tests that merely
  print gas measurements are benchmarks, not ceiling gates. Halmos `check_*`
  functions are not executed as proofs by ordinary Forge runs.
- The five previously recorded Halmos timeouts and incomplete deep campaign in
  [VERIFICATION.md](VERIFICATION.md) remain unresolved. This review runs the
  default campaigns; it does not replace either job or remote CI.

For new or changed tests, require a specific observable failure when the claimed
behavior breaks. Assert the fixture reached the intended state before checking
it. Do not catch assertion failures, silently skip fixture errors, compare an
unsigned value with zero, or count a setup-only check as a protocol property.
Use `afterInvariant` and focused success cases to establish meaningful activity;
use a deliberate bad state or mutation where an invariant's detector is subtle.
Keep shared handler changes under the campaigns that consume those handlers.
