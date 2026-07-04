// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @dev Shared payout helpers for jackpot-related modules.
abstract contract DegenerusGamePayoutUtils is DegenerusGameStorage {
    /// @dev Half whale pass price unit (each half-pass = 1 ticket/level for 100 levels).
    uint256 internal constant HALF_WHALE_PASS_PRICE =
        2.25 ether;

    /// @dev Route coin-presale-box ETH proceeds: 80% to the vault, 20% to sDGNRS,
    ///      both as claimable credits, while bumping claimablePool by the full
    ///      boxEth so the claimablePool >= Σ (claimableWinnings + afkingFunding) solvency
    ///      invariant holds.
    ///      The integer-division remainder lands on the VAULT (80%) side, so the
    ///      two credits sum to exactly boxEth.
    /// @param boxEth Box proceeds in wei to route.
    function _creditBoxProceeds(uint256 boxEth) internal {
        if (boxEth == 0) return;
        uint256 sdgnrsShare = boxEth / 5;
        claimablePool += uint128(boxEth);
        _creditClaimable(ContractAddresses.VAULT, boxEth - sdgnrsShare);
        _creditClaimable(ContractAddresses.SDGNRS, sdgnrsShare);
    }

    /// @dev Queue deferred whale pass claims for large payouts. Credits the sub-half-pass
    ///      remainder to claimableWinnings and returns it (mirrors _addClaimableEth): the
    ///      caller folds it into its claimableDelta so the single claimablePool bump and the
    ///      source-pool debit both cover it exactly once, preserving the solvency identity.
    /// @return remainderCredited Wei credited to claimableWinnings (0 if none) for the caller to fold.
    function _queueWhalePassClaimCore(
        address winner,
        uint256 amount
    ) internal returns (uint256 remainderCredited) {
        if (winner == address(0) || amount == 0) return 0;

        uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
        uint256 remainder = amount % HALF_WHALE_PASS_PRICE;

        if (fullHalfPasses != 0) {
            whalePassClaims[winner] += fullHalfPasses;
        }
        if (remainder != 0) {
            _creditClaimable(winner, remainder);
        }
        return remainder;
    }
}
