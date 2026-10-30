// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MineFlipGas} from "../libraries/MineFlipGas.sol";

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/// @title IsDGNRS
/// @notice Interface for the sDGNRS token contract (Game, wrapper and miner calls, plus the
///         player burn and redemption-claim doors)
/// @dev sDGNRS uses 12 decimals and is backed by ETH, stETH, and FLIP reserves with pool-based distribution
interface IsDGNRS {
    /// @notice Game-only liquidation forfeiture: burn the seller's full balance without payout.
    function burnForLiquidation(address seller) external;

    /// @notice sDGNRS reward pools (initial allocations plus ongoing-pool century refills)
    /// @dev Each pool has a dedicated balance for specific distribution purposes
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Degenesis
    }

    /// @notice Deposit stETH to sDGNRS reserves
    /// @dev Called by the game contract to deposit stETH backing
    /// @param amount Amount of stETH to deposit
    function depositSteth(uint256 amount) external;

    /// @notice Get the remaining balance for a specific pool
    /// @param pool Pool identifier to query
    /// @return Remaining token balance in the pool
    function poolBalance(Pool pool) external view returns (uint256);

    /// @notice Transfer sDGNRS from a pool to a recipient
    /// @dev Restricted to the game contract. Game passes the recipient account's payee (an
    ///      ordinary wallet's own address, or a smurf's owner), never a smurf key.
    /// @param pool Pool identifier to transfer from
    /// @param to Recipient address
    /// @param amount Amount of sDGNRS to transfer
    /// @return transferred Amount actually transferred (may be less if pool has insufficient balance)
    function transferFromPool_g106128(Pool pool, address to, uint256 amount) external returns (uint256 transferred);

    /// @notice Recycle a random 25-75% of the century's live burns into Whale/Affiliate/Lootbox/Reward.
    /// @dev GAME-only; called at the transition close after levels 100, 200, etc. No backing moves.
    /// @param rngWord Committed transition word; determines a whole percentage independently of burn size.
    function recycleCentury(uint24 completedLevel, uint256 rngWord) external;

    /// @notice Burn all undistributed pool tokens at game over and permanently close recycling
    function burnAtGameOver() external;

    /// @notice Burn sDGNRS. Post-gameOver: immediate proportional payout. During game: joins the
    ///         open redemption batch (returns 0,0,0); the miner settles it after the batch's word.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH received (0 during active game)
    /// @return stethOut stETH received (0 during active game)
    /// @return flipOut Always 0
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 flipOut);

    /// @notice Claim account `id`'s gambling-burn redemption in batch `batchId` once the game is
    ///         over (live batches settle through the miner).
    /// @dev Authorized: `id == 0` is the caller (ID from Game.walletIdOf); a nonzero
    ///      `id` needs Game `resolveAccount_g7029(id, msg.sender).authorized` (the account's key, a
    ///      smurf's owner, or an approved operator), except an acquired account, which anyone may
    ///      claim. Pays the account's PAYEE directly in ETH/stETH: the rolled share of a resolved
    ///      batch, or the game-over value for the batch still open at game over. No lootbox or
    ///      FLIP leg.
    /// @param id Claimant account (0 = caller).
    /// @param batchId Redemption batch to claim.
    /// @custom:reverts NotResolved If a closed batch has no roll.
    /// @custom:reverts NotGameOver If the game is not over.
    /// @custom:reverts Unauthorized If the caller may not act for `id`.
    /// @custom:reverts E (Game) If `id` is unallocated.
    /// @custom:reverts NoClaim If the account has no entry in the batch.
    function claimRedemption(uint32 id, uint32 batchId) external;

    /// @notice Transfer sDGNRS from the wrapper to a recipient (DGNRS wrapper only)
    /// @param to Recipient address
    /// @param amount Amount to transfer
    function wrapperTransferTo(address to, uint256 amount) external;

    /// @notice Get the sDGNRS token balance for an address
    /// @param account Address to query balance for
    /// @return Token balance of the account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get the total supply of sDGNRS tokens
    /// @return Total number of sDGNRS tokens in circulation
    function totalSupply() external view returns (uint256);

    /// @notice Get the FLIP reserve backing sDGNRS
    /// @dev Claimable coinflip backing plus the auto-rebuy carry
    /// @return Amount of FLIP in reserves
    function flipReserve() external view returns (uint256);

    /// @notice Preview the output from burning sDGNRS tokens
    /// @dev Proportional share of current reserves, net of the redemption reservation. The value
    ///      is paid as ETH, stETH, or a mix chosen at pay time — the two are at par, so it is
    ///      reported as one wei-denominated figure.
    /// @param amount Amount of sDGNRS to simulate burning
    /// @return ethOut Total value that would be returned, in wei (paid as ETH and/or stETH)
    /// @return flipOut FLIP that would be received (0 after game over)
    function previewBurnValue(uint256 amount) external view returns (uint256 ethOut, uint256 flipOut);

    /// @notice Total ETH value reserved for closed gambling-burn batches.
    /// @dev A batch close reserves its MAX payout and the Game moves it out of sDGNRS's claimable
    ///      into its redemption reserve, which stays inside claimablePool until the legs pay it.
    function pendingRedemptionEthValue() external view returns (uint256);

    /// @notice Open/settling batch IDs, settlement cursor and unpriced burned supply.
    /// @dev Nonzero escrowedSupply means the next fresh request must budget a batch close.
    function redemptionBatchState()
        external view returns (uint32 openBatch, uint32 settlingBatch, uint32 cursor, uint256 escrowedSupply);

    /// @notice Close the open redemption batch: price it, take its FLIP escrow and reserve its MAX
    ///         payout. Game only, inside the transaction that sends the next live (daily or
    ///         mid-day) VRF request; the ending's request closes nothing.
    /// @dev An empty batch, or a close while another batch settles, is a no-op.
    /// @param gameClaimable sDGNRS's claimable balance on the Game.
    /// @return pull Value the Game moves from that claimable into its redemption reserve.
    function closeRedemptionBatch_g165517(uint256 gameClaimable) external returns (uint256 pull);

    /// @notice Resolve the settling batch at a flat roll of 100 if its live settlement never started
    ///         (Game only; both endings).
    function resolveTerminalRedemptions() external;

    /// @notice True while a closed batch has unsettled claims (RNG consumer stage 1).
    function redemptionSettlementPending_g153837() external view returns (bool);

    /// @notice Settle the closed batch on `word`, the published word of the current session.
    function runRedemptionWork(uint256 word, uint256 gasAllowance) external returns (MineFlipGas.Result memory);

    /// @notice Burn the caller's wrapped DGNRS for backing through sDGNRS redemption.
    function burnWrapped(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 flipOut);
}
