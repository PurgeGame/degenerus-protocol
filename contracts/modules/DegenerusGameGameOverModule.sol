// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @dev Minimal stETH interface (ERC20 subset)
interface IStETH {
    /// @param account Address to query balance of.
    function balanceOf(address account) external view returns (uint256);
    /// @param to Recipient address.
    /// @param amount Transfer amount in wei.
    function transfer(address to, uint256 amount) external returns (bool);
    /// @param spender Address to approve.
    /// @param amount Allowance amount in wei.
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev Admin interface for VRF shutdown during final sweep.
interface IDegenerusAdminShutdown {
    function shutdownVrf() external;
}

/// @dev GNRUS interface for gameover GNRUS cleanup.
interface IGNRUSGameOver {
    function burnAtGameOver() external;
}

/**
 * @title DegenerusGameGameOverModule
 * @notice Handles game over logic including jackpot distribution and final sweeps.
 * @dev Executed via delegatecall from DegenerusGame. Inherits storage layout.
 */
contract DegenerusGameGameOverModule is DegenerusGameStorage {
    /// @notice stETH token contract for liquid staking rewards
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @notice Admin contract for VRF shutdown
    IDegenerusAdminShutdown private constant admin =
        IDegenerusAdminShutdown(ContractAddresses.ADMIN);

    /// @notice GNRUS contract for gameover cleanup
    IGNRUSGameOver private constant charityGameOver =
        IGNRUSGameOver(ContractAddresses.GNRUS);

    /// @notice Fixed refund amount per deity pass for early game over (levels 0-9)
    uint256 private constant DEITY_PASS_EARLY_GAMEOVER_REFUND =
        20 ether;

    // error E() — inherited from DegenerusGameStorage

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
    /// @dev Called when liveness guards trigger (1yr deploy timeout or 120-day inactivity).
    ///      Sets terminal gameOver flag.
    ///
    ///      Distribution logic:
    ///      - If game ended early (levels 0-9): Fixed 20 ETH refund per deity pass purchased,
    ///        FIFO by purchase order, budget-capped to available funds minus claimablePool
    ///      - Remaining funds: 10% to Decimator, 90% to next-level ticketholders
    ///      - Decimator refunds flow to terminal jackpot pool
    ///      - Any uncredited remainder swept to vault and DGNRS
    ///
    ///      VRF fallback: Uses rngWordByDay which may use historical VRF word as secure
    ///      fallback if Chainlink VRF is stalled (after 3 day wait period).
    /// @param day Day index for RNG word lookup from rngWordByDay mapping.
    /// @custom:reverts E When stETH transfer fails
    function handleGameOverDrain(uint48 day) external {
        if (gameOverFinalJackpotPaid) return; // Already processed

        uint24 lvl = level;

        uint256 ethBal = address(this).balance;
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalFunds = ethBal + stBal;

        if (lvl < 10) {
            uint256 refundPerPass = DEITY_PASS_EARLY_GAMEOVER_REFUND;
            uint256 ownerCount = deityPassOwners.length;
            uint256 budget = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
            uint256 totalRefunded;
            for (uint256 i; i < ownerCount; ) {
                address owner = deityPassOwners[i];
                uint16 purchasedCount = deityPassPurchasedCount[owner];
                if (purchasedCount != 0) {
                    uint256 refund = refundPerPass * uint256(purchasedCount);
                    if (refund > budget) {
                        refund = budget;
                    }
                    if (refund != 0) {
                        unchecked {
                            claimableWinnings[owner] += refund;
                            totalRefunded += refund;
                            budget -= refund;
                        }
                    }
                    if (budget == 0) break;
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

        // Burn unallocated tokens before fund distribution (fires on all paths)
        charityGameOver.burnAtGameOver();
        dgnrs.burnAtGameOver();

        if (available == 0) {
            gameOverFinalJackpotPaid = true;
            _setNextPrizePool(0);
            _setFuturePrizePool(0);
            currentPrizePool = 0;
            yieldAccumulator = 0;
            return;
        }

        // Get RNG word for jackpot selection (includes VRF fallback after 3 days)
        uint256 rngWord = rngWordByDay[day];
        if (rngWord == 0) return; // RNG not ready yet — don't latch, allow retry

        gameOverFinalJackpotPaid = true;
        _setNextPrizePool(0);
        _setFuturePrizePool(0);
        currentPrizePool = 0;
        yieldAccumulator = 0;

        emit GameOverDrained(lvl, available, claimablePool);

        // remaining tracks unallocated funds.
        uint256 remaining = available;

        // 10% Terminal Decimator (death bet) — refunds flow back to remaining for terminal jackpot
        uint256 decPool = remaining / 10;
        if (decPool != 0) {
            uint256 decRefund = IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord);
            uint256 decSpend = decPool - decRefund;
            if (decSpend != 0) {
                claimablePool += decSpend;
            }
            remaining -= decPool;
            remaining += decRefund; // Return terminal dec refund to remaining for terminal jackpot
        }

        // 90% (+ decimator refund) to next-level ticketholders (Day-5-style bucket distribution)
        // gameOver=true prevents auto-rebuy inside _addClaimableEth (tickets worthless post-game)
        if (remaining != 0) {
            uint256 termPaid = IDegenerusGame(address(this))
                .runTerminalJackpot(remaining, lvl + 1, rngWord);
            // claimablePool already updated inside JackpotModule._distributeJackpotEth
            remaining -= termPaid;
            // Any undistributed remainder swept to vault
            if (remaining != 0) {
                _sendToVault(remaining, stBal);
            }
        }

    }

    /// @notice Final sweep of all remaining funds after 30 days post-gameover.
    /// @dev Forfeits all unclaimed winnings and sweeps entire balance.
    ///      Funds are split 33% DGNRS / 33% vault / 34% GNRUS.
    ///      Also shuts down the VRF subscription and sweeps LINK to vault.
    /// @custom:reverts E When ETH or stETH transfer fails
    function handleFinalSweep() external {
        if (gameOverTime == 0) return; // Game not over yet
        if (block.timestamp < uint256(gameOverTime) + 30 days) return; // Too early
        if (finalSwept) return; // Already swept

        finalSwept = true;
        claimablePool = 0;

        // Shutdown VRF subscription (fire-and-forget; failure must not block sweep)
        try admin.shutdownVrf() {} catch {}

        uint256 ethBal = address(this).balance;
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalFunds = ethBal + stBal;

        emit FinalSwept(totalFunds);

        if (totalFunds == 0) return;

        _sendToVault(totalFunds, stBal);
    }

    /// @dev Send funds to DGNRS (33%), vault (33%), and GNRUS (34%), stETH-first for all.
    ///      IMPORTANT: Hard-reverts on stETH/ETH transfer failure. Because game-over
    ///      sets terminal state flags that roll back on revert, a stuck stETH transfer
    ///      would block game-over processing until the transfer succeeds.
    /// @param amount Total amount to send (combined ETH + stETH value).
    /// @param stethBal Available stETH balance for transfers.
    /// @custom:reverts E When stETH transfer, approval, or ETH transfer fails
    function _sendToVault(uint256 amount, uint256 stethBal) private {
        uint256 thirdShare = amount / 3;                     // 33% each
        uint256 gnrusAmount = amount - thirdShare - thirdShare; // 34% (remainder to GNRUS)

        // Send stETH-first to each recipient, then ETH for any remainder
        stethBal = _sendStethFirst(ContractAddresses.SDGNRS, thirdShare, stethBal);
        stethBal = _sendStethFirst(ContractAddresses.VAULT, thirdShare, stethBal);
        _sendStethFirst(ContractAddresses.GNRUS, gnrusAmount, stethBal);
    }

    /// @dev Send stETH first to a recipient, then ETH for the remainder. Returns updated stETH balance.
    /// @param to Recipient address.
    /// @param amount Total amount to send (stETH preferred, ETH as fallback).
    /// @param stethBal Remaining stETH balance available for transfers.
    /// @return Updated stETH balance after transfer.
    function _sendStethFirst(address to, uint256 amount, uint256 stethBal) private returns (uint256) {
        if (amount == 0) return stethBal;
        if (amount <= stethBal) {
            if (!steth.transfer(to, amount)) revert E();
            return stethBal - amount;
        }
        if (stethBal != 0) {
            if (!steth.transfer(to, stethBal)) revert E();
        }
        uint256 ethAmount = amount - stethBal;
        if (ethAmount != 0) {
            (bool ok, ) = payable(to).call{value: ethAmount}("");
            if (!ok) revert E();
        }
        return 0;
    }
}
