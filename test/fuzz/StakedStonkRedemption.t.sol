// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Regression coverage for request-bound, forward-priced redemption batches.
contract StakedStonkRedemptionTest is RedemptionFixture {

    function test_BurnBeforeDailyRngJoinsOpenBatch() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint32 id = _openBatchId();
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n);
        assertEq(_claimTokens(alice, id), n);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
    function testFuzz_BurnRecordsTokensAndAggregates(uint128 seed) public {
        uint256 n = bound(seed, 1e12, sdgnrs.totalSupply() / 2000);
        uint32 id = _openBatchId();
        uint256 supply = sdgnrs.totalSupply();
        _burn(alice, n); _burn(alice, n);
        assertEq(_claimTokens(alice, id), 2 * n);
        assertEq(sdgnrs.totalSupply(), supply - 2 * n);
        assertEq(_escrow(), 2 * n);
    }
    function test_OnlyGameClosesAndResolves() public {
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.closeRedemptionBatch(0);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.resolveTerminalRedemptions();
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.runRedemptionWork(99, 9_000_000);
    }
    function test_PriceIsFixedAtCloseNotBurn() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        vm.deal(address(sdgnrs), 20_000 ether);
        uint32 id = _resolveLive(100);
        assertEq(_claimBase(alice, id), 20 ether);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 20 ether);
        assertTrue(_work(9_000_000));
        assertEq(_claimTokens(alice, id), 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
    function test_FlipRemovedAtCloseAndNotAtBurn() public {
        _seedFlipBacking(1_000_000);
        vm.prank(address(sdgnrs));
        uint256 before = coinflip.redeemableFlipBacking();
        uint256 supply = sdgnrs.totalSupply();
        _burn(alice, supply / 1000);
        vm.prank(address(sdgnrs));
        assertEq(coinflip.redeemableFlipBacking(), before);
        uint32 id = _openBatchId();
        _closeAsGame();
        (,,,uint96 escrow,,) = sdgnrs.redemptionBatches(id);
        assertEq(escrow, before / 1000);
        vm.prank(address(sdgnrs));
        assertEq(coinflip.redeemableFlipBacking(), before - escrow);
    }
    function testFuzz_FlipWinOrLossUsesBatchSyntheticResult(uint256 seed) public {
        _seedFlipBacking(1_000_000);
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 id = _openBatchId();
        _closeAsGame();
        settlementWord = uint256(keccak256(abi.encode(seed))) | 2;
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage()"), abi.encode(uint8(1)));
        _work(200_000);
        (,,,uint96 escrow,,uint16 reward) = sdgnrs.redemptionBatches(id);
        assertEq(reward, _synthReward(settlementWord, id));
        // Isolate synthetic FLIP from additional box awards while retaining real funding.
        vm.mockCall(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector), bytes(""));
        uint256 before = coinflip.coinflipAmount(alice);
        assertTrue(_work(9_000_000));
        uint256 expected = reward == 0 ? 0 : uint256(escrow) + uint256(escrow) * reward / 100;
        assertEq(coinflip.coinflipAmount(alice) - before, expected);
    }
    function test_FlipWithdrawalClampsAndReportsActualRemoval() public {
        _seedFlipBacking(1_000_000);
        vm.prank(address(sdgnrs));
        uint256 backing = coinflip.redeemableFlipBacking();
        vm.prank(address(sdgnrs));
        assertEq(coinflip.withdrawRedeemedFlip(type(uint256).max), backing);
        vm.prank(address(sdgnrs));
        assertEq(coinflip.withdrawRedeemedFlip(1), 0);
        vm.prank(address(sdgnrs));
        assertEq(coinflip.redeemableFlipBacking(), 0);
    }

    function test_TwoClaimantsShareClosePriceAndSettleWithoutUnderflow() public {
        uint256 n = sdgnrs.totalSupply() / 1000;
        _burn(alice, n); _burn(bob, n);
        uint32 id = _resolveLive(175);
        assertEq(_claimBase(alice, id), _claimBase(bob, id));
        assertTrue(_work(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(_claimTokens(alice, id) + _claimTokens(bob, id), 0);
    }

}
