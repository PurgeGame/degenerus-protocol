# Architecture and accounting

## Contract boundaries

| Component | Responsibility |
| --- | --- |
| `DegenerusGame` + 12 game modules | Purchases, ticket materialization, advance/VRF, jackpots, lootboxes, side-games and terminal distribution |
| `DegenerusGameStorage` | Shared game/module storage; delegatecalls execute against the Game |
| `FLIP` + `Coinflip` | Token supply, burns, virtual vault allowance, coinflip stakes/credits and the separate craps comp allowance |
| `CrapsBattle` + `CrapsEngine` | Seat/field state and payouts; stateless dice calculation through a pinned STATICCALL |
| `DegenerusVault` | DGVE/DGVF share classes, vault-owned positions and comp distribution authority |
| `sDGNRS` / `DGNRS` / `GNRUS` | Reserve backing, transferable wrapper and charity rights |
| Affiliate, Quests, Jackpots | Referral rewards, activity state and jackpot support |
| Parimutuel | Growth bets; Game seals each outcome through `recordGrowth` |
| DeityPass, AFKingSubscriptionToken, RecordBounty, WWXRP | Pass/seat/record rights and auxiliary token rewards |
| Admin | VRF/feed recovery governance and bounded liquidity operations |

`ContractAddresses.sol` pins protocol dependencies. The deployment order has 31 entries;
the Vault also creates its two share tokens. `DegenerusGameLens` and `DeityBoonViewer`
are in scope but are not entries in that deployment sequence. Third-party renderers,
Chainlink, LINK and stETH have distinct trust boundaries described in Security.

## Main value flow

Ticket and ordinary lootbox ETH funds protocol prize pools. The presale-box proceeds
have a separate vault/sDGNRS split. Jackpot and redemption paths create claimable
obligations or game-specific credits; moving ETH/stETH to a player follows the relevant
claim/recipient checks. Permissionless processing is not authority to redirect payment.
Game-over processing distributes remaining obligations and later sweeps unclaimed balances.
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
