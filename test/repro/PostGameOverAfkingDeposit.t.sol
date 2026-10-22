// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @title Afking deposits close at game over.
/// @notice depositAfkingFunding refuses ETH once gameOver is set, like receive(): a deposit after
///         the final sweep could never be withdrawn or claimed, and a deposit to the vault's ID
///         would inflate DGVE's reserve view. Deposits before game over stay open.
contract PostGameOverAfkingDeposit is DeployProtocol {
    address internal keeper = address(0xBEEF);
    address internal stranger = address(0x5712A);

    bytes4 internal constant GAME_OVER = bytes4(keccak256("GameOver()"));

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(keeper, 1_000 ether);
        vm.deal(stranger, 100 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    receive() external payable {}

    function _driveToGameOver() internal {
        vm.warp(block.timestamp + 370 days);
        for (uint256 i; i < 40 && !game.gameOver(); i++) {
            vm.prank(keeper);
            try game.mineFlip(0) {} catch {}
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("sweep-word", i))) | 1) {}
                        catch {}
                }
            }
        }
        require(game.gameOver(), "fixture: game over never latched");
    }

    function _driveToFinalSweep() internal {
        _driveToGameOver();
        vm.warp(block.timestamp + 30 days + 1);
        vm.prank(keeper);
        game.mineFlip(0);
        require(game.isFinalSwept(), "fixture: final sweep did not run");
    }

    function test_depositBeforeGameOverIsAccepted() public {
        uint32 sid = _giveWalletId(stranger);
        vm.prank(stranger);
        game.depositAfkingFunding{value: 2 ether}(sid);
        assertEq(game.afkingFundingOf(stranger), 2 ether);
    }

    function test_depositAfterGameOverReverts() public {
        uint32 sid = _giveWalletId(stranger);
        _driveToGameOver();
        vm.prank(stranger);
        vm.expectRevert(GAME_OVER);
        game.depositAfkingFunding{value: 2 ether}(sid);
    }

    function test_depositAfterFinalSweepReverts() public {
        uint32 sid = _giveWalletId(stranger);
        uint32 vaultId = game.walletIdOf(address(vault));
        _driveToFinalSweep();
        uint256 gameBal0 = address(game).balance;

        vm.prank(stranger);
        vm.expectRevert(GAME_OVER);
        game.depositAfkingFunding{value: 2 ether}(sid);

        vm.prank(keeper);
        vm.expectRevert(GAME_OVER);
        game.depositAfkingFunding{value: 10 ether}(vaultId);

        assertEq(address(game).balance, gameBal0, "no ETH is stranded in the Game");
        assertEq(game.afkingFundingOf(address(vault)), 0, "vault afking stays zero after the sweep");
    }
}
