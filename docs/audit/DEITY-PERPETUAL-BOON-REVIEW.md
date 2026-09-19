# Deity perpetual tickets and protocol boon draws: focused review

Reviewed September 19, 2026. Scope: genesis/paid registration, initial and rolling
ticket allocation, donation authorization and accounting, draw timing, automatic
delivery, packed storage, and their advance-chain gas compositions.

One payment-without-reward defect was found and fixed. Two measured gas
optimizations were applied. No additional exploitable issue was identified in
this scope. The evidence is code review and regression/gas tests, not a formal
proof over every protocol state.

## [MEDIUM, FIXED] Deployment-day donations had no possible next-day menu

**Location:** `DegenerusGameBoonModule.enterProtocolBoonDraw`,
`DegenerusGame.constructor`, `DegenerusGameAdvanceModule.advanceGame`.

**Description:** GAME initializes `dailyIdx` to its deployment day. Same-day
advance does not request that day's daily RNG word, and later backfill starts
after `dailyIdx`. A donation on that day therefore could not supply the preceding
day's word needed by its next-day boon menu.

**Attack scenario / failure trace:** A player donates 100 FLIP on deployment day.
The wrapper debits the player and credits the issuer's next-day stake. On the next
day the draw seals the pool, finds no menu word, and issues no boons. No attacker
is required; this was an ordinary launch-day transaction.

**Impact:** The donor pays for a draw with no possible reward. Advance remains
live, but the donation is not refunded.

**Regression evidence:** `testLaunchDayDonationsReceiveAllSixBoonsThroughRealAdvance`
accepts donations from both wrappers on day 1, checks exact funding, and drives
production advance through all six day-2 awards. The predecessor remains zero.
`testGenesisDonationsWorkWhenDeploymentCrossesAReset` covers a deployment whose
initial relative day is later than 1. A separate test accepts donations both
before and after VRF fulfillment while RNG remains locked.

**Current correction:** Donation entry has no RNG readiness check. When the
preceding word is missing, the automatic resolver uses the finalized award-day
word to generate its menu. The donor pool is already closed before that word's
request; winner selection uses a separate hash domain. The ordinary published
menu remains unchanged whenever the predecessor word exists. Missing-predecessor
tests verify actual issuance, equal-seed menu equivalence, and replay prevention.
The winner lens also accepts pools without a predecessor word.

**Gas impact:** Removes the donation-side state comparison and conditional word
read. Adds one fallback comparison to the daily resolver, with no new storage.
This replaces the earlier entry-rejection fix recorded in the validation history.

## [GAS, FIXED] Donation copied an unchanged award flag back to storage

**Location:** `DegenerusGameBoonModule.enterProtocolBoonDraw`.

**Current implementation before correction:** Copy the pool to memory, update its
three counters, and assign the entire struct back. Compiler IR and recorded
storage accesses showed two writes to the pool slot, including an unchanged
`awardedMask`, plus one write to the new entry.

**Proposed implementation applied:** Retain a typed storage reference, calculate
the counters in locals, then assign the three adjacent packed fields together.
The award flag is not assigned.

**Savings:** GAME writes per donation decrease from **3 to 2**. The isolated
optimization saved **622 gas per donation** in the principal/snapshot witnesses,
before adding the separate deployment-day safety check.

**Rationale:** One packed pool word and one packed entry word are sufficient.
Checked arithmetic, funding atomicity, and the existing layout are preserved.
`testDonationStorageWriteFootprint` checks the write count and destination slots
for both the first and subsequent donations.

## [GAS, FIXED] Winner searches repeatedly hashed the same mapping prefix

**Location:** `DegenerusGameBoonModule._drawProtocolBoons`.

**Current implementation before correction:** Every binary-search step resolves
`protocolBoonEntries[issuer][day][mid]`. Compiler IR confirmed that the unchanged
issuer/day prefix was recomputed inside the loop.

**Proposed implementation applied:** Cache a typed storage reference to
`protocolBoonEntries[issuer][day]` once, then use `entries[mid]` and `entries[lo]`.

**Savings:** The cold daily-settlement witness with six maximum-depth searches
decreases from **1,827,240 to 1,812,930 gas**, a **14,310 gas** saving. The heaviest
tested combined daily transaction decreases from **14,308,267 to 14,293,957 gas**,
including intrinsic gas. Both remain below the 15M review target and the fixture's
16,777,216 transaction cap.

**Rationale:** Issuer and participation day remain constant throughout all three
searches. Checked index arithmetic and the maximum of 32 reads per search remain.
No new assembly or arithmetic bypass was introduced.

## Safety evidence and remaining constraints

- Only VAULT and sDGNRS may relay a donation; each wrapper supplies its actual
  caller. A paid deity or approved operator cannot name another payer.
- Full principal, including fractional dust, is debited once and credited to the
  issuer's next-day stake. The credit path gives no self-deposit, recycling,
  record, or boon bonus.
- Donation day D closes before the winner word for D+1 is requested. Changing
  score or donating on D+1 cannot alter D's intervals. Backfill and buffered-word
  handling retain the existing daily RNG rules.
- Maximum `uint32` entry count at maximum donation and multiplier fits both the
  principal and cumulative-weight fields; the final valid entry and next rejected
  entry are tested.
- Recipient code is never invoked by reward delivery. A contract with a reverting
  fallback can receive all six awards. An underfunded advance cannot partially
  seal or discard a pool; a funded retry issues its awards.
- Active-boon collisions, saturated entitlement storage, and the afking activity
  bonus route are covered. Ordinary manual-gift limits are absent from the
  protocol draw route.
- The owner registry is bounded at 32. Packed appends preserve partial tails;
  the once-per-transition advance path prevents duplicate renewals; initial buyer and affiliate
  awards remain additive. The cold renewal-plus-drain witness uses 5,622,974 gas.
- Free protocol passes have zero paid-price refund basis. Terminal refund tests
  separate refunds from jackpot winnings.
- Awards intentionally expire if their designated next calendar day is missed.
  Donations are not refunded in that case. This remains a delivery-policy choice.
- The initial deployment build had little remaining runtime-code headroom: 76 bytes in
  GAME and 24 bytes in Mint. The changes fit, but further facade growth needs
  explicit size checks.

Validation: **144 tests passed** in the regression/gas matrix after the storage
optimizations. The final deployment-day guard then passed **35 focused tests**,
including two new launch-day regressions (146 distinct cases across these runs).
The collision and packed-queue fuzz suites each run 1,000 cases. Storage layout,
interface coverage, delegatecall/selector, RNG, advance-call, arithmetic,
storage-writer, pool-accounting, queue-delete, and gas-state gates pass. All 31
deployment contracts remain within the runtime-code limit.

Follow-up bytecode cleanup: removed the duplicate protocol-issuer rejection from
`DegenerusGame.issueDeityBoon`; `DegenerusGameBoonModule.issueDeityBoon` remains the
enforcement point, including for approved operators. With identical Foundry
addresses and compiler settings, GAME runtime decreased from **24,495 to 24,425
bytes**, saving **70 bytes** and leaving **151 bytes** of headroom in that build.
All **28 tests** in `ProtocolBoonDraw` and `DeityBoonPreviousDay` passed, including
exact-error assertions for the manual protocol-issuer rejection. Delegatecall,
raw-selector, and advance-call checks also passed.

Follow-up event cleanup: automatic draws now emit only `ProtocolBoonDrawAwarded`
for each award; manual gifts retain `DeityBoonIssued`. The draw event identifies
the contribution day, with issuance on the following day. BoonModule runtime
decreased from **17,170 to 16,983 bytes**, saving **187 bytes**. All **30 tests** in
`ProtocolBoonDraw`, `DeityBoonPreviousDay`, and `ProtocolBoonAdvanceGas` passed.
The cold six-award daily-settlement fixture now uses **1,794,266 gas including
intrinsic**. The advance-call registry check also passed.

Follow-up genesis batching: both protocol passes and their first 100 ticket levels
now initialize in one creator transaction after all deployment CREATEs. Deployment
scripts and both test fixtures include that call; predicted contract addresses stay
the same. The former constructor calls and level-zero guard are removed. Existing
registration checks prevent replay; no additional initialization flag is stored.

Per level, the batch writes the queue word and queue length once, the owner-registry
length once, and each new combined owner/owed record once. The cold measured call
uses **16,372,064 gas including intrinsic**, below the **16,777,216** transaction
cap. The previous separate registration witnesses totaled **18,099,686 gas before
transaction intrinsic**; comparing that work with the new transaction gives about
**1.73M gas saved**, before constructor-bytecode differences. This comparison
measures initialization work, not the gas cost of the full deployment.

All **51 Foundry tests** passed after the final batch optimization, covering the
write footprint at every genesis level, partial queue tails, existing balances and
fractional entries, repeat/caller authorization, all 30 paid prices, additive buyer
and affiliate awards, renewal, and boon delivery. Storage-layout, interface, and
all source-based gates passed. All 31 deployment contracts fit the runtime limit;
the Foundry build is 24,425 bytes for GAME and 20,739 for WhaleModule.
The final Hardhat deployment, deity NFT, whale/affiliate, and game-over suites
passed **128 tests**, including the actual standalone genesis transaction under
the gas cap. All 31 deployment artifacts fit; GAME is 24,430 bytes and WhaleModule
is 20,744 bytes in that build.

Follow-up donation guard cleanup: removed the duplicate zero/self-donor checks,
the already-capped score check, and the explicit day/entry overflow checks, along
with the unused `DrawEntryLimit` error. The entry increment remains checked before
state writes; Coinflip's checked next-day arithmetic atomically rejects day overflow.
Caller/context, initialized-issuer, amount, game-over/liveness, and deployment-day
readiness checks remain. No advance-chain guard was added.

All **22 focused tests** passed, including exact arithmetic-overflow rejection,
rollback of donor funds and pool entries when next-day credit overflows, maximum
entry widths, authorization, and complete automatic daily settlement. Source-based
gates passed. BoonModule runtime decreased from **16,983 to 16,879 bytes**, saving
**104 bytes** in the Foundry build.

Subsequent policy decision: removed donation-entry game-over and liveness checks
to avoid charging ordinary donations for rejecting post-death FLIP burns. Donation
accounting and issuer authorization still apply; the draw resolver retains its
game-over no-op, so accepted post-death donations issue no boons. Tests now verify
both issuers accept donations after the liveness deadline and after game-over,
with exact debits/credits and no terminal awards. All **24 focused tests** and
source-based gates passed. BoonModule runtime decreased from **16,879 to 16,572
bytes**, saving another **307 bytes**.

Follow-up always-open donation entry: removed `RngNotReady` from the donation
route and replaced missing-menu cancellation with the award-day RNG fallback
described above. The winner lens no longer requires a predecessor word. All
**35 focused tests** passed, covering launch-day and delayed-deployment awards
through production advance, entry before and after VRF fulfillment while locked,
fallback menu equivalence, replay prevention, manual-menu regressions, funding
and authorization, collisions, and gas bounds. All source-based gates passed.
The cold daily-settlement witness with six maximum-depth searches uses
**1,794,575 gas including intrinsic**. BoonModule runtime is **16,536 bytes**;
GAME remains **24,425 bytes** in this Foundry build.
