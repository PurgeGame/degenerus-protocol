// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AfKingHelper} from "./AfKingHelper.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/**
 * @title AfKingIntegration
 * @notice Example integration of afKing mode into DegenerusGame.
 * @dev Copy these functions into your main DegenerusGame contract.
 */
abstract contract AfKingIntegration is AfKingHelper {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event AutoRebuyToggled(address indexed player, bool enabled);
    event AutoFlipToggled(address indexed player, bool enabled);
    event AfKingThresholdClaimed(address indexed player, uint256 ethAmount);

    // -------------------------------------------------------------------------
    // Auto-Mode Toggle Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Toggle auto-rebuy mode for caller.
     * @dev Auto-rebuy converts ETH winnings to tickets automatically.
     *      Required for afKing mode.
     */
    function toggleAutoRebuy() external {
        address player = msg.sender;
        bool newState = !autoRebuyEnabled[player];
        autoRebuyEnabled[player] = newState;

        // Update afKing status (may activate or deactivate)
        _updateAfKingStatus(player);

        emit AutoRebuyToggled(player, newState);
    }

    /**
     * @notice Toggle auto-flip mode for caller.
     * @dev Auto-flip retries coinflips on loss automatically.
     *      Required for afKing mode.
     */
    function toggleAutoFlip() external {
        address player = msg.sender;
        bool newState = !autoFlipEnabled[player];
        autoFlipEnabled[player] = newState;

        // Update afKing status (may activate or deactivate)
        _updateAfKingStatus(player);

        emit AutoFlipToggled(player, newState);
    }

    /**
     * @notice Manually activate afKing mode (if eligible).
     * @dev Checks eligibility and activates. Reverts if not eligible.
     */
    function activateAfKing() external {
        address player = msg.sender;
        require(!afKingMode[player], "Already active");
        require(_isAfKingEligible(player), "Not eligible");

        bool activated = _activateAfKingIfEligible(player);
        require(activated, "Activation failed");
    }

    // Note: No manual deactivation function
    // To deactivate afKing mode:
    // - Disable auto-rebuy: toggleAutoRebuy()
    // - Disable auto-flip: toggleAutoFlip()
    // - Let lazy pass expire
    // This prevents accidental deactivation while keeping intentional exits simple

    // -------------------------------------------------------------------------
    // Claiming Functions (afKing-aware)
    // -------------------------------------------------------------------------

    /**
     * @notice Claim your afKing threshold allowance (up to 2 ETH).
     * @dev The threshold is your "safe money" that can be claimed.
     *      Excess above threshold must stay in the game for auto-rebuy.
     *
     * Example:
     * - Balance: 12.5 ETH → Claims 12 ETH, keeps 0.5 ETH (afKing stays active)
     * - Balance: 7 ETH → Claims 6 ETH, keeps 1 ETH (afKing stays active)
     */
    function claimAfKingThreshold() external {
        address player = msg.sender;

        // Claim up to threshold
        uint256 balance = claimableWinnings[player];
        if (balance == 1) balance = 0; // Sentinel

        uint256 maxClaimableEth =
            _afKingMaxClaimableEthFromBalance(player, balance);
        require(maxClaimableEth > 0, "No claimable funds");

        claimableWinnings[player] = balance - maxClaimableEth;
        claimablePool -= maxClaimableEth;

        // Update afKing status (may deactivate if balance now too low)
        _updateAfKingStatus(player);

        // Transfer ETH
        (bool success, ) = player.call{value: maxClaimableEth}("");
        require(success, "ETH transfer failed");

        emit AfKingThresholdClaimed(player, maxClaimableEth);
    }

    // -------------------------------------------------------------------------
    // Callback from BURNIE Contract
    // -------------------------------------------------------------------------

    /**
     * @notice Callback from BURNIE contract on token transfers.
     * @dev Updates afKing status for sender and receiver after BURNIE transfers.
     * @param from Sender address.
     * @param to Receiver address.
     */
    function onBurnieTransfer(address from, address to) external {
        require(
            msg.sender == ContractAddresses.COIN,
            "Only BURNIE contract"
        );

        // Update afKing status for both parties
        if (from != address(0)) _updateAfKingStatus(from);
        if (to != address(0)) _updateAfKingStatus(to);
    }

    // -------------------------------------------------------------------------
    // Integration Points for Existing Functions
    // -------------------------------------------------------------------------

    /**
     * @dev Add this to your existing claimWinnings() function:
     *
     * function claimWinnings(uint256 amount) external nonReentrant {
     *     address player = msg.sender;
     *
     *     // Get max claimable (respects afKing)
     *     uint256 maxClaimable = _afKingMaxClaimableEth(player);
     *     require(maxClaimable > 0, "No claimable balance");
     *
     *     // ... rest of claim logic
     *
     *     // Update afKing status after claim
     *     _updateAfKingStatus(player);
     * }
     */

    /**
     * @dev Add this to your existing activity score calculations:
     *
     * function _calculateActivityScore(address player) internal view returns (uint256) {
     *     uint256 baseScore = /* your existing logic * /;
     *
     *     // Apply afKing bonus
     *     uint16 afKingBonus = _afKingActivityBonus(player);
     *     if (afKingBonus > 0) {
     *         baseScore = (baseScore * (10000 + afKingBonus)) / 10000;
     *     }
     *
     *     return baseScore;
     * }
     */

    /**
     * @dev Add this to your endgame module's _addClaimableEth():
     *
     * function _addClaimableEth(address beneficiary, uint256 weiAmount) private {
     *     // ... existing auto-rebuy logic
     *
     *     // Update afKing status after crediting winnings
     *     _updateAfKingStatus(beneficiary);
     * }
     */
}
