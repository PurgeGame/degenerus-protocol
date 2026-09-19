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
| `libraries/*`, `DegenerusTraitUtils` | Internal libraries inlined at compile time (ActivityCurve, BitPacking, Entropy, FlipRound, GameTime, JackpotBucket, PriceLookup, SigFig, TraitUtils); in scope, not deployments |

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
The affiliate winner is fixed at settlement; later score claims do not reopen the award.
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

## Ticket materialization

Purchases queue owed entries; the drain assigns traits from committed entropy. Four
entries make one whole ticket. Current/near queues use a double buffer; far-future queues
have a separate key space. Resume cursors and seated round state persist across chunks.

The level owner registry is append-only. Trait buckets pack eight uint32 owner indices
per storage word. The individual drain aggregates trait occurrences before writing runs;
the round drain batches seats. Queue release clears the length in constant time.

`EntryOwnerRegistered` maps level/index to owner. `RoundTraitsGenerated.seatOwners` packs
index-plus-one into eight lanes; zero is an empty lane. Storage bucket indices themselves
are zero-based. Event consumers must not confuse those encodings.

## Invariants to preserve

- Game/module layouts agree; pinned delegatecall targets match their interfaces.
- Credited ETH/stETH obligations remain covered under the stated external-asset assumptions.
- Token supply/backing/virtual allowances reconcile without treating them as interchangeable.
- No double settlement, recipient substitution, duplicate ticket materialization or lost resume state.
- Entropy-dependent processing has the documented freeze boundaries; caller gas cannot choose work.
- Pool writes, unchecked arithmetic and advance-chain external calls remain covered by the source manifests.
