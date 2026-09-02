// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FinalSweepPayoutLegs — the game-over final sweep's three bare payout calls cannot revert.
///
/// @notice Thirty days after game over the crank runs `handleFinalSweep`, which pays the vault,
///         sDGNRS and GNRUS through `_sendStethFirst`: an stETH `transfer` for what the stETH
///         balance covers, then a raw ETH `call` for the rest. All three calls are bare on the
///         crank and hard-revert on failure by policy — the receivers are the protocol's own
///         pinned contracts, which cannot refuse. These pins drive the real crank into the sweep
///         with the REAL receivers and assert every leg pays: stETH-only, ETH-only, and mixed.
contract FinalSweepPayoutLegs is DeployProtocol {
    address internal keeper = address(0xBEEF);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(keeper, 100 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev Latch game over through the liveness timeout and the real crank (the isolation
    ///      suite's driver: advance, fulfil whatever VRF request is pending, repeat).
    function _driveToGameOver() internal {
        vm.warp(block.timestamp + 370 days);
        for (uint256 i; i < 40 && !game.gameOver(); i++) {
            vm.prank(keeper);
            try game.advanceGame() {} catch {}
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

    /// @dev The sweep tx itself. No try/catch: a revert here is the failure these pins exist for.
    function _sweep() internal {
        vm.warp(block.timestamp + 30 days + 1);
        vm.prank(keeper);
        game.advanceGame();
    }

    struct Ledger {
        uint256 vaultSt;
        uint256 sdSt;
        uint256 gnSt;
        uint256 vaultEth;
        uint256 sdEth;
        uint256 gnEth;
    }

    function _ledger() internal view returns (Ledger memory l) {
        l.vaultSt = mockStETH.balanceOf(ContractAddresses.VAULT);
        l.sdSt = mockStETH.balanceOf(ContractAddresses.SDGNRS);
        l.gnSt = mockStETH.balanceOf(ContractAddresses.GNRUS);
        l.vaultEth = ContractAddresses.VAULT.balance;
        l.sdEth = ContractAddresses.SDGNRS.balance;
        l.gnEth = ContractAddresses.GNRUS.balance;
    }

    /// @notice Every wei the game holds at the sweep (ETH + stETH) leaves it, and lands on the
    ///         three receivers — the ETH leg (`_sendStethFirst`'s raw call) pays when stETH is short.
    function test_ethOnlySweepPaysAllThreeReceiversThroughTheRawCall() public {
        _driveToGameOver();
        // Strip stETH so the ETH leg carries the whole sweep; leave a real ETH balance.
        uint256 st = mockStETH.balanceOf(address(game));
        if (st != 0) {
            vm.prank(address(game));
            mockStETH.transfer(address(0xdead), st);
        }
        vm.deal(address(game), 90 ether);
        Ledger memory b = _ledger();
        _sweep();
        Ledger memory a = _ledger();
        assertEq(address(game).balance, 0, "the sweep must leave the game empty");
        uint256 paid = (a.vaultEth - b.vaultEth) + (a.sdEth - b.sdEth) + (a.gnEth - b.gnEth);
        assertEq(paid, 90 ether, "every wei reached the three receivers");
        assertGt(a.vaultEth - b.vaultEth, 0, "the vault's ETH leg paid");
        assertGt(a.sdEth - b.sdEth, 0, "sDGNRS's ETH leg paid");
        assertGt(a.gnEth - b.gnEth, 0, "GNRUS's ETH leg paid");
        assertEq(a.vaultSt + a.sdSt + a.gnSt, b.vaultSt + b.sdSt + b.gnSt, "no stETH moved");
    }

    /// @notice stETH covers everything: the `steth.transfer` legs pay and the raw call is idle.
    function test_stethOnlySweepPaysThroughTransfer() public {
        _driveToGameOver();
        vm.deal(address(game), 0);
        mockStETH.mint(address(game), 60 ether);
        uint256 st = mockStETH.balanceOf(address(game));
        Ledger memory b = _ledger();
        _sweep();
        Ledger memory a = _ledger();
        assertEq(mockStETH.balanceOf(address(game)), 0, "the sweep must move every stETH share");
        uint256 paidSt = (a.vaultSt - b.vaultSt) + (a.sdSt - b.sdSt) + (a.gnSt - b.gnSt);
        // Rebasing mock: the receivers' balances are share-derived, so allow one wei per receiver.
        assertApproxEqAbs(paidSt, st, 3, "every stETH share reached the three receivers");
        assertEq(a.vaultEth + a.sdEth + a.gnEth, b.vaultEth + b.sdEth + b.gnEth, "no ETH moved");
    }

    /// @notice Mixed holdings: stETH pays first and the ETH call covers the remainder for whichever
    ///         receiver the stETH ran out on.
    function test_mixedSweepPaysStethFirstThenEth() public {
        _driveToGameOver();
        vm.deal(address(game), 40 ether);
        uint256 st0 = mockStETH.balanceOf(address(game));
        if (st0 < 20 ether) mockStETH.mint(address(game), 20 ether - st0);
        uint256 st = mockStETH.balanceOf(address(game));
        Ledger memory b = _ledger();
        _sweep();
        Ledger memory a = _ledger();
        assertEq(address(game).balance, 0, "ETH swept");
        assertEq(mockStETH.balanceOf(address(game)), 0, "stETH swept");
        uint256 paidEth = (a.vaultEth - b.vaultEth) + (a.sdEth - b.sdEth) + (a.gnEth - b.gnEth);
        uint256 paidSt = (a.vaultSt - b.vaultSt) + (a.sdSt - b.sdSt) + (a.gnSt - b.gnSt);
        assertEq(paidEth, 40 ether, "the ETH remainder reached the receivers");
        assertApproxEqAbs(paidSt, st, 3, "the stETH reached the receivers");
    }

    /// @notice Nothing to sweep: the stage completes without a payout and never reverts.
    function test_emptySweepCompletes() public {
        _driveToGameOver();
        vm.deal(address(game), 0);
        uint256 st = mockStETH.balanceOf(address(game));
        if (st != 0) {
            vm.prank(address(game));
            mockStETH.transfer(address(0xdead), st);
        }
        _sweep();
        assertEq(address(game).balance, 0);
        assertEq(mockStETH.balanceOf(address(game)), 0);
    }
}
