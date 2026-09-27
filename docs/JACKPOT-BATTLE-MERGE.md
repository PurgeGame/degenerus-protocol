# Paid and awarded jackpot battle entries

> **Current implementation:** the working tree applies an 8,000 jackpot fee, Added = max(floor, 0.5% of last pool) with a 150,000-FLIP floor while the game level is 0 or 1 and 50,000 after, and one award per 10,000 of Added, capped at 500. Retuned component rolls support **25,000 / 500,000** retail at a 0.705% normal premium / 4.091% high discount versus expected entry cost. Reward values are **24,800 / 520,800**, conversion **21:1**. See [the current pricing configuration and verification](JACKPOT-FIXED-8K-PROPOSAL.md). The earlier pricing and schedule calculations below are retained as historical design context and are superseded by that document. The settlement and read/replay sections reflect the current implementation. Shared dice are now enforced for paid and awarded entries; awarded scatter and other entry-specific draws do not rehash the battle dice.

Implementation and verification notes. The approved battle behavior is paid entries followed by the drawn entries; both feed one scoreboard and final pot. A wallet in both groups receives two separately scored runs on the same battle dice, with separately derived board scatter for its award. Normal battle play, run limits, bust handling, merit ranking and random tie-breaking apply to both groups. The earlier fixed **10,000-FLIP jackpot entry** proposal is under review. Matching ordinary battles remain approximately 20 minutes before and after day swap, with **three** other ordinary battles spaced roughly six hours apart. The five ordinary battles retain day-opening-RNG pricing. The ordinary presets below describe the earlier fixed-fee proposal, before variable-fee compensation.

## Funding and UI

- The protocol allocation is **0.5% of the previous recorded prize pool**, converted to FLIP at the game's level price. Level-one's separate trait draw remains at 0.25%.
- The UI calls the whole protocol allocation **Added**. This includes bankrolls for awarded entries; it is not synonymous with the winner's pot.
- Fixed jackpot buy-in: **10,000 FLIP**, selected by the user. Its payout/multiplier draw happens after entry locks; its entry price is never derived from that settling word. This supersedes all earlier pool-linked pricing and intermediate fixed-price candidates.
- After locking, let `F = paidUnits * 10,000 FLIP`, `A = Added`, and `N = paidUnits + awardedUnits`. High seats count as their day's H copies; duplicate awards count as their awarded units. Every run uses the same unit bankroll so copies do not improve its merit rank.
- First roll the funded pool: `P = (F + A) * multiplier`. The retained lottery is 90% at 0.5×, 9% at 3×, 0.9% at 20× and 0.1% at 100×, with mean 1×. **This is applied once, before play; payouts are not multiplied again.**
- Unit bankroll is `floor(P / N / 2 / 300 FLIP) * 300 FLIP`. Around half goes to gameplay; the remaining funded value goes to the battle pots. Unit bounty is stored in 100-FLIP granules. Division/rounding dust remains in the main pot. The normal high lane receives high copies' extra bounties, as with ordinary battles.
- Example without a pool multiplier: 500,000 FLIP of fees plus 500,000 Added, across 100 units, gives 10,000 per unit. Each gets a 4,800-FLIP bankroll; 520,000 FLIP remains for battle pots. At 0.5× those figures become a 2,400 bankroll and 260,000 in pots.
- Engine chip widths cap an extreme unit bankroll at 83,886,000 FLIP; the 18-bit stored bounty is capped too. Anything above either bound stays in the main pot. The field admits at most 500 awarded units, drawn up to 150 per call, and respects the 300-FLIP minimum bankroll (including a roughly equal pot share). Empty awarded fields still resolve all paid seats.
- Ordinary windows freeze their terms when the day opens. The opener and closer share terms but settle from independent slot-keyed dice. Their five windows divide the existing ladder allocation; the jackpot's Added is separate and is not funded a second time from that ladder.
- RIU uses the agreed routine shares, 5% / 10%; Biggest Dice Run uses its existing 100× peak threshold. Prior ordinary wins do not double the jackpot's RIU share.

## Settlement

The initial standalone paid-entry-book proposal is superseded by the daily-pass integration discussion. Scheduled period 5 supplies its direct-entry/day-ticket field. CrapsBattle owns the persistent scoreboard and cursor; JackpotBattle is its cold delegate module, sharing an append-only storage base. **The jackpot battle happens at daily jackpot time.** Its paid entry closes atomically with the daily RNG request that locks its field, at or after the 22:57 UTC boundary. It has no earlier afternoon close, separate midday RNG request, or afternoon paid settlement. After the daily word arrives, jackpot processing resolves the paid field in budgeted transactions, then the awarded field, then finalizes once. Both fields use one shared battle dice seed from that committed daily word. Awarded board scatter is derived separately by entry ID without changing the dice seed or the field's rotation seed. A VRF delay does not reopen entry. The Game retains its existing daily lock and pending-battle stage across required calls. Skipped days and stalled VRF must preserve the existing lapse/refund behavior without attaching a drawn field to the wrong day. Entry routing must follow the active round until its request closes it, rather than rolling to a new round just because wall-clock midnight/turnover passed.

The daily request freezes paid entries and locks awarded-entry eligibility and preferred boards before its settling randomness exists. The Game selects and snapshots the awarded field from those frozen inputs once the daily word is available. Both settlement stages use the normal table's work-unit meter and maximum allocation bound. Settlement begins only once the awarded field is sealed, so a paid field can never finalize early. One walk may then cross from paid into awarded seats, and the call that seals the field settles on whatever of its 1,500 units its own draw left (the draw is charged 110 units plus 10 per entry). The last drawn batch finalizes the pot, RIU and record eligibility exactly once. Empty drawn fields still close a paid battle.

Every craps run uses the same bounds: a 1,000-roll budget checked between shooters, a 1,511-roll absolute ceiling, and a 512-shooter cap. This includes ordinary, custom, paid, high, comp, day-pass and awarded runs; the engine has no jackpot-specific budget branch. A run that reaches the budget stops like any hard bound: a bust before its goal, a Goal after it. Goals rank by peak, then ending bankroll; busts rank by the normal survival/remainder composite. Standing and the round's random entry-id tie-break complete the comparison. All-bust fields still have a pot winner, with no individual bust payment or qualifying RIU/record peak.

The UI needs a current quote, full added allocation, actual pot, shared multiplier, separate paid/drawn entries and counts, progress cursors and final winner. Paid boards are ticket-local and preserve the existing preference-update behavior; awarded entries snapshot the existing preferred board.

## Verification

Check normal-engine parity, all-bust fields, tie-order independence, identical results under different chunking, paid-plus-awarded wallets, shared dice at every shooter/roll coordinate, entry-specific awarded scatter derivation, price rounding and freeze, pool accounting, empty fields, replay/retry and midnight/stall behavior. Re-measure bounded transactions against the 10.5M target, including correlated shared-dice hot runs, one full-run budget overshoot and final awards; the old shortened-run gas allowance does not apply.

## Schedule and daily-pass integration

Use **six windows: five ordinary battles followed by the daily jackpot battle**. The user's timing requirement is one ordinary battle approximately 20 minutes before the day swap, the jackpot battle at the swap, and one ordinary battle approximately 20 minutes after. Anchor the ordinary closes exactly 20 minutes either side: **22:37 → 22:57 jackpot → 23:17**, UTC. These are scheduled closes/triggers, not guaranteed settlement times. A day opens after its required daily processing, its first ordinary deadline is 23:17 that evening, and its remaining deadlines fall the following calendar day. The 22:37 closer belongs to the closing day; the 23:17 opener belongs to the new day. Windows accept entries once that protocol day has opened, until their respective close. The jackpot close is the actual daily request/lock, not a separate earlier wall-clock deadline. The other three ordinary battles close at **05:00, 11:00 and 17:00**, approximately six hours apart around the cluster.

| Period | Entry closes | Battle | Normal entry cost |
| --- | --- | --- | --- |
| 0 | 23:17 | Opener, 20 minutes after swap | Equal-weight tier draw; mean 3,566.67 FLIP |
| 1 | 05:00 | Routine | 7:2:1 tier draw; mean 1,890 FLIP |
| 2 | 11:00 | Routine | Same distribution |
| 3 | 17:00 | Routine | Same distribution |
| 4 | 22:37 | Ordinary closer, 20 minutes before swap | Same terms as that day's opener; independent battle randomness |
| 5 | Daily RNG request at/after 22:57 | Jackpot battle | Fixed 10,000 FLIP |

At/after the 22:57 daily boundary, the jackpot request closes period 5's field. After fulfillment, paid batches run first and awarded batches close the shared battle as part of daily jackpot processing. Batching is a transaction gas bound, not a reason to move the battle hours before jackpot time.

### Ordinary presets

These retain the existing three bankroll tiers, three equally likely bounty choices per tier, day-opening RNG selection and normal five-round bankroll / five-times goal format. The numerical values increase as follows; every bankroll remains a multiple of 300 FLIP and every bounty a multiple of 100 FLIP, never greater than its bankroll.

| Tier | Bankroll | Bounty choices, paid into pot | Total entry price choices | Mean entry cost |
| --- | --- | --- | --- | --- |
| Small | 600 | 200 / 300 / 400 | 800 / 900 / 1,000 | 900 |
| Medium | 1,800 | 600 / 1,000 / 1,400 | 2,400 / 2,800 / 3,200 | 2,800 |
| Large | 4,500 | 1,500 / 2,500 / 3,500 | 6,000 / 7,000 / 8,000 | 7,000 |

All figures are FLIP. Opener and closer draw tiers equally, so their mean is `(900 + 2,800 + 7,000) / 3 = 10,700/3 = 3,566.67`. The three routine windows keep the 70% / 20% / 10% tier weighting, so their mean is `0.7*900 + 0.2*2,800 + 0.1*7,000 = 1,890`. Each ordinary price is known from the opening day's word before entry; its later settling word supplies the actual run randomness.

The whole day's expected entry cost is `2 * (10,700/3) + 3 * 1,890 + 10,000 = 68,410/3 = 22,803.33` FLIP. The current documented mean is `1,368,127/60 = 22,802.12`: a difference of only **1.22 FLIP**. Both round to **22,800 FLIP** at the existing nearest-100 denomination rule. This is expected entry cost, not a forecast of winnings. Actual live day prices still vary with the ordinary window draws.

The normal/high pass denominations can therefore stay 22,800 / 433,200 FLIP, the 19:1 conversion can stay intact, and the existing future-day retail prices of 25,000 / 450,000 FLIP can remain. Pass balances, debits, saturation and reservations stay count-based. The pass now covers six battles, so active-period loops, all-day high flags, accepted upgrade masks and per-window comp quotes must reflect six periods. Preserve the existing eight-slot day namespace and packed storage capacity; teach the scheduled cursor to skip its unused window position as well as the day-ticket position. Pricing/preset helpers give period 4 the opener's terms and advance price, and period 5 the fixed jackpot price. Advance quotes become 3,567 FLIP for either bookend (nearest whole FLIP), 1,890 for a routine window and 10,000 for the jackpot. The close/arming logic must recognize the new ordinary deadlines and period 5's daily-request lock. No pass-ledger expansion or dynamic pass valuation is required.

A day ticket supplies its period-5 seat to the paid jackpot field, with the same high flag and one-seat collision checks as direct entry. A wallet also selected by the jackpot draw receives an additional separately scored run using the same dice and entry-specific board scatter; its awarded run does not inherit the paid seat's high flag.

Implementation must distinguish the daily-request jackpot from the five lootbox-RNG ordinary windows. Preset selection, routine boost weighting, event detection, opening previews, advance comp quotes and keeper arming currently assume seven windows with the old deadlines. Recheck the boosted engine's return envelope at the increased chip sizes before relying on the existing handle-based house-boost calibration. Settle the old event's house-boost allocation explicitly and preserve the selected routine RIU shares (5%/10%) for the merged jackpot battle. The new schedule must not silently double-fund Added or switch its RIU shares. Paid runs use the normal work budget, then the awarded field closes the shared scoreboard once.

## Read and replay surface

Call the `JackpotBattle` ABI at **the CRAPS address** (the table delegates these selectors): `jackpotEntryPrice()`, `jackpotProgress()`, and `jackpotBattleOf(slot)`. The round view returns raw Added, rolled total pool, multiplier, per-unit bankroll/bounty, pot remainder, paid/awarded unit counts, field counts, committed word and cursor. `JackpotBattleLocked`, `JackpotBattleStarted`, `JackpotBattleEntry`, and the existing normal craps settlement/finalization events expose the same lifecycle to the indexer. `preferredBoardOf(player)` stays on the table.

The daily request locks the field. Stage 18 applies a fresh daily word without constructing or playing a battle. Stage 16 (jackpot phase) or 17 (purchase phase) first constructs the awarded field, up to 150 entries per call. The sealing call then settles on its leftover budget, and later calls resolve at most 1,500 work units plus one indivisible run of at most 1,511 rolls. Paid and awarded seats may share a call. Only after completion does Game continue its existing ticket/payout/transition stages. Stage 12 retains its separate gap-backfill transaction. Terminal game-over handling retains its existing precedence; it does not wait on a FLIP battle.
