# Deity perpetual tickets and protocol boon draws

Protocol deities grant boons to players who wager ETH on their hero symbols in
Degenerette. Normal daily advance automatically issues the rewards. No separate
entry payment or player claim is required.

## Genesis and paid passes

- VAULT is the WWXRP deity: existing symbol/token ID **0**.
- sDGNRS is the ETH deity: existing symbol/token ID **6**.
- After all contracts are deployed, the creator calls `game.initProtocolDeity()`
  once to register both real soulbound deity NFTs and their initial tickets.
  Deployment scripts include this transaction after all CREATEs, preserving every
  predicted address. Their constructors still start their subscriptions.
- **32 total passes: two genesis grants and 30 paid passes.** Genesis grants have
  no paid-price refund basis and do not advance the public price curve.
- Each deity gets **one ordinary whole ticket per level**, equal to four entries,
  in addition to the virtual symbol-bucket participation below.

A separate `uint8 deityPassSales` counts only paid purchases. For `sold` paid
passes already sold, the next undiscounted price is:

```text
sold <= 23: 24 + sold * (sold + 1) / 2 ETH
sold > 23:  300 * 2^(sold - 23) ETH
```

Existing discount and payment mechanics remain applicable. Public symbols 0 and 6
are reserved even during partial deployment.

| Paid purchase | Total passes after purchase | Base price (ETH) |
|---:|---:|---:|
| 1 | 3 | 24 |
| 2 | 4 | 25 |
| 3 | 5 | 27 |
| 4 | 6 | 30 |
| 5 | 7 | 34 |
| 6 | 8 | 39 |
| 7 | 9 | 45 |
| 8 | 10 | 52 |
| 9 | 11 | 60 |
| 10 | 12 | 69 |
| 11 | 13 | 79 |
| 12 | 14 | 90 |
| 13 | 15 | 102 |
| 14 | 16 | 115 |
| 15 | 17 | 129 |
| 16 | 18 | 144 |
| 17 | 19 | 160 |
| 18 | 20 | 177 |
| 19 | 21 | 195 |
| 20 | 22 | 214 |
| 21 | 23 | 234 |
| 22 | 24 | 255 |
| 23 | 25 | 277 |
| 24 | 26 | 300 |
| 25 | 27 | 600 |
| 26 | 28 | 1,200 |
| 27 | 29 | 2,400 |
| 28 | 30 | 4,800 |
| 29 | 31 | 9,600 |
| 30 | 32 | 19,200 |

## Perpetual coverage and affiliate awards

Genesis grants cover levels 1–100. A purchased pass at storage level `L` covers
`L+1` through `L+100`, inclusive. Each transition into the next purchase phase
extends the far-future queue to `level+100`, maintaining rolling 100-level
coverage. These are real queue entries, available to the existing far-future
jackpot samplers.

The genesis batch walks the 100 levels once. Per level, both new queue positions
share one packed append, and the owner-registry length updates once. Each fresh
owner/owed record is written once. Existing entries and fractional remainders are
added to without duplicating queue positions. Creator authorization and the
existing duplicate-registration checks protect setup; there is no level-zero
guard or extra initialization flag.

The buyer's perpetual range and the affiliate's existing whale-pass award are
**additive**. The affiliate award remains 20 entries (five whole tickets) per level
in the level-1–9 bonus window, then one whole ticket every other level for the
remainder of the 100-level grant. Existing tickets belonging to either person
remain intact. Each address is appended only once to a given queue cohort.

The deity registry is a plain owner list. The advance runs the renewal exactly once
per transition (a resumed transition skips the housekeeping), so every owner is
extended unconditionally; a jackpot-phase purchase grants 99 levels so its range
stops short of the transition target. Fresh owners are stored with their completed
owed record in one write;
the registry length is updated once for the entire renewal batch. At renewal, up
to eight new registry positions are accumulated into a packed queue word before
writing it. Existing queue tails, owed balances, and
fractional remainders are preserved. Full registries and saturated owed balances
follow the advance path's skip/saturate policy rather than reverting.

| Bucket color | Virtual entries for the symbol's deity |
|---|---|
| 0–4 | `max(2, floor(bucketLength / 50))` |
| 5–6 | `max(1, floor(bucketLength / 100))` |
| Gold (7) | 1 |
| No deity owns the symbol | 0 |

## ETH hero wagers

An ordinary ETH Degenerette bet on **symbol 0 (WWXRP)** enters the Vault deity's
pool; a bet on **symbol 6 (ETH)** enters sDGNRS's pool. The corresponding genesis
pass must be initialized. Other symbols, FLIP bets, generated lootbox spins
(including WWXRP box and foil spins) and record bounty spins never create entries.
WWXRP is not a bet currency.

The entry belongs to the bet recipient, including gifted bets and approved
operator placements. Its paid amount is `amountPerSpin * spinCount`, before any
Degenerette stake boon. ETH from the wallet, claimable winnings or afking funding
all qualifies. The ordinary bet receives its ordinary payout; entry neither
charges extra ETH nor credits the deity's coinflip balance. The standalone
`donateFlipForBoons` wrappers and GAME's donation relay have been removed.

Eligibility follows ordinary bet placement: at least **0.005 ETH per spin**, an
unrevealed nonzero lootbox RNG index, valid spin count, and no game-over/liveness
trigger. A funding failure rolls back the bet, hero ledger and boon entry together.
Participation is earned at placement regardless of the eventual spin result or
whether the deity's symbol wins the jackpot hero draw.

Boon entries reuse the hero ledger's stake granularity:

```text
wagerUnits = floor(paidEthWei / 1e14)  // 0.0001 ETH
score <= 400:  multiplierUnits = 800 + 2 * score
score < 1200:  multiplierUnits = 1600 + (score - 400)
score >= 1200: multiplierUnits = 2400
weight = wagerUnits * multiplierUnits
```

Each entry snapshots canonical `playerActivityScore(recipient)` before this bet's
quest credit. The already-read effective quest streak is reused; canonical score
uses the routed ticket level, which can differ from Degenerette's payout-score
level during jackpot phases. The multiplier is 1x at score 0, 2x at 400, and 3x at
1200 and above. Later score changes do not alter earlier entries.

Exact paid ETH is retained in the pool total and entry event. Only weight truncates;
for example, 0.00995 ETH counts as 99 wager units. Splitting the same total stake
at the same score cannot gain weight. The existing jackpot hero ledger still
records raw ETH units with its own saturation rule; boon weights accumulate
separately with checked arithmetic.

## Automatic next-day awards

Each issuer has a separate pool for participation day `D`. Each nonempty pool awards
its three normal deity boon slots on `D+1`, independently and **with replacement**.
A single address can win all three, win from both issuers, and keep winning on
later days. These awards do not read or write the ordinary manual-gift recipient
caps. The three-slot daily supply per issuer remains the source of the rewards.

- The boon menu is the existing deity menu, derived from `rngWordByDay[D]` and the
  issuer, award day, and slot. If that word is missing (notably deployment day),
  the automatic draw uses `rngWordByDay[D+1]` for its menu instead. That fallback
  menu becomes known at settlement; winners use a separate hash domain.
- Each winner uses `rngWordByDay[D+1]`, with a domain-separated hash including
  issuer, participation day, and slot. Participation closes before that word is
  requested. There are no empty-bucket draws or prize-pool qualification gates.
- Every qualifying bet appends a cumulative-weight interval. Winner lookup is a binary
  search with at most 32 reads because the entry count is `uint32`.
- Days with both pools populated issue all six awards inside the existing daily RNG settlement,
  after the word is recorded, flips settle, and the daily quest and craps window
  are opened. There is no extra advance call. The normal recorded-word shortcut
  prevents repeated processing; gas witnesses include six maximum-depth searches
  in the full fresh-word jackpot and consolidation transactions.
- Each pool's three-bit `awardedMask` seals its awards before delivery, making
  repeated processing harmless. Nothing loops over all participants.

Duplicate or weaker packed boons are ignored; stronger active lanes remain.
Expired lanes are cleared before applying a fresh award. Different boon categories
and currencies retain independent lanes. Instant activity and shield awards keep
their existing saturating behavior; a whale-pass entitlement that cannot fit is
ignored. These collisions never invoke the manual recipient-limit reverts and
never cause a reroll or extra recipient selection.

Awards are only issued on their designated next calendar day. A missed day does
not later grant permanent activity/shield/pass benefits. Historical pools remain
inspectable. A missing predecessor word uses the award-day menu fallback; empty,
expired, or already processed work does not block advance. Normal game-over
handling does not issue fresh boons.

Manual issuance by VAULT or sDGNRS is rejected, including requests through an
approved operator. Public paid deities retain their ordinary manual-gift rules.

## Storage and read interface

The deity registry keeps its existing root and one-slot element stride. After
terminal-decimator removal, `deityPassSales`, `protocolBoonPools`, and
`protocolBoonEntries` occupy its former slots 47–49; all other surviving fields
retain their positions. This layout is for a new deployment, not an in-place
migration of existing contract state.

| Record | Fields | Bits |
|---|---|---:|
| Pool | `uint112 totalWageredWei`, `uint64 totalWeight`, `uint32 entryCount`, `uint8 awardedMask` | 216 |
| Entry | `address player`, `uint64 cumulativeWeight`, `uint16 scoreSnapshot` | 240 |

Each record fits one slot. Entry count and cumulative weight use checked
arithmetic, and an individual weight must fit `uint64` before casting. With a
minimum multiplier of 800, the cumulative weight bound also bounds paid ETH below
`uint112`, even including less than `1e14` wei of dust per entry and up to
`uint32.max` entries. Qualifying bets add one packed pool write and one packed
entry write to the ordinary placement path. Entry needs no separate transaction
or module delegatecall. Draws cache the issuer/day entry mapping before searching
the three winner intervals.

`DegenerusGameLens` exposes `deityOwnerAt`, `deityPassSalesCount`,
`protocolBoonPool`, `protocolBoonEntryAt`, `protocolBoonQuote`, and
`findProtocolBoonWinners`. Quotes return
`(wagerUnits, score, multiplierUnits, weight)` for an ETH amount and the recipient's
current canonical score; they do not promise bet eligibility
or remaining pool capacity. Quotes and historical winner lookup stay outside the
size-constrained GAME facade. `ProtocolBoonDrawEntered` and
`ProtocolBoonDrawAwarded` provide entry and issuance logs. Entry events are emitted
by the Degenerette module through GAME and include issuer, player, day, paid ETH,
score, weight and entry index. Automatic draws update used-slot views and emit only the draw award event; `DeityBoonIssued` remains the
manual-gift event. The draw event's `day` identifies the wager pool, and
the award day is `day + 1`.

## Verification

The focused Foundry suites cover currency and symbol eligibility, exact paid ETH,
activity snapshots and quote parity (including jackpot-phase routing), weight
rounding, multi-spin bets, boon-bonus exclusion, gift and operator attribution,
claimable-ETH funding, failed-payment rollback, closed-day isolation, launch-day
and ordinary automatic awards, collision handling, recipient callback resistance,
entry-count and weight bounds, and game-over/liveness gating.

The existing six maximum-depth searches remain covered by the daily advance gas
witness. Degenerette scoring, stake boons and RNG freeze regression suites run
alongside the entry tests. Source gates cover delegatecall routing, removed
selectors, RNG closure, pool writes and advance-chain calls.

Validated September 22, 2026: **106 Foundry tests passed**, zero failed, with one
existing skipped per-spin DGNRS test. Fuzz properties run 1,000 cases each. The
cold daily settlement with six maximum-depth boon searches used **1,800,678 gas**,
including intrinsic gas. Interface coverage, all ten source gates, storage-layout
consistency and all 32 checked deployment runtime-size limits pass. Logs are under
`.audit-test-logs/eth-hero-boons-final/`.
