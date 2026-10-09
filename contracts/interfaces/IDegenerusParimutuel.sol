// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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

/// @title IDegenerusParimutuel
/// @author Burnie Degenerus
/// @notice The game's view of the parimutuel market: the seal it pushes and the in-order
///         settlement stage it cranks, plus the player bet door.
interface IDegenerusParimutuel {
    function runGrowthWork(uint256 budget) external returns (MineFlipGas.Result memory);
    function marketStateById(uint32 playerId, uint24 round) external view returns (
        uint24 openRound, uint128 overCount, uint128 underCount, uint256 questReward,
        uint8 side, bool claimed, uint8 outcome, uint256 payout
    );
    /// @notice Bet the fixed FLIP stake on round's OVER or UNDER side for account `id`.
    /// @dev Authorized: `id == 0` is the caller, whose ID comes from the Game registry. A nonzero `id` needs Game
    ///      `resolveAccount(id, msg.sender).authorized` (the account's key, a smurf's owner, or an
    ///      approved operator); the gates and growth-bet reward use that ID. The
    ///      stake burns from the account's PAYEE (`burnCoin(payee, STAKE)`); the bet, the
    ///      settlement credit (`creditFlipBatch` by ID) and the quest reward are the account's.
    /// @param id Account placing the bet (0 = caller).
    /// @param over True for OVER, false for UNDER.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E (Game) If `id` is unallocated.
    function placeBet(uint32 id, bool over) external;

    /// @notice Record the settled side of a growth round.
    /// @dev Called by GAME at the level transition that banks the successor ratchet entry —
    ///      the moment round `round`'s three terms are all final. Must run after every
    ///      ratchet write the transition performs, so a century entry reads its pushed
    ///      achieved pool rather than zero. Seals the outcome only; winners are paid later by
    ///      `runGrowthWork`. Game sets its settlement-pending bit when this returns true.
    /// @param round The growth round being settled.
    /// @param over True if the round resolved OVER, false for UNDER.
    /// @return settlementPending True when a sealed round now has unpaid winners (this round's
    ///         winning side is non-empty, or an earlier sealed round is still settling); false
    ///         when nothing is left to pay.
    /// @custom:reverts OnlyGame If caller is not GAME.
    function recordGrowth(uint24 round, bool over) external returns (bool settlementPending);
}
