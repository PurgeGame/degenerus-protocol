# Architecture and accounting

## Contract boundaries

| Component | Responsibility |
| --- | --- |
| `DegenerusGame` + 16 delegatecall components (`eip170`) | Purchases, ticket materialization, the miner engine and VRF, jackpots, lootboxes, side-games and terminal distribution. Under the primary `eip170` profile the Game (`Eip170Game` = `GameFacade` + `GameBoonActions`) delegatecalls sixteen deployments: Actions (also the Bingo route), Purchase, Mint, DegenesisFoil (Degenesis plus the foil user entries; also the Degenesis route), Advance, Jackpot, JackpotDraw, Whale, TicketFoil (Ticket plus the foil worker), Lootbox, Boon, Degenerette, Afking, Endgame (the GameOver module), Decimator and MinerRng (the `mineRun` entries plus Rng; also the Rng route). The `glamsterdam` alternate folds the same logic into a Game shell that hosts the purchase, miner, bingo and bet entries, plus Endgame, Daily, Pass and Box workers. Shared source lives in `contracts/modules/*`; `DegenerusGameMintStreakUtils` and `DegenerusGamePayoutUtils` are abstract bases inherited by modules, the Game and the Lens, not deployments |
| `DegenerusGameStorage` | Shared game/module storage; every delegatecall executes in the Game's storage context. Modules also delegatecall sibling modules from inside a delegatecall (Advance to GameOver, Jackpot, Afking, Boon, Degenesis and Ticket; Jackpot to Whale for early-bird and quadrant pass awards, and to Decimator and Ticket; the foil entries to Degenerette, Jackpot and Mint; Degenesis to Boon, Mint and Whale; Afking to Degenesis and Whale; Degenerette and Whale to Lootbox; the miner engine to its workers); `make check-delegatecall` pins each selector/target pair |
| `FLIP` + `Coinflip` | `FLIP`: token supply, burns, the virtual vault allowance and the separate craps comp lane (`_crapsCompAllowance`). `Coinflip` (`CoinflipCore` through the selected profile): daily flip stakes, settled credits and the record pool; it holds no comp state. Under `eip170`, Quests and Affiliate are separate deployments (`Eip170Quests`, `Eip170Affiliate`); under `glamsterdam` the Coinflip deployment also hosts them |
| `Craps`, `LootboxCraps`, `CrapsBattle` + `CrapsEngine` | `CrapsBattle` (`CrapsBattleCore` through the selected profile; `CrapsBattleStorage is LootboxCraps, CrapsCustomTerms` and `LootboxCraps is Craps`) holds seat/field state and payouts; `CrapsEngine is Craps, CrapsCustomTerms` is a deployment ahead of the table (under `glamsterdam` the table hosts the engine) and exposes `settleSlip` and `settleBattle` as `public pure` and `settleBattleCompact_g439244` as `external pure`, which is what makes the table's pinned call a STATICCALL; the table calls the compact wrapper, which runs `settleBattle` to play a seat's whole run (board, scatter, shooter boost and rotation) under the shared 600-roll between-shooter budget and 1,111-roll ceiling and returns the payment, scaled bankroll, battle ranking score (goals: high point, then ending bankroll; busts: shooters completed, then whether anything was kept, then high point, then remainder) and longest hand, so the comparator lives in the engine, not the table |
| `JackpotBattle` | `JackpotBattle is CrapsLifecycleViews, CrapsProgressiveActions` (both on `CrapsBattleStorage`). Under `eip170` it is the `CRAPS_LIFECYCLE_MODULE` deployment (`Eip170JackpotBattle`), reached only through `CrapsBattle`'s lifecycle router, which delegatecalls it in the table's storage; under `glamsterdam` the table inherits it. It locks the daily jackpot battle's field at the RNG request, draws and appends its awarded entries, seals the field and serves its views. The table's normal resolver settles and pays every seat |
| `DegenerusVault` | DGVE/DGVF share classes, vault-owned positions and comp distribution authority |
| `sDGNRS` / `DGNRS` / `GNRUS` | Reserve backing, transferable wrapper and charity rights |
| Affiliate, Quests, Jackpots | Referral rewards, activity state and jackpot support |
| Parimutuel | Growth bets; Game seals each outcome through `recordGrowth` |
| DeityPass, AFKingSubscriptionToken, RecordBounty, WWXRP | Pass/seat/record rights and auxiliary token rewards |
| Admin | VRF coordinator-swap recovery governance, native VRF funding (`donateVrf`, which forwards the whole payment to the coordinator subscription and credits the donor mid-day request credit in the Game) and bounded liquidity operations; plain ETH sent to it goes to the Vault |
| `DegenerusOwnerGovernance`, `Icons32Data` | DGVE-escrow owner approval (below); the icon data store |
| `libraries/*`, `DegenerusTraitUtils` | Internal libraries inlined at compile time (including ActivityCurve, BitPacking, BoundedCall, Entropy, FlipRound, GameTime, JackpotBucket, MineFlipGas, PackedTicketSample, PriceLookup, SigFig, TraitUtils); in scope, not deployments |

`ContractAddresses.sol` pins every protocol contract plus the external endpoints and build
parameters: the VRF coordinator, the key hash, the lane's maximum gas price and native
premium, stETH, the ENS reverse registrar, the CREATOR address and the deploy-day boundary.
VRF requests are paid in native ETH from the coordinator subscription. The ENS registrar
receives a best-effort raw `setName(string)` call from the constructors of the named
protocol contracts, skipped when the pin is zero. The `eip170` deployment order
(`deployments/eip170.json`) has 37 entries; the `glamsterdam` alternate
(`deployments/glamsterdam.json`) has 21, with shared addresses aliasing hosted components.
The Vault also creates its two share tokens. `DegenerusGameLens` and `DeityBoonViewer`
are in scope but are not entries in that deployment sequence. Third-party renderers,
the VRF coordinator and stETH have distinct trust boundaries described in Security.

## Main value flow

Ticket and ordinary lootbox ETH funds protocol prize pools. Degenesis-box ETH is held in
`claimablePool` until its cohort splits (below). Jackpot and redemption paths create claimable
obligations or game-specific credits; moving ETH/stETH to a player follows the relevant
claim/recipient checks. Permissionless processing is not authority to redirect payment.

Every box with an activity-score bonus draws one shared per-(wallet, level) allowance.
The first 10 ETH of bonus spend takes the full bonus; the bonus then tapers linearly to
half at 20 ETH and to neutral at 40 ETH. A box earns the integral of that weight over
the spend it covers. Every route draws at settlement against the live opening level.
Ordinary and pass/cover orders freeze their score, per-box value and modifiers at purchase;
opening draws once for the entire order before any reward roll or nested ETH spin.
Purchases made after a cohort's word is published consume no allowance until their
later cohort opens. The engine settles redemption, daily AFKing, then queued human
boxes, so daily AFKing boxes now receive allowance before human orders in that cohort.
Direct reward and ETH recirculation boxes also draw when they settle; existing immediate
foil-claim recirculation can still consume allowance between keeper calls. Penalty and
neutral boxes draw nothing, and protocol-owned sDGNRS daily boxes remain exempt.

Queued orders use the existing basis-point eligible fraction, shared across their boxes;
daily AFKing and direct boxes retain their exact-wei calculation. Pass/cover grants draw
against count times the stored per-box value (whole 0.001 ETH units), with discarded dust
remaining in the funded pools. Dust can move the rounded fraction by one basis point: a 1 ETH + 1 wei
cover at 9 ETH used now represents 1 ETH and gets a 10,000-bps fraction rather than
9,999 bps. Its bonus budget at 145% EV increases by 0.000045 ETH, not merely one wei.

Each ordinary purchase picks one box type: small, medium or large (1x/5x/25x the purchase
level's ticket price, resolved at purchase) or a custom of 0.01–2,000 ETH in 0.001 ETH steps,
1–100 boxes (input `[quantity:7][kind:2][customUnits:21]`). The queue stores one 85-bit
entry per order, three per storage word: wallet ID, per-box units, a 12-bit activity-score
code (exact to 2,042, then 14-point steps to 30,000), effective boost bps, quantity and the
distress flag. Logical position `p` lives in word `p / 3` at bit `(p % 3) * 85`; write
counts, `boxCursor`, event tags and seeds stay in logical positions, so the worker admits,
settles and resumes one order at a time at any lane. A lane-0 append overwrites the whole
word; lanes 1 and 2 OR into it. System grants (whale, lazy, deity, subscription cover) floor
per box to whole units and stay inside the 2,000 ETH cap by their formulas; a whale purchase
of up to 1,000 paid passes folds its 10% box leg to `min(quantity, 100)` boxes of at most
4 ETH. Redemption, daily AFKing, direct and recirculated boxes never enter the queue and keep
their wide amounts.

An ending decided at the purchase deadline first settles every outstanding account loan, repaying at
the current manual-repayment price or seizing ([account loans](ACCOUNT-LOANS.md)), so a
defaulted borrower's refunds and terminal awards accrue to its lender. Game-over processing
reserves existing claims and applicable deity refunds, credits 2% of the remaining pool to the terminal level's top affiliate, and
sends the rest to the main terminal ticket jackpot. If no affiliate is ranked, the
jackpot receives the entire pool.
The affiliate winner is fixed when the terminal cohort is latched, before any terminal
word exists; later score claims do not reopen the award. The terminal word is one the
game-over path requests itself after liveness froze purchases. If 14 days pass without a
completed daily session, or a request's word is still not in use 14 days after it was sent,
the ending is deterministic instead, even if VRF would still answer: no loan settlement and
no terminal request, deity refunds as
above, no affiliate share, and the rest split across every ticket of the terminal level,
claimed through `claimDeadVrf`. The later final sweep handles unclaimed balances.
Read the terminal paths separately from live-game withdrawal paths.

FLIP has special routing for VAULT and sDGNRS: their backing/allowances are not ordinary
wallet balances. Coinflip credits are not equivalent to minting immediately spendable
FLIP. The comp allowance is neither circulating FLIP nor vault mint backing.

## Degenesis sale

Degenesis is a seven-day launch sale of boxes, kept separate from purchases and lootboxes. Day 1 is
the deploy day; Degenesis day `c` (1..7) is day index `c + 1` (`GameTimeLib.DEGENESIS_START_DAY = 2`),
and `MAIN_LAUNCH_DAY = 9` is the first post-Degenesis day. The sale has no aggregate ETH cap.
All its logic lives in `DegenerusGameDegenesisModule`; outside it the game pays a constant
timestamp compare (credit accrual) and slot-0 reads of `degenesisClosed`.

**Credit.** While the requested logical day is below 9, a qualifying spend earns `spend / 4`
Degenesis credit on the buyer's wallet ID (`degenesisCredit`, view `degenesisCreditOf`): tickets
(Mint `totalCost`), ordinary lootboxes, whale, lazy and deity passes (full charged price) and foil
premiums. Only ETH,
claimable and prepaid parts qualify; FLIP-paid parts, reward grants, daily AFKing deliveries, Degenesis
purchases and the Vault and sDGNRS bodies earn nothing. Credit is permission to spend, not payment, and
expires unused when the window closes.

**Purchase.** `purchaseDegenesisBox(uint32 id, uint256 amount)` is payable, a standalone entry
forwarded by the Game facade to the module. Sale day 2..8 and liveness are required, `amount` is at
least 0.01 ETH in whole 0.0001-ETH units, and the unit count fits 38 bits (about 27.5M ETH per order).
It consumes `amount` of credit 1:1, pays from `msg.value`, then the buyer's claimable, then prepaid
AFKing balance (overpay is credited to the payer's AFKing), and adds `amount` to `claimablePool`.
The Vault wallet ID cannot buy. It pays no affiliate commission and earns no quest, streak or
activity credit. Orders pack three to a slot (`degenesisOrders`: ID 32, units 38, seconds-into-day
15 bits per lane); `degenesisDays[c]` holds the cohort's volume `V` in units, its order count and the
split flag.

**Cohort split and pricing.** `prepareDegenesis_g47(day)` runs inside `prepareRequestBoundary`, before the
daily request, while `degenesisClosed < 7`. A cohort is sealed once its day index is below the
request day. The split sends `V / 4` to the Vault budget (`degenesisVaultBudget`, inside
`claimablePool`, excluded from Vault claimables), `V / 4` to sDGNRS AFKing funding, `V / 4` to
the future pool, and `V / 4` to insurance in `yieldAccumulator`. The Vault and sDGNRS quarters
stay inside `claimablePool`; the future and insurance quarters leave it together. A
request after a stretch with no requests splits every sealed cohort at once. Pricing then closes
empty sealed cohorts and prices one nonempty cohort once the previous cohort has closed, with
`Q = min(2.5T, 2/3 of the Degenesis pool)` and `T` = 20B tokens on days 1-3, 10B on days 4-7. Pricing
writes `degenesisActive` (Q, paid, bound day, cursor); the reservation is `1.5Q`, which no award
sum can exceed. Cohorts price strictly in order, so a settlement backlog delays the next cohort's
randomness and never lowers its rate.

**Binding.** `_recordDailyRng` copies the bound day's word into `degenesisWord` when
`degenesisClosed < 7 && boundDay == day`. V, the pool
balance and the orders are fixed before the request, so no outcome input changes afterwards.

**Settlement.** `MinerAction.DegenesisSettle` is selected after `GrowthSettle` while `degenesisWord`
is nonzero and the terminal bit is clear; it delegatecalls `runDegenesisWork_g1860(allowance)`. It is not
an RNG consumer and never gates daily completion or requests. Each order's outcome is a pure function
of the bound word and the frozen cohort, with seed `hash4(DEGENESIS_ORDER_DOMAIN, word, day << 32 |
index, walletId)`: 50% FLIP-valued, 40% sDGNRS, 10% WWXRP, with an independent size roll.
FLIP-valued results scale the ladder by `base(day) / 2 x earlyBonus x K / (K + V)` (K = 46 ETH),
collapse to hundreds above the round threshold, and denominate half the time into Craps day passes
(12 high-roller passes at most); a result below one whole FLIP, or a lost sub-pass fraction, pays the
WWXRP consolation. sDGNRS awards are `units x Q x [5000, 15000] bps / V`; a zero award or an empty
pool pays WWXRP. Coin credits flush in one `creditFlipBatch` per chunk of at most 128 orders; the
cursor advances before each order pays, and each order admits against its own branch bound plus the
flush it still owes. Orders resolve to the reward account's wallet ID; sDGNRS goes to its payee.

**Closing.** The cohort closes when its last order resolves (or immediately when empty): the
reservation is released, `degenesisActive` and `degenesisWord` clear and `degenesisClosed`
increments. The seventh close burns the remaining `Pool.Degenesis` balance, once.

**Vault and sDGNRS funding.** `Vault.spendDegenesis(recipientId, whalePass, quantity, boxOrder, maxCost)`
(owner only) reaches the module through the facade. It moves `maxCost` from `degenesisVaultBudget`
into Vault claimable, runs the existing claimable-funded Mint or Whale purchase, and returns what the
purchase did not take. The selected allocated account receives the products and normal rewards,
without new DeGenesis credit or operator approval. Recipient 0 selects the Vault. The Vault
ledger returns to its original balance; the actual cost leaves the restricted budget and
`claimablePool` for the ordinary purchase pools.
sDGNRS subscribes with AFKing funding first, and `topUpSdgnrsAfking_g318()` tops its AFKing funding up to
10 ETH from claimable (above the 1-wei sentinel) before each once-per-level bulk whale attempt.

**Daily engine and craps.** Before `MAIN_LAUNCH_DAY` the daily phase processes a Degenesis day by
unlocking randomness only (`STAGE_DEGENESIS_DAY = 21`): no level-1 FLIP draw, no purchase-phase
ticket or ETH leg, no `lastPurchaseDay` latch (the seal and the early-turbo latch both require
`day >= MAIN_LAUNCH_DAY`, keyed on the processed day), so the level cannot advance. The request that
opens day 9 follows the normal early-turbo rule. Scheduled craps windows and jackpot-battle locks
start on Degenesis day 2 (`lockJackpotBattle` returns false before `_firstWindowDay`); the battle
awards no seats for window days before `MAIN_LAUNCH_DAY`, so paid seats share the whole subsidy; pass
reservations before day 3 are refused and `deliverPasses` clamps to day 3.

**Terminal.** Game-over setup first runs `splitDegenesis()` over all cohorts (idempotent). After the
deity-refund budget and before `gameOver` is set, it zeroes `degenesisVaultBudget` and sDGNRS's whole
AFKing balance and subtracts them from `claimablePool`, so they join the final prizes
(`DegenesisFundsReleased`); the missing-randomness check counts them as distributable. Unresolved
orders are forfeited: `degenesisActive` clears with the terminal inventory burn.

## Purchase timing and pool acceleration

Game days are logical: `dailyIdx` advances once, at an accepted daily VRF request, and a stall
or unattended stretch neither skips nor backfills days. Every level, level 0 included, has a
30-game-day purchase deadline measured from `purchaseStartDay` (`_PURCHASE_TIMEOUT_DAYS`);
level 0's timer starts at the first post-Degenesis day (`MAIN_LAUNCH_DAY`). Reaching
`purchaseStartDay + 30` activates distress purchases, and game-over becomes eligible once that
day's session has completed and a later wall-clock reset day has begun, if the target is still
unmet. A funded last-purchase/jackpot phase can finish beyond that boundary. The independent
14-day no-completion deadman (`_vrfDeadmanFired`: no daily session completed in 14 days) and the
30-day post-game sweep keep their separate timing rules.

Ordinary purchase dailies budget 4% of the future pool, split 75% to ticket backing
in the next pool, 23% to ETH prizes, and 2% to the insurance accumulator. These are
3%, 0.92%, and 0.08% of the future pool respectively, before integer rounding.
Unpaid ETH stays in the future pool; ticket conversion and winner caps are unchanged.
Level 0 retains its existing FLIP-only daily path; it does not run this ETH drip.

At the purchase-to-jackpot transition, the base next-to-future skim uses the elapsed
purchase age in logical days directly. For levels after 0:

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

`mineRun` is the single engine entry. The miner engine (`GameMiner`) is hosted per profile:
under `eip170` the Game delegates `mineRun` to the MinerRng deployment, under `glamsterdam`
the Game contains it. It selects the next action from storage
(`_nextMinerAction`) and runs the advance worker or drains existing read consumers
before the next daily request can reuse their randomness storage. Workers run by
delegatecall, preserving the original caller. When the mandatory first unit is a VRF
request, `BoundedCall.admitFirst` reverts `InsufficientExecutionGas` unless gas covers
the request minimum plus its tail. Each chunk is admitted only while both
the remaining worker allowance and actual available gas cover its cold-path bound
and complete call, checkpoint and return tail. A call can execute multiple admitted
chunks; there is no fixed transaction gas ceiling. Standalone advancement is a miner
action like any other and is paid by measured gas; terminal actions are unpaid. The bounty prices measured
gas above each call's first 1M at a capped basefee times a multiplier that starts at 0.3x and rises 0.45x per 30 minutes the work waits: 1.2x
after one hour, 2.1x after two. A caller with a deity pass, or a lazy/whale pass covering
the current level, earns double. A call that starts while the daily RNG lock is held earns
double again.

`Advance(18, lvl)` reports a fresh daily word applied (the daily phase stages follow it).
`Advance(19, lvl)` reports a group of staged BAF awards drawn and paid. These are distinct
work stages; neither changes the game phase by itself.

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

The VRF callback (`rawFulfillRandomWords`, in the Game itself) accepts only the coordinator and
only the active request: the low 64 bits of the request ID must equal the stored `vrfRequestId`
(packed into the coordinator slot; ID 0 and superseded IDs are ignored, and a fresh request whose
ID has zero low 64 bits is refused). It stores the raw word and nothing else. Daily nudges
(`reverseFlip`, count 0..255, stored in slot 0) move only the coinflip word: the daily apply
adds the frozen count to the raw word for Coinflip, while the recorded daily word and every other
consumer (lootbox and session words, jackpots, quests, craps, WWXRP, the terminal word) use the raw
word. `DailyRngApplied(day, word, nudges)` records the apply. Midday requests apply no nudge. A
mid-day request is issued only by `mineRun`: an empty queue never requests; pending work at or
above the ETH threshold requests at no charge; pending work below it (FLIP-only included) requests
only when the `mineRun` caller's donated native request credit (`middayRngCredit`) covers the
charge, which it then spends. The charge is 300,000 x (max(basefee, 0.01 gwei) + 0.25 gwei) x 2
wei per request. A mid-day request is also refused above the owner-set basefee ceiling (1x for
lootbox work, 4x for a closed craps window) and, outside a craps window, below 1.5 times the
subscription's minimum fulfillment balance. A closed craps window waives the pending-work and threshold gates. Raw
values 0 and 1 are refused and remain retryable; 1 is the nonzero waiting sentinel. Mandatory
miner publication emits the applied word and performs request cleanup outside the callback.
Request ID and timestamp retain nonzero idle values; the active flag controls authority.
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
sweep counts as finished; miners see it through `advanceDue`. Either way it is fully
minted before the last-purchase consolidation, so the BAF and the day-1 early-bird draw
read every L+1 ticket queued before the last-purchase request.

Unminted levels are drawn by wallet, one queue lane per wallet registration. Under the RNG
lock, a player far-future append reverts when it is a new registration (it would add a
lane); a top-up only raises an owed count and is allowed. Lootbox resolutions that run under the lock (Degenerette bets,
sDGNRS redemption claims) revert in those cases; the player
can retry once the word lands. Foil claims revert `RngLocked` for the whole time the daily lock
holds the pools frozen: an ETH tier pays from the live future pool. The pending-pool word keeps
its top bit (255) as a sentinel between freezes and carries no seed.

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
[final battery] gas and a full draw chunk measures up to [final battery]; see
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
(`playCoinflip(VAULT, 0)`), so the vault's bracket score holds every winning flip the bracket
counts, as for a player who claims at the close of that day. The BAF day's own flip settles after
the next request and scores the next bracket. On an x0 purchase day every leg that can seal keeps
`BAF_VAULT_SETTLE` (one full 90-day claim walk) in its tail. A separate daily-phase checkpoint
settles the Vault every 45 resolved days before any phase can unlock, using the Game’s own successful-settle
stamp. Both routes bank winnings through the same zero-deposit helper; RNG application and terminal
resolution acquire no new Vault dependency.

Coinflip retains 15 seven-day pages per wallet, with absolute page tags and a tagged overflow fallback
for a collision with live stakes. Claims read these pages and advance the existing cursor. Stakes and
rolling carry older than 90 resolved days forfeit; stored banked winnings do not. BAF uses two tagged
score records per wallet, alternating brackets, preserving the closing and next bracket simultaneously.
Affiliate earnings use one retained word: two 35-bit exact scores, five clipped bonus-history lanes,
a level tag and the immutable upline cache. Scores cap at 34,359,738,367 per level; actual commissions
remain unchanged. See [storage reuse](STORAGE-REUSE.md) for layouts and reader migration.

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

`EntriesQueued` (with its scaled and range variants) identifies the wallet ID and level when
entries are queued, and `WalletRegistered` fires once per wallet ID; a wallet uses the same global
index across levels. The Lens exposes
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

`ticketGenerationStartBlock` at slot 47 holds the latest window: the level in its low24 bits,
then the inclusive first block above it. Read the slot directly with `extsload_g2807007(bytes32(uint256(47)))`
and require the level tag to match. `TicketGenerationStarted(level, blockNumber)` preserves historical
bounds. Deployment marks level1 (level0 never holds tickets); level L+1 is stamped at L's first fresh
mid-day request after meeting its goal, or when L's last purchase day latches, whichever opens
generation first. Repeated marks preserve the first block. The bound can precede actual generation;
it is not a first-reveal timestamp.

## Recent settlement boundaries

The first fresh mid-day RNG request after a purchase level meets its goal activates the next
level's future-ticket pool. A daily request activates it early only on a turbo transition,
where the early-bird draw needs those tickets. Ordinary purchase dailies leave that pool
unminted for their jackpots. Mid-day requests retain the normal
native-balance, basefee, pending-value and donation-credit rules. Retries keep their original cohort.
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
The vault or the DGVE governance executor can mint any amount for free through
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
payout state; old wins are not reserved ETH obligations. A VRF stall leaves the logical day
where it was (recovery backfills nothing) and freezes auto-rebuy arming; 14 days without a
completed daily session, or a request whose word is not in use 14 days after it was sent, ends
the game deterministically. The NatSpec of `_livenessTriggered`,
`_vrfDead` and `_handleGameOverPath` states the implemented behavior.

At the first AFKing stage of each level, sDGNRS attempts a whale-pass purchase of
the largest group of five paid passes affordable from a quarter of its claimable,
capped at 1,000 paid passes. The attempt latch advances even if it buys nothing;
later chunks and days cannot retry the same level. A purchase consumes the stage's
shared work budget. Its ordinary daily box is separate from this level-start action.

At century transitions the BAF reservation and the Decimator draw precede the tagged 5d4
future-pool keep roll; the BAF awards themselves pay from the staged reservation afterwards. The keep range is 50–80%, with mean 65%. Consult the Advance module for
the exact pool snapshots and ordering; altering a pool size must not reroll winners.

At the final transition close after each x00 level, sDGNRS recycles a random 25–75% of all
live burns since the previous century close. A tagged hash of the committed transition word and completed level
selects one of the 51 whole percentages; the event records it, and retries cannot
reroll a completed century. Its post-refill supply checkpoint captures both
redemption burns and automatic self-award burns without per-burn accounting writes. New inventory
is split Whale/Affiliate/Lootbox/Reward in a 1:3:2:1 ratio, with allocation dust to
Lootbox; Degenesis and the wrapper receive no allocation. A processed-century
marker prevents replay, and terminal pool destruction permanently closes the
mechanism even when inventory is zero. Recycling moves no backing and changes no
pending redemption claims. See [economic disclosures](../ECONOMIC_DISCLOSURES.md)
for dilution and timing, and `SdgnrsCenturyRecycle` for the accounting tests.

## Invariants to preserve

- Game/module layouts agree; pinned delegatecall targets match their interfaces.
- Credited ETH/stETH obligations remain covered under the stated external-asset assumptions.
- Every allocated wallet ID, protocol IDs included, starts with a 1-wei claimable sentinel outside `claimablePool`. No path pays it out, so `claimablePool` equals the sum over IDs of (claimable − 1 + prepaid), and no credit in metered work writes an empty balance slot. Only the final game-over sweep takes it, at most 3 wei for the protocol sinks.
- Token supply/backing/virtual allowances reconcile without treating them as interchangeable.
- No double settlement, recipient substitution, duplicate ticket materialization or lost resume state.
- Entropy-dependent processing has the documented freeze boundaries; caller gas may select a safe checkpoint, never a committed outcome.
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

## DGVE owner approval

[Owner governance](OWNER_GOVERNANCE.md) executes the bounded owner controls after escrowed approval exceeds 50.1% of the live DGVE supply. Voting delegates can manage allocated votes; each depositor alone can withdraw their tokens. Initial icon uploads use a one-time creator setup window, which closes permanently at completion or governance takeover.
