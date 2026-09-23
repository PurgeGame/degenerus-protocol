# Architecture and accounting

## Contract boundaries

| Component | Responsibility |
| --- | --- |
| `DegenerusGame` + 12 game modules | Purchases, ticket materialization, advance/VRF, jackpots, lootboxes, side-games and terminal distribution. The twelve delegatecall modules are Advance, Afking (`GameAfkingModule`), Bingo, Boon, Decimator, Degenerette, FoilPack, GameOver, Jackpot, Lootbox, Mint and Whale; `DegenerusGameMintStreakUtils` and `DegenerusGamePayoutUtils` are abstract bases inherited by modules, the Game and the Lens, not deployments |
| `DegenerusGameStorage` | Shared game/module storage; every delegatecall executes in the Game's storage context. Modules also delegatecall sibling modules from inside a delegatecall (Advance to GameOver, Jackpot and Mint; Mint to FoilPack and Lootbox; FoilPack to Degenerette and Jackpot; Afking and Whale to Lootbox; Decimator, Degenerette and Lootbox to further modules); `make check-delegatecall` pins each selector/target pair |
| `FLIP` + `Coinflip` | `FLIP`: token supply, burns, the virtual vault allowance and the separate craps comp lane (`_crapsCompAllowance`). `Coinflip`: daily flip stakes, settled credits and the record pool; it holds no comp state |
| `Craps`, `LootboxCraps`, `CrapsBattle` + `CrapsEngine` | `CrapsBattle is LootboxCraps is Craps` holds seat/field state and payouts; `CrapsEngine is Craps` is the one deployment after the table and exposes `settleSlip` as `external pure`, which is what makes the table's pinned call a STATICCALL |
| `CoinDrawBattle` | `CoinDrawBattle is Craps`, storage-free and GAME-only, deployed after `CrapsEngine`: plays the purchase-day fill draw's closed battle in memory and returns what each wallet is owed; the Game credits it |
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
RecordBounty, skipped when the pin is zero. The deployment order has 31 entries;
the Vault also creates its two share tokens. `DegenerusGameLens` and `DeityBoonViewer`
are in scope but are not entries in that deployment sequence. Third-party renderers,
Chainlink, LINK and stETH have distinct trust boundaries described in Security.

## Main value flow

Ticket and ordinary lootbox ETH funds protocol prize pools. Presale-box ETH is credited
80% to the Vault and 20% to sDGNRS as claimable (`_creditBoxProceeds`); the closing buyer
also receives the sDGNRS `PresaleBox` pool remainder once presale is drained. Jackpot and redemption paths create claimable
obligations or game-specific credits; moving ETH/stETH to a player follows the relevant
claim/recipient checks. Permissionless processing is not authority to redirect payment.
Game-over processing reserves existing claims and applicable deity refunds, credits 2% of
the remaining pool to the terminal level's top affiliate, and sends the rest to the main
terminal ticket jackpot. If no affiliate is ranked, the jackpot receives the entire pool.
The affiliate winner is fixed when the terminal cohort is latched; later score claims
do not reopen the award. A delivered daily word may be reused; see the allocation
timing exception in `KNOWN-ISSUES.md` and the seed rules in `audit/RNG-DOMAINS.md`.
The later final sweep handles unclaimed balances.
Read the terminal paths separately from live-game withdrawal paths.

FLIP has special routing for VAULT and sDGNRS: their backing/allowances are not ordinary
wallet balances. Coinflip credits are not equivalent to minting immediately spendable
FLIP. The comp allowance is neither circulating FLIP nor vault mint backing.

## Purchase timing and pool acceleration

Level 0 retains its 365-day purchase deadline. Later levels have a 30-day purchase
deadline: elapsed day 30 activates distress purchases, and game-over becomes eligible
on day 31 if the target is still unmet. A funded last-purchase/jackpot phase can finish
beyond that boundary. Existing VRF grace, missed-day forgiveness, the independent
30-day VRF deadman, and the 30-day post-game sweep keep their separate timing rules.

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

The shared comp allowance starts at 4.56M FLIP-equivalent. Each battle credits 2% of
participating bankroll once at finalization, including high-seat multiples and paid,
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
first RNG request after it: typically a craps battle's mid-day request, otherwise the
last-purchase daily request (or, after a same-day turbo latch, that same request). The
frozen pool mints inside the unified sweep with that first cohort, on its word, before the
sweep counts as finished; keepers see it through `advanceDue`. Either way it is fully
minted before the last-purchase consolidation, so the BAF, the day-1 early-bird and the
jackpot-phase bonus draws read every L+1 ticket queued before the last-purchase request.

Unminted levels are drawn by wallet, one queue lane per wallet registration. Under the RNG
lock, a player far-future append reverts when it is a new registration (it would add a
lane); a top-up only raises an owed count and is allowed. Lootbox resolutions that run under the lock (Degenerette bets,
Decimator claims, sDGNRS redemption claims, foil claims) revert in those cases; the player
can retry once the word lands.

Coin jackpot: purchase days pay the ETH drip on the active level and a coin fill draw
over unminted levels; jackpot days run the coin draw on the bonus traits of level + 1, and
the carryover board also draws from level + 1. Every trait coin draw splits its daily budget in
half. The craps half pays up to 25 winners, one per 2,400 FLIP: each gets a seat on
tomorrow's opener, and what is left of the half upgrades gifts, from the front, to a whole
day at 20,400 FLIP more (the 22,800 day-pass value less the seat). A whole-day gift banks
one normal craps pass, spendable only on a future day whose word does not exist yet. If the
pass bank is saturated, the winner receives its 22,800 FLIP value instead. The coin half,
plus whatever the craps half left, pays up to 25 winners equal whole-100-FLIP shares; the
sub-share remainder is not minted. An opener winner the table cannot seat (one already
holding tomorrow, or the vault or sDGNRS, which `openBonusDay` seats for the whole day) is
paid the opener's expected cost, 2,400 FLIP. Opener seats go through the craps comp door
(`vaultComp` kind 5), which burns nothing for the Game (the draw mints that much less FLIP
instead), after the Game vets the winner with an `extsload` of the table's day claims.
Every seat the Game writes (these and lootbox pass reservations) carries a fixed standing
of 100 rather than a read of the holder's activity score: above the boost floor and most
casual wallets, below a dedicated player; `amendSlip` re-reads the real score. The trait
draw's craps pulls come first.

The purchase-day fill draw pays no seats, passes or shares: its whole budget is one closed
craps battle, played and paid in the draw's own transaction. It walks up to 50 wallets: it
picks an unvisited level in `[purchaseLevel + 1, purchaseLevel + 99]`, walks its queue from
a random lane, taking each wallet at most once, until it has its wallets or the level is
exhausted, then picks again (at most 16 picks). `CoinDrawBattle` (a storage-free, GAME-only
contract at `COIN_DRAW_BATTLE`) plays the field on the day's word: half the budget is the
stakes, split into equal units of at least 50 FLIP (each exactly five boards deep) (a wallet walked twice holds
two units but plays one run, and the units multiply only what that run pays), and half is
the pot. Each run is the scheduled Dice Run shape (five rounds deep, all ten chips thrown by
the dice, goal at five times the bankroll, no shooter boost) capped at exactly 200 rolls and
22 shooters (the longest of 200,000 simulated runs; 0.004% reach it): a bust pays nothing, a run stopped
by either cap or latched at the goal pays its bankroll per unit, and the pot goes to the paid run with the highest ending bankroll (the earlier-drawn
wallet on a tie; with no paid run it is not minted). Each run payout and the pot land on
the protocol's award figures (whole FLIP up to 1,000, the EV-preserving 100-FLIP granule
above). The Game credits the result in one batch. The field, the budget and the entrants' queues are fixed before the word exists, so
the battle is a jackpot result, not an entry window. A roll budget under one hand's 512 is
exact in `Craps._settleSlip`: the last hand is cut where it runs out and refunds its live
stakes; the table's 8,192 budget keeps its between-shooters meaning. The two caps bound
`resolve` at 7.31M gas for a full field whatever the dice do (test/craps/CoinDrawBattle.t.sol),
and every purchase-day fixture that runs the battle must clear the 16.7M transaction cap with
that whole bound added to its measured gas. The BAF scatter is 80% of the BAF pool (50% to each round's best BAF score, 30% to the
second) over 48 rounds of four samples: 12 each at the BAF level, level + 1, level + 2..5
and level + 6..99 (centuries: 8, 8, 8, 8, and 16 on the previous 99 levels). The two
unminted ranges sample one queue lane per wallet.

The level owner registry is append-only. Trait buckets pack eight uint32 owner indices
per storage word. The individual drain aggregates trait occurrences before writing runs;
the round drain batches seats. Queue release clears the length in constant time.

`EntryOwnerRegistered` maps level/index to owner; both `lvl` and `owner` are indexed, so a
wallet's registry positions at a level are one log filter. Storage bucket owner indices
are zero-based; generated inventory is separate from the queue's remaining owed balance.

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
level L+1 is stamped when L's last purchase day latches (the seal, or a same-day turbo
latch), before any of its drains. This inclusive lower bound can precede actual generation; it is not a first-reveal
timestamp. Retries preserve it, and older levels retain their bounds.

## Recent settlement boundaries

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


Purchase-phase ticket awards, early-bird tickets and carryover tickets are separate
bounded stages. The packed queue holds eight owner indices per word and must use
its codec helpers; Solidity array operations do not express its logical length.
`PackedTicketSampleLib` samples eight lanes from one selected word, with explicit
handling of a padded final word. These groups intentionally share a word draw.

Protocol deity grants occur after the deployment sequence. Their perpetual entries
and protocol boon cohorts have their own pre-request scheduling and closure rules.
Foil packs resolve tomorrow's committed draw. A VRF stall skips missed days on
recovery, freezes auto-rebuy arming, and can enter the existing deadman path;
`VRF-STALL-AND-DEADMAN-PLAN.md` describes a further design that is not implemented.

At the first AFKing stage of each level, sDGNRS attempts a whale-pass purchase of
the largest group of five paid passes affordable from a quarter of its claimable,
capped at 100 paid passes. The attempt latch advances even if it buys nothing;
later chunks and days cannot retry the same level. A purchase consumes the stage's
shared work budget. Its ordinary daily box is separate from this level-start action.

At century transitions the BAF/Decimator draws precede the tagged 5d4 future-pool
keep roll. The keep range is 50–80%, with mean 65%. Consult the Advance module for
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
pending redemption claims. See [the recycling design](SDGNRS-CENTURY-RECYCLE-PLAN.md)
and [economic disclosures](../ECONOMIC_DISCLOSURES.md) for dilution and timing.

## Invariants to preserve

- Game/module layouts agree; pinned delegatecall targets match their interfaces.
- Credited ETH/stETH obligations remain covered under the stated external-asset assumptions.
- Token supply/backing/virtual allowances reconcile without treating them as interchangeable.
- No double settlement, recipient substitution, duplicate ticket materialization or lost resume state.
- Entropy-dependent processing has the documented freeze boundaries; caller gas cannot choose work.
- Pool writes, unchecked arithmetic and advance-chain external calls remain covered by the source manifests.

### Decimator claim entropy

A decimator round packs its pool, total qualifying burn and a 32-bit claim seed into one
mapping-value slot. The seed is the low 32 bits of `keccak(word, DECIMATOR_BOX_TAG)`, so
no other consumer of the day word shares its bits; the claim-box root re-hashes it with
the tag and the fixed round level, and the box resolver then mixes the winning owner.
Winner selection still uses the full word before the snapshot. The layout is unchanged.
