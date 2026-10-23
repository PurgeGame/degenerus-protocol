// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {NativeFailureExport, NativeFailureProbe} from "../helpers/NativeFailureExport.sol";
import {SelectorFaultProxy} from "./GameExternalIsolation.t.sol";
import {IStETH} from "../../contracts/interfaces/IStETH.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {AfkingStethHost, AdversarialAfkingSteth} from "./helpers/AfkingStethFixture.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @dev Registers a smurf of `owner` the way the mint module records one, without a purchase.
contract SmurfHost is AfkingStethHost {
    function makeSmurf(address owner) external returns (uint32 smurfId) {
        uint32 ownerId = _seedWallet(owner);
        smurfId = uint32(wallets.length);
        wallets.push(uint256(ownerId) << 160);
        mintPacked_[smurfId] = uint256(1) << BitPackingLib.SMURF_FLAG_SHIFT;
        balancesPacked[smurfId] = 1;
        _smurfWords[ownerId][0] = smurfId;
        mintPacked_[ownerId] = BitPackingLib.setPacked(
            mintPacked_[ownerId], BitPackingLib.SMURF_COUNT_SHIFT, BitPackingLib.MASK_16, 1
        );
    }
}

contract AfkingStethFundingTest is DeployProtocol, NativeFailureExport {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf_g3120(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }


    SmurfHost internal host;
    AdversarialAfkingSteth internal badToken;
    address internal constant PLAYER = address(0xA11CE);
    address internal constant NEXT = address(0xB0B);
    uint256 internal constant WORK_GAS = 6_000_000;

    event SubscriptionExpired(uint32 indexed player, uint8 reason);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 2 days);
        vm.etch(address(game), type(SmurfHost).runtimeCode);
        host = SmurfHost(payable(address(game)));
        vm.deal(address(game), 100 ether);
        host.prepare();
    }

    function _flags() internal view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_PROTOCOL_FLAGS)))
            >> (8 * GameSlots.AFKING_PROTOCOL_FLAGS_OFFSET));
    }

    function _authorize(address player, uint256 allowance_) internal {
        vm.prank(player);
        mockStETH.approve(address(game), allowance_);
    }

    function _adversarial() internal {
        vm.etch(address(mockStETH), type(AdversarialAfkingSteth).runtimeCode);
        badToken = AdversarialAfkingSteth(payable(address(mockStETH)));
    }

    function _work() internal returns (MineFlipGas.Result memory result) {
        // A hostile token may spend the whole offered allowance. Its failed
        // member is checkpointed; the next funded member resumes next call.
        for (uint256 i; i < 4 && !result.done; ++i) {
            result = host.subWork{gas: WORK_GAS}(WORK_GAS);
            assertTrue(result.progressed || result.done, "funded retry must progress");
        }
        assertTrue(result.done, "bounded retries drain the cohort");
    }

    function _add(address player, bool tickets, uint8 quantity, uint256 prepaid, uint256 claimable) internal {
        host.add(player, tickets, quantity, prepaid, claimable);
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
        assertEq(host.stateOf(player).position1, 0, "no record survives");
        assertEq(host.entries(player), 0, "no tickets delivered");
    }

    function testFuzz_OnlyResidualPaidClaimableThenPrepaidThenSteth(
        bool tickets,
        uint8 quantitySeed,
        uint96 prepaidSeed,
        uint96 claimSeed
    ) public {
        uint8 quantity = uint8(bound(quantitySeed, 1, 8));
        uint256 cost = host.price() * quantity;
        uint256 prepaid = bound(prepaidSeed, 0, cost - 1);
        uint256 claimable = bound(claimSeed, 0, cost - prepaid - 1);
        _add(PLAYER, tickets, quantity, prepaid, claimable + 1);
        mockStETH.mint(PLAYER, 100 ether);
        uint256 missing = cost - prepaid - claimable;
        _authorize(PLAYER, missing);
        uint256 backingBefore = mockStETH.balanceOf(address(game));
        uint256 poolBefore = game.claimablePoolView();
        uint256 prizesBefore = game.nextPrizePoolView() + game.futurePrizePoolView();
        _work();
        assertEq(mockStETH.balanceOf(address(game)) - backingBefore, missing, "only original residual pulled");
        assertEq(mockStETH.allowance(PLAYER, address(game)), 0, "GAME consumes exact finite allowance");
        assertEq(host.claimableOf(PLAYER), 1, "original claimable slice retained with sentinel");
        assertEq(game.afkingFundingOf(PLAYER), 0, "original prepaid slice consumed");
        assertEq(game.claimablePoolView(), poolBefore + missing - cost, "receipt and both debits conserve liabilities");
        assertEq(game.nextPrizePoolView() + game.futurePrizePoolView(), prizesBefore + cost);
        assertGt(host.memberOf(PLAYER), 0);
        assertEq(host.endpoint(), game.currentDayView(), "the pass completed");
        if (tickets) assertGt(host.entries(PLAYER), 0);
        else assertEq(host.pendingBoxes(), 1);
    }

    function test_InternallyFundedDoesNotInteractWithSteth() public {
        _add(PLAYER, true, 1, host.price(), 0);
        _authorize(PLAYER, type(uint256).max);
        _expectNoTokenCalls();
        _work();
        assertGt(host.entries(PLAYER), 0);
    }

    function test_ClaimableOnlyFundingDoesNotInteractWithSteth() public {
        _add(PLAYER, true, 1, 0, host.price() + 1);
        _authorize(PLAYER, type(uint256).max);
        _expectNoTokenCalls();
        _work();
        assertEq(host.claimableOf(PLAYER), 1);
    }

    function test_WrongSpenderAllowanceCannotPay() public {
        _add(PLAYER, true, 1, 0, 0);
        mockStETH.mint(PLAYER, 1 ether);
        vm.prank(PLAYER);
        mockStETH.approve(address(afkingModule), type(uint256).max);
        _work();
        _assertEvicted(PLAYER);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
    }

    function test_AllowanceRevocationEvicts() public {
        _add(PLAYER, true, 1, 0, 0);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, type(uint256).max);
        vm.prank(PLAYER);
        mockStETH.approve(address(game), 0);
        _work();
        _assertEvicted(PLAYER);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
    }

    /// @notice An unfunded ordinary member expires and the rewards it has not settled are
    ///         forfeited: no FLIP reaches the member or its upline.
    function test_UnfundedExpiryForfeitsUnsettledRewards() public {
        _add(PLAYER, true, 1, host.price() * 2, 0);
        uint32 id = game.walletIdOf_g3120(PLAYER);
        _work();
        assertEq(host.stateOf(PLAYER).checkpointDay + 1, host.endpoint(), "one unsettled day is owed");
        host.setBalances(PLAYER, 0, 0);
        vm.warp(block.timestamp + 1 days);
        host.nextDay();
        uint256 stakeBefore = coinflip.coinflipAmount(PLAYER);
        vm.expectEmit(true, false, false, true, address(game));
        emit SubscriptionExpired(id, 1);
        _work();
        assertEq(host.memberOf(PLAYER), 0, "unpaid member removed");
        assertEq(coinflip.coinflipAmount(PLAYER), stakeBefore, "the unsettled day is forfeited");
    }

    /// @notice A smurf's residual is pulled from its owner's stETH, the subscriber's payee.
    function test_SmurfFallbackPullsFromTheOwner() public {
        host.subscriptionWindow();
        uint32 smurfId = host.makeSmurf(PLAYER);
        uint256 seat = _grantSeat(PLAYER);
        vm.prank(PLAYER);
        game.subscribe(smurfId, true, 1, seat);
        mockStETH.mint(PLAYER, 1 ether);
        mockStETH.mint(NEXT, 1 ether);
        _authorize(PLAYER, type(uint256).max);
        _authorize(NEXT, type(uint256).max);
        vm.warp(block.timestamp + 1 days);
        host.nextDay();
        uint256 ownerShares = mockStETH.sharesOf(PLAYER);
        _work();
        assertLt(mockStETH.sharesOf(PLAYER), ownerShares, "the owner paid");
        assertEq(mockStETH.sharesOf(NEXT), 1 ether, "no other holder is touched");
        (, uint256 position1) = GameSlotKeys.subLane(address(game), smurfId);
        assertGt(position1, 0, "the smurf stays subscribed");
        assertEq(host.memberOf(PLAYER), 0, "the owner is not itself subscribed");
    }

    function test_OnlyGameCanCallAtomicPull() public {
        vm.expectRevert(bytes4(keccak256("OnlySelf()")));
        game.pullAfkingSteth(uint32(1), PLAYER, 1);
        vm.expectRevert(bytes4(keccak256("E()")));
        afkingModule.pullAfkingSteth(uint32(1), PLAYER, 1);
    }

    function testFuzz_TokenFailureRollsBackPullAndExpiresUnfundedMember(uint8 operationSeed, uint8 faultSeed) public {
        _adversarial();
        _add(PLAYER, true, 1, 0, 1);
        _add(NEXT, true, 1, host.price(), 0);
        badToken.mint(PLAYER, 1 ether);
        _authorize(PLAYER, 1 ether);
        AdversarialAfkingSteth.Operation op = AdversarialAfkingSteth.Operation(bound(operationSeed, 1, 5));
        AdversarialAfkingSteth.Fault fault_ = AdversarialAfkingSteth.Fault(bound(faultSeed, 1, 4));
        badToken.configureFault(op, fault_);
        uint256 beforeSource = badToken.sharesOf(PLAYER);
        uint256 beforeGame = badToken.sharesOf(address(game));
        uint256 poolBefore = game.claimablePoolView();
        _work();
        _assertEvicted(PLAYER);
        assertGt(host.entries(NEXT), 0, "token failure cannot block the next funded subscriber");
        assertEq(game.claimablePoolView(), poolBefore - host.price());
        assertEq(badToken.sharesOf(PLAYER), beforeSource, "failed pull rolls source shares back");
        assertEq(badToken.sharesOf(address(game)), beforeGame, "failed pull rolls receipt back");
        assertEq(badToken.allowance(PLAYER, address(game)), 1 ether, "failed pull rolls allowance back");
        assertEq(badToken.transferCalls(), 0, "failed post-transfer read rolls token state back");
        assertEq(game.afkingFundingOf(PLAYER), 0);
        assertEq(host.claimableOf(PLAYER), 1);

    }

    function test_EveryFundingSelectorRefusesAllExternalFailuresWithoutBlockingNextMember() public {
        bytes4[6] memory selectors = [IStETH.balanceOf.selector, IStETH.getSharesByPooledEth.selector,
            IStETH.getPooledEthByShares.selector, IStETH.sharesOf.selector, IStETH.allowance.selector,
            IStETH.transferSharesFrom.selector];
        address implementation = address(0xF004);
        vm.etch(implementation, address(mockStETH).code);
        for (uint256 i; i < selectors.length; ++i) for (uint8 mode = 1; mode <= 5; ++mode) {
            uint256 snap = vm.snapshotState();
            _add(PLAYER, true, 1, 0, 1);
            _add(NEXT, true, 1, host.price(), 0);
            mockStETH.mint(PLAYER, 1 ether); _authorize(PLAYER, 1 ether);
            vm.etch(address(mockStETH), address(new SelectorFaultProxy(implementation, selectors[i], mode)).code);
            _work();
            assertGt(host.entries(NEXT), 0);
            if (mode == 4) assertGt(host.entries(PLAYER), 0, "valid oversized prefix funds normally");
            else {
                _assertEvicted(PLAYER);
                // Restore normal reads to inspect the rolled-back dependency state.
                vm.etch(address(mockStETH), implementation.code);
                assertEq(mockStETH.sharesOf(PLAYER), 1 ether);
                assertEq(mockStETH.allowance(PLAYER, address(game)), 1 ether);
            }
            vm.revertToState(snap);
        }
    }

    function test_PostTransferEmptyAndSpoofedMeteringFailuresRollbackThenExpire() public {
        for (uint8 m = 8; m <= 9; ++m) {
            uint256 snap = vm.snapshotState();
            _adversarial(); _add(PLAYER, true, 1, 0, 1);
            badToken.mint(PLAYER, 1 ether); _authorize(PLAYER, 1 ether);
            badToken.configureFault(AdversarialAfkingSteth.Operation.BalanceAfter,
                AdversarialAfkingSteth.Fault(m));
            _work(); _assertEvicted(PLAYER);
            assertEq(badToken.sharesOf(PLAYER), 1 ether);
            assertEq(badToken.transferCalls(), 0);
            vm.revertToState(snap);
        }
    }

    function test_InnerReadUnderfundingCannotExpireMemberAndRetrySucceeds() public {
        _add(PLAYER, false, 1, 0, 1);
        mockStETH.mint(PLAYER, 1 ether); _authorize(PLAYER, 1 ether);
        address implementation = address(0xF007);
        vm.etch(implementation, address(mockStETH).code);
        vm.etch(address(mockStETH), address(new SelectorFaultProxy(implementation, IStETH.balanceOf.selector, 12)).code);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.subWork{gas: WORK_GAS}(MineFlipGas.budget(WORK_GAS, 10_000, true));
        assertGt(host.memberOf(PLAYER), 0, "nested underfunding preserves membership");
        vm.etch(address(mockStETH), implementation.code);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
        _work();
        assertGt(host.memberOf(PLAYER), 0, "funded retry keeps the subscription");
        assertLt(mockStETH.balanceOf(PLAYER), 1 ether, "retry funds the buy");
    }

    function test_OuterPullUnderfundingCannotExpireMember() public {
        _add(PLAYER, false, 1, 0, 1);
        mockStETH.mint(PLAYER, 1 ether); _authorize(PLAYER, 1 ether);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.subWork{gas: 900_000}(MineFlipGas.budget(900_000, 10_000, true));
        assertGt(host.memberOf(PLAYER), 0);
        assertEq(mockStETH.sharesOf(PLAYER), 1 ether);
    }

    function testFuzz_InvalidTransferReceiptsRollBack(uint8 faultSeed) public {
        _adversarial();
        _add(PLAYER, false, 1, 0, 0);
        badToken.mint(PLAYER, 1 ether);
        _authorize(PLAYER, 1 ether);
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
        _add(PLAYER, true, 1, host.price() - 1, 0);
        badToken.configureRatio(3 ether, 2 ether);
        badToken.configureShares(PLAYER, 2 ether);
        badToken.configureShares(address(game), 1);
        _authorize(PLAYER, 1);
        uint256 beforeBacking = badToken.balanceOf(address(game));
        _work();
        assertEq(
            badToken.balanceOf(address(game)) - beforeBacking, 2, "recipient delta can exceed pooled return by one"
        );
        assertEq(game.afkingFundingOf(PLAYER), 1, "recipient rounding excess stays in the prepaid balance");
        assertEq(badToken.allowance(PLAYER, address(game)), 0, "allowance spends returned pooled value");
        assertGt(host.entries(PLAYER), 0);
    }

    function test_RoundingCanRequireAllowanceAboveShortfall() public {
        _adversarial();
        _add(PLAYER, true, 1, host.price() - 1, 0);
        badToken.configureRatio(5 ether, 2 ether);
        badToken.configureShares(PLAYER, 2 ether);
        _authorize(PLAYER, 1);
        _work();
        _assertEvicted(PLAYER);
        assertEq(badToken.allowance(PLAYER, address(game)), 1);
        assertEq(game.afkingFundingOf(PLAYER), host.price() - 1);
    }

    function test_RoundingWithNonzeroShareQuotePaysMinimumShares() public {
        _adversarial();
        uint256 shortfall = 5;
        _add(PLAYER, true, 1, host.price() - shortfall, 0);
        badToken.configureRatio(3 ether, 2 ether);
        badToken.configureShares(PLAYER, 2 ether);
        _authorize(PLAYER, 6);
        _work();
        assertEq(badToken.sharesOf(PLAYER), 2 ether - 4);
        assertEq(game.afkingFundingOf(PLAYER), 1);
        assertEq(badToken.allowance(PLAYER, address(game)), 0);
    }

    function test_CompletedPassAndPendingReadNeverPull() public {
        _expectNoTokenCalls();
        _work();
        assertTrue(host.subWork(WORK_GAS).done, "completed pass does not replay");
        host.nextDay();
        host.closeReadForTest();
        assertFalse(host.subWork(WORK_GAS).progressed, "prior read blocks new preparation");
    }

    /// @notice A protocol seat that cannot pay is paused, never pulled from and never removed.
    function test_ProtocolSeatNeverPullsStethAndPausesWhenUnfunded() public {
        _add(ContractAddresses.VAULT, false, 1, 0, 0);
        _add(ContractAddresses.SDGNRS, false, 1, 0, 0);
        mockStETH.mint(ContractAddresses.VAULT, 1 ether);
        mockStETH.mint(ContractAddresses.SDGNRS, 1 ether);
        vm.prank(ContractAddresses.VAULT);
        mockStETH.approve(address(game), type(uint256).max);
        vm.prank(ContractAddresses.SDGNRS);
        mockStETH.approve(address(game), type(uint256).max);
        _expectNoTokenCalls();
        _work();
        assertGt(host.memberOf(ContractAddresses.VAULT), 0);
        assertGt(host.memberOf(ContractAddresses.SDGNRS), 0);
        assertTrue(_flags() & 8 != 0, "unfunded Vault is paused");
        assertTrue(_flags() & 16 != 0, "unfunded sDGNRS is paused");
        assertEq(mockStETH.balanceOf(ContractAddresses.VAULT), 1 ether, "vault backing remains reserved");
        assertEq(mockStETH.balanceOf(ContractAddresses.SDGNRS), 1 ether, "redemption backing remains reserved");
        assertEq(mockStETH.allowance(ContractAddresses.VAULT, address(game)), type(uint256).max);
        assertEq(mockStETH.allowance(ContractAddresses.SDGNRS, address(game)), type(uint256).max);
    }

    function testFuzz_AtomicPullRefusesProtocolFundingWallet(bool sdgnrsSource) public {
        address source = sdgnrsSource ? ContractAddresses.SDGNRS : ContractAddresses.VAULT;
        _add(PLAYER, true, 1, 0, 0);
        mockStETH.mint(source, 1 ether);
        vm.prank(source);
        mockStETH.approve(address(game), type(uint256).max);
        _expectNoTokenCalls();
        uint32 subscriber = game.walletIdOf_g3120(PLAYER);
        vm.prank(address(game));
        vm.expectRevert(abi.encodeWithSignature("AfkingStethPullFailed()"));
        game.pullAfkingSteth(subscriber, source, 1);
        assertEq(mockStETH.balanceOf(source), 1 ether);
    }

    function test_ClosedGameDoesNotAttemptFallback() public {
        _add(PLAYER, true, 1, 0, 0);
        _authorize(PLAYER, type(uint256).max);
        vm.warp(block.timestamp + 100 days);
        _expectNoTokenCalls();
        MineFlipGas.Result memory result = host.subWork(WORK_GAS);
        assertFalse(result.progressed);
        assertGt(host.memberOf(PLAYER), 0, "terminal drain owns closed-game membership");
        uint256 seat = _grantSeat(PLAYER);
        vm.prank(PLAYER);
        vm.expectRevert(abi.encodeWithSignature("GameOver()"));
        game.subscribe(0, true, 1, seat);
    }

    /// @notice Signup buys nothing and pulls nothing; the next daily pass pays the cost from the
    ///         subscriber's own stETH, and a later change buys nothing.
    function test_SignupPullsNothingAndNextDailyBuyUsesFallback() public {
        host.subscriptionWindow();
        uint256 seat = _grantSeat(PLAYER);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, type(uint256).max);
        vm.prank(PLAYER);
        game.subscribe(0, true, 1, seat);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether, "signup pulls nothing");
        assertEq(host.entries(PLAYER), 0, "signup buys nothing");
        vm.warp(block.timestamp + 1 days);
        host.nextDay();
        vm.prank(PLAYER);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        game.subscribe(0, true, 2, 0);
        _work();
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether - host.price(), "the daily buy paid from the payee");
        assertGt(host.entries(PLAYER), 0);
        host.subscriptionWindow();
        vm.prank(PLAYER);
        game.subscribe(0, true, 2, 0);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether - host.price(), "a change after the daily purchase buys nothing");
        assertEq(host.endpoint(), game.currentDayView());
    }

    function test_SameDayReenrollmentPaysNothingAndKeepsAllowance() public {
        host.subscriptionWindow();
        uint256 seat = _grantSeat(PLAYER);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, type(uint256).max);
        vm.prank(PLAYER);
        game.subscribe(0, true, 1, seat);
        vm.prank(PLAYER);
        game.subscribe(0, true, 0, 0);
        uint256 seat2 = _grantSeat(PLAYER);
        vm.prank(PLAYER);
        game.subscribe(0, true, 1, seat2);
        assertEq(mockStETH.allowance(PLAYER, address(game)), type(uint256).max);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether, "same-day re-enrollment pays nothing");
    }

    function test_AtomicPullRechecksPayee() public {
        _add(PLAYER, true, 1, 0, 0);
        _authorize(NEXT, type(uint256).max);
        uint32 subscriber = game.walletIdOf_g3120(PLAYER);
        vm.prank(address(game));
        vm.expectRevert(abi.encodeWithSignature("AfkingStethPullFailed()"));
        game.pullAfkingSteth(subscriber, NEXT, 1);
    }

    function test_PoolOverflowRejectsPullWithoutTruncatingCredit() public {
        _add(PLAYER, true, 1, 0, 0);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, type(uint256).max);
        host.setPool(type(uint128).max);
        _work();
        _assertEvicted(PLAYER);
        assertEq(game.claimablePoolView(), type(uint128).max);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
    }

    function test_ExtremeCalibrationCannotBypassDependencyMinimumAndRetrySucceeds() public {
        _add(PLAYER, true, 1, 0, 0);
        _add(NEXT, true, 1, host.price(), 0);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, type(uint256).max);
        uint256 budget = MineFlipGas.budget(WORK_GAS, type(uint32).max, true);
        MineFlipGas.Result memory result = host.subWork{gas: WORK_GAS}(budget);
        assertTrue(result.progressed); // Empty box section is still mandatory progress.
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.subWork{gas: WORK_GAS}(budget);
        assertGt(host.memberOf(PLAYER), 0, "underfunding cannot expire a subscriber");
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
        assertEq(host.entries(PLAYER), 0);
        _work();
        assertGt(host.entries(PLAYER), 0);
        assertGt(host.entries(NEXT), 0);
    }

    function test_LowWorkerAllowanceDefersBeforeAttemptThenSucceeds() public {
        _add(PLAYER, true, 1, 0, 0);
        mockStETH.mint(PLAYER, 1 ether);
        _authorize(PLAYER, type(uint256).max);
        MineFlipGas.Result memory deferred =
            host.subWork(GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS - 1);
        assertTrue(deferred.progressed, "empty box section advanced to tickets");
        assertFalse(deferred.done);
        assertGt(host.memberOf(PLAYER), 0);
        assertEq(mockStETH.balanceOf(PLAYER), 1 ether);
        _work();
        assertGt(host.entries(PLAYER), 0);
    }
    function test_NativeOuterFundingRollbackBoundary() public {
        NativeFailureProbe probe = new NativeFailureProbe();
        address implementation = address(0xF005);
        vm.etch(implementation, address(game).code);
        uint8[7] memory modes = [uint8(0), 1, 2, 5, 8, 9, 10];
        for (uint256 i; i < modes.length; ++i) {
            uint256 snap = vm.snapshotState();
            _add(PLAYER, true, 1, 0, 1);
            _add(NEXT, true, 1, host.price(), 0);
            mockStETH.mint(PLAYER, 1 ether); _authorize(PLAYER, 1 ether);
            vm.etch(address(game), address(new SelectorFaultProxy(implementation,
                bytes4(keccak256("pullAfkingSteth(uint32,address,uint256)")), modes[i])).code);
            if (i == 0) _nativeCheckedFixture("afking-low", address(this), address(probe),
                abi.encodeCall(probe.invoke, (address(game), abi.encodeCall(host.subWork, (WORK_GAS)), 900_000)));
            _nativeCheckedFixture(string.concat("afking-", vm.toString(modes[i])), address(this), address(probe),
                abi.encodeCall(probe.invoke, (address(game), abi.encodeCall(host.subWork, (WORK_GAS)), WORK_GAS)));
            require(vm.revertToState(snap));
            vm.deleteStateSnapshot(snap);
        }
    }

    function test_NativeEveryStethFundingSite() public {
        uint8[6] memory modes = [uint8(1), 2, 8, 9, 10, 12];
        address implementation = address(0xF006);
        vm.etch(implementation, address(mockStETH).code);
        NativeFailureProbe probe = new NativeFailureProbe();
        for (uint256 site; site < 6; ++site) for (uint256 i; i < modes.length; ++i) {
            this.exportNativeStethFundingCase(site, modes[i], implementation, probe);
        }
    }

    function exportNativeStethFundingCase(uint256 site, uint8 mode, address implementation, NativeFailureProbe probe) external {
        require(msg.sender == address(this));
        bytes4[6] memory selectors = [IStETH.balanceOf.selector, IStETH.getSharesByPooledEth.selector,
            IStETH.getPooledEthByShares.selector, IStETH.sharesOf.selector, IStETH.allowance.selector,
            IStETH.transferSharesFrom.selector];
        uint256 snap = vm.snapshotState();
        _add(PLAYER, true, 1, 0, 1);
        _add(NEXT, true, 1, host.price(), 0);
        mockStETH.mint(PLAYER, 1 ether); _authorize(PLAYER, 1 ether);
        vm.etch(address(mockStETH), address(new SelectorFaultProxy(implementation, selectors[site], mode)).code);
        _nativeCheckedFixture(string.concat("steth-fund-", vm.toString(site), "-", vm.toString(mode)),
            address(this), address(probe), abi.encodeCall(probe.invoke,
                (address(game), abi.encodeCall(host.subWork, (WORK_GAS)), WORK_GAS)));
        require(vm.revertToState(snap)); vm.deleteStateSnapshot(snap);
    }

}
