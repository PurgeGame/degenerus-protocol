# DGVE owner approval

[`DegenerusOwnerGovernance`](../contracts/DegenerusOwnerGovernance.sol) executes the owner controls listed under [Allowed actions](#allowed-actions-and-callbacks) when settled approval exceeds **50.1% of the current DGVE supply**. A holder with all the shares uses the same route as several heirs acting together. `Vault.isVaultOwner` recognizes only this fixed executor; a wallet's balance does not grant direct administrative access.

Each owner has one escrow position. Tokens remain transferable and redeemable outside escrow. Depositing grants no additional claim on Vault reserves, and sending tokens directly to governance creates no position or votes. There is no recovery function for unsolicited tokens or ETH.

## Approving an action

1. Approve governance to transfer the chosen DGVE amount.
2. Call `propose(owner, target, value, data, amount)`. A positive amount deposits the caller's tokens and commits them to this action. Other owners use `support(owner, proposalId, amount)` to add their separate positions.
3. Support counts automatically from the next block. Support assigned in the current block never counts, even in a separate transaction.
4. Anyone can call `execute(proposalId, data)` for an unexpired proposal whose settled weight exceeds 50.1% of live supply. The caller supplies exactly its approved ETH value. The executor calls the approved target once with calldata whose hash matches the proposal.
5. Owners withdraw their positions individually. They can also withdraw before execution, after expiry, or after a failed action. No vote can prevent withdrawal.

Proposals expire after seven days. Exactly 50.1% does not pass. Redemptions change the live denominator; idle deposits and direct donations still remain in that denominator without approving any action. A failed target call rolls the whole execution back, allowing retry or withdrawal.

Positions cannot be partially withdrawn or topped up. `clearVote(owner)` removes support while leaving idle custody. Reassigning the position excludes it for the new assignment block, even if the tokens have long been escrowed. Withdrawal clears custody and any assignment; the stored delegate has no effect while the amount is zero, and a later deposit replaces it. No function enumerates voters.

## Voting delegation

`deposit(amount, delegate)` creates an idle position, with zero meaning no delegate. `setVotingDelegate(delegate)` changes or revokes the delegate and clears all existing approval atomically. Only the depositor can change the delegate.

A delegate may call `propose(owner, ..., 0)`, `support(owner, proposalId, 0)`, or `clearVote(owner)`. These use only the owner's existing escrow. Positive deposit amounts require the owner as caller, even if governance has an unused token allowance. Delegates cannot withdraw, transfer or redeem the tokens, change their destination, appoint another delegate, or acquire the owner's personal gameplay permissions. One delegate can represent several owners without merging their positions.

Delegation is full voting trust over the allocated amount. Anyone controlling enough ownership or delegated votes can approve an action. The next-block rule prevents atomic borrowing from supplying votes. It does not provide a human review window or prevent loans held across blocks.

## Direct Vault gameplay

A holder or delegate controlling more than 50.1% of supply in existing escrow can call `directAction(data, owners)` without a proposal. Each listed position must belong to the caller or currently delegate to them. The list must use strictly increasing addresses, and only deposits from earlier blocks count. Withdrawal and redeposit reset this block boundary; assigning existing escrow to a proposal does not.

The function calls only the Vault, with calldata selecting `playerAction` or `spendDegenesis`. `playerAction` enforces its own target/selector allowlist ([Vault player actions](VAULT_PLAYER_ACTIONS.md)); `spendDegenesis(recipientId, whalePass, quantity, boxOrder, maxCost)` buys for any allocated account using the restricted budget; recipient 0 selects the Vault. Recipient approval is not required. Normal rewards and boons apply, but the spend adds no DeGenesis credit. All admin actions, including comp allowances, mints and sweeps, still need proposals. Independent holders without a common controller use proposals for gameplay too. Voting delegation grants no access to a holder's personal player account; a majority of delegated positions does authorize this Vault gameplay route.

Direct gameplay changes no governance storage. It forwards the caller's `msg.value`, which `DirectAction` logs with the caller and Vault selector. For `playerAction`, the encoded `ethValue` argument specifies additional Vault reserves. The owner list is supplied by the caller; governance never enumerates all depositors.

## Allowed actions and callbacks

`contracts/libraries/OwnerActions.sol` fixes the allowed target and selector pairs. It covers selectors on the Vault, Admin, Game, WWXRP, Craps, GNRUS, Icons32Data, DeityPass, RecordBounty and AFKing subscription token contracts. Each target enforces its own limits, and Vault `playerAction` enforces its nested allowlist. Governance cannot call itself or the DGVE token, redeem escrow, make arbitrary calls or use `delegatecall`.

The executor has no reentrancy lock or OpenZeppelin helpers. It calls the fixed, non-upgradeable DGVE implementation, whose transfers have no hooks and return a checked boolean. Custody accounting is committed before transfers, and proposals are marked executed before calling the target. An authorized callback may clear or withdraw its own position, but cannot replay execution, withdraw twice, or count reassigned support in its assignment block. A later revert rolls those callback changes back too. Tests exercise both rejected and permitted callbacks.

Positions occupy two storage slots and proposals occupy four. Each proposal stores a calldata hash; its `ProposalCreated` event carries the full calldata and domain-separated action hash. Execution requires those exact bytes. The ETH value is bounded by `uint96`, and DGVE's maximum supply of `1e30` fits the `uint128` position and weight fields. Block numbers occupy packed `uint40` fields. No activation transaction or global voter enumeration is required. The threshold uses quotient/remainder arithmetic, avoiding multiplication overflow without a general-purpose math library.

`DegenerusAdmin.propose` called by the executor (the admin VRF-coordinator-swap path) uses reserved proposer identity 1 and needs no Game wallet registration. Community sDGNRS proposal and voting rules stay separate. `Admin.swapGameEthForStEth(recipient)` includes the recipient in the approved calldata; zero and the executor itself are rejected.

## Initial icons and deployment

The creator can upload each of the 33 paths and three name quadrants once without DGVE or proposals. Empty entries, duplicate initialization and invalid batches revert. Completion permanently closes this permission. A successful governance write or finalization also closes it, even during partial setup.

`Icons32Data(bool finalizeOnBootstrap)` fixes whether completion also finalizes all artwork. `ICONS32_FINALIZE=1` selects this behavior before deployment. Otherwise, later edits or finalization require governance. The creator cannot reopen setup or directly finalize later.

`wireIcons32` verifies previously written entries before resuming, uploads missing entries, and checks the entire canonical dataset afterward. A fresh setup uses seven upload transactions. Repeating completed setup submits none. A mismatch requires an approved correction; it is never silently overwritten.

The executor is the final deployment in each profile: nonce `N+36` in the eip170 profile and `N+20` in the glamsterdam profile, where `N` is the first deployment's nonce. Earlier contract addresses follow the deployer's CREATE nonces in profile order; the Vault's constructor creates the DGVF and DGVE tokens from the Vault's own nonce.

## CLI

Compile first. `scripts/owner-governance.js` reads `RPC_URL` (or `--rpc`; default `http://127.0.0.1:8545`) and `OWNER_GOVERNANCE_ADDRESS` (or `--governance`); write commands additionally use `PRIVATE_KEY`. Token amounts and ETH values are integer base units. Keep signing keys out of shell command arguments.

```sh
node scripts/owner-governance.js inspect --owner "$OWNER" --proposal 1
node scripts/owner-governance.js approve --amount "$AMOUNT"
node scripts/owner-governance.js deposit --amount "$AMOUNT" --delegate "$DELEGATE"
node scripts/owner-governance.js propose --owner "$OWNER" --target "$TARGET" --data "$CALLDATA" --amount 0 --value 0
node scripts/owner-governance.js support --owner "$OWNER" --proposal 1 --amount 0
node scripts/owner-governance.js execute --proposal 1
node scripts/owner-governance.js clear --owner "$OWNER"
node scripts/owner-governance.js set-delegate --delegate 0x0000000000000000000000000000000000000000
node scripts/owner-governance.js withdraw
node scripts/owner-governance.js direct --data "$VAULT_CALLDATA" --value 0
node scripts/owner-governance.js direct --data "$VAULT_CALLDATA" --owners "$OWNER1,$OWNER2" --value 0
```

`inspect` retrieves the transaction from its `ProposalCreated` log through `eth_getLogs`, verifies it against the stored hash, and shows approval totals, position, delegate, settled approval and current-block support. Execution uses the verified event calldata, reads the stored ETH value and forwards that exact amount from its caller. The target's timing and other conditions can still make an approved action revert.

`direct` (also accepted as `direct-action`) discovers the caller's delegated positions from deposit and delegate-change logs, includes their own position, checks current control, and sorts the owners. Revoked and withdrawn positions are excluded. `--from-block` can start discovery at the governance deployment block to reduce log queries. Explicit `--owners` skips discovery; duplicates and uncontrolled positions reject before submission. `--data` must encode the Vault's `playerAction` or `spendDegenesis`; `--value` funds the call from the signer. The contract rechecks current control, deposit blocks and the live threshold.
