// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

interface IERC20BalanceOf {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title AfKingHelper
 * @notice Helper functions for afKing mode (auto-mode with activity bonus).
 * @dev This contract provides pure functions and internal helpers for afKing mode logic.
 *      Can be inherited by game modules or used via delegatecall.
 *
 * ## afKing Mode Requirements
 *
 * To activate afKing mode, players must:
 * 1. Enable auto-rebuy (ETH winnings → tickets)
 * 2. Enable auto-flip (auto-retry coinflips on loss)
 * 3. Have claimable balance >= 2 ETH (initial requirement)
 * 4. Have BURNIE balance >= 50k (initial requirement)
 * 5. Have active lazy pass (10 or 100 level)
 *
 * ## afKing Mode Benefits
 *
 * - Activity score bonus: 25% base, +5% per level after 5, max 50% at 10 levels
 * - Maximum bonus: +50% (achieved at 25 consecutive levels)
 * - Bonus compounds with other activity bonuses
 * - Can claim threshold amounts without deactivating mode
 *
 * ## Claiming with afKing Mode Active
 *
 * Players can claim in complete multiples of threshold:
 * - ETH: Can claim floor(balance / 2 ETH) × 2 ETH
 * - BURNIE: To claim all, must disable auto-rebuy first (deactivates afKing)
 * - Claiming threshold amounts does NOT deactivate afKing
 * - Balance can drop below threshold from claiming (mode stays active)
 *
 * ## Deactivation Triggers
 *
 * afKing mode automatically deactivates ONLY if:
 * - Player disables auto-rebuy
 * - Player disables auto-flip
 * - Lazy pass expires or becomes inactive
 * - Player manually deactivates
 *
 * afKing mode does NOT deactivate from:
 * - Claiming threshold amounts (even if balance drops)
 * - Spending BURNIE (even if balance drops)
 * - Auto-rebuy converting ETH to tickets
 */
abstract contract AfKingHelper is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when afKing mode is activated.
    /// @param player Player who activated afKing mode.
    /// @param activationLevel Level at which afKing mode was activated.
    event AfKingActivated(address indexed player, uint24 activationLevel);

    /// @notice Emitted when afKing mode is deactivated.
    /// @param player Player who deactivated afKing mode.
    /// @param reason Reason for deactivation (0=manual, 1=auto-rebuy off, 2=auto-flip off, 3=lazy pass expired).
    /// @param levelsActive Number of levels player was in afKing mode.
    event AfKingDeactivated(
        address indexed player,
        uint8 reason,
        uint24 levelsActive
    );

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Minimum claimable ETH balance to maintain afKing mode.
    uint256 private constant AFKING_MIN_ETH =
        2 ether / ContractAddresses.COST_DIVISOR;

    /// @notice Minimum BURNIE balance to maintain afKing mode.
    uint256 private constant AFKING_MIN_BURNIE = 50_000 ether;

    /// @notice Activity score bonus per level after the initial threshold (basis points).
    uint16 private constant AFKING_ACTIVITY_BPS_PER_LEVEL = 500; // 5%

    /// @notice Base activity score bonus while afKing is active (basis points).
    uint16 private constant AFKING_ACTIVITY_MIN_BPS = 2500; // 25%

    /// @notice Levels before scaling above base bonus.
    uint24 private constant AFKING_ACTIVITY_LEVELS_BEFORE_SCALE = 5;

    /// @notice Maximum activity score bonus from afKing mode (basis points).
    uint16 private constant AFKING_ACTIVITY_MAX_BPS = 5000; // 50%

    // -------------------------------------------------------------------------
    // Lazy Pass Integration
    // -------------------------------------------------------------------------

    /**
     * @notice Check if player has an active lazy pass (10 or 100 level).
     * @dev Override this function in your main contract to check actual lazy pass ownership.
     * @return hasPass True if player has active lazy pass.
     */
    function _hasActiveLazyPass(
        address player
    ) internal view virtual returns (bool);

    // -------------------------------------------------------------------------
    // afKing Eligibility Checks
    // -------------------------------------------------------------------------

    /**
     * @notice Check if player is eligible for afKing mode.
     * @dev Checks all requirements: auto modes enabled + sufficient balances + lazy pass.
     * @param player Address to check.
     * @return eligible True if player meets all afKing requirements.
     */
    function _isAfKingEligible(address player) internal view returns (bool) {
        // Requirement 1: Auto-rebuy enabled
        if (!autoRebuyEnabled[player]) return false;

        // Requirement 2: Auto-flip enabled
        if (!autoFlipEnabled[player]) return false;

        // Requirement 3: Claimable ETH >= 2 ETH
        uint256 ethBalance = claimableWinnings[player];
        if (ethBalance == 1) ethBalance = 0; // Sentinel handling
        if (ethBalance < AFKING_MIN_ETH) return false;

        // Requirement 4: BURNIE balance >= 50k
        uint256 burnieBalance = IERC20BalanceOf(ContractAddresses.COIN)
            .balanceOf(player);
        if (burnieBalance < AFKING_MIN_BURNIE) return false;

        // Requirement 5: Active lazy pass (10 or 100 level)
        if (!_hasActiveLazyPass(player)) return false;

        return true;
    }

    /**
     * @notice Calculate afKing activity score bonus for a player.
     * @dev Bonus = 25% base, +5% per level after 5, capped at 50% (10 levels).
     * @param player Address to calculate bonus for.
     * @return bonusBps Activity score bonus in basis points (0-5000).
     */
    function _afKingActivityBonus(
        address player
    ) internal view returns (uint16) {
        if (!afKingMode[player]) return 0;

        uint24 activationLevel = afKingActivatedLevel[player];
        if (activationLevel == 0) return 0;

        // Calculate consecutive levels in afKing mode
        uint24 currentLevel = level;
        if (currentLevel < activationLevel) return 0;

        uint24 levelsActive = currentLevel - activationLevel;

        // Calculate bonus: 25% base, +5% per level after 5, max 50%
        uint256 bonusBps = AFKING_ACTIVITY_MIN_BPS;
        if (levelsActive > AFKING_ACTIVITY_LEVELS_BEFORE_SCALE) {
            uint256 extraLevels = uint256(
                levelsActive - AFKING_ACTIVITY_LEVELS_BEFORE_SCALE
            );
            bonusBps += extraLevels * AFKING_ACTIVITY_BPS_PER_LEVEL;
        }
        if (bonusBps > AFKING_ACTIVITY_MAX_BPS) bonusBps = AFKING_ACTIVITY_MAX_BPS;

        return uint16(bonusBps);
    }

    /**
     * @notice Get maximum claimable ETH for player (respects afKing threshold).
     * @dev If afKing is active, can claim in complete multiples of threshold (2 ETH).
     *      Fractional remainder above the last complete threshold must stay for auto-rebuy.
     *
     * @param player Address to check.
     * @return maxClaimable Maximum ETH player can claim without breaking afKing.
     *
     * Examples:
     * - Balance 12.5 ETH → Can claim 12 ETH (6×2), must keep 0.5 ETH
     * - Balance 18 ETH → Can claim 18 ETH (9×2), must keep 0 ETH
     * - Balance 7 ETH → Can claim 6 ETH (3×2), must keep 1 ETH
     * - Balance 1 ETH → Can claim 1 ETH (already deactivated, below threshold)
     */
    function _afKingMaxClaimableEth(
        address player
    ) internal view returns (uint256) {
        uint256 balance = claimableWinnings[player];
        if (balance == 1) balance = 0; // Sentinel

        return _afKingMaxClaimableEthFromBalance(player, balance);
    }

    /**
     * @notice Get maximum claimable ETH for a player from a known balance.
     * @dev Avoids rereading claimableWinnings when balance is already in memory.
     * @param player Address to check.
     * @param balance Current claimable balance (sentinel-normalized).
     * @return maxClaimable Maximum ETH player can claim without breaking afKing.
     */
    function _afKingMaxClaimableEthFromBalance(
        address player,
        uint256 balance
    ) internal view returns (uint256) {
        // If not in afKing mode, can claim all
        if (!afKingMode[player]) return balance;

        // In afKing mode: can claim complete multiples of threshold
        // Formula: floor(balance / threshold) * threshold
        uint256 completeThresholds = balance / AFKING_MIN_ETH;
        return completeThresholds * AFKING_MIN_ETH;
    }

    /**
     * @notice Get maximum claimable BURNIE for player (respects afKing threshold).
     * @dev If afKing is active, can transfer in complete multiples of threshold (50k BURNIE).
     *      Fractional remainder above the last complete threshold must stay for auto-flip.
     *
     * @param player Address to check.
     * @return maxClaimable Maximum BURNIE player can transfer without breaking afKing.
     *
     * Examples:
     * - Balance 250k BURNIE → Can transfer 250k (5×50k), must keep 0
     * - Balance 320k BURNIE → Can transfer 300k (6×50k), must keep 20k
     * - Balance 180k BURNIE → Can transfer 150k (3×50k), must keep 30k
     * - Balance 80k BURNIE → Can transfer 50k (1×50k), must keep 30k
     * - Balance 40k BURNIE → Can transfer 40k (already deactivated, below threshold)
     */
    function _afKingMaxClaimableBurnie(
        address player
    ) internal view returns (uint256) {
        uint256 balance = IERC20BalanceOf(ContractAddresses.COIN)
            .balanceOf(player);

        // If not in afKing mode, can transfer all
        if (!afKingMode[player]) return balance;

        // In afKing mode: can transfer complete multiples of threshold
        // Formula: floor(balance / threshold) * threshold
        uint256 completeThresholds = balance / AFKING_MIN_BURNIE;
        return completeThresholds * AFKING_MIN_BURNIE;
    }

    // -------------------------------------------------------------------------
    // afKing Mode State Management
    // -------------------------------------------------------------------------

    /**
     * @notice Attempt to activate afKing mode for a player.
     * @dev Checks eligibility and activates if requirements are met.
     * @param player Address to activate afKing mode for.
     * @return activated True if afKing mode was activated.
     */
    function _activateAfKingIfEligible(
        address player
    ) internal returns (bool) {
        // Already active
        if (afKingMode[player]) return false;

        // Check eligibility
        if (!_isAfKingEligible(player)) return false;

        // Activate afKing mode
        afKingMode[player] = true;
        afKingActivatedLevel[player] = level;

        emit AfKingActivated(player, level);
        return true;
    }

    /**
     * @notice Deactivate afKing mode for a player.
     * @dev Called when player disables auto modes, lazy pass expires, or manual deactivation.
     * @param player Address to deactivate afKing mode for.
     * @param reason Reason code (0=manual, 1=auto-rebuy off, 2=auto-flip off, 3=lazy pass expired).
     */
    function _deactivateAfKing(address player, uint8 reason) internal {
        if (!afKingMode[player]) return;

        // Calculate levels active
        uint24 activationLevel = afKingActivatedLevel[player];
        uint24 levelsActive = (level >= activationLevel)
            ? level - activationLevel
            : 0;

        // Clear afKing state
        afKingMode[player] = false;
        afKingActivatedLevel[player] = 0;

        emit AfKingDeactivated(player, reason, levelsActive);
    }

    /**
     * @notice Check and update afKing mode status after settings change.
     * @dev Call this after: auto-mode toggle, lazy pass changes.
     *      Does NOT deactivate based on balance changes from claiming.
     *      Balance drops are allowed - only auto-mode/lazy pass changes matter.
     * @param player Address to check.
     */
    function _updateAfKingStatus(address player) internal {
        bool currentlyActive = afKingMode[player];

        if (currentlyActive) {
            // Check reasons for deactivation (NOT balance-related)
            uint8 reason = 0;

            if (!autoRebuyEnabled[player]) {
                reason = 1; // Auto-rebuy disabled
            } else if (!autoFlipEnabled[player]) {
                reason = 2; // Auto-flip disabled
            } else if (!_hasActiveLazyPass(player)) {
                reason = 3; // Lazy pass expired/not active
            }

            // Deactivate only if auto modes disabled or lazy pass gone
            if (reason > 0) {
                _deactivateAfKing(player, reason);
            }
        } else {
            // Try to auto-activate if eligible (includes balance checks for activation)
            _activateAfKingIfEligible(player);
        }
    }

    // -------------------------------------------------------------------------
    // View Functions (for frontend/analytics)
    // -------------------------------------------------------------------------

    /**
     * @notice Get afKing mode status and stats for a player.
     * @param player Address to query.
     * @return active True if afKing mode is currently active.
     * @return eligible True if player is eligible for afKing mode.
     * @return levelsActive Number of consecutive levels in afKing mode.
     * @return activityBonus Current activity score bonus in basis points.
     * @return maxClaimableEth Maximum ETH player can claim without breaking afKing.
     * @return maxClaimableBurnie Maximum BURNIE player can transfer without breaking afKing.
     */
    function getAfKingStatus(
        address player
    )
        external
        view
        returns (
            bool active,
            bool eligible,
            uint24 levelsActive,
            uint16 activityBonus,
            uint256 maxClaimableEth,
            uint256 maxClaimableBurnie
        )
    {
        active = afKingMode[player];
        eligible = _isAfKingEligible(player);

        if (active) {
            uint24 activationLevel = afKingActivatedLevel[player];
            uint24 currentLevel = level;
            levelsActive = (currentLevel >= activationLevel)
                ? currentLevel - activationLevel
                : 0;

            if (activationLevel != 0) {
                uint256 bonusBps = AFKING_ACTIVITY_MIN_BPS;
                if (levelsActive > AFKING_ACTIVITY_LEVELS_BEFORE_SCALE) {
                    uint256 extraLevels = uint256(
                        levelsActive - AFKING_ACTIVITY_LEVELS_BEFORE_SCALE
                    );
                    bonusBps += extraLevels * AFKING_ACTIVITY_BPS_PER_LEVEL;
                }
                if (bonusBps > AFKING_ACTIVITY_MAX_BPS) {
                    bonusBps = AFKING_ACTIVITY_MAX_BPS;
                }
                activityBonus = uint16(bonusBps);
            }
        }

        maxClaimableEth = _afKingMaxClaimableEth(player);
        maxClaimableBurnie = _afKingMaxClaimableBurnie(player);
    }

    /**
     * @notice Get afKing mode constants.
     * @return minEth Minimum ETH balance required (in wei).
     * @return minBurnie Minimum BURNIE balance required (in wei).
     * @return bpsPerLevel Activity bonus per level (basis points).
     * @return maxBps Maximum activity bonus (basis points).
     */
    function getAfKingConstants()
        external
        pure
        returns (
            uint256 minEth,
            uint256 minBurnie,
            uint16 bpsPerLevel,
            uint16 maxBps
        )
    {
        return (
            AFKING_MIN_ETH,
            AFKING_MIN_BURNIE,
            AFKING_ACTIVITY_BPS_PER_LEVEL,
            AFKING_ACTIVITY_MAX_BPS
        );
    }
}
