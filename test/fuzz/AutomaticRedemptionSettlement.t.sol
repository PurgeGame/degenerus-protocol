// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
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
        ticketsFullyProcessed = true;
        rngLockedFlag = false;
    }
}
contract RedemptionRejectEth {
    receive() external payable { revert(); }
}

contract AutomaticRedemptionSettlementTest is RedemptionFixture {
    function _process(uint256 budget) internal returns (bool done) {
        done = sdgnrs.runRedemptionWork(settlementWord, budget).done;
    }
    function _redemptionCursor() internal view returns (uint256) { return _cursor(); }
    function _oneClaimAllowance() internal returns (uint256) { return _oneClaimBudget(); }
    function _settleClaimAt(uint256 budget) internal {
        uint256 before = _cursor();
        _work(budget);
        assertTrue(_cursor() == before + 1 || !sdgnrs.redemptionSettlementPending());
    }
    function _settleOneClaim() internal { _settleClaimAt(_oneClaimAllowance()); }
    /// @dev Close and resolve using an actual batch word whose roll matches the fixture.
    function _resolve(uint32 batchId, uint16 roll, uint256 entropy) internal {
        assertEq(batchId, _openBatchId());
        _closeAsGame();
        settlementWord = ((entropy % (type(uint256).max / 155 / 256)) * 155 + roll - 21) * 256 + 2;
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RedemptionTerminalSeeder).runtimeCode);
        RedemptionTerminalSeeder(payable(address(game))).seedLiveRedemptionWord(settlementWord);
        vm.etch(address(game), original);
        vm.prank(address(game));
        sdgnrs.runRedemptionWork(settlementWord, 200_000);
        assertEq(_rollOf(batchId), roll);
    }

    function test_AdvanceAutomaticallySettlesTopupsAndBothRecipients() public {
        uint32 day = _openBatchId();
        uint256 amount = sdgnrs.totalSupply() / 1000;
        _burn(alice, amount);
        _burn(alice, amount);
        _burn(bob, amount);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "open burns reserve nothing");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _complete(38_402); // 175% roll, losing escrow flip
        (uint128 a,) = sdgnrs.pendingRedemptions(alice, day);
        (uint128 b,) = sdgnrs.pendingRedemptions(bob, day);
        assertEq(a, 0);
        assertEq(b, 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertFalse(game.rngLocked());
    }

    function test_KeeperSettlesFifoHeadThenCannotPayTwice() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        _settleOneClaim();
        (uint128 a,) = sdgnrs.pendingRedemptions(alice, day);
        (uint128 b,) = sdgnrs.pendingRedemptions(bob, day);
        assertEq(a, 0, "the first burner heads the queue");
        assertGt(b, 0, "the second waits for the next step");
        uint256 aliceCredit = game.claimableWinningsOf(alice);
        uint256 remaining = sdgnrs.pendingRedemptionEthValue();
        vm.prank(address(game));
        assertFalse(_process(14_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), remaining);
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(game.claimableWinningsOf(alice), aliceCredit, "the settled head is not paid again");
        uint256 bobCredit = game.claimableWinningsOf(bob);
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        assertEq(game.claimableWinningsOf(alice), aliceCredit, "a drained cohort pays nothing twice");
        assertEq(game.claimableWinningsOf(bob), bobCredit, "a drained cohort pays nothing twice");
    }

    /// @dev A dependency refusing one claim must not hold the cohort (and every later RNG
    ///      request): the claim parks with its word and settles later, once, for its player.
    function test_RefusedSettlementParksClaimAndCohortCompletes() public {
        uint32 day = _openBatchId();
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
                && logs[i].topics[0] == keccak256("RedemptionParked(address,uint32,bytes)")) ++parked;
        }
        assertEq(parked, 2);
        (uint128 a,) = sdgnrs.pendingRedemptions(alice, day);
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
        (a,) = sdgnrs.pendingRedemptions(alice, day);
        assertEq(a, 0);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(alice);
        sdgnrs.claimParkedRedemption(alice, day);
    }

    /// @dev The Game re-raises an out-of-gas module call as EmptyRevert(). Settlement must treat
    ///      it as caller-withheld gas and revert, never as a refusal that parks the claim.
    function test_OutOfGasGameModuleCallRevertsInsteadOfParking() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(DegenerusGame.resolveRedemptionLootbox.selector),
            abi.encodeWithSignature("EmptyRevert()"));
        vm.expectRevert(abi.encodeWithSignature("EmptyRevert()"));
        vm.prank(address(game));
        _process(9_000_000);
    }

    function _logDigest(bytes32 digest, Vm.Log[] memory logs) internal view returns (bytes32) {
        for (uint256 i; i < logs.length; ++i) {
            // Player awards and every Game/sDGNRS event must remain identical across
            // every settlement route.
            if (logs[i].emitter == address(game) || logs[i].emitter == address(sdgnrs)) {
                digest = keccak256(abi.encode(digest, logs[i].emitter, logs[i].topics, logs[i].data));
            }
        }
        return digest;
    }

    function _transcriptOf(bytes32 digest) internal view returns (bytes32) {
        return keccak256(abi.encode(digest, game.claimableWinningsOf(alice), game.claimableWinningsOf(bob),
            coinflip.coinflipAmount(alice), coinflip.coinflipAmount(bob), sdgnrs.pendingRedemptionEthValue()));
    }

    function _claimTranscript() internal view returns (bytes32) {
        return _transcriptOf(_logDigest(bytes32(0), vm.getRecordedLogs()));
    }

    /// @dev The cohort's pinned session word decides every live payout: one engine call, one
    ///      call per claim with the Game's live word moved in between, and the parked route
    ///      (claims refused, then claimed later on their parked word) all produce one transcript.
    function test_FrozenWordProducesSameTranscriptAcrossAllClaimRoutes() public {
        uint32 day = _openBatchId();
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

        // Allowances are probed first, so the recorded transcript holds only the applied steps.
        uint256 first = _oneClaimAllowance();
        vm.recordLogs();
        _settleClaimAt(first);
        bytes32 digest = _logDigest(bytes32(0), vm.getRecordedLogs());
        // A later call reads the cohort's word, never the Game's current one.
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RedemptionTerminalSeeder).runtimeCode);
        RedemptionTerminalSeeder(payable(address(game))).seedLiveRedemptionWord(0xD1FF);
        vm.etch(address(game), original);
        uint256 second = _oneClaimAllowance();
        vm.getRecordedLogs(); // Drop the probes' events.
        _settleClaimAt(second);
        assertFalse(sdgnrs.redemptionSettlementPending());
        digest = _logDigest(digest, vm.getRecordedLogs());
        assertEq(_transcriptOf(digest), automatic, "per-claim calls use the frozen cohort word");
        assertTrue(vm.revertToState(snapshot));

        // Withhold custody so both live settlements are refused and park with their word.
        uint256 eth = address(sdgnrs).balance;
        uint256 st = mockStETH.balanceOf(address(sdgnrs));
        vm.deal(address(sdgnrs), 0);
        vm.prank(address(sdgnrs));
        mockStETH.transfer(address(0xDEAD), st);
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        (uint128 parked,) = sdgnrs.pendingRedemptions(alice, day);
        assertGt(parked, 0, "harness: the refused claim parked");
        vm.deal(address(sdgnrs), eth);
        vm.prank(address(0xDEAD));
        mockStETH.transfer(address(sdgnrs), st);
        vm.recordLogs();
        vm.prank(alice);
        sdgnrs.claimParkedRedemption(alice, day);
        vm.prank(bob);
        sdgnrs.claimParkedRedemption(bob, day);
        assertEq(_claimTranscript(), automatic, "parked claims use the frozen cohort word");
    }

    function test_LiveSettlementDoesNotPushEthToRecipient() public {
        RedemptionRejectEth receiver = new RedemptionRejectEth();
        uint256 amount = sdgnrs.totalSupply() / 1000;
        vm.prank(address(game));
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, address(receiver), amount), amount);
        uint32 day = _openBatchId();
        _burn(address(receiver), sdgnrs.balanceOf(address(receiver)));
        _resolve(day, 100, 99);
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(address(receiver).balance, 0);
    }

    function test_MaxCapMaximumRollAutoSettlementFitsGasCeiling() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);
        assertEq(_claimBase(alice, day), 160 ether);
        vm.prank(address(game));
        uint256 beforeGas = gasleft();
        assertTrue(_process(9_000_000));
        uint256 used = beforeGas - gasleft() + 21_000;
        emit log_named_uint("maximum_redemption_settlement_gas", used);
        assertLe(used, 10_000_000);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_TerminalClaimHasNoExpiry() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        // The self-claim is the terminal door only: a live game settles through mineFlip.
        vm.expectRevert(sDGNRS.NotGameOver.selector);
        vm.prank(alice);
        sdgnrs.claimRedemption(alice, day);
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
