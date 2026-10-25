// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {GNRUS} from "../../contracts/GNRUS.sol";

contract PlayerErrorsTest is DeployProtocol {
    address private constant PLAYER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);

    function setUp() public {
        _deployProtocol();
        _giveWalletId(PLAYER);
        vm.prank(address(game)); coin.mintForGame_g152734(PLAYER, 100);
    }

    function testTransferShortfallIsNamedAndAtomic() public {
        uint256 supply = coin.totalSupply();
        vm.prank(PLAYER);
        vm.expectRevert(FLIP.InsufficientBalance.selector);
        coin.transfer(RECIPIENT, 101);
        assertEq(coin.balanceOf(PLAYER), 100);
        assertEq(coin.balanceOf(RECIPIENT), 0);
        assertEq(coin.totalSupply(), supply);
    }

    function testAllowanceShortfallIsNamedAndAtomic() public {
        vm.prank(PLAYER); coin.approve(address(this), 50);
        vm.expectRevert(FLIP.InsufficientAllowance.selector);
        coin.transferFrom(PLAYER, RECIPIENT, 51);
        assertEq(coin.allowance(PLAYER, address(this)), 50);
        assertEq(coin.balanceOf(PLAYER), 100);
    }

    function testDepositBurnShortfallIsNamedAndAtomic() public {
        uint256 supply = coin.totalSupply();
        vm.prank(PLAYER);
        vm.expectRevert(FLIP.InsufficientBalance.selector);
        coinflip.playCoinflip(0, 1_000);
        assertEq(coin.balanceOf(PLAYER), 100);
        assertEq(coin.totalSupply(), supply);
    }

    function testGnrusOverburnIsNamedAndAtomic() public {
        uint256 supply = gnrus.totalSupply();
        vm.prank(PLAYER);
        vm.expectRevert(GNRUS.InsufficientBalance.selector);
        gnrus.burn(1 ether);
        assertEq(gnrus.balanceOf(PLAYER), 0);
        assertEq(gnrus.totalSupply(), supply);
    }
}
