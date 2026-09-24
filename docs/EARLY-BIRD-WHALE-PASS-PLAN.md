# Early-bird jackpot whale-pass conversion

September 24, 2026. Implemented in the working tree from base `3a9bbe9c`.
Implementation and verification results are recorded below.

## Agreed direction

The user selected **45 tickets per winning slot**, explicitly allowing a wallet
with multiple winning slots to collect that amount for each win. Calculate the
ordinary early-bird ticket payout first. If it would exceed 45 tickets per slot,
and the total budget left after funding 45 tickets for every slot covers at least
one full whale pass, pay 45 tickets per slot and convert that pooled surplus into
as many whole prize passes as it covers. **Award all those passes to one player
from a fresh draw using the early-bird bonus-trait board, preferring an eligible
gold trait when one exists.** The winner need not have won an immediate ticket
prize in this draw.

If the surplus cannot cover a full pass, retain the ordinary all-ticket payout,
even if that is more than 45 tickets per slot. This is a conditional cap. After
conversion, any remainder smaller than a full pass stays in nextPrizePool and
does not buy extra tickets above the cap.

**All early-bird ETH continues going to nextPrizePool.** Conversion changes the
prize mix only. Full prize passes use pairs of existing half-pass claim units.
This rule supersedes the earlier proposed 25% allocation, fixed 54 ETH activation
and three-pass minimum; no percentage ceiling or three-pass gate remains.

The tradeoff is a bounded immediate ticket prize plus a growing long-term pass
lottery, while nextPool still receives the entire original ETH amount. The main
implementation risks are incorrect surplus arithmetic, inadvertently rerouting
ETH, excess settlement gas, and accidentally changing the existing draw.

## Existing mechanism

- `_priceEarlyBirdTickets` in `DegenerusGameJackpotModule.sol` snapshots 3% of the
  future pool on jackpot day one, after any golden-ticket resolution. It moves
  the entire amount from future to next and latches the ticket entries.
- `payEarlyBirdTickets` consumes the latch in its own advance stage. It selects
  from the next level's bonus-trait buckets, including existing deity weights,
  and awards equal whole-ticket prizes to at most 128 winning slots. Slots can
  belong to the same wallet. Empty buckets redistribute slots.
- Gold is color tier 7, detected by `((trait >> 3) & 7) == 7`.
  `_pickSoloQuadrant` already prefers gold for the solo ETH prize, but does not
  filter out empty buckets. The proposed pass draw needs an eligible-bucket
  filter before choosing its gold or fallback trait.
- `HALF_WHALE_PASS_PRICE` in `DegenerusGameStorage.sol` is 2.25 ETH. Two units
  represent a full pass's regular ticket entitlement, so this plan uses 4.5 ETH
  per full prize pass. That is the jackpot accounting rate, not the retail
  purchase price or a promise of realizable ETH value.
- `claimWhalePass` in `DegenerusGameWhaleModule.sol` applies the usual pass stats
  and queues the entitlement over 100 levels beginning at current level + 1
  when claimed. One full pass supplies 200 entries in whole-ticket strides.
  It does not deliver the retail purchase's lootbox, affiliate commission,
  five-for-six bonus, early purchase ticket boost, or free AFKing seat.

## Budget rule

All arithmetic below is integer wei arithmetic. Let `F` be the existing future
pool snapshot, `B` the early-bird budget, and `p` the level + 1 whole-ticket price.
Derive the winner-slot count from the full original budget, before conversion:

```text
B = floor(F * 300 / 10_000)
T = floor(B / p)
N = min(T, 128)
if N >= 8: N = floor(N / 8) * 8
if N == 0: no awards; all B still credits nextPool

ordinaryTicketsEach = floor(T / N)
P = 2 * HALF_WHALE_PASS_PRICE         // 4.5 ETH per full prize pass
surplus = ordinaryTicketsEach > 45 ? B - 45 * N * p : 0
fullPasses = floor(surplus / P)
ticketsEach = fullPasses > 0 ? 45 : ordinaryTicketsEach
halfPasses = 2 * fullPasses           // existing claim ledger denomination
ticketAwardValue = N * ticketsEach * p
passAwardValue = fullPasses * P       // entitlement sizing, not a pool transfer
dust = B - ticketAwardValue - passAwardValue
nextPoolCredit = B                   // user requirement: all ETH still goes here
```

The surplus is the **entire original budget remaining after reserving the capped
ticket awards**, including original equal-share or sub-ticket rounding dust.
Compute it from exact `B`, not by reconstructing ETH from the rounded entry latch.
The explicit `ordinaryTicketsEach > 45` condition prevents converting mere
rounding dust when the original payout is already 45 or fewer tickets.

For a populated draw, `ticketAwardValue + passAwardValue + dust = B`. When passes
are awarded, `0 <= dust < P`. Without conversion, the existing whole-ticket and
equal-share rounding applies. No part of `passAwardValue` is reserved in or
returned to futurePrizePool. If no bucket is eligible, award nothing; the entire
`B` still remains in next.

Example at a 0.04 ETH ticket price and 128 winning slots:

| Early-bird budget | Ordinary tickets/slot | New tickets/slot | Full passes total | Unallocated award value | ETH to nextPool |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 230.40 ETH | 45 | 45 | 0 | 0 | 230.40 ETH |
| 234.90 ETH | 45 | 45 | 0 | 4.50 ETH | 234.90 ETH |
| 235.52 ETH | 46 | 45 | 1 | 0.62 ETH | 235.52 ETH |
| 256 ETH | 50 | 45 | 5 | 3.10 ETH | 256 ETH |
| 512 ETH | 100 | 45 | 62 | 2.60 ETH | 512 ETH |

Conversion implies `N = 128`: when the original draw has fewer slots, its ordinary
whole-ticket award cannot exceed 45 per slot. The first eligible budget at each
current price tier is therefore `max(46 * 128 * p, 45 * 128 * p + P)`:

| Next-level ticket price | First early-bird budget eligible for conversion | Full passes at activation |
| ---: | ---: | ---: |
| 0.01 ETH | 62.10 ETH | 1 |
| 0.02 ETH | 119.70 ETH | 1 |
| 0.04 ETH | 235.52 ETH | 1 |
| 0.08 ETH | 471.04 ETH | 2 |
| 0.12 ETH | 706.56 ETH | 3 |
| 0.16 ETH | 942.08 ETH | 4 |
| 0.24 ETH | 1,413.12 ETH | 6 |

Check both conditions afresh for every draw. There is no permanent activation
switch. At 0.04 ETH per ticket, activation corresponds to approximately 7,850.67
ETH in the future pool at the existing 3% snapshot.

## Winner allocation

1. Preserve the original budget's slot count, grouping in eights, bonus traits,
   bucket redistribution and source-ticket sampler. Conversion changes the
   immediate prize quantities, not the original ticket recipients or source
   indices. A capped prize is **45 whole tickets = 180 entries**.
2. For the pass prize, use the same day's official, hero-adjusted bonus traits
   and the same level + 1 source inventory. This is a fresh recipient draw from
   that board, rather than a new trait-board roll or a selection from the
   immediate ticket-winner list. The new winner can also be a ticket winner,
   but winning tickets is not a prerequisite.
3. Scan the four winning trait buckets. A bucket is eligible when its real
   entry count plus `_deityVirtualCount(trait, len, deity)` is nonzero. Among
   those eligible buckets, build the subset with gold color tier 7. A gold
   bucket with no real entries but a deity is eligible: existing gold rules
   give that deity one virtual entry.
4. If eligible gold buckets exist, pick uniformly among them using the game's
   existing hash/range convention. Otherwise pick uniformly among all eligible
   winning buckets. Ignore empty gold buckets; they must not strand the prize
   or prevent fallback to an eligible non-gold bucket. Selection is equal per
   eligible bucket, then weighted by entries within the chosen bucket.
5. Draw one fresh entry uniformly from the chosen trait's real plus virtual
   inventory, using the shared `_deityVirtualCount` and `_bucketOwnerAt` helpers.
   A single recipient needs no packed-word group or sampling cursor. Give the
   resulting player **all `W` full passes** with one
   `whalePassClaims[player] += 2 * W` update and one pass-win event. Do not loop
   once per pass or split the allocation among players.
6. Derive separate tagged entropy for bucket choice and entry selection from
   the already committed day's word, day and source level. Keep the pass count
   and budget out of both seeds. Preserve the original ticket-draw seeds and
   salt domain; do not reuse a prior winning index.
   A fresh draw needs no additional VRF request or advance stage.
7. The 45-ticket rule remains per winning slot: two capped ticket wins pay a
   wallet 90 tickets. Those wins do not add pass-draw chances. Pass odds come
   directly from the chosen trait's eligible entry inventory and deity rules.
   Do not deduplicate wallets or exclude prior ticket winners.
8. If `W == 0` or no winning bucket is eligible, skip the pass draw before any
   range reduction and clear its pending state. All ETH stays in next whether
   an eligible recipient exists or not.

Pass selection scans four buckets, samples one source entry and credits one
aggregate claim. The immediate ticket draw remains bounded by 128 slots,
regardless of jackpot size. Converted-path gas measurements are recorded below.

Use a small eligibility-aware picker for this path. Reusing the existing solo
picker without adding an active mask can select an empty gold bucket; changing
the solo picker's established semantics would affect unrelated ETH jackpots.

## Accounting and implementation sequence

1. In `_priceEarlyBirdTickets`, snapshot exact `B`, calculate the ordinary slot
   count and ticket prize, then apply the conditional cap and pooled surplus
   calculation. Move the full `B` from future to next as today.
2. When conversion applies, latch `N * 45 * 4` ticket entries and
   `U = 2 * fullPasses`; otherwise retain the existing entry calculation and
   latch zero pass units. The capped entries still fund the original 128-slot
   draw. The exact budget is available here, so no later reconstruction or
   rereading of a changed future pool is needed.
3. Store pending `U` in safely appended shared storage unless a layout review
   establishes a safe existing location. Do not silently repurpose packed
   fields or shift existing delegatecall storage offsets.
4. Run the original ticket distribution, then the independent gold-preferred
   pass draw from the same frozen bonus-trait inventory. The jackpot module
   delegates recipient selection, claim credit and the award event to the whale
   module, keeping both runtimes within the deployment size limit. The shared
   helper moves no pools in early-bird mode. Share deity weighting and packed
   owner lookup; use a direct single-entry draw and separate entropy domains.
   There is no need to retain the ticket-winner list.
5. Increment `whalePassClaims` directly by even units and consume both early-bird
   latches atomically, preserving the other pending daily fields. Make no
   prize-pool or claimable-pool writes in this award stage. Relative to the
   early-bird snapshot alone, the final changes must remain:

   ```text
   nextPrizePool change   = +B
   futurePrizePool change = -B
   claimablePool change   = 0
   ```

6. Emit the existing `JackpotTicketWin` for immediate tickets and
   `JackpotWhalePassWin` with source 4 for early-bird pass credits.
   Event counts remain half-passes. Explain both prize components in the UI,
   including that pass claims are deferred, the 45-ticket cap is per slot, and
   the pass winner is drawn separately with preference for eligible gold traits.
7. Use `claimWhalePass` for delivery, including its existing claim-time level
   targeting, permissionless settlement to the named player, RNG restrictions
   and liveness/game-over rules. Do not expand 100-level ranges during the
   locked jackpot stage or route these awards through a retail purchase.
8. Update architecture, economic disclosures, storage-layout goldens, RNG and
   pool-write manifests as applicable. Check module runtime size and alignment
   under production and fixture pins.

Pass awards are future participation rights, not ETH withdrawal claims. Their
accounting value must not be credited to another reserve or claimablePool. The
existing `_queueWhalePassClaimCore` would credit a fractional remainder as
claimable ETH; do not pass the raw surplus to that helper. The remainder stays
in next with no additional ticket or cash award.

## Validation required before implementation is complete

- At every price tier, test 45/46 ordinary tickets and one-pass surplus
  boundaries minus/at/plus one wei. Cover more than 45 tickets with insufficient
  surplus (retain the normal payout), and sufficient rounding surplus with
  only 45 ordinary tickets (no conversion). Test falling below either gate.
- Check populated-draw award-value conservation including dust; after conversion
  dust is below one full pass, every slot receives 180 entries, and each pass
  award increments the claim ledger by an even amount.
- Exercise one pass, many passes, very large allocations, duplicate wallets, every
  active-bucket mask, deity-only buckets, hero-adjusted traits and an empty draw.
  Confirm the original ticket slot count, recipients and source indices remain
  unchanged. A separate pass winner may have no immediate ticket wins.
- Cover zero, one, two, three and four gold traits, all eligible-gold masks,
  empty gold buckets, gold with only a deity, non-gold fallback and no eligible
  bucket. Assert the chosen bucket is eligible and gold whenever eligible gold
  exists; multi-gold and fallback choice use equal bucket probabilities.
- Check entry selection against the source inventory and existing deity weights.
  Verify one recipient receives the entire `2 * W` credit and one pass-win
  event. Ticket-win multiplicity is not a pass-selection input. Changing only
  pass quantity, while conversion remains enabled, must preserve the chosen
  pass trait and recipient; the fresh draw must not copy ticket-draw entropy.
- Cover ordinary and turbo day one, late advancement, retries, terminal cleanup,
  preservation of unrelated pending fields, full `B` credited to next, and no
  pool movement or duplicate awards from settlement or replay.
- Exercise claims aggregated with other pass sources, one-time consumption,
  correct 100-level coverage, RNG/liveness restrictions and absence of retail
  side rewards.
- Extend `DailyJackpotDayShapes.t.sol`, `JackpotEightWinnerGroups.t.sol`, and
  relevant event/solvency tests. Preserve the assertion that the early-bird
  distribution stage never moves pools, including when it awards passes.
- Extend `EarlyBird128Stress.t.sol` and `JackpotDayOneWorstCase.t.sol` with
  `B >= max(46 * 128 * p, 45 * 128 * p + P)` for 128 ticket winners plus
  one fresh trait sample and pass-credit write, with a pass recipient absent
  from the ticket-winner list. Also test a much larger pass quantity to confirm
  it adds no per-pass work. Include cold state, hero scans, partial source words,
  gold/deity/fallback cases and late calls. Require existing stage gas and
  transaction limits.
  An all-ticket fixture does not establish the gas cost of the converted path.

## Incentives, scenarios and risks

| Actor | Expected effect and response |
| --- | --- |
| Variance-seeking player | Large draws add a pass lottery while keeping 45 immediate tickets per winning slot. Display both components. |
| EV maximizer | Compares long-term participation and pass stats with immediate entries. The accounting rate does not establish equal expected returns. |
| Whale/coordinated holders | Repeated ticket wins retain repeated ticket awards; the independent pass draw depends on eligible trait entries, not earlier wins. No wallet-level deduplication is introduced. |
| Affiliate | No retail purchase occurs and no new referral payout is generated. |
| Griefer/competitor | May push a known pool threshold, but receives no new post-word recipient or randomness input. |
| Late entrant | Uses the same eligible early-bird board and can win the pass prize without winning immediate tickets. Passes grant no retroactive entry into this draw. |

Gold preference gives eligible gold buckets the entire pass opportunity whenever
at least one exists. This intentionally favors those traits over non-gold traits
for the headline pass prize. A deity-only eligible gold bucket wins certainly
when it is the only eligible gold bucket; retain and disclose the existing
virtual-entry rule rather than silently excluding the deity. Multiple eligible
gold buckets share the bucket selection equally, regardless of their sizes.

As the pool grows, immediate awards stop growing beyond 45 per slot once
conversion activates. Subsequent surplus grows the one winner's full-pass prize,
with less than 4.5 ETH of residual award value per populated converted draw.
There is no 25% ceiling: the pass share can approach the entire award budget at
very large sizes while the 45-ticket base persists. A smaller pool or a higher
next-level ticket price can switch conversion off again.

The first conversion can reduce the ordinary ticket prize abruptly to 45. At
low ticket prices it may have grown above 46 while waiting for enough pooled
surplus to cover a pass. At higher prices, removing one ticket from every slot
can already buy several passes. Total accounting value including dust is
conserved; immediate ticket supply is not monotonic at activation.

All ETH still supports the next pool. Converted entries compete in later draws
without a dedicated future-pool credit, shifting participation and competition
for prizes over time. Passes can generate later early-bird eligibility and
reinforce long-term holders' participation. This creates no new capital and is
not proof of a stable economic equilibrium. Declining play or game termination
can substantially reduce the realized value of the longer-horizon entitlement;
existing game-over rules can also prevent claiming it.

| Risk | Likelihood without safeguards | Impact | Mitigation/monitoring |
| --- | --- | --- | --- |
| Ticket count confused with quarter-ticket entries | Material implementation risk | High | Explicit 45 tickets = 180 entries; boundary tests |
| Reused payout helper reroutes ETH or pays cash dust | Material implementation risk | High | Direct even-unit claims; assert full next credit and no award-stage pool writes |
| Conversion changes winner count or RNG inputs | Material refactor risk | High | Derive original cap first; recipient/index parity tests; separate pass entropy |
| Settlement cost grows with pass quantity | Material with per-pass delivery | High | One aggregate deferred credit; cold gas stress at small and large quantities |
| Pass prize concentrates in one wallet | Certain per converted draw | Intended variance | One fresh trait draw receives the entire prize; apply the stated gold and entry weights |
| Empty gold bucket strands the prize | Material with unfiltered solo-picker reuse | High | Filter eligible buckets first; fallback when no eligible gold exists |
| Gold/deity concentration exceeds player expectations | Depends on eligible board | Economic tradeoff | Disclose gold preference and virtual entries; monitor chosen traits and recipients |
| Pass share dominates at scale | Expected by this cap rule | Economic tradeoff | Display and monitor pass share, immediate tickets and outstanding claims |
| Long-term entitlement disappoints during decline | Depends on continuation | Moderate/high | Explain deferred claims and continuation dependence |

Prioritize exact arithmetic and unchanged ETH routing, then bounded gas and
winner parity. Monitor ordinary versus capped tickets per slot, pass quantities
and recipients, chosen pass trait and gold/fallback route, residual award value,
full next-pool credit, claim latency and stage gas.

## Implementation verification — September 24, 2026

These measurements precede the shared whale-award helper introduced for
[quadrant ETH conversion](JACKPOT-QUADRANT-WHALE-PASSES.md). That document records
the latest joint verification; the early-bird payout rules and entropy are unchanged.

The focused Foundry run passed **61 tests, zero failures and zero skips**, across
six selected sources and their imported suites. Fuzz tests retained 1,000 runs.
Sources: `EarlyBirdWhalePass`, `DailyJackpotDayShapes`, `JackpotEightWinnerGroups`,
`EarlyBird128Stress`, `JackpotDayOneWorstCase` and `DeadVrfEnding`.

Coverage includes every ticket-price activation boundary, exact-wei surplus and
pool conservation, unchanged ticket recipients and source indices, repeated
wallet wins, eligible gold and empty-bucket fallback, deity-only gold, amount
independence, claim aggregation and restrictions, replay and terminal cleanup.
The cold production advance fixture includes a pass recipient outside all 128
ticket recipients, hero processing and partial source words.

| Converted early-bird fixture | Full passes | Measured advance call gas |
| --- | ---: | ---: |
| 300 ETH budget, cold empty queue | 15 | 7,954,662 |
| Same budget, partial queue and late call | 15 | 7,944,704 |
| 30,000 ETH budget, cold empty queue | 6,615 | 7,954,662 |

These measurements exclude transaction intrinsic gas and test assertion costs.
They pass the fixture's 10M target and capped transaction call. The identical
small/large award cost confirms that crediting more passes adds no per-pass work
in this fixture; it is not a proof of a global gas maximum.

All eleven source/interface gates pass. The storage oracle passes all 27 goldens
and shared-slot alignment. Comparison with the base confirms that every existing
field is unchanged: only `earlyBirdWhalePasses` is appended at slot 74 in the Game
and its twelve modules.

All 33 deployment entries fit EIP-170 under production and Foundry fixture pins.
The jackpot module is 24,528 runtime bytes (48 spare); the whale module is 23,947
bytes (629 spare) under both pin sets. Production sizes were checked against a
forced fresh build, including metadata/source hashes. The tight jackpot size
budget is why recipient selection lives in the whale module.

Reproduce the affected run:

```sh
python3 scripts/test-foundry-groups.py \
  --file test/fuzz/EarlyBirdWhalePass.t.sol \
  --file test/fuzz/DailyJackpotDayShapes.t.sol \
  --file test/fuzz/JackpotEightWinnerGroups.t.sol \
  --file test/gas/EarlyBird128Stress.t.sol \
  --file test/gas/JackpotDayOneWorstCase.t.sol \
  --file test/fuzz/DeadVrfEnding.t.sol \
  --log-dir .audit-test-logs/early-bird-final
```

Logs and the test summary are in that ignored local evidence directory. This was
an affected-suite verification; the full repository suites were not rerun.
