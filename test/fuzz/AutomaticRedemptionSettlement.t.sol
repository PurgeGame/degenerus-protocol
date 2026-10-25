// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

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
        _clearRngRequest();
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
        assertTrue(_cursor() == before + 1 || !sdgnrs.redemptionSettlementPending_g153837());
    }
    function _settleOneClaim() internal { _settleClaimAt(_oneClaimAllowance()); }
    /// @dev Close and resolve using an actual batch word whose roll matches the fixture.
    function _resolve(uint32 batchId, uint16 roll, uint256 entropy) internal {
        assertEq(batchId, _openBatchId());
        _closeAsGame();
        settlementWord = _wordForRollFrom(roll, entropy);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RedemptionTerminalSeeder).runtimeCode);
        RedemptionTerminalSeeder(payable(address(game))).seedLiveRedemptionWord(settlementWord);
        vm.etch(address(game), original);
        vm.prank(address(game));
        sdgnrs.runRedemptionWork(settlementWord, RESOLVE_ONLY_ALLOWANCE);
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
        (uint128 a,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(alice), day);
        (uint128 b,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(bob), day);
        assertEq(a, 0);
        assertEq(b, 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending_g153837());
        assertFalse(game.rngLocked());
    }

    function test_KeeperSettlesFifoHeadThenCannotPayTwice() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolve(day, 100, 99);
        _settleOneClaim();
        (uint128 a,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(alice), day);
        (uint128 b,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(bob), day);
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

    function _assertCohortPaid(uint32 day) internal {
        assertFalse(sdgnrs.redemptionSettlementPending_g153837());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertEq(_claimTokens(alice, day), 0);
        assertEq(_claimTokens(bob, day), 0);
    }

    /// @dev Two live claims at roll 100; the first burner heads the queue.
    function _resolveTwoClaims() internal returns (uint32 day) {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        day = _resolveLive(100);
    }

    /// @dev Roll-100 batch whose synthetic flip wins, with FLIP escrowed for both claims.
    function _resolveWinningFlip() internal returns (uint32 day) {
        _seedFlipBacking(1_000_000);
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        day = _openBatchId();
        _closeAsGame();
        settlementWord = _wordForRoll(100);
        while (_synthReward(settlementWord, day) == 0) settlementWord = _wordForRollFrom(100, settlementWord + 1);
        _mockSettlingStage();
        vm.prank(address(game));
        sdgnrs.runRedemptionWork(settlementWord, RESOLVE_ONLY_ALLOWANCE);
        (, , uint256 escrow, , uint16 reward) = _batch(day);
        assertGt(escrow, 0, "FLIP escrowed");
        assertGt(reward, 0, "the batch flip won");
    }

    /// @dev A claim that cannot complete reverts the whole step: no claim is consumed, none paid,
    ///      the reserve and cursor stay put. Once the cause clears, the same cohort settles in full.
    function test_RevertedLootboxLegRevertsWholeSettlement() public {
        uint32 day = _resolveTwoClaims();
        uint256 credit = game.claimableWinningsOf(alice);
        uint256 bobCredit = game.claimableWinningsOf(bob);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector), hex"12345678");
        assertGt(_claimTokens(alice, day), 0);
        bytes memory reason = _assertWorkRevertsUnchanged(day, 9_000_000);
        assertEq(reason, hex"12345678", "the failing leg's reason bubbles");
        assertEq(_cursor(), 0);
        assertGt(_claimTokens(alice, day), 0);
        assertGt(_claimTokens(bob, day), 0);
        vm.clearMockedCalls();
        _mockSettlingStage();
        assertTrue(_work(9_000_000));
        _assertCohortPaid(day);
        assertGt(game.claimableWinningsOf(alice), credit);
        assertGt(game.claimableWinningsOf(bob), bobCredit);
    }

    function test_RevertedDirectLegRevertsWholeSettlement() public {
        uint32 day = _resolveTwoClaims();
        uint256 credit = game.claimableWinningsOf(alice);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.creditRedemptionDirect.selector), hex"12345678");
        _assertWorkRevertsUnchanged(day, 9_000_000);
        assertGt(_claimTokens(alice, day), 0);
        assertGt(_claimTokens(bob, day), 0);
        vm.clearMockedCalls();
        _mockSettlingStage();
        assertTrue(_work(9_000_000));
        _assertCohortPaid(day);
        assertGt(game.claimableWinningsOf(alice), credit);
    }

    function test_RevertedFlipCreditRevertsWholeSettlement() public {
        uint32 day = _resolveWinningFlip();
        vm.mockCallRevert(address(coinflip), abi.encodeWithSelector(coinflip.creditFlip_g317.selector), hex"12345678");
        _assertWorkRevertsUnchanged(day, 9_000_000);
        assertGt(_claimTokens(alice, day), 0);
        assertGt(_claimTokens(bob, day), 0);
        vm.clearMockedCalls();
        _mockSettlingStage();
        uint256 stake = coinflip.coinflipAmount(alice);
        assertTrue(_work(9_000_000));
        _assertCohortPaid(day);
        assertGt(coinflip.coinflipAmount(alice), stake, "the FLIP credit lands once the leg works");
    }

    /// @dev A prefix paid by an earlier step stays consumed when a later claim reverts its step.
    function test_RevertedLaterClaimKeepsEarlierPaidPrefix() public {
        uint32 day = _resolveTwoClaims();
        assertFalse(_work(_oneClaimBudget()));
        assertEq(_cursor(), 1);
        assertEq(_claimTokens(alice, day), 0);
        uint256 paid = game.claimableWinningsOf(alice);
        assertGt(paid, 0);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector), hex"12345678");
        _assertWorkRevertsUnchanged(day, 9_000_000);
        assertEq(_cursor(), 1);
        assertEq(game.claimableWinningsOf(alice), paid, "the paid prefix is not paid twice");
        assertGt(_claimTokens(bob, day), 0);
        vm.clearMockedCalls();
        _mockSettlingStage();
        assertTrue(_work(9_000_000));
        _assertCohortPaid(day);
        assertEq(game.claimableWinningsOf(alice), paid);
    }

    /// @dev A metering-selector revert cannot impersonate caller underfunding: it bubbles as
    ///      itself and consumes nothing.
    function test_SpoofedGameMeteringErrorRevertsWholeSettlement() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 day = _resolveLive(100);
        uint256 credit = game.claimableWinningsOf(alice);
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.resolveRedemptionLootbox.selector),
            abi.encodeWithSignature("EmptyRevert()"));
        bytes memory reason = _assertWorkRevertsUnchanged(day, 9_000_000);
        assertEq(reason, abi.encodeWithSignature("EmptyRevert()"));
        assertGt(_claimTokens(alice, day), 0);
        vm.clearMockedCalls();
        _mockSettlingStage();
        assertTrue(_work(9_000_000));
        assertEq(_claimTokens(alice, day), 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertGt(game.claimableWinningsOf(alice), credit);
    }

    /// @dev A refusing nested dependency reverts the step; its claim stays live and pays once the
    ///      dependency answers.
    function test_NestedBoxSubcallRefusalRevertsWholeSettlement() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 day = _resolveLive(100);
        uint256 credit = game.claimableWinningsOf(alice);
        bytes memory original = ContractAddresses.GAME_BOON_MODULE.code;
        vm.etch(ContractAddresses.GAME_BOON_MODULE, type(RedemptionRefusingBoonModule).runtimeCode);
        _assertWorkRevertsUnchanged(day, 9_000_000);
        assertGt(_claimTokens(alice, day), 0);
        vm.etch(ContractAddresses.GAME_BOON_MODULE, original);
        assertTrue(_work(9_000_000));
        assertEq(_claimTokens(alice, day), 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertGt(game.claimableWinningsOf(alice), credit);
    }

    /// @dev Exhaustion of the nested call's whole gas reverts the step the same way.
    function test_NestedBoxSubcallExhaustionRevertsWholeSettlement() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 day = _resolveLive(100);
        uint256 credit = game.claimableWinningsOf(alice);
        bytes memory original = ContractAddresses.GAME_BOON_MODULE.code;
        vm.etch(ContractAddresses.GAME_BOON_MODULE, type(RedemptionGasBurningBoonModule).runtimeCode);
        _assertWorkRevertsUnchanged(day, 9_000_000);
        assertGt(_claimTokens(alice, day), 0);
        vm.etch(ContractAddresses.GAME_BOON_MODULE, original);
        assertTrue(_work(9_000_000));
        assertEq(_claimTokens(alice, day), 0);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertGt(game.claimableWinningsOf(alice), credit);
    }

    /// @dev Admission only decides whether a claim starts: with an allowance below the head
    ///      claim's bound the step returns without touching it.
    function test_ShortAllowanceStartsNoClaim() public {
        uint32 day = _resolveTwoClaims();
        bytes32 before = _redemptionDigest(day);
        assertFalse(_work(1_000_000));
        assertEq(_redemptionDigest(day), before, "a claim that does not fit is left whole");
        assertEq(_cursor(), 0);
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
    ///      call per claim with the Game's live word moved in between, all produce one transcript.
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
        assertFalse(sdgnrs.redemptionSettlementPending_g153837());
        digest = _logDigest(digest, vm.getRecordedLogs());
        assertEq(_transcriptOf(digest), automatic, "per-claim calls use the frozen cohort word");
        assertTrue(vm.revertToState(snapshot));


    }

    function test_LiveSettlementDoesNotPushEthToRecipient() public {
        RedemptionRejectEth receiver = new RedemptionRejectEth();
        // A burner holds a wallet ID: the receiver gets one with a one-ticket purchase.
        vm.deal(address(receiver), 1 ether);
        vm.prank(address(receiver));
        game.purchaseOrderFor{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 amount = sdgnrs.totalSupply() / 1000;
        vm.prank(address(game));
        assertEq(sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Whale, address(receiver), amount), amount);
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
