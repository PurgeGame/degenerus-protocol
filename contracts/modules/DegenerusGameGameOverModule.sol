// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusGame, MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @dev Minimal stETH interface (ERC20 subset)
interface IStETH {
    /// @param account Address to query balance of.
    function balanceOf(address account) external view returns (uint256);
    /// @param to Recipient address.
    /// @param amount Transfer amount in wei.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Admin interface for VRF shutdown during final sweep.
interface IDegenerusAdminShutdown {
    function shutdownVrf() external;
}

/// @dev GNRUS interface for gameover GNRUS cleanup.
interface IGNRUSGameOver {
    function burnAtGameOver() external;
    function onFinalSweep() external;
}

interface IFlipTombstone {
    function tombstoneAtGameOver() external;
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

    /// @notice FLIP coin contract for the gameover worthless-token tombstone flood
    IFlipTombstone private constant flip =
        IFlipTombstone(ContractAddresses.COIN);

    /// @notice Fixed refund amount per deity pass for early game over (levels 0-9)
    uint256 private constant DEITY_PASS_EARLY_GAMEOVER_REFUND =
        20 ether;

    // error E() — inherited from DegenerusGameStorage

    /// @notice Process game over by distributing remaining funds via jackpots.
    /// @dev Called when liveness guards trigger (1yr deploy timeout or 120-day inactivity).
    ///      Sets terminal gameOver flag.
    ///
    ///      Distribution logic:
    ///      - If game ended early (levels 0-9): Fixed 20 ETH refund per deity pass purchased,
    ///        FIFO by purchase order, budget-capped to available funds minus claimablePool
    ///      - Remaining funds: 10% to Decimator, 90% to the phase-correct terminal ticket cohort
    ///      - Decimator refunds flow to terminal jackpot pool
    ///      - Any uncredited remainder swept to vault and sDGNRS
    ///
    ///      Reads rngWordByDay[day] for entropy; reverts if funds exist but word is not yet available.
    ///      VRF fallback logic (historical word, stall timeout) is in AdvanceModule._gameOverEntropy.
    /// @param day Day index for RNG word lookup from rngWordByDay mapping.
    /// @custom:reverts Invariant When distributable funds exist but the RNG word is unavailable (defense-in-depth).
    /// @custom:reverts TransferFailed When an stETH or ETH transfer fails.
    function handleGameOverDrain(uint24 day) external {
        if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) != 0) return; // Already processed

        uint24 lvl = level;

        uint256 totalFunds = address(this).balance + steth.balanceOf(address(this));

        // Compute available funds FIRST (before any side effects)
        // Deity pass refunds have not happened yet, so claimablePool is pre-refund.
        // sDGNRS redemption ETH is segregated out of the game at submit (pullRedemptionReserve
        // transfers it to the sDGNRS contract), so it is no longer part of totalFunds here —
        // subtracting pendingRedemptionEthValue would double-count it.
        uint256 reserved = uint256(claimablePool);
        uint256 preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;

        // RNG gate: when distributable funds exist, require RNG word.
        // Defense-in-depth -- caller (_handleGameOverPath) already guarantees
        // rngWordByDay[day] != 0 before calling, so this revert should never fire.
        uint256 rngWord;
        if (preRefundAvailable != 0) {
            rngWord = rngWordByDay[day];
            if (rngWord == 0) revert Invariant();
        }

        // === All side effects below this line (RNG confirmed or no funds to distribute) ===

        // Deity pass refunds (levels 0-9): refund each owner what they paid, capped at the flat
        // DEITY_PASS_EARLY_GAMEOVER_REFUND so a boon-discounted deity (paid < 20 ETH) never refunds
        // more than it paid, then clamped to the remaining distributable budget (FIFO).
        if (lvl < 10) {
            uint256 ownerCount = deityPassOwners.length;
            uint256 budget = preRefundAvailable;
            uint256 totalRefunded;
            for (uint256 i; i < ownerCount; ) {
                address owner = deityPassOwners[i];
                uint256 refund = deityPassPricePaid[owner];
                if (refund != 0) {
                    if (refund > DEITY_PASS_EARLY_GAMEOVER_REFUND) {
                        refund = DEITY_PASS_EARLY_GAMEOVER_REFUND;
                    }
                    if (refund > budget) {
                        refund = budget;
                    }
                    if (refund != 0) {
                        _creditClaimable(owner, refund);
                        unchecked {
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
                claimablePool += uint128(totalRefunded); // Safe: totalRefunded bounded by preRefundAvailable which fits uint128
            }
        }

        // Latch terminal state
        gameOver = true;
        _goWrite(GO_TIME_SHIFT, GO_TIME_MASK, uint48(block.timestamp));

        // Burn unallocated tokens
        charityGameOver.burnAtGameOver();
        dgnrs.burnAtGameOver();
        // Flood FLIP's VAULT mint allowance as a one-shot worthless-token tombstone
        flip.tombstoneAtGameOver();

        _goWrite(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK, 1);
        _setNextPrizePool(0);
        _setFuturePrizePool(0);
        _setCurrentPrizePool(0);
        yieldAccumulator = 0;
        // Terminal state also clears the freeze: with the live pools drained, _unlockRng's
        // _unfreezePool must not resurrect the pending pool back into them, and no
        // post-gameOver box/Degenerette resolution may draw ETH from a phantom pending pool.
        prizePoolPendingPacked = 0;
        prizePoolFrozen = false;
        // All three pools are drained to zero at game over. Emit the terminal snapshot here —
        // before the available==0 early return below — so every game-over path logs it once. The
        // daily snapshot in _unlockRng skips game-over (gameOver is set above) to avoid a duplicate.
        emit PrizePoolDailySnapshot(
            0,
            0,
            0,
            claimablePool,
            address(this).balance + steth.balanceOf(address(this)),
            yieldAccumulator
        );

        // Recalculate available after refunds (claimablePool may have grown).
        // sDGNRS redemption ETH was already segregated out of the game at submit, so it is not
        // part of totalFunds here — only claimablePool is reserved.
        uint256 postRefundReserved = uint256(claimablePool);
        uint256 available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0;

        if (available == 0) return;

        emit GameOverDrained(lvl, available, claimablePool);

        // remaining tracks unallocated funds.
        uint256 remaining = available;

        // 10% Terminal Decimator (death bet) -- refunds flow back to remaining for terminal jackpot
        uint256 decPool = remaining / 10;
        if (decPool != 0) {
            uint256 decRefund = IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord);
            uint256 decSpend = decPool - decRefund;
            if (decSpend != 0) {
                claimablePool += uint128(decSpend); // Safe: decSpend bounded by decPool which is a fraction of available
            }
            remaining -= decPool;
            remaining += decRefund;
        }

        // 90% (+ decimator refund) to the final ticket cohort (Day-5-style bucket distribution).
        // gameOver=true prevents auto-rebuy inside _addClaimableEth (tickets worthless post-game).
        // Pay from the SAME phase-correct level the AdvanceModule terminal drain materialized:
        // current `lvl` in jackpot phase and in the locked last-purchase transition (where level was
        // already promoted), otherwise purchase-phase `lvl + 1`. Any leftover from empty trait
        // buckets stays in the contract until handleFinalSweep (30 days later) folds it into the
        // three-way split to vault / sDGNRS / GNRUS.
        if (remaining != 0) {
            IDegenerusGame(address(this)).runTerminalJackpot(
                remaining,
                _gameOverTicketLevel(lvl),
                rngWord
            );
        }
    }

    /// @notice Final sweep of all remaining funds after 30 days post-gameover.
    /// @dev Pays each sink (vault, sDGNRS, GNRUS) the claimable balance still
    ///      owed to it, then splits the remainder ~1/3 each (GNRUS absorbs the
    ///      rounding wei). All other unclaimed player balances are forfeited.
    ///      After GO_SWEPT=1, claimWinnings() reverts, so this is the last
    ///      chance for the three sinks to receive what they earned in-game.
    ///      Also shuts down the VRF subscription and sweeps LINK to vault.
    /// @custom:reverts TransferFailed When ETH or stETH transfer fails
    function handleFinalSweep() external {
        uint256 goTime = _goRead(GO_TIME_SHIFT, GO_TIME_MASK);
        if (goTime == 0) return; // Game not over yet
        if (block.timestamp < goTime + 30 days) return; // Too early
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return; // Already swept

        _goWrite(GO_SWEPT_SHIFT, GO_SWEPT_MASK, 1);
        charityGameOver.onFinalSweep(); // stamp GNRUS with the sweep time (anchors its recovery gates)

        uint256 owedV  = _claimableOf(ContractAddresses.VAULT);
        uint256 owedSD = _claimableOf(ContractAddresses.SDGNRS);
        uint256 owedG  = _claimableOf(ContractAddresses.GNRUS);
        _debitClaimable(ContractAddresses.VAULT, owedV);
        _debitClaimable(ContractAddresses.SDGNRS, owedSD);
        _debitClaimable(ContractAddresses.GNRUS, owedG);
        if (owedV  != 0) emit ClaimableSpent(ContractAddresses.VAULT,  owedV,  0, MintPaymentKind.Internal, owedV);
        if (owedSD != 0) emit ClaimableSpent(ContractAddresses.SDGNRS, owedSD, 0, MintPaymentKind.Internal, owedSD);
        if (owedG  != 0) emit ClaimableSpent(ContractAddresses.GNRUS,  owedG,  0, MintPaymentKind.Internal, owedG);
        claimablePool = 0;

        // Shutdown VRF subscription (fire-and-forget; failure must not block sweep)
        try admin.shutdownVrf() {} catch {}

        uint256 ethBal = address(this).balance;
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalFunds = ethBal + stBal;

        emit FinalSwept(totalFunds);

        if (totalFunds == 0) return;

        // Invariant claimablePool >= sum(claimableWinnings[*]) and balance >=
        // claimablePool guarantee totalFunds >= owedV+owedSD+owedG; if the
        // invariant ever fails, _sendStethFirst reverts (hard-revert policy).
        uint256 remainder  = totalFunds - (owedV + owedSD + owedG);
        uint256 thirdShare = remainder / 3;
        uint256 gnrusExtra = remainder - thirdShare - thirdShare;

        stBal = _sendStethFirst(ContractAddresses.VAULT,  owedV  + thirdShare, stBal);
        stBal = _sendStethFirst(ContractAddresses.SDGNRS, owedSD + thirdShare, stBal);
        _sendStethFirst(ContractAddresses.GNRUS,          owedG  + gnrusExtra, stBal);
    }

    /// @dev Send stETH first to a recipient, then ETH for the remainder. Returns updated stETH balance.
    ///      IMPORTANT: Hard-reverts on stETH/ETH transfer failure. Because game-over
    ///      sets terminal state flags that roll back on revert, a stuck stETH transfer
    ///      would block game-over processing until the transfer succeeds.
    /// @param to Recipient address.
    /// @param amount Total amount to send (stETH preferred, ETH as fallback).
    /// @param stethBal Remaining stETH balance available for transfers.
    /// @return Updated stETH balance after transfer.
    function _sendStethFirst(address to, uint256 amount, uint256 stethBal) private returns (uint256) {
        if (amount == 0) return stethBal;
        if (amount <= stethBal) {
            if (!steth.transfer(to, amount)) revert TransferFailed();
            return stethBal - amount;
        }
        if (stethBal != 0) {
            if (!steth.transfer(to, stethBal)) revert TransferFailed();
        }
        uint256 ethAmount = amount - stethBal;
        if (ethAmount != 0) {
            (bool ok, ) = payable(to).call{value: ethAmount}("");
            if (!ok) revert TransferFailed();
        }
        return 0;
    }
}
