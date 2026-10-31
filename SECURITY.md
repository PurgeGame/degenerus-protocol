# Security and authority

Report an affected function, preconditions, reproducible sequence, broken invariant and impact to
**burnie@degener.us** or a repository issue. The audit subject is the [audit
handoff](docs/AUDIT.md), not a live deployment claim.

## Roles

| Role | Authority and limits |
| --- | --- |
| Vault owner | Fixed DGVE governance executor. Admin actions require proposal approval assigned before the execution block exceeding **50.1% of live DGVE supply**. Direct Vault gameplay requires that majority under one caller’s control in deposits from earlier blocks; exactly 50.1% fails. No wallet has direct owner access. |
| Voting delegate | May assign or clear an owner's escrowed DGVE votes; a majority under one caller's control also permits direct Vault gameplay and restricted-budget purchases. Cannot withdraw, redeem or transfer that owner's tokens, change their delegate, or use their player account. |
| Comp delegate | Owner-set FLIP-value spending limit. May grant any supported comp to any recipient. Cannot set prices, refill the shared budget or authorize delegates. Setting an allowance replaces it; zero revokes it. |
| Battle creator | Owner-authorized custom-battle creation within contract bounds. No comp-budget authority. |
| sDGNRS governance | Emergency VRF coordinator-swap proposals and votes under stall, threshold and recovery-cancellation rules; balance-weighted charity voting through `GNRUS.castBallot`, once per slot per level, with multiple slots allowed. |
| Player-approved operator | Only the authority granted through the Game's operator mechanism; permissionless settlement alone grants no spending or withdrawal rights. |
| CREATOR | Initial allocations; one-time installation of each icon path/name quadrant. This bootstrap closes on completion or the first successful governance icon write/finalization. Later icon changes require governance and remain possible only before finalization. |

Each owner can withdraw their escrow at any time or revoke delegation while clearing support. Voting
delegation grants full voting trust over that position. Same-block exclusion prevents atomic
borrowing from supplying votes; it provides no review delay and does not exclude borrowing across
blocks. Proposals expire after seven days. See [DGVE owner approval](docs/OWNER_GOVERNANCE.md).

## Vault-owner powers

- Spend/manage vault positions through its game, coinflip, subscription and redemption interfaces;
  set operator approvals and the liquidation-buyer fallback (on/off and its ETH floor).
- Grant comps and set delegate limits. Create custom battles, authorize creators, choose the vault's
  default craps board and amend its open slips.
- Mint WWXRP for free to any nonzero recipient up to the uint256 supply ceiling; register or revoke
  trusted WWXRP minters, each of which may mint or credit amounts within the uint256 ceilings, burn
  any holder's WWXRP and consume any player's WWXRP boon ([WWXRP
  boons](docs/WWXRP-BOONS.md#future-ecosystem-applications)). Distribute AFKing seats within the
  token's tranche/lock rules; manage eligible vault seats and recover foreign tokens/NFTs. The
  foreign-token sweep excludes stETH backing. Share redemption still burns the relevant shares.
- Set lootbox RNG threshold and midday basefee ceiling. Declare Thanos scaling at least three levels
  ahead, with shift <=8, the projected-entry floor and pending-declaration locks.
- Stake surplus Game ETH into stETH, keeping the player-claim ETH reserve and the VRF funding target
  in ETH; exchange supplied ETH for an equal amount of Game stETH through Admin, paying the
  explicitly approved recipient.
- Permanently raise a registered main ID's base smurf allowance directly through the Game, up to
  65,535 base creations, plus one per 120 current main activity points, subject to the 65,535 total
  lifetime creation cap. Grants preserve prior creation counts and never permit children of smurfs.
- Retry an unanswered live RNG request once after 20 hours through Admin. This replaces the
  transport request ID while preserving its logical day, kind, committed cohort and original
  timeout. It cannot replace a word already accepted by the Game. This recovery power does not prove
  that a privileged actor with advance knowledge of an undelivered VRF result cannot prefer a
  replacement request.
- Propose a VRF coordinator swap after 44 hours of stall. The community proposal path opens only
  after a seven-day stall and requires the proposer to hold at least 0.5% of sDGNRS voting supply;
  there is no post-proposal delay. Execution still needs the decaying vote threshold; recovery
  cancels applicable proposals. Retry retired-subscription cancellation with prescribed recovery
  destinations.
- Manage permitted charity slots; burn or unwrap the Vault's DGNRS under its restrictions (the
  level-vested release is permissionless and always pays the Vault); set supported NFT
  renderers/colors; and edit or finalize the icon data until it is finalized. Charity slots 0..2
  lock once filled; residual charity recovery has its own long post-game delay.

There is no owner setter for the craps engine, comp rate or shared comp balance. Contracts have no
proxy upgrade path. This does not make every configuration immutable: governance can replace the
external VRF coordinator endpoint and the owner can change the controls listed above.

## External dependencies and settlement

Chainlink VRF v2.5 supplies randomness. Requests are paid in native ETH from the subscription, which
yield surplus, sDGNRS balances and `donateVrf` donations fund; there is no LINK token or price feed.
Healthy Lido stETH behavior is assumed for external asset accounting.

A failed stETH balance read can be treated as zero. The Game's bounded read (`_boundedStethBalance`)
returns zero for a failed or malformed response, so the one-shot final sweep can close while stETH
remains at the Game, even if the read later recovers; the sweep reverts instead if the read starts
short of gas.
`test/repro/V08StethDeadSweep.t.sol::test_revertingSteth_sweepCompletesAndLeavesStethInPlace`
asserts this with a mocked reverting `balanceOf`. This presupposes a failed external asset, which
the dependency assumption above excludes; the boundary says nothing about the market value of a
failed token. A way for an ordinary caller to induce this outcome with healthy supported stETH,
including through gas selection, remains in scope. Distinguish this from a transfer failure, which
reverts the sweep.

### VRF callback trust and request IDs

Callback authority is the coordinator address plus the low 64 bits of the request ID
(`vrfRequestId`, packed beside `vrfCoordinator`). All request paths, including retries and
coordinator-swap re-issues, refuse an ID whose low 64 bits are zero. A consumed session retains its
answered ID. The callback relies on Chainlink VRF v2.5 deleting the request commitment before
calling back, so each request can be fulfilled only once.

A coordinator that delivered the same request twice could overwrite `rngWordCurrent` while boxes,
bets, Craps or Decimator consumers remain unresolved; later reads of the shared session word would
use the second word. The accepted trust assumption is the coordinator's one-fulfillment guarantee.
Separately, a superseded or dropped request could match a later retained ID through a low-64-bit
collision. Assuming independent, uniformly distributed IDs, the chance of that match is 2^-64 per
late delivery against a retained nonzero ID. Coordinator authentication still applies; truncation
does not let an arbitrary caller submit a word.

### VRF funding configuration

Funding estimates use the constants compiled into `ContractAddresses`: `VRF_LANE_MAX_GAS_PRICE` is
200 gwei and `VRF_NATIVE_PREMIUM` is 24% for the configured Ethereum mainnet lane. The minimum
fulfillment balance includes the configured callback gas limit; low-water and target balances scale
up when that limit exceeds 150,000. A mid-day lootbox request requires 1.5x the minimum fulfillment
balance. Daily, retry, Craps and terminal requests are not balance-gated.

Rotating to a lane with a higher maximum gas price or premium does not update the compiled
constants. The subscription must have enough ETH for the selected coordinator's actual billing.
Underfunding can leave requests unanswered until `donateVrf` or a direct top-up funds them; retry,
rotation and the 14-day ending retain their existing rules. Credit pricing and refill sources are
described in [Native randomness funding](ECONOMIC_DISCLOSURES.md#native-randomness-funding).

## Audit boundaries

Outcomes of valid sDGNRS governance approval are governance decisions; bypasses of authorization,
voting or execution rules remain in scope. Genesis-only self-disruption is excluded under the [audit
criteria](docs/AUDIT.md).

WWXRP's discretionary supply and burn-weighted draws are described in [Economic
Disclosures](ECONOMIC_DISCLOSURES.md#creator-and-vault-interests). Findings about its value, supply
or draw weighting are excluded. A path where WWXRP moves ETH, stETH, sDGNRS or tickets, or pays FLIP
beyond what those draws pay by rule, remains in scope.

The ending rules do not exclude an actor-induced stall, brick or premature ending. Earned claims and
the terminal level's paid ticket obligations must retain their specified protections; losing those
claims or tickets remains in scope.

Treat external failures, compromised owners and permissionless callers according to the explicit
boundaries above. Trusted governance decisions within those powers and the accepted cases in [Known
Issues](KNOWN-ISSUES.md) are distinguished from authority bypasses.

Permissionless processing must credit the rightful owner. Spending/cashout requires the appropriate
owner/operator authorization; caller-funded gifts spend the funder's resources. Review post-game
push-payment exceptions separately. Do not infer safety from a `view`, `pure`, or trusted-address
label alone; gas and failure behavior still matter.
