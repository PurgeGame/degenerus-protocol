// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title WwxrpGameMintScaleTest -- the vault owner's multiplier on WWXRP the game prints.
/// @notice Every WWXRP mint the pinned game contracts request (Game and its modules, Coinflip,
///         Jackpots) is multiplied by gameMintScale (whole number, default 1, no upper bound;
///         an oversized product saturates instead of reverting).
///         Trusted-minter apps mint the exact amount. Only the vault owner can set the scale.
contract WwxrpGameMintScaleTest is DeployProtocol {
    address private owner;
    address private player;
    address private app;

    event GameMintScaleSet(uint256 scale);

    function setUp() public {
        _deployProtocol();
        owner = makeAddr("scale_vault_owner");
        player = makeAddr("scale_player");
        app = makeAddr("scale_app");
        vm.mockCall(ContractAddresses.VAULT, abi.encodeWithSignature("isVaultOwner(address)", owner), abi.encode(true));
    }

    function _mintFrom(address minter, uint256 amount) private returns (uint256 minted) {
        uint256 before = wwxrp.balanceOf(player);
        vm.prank(minter);
        wwxrp.mintPrize(player, amount);
        minted = wwxrp.balanceOf(player) - before;
    }

    function testDefaultIsOneX() public {
        assertEq(wwxrp.name(), "Worthless Wrapped XRP");
        assertEq(wwxrp.gameMintScale(), 1, "deploy default 1x");
        assertEq(_mintFrom(ContractAddresses.GAME, 7 ether), 7 ether, "game mint unchanged at 1x");
    }

    function testFuzz_ScaleAppliesToEveryPinnedGameMinter(uint64 scale, uint128 amount) public {
        vm.expectEmit(false, false, false, true, address(wwxrp));
        emit GameMintScaleSet(scale);
        vm.prank(owner);
        wwxrp.setGameMintScale(scale);
        uint256 expected = uint256(amount) * scale;
        assertEq(_mintFrom(ContractAddresses.GAME, amount), expected, "Game scaled");
        assertEq(_mintFrom(ContractAddresses.COINFLIP, amount), expected, "Coinflip scaled");
        assertEq(_mintFrom(ContractAddresses.JACKPOTS, amount), expected, "Jackpots scaled");
    }

    function testZeroStopsGamePrintingButNotTrustedApps() public {
        vm.startPrank(owner);
        wwxrp.setGameMintScale(0);
        wwxrp.setTrustedMinter(app, true);
        vm.stopPrank();
        assertEq(_mintFrom(ContractAddresses.GAME, 5 ether), 0, "game prints nothing at 0");
        assertEq(_mintFrom(app, 5 ether), 5 ether, "trusted app mints the exact amount");
    }

    function testHugeRequestNeverReverts() public {
        vm.prank(owner);
        wwxrp.setGameMintScale(type(uint256).max);
        uint256 room = type(uint256).max - wwxrp.totalSupply();
        assertEq(_mintFrom(ContractAddresses.GAME, type(uint256).max), room, "saturates at the supply room");
        assertEq(_mintFrom(ContractAddresses.COINFLIP, 1), 0, "a full supply mints nothing, no revert");
    }

    function testFuzz_OverflowingProductSaturates(uint256 scale, uint256 amount) public {
        scale = bound(scale, 2, type(uint256).max);
        amount = bound(amount, type(uint256).max / scale + 1, type(uint256).max);
        vm.prank(owner);
        wwxrp.setGameMintScale(scale);
        uint256 room = type(uint256).max - wwxrp.totalSupply();
        assertEq(_mintFrom(ContractAddresses.JACKPOTS, amount), room, "overflow saturates");
    }

    /// @dev Trusted apps and the vault are never scaled, at any scale; a pinned game minter that
    ///      is also registered as trusted is still scaled (the pinned branch is checked first).
    function testFuzz_OnlyPinnedGameMintsAreScaled(uint64 scale, uint128 amount) public {
        vm.startPrank(owner);
        wwxrp.setGameMintScale(scale);
        wwxrp.setTrustedMinter(app, true);
        wwxrp.setTrustedMinter(ContractAddresses.COINFLIP, true);
        vm.stopPrank();
        assertEq(_mintFrom(app, amount), amount, "trusted app scaled");
        assertEq(_mintFrom(ContractAddresses.COINFLIP, amount), uint256(amount) * scale, "trusted pinned minter unscaled");
        uint256 before = wwxrp.balanceOf(player);
        vm.prank(owner);
        wwxrp.vaultMintTo(player, amount);
        assertEq(wwxrp.balanceOf(player) - before, amount, "vault mint scaled");
    }

    /// @dev The largest unsaturated request mints exactly amount * scale; one more saturates.
    function testFuzz_SaturationBoundaryIsExact(uint256 scale) public {
        scale = bound(scale, 2, type(uint128).max);
        vm.prank(owner);
        wwxrp.setGameMintScale(scale);
        uint256 edge = type(uint256).max / scale;
        uint256 room = type(uint256).max - wwxrp.totalSupply();
        uint256 expected = edge * scale;
        if (expected > room) expected = room;
        assertEq(_mintFrom(ContractAddresses.GAME, edge), expected, "edge request not exact");
    }

    function testOnlyVaultOwnerSetsAndThereIsNoCeiling() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSignature("NotVaultOwner()"));
        wwxrp.setGameMintScale(2);
        assertEq(wwxrp.gameMintScale(), 1, "unchanged");
        vm.prank(owner);
        wwxrp.setGameMintScale(1e30);
        assertEq(wwxrp.gameMintScale(), 1e30, "any scale accepted");
        assertEq(_mintFrom(ContractAddresses.GAME, 3), 3e30, "scaled by the large multiplier");
    }
}
