// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @dev Shared payout helpers for jackpot-related modules.
abstract contract DegenerusGamePayoutUtils is DegenerusGameStorage {
    /// @dev Half whale pass price unit (each half-pass = 1 entry/level over 100 levels = 100 entries = 25 whole tickets).
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
