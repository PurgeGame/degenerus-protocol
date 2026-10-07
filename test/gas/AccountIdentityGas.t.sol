// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Run with FOUNDRY_ISOLATE=true; each measured call executes against committed prior state.
contract AccountIdentityGasTest is DeployProtocol {
    address private owner;
    address private plain;
    address private operator;
    address private freshOwner;
    uint32 private smurfId;
    uint32 private plainId;
    uint256 private price;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        owner = makeAddr("gas-owner");
        plain = makeAddr("gas-plain");
        operator = makeAddr("gas-operator");
        freshOwner = makeAddr("gas-fresh-owner");
        vm.deal(owner, 100 ether);
        vm.deal(plain, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(freshOwner, 100 ether);
        vm.deal(address(this), 100 ether);
        _giveWalletId(owner);
        plainId = _giveWalletId(plain);
        _giveWalletId(freshOwner);
        price = game.mintPrice();
        vm.prank(owner);
        smurfId = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, true);
        vm.prank(plain);
        game.setOperatorApproval(0, operator, true);
        game.depositAfkingFunding{value: 3 ether}(smurfId);
        game.depositAfkingFunding{value: 3 ether}(plainId);
        RecyclingState.seedWriteBuffer(address(game), 1);
    }

    function _report(string memory scenario) private {
        Vm.Gas memory used = vm.lastCallGas();
        emit log_named_uint(scenario, vm.snapshotGasLastCall("account-identity", scenario));
        emit log_named_uint(string.concat(scenario, "_gross"), used.gasTotalUsed);
        emit log_named_int(string.concat(scenario, "_refund_counter"), used.gasRefunded);
    }

    function test_Gas_CreateFirstSmurf() public {
        vm.prank(freshOwner);
        game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        _report("create_first_smurf");
    }

    function test_Gas_CreateAdditionalSmurf() public {
        vm.prank(owner);
        game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        _report("create_additional_smurf");
    }

    function test_Gas_PurchaseSelfByZero() public {
        vm.prank(plain);
        game.purchase{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        _report("purchase_self_zero");
    }

    function test_Gas_PurchaseSelfById() public {
        vm.prank(plain);
        game.purchase{value: price}(plainId, 400, 0, 0, MintPaymentKind.DirectEth, false);
        _report("purchase_self_id");
    }

    function test_Gas_PurchaseSmurfByOwner() public {
        vm.prank(owner);
        game.purchase{value: price}(smurfId, 400, 0, 0, MintPaymentKind.DirectEth, false);
        _report("purchase_smurf_owner");
    }

    function test_Gas_PurchaseSmurfByOperator() public {
        vm.prank(operator);
        game.purchase{value: price}(smurfId, 400, 0, 0, MintPaymentKind.DirectEth, false);
        _report("purchase_smurf_operator");
    }

    function test_Gas_BetSelfById() public {
        vm.prank(plain);
        game.placeDegeneretteBet{value: 0.01 ether}(plainId, 0, 0.01 ether, 1, 3);
        _report("bet_self_id");
    }

    function test_Gas_BetSmurfByOwner() public {
        vm.prank(owner);
        game.placeDegeneretteBet{value: 0.01 ether}(smurfId, 0, 0.01 ether, 1, 3);
        _report("bet_smurf_owner");
    }

    function test_Gas_BetSmurfByOperator() public {
        vm.prank(operator);
        game.placeDegeneretteBet{value: 0.01 ether}(smurfId, 0, 0.01 ether, 1, 3);
        _report("bet_smurf_operator");
    }

    function test_Gas_WithdrawSelfById() public {
        vm.prank(plain);
        game.withdrawAfkingFunding(plainId, 1 ether);
        _report("withdraw_self_id");
    }

    function test_Gas_WithdrawSmurfByOwner() public {
        vm.prank(owner);
        game.withdrawAfkingFunding(smurfId, 1 ether);
        _report("withdraw_smurf_owner");
    }

    function test_Gas_WithdrawSmurfByOperator() public {
        vm.prank(operator);
        game.withdrawAfkingFunding(smurfId, 1 ether);
        _report("withdraw_smurf_operator");
    }

    function test_Gas_RecordPayoutPlain() public {
        vm.prank(ContractAddresses.COINFLIP);
        (, address payee) = game.payRecordSdgnrs(plainId, 100);
        _report("record_payout_plain");
        assertEq(payee, plain);
    }

    function test_Gas_RecordPayoutSmurf() public {
        vm.prank(ContractAddresses.COINFLIP);
        (, address payee) = game.payRecordSdgnrs(smurfId, 100);
        _report("record_payout_smurf");
        assertEq(payee, owner);
    }
}
