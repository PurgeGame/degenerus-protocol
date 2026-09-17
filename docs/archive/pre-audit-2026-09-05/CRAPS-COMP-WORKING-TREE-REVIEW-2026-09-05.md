> Historical document. Superseded by the [current audit handoff](../../AUDIT.md). Claims and test counts below apply only to their original revision.

# Working-tree review: craps comps and authority

Reviewed on 2026-09-05 against HEAD e013043d9 plus the current working tree.
No production source was edited by this review. This is a targeted review of the new
comp allowance, recipient-aware entry refactor, engine extraction and related wiring;
it is not a rerun of the earlier full-repository audit.

## Verdict and concrete follow-ups

No demonstrated contract accounting, recipient-ownership or authorization defect found
in the reviewed paths. The accrual formula implements 2% of bankroll only, once per
completed battle. Pass/comp/paid seats count alike; high seats contribute their full
multiplied bankroll. The sole high rider's bounty capital is excluded.

1. **Local indexer ABI integration is unfinished.** The sibling database checkout still
   vendors `crapsCompsRemaining`, `crapsGrantComps` and `CrapsCompsGranted`. Those are removed
   here. The replacement getter is on FLIP, and new grant/spend/accrual events need ABI,
   retention and consumer updates. This is a deployment integration gap, not a demonstrated
   change to player payouts. Read-only inspection; no database files changed.
2. **Comp upgrades still report their charge in a field named burned.**
   `_upgradeDayWindows` emits `CrapsDayWindowsUpgraded(..., burned)` for both paid and comp
   upgrades, although comp upgrades debit an allowance and burn no player FLIP. The local
   database's `handleCrapsDayWindowsUpgraded` writes that field directly into its `burned`
   column. Consumers must distinguish comp funding, or the event should report actual
   burned value separately from comp charge. Existing `CrapsCompSpent` and
   `CrapsCompGranted` identify the allowance debit. This is a reporting mismatch, not an
   extra token debit.
3. **Custom-entry comps are not implemented.** Kind 0 routes only through
   `_joinableWindow(period)`, which admits today's scheduled periods 0..6. Custom battles
   earn allowance, but the vault cannot spend it on custom seats. The newer build plan
   explicitly makes this choice; it differs from the earlier all-entry-types plan.

## Implementation as written

The balance is `FLIP.crapsCompAllowance()`, initialized to 4,560,000 ether of FLIP units.
It replaces the old 200-pass lifetime counter. It is separate from token balances,
circulating supply and the vault's ordinary mint allowance. No owner refill, rate setter,
transfer, withdrawal or cash conversion exists for this allowance.

At finalization, B = slot bankroll, N = total seats, K = high seats, H = high multiplier:

    eligible = B * N
    if K != 0: eligible += B * K * (H - 1)
    earned = eligible / 50

The guarded high term handles custom battles with no high lane. It credits FLIP through
CRAPS-only `creditCrapsComps`. Completed-scoreboard state is committed first. No accrual
occurs for a partial field, unused pass credit, bounty, donation, boost, prize or return.
Day tickets contribute their window-specific bankroll on each window's completion.
Scheduled and custom fields, including protocol-body seats, accrue. Re-resolving an
already completed field does not credit again.

The vault owner submits `DegenerusVault.crapsComp(uint256[] codes)`. Vault forwards each
code to CRAPS-only-to-vault `vaultComp`, which computes the charge. The existing FLIP
craps burn door checks CRAPS first and switches to allowance debit on its internal comp
flag. It returns before burning tokens, consuming a boon or reporting a paid quest action.
Every player-paid entry supplies zero for the comp flag.

| Kind | Grant | Debit |
| --- | --- | --- |
| 0 | Today's scheduled window, normal/high | (bankroll + bounty) × selected multiple |
| 1 | Today's whole day, normal/high, before first window closes | Sum of all seven window prices |
| 2 | Consecutive future days, normal/high | 25,000 / 450,000 FLIP per day |
| 3 | Selected windows of recipient's existing day ticket upgraded to high | Sum of missing (H-1) × (bankroll + bounty) |
| 4 | Banked normal/high passes | 22,800 / 433,200 FLIP per pass actually banked |

Credit excludes bounty; priced grant debit includes bounty. Granting does not itself
accrue budget, but those seats earn the same 2% after playing. Grants respect ordinary
closing, duplicate-seat, lane and recipient-standing rules. New comp seats start with
zero named chips; the recipient can amend their own slip before its cutoff. Existing
boons survive upgrades. Banked passes are banked directly, without the old grant's
automatic tomorrow reservation. Near a pass-lane cap, fewer passes may bank and only
those are charged; a completely full lane reverts. Counts/masks are uint8. Any reverted
item unwinds the entire vault batch.

Encoding: address bits 0..159; kind 160..167; high flag 168; period/first day/ticket day
176..199; count or upgrade mask 200..207. The operator cannot choose a discount or price.
There is no comp quote/max-debit API in this version.

## Authority map

Most owner powers follow `balanceOf(DGVE) * 1000 > totalSupply(DGVE) * 501`, not a permanent
admin EOA, deployer flag, or DGVF majority. Holding exactly 50.1% does not qualify. This
review did not query a deployed chain to identify the current qualifying wallet.

- Craps: create custom battles with permitted terms; grant/revoke battle-creator status;
  set the vault's default board or `uint32.max` to stop future automatic day seating;
  amend vault-owned open slips; spend vault funds entering custom battles; grant the
  scheduled/day/pass comps above to any nonzero recipient, including one's own wallet.
  A delegated battle creator gets creation rights, not comp-budget authority. No owner
  power replaces the engine, chooses RNG, changes settled bets, or changes the fixed 2%.
- Vault operations: play/purchase/subscribe/claim using the exposed vault game actions;
  sell eligible vault future entries; configure salvage purchasing and reserve floor;
  manage vault coinflip deposits, claims, auto-rebuy and decimator participation; set
  game operator approvals. These are concrete spending powers over the vault's positions.
- Vault assets: mint WWXRP subject to that token's vault allowance; distribute the AFKing
  vault tranche subject to its cap/sale lock; transfer/restyle eligible vault seats;
  claim vault sDGNRS redemptions; sweep foreign tokens/NFTs within token restrictions.
  stETH backing is explicitly protected from the foreign-token sweep. Share redemption
  still requires burning the relevant held shares; no unrestricted owner ETH withdrawal.
- Game controls: set lootbox RNG threshold and midday basefee ceiling; declare future
  Thanos scaling subject to the six-level notice, exponent cap, projected-entry floor
  and lock rules; stake surplus game ETH into stETH while preserving player ETH claims.
- Admin liquidity/governance: exchange one's supplied ETH for equal-amount game stETH;
  propose VRF recovery after the 44-hour stall and feed recovery after the two-day stall.
  Proposals still follow voting, threshold and recovery-cancellation rules; owner status
  does not grant an immediate unilateral coordinator/feed swap. Retry cancellation of
  retired VRF subscriptions, with recovered LINK following prescribed destinations.
- Other owner roles: change permitted charity slots (first three lock after first fill),
  assist holder redemptions and reclaim residual charity backing after its long delay;
  claim level-vested DGNRS and unwrap one's DGNRS into recipient sDGNRS under the existing
  restrictions; select deity/AFKing/record renderers and available color controls.
- Separate CREATOR role: Icons32Data path/symbol setters and finalization use the pinned
  CREATOR address, not DGVE majority. Its setters stop permanently after finalization.

## Validation and space

95 tests passed, zero failed/skipped, across nine suites: comp accounting, real FLIP lane,
vault grant/rollback, pass behavior, dice-engine parity, size/gas, keeper gas and the
real-wiring conservation invariants. The parity test covers 400 deterministic engine
inputs. Source gates for caller-independent drains and bounded queue release passed.
26 available artifact storage layouts matched current goldens. `git diff --check` passed.
Logs: `audit/comp-working-tree-2026-09-05/targeted-tests.log` (local, ignored).

| Runtime | Bytes | Margin below 24,576 |
| --- | ---: | ---: |
| CrapsBattle | 23,187 | 1,389 |
| CrapsEngine | 3,973 | 20,603 |
| FLIP | 8,636 | 15,940 |
| DegenerusVault | 10,699 | 13,877 |

Pinned Solidity 0.8.34, via IR, optimizer 1,000 runs, Osaka, Foundry address configuration.
The engine is appended to deterministic deployment order, preserving prior addresses.
Its STATICCALL adds a per-seat boundary; relevant gas tests passed. No payout delegatecall
module or shared-storage refactor was introduced. Remeasure deployment-specific builds;
this pass did not run the whole Hardhat suite or update the off-chain applications.
