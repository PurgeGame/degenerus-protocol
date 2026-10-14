# Account loans

`Game.borrow(id, dueLevel, minEthOut)` lends ETH against the selected account's far-future tickets. The lender is sDGNRS, or the Vault when sDGNRS cannot fund the principal and the Vault owner has enabled fallback. Only the current owner can borrow. Protocol roots, already-acquired accounts and accounts with an open loan are excluded. Borrowing works during the RNG lock: the quote reads no randomness, nothing changes hands at borrowing, and a new loan is always due above the level being seized. A main account with more than five lifetime smurfs cannot borrow; smurfs can borrow whatever their family's size.

The borrower picks the due level X, from the next level up to the level that keeps X + 2 within 100 levels of the active ticket level. The principal values only whole tickets at levels X + 2 and above, which are still far-future buckets when the game enters X:

| Levels ahead (d) | Share of face |
|---|---|
| 2 | 10% |
| 2 → 20 | linear, 10% → 5% |
| 20 → 100 | linear, 5% → 2% |

`rate(d) = 1000 − (d − 2)·500/18` bps for d ≤ 20, else `500 − (d − 20)·300/80`. The quote has no randomness. The principal must be at least 0.05 ETH, and the ETH part at least `minEthOut`. Printed tickets and children contribute nothing. Payment is ETH, with stETH covering any shortfall in the Game's ETH balance; a failed payment reverts the whole borrow.

A loan taken in the purchase phase more than 20 days after it began (`purchaseStartDay`; credited stall days do not count) pays half its principal, rounded down to whole tickets, as tickets at the live ticket level instead of ETH. Those tickets are priced at that level and pooled like a ticket buy (90% next pool, 10% future pool), with no affiliate, quest or activity credit. The loan's principal, interest and repayment are unchanged: the borrower owes on the whole amount. Jackpot-phase loans are always all ETH. The borrower keeps the account, its balances and its play while the loan is open, except that a main with an open loan cannot create smurfs.

## Repayment

`Game.repay(id)` is payable and owner-only, and works while the game's level is below X, including during the RNG lock. With T = X − (level at borrowing) and c = max(1, levels elapsed):

`owed = principal × (1 + 5%·c + 1%·(T − c))`, which equals `principal × (100 + T + 4c) / 100`.

The amount owed goes to the lender's game claimable. `msg.value` pays first; the account's own claimable covers any shortfall, always leaving its 1-wei sentinel; ETH beyond the amount owed is credited to the account's AFKing balance.

## Seizure

The daily request that enters level X arms the settlement of every unpaid loan due at X. The mining engine runs it next, ahead of the wait for the VRF word and every consumer of it (`MinerAction.SeizeLoans`), in bounded chunks that resume from a cursor.

First, automatic repayment. If the borrowing account's own claimable (above its 1-wei sentinel) plus its prepaid AFKing funding covers the full-term amount `principal × (1 + 5%·T)`, that amount moves to the lender's claimable, claimable first and then AFKing. The loan closes with `LoanRepaid` (payer = the account's payee), and the borrower keeps everything else. Only that account's slot counts, never its main's or siblings'. A borrower who prefers to default withdraws before X. An account already acquired by a lender (a smurf whose main was seized) is never auto-repaid.

Otherwise the account is seized. Each seizure is the old sale:

- The lender takes the account. A main takes its existing children, which keep their tickets and records. A child seized on its own earlier keeps its own lender.
- For a main, the borrower wallet's entire native sDGNRS balance is burned for no payout, and the wallet's default gameplay ID is cleared. Redeem before the due level to keep redemption value. Already-submitted redemption claims stay with the account.
- The seized account's AFKing run stops, and for a main every smurf's run. Already-paid box stamps still open, with rewards going to the lender.
- A deity account's soulbound pass moves with it to the lender (a family holds at most one deity). The lender cannot smite or issue boons with it; the account's perpetual tickets, symbol draws and any early-game-over refund now accrue to the lender.
- Claimable ETH, prepaid AFKing funding and unclaimed rewards stay with the seized ID for the lender to collect.

Main and smurf loans are independent. If a main is seized while its smurf's own loan is open, nobody can repay that loan any more, and the smurf is seized to its own lender at its own due level.

Terminal handling outranks seizure: at liveness or game over, unpaid loans are never seized, and the borrower keeps both the principal and the account.

## Integration

- `Lens.previewBorrow(game, id, dueLevel)` returns account, lender ID, eligibility (every gate but the caller's ownership), face value, principal and `ticketWei`, the part of the principal a borrow now would pay as tickets. `Lens.loanOf(game, id)` returns the open loan and the amount owed at the current level. `Lens.loansDue(game, X)` lists the accounts due at X, in settlement order; once the game has entered X the list is history.
- Events: `LoanTaken(accountId, borrower, lenderId, principal, dueLevel, ticketWei)` (`ticketWei` = the part paid as tickets) and `LoanRepaid(accountId, payer, owed)` from the Mint module (a manual repayment) or the Advance module (an automatic one at X); `LoanSeized(accountId, lenderId)` from the Advance module. A deity seizure also emits the pass's `Transfer`.
- `walletIdOf(address)` returns the current default gameplay ID; a main seizure clears it and later gameplay can register a replacement. `walletIdentityOf(address)` is permanent and does not reset.
- `resolveAccount(id, caller)` resolves current payee and authorization. Raw wallet-table keys are historical metadata on acquired roots, not spending authority. `Lens.walletOfId` returns the current payee.
- `acquiredBuyer(id)` returns the lender that seized the account (zero if not acquired). Child ownership follows at most two links.
- `sweepAccounts(ids)` accepts at most 32 subaccount IDs (smurfs or acquired accounts, never a main) and pays each one's current owner. sDGNRS-owned IDs are permissionless; anything else needs the current payee or an operator approved for that ID. The Vault sweeps through `Vault.gameSweepAccounts(ids)`. It moves available claimable ETH (keeping the 1-wei sentinel) into the owner's main game balance without changing `claimablePool`. Acquired accounts, and every account after game over, also move their prepaid funding. Settled FLIP goes to the payee. Acquired accounts also give up their auto-rebuy carry once caught up and unfrozen. Collection stays available for later awards; ordinary prize resolution never traverses the family. Unclaimed prizes (bingo, foil, whale pass, AFKing FLIP and so on) have permissionless claims that credit the account, after which a sweep collects them.
- Swept ETH becomes usable in the existing buyer paths: sDGNRS counts its main game claimable as redemption backing; the Vault can withdraw through `gameClaimWinnings`, and DGVE burns can pull the balance automatically. The final game-over sweep deadline still applies.
- `WWXRP.withdrawAcquired(id)` fixes the recipient to the buyer. Swept FLIP follows protocol-receiver handling: sDGNRS's stakes onto its next flip as backing, and the Vault's becomes its mint allowance. sDGNRS pool rewards earned by sDGNRS-owned accounts burn automatically.
- `Vault.setLiquidationBuyFallback(enabled, floorWei)` controls future Vault lending. sDGNRS retains 1 ETH of game claimable; the Vault keeps its configured floor across claimable and prepaid funding.

## Redemptions

Each new live redemption, including a top-up, must have at least 0.01 ETH of free-backing value using supply plus open-batch escrow. Accepted claims are never subjected to the admission minimum again.

## Storage

- `_loans` (slot 80): one word per account — principal, lender, start level, due level, list index, family size.
- `_loansDue` (slot 81) and `_loansDueCount` (slot 82): each due level's account IDs, eight per word, and its open count. Repayment swaps the last ID into the freed lane.
- `loanSeizeCursor`: slot 5, bytes 16–19. The pending flag is bit 2 of `decimatorFlags` in slot 0, which the engine's selector already reads.

No existing slot moves.

## Verification

`test/fuzz/AccountLoans.t.sol` covers valuation, gates, repayment, lenders, payout and the ported sale behaviours through borrow-then-default. `test/fuzz/LoanSeizure.t.sol` drives real level transitions, chunked seizure, automatic repayment, terminal precedence and deity passes. `test/gas/LoanSeizureGas.t.sol` measures the cold per-loan seizure and automatic-repayment costs against their admission bound.
