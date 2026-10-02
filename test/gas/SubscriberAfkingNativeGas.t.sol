// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev A full production facade with controlled, committed native-worker inputs.
///      The measured calls delegate to the unmodified production AFKing module.
contract SubscriberNativeGasHost is DegenerusGame {
    function prepare(bool whale) external {
        uint24 day = _simulatedDayIndex();
        level = 4;
        dailyIdx = day - 1;
        _afkingResetDay = day;
        _subCursor = 0;
        _subOpenCursor = 0;
        _pendingBoxCount = 0;
        delete _subscribers;
        subsFullyProcessed = false;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngLockedFlag = false;
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        _setRngComplete(true);
        _sdgnrsBonusLevel = whale ? 0 : level;
        // This fixture skips the first four levels; retire only their bootstrap
        // far-future headers before the real purchase binds levels101..104.
        for (uint24 oldLevel = 1; oldLevel <= 4; ++oldLevel) {
            uint256[] storage q = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(oldLevel))];
            assembly ("memory-safe") { sstore(q.slot, 0) }
        }
        if (whale) {
            _creditClaimable(ContractAddresses.SDGNRS, 2_000 ether);
            claimablePool += 2_000 ether;
        }
    }

    /// @param mode 0=self funded ticket,1=claimable ticket,2=external mixed funding,
    ///             3=unfunded expiry,4=cancelled tombstone,5=maximum box stamp.
    function add(address player, uint8 mode) external {
        _subscribers.push(player);
        _subscriberIndex[player] = _subscribers.length;
        Sub storage sub = _subOf[player];
        uint24 yesterday = _afkingResetDay - 1;
        sub.dailyQuantity = mode == 4 ? 0 : 255;
        sub.flags = mode == 5 ? 0 : 4;
        sub.lastAutoBoughtDay = yesterday;
        sub.lastOpenedDay = yesterday;
        sub.afkingStartDay = yesterday;
        sub.afkCoveredThroughDay = yesterday;
        if (mode == 0 || mode == 5) _creditAfkingValue(player, 100 ether);
        if (mode == 1) {
            sub.flags |= 2;
            _creditClaimable(player, 100 ether);
            claimablePool += 100 ether;
        }
        if (mode == 2) {
            address funder = address(uint160(player) + 0x100000);
            sub.flags |= 1;
            _fundingSourceOf[player] = funder;
            _creditAfkingValue(funder, 1 ether);
            _creditClaimable(player, 100 ether);
            claimablePool += 100 ether;
        }
    }

    function openFixture(address player, uint256 word) external {
        uint24 day = _simulatedDayIndex();
        level = 299;
        dailyIdx = day;
        rngRequestDay = day;
        rngWordCurrent = word < 2 ? 99 : word;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        rngLockedFlag = false;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        subsFullyProcessed = true;
        delete _subscribers;
        _subscribers.push(player);
        _subOpenCursor = 0;
        _pendingBoxCount = 1;
        Sub storage sub = _subOf[player];
        sub.lastAutoBoughtDay = day;
        sub.lastOpenedDay = day - 1;
        sub.amount = 61_200; //255 tickets at the maximum0.24ETH price.
        sub.score = 305; //Maximum useful activity-score multiplier.
        // All following destinations are newly funded, cold far-future queues.
        for (uint24 oldLevel = 1; oldLevel <= 100; ++oldLevel) {
            uint256[] storage q = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(oldLevel))];
            assembly ("memory-safe") { sstore(q.slot, 0) }
        }
        _setPrizePools(1_000 ether, 10_000 ether);
    }

    function subWork(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _work(abi.encodeWithSignature("runSubscriberWork(uint24,uint256)", _afkingResetDay, allowance));
    }
    function openWork(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _work(abi.encodeWithSignature("runAfkingWork(uint256)", allowance));
    }
    function pendingBoxes() external view returns (uint256) { return _pendingBoxCount; }
    function memberCount() external view returns (uint256) { return _subscribers.length; }
    function delivered(address player) external view returns (uint24, uint24) {
        return (_subOf[player].lastAutoBoughtDay, _subOf[player].lastOpenedDay);
    }
    function claimableOf(address player) external view returns (uint256) { return _claimableOf(player); }
    function pendingEntries(address player, uint24 lvl) external view returns (uint256) {
        return _entriesOwedTotal(lvl, player);
    }
    function _work(bytes memory data) private returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory result) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        return abi.decode(result, (MineFlipGas.Result));
    }
}

contract SubscriberAfkingNativeGasTest is DeployProtocol {
    SubscriberNativeGasHost private host;
    address private constant PLAYER = address(0xA11CE123);
    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.etch(address(game), type(SubscriberNativeGasHost).runtimeCode);
        host = SubscriberNativeGasHost(payable(address(game)));
        vm.deal(address(game), 50_000 ether);
    }
    function _lastGas() private returns (uint256 used) {
        used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_064;
    }
    function test_ColdHundredPaidPassWhaleFitsNativeBound() public {
        host.prepare(true);
        uint256[100] memory beforeEntries;
        for (uint24 i; i < 100; ++i) beforeEntries[i] = host.pendingEntries(ContractAddresses.SDGNRS, i + 5);
        vm.recordLogs();
        MineFlipGas.Result memory result = host.subWork{gas: 12_000_000}(12_000_000);
        uint256 used = _lastGas();
        emit log_named_uint("native_subscriber_100_paid_passes_including_intrinsic", used);
        assertTrue(result.progressed && result.done);
        assertLe(used, GasBounds.SUBSCRIBER_WHALE_GAS + GasBounds.SUBSCRIBER_TAIL_GAS,
            "whale action exceeds saved atomic envelope");
        assertLe(used, MineFlipGas.MAX_STEP_GAS);
        assertEq(host.claimableOf(ContractAddresses.SDGNRS), 1_600 ether, "all100 paid passes bought");
        uint256 purchaseLogs;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].emitter == address(game)
                && logs[i].topics[0] == keccak256("WhalePassPurchased(address,uint256,uint256)")) {
                (uint256 quantity, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(quantity, 100);
                assertEq(paid, 400 ether);
                ++purchaseLogs;
            }
        }
        assertEq(purchaseLogs, 1, "one aggregate100-pass purchase");
        for (uint24 i; i < 100; ++i) {
            assertGt(host.pendingEntries(ContractAddresses.SDGNRS, i + 5), beforeEntries[i],
                "purchase must deliver every level in the100-level span");
        }
    }
    function test_ColdSubscriberFundingAndRemovalBranchesFitSavedBound() public {
        uint256 base = vm.snapshotState();
        uint256 peak;
        for (uint8 mode; mode <= 5; ++mode) {
            host.prepare(false);
            host.add(PLAYER, mode);
            MineFlipGas.Result memory result = host.subWork{gas: 12_000_000}(12_000_000);
            uint256 used = _lastGas();
            emit log_named_uint("subscriber_branch_mode", mode);
            emit log_named_uint("native_single_subscriber_including_intrinsic", used);
            assertTrue(result.progressed && result.done);
            assertEq(result.rewardBasis, 1, "exactly one subscriber processed");
            assertLe(used, GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS,
                "cold full item exceeds saved atomic envelope");
            assertLe(used, MineFlipGas.MAX_STEP_GAS);
            if (mode == 3 || mode == 4) assertEq(host.memberCount(), 0, "expired member removed");
            else {
                (uint24 bought, uint24 opened) = host.delivered(PLAYER);
                assertEq(bought, game.currentDayView());
                assertEq(opened, mode == 5 ? bought - 1 : bought);
            }
            if (used > peak) peak = used;
            vm.revertToState(base);
        }
        emit log_named_uint("native_subscriber_branch_peak", peak);
    }
    function testFuzz_ColdSaturatedAfkingGrantFitsSavedBound(uint256 word, bool protocolPlayer) public {
        address player = protocolPlayer ? ContractAddresses.SDGNRS : PLAYER;
        host.openFixture(player, word);
        MineFlipGas.Result memory result = host.openWork{gas: 12_000_000}(12_000_000);
        uint256 used = _lastGas();
        assertTrue(result.progressed && result.done);
        assertEq(result.rewardBasis, 1);
        assertEq(host.pendingBoxes(), 0);
        assertLe(used, GasBounds.AFKING_OPEN_GAS + GasBounds.AFKING_TAIL_GAS,
            "cold full AFKing grant exceeds saved atomic envelope");
        assertLe(used, MineFlipGas.MAX_STEP_GAS);
        (uint24 bought, uint24 opened) = host.delivered(player);
        assertEq(opened, bought);
    }
}
