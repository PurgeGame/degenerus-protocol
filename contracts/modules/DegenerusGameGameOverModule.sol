// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {IDegenerusTrophies} from "../interfaces/IDegenerusTrophies.sol";
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
    /// @dev stETH token interface
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    IDegenerusJackpots internal constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);
    IDegenerusStonk internal constant dgnrs = IDegenerusStonk(ContractAddresses.DGNRS);
    IDegenerusTrophies internal constant trophies = IDegenerusTrophies(ContractAddresses.TROPHIES);

    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;

    /// @dev Generic revert for error conditions
    error E();

    event PlayerCredited(
        address indexed player,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Sweep game funds on gameover - distributes remaining funds via jackpot or vault sweep.
    /// @dev Called when liveness guards trigger (2.5yr deploy or 365-day inactivity).
    ///      Transitions game to GAMEOVER (86).
    ///
    ///      GAMEOVER: Run a final BAF with 50% of non-claimable funds (ETH-only payouts),
    ///      then a Decimator using the remaining funds (ETH-only payouts).
    ///      Any unawarded decimator portion is swept to the vault and DGNRS.
    ///      Final sweep of all remaining funds occurs 1 month after gameover.
    ///      If RNG fallback is active (VRF stalled), skip the BAF.
    ///
    ///      VRF FALLBACK: Uses rngWordByDay which is set by _gameOverEntropy. If Chainlink VRF
    ///      is broken, waits 3 days then uses earliest historical VRF word as secure fallback.
    ///      This prevents manipulation since historical VRF was already verified on-chain.
    /// @param day Day index for RNG word lookup.
    function handleGameOverDrain(uint48 day) external {
        if (gameOverFinalJackpotPaid) return; // Already processed

        uint256 ethBal = address(this).balance;
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalFunds = ethBal + stBal;

        // Calculate available funds (excluding claimable winnings reserve)
        uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;

        gameState = GAME_STATE_GAMEOVER; // Terminal state
        gameOverTime = uint48(block.timestamp);
        gameOverFinalJackpotPaid = true;

        if (available == 0) return; // Nothing to distribute

        // Get RNG word for jackpot selection (includes VRF fallback after 3 days)
        uint256 rngWord = rngWordByDay[day];
        if (rngWord == 0) return; // RNG not ready yet (wait for fallback)

        // remaining tracks unallocated funds; BAF refunds stay here for decimator.
        uint256 remaining = available;

        if (rngFulfilled) {
            uint256 bafPool = remaining / 2;
            if (bafPool != 0) {
                uint256 bafSpend = _payGameOverBafEthOnly(bafPool, rngWord);
                if (bafSpend != 0) {
                    remaining -= bafSpend;
                }
            }
        }

        _payGameOverDecimatorEthOnly(remaining, rngWord);
    }

    /// @dev Run a final BAF jackpot with ETH-only payouts using the upcoming BAF bracket.
    ///      Returns amount actually credited (net spend).
    function _payGameOverBafEthOnly(
        uint256 amount,
        uint256 rngWord
    ) private returns (uint256 netSpend) {
        if (amount == 0) return 0;

        uint24 lvl = level;
        if (lvl == 0) {
            lvl = 1;
        }
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

        if (len != 0) {
            try trophies.mintBaf(winners[0], bafLvl, 0) {} catch {}
        }

        return credited;
    }

    /// @dev Round level up to the nearest bracket of 10 for BAF tracking.
    function _bafBracketLevel(uint24 lvl) private pure returns (uint24) {
        uint256 bracket = ((uint256(lvl) + 9) / 10) * 10;
        if (bracket > type(uint24).max) return MAX_BAF_BRACKET;
        return uint24(bracket);
    }

    /// @dev Run a Decimator jackpot with ETH-only payouts using all non-claimable funds.
    ///      If no eligible winners or snapshot already exists, the refund is sent to the vault.
    /// @param amount Total ETH amount to distribute.
    /// @param rngWord VRF random word for winner selection.
    function _payGameOverDecimatorEthOnly(uint256 amount, uint256 rngWord) private {
        if (amount == 0) return;

        uint24 lvl = level;
        if (lvl == 0) {
            lvl = 1;
        }

        uint256 refund = jackpots.runDecimatorJackpot(amount, lvl, rngWord);
        uint256 netSpend = amount - refund;
        if (netSpend != 0) {
            claimablePool += netSpend;
        }
        if (refund != 0) _sendToVault(refund);
    }

    /// @notice Final sweep of all remaining funds to vault after 1 month post-gameover.
    /// @dev Called automatically by advanceGame when appropriate time has passed.
    ///      Only sweeps funds beyond claimablePool (preserves player winnings).
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
        _sendToVault(available);
    }

    /// @dev Send funds to vault (50%) and DGNRS (50%), prioritizing stETH over ETH.
    /// @param amount Total amount to send (combined ETH + stETH value).
    function _sendToVault(uint256 amount) private {
        if (amount == 0) return;

        uint256 dgnrsAmount = amount / 2;  // 50%
        uint256 vaultAmount = amount - dgnrsAmount;  // 50%

        uint256 stethBal = steth.balanceOf(address(this));

        if (vaultAmount > 0) {
            if (vaultAmount <= stethBal) {
                if (!steth.transfer(ContractAddresses.VAULT, vaultAmount)) revert E();
                stethBal -= vaultAmount;
            } else {
                if (stethBal > 0) {
                    if (!steth.transfer(ContractAddresses.VAULT, stethBal)) revert E();
                }
                uint256 ethAmount = vaultAmount - stethBal;
                stethBal = 0;
                if (ethAmount > 0) {
                    (bool ok, ) = payable(ContractAddresses.VAULT).call{value: ethAmount}("");
                    if (!ok) revert E();
                }
            }
        }

        if (dgnrsAmount > 0) {
            if (dgnrsAmount <= stethBal) {
                if (!steth.approve(ContractAddresses.DGNRS, dgnrsAmount)) revert E();
                dgnrs.depositSteth(dgnrsAmount);
            } else {
                if (stethBal > 0) {
                    if (!steth.approve(ContractAddresses.DGNRS, stethBal)) revert E();
                    dgnrs.depositSteth(stethBal);
                }
                uint256 ethAmount = dgnrsAmount - stethBal;
                if (ethAmount > 0) {
                    (bool ok, ) = payable(ContractAddresses.DGNRS).call{value: ethAmount}("");
                    if (!ok) revert E();
                }
            }
        }
    }
}
