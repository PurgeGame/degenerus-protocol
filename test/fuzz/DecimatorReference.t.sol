// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DecimatorBattleHarness} from "./helpers/DecimatorBattleHarness.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

contract DecimatorReferenceTest is Test {
    DecimatorBattleHarness private h;
    DegenerusGameLens private lens;

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        h = new DecimatorBattleHarness();
        lens = new DegenerusGameLens();
        h.open(5);
    }

    function _burn(address owner, uint256 amount) private {
        vm.prank(ContractAddresses.COIN);
        h.recordFor(owner, 5, amount, 10_000, 0);
    }

    function test_AggregateTracksActualTopupAndDecay() public {
        _burn(address(1), 2001);
        _burn(address(2), 4000);
        vm.warp(block.timestamp + 1 days);
        _burn(address(1), 2001);
        assertEq(h.roundOf(5).totalCreditedStack, 7801);
        assertEq(h.roundOf(5).count, 2);
        assertEq(h.entryOf(5, 1).stack, 3801);
        assertEq(abi.encode(lens.decBattleRoundOf(address(h), 5)), abi.encode(h.roundOf(5)));
        h.seal(5, 0, 123);
        (uint64 stack, uint40 count, uint256 cap) = lens.decBurnReferenceOf(address(h));
        assertEq(stack, 7801);
        assertEq(count, 2);
        assertEq(cap, 15602);
        assertEq(h.seal(5, 1 ether, 456), 1 ether);
        (,, uint256 afterCap) = h.referenceOf();
        assertEq(afterCap, cap, "retry cannot rewrite the reference");
    }

    function test_BootstrapAndEmptySealDoNotWriteHistory() public {
        assertEq(h.seal(5, 10 ether, 123), 10 ether);
        (uint64 stack, uint40 count, uint256 cap) = h.referenceOf();
        assertEq(stack, 0);
        assertEq(count, 0);
        assertEq(cap, 8000);
    }

    function test_AggregateOverflowRevertsEntireNewEntryAndTopup() public {
        _burn(address(1), type(uint64).max);
        vm.expectRevert();
        _burn(address(2), 1);
        vm.expectRevert();
        _burn(address(1), 1);
        assertEq(h.roundOf(5).totalCreditedStack, type(uint64).max);
        assertEq(h.roundOf(5).count, 1);
        assertEq(h.entryOf(5, 1).stack, type(uint64).max);
        assertEq(h.entryOf(5, 2).owner, address(0));
        h.seal(5, 1 ether, 123);
        (,, uint256 cap) = h.referenceOf();
        assertEq(cap, uint256(type(uint64).max) * 4, "cap math must widen before multiplying");
    }

    function test_OversizedPoolReturnsUntouchedWithoutReference() public {
        _burn(address(1), 2000);
        uint128 pool = uint128(type(uint96).max) + 1;
        assertEq(h.seal(5, pool, 123), pool);
        assertEq(h.roundOf(5).phase, 0);
        assertEq(h.reserved(), 0);
        (, uint40 count,) = h.referenceOf();
        assertEq(count, 0);
    }

    function test_CountOverflowIsCheckedAnd8001stEntryIsAllowed() public {
        h.forceCount(5, 8000);
        _burn(address(1), 2000);
        assertEq(h.roundOf(5).count, 8001);
        h.forceCount(5, type(uint40).max);
        vm.expectRevert();
        _burn(address(2), 2000);
        assertEq(h.roundOf(5).count, type(uint40).max);
    }
}
