// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {console2} from "forge-std/console2.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {AfkingStethHost} from "../fuzz/helpers/AfkingStethFixture.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract AfkingItemGasHost is AfkingStethHost {
    function setCheckpoint(address player, uint24 day) external {
        uint256 position = _subPosition1(_walletIdOf(player)) - 1;
        uint256 lane = _subLaneAt(position);
        _setSubLaneAt(position, _withSubCheckpoint(lane, day, _subCheckpointStreak(lane)));
    }

    function markRemoval(address player) external {
        uint256 position = _subPosition1(_walletIdOf(player)) - 1;
        _setSubLaneAt(position, _subLaneAt(position) | SUB_REMOVAL_BIT);
    }

    function pauseUnfunded(uint8 bit) external {
        _afkingProtocolFlags |= bit;
    }
}

/// @notice Worst single preparation item per path, against the per-item admission reserve.
///         Each case runs one cohort member through the production worker and reports the gas
///         of the whole call; the empty-cohort call is subtracted so only the item remains.
contract AfkingCompactItemGasTest is DeployProtocol {
    AfkingItemGasHost private host;
    uint256 private constant WORK_GAS = 6_000_000;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 2 days);
        vm.etch(address(game), type(AfkingItemGasHost).runtimeCode);
        host = AfkingItemGasHost(payable(address(game)));
        vm.deal(address(game), 100 ether);
        host.prepare();
    }

    function _measure() private returns (uint256 used) {
        // Cold-access prices: nothing the setup touched counts as warm.
        vm.cool(address(game));
        vm.cool(address(coinflip));
        vm.cool(address(affiliate));
        vm.cool(address(quests));
        vm.cool(address(mockStETH));
        vm.cool(address(afkingModule));
        vm.cool(address(lootboxModule));
        uint256 before = gasleft();
        MineFlipGas.Result memory result = host.subWork{gas: WORK_GAS}(WORK_GAS);
        used = before - gasleft();
        assertTrue(result.done, "the cohort drains in one call");
    }

    function _baseline() private returns (uint256 used) {
        uint256 snap = vm.snapshotState();
        host.prepare();
        used = _measure();
        vm.revertToState(snap);
    }

    function _report(string memory label, uint256 used, uint256 base) private pure returns (uint256 item) {
        item = used - base;
        console2.log(label, item);
        assertLt(item, GasBounds.SUBSCRIBER_ITEM_GAS, label);
    }

    function test_ItemGasPerPath() public {
        uint256 base = _baseline();
        uint24 e = host.endpoint();

        // Funded quantity-8 box with a 5-day-old checkpoint (score from the streak).
        uint256 snap = vm.snapshotState();
        host.add(address(0xB0C5), false, 8, 5 ether, 0);
        host.setCheckpoint(address(0xB0C5), e - 5);
        _report("box delivery", _measure(), base);
        vm.revertToState(snap);

        // Funded quantity-8 tickets.
        snap = vm.snapshotState();
        host.add(address(0x71C4), true, 8, 5 ether, 0);
        _report("ticket delivery", _measure(), base);
        vm.revertToState(snap);

        // Unfunded ordinary member: quest handback and removal.
        snap = vm.snapshotState();
        host.add(address(0xDEAD), false, 8, 0, 0);
        host.setCheckpoint(address(0xDEAD), e - 5);
        _report("ordinary expiry", _measure(), base);
        vm.revertToState(snap);

        // Seized run removed before it buys.
        snap = vm.snapshotState();
        host.add(address(0x5E12), true, 8, 5 ether, 0);
        host.markRemoval(address(0x5E12));
        _report("seized removal", _measure(), base);
        vm.revertToState(snap);

        // Unfunded protocol seat: a 5-day settlement through the affiliate claim, then the pause.
        snap = vm.snapshotState();
        host.add(address(sdgnrs), false, 1, 0, 0);
        host.setBalances(address(sdgnrs), 0, 1);
        host.setCheckpoint(address(sdgnrs), e - 5);
        _report("protocol unfunded pause", _measure(), base);
        vm.revertToState(snap);

        // Paused protocol seat that can pay again: resume and buy.
        snap = vm.snapshotState();
        host.add(address(sdgnrs), false, 1, 1 ether, 0);
        host.pauseUnfunded(16);
        _report("protocol resume", _measure(), base);
        vm.revertToState(snap);
    }
}
