// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @notice Symbolically executes production storage helpers, not copied arithmetic.
/// @dev Every monetary input is uint96 (up to ~79 billion ETH). This leaves room
/// for sums in the uint128 ledgers. These are local transition proofs, not a proof
/// of caller authorization, reward entitlement, or all reachable Game states.
/// The harness alone seeds arbitrary ledgers; production code is unchanged.
contract EthLedgerProductionProof is Test, DegenerusGameStorage {

    function _seed(uint32 account, uint32 otherId, uint256 claim, uint256 prepaid, uint256 other) private {
        balancesPacked[account] = claim | (prepaid << 128);
        balancesPacked[otherId] = other;
    }

    function check_claim_credit_is_local(uint32 account, uint32 otherId, uint96 claim, uint96 prepaid, uint96 amount, uint256 other) public {
        if (account == 0 || account == otherId) return;
        _seed(account, otherId, claim, prepaid, other);
        _creditClaimable(account, amount);
        assert(_claimableOf(account) == uint256(claim) + amount);
        assert(_afkingOf(account) == prepaid);
        assert(balancesPacked[otherId] == other);
        // This helper does not fund the credit: its caller must pair the pool move.
        assert(claimablePool == 0);
    }

    function check_prepaid_credit_accounts_liability(uint32 account, uint32 otherId, uint96 claim, uint96 prepaid, uint96 amount, uint96 pool) public {
        if (account == 0 || account == otherId) return;
        _seed(account, otherId, claim, prepaid, 123);
        claimablePool = pool;
        _creditAfkingValue(account, amount);
        assert(_claimableOf(account) == claim);
        assert(_afkingOf(account) == uint256(prepaid) + amount);
        assert(claimablePool == uint256(pool) + amount);
        assert(balancesPacked[otherId] == 123);
    }

    /// @dev The borrow ledger composition uses production debit/credit/pool helpers. Loan
    /// eligibility and lender selection are covered by AccountLoans and LoanAccounting.
    /// Symbolic IDs also avoid mixing solc-prehashed literal mapping slots with Halmos
    /// structured mapping keys; distinct nonzero IDs match the production lender/borrower split.
    function check_loan_credit_retains_total_obligations(
        uint32 lender, uint32 borrower, uint96 lenderClaim, uint96 lenderPrepaid, uint96 borrowerPrepaid,
        uint96 fromClaim, uint96 fromPrepaid, uint96 tickets, bool frozen
    ) public {
        if (lender == 0 || borrower == 0 || lender == borrower) return;
        if (fromClaim > lenderClaim || fromPrepaid > lenderPrepaid) return;
        uint256 principal = uint256(fromClaim) + fromPrepaid;
        if (tickets > principal) return;
        balancesPacked[lender] = (uint256(lenderClaim) + 1) | (uint256(lenderPrepaid) << 128);
        balancesPacked[borrower] = 1 | (uint256(borrowerPrepaid) << 128);
        uint256 before_ = uint256(lenderClaim) + lenderPrepaid + borrowerPrepaid;
        claimablePool = uint128(before_);
        _setPrizePools(0, 0);
        _setPendingPools(0, 0);
        prizePoolFrozen = frozen;
        _debitClaimableAndAfking(lender, fromClaim, fromPrepaid);
        claimablePool -= uint128(principal);
        _addPrizeContribution(tickets - tickets / 10, tickets / 10);
        _creditAfkingValue(borrower, principal - tickets);
        assert(_claimableOf(lender) == uint256(lenderClaim) + 1 - fromClaim);
        assert(_afkingOf(lender) == uint256(lenderPrepaid) - fromPrepaid);
        assert(_claimableOf(borrower) == 1);
        assert(_afkingOf(borrower) == uint256(borrowerPrepaid) + principal - tickets);
        assert(claimablePool == before_ - tickets);
        (uint128 n, uint128 f) = _getPrizePools();
        (uint128 pn, uint128 pf) = _getPendingPools();
        assert(uint256(claimablePool) + n + f + pn + pf == before_);
    }

    function check_combined_debit_keeps_lanes_separate(uint32 account, uint32 otherId, uint96 claim, uint96 prepaid, uint96 cash, uint96 funding) public {
        if (account == 0 || account == otherId) return;
        if (cash > claim || funding > prepaid) return;
        _seed(account, otherId, claim, prepaid, 123);
        _debitClaimableAndAfking(account, cash, funding);
        assert(_claimableOf(account) == uint256(claim) - cash);
        assert(_afkingOf(account) == uint256(prepaid) - funding);
        assert(balancesPacked[otherId] == 123);
    }

    function debit(uint32 account, uint256 cash, uint256 funding) external {
        _debitClaimableAndAfking(account, cash, funding);
    }

    function check_overdraw_reverts_without_cross_lane_borrow(uint32 account, uint32 otherId, uint96 claim, uint96 prepaid, uint256 cash, uint256 funding) public {
        if (account == 0 || account == otherId) return;
        if (cash <= claim && funding <= prepaid) return;
        _seed(account, otherId, claim, prepaid, 123);
        uint256 before_ = balancesPacked[account];
        (bool ok,) = address(this).call(abi.encodeCall(this.debit, (account, cash, funding)));
        assert(!ok);
        assert(balancesPacked[account] == before_);
    }

    function check_shortfall_conserves_and_preserves_sentinel(uint32 account, uint32 otherId, uint96 available, uint96 prepaid, uint96 cost, bool useClaim) public {
        if (account == 0 || account == otherId) return;
        if (uint256(cost) > (useClaim ? uint256(available) : 0) + prepaid) return;
        _seed(account, otherId, uint256(available) + 1, prepaid, 123);
        claimablePool = uint128(uint256(available) + prepaid);
        (uint256 cash, uint256 funding) = _settleShortfall(account, cost, useClaim);
        assert(cash + funding == cost);
        assert(_claimableOf(account) >= 1);
        assert(_claimableOf(account) + _afkingOf(account) == uint256(available) + prepaid + 1 - cost);
        assert(claimablePool == uint256(available) + prepaid - cost);
        assert(useClaim || cash == 0);
        assert(balancesPacked[otherId] == 123);
    }

    function check_redemption_release_is_reclassification_and_once(uint96 available, uint96 prepaid, uint96 reserved) public {
        balancesPacked[SDGNRS_WALLET_ID] = (uint256(available) + 1) | (uint256(prepaid) << 128);
        claimablePool = uint128(uint256(available) + prepaid + reserved);
        _setRedemptionReserve(reserved);
        _releaseRedemptionReserve();
        assert(_redemptionReserve() == 0);
        assert(_claimableOf(SDGNRS_WALLET_ID) == uint256(available) + 1 + reserved);
        assert(_afkingOf(SDGNRS_WALLET_ID) == prepaid);
        assert(claimablePool == uint256(available) + prepaid + reserved);
        uint256 after_ = balancesPacked[SDGNRS_WALLET_ID];
        _releaseRedemptionReserve();
        assert(balancesPacked[SDGNRS_WALLET_ID] == after_);
        assert(claimablePool == uint256(available) + prepaid + reserved);
    }

    function check_prize_contribution_conserves_in_either_buffer(
        uint96 next, uint96 future, uint96 pendingNext, uint96 pendingFuture,
        uint96 addNext, uint96 addFuture, bool frozen
    ) public {
        _setPrizePools(next, future);
        _setPendingPools(pendingNext, pendingFuture);
        prizePoolFrozen = frozen;
        _addPrizeContribution(addNext, addFuture);
        (uint128 n, uint128 f) = _getPrizePools();
        (uint128 pn, uint128 pf) = _getPendingPools();
        assert(n == uint256(next) + (frozen ? 0 : addNext));
        assert(f == uint256(future) + (frozen ? 0 : addFuture));
        assert(pn == uint256(pendingNext) + (frozen ? addNext : 0));
        assert(pf == uint256(pendingFuture) + (frozen ? addFuture : 0));
    }

    function check_yield_excludes_all_counted_obligations(
        uint96 current, uint96 next, uint96 future, uint96 claim, uint96 accumulated,
        uint96 pendingNext, uint96 pendingFuture, uint96 eth, uint96 steth
    ) public {
        currentPrizePool = current;
        _setPrizePools(next, future);
        claimablePool = claim;
        yieldAccumulator = accumulated;
        _setPendingPools(pendingNext, pendingFuture);
        vm.deal(address(this), eth);
        uint256 obligations = uint256(current) + next + future + claim + accumulated + pendingNext + pendingFuture;
        uint256 backing = uint256(eth) + steth;
        assert(_untrackedYield(steth) == (backing > obligations ? backing - obligations : 0));
    }
}
