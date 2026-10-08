# Account liquidation

`Game.liquidateAccount(id, minEthOut)` sells the selected account to sDGNRS, or to the Vault when sDGNRS cannot fund the price and the Vault owner has enabled fallback. Only the current owner can sell. A deity-pass holder cannot sell either their main account or a child. Protocol roots and already-acquired accounts are excluded.

Selling a main account transfers its existing children without rewriting their tickets or records. A child sold separately retains its buyer when its former parent is later sold. Printed tickets and children contribute nothing to the quote. The selected account's eligible unprinted far-future holdings determine the price: the legacy cash value plus 25% of its nominal replacement-ticket value. No replacement tickets or FLIP are issued as the acquisition price.

The seller receives only the quoted price in native ETH. Claimable ETH, unspent own AFKing funding and unclaimed rewards stay with the sold ID, including when selling a main account. Withdraw or claim first to keep them. `minEthOut` protects the price. External funders retain their own money. The entire sale, including the sDGNRS forfeiture, reverts if native payment fails.

**Liquidation destroys the seller wallet’s entire remaining native sDGNRS balance for no payout**, including dust. This creates no redemption claim or new ID association. Redeem before selling to obtain redemption value; already-submitted claims remain attached to their existing account and transfer with it. Wrapped DGNRS is outside this native-balance forfeiture. This rule also applies when selling a standalone child.

Coinflip wagers transfer unchanged. Existing auto-rebuy continues until collection, so its carry can win or lose during that interval. `Coinflip.claimAcquiredCoinflips(id)` runs ordinary bounded settlement, pays the buyer, and banks carry/disables auto-rebuy once caught up and unfrozen. There is no sale-day cutoff or special preview arithmetic.

The normal AFKing worker cancels acquired subscriptions before another purchase and preserves already-paid box stamps. Pending run accrual can be forfeited like an expired subscription; claim it before selling. No eager cleanup runs during liquidation.

## Integration

- `previewLiquidateAccount(id)` returns account/buyer IDs, eligibility, native liquidity, face value, legacy budget, nominal ticket value, and price. Use `eth_call`: the Game dispatcher is not marked `view`. Eligibility and funding are rechecked at execution.
- `walletIdOf(address)` returns the current default gameplay ID. A main sale clears it; later gameplay can register a replacement.
- `walletIdentityOf(address)` returns the permanent identity used for governance and original address-derived affiliate links. A sale does not reset it.
- `resolveAccount(id, caller)` resolves current payee and authorization. Raw wallet-table keys are historical metadata on acquired roots, not spending authority. `Lens.walletOfId` returns the current payee.
- `acquiredBuyer(id)` returns the actual buyer ID (zero if unacquired). Child ownership follows at most two links. No unbounded family walk is used.
- `harvestAcquiredAccounts(buyerId, ids)` accepts at most 32 acquired IDs for buyer 1 (Vault) or 2 (sDGNRS). Anyone can call; the caller receives nothing. It moves available claimable ETH and prepaid funding into the buyer’s main game balance without changing `claimablePool`. Duplicates do not double-pay. This collector makes no token or cleanup calls.
- Collection remains available for later awards to the acquired root or any inherited child. There is no sale-time balance snapshot or one-time completion marker. An off-chain caller supplies the IDs and can sweep them again after more winnings arrive; liquidation and ordinary prize resolution do not traverse the family.
- Swept ETH becomes usable in the existing buyer paths: sDGNRS counts its main game claimable as redemption backing and pulls it to fund redemption reserves; Vault can withdraw through `gameClaimWinnings`, and DGVE burns can pull the balance automatically. The normal final game-over sweep deadline still applies.
- Token collection is separate: `Coinflip.claimAcquiredCoinflips(id)` and `WWXRP.withdrawAcquired(id)` fix the recipient to the buyer. They cannot pay the caller.
- Collected FLIP follows existing protocol-receiver handling: sDGNRS receives tomorrow's flip stake and Vault receives its FLIP mint allowance. It is not left in an unusable ERC20 balance. The hooks also collect awards arriving after an earlier collection disabled auto-rebuy.
- sDGNRS pool rewards earned by sDGNRS-owned accounts burn automatically through the existing self-award branch of `transferFromPool`. This reduces the awarding pool and total supply, without deleting the smurf or burning the other reward pools. No separate reward-burn transaction is necessary.
- Foil, Bingo, BAF, draw and redemption claims needing a level, batch or witness use their separate claim doors. Acquired-account parked and terminal redemption claims can be triggered permissionlessly with the recorded buyer as payee. The collector does not discover every outstanding claim.
- A terminal redemption payable to sDGNRS itself releases its escrow or reserve and retains the assets as free backing, without an ETH transfer to its restricted receiver.
- `Vault.setLiquidationBuyFallback(enabled, floorWei)` controls future fallback purchases. Disabling it does not revoke ownership or block collection. sDGNRS retains 1 ETH of game claimable; the Vault keeps its configured floor across claimable and prepaid funding.

The old partial salvage APIs are removed. Shared Coinflip backing helpers still used by automatic Decimator entry are named `previewFlipBacking`, `previewFlipBackingById` and `consumeFlipBacking`.

## Redemptions

Each new live redemption, including a top-up, must have at least 0.01 ETH of free-backing value using supply plus open-batch escrow. There is no fixed token minimum. Accepted claims are never subjected to the admission minimum again. A lootbox half below 0.01 ETH is still forfeited; existing batch caps, packed entries and game-over deterministic burns are unchanged.

## Deployment and storage

Coinflip's ordinary settlement and previews are unchanged; the acquired-account collection hook is the only new behavior. No module or deployment-order change is needed.

Game slot 77 retains the current gameplay ID and permanent identity. Smurf creation counts and admin bases belong to the main ID: bits 224–239 and 240–255 of its existing mint word. Selling a child never refunds a creation. Selling the main leaves both fields on the sold ID, which cannot create more children because it is acquired. A replacement ID starts with zero count and zero base. Existing storage roots and types do not change. Acquired roots use the existing wallet-table owner lane, preserving half-pass counts and all ticket positions; there is no new acquisition mapping.

## Verification

Integration on top of main's ID-packing changes (`c0fdf0e85`) has 217 passing selected regression tests across 24 suites. Two existing redemption miner-reward assertions still fail; both reproduced on the implementation's starting snapshot. All 37 new liquidation, recurring-collection, value-minimum and AFKing acquisition tests pass, together with the packed-entry and range-award checks. Coverage includes actual sDGNRS reserve funding and Vault withdrawals, repeated later awards to acquired roots and children, and automatic sDGNRS reward burning.

A clean production build passes interface, storage and all ten source checks. All 37 deployment contracts fit the runtime limit; Game has 44 bytes remaining and Coinflip has 1,381. Measured isolated liquidation costs 380,564 gas in the supplied fixture. These are targeted checks, not a complete protocol audit.
