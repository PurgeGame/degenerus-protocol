# Security and authority

Report an affected function, preconditions, reproducible sequence, broken invariant and
impact to **burnie@degener.us** or a repository issue. The audit subject is the
[snapshot manifest](docs/audit/snapshot.json), not a live deployment claim.

## Roles

| Role | Authority and limits |
| --- | --- |
| Vault owner | Wallet with **more than 50.1% of DGVE**: `balance * 1000 > supply * 501`. Authority follows shares, not the deployer address. |
| Comp delegate | Owner-set FLIP-value spending limit. May grant any supported comp to any recipient. Cannot set prices, refill the shared budget or authorize delegates. Setting an allowance replaces it; zero revokes it. |
| Battle creator | Owner-authorized custom-battle creation within contract bounds. No comp-budget authority. |
| sDGNRS governance | VRF/feed recovery proposals and votes under stall, threshold and recovery-cancellation rules; balance-weighted charity voting through `GNRUS.vote`, once per slot per level, with multiple slots allowed. |
| Player-approved operator | Only the authority granted through the Game's operator mechanism; permissionless settlement alone grants no spending or withdrawal rights. |
| CREATOR | Initial allocations; icon-data setters until their irreversible finalization. This icon role is separate from DGVE ownership. |

## Vault-owner powers

- Spend/manage vault positions through its game, coinflip, subscription and redemption
  interfaces; set operator approvals and the salvage-purchase reserve policy.
- Grant comps and set delegate limits. Create custom battles, authorize creators, choose
  the vault's default craps board or disable future automatic seating, and amend its open slips.
- Distribute WWXRP from its vault allowance and AFKing seats within the token's tranche/lock
  rules; manage eligible vault seats and recover foreign tokens/NFTs. The foreign-token
  sweep excludes stETH backing. Share redemption still burns the relevant shares.
- Set lootbox RNG threshold and midday basefee ceiling. Declare Thanos scaling at least
  six levels ahead, with shift <=8, the projected-entry floor and pending-declaration locks.
- Stake surplus Game ETH into stETH subject to player-claim reserves; exchange supplied
  ETH for an equal amount of Game stETH through Admin.
- Propose VRF recovery after 44 hours of stall, or feed recovery after two unhealthy days.
  Community proposal paths require the specified sDGNRS stake and seven-day delay.
  Execution still needs the decaying vote threshold; recovery cancels applicable proposals.
  Retry retired-subscription cancellation with prescribed recovery destinations.
- Manage permitted charity slots, claim level-vested DGNRS, unwrap owned DGNRS under its
  restrictions, and set supported NFT renderers/colors. Charity slots 0..2 lock once filled;
  residual charity recovery has its own long post-game delay.

There is no owner setter for the craps engine, comp rate or shared comp balance. Contracts
have no proxy upgrade path. This does not make every configuration immutable: governance
can replace external VRF/feed endpoints and the owner can change the controls listed above.

## External dependencies and settlement

Chainlink supplies VRF randomness and the LINK/ETH price feed. LINK funds VRF requests;
the feed supports donation valuation. Lido stETH supplies external asset accounting.

Treat external failures, compromised owners and permissionless callers according to the
explicit boundaries above. Trusted governance decisions within those powers and the
accepted cases in [Known Issues](KNOWN-ISSUES.md) are distinguished from authority bypasses.

Permissionless processing must credit the rightful owner. Spending/cashout requires the
appropriate owner/operator authorization; caller-funded gifts spend the funder's resources.
Review post-game push-payment exceptions separately. Do not infer safety from a `view`,
`pure`, or trusted-address label alone; gas and failure behavior still matter.
