// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @dev Minimal stETH interface (ERC20 subset)
interface IStETH {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @title DegenerusGameGameOverModule
 * @notice Handles game over logic including jackpot distribution and final sweeps.
 * @dev Executed via delegatecall from DegenerusGame. Inherits storage layout.
 */
contract DegenerusGameGameOverModule is DegenerusGameStorage {
    /// @notice stETH token contract for liquid staking rewards
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @notice Jackpots contract for BAF and Decimator distributions
    IDegenerusJackpots internal constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);

    /// @notice DGNRS token contract for fund deposits
    IDegenerusStonk internal constant dgnrs = IDegenerusStonk(ContractAddresses.DGNRS);

    /// @notice Maximum BAF bracket level (rounded to nearest 10, capped at uint24 max)
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;

    /// @notice Fixed refund amount per deity pass for early game over (levels 1-9)
    uint256 private constant DEITY_PASS_EARLY_GAMEOVER_REFUND = 20 ether;

    /// @notice Generic error for failed operations
    /// @dev Used for transfer failures and other error conditions
    error E();

    /// @notice Emitted when winnings are credited to a player's claimable balance
    /// @param player The player who earned the winnings
    /// @param recipient The address receiving the credit (same as player)
    /// @param amount The amount credited in wei
    event PlayerCredited(
        address indexed player,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Process game over by distributing remaining funds via jackpots.
    /// @dev Called when liveness guards trigger (2.5yr deploy timeout or 365-day inactivity).
    ///      Sets terminal gameOver flag.
    ///
    ///      Distribution logic:
    ///      - If game never started (level 0, not in BURN state): Full refund of deity pass payments
    ///      - If game ended early (levels 1-9): Fixed 20 ETH refund per deity pass purchased
    ///      - Remaining funds split: 50% to BAF jackpot, remainder to Decimator jackpot
    ///      - Any unawarded funds swept to vault and DGNRS
    ///
    ///      VRF fallback: Uses rngWordByDay which may use historical VRF word as secure
    ///      fallback if Chainlink VRF is stalled (after 3 day wait period).
    /// @param day Day index for RNG word lookup from rngWordByDay mapping.
    /// @custom:reverts E When stETH transfer fails
    function handleGameOverDrain(uint48 day) external {
        if (gameOverFinalJackpotPaid) return; // Already processed

        uint24 currentLevel = level;
        uint24 lvl = currentLevel == 0 ? 1 : currentLevel;

        uint256 ethBal = address(this).balance;
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalFunds = ethBal + stBal;

        if (currentLevel == 0 && !jackpotPhaseFlag) {
            uint256 ownerCount = deityPassOwners.length;
            uint256 totalRefunded;
            for (uint256 i; i < ownerCount; ) {
                address owner = deityPassOwners[i];
                uint256 refund = deityPassPaidTotal[owner];
                if (refund != 0) {
                    unchecked {
                        claimableWinnings[owner] += refund;
                        totalRefunded += refund;
                    }
                    deityPassPaidTotal[owner] = 0;
                    deityPassRefundable[owner] = 0;
                }
                unchecked {
                    ++i;
                }
            }
            if (totalRefunded != 0) {
                claimablePool += totalRefunded;
            }
        } else if (currentLevel >= 1 && currentLevel < 10) {
            uint256 refundPerPass = DEITY_PASS_EARLY_GAMEOVER_REFUND;
            uint256 ownerCount = deityPassOwners.length;
            uint256 totalRefunded;
            for (uint256 i; i < ownerCount; ) {
                address owner = deityPassOwners[i];
                uint16 purchasedCount = deityPassPurchasedCount[owner];
                if (purchasedCount != 0) {
                    uint256 refund = refundPerPass * uint256(purchasedCount);
                    unchecked {
                        claimableWinnings[owner] += refund;
                        totalRefunded += refund;
                    }
                    deityPassPaidTotal[owner] = 0;
                    deityPassRefundable[owner] = 0;
                }
                unchecked {
                    ++i;
                }
            }
            if (totalRefunded != 0) {
                claimablePool += totalRefunded;
            }
        }

        // Calculate available funds (excluding claimable winnings reserve)
        uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;

        gameOver = true; // Terminal state
        gameOverTime = uint48(block.timestamp);
        gameOverFinalJackpotPaid = true;

        if (available == 0) return; // Nothing to distribute

        // Get RNG word for jackpot selection (includes VRF fallback after 3 days)
        uint256 rngWord = rngWordByDay[day];
        if (rngWord == 0) return; // RNG not ready yet (wait for fallback)

        // remaining tracks unallocated funds; BAF refunds stay here for decimator.
        uint256 remaining = available;

        uint256 bafPool = remaining / 2;
        if (bafPool != 0) {
            uint256 bafSpend = _payGameOverBafEthOnly(bafPool, rngWord, lvl);
            if (bafSpend != 0) {
                remaining -= bafSpend;
            }
        }

        _payGameOverDecimatorEthOnly(remaining, rngWord, lvl, stBal);
    }

    /// @dev Run a final BAF jackpot with ETH-only payouts using the calculated BAF bracket level.
    /// @param amount Total prize pool for the BAF jackpot.
    /// @param rngWord VRF random word for winner selection.
    /// @param lvl Current game level used to calculate BAF bracket.
    /// @return netSpend Amount actually credited to winners.
    function _payGameOverBafEthOnly(
        uint256 amount,
        uint256 rngWord,
        uint24 lvl
    ) private returns (uint256 netSpend) {
        uint24 bafLvl = _bafBracketLevel(lvl);

        (address[] memory winners, uint256[] memory amounts, , ) = jackpots
            .runBafJackpot(amount, bafLvl, rngWord);

        uint256 credited;
        uint256 len = winners.length;
        for (uint256 i; i < len; ) {
            address winner = winners[i];
            uint256 prize = amounts[i];
            if (winner != address(0) && prize != 0) {
                unchecked {
                    claimableWinnings[winner] += prize;
                }
                emit PlayerCredited(winner, winner, prize);
                credited += prize;
            }
            unchecked {
                ++i;
            }
        }

        if (credited != 0) {
            claimablePool += credited;
        }

        return credited;
    }

    /// @dev Round level up to the nearest bracket of 10 for BAF tracking.
    /// @param lvl Current game level.
    /// @return Bracket level rounded up to nearest 10, capped at MAX_BAF_BRACKET.
    function _bafBracketLevel(uint24 lvl) private pure returns (uint24) {
        unchecked {
            uint256 bracket = ((uint256(lvl) + 9) / 10) * 10;
            if (bracket > type(uint24).max) return MAX_BAF_BRACKET;
            return uint24(bracket);
        }
    }

    /// @dev Run a Decimator jackpot with ETH-only payouts using remaining non-claimable funds.
    ///      Any refund (no eligible winners or existing snapshot) is sent to the vault.
    /// @param amount Total amount to distribute via Decimator.
    /// @param rngWord VRF random word for winner selection.
    /// @param lvl Current game level for Decimator calculation.
    /// @param stethBal Current stETH balance for vault sweep allocation.
    function _payGameOverDecimatorEthOnly(
        uint256 amount,
        uint256 rngWord,
        uint24 lvl,
        uint256 stethBal
    ) private {
        uint256 refund = IDegenerusGame(address(this)).runDecimatorJackpot(
            amount,
            lvl,
            rngWord
        );
        uint256 netSpend = amount - refund;
        if (netSpend != 0) {
            claimablePool += netSpend;
        }
        if (refund != 0) _sendToVault(refund, stethBal);
    }

    /// @notice Final sweep of all remaining funds to vault after 30 days post-gameover.
    /// @dev Preserves claimablePool for player withdrawals. Only sweeps excess funds.
    ///      Funds are split 50/50 between vault and DGNRS contract.
    /// @custom:reverts E When ETH or stETH transfer fails
    function handleFinalSweep() external {
        if (gameOverTime == 0) return; // Game not over yet
        if (block.timestamp < uint256(gameOverTime) + 30 days) return; // Too early

        uint256 ethBal = address(this).balance;
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalFunds = ethBal + stBal;

        // Calculate available funds (excluding claimable winnings reserve)
        uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;

        if (available == 0) return; // Nothing to sweep

        // Send all available funds to vault and DGNRS (uses helper for correct ETH/stETH split)
        _sendToVault(available, stBal);
    }

    /// @dev Send funds to vault (50%) and DGNRS (50%), prioritizing stETH transfers over ETH.
    /// @param amount Total amount to send (combined ETH + stETH value).
    /// @param stethBal Available stETH balance for transfers.
    /// @custom:reverts E When stETH transfer, approval, or ETH transfer fails
    function _sendToVault(uint256 amount, uint256 stethBal) private {
        uint256 dgnrsAmount = amount / 2;  // 50%
        uint256 vaultAmount = amount - dgnrsAmount;  // 50%

        if (vaultAmount != 0) {
            if (vaultAmount <= stethBal) {
                if (!steth.transfer(ContractAddresses.VAULT, vaultAmount)) revert E();
                stethBal -= vaultAmount;
            } else {
                if (stethBal != 0) {
                    if (!steth.transfer(ContractAddresses.VAULT, stethBal)) revert E();
                }
                uint256 ethAmount = vaultAmount - stethBal;
                stethBal = 0;
                if (ethAmount != 0) {
                    (bool ok, ) = payable(ContractAddresses.VAULT).call{value: ethAmount}("");
                    if (!ok) revert E();
                }
            }
        }

        if (dgnrsAmount != 0) {
            if (dgnrsAmount <= stethBal) {
                if (!steth.approve(ContractAddresses.DGNRS, dgnrsAmount)) revert E();
                dgnrs.depositSteth(dgnrsAmount);
            } else {
                if (stethBal != 0) {
                    if (!steth.approve(ContractAddresses.DGNRS, stethBal)) revert E();
                    dgnrs.depositSteth(stethBal);
                }
                uint256 ethAmount = dgnrsAmount - stethBal;
                if (ethAmount != 0) {
                    (bool ok, ) = payable(ContractAddresses.DGNRS).call{value: ethAmount}("");
                    if (!ok) revert E();
                }
            }
        }
    }
}
