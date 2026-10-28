# Deity perpetual tickets and protocol boon draws

Protocol deities grant boons to players who wager ETH on their hero symbols in
Degenerette. Normal daily advance automatically issues the rewards. No separate
entry payment or player claim is required.

## Genesis and paid passes

- VAULT is the WWXRP deity: symbol/token ID **0**.
- sDGNRS is the ETH deity: symbol/token ID **6**.
- After all contracts are deployed (all CREATEs, so every predicted address holds), the
  creator calls `game.initProtocolDeity()` once, at level 0, to register both soulbound deity
  NFTs and their initial tickets. The Vault and sDGNRS constructors start their own
  subscriptions.
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

Deity-pass discount boons and the payment waterfall apply as for any purchase.
Public symbols 0 and 6 are reserved even before the genesis grants exist
(`purchaseDeityPass` reverts `SymbolTaken`).

Base prices for paid purchases 1, 2, 10, 23, 24, 25 and 30 (total passes 3, 4, 12, 25, 26, 27
and 32) are 24, 25, 69, 277, 300, 600 and 19,200 ETH.

## Perpetual coverage and affiliate awards

Genesis grants cover levels 1–100. A purchased pass at storage level `L` covers
`L+1` through `L+100`, inclusive. Each transition into the next purchase phase
extends the far-future queue to `level+100`, maintaining rolling 100-level
coverage. These are real queue entries, available to the far-future
jackpot samplers.

The genesis batch walks the 100 levels once, appending both new queue positions per level in
one packed append; existing entries and fractional remainders are added to without duplicating
queue positions. `initProtocolDeity` reverts `E()` unless the caller is the creator and
`level == 0`; a repeat call reverts `AlreadyOwnsDeityPass` (there is no separate flag).

The buyer's perpetual range and the affiliate's whale-pass award are
**additive**. The affiliate award is 20 entries (five whole tickets) per level
in the level-1–9 bonus window, then one whole ticket every other level for the
remainder of the 100-level grant. Existing tickets belonging to either person
remain intact. Each address is appended only once to a given queue cohort.

The deity registry is a plain owner list. The advance runs the renewal exactly once per
transition (`phaseTransitionActive` is cleared in the same step), so every owner is extended
unconditionally; a jackpot-phase purchase grants 99 levels so its range stops short of the
transition target. Renewal appends new queue positions in packed groups of eight and preserves
existing queue tails, owed balances and fractional remainders. Far-future owed balances saturate
at 2^30 - 1 instead of reverting.

| Bucket color | Virtual entries for the symbol's deity |
|---|---|
| 0–4 | `max(2, floor(bucketLength / 50))` |
| 5–6 | `max(1, floor(bucketLength / 100))` |
| Gold (7), except gold Dice 6 | 1 |
| Gold Dice 6 | 0 |
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
charges extra ETH nor credits the deity's coinflip balance.

Eligibility follows ordinary bet placement: at least **0.005 ETH per spin**, 1 to
25 spins, and no game-over/liveness trigger. A funding failure rolls back the bet, hero ledger and boon entry together.
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
at the same score cannot gain weight. The jackpot hero ledger
records raw ETH units with its own saturation rule; boon weights accumulate
separately with checked arithmetic.

## Automatic next-day awards

Each issuer has a separate pool for participation day `D`. Each nonempty pool awards
its three normal deity boon slots on `D+1`, independently and **with replacement**.
A single address can win all three, win from both issuers, and keep winning on
later days. These awards do not read or write the manual-gift lifetime recipient
cap.

Manual gifts also allow several boons to the same recipient on the same day. Each
deity still has three daily slots and may give at most ten boons to any one
recipient over the game's lifetime. A deity account cannot gift itself.

- The boon menu is the deity menu, `hash4(DEITY_MENU, word(D), (issuerId << 24) | (D+1),
  slot)`, where `word(d)` is the recorded daily word for game day `d` (`_recordedDailyWord`),
  mapped through the boon weight table with the decimator and deity-pass bands excluded
  (`_deityBoonForSlot`). If `word(D)` is missing (deployment day), the menu uses `word(D+1)`
  instead, so that menu becomes known only at settlement; winners use a separate hash domain.
- Each winner roll is `hash4(PROTOCOL_BOON_WINNER, word(D+1), issuerId, slot)` modulo the
  pool's total weight; the word is day-specific, so the participation day is not hashed
  separately. Participation closes before that word is requested. There are no empty-bucket
  draws or prize-pool qualification gates.
- Every qualifying bet appends a cumulative-weight interval. Winner lookup is a binary
  search with at most 32 reads because the entry count is `uint32`.
- Days with both pools populated issue all six awards inside the daily word
  application (`applyDailyWord_g1652`), after the word is recorded, flips settle, and
  the daily quest and craps window are opened. There is no extra advance call. A
  day whose word is already recorded cannot be applied again, so the draw runs at
  most once per day.
- Each pool's three-bit `awardedMask` seals its awards before delivery, making
  repeated processing harmless. Nothing loops over all participants.

Duplicate or weaker packed boons are ignored; stronger active lanes remain.
Expired lanes are cleared before applying a fresh award. Different boon categories
and currencies retain independent lanes. Instant activity awards add to the recipient's level count (saturating at
`uint24.max`) and quest streak, shield awards saturate at `uint8.max`, and a
whale-pass award adds two half passes to the recipient's pending claim. These
collisions never invoke the manual recipient-limit reverts and
never cause a reroll or extra recipient selection.

Awards are issued only while the logical game day equals the award day (`awardDay ==
_gameDay()`); a pool whose award day passes undrawn grants nothing later. Pools are held in a
two-day ring (below), so a day's pool stays inspectable through its draw day; older pools are
recoverable from events. Empty, expired or already processed work does not block advance. After
game over no fresh boons are issued.

Manual issuance by VAULT or sDGNRS is rejected, including requests through an
approved operator. Public paid deities retain their ordinary manual-gift rules.

## Storage and read interface

`deityPassIds` packs eight `uint32` wallet IDs per word (its length is the deity
count, at most 32). `deityPassSales` is at Game storage slot 35, and
`protocolBoonPools` and `protocolBoonEntries` are the fixed-array roots at slots 832
and 836 (pinned by `test/fuzz/StorageSlotPins.t.sol`).

| Record | Fields | Bits |
|---|---|---:|
| Pool | `uint112 totalWageredWei`, `uint64 totalWeight`, `uint32 entryCount`, `uint8 awardedMask`, `uint24 day` | 240 |
| Entry | `uint32 playerId`, `uint64 cumulativeWeight`, `uint16 scoreSnapshot` | 112 |

Pools and entries are two-slot rings keyed `[issuer][day & 1]` over logical game days. Day D's
pool is written only while the game day is D and drawn only while it is D + 1, so by the time day
D + 2 writes the same slots, day D has been drawn or never can be. The pool's `day` tag names the
wager day it holds: the first entry of a new day resets the pool, and a draw or lens read for an
untagged day sees an empty pool, so an older day's pool can never be drawn on a later day's words.
Entries at or past `entryCount` are leftovers from an older day and are never read.

Each record fits one slot. Entry count and cumulative weight use checked arithmetic, and an
individual weight must fit `uint64` before casting. With a minimum multiplier of 800, the
cumulative weight bound also bounds paid ETH below `uint112`, even with under `1e14` wei of dust
per entry and up to `uint32.max` entries. A qualifying bet adds one packed pool write and one
packed entry write to ordinary placement.

`DegenerusGameLens` exposes `deityOwnerAt`, `deityPassSalesCount`,
`protocolBoonPool`, `protocolBoonEntryAt`, `protocolBoonQuote`, and
`findProtocolBoonWinners`. Quotes return
`(wagerUnits, score, multiplierUnits, weight)` for an ETH amount and the recipient's
current canonical score (an amount below 0.005 ETH reverts `E()`); they do not
promise bet eligibility or remaining pool capacity. The pool, entry and winner lookups answer for the
wager day and its draw day, until a later same-parity day reuses the ring slot; after that the day reads as an empty,
not-ready pool. Quotes and winner lookup stay outside the
size-constrained GAME facade. `ProtocolBoonDrawEntered` and
`ProtocolBoonDrawAwarded` provide entry and issuance logs. Entry events are emitted
by the Degenerette bet module through GAME and include issuer, player, day, paid ETH,
score, weight and entry index. Automatic draws update used-slot views and emit only the draw award event; `DeityBoonIssued` is the
manual-gift event. The draw event's `day` identifies the wager pool, and
the award day is `day + 1`.

## Verification

- `test/fuzz/ProtocolBoonDraw.t.sol`: currency and symbol eligibility, exact paid ETH,
  activity snapshots and quote parity (including jackpot-phase routing), weight
  rounding, multi-spin bets, boon-boost exclusion, gift and operator attribution,
  claimable-ETH funding, failed-payment rollback, closed-day isolation, launch-day
  and ordinary automatic awards, collision handling, recipient callback resistance,
  entry-count and weight bounds, ring-slot reuse and stale-pool isolation, and
  game-over/liveness gating.
- `test/fuzz/DeityPerpetualTickets.t.sol`: genesis grants, paid ranges (including the
  jackpot-phase 99-level range), 32-owner renewal, reserved symbols and repeated genesis.
- `test/gas/ProtocolBoonAdvanceGas.t.sol`: six maximum-depth searches in the daily word
  application, and insufficient-gas behavior.
- `test/fuzz/DegeneretteBoonStake.t.sol`: Degenerette stake-boon consumption.
- Source gates: `scripts/advance-call-manifest.tsv` (the `resolveProtocolBoonDraws`
  delegatecall), `scripts/rng-taint-manifest.tsv` and `scripts/rng-window-manifest.tsv`
  (the menu and winner words), `scripts/write-owners-manifest.tsv` (pool and entry
  writers).
