# Known issues

Accepted behaviors that could otherwise be reported as findings. Anything outside these
bounds is in scope.

| Issue | Accepted behavior |
| --- | --- |
| Permissionless timing and order | Settlement, resolution and crank calls (advances, box opens, bet and battle resolution, claims, window closes) are permissionless and assumed to run in roughly chronological order, soon after each becomes possible. Running one early, late or out of order can shift a result slightly (the level a bounty, boon or whale pass is priced or queued at, a progressive doubling, a capped bonus allocation) within accepted bounds. Since anyone can make the call and it is made as soon as it is possible, the ordering is not a practical lever. |
| Daily VRF retry reroll | The vault owner's single retry, 12 hours into a stalled daily request, replaces the request, so a late fulfillment of the original is discarded: a reroll left to the same trusted party as the coordinator swap. |
| Mid-day promotion reroll | A lootbox-only mid-day request stalled past 4 hours is replaced by any caller's next-day advance, discarding a late fulfillment: one public reroll of that lootbox index. |
| Unrefunded craps comp seat | A window-ahead comp seat on a day that never opens (including a VRF-stalled day) is not refunded by the lapse sweep. The loss is vault comp-lane FLIP, not player money. |
| Transient liveness | Liveness reads true, then false again, in two windows: from the day after a deadline day whose distress buys met the target until that day's word is applied, and on the first day after the purchase deadline if nobody advances that day. Inside them purchases, burns and afking subscriptions revert, decimator claims take the terminal route, and an sDGNRS redemption claim settles in terminal shape and forfeits its FLIP escrow. |
| Small Thanos balance | A lone balance can truncate to zero at high shifts; bounded under 0.64 whole tickets (about 0.153 ETH at the highest ticket price). |
| Governance | Outcomes of valid sDGNRS governance approval are governance decisions, not findings; bypasses of authorization, voting or execution rules remain in scope. Genesis-only self-disruption is excluded. |
