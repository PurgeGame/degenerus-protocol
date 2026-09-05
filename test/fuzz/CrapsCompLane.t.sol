// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The craps comp lane inside the REAL FLIP: an accounting allowance the table feeds and a
///      comp burn spends, that is never a balance, never supply and never the vault's mint
///      allowance.
contract CrapsCompLane is DeployProtocol {
    uint256 internal constant INITIAL = 4_560_000 ether;
    uint256 internal constant COMP = 0x10;

    address internal player = makeAddr("player");

    function setUp() public {
        _deployProtocol();
    }

    function test_theLaneOpensOnTheConvertedPassAllowance() public view {
        assertEq(coin.crapsCompAllowance(), INITIAL, "the lane did not open on 200 passes' worth");
        assertEq(coin.crapsCompAllowance(), 200 * 22_800 ether, "the conversion is not 200 x 22,800");
    }

    function test_onlyTheTableFeedsTheLane() public {
        vm.expectRevert(FLIP.OnlyGame.selector);
        coin.creditCrapsComps(1 ether);
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(FLIP.OnlyGame.selector);
        coin.creditCrapsComps(1 ether);
        vm.prank(ContractAddresses.CRAPS);
        coin.creditCrapsComps(7 ether);
        assertEq(coin.crapsCompAllowance(), INITIAL + 7 ether, "the credit did not land");
    }

    function test_aCompBurnChargesTheLaneAndNobodyElse() public {
        uint256 supply = coin.totalSupply();
        uint256 uncirculated = coin.supplyIncUncirculated();
        uint256 vaultAllowance = coin.vaultMintAllowance();
        vm.prank(ContractAddresses.CRAPS);
        uint8 mask = coin.burnCoinForCraps(player, (1_000 ether) | COMP);
        assertEq(mask, 0, "a comp consumed a boon");
        assertEq(coin.crapsCompAllowance(), INITIAL - 1_000 ether, "the lane was not charged the gross");
        assertEq(coin.balanceOf(player), 0, "the recipient's balance moved");
        assertEq(coin.totalSupply(), supply, "a comp changed supply");
        assertEq(coin.supplyIncUncirculated(), uncirculated, "a comp changed the uncirculated figure");
        assertEq(coin.vaultMintAllowance(), vaultAllowance, "a comp touched the vault's mint allowance");
    }

    function test_theLaneRefusesWhatItCannotCover() public {
        vm.prank(ContractAddresses.CRAPS);
        vm.expectRevert(FLIP.Insufficient.selector);
        coin.burnCoinForCraps(player, (INITIAL + 1 ether) | COMP);
        assertEq(coin.crapsCompAllowance(), INITIAL, "a refused comp moved the lane");
    }

    function test_theCompBitIsTheTablesAlone() public {
        vm.expectRevert(FLIP.OnlyGame.selector);
        coin.burnCoinForCraps(player, (1 ether) | COMP);
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(FLIP.OnlyGame.selector);
        coin.burnCoinForCraps(player, (1 ether) | COMP);
    }

    function test_theLaneIsNotTheVaultsMintAllowance() public {
        // The lane holds millions; the vault's own allowance does not. A vault mint against the
        // lane's figure must fail on the vault allowance alone.
        uint256 allowance = coin.vaultMintAllowance();
        assertLt(allowance, INITIAL, "the fixture's vault allowance already covers the probe");
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(FLIP.Insufficient.selector);
        coin.vaultMintTo(player, INITIAL);
        assertEq(coin.balanceOf(ContractAddresses.VAULT), allowance, "balanceOf(VAULT) reports the lane");
    }

    function test_aPaidBurnStillBurnsThePlayer() public {
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(player, 5_000 ether);
        uint256 lane = coin.crapsCompAllowance();
        vm.prank(ContractAddresses.CRAPS);
        coin.burnCoinForCraps(player, 1_000 ether);
        assertEq(coin.balanceOf(player), 4_000 ether, "the paid burn did not burn the player");
        assertEq(coin.crapsCompAllowance(), lane, "a paid burn touched the lane");
    }
}
