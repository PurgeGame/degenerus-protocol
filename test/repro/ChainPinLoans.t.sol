// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {SeizureGasSeeder, LoanSeizureGasBase} from "../gas/LoanSeizureGas.t.sol";

interface IChainPinDeityMint {
    function mint(address to, uint256 tokenId) external;
}

/// @dev SeizureGasSeeder plus: a deity pass forced onto any account (a purchase allows one per
///      smurf group, so a family holding several passes is only reachable by seeding it) and a
///      claimable-only balance setter for steering the lender choice.
contract ChainPinLoanSeeder is SeizureGasSeeder {
    function forceDeity(uint32 id, uint8 symbol) external {
        mintPacked_[id] = mintPacked_[id] | (uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT);
        deityBySymbol[symbol] = id;
        _pushDeityId(id);
        IChainPinDeityMint(ContractAddresses.DEITY_PASS).mint(_payee(_walletElement(id)), symbol);
    }

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
///         subscription cancel, DeityPass.seize InvalidToken, an already-seized smurf) would block
///         the chain. These pins run the worst reachable families through both stages and assert
///         every mineFlip succeeds and the stage completes with the right ownership.
contract ChainPinLoansTest is LoanSeizureGasBase {
    uint8 private constant ACTION_SEIZE_LOANS = 19;
    uint256 private constant GO_LOAN_STEP_SHIFT = 64;
    uint32 private constant VAULT_ID = 1;
    uint32 private constant SDGNRS_ID = 2;

    uint32[5] private kids;

    function _pin() private view returns (ChainPinLoanSeeder) { return ChainPinLoanSeeder(address(game)); }

    function _forceDeity(uint32 id, uint8 symbol) private {
        _etch();
        _pin().forceDeity(id, symbol);
        _unetch();
    }

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
        (, payee, ) = game.resolveAccount_g502(id, address(0));
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
        _setClaimable(SDGNRS_ID, 500 ether);
    }

    /// @dev A subscribed main with five subscribed smurfs, a (forced) deity pass on every account,
    ///      native sDGNRS on the main's wallet, and the Vault enabled as the second lender.
    function _prepareFamily() private {
        _setUpBase();
        seeder = address(new ChainPinLoanSeeder());
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, borrower, 1e15);
        _sub(root);
        for (uint256 i; i < 5; ++i) {
            uint256 price = game.mintPrice();
            vm.prank(borrower);
            kids[i] = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
            _sub(kids[i]);
        }
        _forceDeity(root, 10);
        for (uint256 i; i < 5; ++i) _forceDeity(kids[i], uint8(11 + i));
        _seedLevel(kids[0], 8, 400);
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
        game.mineFlip(0);
        for (uint256 i; i < 5 && game.nextMinerAction() == ACTION_SEIZE_LOANS; ++i) game.mineFlip(0);
        assertTrue(game.nextMinerAction() != ACTION_SEIZE_LOANS, "the seizure stage completed");
    }

    /// @dev The main and four smurfs went to sDGNRS with their passes; kid 0 went to the Vault with its own.
    function _assertFamilyOwnership(bool kid0ToVault) private view {
        assertFalse(_open(root), "main loan closed");
        assertEq(_payeeOf(root), address(sdgnrs), "main to its lender");
        assertEq(sdgnrs.balanceOf(borrower), 0, "native sDGNRS burned");
        assertEq(deityPass.ownerOf(10), address(sdgnrs), "main's pass follows it");
        for (uint256 i; i < 5; ++i) {
            bool toVault = kid0ToVault && i == 0;
            assertEq(_payeeOf(kids[i]), toVault ? address(vault) : address(sdgnrs), "smurf follows its lender");
            assertEq(deityPass.ownerOf(11 + i), toVault ? address(vault) : address(sdgnrs), "smurf pass follows");
        }
    }

    // ---------------------------------------------------------------- live SeizeLoans

    /// @dev S1 F6 / S4 F5 (b): smurf 0 seized to the Vault first, then its main (five more passes, six
    ///      subscription runs, native sDGNRS) in the same stage; the seized smurf is skipped.
    function test_LiveSeizure_MainWithFiveDeitySmurfsOneAlreadySeizedToTheOtherLender() public {
        _prepareFamily();
        _borrowFromVault(borrower, kids[0], 1);
        _starve(kids[0]);
        _borrowAs(borrower, root, 1);
        _starve(root);
        _seizeLive(1);
        assertFalse(_open(kids[0]), "smurf loan closed");
        _assertFamilyOwnership(true);
    }

    /// @dev Reverse list order: the main's seizure takes the whole family first, then the smurf's own
    ///      loan defaults to its own lender and its pass moves on.
    function test_LiveSeizure_MainFirstThenItsSmurfsOwnLoanInTheSameStage() public {
        _prepareFamily();
        _borrowAs(borrower, root, 1);
        _starve(root);
        _borrowFromVault(borrower, kids[0], 1);
        _starve(kids[0]);
        _seizeLive(1);
        assertFalse(_open(kids[0]), "smurf loan closed");
        _assertFamilyOwnership(true);
    }

    /// @dev A smurf-only loan that comes due after its main's seizure.
    function test_LiveSeizure_SmurfOnlyLoanAfterItsMainsSeizure() public {
        _prepareFamily();
        _borrowAs(borrower, root, 1);
        _starve(root);
        _borrowFromVault(borrower, kids[0], 2);
        _starve(kids[0]);
        _seizeLive(1);
        assertTrue(_open(kids[0]), "the smurf loan is not due yet");
        _assertFamilyOwnership(false);
        _seizeLive(2);
        assertFalse(_open(kids[0]), "smurf loan closed");
        _assertFamilyOwnership(true);
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

    /// @dev S4 F5 (a): the terminal latch with the same family plus loans at the near and far ends
    ///      of the due scan. The decision call latches, the next call settles the whole book.
    function test_TerminalLatch_SettlesTheDeityFamilyAndTheHorizonEdge() public {
        _prepareFamily();
        _borrowFromVault(borrower, kids[0], 1);
        _starve(kids[0]);
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
        game.mineFlip(0);
        assertEq(_loanStep(), 1, "the decision owes settlement");
        game.mineFlip(0);
        assertEq(_loanStep(), 0, "one call finishes the book");

        assertFalse(_open(kids[0]), "smurf loan closed");
        _assertFamilyOwnership(true);
        assertFalse(_open(mid), "mid-horizon loan closed");
        assertFalse(_open(edge), "far-horizon loan closed");
        assertEq(_payeeOf(mid), address(sdgnrs));
        assertEq(_payeeOf(edge), address(sdgnrs));

        // The ending moves on: the next call sends the terminal request or waits for it.
        (bool ok, bytes memory reason) = address(game).call(abi.encodeCall(game.mineFlip, (uint32(0))));
        if (!ok) {
            assertTrue(reason.length == 4 && (bytes4(reason) == bytes4(keccak256("RngNotReady()"))
                || bytes4(reason) == bytes4(keccak256("NoWork()"))), "the call after the loan stage failed");
        }
    }
}
