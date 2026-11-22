# Economic disclosures

This describes protocol allocations and rights, not a return guarantee. The source defines price
tables and reward curves.

## Creator and vault interests

- CREATOR receives the initial DGVE and DGVF share supplies, initially controlling the Vault. Admin
  actions require escrowed DGVE approval exceeding **50.1% of current supply**, assigned before the
  execution block, through the fixed governance executor. Holders may delegate voting alone;
  withdrawals remain theirs. Redemptions follow the relevant shares. Burning a share class's entire
  supply pays its backing and mints the burner a fresh 1 trillion shares, so a class never reaches
  zero supply and its sole holder keeps it.
- The vault allocation is **200B DGNRS**, backed by the **20% sDGNRS allocation** held by the
  wrapper. These are the same economic position, not two allocations. **50B** is released to the
  Vault at deployment; **5B per level** vests to the Vault (anyone may trigger the release), capped
  at **200B**. DGVE owner governance decides what to do with it: redeem it under the live or
  post-game backing rules, unwrap up to **40B** over the contract's life into soulbound sDGNRS, or
  sweep it out. If the game ends before level 30, the unvested DGNRS stays in the wrapper: its
  sDGNRS backing keeps its share of the holder base, cannot be redeemed, and leaves with the year
  sweep.
- Other initial sDGNRS allocations: affiliate 30%, lootbox 20%, whale 10%, reward 10%, Degenesis
  10%. See `sDGNRS` and `DGNRS` for pool movements and redemption conditions.
- **Live sDGNRS redemption.** A burn joins the open batch and is priced when a daily or mid-day
  request closes it: its proportional share of the backing times a rolled whole percentage from **21
  to 175** (mean 98, so on average 2% stays with the remaining holders), limited to the backing
  available. Half is credited as claimable ETH and half opens a redemption lootbox; a lootbox half
  below **0.01 ETH** is not paid and stays in the backing. A live redemption needs at least 0.01 ETH
  of backing value. After game over a burn pays its proportional backing directly, with no roll. A
  burn made before the terminal payout completes is priced on the backing at that moment, without
  terminal winnings sDGNRS has not yet been credited.
- At the final transition close after levels **100, 200, 300, etc.**, a random **25–75%** (a whole
  percentage from the committed transition word; mean 50%) of the sDGNRS holder-base reduction since
  the previous such close (the first interval starts at deployment) is minted back into the ongoing
  pools, split **Whale : Affiliate : Lootbox : Reward = 1 : 3 : 2 : 1**, rounding down with dust to
  Lootbox. Burns counted include live and wrapped redemptions once their batches close, and
  automatic self-award burns. Vault and Degenesis allocations receive no refill.
- Recycling adds no ETH/stETH/FLIP backing and dilutes existing tokens at the refill: with fraction
  `b` of the previous checkpoint's holder base removed and refill fraction `r`, each surviving token
  loses `r*b / (1-b+r*b)` of its backing (with 50% burned, a 25/50/75% refill costs 20%, 33.3% or
  42.9%). Closed redemption batches keep their recorded pricing. The holder base stays at or below
  the initial ceiling and the previous post-refill holder base; token supply can increase at the
  refill. Reward settlement uses live-pool pricing, so an unresolved win may pay more tokens after a
  refill. Game over ends recycling with no catch-up mint.
- Degenesis is a seven-day launch sale (day indices 2 through 8; the main game starts on day 9) with
  no cap on aggregate ETH. It is not a return guarantee, and every reward below is random.
  - **Eligibility.** A buyer first spends on normal assets (tickets, lootboxes, passes and foil
    packs). While the window is open each such ETH, claimable or prepaid spend earns Degenesis
    credit equal to **25%** of the price paid; FLIP-paid spend, reward grants and Degenesis
    purchases earn none, and the Vault and sDGNRS earn none. Credit is permission to spend, not
    payment, and expires unused when the window closes. Buying a Degenesis box consumes credit 1:1
    and is paid separately. The Vault cannot buy.
  - **Orders.** A box costs at least **0.01 ETH**, in whole **0.0001 ETH** units, up to a per-order
    bound of about **27.5M ETH**. One roll per order; splitting an order changes variance, not the
    expected sDGNRS per ETH (apart from rounding and the fixed WWXRP consolation). A Degenesis box
    pays no affiliate commission. The purchase itself earns no quest, streak or activity credit; an
    additional drawn boon can grant activity or a quest shield.
  - **ETH routing.** Each day's ETH is held as a reserved obligation, then split once per daily
    cohort at the first daily request after the day ends: **25%** to the future prize pool, **25%**
    to the insurance accumulator (yield), **25%** to a restricted Vault purchase budget, **25%** to
    sDGNRS AFKing funding. The vault owner spends the budget through `spendDegenesis` on tickets,
    lootboxes or whale passes at normal prices for **any allocated account it selects** (recipient 0
    selects the Vault); the recipient receives the products and their normal rewards. A live
    purchase boost, lootbox boost or whale discount the recipient holds applies to that purchase and
    is used up by it; a whale discount lowers the budget's charge. The budget is never withdrawable.
    When the seventh cohort closes, sDGNRS AFKing funding above **10 ETH** moves to sDGNRS's
    claimable. Unspent Vault budget and the sDGNRS AFKing balance remaining at game over
    join the final prize distribution.
  - **Outcomes.** Each order rolls one exclusive category: **50%** FLIP-valued reward, **40%**
    sDGNRS, **10%** WWXRP, with an independent size roll for FLIP and sDGNRS. A FLIP result below
    one whole FLIP, a lost fractional pass, or a zero sDGNRS award pays the WWXRP consolation (1
    WWXRP before the vault owner's `gameMintScale`) instead; every order selects a primary reward or
    consolation before that scale applies.
  - **Additional boons.** Every primary outcome, including consolation, also draws from the ordinary
    boon table with a probability budget of **20% of the raw ETH order, capped at 1 ETH**,
    normalized at one boon's full-use value at launch level 1 (about 0.315 ETH), up to the
    sampler's whole-ppm rounding of each chance: each full 100%
    guarantees a draw and the remainder rolls once more, up to **three draws per order**. Activity,
    boosts, early bonuses and cohort volume do not multiply it; it creates no ETH reserve and does
    not reduce the primary reward. Types may repeat and ordinary upgrade/discard rules apply, so
    three draws need not give three active boons. Expiry starts on the settlement day, so early-sale
    boons can expire before launch. Splitting a large purchase can produce more draws by avoiding
    the per-order ceiling. Boon grants earn no Degenesis credit.
  - **sDGNRS schedule.** The sale pool is **100B** sDGNRS (10% of the initial supply). For a cohort
    with applied ETH `V` and remaining pool `R`, `Q = min(2.5T, 2/3 R)` with target `T = 20B` on
    days 1-3 and `10B` on days 4-7. An sDGNRS order of `x` ETH receives `x * Q * m / V`, with `m`
    uniform from 0.5 to 1.5 (mean 1), so expected awards within the cohort are proportional to order
    ETH and depend on the frozen cohort volume and remaining pool. The cohort reserves `1.5Q`, which
    no combination of rolls can exceed; the unused reservation is released when the cohort closes.
    Cohorts price strictly in order. Expected payout is about 20, 20, 16, 10, 9.1, 6.7 and 4.9B on
    days 1-7 (86.6B in total with many small orders); it is not guaranteed, varies with
    concentration, and a quiet day pays more per ETH. Whatever remains after the seventh cohort
    closes is burned, which raises every holder's share of the backing.
  - **FLIP ceiling.** The FLIP-valued reward keeps its random ladder, scaled by a day schedule
    (nominal mean 2.5x purchase value on day 1, falling 0.125x per day to 1.75x on day 7), an early
    bonus (up to +5%, falling to zero after six hours of the day), and a daily volume factor `46 ETH
    / (46 ETH + V)` frozen for the cohort. Expected FLIP-valued rewards over the sale stay below
    about **718 ETH of FLIP value (72M FLIP at 0.01 ETH per 1,000 FLIP)**, however much is sold;
    realized rewards can exceed that expected-value ceiling. A busy day pays less FLIP per ETH and
    a quiet day more.
  - **Settlement and forfeiture.** Orders resolve through the miner engine after their cohort's
    daily word; calculated primary FLIP and sDGNRS amounts are fixed by that word and the frozen
    cohort. FLIP credits remain subject to Coinflip's daily stake cap.
    **Unopened boxes are forfeited at game over**: their rewards are not claimable against the
    burned inventory.
  - Ordinary ticket/lootbox prize-pool funding is distinct from the Degenesis allocation.
- The vault receives prescribed surplus/yield, default-referrer rewards and protocol-owned gameplay
  positions. It holds a genesis deity pass and, like every deity, receives **one perpetual ticket
  per level** (4 entries, granted 100 levels ahead and extended one level per level transition) and
  accrues BAF score from settled coinflip wins like any player. The vault funds its daily lootbox
  subscription from its own balance. Vault positions may participate in rewards under their entry
  rules. The vault is excluded from BAF's top-4 leaderboard and its 10% top-bettor and 5%
  third/fourth-place slices, but retains BAF score for eligible ticket-based awards. The vault's
  own direct coinflip deposits enter BAF's armed-day weighted depositor draw and can set the flip
  record like any player's.
- WWXRP is a joke prize token with no backing or intended value; its supply is fully at the vault
  owner's (DGVE governance executor's) discretion:
  - **Free minting.** The vault owner can mint **WWXRP for free** to any nonzero recipient, up to
    the uint256 supply ceiling (`WWXRP.vaultMintTo`, `DegenerusVault.wwxrpMint`). There is no mint
    reserve or century allocation; Vault-held WWXRP uses ordinary balances and counts in total
    supply.
  - **Trusted minters** (`WWXRP.setTrustedMinter`, any nonzero address, revocable) each hold three
    separate powers without player approval: mint or credit amounts subject to the uint256 ceilings
    (`mintPrize`, `creditPrize`), burn any holder's balance or claimable credit (`burnForGame`,
    `burnForAccount`), and consume any player's WWXRP boon (`consumeBoon`).
  - **Game mint scale.** A whole-number multiplier with no upper bound applies to every WWXRP mint
    the game contracts request (`WWXRP.setGameMintScale`, default 1x), when the producer awards a
    mint or claimable credit: an award at scale 0 pays nothing and is not paid later (anyone can
    trigger a BAF consolation claim, so those are lost too). Withdrawals do not rescale earned
    credits; a pending BAF consolation uses the scale when its claim credits the account.
  - **Draws.** Discretionary minting also applies to the daily draw (up to about 606 FLIP a day in
    expectation with populated winning buckets and timely claims) and century incinerator when BAF
    is skipped (10% of the armed day's lost FLIP). Winners are weighted by WWXRP burned, so the
    vault owner can mint enough to take nearly all of those FLIP awards. Supply, price and balances
    are unprotected; the [audit boundaries](SECURITY.md#audit-boundaries) distinguish these rules
    from a path that pays assets beyond the prescribed awards.
- AFKing subscription seats: no seat is minted at deployment; the Vault's and sDGNRS's exempt
  subscriptions hold none. Once all **5,000** free-tranche seats are minted, the vault owner can
  mint further seats to chosen recipients while live seats plus the subscriber set stay at or below
  **10,002** (`SEAT_CAP`: 10,000 player places plus the two protocol subscriptions); capacity
  reopens as subscriptions leave the set.
- The craps comp allowance starts at **4.96M FLIP-equivalent** (`200 * CrapsPriceLib.NORMAL_VALUE`)
  and grows by **2% of completed non-jackpot battle eligible bankroll** (bankroll copies only: a
  sole high seat's extra bounty counts in the day's staked action but is bounty, not eligible
  bankroll), plus a jackpot battle's fee-based comp share (2% of its eligible base fees and 80% of a
  12% loss budget on extra high-seat fees at risk: all such fees for one high seat, half for
  multiple high seats) and, for a day that never opens, a refund of every window-ahead comp seat
  reserved in any of its six windows, at the class price charged for it, while that day is within
  the 30-day scheduled settlement deadline. It cannot be cashed out, but grants produce ordinary
  player reward opportunities. Owner and delegate recipients are not restricted to unrelated
  wallets. Owner grants charge no delegate allowance; the lane balance is their only cap.

## Accounting and value

ETH/stETH obligations, FLIP coinflip credits, reserve-token backing, vault mint allowance and comp
allowance are separate ledgers. A credit is not necessarily a liquid token or immediately
withdrawable ETH. stETH yield/asset behavior is an external dependency; the buffer is not a
guarantee against arbitrary losses.

Coinflip settles only the last **90 resolved days**. Older unclaimed stakes and stale auto-rebuy
carry forfeit; already banked claimable winnings do not expire. The Game banks the Vault's pending
winnings every 45 resolved days as well as at the x0 purchase seal. Skipped-bracket BAF consolation
expires when that player's score record for the bracket is reused by BAF score in a bracket 20,
40, ... levels later. Gameplay FLIP burns spend the
wallet, then banked coinflip winnings, then the player's auto-rebuy carry once that day's flip is
applied. Transfers and ordinary coinflip claims (`claimCoinflips`) never spend carry;
`claimCoinflipCarry` withdraws it. The Vault never spends carry through a gameplay burn; GNRUS's
purchase-phase-end ticket buy and sDGNRS's automatic Decimator entry do spend it, after that
account's banked coinflip winnings.

A winning coinflip day's reward percent gains 2 points on every day settled at level 0, on the
second day of a three-day jackpot phase and on the first settlement after a turbo jackpot phase,
and 6 points instead when that level (after a turbo phase, the turbo level) is a nonzero multiple
of 10. Re-bet winnings and auto-rebuy carry gain a 0.75% recycling bonus when they ride a flip;
with it, recycled stake has an expected return of about 99.16% on a normal day, 100.17% on a
2-point day and 102.19% on a 6-point day.

FLIP buys tickets (`redeemFlip`) only while the FLIP purchase window is open. A FLIP purchase opens
it when no daily request is in progress and the next pool is above the next level's target. GNRUS's
FLIP buy at the request that ends a purchase phase runs before that request takes the daily lock,
so it opens the window whenever GNRUS has FLIP to spend. The window stays open until the request for
that level's final jackpot draw. A window still closed when the phase-ending request takes the lock
opens during that level's jackpot days only if the next pool passes the following level's target
between draws.

Growth bets cost a fixed 1,000 FLIP, one per wallet ID per level, from a wallet with any past
purchase, pass or activity award or with a live AFKing run, and are open in a standard (three-draw)
jackpot phase until its third draw; turbo phases open no market. Round L resolves OVER when level
L+1's achieved prize pool times level L-1's exceeds the square of level L's (a tie is UNDER; for
round 1, level 0's term is the 50 ETH bootstrap pool) and
settles when level L+1's purchase phase closes and its pool consolidates; stakes burn at placement,
each winner is credited 1,000 FLIP times the round's bets divided by its winners, rounded down, as a
coinflip stake, and the rounding remainder, a round with no bet on the winning side and a round
still unsettled at game over stay burned.

Affiliate leaderboard and proportional DGNRS scores cap at **34,359,738,367 whole FLIP per wallet ID
per level**. The allocation denominator counts only accepted score. Commissions, kickbacks, quest
rewards and AFKing payouts keep their uncapped inputs. Current scores remain exact; exact retired
history is available from events, while clipped history preserves the activity-bonus calculation. At
each level entry the level's top affiliate receives 0.5% of the sDGNRS affiliate pool, and 2.5% of
the remainder is set aside for that level's proportional claims (`claimAffiliateDgnrs`); claims stay
open only while the game is at that level, and the part not claimed stays in the pool when the next
level replaces the allocation. A GNRUS ticket donation made under a donor's code pays that donor the
purchase bonus and the whole commission as one FLIP stake, with no upline split; GNRUS keeps the
tickets, quests, records and
activity. A GNRUS purchase without a donor code routes like any other purchase. Affiliate commission
is paid on fresh funding at 25% of the FLIP-valued spend at affiliate levels 1–3 and 20% after, and
on recycled funding at 5%. Lootbox commission tapers for a buyer whose activity score is 100 or
more, down to a quarter of the rate at 255; a purchase of five or more whale passes pays half the
fresh rate; and on the day before a level's final jackpot draw a ticket's fresh basis is raised by
7/5 at ticket levels up to 3 and by 3/2 after. Prepaid AFKing funds count as fresh funding on every
purchase, the same as ETH sent with it; only spend funded from claimable winnings is recycled. A
purchase's commission, less the kickback the code returns to the buyer (0–25%), goes whole to one
recipient: the code's owner on 15 of 20 outcomes, the owner's referrer on 4 and that referrer's
referrer on 1, chosen by a public hash of the calendar day, buyer and code, so every purchase by one
buyer under one code on one day lands on the same position in that chain, and nothing is paid when
that recipient is the buyer. A buyer without a referrer pays the Vault or sDGNRS on even odds, and a
buyer whose first affiliate-routed purchase carries no valid code keeps that route, since a stored
referral never changes.

Game EV depends on the product, activity, timing, prices and other participants. Do not extend a
claim about ticket-ETH routing into a claim of zero house edge for every side-game. Craps uses
distinct bankroll and bounty components: bounty does not earn the comp subsidy. Pass denominations
and fixed future retail prices differ intentionally; expected-value constants are not promises of a
realized payout. The game links no wallets: each wallet ID is a separate player with its own
activity score, limits and awards, so a person playing through several wallets plays as several
players. A cashout or smite curse lowers the activity score by one point per curse point, up to 20;
a ticket or box purchase paid in ETH, claimable or prepaid funds and costing at least one ticket
price clears it (an AFKing subscription's daily purchase does not), as do a foil pack, a whale,
lazy or deity pass purchase, and `decurse` for 100 FLIP. A FLIP-paid ticket purchase does not clear
it. In a combined order with a foil pack, the ticket and box legs are scored before the foil leg
clears the curse, so ticket and box legs that together cost less than one ticket price are scored
with the curse. Anyone may settle another account's half-pass credits, bingo and AFKing FLIP.
Settlement pays
that account (and, for AFKing FLIP, its affiliate chain), never the caller, and uses the state when
it runs: the whale-pass window starts at the next level, the bingo sDGNRS share is taken from the
Reward pool as it stands then, and the AFKing affiliate base follows the referrer chain and
leaderboard level current then ([AFKing
subscriptions](docs/ARCHITECTURE-DETAILS.md#afking-subscriptions)). Any half-pass claim, whatever its
size, activates the whole 100-level whale-pass status; the half-pass count sets only the tickets.

At each level's consolidation sDGNRS banks Craps high-roller passes worth up to 5% of the
consolidated current pool, valued in FLIP at the level's ticket price (the house's level cut), and
each completed level adds FLIP worth 0.2% of its achieved prize pool to Coinflip's record reward
pool. Neither debits an ETH pool.

Jackpot prize shapes (mechanics in [jackpot legs](docs/ARCHITECTURE-DETAILS.md#jackpot-legs)):

- **ETH quadrants, jackpot phase.** Up to 25% of each quadrant's ETH allocation (solo included)
  converts to full whale passes at 4.5 ETH each, starting at 18 ETH; the quadrant's first ETH
  winner receives all its passes in addition to its ETH prize (the solo winner holds both), the rest
  pays the quadrant's ETH winners, and the pass cost goes to futurePrizePool. The passes are a
  longer-term participation claim, not a cash claim.
- **Orange King.** On a jackpot-phase ETH draw without an active Decimator jackpot plan, an Orange
  King drawn in Cards moves half of the Cards allocation to the solo quadrant, or, when Cards is
  itself solo, half of each other quadrant's allocation to Cards. It applies before pass conversion
  and rounding and does not change the draw's total.
- **Daily ETH winner counts** scale with the budget in both phases: 32, 16 and 4 non-solo winners,
  doubling at 40, 160, 640, 2,560 and 10,240 ETH, up to 1,024, 512 and 128. Non-solo prizes are
  whole multiples of 0.1 ETH, so small budgets pay fewer winners, not smaller prizes; rounding goes
  to the solo winner. A wallet can win more than one slot. The terminal jackpot keeps fixed counts.
- **Ticket jackpots** (purchase daily, early bird, jackpot-phase daily) pay the three non-solo
  quadrants (solo only when it is the one quadrant with holders): up to 96 winners, up to 192 from
  40 ETH, and up to 384 from 160 ETH of awarded ticket value (half the moved ticket backing on the
  purchase daily: [purchase
  dailies](docs/ARCHITECTURE-DETAILS.md#purchase-timing-and-pool-acceleration)). Above 25 tickets
  per slot, when the surplus covers a full pass at 4.5 ETH, every slot keeps 25 tickets and
  the surplus becomes whole passes split across paying quadrants in proportion to their winners, one
  separately drawn recipient per quadrant (deity virtual entries included), who need not have won
  tickets. Repeated ticket wins add no pass-draw
  chances. All ticket-jackpot ETH and rounding stays in nextPrizePool; the passes must be claimed
  under the pass rules, depend on continued play and are not a segregated ETH reserve or cash claim.
- **Foil packs.** A pack costs ten ticket prices of the active ticket level, times 2^s on a Thanos
  level with shift s; each wallet may buy one per level, and 75% of the price goes to nextPrizePool
  and 25% to futurePrizePool. A pack raises the buyer's quest streak to at least 12 and freezes the
  buyer's activity score at purchase; the frozen score counts a quest streak of at least 12, sets
  the pack's multiplier (2.07x at the lowest score, 7, rising to 6x), which widens its four rarest
  colors, gold included, and is the score its reward spins use. Each day's board grades each of the
  pack's four lines from 0 to 8; grades 4 to 8 stake 16, 48, 280, 3,200 or 80,000 faces on reward
  spins, in ETH (40%, one face is one ticket price at the pack's level, without the Thanos factor),
  FLIP (40%, 1,000 FLIP a face) or WWXRP (20%, no value), and grade 8 adds a half whale pass. Three
  or more gold quadrants among the sixteen pay 20,000, 80,000, 250,000, 750,000, 2,500,000 or
  7,500,000 FLIP for 3, 4, 5, 6, 7 and 8 or more, plus 25,000 FLIP when exactly one line is all
  gold. A pack with two or more all-gold lines instead takes the golden-ticket grand when it
  generates outside an ending: 25% of futurePrizePool as claimable ETH, then the current, next and
  future pools plus the yield accumulator less that ETH, 75% of it as half whale passes at 2.25 ETH
  and 25% as FLIP at the next level's ticket price, in whole 100-FLIP units. Match and gold awards
  pay only when claimed (`claimFoilMatch`, `claimGoldenTicket`) inside their two-day windows ([RNG
  domains](docs/audit/RNG-DOMAINS.md#foil-packs)) and never once liveness triggers; the grand needs
  no claim.

Every level's purchase target, level 0 included, has a **30-game-day** window from
`purchaseStartDay` (level 0's starts at `MAIN_LAUNCH_DAY`). Day 30 activates distress purchases; if
the target is still unmet, game over becomes eligible once that day's session has completed and a
later wall-clock reset day has begun. A stall adds no game days; 14 days without a completed daily
session takes the hard-stall ending instead. Funded jackpot phases can extend wall-clock time.
Ordinary purchase dailies budget **4% of the future pool**, split 75/23/2 between ticket backing,
ETH prizes and insurance; unpaid ETH prizes stay in the future pool. Level 0 runs a FLIP-only daily
path. See [the timing and skim
curve](docs/ARCHITECTURE-DETAILS.md#purchase-timing-and-pool-acceleration).

### Game-over treatment

Terminal entry ends unfinished lootbox, Degenerette and non-daily Craps entropy consumers. No prior
session word is retained to resolve them. Already-earned claims and the terminal level's paid
ticket obligations retain their specified protections. A half-pass credit awarded but not yet
claimed gives no tickets once liveness triggers: `claimWhalePass` reverts from then on. Coinflip
deposits, growth bets (when the dead-VRF ending interrupts a jackpot phase) and future Craps
reservations from ordinary accounts are still accepted after terminal entry; nothing resolves or
refunds them, and FLIP and Craps passes have no value after game over.

- **VRF-alive ending (purchase timeout).** The game-over path settles every outstanding loan, then
  requests its own terminal word after liveness freezes purchases and latches the terminal cohort.
  After existing claims are reserved, the whole distributable pool goes to the terminal level's
  ticket jackpot. This ending refunds no deity pass; a deity holder can still win terminal ticket
  prizes through its tickets. The terminal request leaves the RNG cycle unfinished for good, so the
  Vault's DGNRS unwrap stays refused after this ending; no ETH or stETH exit reads that state, and
  the Vault's DGNRS still redeems its backing through the wrapper's burn until the year sweep.
- **Deterministic dead-VRF ending.** Fourteen days without a completed daily session, or a request
  whose word is still not in use 14 days after it was sent (including a terminal request), takes
  this path even if the coordinator would still answer. No daily session completes after terminal
  entry, so a VRF-alive ending that has not set `gameOver` within 14 days of the last completed daily
  session also takes this path. This path starts no new loan settlement, terminal request or jackpot
  draw; earlier loan settlements remain effective: after claims are reserved and, below level 10,
  paid deity passes are refunded (the lesser of the price paid and 20 ETH, in purchase order, within
  the funds not reserved for existing claims, the Vault's Degenesis budget or sDGNRS's AFKing
  balance; those two are released after the refunds and join only the ticket pot), the remaining
  pool is shared across the terminal level's tickets through `claimDeadVrf`. Tickets not yet created
  take the average share; created tickets split the rest equally per occupied trait bucket and then
  equally within a bucket, so an entry in a thin bucket takes more than one in a crowded bucket. The
  RNG state the unanswered request left stays set: the cycle stays unfinished, and the daily RNG
  lock stays held when the
  request was a daily one. After game over no ETH or stETH exit reads that state; it refuses the
  Vault's DGNRS unwrap and keeps a Craps preferred board from being saved.
- **Sealed Decimator round.** In either ending, a round that is sealed but not yet paid stays
  reserved outside the terminal pot and cannot be paid after terminal entry. The final sweep releases
  it with the rest of the remainder.
- **Final sweep.** **30 days after terminal payout completes** (`GO_TIME`, stamped when the terminal
  jackpot finishes or the hard-stall pot is fixed), the Vault, sDGNRS and GNRUS receive their own
  game balances and thirds of the remaining Game ETH/stETH, and **every other unclaimed game
  balance, including unclaimed `claimDeadVrf` shares, is forfeited**. A share no terminal ticket can
  take (an empty trait bucket, rounding, or the whole pot when the terminal level has no tickets)
  stays in the Game until then.
- **Year sweep.** From **365 days after terminal payout completes** (`GO_TIME`, as for the final
  sweep), once the final sweep has run, anyone may call `sDGNRS.yearSweep`, which sends all ETH and
  stETH sDGNRS holds half to GNRUS and half to the Vault (repeatable, so later arrivals are swept
  too). The first sweep **ends every sDGNRS claim**: native and wrapped (DGNRS) burns and
  uncollected redemption claims revert from then on. GNRUS's half belongs to whoever holds GNRUS
  when it arrives: a holder who burns earlier takes no share of it, and the owner's forced
  redemption of a holder (`vaultRedeemFor`) waits for the first year sweep for that reason. Whatever
  GNRUS still holds three years after the first year sweep, the Vault owner may move to the Vault
  (`sweepResidualToVault`).

The phase accounting is in [Accounting](docs/ACCOUNTING.md); owner authority is in
[Security](SECURITY.md).

## Native randomness funding

At level entry, yield surplus (custody beyond obligations) is distributed **23% each** to the Vault,
sDGNRS and GNRUS as claimable balances and **23%** to the insurance accumulator; the remaining 8%
stays unallocated.

VRF requests are paid in ETH. Funding takes untracked yield first, then sDGNRS ordinary claimable,
then its prepaid AFKing balance: at level entry (before the 23% stakeholder distributions, and only
for a deficit of at least a tenth of the target/low-water gap), at a daily low-water check, and at a
coordinator swap when the replacement subscription is below low water. Each sDGNRS debit reduces
aggregate claim liabilities by the amount sent. A debit from ordinary claimable reduces its live
redemption backing immediately; prepaid AFKing is excluded from that backing. No other player's
claim, prize pool, redemption reserve or accumulated yield is debited. Funding uses only the Game's
liquid ETH and never swaps or unstakes stETH. Manual staking keeps one funding target beyond its
claim ETH reserve; automatic staking retains `claimablePool` with no additional VRF target. These
ETH reserves are soft for funding, while total ETH plus stETH must still cover all obligations.

A native donation sends its full value to the subscription and banks floor(value / 4) wei of mid-day
request credit, spendable only by the donor's own `mineRun` against pending work; it earns no FLIP
and has no value after game over. Optional lootbox requests require the subscription balance floor;
daily, retry, terminal and craps requests do not. Custom battles and expensive fulfillment can
consume more than the scheduled-window estimate; refills and donations replenish the subscription
when liquid sources exist.

A below-threshold mid-day lootbox request spends `300,000 * (max(basefee, 0.01 gwei) + 0.25 gwei) *
2` wei of the caller's credit; queues at or above the threshold and Craps windows pay nothing
([mid-day gates](docs/ARCHITECTURE-DETAILS.md#mid-day-requests)). Four donated wei back each credit
wei. The subscription pays the actual coordinator bill, including any excess over donation backing.
The compiled funding estimates and coordinator-rotation limits are documented in
[Security](SECURITY.md#vrf-funding-configuration).
