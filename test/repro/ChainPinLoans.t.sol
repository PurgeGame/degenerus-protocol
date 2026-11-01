// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {SeizureGasSeeder, LoanSeizureGasBase} from "../gas/LoanSeizureGas.t.sol";

/// @dev SeizureGasSeeder plus a claimable-only balance setter for steering the lender choice.
contract ChainPinLoanSeeder is SeizureGasSeeder {
    function setClaimable(uint32 id, uint128 claimable) external {
        uint256 old = balancesPacked[id];
        uint128 oldBacked = uint128(old) > 1 ? uint128(old) - 1 : 0;
        uint128 newBacked = claimable > 1 ? claimable - 1 : 0;
        claimablePool = claimablePool - oldBacked + newBacked;
        balancesPacked[id] = (old >> 128 << 128) | claimable;
    }
}

/// @notice Loan seizure has no failure isolation: the live SeizeLoans stage and the game-over loan
///         stage both run `GameOverModule.seizeLoan`, so a deterministic revert in it (burn,
///         subscription cancel, DeityPass.seize InvalidToken) would block the chain. These pins run
///         the heaviest accounts (an active AFKing run, a deity pass and native sDGNRS each) owed
///         to both lenders through both stages and assert every mineFlip succeeds and the stage
///         completes with the right ownership.
contract ChainPinLoansTest is LoanSeizureGasBase {
    uint8 private constant ACTION_SEIZE_LOANS = 19;
    uint256 private constant GO_LOAN_STEP_SHIFT = 64;
    uint32 private constant VAULT_ID = 1;
    uint32 private constant SDGNRS_ID = 2;

    address private other;
    uint32 private second;

    function _pin() private view returns (ChainPinLoanSeeder) { return ChainPinLoanSeeder(address(game)); }

    function _setClaimable(uint32 id, uint128 amount) private {
        _etch();
        _pin().setClaimable(id, amount);
        _unetch();
    }

    function _seedLevel(uint32 id, uint24 lvl, uint32 entries) private {
        _etch();
        _pin().seedLevel(id, lvl, entries);
        _unetch();
    }

    function _payeeOf(uint32 id) private view returns (address payee) {
        (, payee, ) = game.resolveAccount_g7029(id, address(0));
    }

    function _open(uint32 id) private view returns (bool) {
        return lens.loanOf(address(game), id).principal != 0;
    }

    function _borrowAs(address who, uint32 id, uint24 due) private {
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, due, type(uint256).max);
        assertTrue(q.eligible, "borrow eligible");
        vm.prank(who);
        game.borrow(id, due, type(uint256).max, q.principal - q.ticketWei);
    }

    /// @dev Balances one wei short of the repayment price, so the loan defaults.
    function _starve(uint32 id) private {
        DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), id);
        uint256 owed = info.principal * (10_000 + (info.dueLevel - info.startLevel) * 500) / 10_000;
        _setBalances(id, owed / 2, owed - owed / 2);
    }

    /// @dev The Vault lends only while sDGNRS cannot, so sDGNRS is drained for the one borrow.
    function _borrowFromVault(address who, uint32 id, uint24 due) private {
        _setClaimable(SDGNRS_ID, 1 ether);
        _borrowAs(who, id, due);
        assertEq(lens.loanOf(address(game), id).lenderId, VAULT_ID, "the Vault lent");
        _setClaimable(SDGNRS_ID, 500 ether);
    }

    /// @dev `who` subscribed to AFKing, holding the deity pass on `symbol` and native sDGNRS.
    function _loadAccount(address who, uint32 id, uint8 symbol) private {
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe{value: 2 ether}(id, false, 1, seat);
        vm.prank(who);
        game.purchaseDeityPass{value: 300 ether}(id, symbol, bytes32(0));
        vm.prank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, who, 1e15);
    }

    /// @dev Two loaded accounts (the base borrower's and a second wallet's) and the Vault enabled
    ///      as the second lender.
    function _prepare() private {
        _setUpBase();
        seeder = address(new ChainPinLoanSeeder());
        other = makeAddr("pin-second-borrower");
        vm.deal(other, 1_000 ether);
        second = _giveWalletId(other);
        _seedLevel(second, 8, 400);
        _loadAccount(borrower, root, 10);
        _loadAccount(other, second, 31);
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.setLiquidationBuyFallback, (true, 1 ether)), 0);
        _etch();
        _pin().fund(VAULT_ID, 100 ether);
        _unetch();
    }

    function _enterDue(uint24 due) private {
        _etch();
        _pin().enterDue(due);
        _unetch();
    }

    function _seizeLive(uint24 due) private {
        _enterDue(due);
        assertEq(game.nextMinerAction(), ACTION_SEIZE_LOANS, "the seizure stage is next");
        game.mineRun(0);
        for (uint256 i; i < 5 && game.nextMinerAction() == ACTION_SEIZE_LOANS; ++i) game.mineRun(0);
        assertTrue(game.nextMinerAction() != ACTION_SEIZE_LOANS, "the seizure stage completed");
    }

    function _assertSeized(uint32 id, address seller, uint8 symbol, address lender) private view {
        assertFalse(_open(id), "loan closed");
        assertEq(_payeeOf(id), lender, "account to its lender");
        assertEq(sdgnrs.balanceOf(seller), 0, "native sDGNRS burned");
        assertEq(game.walletIdOf_g3120(seller), 0, "seller's default ID cleared");
        assertEq(deityPass.ownerOf(symbol), lender, "the pass follows its account");
        (, , bool sellerAuth) = game.resolveAccount_g7029(id, seller);
        assertFalse(sellerAuth, "the seller lost control");
    }

    // ---------------------------------------------------------------- live SeizeLoans

    function test_LiveSeizure_BothLendersInOneStage() public {
        _prepare();
        _borrowFromVault(other, second, 1);
        _starve(second);
        _borrowAs(borrower, root, 1);
        _starve(root);
        _seizeLive(1);
        _assertSeized(second, other, 31, address(vault));
        _assertSeized(root, borrower, 10, address(sdgnrs));
    }

    function test_LiveSeizure_BothLendersInReverseListOrder() public {
        _prepare();
        _borrowAs(borrower, root, 1);
        _starve(root);
        _borrowFromVault(other, second, 1);
        _starve(second);
        _seizeLive(1);
        _assertSeized(root, borrower, 10, address(sdgnrs));
        _assertSeized(second, other, 31, address(vault));
    }

    function test_LiveSeizure_LaterLoanAfterAnEarlierSeizure() public {
        _prepare();
        _borrowAs(borrower, root, 1);
        _starve(root);
        _borrowFromVault(other, second, 2);
        _starve(second);
        _seizeLive(1);
        assertTrue(_open(second), "the other loan is not due yet");
        assertEq(_payeeOf(second), other);
        _assertSeized(root, borrower, 10, address(sdgnrs));
        _seizeLive(2);
        _assertSeized(second, other, 31, address(vault));
    }

    // ---------------------------------------------------------------- game-over loan stage

    function _loanStep() private view returns (uint256) {
        return uint8(uint256(vm.load(address(game), bytes32(uint256(GameSlots.GAME_OVER_STATE_PACKED))))
            >> GO_LOAN_STEP_SHIFT);
    }

    function _maxDue(uint32 id) private view returns (uint24) {
        for (uint24 d = 99; d > 1; --d) {
            try lens.previewBorrow(address(game), id, d, type(uint256).max) returns (DegenerusGameLens.LoanQuote memory q) {
                if (q.eligible) return d;
            } catch {}
        }
        return 0;
    }

    /// @dev The terminal latch with both loaded accounts plus loans at the near and far ends of the
    ///      due scan. The decision call latches, the next call settles the whole book.
    function test_TerminalLatch_SettlesBothLendersAndTheHorizonEdge() public {
        _prepare();
        _borrowFromVault(other, second, 1);
        _starve(second);
        _borrowAs(borrower, root, 1);
        _starve(root);

        address midOwner = makeAddr("pin-mid");
        address edgeOwner = makeAddr("pin-edge");
        vm.deal(midOwner, 10 ether);
        vm.deal(edgeOwner, 10 ether);
        uint32 mid = _giveWalletId(midOwner);
        uint32 edge = _giveWalletId(edgeOwner);
        _seedLevel(mid, 60, 400);
        for (uint24 l = 100; l <= 101; ++l) _seedLevel(edge, l, 400);
        _borrowAs(midOwner, mid, 5);
        _setBalances(mid, 0, 0);
        uint24 edgeDue = _maxDue(edge);
        assertGt(edgeDue, 90, "a far-horizon loan is possible");
        _borrowAs(edgeOwner, edge, edgeDue);
        _setBalances(edge, 0, 0);

        vm.warp(block.timestamp + 31 days);
        _etch();
        _pin().completedDeadline();
        _unetch();
        assertTrue(game.livenessTriggered(), "completed purchase deadline");
        game.mineRun(0);
        assertEq(_loanStep(), 1, "the decision owes settlement");
        game.mineRun(0);
        assertEq(_loanStep(), 0, "one call finishes the book");

        _assertSeized(second, other, 31, address(vault));
        _assertSeized(root, borrower, 10, address(sdgnrs));
        assertFalse(_open(mid), "mid-horizon loan closed");
        assertFalse(_open(edge), "far-horizon loan closed");
        assertEq(_payeeOf(mid), address(sdgnrs));
        assertEq(_payeeOf(edge), address(sdgnrs));

        // The ending moves on: the next call sends the terminal request or waits for it.
        (bool ok, bytes memory reason) = address(game).call(abi.encodeCall(game.mineRun, (uint32(0))));
        if (!ok) {
            assertTrue(reason.length == 4 && (bytes4(reason) == bytes4(keccak256("RngNotReady()"))
                || bytes4(reason) == bytes4(keccak256("NoWork()"))), "the call after the loan stage failed");
        }
    }
}
