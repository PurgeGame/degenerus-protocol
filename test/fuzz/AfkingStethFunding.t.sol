// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {AfkingStethHost, AdversarialAfkingSteth} from "./helpers/AfkingStethFixture.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract AfkingStethFundingTest is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }


    /// @dev operatorApprovals[id][op] read from storage.
    function _approved(uint32 id, address op) internal view returns (bool) {
        return game.afkingFundingApproved(id, game.walletIdOf(op));
    }
    AfkingStethHost internal host;
    AdversarialAfkingSteth internal badToken;
    address internal constant PLAYER = address(0xA11CE);
    address internal constant FUNDER = address(0xF00D);
    address internal constant NEXT = address(0xB0B);
    uint256 internal constant WORK_GAS = 6_000_000;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 2 days);
        vm.etch(address(game), type(AfkingStethHost).runtimeCode);
        host = AfkingStethHost(payable(address(game)));
        vm.deal(address(game), 100 ether);
        host.prepare();
    }

    function _consent(address funder, address player) internal {
        if (funder == player) return;
        _aid(funder);
        uint32 playerId = _aid(player);
        vm.prank(funder);
        game.setAfkingFundingApproval(0, playerId, true);
    }

    function _authorize(address funder, address player, uint256 allowance_) internal {
        _consent(funder, player);
        vm.prank(funder);
        mockStETH.approve(address(game), allowance_);
    }

    function _adversarial() internal {
        vm.etch(address(mockStETH), type(AdversarialAfkingSteth).runtimeCode);
        badToken = AdversarialAfkingSteth(payable(address(mockStETH)));
    }

    function _work() internal returns (MineFlipGas.Result memory result) {
        result = host.subWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(result.done, "worker drains admitted cohort");
    }

    function _add(
        address player,
        address source,
        bool drainFirst,
        bool tickets,
        uint8 quantity,
        uint256 prepaid,
        uint256 claimable
    ) internal {
        host.add(player, source, drainFirst, tickets, quantity, prepaid, claimable);
    }

    function _expectNoTokenCalls() internal {
        vm.expectCall(
            address(mockStETH), abi.encodeWithSelector(mockStETH.balanceOf.selector, address(game)), uint64(0)
        );
        vm.expectCall(address(mockStETH), abi.encodeWithSelector(mockStETH.getSharesByPooledEth.selector), uint64(0));
        vm.expectCall(address(mockStETH), abi.encodeWithSelector(mockStETH.getPooledEthByShares.selector), uint64(0));
        vm.expectCall(address(mockStETH), abi.encodeWithSelector(mockStETH.transferSharesFrom.selector), uint64(0));
    }

    function _assertEvicted(address player) internal view {
        assertEq(host.memberOf(player), 0, "unpaid member removed");
        DegenerusGameStorage.Sub memory sub = host.stateOf(player);
        assertEq(sub.dailyQuantity, 0);
        assertEq(sub.lastAutoBoughtDay, 0, "no paid marker survives");
        assertEq(sub.affiliateBase, 0, "unclaimed affiliate accrual forfeited");
        assertEq(sub.pendingFlip, 0, "unclaimed FLIP forfeited");
        assertEq(host.entries(player), 0, "no tickets delivered");
    }

    function testFuzz_OnlyResidualPaidBothOrdersAndSources(
        bool sponsored,
        bool drainFirst,
        bool tickets,
        uint8 quantitySeed,
        uint96 prepaidSeed,
        uint96 claimSeed
    ) public {
        uint8 quantity = uint8(bound(quantitySeed, 1, 255));
        uint256 cost = host.price() * quantity;
        uint256 prepaid = bound(prepaidSeed, 0, cost - 1);
        uint256 claimable = bound(claimSeed, 0, cost - prepaid - 1);
        address source = sponsored ? FUNDER : PLAYER;
        _add(PLAYER, sponsored ? FUNDER : address(0), drainFirst, tickets, quantity, prepaid, claimable + 1);
        mockStETH.mint(source, 100 ether);
        uint256 missing = cost - prepaid - claimable;
        _authorize(source, PLAYER, missing);
        uint256 backingBefore = mockStETH.balanceOf(address(game));
        uint256 poolBefore = game.claimablePoolView();
        uint256 prizesBefore = game.nextPrizePoolView() + game.futurePrizePoolView();
        _work();
        assertEq(mockStETH.balanceOf(address(game)) - backingBefore, missing, "only original residual pulled");
        assertEq(mockStETH.allowance(source, address(game)), 0, "GAME consumes exact finite allowance");
        assertEq(host.claimableOf(PLAYER), 1, "original claimable slice retained with sentinel");
        assertEq(game.afkingFundingOf(source), 0, "original prepaid slice consumed");
        assertEq(game.claimablePoolView(), poolBefore + missing - cost, "receipt and both debits conserve liabilities");
        assertEq(game.nextPrizePoolView() + game.futurePrizePoolView(), prizesBefore + cost);
        assertGt(host.memberOf(PLAYER), 0);
        assertEq(host.stateOf(PLAYER).lastAutoBoughtDay, game.currentDayView());
        if (tickets) assertGt(host.entries(PLAYER), 0);
        else assertEq(host.pendingBoxes(), 1);
    }

    function test_InternallyFundedDoesNotInteractWithSteth() public {
        _add(PLAYER, address(0), false, true, 1, host.price(), 0);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        _expectNoTokenCalls();
        _work();
        assertGt(host.entries(PLAYER), 0);
    }

    function test_ClaimableOnlyFundingDoesNotInteractWithSteth() public {
        _add(PLAYER, address(0), true, true, 1, 0, host.price() + 1);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        _expectNoTokenCalls();
        _work();
        assertEq(host.claimableOf(PLAYER), 1);
    }

    function test_SponsoredFundingRequiresLiveOperatorApproval() public {
        _add(PLAYER, FUNDER, false, true, 1, 0, 0);
        mockStETH.mint(FUNDER, 1 ether);
        vm.startPrank(FUNDER);
        mockStETH.approve(address(game), type(uint256).max);
        game.setOperatorApproval(0, NEXT, true);
        vm.stopPrank();
        vm.prank(PLAYER);
        game.setOperatorApproval(0, FUNDER, true);
        assertFalse(_approved(game.walletIdOf(FUNDER), PLAYER));
        _expectNoTokenCalls();
        _work();
        _assertEvicted(PLAYER);
    }

    function test_OperatorApprovalIsPairScopedAndRevocableWhileLockedOrClosed() public {
        _consent(FUNDER, PLAYER);
        uint32 funderId = game.walletIdOf(FUNDER);
        assertFalse(_approved(funderId, NEXT));
        host.setLock(true);
        vm.prank(FUNDER);
        game.setAfkingFundingApproval(0, _aidCache[PLAYER], false);
        assertFalse(_approved(funderId, PLAYER));
        host.setClosed(true);
        _consent(FUNDER, PLAYER);
        assertTrue(_approved(funderId, PLAYER));
    }

    function test_WrongSpenderAllowanceCannotPay() public {
        _add(PLAYER, address(0), false, true, 1, 0, 0);
        _consent(PLAYER, PLAYER);
        mockStETH.mint(PLAYER, 1 ether);
        vm.prank(PLAYER);
        mockStETH.approve(address(afkingModule), type(uint256).max);
        _work();
        _assertEvicted(PLAYER);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
    }

    function test_LiveOperatorRevocationEvictsDespiteStoredFundingSource() public {
        _add(PLAYER, FUNDER, false, true, 1, 0, 0);
        mockStETH.mint(FUNDER, 1 ether);
        _authorize(FUNDER, PLAYER, type(uint256).max);
        vm.prank(FUNDER);
        game.setAfkingFundingApproval(0, _aidCache[PLAYER], false);
        _work();
        _assertEvicted(PLAYER);
        _consent(FUNDER, PLAYER);
        assertTrue(_approved(game.walletIdOf(FUNDER), PLAYER));
        assertEq(mockStETH.balanceOf(FUNDER), 1 ether);
    }

    function test_LiveAllowanceRevocationEvictsAndDoesNotClearOperatorApproval() public {
        _add(PLAYER, FUNDER, false, true, 1, 0, 0);
        mockStETH.mint(FUNDER, 1 ether);
        _authorize(FUNDER, PLAYER, type(uint256).max);
        vm.prank(FUNDER);
        mockStETH.approve(address(game), 0);
        _work();
        _assertEvicted(PLAYER);
        assertTrue(_approved(game.walletIdOf(FUNDER), PLAYER));
    }

    function test_SourceChangeRequiresNewWalletOperatorApproval() public {
        _add(PLAYER, FUNDER, false, true, 1, 0, 0);
        mockStETH.mint(FUNDER, 1 ether);
        mockStETH.mint(NEXT, 1 ether);
        _authorize(FUNDER, PLAYER, type(uint256).max);
        vm.prank(NEXT);
        mockStETH.approve(address(game), type(uint256).max);
        host.setSource(PLAYER, NEXT);
        _expectNoTokenCalls();
        _work();
        _assertEvicted(PLAYER);
        assertEq(mockStETH.sharesOf(FUNDER), 1 ether);
        assertEq(mockStETH.sharesOf(NEXT), 1 ether);
    }

    function test_OnlyGameCanCallAtomicPull() public {
        vm.expectRevert();
        game.pullAfkingSteth(uint32(1), FUNDER, 1);
        vm.expectRevert();
        afkingModule.pullAfkingSteth(uint32(1), FUNDER, 1);
    }

    function testFuzz_TokenRefusalExpiresButGasFailureRollsBack(uint8 operationSeed, uint8 faultSeed) public {
        _adversarial();
        _add(PLAYER, FUNDER, false, true, 1, 0, 1);
        _add(NEXT, address(0), false, true, 1, host.price(), 0);
        badToken.mint(FUNDER, 1 ether);
        _authorize(FUNDER, PLAYER, 1 ether);
        AdversarialAfkingSteth.Operation op = AdversarialAfkingSteth.Operation(bound(operationSeed, 1, 5));
        AdversarialAfkingSteth.Fault fault_ = AdversarialAfkingSteth.Fault(bound(faultSeed, 1, 4));
        badToken.configureFault(op, fault_);
        uint256 beforeSource = badToken.sharesOf(FUNDER);
        uint256 beforeGame = badToken.sharesOf(address(game));
        uint256 poolBefore = game.claimablePoolView();
        bool executionFailure = fault_ == AdversarialAfkingSteth.Fault.Malformed
            || fault_ == AdversarialAfkingSteth.Fault.BurnGas;
        if (executionFailure) {
            vm.expectRevert();
            host.subWork{gas: WORK_GAS}(WORK_GAS);
            assertGt(host.stateOf(PLAYER).setPosition, 0, "execution failure preserves membership");
            assertEq(game.claimablePoolView(), poolBefore);
            assertLt(host.stateOf(NEXT).lastAutoBoughtDay, game.currentDayView(), "following subscriber is untouched");
        } else {
            _work();
            _assertEvicted(PLAYER);
            assertGt(host.entries(NEXT), 0, "token refusal cannot block the next funded subscriber");
            assertEq(game.claimablePoolView(), poolBefore - host.price());
        }
        assertEq(badToken.sharesOf(FUNDER), beforeSource, "failed pull rolls source shares back");
        assertEq(badToken.sharesOf(address(game)), beforeGame, "failed pull rolls receipt back");
        assertEq(badToken.allowance(FUNDER, address(game)), 1 ether, "failed pull rolls allowance back");
        assertEq(badToken.transferCalls(), 0, "failed post-transfer read rolls token state back");
        assertEq(game.afkingFundingOf(FUNDER), 0);
        assertEq(host.claimableOf(PLAYER), 1);
        if (executionFailure) {
            badToken.configureFault(op, AdversarialAfkingSteth.Fault.None);
            _work();
            assertGt(host.entries(PLAYER), 0, "retry pays the original subscriber");
            assertGt(host.entries(NEXT), 0);
        }
    }

    function testFuzz_InvalidTransferReceiptsRollBack(uint8 faultSeed) public {
        _adversarial();
        _add(PLAYER, address(0), false, false, 1, 0, 0);
        badToken.mint(PLAYER, 1 ether);
        _authorize(PLAYER, PLAYER, 1 ether);
        badToken.configureFault(
            AdversarialAfkingSteth.Operation.Transfer, AdversarialAfkingSteth.Fault(bound(faultSeed, 5, 7))
        );
        _work();
        _assertEvicted(PLAYER);
        assertEq(badToken.sharesOf(PLAYER), 1 ether);
        assertEq(badToken.allowance(PLAYER, address(game)), 1 ether);
        assertEq(host.pendingBoxes(), 0);
    }

    function test_RoundingCreditsExcessForOneWeiShortfall() public {
        _adversarial();
        _add(PLAYER, FUNDER, false, true, 1, host.price() - 1, 0);
        badToken.configureRatio(3 ether, 2 ether);
        badToken.configureShares(FUNDER, 2 ether);
        badToken.configureShares(address(game), 1);
        _authorize(FUNDER, PLAYER, 1);
        uint256 beforeBacking = badToken.balanceOf(address(game));
        _work();
        assertEq(
            badToken.balanceOf(address(game)) - beforeBacking, 2, "recipient delta can exceed pooled return by one"
        );
        assertEq(game.afkingFundingOf(FUNDER), 1, "recipient rounding excess belongs to funder");
        assertEq(badToken.allowance(FUNDER, address(game)), 0, "allowance spends returned pooled value");
        assertGt(host.entries(PLAYER), 0);
    }

    function test_RoundingCanRequireAllowanceAboveShortfall() public {
        _adversarial();
        _add(PLAYER, FUNDER, false, true, 1, host.price() - 1, 0);
        badToken.configureRatio(5 ether, 2 ether);
        badToken.configureShares(FUNDER, 2 ether);
        _authorize(FUNDER, PLAYER, 1);
        _work();
        _assertEvicted(PLAYER);
        assertEq(badToken.allowance(FUNDER, address(game)), 1);
        assertEq(game.afkingFundingOf(FUNDER), host.price() - 1);
    }

    function test_RoundingWithNonzeroShareQuotePaysMinimumShares() public {
        _adversarial();
        uint256 shortfall = 5;
        _add(PLAYER, FUNDER, false, true, 1, host.price() - shortfall, 0);
        badToken.configureRatio(3 ether, 2 ether);
        badToken.configureShares(FUNDER, 2 ether);
        _authorize(FUNDER, PLAYER, 6);
        _work();
        assertEq(badToken.sharesOf(FUNDER), 2 ether - 4);
        assertEq(game.afkingFundingOf(FUNDER), 1);
        assertEq(badToken.allowance(FUNDER, address(game)), 0);
    }

    function test_AlreadyBoughtPendingAndCanceledNeverPull() public {
        uint24 today = game.currentDayView();
        _add(PLAYER, address(0), false, true, 1, 0, 0);
        _add(NEXT, address(0), false, false, 1, 0, 0);
        _add(FUNDER, address(0), false, true, 0, 0, 0);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        _authorize(NEXT, NEXT, type(uint256).max);
        _authorize(FUNDER, FUNDER, type(uint256).max);
        host.setMarkers(PLAYER, today, today);
        host.setMarkers(NEXT, today - 1, today - 2);
        _expectNoTokenCalls();
        _work();
        assertGt(host.memberOf(PLAYER), 0);
        assertGt(host.memberOf(NEXT), 0);
        assertEq(host.memberOf(FUNDER), 0);
    }

    function test_ProtocolSubscriptionKeepsExistingFundingFailureExemption() public {
        _add(ContractAddresses.VAULT, address(0), false, false, 1, 0, 0);
        _add(ContractAddresses.SDGNRS, address(0), false, false, 1, 0, 0);
        mockStETH.mint(ContractAddresses.VAULT, 1 ether);
        mockStETH.mint(ContractAddresses.SDGNRS, 1 ether);
        _authorize(ContractAddresses.VAULT, ContractAddresses.VAULT, type(uint256).max);
        _authorize(ContractAddresses.SDGNRS, ContractAddresses.SDGNRS, type(uint256).max);
        _expectNoTokenCalls();
        _work();
        assertGt(host.memberOf(ContractAddresses.VAULT), 0);
        assertGt(host.memberOf(ContractAddresses.SDGNRS), 0);
        assertEq(mockStETH.balanceOf(ContractAddresses.VAULT), 1 ether, "vault backing remains reserved");
        assertEq(mockStETH.balanceOf(ContractAddresses.SDGNRS), 1 ether, "redemption backing remains reserved");
        assertEq(mockStETH.allowance(ContractAddresses.VAULT, address(game)), type(uint256).max);
        assertEq(mockStETH.allowance(ContractAddresses.SDGNRS, address(game)), type(uint256).max);
    }

    function testFuzz_ProtocolFundingWalletCannotSponsorStethPull(bool sdgnrsSource) public {
        address source = sdgnrsSource ? ContractAddresses.SDGNRS : ContractAddresses.VAULT;
        _add(PLAYER, source, false, true, 1, 0, 0);
        mockStETH.mint(source, 1 ether);
        _authorize(source, PLAYER, type(uint256).max);
        _expectNoTokenCalls();
        _work();
        _assertEvicted(PLAYER);
        assertEq(mockStETH.balanceOf(source), 1 ether, "operator approval cannot release protocol reserves");
        assertEq(mockStETH.allowance(source, address(game)), type(uint256).max);
    }

    function testFuzz_AtomicPullRefusesProtocolFundingWallet(bool sdgnrsSource) public {
        address source = sdgnrsSource ? ContractAddresses.SDGNRS : ContractAddresses.VAULT;
        _add(PLAYER, source, false, true, 1, 0, 0);
        mockStETH.mint(source, 1 ether);
        _authorize(source, PLAYER, type(uint256).max);
        _expectNoTokenCalls();
        uint32 subscriber = game.walletIdOf(PLAYER);
        vm.prank(address(game));
        vm.expectRevert(abi.encodeWithSignature("AfkingStethPullFailed()"));
        game.pullAfkingSteth(subscriber, source, 1);
        assertEq(mockStETH.balanceOf(source), 1 ether);
    }

    function test_ClosedGameDoesNotAttemptFallback() public {
        _add(PLAYER, address(0), false, true, 1, 0, 0);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        vm.warp(block.timestamp + 100 days);
        _expectNoTokenCalls();
        MineFlipGas.Result memory result = host.subWork(WORK_GAS);
        assertFalse(result.progressed);
        assertGt(host.memberOf(PLAYER), 0, "terminal drain owns closed-game membership");
        uint256 seat = _grantSeat(PLAYER);
        vm.prank(PLAYER);
        vm.expectRevert(abi.encodeWithSignature("GameOver()"));
        game.subscribe(0, false, true, 1, 0, seat);
    }

    function test_NewSubscribeAndActiveCoverBuyUseFallback() public {
        uint256 seat = _grantSeat(PLAYER);
        _aid(PLAYER);
        uint32 funderId = _aid(FUNDER); // a funding source must already hold a wallet ID
        mockStETH.mint(FUNDER, 1 ether);
        _authorize(FUNDER, PLAYER, type(uint256).max);
        vm.prank(PLAYER);
        game.subscribe(0, false, true, 1, funderId, seat);
        assertEq(mockStETH.balanceOf(FUNDER), 1 ether - host.price());
        uint256 firstEntries = host.entries(PLAYER);
        vm.warp(block.timestamp + 1 days);
        host.nextDay();
        vm.prank(PLAYER);
        game.subscribe(0, false, true, 2, funderId, 0);
        assertEq(mockStETH.balanceOf(FUNDER), 1 ether - 3 * host.price());
        assertGt(host.entries(PLAYER), firstEntries);
        assertEq(host.stateOf(PLAYER).lastAutoBoughtDay, game.currentDayView());
    }

    function test_NewSubscribeFailureRevertsButActiveUnfundedCoverBuySkips() public {
        uint256 seat = _grantSeat(PLAYER);
        _aid(PLAYER);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        vm.prank(PLAYER);
        vm.expectRevert(abi.encodeWithSignature("MustPurchaseToBeginAfking()"));
        game.subscribe(0, false, true, 1, 0, seat);
        assertEq(host.memberOf(PLAYER), 0);
        _add(PLAYER, address(0), false, true, 1, 0, 0);
        vm.prank(PLAYER);
        game.subscribe(0, false, true, 2, 0, seat);
        assertGt(host.memberOf(PLAYER), 0, "unpaid optional cover buy does not evict");
        assertEq(host.stateOf(PLAYER).lastAutoBoughtDay, game.currentDayView() - 1);
        _work();
        _assertEvicted(PLAYER);
    }

    function test_AllowancePersistsThroughCancellationAndReenrollment() public {
        uint256 seat = _grantSeat(PLAYER);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        _aid(PLAYER);
        vm.prank(PLAYER);
        game.subscribe(0, false, true, 1, 0, seat);
        vm.prank(PLAYER);
        game.subscribe(0, false, true, 0, 0, 0);
        uint256 seat2 = _grantSeat(PLAYER);
        vm.prank(PLAYER);
        game.subscribe(0, false, true, 1, 0, seat2);
        assertEq(mockStETH.allowance(PLAYER, address(game)), type(uint256).max);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether - host.price(), "same-day re-enrollment does not double-pay");
    }

    function test_AtomicPullRechecksConfiguredSource() public {
        _add(PLAYER, FUNDER, false, true, 1, 0, 0);
        _authorize(NEXT, PLAYER, type(uint256).max);
        uint32 subscriber = game.walletIdOf(PLAYER);
        vm.prank(address(game));
        vm.expectRevert(abi.encodeWithSignature("AfkingStethPullFailed()"));
        game.pullAfkingSteth(subscriber, NEXT, 1);
    }

    function test_PoolOverflowRejectsPullWithoutTruncatingCredit() public {
        _add(PLAYER, address(0), false, true, 1, 0, 0);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        host.setPool(type(uint128).max);
        _work();
        _assertEvicted(PLAYER);
        assertEq(game.claimablePoolView(), type(uint128).max);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
    }

    function test_ExtremeCalibrationFundsExactlyOneSubscriberThenResumes() public {
        _add(PLAYER, address(0), false, true, 1, 0, 0);
        _add(NEXT, address(0), false, true, 1, host.price(), 0);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        uint256 budget = MineFlipGas.budget(WORK_GAS, type(uint32).max, true);
        MineFlipGas.Result memory result = host.subWork{gas: WORK_GAS}(budget);
        assertTrue(result.progressed);
        assertGt(host.entries(PLAYER), 0);
        assertEq(host.entries(NEXT), 0);
        result = host.subWork{gas: WORK_GAS}(budget);
        assertTrue(result.progressed);
        assertGt(host.entries(NEXT), 0);
    }

    function test_LowWorkerAllowanceDefersBeforeAttemptThenSucceeds() public {
        _add(PLAYER, address(0), false, true, 1, 0, 0);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, PLAYER, type(uint256).max);
        MineFlipGas.Result memory deferred =
            host.subWork(GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS - 1);
        assertFalse(deferred.progressed);
        assertFalse(deferred.done);
        assertGt(host.memberOf(PLAYER), 0);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
        _work();
        assertGt(host.entries(PLAYER), 0);
    }
}
