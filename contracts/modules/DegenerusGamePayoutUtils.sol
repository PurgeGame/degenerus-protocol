// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @dev Shared payout helpers for jackpot-related modules.
abstract contract DegenerusGamePayoutUtils is DegenerusGameStorage {
    /// @notice Emitted when ETH is credited to a player's claimable balance.
    /// @param player The original winner (ticket holder).
    /// @param recipient The address receiving the credit.
    /// @param amount Wei credited.
    event PlayerCredited(address indexed player, address indexed recipient, uint256 amount);

    /// @dev Half whale pass price (100 tickets over levels 10-109).
    uint256 internal constant HALF_WHALE_PASS_PRICE =
        2.175 ether;

    struct AutoRebuyCalc {
        bool toFuture;
        bool hasTickets;
        uint24 targetLevel;
        uint32 ticketCount;
        uint256 ethSpent;
        uint256 reserved;
        uint256 rebuyAmount;
    }

    function _creditClaimable(address beneficiary, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        unchecked {
            claimableWinnings[beneficiary] += weiAmount;
        }
        emit PlayerCredited(beneficiary, beneficiary, weiAmount);
    }

    function _calcAutoRebuy(
        address beneficiary,
        uint256 weiAmount,
        uint256 entropy,
        AutoRebuyState memory state,
        uint24 currentLevel,
        uint16 bonusBps,
        uint16 bonusBpsAfKing
    ) internal pure returns (AutoRebuyCalc memory c) {
        if (!state.autoRebuyEnabled) return c;

        if (state.takeProfit != 0) {
            c.reserved = (weiAmount / state.takeProfit) * state.takeProfit;
        }
        c.rebuyAmount = weiAmount - c.reserved;

        uint256 levelOffset = (EntropyLib.entropyStep(
            entropy ^ uint256(uint160(beneficiary)) ^ weiAmount
        ) & 3) + 1; // 1-4 levels ahead
        c.toFuture = levelOffset > 1; // +1 → next (25%), +2/+3/+4 → future (75%)
        c.targetLevel = currentLevel + uint24(levelOffset);

        uint256 ticketPrice = PriceLookupLib.priceForLevel(c.targetLevel) >> 2;
        if (ticketPrice == 0) return c;

        uint256 baseTickets = c.rebuyAmount / ticketPrice;
        if (baseTickets == 0) return c;

        c.hasTickets = true;
        c.ethSpent = baseTickets * ticketPrice;

        uint256 bonusTickets = (baseTickets *
            (state.afKingMode ? bonusBpsAfKing : bonusBps)) / 10_000;
        c.ticketCount = bonusTickets > type(uint32).max
            ? type(uint32).max
            : uint32(bonusTickets);
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
            claimablePool += remainder;
            emit PlayerCredited(winner, winner, remainder);
        }
    }
}
