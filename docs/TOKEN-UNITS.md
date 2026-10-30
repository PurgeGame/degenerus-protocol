# FLIP and WWXRP amount units

FLIP and WWXRP use **zero decimals**. One raw unit is one token in balances, allowances,
transfer/mint/burn calls, and paid rewards. For example, depositing 100 FLIP passes `100`, and
entering a WWXRP draw with 25 tokens passes `25`. Do not multiply these amounts by `10^18` or use
`parseEther` for them.

ETH, stETH, GNRUS and the two vault share tokens use 18 decimals. DGNRS and sDGNRS use 12 decimals.
Mathematical fixed-point scales are separate from token denominations. The stateless Craps
simulation, Decimator normalized peak, and internal box/foil spin stakes carry 10^18 sub-units per
token (`TOKEN_MATH_SCALE`); their receipts are computation results, not ERC20 balances. BoxSpin
payouts and Craps battle payments are whole tokens.

Craps and box/foil spin payments floor to whole tokens at the final payment boundary. Craps keeps
fractional wins and hot bonuses throughout a run, including escalation and affordability checks. Box
and foil spins keep fractional stakes and payouts until the reward is paid. There is no persistent
dust balance or carry ledger. FLIP-paid ticket charges round up to the next whole token so the buyer
is never undercharged.

Explicit rounding rules:

- A positive qualifying mining reward pays at least 1 FLIP. A reward whose 10^18-scaled value floors
  to zero pays nothing, and ineligible callers are paid nothing.
- Qualifying lootbox consolation has a base amount of `max(1, floor(ETH_wei * 500 / 10^18))`
  WWXRP, using the reward roll's ETH amount. Before WWXRP's `gameMintScale` (default 1), 0.01 ETH
  corresponds to 5 WWXRP and 0.003 ETH to 1 WWXRP; the scale applies when the prize is credited.
- Where the award mechanic applies (`FlipRoundLib`), amounts above 1,000 FLIP are rounded
  stochastically to multiples of 100 FLIP. Smaller awards keep their integer amount.
- RNG-nudge prices floor each recurrence: 100, 150, 225, 337, 505, 757, 1,135, …
- Coinflip keeps seven uint32 daily stake lanes and a page tag per word. The per-day cap is
  4,294,967,295 FLIP. Manual deposits above it revert `StakeAboveDailyCap`; automatic credits
  saturate.
- Affiliate leaderboard/DGNRS scores cap at 34,359,738,367 FLIP per wallet ID per level. Commission
  and kickback payouts do not inherit this score cap.
- The one-shot game-over FLIP tombstone adds up to `10^18` raw units (10^18 FLIP) to the Vault
  mint allowance, saturating at uint128 max.

The Craps-to-FLIP payment codec is `(amount << 8) | flags`. The receiver reads `amount = encoded >>
8`; the low byte is flags, not amount data. Amounts must fit 248 bits, and only flag bits `0x1f` are
permitted (`InvalidCrapsFlags` otherwise).

Token callers, indexers, and displays must select units from each asset's `decimals()`.
