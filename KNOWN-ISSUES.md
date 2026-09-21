# Known issues and accepted assumptions

The following are disclosed design/acceptance boundaries for this handoff. A mechanism
or impact outside a stated bound remains a separate review question.

| Case | Disclosed behavior / boundary |
| --- | --- |
| Scheduled operation | Daily opening and on-schedule battle resolution are assumed. They are operational expectations, not ordering enforced on every permissionless entry point. |
| Daily VRF retry | Only while the requested word has not been received: the vault owner gets first opportunity after 11 hours; anyone can retry after 12 hours. The single retry replaces the request ID, discarding a late fulfillment of the original request. A governance coordinator swap re-arms the retry. |
| Mid-day request promotion | A lootbox-only mid-day VRF request stalled past 4 hours is abandoned by any caller's advance and re-issued as that day's daily request; the promoted request keeps its own 12-hour retry. |
| Vault AFKing recovery | `DegenerusVault.recoverAfkingFunding` is permissionless: anyone can return the vault's staged AFKing salvage reserve to the vault at gas cost, which makes the vault's salvage-buyer fallback in `sellFarFutureEntries` and the AFKing-funded leg of its own daily auto-buy interruptible until the owner re-stages. No value leaves the vault. |
| Unopened craps comp window | A window-ahead comp seat on a day that never opens, including a VRF-stalled day, is not refunded by the whole-day lapse sweep, which walks day tickets only. The seat was paid from the vault's FLIP comp lane, so the loss is comp-lane FLIP, not player money. Accepted under the scheduling assumption. |
| Cross-day progressive qualification | One day marker per winner can be overwritten by another day's routine win before the earlier event resolves; this can remove its doubling. Accepted under scheduled resolution. Shared progressive-pool depletion is also resolution-order-dependent. |
| Extended unattended advance | A stall of more than 120 days without a sealed day ends the game in every phase (`_vrfDeadmanFired` feeds `_livenessTriggered`), so the gap backfill (`_backfillGapDays`, bounded at 120 days for gas) never sees a wider gap. Days skipped by a shorter stall receive derived words and coinflip settlement only: no daily draw, no foil board, no seal. |
| Terminal entropy reuse before the affiliate latch | A delivered but unconsumed ordinary daily word can precede the terminal affiliate/cohort latch after the 14-day grace. An affiliate claim can still populate an empty terminal-level board before that latch, changing allocation from 100% ticket jackpot to 98% plus 2% affiliate. Jackpot winner seeds exclude payout amount as of the 2026-09-21 seed cleanup; `TerminalAffiliateKnownWord.t.sol` verifies identical recipients across both allocations. Requires a dead game and an empty board after 120 purchase days; retained as an allocation timing exception. |
| Terminal RNG fallback | Catastrophic prolonged VRF failure can use historical words with prevrandao for terminal release. The accepted terminal fallback is not a live-game entropy guarantee. |
| Whale-pass boon timing | A lootbox-rolled whale pass queues its tickets at `claimWhalePass`, so the queued levels follow the level at claim, not at box open; the claim window is four days from the roll. |
| Decimator bounty pricing | A decimator box's ETH-target bounty converts to FLIP at the active ticket level (`_activeTicketLevel`) when the batch settles, so a level advance between burn and settlement changes the FLIP paid. |
| Lootbox boon resolution | The boon draw is keyed on the live level when a box is opened, not the level at purchase or at the RNG request. The boon weight table is fixed, but its budget normalization is level-priced, so the same committed word can deliver a different boon type or hit chance if the box opens before versus after a level advance. Opening is permissionless and swept by the crank; the order of an open against an advance is not enforced. Accepted under the scheduling assumption. |
| Degenerette resolution | Assumes roughly chronological resolution; capped bonus allocation can depend on resolution order. |
| Small Thanos balance | A lone balance can truncate to zero on division at high shifts. The accepted bound is under 0.64 whole tickets (about 0.153 ETH at the highest ticket price), confined to the small position. |
| Affiliate rounding/selection | Deterministic affiliate selection and bounded floor-of-sum rounding differences; not a general allowance for redirecting funds or arbitrary rounding loss. |
| Bulk whale commission | The fresh affiliate rate halves at five or more paid passes in one call. A buyer can keep the full rate on the remainder above a multiple of five by buying it in a separate call; bonus passes are counted per five within a single call, so the split cannot gain a bonus pass. Accepted. |
| Vault-owner bounty eligibility | The DGVE-majority wallet is always bounty-eligible, regardless of activity or time of day. |
| Owner comps | Vault-owner comps charge no delegate allowance; their only cap is the shared FLIP comp lane balance. Recipients are unrestricted. |
| Governance | Outcomes requiring valid sDGNRS governance approval are governance decisions, not findings. Bypasses of authorization, voting or execution rules remain in scope. Genesis-only self-disruption is excluded. |

## Token and integration semantics

- sDGNRS and GNRUS are soulbound, not conventional transferable ERC-20s.
- DGNRS is a transferable ERC-20 whose only destination restriction is a revert on transfers
  to the DGNRS contract itself.
- FLIP protocol-authorized spending, coinflip auto-claim and special VAULT/sDGNRS routing
  are intentional; wallet supply, virtual allowance and backing are not interchangeable.
