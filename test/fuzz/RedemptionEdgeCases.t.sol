// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Regression coverage for request-bound, forward-priced redemption batches.
contract RedemptionEdgeCasesTest is RedemptionFixture {

    function testFuzz_MinimumBurn(uint256 seed) public {
        uint256 amount = bound(seed, 1, 1 ether - 1);
        vm.expectRevert(sDGNRS.BurnTooSmall.selector);
        _burn(alice, amount);
    }
    function test_ZeroAndExcessBalanceRejected() public {
        vm.expectRevert(sDGNRS.Insufficient.selector); _burn(alice, 0);
        uint256 excess = sdgnrs.balanceOf(alice) + 1;
        vm.expectRevert(sDGNRS.Insufficient.selector); _burn(alice, excess);
    }
    function test_DailyCapSharedAcrossBatches() public {
        uint256 n = sdgnrs.totalSupply() * 16 / 1000;
        _burn(alice, n);
        _resolveLive(100); assertTrue(_work(9_000_000));
        vm.expectRevert(sDGNRS.ExceedsDailyRedemptionCap.selector); _burn(alice, 1 ether);
    }
    function test_DailyCapResetsWhileOpenBatchRetainsTokens() public {
        uint256 n = sdgnrs.totalSupply() * 8 / 1000;
        uint32 id = _openBatchId();
        _burn(alice, 2 * n);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _burn(alice, n);
        assertEq(_openBatchId(), id);
        assertEq(_claimTokens(alice, id), 3 * n);
    }
    function test_BatchSupplyCapIsExactInRawUnits() public {
        vm.deal(address(sdgnrs), 1 ether);
        uint256 supply = sdgnrs.totalSupply();
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Affiliate, alice, supply * 3 / 10);
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Lootbox, alice, supply / 5);
        _burn(alice, supply / 2);
        vm.expectRevert(sDGNRS.Insufficient.selector); _burn(bob, 1 ether);
        (uint32 id,) = _state();
        (uint128 burned,uint128 snapshot,,,,) = sdgnrs.redemptionBatches(id);
        assertEq(burned, snapshot / 2);
    }
    function test_CloseEmptyOrWhilePriorBatchSettlesIsNoOp() public {
        uint32 id = _openBatchId();
        assertEq(_closeAsGame(), 0); assertEq(_openBatchId(), id);
        _burn(alice, sdgnrs.totalSupply() / 1000); _closeAsGame();
        _burn(bob, sdgnrs.totalSupply() / 1000);
        uint256 escrow = _escrow();
        assertEq(_closeAsGame(), 0);
        assertEq(_escrow(), escrow); assertEq(_openBatchId(), id + 1);
    }
    function testFuzz_UnknownBatchClaimRejected(uint32 seed) public {
        uint32 id = uint32(bound(seed, 2, type(uint32).max));
        _latchGameOver();
        vm.expectRevert(sDGNRS.NotResolved.selector);
        vm.prank(alice); sdgnrs.claimRedemption(0, id);
    }
    function test_ClaimBeforeResolutionAndLiveManualClaimRejected() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 id = _openBatchId(); _closeAsGame();
        vm.expectRevert(sDGNRS.NotResolved.selector); vm.prank(alice); sdgnrs.claimRedemption(0, id);
        _terminalize();
        uint32 aliceId = game.walletIdOf(alice);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        vm.prank(bob); sdgnrs.claimRedemption(aliceId, id);
    }
    function test_BurnBlockedDuringLiveness() public {
        vm.warp(vm.getBlockTimestamp() + 31 days);
        assertTrue(game.livenessTriggered());
        vm.expectRevert(sDGNRS.BurnsBlockedDuringLiveness.selector);
        _burn(alice, 1 ether);
    }
    function test_ZeroValueClaimStillClearsItsTokens() public {
        vm.deal(address(sdgnrs), 0);
        _burn(alice, 1 ether);
        uint32 id = _resolveLive(21);
        assertTrue(_work(9_000_000));
        assertEq(_claimTokens(alice, id), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }
    function test_DustLootboxReturnsToBacking() public {
        uint256 n = sdgnrs.totalSupply() / 1_000_000;
        _burn(alice, n);
        uint32 id = _resolveLive(100);
        uint256 base = _claimBase(alice, id);
        uint256 before = game.claimableWinningsOf(alice);
        assertTrue(_work(9_000_000));
        assertEq(game.claimableWinningsOf(alice) - before, base / 2);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
    function test_ActivityScoreFrozenOnFirstBurn() public {
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScore.selector, alice), abi.encode(uint256(100), game.walletIdOf(alice)));
        uint32 id = _openBatchId();
        _burn(alice, 1 ether);
        vm.mockCall(address(game), abi.encodeWithSelector(game.playerActivityScore.selector, alice), abi.encode(uint256(200), game.walletIdOf(alice)));
        _burn(alice, 1 ether);
        (,uint16 score) = sdgnrs.pendingRedemptions(game.walletIdOf(alice), id);
        assertEq(score, 101);
    }
    function testFuzz_TerminalClaimPaysExactlyOnce(uint16 seed) public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint16 roll = uint16(bound(seed, 21, 175));
        uint32 id = _resolveLive(roll);
        uint256 expected = _claimBase(alice,id) * roll / 100;
        _terminalize();
        uint256 before = _received(alice);
        vm.prank(alice); sdgnrs.claimRedemption(0, id);
        assertEq(_received(alice) - before, expected);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(alice); sdgnrs.claimRedemption(0, id);
    }
    function test_OperatorCanClaimTerminalForOwnerOnly() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 id = _resolveLive(100); _terminalize();
        uint32 aliceId = game.walletIdOf(alice);
        vm.prank(alice); game.setOperatorApproval(0, bob, true);
        uint256 before = _received(alice); uint256 opBefore = _received(bob);
        vm.prank(bob); sdgnrs.claimRedemption(aliceId, id);
        assertGt(_received(alice), before); assertEq(_received(bob), opBefore);
    }

}
