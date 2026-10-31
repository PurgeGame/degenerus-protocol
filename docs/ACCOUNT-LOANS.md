# Account loans

`Game.borrow(id, dueLevel, amount, minEthOut)` credits prepaid AFKing funding against the selected
account's far-future
tickets. The lender is sDGNRS, or the Vault when sDGNRS cannot fund the principal and the Vault
owner has enabled fallback. Only the current owner can borrow. Protocol roots, already-acquired
accounts and accounts with an open loan are excluded, and borrowing closes once the game-over
deadline, deadman or VRF failure fires. Borrowing works during the RNG lock: the quote reads no
randomness, the account and its collateral tickets stay with the borrower (the non-ticket principal
is
credited, with any ticket part queued like a purchase), and a new loan is always due above the level
being settled. A main account with more than five lifetime smurfs cannot borrow; smurfs can borrow
whatever their family's size.

New loans close at exactly 48 hours after the last completed daily session, whether the delay is
VRF or unfinished processing, and reopen when another day completes. Receiving a VRF word or
starting a request alone does not reset this clock. The gate stays closed through the 14-day
hard-stall ending. Manual repayment and due-level settlement are unaffected. Before the first
completion, the clock starts at deployment (including level 0/Degenesis), so an uninitialized
zero timestamp cannot prematurely block launch-phase borrowing.

The borrower picks the due level X, from the next level up to the level that keeps X + 2 within 100
levels of the active ticket level (`LOAN_HORIZON_LEVELS`). The active ticket level is at most the
current level + 1, so every open loan is due within 99 levels of the current level. The principal
values only whole tickets at levels X + 2 and above, which are still far-future buckets when the
game enters X:

| Levels ahead (d = ticket level − active ticket level) | Share of face |
|---|---|
| 2 | 10% |
| 2 → 20 | linear, 10% → 5% |
| 20 → 100 | linear, 5% → 2% |

`rate(d) = 1000 − (d − 2)·500/18` bps for d ≤ 20, else `500 − (d − 20)·300/80`. The quote has no
randomness. The borrower takes any part of it: the principal is the quote capped at `amount` (pass
`type(uint256).max` for all of it). The account is the collateral whatever was drawn, so a partial
loan that defaults is seized like a full one. The principal must be at least 0.05 ETH, and the
AFKing
credit at least `minEthOut` (the ABI name is retained). Only the account's own queued far-future
entries count; created tickets
and its children's entries contribute nothing. The non-ticket principal credits the borrowing
account's AFKing balance; no ETH or stETH leaves
the Game. The owner can withdraw it through `withdrawAfkingFunding`, which pays ETH with stETH
fallback. Unspent credit remains available for purchases and automatic loan repayment.

A loan taken in the purchase phase more than 20 days after it began (`purchaseStartDay`, counted in
game days) pays half its principal, rounded down to whole tickets, as tickets at the live ticket
level instead of AFKing credit. Those tickets are priced at that level and pooled like a ticket buy
(90% next pool, 10% future pool), with no affiliate, quest or activity credit. The loan's
principal, interest and repayment are unchanged: the borrower owes on the whole amount.
Jackpot-phase loans are always all AFKing credit. The borrower keeps the account, its balances and
its play while the loan is open, except that a main with an open loan cannot create smurfs.

## Manual repayment

`Game.clearDebtNow(id)` is payable and owner-only, and works while the game's level is below X and
the game is not over, including during the RNG lock and while a game-over settlement is running.
With T = X − (level at borrowing) and c = max(1, levels elapsed):

`owed = principal × (1 + 5%·c + 1%·(T − c))`, which equals `principal × (100 + T + 4c) / 100`.

The amount owed goes to the lender's game claimable. `msg.value` pays first; the account's own
claimable covers any shortfall, always leaving its 1-wei sentinel; ETH beyond the amount owed is
credited to the account's AFKing balance.

## Settlement at the due level

The daily request that enters level X arms the settlement of every unpaid loan due at X. The mining
engine (`mineRun`) runs it next, ahead of the wait for the VRF word and every consumer of it
(`MinerAction.SeizeLoans`), in bounded chunks that resume from a cursor. Each loan settles one of
two ways.

**Automatic repayment.** If the borrowing account's own claimable (above its 1-wei sentinel) plus
its prepaid AFKing funding covers the full-term amount `principal × (1 + 5%·T)` (the
manual-repayment formula with every level used), that amount moves to the lender's claimable,
claimable first and then AFKing. The loan closes with `LoanRepaid` (payer = the account's payee),
and the borrower keeps everything else. Only that account's slot counts, never its main's or
siblings'. Unspent principal credited at borrowing counts toward this automatic repayment;
interest still needs additional funds. A borrower who prefers to default withdraws before X.
An account already acquired by a lender (a smurf whose main was seized) is never auto-repaid.

**Seizure.** Otherwise the lender takes the account:

- A main takes its existing children, which keep their tickets and records. A child seized on its
  own earlier keeps its own lender.
- For a main, the borrower wallet's entire native sDGNRS balance is burned for no payout, and the
  wallet's default gameplay ID is cleared. Redemption proceeds must be withdrawn before seizure
  to keep them outside the seized account. Already-submitted redemption claims stay with the account.
- The seized account's AFKing run stops, and for a main every smurf's run. Already-paid box stamps
  still open, with rewards going to the lender.
- A deity account's soulbound pass moves with it to the lender (a family holds at most one deity).
  The Vault can smite or issue boons with an acquired pass through `playerAction`; the account's
  perpetual tickets, symbol draws and any early-game-over refund accrue to the lender.
- Claimable ETH, prepaid AFKing funding and unclaimed rewards stay with the seized ID for the lender
  to collect.

Main and smurf loans are independent. If a main is seized while its smurf's own loan is open, the
former borrower can no longer repay that loan, and the smurf is seized to its own lender at its own
due level.

## Settlement at game over

When the game-over decision is made, the ending is classified as a purchase timeout or a hard stall
(`_endingReason()`), in the same transaction that latches the ending:

- **Purchase timeout** (in the purchase phase before its final-day seal, with 30 completed game days
  since the level's purchase start, the wall day past the last completed day, and the next pool not
  above the next level's target): every outstanding loan settles before the ending's terminal RNG
  request, by the rules above with one difference: automatic repayment charges what a manual
  repayment would cost at the current level (the formula under "Manual repayment", also
  `Lens.loanOf(...).owed`), not the full term. A loan due at the current level costs its full term,
  as it would at its due level. The level just entered first finishes its pending batch from its
  cursor; then each later due level is settled in ascending order, in list order within a level, up
  to the current level + 99. The deciding call only records the decision. Settlement then runs alone
  in the following calls (`Advance` stage 20 per checkpoint). The terminal request, deity refunds,
  `gameOver`, terminal burns and terminal awards all come after it, so a seized account's terminal
  awards belong to its lender. A coordinator refusal or missing word only changes which payout path
  runs. A hard stall that begins after the decision ends the settlement: loans already settled stay
  settled, the remaining loans are left as they stand, and the deterministic fallback pays the
  settled owners. A zero terminal pot still settles every loan.
- **Hard stall** (an active VRF request still unpublished 14 days after its request time, an expired
  refused terminal-request timer, or no daily session completed for 14 days): loans are left as they
  stand, and the borrower keeps both the principal and the account. Nothing settles them later.

Settlement must not block the ending. Borrowing closes when liveness fires and the level stops
moving, so the work is fixed and finite. Each loan touches only its own record, its family (at most
six accounts), the 32-entry deity registry and fixed protocol contracts, with no borrower-controlled
call and no ETH payout. Each step below carries a no-revert obligation; the right column is the
implementation's basis for it, to be verified against the source:

| Step | Basis for the no-revert obligation |
|---|---|
| Unused levels `due − start − used` | `used` is at most `level − start` (or 1), and no loan being settled is due below the current level, while borrowing requires the due level to exceed the start level. |
| Owed amount | A 96-bit principal times at most 59,500 bps (every level used, 99 levels), in 256-bit arithmetic. |
| Borrower debit | Both legs are checked against the balances before either is written; a shortfall seizes instead. |
| Lender credit | The lender is sDGNRS or the Vault (never ID 0). |
| `sDGNRS.burnForLiquidation` | Game-only, no liveness gate, a zero balance returns early, and supply always covers a holder's balance. |
| Ownership write | A raw slot write; protocol roots never borrow. |
| AFKing stop and `Quests.finalizeAfking` | Finalize is idempotent and only writes the handback: the streak saturates at uint16, the century-shield grant is capped and guarded, and the anchor is the reward endpoint. |
| `DeityPass.seize` | Passes are soulbound and never burned, so a registered symbol always has an owner; the receiver is sDGNRS or the Vault. |

The intended only failure is gas: a starved call reverts whole and leaves every loan and cursor as
it was, and the first unit of every call is always admitted, so a call with enough gas always makes
progress. Manual repayment during settlement removes only an unsettled entry, and the entry it swaps
into the freed lane is unsettled too, so the cursor never passes an open loan.

## Integration

- `Lens.previewBorrow(game, id, dueLevel, amount)` returns account, lender ID, eligibility
  (excluding the caller's ownership and `minEthOut` check), face value, `maxPrincipal` (the full
  quote), `principal` (the quote capped at `amount`) and `ticketWei`, the part of `principal` a
  borrow now would pay as tickets; `principal - ticketWei` is the AFKing credit. `Lens.loanOf(game,
  id)` returns the open loan and `owed`, the
  repayment price at the current level while it is below the due level (otherwise `owed` is zero); a
  purchase-timeout game over uses this price for loans not yet due and the full term for loans due
  now (`clearDebtNow`, auto-repayment and the Lens share `_loanOwedAt`). `Lens.loansDue(game, X)`
  lists the accounts due at X, in settlement order. Once that level's batch has finished settling,
  or a purchase-timeout game over has finished settling all loans, the list is history.
- Events: `LoanTaken(accountId, borrower, lenderId, principal, dueLevel, ticketWei)` (`ticketWei` =
  the part paid as tickets, the rest credited to AFKing) and `LoanRepaid(accountId, payer, owed)`
  from the Purchase module (a
  manual repayment) or the Advance module (an automatic one); `LoanSeized(accountId, lenderId)` from
  the GameOver module (`seizeLoan`, reached by delegatecall from the Advance module). A deity
  seizure also emits the pass's `Transfer`. Game-over settlement emits `Advance(20, level)` for each
  checkpoint that made progress.
- `walletIdOf_g3120(address)` returns the current default gameplay ID; a main seizure clears it and
  later gameplay can register a replacement. `walletIdentityOf_g8516(address)` is permanent and does
  not reset.
- `resolveAccount_g7029(id, caller)` returns the key, the current payee and whether `caller` is
  authorized. Raw wallet-table keys are historical metadata on acquired roots, not spending
  authority. `Lens.walletOfId` returns the current payee.
- `acquiredBuyer(id)` returns the lender that seized the account (zero if not acquired). Child
  ownership follows at most two links.
- `sweepAccounts(ids)` accepts at most 32 subaccount IDs (smurfs or acquired accounts, never a main)
  and pays each one's current owner. sDGNRS-owned IDs are permissionless; anything else needs the
  current payee or an operator approved for that ID. The Vault sweeps through `Vault.playerAction`
  calling `Game.sweepAccounts`. It moves available claimable ETH (keeping the 1-wei sentinel) into
  the owner's main game balance without changing `claimablePool`. Acquired accounts, and every
  account after game over, also move their prepaid funding. Settled FLIP goes to the payee. Acquired
  accounts also give up their auto-rebuy carry once caught up and unfrozen. Collection stays
  available for later awards, including terminal awards, until the final sweep; ordinary prize
  resolution never traverses the family. Permissionless prize claims retain their own eligibility
  and expiry rules; AFKing FLIP and whale-pass claims close at liveness. A sweep collects resulting
  ETH and FLIP credits, not tickets or tokens already delivered to the payee.
- Swept ETH is usable by the lenders: sDGNRS counts its main game claimable as redemption backing;
  the Vault can withdraw through `Vault.playerAction` calling `Game.claimClaimable` or
  `Game.claimWinnings`, and DGVE burns (`burnEth`) pull the balance automatically. The final
  game-over sweep deadline still applies.
- `WWXRP.withdrawAcquired(id)` fixes the recipient to the buyer. Swept FLIP follows
  protocol-receiver handling: sDGNRS's stakes onto its next flip as backing, and the Vault's becomes
  its mint allowance. sDGNRS pool rewards earned by sDGNRS-owned accounts burn automatically.
- `Vault.setLiquidationBuyFallback(enabled, floorWei)` controls future Vault lending. sDGNRS retains
  1 ETH of game claimable; the Vault keeps its configured floor across claimable and prepaid
  funding.

## Redemptions

Each new live redemption, including a top-up, must have at least 0.01 ETH of free-backing value
using supply plus open-batch escrow. Accepted claims are never subjected to the admission minimum
again.

## Storage

- `_loans` (slot 63): one word per account: principal (bits 0–95), lender ID (96–103), level at
  borrowing (104–127), due level (128–151), list index (152–183), family size (184–191). A closed
  loan is rewritten to bit 255 alone, so principal 0 means no open loan.
- `_loansDue` (slot 64) and `_loansDueCount` (slot 65): each due level's account IDs, eight per
  word, and its count. Repayment swaps the last ID into the freed lane; settlement deletes the loan
  and leaves the list behind as history.
- `loanSeizeCursor`: slot 4, bytes 16–19. The pending flag is bit 2 of `decimatorFlags` in slot 0,
  which the engine's selector reads.
- Game-over settlement: bits 64–71 of `gameOverStatePacked` (slot 14) hold the level offset being
  settled (0 = none owed or finished) and bits 72–103 the next index in that level's list.

## Verification

- `test/fuzz/AccountLoans.t.sol` covers valuation, partial amounts, gates, repayment, lenders,
  AFKing credit, withdrawal and the seizure behaviours through borrow-then-default.
- `test/fuzz/LoanSeizure.t.sol` drives real level transitions, chunked seizure, automatic repayment
  and deity passes.
- `test/fuzz/TerminalLoanSettlement.t.sol` drives real endings: a deadline ending settling a mixed
  book (repayment at the current price, below the full term; one wei short; a five-smurf family with
  a deity pass, a main seized before its smurf's own loan, a loan due at the horizon) before its
  terminal request, then the payout and the final sweep; chunked settlement around manual
  repayments; a hard stall at the decision leaving loans as they stand; an older request dying, or
  its word landing, mid-settlement; an empty book; a deadman landing on a part-settled pending
  batch; and a fuzzed book checked against an independent ledger.
- `test/gas/LoanSeizureGas.t.sol` measures the cold per-loan seizure and automatic-repayment costs
  against their admission bound, and the cold game-over checkpoint (the worst family, six live
  AFKing runs and a deity pass, plus the full 99-level scan) through the full `mineRun` stack.
