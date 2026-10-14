// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Setup and phase-boundary helpers only. All account operations, subscription accrual,
///      seizure, cancellation, cleanup and claims execute the production implementations.
contract LiquidationAuditHost is DegenerusGame {
    function openWindow() external {
        uint24 day = _simulatedDayIndex();
        dailyIdx = day;
        purchaseStartDay = day;
        _afkingResetDay = day;
        _recordDailyRng(day - 1, 123_456);
        _setRngComplete(true);
        _setRngRequestActive(false);
        rngLockedFlag = false;
    }

    function fundLender() external {
        _creditClaimable(SDGNRS_WALLET_ID, 100 ether);
        claimablePool += 100 ether;
    }

    function collateral(uint32 id) external {
        _queueEntries(id, _activeTicketLevel() + 6, 400, false);
    }

    function seizeAt(uint24 due) external {
        level = due;
        _setLoansDuePending(true);
        loanSeizeCursor = 0;
        (bool ok, bytes memory result) = ContractAddresses.GAME_ADVANCE_MODULE
            .delegatecall(abi.encodeWithSignature("runLoanSeizureWork(uint256)", uint256(10_000_000)));
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    function prepareNextDay() external {
        uint24 day = _simulatedDayIndex();
        dailyIdx = day - 1;
        _afkingResetDay = day;
        _subCursor = 0;
        subsFullyProcessed = false;
        rngLockedFlag = false;
        _setRngComplete(true);
        _setRngRequestActive(false);
        _sdgnrsBonusLevel = level;
        (bool ok, bytes memory result) = ContractAddresses.GAME_AFKING_MODULE
            .delegatecall(abi.encodeWithSignature("runSubscriberWork(uint24,uint256)", day, uint256(10_000_000)));
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        require(abi.decode(result, (MineFlipGas.Result)).done, "preparation incomplete");
    }

    function subState(uint32 id) external view returns (Sub memory) {
        return _subOf[id];
    }
}

/// @notice Liquidation access regressions and the by-design reward cleanup.
contract LiquidationAccessAuditTest is DeployProtocol {
    LiquidationAuditHost private host;
    address private borrower;
    address private operator;
    uint32 private root;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 2 days);
        vm.etch(address(game), type(LiquidationAuditHost).runtimeCode);
        host = LiquidationAuditHost(payable(address(game)));
        host.openWindow();
        vm.deal(address(game), 1000 ether);
        host.fundLender();
        borrower = makeAddr("audit-borrower");
        operator = makeAddr("audit-old-operator");
        vm.deal(borrower, 100 ether);
        root = _giveWalletId(borrower);
        _grantSmurfBase(borrower, 4);
        host.collateral(root);
    }

    function _one(uint32 id) private pure returns (uint32[] memory ids) {
        ids = new uint32[](1);
        ids[0] = id;
    }

    function _subscribe(address owner, uint32 id, uint32 source) private {
        uint256 seat = _grantSeat(owner);
        vm.prank(owner);
        game.subscribe{value: 0.02 ether}(id, false, true, 1, source, seat);
    }

    function _default(uint32 id) private {
        uint24 due = game.level() + 1;
        vm.prank(borrower);
        game.borrow(id, due, 0);
        host.seizeAt(due);
        assertEq(game.acquiredBuyer(id), 2, "seized to sDGNRS");
    }

    function _cleanup() private {
        vm.warp(block.timestamp + 1 days);
        host.prepareNextDay();
    }

    /// @dev By design: a seized or funder-seized run's unclaimed rewards are claimable
    ///      permissionlessly until the stage reclaims the tombstone, which deletes them.
    function _assertRewardsGoneAfterCleanup(uint32 id) private {
        DegenerusGameStorage.Sub memory gone = host.subState(id);
        assertEq(gone.setPosition, 0);
        assertEq(gone.pendingFlip, 0, "reclaim deletes unclaimed FLIP");
        assertEq(gone.affiliateBase, 0, "reclaim deletes unclaimed affiliate base");
        vm.recordLogs();
        game.claimAfkingFlip(_one(id));
        affiliate.claim(_one(id));
        assertEq(vm.getRecordedLogs().length, 0, "nothing left to claim");
    }

    function test_SeizedSubscriptionRewardsClaimableUntilCleanup() public {
        _subscribe(borrower, root, 0);
        DegenerusGameStorage.Sub memory before = host.subState(root);
        assertGt(before.pendingFlip, 0, "paid subscription earned FLIP");
        assertGt(before.affiliateBase, 0, "paid subscription earned affiliate rewards");
        _default(root);
        DegenerusGameStorage.Sub memory cancelled = host.subState(root);
        assertEq(cancelled.dailyQuantity, 0);
        assertEq(cancelled.pendingFlip, before.pendingFlip, "seizure leaves rewards in tombstone");
        assertEq(cancelled.affiliateBase, before.affiliateBase);

        // The lender can claim before cleanup, so this is a real claim that disappears.
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs();
        game.claimAfkingFlip(_one(root));
        assertGt(vm.getRecordedLogs().length, 0, "claim works before cleanup");
        assertTrue(vm.revertToState(snapshot));

        _cleanup();
        _assertRewardsGoneAfterCleanup(root);
    }

    function test_SponsoredSubscriberRewardsClaimableUntilFunderSeizureCleanup() public {
        address subscriber = makeAddr("audit-sponsored");
        vm.deal(subscriber, 1 ether);
        uint32 id = _giveWalletId(subscriber);
        vm.prank(borrower);
        game.setAfkingFundingApproval(root, id, true);
        _subscribe(subscriber, id, root);
        // This unrelated subscriber has ample own funding, but its selected source is sold.
        vm.prank(subscriber);
        game.depositAfkingFunding{value: 0.5 ether}(id);
        DegenerusGameStorage.Sub memory before = host.subState(id);
        assertGt(before.pendingFlip, 0);
        assertGt(before.affiliateBase, 0);
        _default(root);
        assertEq(game.acquiredBuyer(id), 0, "subscriber itself was not seized");
        _cleanup();
        assertEq(host.subState(id).setPosition, 0);
        assertEq(game.afkingFundingOf(subscriber), 0.5 ether, "own prepaid ETH survives");
        _assertRewardsGoneAfterCleanup(id);
    }

    function test_OldOperatorAndOwnerCannotSpendSeizedMainOrChild() public {
        uint256 price = game.mintPrice();
        vm.prank(borrower);
        uint32 child = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        vm.startPrank(borrower);
        game.setOperatorApproval(root, operator, true);
        game.setOperatorApproval(child, operator, true);
        vm.stopPrank();
        _default(root);
        uint32[2] memory ids = [root, child];
        address[2] memory callers = [borrower, operator];
        for (uint256 i; i < ids.length; ++i) {
            for (uint256 j; j < callers.length; ++j) {
                (, address payee, bool authorized) = game.resolveAccount(ids[i], callers[j]);
                assertEq(payee, address(sdgnrs));
                assertFalse(authorized);
                vm.startPrank(callers[j]);
                vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
                game.claimWinnings(ids[i]);
                vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
                game.withdrawAfkingFunding(ids[i], 1);
                vm.expectRevert();
                coinflip.setCoinflipAutoRebuy(ids[i], false, 0);
                vm.expectRevert();
                wwxrp.withdraw(ids[i], 0);
                vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
                game.setOperatorApproval(ids[i], callers[j], true);
                vm.stopPrank();
            }
        }
        uint32 replacement = _giveWalletId(borrower);
        assertNotEq(replacement, root);
        (,, bool allowed) = game.resolveAccount(replacement, borrower);
        assertTrue(allowed, "new main is usable");
        (,, allowed) = game.resolveAccount(replacement, operator);
        assertFalse(allowed, "old approval does not migrate to new main");
    }

    function test_StaleFundingAndStethApprovalsCannotChargeFormerOwnerOrBuyer() public {
        address subscriber = makeAddr("audit-steth-subscriber");
        vm.deal(subscriber, 1 ether);
        uint32 id = _giveWalletId(subscriber);
        vm.startPrank(borrower);
        game.setAfkingFundingApproval(root, id, true);
        mockStETH.approve(address(game), type(uint256).max);
        vm.stopPrank();
        mockStETH.mint(borrower, 2 ether);
        _subscribe(subscriber, id, root);
        _default(root);
        assertFalse(game.afkingFundingApproved(root, id));
        uint256 formerOwnerBalance = mockStETH.balanceOf(borrower);
        uint256 buyerBalance = mockStETH.balanceOf(address(sdgnrs));
        _cleanup();
        assertEq(mockStETH.balanceOf(borrower), formerOwnerBalance);
        assertEq(mockStETH.balanceOf(address(sdgnrs)), buyerBalance);
        assertEq(mockStETH.allowance(borrower, address(game)), type(uint256).max);
    }

    function test_StandaloneSmurfDefaultPreservesMainAndSiblingAccess() public {
        uint256 price = game.mintPrice();
        vm.startPrank(borrower);
        uint32 child = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        uint32 sibling = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        game.setOperatorApproval(root, operator, true);
        game.setOperatorApproval(child, operator, true);
        game.setOperatorApproval(sibling, operator, true);
        game.depositAfkingFunding{value: 1 ether}(sibling);
        vm.stopPrank();
        host.collateral(child);
        _default(child);

        assertEq(game.walletIdOf(borrower), root, "main account remains current");
        (,, bool allowed) = game.resolveAccount(child, operator);
        assertFalse(allowed, "approval on seized child is dead");
        (,, allowed) = game.resolveAccount(root, operator);
        assertTrue(allowed, "unseized main approval survives");
        (,, allowed) = game.resolveAccount(sibling, operator);
        assertTrue(allowed, "unseized sibling approval survives");
        uint256 before = borrower.balance;
        vm.prank(operator);
        game.withdrawAfkingFunding(sibling, 1 ether);
        assertEq(borrower.balance, before + 1 ether, "surviving approval still pays owner");
    }
}
