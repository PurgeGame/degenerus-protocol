# Audit readiness

## Current revision

The current source is the revision identified by [the snapshot manifest](audit/snapshot.json).
The primary audit and deployment target is the `eip170` profile (`contracts/profiles/eip170`,
37 deployment entries, table in `deployments/eip170.json`); the `glamsterdam` profile
(`contracts/profiles/glamsterdam`, 21 entries) is the maintained alternate. The profile is
selected by `scripts/select-profile.js`. The build uses Solidity 0.8.38 via IR with the
optimizer at 1000 runs and the Osaka EVM.

Properties reviewed at this revision:

- **RNG commitment.** Cohorts seal before a request. The callback accepts only the
  coordinator, compares the low 64 bits of the request ID with the stored ID and records the raw
  word; nudges (`reverseFlip`) change only the coinflip word. Every other consumer hashes a
  unique `RngTags` domain with the raw word ([RNG domains](audit/RNG-DOMAINS.md)).
- **Progress.** The miner entry `mineRun(uint32)` persists cursors, bounds atomic work and
  reserves return gas. `dailyIdx` is the logical game day and advances at the daily VRF
  request. The purchase timeout is 30 completed game days (level 0 included, counted from the
  end of the Degenesis phase), and 14 days without a completed daily session end the game on
  the deterministic dead-VRF path even if the coordinator still answers.
- **VRF funding.** Requests are paid in native ETH from the coordinator subscription
  (`DegenerusAdmin.donateVrf` forwards the donation and credits one quarter of it as mid-day
  request credit); the coordinator can be replaced only through the emergency governance path.
- **Backing and accounts.** See [architecture](ARCHITECTURE.md), with the storage positions of
  the current layout (`scripts/layout/golden`).

The [readiness record](audit/freeze.json) identifies the tested contract revision and lists the
remaining release checks: hosted CI on the pushed commit, the 60-partition deep invariant
campaign (a scheduled or manual CI workflow) and the final audit tag.

### Verification available for reviewers

All results below are for the contract revision named in the readiness record.

| Evidence | Result |
|---|---|
| Foundry, all groups | 6,715 passing executions, 0 failures, 2 optional skips (integration and gas suites with transaction isolation; mainnet-fork stETH and VRF suites at block 26,193,851) |
| Hardhat | 98 files, 1,557 passing, 0 failures |
| Invariants | 389 passing at 256 runs × depth 128 |
| Halmos | 68 properties passing across 9 suites; not a proof of gas-metered liveness |
| Structural gates | 24 checks per profile pass on both profiles: sizes, storage layouts (top-level and recursive), owner and Vault action coverage, generated-file freshness and every source gate |
| Profile differential | 11 scenarios per profile, 0 differences; slot, payout, event and revert mutations detected |
| Native replay | 7,819 calls per profile on Osaka Geth, 0 failures |
| Slither 0.11.5 | complete parsing and SlithIR (459 contracts, 6,899 functions); detector output triaged in [analyzer triage](audit/ANALYZER-TRIAGE.md) |
| Aderyn 0.6.8 | 12 High and 25 Low categories, triaged in [analyzer triage](audit/ANALYZER-TRIAGE.md) |

The EIP-170 deployment's smallest runtime margin is 252 bytes; the alternate Glamsterdam
schedule's smallest margin is 69 bytes. These are measured build limits, not a claim that the
alternate schedule is available on the target chain. Commands to reproduce every row are in
[verification](VERIFICATION.md).

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
  `spendDegenesis` (the Vault's restricted purchase). See [architecture](ARCHITECTURE.md#degenesis-sale).
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
  `claimablePool` equal to the sum of claimable and prepaid balances plus unsplit cohort volume.
- The level cannot advance before day 9, on any cranking schedule.
- The Vault cannot buy a Degenesis box through any path, and the restricted budget never becomes
  withdrawable.

Unopened boxes are forfeited at game over and unspent credit has no value after the window; both are
disclosed in [economic disclosures](../ECONOMIC_DISCLOSURES.md). Its suites are listed in
[verification](VERIFICATION.md#focused-suites-by-area).

## Trust boundaries and release constraints

- **Unanswered VRF requests:** the vault owner may retry once after 20 hours;
  governance can replace a stalled coordinator under its voting rules (the owner path proposes
  after a 44-hour stall, the community path after 7 days with 0.5% of circulating sDGNRS). A
  request not published within 14 days ends the game on the deterministic path. Accepted
  on-chain answers cannot be replaced. These powers do not prove resistance to a
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
