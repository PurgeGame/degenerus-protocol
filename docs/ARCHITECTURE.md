# Architecture and accounting

## Contract boundaries

| Component | Responsibility |
| --- | --- |
| `DegenerusGame` + 16 game modules | Purchases, ticket materialization, the miner engine and VRF, jackpots, lootboxes, side-games and terminal distribution. The sixteen delegatecall modules are Advance, Afking (`GameAfkingModule`), Bingo, Boon, Decimator, Degenerette, FoilPack, GameOver, Jackpot, JackpotDraw, Lootbox, Miner, Mint, Rng, Ticket and Whale; `DegenerusGameMintStreakUtils` and `DegenerusGamePayoutUtils` are abstract bases inherited by modules, the Game and the Lens, not deployments |
| `DegenerusGameStorage` | Shared game/module storage; every delegatecall executes in the Game's storage context. Modules also delegatecall sibling modules from inside a delegatecall (Advance to GameOver, Jackpot and Mint; Jackpot to Whale for early-bird and quadrant pass awards; Mint to FoilPack and Lootbox; FoilPack to Degenerette and Jackpot; Afking and Whale to Lootbox; Degenerette and Lootbox to further modules); `make check-delegatecall` pins each selector/target pair |
| `FLIP` + `Coinflip` | `FLIP`: token supply, burns, the virtual vault allowance and the separate craps comp lane (`_crapsCompAllowance`). `Coinflip`: daily flip stakes, settled credits and the record pool; it holds no comp state |
| `Craps`, `LootboxCraps`, `CrapsBattle` + `CrapsEngine` | `CrapsBattle is LootboxCraps is Craps` holds seat/field state and payouts; `CrapsEngine is Craps` is the one deployment after the table and exposes `settleSlip`, `settleRanked` and `settleBattle` as `external pure`, which is what makes the table's pinned call a STATICCALL; the table calls `settleBattle`, which plays a seat's whole run (board, scatter, shooter boost and rotation) under the shared 1,000-roll budget and also returns the battle ranking score (goals: high point, then ending bankroll; busts: shooters completed, then whether anything was kept, then high point, then remainder), so the comparator lives in the engine, not the table |
| `JackpotBattle` | `JackpotBattle is CrapsBattleStorage`, deployed after `CrapsEngine` and reached only by `CrapsBattle`'s fallback delegatecall, so it runs in the table's storage: it locks the daily jackpot battle's field at the RNG request, draws and appends its awarded entries, seals the field and serves its views. The table's normal resolver settles and pays every seat |
| `DegenerusVault` | DGVE/DGVF share classes, vault-owned positions and comp distribution authority |
| `sDGNRS` / `DGNRS` / `GNRUS` | Reserve backing, transferable wrapper and charity rights |
| Affiliate, Quests, Jackpots | Referral rewards, activity state and jackpot support |
| Parimutuel | Growth bets; Game seals each outcome through `recordGrowth` |
| DeityPass, AFKingSubscriptionToken, RecordBounty, WWXRP | Pass/seat/record rights and auxiliary token rewards |
| Admin | VRF/feed recovery governance and bounded liquidity operations |
| `libraries/*`, `DegenerusTraitUtils` | Internal libraries inlined at compile time (ActivityCurve, BitPacking, Entropy, FlipRound, GameTime, JackpotBucket, PackedTicketSample, PriceLookup, SigFig, TraitUtils); in scope, not deployments |

`ContractAddresses.sol` pins every protocol contract plus the external endpoints: the VRF
coordinator and key hash, the LINK token, the LINK/ETH feed, stETH, the ENS reverse registrar
and the CREATOR address. The ENS registrar receives a best-effort raw `setName(string)` call
from the constructors of Coinflip, DeityPass, Parimutuel, AFKingSubscriptionToken and
RecordBounty, skipped when the pin is zero. The deployment order has 32 entries;
the Vault also creates its two share tokens. `DegenerusGameLens` and `DeityBoonViewer`
are in scope but are not entries in that deployment sequence. Third-party renderers,
Chainlink, LINK and stETH have distinct trust boundaries described in Security.

## Main value flow

Ticket and ordinary lootbox ETH funds protocol prize pools. Presale-box ETH is credited
80% to the Vault and 20% to sDGNRS as claimable (`_creditBoxProceeds`); the closing buyer
also receives the sDGNRS `PresaleBox` pool remainder once presale is drained. Jackpot and redemption paths create claimable
obligations or game-specific credits; moving ETH/stETH to a player follows the relevant
claim/recipient checks. Permissionless processing is not authority to redirect payment.

A purchased ETH Degenerette bet resolves its combined win lootbox once per bet ID.
If the shared score allowance for `level + 1` has usage below 10 ETH at settlement,
the box applies its frozen activity-score bonus to at most `50 ETH - used`; overflow
receives neutral EV. Recorded usage stays capped at 10 ETH, so crossing that boundary
exhausts the allowance for later boxes. Eligibility is read at settlement, with no
purchase reservation. Ordinary boxes, AFKing, redemption, and internal ETH reward-spin
recirculation retain the normal 10 ETH allowance.

Game-over processing reserves existing claims and applicable deity refunds, credits 2% of
the remaining pool to the terminal level's top affiliate, and sends the rest to the main
terminal ticket jackpot. If no affiliate is ranked, the jackpot receives the entire pool.
The affiliate winner is fixed when the terminal cohort is latched, before any terminal
word exists; later score claims do not reopen the award. The terminal word is one the
game-over path requests itself after liveness froze purchases, even when the deadman
ends a game whose day is stuck in processing. If VRF is dead (a
request unanswered for 14 days) the ending is deterministic instead: deity refunds as
above, no affiliate share, and the rest split across every ticket of the terminal level,
claimed through `claimDeadVrf`. The later final sweep handles unclaimed balances.
Read the terminal paths separately from live-game withdrawal paths.

FLIP has special routing for VAULT and sDGNRS: their backing/allowances are not ordinary
wallet balances. Coinflip credits are not equivalent to minting immediately spendable
FLIP. The comp allowance is neither circulating FLIP nor vault mint backing.

## Purchase timing and pool acceleration

Level 0 has a 250-day purchase deadline (`_DEPLOY_IDLE_TIMEOUT_DAYS`). Later levels have
a 30-day purchase deadline: elapsed day 30 activates distress purchases, and game-over becomes eligible
on day 31 if the target is still unmet. A funded last-purchase/jackpot phase can finish
beyond that boundary. The deadline is read at the start of a caught-up day, so days a
VRF stall or an unattended stretch skipped are credited to it on catch-up; a stall has
14 days from its request before VRF counts as dead. The independent 30-day no-seal
deadman and the 30-day post-game sweep keep their separate timing rules.

Ordinary purchase dailies budget 4% of the future pool, split 75% to ticket backing
in the next pool, 23% to ETH prizes, and 2% to the insurance accumulator. These are
3%, 0.92%, and 0.08% of the future pool respectively, before integer rounding.
Unpaid ETH stays in the future pool; ticket conversion and winner caps are unchanged.
Level 0 retains its existing FLIP-only daily path; it does not run this ETH drip.

At the purchase-to-jackpot transition, the base next-to-future skim uses the elapsed
purchase age directly. For levels after 0:

| Purchase age | Base skim |
| --- | --- |
| Days 0–3 | 30% + level bonus |
| Days 3–8 | Linear decline to 15% |
| Days 8–30 | Linear rise to 45% + level bonus |

The level bonus remains one percentage point per ten levels within the century,
using the incoming purchase level as before; the trough excludes that bonus.
Interpolation floors only after multiplying by elapsed days, so day 30 reaches
the exact endpoint. If a funded transition finishes later, the rising slope continues,
with the existing 100% base-rate ceiling. The separate x9 bonus, ratio adjustment,
overshoot surcharge, randomness, 1% insurance skim, and 80% cap on the actual
future-pool take remain in place.

The level-0 transition (`purchaseLevel == 1`) keeps its original curve: 30% through
day 8, down to 13% on day 21, back to 30% on day 35, then +0.14 percentage points
per day. An x01 transition in a later century uses the accelerated curve.

## Comp accounting

The shared comp allowance starts at 4.96M FLIP-equivalent (`200 * CrapsPriceLib.NORMAL_VALUE`).
Each battle credits 2% of participating bankroll once at finalization, including high-seat multiples and paid,
pass, comp and protocol seats; bounty, donations and boosts are excluded.

Grants debit the shared allowance and, for delegates, their individual limit atomically.
Priced entries include bankroll and bounty; undrawn future entries use fixed estimates
without a later price true-up. Banked passes charge only the quantity actually granted.
Comps grant ordinary reward eligibility without burning player FLIP. Future reservations
must precede the day draw and prevent duplicate or conflicting seats.

For comp upgrades, the event field `burned` records the allowance charge; no player
FLIP is burned.

The vault owner and authorized comp delegates can also fund an open battle pool through
`DegenerusVault.crapsCompDonate(custom, index, granules)`. `custom = true` selects a
custom battle by its number; `false` selects one of today's daily window periods (0–6).
Each granule is 100 FLIP, so `crapsCompDonate(true, 1, 10)` adds 1,000 FLIP to custom
battle 1. The shared comp budget and a delegate's remaining allowance are debited
atomically. The table applies the ordinary donation cap and joinability checks;
closed or armed battles cannot receive funds. These donations earn no additional
comp allowance and consume no boon or quest credit. `CrapsCompDonated` records the
operator and charge; the table's `CrapsBonusDonated` records the vault as donor.

## Ticket materialization

`mineFlip` is the single engine entry: `DegenerusGame` delegates it to
`DegenerusGameMinerModule`, which selects the next action from storage
(`_nextMinerAction`) and runs the advance worker or drains existing read consumers
before the next daily request can reuse their randomness storage. Workers run by
delegatecall, preserving the original caller, and each chunk is admitted only while the
caller's gas covers its declared bound. Standalone advancement is a miner action like any
other and is paid by measured gas; terminal actions are unpaid. The bounty prices measured
gas above each call's first 1M at a capped basefee times a multiplier that starts at 0.3x and rises 0.45x per 30 minutes the work waits: 1.2x
after one hour, 2.1x after two. A caller with a deity pass, or a lazy/whale pass covering
the current level, earns double. A call that starts while the daily RNG lock is held earns
double again.

`Advance(18, lvl)` reports a fresh daily word applied with its jackpot field still
pending. `Advance(19, lvl)` reports committed ticket progress waiting for the previous
read consumers to finish before the next RNG request. These are distinct work stages;
neither changes the game phase by itself.

`rngComplete` is cached in slot 0 bit 248. A fresh normal request clears it;
consumer completion and the daily seal set it only after committed tickets, the
midday latch, sDGNRS redemption settlement, AFKing boxes, the combined human box/bet
cursor, Decimator rounds and read-bound Craps all finish. Requests
read this flag; unanswered retries preserve the same session and buffer tags.

There is one reusable `rngWordCurrent` and two physical queue tags, 0 and 1.
Slot 0 bit 252 selects write; read is its opposite. A normal fresh request swaps
only after read completion and resets the released queue headers in constant work.
The uint48 lootbox fields in events and APIs carry these physical tags, without a
monotonic counter. History must pair commitments and results with their publication
interval using block number and log index. AFKing boxes, ticket/foil generation
and Decimator settlement use the active session word. Pre-request AFKing stamps
cannot open until their daily seal; every pending stamp blocks subsequent requests.
Timed player claims retain their own required results independently.

The VRF callback authenticates the active request, adds the frozen daily nudge
count (0..255, stored in slot 0), and writes only the final word. Midday requests
apply no daily nudge. A mid-day request is issued only by `mineFlip`: an empty queue never
requests; pending work at or above the ETH threshold requests at no charge; pending work
below it (FLIP-only included) requests only when the `mineFlip` caller's donated LINK
credit covers the charge, which it then spends. A closed craps window waives both gates. Final values 0 and 1 are refused and remain retryable;
1 is the nonzero waiting sentinel. Mandatory keeper publication emits the applied
word and performs nudge/request cleanup outside the LINK-funded callback. Request
ID and timestamp retain nonzero idle values; the active flag controls authority.
Terminal advancement bypasses normal read completion and kills unfinished boxes,
bets and Craps rather than retaining earlier session words. Paid ending tickets
and already-earned claims follow the existing terminal distribution.

Purchases queue owed entries; the drain assigns traits from committed entropy. The round
worker groups up to four entries per seat; cards are client presentation. Resume cursors
and seated round state persist across chunks.

Only levels at or below the mint ceiling are ever minted: `level + 1`, or `level + 2` from
the seal that latches a level's last purchase day until the next request bumps `level`.
Minted levels use a double buffer, and each advance drains the read window
`[purchaseLevel - 1, mint ceiling]`. Every entry for a higher level waits, without traits,
in the far-future key space.

Level L+1 starts to exist when L's last purchase day latches at its seal. The seal moves
L+1 under the ceiling: its far-future pool freezes, and later L+1 entries take its write
buffer. The read side is fully drained at the seal, so the first buffer swap after it is the
first RNG request after it: typically a mid-day request (a closed craps window counts as
request work), otherwise the
last-purchase daily request (or, after a same-day turbo latch, that same request). The
frozen pool mints inside the unified sweep with that first cohort, on its word, before the
sweep counts as finished; keepers see it through `advanceDue`. Either way it is fully
minted before the last-purchase consolidation, so the BAF and the day-1 early-bird draw
read every L+1 ticket queued before the last-purchase request.

Unminted levels are drawn by wallet, one queue lane per wallet registration. Under the RNG
lock, a player far-future append reverts when it is a new registration (it would add a
lane); a top-up only raises an owed count and is allowed. Lootbox resolutions that run under the lock (Degenerette bets,
sDGNRS redemption claims, foil claims) revert in those cases; the player
can retry once the word lands.

Daily board: every day rolls one winning board (four traits plus the day's hero), which
the ETH, ticket and early-bird legs, the golden ticket and the foil claim all read. The
board's solo quadrant pays the day's headline ETH prize to one winner, and every ticket leg
on that board (purchase tickets, jackpot daily tickets, early-bird tickets) skips it unless
it is the only active bucket.

Jackpot battle: the day's sixth window (period 5) is one craps battle of paid seats (an
announced 6,000/8,000/10,000-FLIP base entry at 25/50/25 odds, direct or on a day ticket) and awarded seats drawn from the far-future
queues. The daily RNG request locks the paid field, its fee, and the award target. The
unscaled baseline is 0.5% of the recorded prize pool at the level's ticket price, at least
150,000 FLIP while `level` is 0 or 1 and 50,000 after. Stored Added is that baseline
scaled by the frozen fee divided by 8,000. The request latches the battle's pending bit. Stage 18 applies the fresh word and
does nothing else. Every later advance runs one battle step, stage 16 on jackpot days and 17 on
purchase days, until the field completes; only then does the day's ETH, ticket and
transition work run. The RNG lock stays held across all of it, including across midnight, so
the paid field, preferences, queues and the committed word cannot change. Level
1's purchase days, which pay no ETH jackpot, also run a trait-matched FLIP draw on the
day's board over level 1: up to 50 winners, one equal whole-100-FLIP share each; the
sub-share remainder and any unfilled share are not minted. Craps does not read or store the aggregate activity score. Equivalent entries receive the same
dice ranking and payouts. Wallet-funded entries and cash upgrades charge 5% extra unless the
player minted this/last level (next-level purchase-phase mints also qualify), has at least three
credited lifetime mint levels, or holds a deity pass. The latter two checks use the packed player
record and skip the current-level call. Awarded passes and vault comps retain their funded
entitlement without a newcomer charge.

At lock, 5% of unrolled gross Added funds the high-roller reserve, and the award target
is fixed at one per 10,000 FLIP of the **unscaled baseline**, capped at 500. The two
new uint32 fields, frozen fee and subsidy multiplier, occupy the spare bytes in the
round's slot 5; no previous member moves. The future battle word selects a separate
hidden subsidy multiplier (60% at 0.25x, 30% at 1x, 9% at 5x, 1% at 10x). The existing
event multiplier remains 90% at 0.5x, 9% at 3x, 0.9% at 20x and 0.1% at 100x.
Both average 1x. With integer floors, the pool is
`(paid units * frozen fee + (Added - floor(Added / 20)) * subsidyMultiplier) * eventMultiplier`.
High extras receive only fee-funded capital times the event multiplier; the reserve
receives neither roll. Price is public before entry, while the subsidy stays unknown
until the future word arrives. Award counts do not grow with either lottery. The Game
draws them in chunks of up to 50, continuing within the same transaction
while another full chunk fits the remaining gas:
each visit picks uniformly among nonempty eligible levels in the 99 unminted levels above
the mint ceiling, chooses a starting queue position, then walks every holder at that level
once, wrapping at the end. Levels are selected with replacement between visits, so a wallet
can hold multiple awarded seats. Chunk boundaries preserve the unfinished visit. It batch-reads the
distinct wallets' saved boards and appends one packed word per entry; the battle makes no
storage callbacks. The chunk that reaches the target seals the field: each unit's bankroll is
half its share of the main pool, rounded down to 300 FLIP (at least 300), its bounty is
bounded by that bankroll, and the dust stays in the pot. Each paid seat gets one place in
the Added-funded main allocation. Extra high units receive a separate, fee-only allocation
under the same pool multiplier. Only the base seats' fee-funded bankroll is booked as craps
action and comped 2%, once, at seal. Extra high fees earn comps equal to 9.6% of their
pre-roll at-risk value (all extra fees for a sole high seat, half for a contested high field),
and do not enter the action books. Every seat throws the same dice; an award keys its scatter,
survival coin and shooter boost to its own bet id. Seats settle through the table's normal
resolver, paid then day tickets then awards, on 1,500 work units per call; the sealing call
first charges its draw (110 units plus 10 per entry) and settles on the rest. The last seat
finalizes the field once: the best run takes the pot, a contested high lane pays its winner,
and the pot winner can claim RIU (5% of the progressive at a 25x peak, 10% at 120x, with the
pass/liquid split) and the biggest Dice Run record (100x floor, strict improvement).
After all seats settle, a separate 1-in-10 draw pays the accumulated high-roller reserve
to one uniformly sampled paid high seat, excluding sDGNRS; empty eligible fields carry the
reserve forward. This award is Coinflip credit and creates no extra action, comps or passes. Warm-up
and skipped days have no paid field; their award-only battle uses the day's otherwise unused
remainder-seven slot, which the lapse sweep never walks. The worst settle call is bounded near
8.6M gas and a full draw chunk measures up to 7.2M; see
[the preferences and jackpot battle interface](CRAPS-PREFERENCES.md) and the
`JackpotBattleStageGas`, `JackpotBattleDrawGas` and `JackpotBattleAwardsGas` tests.
The BAF scatter is 80% of the BAF pool (50% to each round's best BAF score, 30% to the
second) over 48 rounds of four samples: 12 each at the BAF level, level + 1, level + 2..5
and level + 6..99, including century levels. The two
unminted ranges sample one queue lane per wallet.

Century scatter no longer samples completed levels. Each forward band receives 25%
of scatter rounds (previously 1/6 at centuries); the retired 99-level band receives
none. This changes century candidate exposure, not the scatter pool or its 50/30
first/second split. Empty rounds still refund their allocation, so realized payouts
depend on populated candidates and their BAF scores.

BAF payout is staged. The x0 consolidation records the bracket's resolution day, arms the
award stage and reserves in `claimablePool` (debiting `futurePool`) the ETH term of the whole
award schedule: R scatter rounds paying (P/2)/R to the round's best BAF score and
((P*30)/100)/R to its second, then three head awards (P/10 top bettor, P/20 armed-day
depositor draw, P/20 word-picked third or fourth place). R is 48 below a 500 ETH pool and
doubles at each fourfold step from 500 ETH up to 1,536 at 128,000 ETH; the bands keep a quarter
of the rounds each and the head awards are fixed. The schedule depends only on the pool, so the
Decimator seal, the keep roll and the settled pools are fixed in that transaction. The following
advance calls (`STAGE_JACKPOT_BAF_AWARDS`, stage 19) draw and pay awards in index order in fixed
groups of eight. A round pair's four awards are drawn together when the pair starts
(`DegenerusJackpots.bafPairWinners`): two trait-bucket samples, or one eight-lane far-future
sample split between the two rounds, ranked by the frozen BAF scores. Ticket awards paid earlier
in the stage can add far-future lanes a later pair samples; the state each group starts from is
the same under every call partition, so a resumed stage redraws nothing already paid and gas
selects only how many groups a call runs. A head award (at least a twentieth of the pool) takes
half as claimable ETH and half as lootbox tickets or whale-pass halves; a scatter award is all
ETH or all tickets, alternating by round and rank. The last group returns the ETH term of awards
no candidate took to the pending future pool (the stage runs under the daily lock, with the
pools frozen), clears the board and bumps the bracket epoch. A game-over latch during the stage
releases the uncredited reservation into the distributable total.

The x0 last-purchase seal arms the next day's weighted depositor draw and, in the same step,
settles the vault's coinflip position through that day's applied result
(`depositCoinflip(VAULT, 0)`), so the vault's bracket score holds every winning flip the bracket
counts, as for a player who claims at the close of that day. The BAF day's own flip settles after
the next request and scores the next bracket. On an x0 purchase day every leg that can seal keeps
`BAF_VAULT_SETTLE` (one full 365-day claim walk) in its tail.

The global wallet registry is append-only: each wallet gets one permanent, one-based
uint32 ID. IDs are never reassigned. Queue words pack eight IDs; trait buckets pack
eight zero-based global owner indices per completed storage word in two parity buffers. The unfinished zero to seven
lanes live in the header above its uint32 count. Each buffer retains its full
level stamp; a per-buffer bitmap validates buckets at that actual level; takeover invalidates old counts without clearing payload words. The
individual drain aggregates trait occurrences before writing runs; the round drain
batches seats. Queue release clears the length in constant time. Bingo stays open
on completed inventory until that buffer is actually reassigned to L+2, so its
deadline depends on game progress. Unfinished normal paid ticket work and revealed
foil drainage defer takeover. A foil pack whose next-day entropy lands after its
level retired is consumed without writing traits into the newer buffer; its record
and tagged draw still support unexpired match/gold claims. Its old-level Bingo eligibility
has expired at the same retirement boundary.

`EntryOwnerRegistered` still identifies the level and zero-based owner index when a wallet
joins a queue; a wallet uses the same global index across levels. The Lens exposes
`walletIdOf` and `walletOfId` for direct identity lookup. Pending balances are separate:
near balances share one reusable word per wallet ID: even/odd levels each have
read/write lanes and an absolute-level tag. A parity can be rebound only after
both balances clear. Near queues reuse two roots per cohort. Far-future balances
use a fixed `uint256[13]` per owner: slot `(level - 1) % 100` selects one of 100
32-bit lanes, each holding 30 owed bits, snap-done and presence. The existing
far-future queue tags authenticate each slot's level before reading or topping up.
Far-future additions saturate at 2^30-1 through one shared clamp before narrowing.
Thanos fractions round on first drain touch using committed entropy and stable
identity, before a checkpoint persists the whole balance. Far-future queues
reuse 100 roots; rebinding a nonempty queue reverts.

IDs through 3,000,000,000 retain lazy registration at the ordinary ticket minimum.
An ordinary ticket purchase allocating a higher ID must contain at least 0.04 ETH
of nominal ticket value before bonus entries. Existing IDs keep the ordinary minimum;
passes and ticket-producing prizes can allocate freely. The rule applies equally to
ETH-equivalent ticket value funded by ETH, claimable balance, prepaid AFKING or FLIP.
There is no separate registration fee, and box spend or overpayment does not qualify a
smaller ticket leg.

`EntryTraitsRevealed` replaces `RoundTraitsGenerated`. Each anonymous log has four indexed
player keys, `(uint256(level) << 160) | uint160(player)`, and one `uint144` data word:
sixteen trait bytes followed by sixteen presence bits. Byte `4*j+q` is player position
`j`'s trait in quadrant `q`; bit `128+4*j+q` marks it present, including valid trait zero.
A full eight-seat round emits two logs, and unused trailing topics are zero. This is
entry inventory: it carries no round number, owner-registry position or card identity.
Consumers retain normal block/transaction/log order but cannot use the event as a round ID.

Query the Game address at each of the four topic positions, union by transaction hash
and log index, then explicitly decode the anonymous ABI and inspect every matching player
position. Signature-based `parseLog` cannot identify this event. Cross-level wallet history
requires enumerating level keys; there is no wallet-only wildcard inside a composite topic.
Named `TraitsGenerated` still covers per-entry and foil generation paths.

`ticketGenerationStartBlock[level]` at slot 70 is readable through `extsload` at
`keccak256(abi.encode(uint256(level), uint256(70)))`. Deployment initializes level 1 (level 0 never holds tickets);
level L+1 is stamped at L's first fresh mid-day request after meeting its goal, or when L's last purchase day latches
(the seal or a same-day turbo latch), whichever opens generation first. Later latches preserve
the original bound. This inclusive lower bound can precede actual generation; it is not a first-reveal
timestamp. Retries preserve it, and older levels retain their bounds.

## Recent settlement boundaries

The first fresh mid-day RNG request after a purchase level meets its goal activates the next
level's future-ticket pool. A daily request activates it early only on a turbo transition,
where the early-bird draw needs those tickets. Ordinary purchase dailies leave that pool
unminted for their jackpots. Mid-day requests retain the normal
LINK, basefee, pending-value and donation-credit rules. Retries keep their original cohort.
The queue freezes before its word is requested; advance calls then mint it in bounded
batches. Later next-level purchases enter the ordinary write buffer for a subsequent word.
A mid-day activation drains the future pool separately, leaving current-level queues for
the daily request, including during a turbo last-purchase window. Turbo daily activation
uses the ordinary sweep. The standard last-purchase transition still drains its frozen
next-level pool before jackpots, even without an earlier mid-day activation.
The daily retry can commit intervening current-level purchases,
and an unanswered request retains the 14-day deterministic ending. Early-created tickets
leave the unminted future-queue FLIP draw. No extra request is scheduled for ticket minting.

Jackpot phases use either one physical day (turbo) or three physical days. Every
non-turbo level uses the three-day schedule, even when reaching the purchase target
takes more than three days. `jackpotDuration()` returns 1 or 3. The counter tracks
completed physical draws: standard phases step 0 → 1 → 2 → 3, turbo phases 0 → 1.
The final draw pays the remaining current pool. One packed bit selects turbo;
an independent bit carries its coinflip bonus to the next purchase settlement.
The existing turbo trigger and BAF last-purchase window remain in place.

WWXRP has no vault mint allowance, escrow reserve or automatic century top-ups.
The vault or its current DGVE-majority owner can mint any amount for free through
`vaultMintTo`; the owner can also use `DegenerusVault.wwxrpMint`. Vault-held WWXRP
uses ordinary balances and burns. Standard ERC20 approvals and the trusted
minter registry remain available.


Purchase-phase ticket awards, early-bird tickets and the jackpot battle's steps are separate
bounded stages. The packed queue holds eight owner indices per word and must use
its codec helpers; Solidity array operations do not express its logical length.
`PackedTicketSampleLib` samples eight lanes from one selected word, with explicit
handling of a padded final word. These groups intentionally share a word draw.
Jackpot ticket and ETH legs award one group per checkpointed step and draw only the
groups they award, so a resumed quadrant repeats no draw and pays the same winners.
The BAF trait sampler consumes up to four of these lanes and caches the bucket's
packed-word root and owner-registry root once per call. A padding redraw loads
its source word through that cached root or from the header tail; entry weights and sampled order are unchanged.

Each jackpot-phase ETH quadrant can convert up to 25% of its original allocation
to full whale passes at 4.5 ETH each. The usual shares and ETH winner counts are
calculated first. The Jackpot module delegates a separate recipient draw and
claim credit to `WhaleModule.awardWhalePass`; it returns the exact cost credited
to futurePrizePool. The Jackpot module includes that cost in the current-pool
debit and pays the remaining ETH to the original winners. The solo ETH winner
still owns any golden-ticket arm. `QuadrantWhalePass` covers the conversion rules.

Purchase-phase and jackpot-phase ETH draws size their winners from the draw's ETH
budget. The three non-solo quadrants target 32, 16 and 4 winners and double at 40, 160,
640, 2,560 and 10,240 ETH, up to 1,024, 512 and 128. Each non-solo award is a whole multiple of 0.1 ETH: a quadrant pays fewer winners
than its target when its share, net of pass conversion, cannot fund 0.1 ETH each, and
its rounding leftover joins the solo prize, which settles last. An empty bucket's share
stays unpaid as before. The terminal jackpot keeps its fixed 152/104/48/1 geometry.
`JackpotWinnerScaling` covers the targets and the worked 5,000 ETH day.

Early-bird pricing still moves the entire 3% future-pool slice to nextPrizePool.
Every ticket leg (purchase daily, early bird and jackpot-phase daily) sizes its
winners from its ticket budget value: 32 per non-solo quadrant, doubling at 40 and
160 ETH to 128 per quadrant (384 in all); every winner gets
the same whole tickets, at least one. When that exceeds 25 tickets per winner and the
surplus after reserving 25 per winner covers at least one full prize pass (4.5 ETH of
award value), each winner keeps 25 and the surplus converts to even half-pass claim
units, derived again from the frozen budget at settlement. The leg distributes its
tickets over its board's three non-solo quadrants (the solo quadrant serves only when it
is the one active bucket). Its whole passes split across the quadrants that paid tickets
in proportion to their winners, with rounding passes one each in quadrant order, and each
such quadrant draws one fresh recipient from its own bucket at normal entry/deity weights.
A recipient need not have won immediate tickets. Pass selection uses separate tagged
entropy from the leg's committed quadrant seed; award amounts do not reroll recipients.
Settlement moves no ETH and the sub-pass remainder also stays in next. Below the
conversion conditions, the ordinary ticket payout remains intact.
`EarlyBirdWhalePass` covers the conversion rules.

Protocol deity grants occur after the deployment sequence. Their perpetual entries
and protocol boon cohorts have their own pre-request scheduling and closure rules.
Foil packs generate from the next daily request's committed cohort (never a mid-day word), then compare their four lines
against each eligible day's board, purchase and jackpot days alike, at the same face
table. Two tagged draw slots retain each board, level and payout seed. Match claims
expire after the logical draw day and following day, even if a stalled draw first
arrives later. Golden-ticket claims expire after the generation day and following day.
Each player has four tagged reusable pack records, including the four lines and
gold-paid flag, plus one word of reusable daily match bitmaps. A purchase may reuse
a slot only after the old pack has generated and its level, gold window and both
live match days no longer need it; a collision rejects the new purchase without
blocking advancement. Historical records are reconstructed from events.
Match randomness is fixed, but ETH caps, sDGNRS rewards, and recirculation use live
payout state; old wins are not reserved ETH obligations. A VRF stall skips missed days on
recovery and freezes auto-rebuy arming; a request unanswered for 14 days ends the game
deterministically. The NatSpec of `_livenessTriggered`,
`_vrfDead` and `_handleGameOverPath` states the implemented behavior.

At the first AFKing stage of each level, sDGNRS attempts a whale-pass purchase of
the largest group of five paid passes affordable from a quarter of its claimable,
capped at 100 paid passes. The attempt latch advances even if it buys nothing;
later chunks and days cannot retry the same level. A purchase consumes the stage's
shared work budget. Its ordinary daily box is separate from this level-start action.

At century transitions the BAF reservation and the Decimator draw precede the tagged 5d4
future-pool keep roll; the BAF awards themselves pay from the staged reservation afterwards. The keep range is 50–80%, with mean 65%. Consult the Advance module for
the exact pool snapshots and ordering; altering a pool size must not reroll winners.

At the final transition close after each x00 level, sDGNRS recycles a random 25–75% of all
live burns since the previous century close, immediately before the Coinflip
century seed. A tagged hash of the committed transition word and completed level
selects one of the 51 whole percentages; the event records it, and retries cannot
reroll a completed century. Its post-refill supply checkpoint captures both
redemption burns and automatic self-award burns without per-burn accounting writes. New inventory
is split Whale/Affiliate/Lootbox/Reward in a 1:3:2:1 ratio, with allocation dust to
Lootbox; PresaleBox and the wrapper receive no allocation. A processed-century
marker prevents replay, and terminal pool destruction permanently closes the
mechanism even when inventory is zero. Recycling moves no backing and changes no
pending redemption claims. See [economic disclosures](../ECONOMIC_DISCLOSURES.md)
for dilution and timing, and `SdgnrsCenturyRecycle` for the accounting tests.

## Invariants to preserve

- Game/module layouts agree; pinned delegatecall targets match their interfaces.
- Credited ETH/stETH obligations remain covered under the stated external-asset assumptions.
- Token supply/backing/virtual allowances reconcile without treating them as interchangeable.
- No double settlement, recipient substitution, duplicate ticket materialization or lost resume state.
- Entropy-dependent processing has the documented freeze boundaries; caller gas cannot choose work.
- Pool writes, unchecked arithmetic and advance-chain external calls remain covered by the source manifests.

### Decimator battle

The periodic Decimator is a shared-dice craps battle paid in ETH and half whale passes.
See [Decimator battle](DECIMATOR-BATTLE.md) for the full rules, ABI and accounting.
Ordinary x5 excluding x95 uses one jackpot day; x00 remains original-only. Manual burns
and top-ups require at least 2,000 whole FLIP. Automatic sDGNRS burns cap at four times
the previous original mean, bootstrap 8,000, skipping available amounts below 2,000.

For original count N and reserved pool P, available matching money is active non-solo
shares plus solo's excess over floor(35% of the priced ETH leg). M=min(N,floor(available*N/P))
generated slots cost F=ceil(M*P/N); no active non-solo cohort means M=0. Solo receives
min(activeNonSolo+soloShare-F,soloShare), split into its normal cash/pass award. Solo
weight is zero. Inactive shares and surplus above normal solo use the final-day unpaid sweep.

The fixed field T=N+M has exactly min(1000,ceil(T/2)) survivors, chosen by one hash draw
per floor-rounded stratum plus a common tagged random rotation. Original and generated
workers replay the same strata; the locked worker runs generated IDs and the unlocked
worker runs originals. Opposite-type strata are cheap skips, and the generated loop is
skipped entirely when M=0. At most 1,000 total engine runs occur, independent of population.
Original IDs 1..N and generated IDs N+1..T use one top-K heap, with
K=min(200,floor(T/2),max(20,ceil(T/10))). Enough survivors always exist to fill K.
Original scores use frozen stack times peak; generated scores use the original mean.
Both types share dice, board, tie and the bounded engine helper. Zero-quota rounds
release the reservation after sampled work; normal payouts keep the champion/pass rules.

One plan word stores soloAmount128, four weights16, generated count40, stratum cursor16
and mode8. The two-word round stores original pool/count/aggregate, phase, quota and
its stratum cursor. Only retained generated candidates store owners by ordinal 1..N.
Decimator owns funding and JackpotWork.paid; Jackpot pays normal solo cash/passes on
soloAmount. The existing final-day sweep handles unspent daily ETH. Every delegate shares
storage; this is a fresh-deployment change. Lens exposes the plan, both winner-owner types
and survivor replay from (word,lvl,T,stratum).

### High-roller jackpot reserve

`JackpotBattle.lockJackpotBattle` assigns 5% of gross, price-scaled, unrolled Added to a persistent reserve and leaves 95% for the main subsidy lottery. Award counts use the unscaled baseline and are fixed at lock. Neither hidden multiplier changes the reserve contribution. Once the field finalizes, any eligible high entry gives the event one 10% chance to pay the whole reserve through Coinflip credit. Each accepted high entry has one equal ticket; sDGNRS is excluded, the vault is eligible, and activity score is unused. Pass and comp entries consume their existing funding and qualify. Paid entry/upgrade closure freezes the field before the settling RNG. The cold module samples already-resolved paid seats in bounded batches, preserving its nominee/count/cursor; the final draw is idempotent. Reserve grants do not generate action, comps or another protocol multiplier.
