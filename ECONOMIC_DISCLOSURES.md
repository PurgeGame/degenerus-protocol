# Economic disclosures

This describes protocol allocations and rights, not a return guarantee. The source defines
price tables and reward curves.

## Creator and vault interests

- CREATOR receives the initial DGVE and DGVF share supplies, initially controlling the
  Vault. Governance authority follows DGVE ownership; redemptions follow the relevant shares.
- The creator allocation is **200B DGNRS**, backed by the **20% sDGNRS allocation** held by
  the wrapper. These are the same economic position, not two allocations. **50B** is
  released initially; **5B per level** vests to the current vault owner, capped at **200B**.
- Other initial sDGNRS allocations: affiliate 30%, lootbox 20%, whale 10%, reward 10%,
  presale box 10%. See `sDGNRS` and `DGNRS` for pool movements and redemption conditions.
- At the final transition close after levels **100, 200, 300, etc.**, a random **25–75%** of all
  sDGNRS burned since the previous such close is minted back into the ongoing
  pools, split **Whale : Affiliate : Lootbox : Reward = 1 : 3 : 2 : 1**. The first
  interval starts at deployment. This includes live player redemptions, wrapped
  redemptions' underlying sDGNRS burn, and automatic self-award burns. The committed
  transition RNG word selects a whole percentage (25 through 75; mean 50%). Each mint
  rounds down in raw token units; allocation dust goes to Lootbox. Creator and
  PresaleBox allocations receive no refill.
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
- Presale-box proceeds are capped at **50 ETH** and split **80% Vault / 20% sDGNRS**.
  Ordinary ticket/lootbox prize-pool funding is distinct from this presale allocation.
- The vault receives prescribed surplus/yield, default-referrer rewards and protocol-owned
  gameplay positions. It holds a genesis deity pass and, like every deity, receives **one
  perpetual ticket per level** (4 entries, granted 100 levels ahead and extended one level per
  level transition) and accrues BAF score from them like any player.
  The vault funds its daily lootbox subscription from its own balance. Vault positions
  may participate in rewards under their entry rules. The vault is excluded from BAF's
  top-4 leaderboard and its 10% top-bettor and 5% third/fourth-place slices, but retains
  BAF score for eligible ticket-based awards.
- The vault owner (>50.1% of DGVE) can register any address as a WWXRP minter and burner
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
- The craps comp allowance starts at **4.56M FLIP-equivalent** and grows by **2% of completed
  battle bankroll**. It cannot be cashed out, but grants produce ordinary player reward
  opportunities. Owner and delegate recipients are not restricted to unrelated wallets.
  Owner grants charge no delegate allowance; the lane balance is their only cap.

## Accounting and value

ETH/stETH obligations, FLIP coinflip credits, reserve-token backing, vault mint allowance
and comp allowance are separate ledgers. A credit is not necessarily a liquid token or
immediately withdrawable ETH. stETH yield/asset behavior is an external dependency; the
buffer is not a guarantee against arbitrary losses.

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

The early-bird jackpot converts large ticket prizes into a mixed award: once its
ordinary payout exceeds 45 tickets per winning slot and the pooled surplus can
cover a full prize pass at the 4.5 ETH accounting rate, every slot receives 45
tickets and one separate winner receives all surplus full passes. The pass draw
prefers eligible gold winning traits, including deity virtual entries; otherwise
it draws from the other eligible winning traits. The recipient need not have won
an immediate ticket prize. All early-bird ETH and rounding remainder still go to
nextPrizePool; these passes confer future participation, not a segregated ETH
reserve or cash claim. They must be claimed under the existing pass rules and
depend on continued play. Repeated ticket wins each retain their 45-ticket award;
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
After existing claim liabilities and applicable paid-deity refunds are reserved, 2% of the
distributable terminal pool is credited to the top affiliate for the terminal ticket level;
the remainder goes to that level's terminal ticket jackpot. With no ranked affiliate, the
ticket jackpot receives the entire distributable pool. Affiliate score must be claimed
before the terminal cohort is latched to affect this award. A newly requested terminal word
follows the latch; an already delivered ordinary word can precede it (see `KNOWN-ISSUES.md`).
Changing the allocation does not reroll jackpot recipients.
Later affiliate claims cannot change the credited winner or the terminal pool. The terminal decimator has been removed.
Read `DegenerusGameGameOverModule` and the reserve-token terminal paths for the exact
claim/forfeiture rules. Owner authority is enumerated in [Security](SECURITY.md).
