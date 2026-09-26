# Degenerette bet queue

Degenerette bets resolve the same way lootboxes do: a permissionless keeper crank
walks a queue and settles what it can afford, instead of the player or a
dedicated resolver paying to settle each bet. This replaces the old per-player
`degeneretteBets`/`degeneretteBetNonce` bet book and its own resolver
(`degeneretteResolve`).

## Queue and bet id

Each bet is one storage word appended to `degeneretteQueue[index]`
(`contracts/storage/DegenerusGameStorage.sol`), where `index` is the lootbox
RNG index active when the bet is placed. A bet's id is its queue position + 1,
scoped to that index (not global, and no longer per-player). Placement only
appends while `index`'s RNG word is still unset; once the word lands the queue
for that index is frozen (no further placements), and it is either resolved by
the sweep or resolved early by anyone via `resolveDegeneretteBets`.

`degeneretteQueue` occupies the storage slot vacated by the retired WWXRP
whale-pass mapping (`wwxrpJackpotWhalePassBracketAwarded`, slot 21). The old
per-player `degeneretteBets` / `degeneretteBetNonce` mappings are gone; the
biggest-spin record bounty now lives in `degeneretteRecordBounty` (slot 37,
keyed `(index << 64) | betId`), and `earlyTicketLevel` moved into the freed
space right after it (slot 38; its old slot, 75, is now unused). Nothing else
in the storage layout shifted.

### Bet word layout (LSB -> MSB)

| Bits | Field | Notes |
| --- | --- | --- |
| 0..159 | owner | bet payee |
| 160..164 | symbol | chosen hero symbol 0..31; quadrant = symbol >> 3 |
| 165..169 | spinCount | 1..25 |
| 170 | currency | 0 = ETH, 1 = FLIP |
| 171 | record flag | set when a biggest-spin record bounty is armed in `degeneretteRecordBounty` |
| 172..187 | activity | activity score in whole points |
| 188..251 | stake per spin | in currency units: ETH = gwei, FLIP = whole FLIP |
| 252..255 | reserved | always zero |

## Placement rules

`placeDegeneretteBet(player, currency, amountPerSpin, spinCount, symbol)` only
accepts ETH (0) and FLIP (1); `spinCount` is capped per currency (ETH 25, FLIP
15). `amountPerSpin` must be a whole multiple of the currency's stake unit —
1 gwei for ETH, 1 whole FLIP for FLIP — and at least the currency's minimum bet
(0.005 ETH / 100 FLIP); any violation, an out-of-range symbol, or a bet placed
against an already-revealed index reverts `InvalidBet` (or `RngNotReady` for
the revealed-index case). A self-or-operator-funded bet may also consume a
per-currency stake boon, which raises the effective stake per spin by a
percentage of the (capped) total bet, spread across the spins and then floored
to the stake unit — the player never spins on an un-funded fractional unit.

## Sweep integration

The human-box sweep, `DegenerusGameLootboxModule.openHumanBoxes`, walks a
monotonic cursor `(boxCursorIndex, boxCursor)` across finalized RNG indices.
At each index it opens every ready box in `boxPlayers[index]` first, then —
once that index's box entries are exhausted (`cur - qlen`, where `qlen =
boxPlayers[index].length`) — continues the same cursor into
`degeneretteQueue[index]`, delegatecalling
`DegenerusGameDegeneretteModule.sweepDegeneretteBets(index, pos, budget,
mustRunFirst, rngWord)` for the remaining walk budget. Both lists are frozen
once the index's word lands (placement and box deposits both require an unset
word), so the combined position stays stable across calls. The sweep only
advances past an index once both its boxes and its bets are drained; an
un-worded index halts the whole walk so nothing downstream is orphaned.

Two entry points reach this sweep:

- `mineFlip()` — the permissionless keeper crank (`DegenerusGame.sol`, routed
  through `GameAfkingModule`), which pays the caller a bounty for the work it
  runs.
- `openBoxes(maxCount)` — a permissionless, **unrewarded** liveness valve that
  opens AFKing boxes first, then spends any remaining budget on the same
  human-box sweep. Only `mineFlip()` pays a bounty.

`sweepDegeneretteBets` is resumable mid-queue: it resolves bets from `pos`
while `unitsSpent < budget`, and the first bet of a call always runs
(`mustRunFirst`) so no oversized bet can wedge the cursor for later callers —
every other bet that would exceed the remaining budget breaks (not skips),
leaving the cursor exactly there for the next call.

### Frozen-pool hold

`sweepDegeneretteBets` returns immediately (no-op) while `prizePoolFrozen` is
set, because the frozen-pool ETH path can revert `Insolvent` when the pending
buffer runs short, and a revert there would stall the whole box-open frontier
behind the bet queue. This is safe only because the freeze itself only ever
runs inside the RNG lock the sweep already waits out (an un-worded index halts
the walk before it), so the sweep never observes a freeze mid-walk that it
also needs to walk through.

### Budget vs credited work

Each queued bet is priced into the sweep's walk-unit budget at a **worst-case**
rate from its own word, so a call can bound its total gas without simulating
the resolution:

| Charge | Constant | Value |
| --- | --- | --- |
| ETH bet entry | `BET_ENTRY_WEIGHT_ETH` | 36 units (prices a cold 1-spin win that scores 7+: box + sDGNRS award, up to ~169k) |
| FLIP bet entry | `BET_ENTRY_WEIGHT_FLIP` | 4 units |
| Per ETH spin | `BET_SPIN_WEIGHT_ETH` | 2 units |
| Per FLIP spin | `BET_SPIN_WEIGHT_FLIP` | 1 unit |
| Armed record | `BET_RECORD_WEIGHT` | +6 units |
| Zeroed/skip slot | — | 1 unit |

The keeper bounty, however, is credited only for the work the call actually
ran (`workGas`, converted to units by `BET_WORK_UNIT_GAS`):

| Work | Constant | Value |
| --- | --- | --- |
| Base per resolved bet | `BET_WORK_BASE_GAS` | 5,000 gas |
| Per spin | `BET_WORK_SPIN_GAS` | 3,500 gas |
| A win box opened | `BET_WORK_BOX_GAS` | +65,000 gas |
| Unit divisor (floor) | `BET_WORK_UNIT_GAS` | 4,700 gas/unit |

Because the budget charge is worst-case and the bounty is actual-work, a
self-keeping caller who resolves their own cheap bet earns less bounty than
the budget it consumed — self-keeping is unprofitable by construction.
Measured sweep cost per bet: ~9.1k gas for a 1-spin loss, ~68k for FLIP 15
spins, ~100k for ETH 25 spins without a box, and ~80-86k for a 1-spin ETH win
that opens a box.

## Manual resolve API

`resolveDegeneretteBets(uint48 index, uint64[] betIds)` is permissionless and
pays no keeper reward; it lets anyone settle chosen bets at `index` ahead of
the sweep (credits always go to each bet's owner). The first id fails fast
with `InvalidBet` if it is zero, out of range, or already resolved; later ids
in the same call are skipped instead, so a racing duplicate settle bails
cheaply without reverting the whole batch.

`degeneretteBetInfo(uint48 index, uint64 betId)` is a view that returns the
raw queued bet word (zero once resolved or if the id is unknown/out of
range).

## Removed surface

- `degeneretteResolve(address[], uint64[])` — the old keeper helper and its
  flat ~1 FLIP reward. `MinerBounty` kind 3
  (`MINER_BOUNTY_DEGENERETTE_RESOLVE`) is retired; queued-bet resolutions now
  earn the box-open bounty (kind 2, `MINER_BOUNTY_BOX_OPEN`) via the sweep.
- `DegenerusVault.gameResolveDegeneretteBets` — the vault's wrapper around the
  old per-player resolve call. The vault's bets are now resolved by the
  `mineFlip()` sweep like anyone else's; no resolve call is needed.
- The per-spin `DegeneretteResult` event — replaced by one `DegeneretteResolved`
  event per bet (below).

## Event format

`DegeneretteBetPlaced(address indexed player, uint32 indexed index, uint64
indexed betId, uint256 packed)` is emitted at placement; `packed` is the
queued bet word (layout above).

`DegeneretteResolved(address indexed player, uint32 indexed index, uint64
indexed betId, uint256 totalPayout, uint32 resultTraits, bytes spins)` is
emitted once per resolved bet, whether resolved by the sweep or by
`resolveDegeneretteBets`. `spins` packs 5 bytes per spin (spin 0 first): 4
bytes of big-endian player traits, then one byte of `score (bits 0-3) | gold
matches (bits 4-6)`. Per-spin payouts are recomputable off-chain from each
spin's score and gold, the bet word's stake-per-spin and currency, and its
activity score — nothing else needed to itemize an indexer's view of a bet's
spins beyond this one event. `PayoutCapped` (ETH pool-cap overflow to
lootbox) is unchanged.

## Gas

Placement is roughly unchanged versus the old per-player book: one new queue
slot plus the array length write replaces the old bet slot plus nonce-counter
write, and a player's very first-ever bet is now about 17k gas cheaper (no
nonce slot to initialize). Resolution is about 2.4k gas per spin cheaper than
before, from the packed per-bet event replacing the old per-spin event — and
under the new model players no longer pay resolution gas at all; the keeper
crank (or an early permissionless resolver) does.

## Settlement order and indexing

Everything a bet's spins roll — player tickets, the house reel, scores, gold
matches, the FLIP survival flip and rounding — is fixed by the index word and
the bet's own id, so no choice made after the word lands can change them. A
few payout legs read live state instead, so the order bets settle in can shift
their size, exactly as the old per-player resolve could: the ETH leg is capped
at 10% of the live future pool (later wins in a busy index see a smaller pool),
the S>=7 sDGNRS award is a share of the live Reward pool, and the win box and
affiliate legs price at the live level. Anyone may settle any bet early with
`resolveDegeneretteBets`, so a bettor can put their own winning bet first.

`PayoutCapped` carries no bet id, but every capped spin of a bet emits it
before that bet's `DegeneretteResolved` (and after the previous bet's), so an
indexer attributes it by log order within the transaction. Claimable ETH is
credited once per run of consecutive bets with the same owner, not per bet;
per-bet ETH follows from the packed spins, the 3-tier split and any
`PayoutCapped` of that bet.
