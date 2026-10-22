// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusJackpots} from "../../contracts/DegenerusJackpots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract BafStorageReuseTest is Test {
    DegenerusJackpots private jp;
    uint32 private constant ID = 42;

    function setUp() public {
        jp = new DegenerusJackpots();
        vm.mockCall(ContractAddresses.WWXRP, abi.encodeWithSignature("creditPrize(uint32,uint256)"), hex"");
    }

    function _slot(uint24 bracket) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(uint256(ID), uint256(0)))) + ((bracket / 10) & 1));
    }

    function _word(uint24 bracket) private view returns (uint256) { return uint256(vm.load(address(jp), _slot(bracket))); }

    function _credit(uint24 bracket, uint256 amount) private {
        vm.prank(ContractAddresses.COINFLIP);
        jp.recordBafFlip(ID, bracket, amount);
    }

    function _skip(uint24 bracket) private {
        vm.prank(ContractAddresses.GAME);
        jp.markBafSkipped(bracket);
    }

    function test_closingAndNextCoexistThenReuseAfterFinalization() public {
        _credit(10, 2000);
        _credit(20, 3000);
        assertEq(uint168(_word(10)), 2000);
        assertEq(uint168(_word(20)), 3000);
        vm.prank(ContractAddresses.GAME);
        jp.finalizeBaf(10);
        _credit(30, 4000);
        assertEq(uint24(_word(30) >> 232), 30);
        assertEq(uint168(_word(30)), 4000);
        assertEq(uint168(_word(20)), 3000, "next bracket preserved");
    }

    // Deliberately bypass Coinflip's Game-derived bracket and Game's stage ordering.
    // The recorder has no defensive revert; production lifetime safety is supplied
    // by those callers, not by rejecting an authorized credit here.
    function test_outOfSequenceAuthorizedCreditDoesNotBlock() public {
        _credit(10, 2000);
        _credit(30, 4000);
        assertEq(uint24(_word(30) >> 232), 30);
        assertEq(uint168(_word(30)), 4000);
    }

    function test_oldConsolationExpiresAndCannotConsumeNewOccupant() public {
        _credit(10, 2000);
        _skip(10);
        assertEq(jp.bafConsolationOfId(ID, 10), 2);
        _credit(30, 5000);
        _skip(30);
        assertEq(jp.bafConsolationOfId(ID, 10), 0);
        assertEq(jp.bafConsolationOfId(ID, 30), 5);
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        jp.claimBafConsolation(ID, 10);
        assertEq(uint168(_word(30)), 5000);
        jp.claimBafConsolation(ID, 30);
        assertEq(uint168(_word(30)), 0);
        assertEq(uint24(_word(30) >> 232), 30, "claimed word remains allocated");
        vm.expectRevert(DegenerusJackpots.NothingToClaim.selector);
        jp.claimBafConsolation(ID, 30);
    }

    function test_saturationCannotWrapIntoEpochOrBracket() public {
        _credit(10, type(uint256).max);
        _credit(10, type(uint256).max);
        assertEq(uint168(_word(10)), type(uint168).max);
        assertEq(uint64(_word(10) >> 168), 0);
        assertEq(uint24(_word(10) >> 232), 10);
    }

    function test_manyBracketsReuseExactlyTwoPlayerWords() public {
        for (uint24 bracket = 10; bracket <= 1000; bracket += 10) {
            _credit(bracket, bracket);
            assertEq(uint168(_word(bracket)), bracket);
            assertEq(uint24(_word(bracket) >> 232), bracket);
            _skip(bracket);
        }
        assertEq(_slot(10), _slot(990));
        assertEq(_slot(20), _slot(1000));
        assertEq(uint24(_word(990) >> 232), 990);
        assertEq(uint24(_word(1000) >> 232), 1000);
    }
}
