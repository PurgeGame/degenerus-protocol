// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {IStETH} from "../interfaces/IStETH.sol";

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
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
    IStETH internal constant payoutSteth = IStETH(ContractAddresses.STETH_TOKEN);
    function _transferSteth(address to, uint256 amount) internal {
        if (amount == 0) return;
        if (to == ContractAddresses.SDGNRS) {
            if (!payoutSteth.approve(ContractAddresses.SDGNRS, amount)) revert TransferFailed();
            dgnrs.depositSteth(amount);
            return;
        }
        if (!payoutSteth.transfer(to, amount)) revert TransferFailed();
    }

    function _payoutWithStethFallback(address to, uint256 amount) internal {
        if (amount == 0) return;

        // ETH is preferred for player claims, but the untrusted ETH .call MUST run LAST (CEI):
        // _claimWinningsInternal has already debited claimablePool by the full payout, so sending
        // ETH while the stETH remainder is still held would let a reentrant distributeYieldSurplus
        // read that in-flight stETH as unreserved backing and over-distribute it. Mirrors the
        // stETH-before-ETH ordering of _payoutWithEthFallback and the sDGNRS _payEth path.
        uint256 ethBal = address(this).balance;
        uint256 ethSend = amount <= ethBal ? amount : ethBal;
        uint256 remaining = amount - ethSend;

        // Move the stETH leg out first (a stETH transfer hands no control to `to`); any stETH
        // shortfall is folded into the single ETH .call below.
        if (remaining != 0) {
            uint256 stBal = payoutSteth.balanceOf(address(this));
            uint256 stSend = remaining <= stBal ? remaining : stBal;
            _transferSteth(to, stSend);
            ethSend += remaining - stSend;
        }

        // Untrusted ETH .call LAST — all ledger debits and the stETH transfer have completed.
        // An insufficient self-balance fails the value transfer itself (callee never runs),
        // so the !ok revert below covers the shortfall case.
        if (ethSend != 0) {
            (bool ok, ) = payable(to).call{value: ethSend}("");
            if (!ok) revert TransferFailed();
        }
    }

    /// @dev Route coin-presale-box ETH proceeds: 80% to the vault, 20% to sDGNRS,
    ///      both as claimable credits, while bumping claimablePool by the full
    ///      boxEth to reserve the credits.
    ///      The integer-division remainder lands on the VAULT (80%) side, so the
    ///      two credits sum to exactly boxEth.
    /// @param boxEth Box proceeds in wei to route.
    function _creditBoxProceeds(uint256 boxEth) internal {
        if (boxEth == 0) return;
        uint256 sdgnrsShare = boxEth / 5;
        claimablePool += uint128(boxEth);
        _creditClaimableLogged(VAULT_WALLET_ID, boxEth - sdgnrsShare);
        _creditClaimableLogged(SDGNRS_WALLET_ID, sdgnrsShare);
    }

    /// @dev Queue deferred whale pass claims for large payouts. Credits the sub-half-pass
    ///      remainder to claimableWinnings and returns it (mirrors _addClaimableEth): the
    ///      caller folds it into its claimableDelta so the single claimablePool bump and the
    ///      source-pool debit both cover it exactly once, preserving the solvency identity.
    /// @param winner Wallet ID credited with whole half-passes and any sub-half-pass remainder.
    /// @param amount Payout amount in wei to convert into half-passes plus remainder.
    /// @return remainderCredited Wei credited to claimableWinnings (0 if none) for the caller to fold.
    function _queueWhalePassClaimCore(
        uint32 winner,
        uint256 amount
    ) internal returns (uint256 remainderCredited) {
        if (winner == 0 || amount == 0) return 0;

        uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
        uint256 remainder = amount % HALF_WHALE_PASS_PRICE;

        if (fullHalfPasses != 0) {
            _addHalfPasses(winner, fullHalfPasses);
        }
        if (remainder != 0) {
            _creditClaimableLogged(winner, remainder);
        }
        return remainder;
    }
}
