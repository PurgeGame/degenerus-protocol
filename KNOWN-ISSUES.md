# Known issues

Accepted behaviors that could otherwise be reported as findings. Anything outside these
bounds is in scope.

| Issue | Accepted behavior |
| --- | --- |
| Small Thanos balance | A lone balance can truncate to zero at high shifts; maximum loss is 0.153 ETH at the highest effective price of 61.44 ETH per whole ticket (15.36 ETH per trait entry), less than 1% of one entry. |
| WWXRP | WWXRP is a joke prize token with no backing or intended value. The vault owner, and any minter it trusts, can mint any amount to anyone and burn any balance; supply, price and balances are unprotected. That includes minting WWXRP to enter the daily draw (about 606 FLIP a day on average) and the century incinerator (10% of the BAF day's lost FLIP), whose winners are weighted by WWXRP burned: the vault owner can take nearly all of that FLIP. Findings about WWXRP value, supply or draw weighting are out of scope; a path where WWXRP moves ETH, stETH, sDGNRS or tickets, or pays FLIP beyond what those draws pay by rule, remains in scope. |
| Governance | Outcomes of valid sDGNRS governance approval are governance decisions, not findings; bypasses of authorization, voting or execution rules remain in scope. Genesis-only self-disruption is excluded. |
| Reserved RNG words | Final session words 0 and 1 are refused, leaving the request pending for the existing retry/rotation paths. Daily nudges add modulo 2^256 before this check. The accepted probability is 2/2^256 per uniform word; no entropy-normalizing fallback is used. Other loss of callback authority or retry liveness remains in scope. |
| Serialized RNG sessions | Fresh daily and midday requests wait for every committed read consumer. Keeper work is bounded and resumable; paid consumer volume can delay the next request. A normal fresh request which overwrites unfinished read work, an unbounded reset, or a consumer that cannot progress remains in scope. |
| Terminal unfinished games | Terminal entry kills unfinished lootbox, Degenerette and non-daily Craps entropy consumers. No prior session word is retained to resolve them. Earned claims and the terminal level's paid ticket obligations retain their ending treatment; losing those claims or tickets remains in scope. |
| Bingo inventory retirement | A completed level stays claimable until actual L+2 generation takes over its parity buffer, subject to existing terminal restrictions. The deadline depends on game progression rather than a fixed number of days. Closing earlier or letting retired inventory win remains in scope. |
