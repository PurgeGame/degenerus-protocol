# Account loans

`Game.borrow(id, dueLevel, amount, minEthOut)` lends ETH against the selected account's far-future tickets. The lender is sDGNRS, or the Vault when sDGNRS cannot fund the principal and the Vault owner has enabled fallback. Only the current owner can borrow. Protocol roots, already-acquired accounts and accounts with an open loan are excluded, and borrowing closes once the game-over deadline, deadman or VRF failure fires. Borrowing works during the RNG lock: the quote reads no randomness, nothing changes hands at borrowing, and a new loan is always due above the level being settled. A main account with more than five lifetime smurfs cannot borrow; smurfs can borrow whatever their family's size.

The borrower picks the due level X, from the next level up to the level that keeps X + 2 within 100 levels of the active ticket level (`LOAN_HORIZON_LEVELS`). The active ticket level is at most the current level + 1, so every open loan is due within 99 levels of the current level. The principal values only whole tickets at levels X + 2 and above, which are still far-future buckets when the game enters X:

| Levels ahead (d) | Share of face |
|---|---|
| 2 | 10% |
| 2 → 20 | linear, 10% → 5% |
| 20 → 100 | linear, 5% → 2% |

`rate(d) = 1000 − (d − 2)·500/18` bps for d ≤ 20, else `500 − (d − 20)·300/80`. The quote has no randomness. The borrower takes any part of it: the principal is the quote capped at `amount` (pass `type(uint256).max` for all of it). The account is the collateral whatever was drawn, so a partial loan that defaults is seized like a full one. The principal must be at least 0.05 ETH, and the ETH part at least `minEthOut`. Printed tickets and children contribute nothing. Payment is ETH, with stETH covering any shortfall in the Game's ETH balance; a failed payment reverts the whole borrow.

A loan taken in the purchase phase more than 20 days after it began (`purchaseStartDay`; credited stall days do not count) pays half its principal, rounded down to whole tickets, as tickets at the live ticket level instead of ETH. Those tickets are priced at that level and pooled like a ticket buy (90% next pool, 10% future pool), with no affiliate, quest or activity credit. The loan's principal, interest and repayment are unchanged: the borrower owes on the whole amount. Jackpot-phase loans are always all ETH. The borrower keeps the account, its balances and its play while the loan is open, except that a main with an open loan cannot create smurfs.

## Manual repayment

`Game.repay(id)` is payable and owner-only, and works while the game's level is below X and the game is not over, including during the RNG lock and while a game-over settlement is running. With T = X − (level at borrowing) and c = max(1, levels elapsed):

`owed = principal × (1 + 5%·c + 1%·(T − c))`, which equals `principal × (100 + T + 4c) / 100`.

The amount owed goes to the lender's game claimable. `msg.value` pays first; the account's own claimable covers any shortfall, always leaving its 1-wei sentinel; ETH beyond the amount owed is credited to the account's AFKing balance.

## Settlement at the due level

The daily request that enters level X arms the settlement of every unpaid loan due at X. The mining engine runs it next, ahead of the wait for the VRF word and every consumer of it (`MinerAction.SeizeLoans`), in bounded chunks that resume from a cursor. Each loan settles one of two ways.

**Automatic repayment.** If the borrowing account's own claimable (above its 1-wei sentinel) plus its prepaid AFKing funding covers the full-term amount `principal × (1 + 5%·T)` (the manual-repayment formula with every level used), that amount moves to the lender's claimable, claimable first and then AFKing. The loan closes with `LoanRepaid` (payer = the account's payee), and the borrower keeps everything else. Only that account's slot counts, never its main's or siblings'. A borrower who prefers to default withdraws before X. An account already acquired by a lender (a smurf whose main was seized) is never auto-repaid.

**Seizure.** Otherwise the lender takes the account, exactly as the old sale did:

- A main takes its existing children, which keep their tickets and records. A child seized on its own earlier keeps its own lender.
- For a main, the borrower wallet's entire native sDGNRS balance is burned for no payout, and the wallet's default gameplay ID is cleared. Redeem before the due level to keep redemption value. Already-submitted redemption claims stay with the account.
- The seized account's AFKing run stops, and for a main every smurf's run. Already-paid box stamps still open, with rewards going to the lender.
- A deity account's soulbound pass moves with it to the lender (a family holds at most one deity). The lender cannot smite or issue boons with it; the account's perpetual tickets, symbol draws and any early-game-over refund now accrue to the lender.
- Claimable ETH, prepaid AFKing funding and unclaimed rewards stay with the seized ID for the lender to collect.

Main and smurf loans are independent. If a main is seized while its smurf's own loan is open, nobody can repay that loan any more, and the smurf is seized to its own lender at its own due level.

## Settlement at game over

When the game-over decision is made, the ending records whether VRF was already dead (`_vrfDead()` or the dead-ending latch), in the same transaction that latches the ending:

- **VRF alive** (the insufficient-pool deadline, or the no-progress deadman with VRF working): every outstanding loan settles before the ending's terminal RNG request, by the rules above with one difference: automatic repayment charges what a manual repayment would cost at the current level (the formula under "Manual repayment", also `Lens.loanOf(...).owed`), not the full term. A loan due at the current level costs its full term, as it would at its due level. The level just entered first finishes its pending batch from its cursor; then each later due level is settled in ascending order, in list order within a level, up to the current level + 99. The deciding call only records the decision. Settlement then runs alone in the following calls (`Advance` stage 20 per checkpoint). The terminal request, deity refunds, `gameOver`, terminal burns and terminal awards all come after it, so a seized account's terminal awards belong to its lender. A later VRF timeout, coordinator refusal or missing word only changes which payout path runs: it never skips a remaining loan or reverses a settled one, and the deterministic fallback pays the settled owners. A zero terminal pot still settles every loan.
- **VRF already dead**: loans are left as they stand, and the borrower keeps both the principal and the account. Nothing settles them later.

Settlement cannot block the ending. Borrowing closed when liveness fired and the level no longer moves, so the work is fixed and finite. Each loan touches only its own record, its family (at most six accounts), the 32-entry deity registry and fixed protocol contracts, with no borrower-controlled call and no ETH payout. No step can revert:

| Step | Why it cannot revert |
|---|---|
| Unused levels `due − start − used` | `used` is at most `level − start` (or 1), and no loan being settled is due below the current level, while borrowing requires the due level to exceed the start level. |
| Owed amount | A 96-bit principal times at most 59,500 bps (every level used, 99 levels), in 256-bit arithmetic. |
| Borrower debit | Both legs are checked against the balances before either is written; a shortfall seizes instead. |
| Lender credit | The lender is sDGNRS or the Vault (never ID 0); total ETH is far below 2^128. |
| `sDGNRS.burnForLiquidation` | Game-only, no liveness gate, a zero balance returns early, and supply always covers a holder's balance. |
| Ownership write | A raw slot write; protocol roots never borrow. |
| AFKing stop and `Quests.finalizeAfking` | A run's covered day never precedes its start day, and the Quests arithmetic is guarded. |
| `DeityPass.seize` | Passes are soulbound and never burned, so a registered symbol always has an owner; the receiver is sDGNRS or the Vault. |

Gas is the only failure a call can meet: a starved call reverts whole and leaves every loan and cursor as it was, and the first unit of every call is always admitted, so a call with enough gas always makes progress. The worst unit (a six-account deity family) costs well under 1M gas. Manual repayment during settlement removes only an unsettled entry, and the entry it swaps into the freed lane is unsettled too, so the cursor never passes an open loan.

## Integration

- `Lens.previewBorrow(game, id, dueLevel, amount)` returns account, lender ID, eligibility (every gate but the caller's ownership), face value, `maxPrincipal` (the full quote), `principal` (the quote capped at `amount`) and `ticketWei`, the part of `principal` a borrow now would pay as tickets. `Lens.loanOf(game, id)` returns the open loan and `owed`, the repayment price at the current level; a game over decided with VRF alive auto-repays at exactly this price (`repay`, auto-repayment and the Lens share `_loanOwedAt`). `Lens.loansDue(game, X)` lists the accounts due at X, in settlement order. Once the game has entered X, or a game over with VRF alive has finished settling, the list is history.
- Events: `LoanTaken(accountId, borrower, lenderId, principal, dueLevel, ticketWei)` (`ticketWei` = the part paid as tickets) and `LoanRepaid(accountId, payer, owed)` from the Mint module (a manual repayment) or the Advance module (an automatic one); `LoanSeized(accountId, lenderId)` from the Advance module. A deity seizure also emits the pass's `Transfer`. Game-over settlement emits `Advance(20, level)` for each checkpoint that made progress.
- `walletIdOf(address)` returns the current default gameplay ID; a main seizure clears it and later gameplay can register a replacement. `walletIdentityOf_g8516(address)` is permanent and does not reset.
- `resolveAccount(id, caller)` resolves current payee and authorization. Raw wallet-table keys are historical metadata on acquired roots, not spending authority. `Lens.walletOfId` returns the current payee.
- `acquiredBuyer(id)` returns the lender that seized the account (zero if not acquired). Child ownership follows at most two links.
- `sweepAccounts(ids)` accepts at most 32 subaccount IDs (smurfs or acquired accounts, never a main) and pays each one's current owner. sDGNRS-owned IDs are permissionless; anything else needs the current payee or an operator approved for that ID. The Vault sweeps through `Vault.gameSweepAccounts(ids)`. It moves available claimable ETH (keeping the 1-wei sentinel) into the owner's main game balance without changing `claimablePool`. Acquired accounts, and every account after game over, also move their prepaid funding. Settled FLIP goes to the payee. Acquired accounts also give up their auto-rebuy carry once caught up and unfrozen. Collection stays available for later awards, including terminal awards, until the final sweep; ordinary prize resolution never traverses the family. Unclaimed prizes (bingo, foil, whale pass, AFKing FLIP and so on) have permissionless claims that credit the account, after which a sweep collects them.
- Swept ETH becomes usable in the existing buyer paths: sDGNRS counts its main game claimable as redemption backing; the Vault can withdraw through `gameClaimWinnings`, and DGVE burns can pull the balance automatically. The final game-over sweep deadline still applies.
- `WWXRP.withdrawAcquired(id)` fixes the recipient to the buyer. Swept FLIP follows protocol-receiver handling: sDGNRS's stakes onto its next flip as backing, and the Vault's becomes its mint allowance. sDGNRS pool rewards earned by sDGNRS-owned accounts burn automatically.
- `Vault.setLiquidationBuyFallback(enabled, floorWei)` controls future Vault lending. sDGNRS retains 1 ETH of game claimable; the Vault keeps its configured floor across claimable and prepaid funding.

## Redemptions

Each new live redemption, including a top-up, must have at least 0.01 ETH of free-backing value using supply plus open-batch escrow. Accepted claims are never subjected to the admission minimum again.

## Storage

- `_loans` (slot 80): one word per account: principal, lender, start level, due level, list index, family size.
- `_loansDue` (slot 81) and `_loansDueCount` (slot 82): each due level's account IDs, eight per word, and its count. Repayment swaps the last ID into the freed lane; settlement deletes the loan and leaves the list behind as history.
- `loanSeizeCursor`: slot 5, bytes 16–19. The pending flag is bit 2 of `decimatorFlags` in slot 0, which the engine's selector already reads.
- Game-over settlement: bits 64–71 of `gameOverStatePacked` (slot 17) hold the level offset being settled (0 = none owed or finished) and bits 72–103 the next index in that level's list.

No slot moves.

## Verification

- `test/fuzz/AccountLoans.t.sol` covers valuation, partial amounts, gates, repayment, lenders, payout and the ported sale behaviours through borrow-then-default.
- `test/fuzz/LoanSeizure.t.sol` drives real level transitions, chunked seizure, automatic repayment and deity passes.
- `test/fuzz/TerminalLoanSettlement.t.sol` drives real endings: a deadline ending settling a mixed book (repayment at the current price, below the full term; one wei short; a five-smurf family with a deity pass, a main seized before its smurf's own loan, a loan due at the horizon) before its terminal request, then the payout and the final sweep; chunked settlement around manual repayments; a VRF dead at the decision leaving loans as they stand; an older request dying, or its word landing, mid-settlement; an empty book; a deadman landing on a part-settled pending batch; and a fuzzed book checked against an independent ledger.
- `test/gas/LoanSeizureGas.t.sol` measures the cold per-loan seizure and automatic-repayment costs against their admission bound, and the cold game-over checkpoint (the worst family, six live AFKing runs and a deity pass, plus the full 99-level scan) through the full `mineFlip` stack.
