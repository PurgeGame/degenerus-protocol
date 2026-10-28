# Known issues

Accepted implementation limitations. Only the specific effects described below are
accepted; broader impacts remain in scope under the [audit criteria](docs/AUDIT.md).

Game rules and economic rights are in [Economic Disclosures](ECONOMIC_DISCLOSURES.md).
Authority, external-service assumptions and configuration limits are in
[Security](SECURITY.md).

| Issue | Accepted limitation |
| --- | --- |
| Small Thanos balance | A lone balance can truncate to zero at high shifts; maximum loss is 0.153 ETH at the highest effective price of 61.44 ETH per whole ticket (15.36 ETH per trait entry), less than 1% of one entry. |
| Reserved RNG words | `rawFulfillRandomWords` returns normally without storing when the delivered word is 0 or 1 (1 is the waiting sentinel). The Game keeps waiting even though the coordinator has fulfilled the request; recovery needs a fresh request through the existing retry/rotation paths, or the 14-day ending applies. The accepted probability is 2/2^256 per delivered word; no entropy-normalizing fallback is used. Other loss of callback authority or retry liveness remains in scope. |
| Loan settlement timing | Loans due at a level settle in the first mining stage after the request that enters that level. Auto-repay reads the borrower's claimable and prepaid afking balances when that stage runs. If the level's random word is already public, a borrower may add or withdraw those balances after seeing it and so choose between repayment and seizure. Each loan must still be retired exactly once: the lender receives the full owed amount or the account. |
