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
- WWXRP starts with a **1B** uncirculated vault mint allowance, with further century
  allocations.
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

Game-over distribution and the later final sweep have distinct deadlines and beneficiaries.
After existing claim liabilities and applicable paid-deity refunds are reserved, 2% of the
distributable terminal pool is credited to the top affiliate for the terminal ticket level;
the remainder goes to that level's terminal ticket jackpot. With no ranked affiliate, the
ticket jackpot receives the entire distributable pool. Affiliate score must be claimed
before the terminal cohort is latched, ahead of the terminal word, to affect this award.
Later affiliate claims cannot change the credited winner or the terminal pool. The terminal decimator has been removed.
Read `DegenerusGameGameOverModule` and the reserve-token terminal paths for the exact
claim/forfeiture rules. Owner authority is enumerated in [Security](SECURITY.md).
