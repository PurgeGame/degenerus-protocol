# Deity perpetual tickets and protocol boon draws

Status: implementation proposal, 2026-09-19. Based on the working tree at HEAD
`a35b0255`, including its existing uncommitted ticket-packing and deity-menu changes.
This document does not implement the contract changes.

## Confirmed behavior

- VAULT receives the WWXRP deity pass (the existing XRP symbol slot, token ID 0)
  and sDGNRS receives the ETH deity pass (Ethereum, token ID 6) at genesis,
  including symbol ownership and ordinary deity benefits. These use two of the
  existing 32 passes, leaving 30 public passes.
- Deity pass prices double after the 300 ETH price point. Keep the existing
  triangular curve through 300 ETH, then charge 600, 1,200, 2,400 ETH, and so on.
- The first public pass costs 24 ETH. The two free genesis passes do not advance
  the pricing counter; count paid sales separately from total ownership.
- Every deity owner receives one perpetual whole ticket per level. The protocol
  owners receive that same grant, replacing their current four tickets per level.
- Deity virtual tickets for the top two non-gold colors (color indices 5 and 6)
  decrease from a minimum of two / 2% of the bucket to a minimum of one / 1%.
- Both contracts expose a player donation function. The donated FLIP funds the
  chosen contract's coinflip stake for the next game day.
- Donations enter a separate draw for that contract's three deity boons for the
  next day. Weight is donated FLIP times the donor's degen-score multiplier:
  2x at score 400, 3x at score 1,200, capped at 3x thereafter. The prize is a boon,
  independent of whether the funded coinflip wins.
- There is no daily or lifetime limit on boons an address can receive through
  these draws. The same address can win multiple slots and both contracts' draws.
- Donations are limited to 100–25,000 FLIP per call. Truncate the draw's base
  amount to 100-FLIP units: 1–250 fits uint8. Keep the full donated principal in
  the next-day coinflip credit. Repeat donations remain allowed.
- The vault can issue deity boons only through this draw. Apply the same exclusive
  issuance rule to sDGNRS. Ordinary player deities retain their gift mechanism.

## Proposed defaults and decisions still open

| Decision | Proposal |
| --- | --- |
| Supply cap interpretation | This plan uses 30 public sales alongside the two genesis passes (32 total), matching the existing symbol supply. If 30 means total passes instead, there are 28 public sales. The user has confirmed that public pricing starts at 24 ETH regardless of the free grants. |
| Ticket quantity | Four ordinary owed entries per level, using the existing ticket/snap rules. A guarantee of one materialized ticket even after a snap would be an additional rule. |
| Score interpolation | Use a linear ramp from 1x at score 0 to 2x at 400, then a gentler linear ramp to 3x at 1,200; flat thereafter. Snapshot the canonical player activity score for each donation. The endpoints and cap are confirmed; this interpolation is the implementation proposal. |
| Repeat wins | Three independent draws with replacement per contract. No recipient blacklist based on earlier gifts or wins. |
| Duplicate boon effects | Preserve existing packed-lane behavior: strongest active tier per category, plus the existing immediate awards. Unlimited issuance does not create a bank of duplicate consumables. |
| Expiry / missed draws | Preserve a fixed award day and its existing deity expiry: day D donations award day D+1 boons. Claims are valid on D+1 once its word is available. No donations means no awards. Late/missing randomness can therefore cause that day's boons to expire; extending validity or banking missed prizes needs a separate decision. |

## 1. Make genesis passes use real registration

Today the Game constructor writes only `HAS_DEITY_PASS` for the protocol owners.
They are absent from `deityPassOwners`, `deityBySymbol`, and the NFT ownership map.
Their constructors separately enqueue 16 entries per level for levels 1–100.

Extract common registration from `purchaseDeityPass`: validate ownership/symbol,
set the packed deity flag, record the owner and symbol, mint the soulbound NFT,
and initialize perpetual coverage. Paid-purchase rewards remain in the purchase
path. A genesis grant pays zero, has zero refund basis, and creates no affiliate
bundle, purchase-credit, or DGNRS purchase reward.

Pin `VAULT_DEITY_SYMBOL = 0` and `SDGNRS_DEITY_SYMBOL = 6`. Both checked-in icon
datasets place XRP at crypto index 0 and Ethereum at crypto index 6. Use those
indices rather than inferring IDs from example names in NFT unit tests. Verify
the displayed WWXRP name/art against the selected deployment dataset; keep the
symbol ID stable. Public purchases must reject both reserved symbols even during
partial deployment, before the corresponding protocol constructor registers it.

Replace constructor calls to `initPerpetualTickets()` with an issuer-gated,
one-time `initProtocolDeity()` call. The caller determines the fixed owner and
symbol; the caller cannot choose a beneficiary. Reject repeats in state rather
than relying only on the fact that today's caller invokes it from a constructor.
Initialize before any constructor behavior that relies on the deity flag.

The existing deployment order already places GAME, WhaleModule, and DeityPass
before VAULT and sDGNRS. Keep those dependencies and verify that no registration
helper calls a later deployment. Remove the Game constructor's synthetic flags.
Keep the genesis paid price at zero so existing early-game-over refund logic
correctly skips both grants.

### Paid-pass price schedule

Change the doubling anchor from 26 existing passes / 375 ETH to 23
paid sales / 300 ETH. Here `sold` counts completed paid purchases only, excluding
both genesis grants. The first public buyer encounters `sold == 0` and pays
24 ETH. Keep a separate paid-sale counter so partial deployment cannot make an
owner-count subtraction underflow or misprice a public purchase. Increment it
exactly once per successful paid purchase; genesis registration does not touch it.

```text
sold <= 23: price = 24 + sold * (sold + 1) / 2 ETH
sold > 23:  price = 300 * 2^(sold - 23) ETH
```

| Public purchase | Base price (ETH) |
| --- | --- |
| 1 | 24 |
| 2 | 25 |
| 3 | 27 |
| 4 | 30 |
| 5 | 34 |
| 6 | 39 |
| 7 | 45 |
| 8 | 52 |
| 9 | 60 |
| 10 | 69 |
| 11 | 79 |
| 12 | 90 |
| 13 | 102 |
| 14 | 115 |
| 15 | 129 |
| 16 | 144 |
| 17 | 160 |
| 18 | 177 |
| 19 | 195 |
| 20 | 214 |
| 21 | 234 |
| 22 | 255 |
| 23 | 277 |
| 24 | 300 |
| 25 | 600 |
| 26 | 1,200 |
| 27 | 2,400 |
| 28 | 4,800 |
| 29 | 9,600 |
| 30 | 19,200 |

Existing 10% / 20% / 35% discount boons apply to these base prices. Update the
Whale module's anchor constants, price-curve tests, and pricing documentation.
This table uses 30 public sales plus two free passes, matching the existing
32-symbol supply. If the requested cap is instead 30 total passes including
genesis, stop at public purchase 28 (4,800 ETH) and explicitly resolve the two
remaining symbols' availability. Do not conflate those supply choices.

## 2. Extend the existing packed ticket mechanism

### Recommended design: rolling 100-level coverage

Retain physical queued coverage. Both `Game.sampleFarFutureTickets` and
`JackpotModule._awardFarFutureCoinJackpot` sample far-future queue owners directly.
Materializing deity tickets only when their level arrives would remove that
eligibility. A virtual-ticket alternative would need coordinated changes to both
samplers, owner deduplication, salvage, and views.

Use one shared perpetual grant for all deity owners:

1. At genesis, queue four entries per owner for levels 1–100.
2. At a paid pass purchase at storage level L, queue four entries for L+1 through
   L+100. Keep the buyer's existing affiliate bundle separate.
3. At each phase transition, extend every registered deity through
   `purchaseLevel + 99`, replacing the two-address FoilPack implementation.
4. Preserve symbol-based virtual jackpot entries with the color adjustment below.
   The ordinary perpetual ticket is an additional benefit; it does not replace
   symbol ownership.

### Packing

- Keep queue lanes as eight `uint32` owner positions per word. Keep trait bucket
  lanes and the existing immutable level-owner registry semantics.
- Replace the owner-list element with a one-slot struct containing `address owner`
  and `uint24 ticketsThroughLevel`. This uses 184 bits. Update every reader,
  including game-over refunds. The array remains one slot per element, but this
  is still an explicit schema change to validate, not an assumed live migration.
- Use the coverage watermark to prevent duplicate grants when transition work
  resumes. Initial registration sets it only after the range has been queued.
- Build a batch queue append helper that writes assembled owner-position words
  and updates queue length once. Handle an existing partially occupied tail and
  overwrite stale lanes correctly. Already-queued owners receive an owed increase
  without another queue position.
- With 32 new owners and an aligned tail, the queue positions occupy four words;
  an unaligned tail can touch five. Owner records and address lookups still have
  separate costs. Do not describe the entire grant as only four storage writes.
- Reuse the existing eight-seat ticket drain and its write budget. One ticket is
  four entries in the owed field, not four queue positions.

The main gas uncertainty is a paid deity purchase with both its new 100-level
coverage and the affiliate's existing 100-level bundle. Measure that transaction
early. Also measure 32-owner replenishment composed with a cold transition drain.
If composition exceeds the existing budget, make replenishment its own bounded
advance stage. If acquisition exceeds the transaction cap, revisit compact
far-future entitlements rather than shipping partially registered paid passes.

### Color-based virtual tickets

Change the shared `_deityVirtualCount` helper in
`DegenerusGameJackpotModule.sol`, which currently treats all seven non-gold colors
as `max(2, floor(len / 50))`. Use this table for every deity, including the two
genesis owners:

| Color index | Virtual ticket occurrences in that trait bucket |
| --- | --- |
| 0–4 | `max(2, floor(len / 50))` — existing two-ticket / 2% rule |
| 5–6, the two rarest non-gold colors | `max(1, floor(len / 100))` — new one-ticket / 1% rule |
| 7, gold | Exactly one — existing flat gold rule |
| Any color without a deity owner | Zero |

Here `len` counts physical occurrences in that individual trait bucket, before
virtual tickets are added. These percentages set virtual weight; they are not
an exact percentage of the enlarged bucket's total winner probability. Do not
multiply these per-trait virtual occurrences by the four-entry conversion used
for ordinary queued whole tickets. Leave trait color-generation probabilities
unchanged.

Both ordinary bucket selection and the shared coin/Craps-comp selection use this
helper. Cover them all, including empty physical buckets where the minimum alone
makes the deity eligible. Preserve the virtual-entry sentinel used by downstream
jackpot/golden-ticket logic.

## 3. Fund the next-day coinflip and record draw weight atomically

Proposed public functions on both contracts:

```solidity
function donateFlipForBoons(uint256 amount) external;
```

Each wrapper forwards its actual `msg.sender` and amount to a GAME endpoint that
accepts calls only from VAULT or sDGNRS. The issuer is the calling contract. Do not
expose a wrapper that lets someone name a different payer.

The Boon module, executing in GAME context, performs one atomic operation:

1. Validate `100 ether <= amount <= 25_000 ether` (FLIP's 18-decimal units),
   live game, and day/count arithmetic bounds. Out-of-range donations revert
   atomically rather than being clamped.
2. Read the donor's canonical activity score, compute the capped multiplier and
   effective weight below, and append an immutable weighted interval for
   `(issuer, participationDay)`.
3. Call `FLIP.burnCoin(donor, amount)` to debit the principal through the existing
   wallet/settled-claimable rules.
4. Call `Coinflip.creditFlip(issuer, amount)` to credit that exact principal to
   the issuer's next-day stake.
5. Emit issuer, donor, participation day, target day, raw amount, score snapshot,
   effective weight, and entry index.

Both existing sinks already authorize GAME. This needs no new general burn or
mint authority for the vault and no token transfer through its virtual reserve.
Ordinary FLIP transfers to VAULT credit its mint allowance, which would be the
wrong destination for this feature. Ordinary transfers do not enroll donors.

Use the protocol credit route, with no donor/issuer boon consumption, recycling
bonus, or direct-deposit record weight. The donor owns the raffle entry; the
chosen contract owns the stake and its winnings. A downstream revert must undo
the debit, credit, and interval together. No additional stake is created when a
boon is claimed.

### Degen-score weighting

Use the same canonical score returned by `Game.playerActivityScore(donor)`,
including its effective quest-streak handling. Snapshot it once per donation,
before funding side effects. A later score increase, lapse, curse, or boon cannot
change an existing interval. A new donation receives the score then in effect.

| Degen score | Weight multiplier |
| --- | --- |
| 0 | 1x |
| 200 | 1.5x |
| 400 | 2x |
| 800 | 2.5x |
| 1,200 and above | 3x |

Use integer scale 800 to represent every whole-score step exactly, without
rounding the multiplier to basis points:

```text
score <= 400:  multiplierUnits = 800 + 2 * score
score < 1200:  multiplierUnits = 1600 + (score - 400)
otherwise:     multiplierUnits = 2400

amountUnits = floor(donatedFlipWei / (100 * 10^18))  // 1..250, fits uint8
effectiveWeight = uint256(amountUnits) * multiplierUnits
```

Truncate the base donation once, before applying the score multiplier. Retain
the common 800 scale in cumulative weight instead of dividing it back out: this
preserves the linear score ramp even on a minimum-size donation. A score-200
donor's one unit weighs 1,200 versus 800 at score zero, exactly 1.5x. The common
scale cancels in winner probabilities.

The full amount goes to next-day coinflip, including any remainder below the
next 100-FLIP unit; that remainder carries no draw weight. For example, 199 FLIP
at score 1,200 stores `amountUnits == 1`, contributes scaled weight 2,400, and
funds 199 FLIP of coinflip stake. Donation quotes should make the truncated base
visible and default input amounts to multiples of 100 FLIP.

The 100 FLIP minimum guarantees nonzero weight. The maximum amount produces
250 units and, at the 3x score cap, scaled weight 600,000. Only the unboosted
amount fits uint8: a normalized 3x weight could already be 750, so do not store
boosted or cumulative weight in that byte. Widen before multiplication and check
narrowing/count bounds before funding. Larger contributions can use multiple
calls; there is no per-address participation or boon-award cap. A 1,000 FLIP
donation at score 1,200 contributes scaled weight 24,000 and exactly 1,000 FLIP
of next-day stake.

Add a dedicated pure curve helper to `ActivityCurveLib` and use it in entry
weight calculation and previews. Do not reuse or retune WWXRP's current
`drawMultBps`, which rescales the Decimator curve and reaches its hard cap at a
different score. This feature changes only the protocol boon draws.

## 4. Select the three recipients using the next day's word

For participation day D and issuer I:

| Item | Source |
| --- | --- |
| Coinflip stake day | D+1 |
| Three prize types | Existing deity menu for I on D+1, derived from `rngWordByDay[D]` |
| Winner randomness | `rngWordByDay[D+1]` |
| Winner selection | Independent domain-separated hash of issuer, D, slot, and the winner word, reduced over total effective score-adjusted weight |

The menu can be previewed after D's word is recorded. Never select winners from
that known menu seed: players can still donate on D. Do not salt the winner roll
with the final donor count or another last-donor-controlled input. Day indexing
must use the same wall-day definition as Coinflip, not a lagging processed cursor.

Keep two independent pools with three slots each. If a donor owns 10% of one
pool's effective weight, that donor has approximately 10% probability for each
of its slots, subject only to integer sampling granularity. For example, equal
raw donations from score-0 and score-1,200 donors yield 1:3 weight and 25%:75%
per-slot probabilities. Splitting a donation at the same score cannot increase
aggregate weight (rounding can only reduce it); different-score donors are
intentionally weighted differently. All three slots are drawn whenever the
pool is nonempty; do not copy WWXRP's dud-day gates or uniformly chosen buckets.

### Storage and permissionless claims

Keep draw state in the Game's shared storage and behavior in the Boon module;
use thin vault/sDGNRS wrappers. No new deployed contract is needed initially.

- One packed pool header: `uint112 totalDonatedWei`, `uint64 totalWeight`,
  `uint32 entryCount`, and `uint8 claimedMask` (three bits used): 216 bits total.
  This retains exact raw-principal totals alongside scaled effective weight.
- Append immutable cumulative effective-weight intervals. Pack each entry as
  `address donor` (160 bits), `uint64 cumulativeWeight`, `uint8 amountUnits`, and
  `uint16 scoreSnapshot`: 248 bits, one storage slot. The canonical score's hard
  cap of 65,534 fits uint16. Retaining the amount byte and score supports precise
  entry previews without another storage slot. Emit raw principal as well.
- Reject a new entry once its count cannot increment within uint32. With at most
  `2^32 - 1` entries of at most 25,000 FLIP each, cumulative raw principal is
  below `2^107` wei and cumulative scaled weight is below `2^52`, safely within
  uint112 and uint64 respectively. Recheck both proofs if the amount limit,
  multiplier scale, or score cap changes.
  No saturation or zero-width entries are needed under these bounds.
- Expose a permissionless claim with `(participationDay, slot, entryIndex)` through
  the issuer. The module verifies the interval around the supplied index in O(1)
  reads and always awards to the stored donor.
- Mark the slot used before applying the boon; a revert rolls the mark back.
  Keep historic per-pool masks distinct from the existing single-day issuer mask.
  Update/read today's issuer used mask consistently so the existing menu viewer
  cannot show claimed protocol slots as unused.
- Expose effective-weight pool totals, entry endpoints, donation-weight quotes,
  prize previews, and winning-entry lookup. Quotes report raw coinflip principal
  separately from boosted draw weight; callers cannot supply their own score.
  An indexer or binary-search view locates the index. The transaction does not
  scan every donor. Claims can be submitted by anyone, including a keeper, but
  there is no mandatory donor loop in `advanceGame`.
- No array deletion or donor sweep is required to finish a day.

Claims become available on D+1 once its word exists. The proposed fixed-day
expiry must be checked explicitly before **all** award branches, including
immediate activity/shield/pass awards; merely writing an old expiry into a boon
lane would still allow delayed permanent awards. If delayed claims are desired,
specify their validity and anti-stockpiling rule before implementation.

## 5. Enforce draw-only issuance without recipient caps

Reject protocol issuers in ordinary `issueDeityBoon`, both at the facade and at
the module boundary. A vault-approved operator must not be able to use the
ordinary player-resolution route to bypass the draw. Leave unrelated operator
powers intact.

The dedicated claim path verifies the draw and then applies the existing boon
effect. It must neither read nor increment `deityRecipientBoonCount` or
`deityBoonRecipientDay`. A previous ordinary gift cannot block a draw win, and a
draw win cannot consume the recipient's ordinary gift allowance. Repeated wins
consume different issuer/day/slot entitlements, with no per-address award count.

Clear expired boon state before applying a won boon, so an expired higher tier
does not suppress it. Retain existing active-tier merging and independent
currency lanes. A quest shield, activity grant, or whale-pass claim follows its
existing effect semantics. This plan removes issuance limits, not the storage
model's one-active-boon-per-category rule.

## Implementation sequence and acceptance evidence

1. **Genesis and registration:** shared registration, real NFTs, selected symbols,
   separate paid-sale price counter, doubling after 300 ETH, zero-price refunds, and
   deployment fixture updates.
2. **Tickets:** coverage watermarks, one-ticket grants, packed batch append,
   transition integration, color-5/6 virtual-weight reduction, and early
   acquisition/transition gas measurements.
3. **Draw funding and storage:** wrappers, gated facade/module entry, score curve
   and per-donation snapshot, exact debit and next-day stake credit, effective-
   weight cumulative intervals, and events.
4. **Resolution and access:** next-day winner word, menu parity, interval proof,
   caps bypass, manual protocol issuance rejection, expiry and viewer support.
5. **Integration verification and documentation:** update affected interfaces,
   layout goldens, manifests, protocol docs, and deployment checks.

Required behavioral checks:

- NFT ownership (`ownerOf(0) == VAULT`, `ownerOf(6) == SDGNRS`), symbol mapping,
  deity bit, owner registry, zero refund basis,
  genesis idempotence, public symbol availability, and paid price curve agree.
- Price-curve boundaries at `sold == 22/23/24`, the last public purchase, and all
  discount tiers: the transition is 277 → 300 → 600 ETH before discounts.
- Both free genesis registrations leave the paid-sale counter at zero; the first
  public price remains 24 ETH. Failed purchases do not increment the counter.
- Exactly four ordinary entries per deity per covered level before snap; no
  duplicate transition grants; coverage at 1/5/6/99/100/101; late acquisition,
  purchased-ticket merging, far-future salvage, and terminal behavior.
- Queue codec and round-drain behavior at 7/8/9 and 31/32 owners, including a
  partial tail, reused words, near/far keys, read/write cohorts, and chunk resumes.
- All eight virtual-ticket color tiers and all symbol/quadrant encodings, with
  bucket lengths around 0/49/50/99/100/149/150/199/200/299/300. Verify the new 1%
  floor on colors 5/6, unchanged 2% floor on 0–4, flat gold, no-owner zero, and
  matching behavior across ETH, FLIP, and Craps-comp winner selection.
- Donation debits equal next-day issuer stake credits; neither treasury reserve
  nor donor stake receives a second credit. Exercise wallet and settled-claimable
  funding, insufficient funds, rollback, day rollover, and the genesis seed window.
- Amounts just below/at/above 100 FLIP and 25,000 FLIP; truncation boundaries
  around 199/200 and 24,999/25,000 FLIP; exact full-principal credits; repeated
  maximum donations and the uint32 count boundary. Verify units 1 and 250 round
  trip through uint8, maximum scaled weight is 600,000 without narrow arithmetic
  overflow, and the 248-bit entry / 216-bit header each fit one slot.
- Known menu randomness cannot determine recipients; missing words, retries,
  mid-day requests, VRF replacement, and gap backfill preserve fixed outcomes.
- Multiple wins in one day and more than ten lifetime wins succeed for one
  address; both issuers and ordinary gifts coexist. Each individual slot pays
  once. Incorrect indices, forged issuer/payer, direct module calls, and vault
  operator attempts fail.
- Curve boundaries at score 0/399/400/401/1,199/1,200/1,201 and the canonical
  score maximum; monotonicity, exact endpoint multipliers, and the flat 3x cap.
  Check amount-unit truncation, boosted-weight overflow rollback, and that
  3x draw weight still credits only 1x donated principal to coinflip.
- Score changes after entry leave all old intervals/outcomes unchanged. Later
  donations use fresh snapshots; recipient activity at claim is not consulted
  for winner selection. Verify effective quest-streak parity with the score view.
- Statistical score-adjusted recipient weighting and splitting at the same score;
  equal-principal 1x versus 3x donors produce 25% versus 75% per-slot shares; empty and
  single-donor pools; duplicate categories; expired stronger lanes; late claims.
- Production bytecode/deployment sizes and cold composite gas remain within
  repository limits. Include worst-case deity acquisition, all-owner renewal,
  and the heaviest boon effects. Run the structural/interface/RNG/layout checks
  documented in `docs/VERIFICATION.md`, plus focused existing Foundry/Hardhat
  ticket, deity, boon, WWXRP-pattern, coinflip, and solvency regressions.

No contract tests were run for this planning-only change. Gas and bytecode
acceptance remain implementation gates, not measured claims in this document.
