// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

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

/// @dev Etched over the boon module: every box boon draw refuses with its own reason.
contract RedemptionRefusingBoonModule {
    error BoonRefused(uint256 code);
    fallback() external payable { revert BoonRefused(7); }
}

/// @dev Etched over the boon module: every box boon draw burns all forwarded gas (empty data).
contract RedemptionGasBurningBoonModule {
    fallback() external payable { assembly { invalid() } }
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
        (uint128 a,) = sdgnrs.pendingRedemptions(game.walletIdOf(alice), day);
        (uint128 b,) = sdgnrs.pendingRedemptions(game.walletIdOf(bob), day);
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
        (uint128 a,) = sdgnrs.pendingRedemptions(game.walletIdOf(alice), day);
        (uint128 b,) = sdgnrs.pendingRedemptions(game.walletIdOf(bob), day);
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
                && logs[i].topics[0] == keccak256("RedemptionParked(uint32,uint32,bytes)")) ++parked;
        }
        assertEq(parked, 2);
        (uint128 a,) = sdgnrs.pendingRedemptions(game.walletIdOf(alice), day);
        assertGt(a, 0, "parked claim keeps its record");

        // Custody restored: only the player (or an approved operator) settles, exactly once.
        vm.deal(address(sdgnrs), eth);
        vm.prank(address(0xDEAD));
        mockStETH.transfer(address(sdgnrs), st);
        uint32 aliceId = game.walletIdOf(alice);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        vm.prank(bob);
        sdgnrs.claimParkedRedemption(aliceId, day);
        uint256 before = game.claimableWinningsOf(alice);
        vm.prank(alice);
        sdgnrs.claimParkedRedemption(0, day);
        assertGt(game.claimableWinningsOf(alice), before, "parked claim pays its direct half");
        (a,) = sdgnrs.pendingRedemptions(game.walletIdOf(alice), day);
        assertEq(a, 0);
        vm.expectRevert(sDGNRS.NoClaim.selector);
        vm.prank(alice);
        sdgnrs.claimParkedRedemption(0, day);
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

    /// @dev A nested box sub-call (here the boon draw inside the redemption order's boxes) that
    ///      refuses with revert data reaches sDGNRS with that data, so the claim parks with its
    ///      word and the cursor moves on; the cohort completes.
    function test_NestedBoxSubcallRefusalParksClaim() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        bytes memory original = ContractAddresses.GAME_BOON_MODULE.code;
        vm.etch(ContractAddresses.GAME_BOON_MODULE, type(RedemptionRefusingBoonModule).runtimeCode);

        // One claim's step: the refused head parks and the cursor moves to the next claim.
        uint32 cursorBefore = _cursor();
        uint256 step = _oneClaimAllowance();
        vm.recordLogs();
        _work(step);
        assertEq(_cursor(), cursorBefore + 1, "cursor advanced past the parked claim");
        assertTrue(sdgnrs.redemptionSettlementPending(), "the next claim is still queued");
        vm.prank(address(game));
        assertTrue(_process(9_000_000), "the refused claims do not hold the cohort");
        assertFalse(sdgnrs.redemptionSettlementPending());
        bytes memory reason;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(sdgnrs)
                && logs[i].topics[0] == keccak256("RedemptionParked(uint32,uint32,bytes)")) {
                reason = abi.decode(logs[i].data, (bytes));
            }
        }
        assertEq(reason, abi.encodeWithSelector(RedemptionRefusingBoonModule.BoonRefused.selector, 7),
            "the sub-call's own reason reaches sDGNRS");
        (uint128 a,) = sdgnrs.pendingRedemptions(game.walletIdOf(alice), day);
        assertGt(a, 0, "parked claim keeps its record");

        vm.etch(ContractAddresses.GAME_BOON_MODULE, original);
        vm.prank(alice);
        sdgnrs.claimParkedRedemption(0, day);
        (a,) = sdgnrs.pendingRedemptions(game.walletIdOf(alice), day);
        assertEq(a, 0, "the parked claim settles once the dependency answers");
    }

    /// @dev A nested box sub-call that runs out of gas returns no data: the Lootbox module
    ///      re-raises it as EmptyRevert(), and settlement reverts instead of parking, so a caller
    ///      cannot starve a sub-call to skip a claim.
    function test_NestedBoxSubcallOutOfGasRevertsInsteadOfParking() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        uint32 cursorBefore = _cursor();
        vm.etch(ContractAddresses.GAME_BOON_MODULE, type(RedemptionGasBurningBoonModule).runtimeCode);
        vm.expectRevert(abi.encodeWithSignature("EmptyRevert()"));
        vm.prank(address(game));
        _process(9_000_000);
        assertEq(_cursor(), cursorBefore, "nothing settled or parked");
        assertTrue(sdgnrs.redemptionSettlementPending());
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
        (uint128 parked,) = sdgnrs.pendingRedemptions(game.walletIdOf(alice), day);
        assertGt(parked, 0, "harness: the refused claim parked");
        vm.deal(address(sdgnrs), eth);
        vm.prank(address(0xDEAD));
        mockStETH.transfer(address(sdgnrs), st);
        vm.recordLogs();
        vm.prank(alice);
        sdgnrs.claimParkedRedemption(0, day);
        vm.prank(bob);
        sdgnrs.claimParkedRedemption(0, day);
        assertEq(_claimTranscript(), automatic, "parked claims use the frozen cohort word");
    }

    function test_LiveSettlementDoesNotPushEthToRecipient() public {
        RedemptionRejectEth receiver = new RedemptionRejectEth();
        // A burner holds a wallet ID: the receiver gets one with a one-ticket purchase.
        vm.deal(address(receiver), 1 ether);
        vm.prank(address(receiver));
        game.purchase{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 amount = sdgnrs.totalSupply() / 1000;
        vm.prank(address(game));
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, address(receiver), amount), amount);
        uint32 day = _openBatchId();
        _burn(address(receiver), sdgnrs.balanceOf(address(receiver)));
        _resolve(day, 100, 99);
        uint256 held = address(receiver).balance;
        vm.prank(address(game));
        assertTrue(_process(9_000_000));
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(address(receiver).balance, held, "settlement pushes no ETH to the recipient");
    }

    function test_TerminalClaimHasNoExpiry() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        // The self-claim is the terminal door only: a live game settles through mineFlip.
        vm.expectRevert(sDGNRS.NotGameOver.selector);
        vm.prank(alice);
        sdgnrs.claimRedemption(0, day);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RedemptionTerminalSeeder).runtimeCode);
        RedemptionTerminalSeeder(payable(address(game))).end();
        vm.etch(address(game), original);
        vm.warp(vm.getBlockTimestamp() + 2000 days);
        uint256 remaining = sdgnrs.pendingRedemptionEthValue();
        uint256 beforeBalance = alice.balance;
        vm.prank(alice);
        sdgnrs.claimRedemption(0, day);
        assertEq(alice.balance - beforeBalance, remaining);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }
}
