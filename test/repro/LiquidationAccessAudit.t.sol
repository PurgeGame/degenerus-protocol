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
        _afkingEndpointDay = day;
        subsFullyProcessed = true;
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

    function laneOf(uint32 id) external view returns (uint256 lane, uint256 position1) {
        return _subLaneOf(id);
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

    function _subscribe(address owner, uint32 id) private {
        uint256 seat = _grantSeat(owner);
        vm.prank(owner);
        game.subscribe{value: 0.02 ether}(id, true, 1, seat);
    }

    function _default(uint32 id) private {
        uint24 due = game.level() + 1;
        vm.prank(borrower);
        game.borrow(id, due, type(uint256).max, 0);
        host.seizeAt(due);
        assertEq(game.acquiredBuyer(id), 2, "seized to sDGNRS");
    }

    function _cleanup() private {
        vm.warp(block.timestamp + 1 days);
        host.prepareNextDay();
    }

    /// @dev A seized run is removed by the next pass without being settled: its unclaimed
    ///      rewards are forfeited, and nothing is left to claim.
    function _assertRewardsGoneAfterCleanup(uint32 id) private {
        (, uint256 position1) = host.laneOf(id);
        assertEq(position1, 0, "the pass removed the run");
        vm.recordLogs();
        game.claimAfkingFlip(_one(id));
        affiliate.claim(_one(id));
        assertEq(vm.getRecordedLogs().length, 0, "nothing left to claim");
    }

    function test_SeizedSubscriptionRewardsClaimableUntilCleanup() public {
        _subscribe(borrower, root);
        _cleanup(); // one completed pass after signup: one day owed
        _default(root);
        (uint256 lane, uint256 position1) = host.laneOf(root);
        assertGt(position1, 0, "the closed run keeps its place until the next pass");
        assertEq((lane >> 68) & 1, 1, "seizure marks the run for removal");

        // The lender can claim before cleanup, so this is a real claim that disappears.
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs();
        game.claimAfkingFlip(_one(root));
        assertGt(vm.getRecordedLogs().length, 0, "claim works before cleanup");
        assertTrue(vm.revertToState(snapshot));

        _cleanup();
        _assertRewardsGoneAfterCleanup(root);
    }

    function test_UnrelatedSubscriberKeepsItsRunWhenAnotherAccountIsSeized() public {
        address subscriber = makeAddr("audit-bystander");
        vm.deal(subscriber, 1 ether);
        uint32 id = _giveWalletId(subscriber);
        _subscribe(subscriber, id);
        vm.prank(subscriber);
        game.depositAfkingFunding{value: 0.5 ether}(id);
        _default(root);
        assertEq(game.acquiredBuyer(id), 0, "subscriber itself was not seized");
        _cleanup();
        (uint256 lane, uint256 position1) = host.laneOf(id);
        assertGt(position1, 0, "its run survives the cleanup pass");
        assertEq((lane >> 68) & 1, 0, "and is not marked for removal");
        assertGt(game.afkingFundingOf(subscriber), 0, "own prepaid ETH survives");
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
                vm.expectRevert(bytes4(keccak256("NotApproved()")));
                coinflip.setCoinflipAutoRebuy(ids[i], false, 0);
                vm.expectRevert(bytes4(keccak256("NotApproved()")));
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

    function test_SeizedRunCannotChargeFormerOwnerOrBuyerStethApproval() public {
        vm.startPrank(borrower);
        mockStETH.approve(address(game), type(uint256).max);
        vm.stopPrank();
        mockStETH.mint(borrower, 2 ether);
        _subscribe(borrower, root);
        _default(root);
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
