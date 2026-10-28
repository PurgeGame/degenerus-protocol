# Economic disclosures

This describes protocol allocations and rights, not a return guarantee. The source defines
price tables and reward curves.

## Creator and vault interests

- CREATOR receives the initial DGVE and DGVF share supplies, initially controlling the
  Vault. Owner actions require escrowed DGVE approval exceeding **50.1% of current supply**,
  assigned before the execution block, through the fixed governance executor. Holders may
  delegate voting alone; withdrawals remain theirs. Redemptions follow the relevant shares.
- The vault allocation is **200B DGNRS**, backed by the **20% sDGNRS allocation** held by
  the wrapper. These are the same economic position, not two allocations. **50B** is
  released to the Vault at deployment; **5B per level** vests to the Vault (anyone may trigger
  the release), capped at **200B**. DGVE owner governance decides what
  to do with it: burn it for backing, which lands ETH/stETH in vault reserves, unwrap up to
  **40B** over the contract's life into soulbound sDGNRS, or sweep it out.
- Other initial sDGNRS allocations: affiliate 30%, lootbox 20%, whale 10%, reward 10%,
  Degenesis 10%. See `sDGNRS` and `DGNRS` for pool movements and redemption conditions.
- At the final transition close after levels **100, 200, 300, etc.**, a random **25–75%** (a
  whole percentage from the committed transition word; mean 50%) of all sDGNRS burned since the
  previous such close (the first interval starts at deployment) is minted back into the ongoing
  pools, split **Whale : Affiliate : Lootbox : Reward = 1 : 3 : 2 : 1**, rounding down with dust
  to Lootbox. Burns counted include live redemptions, wrapped redemptions' underlying burn and
  automatic self-award burns. Vault and Degenesis allocations receive no refill.
- Recycling adds no ETH/stETH/FLIP backing and dilutes existing tokens at the refill: with
  fraction `b` of the previous checkpoint's supply burned and refill fraction `r`, each surviving
  token loses `r*b / (1-b+r*b)` of its backing (with 50% burned, a 25/50/75% refill costs 20%,
  33.3% or 42.9%). Submitted redemption claims keep their recorded amounts. Supply stays below
  the initial ceiling and at or below the previous post-refill supply, but can increase at the
  refill itself. Reward settlement uses live-pool pricing, so an unresolved win may pay more
  tokens after a refill. Game over ends recycling with no catch-up mint.
- Degenesis is a seven-day launch sale (day indices 2 through 8; the main game starts on day 9)
  with no cap on aggregate ETH. It is not a return guarantee, and every reward below is random.
  - **Eligibility.** A buyer first spends on normal assets (tickets, lootboxes, passes and foil
    packs). While the window is open each such ETH,
    claimable or prepaid spend earns Degenesis credit equal to **25%** of the price paid; FLIP-paid
    spend, reward grants and Degenesis purchases earn none, and the Vault and sDGNRS earn none.
    Credit is permission to spend, not payment, and expires unused when the window closes. Buying a
    Degenesis box consumes credit 1:1 and is paid separately. The Vault cannot buy.
  - **Orders.** A box costs at least **0.01 ETH**, in whole **0.0001 ETH** units, up to a per-order
    bound of about **27.5M ETH**. One roll per order; splitting an order changes variance, not the
    expected sDGNRS per ETH (apart from rounding and the fixed WWXRP consolation). A Degenesis box
    pays no affiliate commission. The purchase itself earns no quest, streak or activity credit;
    an additional drawn boon can grant activity or a quest shield.
  - **ETH routing.** Each day's ETH is held as a reserved obligation, then split once per daily
    cohort at the first daily request after the day ends: **25%** to the future prize pool, **25%**
    to the insurance accumulator (yield), **25%** to a restricted Vault purchase budget, **25%** to
    sDGNRS AFKing funding. The vault owner spends the budget through `spendDegenesis` on tickets,
    lootboxes or whale passes at normal prices for **any allocated account it selects** (recipient
    0 selects the Vault); the recipient receives the products and their normal rewards. The budget
    is never withdrawable. Unspent Vault budget and all sDGNRS AFKing funding join the final prize
    distribution at game over.
  - **Outcomes.** Each order rolls one exclusive category: **50%** FLIP-valued reward, **40%**
    sDGNRS, **10%** WWXRP, with an independent size roll for FLIP and sDGNRS. A FLIP result below
    one whole FLIP, a lost fractional pass, or a zero sDGNRS award pays the WWXRP consolation
    (1 WWXRP before the vault owner's `gameMintScale`) instead; no order resolves to nothing.
  - **Additional boons.** Every primary outcome, including consolation, also draws from the
    ordinary boon table with a probability budget of **20% of the raw ETH order, capped at
    1 ETH**, normalized at launch level 1 with the ordinary 50% utilization assumption: each full
    100% guarantees a draw and the remainder rolls once more, up to **three draws per order**.
    Activity, boosts, early bonuses and cohort volume do not multiply it; it creates no ETH reserve
    and does not reduce the primary reward. Types may repeat and ordinary upgrade/discard rules
    apply, so three draws need not give three active boons. Expiry starts on the settlement day,
    so early-sale boons can expire before launch. Splitting a large purchase can produce more draws
    by avoiding the per-order ceiling. Boon grants earn no Degenesis credit.
  - **sDGNRS schedule.** The sale pool is **100B** sDGNRS (10% of the initial supply). For a cohort
    with applied ETH `V` and remaining pool `R`, `Q = min(2.5T, 2/3 R)` with target `T = 20B` on days
    1-3 and `10B` on days 4-7. An sDGNRS order of `x` ETH receives `x * Q * m / V`, with `m`
    uniform from 0.5 to 1.5 (mean 1), so every order's expected award is proportional to its ETH and
    independent of other orders. The cohort reserves `1.5Q`, which no combination of rolls can
    exceed; the unused reservation is released when the cohort closes. Cohorts price strictly in
    order. Expected payout is about 20, 20, 16, 10, 9.1, 6.7 and 4.9B on days 1-7 (86.6B in total
    with many small orders); it is not guaranteed, varies with concentration, and a quiet day pays
    more per ETH. Whatever remains after the seventh cohort closes is burned, which raises every
    holder's share of the backing.
  - **FLIP ceiling.** The FLIP-valued reward keeps its random ladder, scaled by a day schedule
    (nominal mean 2.5x purchase value on day 1, falling 0.125x per day to 1.75x on day 7), an early
    bonus (up to +5%, falling to zero after six hours of the day), and a daily volume factor
    `46 ETH / (46 ETH + V)` frozen for the cohort. Expected FLIP-valued rewards over the sale stay
    below about **718 ETH of FLIP value (72M FLIP at 0.01 ETH per 1,000 FLIP)**, however much is
    sold; individual rolls are random and uncapped. A busy day pays less FLIP per ETH and a quiet
    day more.
  - **Settlement and forfeiture.** Orders resolve through the miner engine after their cohort's
    daily word; reward amounts are fixed by that word and the frozen cohort. **Unopened boxes are
    forfeited at game over**: their rewards are not claimable against the burned inventory.
  - Ordinary ticket/lootbox prize-pool funding is distinct from the Degenesis allocation.
- The vault receives prescribed surplus/yield, default-referrer rewards and protocol-owned
  gameplay positions. It holds a genesis deity pass and, like every deity, receives **one
  perpetual ticket per level** (4 entries, granted 100 levels ahead and extended one level per
  level transition) and accrues BAF score from them like any player.
  The vault funds its daily lootbox subscription from its own balance. Vault positions
  may participate in rewards under their entry rules. The vault is excluded from BAF's
  top-4 leaderboard and its 10% top-bettor and 5% third/fourth-place slices, but retains
  BAF score for eligible ticket-based awards.
- WWXRP is a joke prize token with no backing or intended value; its supply is fully at the
  vault owner's (DGVE governance executor's) discretion:
  - **Free minting.** The vault owner can mint **unlimited WWXRP for free** to any nonzero
    recipient (`WWXRP.vaultMintTo`, `DegenerusVault.wwxrpMint`). There is no mint reserve or
    century allocation; Vault-held WWXRP uses ordinary balances and counts in total supply.
  - **Trusted minters** (`WWXRP.setTrustedMinter`, any address, revocable) each hold three
    separate powers with no cap and no player approval: mint or credit any amount to any recipient
    (`mintPrize`, `creditPrize`), burn any holder's balance or claimable credit (`burnForGame`, `burnForAccount`),
    and consume any player's WWXRP boon (`consumeBoon`).
  - **Game mint scale.** A whole-number multiplier with no upper bound applies to every WWXRP
    mint the game contracts request (`WWXRP.setGameMintScale`, default 1x), at mint time, not
    when the prize is won: a prize minted at scale 0 mints nothing and is not paid later (anyone
    can trigger a BAF consolation claim, so those are lost too), and an unclaimed award pays at the
    scale set when it is claimed.
  - **Draws.** Discretionary minting also applies to the daily draw (about 606 FLIP a day on
    average) and century incinerator (10% of the BAF day's lost FLIP). Winners are weighted by
    WWXRP burned, so the vault owner can mint enough to take nearly all of those FLIP awards.
    Supply, price and balances are unprotected; the [audit boundaries](SECURITY.md#audit-boundaries)
    distinguish these rules from a path that pays assets beyond the prescribed awards.
- AFKing subscription seats: construction mints serial 1 to sDGNRS (it has no transfer
  surface, so that seat never leaves) and serial 2 to the Vault (transferable like any seat).
  Once all **1,000** free-tranche seats are claimed, the vault owner can mint further seats
  to chosen recipients while live seats plus the subscriber set stay at or below **2,000**
  (`SEAT_CAP`), which leaves at most **998** vault-minted seats.
- The craps comp allowance starts at **4.96M FLIP-equivalent** (`200 * CrapsPriceLib.NORMAL_VALUE`)
  and grows by **2% of completed battle bankroll**, plus a jackpot battle's high-seat comp
  share (80% of a 12% loss budget on high-seat fees) and refunds of prepaid jackpot-window
  entries for periods that never ran. It cannot be cashed out, but grants produce ordinary player reward
  opportunities. Owner and delegate recipients are not restricted to unrelated wallets.
  Owner grants charge no delegate allowance; the lane balance is their only cap.

## Accounting and value

ETH/stETH obligations, FLIP coinflip credits, reserve-token backing, vault mint allowance
and comp allowance are separate ledgers. A credit is not necessarily a liquid token or
immediately withdrawable ETH. stETH yield/asset behavior is an external dependency; the
buffer is not a guarantee against arbitrary losses.

Coinflip settles only the last **90 resolved days**. Older unclaimed stakes and stale
auto-rebuy carry forfeit; already banked claimable winnings do not expire. The Game
banks the Vault's pending winnings every 45 resolved days as well as at the x0 purchase
seal. Skipped-bracket BAF consolation expires when that player's two alternating score
records are reused.

Affiliate leaderboard and proportional DGNRS scores cap at **34,359,738,367 whole
FLIP per wallet ID per level**. The allocation denominator counts only accepted score.
Commissions, kickbacks, quest rewards and AFKing payouts keep their uncapped inputs.
Current scores remain exact; exact retired history is available from events, while
clipped history preserves the activity-bonus calculation.

Game EV depends on the product, activity, timing, prices and other participants. Do not
extend a claim about ticket-ETH routing into a claim of zero house edge for every side-game.
Craps uses distinct bankroll and bounty components: bounty does not earn the comp subsidy.
Pass denominations and fixed future retail prices differ intentionally; expected-value
constants are not promises of a realized payout.

Jackpot prize shapes (mechanics in [jackpot legs](docs/ARCHITECTURE-DETAILS.md#jackpot-legs)):

- **ETH quadrants, jackpot phase.** Up to 25% of each quadrant's ETH allocation (solo included)
  converts to full whale passes at 4.5 ETH each, starting at 18 ETH; one fresh draw from the
  quadrant receives all its passes, the rest pays its normal ETH winners, and the pass cost goes to
  futurePrizePool. The passes are a longer-term participation claim, not a cash claim.
- **Daily ETH winner counts** scale with the budget in both phases: 32, 16 and 4 non-solo winners,
  doubling at 40, 160, 640, 2,560 and 10,240 ETH, up to 1,024, 512 and 128. Non-solo prizes are
  whole multiples of 0.1 ETH, so small budgets pay fewer winners, not smaller prizes; rounding goes
  to the solo winner. A wallet can win more than one slot. The terminal jackpot keeps fixed counts.
- **Ticket jackpots** (purchase daily, early bird, jackpot-phase daily) pay the three non-solo
  quadrants (solo only when it is the one quadrant with holders): 96 winners, 192 from 40 ETH, 384
  from 160 ETH. Above 25 tickets per slot, when the surplus covers a full pass at 4.5 ETH, every
  slot keeps 25 tickets and the surplus becomes whole passes split across paying quadrants in
  proportion to their winners, one separately drawn recipient per quadrant (deity virtual entries
  included), who need not have won tickets. Repeated ticket wins add no pass-draw chances. All
  ticket-jackpot ETH and rounding stays in nextPrizePool; the passes must be claimed under the pass
  rules, depend on continued play and are not a segregated ETH reserve or cash claim.

Every level's purchase target, level 0 included, has a **30-game-day** window from
`purchaseStartDay` (level 0's starts at `MAIN_LAUNCH_DAY`). Day 30 activates distress purchases;
if the target is still unmet, game over becomes eligible once that day's session has completed and
a later wall-clock reset day has begun. A stall adds no game days; 14 days without a completed
daily session takes the hard-stall ending instead. Funded jackpot phases can extend wall-clock
time. Ordinary purchase dailies budget **4% of the future pool**, split 75/23/2 between ticket
backing, ETH prizes and insurance; unpaid ETH prizes stay in the future pool. Level 0 runs a
FLIP-only daily path. See [the timing and skim curve](docs/ARCHITECTURE-DETAILS.md#purchase-timing-and-pool-acceleration).

### Game-over treatment

Terminal entry ends unfinished lootbox, Degenerette and non-daily Craps entropy consumers.
No prior session word is retained to resolve them. Already-earned claims and the terminal
level's paid ticket obligations retain their specified protections.

- **VRF-alive ending (purchase timeout).** The game-over path settles every outstanding loan,
  then requests its own terminal word after liveness freezes purchases and latches the terminal
  cohort. After existing claims and applicable paid-deity refunds are reserved, the whole
  distributable pool goes to the terminal level's ticket jackpot.
- **Deterministic dead-VRF ending.** Fourteen days without a completed daily session, or a
  request whose word is still not in use 14 days after it was sent (including a terminal
  request), takes this path even if the coordinator would still answer. There is no loan
  settlement, terminal request or jackpot draw: after claims and deity refunds are reserved, the
  remaining pool is shared across the terminal level's tickets through `claimDeadVrf`.
- **Final sweep.** **30 days after terminal payout completes** (`GO_TIME`, stamped when the
  terminal jackpot finishes or the hard-stall pot is fixed), the Vault, sDGNRS and GNRUS receive
  their own game balances and thirds of the remaining Game ETH/stETH, and **every other unclaimed
  game balance, including unclaimed `claimDeadVrf` shares, is forfeited**.

The phase accounting is in [Accounting](docs/ACCOUNTING.md); owner authority is in
[Security](SECURITY.md).

## Native randomness funding

VRF requests are paid in ETH. Funding takes untracked yield first, then sDGNRS ordinary
claimable, then its prepaid AFKing balance: at level entry (before the 23% stakeholder
distributions, and only for a deficit of at least a tenth of the target/low-water gap), at a
daily low-water check, and at a coordinator swap whose old subscription could not refund. Each
sDGNRS debit reduces aggregate claim liabilities by the amount sent, so its live price and
redemption preview reflect it immediately. No other player's claim, prize pool, redemption
reserve or accumulated yield is debited. Funding uses only the Game's liquid ETH and never swaps
or unstakes stETH; staking keeps one funding target beyond the player-claim ETH reserve, which is
soft for funding, while total ETH plus stETH must still cover all obligations.

A native donation sends its full value to the subscription and banks floor(value / 4) wei of
mid-day request credit, spendable only by the donor's own `mineRun` against pending work; it earns
no FLIP and has no value after game over. Optional lootbox requests require the subscription
balance floor; daily, retry, terminal and craps requests do not. Custom battles and expensive
fulfillment can consume more than the scheduled-window estimate; refills and donations replenish
the subscription when liquid sources exist.

A below-threshold mid-day lootbox request spends `300,000 * (max(basefee, 0.01 gwei) +
0.25 gwei) * 2` wei of the caller's credit; queues at or above the threshold and Craps windows
pay nothing ([mid-day gates](docs/ARCHITECTURE-DETAILS.md#mid-day-requests)). Four donated wei
back each credit wei; at the measured bill of about 107,000 gas and 24% premium that covers
roughly 18 times `max(basefee, 0.01 gwei) + 0.25 gwei`, an estimate, not a bound. The
subscription pays the actual bill, including any excess over the donation backing. The compiled funding estimates and coordinator-rotation limits are documented
in [Security](SECURITY.md#vrf-funding-configuration).
