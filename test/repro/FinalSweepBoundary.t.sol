// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Production Game plus one seam: the Advance module's terminal phase, called the way the
///      miner's Terminal dispatch calls it, so the sweep's own time check is exercised without
///      the miner's selection in front of it.
contract SweepBoundaryHost is DegenerusGame {
    function terminalPhaseOnly() external returns (bool progressed) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runTerminalPhase(uint256)", gasleft() - 200_000)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        progressed = abi.decode(data, (MineFlipGas.Result)).progressed;
    }
}

/// @title FinalSweepBoundary -- the final sweep runs at exactly GO_TIME + 30 days, never earlier
/// @notice A real hard-stall ending (14 days without a completed day) runs through mineRun until
///         the terminal payout stamps GO_TIME (`_finishTerminalPayout`). The sweep delay is the
///         literal `30 days` in two places: `_nextMinerAction` selects Terminal after game over
///         only when `block.timestamp >= GO_TIME + 30 days`, and `_handleFinalSweep` returns
///         early while `block.timestamp < goTime + 30 days`. Both are probed one second before
///         the boundary and at the boundary.
contract FinalSweepBoundaryTest is DeployProtocol {
    address private constant BUYER = address(0xB0B5);
    address private constant SAVER = address(0x5A7E);
    uint256 private constant SAVED = 3 ether;

    bytes private realCode;
    uint32 private saverId;
    uint256 private goTime;

    function setUp() public {
        _deployProtocol();
        realCode = address(game).code;
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(BUYER, 100 ether);
        vm.deal(SAVER, 10 ether);
        vm.prank(BUYER);
        game.purchaseOrderFor{value: 0.05 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        saverId = _giveWalletId(SAVER);
        vm.prank(SAVER);
        game.depositAfkingFunding{value: SAVED}(saverId);
        _completeDay();
        // No completed day for 14 days: the hard-stall ending.
        vm.warp(vm.getBlockTimestamp() + 15 days);
        assertTrue(game.livenessTriggered(), "fixture: hard stall triggered");
        for (uint256 i; i < 256 && game.gameOverTimestamp() == 0; ++i) {
            _fulfillPending();
            game.mineRun(0);
        }
        goTime = game.gameOverTimestamp();
        assertTrue(game.gameOver(), "fixture: game over");
        assertGt(goTime, 0, "fixture: the terminal payout stamped GO_TIME");
        assertFalse(game.isFinalSwept(), "fixture: not swept at the stamp");
    }

    function _completeDay() private {
        for (uint256 i; i < 16 && !game.rngLocked(); ++i) game.mineRun(0);
        _fulfillPending();
        for (uint256 i; i < 64 && game.rngLocked(); ++i) game.mineRun(0);
        _finishReadConsumers();
    }

    function _fulfillPending() private {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(id);
        if (!fulfilled) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("sweep-boundary", id))));
    }

    /// @notice One second before the boundary: the miner has no work, the sweep's own check
    ///         refuses, and every balance stays claimable.
    function test_OneSecondBeforeTheBoundaryNothingIsSwept() public {
        vm.warp(goTime + 30 days - 1);
        uint256 pool = game.claimablePoolView();
        assertGt(pool, 0, "fixture: claimable obligations exist");
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Idle), "no terminal work before the boundary");
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.mineRun(0);

        vm.etch(address(game), type(SweepBoundaryHost).runtimeCode);
        bool progressed = SweepBoundaryHost(payable(address(game))).terminalPhaseOnly();
        vm.etch(address(game), realCode);
        assertFalse(progressed, "the sweep's own check refuses one second early");
        assertFalse(game.isFinalSwept(), "not swept one second early");
        assertEq(game.claimablePoolView(), pool, "claimablePool untouched one second early");

        uint256 before = SAVER.balance;
        vm.prank(SAVER);
        game.withdrawAfkingFunding(saverId, SAVED);
        assertEq(SAVER.balance, before + SAVED, "a balance is still withdrawable one second early");
    }

    /// @notice At the boundary: the miner selects the terminal step, one call sweeps, claims close,
    ///         and the sweep never runs again.
    function test_AtTheBoundaryTheSweepRunsOnce() public {
        vm.warp(goTime + 30 days);
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Terminal), "terminal work at the boundary");
        game.mineRun(0);
        assertTrue(game.isFinalSwept(), "swept at the boundary");
        assertEq(game.claimablePoolView(), 0, "claimablePool zero after the sweep");
        vm.prank(SAVER);
        vm.expectRevert(bytes4(keccak256("AlreadySwept()")));
        game.withdrawAfkingFunding(saverId, SAVED);
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Idle), "nothing left after the sweep");
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.mineRun(0);
    }

    /// @notice The sweep's own check at the boundary, without the miner's selection.
    function test_AtTheBoundaryTheTerminalPhaseSweeps() public {
        vm.warp(goTime + 30 days);
        vm.etch(address(game), type(SweepBoundaryHost).runtimeCode);
        bool progressed = SweepBoundaryHost(payable(address(game))).terminalPhaseOnly();
        vm.etch(address(game), realCode);
        assertTrue(progressed, "the terminal phase sweeps at the boundary");
        assertTrue(game.isFinalSwept(), "swept at the boundary");
    }
}
