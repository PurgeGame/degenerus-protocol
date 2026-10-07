// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

contract WwxrpClaimableTest is DeployProtocol {
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);
    uint32 private aliceId;

    function setUp() public {
        _deployProtocol();
        aliceId = _giveWalletId(alice);
    }

    function _credit(uint32 id, uint256 amount) private {
        vm.prank(address(game));
        wwxrp.creditPrize(id, amount);
    }

    function test_AwardTouchesOnlyTheIdLedgerAndNoSupplyOrWallet() public {
        uint256 supply = wwxrp.totalSupply();
        vm.expectCall(address(game), abi.encodeWithSelector(game.resolveAccount.selector), 0);
        vm.expectCall(address(game), abi.encodeWithSelector(game.walletIdOf.selector), 0);
        vm.record();
        _credit(aliceId, 100);
        (, bytes32[] memory writes) = vm.accesses(address(wwxrp));
        assertEq(writes.length, 1, "one reward-ledger write");
        assertEq(wwxrp.claimable(aliceId), 100);
        assertEq(wwxrp.totalSupply(), supply);
        assertEq(wwxrp.balanceOf(alice), 0);
        _credit(aliceId, 50);
        assertEq(wwxrp.claimable(aliceId), 150);
    }

    function test_WithdrawPartialAndAllNeverRegistersAndMintsExactlyOnce() public {
        _credit(aliceId, 100);
        vm.prank(alice); assertEq(wwxrp.withdraw(0, 35), 35);
        assertEq(wwxrp.balanceOf(alice), 35);
        assertEq(wwxrp.claimable(aliceId), 65);
        vm.prank(alice); assertEq(wwxrp.withdraw(aliceId, 0), 65);
        assertEq(wwxrp.balanceOf(alice), 100);
        assertEq(wwxrp.claimable(aliceId), 0);
        vm.prank(alice); assertEq(wwxrp.withdraw(0, 0), 0);
        vm.prank(bob); assertEq(wwxrp.withdraw(0, 0), 0);
        assertEq(game.walletIdOf(bob), 0);
    }

    function test_SmurfAndOwnerBalancesStaySeparateOperatorCannotRedirectWithdrawal() public {
        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(alice, price);
        vm.prank(alice);
        uint32 smurf = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        _credit(aliceId, 10);
        _credit(smurf, 70);
        vm.expectRevert(WWXRP.NotApproved.selector);
        vm.prank(bob); wwxrp.withdraw(smurf, 0);
        vm.prank(alice); game.setOperatorApproval(smurf, bob, true);
        vm.prank(bob); wwxrp.withdraw(smurf, 0);
        assertEq(wwxrp.balanceOf(alice), 70);
        assertEq(wwxrp.balanceOf(bob), 0);
        assertEq(wwxrp.claimable(smurf), 0);
        assertEq(wwxrp.claimable(aliceId), 10);
    }

    function test_DrawSpendsClaimableBeforeHeldAndRollsBackOnShortfall() public {
        _credit(aliceId, 50);
        vm.prank(ContractAddresses.VAULT); wwxrp.vaultMintTo(alice, 30);
        uint256 supply = wwxrp.totalSupply();
        vm.prank(alice); wwxrp.enter(0, 25);
        assertEq(wwxrp.claimable(aliceId), 25);
        assertEq(wwxrp.balanceOf(alice), 30);
        assertEq(wwxrp.totalSupply(), supply);
        vm.expectRevert(WWXRP.InsufficientBalance.selector);
        vm.prank(alice); wwxrp.enter(0, 56);
        assertEq(wwxrp.claimable(aliceId), 25, "failed draw restores claimable");
        vm.prank(alice); wwxrp.enter(0, 40);
        assertEq(wwxrp.claimable(aliceId), 0);
        assertEq(wwxrp.balanceOf(alice), 15);
        assertEq(wwxrp.totalSupply(), supply - 15);
    }

    function test_ScaleFreezesAtCreditAndWithdrawalDoesNotRescale() public {
        vm.mockCall(ContractAddresses.VAULT, abi.encodeWithSignature("isVaultOwner(address)", alice), abi.encode(true));
        vm.prank(alice); wwxrp.setGameMintScale(3);
        _credit(aliceId, 10);
        vm.prank(alice); wwxrp.setGameMintScale(0);
        _credit(aliceId, 10);
        assertEq(wwxrp.claimable(aliceId), 30);
        vm.prank(alice); wwxrp.withdraw(0, 0);
        assertEq(wwxrp.balanceOf(alice), 30);
    }

    function test_SaturationCannotRevertAwardsAndWithdrawalPreservesUnmintableRemainder() public {
        vm.prank(ContractAddresses.VAULT); wwxrp.vaultMintTo(alice, type(uint256).max);
        _credit(aliceId, type(uint256).max - 5);
        _credit(aliceId, 10);
        assertEq(wwxrp.claimable(aliceId), type(uint256).max);
        vm.prank(alice); assertEq(wwxrp.withdraw(0, 0), 0);
        assertEq(wwxrp.claimable(aliceId), type(uint256).max);
        vm.prank(address(game)); wwxrp.burnForGame(alice, 10);
        vm.prank(alice); assertEq(wwxrp.withdraw(0, 0), 10);
        assertEq(wwxrp.claimable(aliceId), type(uint256).max - 10);
        assertEq(wwxrp.totalSupply(), type(uint256).max);
    }

    function test_OnlyAuthorizedProducersAndZeroNeverAccrues() public {
        vm.expectRevert(WWXRP.OnlyMinter.selector);
        wwxrp.creditPrize(aliceId, 100);
        _credit(0, 100);
        assertEq(wwxrp.claimable(0), 0);
        _credit(aliceId, 100);
        vm.expectRevert(WWXRP.OnlyMinter.selector);
        wwxrp.burnForAccount(aliceId, 1);
        vm.expectCall(address(game), abi.encodeWithSelector(game.resolveAccount.selector), 0);
        vm.prank(address(game)); wwxrp.burnForAccount(aliceId, 40);
        assertEq(wwxrp.claimable(aliceId), 60);
    }

    function testFuzz_CreditWithdrawConsumeConserves(uint96 credited, uint96 wanted, uint96 spent) public {
        _credit(aliceId, credited);
        uint256 take = wanted == 0 || wanted > credited ? credited : wanted;
        vm.prank(alice); wwxrp.withdraw(0, wanted);
        uint256 burn = uint256(spent) % (uint256(credited) + 1);
        vm.prank(address(game)); wwxrp.burnForAccount(aliceId, burn);
        assertEq(wwxrp.balanceOf(alice) + wwxrp.claimable(aliceId), uint256(credited) - burn);
        assertLe(wwxrp.balanceOf(alice), take);
    }
}
