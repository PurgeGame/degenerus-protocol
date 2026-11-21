// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title Afking deposits close at game over.
/// @notice depositAfkingFunding refuses ETH once gameOver is set, like receive(): a deposit after
///         the final sweep could never be withdrawn or claimed, and a deposit to the vault's ID
///         would inflate DGVE's reserve view. Deposits before game over stay open.
contract PostGameOverAfkingDeposit is DeployProtocol {
    address internal keeper = address(0xBEEF);
    address internal stranger = address(0x5712A);

    bytes4 internal constant GAME_OVER = bytes4(keccak256("GameOver()"));
    bytes4 internal constant ALREADY_SWEPT = bytes4(keccak256("AlreadySwept()"));

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
            try game.mineRun(0) {} catch {}
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
        game.mineRun(0);
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
        uint32 vaultId = game.walletIdOf_g3120(address(vault));
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

    /// @notice Prepaid AFKing left in an ordinary account at the final sweep is forfeited: the
    ///         stored figure remains, no path pays it, and every balance view reads zero.
    function test_afkingViewsReadZeroAfterFinalSweep() public {
        uint32 sid = _giveWalletId(stranger);
        vm.prank(stranger);
        game.depositAfkingFunding{value: 2 ether}(sid);
        DegenerusGameLens lens = new DegenerusGameLens();
        address[] memory who = new address[](1);
        who[0] = stranger;
        (,,, uint256[] memory fundings) = lens.afkingSnapshot(address(game), who);
        assertEq(fundings[0], 2 ether, "fixture: the Lens reports the deposit before the sweep");
        assertEq(game.afkingFundingOf(stranger), 2 ether, "fixture: the Game reports the deposit before the sweep");

        _driveToFinalSweep();

        assertEq(
            uint256(vm.load(address(game), GameSlotKeys.balances(sid))) >> 128,
            2 ether,
            "fixture: the stored prepaid figure survives the sweep"
        );
        vm.prank(stranger);
        vm.expectRevert(ALREADY_SWEPT);
        game.withdrawAfkingFunding(sid, 1);

        assertEq(game.afkingFundingOf(stranger), 0, "the Game view reads zero after the sweep");
        uint256[] memory claimables;
        (,, claimables, fundings) = lens.afkingSnapshot(address(game), who);
        assertEq(claimables[0], 0, "the Lens batch view reads zero claimable after the sweep");
        assertEq(fundings[0], 0, "the Lens batch view reads zero prepaid AFKing after the sweep");
        (uint128 claimable, uint128 afking) = lens.accountBalances(address(game), sid);
        assertEq(uint256(claimable) + afking, 0, "the Lens account view reads zero after the sweep");
    }
}
