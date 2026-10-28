# Audit readiness

## Current revision

The current source is the revision identified by [the snapshot manifest](audit/snapshot.json).
The primary audit and deployment target is the `eip170` profile (`contracts/profiles/eip170`,
37 deployment entries, table in `deployments/eip170.json`); the `glamsterdam` profile
(`contracts/profiles/glamsterdam`, 21 entries) is the maintained alternate. The profile is
selected by `scripts/select-profile.js`. The build uses Solidity 0.8.38 via IR with the
optimizer at 1000 runs and the Osaka EVM.

Properties reviewed at this revision:

- **RNG commitment.** Cohorts seal before a request; retries and coordinator re-issues replace
  only the transport request ID. The callback accepts only the coordinator and the retained
  nonzero low-64-bit request ID and records the raw word; nudges (`reverseFlip`) change only the
  coinflip word. Consumers derive values through tagged `RngTags` hashes of the raw word or of
  seeds already derived from it (for example foil-line and ticket-stream seeds, expanded
  deterministically); the coinflip win bit is the one raw-bit use
  ([RNG domains](audit/RNG-DOMAINS.md), [properties](PROPERTIES.md#rng)).
- **Progress.** The miner entry `mineRun(uint32)` persists cursors, bounds atomic work and
  reserves return gas. `dailyIdx` is the logical game day and advances at the daily VRF
  request. The purchase timeout is 30 completed game days (level 0 included, counted from the
  end of the Degenesis phase), and 14 days without a completed daily session end the game on
  the deterministic dead-VRF path even if the coordinator still answers.
- **VRF funding.** Requests are paid in native ETH from the coordinator subscription
  (`DegenerusAdmin.donateVrf` forwards the donation and credits one quarter of it as mid-day
  request credit); the coordinator can be replaced only through the emergency governance path.
- **Backing and accounts.** See [accounting](ACCOUNTING.md) and [architecture](ARCHITECTURE.md),
  with the storage positions of the current layout (`scripts/layout/golden`).

The [readiness record](audit/freeze.json) identifies the tested contract revision and lists the
remaining release checks: successful hosted CI on the final handoff commit, the 60-partition deep invariant
campaign (a scheduled or manual CI workflow) and the final audit tag.

## Preparation review — 2026-10-28

This is a readiness review, not an independent security audit. The preparation checks below ran
on the production contracts of `9f504b54911e60db1ca168965cdc8a15fe688815` and preceded the test
extensions recorded separately in `freeze.json`. The current scoped sources, identified by
[the snapshot manifest](audit/snapshot.json), include later contract changes; results in this
section and in `freeze.json` apply to the revisions they name. The items
below record verification gaps. The stETH balance-read failure behavior and its disposition are
in [Security](../SECURITY.md#external-dependencies-and-settlement). Broader effects are not silently accepted; see [Known Issues](../KNOWN-ISSUES.md).

Fresh local checks passed: 125 assurance self-tests, the production build in an empty
artifact directory, size limits for 41 deployment rows, source gates, top-level and recursive
storage layouts, owner/Vault action coverage and three deployment-configuration tests.
The focused stETH regression (`test/repro/V08StethDeadSweep.t.sol`) also passed. Source
hashes matched all 163 scoped files, and that preparation pass left contract/test sources
unchanged. These checks
are recorded separately from the earlier full battery in `freeze.json`.

### Verification and handoff issues

- **Hosted build gate failed before compilation.** [CI run 40620501086](https://github.com/PurgeGame/degenerus-protocol/actions/runs/40620501086)
  for `9f504b54911e60db1ca168965cdc8a15fe688815` ran the assurance self-tests before
  installing Solidity. Six tests failed with `solc is required for the recipient-call
  source gate`. The workflow checks source identity first and runs assurance tests
  after the production build installs the pinned compiler. A new hosted run is still
  required; local success does not repair the old run.
- **Full Foundry command needed per-group isolation.** The gas group requires isolation;
  the remaining groups use non-isolated execution in CI. The README and verification
  guide show separate commands. Bare `make test-foundry` does not choose this per group.
- **Native replay evidence is a separate handoff artifact.** The original recorder,
  capture logs, world-state dumps, matching artifacts and results have been recovered and
  packaged as `native-evidence-2026-10-28.tar.gz` (112,800,290 bytes). Its SHA-256 and
  provenance checks are in [the readiness record](audit/freeze.json). Supply this ignored
  archive alongside the repository; it is not downloaded by cloning. All 2,822 member
  hashes were verified, including bindings to the current production sources and retained
  runtime sets. The original 7,819-call runs were not rerun during packaging. See
  [consolidation tooling](../scripts/consolidation/README.md) and the archive's README.
- **Final freeze remains pending.** Deep invariants, hosted success on the final inputs
  and the final audit tag remain open in the readiness record. Source hashes alone do
  not close these items.
- **Dependency advisories require tooling triage.** `npm audit --json` on 2026-10-28
  reported 49 affected package entries (1 critical, 25 high, 10 moderate, 13 low).
  All are marked development dependencies in the lockfile. The critical entry is
  `handlebars@4.7.9` through `solidity-coverage -> sc-istanbul`, including
  [GHSA-8r5x-fm3f-whwj](https://github.com/advisories/GHSA-8r5x-fm3f-whwj).
  Advisory reachability in this project's tooling has not been established. The
  production-only npm audit reported zero, but Solidity build dependencies are also
  marked development dependencies, so that result is not contract-security evidence.
  Dependencies remain pinned; review compatible fixes and rerun the affected tooling
  before changing the lockfile. No automatic dependency upgrade was applied.

### Testing gap closure — 2026-10-28

The follow-up adds test and runner coverage while preserving the production contracts.
Results and exact evidence paths are recorded separately under `testing_gap_closure` in
[the readiness record](audit/freeze.json); they do not change the historical battery totals.

- The storage-reuse campaign targets the current implementation. Five clean baselines
  pass, and all eight deliberate faults fail their intended assertions. Compiler/setup
  errors cannot count as detecting a fault.
- Paid production lifecycles reach level 31 at default and minimum calibration. They check
  rewards against the real keeper ledger and reconcile actual FLIP holder balances before
  and after each call. An extra credited token is detected by the intended assertion.
- Native replay executes rejected player calls and checks the entire captured lifecycle
  under the transaction cap. It verifies fixture ETH as well as protocol balances and
  storage. The source-pinned inactive redemption-cache exception and the separate paid
  Foundry coverage are described in [the replay guide](../scripts/consolidation/README.md#capped-native-replay).
  Default and minimum calibration complete all 7,819 captured rows on both profiles.
  Constant maximum calibration refuses subscriber admission atomically at level 23;
  another caller using normal calibration recovers without changing the financial outcome.
  Two separately labelled maximum-with-normal-recovery campaigns also complete level 31,
  each checking all 6,523 checkpoints and 246 expected rejected player attempts.
- A composed mature-level test requires real repayment, seizure, live redemption, terminal
  ticket claims and individual sweep allocations. Its default/deep campaigns and negative
  controls are recorded with their exact source inputs.
- The deeper campaign exposed invalid purchase-coverage assumptions in the multi-level
  and whale/sybil handlers. Their first fuzzed steps require actual purchases and committed miner work;
  subsequent adversarial actions remain unrestricted. Required-prefix failures remain
  visible even when the fuzzer ignores reverting handlers. The original failing traces
  and corrected reruns are retained. All 34 multi-level and 21 whale/sybil tests pass in
  both default and deep campaigns.
- Funded subscriber tests check atomic refusal, actual share spending, retained membership
  and recovery by another keeper. The final isolated mock campaign passes 512 fuzz cases;
  pinned real Lido passes 1,028 gas/calibration points (537 refusals and 491 purchases).
  Another 627 cold native Geth probes cover funded mocks, including exact admission
  boundaries. No healthy-token gas-induced expiry was reproduced within these envelopes.
- Runner cleanup kills remaining compiler descendants on normal wrapper exit and
  interruption, and Linux runners wait for their exit before restoring source inputs.
  Regressions reproduce compilers surviving their parent process. All 154 assurance-tool
  checks pass on the final tooling revision.

The broad deep-invariant campaign remains in progress until its final result is entered
in the readiness record. No unfinished campaign is counted as passing. Constant maximum
calibration remains a preserved failed replay; the successful adaptive recovery campaigns
do not relabel it. Hosted release checks and the audit tag are separate outstanding items.

### Verification available for reviewers

All results below are for the contract revision named in the readiness record.

| Evidence | Result |
|---|---|
| Foundry, all groups | 6,715 passing executions, 0 failures, 2 optional skips (integration and gas suites with transaction isolation; mainnet-fork stETH and VRF suites at block 26,193,851) |
| Hardhat | 98 files, 1,557 passing, 0 failures |
| Invariants | 389 passing; default profile uses 256 runs × depth 128, with explicit per-property overrides |
| Halmos | 68 properties passing across 9 suites; not a proof of gas-metered liveness |
| Structural gates | 24 checks per profile pass on both profiles: sizes, storage layouts (top-level and recursive), owner and Vault action coverage, generated-file freshness and every source gate |
| Profile differential | 11 scenarios per profile, 0 differences; slot, payout, event and revert mutations detected |
| Native replay | Retained local result: 7,819 calls per profile on Osaka Geth, 0 failures; authenticated capture inputs are supplied in a separate archive (see preparation findings) |
| Slither 0.11.5 | complete parsing and SlithIR (459 contracts, 6,899 functions); detector output triaged in [analyzer triage](audit/ANALYZER-TRIAGE.md) |
| Aderyn 0.6.8 | 12 High and 25 Low categories, triaged in [analyzer triage](audit/ANALYZER-TRIAGE.md) |

The EIP-170 deployment's smallest runtime margin is 252 bytes; the alternate Glamsterdam
schedule's smallest margin is 69 bytes. These are measured build limits, not a claim that the
alternate schedule is available on the target chain. Reproduction commands and evidence
limitations are in [verification](VERIFICATION.md).

## DGVE owner governance

The [owner-governance guide](OWNER_GOVERNANCE.md) describes the escrow executor, voting
delegation, direct Vault gameplay and bounded creator icon setup, and [verification](VERIFICATION.md#focused-suites-by-area)
lists its focused suites.

## Degenesis sale — review scope

The seven-day Degenesis sale runs on logical days 2 to 8, before the main launch on day 9.

Surface:

- `DegenerusGameDegenesisModule` (delegatecall module, `GAME_DEGENESIS_MODULE`; in the `eip170` profile
  it is hosted by the `DegenesisFoil` deployment): the standalone `purchaseDegenesisBox`,
  `prepareDegenesis_g47` (split and pricing at the daily request), `runDegenesisWork_g1860`
  (the `DegenesisSettle` miner stage), `splitDegenesis` (terminal), `topUpSdgnrsAfking_g318` and
  `spendDegenesis` (the Vault's restricted purchase). See [architecture details](ARCHITECTURE-DETAILS.md#degenesis-sale).
- Storage: slot 0 byte 27 `degenesisClosed`, slot 12 `degenesisVaultBudget` and `degenesisOpenedAt`, slot 13 `degenesisCredit`,
  slot 20 `degenesisActive`, appended `degenesisWord` (slot 66), `degenesisDays` (67) and
  `degenesisOrders` (68). `Pool.Degenesis` is sDGNRS pool index 4 (10% of the initial supply).
- Credit accrual at the Mint, Whale, foil and purchase spend sites; credit is 25% of
  qualifying ETH, claimable and prepaid spend while the requested logical day is below 9, and
  the Vault and sDGNRS earn none.
- RNG: `degenesisWord` is copied in `_recordDailyRng`; new tags are listed in
  [RNG domains](audit/RNG-DOMAINS.md#degenesis-cohort-binding). Pricing inputs (volume, pool, orders)
  are fixed before the request.
- Daily engine: Degenesis days (indices 2..8) unlock randomness only (`STAGE_DEGENESIS_DAY`); both
  `lastPurchaseDay` latches require `day >= MAIN_LAUNCH_DAY` (9), keyed on the processed day. Craps
  windows and battle locks start on day 2 (`lockJackpotBattle` returns `bool`), and awarded seats start
  at `MAIN_LAUNCH_DAY`.
- Terminal: `splitDegenesis()` runs first in terminal setup; the Vault budget and sDGNRS AFKing funding
  leave `claimablePool` before `gameOver` is set (`DegenesisFundsReleased`); unresolved orders are
  forfeited with the inventory burn.
- Gas: `MineFlipGasBounds.DEGENESIS_*` constants; the `DegenesisSettle` stage admits per branch plus a
  growing flush reserve. See [verification](VERIFICATION.md).

Questions for review:

- Every order's reward is a pure function of the bound word and the frozen cohort; settlement
  order, chunking and caller gas cannot change it.
- The sum of sDGNRS awards in a cohort cannot exceed the `1.5Q` reservation, and `Q` never reads the
  live pool after pricing.
- Conservation: purchase, split, Vault spend, sDGNRS top-up and terminal release each leave
  `claimablePool` equal to the sum of claimable and prepaid balances plus the Vault budget and
  unsplit cohort volume ([accounting](ACCOUNTING.md#obligation-equation)).
- The level cannot advance before day 9, on any cranking schedule.
- The Vault cannot buy a Degenesis box through any path, and the restricted budget never becomes
  withdrawable; `spendDegenesis` buys only ordinary products, for any allocated recipient.

Unopened boxes are forfeited at game over and unspent credit has no value after the window; both are
disclosed in [economic disclosures](../ECONOMIC_DISCLOSURES.md). Its suites are listed in
[verification](VERIFICATION.md#focused-suites-by-area).

## Trust boundaries and release constraints

- **Unanswered VRF requests:** the vault owner may retry once after 20 hours;
  governance can replace a stalled coordinator under its voting rules (the owner path proposes
  after a 44-hour stall, the community path after 7 days with 0.5% of circulating sDGNRS). A
  request not published within 14 days ends the game on the deterministic path. Accepted
  on-chain answers cannot be replaced through the retry path. The callback still relies on
  the coordinator fulfilling each request only once; a duplicate authenticated callback can
  overwrite the retained word, as described in [Security](../SECURITY.md#vrf-callback-trust-and-request-ids).
  These powers do not prove resistance to a
  privileged party selectively rejecting an answer known before on-chain acceptance.
- **External asset availability:** required stETH transfers and VRF coordinator
  availability, with its native-ETH subscription balance, remain dependencies. Optional funding/individual redemption failure
  isolation does not make every protocol-level transfer failure ignorable.
- **Terminal treatment:** unfinished game entropy consumers have the ending treatment
  disclosed in [Economic Disclosures](../ECONOMIC_DISCLOSURES.md#game-over-treatment). Earned claims and paid terminal
  ticket obligations must retain their specified protections.
- **Deployment headroom:** the `eip170` profile exists because its deployments are sized
  against the 24,576-byte EIP-170 limit. Any source, compiler, optimizer, profile or
  address-pin change requires the production size and metadata gate again
  (`scripts/check-deployment-sizes.js`); test deployments with relaxed limits are not
  deployment evidence.
- **Evidence scope:** mock-based tests, bounded invariant campaigns and arithmetic
  models do not prove the behavior of external services or every possible state.
  Halmos does not establish production gas-metered FSM liveness: its unconstrained
  GAS model is unsuitable for that claim; the retained transition tests run in Foundry.
  Local results do not establish that remote CI ran successfully.

Review findings against [AUDIT.md](AUDIT.md), [SECURITY.md](../SECURITY.md) and
[Known Issues](../KNOWN-ISSUES.md). Accepted governance powers are distinct from authorization bypasses or unbounded payouts.
