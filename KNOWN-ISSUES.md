# Known issues

Accepted behaviors that could otherwise be reported as findings. Anything outside these
bounds is in scope.

| Issue | Accepted behavior |
| --- | --- |
| Permissionless timing and order | Settlement, resolution and crank calls (advances, box opens, bet and battle resolution, claims, window closes) are permissionless and assumed to run in roughly chronological order, soon after each becomes possible. Running one early, late or out of order can shift a result slightly (the level a bounty, boon or whale pass is priced or queued at, a progressive doubling, a capped bonus allocation) within accepted bounds. Since anyone can make the call and it is made as soon as it is possible, the ordering is not a practical lever. |
| Small Thanos balance | A lone balance can truncate to zero at high shifts; bounded under 0.64 whole tickets (about 0.153 ETH at the highest ticket price). |
| WWXRP | WWXRP is a joke prize token with no backing or intended value. The vault owner, and any minter it trusts, can mint any amount to anyone and burn any balance; supply, price and balances are unprotected. That includes minting WWXRP to enter the daily draw (about 606 FLIP a day on average) and the century incinerator (10% of the BAF day's lost FLIP), whose winners are weighted by WWXRP burned: the vault owner can take nearly all of that FLIP. Findings about WWXRP value, supply or draw weighting are out of scope; a path where WWXRP moves ETH, stETH, sDGNRS or tickets, or pays FLIP beyond what those draws pay by rule, remains in scope. |
| Governance | Outcomes of valid sDGNRS governance approval are governance decisions, not findings; bypasses of authorization, voting or execution rules remain in scope. Genesis-only self-disruption is excluded. |
