# Known issues

Accepted behaviors that could otherwise be reported as findings. Anything outside these
bounds is in scope.

| Issue | Accepted behavior |
| --- | --- |
| Permissionless timing | Boxes, Degenerette bets, scheduled craps windows, the daily jackpot battle and decimator winners each settle through an in-order walk (`advanceGame`, `openBoxes`, `mineFlip`, `keepScheduled`), so no caller chooses which item settles next; a caller chooses only when the next step runs. A step that lands before or after a level advance uses the level live at that moment: a box's boon draw, a decimator winner's box, the first level of whale-pass tickets queued by `claimWhalePass`, and crank bounty pricing. Anyone can make these calls as soon as they are possible, so timing is not a practical lever. |
| Small Thanos balance | A lone balance can truncate to zero at high shifts; maximum loss is 0.153 ETH at the highest effective price of 61.44 ETH per whole ticket (15.36 ETH per trait entry), less than 1% of one entry. |
| WWXRP | WWXRP is a joke prize token with no backing or intended value. The vault owner, and any minter it trusts, can mint any amount to anyone and burn any balance; supply, price and balances are unprotected. That includes minting WWXRP to enter the daily draw (about 606 FLIP a day on average) and the century incinerator (10% of the BAF day's lost FLIP), whose winners are weighted by WWXRP burned: the vault owner can take nearly all of that FLIP. Findings about WWXRP value, supply or draw weighting are out of scope; a path where WWXRP moves ETH, stETH, sDGNRS or tickets, or pays FLIP beyond what those draws pay by rule, remains in scope. |
| Governance | Outcomes of valid sDGNRS governance approval are governance decisions, not findings; bypasses of authorization, voting or execution rules remain in scope. Genesis-only self-disruption is excluded. |
