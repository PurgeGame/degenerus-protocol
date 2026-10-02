// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";

/// @dev Etched over the game only to seed a claimable balance, then the real runtime is restored.
contract ClaimableSeeder is DegenerusGame {
    function seedClaimable(address player, uint256 amount) external {
        balancesPacked[player] += amount;
        claimablePool += uint128(amount);
    }
}

/// @title PostGameOverShortfall — after game over, a stETH leg that cannot move never blocks what exists.
/// @notice The daily auto-stake keeps the claimable pool in ETH during play, but the terminal payout
///         credits winners out of stETH-heavy prize pools, so after game over later claimants are
///         paid partly in stETH. A stopped Lido (transfers revert) or an stETH loss (the balance
///         runs short) must only limit what can be taken, never block what exists.
contract PostGameOverShortfall is DeployProtocol {
    address internal keeper = address(0xBEEF);
    address internal alice = address(0xA11CE);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(keeper, 100 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev Latch game over through the liveness timeout and the real crank (FinalSweepPayoutLegs'
    ///      driver: advance, fulfil whatever VRF request is pending, repeat).
    function _driveToGameOver() internal {
        vm.warp(block.timestamp + 370 days);
        for (uint256 i; i < 40 && !game.gameOver(); i++) {
            vm.prank(keeper);
            try game.mineFlip() {} catch {}
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("shortfall-word", i))) | 1) {}
                        catch {}
                }
            }
        }
        require(game.gameOver(), "fixture: game over never latched");
    }

    function _seedClaimable(address player, uint256 amount) internal {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(ClaimableSeeder).runtimeCode);
        ClaimableSeeder(payable(address(game))).seedClaimable(player, amount);
        vm.etch(address(game), real);
    }

    /// @notice A claimant owed more than the game's ETH, with the stETH leg frozen (Lido stopped):
    ///         the full claim waits for the stETH, but `claimWinnings(player, amount)` takes the ETH
    ///         that exists — the partial cap holds after game over.
    function test_aPostGameOverClaimTakesTheEthThatExists() public {
        _driveToGameOver();
        _seedClaimable(alice, 10 ether);
        vm.deal(address(game), 4 ether);
        mockStETH.mint(address(game), 20 ether);
        vm.mockCallRevert(address(mockStETH), abi.encodeWithSelector(mockStETH.transfer.selector), "STOPPED");

        vm.prank(alice);
        vm.expectRevert();
        game.claimWinnings(alice);

        vm.prank(alice);
        game.claimWinnings(alice, 4 ether);
        assertEq(alice.balance, 4 ether, "the ETH that exists was not paid");
        assertEq(game.claimableWinningsOf(alice), 6 ether, "the rest did not stay claimable");
    }

    /// @notice An stETH loss that leaves sDGNRS custodying less than its reserved redemption value
    ///         prices a burn after game over at nothing — its preview and the burn itself — instead
    ///         of panicking every burn.
    function test_aDeficitPricesAnSdgnrsBurnAtZero() public {
        vm.prank(address(game));
        IsDGNRS(address(sdgnrs)).transferFromPool(IsDGNRS.Pool.Reward, alice, 1_000 ether);
        uint256 held = sdgnrs.balanceOf(alice);
        assertGt(held, 0, "fixture: alice holds no sDGNRS");
        _driveToGameOver();

        vm.deal(address(sdgnrs), 0);
        uint256 st = mockStETH.balanceOf(address(sdgnrs));
        if (st != 0) {
            vm.prank(address(sdgnrs));
            mockStETH.transfer(address(0xdead), st);
        }
        _setPendingRedemptionEthValue(1_000_000 ether);

        (uint256 previewEth,) = sdgnrs.previewBurnValue(held);
        assertEq(previewEth, 0, "the preview priced a deficit above zero");
        vm.prank(alice);
        (uint256 ethOut, uint256 stethOut,) = sdgnrs.burn(held);
        assertEq(ethOut + stethOut, 0, "a deficit burn paid out");
        assertEq(sdgnrs.balanceOf(alice), 0, "the burn did not complete");
    }

    /// @dev `_pendingRedemptionEthValue` is the uint96 at byte 16 of sDGNRS slot 0 (after the
    ///      uint128 `_totalSupply`).
    function _setPendingRedemptionEthValue(uint256 v) internal {
        uint256 w = uint256(vm.load(address(sdgnrs), bytes32(0)));
        uint256 mask = ((uint256(1) << 96) - 1) << 128;
        w = (w & ~mask) | (v << 128);
        vm.store(address(sdgnrs), bytes32(0), bytes32(w));
        assertEq(sdgnrs.pendingRedemptionEthValue(), v, "fixture: reserve slot");
    }
}
