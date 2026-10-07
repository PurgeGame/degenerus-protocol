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
    function addStethSubscriber(address player, address source, bool tickets) external {
        uint32 subId = _seedWallet(player);
        _subscribers.push(subId);
        _subOf[subId].setPosition = uint32(_subscribers.length);
        Sub storage sub = _subOf[subId];
        uint24 yesterday = _afkingResetDay - 1;
        sub.dailyQuantity = 255;
        sub.flags = (source == player ? 0 : 1) | (tickets ? 4 : 0);
        if (source != player) _fundingSourceOf[_seedWallet(player)] = _seedWallet(source);
        sub.lastAutoBoughtDay = yesterday;
        sub.lastOpenedDay = yesterday;
        sub.afkingStartDay = yesterday;
        sub.afkCoveredThroughDay = yesterday;
        // A mature run exercises the century-shield handback on eviction.
        sub.subStreakLatch = 300;
        sub.pendingFlip = 1_000;
        sub.affiliateBase = 1_000;
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
    address private constant FUNDER = address(0xF00D123);
    address private constant FUNDER_TWO = address(0xF00D124);
    uint256 private constant WORK_GAS = 12_000_000;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.etch(address(game), type(AfkingStethGasHost).runtimeCode);
        host = AfkingStethGasHost(payable(address(game)));
        vm.deal(address(game), 50_000 ether);
        host.prepare(false);
    }

    function _authorize(address player, address source, bool finite) private {
        if (source != player) {
            uint32 playerId = _giveWalletId(player);
            _giveWalletId(source);
            vm.prank(source);
            game.setAfkingFundingApproval(0, playerId, true);
        }
        vm.prank(source);
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

    function _successCase(bool sponsored, bool finite, bool gameEmpty, bool sourceEmpty, bool tickets) private {
        address source = sponsored ? FUNDER : PLAYER;
        mockStETH.mint(source, 1_000 ether);
        if (!gameEmpty) mockStETH.mint(address(game), 100 ether);
        mockStETH.rebase();
        _authorize(PLAYER, source, finite);
        host.addStethSubscriber(PLAYER, source, tickets);
        uint256 initial = vm.snapshotState();

        host.creditSource(source, 100 ether, !sourceEmpty);
        uint256 baseline = _work();
        _assertDelivered(PLAYER, tickets);
        vm.revertToState(initial);

        host.creditSource(source, 0, !sourceEmpty);
        uint256 beforeShares = mockStETH.sharesOf(source);
        uint256 fallbackGas = _work();
        _assertDelivered(PLAYER, tickets);
        assertLt(mockStETH.sharesOf(source), beforeShares, "successful token pull");
        assertEq(host.memberCount(), 1, "payer remains subscribed");
        emit log_named_uint("production_prepaid_worker_gross_gas", baseline);
        emit log_named_uint("production_steth_worker_gross_gas", fallbackGas);
        emit log_named_uint("production_steth_additional_gross_gas", fallbackGas - baseline);
    }

    function test_GasColdSelfUnlimitedExistingBalances() public { _successCase(false, false, false, false, true); }
    function test_GasColdSelfFiniteExistingBalances() public { _successCase(false, true, false, false, true); }
    function test_GasColdSponsorUnlimitedExistingBalances() public { _successCase(true, false, false, false, true); }
    function test_GasColdSponsorFiniteExistingBalances() public { _successCase(true, true, false, false, true); }
    function test_GasColdSponsorFiniteFirstGameReceipt() public { _successCase(true, true, true, false, true); }
    function test_GasColdSponsorFiniteEmptyPackedSource() public { _successCase(true, true, false, true, true); }
    function test_GasColdSponsorFiniteBothEmpty() public { _successCase(true, true, true, true, true); }
    function test_GasColdSelfFiniteBothEmpty() public { _successCase(false, true, true, true, true); }
    function test_GasColdMaximumBoxSponsorFiniteBothEmpty() public { _successCase(true, true, true, true, false); }

    function _batch(uint256 count, bool fallbackEnabled, bool sharedSource) private returns (uint256 grossGas) {
        mockStETH.mint(address(game), 100 ether);
        mockStETH.mint(FUNDER, 1_000 ether);
        host.creditSource(FUNDER, fallbackEnabled ? 0 : 100 ether, true);
        if (!sharedSource && count == 2) {
            mockStETH.mint(FUNDER_TWO, 1_000 ether);
            host.creditSource(FUNDER_TWO, fallbackEnabled ? 0 : 100 ether, true);
        }
        _authorize(PLAYER, FUNDER, false);
        host.addStethSubscriber(PLAYER, FUNDER, true);
        if (count == 2) {
            address secondSource = sharedSource ? FUNDER : FUNDER_TWO;
            _authorize(PLAYER_TWO, secondSource, false);
            host.addStethSubscriber(PLAYER_TWO, secondSource, true);
        }
        MineFlipGas.Result memory result;
        (result, grossGas) = host.measuredSubWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(result.progressed && result.done);
        assertEq(result.rewardBasis, count);
        _assertDelivered(PLAYER, true);
        if (count == 2) _assertDelivered(PLAYER_TWO, true);
    }

    function _warmMarginal(bool sharedSource) private {
        uint256 initial = vm.snapshotState();
        uint256 baselineOne = _batch(1, false, sharedSource);
        vm.revertToState(initial);
        uint256 baselineTwo = _batch(2, false, sharedSource);
        vm.revertToState(initial);
        uint256 fallbackOne = _batch(1, true, sharedSource);
        vm.revertToState(initial);
        uint256 fallbackTwo = _batch(2, true, sharedSource);
        uint256 baselineMarginal = baselineTwo - baselineOne;
        uint256 fallbackMarginal = fallbackTwo - fallbackOne;
        emit log_named_uint("production_second_prepaid_subscriber_gross_gas", baselineMarginal);
        emit log_named_uint("production_second_steth_subscriber_gross_gas", fallbackMarginal);
        emit log_named_uint("production_second_steth_additional_gross_gas", fallbackMarginal - baselineMarginal);
    }

    function test_GasWarmSecondSubscriberSharedFunder() public { _warmMarginal(true); }
    function test_GasWarmSecondSubscriberDistinctFunder() public { _warmMarginal(false); }

    function _failedFixture(bool followingSubscriber) private returns (AdversarialAfkingSteth faulty) {
        mockStETH.mint(FUNDER, 1_000 ether);
        mockStETH.mint(address(game), 100 ether);
        _authorize(PLAYER, FUNDER, true);
        host.addStethSubscriber(PLAYER, FUNDER, true);
        // Activate production quest bookkeeping so failure measures real handback.
        uint24 yesterday = game.currentDayView() - 1;
        uint32 playerId = game.walletIdOf(PLAYER);
        vm.prank(address(game));
        quests.beginAfking(playerId, yesterday);
        if (followingSubscriber) {
            host.addStethSubscriber(PLAYER_TWO, PLAYER_TWO, true);
            host.creditSource(PLAYER_TWO, 100 ether, true);
        }
        vm.etch(address(mockStETH), type(AdversarialAfkingSteth).runtimeCode);
        faulty = AdversarialAfkingSteth(payable(address(mockStETH)));
    }

    function test_GasFullStipendFailureFinalizesEvictionAndFollowingSubscriber() public {
        AdversarialAfkingSteth faulty = _failedFixture(true);
        uint256 initial = vm.snapshotState();
        uint32 playerId = game.walletIdOf(PLAYER);
        vm.prank(FUNDER);
        game.setAfkingFundingApproval(0, playerId, false);
        MineFlipGas.Result memory baselineResult;
        uint256 baseline;
        (baselineResult, baseline) = host.measuredSubWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(baselineResult.done);
        assertEq(baselineResult.rewardBasis, 2);
        vm.revertToState(initial);

        faulty.configureFault(AdversarialAfkingSteth.Operation.BalanceAfter, AdversarialAfkingSteth.Fault.BurnGas);
        uint256 sourceShares = mockStETH.sharesOf(FUNDER);
        uint256 gameShares = mockStETH.sharesOf(address(game));
        uint256 allowanceBefore = mockStETH.allowance(FUNDER, address(game));
        MineFlipGas.Result memory result;
        uint256 grossGas;
        (result, grossGas) = host.measuredSubWork{gas: WORK_GAS}(WORK_GAS);
        assertTrue(result.progressed && result.done);
        assertEq(result.rewardBasis, 2, "failed payer and swapped-in subscriber processed");
        assertEq(host.memberCount(), 1, "unpaid payer evicted");
        assertEq(mockStETH.sharesOf(FUNDER), sourceShares, "post-transfer failure rolls back source debit");
        assertEq(mockStETH.sharesOf(address(game)), gameShares, "post-transfer failure rolls back receipt");
        assertEq(mockStETH.allowance(FUNDER, address(game)), allowanceBefore, "allowance rollback");
        _assertDelivered(PLAYER_TWO, true);
        (uint24 bought,) = host.delivered(PLAYER);
        assertEq(bought, 0, "evicted record cleared");
        assertLe(grossGas, 2 * GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS);
        emit log_named_uint("production_eviction_and_following_prepaid_worker_gross_gas", baseline);
        emit log_named_uint("production_full_stipend_eviction_and_following_worker_gross_gas", grossGas);
        emit log_named_uint("production_full_stipend_failure_additional_gross_gas", grossGas - baseline);
    }

    function test_GasFullStipendSingleEvictionFitsAdmissionBound() public {
        AdversarialAfkingSteth faulty = _failedFixture(false);
        faulty.configureFault(AdversarialAfkingSteth.Operation.Transfer, AdversarialAfkingSteth.Fault.BurnGas);
        uint256 used = _work();
        assertEq(host.memberCount(), 0);
        emit log_named_uint("production_full_stipend_single_eviction_gross_gas", used);
    }

    function test_InsufficientAdmissionAllowanceDefersWithoutChargingOrEvicting() public {
        mockStETH.mint(FUNDER, 1_000 ether);
        _authorize(PLAYER, FUNDER, true);
        host.addStethSubscriber(PLAYER, FUNDER, true);
        uint256 sourceShares = mockStETH.sharesOf(FUNDER);
        uint256 allowanceBefore = mockStETH.allowance(FUNDER, address(game));
        uint256 required = GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS + MineFlipGas.CHECK_RESERVE;
        (MineFlipGas.Result memory result,) = host.measuredSubWork{gas: WORK_GAS}(required - 1);
        assertFalse(result.progressed || result.done);
        assertEq(host.memberCount(), 1);
        assertEq(host.cursor(), 0);
        assertEq(host.fundingOf(FUNDER), 0);
        assertEq(mockStETH.sharesOf(FUNDER), sourceShares);
        assertEq(mockStETH.allowance(FUNDER, address(game)), allowanceBefore);
        (uint24 bought,) = host.delivered(PLAYER);
        assertLt(bought, game.currentDayView());
        // A later miner with adequate budget admits and pays exactly this item.
        _work();
        _assertDelivered(PLAYER, true);
    }

    function test_AdmissionBoundaryPaysAtMinimumAndDefersOneGasBelow() public {
        mockStETH.mint(FUNDER, 1_000 ether);
        _authorize(PLAYER, FUNDER, true);
        host.addStethSubscriber(PLAYER, FUNDER, true);
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
        _assertDelivered(PLAYER, true);
        assertLe(grossGas, GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS);
        emit log_named_uint("production_minimum_subscriber_worker_allowance", high);
        emit log_named_uint("production_admitted_at_boundary_gross_gas", grossGas);
    }
}
