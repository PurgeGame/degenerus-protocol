# Architecture and accounting

## Contract boundaries

| Component | Responsibility |
| --- | --- |
| `DegenerusGame` + 12 game modules | Purchases, ticket materialization, advance/VRF, jackpots, lootboxes, side-games and terminal distribution. The twelve delegatecall modules are Advance, Afking (`GameAfkingModule`), Bingo, Boon, Decimator, Degenerette, FoilPack, GameOver, Jackpot, Lootbox, Mint and Whale; `DegenerusGameMintStreakUtils` and `DegenerusGamePayoutUtils` are abstract bases inherited by modules, the Game and the Lens, not deployments |
| `DegenerusGameStorage` | Shared game/module storage; every delegatecall executes in the Game's storage context. Modules also delegatecall sibling modules from inside a delegatecall (Advance to GameOver, Jackpot and Mint; Mint to FoilPack and Lootbox; FoilPack to Degenerette and Jackpot; Afking and Whale to Lootbox; Decimator, Degenerette and Lootbox to further modules); `make check-delegatecall` pins each selector/target pair |
| `FLIP` + `Coinflip` | `FLIP`: token supply, burns, the virtual vault allowance and the separate craps comp lane (`_crapsCompAllowance`). `Coinflip`: daily flip stakes, settled credits and the record pool; it holds no comp state |
| `Craps`, `LootboxCraps`, `CrapsBattle` + `CrapsEngine` | `CrapsBattle is LootboxCraps is Craps` holds seat/field state and payouts; `CrapsEngine is Craps` is the one deployment after the table and exposes `settleSlip` as `external pure`, which is what makes the table's pinned call a STATICCALL |
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
worker groups up to four entries per seat; cards are client presentation. Current/near
queues use a double buffer; far-future queues have a separate key space. Resume cursors
and seated round state persist across chunks.

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
`keccak256(abi.encode(uint256(level), uint256(70)))`. Deployment initializes levels 0..5;
a fresh level-promoting RNG request stamps the newly opened level+5 window before any
drain. This inclusive lower bound can precede actual generation; it is not a first-reveal
timestamp. Retries preserve it, and older levels retain their bounds.

## Recent settlement boundaries

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

At the final transition close after each x00 level, sDGNRS recycles half of all
live burns since the previous century close, immediately before the Coinflip
century seed. Its post-refill supply checkpoint captures both redemption burns
and automatic self-award burns without per-burn accounting writes. New inventory
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
