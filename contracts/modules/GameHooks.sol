// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

abstract contract GameHooks is DegenerusGameStorage {
    /// @notice The one wallet-ID hook for protocol contracts with their own player entry points.
    /// @dev With `allocate = false`, return the ordinary wallet's existing ID or zero.
    ///      Allocation carries no spend here, so it is available only through the free-ID
    ///      threshold. Later callers must first register through a qualifying Game purchase.
    function _registerWallet(address owner, bool allocate) internal returns (uint32 id) {
        if (msg.sender != ContractAddresses.AFFILIATE && msg.sender != ContractAddresses.COINFLIP
            && msg.sender != ContractAddresses.CRAPS
            && msg.sender != ContractAddresses.PARIMUTUEL && msg.sender != ContractAddresses.WWXRP
            && msg.sender != ContractAddresses.ADMIN && msg.sender != ContractAddresses.COIN
            && msg.sender != ContractAddresses.GNRUS) revert E();
        if (!allocate) return _walletIdOf(owner);
        (id, ) = _registerWallet(owner, 0);
    }

    /// @notice Stable identity for wallet-bound governance and address-derived referral codes.
    function _registerWalletIdentity(address owner) internal returns (uint32 id) {
        if (msg.sender != ContractAddresses.ADMIN && msg.sender != ContractAddresses.GNRUS
            && msg.sender != ContractAddresses.AFFILIATE) revert E();
        id = uint32(walletIds[owner] >> 32);
        if (id == 0) (id, ) = _registerWallet(owner, 0);
    }

    /// @notice QUESTS-only: record a secondary/level quest completion against a live afking
    ///         run's streak, so its activity score reflects the player's own quest effort (the
    ///         primary rides the elapsed days).
    /// @dev No-op for a non-member and a run pending removal. Adds `amount` to the checkpoint
    ///      streak, saturating; the checkpoint day does not move, so nothing accrued changes.
    ///      `amount` is 1 for a daily secondary completion and LEVEL_QUEST_STREAK_BONUS for a
    ///      level-quest completion.
    /// @param id Wallet ID of the afking subscriber whose completion is being recorded.
    /// @param amount The streak increment to apply.
    function _recordAfkingSecondary(uint32 id, uint16 amount) internal {
        if (msg.sender != ContractAddresses.QUESTS) revert NotApproved();
        (uint256 lane, uint256 position1) = _subLaneOf(id);
        if (position1 == 0 || lane & SUB_REMOVAL_BIT != 0) return;
        _setSubLaneAt(position1 - 1, _withSubCheckpoint(lane, _subDay(lane), _subCheckpointStreak(lane) + amount));
    }

    /// @notice QUESTS-only: raise a live afking run's streak to at least `floor`, the same
    ///         foil-pack quest-streak guarantee a manual player's streak receives.
    /// @dev No-op for a non-member and a run pending removal. Raises the checkpoint streak by
    ///      the shortfall of the live streak; the checkpoint day does not move, so nothing
    ///      accrued changes.
    /// @param id Wallet ID of the afking subscriber whose streak is floored.
    /// @param floor The minimum live streak.
    function _floorAfkingStreakBase(uint32 id, uint16 floor) internal {
        if (msg.sender != ContractAddresses.QUESTS) revert NotApproved();
        (uint256 lane, uint256 position1) = _subLaneOf(id);
        if (position1 == 0 || lane & SUB_REMOVAL_BIT != 0) return;
        uint256 live = _subStreakAt(lane, _afkingEndpoint());
        if (live >= floor) return;
        _setSubLaneAt(position1 - 1, _withSubCheckpoint(lane, _subDay(lane), _subCheckpointStreak(lane) + floor - live));
    }
}
