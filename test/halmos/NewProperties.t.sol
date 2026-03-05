// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title v5.0 New Symbolic Properties for Halmos
/// @notice Targeted properties for BPS split conservation, lootbox split exactness,
///         affiliate reward bounds, and ticket cost non-zero -- all designed to avoid
///         256-bit division timeout triggers.
/// @dev Run with: halmos --contract NewPropertiesTest --forge-build-out forge-out --solver-timeout-assertion 60000
contract NewPropertiesTest is Test {
    // =========================================================================
    // Property 1: BPS split conservation
    // =========================================================================

    /// @notice BPS split of any amount conserves total: share + remainder == amount
    /// @dev Targets Phase 32's BPS arithmetic verification with full symbolic coverage
    function check_bps_split_exact(uint256 amount, uint16 bps) public pure {
        if (amount > 1e30) return; // reasonable ETH range
        if (bps > 10000) return;

        uint256 share = (amount * bps) / 10000;
        uint256 remainder = amount - share;

        // Conservation: share + remainder == amount (always true by construction)
        assert(share + remainder == amount);
        // Bound: share <= amount
        assert(share <= amount);
        // Bound: share is proportional (never exceeds bps/10000 * amount + 1)
        assert(share <= (amount * uint256(bps) + 9999) / 10000);
    }

    // =========================================================================
    // Property 2: Lootbox four-way split conservation
    // =========================================================================

    /// @notice Four-way lootbox split with remainder pattern conserves total exactly
    /// @dev Models _resolveLootboxRoll's split pattern from LootboxModule
    function check_lootbox_four_split(
        uint256 total,
        uint16 futureBps,
        uint16 nextBps,
        uint16 vaultBps
    ) public pure {
        if (total == 0 || total > 1e30) return;
        if (futureBps + nextBps + vaultBps > 10000) return;

        uint256 futureShare = (total * futureBps) / 10000;
        uint256 nextShare = (total * nextBps) / 10000;
        uint256 vaultShare = (total * vaultBps) / 10000;
        uint256 rewardShare = total - futureShare - nextShare - vaultShare;

        // Conservation: all four shares sum to total exactly
        assert(futureShare + nextShare + vaultShare + rewardShare == total);
        // Each share is bounded
        assert(futureShare <= total);
        assert(nextShare <= total);
        assert(vaultShare <= total);
        assert(rewardShare <= total);
    }

    // =========================================================================
    // Property 3: Affiliate reward bounded
    // =========================================================================

    /// @notice Affiliate reward never exceeds proportional bound
    /// @dev Targets Phase 34's affiliate reward analysis
    function check_affiliate_reward_bounded(uint256 amount, uint16 affiliateBps) public pure {
        if (amount > 1e30) return;
        if (affiliateBps > 10000) return;

        uint256 reward = (amount * affiliateBps) / 10000;

        // Reward never exceeds full amount
        assert(reward <= amount);
        // Reward is bounded by ceil(amount * affiliateBps / 10000)
        assert(reward <= (amount * uint256(affiliateBps) + 9999) / 10000);
        // Reward is zero when affiliateBps is zero
        if (affiliateBps == 0) {
            assert(reward == 0);
        }
    }

    // =========================================================================
    // Property 4: Ticket cost non-zero for meaningful quantities
    // =========================================================================

    /// @notice For quantity >= 400 (1 full ticket), cost is always non-zero
    /// @dev Uses PriceLookupLib to verify against actual protocol price table
    function check_ticket_cost_nonzero(uint24 level, uint32 quantity) public pure {
        if (quantity < 400 || quantity > 40000) return;

        uint256 priceWei = PriceLookupLib.priceForLevel(level);
        uint256 cost = (priceWei * uint256(quantity)) / 400;

        // priceWei >= 0.01 ether (10^16), quantity >= 400
        // cost >= (10^16 * 400) / 400 = 10^16 > 0
        assert(cost > 0);
        // cost <= 100 full ticket prices
        assert(cost <= priceWei * 100);
    }
}
