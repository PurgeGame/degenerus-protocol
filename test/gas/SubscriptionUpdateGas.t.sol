// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Run with FOUNDRY_ISOLATE=true for cold external-call gas. Each scenario reports the
///      subscribe call's execution gas and its storage reads and writes.
contract SubscriptionUpdateGasTest is DeployProtocol {
    address private constant PLAYER = address(0xA11CE);
    uint32 private playerId;
    uint256 private seatId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        seatId = _grantSeat(PLAYER);
        playerId = game.walletIdOf(PLAYER);
        vm.deal(address(this), 100 ether);
        game.depositAfkingFunding{value: 100 ether}(playerId);
        _finishSubscriptionWindow();
    }

    function _subscribeRaw(bool tickets, uint8 quantity, uint256 seat) private {
        vm.prank(PLAYER);
        game.subscribe(0, tickets, quantity, seat);
    }

    function _subscribe(uint8 quantity) private {
        _subscribeRaw(true, quantity, quantity == 0 ? 0 : _grantSeat(PLAYER));
    }

    function _measure(string memory label, bool tickets, uint8 quantity) private {
        uint256 seat = _grantSeat(PLAYER);
        vm.startStateDiffRecording();
        _subscribeRaw(tickets, quantity, seat);
        uint256 gasUsed = vm.snapshotGasLastCall("subscription-update", label);
        (, uint256 reads, uint256 writes) = _digest(vm.stopAndReturnStateDiff());
        emit log_named_string("scenario", label);
        emit log_named_uint("execution_gas", gasUsed);
        emit log_named_uint("sloads", reads);
        emit log_named_uint("sstores", writes);
    }

    function testGas_FreshRun() public { _measure("fresh", true, 1); }
    function testGas_QuantityChange() public { _subscribe(1); _measure("quantity_change", true, 2); }
    function testGas_TicketToBox() public { _subscribe(1); _measure("ticket_to_box", false, 1); }
    function testGas_BoxToTicket() public {
        _subscribeRaw(false, 1, _grantSeat(PLAYER));
        _measure("box_to_ticket", true, 1);
    }
    function testGas_Cancel() public { _subscribe(1); _measure("cancel", true, 0); }

    function test_ActiveUpdateBurnsNoSeat() public {
        _subscribe(1);
        assertEq(afkingSubToken.balanceOf(PLAYER), 0, "the new run burned the seat");
        uint256 seat = _grantSeat(PLAYER);
        _subscribeRaw(true, 2, seat);
        assertEq(afkingSubToken.balanceOf(PLAYER), 1, "a change of a live run burns no seat");
        assertEq(afkingSubToken.ownerOf(seat), PLAYER);
    }

    function test_ReentryAfterCancelNeedsANewSeat() public {
        _subscribe(1);
        _subscribe(0);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        _subscribeRaw(true, 2, seatId);
        _subscribe(2);
        assertEq(GameSlotKeys.subQuantity(address(game), playerId), 2);
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
