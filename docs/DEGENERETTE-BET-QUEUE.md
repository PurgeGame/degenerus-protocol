# Degenerette bet queue

FLIP has zero decimals: pass integer token amounts directly to the API. ETH amounts
are wei.

Degenerette bets resolve the same way lootboxes do: the permissionless miner crank
(`mineRun(uint32)`) walks a queue and settles what its gas allowance admits. There is
no per-player bet book and no separate resolver entry point.

## Queue and bet id

Each bet is a 128-bit lane, two per storage word, appended to `degeneretteQueue[buffer]`
(`contracts/storage/DegenerusGameStorage.sol`), where `buffer` is the physical
RNG write buffer (0/1) when the bet is placed. A bet's id is its position + 1,
scoped to that buffer. Placement appends only to the write buffer; the request's
seal freezes it, and the sealed read buffer resolves only through the miner
chain, in queue order, after its box entries.

The queue is manually addressed: bet `p` sits at
`keccak256(degeneretteQueue[buffer].slot) + (p >> 1)`, shifted by
`(p & 1) * 128`. The Solidity array length is
never written. The write buffer's bet count lives in `lootboxRngPacked` bits
152..183 and commits in the same write that adds the bet's pending ETH or FLIP;
the seal copies it into `degeneretteReadCount` (beside `degeneretteCursor`) and
restarts the write count at zero. The biggest-spin record bounty lives in
`degeneretteRecordBounty`, keyed `(buffer << 64) | betId`.

### Compact bet lane (LSB -> MSB)

| Bits | Field | Notes |
| --- | --- | --- |
| 0..31 | owner | bet owner's wallet ID |
| 32..36 | symbol | chosen hero symbol 0..23; quadrant = symbol >> 3; Dice excluded |
| 37..41 | spinCount | 1..25 |
| 42 | currency | 0 = ETH, 1 = FLIP |
| 43 | record flag | set when a biggest-spin record bounty is armed in `degeneretteRecordBounty` |
| 44..59 | activity | activity score in whole points |
| 60..123 | stake per spin | in currency units: ETH = gwei, FLIP = whole FLIP |
| 124..127 | reserved | always zero |

Storage, resolution, placement events and public views use this same 124-bit
payload directly. Two lanes share one storage word. There is no stored processed
bit: the read cursor alone marks the resolved prefix.

## Placement rules

`betDegenerette(uint32 id, uint8 currency, uint128 amountPerSpin, uint8 spinCount,
uint8 symbol)` accepts only ETH (0) and FLIP (1); any other currency reverts
`UnsupportedCurrency`. `spinCount` is 1..25 for ETH and 1..15 for FLIP.
`amountPerSpin` must be a whole multiple of the currency's stake unit (1 gwei for
ETH, 1 whole FLIP for FLIP) and at least the currency's minimum bet (0.005 ETH /
100 FLIP). A spin-count or amount violation, a symbol above 23, an ETH `msg.value`
above the total bet, or a boosted stake above 64 bits reverts `InvalidBet`; any bet
after the liveness trigger reverts `GameOver`. Every bet binds to the current write
buffer, whose word is not yet requested, so no bet can target a revealed word. A
self- or operator-funded bet may also consume a per-currency stake boon, which
raises the effective stake per spin by a percentage of the (capped) total bet,
spread across the spins and then floored to the stake unit; the player never spins
on an unfunded fractional unit. A gifted bet never consumes the recipient's boon.

## Sweep integration

`mineRun(uint32)` runs the read cohort's consumers in a fixed order
(`_rngConsumerStage`, stages 1..6): sDGNRS redemption settlement, pending AFKing
boxes, human box entries (`GameAfkingModule.runHumanBoxWork_g315`), Degenerette
bets (`DegenerusGameDegeneretteModule.runDegeneretteWork_g670`), the Decimator and
read-bound Craps. The bet worker walks `degeneretteCursor` up to
`degeneretteReadCount`, admits each bet against its declared gas bound, and
resolves it against the buffer's published session word. It writes the advanced
cursor once at the end of a progressing batch. Resolution never writes to the
bet words. A transient cursor blocks worker reentry and hides the in-flight
settled prefix during payout callbacks; a revert rolls back payouts and progress.

Buffer reuse restarts counts and cursors without clearing the stored words.
Placement overwrites each reused lane; the current count hides the old tail.

## Bet view

`degeneretteBetInfo(uint48 index, uint64 betId)` is a view that returns the
compact bet lane (zero once resolved or if the id is unknown/out of
range).

## Event format

`DegeneretteBetPlaced(uint32 indexed player, uint32 indexed index, uint64
indexed betId, uint256 packed)` is emitted at placement; `packed` is the
queued bet word (layout above).

`DegeneretteResolved(uint32 indexed playerId, uint32 indexed index, uint64
indexed betId, uint256 totalPayout, uint32 resultTraits, bytes spins)` is
emitted once per resolved bet, always by the sweep. `spins` packs 5 bytes per spin (spin 0 first): 4
bytes of big-endian player traits, then one byte of `score (bits 0-3) | house
wild count (bits 4-6)`; bit 7 is zero. Traits use the Degenerette lane format
(`[0][wild][color][symbol]` per byte, quadrant = byte position; the player's hero
lane is its only wild) and `resultTraits` is the spin-0 house ticket in the same
format. Per-spin payouts are recomputable off-chain from each spin's score and
wild count, the bet word's stake-per-spin and currency, and its
activity score; this one event itemizes a bet's spins. `PayoutCapped(uint32
indexed playerId, uint256 cappedEthPayout, uint256 excessConverted)` is emitted
for an ETH spin whose cash leg exceeds the pool cap; `excessConverted` is that
spin's whole lootbox share (split remainder plus cap overflow).

## Settlement order and indexing

Everything a bet's spins roll (player tickets, the house reel, scores, house
wilds, the FLIP survival flip and rounding) is fixed by the index word, the bet's
symbol and spin positions, and the bet's own id, so no choice made after the word
lands can change them. A
few payout legs read live state instead, so the order bets settle in can shift
their size: the ETH leg is capped at 10% of the live future pool (later wins
in a busy index see a smaller pool), the S>=7 sDGNRS award is a share of the
live Reward pool, and the win box and affiliate legs price at the live level.
The sweep fixes that order: it resolves a queue strictly in id order, so no
caller can move a bet ahead of an earlier one to claim a bigger share of a
live-priced leg.

`PayoutCapped` carries no bet id, but every capped spin of a bet emits it
before that bet's `DegeneretteResolved` (and after the previous bet's), so an
indexer attributes it by log order within the transaction. Claimable ETH is
credited once per run of consecutive bets with the same owner, not per bet;
per-bet ETH follows from the packed spins, the 3-tier split and any
`PayoutCapped` of that bet.
