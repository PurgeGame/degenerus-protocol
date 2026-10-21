// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FinalSweepPayoutLegs — the game-over final sweep's three bare payout calls cannot revert.
///
/// @notice Thirty days after game over the crank runs the final sweep, which pays the vault,
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

    /// @dev The sweep tx itself. No try/catch: a revert here is the failure these pins exist for.
    function _sweep() internal {
        vm.warp(block.timestamp + 30 days + 1);
        vm.prank(keeper);
        game.mineFlip(0);
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

    // ── VRF shutdown: best-effort after the sweep commits; any failure is ignored ─────

    /// @notice The healthy shutdown: the sweep cancels the subscription and routes Admin's LINK
    ///         to the vault.
    function test_sweepShutsDownTheSubscription() public {
        _driveToGameOver();
        mockLINK.mint(address(admin), 7 ether);
        uint256 vaultLink = mockLINK.balanceOf(ContractAddresses.VAULT);
        _sweep();
        assertEq(admin.subscriptionId(), 0, "subscription left live");
        assertEq(mockLINK.balanceOf(address(admin)), 0, "LINK left in Admin");
        assertEq(mockLINK.balanceOf(ContractAddresses.VAULT) - vaultLink, 7 ether, "LINK did not reach the vault");
    }

    /// @notice A coordinator that refuses the cancel — Chainlink's `PendingRequestExists`, the
    ///         normal state of a dead VRF — cannot block the sweep: `shutdownVrf` catches it
    ///         and still sweeps the LINK.
    function test_sweepSurvivesACoordinatorThatRefusesTheCancel() public {
        _driveToGameOver();
        mockLINK.mint(address(admin), 7 ether);
        vm.mockCallRevert(
            address(mockVRF),
            abi.encodeWithSelector(mockVRF.cancelSubscription.selector),
            abi.encodeWithSignature("PendingRequestExists()")
        );
        _sweep();
        assertEq(address(game).balance, 0, "the sweep did not pay out");
        assertEq(admin.subscriptionId(), 0, "the handle was not spent");
        assertEq(mockLINK.balanceOf(address(admin)), 0, "LINK left in Admin");
    }

    /// @notice A LINK transfer's explicit refusal or false return permits the sweep.
    function test_sweepSurvivesALinkTransferThatFails() public {
        _driveToGameOver();
        mockLINK.mint(address(admin), 7 ether);
        vm.mockCallRevert(address(mockLINK), abi.encodeWithSelector(mockLINK.transfer.selector),
            abi.encodeWithSignature("TransferRefused()"));
        uint256 snap = vm.snapshotState();
        _sweep();
        assertEq(address(game).balance, 0, "the sweep did not pay out (reverting LINK)");
        vm.revertToState(snap);

        vm.clearMockedCalls();
        vm.mockCall(address(mockLINK), abi.encodeWithSelector(mockLINK.transfer.selector), abi.encode(false));
        _sweep();
        assertEq(address(game).balance, 0, "the sweep did not pay out (false-returning LINK)");
    }

    /// @notice An empty-revert (gas-family) cancel cannot hold the sweep back: the shutdown is
    ///         best-effort after the sweep commits, so every sink is paid, the handle is spent and
    ///         Admin's LINK still reaches the vault.
    function test_emptyCancelFailureStillCommitsSweepAndRoutesLink() public {
        _assertShutdownFailureKeepsSweep(address(mockVRF), mockVRF.cancelSubscription.selector, true);
    }

    /// @notice An empty-revert LINK transfer cannot hold the sweep back either; the LINK it could
    ///         not move stays in Admin and nothing else is left half-done.
    function test_emptyLinkFailureStillCommitsSweepAndLeavesLinkInAdmin() public {
        _assertShutdownFailureKeepsSweep(address(mockLINK), mockLINK.transfer.selector, false);
    }

    function _assertShutdownFailureKeepsSweep(address target, bytes4 selector, bool linkMoves) private {
        _driveToGameOver();
        vm.deal(address(game), 90 ether);
        mockLINK.mint(address(admin), 7 ether);
        assertGt(admin.subscriptionId(), 0);
        uint256 held = address(game).balance + mockStETH.balanceOf(address(game));
        uint256 vaultLink = mockLINK.balanceOf(ContractAddresses.VAULT);
        Ledger memory b = _ledger();
        vm.mockCallRevert(target, abi.encodeWithSelector(selector), "");
        _sweep();
        Ledger memory a = _ledger();
        assertEq(address(game).balance, 0, "a failed shutdown held back the ETH sweep");
        assertEq(mockStETH.balanceOf(address(game)), 0, "a failed shutdown held back the stETH sweep");
        uint256 paid = (a.vaultEth - b.vaultEth) + (a.sdEth - b.sdEth) + (a.gnEth - b.gnEth)
            + (a.vaultSt - b.vaultSt) + (a.sdSt - b.sdSt) + (a.gnSt - b.gnSt);
        assertEq(paid, held, "every wei the game held reached the three sinks");
        assertEq(admin.subscriptionId(), 0, "the shutdown spends its handle once");
        if (linkMoves) {
            assertEq(mockLINK.balanceOf(address(admin)), 0, "LINK left in Admin");
            assertEq(mockLINK.balanceOf(ContractAddresses.VAULT) - vaultLink, 7 ether, "LINK did not reach the vault");
        } else {
            assertEq(mockLINK.balanceOf(address(admin)), 7 ether, "a failed LINK transfer moved LINK");
            assertEq(mockLINK.balanceOf(ContractAddresses.VAULT), vaultLink, "a failed LINK transfer credited the vault");
        }

        // The sweep is final: a later crank, healthy dependencies and all, neither re-pays the
        // sinks nor re-runs the shutdown.
        vm.clearMockedCalls();
        bytes32 settled = keccak256(abi.encode(_ledger()));
        uint256 adminLink = mockLINK.balanceOf(address(admin));
        vm.prank(keeper);
        try game.mineFlip(type(uint32).max) {} catch {}
        assertEq(keccak256(abi.encode(_ledger())), settled, "a later crank moved swept funds");
        assertEq(address(game).balance, 0);
        assertEq(admin.subscriptionId(), 0);
        assertEq(mockLINK.balanceOf(address(admin)), adminLink, "a later crank re-ran the shutdown");
    }

    /// @notice A shortfall below what the three sinks are owed — only an stETH loss larger than
    ///         the unclaimed cushion can cause one — splits what exists pro rata instead of
    ///         reverting, so the sweep still completes and every wei the game holds leaves it.
    function test_aShortfallSplitsWhatExistsProRata() public {
        // Afking deposits close at game over, so the sinks are funded before it.
        vm.deal(address(this), 21 ether);
        game.depositAfkingFunding{value: 12 ether}(game.walletIdOf(ContractAddresses.VAULT));
        game.depositAfkingFunding{value: 6 ether}(game.walletIdOf(ContractAddresses.SDGNRS));
        game.depositAfkingFunding{value: 3 ether}(game.walletIdOf(ContractAddresses.GNRUS));
        _driveToGameOver();
        uint256 oV = _owed(ContractAddresses.VAULT);
        uint256 oS = _owed(ContractAddresses.SDGNRS);
        uint256 oG = _owed(ContractAddresses.GNRUS);
        uint256 owed = oV + oS + oG;

        // The loss: every stETH wei gone and the ETH left below what the sinks are owed.
        uint256 st = mockStETH.balanceOf(address(game));
        if (st != 0) {
            vm.prank(address(game));
            mockStETH.transfer(address(0xdead), st);
        }
        uint256 funds = owed / 3;
        vm.deal(address(game), funds);

        Ledger memory b = _ledger();
        _sweep();
        Ledger memory a = _ledger();
        uint256 gotV = a.vaultEth - b.vaultEth;
        uint256 gotS = a.sdEth - b.sdEth;
        uint256 gotG = a.gnEth - b.gnEth;
        assertEq(address(game).balance, 0, "the sweep left ETH behind");
        assertEq(gotV + gotS + gotG, funds, "the legs do not sum to what existed");
        assertEq(gotV, (oV * funds) / owed, "vault leg not pro rata");
        assertEq(gotS, (oS * funds) / owed, "sDGNRS leg not pro rata");
    }

    function _owed(address sink) private view returns (uint256) {
        return game.claimableWinningsOf(sink) + game.afkingFundingOf(sink);
    }

    /// @notice Without a subscription `shutdownVrf` is a no-op, never a revert.
    function test_shutdownVrfWithoutASubscriptionIsANoOp() public {
        vm.prank(ContractAddresses.GAME);
        admin.shutdownVrf();
        assertEq(admin.subscriptionId(), 0);
        vm.prank(ContractAddresses.GAME);
        admin.shutdownVrf();
    }
}
