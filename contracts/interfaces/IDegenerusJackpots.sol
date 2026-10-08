// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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

/// @title IDegenerusJackpots
/// @notice Interface for the jackpot distribution contract.
/// @dev Handles BAF (Big Ass Flip) jackpot calculations and payouts.
interface IDegenerusJackpots {
    /// @dev A near-level round retains every sampled wallet ID, including score-check losers.
    struct BafRound {
        uint8 trait;
        uint32[] candidates;
    }

    function bafConsolationOfId(uint32 playerId, uint24 lvl) external view returns (uint256);
    /// @notice Opens a bracket's resolution (today's winning-flip claims route onward).
    function beginBaf() external;

    /// @notice Closes a resolved bracket: clears the board and bumps the epoch.
    function finalizeBaf(uint24 lvl) external;

    /// @notice Head award `slot` (0 top bettor, 1 armed-day depositor draw, 2 word-picked 3rd/4th).
    /// @dev View, pure in the frozen board, the word and the slot. Slot 1 forwards Coinflip's
    ///      `bafDrawWinner(rngWord)` (also a wallet ID).
    /// @param lvl BAF bracket level.
    /// @param rngWord The BAF transition VRF word.
    /// @param slot Head award slot (0, 1 or 2).
    /// @return winnerId The winner's wallet ID, or 0 when the slot is empty (no winner).
    function bafHeadWinner(uint24 lvl, uint256 rngWord, uint8 slot) external view returns (uint32 winnerId);

    /// @notice Best and second-best BAF score of scatter rounds 2 * pair and 2 * pair + 1 of `rounds`.
    /// @dev View. Candidates are the wallet IDs Game's `sampleTraitEntries` and
    ///      `sampleFarFutureTickets` return; scores are read from the ID-keyed BAF ledger.
    ///      Near-level candidates come from the supplied main board's three non-solo traits.
    /// @param lvl BAF bracket level.
    /// @param rngWord The BAF transition VRF word.
    /// @param pair Round pair index.
    /// @param rounds Total scatter rounds (48..1536, a multiple of 48).
    /// @return winnerIds [best, second] of the even round, then of the odd round, as wallet
    ///         IDs; 0 where no candidate qualifies (no winner).
    /// @param traits The main board's three non-solo traits in quadrant order.
    /// @return draws The two near-level candidate slates; empty for far-future pairs.
    function bafPairWinners(uint24 lvl, uint256 rngWord, uint256 pair, uint256 rounds, uint8[3] calldata traits)
        external view returns (uint32[4] memory winnerIds, BafRound[2] memory draws);

    /// @notice Record a coinflip win for BAF score tracking.
    /// @dev COINFLIP only. VAULT (wallet ID 1) accrues a score but stays off the top-4 board;
    ///      sDGNRS (ID 2) is never reported. Coinflip reports only nonzero IDs and amounts (its
    ///      claim walk runs only for a wallet that holds an ID), so no zero branch is needed.
    /// @param id Wallet ID of the player whose winnings settled.
    /// @param lvl BAF bracket (level rounded up to the next multiple of 10).
    /// @param amount Winning coinflip payout credited to the player's BAF score.
    /// @custom:reverts OnlyCoin If caller is not COINFLIP.
    function recordBafFlip(uint32 id, uint24 lvl, uint256 amount) external;

    /// @notice Mark a BAF bracket as skipped when the daily flip loses.
    /// @dev Bumps lastBafResolvedDay so pre-skip winning-flip credit cannot
    ///      roll forward into future bracket leaderboards.
    /// @param lvl Level whose BAF was skipped.
    function markBafSkipped(uint24 lvl) external;

    /// @notice Day index of the most recent BAF resolution or skip.
    function getLastBafResolvedDay() external view returns (uint24);

    /// @notice Claim the WWXRP consolation of account `id` for a skipped BAF bracket.
    /// @dev Permissionless: anyone may execute; the score is keyed by the account's wallet ID and
    ///      the WWXRP mints to the account's PAYEE. `id == 0` is the caller (ID from Game
    ///      `walletIdOf(msg.sender)`, payee = caller). A nonzero `id` resolves its payee through
    ///      Game `resolveAccount(id, msg.sender)`, ignoring `authorized`. VAULT's consolation
    ///      escrows into its WWXRP mint allowance via the token's vault routing.
    /// @param id Score owner (0 = caller).
    /// @param lvl Skipped bracket level to claim.
    /// @custom:reverts E (Game) If `id` is unallocated.
    /// @custom:reverts NothingToClaim If the bracket is not skipped, or the score is stale, absent
    ///                 or already claimed (a caller with no ID holds no score).
    function claimBafConsolation(uint32 id, uint24 lvl) external;
}
