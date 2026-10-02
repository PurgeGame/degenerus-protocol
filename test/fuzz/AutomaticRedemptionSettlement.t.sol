// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

contract RedemptionTerminalSeeder is DegenerusGame {
    function end() external { gameOver = true; }
    function seedLiveRedemptionWord(uint256 word) external {
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        _setRngRequestActive(false);
        _setRngComplete(false);
        rngLockedFlag = false;
    }
}
contract RedemptionRejectEth {
    receive() external payable { revert(); }
}

contract AutomaticRedemptionSettlementTest is DeployProtocol {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    uint256 private fulfilled;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fundSubscription(1, 100 ether);
        _complete(2);
        vm.deal(address(sdgnrs), 10_000 ether);
        vm.startPrank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, alice, sdgnrs.totalSupply() / 20);
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, bob, sdgnrs.totalSupply() / 20);
        vm.stopPrank();
    }

    function _complete(uint256 word) internal {
        for (uint256 i; i < 500; ++i) {
            if (!game.advanceDue() && !game.rngLocked() && game.rngComplete()) return;
            game.mineFlip();
            uint256 req = mockVRF.lastRequestId();
            if (req != 0 && req != fulfilled) {
                (,, bool done) = mockVRF.pendingRequests(req);
                if (!done) mockVRF.fulfillRandomWords(req, word);
                fulfilled = req;
            }
        }
        revert("redemption fixture did not finish");
    }

    function _process(uint256 budget) internal returns (bool done) {
        done = sdgnrs.runRedemptionWork(budget).done;
    }

    function _burn(address player, uint256 amount) internal {
        vm.prank(player);
        sdgnrs.burn(amount);
    }

    function _resolve(uint24 day, uint16 roll, uint256 word) internal {
        vm.startPrank(address(game));
        sdgnrs.resolveRedemptionPeriod(roll, day);
        sdgnrs.beginRedemptionSettlement(day, word);
        vm.stopPrank();
        // This fixture injects a chosen roll instead of making a fresh request.
        // Match the already-drained session's published-word lifecycle too.
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RedemptionTerminalSeeder).runtimeCode);
        RedemptionTerminalSeeder(payable(address(game))).seedLiveRedemptionWord(word);
        vm.etch(address(game), original);
    }

    function test_AdvanceAutomaticallySettlesTopupsAndBothRecipients() public {
        uint24 day = game.currentDayView();
        uint256 amount = sdgnrs.totalSupply() / 1000;
        _burn(alice, amount);
        _burn(alice, amount);
        _burn(bob, amount);
        assertGt(sdgnrs.pendingRedemptionEthValue(), 0);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _complete(38_402); // 175% roll, losing escrow flip
        (uint96 a,,) = sdgnrs.pendingRedemptions(alice, day);
        (uint96 b,,) = sdgnrs.pendingRedemptions(bob, day);
        assertEq(a, 0);
        assertEq(b, 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertFalse(game.rngLocked());
    }

    function test_ManualFifoClaimThenKeeperCannotPayTwice() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        sdgnrs.claimRedemption(alice, day);
        uint256 remaining = sdgnrs.pendingRedemptionEthValue();
        vm.prank(address(game));
        assertFalse(_process(14_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), remaining);
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
    }

    function test_LiveSettlementDoesNotPushEthToRecipient() public {
        RedemptionRejectEth receiver = new RedemptionRejectEth();
        uint256 amount = sdgnrs.totalSupply() / 1000;
        vm.prank(address(game));
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, address(receiver), amount), amount);
        uint24 day = game.currentDayView();
        _burn(address(receiver), sdgnrs.balanceOf(address(receiver)));
        _resolve(day, 100, 99);
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(address(receiver).balance, 0);
    }

    function test_MaxCapMaximumRollAutoSettlementFitsGasCeiling() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        (uint96 base,,) = sdgnrs.pendingRedemptions(alice, day);
        assertEq(base, 160 ether);
        _resolve(day, 175, 99);
        vm.prank(address(game));
        uint256 beforeGas = gasleft();
        assertTrue(_process(9_000_000));
        uint256 used = beforeGas - gasleft() + 21_000;
        emit log_named_uint("maximum_redemption_settlement_gas", used);
        assertLe(used, 10_000_000);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_TerminalClaimHasNoExpiry() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RedemptionTerminalSeeder).runtimeCode);
        RedemptionTerminalSeeder(payable(address(game))).end();
        vm.etch(address(game), original);
        vm.warp(vm.getBlockTimestamp() + 2000 days);
        uint256 remaining = sdgnrs.pendingRedemptionEthValue();
        uint256 beforeBalance = alice.balance;
        vm.prank(alice);
        sdgnrs.claimRedemption(alice, day);
        assertEq(alice.balance - beforeBalance, remaining);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
}
