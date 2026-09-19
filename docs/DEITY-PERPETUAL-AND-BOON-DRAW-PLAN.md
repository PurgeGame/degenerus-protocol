# Deity perpetual tickets and protocol boon draws

Implementation of the September 19 decisions. Players donate, and normal daily
advance automatically issues the rewards. No player claim is required.

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

## FLIP donations

Both contracts expose:

```solidity
function donateFlipForBoons(uint256 amount) external;
```

The caller is always the payer and entrant. Each donation must be **100–25,000
FLIP**, inclusive. Donations open as soon as the protocol passes are initialized,
including deployment day, for next-day awards. Entry does not require a daily RNG
word and remains open while VRF is pending or fulfilled. There is no per-address
daily donation limit. The complete
amount is debited through GAME's existing FLIP burn permission and credited,
without bonuses, to the chosen issuer's **next-day coinflip stake**. It does not
increase the issuer's wallet or reserve balance.

Donation entry does not check game-over or the liveness deadline. Donations can
still burn FLIP and credit the issuer after death; the game-over draw resolver
issues no boons. This keeps terminal-state checks off ordinary donations.

Only draw weight truncates: `amountUnits = floor(amount / (100 * 1e18))`, stored as
`uint8` in the range 1–250. For example, 199 FLIP funds 199 FLIP of stake and gets
one 100-FLIP weight unit. No token allowance is needed: the authenticated issuer
wrapper passes its actual caller to the GAME-only burn route. Paid deity holders
and arbitrary callers cannot use that relay to debit another address.

Each donation snapshots canonical `playerActivityScore(donor)`. The multiplier
uses scale 800 to retain intermediate-score precision:

```text
score <= 400:  multiplierUnits = 800 + 2 * score
score < 1200:  multiplierUnits = 1600 + (score - 400)
score >= 1200: multiplierUnits = 2400
weight = uint256(amountUnits) * multiplierUnits
```

This gives 1× at score 0, 2× at 400, and 3× at 1200 and above. The multiplier affects
only winning weight; it does not mint or multiply the transferred FLIP. Later
score changes do not alter earlier donations.

## Automatic next-day awards

Each issuer has a separate pool for participation day `D`. Each funded pool awards
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
- Every donation appends a cumulative-weight interval. Winner lookup is a binary
  search with at most 32 reads because the entry count is `uint32`.
- Funded days issue all six awards inside the existing daily RNG settlement,
  after the word is recorded, flips settle, and the daily quest and craps window
  are opened. There is no extra advance call. The normal recorded-word shortcut
  prevents repeated processing; gas witnesses include six maximum-depth searches
  in the full fresh-word jackpot and consolidation transactions.
- Each pool's three-bit `awardedMask` seals its awards before delivery, making
  repeated processing harmless. Nothing loops over all donors.

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
| Pool | `uint112 totalDonatedWei`, `uint64 totalWeight`, `uint32 entryCount`, `uint8 awardedMask` | 216 |
| Entry | `address donor`, `uint64 cumulativeWeight`, `uint8 amountUnits`, `uint16 scoreSnapshot` | 248 |

Each record fits one slot. At most `uint32.max` donations of 25,000 FLIP keep pool
principal below `2^107` wei and cumulative weight below `2^52`. The entry-count
limit is enforced by the checked `uint32` increment before any storage writes or
funding calls. The canonical score already fits `uint16`, and Coinflip's checked
tomorrow-day arithmetic makes a separate maximum-day guard unnecessary. The
wrappers supply the donor, so duplicate zero/self-donor guards are omitted.
A donation writes its packed pool
header once and its packed entry once. Draws cache the issuer/day entry mapping
before searching the three winner intervals.

`DegenerusGameLens` exposes `deityOwnerAt`, `deityPassSalesCount`,
`protocolBoonPool`, `protocolBoonEntryAt`, `protocolBoonQuote`, and
`findProtocolBoonWinners`. Quotes and historical winner lookup stay outside the
size-constrained GAME facade. `ProtocolBoonDrawEntered` and
`ProtocolBoonDrawAwarded` provide entry and issuance logs. Automatic draws update
used-slot views and emit only the draw award event; `DeityBoonIssued` remains the
manual-gift event. The draw event's `day` identifies the contribution pool, and
the award day is `day + 1`.

## Verification

Focused tests cover genesis ownership; all thirty paid prices; every initial
coverage level; existing buyer and affiliate queue collisions; later-level
purchases; packed-tail append and resume; exact principal; score snapshots;
100-FLIP truncation; unauthorized issuer attempts; repeated six-slot wins;
automatic daily progression; full active-boon collisions; maximum-depth cold
winner searches; and relevant full-transaction advance gas paths.

Validation completed September 19, 2026:

- Foundry: **144 passed** in the regression matrix; **35 focused checks passed**
  after the final deployment-day guard, including two additional launch tests.
  Collision and packed-queue fuzz tests each run 1,000 cases.
- The pre-review implementation passed **314 focused Hardhat tests** across the
  main run and corrected-fixture reruns, plus **10 statistical/boundary tests**.
  The subsequent gas optimizations and deployment guard were checked with Foundry.
- Shared storage layouts match all updated snapshots; interface, delegatecall,
  RNG, advance-call, unchecked-math, storage-writer, pool-accounting, queue-delete,
  and gas-dependent-drain checks pass.
- All 31 deployment contracts fit the 24,576-byte runtime limit. In the Hardhat
  deployment build, GAME is 24,500 bytes and Advance is 24,009 bytes.
- Measured cold transactions include six maximum-depth winner searches within
  existing daily settlement. The largest tested combined daily transaction uses
  **14,293,957 gas including intrinsic**, below the 16,777,216 transaction cap.
  After removing the duplicate award log, the standalone daily-settlement fixture
  uses 1,794,266 gas; a fresh paid deity
  purchase with a fresh affiliate uses 10,409,301 gas. Renewal for all 32 deities
  alongside a full far-future drain chunk uses 5,622,974 gas; retrying the drain
  does not grant duplicate tickets.
- Terminal tests issue **600 ETH in total refunds for 30 paid passes**, with no
  refund basis for either genesis pass. Jackpot winnings are accounted separately.
- The final combined genesis initializer passes **51 Foundry tests** and uses
  **16,372,064 gas including intrinsic** in the cold fixture, below the 16,777,216
  transaction cap. It writes each level's packed queue and owner-registry length
  once while preserving existing tickets and fractional entries.
- The final deployment/deity/whale/game-over Hardhat run passes **128 tests**,
  including the standalone genesis transaction and unchanged predicted addresses.
- After removing donation-entry RNG readiness, **35 focused Foundry tests pass**.
  Launch-day and delayed-deployment donations receive six awards through real
  advance, donations stay open throughout the VRF lock, fallback menus match
  normal equal-seed menus, and winner views report launch-day outcomes. Manual
  deity gifts retain their preceding-day menu rules. Source-based gates pass;
  cold settlement with six maximum-depth searches uses **1,794,575 gas** including
  intrinsic in this build.

These are measured fixture bounds, not an exhaustive proof over every game state.

The [focused safety and gas review](audit/DEITY-PERPETUAL-BOON-REVIEW.md) records
the deployment-day fix, measured optimizations, and remaining constraints.
