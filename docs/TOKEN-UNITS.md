# FLIP and WWXRP amount units

FLIP and WWXRP use **zero decimals**. One raw unit is one token in balances,
allowances, transfer/mint/burn calls, and paid rewards. For
example, depositing 100 FLIP passes `100`, and entering a WWXRP draw with 25 tokens
passes `25`. Do not multiply these amounts by `10^18` or use `parseEther` for them.

ETH, stETH, LINK, DGNRS, sDGNRS, GNRUS, and vault shares keep their existing
18-decimal units. Mathematical fixed-point scales remain separate from token denominations. The
stateless Craps simulation, Decimator normalized peak, and internal box/foil spin
stakes retain 10^18 sub-units per token; their receipts are computation results,
not ERC20 balances. BoxSpin payouts and Craps battle payments are whole tokens.

Percentage calculations floor at the final payment boundary. Craps keeps fractional
wins and hot bonuses throughout a run, including escalation and affordability
checks. Box and foil spins retain fractional stakes and payouts until the reward
is paid. There is no persistent dust balance or carry ledger. FLIP-paid ticket
charges round up to the next whole token to avoid undercharging the buyer.

Existing explicit rules remain:

- A positive qualifying mining reward pays at least 1 FLIP. Zero and ineligible
  rewards remain zero; the prior formula's zero cutoff is preserved.
- Qualifying lootbox consolation uses `max(1, floor(ETH_wei * 500 / 10^18))` WWXRP.
  Thus 0.01 ETH corresponds to 5 WWXRP and 0.003 ETH to 1 WWXRP.
- Where the existing award mechanic applies, amounts above 1,000 FLIP are rounded
  stochastically to multiples of 100 FLIP. Smaller awards keep their integer amount.
- RNG-nudge prices floor each recurrence: 100, 150, 225, 337, 505, 757, 1,135, …
- Coinflip keeps eight uint32 daily stake lanes per player/word. The per-day cap is
  4,294,967,295 FLIP. Manual deposits above it revert; automatic credits saturate.
- The one-shot FLIP tombstone allowance is still economically 10^18 FLIP; its raw
  value is now `10^18`, rather than the former `10^36`.

The Craps-to-FLIP payment codec is `(amount << 8) | flags`. The receiver reads
`amount = encoded >> 8`; the low byte is flags, not amount data. Amounts must fit
248 bits, and only flag bits `0x1f` are permitted.

This coordinated change targets fresh deployments. Populated balances or storage
from an 18-decimal deployment cannot be reinterpreted in place. Token callers,
indexers, and displays must select units from each asset's metadata.
