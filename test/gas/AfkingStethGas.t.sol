// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {SubscriberNativeGasHost} from "./SubscriberAfkingNativeGas.t.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {AdversarialAfkingSteth} from "../fuzz/helpers/AfkingStethFixture.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Only input preparation and gross gas metering are test-only. The measured
///      worker, GAME self-call dispatcher, delivery and eviction are production code.
contract AfkingStethGasHost is SubscriberNativeGasHost {
    function addStethSubscriber(address player, bool tickets) external {
        uint32 subId = _seedWallet(player);
        _seedSubscriber(subId, tickets);
        uint256 position = _subPosition1(subId) - 1;
        uint24 yesterday = _afkingResetDay - 1;
        uint256 lane = _subLaneAt(position) | (uint256(SUB_MAX_QUANTITY - 1) << SUB_QTY_SHIFT);
        // A mature run exercises the century-shield handback on eviction.
        _setSubLaneAt(position, _withSubCheckpoint(lane, yesterday, 300));
        _setSubRunStart(subId, yesterday);
    }

    function creditSource(address source, uint256 prepaid, bool sentinel) external {
        if (prepaid != 0) _creditAfkingValue(_seedWallet(source), prepaid);
        if (sentinel) {
            _creditClaimable(_seedWallet(source), 1);
            ++claimablePool;
        }
    }

    function fundingOf(address source) external view returns (uint256) { return _afkingOf(_walletIdOf(source)); }
    function cursor() external view returns (uint256) { return _subCursor; }

    function measuredSubWork(uint256 allowance)
        external returns (MineFlipGas.Result memory result, uint256 grossGas)
    {
        bytes memory data = abi.encodeWithSignature("runSubscriberWork(uint24,uint256)", _afkingResetDay, allowance);
        uint256 beforeGas = gasleft();
        (bool ok, bytes memory returned) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(returned, 32), mload(returned)) }
        result = abi.decode(returned, (MineFlipGas.Result));
        grossGas = beforeGas - gasleft();
    }
}

/// @notice Integrated gas evidence. Run with FOUNDRY_ISOLATE=true to make each
///         measured host call a cold transaction. Gross gas excludes transaction
///         intrinsic gas and includes no storage-refund discount.
contract AfkingStethGasTest is DeployProtocol {
    AfkingStethGasHost private host;
    address private constant PLAYER = address(0xA11CE123);
    address private constant PLAYER_TWO = address(0xA11CE124);
    uint256 private constant WORK_GAS = 12_000_000;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.etch(address(game), type(AfkingStethGasHost).runtimeCode);
        host = AfkingStethGasHost(payable(address(game)));
        vm.deal(address(game), 50_000 ether);
        host.prepare(false);
    }

    function _authorize(address player, bool finite) private {
        vm.prank(player);
        mockStETH.approve(address(game), finite ? 100 ether : type(uint256).max);
    }

    function _work() private returns (uint256 grossGas) {
        MineFlipGas.Result memory result;
        (result, grossGas) = host.measuredSubWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(result.progressed && result.done, "complete admitted worker");
        assertLe(grossGas, GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS,
            "single production item exceeds admission envelope");
    }

    function _assertDelivered(address player, bool tickets) private view {
        (uint24 bought, uint24 opened) = host.delivered(player);
        assertEq(bought, game.currentDayView(), "paid day committed");
        assertEq(opened, tickets ? bought : bought - 1, "correct delivery mode");
    }

    function _successCase(bool finite, bool gameEmpty, bool sourceEmpty, bool tickets) private {
        mockStETH.mint(PLAYER, 1_000 ether);
        if (!gameEmpty) mockStETH.mint(address(game), 100 ether);
        mockStETH.rebase();
        _authorize(PLAYER, finite);
        host.addStethSubscriber(PLAYER, tickets);
        uint256 initial = vm.snapshotState();

        host.creditSource(PLAYER, 100 ether, !sourceEmpty);
        uint256 baseline = _work();
        _assertDelivered(PLAYER, tickets);
        vm.revertToState(initial);

        host.creditSource(PLAYER, 0, !sourceEmpty);
        uint256 beforeShares = mockStETH.sharesOf(PLAYER);
        uint256 fallbackGas = _work();
        _assertDelivered(PLAYER, tickets);
        assertLt(mockStETH.sharesOf(PLAYER), beforeShares, "successful token pull");
        assertEq(host.memberCount(), 1, "payer remains subscribed");
        emit log_named_uint("production_prepaid_worker_gross_gas", baseline);
        emit log_named_uint("production_steth_worker_gross_gas", fallbackGas);
        emit log_named_uint("production_steth_additional_gross_gas", fallbackGas - baseline);
    }

    function test_GasColdUnlimitedExistingBalances() public { _successCase(false, false, false, true); }
    function test_GasColdFiniteExistingBalances() public { _successCase(true, false, false, true); }
    function test_GasColdFiniteFirstGameReceipt() public { _successCase(true, true, false, true); }
    function test_GasColdFiniteEmptyPackedSource() public { _successCase(true, false, true, true); }
    function test_GasColdFiniteBothEmpty() public { _successCase(true, true, true, true); }
    function test_GasColdMaximumBoxFiniteBothEmpty() public { _successCase(true, true, true, false); }

    function _batch(uint256 count, bool fallbackEnabled) private returns (uint256 grossGas) {
        mockStETH.mint(address(game), 100 ether);
        address[2] memory players = [PLAYER, PLAYER_TWO];
        for (uint256 i; i < count; ++i) {
            mockStETH.mint(players[i], 1_000 ether);
            _authorize(players[i], false);
            host.addStethSubscriber(players[i], true);
            host.creditSource(players[i], fallbackEnabled ? 0 : 100 ether, true);
        }
        MineFlipGas.Result memory result;
        (result, grossGas) = host.measuredSubWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(result.progressed && result.done);
        assertEq(result.rewardBasis, count);
        for (uint256 i; i < count; ++i) _assertDelivered(players[i], true);
    }

    function test_GasWarmSecondSubscriber() public {
        uint256 initial = vm.snapshotState();
        uint256 baselineOne = _batch(1, false);
        vm.revertToState(initial);
        uint256 baselineTwo = _batch(2, false);
        vm.revertToState(initial);
        uint256 fallbackOne = _batch(1, true);
        vm.revertToState(initial);
        uint256 fallbackTwo = _batch(2, true);
        uint256 baselineMarginal = baselineTwo - baselineOne;
        uint256 fallbackMarginal = fallbackTwo - fallbackOne;
        emit log_named_uint("production_second_prepaid_subscriber_gross_gas", baselineMarginal);
        emit log_named_uint("production_second_steth_subscriber_gross_gas", fallbackMarginal);
        emit log_named_uint("production_second_steth_additional_gross_gas", fallbackMarginal - baselineMarginal);
    }

    function _failedFixture(bool followingSubscriber) private returns (AdversarialAfkingSteth faulty) {
        mockStETH.mint(PLAYER, 1_000 ether);
        mockStETH.mint(address(game), 100 ether);
        _authorize(PLAYER, true);
        host.addStethSubscriber(PLAYER, true);
        // Activate production quest bookkeeping so failure measures real handback.
        uint24 yesterday = game.currentDayView() - 1;
        uint32 playerId = game.walletIdOf(PLAYER);
        vm.prank(address(game));
        quests.beginAfking(playerId, yesterday);
        if (followingSubscriber) {
            host.addStethSubscriber(PLAYER_TWO, true);
            host.creditSource(PLAYER_TWO, 100 ether, true);
        }
        vm.etch(address(mockStETH), type(AdversarialAfkingSteth).runtimeCode);
        faulty = AdversarialAfkingSteth(payable(address(mockStETH)));
    }

    function test_PostTransferGasExhaustionRollsBackWithoutEviction() public {
        AdversarialAfkingSteth faulty = _failedFixture(true);
        faulty.configureFault(AdversarialAfkingSteth.Operation.BalanceAfter, AdversarialAfkingSteth.Fault.BurnGas);
        uint256 sourceShares = mockStETH.sharesOf(PLAYER);
        uint256 gameShares = mockStETH.sharesOf(address(game));
        uint256 allowanceBefore = mockStETH.allowance(PLAYER, address(game));
        vm.expectRevert(bytes4(keccak256("EmptyRevert()")));
        host.measuredSubWork{gas: WORK_GAS}(WORK_GAS);
        assertEq(host.memberCount(), 2, "failed execution cannot evict");
        assertEq(mockStETH.sharesOf(PLAYER), sourceShares);
        assertEq(mockStETH.sharesOf(address(game)), gameShares);
        assertEq(mockStETH.allowance(PLAYER, address(game)), allowanceBefore);
        faulty.configureFault(AdversarialAfkingSteth.Operation.BalanceAfter, AdversarialAfkingSteth.Fault.None);
        (MineFlipGas.Result memory result,) = host.measuredSubWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(result.done);
        _assertDelivered(PLAYER, true);
        _assertDelivered(PLAYER_TWO, true);
    }

    function test_TransferGasExhaustionPreservesSubscription() public {
        AdversarialAfkingSteth faulty = _failedFixture(false);
        faulty.configureFault(AdversarialAfkingSteth.Operation.Transfer, AdversarialAfkingSteth.Fault.BurnGas);
        vm.expectRevert(bytes4(keccak256("EmptyRevert()")));
        host.measuredSubWork{gas: WORK_GAS}(WORK_GAS);
        assertEq(host.memberCount(), 1);
    }

    function test_InsufficientAdmissionAllowanceDefersWithoutChargingOrEvicting() public {
        mockStETH.mint(PLAYER, 1_000 ether);
        _authorize(PLAYER, true);
        host.addStethSubscriber(PLAYER, false);
        uint256 sourceShares = mockStETH.sharesOf(PLAYER);
        uint256 allowanceBefore = mockStETH.allowance(PLAYER, address(game));
        uint256 required = GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS + MineFlipGas.CHECK_RESERVE;
        (MineFlipGas.Result memory result,) = host.measuredSubWork{gas: WORK_GAS}(required - 1);
        assertFalse(result.progressed || result.done);
        assertEq(host.memberCount(), 1);
        assertEq(host.cursor(), 0);
        assertEq(host.fundingOf(PLAYER), 0);
        assertEq(mockStETH.sharesOf(PLAYER), sourceShares);
        assertEq(mockStETH.allowance(PLAYER, address(game)), allowanceBefore);
        (uint24 bought,) = host.delivered(PLAYER);
        assertLt(bought, game.currentDayView());
        // A later miner with adequate budget admits and pays exactly this item.
        _work();
        _assertDelivered(PLAYER, false);
    }

    function test_AdmissionBoundaryPaysAtMinimumAndDefersOneGasBelow() public {
        mockStETH.mint(PLAYER, 1_000 ether);
        _authorize(PLAYER, true);
        host.addStethSubscriber(PLAYER, false);
        uint256 initial = vm.snapshotState();
        uint256 required = GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS + MineFlipGas.CHECK_RESERVE;
        // The meter also charges worker-entry checks before the item. Discover
        // their exact cost instead of baking compiler-sensitive gas into a test.
        uint256 low = required - 1;
        uint256 high = required + 100_000;
        while (low + 1 < high) {
            uint256 middle = (low + high) / 2;
            (MineFlipGas.Result memory result,) = host.measuredSubWork{gas: WORK_GAS}(middle);
            if (result.progressed) high = middle;
            else low = middle;
            vm.revertToState(initial);
        }
        (MineFlipGas.Result memory deferred,) = host.measuredSubWork{gas: WORK_GAS}(high - 1);
        assertFalse(deferred.progressed || deferred.done);
        assertEq(host.memberCount(), 1);
        assertEq(host.cursor(), 0);
        assertEq(mockStETH.sharesOf(address(game)), 0, "no token movement before admission");
        vm.revertToState(initial);
        (MineFlipGas.Result memory admitted, uint256 grossGas) = host.measuredSubWork{gas: WORK_GAS}(high);
        assertTrue(admitted.progressed && admitted.done);
        _assertDelivered(PLAYER, false);
        assertLe(grossGas, GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS);
        emit log_named_uint("production_minimum_subscriber_worker_allowance", high);
        emit log_named_uint("production_admitted_at_boundary_gross_gas", grossGas);
    }
}
