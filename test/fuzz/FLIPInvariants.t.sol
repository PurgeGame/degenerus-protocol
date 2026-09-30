// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FLIP} from "../../contracts/FLIP.sol";

/// @notice Exact supply deltas against deployed FLIP, including the vault intercept.
/// @dev The former MockFlipSupply copy could pass independently of production and
///      still assumed a 2M initial allowance. Fund reserves through the real API.
contract FlipCoinInvariantsTest is DeployProtocol {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    uint256 private constant MAX_AMOUNT = 100_000_000 ether;

    function setUp() public {
        _deployProtocol();
    }

    function _mint(address to, uint256 amount) private {
        vm.prank(address(game));
        coin.mintForGame(to, amount);
    }

    function _fundVault(uint256 amount) private {
        vm.prank(address(game));
        coin.vaultEscrow(amount);
    }

    function testFuzz_supplyInvariant_afterMint(uint128 raw, bool toVault) public {
        uint256 amount = bound(raw, 1, MAX_AMOUNT);
        uint256 supplyBefore = coin.totalSupply();
        uint256 allowanceBefore = coin.vaultMintAllowance();
        _mint(toVault ? address(vault) : ALICE, amount);
        assertEq(coin.totalSupply(), supplyBefore + (toVault ? 0 : amount));
        assertEq(coin.vaultMintAllowance(), allowanceBefore + (toVault ? amount : 0));
        assertEq(coin.balanceOf(ALICE), toVault ? 0 : amount);
        assertEq(coin.balanceOf(address(vault)), 0, "vault emissions are escrowed, never circulating");
    }

    function testFuzz_mintBurnRoundtrip(uint128 raw) public {
        uint256 amount = bound(raw, 1, MAX_AMOUNT);
        uint256 supplyBefore = coin.totalSupply();
        uint256 allowanceBefore = coin.vaultMintAllowance();
        _mint(ALICE, amount);
        vm.prank(address(game));
        coin.burnCoin(ALICE, amount);
        assertEq(coin.totalSupply(), supplyBefore);
        assertEq(coin.vaultMintAllowance(), allowanceBefore);
        assertEq(coin.balanceOf(ALICE), 0);
    }

    function testFuzz_transferToVault(uint128 raw) public {
        uint256 amount = bound(raw, 1, MAX_AMOUNT);
        _mint(ALICE, amount);
        uint256 supplyBefore = coin.totalSupply();
        uint256 allowanceBefore = coin.vaultMintAllowance();
        vm.prank(ALICE);
        coin.transfer(address(vault), amount);
        assertEq(coin.totalSupply(), supplyBefore - amount);
        assertEq(coin.vaultMintAllowance(), allowanceBefore + amount);
        assertEq(coin.balanceOf(ALICE), 0);
        assertEq(coin.balanceOf(address(vault)), 0);
    }

    function testFuzz_vaultMintTo(uint128 rawReserve, uint128 rawAmount) public {
        uint256 reserve = bound(rawReserve, 1, MAX_AMOUNT);
        uint256 amount = bound(rawAmount, 1, reserve);
        _fundVault(reserve);
        uint256 supplyBefore = coin.totalSupply();
        uint256 allowanceBefore = coin.vaultMintAllowance();
        vm.prank(address(vault));
        coin.vaultMintTo(ALICE, amount);
        assertEq(coin.totalSupply(), supplyBefore + amount);
        assertEq(coin.vaultMintAllowance(), allowanceBefore - amount);
        assertEq(coin.balanceOf(ALICE), amount);
    }

    function testFuzz_vaultMintTo_revertOnExceed(uint128 rawReserve, uint128 rawExtra) public {
        uint256 reserve = bound(rawReserve, 0, MAX_AMOUNT);
        uint256 extra = bound(rawExtra, 1, MAX_AMOUNT);
        _fundVault(reserve);
        uint256 allowanceBefore = coin.vaultMintAllowance();
        vm.prank(address(vault));
        vm.expectRevert(FLIP.Insufficient.selector);
        coin.vaultMintTo(ALICE, allowanceBefore + extra);
        assertEq(coin.vaultMintAllowance(), allowanceBefore);
        assertEq(coin.balanceOf(ALICE), 0);
    }

    function testFuzz_multiOp(uint128 rawMint, uint128 rawTransfer, uint128 rawBurn) public {
        uint256 mintAmount = bound(rawMint, 1, MAX_AMOUNT);
        uint256 transferAmount = bound(rawTransfer, 0, mintAmount);
        uint256 burnAmount = bound(rawBurn, 0, mintAmount - transferAmount);
        uint256 supplyBefore = coin.totalSupply();
        _mint(ALICE, mintAmount);
        vm.prank(ALICE);
        coin.transfer(BOB, transferAmount);
        vm.prank(address(game));
        coin.burnCoin(ALICE, burnAmount);
        assertEq(coin.balanceOf(ALICE), mintAmount - transferAmount - burnAmount);
        assertEq(coin.balanceOf(BOB), transferAmount);
        assertEq(coin.totalSupply(), supplyBefore + mintAmount - burnAmount);
    }
}
