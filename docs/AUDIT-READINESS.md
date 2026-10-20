# Audit readiness — 2026-10-16

## DGVE owner governance — working-tree update, 2026-10-19

The escrow executor, voting delegation, direct Vault gameplay, and bounded creator
icon setup are newer than the frozen source below. The [owner-governance guide](OWNER_GOVERNANCE.md)
describes the authority changes, and [verification](VERIFICATION.md#dgve-owner-governance-2026-10-19)
records the current focused results and regression status. Historical freeze results
do not certify these changes.

## Degenesis sale — review scope (not in the frozen source below)

The seven-day Degenesis sale, its module and the supporting changes are in the working tree
after `audit-2026-10-16` and are not covered by that freeze. A later freeze supersedes the
section below once it records a battery on this source.

New and changed surface:

- `DegenerusGameDegenesisModule` (new delegatecall module, `GAME_DEGENESIS_MODULE`): the standalone
  `buyDegenesisBox`, `prepareDegenesis` (split and pricing at the daily request), `runDegenesisWork`
  (the `DegenesisSettle` miner stage), `splitDegenesis` (terminal), `topUpSdgnrsAfking` and
  `spendDegenesis` (the Vault's restricted purchase). See [architecture](ARCHITECTURE.md#degenesis-sale).
- Storage: slot 0 byte 27 `degenesisClosed`, slot 15 `degenesisVaultBudget`, slot 16 `degenesisCredit`,
  slot 26 `degenesisActive`, appended `degenesisWord`, `degenesisDays` and `degenesisOrders`.
  `Pool.Degenesis` is sDGNRS pool index 4 (10% of the initial supply).
- Credit accrual at the Mint, Whale and FoilPack spend sites; credit is 25% of
  qualifying ETH, claimable and prepaid spend while `block.timestamp < DEGENESIS_END_TS`, and
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
  growing flush reserve. See the [gas review](MINEFLIP-GAS-REVIEW.md) and
  [caller budgeting](CALLER-GAS-BUDGETING.md).

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
disclosed in [economic disclosures](../ECONOMIC_DISCLOSURES.md). Verification of this source is
recorded in [verification](VERIFICATION.md#degenesis-sale-verification).

## Frozen source — `audit-2026-10-16`

Annotated tag: `audit-2026-10-16`. Production source commit:
`1375c3e31` (full hash in [the freeze record](audit/freeze.json)). The full battery ran on
`ea41f2222`, which adds one test-only change (the redemption invariant suite fuzzes from plain
accounts) and re-pinned manifests. Tests written for the earlier gas limits were fixed
test-only in `e232c7d34` and `5963e7ba8`; every Foundry group and Hardhat were rerun in full on
those commits, and hosted CI ran on `5963e7ba8`. The tagged handoff commit adds this section
and the freeze record; `contracts/` is byte-identical across all of them. This freeze
supersedes `audit-2026-10-13` (production `dc4e48562`, section below). See
[the freeze record](audit/freeze.json) for hashes, per-group results and evidence identities.

Production changes since the earlier freeze (32 contract files):

- Loans. At the due level, a borrower whose own claimable winnings (above the sentinel) plus
  prepaid AFKing funding cover principal × (1 + 5% × term) repays automatically, claimable
  first; otherwise the account is seized as before, and an acquired account always defaults.
  A loan taken more than 20 days into a level's purchase phase pays half its principal, in
  whole tickets, as tickets at the live ticket level, priced and pooled like a ticket purchase
  with no affiliate, quest or activity credit; jackpot-phase loans stay all ETH. Interest and
  repayment run on the whole principal. The borrower chooses the amount, up to the quote
  (`borrow(id, dueLevel, amount, minEthOut)`); the whole account stays the collateral.
- Accounts. Every wallet ID starts with an unbacked 1-wei claimable sentinel that sits
  outside `claimablePool` and is never paid or spent. `Game.sweepAccounts` and
  `Vault.gameSweepAccounts` collect a subaccount's ETH and settled FLIP to its current owner
  (permissionless for sDGNRS-owned IDs), replacing `harvestAcquiredAccounts` and
  `Coinflip.claimAcquiredCoinflips`. A miner without a wallet ID runs the work unpaid, and
  `mineFlip` no longer registers miners.
- Fewer storage writes: the pending prize-pool word is folded but not zeroed at unfreeze,
  `jackpotWork` is retired by clearing its kind, BAF board lanes and settled redemption entries
  stay in place behind their bounds and cursors, and redundant RNG session-flag resets are gone.
- Coinflip claims walk one 730-day window that ends at the latest resolved day; older days
  forfeit. The separate first-claim window and the 1,460-day exit walk are gone, so an
  auto-rebuy backlog can no longer leave a claim acting on carry behind public results. The
  rolled carry clamps to `uint128` and banked balances saturate.
- Level quests: an active pass (a deity pass, or a lazy or whale pass covering the current
  level) qualifies with no ticket bought this level. Otherwise the account needs a whole ticket
  in this level's window and a live level streak of at least 5. The growth-bet reward shares
  this gate.
- The lootbox EV allowance is drawn once per order when the order opens, before any reward
  roll, against the live opening level; a purchase freezes only the score and modifiers. Box
  sizes still price at the stored purchase level.
- Game over closes AFKing deposits. A purchase that completes the primary `MINT_ETH` quest
  keeps the level mint streak when a secondary quest completes in the same call. The terminal
  tombstone saturates the vault allowance instead of reverting. The opening-day automatic
  Decimator entry is capped to the round's remaining 64-bit room.
- Mining admission bounds include Glamsterdam new-slot state gas without a reservoir
  ([calibration](VERIFICATION.md#glamsterdam-gas-calibration-2026-10-16)). Zero still selects
  10,000 bps, and callers may pass factors from 2,500. Solo ticket runs, growth-credit flushes
  and Craps settlement calls take at most 32 entries, recipients and seats. The forced atomic
  100-box order uses 12.88M gas, 6.76M of it state gas: the accepted exception to the 10M
  checkpoint target. The forced direct 32-winner jackpot round uses 9.77M.

Verification: the battery ran in parallel worktrees on `ea41f2222`: structural gates, Hardhat,
Halmos (56 properties), the mainnet-fork suite (16 tests), the 25 deep-invariant roots at 1,000
runs × 256 calls (294 tests; `LoanAccounting` is new), static analysis and the seven Foundry
groups. Every Foundry failure, and one Hardhat failure, was a test written for the earlier
limits or for the lootbox score before `235ececf2`; the other Hardhat failure
(`DefaultReferralCode`) timed out under host load. No contract changed. Worker allowances and
driver call caps were rescaled to the new admission bounds, and each rescaled schedule asserts
that it still splits or checkpoints; driven days now revert when they hit their call cap. Each
group was rerun in full on the fix commits and is counted only from that rerun: the standard
Foundry battery is 5,164 passing, 0 failing, 3 skipped over 30 batches, and Hardhat is 96 files,
1,650 passing (`dd225b060` removed five tests that could not fail and added three). The host
killed one Foundry lane at its memory cap (signal 9) during `repro-symbolic`; that group's count
is also from its full rerun. The structural gates passed again on `5963e7ba8`: deployment sizes
are tightest for CrapsBattle (24,482 bytes, 94 spare), the Whale module (102) and Game (210).
Hosted CI ran on `5963e7ba8` (run 38988401219) and every job passed; the deep and Halmos jobs
are push-skipped by design. Static analysis is compared by delta against the earlier tree
analysed in the same session: Slither 1,334 to 1,345 results across seven existing detectors
(the account sweeps, loan seizure and borrowing, two zero-initialised locals and the
module-storage false positive) and Aderyn 2,969 to 2,979 instances in the same 34 categories;
neither has a new category.

Insufficient caller gas for the first unit can still revert. No deployment, external audit
approval or absence-of-bugs claim is implied.

## Earlier freeze — `audit-2026-10-13`

Annotated tag: `audit-2026-10-13`. Production source commit:
`dc4e48562` (full hash in [the freeze record](audit/freeze-audit-2026-10-13.json)). The full
battery ran on `b06427257`, which differs from the production commit only in re-pinned manifests; the
Foundry groups that needed a rerun, the structural identity checks and hosted CI ran on
`6a960ddcd`, which adds one test-file fix and its manifest re-pin. The tagged handoff commit
adds this section and the freeze record; `contracts/` is byte-identical across all of them.
This freeze supersedes `audit-2026-10-12` (production `fd9d30f6f`, section below). See
[the freeze record](audit/freeze-audit-2026-10-13.json) for hashes, per-group results and evidence identities.

Production changes since the earlier freeze (16 contract files):

- The lootbox EV allowance is a two-tier taper per (wallet ID, level): the marginal bonus
  weight is 1 up to 10 ETH, falls linearly to 1/2 at 20 ETH and to 0 at 40 ETH. A box earns
  the integral of that weight over the spend it covers (`_lootboxEvEligible`), so splitting or
  reordering purchases cannot raise the total; usage lanes widen to 72 bits in the same slot.
  The Degenerette 50 ETH win ceiling is retired: a purchased win box resolves through
  `resolveLootboxDirect` on the shared allowance.
- The AFKing daily work writes less. `Sub.lastOpenedDay` is gone (a box is pending exactly
  while its stamp is the cohort's, the count is nonzero and the cursor has not passed it); the
  open loop stores its pending count once per call and the preparation stage releases
  `claimablePool` once per chunk. `createSmurf` appends each smurf to its main's packed
  `_smurfWords` list, so a seizure cancels the account's subscription and, for a main, every
  smurf's through `GameAfkingModule.cancelLiquidatedSubscriptions` with no per-subscriber
  acquisition poll. Self-claims pay `msg.sender` without re-reading the caller's wallet element.
- Account loans replace account sale ([ACCOUNT-LOANS](ACCOUNT-LOANS.md)). An account borrows
  against its far-future tickets: whole tickets at the due level + 2 and above are valued at
  10% of face two levels ahead, 5% at twenty and 2% at a hundred, with no randomness and a
  0.05 ETH minimum. sDGNRS lends, or the Vault when sDGNRS cannot fund it and fallback is
  enabled. Repaying before the due level costs 5% of principal per level used plus 1% per unused
  level of the chosen term, paid to the lender. Borrowing and repaying are deliberately not
  request-locked. The daily request that enters the due level arms the seizure of every unpaid
  loan due there; the mining engine runs it next (`MinerAction.SeizeLoans`) in metered chunks
  from a cursor, ahead of the wait for the word. A seizure gives the lender the account and a
  main's family, burns the borrower wallet's native sDGNRS, stops AFKing runs, and moves a deity
  account's soulbound pass through a game-only `DeityPass.seize`. Terminal handling outranks
  seizure, so at game over the borrower keeps the account. A main with more than five smurfs
  cannot borrow and cannot create smurfs while its loan is open. Storage: `_loans`,
  `_loansDue` and `_loansDueCount` take slots 80-82 and no slot moves.

Verification: the structural gates (production build, deployment sizes with Game at 24,294
bytes and 282 spare, storage-layout oracle, recursive layout check, the 11 source-drift gates),
Hardhat (96 files, 1,652 passing), Halmos (56 properties), the 24 deep-invariant roots at
1,000 runs × 256 calls, and the Foundry groups ran in parallel worktrees. The standard Foundry
battery is 5,038 passing, 0 failing, 2 skipped over 29 batches. Five Foundry batches were killed
by the compiler (signal 9, memory pressure) before any test ran, and `fuzz-2-03` failed on a
stale test: `JackpotCommitmentFreeze` expected `RngLocked` from `borrow`, which the loan design
does not gate. The probe now expects the lender-stage `Insolvent()` (test-only, `40c196818`).
Each affected group (`repro-symbolic`, `fuzz-2`, `fuzz-3`, `integration-gas`) was rerun in full
on the verified commit and is counted only from that rerun. Hosted CI ran on `6a960ddcd`
(run 38583216944) and every job passed; the deep and Halmos jobs are push-skipped by design.
Static analysis is compared by delta against the earlier tree: Slither 1,314 to 1,334 results
and Aderyn 2,460 to 2,499 instances, from the new loan, seizure and taper code, with one new
detector category (two write-after-write notes in the Lens views) and no new Aderyn category.

Insufficient caller gas for the first unit can still revert. No deployment, external audit
approval or absence-of-bugs claim is implied.

## Earlier freeze — `audit-2026-10-12`

Annotated tag: `audit-2026-10-12`. Production source commit:
`fd9d30f6fba04c54bd7be96f95f7c78584f9e098`, hosted CI on
`a5f93874974a170b625f2b7c8736bd6afcee7762` (the same sources with re-pinned manifests). The
tagged handoff commit adds this section and the freeze record; no contract differs from the
production commit. This freeze supersedes `audit-2026-10-10b` (production `8125d2e6a`,
section below). See [the freeze record](audit/freeze-audit-2026-10-12.json) for hashes and evidence identities.

The only change since the earlier freeze is comment corrections in `DegenerusGame`,
`DegenerusVault`, `CrapsBattle` and `DegenerusGameWhaleModule` (4 files, comments only):

- The VRF retry is 20 hours and has no early path; the Game's header and VRF banner said 12
  hours with a vault-owner early retry. The banner's lifecycle now names the real calls
  (`requestDailyRng`, `rawFulfillRandomWords`, `publishRng`, `_unlockRng`).
- The growth-bet market has no RNG-lock restriction. The stake burn's FLIP top-up is
  ungated because it reaches only settled claimable winnings, not the auto-rebuy carry.
- A craps battle entry is binary: one copy of the run or exactly the field's high-roller
  multiple. The Vault's `crapsEnterBattle` documented a nonexistent range.
- The sDGNRS whale award is admitted by its caller against `SUBSCRIBER_WHALE_GAS`; the
  comment described a retired per-stage weight. Two comments no longer name symbols that do
  not exist.

Verification of this revision: the production build of the earlier freeze's tree and of this
tree produce identical runtime bytecode for every one of the 163 artifacts once the trailing
metadata hash is stripped, with identical deployment sizes (Game 24,467 bytes, 109 spare).
The audit-snapshot identity, storage-layout oracle, recursive layout check and the 11
source-drift gates pass on this tree. Because the executable code is unchanged, the Foundry
(4993 passing), Hardhat (1652), deep-invariant (24 roots at 1,000 runs × 256 calls) and
Halmos (56) results recorded for the earlier freeze, and its static-analysis comparison,
carry forward without a rerun. Hosted CI ran on this revision (run 38335169021) and every job passed; the deep and Halmos jobs are push-skipped by design.

Insufficient caller gas for the first unit can still revert. No deployment, external audit
approval or absence-of-bugs claim is implied.

## Earlier freeze — `audit-2026-10-10b`

Annotated tag: `audit-2026-10-10b`. Production source commit:
`8125d2e6a0a4000734bea9944c2a9d366133a3de`. Verified commit (every local lane and hosted CI):
`5a24042c06656d57695bb0f531600341e86e113d`, which differs from the production commit only in
documentation and re-pinned manifests. The tagged handoff commit adds this section and the
freeze record; no contract differs from the production commit. This freeze supersedes
`audit-2026-10-10` (production `69c67918c`, section below). See
[the freeze record](audit/freeze-audit-2026-10-10b.json) for hashes, per-group results and evidence identities.

Production changes since the earlier freeze:

- The Vault, not CREATOR, holds the creator-side allocations. `DGNRS` mints its initial 50B
  to the Vault, and every level-vested release pays the Vault; `claimVested` is
  permissionless, and `unwrapTo` accepts only the Vault. The Vault owner burns wrapped DGNRS
  through `dgnrsBurnWrapped` (an in-game claim or the post-game-over payout lands in vault
  reserves) or unwraps it through `dgnrsUnwrapTo`. The initial DGVE/DGVF supply stays with
  CREATOR because it is the vault ownership.
- `Icons32Data` setters and `finalize` follow `isVaultOwner` (`NotVaultOwner`) instead of
  CREATOR, so cosmetic control moves with DGVE ownership. `initProtocolDeity` stays
  CREATOR-gated at level 0 and grants CREATOR no allocation.
- The closing box of the sale burns the remaining sale-pool balance instead of paying it to the
  closing buyer; the Degenesis closing burn (`DegenesisInventoryBurned(uint256)`) is the current form.
- Comments and naming say miner, not keeper (`_keeperSlot` is `_minerSlot`; the layout
  goldens follow). Game stays 24,467 bytes (109 spare); Vault 11,922; DGNRS 4,735.

Verification of this revision:

| Selection | Verified result |
| --- | --- |
| Foundry standard groups | 7 groups; 4993 passing executions, 0 failures, 2 skipped |
| Hardhat | 96 files; 1652 passing tests, 0 failures |
| Deep invariants (1,000 runs × 256 calls) | 24 roots; 0 failures |
| Halmos | 56 passing properties |
| Split arithmetic | tests and exact check pass |
| Hosted CI (run 38092026845) | every job green; deep and Halmos jobs are push-skipped by design |

All lanes ran on the verified commit in parallel worktrees. The deep sweep kept the existing
inline overrides (AnyInputSafety 256 × 128, SeatCap 64 × 64); AdvanceLiveness completed
256,000 calls. Counts are runner executions and may include inherited suites; the two
optional archived-runtime comparisons are skipped because their historical fixtures are not
configured. Production build, deployment-size, storage-layout, recursive-layout, interface and
source-drift gates pass.

The change needed test updates, not contract fixes: fixtures now take DGNRS from the Vault,
and the closing-box tests assert the burn. `DgnrsWrapperPaths` gained five tests (the Vault
holds the allocation; the owner unwraps only through the Vault; the Vault burns wrapped
DGNRS in game and after game over; icon control follows DGVE ownership), and its vesting
test now releases from a stranger's call and checks that only the Vault is paid.

Static analysis is compared like for like against the earlier freeze with the same tool
versions. Slither 0.11.5 reports 1313 → 1314 results: one note is added for the ignored
return in `DegenerusVault.dgnrsBurnWrapped`, the same pass-through shape as `sdgnrsBurn`.
Aderyn 0.6.8 reports the same 34 categories (2457 → 2460 instances): three reentrancy-order
notes in `Icons32Data` (its read-only owner check precedes its writes) and one more
contract-name-reuse instance; two reentrancy notes in `DGNRS` disappear. Alerts are
retained and triaged by delta, not represented as zero findings.

Insufficient caller gas for the first unit can still revert. No deployment, external audit
approval or absence-of-bugs claim is implied.

## Earlier freeze — `audit-2026-10-10`

Annotated tag: `audit-2026-10-10`. Production source commit:
`69c67918c74b2c301c702f1843d8850ab47bca50`. Final test inputs:
`75d95953ffdb6abfb94de37a040001b240fa9ca2`. The hosted CI commit
`40cad24c10818f30e02d884fceee2d86c6e918a1` and the tagged handoff commit change
documentation and freeze records only; no contract differs from the production commit.
This freeze supersedes `audit-2026-10-09` (production `97c58a8fd`, section below). See
[the freeze record](audit/freeze-audit-2026-10-10.json) for hashes, per-group results and evidence identities.

Production changes since the earlier freeze:

- `1a540f2ed` separates mineFlip RNG request admission budgets: 400k for a mid-day
  request, 1.5M for a daily request, plus 300k only when a nonempty redemption batch
  must close. The terminal allowance (2.5M) is unchanged.
- `69c67918c` keeps the mineFlip gas reserves after the first unit. The floor always
  holds every ancestor's return tail: the first unit may run below it and later units
  must fit above it again, so a call whose first unit fits does not revert for gas.
  Liquidating a smurf account burns no sDGNRS (a main-account sale still does), and its
  payment tries ETH then stETH. Dead code and stale comments were removed
  (`settleGrowth`, `CrapsEngine.settleRanked`, unused `MineFlipGas` helpers and
  zero-allowance guards).

Verification of this revision:

| Selection | Verified result |
| --- | --- |
| Foundry standard groups (final tree) | 7 groups; 4988 passing executions, 0 failures |
| Hardhat | 96 files; 1651 passing tests |
| Deep invariants (1,000 runs × 256 calls) | 24 roots; 0 failures |
| Halmos | 56 passing properties |
| Split arithmetic | tests and exact check pass |
| Hosted CI (run 38005026482) | every job green; deep and Halmos jobs are push-skipped by design |

The deep sweep ran locally with the existing inline overrides retained (AnyInputSafety
256 × 128, SeatCap 64 × 64); the long AdvanceLiveness root completed 256,000 calls. Foundry
groups ran on `e9ebb21d9`, with `fuzz-1` rerun on the final test inputs; Hardhat and the
deep sweep's AdvanceLiveness root ran on the production commit, and the one repaired
Hardhat file was rerun with its final content. Counts are runner executions and may
include inherited suites. Two optional archived-runtime comparisons are skipped because
their historical fixtures are not configured. Production build, deployment-size, storage
layout, interface and source-drift gates pass.

Verification found four stale test expectations; no contract changed. The request budgets
made a mid-day request fit inside gas figures that previously could not admit it
(`PreJackpotNextLevelMint`, `CrapsArmRequestBatching`: now deferred by maximum
calibration); the minimum-allowance far-future drain may now clear a single entry per
call, so its chunk-count guard is bounded by queued entries (`AdvanceGameGas`; a realistic
10M call still finishes in three and the heaviest chunk is unchanged at 638k gas); and a
cache test's durable-history mask was wider than the contract's (`ActivityAffiliateCache`,
a pre-existing mismatch found by the fuzzer, now with a deterministic regression).

Static analysis is compared like for like against the earlier freeze's commit with the
same tool versions. Slither 0.11.5 reports 1314 → 1313 results: four findings on deleted
dead code disappear and two notes appear for the `redemptionBatchState()` view read in
`mineFlip`. Aderyn 0.6.8 reports the same 34 categories (2462 → 2457 instances). Alerts
are retained and triaged by delta, not represented as zero findings.

Insufficient caller gas for the first unit can still revert. No deployment, external audit
approval or absence-of-bugs claim is implied.

## Earlier freeze — `audit-2026-10-09`

Annotated tag: `audit-2026-10-09`. Production source commit:
`97c58a8fdf9a0cf464abe71176a1670e02c28b67`. Verified final test/build inputs:
`97c58a8fdf9a0cf464abe71176a1670e02c28b67`. Final handoff changes after this revision are
documentation and freeze records only. See [the freeze record](audit/freeze-audit-2026-10-09.json)
for source hashes, every selected root, per-run results and evidence identities.

Verification combines the [standard hosted run](https://github.com/PurgeGame/degenerus-protocol/actions/runs/37936049839),
the [deep/symbolic campaign](https://github.com/PurgeGame/degenerus-protocol/actions/runs/37929240395), the
[final-source CI](https://github.com/PurgeGame/degenerus-protocol/actions/runs/37964801163) and full-budget local
replacement runs. The hosted histories retain these resolved issues:

- The original Hardhat vector-generator check lacked Python's `sha3` module.
  CI now installs `safe-pysha3==1.0.5` using Python 3.12, and the complete
  Hardhat selection passes in the later hosted run.
- The V61 stETH-cover-buy scenario crossed a day boundary without completing
  daily processing. The ordered subscription lock correctly rejected it with
  `RngLocked()`. Its setup now calls the real miner/VRF sequence through a
  disjoint actor before taking financial baselines. Every original purchase and
  solvency assertion remains. The entire affected five-root standard batch and
  the full deep V61 root pass on the corrected inputs.
- The cold Decimator plan/frame witness measured 60,298 gas against a stale
  60,000 estimate. The final production revision raises only that estimate to
  65,000. The entire affected cold batch passes all 72 tests, retaining every
  original assertion. The witness already completed under the separate tail
  reserve; no out-of-gas failure was observed.
- The hosted deep AdvanceLiveness job exceeded GitHub's 5½-hour execution limit.
  Its partial artifact is retained as incomplete evidence, with no reported test
  failure. The full-budget local run on the final source supplies that root's
  successful coverage; no run or depth budget was reduced.

The broad regression baseline is `40fbc58eb649d713e7802ce09fd0bf0e7b1e8458`.
Between the hosted baseline and the V61 replacements, only that scenario changes;
retained Foundry selections exclude it and no other Solidity source imports it.
The subsequent production change is limited to the Decimator estimate. Final-source
checks include all 96 Hardhat files (1651 passing tests),
all four fuzz groups, the repro-symbolic group and the full cold integration/gas
suite (1547 passing executions), plus 21 targeted Foundry roots
(201 passing executions), the complete deep
AdvanceLiveness root, and production gates. Bytecode comparison isolates
the larger admission operand in each affected module, with expected jump-address
relocation; all other production executable bytes match after metadata removal.
This is broad baseline coverage plus targeted final-source verification, **not a
complete Foundry full-suite rerun on the final constant**. The record retains exact input
identities and admits no unexplained failures or reduced fuzz/invariant budgets.

To complete the hosted queue sooner, 16 deep roots also ran locally
at the unchanged deep budgets. Complete all-tests root selections cover all of
their planned partitions. The record counts each physical selection once and
retains the actual hosted job status, including any cancelled duplicate work.
The configured deep campaign is 1,000 runs × 256 calls per run, with the existing
inline overrides retained: AnyInputSafety uses 256 × 128 and SeatCap uses 64 × 64.
The record includes the executed run/call totals for each invariant property.

| Selection | Verified result |
| --- | --- |
| Foundry warm | 412 roots; 3887 passing executions |
| Foundry cold integration/gas | 134 roots; 1547 passing executions |
| Deep invariants | 41 planned partitions covered across 24 roots; 214 passing executions |
| Hardhat | 96 files; 1651 passing tests |
| Halmos | 56 passing properties |
| Split arithmetic | 24 passing checks |

The table combines the recorded baseline and replacement revisions above; it is
not a claim that every row ran on the final source. Counts are runner executions
and may include inherited/imported suites. Recorded
skips total 2; their exact identities are in the freeze record. The skips are optional archived-runtime differential tests for growth foil and subscription transitions; their historical-runtime fixtures are not configured in these runs.
Production build, deployment-size, storage-layout, interface and source-drift
gates also pass. Local assurance-tool checks pass 60 unit tests and six partition
tests. Static analyzers completed; their alerts and bounded triage are retained,
not represented as zero findings. The prior interrupted freeze is historical
evidence only.

The candidate retains caller-calibrated `mineFlip(uint32)` batching, boxes-first
AFKing processing and the 300,000-gas VRF callback allowance. Repriced-client stress
replays cover 33 fixtures; each selected peak succeeds with 10M supplied gas. The
largest measured gross peak is 7,931,562 gas. These samples are not exhaustive
upper bounds or promises about final fork rules. Direct VRF callback tests use
about 35.1k gas including standalone transaction overhead and exclude real
coordinator proof verification/billing.

Insufficient caller gas can revert. The first mandatory checkpoint is attempted
regardless of conservative admission estimates; optional continuation work uses
the caller multiplier. No deployment or external audit approval is implied.

## Earlier campaign: review subject and status

Base revision: `98cd2a781c1ce328362351ca9a0761e41e50eea1`, plus the verification
repairs recorded in that campaign's local input manifests. The current snapshot
manifest has since advanced and must not be used to identify this earlier run.
Priorities are RNG commitment integrity, continued progress without an
attacker-induced permanent revert, and protection of ETH/stETH and account data.

**Local campaign complete — 2026-10-08.** The configured selections and repaired
fixtures have completed, including all 24 deep invariant roots. No selected-test
failure remains unresolved. This is a bounded internal review; remote CI,
production deployment and an unconditional security guarantee are not established.

**Two WhaleSybil counterexamples classified as test-oracle errors:** the original campaign saved
47-call `invariant_obligationRatioHealthy` and 51-call
`invariant_solvencyUnderPressure` sequences. Exact finite replays first fail the
ETH-only check at actions 45 and 50 (zero-based), respectively, after automatic
staking. In each state, Game-held ETH plus stETH equals the unchanged 168 ETH of
obligations exactly. The test omitted stETH backing; production surplus accounting
already includes it. Both exact replays now pass, including independent one-wei
ETH and stETH shortfall controls. All five repaired WhaleSybil invariants pass
1,000 runs and 256,000 handler calls each, with zero handler reverts reported.
Preserved inputs and SHA-256 hashes remain recorded in
`.audit-test-logs/readiness-2026-10-08/provider-checkpoint.json`; baseline replay
evidence is under `whale-counterexample-replay/20261008T102434.557048Z-d494e69c/`.
The passing closure run is
`whale-final-deep/20261008T105734.694153Z-33d9fee3/` (13 executions, zero failures).

## Earlier campaign: security conclusions

The source review and focused adversarial reviews found no confirmed ordinary-player
exploit that rerolls a committed result, permanently bricks `mineFlip`, steals
backing, or obtains another account's authority. This is a bounded review conclusion,
not a proof of absence. The additional broad campaigns below test that conclusion
against the repository's complete configured selections. The detailed RNG/mineFlip
review remains local at `docs/audit/rng-mineflip-2026-10-07/REVIEW.md`; this public
handoff summarizes its conclusions and executable coverage below.

| Property | Protection reviewed | Relevant executable coverage |
| --- | --- | --- |
| RNG commitment | Seal cohorts before requesting; authenticate coordinator and active request ID; retain an accepted word; drain read consumers before admitting another request. Seeds use committed IDs/positions, not the settling caller or remaining work. | RngStructuralLivenessReview, RngWindowFreeze, RngIndexDrainOrdering, CrapsRngSeal, PostRequestOutcomeControls, ticket schedule differential tests. |
| Progress | Persist cursors and bound atomic work; reserve nested-call and return gas; keep gas failure distinct from semantic failure; use terminal recovery for unavailable entropy. Ordinary mandatory prize credits do not call arbitrary player receivers. | AdvanceLiveness, AnyInputSafety, NativeAtomicWork, MineFlipWorkerBudget, cold integration/gas selection and terminal regressions. |
| Backing and exactly-once payment | Debit liabilities before transfers, preserve closed/parked redemption reserves, fix redemption payees, isolate failed individual redemptions, and transfer stETH before an untrusted ETH callback. | EthSolvency, PoolConservation, RedemptionInvariants, VaultShareMath, redemption ordering/reentrancy and reserve regressions. |
| Account isolation | Resolve and authorize the selected ID; retain root/child identity on acquisition; revoke former authority through ownership checks; authenticate reused packed records and clear only intended lanes. | WalletIdTruth, IdAuthorizationReview, AccountLiquidation, IdEntryPacking, CrapsAccountsProtocol and recursive storage-layout comparisons. |

The RNG comparison follows the owner's requested equivalence: ETH and equal-value
lootbox compensation count as the same outcome; an unchanged percentage entitlement
counts as unchanged when its pool balance moves. Winners, spins, traits and payout
percentages/multipliers must still respect their commitments. Previously accepted
soft EV-allowance timing remains a gameplay rule. These exceptions do not authorize
arbitrary post-request selection or diversion of payment.

## Earlier campaign: verification repairs

The 2026-10-08 readiness pass changed tests, assurance gates, scope and
documentation; it did not change production Solidity behavior. The later
Decimator estimate correction is recorded in the current freeze section above.

| Gap | Correction and reason |
| --- | --- |
| Scope manifest omitted `ILiquidation.sol` | Include the production interface so a clean snapshot covers all 84 production Solidity sources. |
| Seven JavaScript redemption tests burned below the current 0.01 ETH admission minimum | Use funded, admissible burns, assert the preview meets the minimum, and retain the balance/supply checks. Seed Game claimable through its authenticated payable hook instead of manually writing liabilities. Both affected files pass: 79 tests. |
| AnyInputSafety setup lost its simulated sDGNRS caller | Resolve the wallet ID before the one-shot prank; assert that the backed bystander claim exists. Previously the view lookup consumed the prank and the authenticated funding hook correctly reverted. |
| Shared ticket-queue oracle rejected valid acquired accounts | Recognize a sold root and children that retain their original parent, validate the reserved buyer and its registry, and follow both payee links. Keep malformed-owner detection with seven explicit sensitivity controls and a real-liquidation regression. The repaired AnyInputSafety campaign passes 64 runs × 100 calls. |
| WhaleSybil solvency checks omitted stETH backing | Count only Game-held ETH plus configured stETH in current solvency, historical coverage and terminal claimable checks. Preserve every obligation term and queue assertion. Both exact saved replays pass; each independently removes one wei of ETH and one wei of stETH to verify that the exact oracle and handler ratio detect a real deficit. All five invariants pass their full deep budgets. |
| NativeAtomicWork used obsolete FLIP units | Mint and compare whole FLIP units. The old ether-scaled subtraction could make the surviving-payout assertion pass without a payout. |
| Jackpot gas witness decoded the retired per-seat storage format | Read the correct recycled key and 72-bit seat lane; authenticate the full day and compare the 32-bit owner. All three cases pass with unchanged payout/order/completion checks and 10M allowances; the largest measured call is 6,276,417 gas for the 500-seat field. |
| BAF test books still wrote one interval per storage word | Pack both 128-bit lanes and validate every seeded entry through the production getter. Keep the requirements that every intended award is filled and that allowance partitions preserve the full payout transcript. All seven affected roots pass warm (120 executions). All three gas roots pass cold: century consolidation (28), BAF award groups (14), and pool consolidation (7). Exact-path reruns avoid repeating imported suites. |
| Craps gas sample mixed warm and cold execution | Retain the 212,000 warm regression bound. In both modes require the measured seat to fit the unchanged production reserve with a 20% margin. The cold witness was about 244,500 gas. Both modes now pass. |
| Isolated constructor test collided with an etched contract address | Deploy the production constructor at a distinct CREATE2 address, then install the read-only test surface. The constructor assertion passes warm and cold without changing code-size or gas ceilings. |
| Symbolic checks omitted non-assertion Solidity panics and had stale whole-FLIP assumptions | Check all panic codes, correct the boon-cap units, and use solver-specific arithmetic proofs, an asserted multiplication lemma and exhaustive production-price cases. No input domain is reduced. The complete final Halmos selection passes: all 56 properties, with every panic code checked. |
| Symbolic storage proofs used a layout model that rejected parity-selected Yul slots | Use Halmos's generic storage model for this suite and construct the reference owner's eight lanes with disjoint shifts. All 16 properties pass over their original domains with all panic codes enabled. |
| Earlier focused reviews exposed stale redemption/packed-field fixtures | Bring burns above the admission minimum; read Craps flags from their current position and assert that the owner ID survives the packed update. Preserve the added RNG and unauthorized-ID regressions. |
| Symbolic FSM exploration invented impossible gas readings | Halmos 0.3.3 represents each GAS opcode as an unconstrained `f_gas` value. Saved counterexamples include 2²⁵⁵ gas and nonphysical changes between reads. Retain all three production carriers as real-EVM fuzz checks and add all 16 explicit day/gap boundary cases; they pass with 1,000 fuzz cases each. The separate arithmetic model contract remains symbolic. This removes an unsupported proof claim, not the executable transitions; formal gas/liveness verification remains a limitation. |
| Sentinel accounting model could panic in its assertion | Reconstruct the original pool with `poolAfter + (amount - 1)` instead of subtracting `amount` before adding the sentinel. Replay the reported boundary and retain all valid inputs. Express the Decimator partition guard without an overflowing addition. Production accounting is unchanged. |
| Quadrant payout oracle omitted gold-six solo priority | Apply the existing production rule before the ordinary gold-quadrant tie-break and preserve the saved fuzz counterexample as a regression. The corrected reference still checks every recipient count, ETH/pass allocation and pool-conservation equation; the full affected file passes. |
| Additional century/wrapper burns were below admission value | Fund admissible burns while retaining odd raw units, pool-refill conservation, wrapper equality and pending/settled redemption assertions. Century cases pass warm and cold; the raw-unit wrapper case also passes. |
| Empty advance became too cheap to test a positive miner reward | Queue four real purchases before requesting the day. Retain the assertions that work exceeds the unpaid first million gas, the reward is positive and exactly one miner credit is emitted. All 11 file tests pass. |
| Century seed microbenchmark used its warm cap for isolated transactions | Retain the 15,000 warm cap and bound isolated calls at 40,000 including transaction/cold-access overhead; the failure measured 34,680. Record storage accesses and require every write to be the packed seed word. All file tests pass warm and cold; the production transition reserve is unchanged. |
| Jackpot draw tests assumed one checkpoint per transaction | Keep the existing gas and no-settlement guards, allow multiple admitted 50-entry checkpoints, and assert per-call progress, whole-group increments and target limits. Stop precisely when the field seals before testing settlement replay. All 11 cases pass warm and cold. |
| Automatic whale-purchase fixture treated the packed registry as one ID | Decode its low 32-bit gameplay ID; the upper identity field is not part of the mapping key. All 15 automatic-purchase tests now reach their intended budget, boon, ticket and reward assertions. Production decoding was already correct. |
| Banked-FLIP gas fixture keyed state by address | Seed the registered wallet ID and assert the bank is visible through the production getter. All 24 customer-followup tests pass cold. |
| Redemption determinism fixture discarded every burn input | Transfer existing pool tokens, fund admissible burns over the original range and assert admission. Compare the original batch's resolved roll, payout and exactly-once claim after consumers drain; a later batch can change global reserves after a day warp. Preserve the saved day-warp counterexample. The affected file passes, including the full fuzz campaign. |
| Terminal redemption fixture burned below admission value | Raise the seeded and burned amount together, assert its backing preview, and retain the pending-ending and terminal-payment checks. |
| Multiway split bit-vector proofs exceeded solver budgets | Retain the Solidity formulas and production bucket library as bounded fuzz carriers, and prove their integer arithmetic with explicit checked-overflow bounds in a separate fail-closed Z3 gate. Authenticate the production library and Solidity carrier source files so code changes require model review. All original admitted amounts, BPS splits, counts and remainder indices remain in the proof domain. |
| Three redemption gas cohorts used an obsolete token-unit minimum | Derive the minimum burn from current backing with the existing fixture helper and assert admission. Retain the 45-beneficiary drain, a maximum beneficiary in the middle of a mixed cohort, and the unchanged 500,000 / +5,000-gas checks comparing 2 versus 2,000 claims. All 17 affected-file tests pass cold. |
| Redemption accounting's random seed never admitted its intended claim | Give handler actors useful balances above the admission boundary, choose an admissible initial burn, and require a successful submission and tracked batch. Also fund and register the shared handler's actors in RedemptionInvariants. Both suites now start with a real claim; explicit lifecycle tests require settlement, alongside the existing supply/reserve checks. All 22 cold executions pass, as do both repaired suites at the deep 1,000-run × 256-call budget. |
| Build cache could regard fixture-pinned default artifacts as current | Use separate production artifacts and cache in the documented build and CI. Keep the strict metadata/source check; it rejected the stale local artifact before the fresh production build passed. |
| CI only checked shallow storage goldens | Also compare full recursive compiler layouts for all 16 Game modules and the CrapsBattle/JackpotBattle pair. |
| Serial CI campaigns placed unrelated properties behind one timeout | Run the seven Foundry groups separately and dynamically enumerate every deep invariant root. Split the three expensive Craps suites by named property, with a complementary job retaining every other or inherited test. Preserve budgets and require both production gates and every ordinary test group through the original aggregate check name. Local validation covers all seven groups and an exhaustive 41-job deep partition over 24 roots, with six partition unit tests. Remote CI is not yet evidenced. |
| Audit documentation omitted delayed RNG retry authority | Document the 20-hour owner retry and its trust limitation. The subsequent freeze pass also reconciles gas wording with available-gas admission; production reserves and fixture bounds are retained. |

## Earlier campaign evidence

Local logs, source identities, exact commands and tool versions are generated under
`.audit-test-logs/readiness-2026-10-08/`. Runners use isolated checkouts, authenticate
the compiled inputs, retain failed batches and restore address pins. Repeat the
commands in [VERIFICATION.md](VERIFICATION.md); generated local logs are not shipped
as a substitute for reproducible tests.

| Check | Earlier campaign result |
| --- | --- |
| Assurance-tool unit tests | 67 passed: 57 runner/snapshot tests, six deep-partition tests and four split-proof gate failure-mode tests. |
| Ten source-drift gates plus interface coverage | Passed. |
| Production build and deployment sizes | Passed for all 37 deployment entries. Game: 24,532 bytes (44 bytes spare); Whale: 24,504 (72 spare). |
| Storage goldens and recursive delegate layouts | Passed, including all 16 modules and CrapsBattle/JackpotBattle. |
| Complete Hardhat selection | All 95 files covered; latest results total 1,650 passed, zero failed/pending. Initial ten fixture failures are retained in the logs and superseded by passing reruns of the three corrected files. |
| Complete Foundry regression selection | All 20 regression batches completed: 3,327 initial passes and 24 fixture/model failures, each repaired with passing affected-file reruns. The stronger deep campaign is also complete. |
| Complete cold integration/gas selection | All seven batches completed: 1,452 initial passes and 24 fixture failures, each superseded by passing affected-file reruns. The 2-claim and 2,000-claim cleanup witnesses both measured 182,051 gas with the original limits retained. Counts are test executions; imported suites can repeat. |
| Symbolic arithmetic | All 56 Halmos properties pass in one complete run, checking every Solidity panic code. Two multiway split models use a separate exact-integer gate: 24 proof/non-vacuity/sensitivity checks passed, including uint256 bounds, all four remainder positions and empty-bucket refunds. Four gate failure-mode tests and the retained Solidity fuzz carriers pass. These are arithmetic model proofs, not bytecode equivalence. |
| Slither | Completed against a separate production build with full build information and ASTs; 327 contracts, 75 detectors, 1,343 alerts including inherited and supporting-code duplicates. Security-relevant alert classes are discussed below; this is not a zero-alert claim. |
| Deep invariants | All 24 configured roots covered at 1,000 × 256, with existing suite overrides retained. First five roots: 30 passes. Tail 19 roots: 119 passes and the two now-resolved WhaleSybil oracle failures. Repaired redemption and WhaleSybil/replay batches: 22 and 13 passes. Latest results across these batches: 154 distinct suite/test identities, all PASS, including 87 invariant functions and supplemental regression/helper tests. No configured root is missing. |
| Current source snapshot | Passed: all 84 production Solidity sources and current verification inputs match the refreshed manifest. Recheck after any further repairs. |

### Closure evidence and source currentness

`deep-closure.json` reconciles every deep suite/test result, including Forge's
multiline invariant failures, with the completed reruns. It preserves the two
original failures and links each to its passing result. The deliberate interruption
of the original driver's second batch occurred during compilation; the independent
tail campaign covered those roots. `failure-resolution-current.json` separately
maps all 48 initial ordinary/cold failures to passing affected-suite reruns.
`replay-authentication.json` verifies all 98 saved actions against the regression
source: identical senders, calldata and order, with no warp/roll metadata omitted.

All production Solidity remains identical to the reviewed revision. The final
WhaleSybil repair adds a backing accessor to the shared solvency test helper;
its pre-existing obligation, pending-pool and queue checks are unchanged. Seven
previously completed deep roots import that helper but do not call the new
accessor. Their evidence is retained with this reviewed source difference,
recorded in `deep-input-currentness.json`, rather than described as a fresh run
of identical compiler inputs. Changed redemption and WhaleSybil behavior has
dedicated passing deep reruns.

The final source gates again passed for all 137 registered VRF-word accesses,
325 taint sites, delegatecall/selector alignment and gas-read rules. The restored
production artifacts also pass all 37 deployment size/source checks. Exact commands
and outputs are retained in `closure-gates/`. No production source change,
commit, push or deployment was made to close this audit.

### Static-analysis triage

Slither is supporting evidence, not the acceptance oracle. Its input includes
imported test helpers; it reported an IR-generation warning for the test-only
`activityScoreOf` helper and completed successfully. The warnings and raw JSON
remain in the local evidence. No detector or source warning was suppressed in
production code to obtain a clean-looking report.

| Alert class reviewed | Disposition / verification boundary |
| --- | --- |
| Uninitialized state | The 177 alerts concern 73 declarations in the two shared storage bases. The analyzer treats delegate modules separately; initialization and writers live in Game/CrapsBattle or other modules, and some writes use assembly. Check the layout and writer gates plus runtime lifecycle tests, not module-local absence of an assignment. |
| Weak PRNG | Reported uses are timestamp window selection, packed lane/period indexing and arithmetic remainders. They do not replace committed VRF entropy. The separate request/consumer review is still required. |
| Incorrect shifts/exponentiation | Yul masks deliberately shift constant payloads; XOR selects the other binary slot. Packed-lane and recycling regressions exercise boundaries and neighboring-record preservation. Library/test-support alerts are distinguished from production. |
| ETH reentrancy and stale balance | Request/advance callbacks go to fixed modules, sDGNRS, stETH or the configured coordinator. User withdrawals debit/burn first and put the untrusted ETH callback after stETH delivery. Vault refreshes reserves after Game withdrawals. These conclusions retain the stated external-dependency trust assumptions. |
| Arbitrary ETH send | Private payment helpers receive authenticated/fixed payees from claims or share redemption. Permissionless settlement cannot substitute the caller's recipient. Reentrancy and liquidation tests cover the account/recipient transitions. |
| Delegatecall inside payable loops | Lootbox spin helpers target the fixed Degenerette module with explicit stake parameters. Funding is booked once at the authenticated outer redemption door; the nested helpers do not re-credit `msg.value`. |
| Packed encoding collision | The reported dynamic concatenation constructs an SVG, not an authorization or entropy commitment. |
| Assembly return / module-locked ETH | The jackpot facade intentionally returns its delegate's data; modules execute in the host's storage/custody context. Directly sending ETH to a module is not a supported deposit flow. |
| ERC20 interface | Reported `transferFrom` declarations are ERC721/seat interfaces and deliberately have no ERC20 Boolean return. |

The symbolic gas limitation is visible in Halmos's [GAS implementation](https://github.com/a16z/halmos/blob/v0.3.3/src/halmos/sevm.py);
the installed 0.3.3 source and saved SMT/model evidence were inspected directly.

Other alerts include event ordering, timestamps, zero-initialized accumulators,
integer rounding and fixed dependency calls in loops. The report is retained for
independent audit; detector severity alone is not evidence of an exploitable path.

## Trust boundaries and release constraints

- **Unanswered VRF requests:** the vault owner may retry once after 20 hours;
  governance can replace a stalled coordinator under its voting rules. Accepted
  on-chain answers cannot be replaced. These powers do not prove resistance to a
  privileged party selectively rejecting an answer known before on-chain acceptance.
- **External asset availability:** required stETH transfers and VRF/LINK service
  availability remain dependencies. Optional funding/individual redemption failure
  isolation does not make every protocol-level transfer failure ignorable.
- **Terminal treatment:** unfinished game entropy consumers have the ending treatment
  disclosed in [Known Issues](../KNOWN-ISSUES.md). Earned claims and paid terminal
  ticket obligations must retain their specified protections.
- **Deployment headroom:** Game and Whale are close to EIP-170. Any source, compiler,
  optimizer or address-pin change requires the production size and metadata gate
  again; test deployments with relaxed limits are not deployment evidence.
- **Evidence scope:** mock-based tests, bounded invariant campaigns and arithmetic
  models do not prove the behavior of external services or every possible state.
  Halmos does not establish production gas-metered FSM liveness: its unconstrained
  GAS model is unsuitable for that claim; the retained transition tests run in Foundry.
  Local results do not establish that remote CI ran successfully.

Review findings against [AUDIT.md](AUDIT.md), [SECURITY.md](../SECURITY.md) and
[Known Issues](../KNOWN-ISSUES.md). Accepted governance powers and the explicit RNG
equivalences above are distinct from authorization bypasses or unbounded payouts.
