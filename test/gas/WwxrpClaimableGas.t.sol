// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

contract WwxrpClaimableGasTest is DeployProtocol {
    address private player = address(0xABC123);
    uint32 private id;
    function setUp() public {
        _deployProtocol(); id = _giveWalletId(player);
        vm.prank(address(game)); wwxrp.mintPrize(address(0x123456), 1);
    }
    function _report(string memory label) private {
        Vm.Gas memory used = vm.lastCallGas();
        emit log_named_uint(label, used.gasTotalUsed);
        emit log_named_int(string.concat(label, "_refund"), used.gasRefunded);
    }
    function test_Gas_DirectMintNewRecipient() public {
        vm.prank(address(game)); wwxrp.mintPrize(player, 100); _report("wwxrp_mint_new");
    }
    function test_Gas_CreditNewAccount() public {
        vm.prank(address(game)); wwxrp.creditPrize(id, 100); _report("wwxrp_credit_new");
    }
    function test_Gas_DirectMintExistingRecipient() public {
        vm.prank(address(game)); wwxrp.mintPrize(player, 100);
        vm.prank(address(game)); wwxrp.mintPrize(player, 100); _report("wwxrp_mint_existing");
    }
    function test_Gas_CreditExistingAccount() public {
        vm.prank(address(game)); wwxrp.creditPrize(id, 100);
        vm.prank(address(game)); wwxrp.creditPrize(id, 100); _report("wwxrp_credit_existing");
    }
    function test_Gas_BurnClaimableWithoutWalletLookup() public {
        vm.prank(address(game)); wwxrp.creditPrize(id, 100);
        vm.prank(address(game)); wwxrp.burnForAccount(id, 25); _report("wwxrp_burn_claimable");
    }
}
