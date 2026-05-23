// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";

/// @dev Shared payout helpers for jackpot-related modules.
abstract contract DegenerusGamePayoutUtils is DegenerusGameStorage {
    /// @notice Emitted when ETH is credited to a player's claimable balance.
    /// @param player The original winner (ticket holder).
    /// @param recipient The address receiving the credit.
    /// @param amount Wei credited.
    event PlayerCredited(address indexed player, address indexed recipient, uint256 amount);

    /// @dev Half whale pass price unit (each half-pass = 1 ticket/level for 100 levels).
    uint256 internal constant HALF_WHALE_PASS_PRICE =
        2.25 ether;

    /// @dev Credit ETH to a player's claimable winnings balance.
    /// @param beneficiary Address to credit.
    /// @param weiAmount Amount in wei to credit.
    function _creditClaimable(address beneficiary, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        unchecked {
            claimableWinnings[beneficiary] += weiAmount;
        }
        emit PlayerCredited(beneficiary, beneficiary, weiAmount);
    }

    /// @dev Queue deferred whale pass claims for large payouts.
    function _queueWhalePassClaimCore(address winner, uint256 amount) internal {
        if (winner == address(0) || amount == 0) return;

        uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
        uint256 remainder = amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE);

        if (fullHalfPasses != 0) {
            whalePassClaims[winner] += fullHalfPasses;
        }
        if (remainder != 0) {
            unchecked {
                claimableWinnings[winner] += remainder;
            }
            claimablePool += uint128(remainder);
            emit PlayerCredited(winner, winner, remainder);
        }
    }
}
