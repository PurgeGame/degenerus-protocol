// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

contract SubscriptionUpdateSeeder is DegenerusGameStorage {
    function sourceOf(address player) external view returns (address) { return _fundingSourceOf[player]; }
    function flagsOf(address player) external view returns (uint8) { return _subOf[player].flags; }

    /// @dev Reproduce the worker's call-free tombstone removal after a real cancel.
    /// The sparse funding source intentionally survives, as in production.
    function reclaimCanceled(address player) external {
        require(_subOf[player].dailyQuantity == 0);
        require(_subOf[player].lastOpenedDay >= _subOf[player].lastAutoBoughtDay);
        uint256 index = _subscriberIndex[player] - 1;
        address tail = _subscribers[_subscribers.length - 1];
        _subscribers[index] = tail;
        _subscriberIndex[tail] = index + 1;
        _subscribers.pop();
        delete _subscriberIndex[player];
        delete _subOf[player];
    }
}

/// @dev Run with FOUNDRY_ISOLATE=true for cold external-call gas. To run the
/// historical-runtime differential fuzz test, set AFKING_UPDATE_BASELINE_FILE
/// to a JSON file under contracts containing {"runtime":"0x..."} from the
/// pre-change GameAfkingModule artifact. AFKING_UPDATE_USE_BASELINE switches
/// the measured scenarios to that runtime with otherwise identical fixtures.
contract SubscriptionUpdateGasTest is DeployProtocol {
    address private constant PLAYER = address(0xA11CE);
    address private constant SOURCE_A = address(0xF001);
    address private constant SOURCE_B = address(0xF002);
    address private constant BUYER = address(0xB001);
    bytes private baselineCode;
    bytes private candidateCode;
    uint256 private seatId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        seatId = _grantSeat(PLAYER);
        vm.deal(address(this), 300 ether);
        game.depositAfkingFunding{value: 100 ether}(PLAYER);
        game.depositAfkingFunding{value: 100 ether}(SOURCE_A);
        game.depositAfkingFunding{value: 100 ether}(SOURCE_B);
        vm.prank(SOURCE_A); game.setOperatorApproval(PLAYER, true);
        vm.prank(SOURCE_B); game.setOperatorApproval(PLAYER, true);
        candidateCode = address(afkingModule).code;
        string memory path = vm.envOr("AFKING_UPDATE_BASELINE_FILE", string(""));
        if (bytes(path).length != 0) baselineCode = vm.parseJsonBytes(vm.readFile(path), ".runtime");
        if (vm.envOr("AFKING_UPDATE_USE_BASELINE", false)) {
            require(baselineCode.length != 0, "baseline file required");
            vm.etch(address(afkingModule), baselineCode);
        }
    }

    function _subscribe(uint8 quantity, address source) private {
        vm.prank(PLAYER); game.subscribe(address(0), false, true, quantity, source);
    }

    function _source(uint8 index) private pure returns (address) {
        return index % 4 == 0 ? address(0) : index % 4 == 1 ? PLAYER : index % 4 == 2 ? SOURCE_A : SOURCE_B;
    }

    function _sourceAndFlags() private returns (address source, uint8 flags) {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(SubscriptionUpdateSeeder).runtimeCode);
        source = SubscriptionUpdateSeeder(address(game)).sourceOf(PLAYER);
        flags = SubscriptionUpdateSeeder(address(game)).flagsOf(PLAYER);
        vm.etch(address(game), code);
    }

    function _reclaimCanceled() private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(SubscriptionUpdateSeeder).runtimeCode);
        SubscriptionUpdateSeeder(address(game)).reclaimCanceled(PLAYER);
        vm.etch(address(game), code);
    }

    function _measure(string memory label, uint8 quantity, address source) private {
        vm.recordLogs();
        vm.startStateDiffRecording();
        _subscribe(quantity, source);
        uint256 gasUsed = vm.snapshotGasLastCall("subscription-update", label);
        (bytes32 state, uint256 reads, uint256 writes) = _digest(vm.stopAndReturnStateDiff());
        bytes32 events = keccak256(abi.encode(vm.getRecordedLogs()));
        emit log_named_string("scenario", label);
        emit log_named_uint("execution_gas", gasUsed);
        emit log_named_uint("sloads", reads);
        emit log_named_uint("sstores", writes);
        emit log_named_bytes32("state_digest", state);
        emit log_named_bytes32("events_digest", events);
    }

    function testGas_FreshSelf() public { _measure("fresh_self", 1, address(0)); }
    function testGas_ActiveSelf() public { _subscribe(1, address(0)); _measure("active_self", 2, address(0)); }
    function testGas_ActiveExternalToSelf() public { _subscribe(1, SOURCE_A); _measure("external_to_self", 2, address(0)); }
    function testGas_ActiveSelfToExternal() public { _subscribe(1, address(0)); _measure("self_to_external", 2, SOURCE_A); }
    function testGas_ActiveExternalUpdate() public { _subscribe(1, SOURCE_A); _measure("external_update", 2, SOURCE_A); }
    function testGas_CanceledSelfReentry() public {
        _subscribe(1, address(0)); _subscribe(0, address(0)); _measure("cancel_self_reentry", 2, address(0));
    }
    function testGas_ReclaimedExternalReentry() public {
        _subscribe(1, SOURCE_A); _subscribe(0, SOURCE_A); _reclaimCanceled();
        _measure("reclaimed_external_reentry", 2, address(0));
        (address source, uint8 flags) = _sourceAndFlags();
        assertEq(source, address(0), "old external source cleared despite deleted flags");
        assertEq(flags & 1, 0);
    }

    function test_ActiveUpdateKeepsLastSeatLocked() public {
        _subscribe(1, address(0)); _subscribe(2, address(0));
        vm.prank(PLAYER); vm.expectRevert(AFKingSubscriptionToken.SeatInUse.selector);
        afkingSubToken.transferFrom(PLAYER, BUYER, seatId);
        vm.expectRevert(AFKingSubscriptionToken.NotEvicted.selector);
        afkingSubToken.reclaimSeat(seatId);
        assertEq(afkingSubToken.balanceOf(PLAYER), 1);
    }

    function test_CancelSellStillRequiresSeatOnReentry() public {
        _subscribe(1, address(0)); _subscribe(0, address(0));
        vm.prank(PLAYER); afkingSubToken.transferFrom(PLAYER, BUYER, seatId);
        vm.prank(PLAYER); vm.expectRevert(GameAfkingModule.NoCoin.selector);
        game.subscribe(address(0), false, true, 2, address(0));
        vm.prank(BUYER); afkingSubToken.transferFrom(BUYER, PLAYER, seatId);
        _subscribe(2, address(0));
        (bool active, uint8 quantity,,) = game.subInfo(PLAYER);
        assertTrue(active); assertEq(quantity, 2);
    }

    function testFuzz_TransitionMatchesHistoricalRuntime(
        uint8 initialSource, uint8 nextSource, uint8 quantity, uint8 lifecycle, bool drainFirst, bool tickets
    ) public {
        if (baselineCode.length == 0) { vm.skip(true); return; }
        _subscribe(1, _source(initialSource));
        if (lifecycle % 3 != 0) {
            _subscribe(0, _source(initialSource));
            if (lifecycle % 3 == 2) _reclaimCanceled();
        }
        bytes memory callData = abi.encodeWithSelector(
            game.subscribe.selector, address(0), drainFirst, tickets, quantity, _source(nextSource)
        );
        uint256 snapshot = vm.snapshotState();
        vm.etch(address(afkingModule), baselineCode);
        (bool expectedOk, bytes32 expectedData, bytes32 expectedEvents, bytes32 expectedState) = _attempt(callData);
        assertTrue(vm.revertToState(snapshot));
        vm.etch(address(afkingModule), candidateCode);
        (bool actualOk, bytes32 actualData, bytes32 actualEvents, bytes32 actualState) = _attempt(callData);
        assertEq(actualOk, expectedOk, "success/revert parity");
        assertEq(actualData, expectedData, "return/revert bytes parity");
        assertEq(actualEvents, expectedEvents, "event parity");
        assertEq(actualState, expectedState, "all changed storage words parity");
    }

    function _attempt(bytes memory data) private returns (bool ok, bytes32 returned, bytes32 logs, bytes32 state) {
        vm.recordLogs(); vm.startStateDiffRecording();
        vm.prank(PLAYER);
        bytes memory result;
        (ok, result) = address(game).call(data);
        (state,,) = _digest(vm.stopAndReturnStateDiff());
        returned = keccak256(result);
        logs = keccak256(abi.encode(vm.getRecordedLogs()));
    }

    function _digest(Vm.AccountAccess[] memory accounts)
        private view returns (bytes32 state, uint256 reads, uint256 writes)
    {
        uint256 n;
        for (uint256 i; i < accounts.length; ++i) n += accounts[i].storageAccesses.length;
        Vm.StorageAccess[] memory unique = new Vm.StorageAccess[](n);
        uint256 count;
        for (uint256 i; i < accounts.length; ++i) {
            for (uint256 j; j < accounts[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory access = accounts[i].storageAccesses[j];
                if (access.isWrite) ++writes; else ++reads;
                uint256 k;
                while (k < count && (unique[k].account != access.account || unique[k].slot != access.slot)) ++k;
                if (k == count) unique[count++] = access;
            }
        }
        for (uint256 i = 1; i < count; ++i) {
            Vm.StorageAccess memory access = unique[i]; uint256 j = i;
            while (j != 0 && (uint160(unique[j-1].account) > uint160(access.account)
                || (unique[j-1].account == access.account && unique[j-1].slot > access.slot))) {
                unique[j] = unique[j-1]; --j;
            }
            unique[j] = access;
        }
        for (uint256 i; i < count; ++i) {
            Vm.StorageAccess memory access = unique[i];
            bytes32 value = vm.load(access.account, access.slot);
            if (value != access.previousValue) state = keccak256(abi.encode(state, access.account, access.slot, value));
        }
    }
}
