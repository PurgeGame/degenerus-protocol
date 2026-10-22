// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {claimableBalance} from "../helpers/ClaimableBalance.sol";

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

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

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
        require(vault.isVaultOwner(ContractAddresses.OWNER_GOVERNANCE), "fixture: governance holds owner authority");
        _afking0 = game.afkingFundingOf(address(vault));
    }

    // ---------------------------------------------------------------------
    // A. Owner gate
    // ---------------------------------------------------------------------

    function test_stagingAndRecoveryAreOwnerOnly() public {
        vm.deal(address(vault), 5 ether);
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (ContractAddresses.GAME, abi.encodeWithSignature("depositAfkingFunding(uint32)", 1), 2 ether)), 0), (bytes));

        uint256 recoverAmount0 = game.afkingFundingOf(address(vault));
        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.playerAction(
            ContractAddresses.GAME,
            abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", 0, recoverAmount0),
            0
        );

        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.playerAction(ContractAddresses.GAME, abi.encodeWithSignature("depositAfkingFunding(uint32)", 1), 1 ether);

        assertEq(game.afkingFundingOf(address(vault)), _afking0 + 2 ether, "a stranger moved nothing");
    }

    // ---------------------------------------------------------------------
    // B. Stage and recover
    // ---------------------------------------------------------------------

    function test_ownerStagesAndRecoversWithoutMovingTheReserve() public {
        vm.deal(address(vault), 5 ether);
        vm.deal(ContractAddresses.OWNER_GOVERNANCE, 1 ether);
        (uint256 eth0, ) = vault.previewEth(_dgveSupply());

        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("depositAfkingFunding(uint32)", 1),
            3 ether
        )), 1 ether), (bytes));
        assertEq(game.afkingFundingOf(address(vault)), _afking0 + 4 ether, "msg.value plus vault ETH staged");
        assertEq(address(vault).balance, 2 ether, "vault ETH left the vault");
        (uint256 eth1, uint256 st1) = vault.previewEth(_dgveSupply());
        assertEq(eth1 + st1, eth0 + 1 ether, "staged ETH still backs DGVE (only msg.value is new)");

        uint256 recoverAmount1 = game.afkingFundingOf(address(vault));
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", 0, recoverAmount1),
            0
        )), 0), (bytes));
        assertEq(game.afkingFundingOf(address(vault)), 0, "everything recovered");
        assertEq(address(vault).balance, 2 ether + 4 ether + _afking0, "back in the vault");
        (uint256 eth2, uint256 st2) = vault.previewEth(_dgveSupply());
        assertEq(eth2 + st2, eth1 + st1, "recovery does not move the reserve");
    }

    function test_stagingMoreThanTheVaultHoldsReverts() public {
        vm.deal(address(vault), 1 ether);
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (ContractAddresses.GAME, abi.encodeWithSignature("depositAfkingFunding(uint32)", 1), 2 ether)), 0), (bytes));
    }

    // ---------------------------------------------------------------------
    // C. Burns draw on afking
    // ---------------------------------------------------------------------

    function test_burnEthWithdrawsTheShortfallFromAfking() public {
        vm.deal(address(vault), 10 ether);
        vm.prank(owner);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (ContractAddresses.GAME, abi.encodeWithSignature("depositAfkingFunding(uint32)", 1), 9 ether)), 0), (bytes));
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
    // D. The final sweep pays the Vault and GNRUS their afking balance; sDGNRS's afking
    //    leaves claimablePool for the final prizes at game over
    // ---------------------------------------------------------------------

    function test_finalSweepPaysEachSinkItsAfkingAndClaimable() public {
        vm.startPrank(keeper);
        game.depositAfkingFunding{value: 3 ether}(_aid(ContractAddresses.VAULT));
        game.depositAfkingFunding{value: 5 ether}(_aid(ContractAddresses.SDGNRS));
        game.depositAfkingFunding{value: 7 ether}(_aid(ContractAddresses.GNRUS));
        vm.stopPrank();

        _driveToGameOver();
        // ETH-only sweep so every leg is an exact wei count.
        uint256 st = mockStETH.balanceOf(address(game));
        if (st != 0) {
            vm.prank(address(game));
            mockStETH.transfer(address(0xdead), st);
        }

        uint256 owedV = claimableBalance(game, ContractAddresses.VAULT) + game.afkingFundingOf(ContractAddresses.VAULT);
        uint256 owedS = claimableBalance(game, ContractAddresses.SDGNRS) + game.afkingFundingOf(ContractAddresses.SDGNRS);
        uint256 owedG = claimableBalance(game, ContractAddresses.GNRUS) + game.afkingFundingOf(ContractAddresses.GNRUS);
        assertGe(owedV, 3 ether, "harness: the vault's afking survives to the sweep");
        assertGe(owedG, 7 ether, "harness: GNRUS's afking survives to the sweep");
        // Terminal setup released sDGNRS's whole AFKing bucket, deposits included, to the final prizes.
        assertEq(game.afkingFundingOf(ContractAddresses.SDGNRS), 0, "sDGNRS's afking left for the final prizes");

        // Backed obligations only: each sink's 1-wei claimable sentinel is not ETH the game holds.
        uint256 total = address(game).balance;
        uint256 third = (total - owedV - owedS - owedG) / 3;
        uint256 v0 = ContractAddresses.VAULT.balance;
        uint256 s0 = ContractAddresses.SDGNRS.balance;
        uint256 g0 = ContractAddresses.GNRUS.balance;

        vm.warp(block.timestamp + 30 days + 1);
        vm.prank(keeper);
        game.mineFlip(0);
        assertTrue(game.isFinalSwept(), "harness: the sweep ran");

        assertEq(ContractAddresses.VAULT.balance - v0, owedV + third, "vault: claimable + afking + a third");
        assertEq(ContractAddresses.SDGNRS.balance - s0, owedS + third, "sDGNRS: claimable + a third");
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
}
