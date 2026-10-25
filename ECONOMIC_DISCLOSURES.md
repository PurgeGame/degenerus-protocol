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
- At the final transition close after levels **100, 200, 300, etc.**, a random **25–75%** of all
  sDGNRS burned since the previous such close is minted back into the ongoing
  pools, split **Whale : Affiliate : Lootbox : Reward = 1 : 3 : 2 : 1**. The first
  interval starts at deployment. This includes live player redemptions, wrapped
  redemptions' underlying sDGNRS burn, and automatic self-award burns. The committed
  transition RNG word selects a whole percentage (25 through 75; mean 50%). Each mint
  rounds down in raw token units; allocation dust goes to Lootbox. Vault and
  Degenesis allocations receive no refill.
- Recycling adds no ETH/stETH/FLIP backing and reduces existing tokens' share of
  that backing at the refill. If a fraction `b` of the supply standing at the
  previous checkpoint was burned during the century and the refill fraction is
  `r` (0.25–0.75), each surviving token loses `r*b / (1-b+r*b)` of its backing
  at that close, ignoring raw-unit rounding. With 50% burned, a 25%, 50%, or 75%
  refill reduces backing per surviving token by 20%, 33.3%, or 42.9%, respectively.
  Existing submitted redemption claims retain their recorded amounts. Supply
  remains below the initial ceiling and at or below the previous post-refill
  supply; it can increase at the refill itself. Permissionless
  reward settlement retains live-pool pricing, so an unresolved win may pay more
  tokens after replenishment. Game over permanently ends recycling, with no final
  catch-up mint for an unfinished century.
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
    cohort at the first daily request after the day ends: **50%** to the future prize pool, **25%** to
    a restricted Vault purchase budget, **25%** to sDGNRS AFKing funding. The Vault budget buys
    tickets, lootboxes or whale passes for the Vault through `spendDegenesis` and is never
    withdrawable. Unspent Vault budget and all sDGNRS AFKing funding join the final prize
    distribution at game over.
  - **Outcomes.** Each order rolls one exclusive category: **50%** FLIP-valued reward, **40%**
    sDGNRS, **10%** WWXRP, with an independent size roll for FLIP and sDGNRS. A FLIP result below
    one whole FLIP, a lost fractional pass, or a zero sDGNRS award pays the WWXRP consolation
    (1 WWXRP before the vault owner's `gameMintScale`) instead; no order resolves to nothing.
  - **Additional boons.** Every primary outcome, including consolation, also draws from the
    ordinary boon table using a probability budget of **20% of the raw ETH order, capped at
    1 ETH**. Normalize at launch level 1 with the existing 50% utilization assumption: each full
    100% chance guarantees a draw and the remainder rolls once for another, up to **three draws
    per order**. Activity, boosts, early-purchase bonuses and cohort volume do not multiply this
    budget. It creates no ETH reserve and does not reduce the exclusive primary reward.
    Types may repeat; ordinary upgrades, ignored equal/lower tiers and deity-discount discards
    apply. Three draws need not produce three active boons. Expiry starts on the settlement day,
    so early-sale boons can expire before launch. Splitting large purchases into separate orders
    can produce more total draws by avoiding the per-order ceiling. Neither Degenesis purchases
    nor boon grants earn new Degenesis credit. Ordinary boxes keep their existing one-draw rules.
    `DegenesisBoonsRolled` immediately precedes `DegenesisOrderResolved`: bytes 0, 1 and 2 of
    `boonTypes` identify selected types in draw order, including ignored/discarded draws, with
    unused bytes zero. A zero-draw order still emits the companion event.
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
- The vault owner (the DGVE governance executor) can register any address as a WWXRP minter and burner
  (`WWXRP.setTrustedMinter`), with no cap on what a trusted address may mint or burn. A trusted
  address may also spend any player's WWXRP boon through `WWXRP.consumeBoon`, without that
  player's approval. The vault owner also sets a whole-number multiplier, with no upper bound,
  on every WWXRP mint the game contracts request (`WWXRP.setGameMintScale`, default 1x).
  It applies when the mint happens, not when the prize is won: a WWXRP prize minted while the
  multiplier is 0 mints nothing and is not paid later (anyone can trigger a BAF consolation
  claim, so those are lost too), and an unclaimed award pays at whatever multiplier is set when
  it is claimed. This is
  deliberate: WWXRP is the inflationary side coin, future games are meant to pay and take it, and
  the vault is its sovereign. Treat WWXRP's supply as fully at the vault owner's discretion.
- The vault owner can mint **unlimited WWXRP for free** to any nonzero recipient through
  `WWXRP.vaultMintTo` or `DegenerusVault.wwxrpMint`. There is no mint reserve or century
  allocation. Vault-held WWXRP uses ordinary token balances and counts in total supply.
- The vault holds one permanent AFKing subscription seat and controls a **998-seat**
  tranche it can mint to chosen recipients once all **1,000** free-tranche seats have
  been minted. sDGNRS holds the other permanent seat, for **2,000** seats total.
- The craps comp allowance starts at **4.96M FLIP-equivalent** (`200 * CrapsPriceLib.NORMAL_VALUE`)
  and grows by **2% of completed battle bankroll**. It cannot be cashed out, but grants produce ordinary player reward
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
clipped history preserves the existing activity-bonus calculation.

Game EV depends on the product, activity, timing, prices and other participants. Do not
extend a claim about ticket-ETH routing into a claim of zero house edge for every side-game.
Craps uses distinct bankroll and bounty components: bounty does not earn the comp subsidy.
Pass denominations and fixed future retail prices differ intentionally; expected-value
constants are not promises of a realized payout.

During jackpot phase, each quadrant's ETH allocation can fund a separate full
whale-pass prize using up to 25% of that allocation, rounded down at 4.5 ETH per
full prize pass. A quadrant starts converting at 18 ETH. One fresh draw from
that quadrant receives all its passes; the remaining budget, including the
unused part of the conversion allowance, pays its normal ETH winners. The exact
pass cost goes to futurePrizePool. The solo quadrant follows this same full-pass
rule. These awards concentrate part of the quadrant's prize in one longer-term
participation claim; they do not create a cash withdrawal claim for that value.

Daily ETH jackpots in both phases scale their winner counts with the day's ETH budget:
32, 16 and 4 non-solo winners, doubling at 40, 160, 640, 2,560 and 10,240 ETH, up to
1,024, 512 and 128. Every non-solo prize
is a whole multiple of 0.1 ETH, so small budgets pay fewer winners rather than smaller
prizes, and rounding leftovers go to the solo winner. Winning slots can pay the same
wallet more than once. The terminal jackpot keeps its fixed winner counts.

Every ticket jackpot (the purchase-phase daily, the early bird and the jackpot-phase
daily) pays tickets to holders of the day's winning traits in the board's three
non-solo quadrants (the solo quadrant already pays the day's solo ETH prize; it serves
only when it is the one quadrant with holders). Winner counts double with the ticket
budget: 96, then 192 from 40 ETH and 384 from 160 ETH. Large
prizes become a mixed award: once the payout exceeds 25 tickets per winning slot and
the pooled surplus can cover a full prize pass at the 4.5 ETH accounting rate, every
slot receives 25 tickets and the surplus full passes split across the quadrants that
paid tickets, in proportion to their winners, with one separately drawn recipient per
quadrant (deity virtual entries included). A recipient need not have won an immediate
ticket prize. All ticket-jackpot ETH and rounding remainder still go to
nextPrizePool; these passes confer future participation, not a segregated ETH
reserve or cash claim. They must be claimed under the existing pass rules and
depend on continued play. Repeated ticket wins each retain their 25-ticket award;
they do not add chances to the separate pass draw.

After level 0, the purchase target has a **30-day** window: day 30 is the distress
rescue day, and an unmet target can trigger game over on day 31. Level 0 keeps its
365-day deadline, provided a day is sealed at least every 30 days (the VRF deadman
applies at every level). Funded jackpot phases and the existing VRF recovery rules can
extend elapsed wall-clock time. Ordinary purchase dailies budget **4% of the future
pool**, retaining the 75/23/2 ticket-backing / ETH-prize / insurance split; unpaid ETH
prizes stay in the future pool. Level 0 keeps its FLIP-only daily path. The faster
deadline and revised transition skim change when funds become available for prizes;
see [the timing and skim
curve](docs/ARCHITECTURE.md#purchase-timing-and-pool-acceleration).

Game-over distribution and the later final sweep have distinct deadlines and beneficiaries.
In the normal, VRF-alive ending, after existing claim liabilities and applicable paid-deity
refunds are reserved, 2% of the distributable terminal pool is credited to the top affiliate
for the terminal ticket level; the remainder goes to that level's terminal ticket jackpot. With no ranked affiliate, the
ticket jackpot receives the entire distributable pool. Affiliate score must be claimed
before the terminal cohort is latched to affect this award. The game-over path requests its
own terminal word after liveness freezes purchases and the cohort and affiliate are latched.
Changing the allocation does not reroll jackpot recipients.
Later affiliate claims cannot change the credited winner or the terminal pool.

When VRF is dead, the ending is deterministic: it pays no affiliate share and performs no
jackpot draw. After existing claims and applicable deity refunds are reserved, the remaining
pool is shared across the terminal level's tickets through `claimDeadVrf` until the final
sweep. An unanswered normal-ending terminal request also takes this path after 14 days.
The terminal decimator has been removed.
Read `DegenerusGameGameOverModule` and the reserve-token terminal paths for the exact
claim/forfeiture rules. Owner authority is enumerated in [Security](SECURITY.md).

## Native randomness funding

VRF requests are paid in ETH. At level entry, funding takes untracked yield before the
23% stakeholder distributions, then sDGNRS ordinary claimable and finally its prepaid
AFKing balance if needed. Level entry funds only a deficit of at least a tenth of the
gap between target and low-water. A daily low-water check, and a coordinator swap whose
old subscription could not refund, refill to target in the same order. Each sDGNRS
debit reduces aggregate claim liabilities by the exact amount sent, so its live price
and redemption preview reflect that spending immediately. No other player's claim,
prize pool, redemption reserve or accumulated yield is debited.

Funding is limited to the Game's liquid ETH. It never swaps or unstakes stETH. Staking
retains one funding target beyond the player-claim ETH reserve; that reserve is soft
for funding, while total ETH plus stETH must still cover all remaining obligations.

A native donation sends its full value to the subscription and banks floor(value / 4)
wei of mid-day request credit. Only the donor's own mineFlip can spend that credit,
against pending work. It earns no FLIP and has no value after game over. Optional
lootbox requests require the subscription balance floor; daily, retry, terminal and
craps requests do not. Custom battles and unusually expensive fulfillment can consume
more than the scheduled-window funding estimate; daily refills and donations replenish
the subscription when liquid funding sources are available.
