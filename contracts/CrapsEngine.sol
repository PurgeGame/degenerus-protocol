// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "./Craps.sol";

/// @title CrapsEngine
/// @notice The craps table's dice, deployed on their own. Two pure entry points return a
///         settled run from a slip's packed chips and terms; the table uses `settleRanked`.
/// @dev Holds no storage, takes no constructor arguments, has no owner and no upgrade path.
///      `CrapsBattle` reaches it by STATICCALL at the pinned `ContractAddresses.CRAPS_ENGINE`,
///      which is what keeps the table itself under the EIP-170 ceiling: the engine's whole
///      closure — board, scatter, shooter loop — compiles here and nowhere else. Anyone may call
///      it; it can only compute.
contract CrapsEngine is Craps {
    /// @notice Play one slip to its stop.
    /// @param packedChips  The slip's named chips, ten three-bit legs, the dark side last.
    /// @param chipFlip     Whole FLIP per chip at this slot.
    /// @param scatterHash  The owner-keyed draw that throws the unnamed chips.
    /// @param scatterCount How many of the ten chips the dice place.
    /// @param seed         The window's shooter seed.
    /// @param bankroll     The bankroll the run starts on, in wei.
    /// @param goal         The bankroll that latches a Goal, in wei.
    /// @param player       The slip's owner, who seasons the survival coin.
    /// @param boost        The shooter-boost terms, zero for a custom battle.
    /// @return r The run: bankroll in and out, its peak, hands, units, rolls and the stop.
    function settleSlip(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        address player,
        uint256 boost
    ) external pure returns (SlipResult memory r) {
        r = _play(packedChips, chipFlip, scatterHash, scatterCount, seed, bankroll, goal, player, boost);
    }

    /// @notice `settleSlip` with the table's MERIT COMPOSITE (`_rankOf`) in the fifth word, in
    ///         place of the escalated units the table never reads. What `CrapsBattle` calls: the
    ///         comparator runs here, beside the dice, instead of in the table's bytecode.
    /// @dev Same parameters and the same run as `settleSlip`; only `unitsPlayed` differs.
    function settleRanked(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        address player,
        uint256 boost
    ) external pure returns (SlipResult memory r) {
        r = _play(packedChips, chipFlip, scatterHash, scatterCount, seed, bankroll, goal, player, boost);
        r.unitsPlayed = _rankOf(r);
    }

    function _play(
        uint256 packedChips,
        uint256 chipFlip,
        uint256 scatterHash,
        uint256 scatterCount,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        address player,
        uint256 boost
    ) private pure returns (SlipResult memory r) {
        Bets memory board = _boardFrom(packedChips, chipFlip);
        _scatterInto(board, scatterHash, chipFlip, scatterCount);
        r = _settleSlip(board, seed, bankroll, goal, _MAX_SLIP_HANDS, _SLIP_ROLL_BUDGET, player, boost);
    }
}
