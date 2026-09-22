// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title WwxrpTrustedMintersTest -- the vault owner's trusted minter/burner registry on WWXRP.
/// @notice The vault owner (>50.1% of DGVE) may register any address to mint through mintPrize
///         and burn through burnForGame, exactly as the pinned game contracts can, and may revoke
///         it again. Nobody else may register, and an unregistered address keeps the old reverts.
contract WwxrpTrustedMintersTest is DeployProtocol {
    address private owner;
    address private stranger;
    address private futureGame;
    address private player;

    event TrustedMinterSet(address indexed account, bool trusted);

    function setUp() public {
        _deployProtocol();
        owner = makeAddr("wwxrp_vault_owner");
        stranger = makeAddr("wwxrp_stranger");
        futureGame = makeAddr("wwxrp_future_game");
        player = makeAddr("wwxrp_player");
        // Vault ownership is a DGVE-majority check on the vault; mock it for `owner` only.
        vm.mockCall(
            ContractAddresses.VAULT,
            abi.encodeWithSignature("isVaultOwner(address)", owner),
            abi.encode(true)
        );
    }

    function testOnlyTheVaultOwnerRegisters() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("NotVaultOwner()"));
        wwxrp.setTrustedMinter(futureGame, true);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        wwxrp.setTrustedMinter(address(0), true);

        vm.expectEmit(true, false, false, true, address(wwxrp));
        emit TrustedMinterSet(futureGame, true);
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, true);
        assertTrue(wwxrp.trustedMinter(futureGame), "registered");
    }

    function testUnregisteredAddressStillCannotMintOrBurn() public {
        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.mintPrize(player, 1 ether);

        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.burnForGame(player, 1 ether);
    }

    function testTrustedAddressMintsAndBurnsLikeTheGame() public {
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, true);

        uint256 supplyBefore = wwxrp.totalSupply();
        vm.prank(futureGame);
        wwxrp.mintPrize(player, 500 ether);
        assertEq(wwxrp.balanceOf(player), 500 ether, "minted to the player");
        assertEq(wwxrp.totalSupply(), supplyBefore + 500 ether, "supply grew");

        vm.prank(futureGame);
        wwxrp.burnForGame(player, 200 ether);
        assertEq(wwxrp.balanceOf(player), 300 ether, "burned from the player");
        assertEq(wwxrp.totalSupply(), supplyBefore + 300 ether, "supply shrank");

        // Zero-amount burn is a silent no-op, as for the game.
        vm.prank(futureGame);
        wwxrp.burnForGame(player, 0);
        assertEq(wwxrp.balanceOf(player), 300 ether, "zero burn is a no-op");
    }

    function testRevokedAddressLosesBothPowers() public {
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, true);
        vm.prank(futureGame);
        wwxrp.mintPrize(player, 1 ether);

        vm.expectEmit(true, false, false, true, address(wwxrp));
        emit TrustedMinterSet(futureGame, false);
        vm.prank(owner);
        wwxrp.setTrustedMinter(futureGame, false);
        assertFalse(wwxrp.trustedMinter(futureGame), "revoked");

        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.mintPrize(player, 1 ether);
        vm.prank(futureGame);
        vm.expectRevert(abi.encodeWithSignature("OnlyMinter()"));
        wwxrp.burnForGame(player, 1 ether);
    }

    function testPinnedMintersAreUnaffected() public {
        vm.prank(ContractAddresses.GAME);
        wwxrp.mintPrize(player, 7 ether);
        assertEq(wwxrp.balanceOf(player), 7 ether, "the game still mints");
        vm.prank(ContractAddresses.GAME);
        wwxrp.burnForGame(player, 7 ether);
        assertEq(wwxrp.balanceOf(player), 0, "the game still burns");
        assertFalse(wwxrp.trustedMinter(ContractAddresses.GAME), "pinned minters are not registry entries");
    }
}
