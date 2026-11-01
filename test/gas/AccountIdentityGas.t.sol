// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Run with FOUNDRY_ISOLATE=true; each measured call executes against committed prior state.
contract AccountIdentityGasTest is DeployProtocol {
    address private plain;
    address private operator;
    uint32 private plainId;
    uint256 private price;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        plain = makeAddr("gas-plain");
        operator = makeAddr("gas-operator");
        vm.deal(plain, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(address(this), 100 ether);
        plainId = _giveWalletId(plain);
        price = game.mintPrice();
        vm.prank(plain);
        game.setOperatorApproval(0, operator, true);
        game.depositAfkingFunding{value: 3 ether}(plainId);
        RecyclingState.seedWriteBuffer(address(game), 1);
    }

    function _report(string memory scenario) private {
        Vm.Gas memory used = vm.lastCallGas();
        emit log_named_uint(scenario, vm.snapshotGasLastCall("account-identity", scenario));
        emit log_named_uint(string.concat(scenario, "_gross"), used.gasTotalUsed);
        emit log_named_int(string.concat(scenario, "_refund_counter"), used.gasRefunded);
    }

    function test_Gas_PurchaseSelfByZero() public {
        vm.prank(plain);
        game.purchaseOrderFor{value: price}(0, 400, 0, 0, MintPaymentKind.DirectEth, false);
        _report("purchase_self_zero");
    }

    function test_Gas_PurchaseSelfById() public {
        vm.prank(plain);
        game.purchaseOrderFor{value: price}(plainId, 400, 0, 0, MintPaymentKind.DirectEth, false);
        _report("purchase_self_id");
    }

    function test_Gas_PurchaseByOperator() public {
        vm.prank(operator);
        game.purchaseOrderFor{value: price}(plainId, 400, 0, 0, MintPaymentKind.DirectEth, false);
        _report("purchase_operator");
    }

    function test_Gas_BetSelfById() public {
        vm.prank(plain);
        game.betDegenerette{value: 0.01 ether}(plainId, 0, 0.01 ether, 1, 3);
        _report("bet_self_id");
    }

    function test_Gas_BetByOperator() public {
        vm.prank(operator);
        game.betDegenerette{value: 0.01 ether}(plainId, 0, 0.01 ether, 1, 3);
        _report("bet_operator");
    }

    function test_Gas_WithdrawSelfById() public {
        vm.prank(plain);
        game.withdrawAfkingFunding(plainId, 1 ether);
        _report("withdraw_self_id");
    }

    function test_Gas_WithdrawByOperator() public {
        vm.prank(operator);
        game.withdrawAfkingFunding(plainId, 1 ether);
        _report("withdraw_operator");
    }

    function test_Gas_RecordPayoutPlain() public {
        vm.prank(ContractAddresses.COINFLIP);
        (, address payee) = game.payRecordSdgnrs(plainId, 100);
        _report("record_payout_plain");
        assertEq(payee, plain);
    }
}
