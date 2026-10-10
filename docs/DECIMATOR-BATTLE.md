# Decimator battle

Decimator burns build a virtual craps starting stack. Entries compete by peak bankroll;
that bankroll is a score, not a token balance players can withdraw. Ordinary x5 levels,
excluding x95, combine the original pool with generated entries funded by that level's
single jackpot day. x00 remains an original-only battle.

## Entry and automatic burn

Each manual burn, top-up and automatic entry requires at least **2,000 whole FLIP**.
FLIP has zero decimals. Each wallet has one original entry per round; top-ups add credited
chips and replace its chosen board. A legal board names at most seven chips, at most three
per leg, and cannot name both pass and don't-pass.

Credits include existing quest/boon additions, the Decimator activity multiplier and the
entry-day factor. The multiplier interpolates through 1x at score 0, 1.7049x at 235, 1.9x
at 500, and 2x at 30,000. Each burn locks its own timing and multiplier. The day factor is
0.9^d from the protocol-stamped opening day, using downward-rounded 18-decimal exponentiation.
A credit rounding to zero reverts. Protocol days reset at 22:57 UTC. Credited stacks are
whole FLIP, with no token multiplier.

The automatic sDGNRS burn spends the smaller of settled backing and
`floor(4 * previousCreditedStack / previousOriginalCount)`. Before a nonempty round has
sealed, the cap is 8,000 FLIP. A cap or available amount below 2,000 skips the burn.
The reference updates once on each successfully sealed nonempty original field, including
x00, zero-pot and zero-quota rounds. Empty rounds and rejected/repeated seals preserve
it. Generated entries never enter this reference. There is no fixed 500,000 cap.

The aggregate tracks actual credited additions to original stacks and is checked
against uint64; original count is checked against uint40. These are storage packing bounds,
not an 8,000-player admission limit.

## Jackpot-generated entries

Ordinary x5 keeps its ticket legs and solo/golden-ticket delivery. Let E be the day's
priced ETH leg, Q its normal solo share (about 60%), A the total of active non-solo shares,
N the original count, C its total credited stack and P the reserved Decimator pool.
For positive N and P:

```
available           = A + max(0, Q - floor(35*E/100))
generated entries M = min(N, floor(available*N/P))
funding F           = ceil(M*P/N)
soloAmount U        = min(A + Q - F, Q)
Decimator pool      = P + F
```

There is no separate generated-entry cap. A full match adds N slots and P of funding;
with all cohorts active this is possible whenever P<=65% of E. Empty non-solo cohorts
contribute neither budget nor weight; if all are empty M=0. Matching can draw on solo's
share above 35% of E. Solo keeps between that floor and its normal share, up to wei rounding,
and never receives surplus above its normal share. Each generated slot can win one place.

Solo receives its normal cash/pass split on U: with H=2.25 ETH, pass cost is
`floor(U/(8*H))*(2*H)` when U>=8*H, otherwise zero. Cash is U minus that cost. No non-solo
cash dust is added. An empty solo is unpaid. All unused money, including inactive shares
and surplus when the full match is cheap, follows the existing final-day sweep to future prizes.

For a **1,000 ETH leg** with all cohorts active, A=400, Q=600 and available=650 ETH.
At N=2,000 and P=140 ETH, M=2,000 and F=140 ETH. Solo gets **451.5 ETH cash plus
148.5 ETH in whale passes** (66 half-passes), and 260 ETH is swept. The accounting is
140+451.5+148.5+260=1,000 ETH. At P=650 ETH the full match leaves solo 350 ETH:
264.5 ETH cash and 85.5 ETH in passes. At P=1,000 ETH, M=1,300 and F remains 650 ETH.

Only active non-solo cohorts have weights, equal to their existing ETH winner targets.
Solo weight is zero and it receives no generated entries. A sampled generated ordinal j
belongs to the first quadrant whose `floor(M*cumulativeWeight/totalWeight)` reaches j.
It draws from real tickets plus the existing deity weight, then reads that recipient's
saved board. The daily RNG lock freezes cohorts and preferences until this work finishes.
Repeated recipients retain distinct entry IDs. With no originals or zero P, normal
cash/pass awards apply; the one-day schedule and ticket legs remain.

## Runs and eligibility

All runs share the event dice seed. The engine starts at 3,000 × 10^18 simulation units with
ten 60-FLIP chips: chosen chips plus random scattering, using the normal battle boost row
for the named-chip count. It stops at bust, 48 shooters or exactly 511 rolls. The highest
bankroll at completed shooter boundaries determines the score; a mid-hand roll cutoff also
counts remaining wagers at face value. A later bust does not erase an earlier peak.

An original score is its credited stack times normalized peak. A generated score is
`floor(C * normalizedPeak / N)`. The bounded engine keeps scores within 192 bits. Equal scores use an independent
tagged random key, then entry ID. The same tie domain applies to both entry types. Generated survival keys use synthetic player
identities, so another award to the same wallet does not reuse its original run.

Let T=N+M. **Exactly S=min(1000,ceil(T/2)) slots survive**: half rounded up through
2,000 slots, exactly 1,000 above that. Partition [0,T) into S floor-rounded strata,
pick one position per stratum, and rotate all selected positions by one common random offset:

```
r = H(SAMPLE_TAG,word,lvl) % T
lo = i*T/S; hi = (i+1)*T/S
pos = lo + H(SAMPLE_TAG,word,lvl,i) % (hi-lo)
id = (pos+r)%T + 1
```

Strata give distinct survivors. Over all rotations every slot appears equally often,
so inclusion probability is S/T under uniform hash draws, independent of ID. The usual
negligible modulo bias of 256-bit hashes remains. Unselected IDs are never visited.
The complete survivor set replays from (word,lvl,T); plan terms bind before any run.

Hash inputs use full ABI words. Sampling's domain is `decimator.battle.sample.v1`;
original and generated runs share `decimator.battle.dice.v1`, `.board.v1` and `.tie.v1`.
Generated entries additionally use `.generated.player.v1` and `.generated.recipient.v1`.
IDs never overlap; shared dice omits identity. There is no per-entry eligibility coin.

## Prize places and payments

```
K = min(200, floor(fieldEntries / 2), max(20, ceil(fieldEntries / 10)))
W = K                         // S >= K at every field size
```

The 20-place target is always subject to the **50% entrant cap, rounded down**, even when
more entries survive. x00 and original-only fallbacks use the same rule. One entry means
zero prize places even if it is eligible. Entries count, not distinct wallets.

| Field entries | Maximum prize places |
|---:|---:|
| 1 / 2 | 0 / 1 |
| 19 / 20 | 9 / 10 |
| 39 / 40 / 41 | 19 / 20 / 20 |
| 199 / 200 / 201 | 20 / 20 / 21 |
| 1,990 / 1,991 / 2,000 | 199 / 200 / 200 |

The best K survivors are paid. Every retained node is one
entry and one prize place. The best retained run receives the champion bonus **once**. With a positive winner count:

```
bonus = floor(pool / 20)
base  = floor((pool - bonus) / W)
first = pool - base * (W - 1)
```

The champion gets half its award in whole half whale passes, rounded down at 2.25 ETH each,
and the rest in ETH. If `base` buys a half pass, other logical payout positions alternate:
odd positions take ETH, even positions take whole half passes. Otherwise all take ETH.
Pass-position leftovers top up other ETH positions; final division dust follows pass
funding to future prizes. The champion receives 9.75% at 20 places and 5.475% at 200 before
pass conversions and integer rounding.

Payout order puts the champion first, followed by heap positions, not sorted merit rank.
Every retained entry receives its own ETH/pass credit and claim receipt.
Passes use the existing claim flow; no ETH is pushed during settlement. Empty fields return
their pool. Zero winners, including a one-entry field, release the whole reservation to
future prizes, using the pending buffer while frozen.

## Settlement, accounting and replay

Generated work completes under the RNG lock; originals run at consumer stage 5 after
unlock. Both cursors count strata, at most 1,000 each. The locked worker skips natural IDs;
the unlocked worker skips generated IDs. With M=0 the locked loop is skipped entirely.
Only the sampled survivors call the engine: at most 1,000 runs in total, independent of N.
Gas and miner identity affect checkpoint sizes, never outcomes. Admission uses a measured
small bound for opposite-type strata and the existing full bound for an engine run.

One min-heap retains at most 200 eligible entries. Every node stores a 192-bit score and
64-bit ID. Original IDs are `1..N`; generated IDs are `N+1..N+M`. Generated owners are keyed
by ordinal `id-N` (1–N), reused across rounds; only candidates admitted to the heap write
an owner. Evictions need no cleanup. Original owners come from their entry records. Ranking
scans at most 100 leaves, moves the champion first and releases pass funding once.

Advance reserves `P` once. Initialization transfers `F` from current to claimable once,
recording it in JackpotWork.paid. Jackpot debits subsequent solo cash and pass cost; only
cash increases claimable liability, and pass cost funds futurePrizePool. Winner
ETH consumes the reservation without increasing aggregate claimable funds. One plan word
stores uint128 `soloAmount`, four uint16 weights, uint40 generated count, uint16 stratum
cursor and uint8 mode. Cumulative allocation ends are calculated for sampled entries. Pricing
inputs appear in the plan event; field count derives from original plus generated counts,
and traits stay in the live JackpotWork while generated entries run. x00 and zero-pot seals
write no plan. Game-over behavior is unchanged: the existing ending and final sweep handle
remaining funds. There is no Decimator-specific retirement or uncredited-fund counter.

Lens exposes `decBurnReferenceOf` (stack, count, next automatic cap), `decBattleRoundOf`,
`decJackpotPlanOf` and `decWinnerAt` (score, ordering key and owner for either entry type),
and `decSurvivorAt(word,lvl,T,stratum)`, alongside original entry and cursor views. Field size,
survival odds and whether the floor raised capacity are derived by the client. The
shared heap is readable only for its active round; finished results use receipts.

`DecimatorReferenceUpdated` includes the reference level, without storing a duplicate level.
`DecimatorResolved` records the original seal. `DecimatorFieldBound` reports original-only
capacity; `DecimatorJackpotPlan` carries jackpot pricing, traits and allocation instead.
`DecimatorGenerated` records sampled generated entries with ID, recipient, quadrant, board,
peak and score. Skipped IDs replay from the sealed word and final field size. Sampled
originals emit `DecimatorRun`. `DecimatorRanked` identifies the champion; each
`DecimatorClaimed` reports one entry's ETH and passes. There are no bucket-budget, separate
funding, pack or group-payment events.

This revision requires a fresh deployment: round packing changes to uint96 pool, uint40
original count and uint64 credited aggregate; reference and generated-plan storage is
appended. Every delegate module shares the layout. This is not an in-place migration.
Earlier economic simulations and gas measurements do not validate this revised quota or
saved-board generated field.
