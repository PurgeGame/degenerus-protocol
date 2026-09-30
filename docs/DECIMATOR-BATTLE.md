# Decimator battle

The periodic Decimator now burns FLIP into a shared-dice craps competition with ETH prizes.
The former bucket lottery and ETH/lootbox payout split are removed. Everything from entry
accounting through the last ETH credit executes on chain. This change requires a fresh
protocol deployment; it is not a migration of live bucket records.

## Entry and timing

`FLIP.decimatorBurn(player, amount, chips)` retains its operator authorization and 1,000 FLIP
minimum. A wallet gets one accumulated entry per event, regardless of top-up count.
There is no configured maximum burn and no amount-based chip discount.

`chips` is the entry's board, in the normal battles' thirty-bit encoding and under their
rules: ten three-bit leg counts, at most three chips on a leg, at most seven named in all,
never both the pass line and don't pass. Zero leaves the whole board to the dice. Each burn
sets the board, so the last burn before the window closes decides it; every burn precedes
the sealed word. The vault enters through `coinDecimatorBurn(amount, chips)`; the protocol's
sDGNRS auto-entry plays a fully random board.

Each burn adds:

```
base = amount + completed quest bonus + consumed Decimator boon bonus
chips = floor(base × degenMultBps × dayFactor / (10,000 × 10^18))
startingStack += chips
```

Existing quest rewards still credit Coinflip; their chip addition and the existing boon
bonus (which applies to at most 50,000 base FLIP per burn) are retained. The protocol's
sDGNRS auto-entry spending policy remains capped at 500,000 FLIP. That policy does not cap
player burns or the amount receiving the degen multiplier.

The battle multiplier interpolates in integer basis points through:

| Degen score | Multiplier |
|---:|---:|
| 0 | 1x |
| 235 | 1.7049x |
| 500 | 1.9x |
| 30,000 and above | 2x |

The entry-day factor is `0.9^d`, where `d` counts protocol day boundaries since the window
opened. Protocol days reset at 22:57 UTC. Advance stamps the opening day; the first burner
does not start the clock. Opening day receives 1x, then 0.9x, 0.81x, 0.729x, and so on.
Both multiplier and timing lock separately for each burn. Top-ups do not reprice earlier
chips or inherit their earlier timing. The old 1.2x opening modifier, final-day modifier,
and first-500,000 multiplier cap are gone. The original activity curve remains for WWXRP.

Timing uses 18-decimal exponentiation by squaring with downward rounding at each product,
bounded by the 24-bit day offset. A burn that rounds to zero chips reverts atomically.

## Run and ranking

Entry closes before the resolving VRF word is known. The sealed round stores its full word,
entrant count and ETH pool. All entries use the same event dice. Each plays ten chips: the
ones its board names, the dice scattering the rest, with total opening wager equal to
one-fifth of its starting stack. Wagers double every three shooters. Existing owner-specific
survival draws remain, and the shooter-profit boost follows the normal battles' row for the
number of named chips (`Craps._shooterBoostTerms`): a fully random board keeps the natural
15% chance of a 32% boost, and each named chip trades some of it away. There is no rotating
boost. There is no goal, protected bankroll, payout for surviving bankroll or cash-out.
A run ends at bust, after 64 shooters, or at exactly 511 rolls, and is ranked by the
highest virtual bankroll it reached. Nothing is wagered or returned: the bankroll exists only to
score the run. When the roll cap stops a hand mid-way, chips still on the table count at face
value for that last reading. The bounds come from 200,000 simulated shared-dice runs over every
board size: none reached 64 shooters and 10 (in 2 of 1,000 rounds) reached 511 rolls. They
bound a run's gas, not any payout. The engine exposes them as `settleSlipBounded(..., bounds)`; a replay must pass the
same `(511 << 16) | 64`.

Ranking uses the highest bankroll at a **completed shooter boundary**, including the
initial bankroll; a run the roll cap stops mid-hand takes its last reading at the cut. Busting later does not erase the high point. To avoid a wager-type cap on
large burns, the engine runs in normalized units: 3,000 starting FLIP and ten 60-FLIP chips.
The exact 512-bit product of original starting stack and normalized peak determines ranking;
the common denominator is 3,000 FLIP. It introduces no truncation in comparisons. A stack is
held in 160 bits (a burn that would cross 2^160 wei of chips reverts; that is about 10^12
times FLIP's uint128 supply ceiling), so the product's high word always fits the 192 bits a
retained node gives it. This normalized process defines the virtual chips' rounding behavior.

After each run, a separately tagged fair coin controls eligibility. **Tails never enters the
leaderboard and gets no prize**, even with the highest raw peak. Heads compete for places.
Repeated settlement cannot reroll an entry. A separate 192-bit random tiebreak orders equal
peaks, with immutable entry id as the final fallback. The coin does not depend on the run, so
settlement flips it first and runs the engine only for heads. A tails run is still exactly
replayable off chain: every engine input is public after sealing and `settleSlipBounded` is a
pure function at the pinned engine address.

Domain-separated roots use `keccak256(abi.encode(tag, fullWord, level[, entryId]))`:
`decimator.battle.dice.v1` omits entry identity; `board.v1`, `final-coin.v1` and `tie.v1`
include it. The final coin is derived from the same sealed word, so its replay order does
not imply later-arriving entropy.

## Prizes

For `N` original entries, the quota is `K = min(100, ceil(N/10))`. Keep the highest `K`
HEADS entries. Actual winners `W` may be fewer if fewer than `K` coins return heads.
Above 1,000 entrants the cap means fewer than 10% can receive prizes.

First receives a bonus of 5% of the entire pool. The remaining 95% is split equally among
**all winners, including first**; second and third have no extra bonus. With pool `P`:

```
bonus = floor(P / 20)
base = floor((P - bonus) / W)
first = base + (P - base × W)
others = base
```

Thus first gets 14.5% with 10 winners or 5.95% with 100; each other winner gets 9.5% or
0.95%, respectively. First absorbs all rounding dust. One eligible winner gets everything.

Each winner is paid in ETH or in half whale passes (2.25 ETH each), never both:

- First (the champion, moved to leaderboard position 0 at ranking) is the exception and
  takes both: half its amount, bonus included, in whole half passes rounded down, and the
  rest (including that half's leftover) in ETH.
- Once an equal share `base` also buys a half pass, the other places alternate in payout
  order: odd positions take ETH, even positions take whole half passes. Otherwise they all
  take ETH.
- Only the money that buys passes leaves the reservation, returned to the future prize pool
  (pending while frozen) in one move when the round is ranked. Every other pass winner's
  leftover below a half pass is split equally over the other ETH winners on top of their
  `base`; that split's indivisible dust follows the passes.
- Passes are claimed later through the existing `claimWhalePass` flow.
No entries returns the pool immediately; all tails releases the sealed reservation back to
the future pool, using the pending buffer if frozen. Zero-value pools distribute zero ETH.

Large stacks retain higher absolute peaks, but prize saturation and the final coin limit
returns from a dominant entry. ETH EV is field-dependent and is not strictly proportional
to chips. The accepted simulation showed moderately above-field stacks can have better
ETH per FLIP than average or very large stacks. That simulation drew every board at random;
chosen boards with their different boost terms are not yet covered by it. Wallet splitting
remains possible; wallet identity is not proof of a distinct human.

## Bounded settlement and accounting

Sealing is constant work. Rounds append to a FIFO, so a large field does not hold the
main RNG lock or stop later entry windows. Each run visits a min-heap of at most 100
eligible entries, with at most six heap moves. Total settlement work grows with entrants;
per-call work stays bounded. The entry count is a checked `uint64`, rather than a configured
population cap. No implementation can process literally infinite players in finite time.

The keeper leg uses at most 1,920 work units (4.7k gas each) minus prior box-scan work, the
same envelope as the box legs, and may finish one bounded item beyond it. Every piece of work
is charged after it runs, by its outcome and at its measured worst case: the call frame, a
tails coin, a heads run's fixed cost plus one unit per six rolls, a filling insert (fresh or
reused slots priced apart), each heap level, a root reject, each scanned leaf and each ETH
credit. `test/gas/DecimatorPricing.t.sol` pins every call, real dice on all board sizes and the
heaviest heap shapes alike, at or under 90% of its charge. Calls have an additional 256-run limit. Final ranking scans
the heap's leaves (at most 50 nodes) on a separate call, followed by bounded ETH-credit
batches. Budget and caller identity do not affect results. Sealed battles can progress during
RNG locks. Settlement stops at game over and the ending never waits for it: a round still
queued keeps its uncredited reservation in `claimablePool`, which the final sweep releases.

Advance moves the sealed pool from future prizes into `claimablePool` once. Winner credits
use that reservation without increasing `claimablePool`. An all-tails refund, and the pass
money moved at ranking, reduce `claimablePool` and increase future prizes by the same amount. No separate pending-pool
counter is stored. Run cursors, heap size and payout progress are saved once per batch.
No ETH is pushed to winners during settlement; the existing claim flow applies.

## Integration surface

- Player entry is `FLIP.decimatorBurn(address,uint256,uint32 chips)`; the vault's is
  `coinDecimatorBurn(uint256,uint32 chips)`.
- Internal Game record ABI is now `recordDecBurn(address,uint24,uint256,uint256,uint32) -> uint64`.
- `Game.settleDecimatorWinners(uint256) -> (workItems,unitsUsed,moved)` is the public,
  permissionless progress path. Direct calls earn no bounty; ordinary `mineFlip` uses the
  same worker and its existing work-priced bounty.
- `DecimatorBurn` now emits a `uint64 entryId` instead of a bucket.
- `DecBurnRecorded` reports event, entry, base amount (burn plus quest and boon bonuses),
  credited chips, cumulative stack and the board the burn set. Storage keeps one owner slot
  per entry id and one word per wallet packing id, board and stack; a retained node is two
  slots (the score's low word, then its high word above the entry id), and the tiebreak is
  recomputed from the id when two scores are equal. The FIFO settles one round at a time, so a
  single leaderboard is reused round after round: only the first round to reach a position
  pays for fresh slots, and a filling insert is charged by whether its slot was fresh.
- `DecimatorResolved` reports event, full word, pool and entrant count.
- `DecimatorRun` reports each heads run's normalized peak. Tails skip the engine and log
  nothing: the coin and the run both replay from the sealed word and entry id. A missing run
  event alone does not distinguish tails from an entry not yet processed; compare the id with
  the round's `cursor`.
- `DecimatorRanked` reports champion id and actual winner count.
- `DecimatorClaimed` reports each payout: the ETH credited and the half passes queued (one of the two is zero, except the champion's). `PlayerCredited` also fires for ETH.
- Lens: `decBurnOf` and `decEntryAt` (owner, stack and board), `decBattleRoundOf`,
  `decWinnerAt` (the exact high/low score words and the full ordering key; answers only while
  the round is at the head of the queue, since the next round reuses the slots; finished
  rounds are recorded by their `DecimatorRanked` and `DecimatorClaimed` events), `decSettleCursorOf`.
  Winner indices expose heap order, not display rank. Sort by the high/low/key tuple for a
  leaderboard; the round explicitly identifies first. Entry records remain readable across
  later windows. An event with no entrants is never written, so `phase == 0` alone does not
  mean a window is open; read `decWindow()` and the level.

The shared Game storage replaces only retired Decimator roots at slots 40–43 and 75;
the unused final slot 76 is removed.
Every unrelated slot retains its position and type. Modules use the same shared layout.

Tests are in `test/fuzz/DecimatorBattle.t.sol`, `test/gas/DecimatorBattleGas.t.sol`,
`test/gas/DecimatorPricing.t.sol`, the
Decimator cases in `LensParity.t.sol` and `ReviewFixes0924.t.sol`, and the migrated
`SdgnrsAutoDecimator.t.sol` / century-consolidation integration suites.

Validation uses the standard Foundry address fixture (`node scripts/lib/patchForFoundry.js`).
The focused suite command is:

```sh
forge test --match-contract 'DecimatorBattleTest|DecimatorBattleGasTest|DecimatorPricingTest|SdgnrsAutoDecimatorTest|LensParityTest|DecimatorLegEndingIdleTest|JackpotCommitmentFreezeTest|AdvanceCentury|ConsumerPointEquivalence' --fuzz-runs 256 -vv
```

On 29 September 2026, after the gas pass, every suite above passed with 256 runs per fuzz
test. The real-engine gas corpus settled three 1,001-entry fields in 37 batches (84 before the
pass); the largest batch used **6,915,709 gas**. A real `mineFlip` with a pending round settled
142 runs in **6,321,818 gas**. Across the pricing corpus no call exceeded 81% of its charge.
Sealing a synthetic `uint64.max` entrant count costs what a one-entry seal does. These are
measured cases, not a claim to have sampled every possible dice sequence.

Interface coverage, delegatecall alignment, storage-layout consistency, raw selectors,
RNG window/taint, pool accounting, storage ownership, unchecked arithmetic, bounded array
clears, advance-call classification and deterministic-drain source checks passed. All
affected production contracts fit the 24,576-byte runtime limit. No deployment was made.
