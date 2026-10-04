// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";

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

    /// @dev A dependency refusing one claim must not hold the cohort (and every later RNG
    ///      request): the claim parks with its word and settles later, once, for its player.
    function test_RefusedSettlementParksClaimAndCohortCompletes() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        // Strip custody so the live legs must pull stETH that is not there.
        uint256 eth = address(sdgnrs).balance;
        uint256 st = mockStETH.balanceOf(address(sdgnrs));
        vm.deal(address(sdgnrs), 0);
        vm.prank(address(sdgnrs));
        mockStETH.transfer(address(0xDEAD), st);

        vm.recordLogs();
        vm.prank(address(game));
        assertTrue(_process(9_000_000), "refused claims do not hold the cohort");
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserved, "parked reservations stay segregated");
        uint256 parked;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(sdgnrs)
                && logs[i].topics[0] == keccak256("RedemptionParked(address,uint24,bytes)")) ++parked;
        }
        assertEq(parked, 2);
        (uint96 a,,) = sdgnrs.pendingRedemptions(alice, day);
        assertGt(a, 0, "parked claim keeps its record");

        // Custody restored: only the player (or an approved operator) settles, exactly once.
        vm.deal(address(sdgnrs), eth);
        vm.prank(address(0xDEAD));
        mockStETH.transfer(address(sdgnrs), st);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        vm.prank(bob);
        sdgnrs.claimParkedRedemption(alice, day);
        uint256 before = game.claimableWinningsOf(alice);
        vm.prank(alice);
        sdgnrs.claimParkedRedemption(alice, day);
        assertGt(game.claimableWinningsOf(alice), before, "parked claim pays its direct half");
        (a,,) = sdgnrs.pendingRedemptions(alice, day);
        assertEq(a, 0);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(alice);
        sdgnrs.claimParkedRedemption(alice, day);
    }

    /// @dev The Game re-raises an out-of-gas module call as EmptyRevert(). Settlement must treat
    ///      it as caller-withheld gas and revert, never as a refusal that parks the claim.
    function test_OutOfGasGameModuleCallRevertsInsteadOfParking() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(DegenerusGame.resolveRedemptionLootbox.selector),
            abi.encodeWithSignature("EmptyRevert()"));
        vm.expectRevert(abi.encodeWithSignature("EmptyRevert()"));
        vm.prank(address(game));
        _process(9_000_000);
    }

    function _claimTranscript() internal returns (bytes32 digest) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            // Player awards and every Game/sDGNRS event must remain identical across
            // all three routes.
            if (logs[i].emitter == address(game) || logs[i].emitter == address(sdgnrs)) {
                digest = keccak256(abi.encode(digest, logs[i].emitter, logs[i].topics, logs[i].data));
            }
        }
        return keccak256(abi.encode(digest, game.claimableWinningsOf(alice), game.claimableWinningsOf(bob),
            coinflip.coinflipAmount(alice), coinflip.coinflipAmount(bob), sdgnrs.pendingRedemptionEthValue()));
    }

    function test_FrozenWordProducesSameTranscriptAcrossAllClaimRoutes() public {
        uint24 day = game.currentDayView();
        uint256 amount = sdgnrs.totalSupply() / 1000;
        _burn(alice, amount);
        _burn(bob, amount);
        _resolve(day, 100, 99);
        uint256 snapshot = vm.snapshotState();

        vm.recordLogs();
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        bytes32 automatic = _claimTranscript();
        assertTrue(vm.revertToState(snapshot));

        vm.recordLogs();
        sdgnrs.claimRedemption(alice, day);
        sdgnrs.claimRedemption(bob, day);
        vm.prank(address(game));
        assertTrue(_process(9_000_000)); // Clear only the already-drained cohort metadata.
        assertEq(_claimTranscript(), automatic, "single claims use the frozen cohort word");
        assertTrue(vm.revertToState(snapshot));

        address[] memory players = new address[](2);
        players[0] = alice;
        players[1] = bob;
        vm.recordLogs();
        sdgnrs.claimRedemptionMany(players, day);
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        assertEq(_claimTranscript(), automatic, "batch claims use the frozen cohort word");
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
