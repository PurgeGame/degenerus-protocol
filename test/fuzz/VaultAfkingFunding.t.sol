// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";

/// @title VaultAfkingFunding — the vault's prepaid afking ETH is vault reserve, moved only by the owner.
///
/// @notice The vault stages ETH into its game-side afking bucket (its own daily auto-buy and the
///         salvage-buyer fallback spend it). That ETH stays DGVE backing:
///           A  gate      — staging and recovery are vault-owner only.
///           B  round     — owner stages vault ETH and recovers it; DGVE's reserve never moves.
///           C  burn      — a DGVE burn larger than the vault's own balance withdraws the
///                          shortfall from afking and pays in full.
///           D  sweep     — the final sweep pays each protocol sink (vault, sDGNRS, GNRUS) its
///                          afking balance along with its claimable, and zeroes both.
contract VaultAfkingFunding is DeployProtocol {
    address internal keeper = address(0xBEEF);
    address internal stranger = address(0x5712A);
    address internal owner;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(keeper, 1_000 ether);
        vm.deal(stranger, 10 ether);
        mockVRF.fundSubscription(1, 100e18);
        owner = ContractAddresses.CREATOR;
        require(vault.isVaultOwner(owner), "fixture: CREATOR holds the DGVE majority");
        _afking0 = game.afkingFundingOf(address(vault));
    }

    // ---------------------------------------------------------------------
    // A. Owner gate
    // ---------------------------------------------------------------------

    function test_stagingAndRecoveryAreOwnerOnly() public {
        vm.deal(address(vault), 5 ether);
        vm.prank(owner);
        vault.gameDepositAfkingFunding(2 ether);

        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.recoverAfkingFunding();

        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.gameDepositAfkingFunding(1 ether);

        assertEq(game.afkingFundingOf(address(vault)), _afking0 + 2 ether, "a stranger moved nothing");
    }

    // ---------------------------------------------------------------------
    // B. Stage and recover
    // ---------------------------------------------------------------------

    function test_ownerStagesAndRecoversWithoutMovingTheReserve() public {
        vm.deal(address(vault), 5 ether);
        (uint256 eth0, ) = vault.previewEth(_dgveSupply());

        vm.prank(owner);
        vault.gameDepositAfkingFunding{value: 1 ether}(3 ether);
        assertEq(game.afkingFundingOf(address(vault)), _afking0 + 4 ether, "msg.value plus vault ETH staged");
        assertEq(address(vault).balance, 2 ether, "vault ETH left the vault");
        (uint256 eth1, uint256 st1) = vault.previewEth(_dgveSupply());
        assertEq(eth1 + st1, eth0 + 1 ether, "staged ETH still backs DGVE (only msg.value is new)");

        vm.prank(owner);
        vault.recoverAfkingFunding();
        assertEq(game.afkingFundingOf(address(vault)), 0, "everything recovered");
        assertEq(address(vault).balance, 2 ether + 4 ether + _afking0, "back in the vault");
        (uint256 eth2, uint256 st2) = vault.previewEth(_dgveSupply());
        assertEq(eth2 + st2, eth1 + st1, "recovery does not move the reserve");
    }

    function test_stagingMoreThanTheVaultHoldsReverts() public {
        vm.deal(address(vault), 1 ether);
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        vault.gameDepositAfkingFunding(2 ether);
    }

    // ---------------------------------------------------------------------
    // C. Burns draw on afking
    // ---------------------------------------------------------------------

    function test_burnEthWithdrawsTheShortfallFromAfking() public {
        vm.deal(address(vault), 10 ether);
        vm.prank(owner);
        vault.gameDepositAfkingFunding(9 ether);
        assertEq(address(vault).balance, 1 ether, "harness: the vault keeps 1 ETH on hand");

        uint256 supply = _dgveSupply();
        uint256 burn = supply / 2;
        (uint256 previewOut, uint256 previewSt) = vault.previewEth(burn);
        assertGt(previewOut + previewSt, 1 ether, "harness: the claim exceeds the vault's own balance");

        uint256 afkingBefore = game.afkingFundingOf(address(vault));
        uint256 ownerBefore = owner.balance;
        vm.prank(owner);
        (uint256 ethOut, uint256 stOut) = vault.burnEth(burn);

        assertEq(ethOut + stOut, previewOut + previewSt, "the burn pays what the preview promised");
        assertEq(owner.balance - ownerBefore, ethOut, "paid in ETH");
        assertEq(
            afkingBefore - game.afkingFundingOf(address(vault)),
            ethOut + stOut - 1 ether - _claimable0Net(),
            "only the shortfall came out of afking"
        );
    }

    // ---------------------------------------------------------------------
    // D. The final sweep pays each sink its afking balance
    // ---------------------------------------------------------------------

    function test_finalSweepPaysEachSinkItsAfkingAndClaimable() public {
        vm.startPrank(keeper);
        game.depositAfkingFunding{value: 3 ether}(ContractAddresses.VAULT);
        game.depositAfkingFunding{value: 5 ether}(ContractAddresses.SDGNRS);
        game.depositAfkingFunding{value: 7 ether}(ContractAddresses.GNRUS);
        vm.stopPrank();

        _driveToGameOver();
        // ETH-only sweep so every leg is an exact wei count.
        uint256 st = mockStETH.balanceOf(address(game));
        if (st != 0) {
            vm.prank(address(game));
            mockStETH.transfer(address(0xdead), st);
        }

        uint256 owedV = game.claimableWinningsOf(ContractAddresses.VAULT) + game.afkingFundingOf(ContractAddresses.VAULT);
        uint256 owedS = game.claimableWinningsOf(ContractAddresses.SDGNRS) + game.afkingFundingOf(ContractAddresses.SDGNRS);
        uint256 owedG = game.claimableWinningsOf(ContractAddresses.GNRUS) + game.afkingFundingOf(ContractAddresses.GNRUS);
        assertGe(owedV, 3 ether, "harness: the vault's afking survives to the sweep");
        assertGe(owedS, 5 ether, "harness: sDGNRS's afking survives to the sweep");
        assertGe(owedG, 7 ether, "harness: GNRUS's afking survives to the sweep");

        uint256 total = address(game).balance;
        uint256 third = (total - owedV - owedS - owedG) / 3;
        uint256 v0 = ContractAddresses.VAULT.balance;
        uint256 s0 = ContractAddresses.SDGNRS.balance;
        uint256 g0 = ContractAddresses.GNRUS.balance;

        vm.warp(block.timestamp + 30 days + 1);
        vm.prank(keeper);
        game.advanceGame();
        assertTrue(game.isFinalSwept(), "harness: the sweep ran");

        assertEq(ContractAddresses.VAULT.balance - v0, owedV + third, "vault: claimable + afking + a third");
        assertEq(ContractAddresses.SDGNRS.balance - s0, owedS + third, "sDGNRS: claimable + afking + a third");
        assertEq(
            ContractAddresses.GNRUS.balance - g0,
            owedG + (total - owedV - owedS - owedG - third - third),
            "GNRUS: claimable + afking + the rest"
        );
        assertEq(game.afkingFundingOf(ContractAddresses.VAULT), 0, "vault afking zeroed");
        assertEq(game.afkingFundingOf(ContractAddresses.SDGNRS), 0, "sDGNRS afking zeroed");
        assertEq(game.afkingFundingOf(ContractAddresses.GNRUS), 0, "GNRUS afking zeroed");
        assertEq(address(game).balance, 0, "the game is empty");
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /// @dev CREATOR (the DGVE owner) is this test contract; it receives burn payouts.
    receive() external payable {}

    /// @dev Whatever afking the vault staged at construction (its self-subscribe).
    uint256 internal _afking0;

    /// @dev DGVE's constructor supply (1T shares to CREATOR); no test burns before reading it.
    function _dgveSupply() internal pure returns (uint256) {
        return 1_000_000_000_000 * 1e18;
    }

    function _claimable0Net() internal view returns (uint256) {
        uint256 c = game.claimableWinningsOf(address(vault));
        return c <= 1 ? 0 : c - 1;
    }

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
}
