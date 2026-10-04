// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title RngReuseJackpotStraddle — PoC for the daily-jackpot pending-settlement
///        wall-day straddle that reuses the prior day's VRF word (v60 R2, RNGREUSE).
///
/// @notice In the jackpot phase, the "fresh daily jackpot" leg
///         (AdvanceModule:519 `payDailyJackpot(true, lvl, rngWord)`) sets
///         `dailyJackpotCoinTicketsPending = true` UNCONDITIONALLY
///         (JackpotModule:481) and breaks WITHOUT `_unlockRng`. The deferred
///         coin/ticket half is completed by a LATER same-day advance
///         (AdvanceModule:506 → `payDailyJackpotCoinAndTickets` → `_unlockRng`).
///
///         If no advance completes that pending before the wall-day boundary,
///         `_unlockRng(D)` never runs, so `rngWordCurrent` / `rngRequestTime`
///         stay = day-D's word and `dailyIdx` stays < D. On day D+1 the new-day
///         advance calls `rngGate(D+1)` (AdvanceModule:330) BEFORE the :506
///         pending-completion. rngGate's fresh-word branch
///         (`currentWord != 0 && rngRequestTime != 0`, :1217) fires, the gap
///         backfill is skipped (`_recordedDailyWord(dailyIdx+1) != 0`), and
///         `_applyDailyRng(D+1, currentWord)` writes
///             _recordedDailyWord(D+1) = _recordedDailyWord(D)
///         → day D+1's RNG == day D's RNG (already publicly revealed via the
///         day-D word/event) → predictable coinflip/jackpot entropy.
///
/// @dev Two tests, identical drive, single difference = whether the pending is
///      completed before crossing midnight:
///   - testControl_PendingCompletedSameDay_FreshWordNextDay: complete the
///     pending same-day (drain to !rngLocked), THEN cross the wall-day → D+1
///     requests its OWN fresh word, distinct from D. (Proves the harness mints
///     distinct per-day words, so the bug test's equality is meaningful.)
///   - testBug_PendingStraddlesWallDay_ReusesPriorDayWord: cross the wall-day
///     WITHOUT completing the pending → the next advance reuses day-D's word.
///     `assertEq(wordD1, wordD)` PASSES on buggy HEAD (the reuse), and would
///     FAIL once the deferred jackpot is completed before rngGate sees D+1.
contract RngReuseJackpotStraddleTest is DeployProtocol {
    /// @dev prizePoolsPacked slot (confirmed via the BAF/RngRetry tests): [future:128 | next:128].
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    /// @dev AdvanceModule stage emitted when payDailyJackpot(true) sets the pending and breaks (no unlock).
    uint8 private constant STAGE_JACKPOT_DAILY_STARTED = 10;
    /// @dev topic0 of `event Advance(uint8 stage, uint24 lvl)` (both params non-indexed → in data).
    bytes32 private constant TOPIC_ADVANCE = keccak256("Advance(uint8,uint24)");

    address private buyer;
    uint256 private lastFulfilledReqId;
    uint256 private vrfNonce;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        buyer = makeAddr("rngreuse_buyer");
        vm.deal(buyer, 1_000_000 ether);
        vm.deal(address(game), 5_000 ether);

        // LINK for any VRF request path (mirrors the RngRetry PoC).
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    // ==================== Tests ====================

    function test_PreferredBoardFrozenAcrossPendingBattleAndMidnight() public {
        vm.prank(buyer); crapsBattle.setPreferredBoard(3);
        uint24 day = _driveToJackpotPendingSet();
        uint256 wordD = game.rngWordForDay(day);
        _assertPreferenceFrozen();
        vm.warp(block.timestamp + 2 days + 1);
        _assertPreferenceFrozen();
        _drainUntilUnlocked();
        assertFalse(game.rngLocked());
        vm.prank(buyer); crapsBattle.setPreferredBoard(0);
        assertEq(crapsBattle.preferredBoardOf(buyer), 0);
        // The unprocessed wall day must not inherit the revealed pending-battle word. The drain
        // runs on to the wall day's own request (the engine composes actions, 60d31f775), so
        // day + 1 is now a skipped gap day whose word derives from that fresh request.
        assertTrue(game.rngWordForDay(day + 1) != wordD, "the skipped day never inherits the pending day's word");
    }

    function _assertPreferenceFrozen() private {
        assertTrue(game.rngLocked());
        uint32 saved = crapsBattle.preferredBoardOf(buyer);
        vm.prank(buyer); vm.expectRevert(CrapsBattleStorage.BetLocked.selector);
        crapsBattle.setPreferredBoard(saved == 0 ? 3 : 0);
        // A fresh wallet cannot initialize even the random board during the commitment.
        vm.prank(address(0xC0FFEE)); vm.expectRevert(CrapsBattleStorage.BetLocked.selector);
        crapsBattle.setPreferredBoard(0);
    }


    function testControl_PendingCompletedSameDay_FreshWordNextDay() public {
        uint24 D = _driveToJackpotPendingSet();
        uint256 wordD = game.rngWordForDay(D);
        emit log_named_uint("[control] jackpot pending-set on day", D);
        emit log_named_uint("[control] rngWordForDay(D)", wordD);
        assertTrue(wordD != 0, "control: day D word must be recorded at pending-set");
        assertTrue(game.rngLocked(), "control: still locked at pending-set (no unlock yet)");

        // COMPLETE the deferred settlement (and any phase transition) SAME-DAY:
        // drain until the day fully unlocks. No wall-day straddle.
        _drainUntilUnlocked();
        assertTrue(!game.rngLocked(), "control: day D must fully unlock same-day");
        assertEq(game.currentDayView(), D, "control: still day D after same-day completion");

        // Cross the wall-day and run the next day normally: it must request a FRESH word.
        vm.warp(block.timestamp + 1 days + 1);
        uint24 D1 = game.currentDayView();
        assertGt(D1, D, "control: warp advanced to a later day");
        uint256 wordD1 = _advanceUntilWordRecorded(D1); // fulfills the fresh request

        emit log_named_uint("[control] rngWordForDay(D+1)", wordD1);
        assertTrue(wordD1 != 0, "control: day D+1 word must be recorded");
        assertTrue(
            wordD1 != wordD,
            "control: completing the pending same-day -> D+1 gets a FRESH, distinct VRF word"
        );
    }

    /// @notice FIX/regression: with the day-clamp, a jackpot-pending straddle no longer
    ///         reuses day D's word for D+1. The clamp seals day D first (its deferred half
    ///         stays on wordD), then D+1 requests its OWN fresh VRF word. Pre-fix this drive
    ///         produced `wordD1 == wordD` (the reuse); post-fix `wordD1 != wordD` and `!= 0`
    ///         (no orphan). Fails RED on un-clamped code, GREEN with the clamp.
    function testFix_PendingStraddle_DPlus1GetsFreshWord() public {
        uint24 D = _driveToJackpotPendingSet();
        uint256 wordD = game.rngWordForDay(D);
        emit log_named_uint("[pending] jackpot pending-set on day", D);
        emit log_named_uint("[pending] rngWordForDay(D)", wordD);
        assertTrue(wordD != 0, "day D word must be recorded at pending-set");
        assertTrue(game.rngLocked(), "still locked at pending-set (pending NOT completed)");

        // STRADDLE: cross the wall-day WITHOUT completing the deferred settlement.
        vm.warp(block.timestamp + 1 days + 1);
        uint24 D1 = game.currentDayView();
        assertGt(D1, D, "warp advanced to a later day");

        // Advance + fulfill: the clamp seals day D (deferred half on wordD), then D+1 asks fresh.
        uint256 wordD1 = _advanceUntilWordRecorded(D1);

        emit log_named_uint("[pending] rngWordForDay(D+1) after fix", wordD1);
        assertTrue(wordD1 != 0, "no orphan: day D+1 still gets a word written");
        assertTrue(
            wordD1 != wordD,
            "FIXED: day D+1 gets a FRESH word, not the reused day-D word (pre-fix: ==)"
        );
    }

    /// @notice Generality: the reuse is NOT gated on `dailyJackpotCoinTicketsPending`.
    ///         Any day whose VRF word was applied by rngGate but NOT yet sealed by
    ///         `_unlockRng` reuses across a wall-day. Here the straddle point is the
    ///         LEVEL TRANSITION into the jackpot phase (STAGE_ENTERED_JACKPOT, :499):
    ///         day-D's word is applied + `jackpotPhaseFlag` is set, but `_unlockRng`
    ///         is deliberately skipped ("Do not unlock here", :497) and
    ///         `payDailyJackpot(true)` (the SOLE writer of the pending flag, via
    ///         JackpotModule:481 ← AdvanceModule:519) has NOT run yet. So
    ///         `dailyJackpotCoinTicketsPending == false` here by construction.
    function testFix_TransitionStraddle_DPlus1GetsFreshWord() public {
        // _driveToJackpotPhase() returns the instant jackpotPhase() flips true — i.e.
        // immediately after STAGE_ENTERED_JACKPOT, before the pending-set advance.
        // dailyJackpotCoinTicketsPending is FALSE here (sole writer is the later :519),
        // so this proves the fix covers the non-pending break point too.
        // The engine composes the jackpot entry with the first jackpot stages in one call when the
        // allowance covers them (60d31f775), so the old post-entry break point is not a separate
        // step any more. The transition straddle is taken at the same day's last checkpoint
        // before the entry: the transition word is applied, the lock is held, and the next chunk
        // is the consolidation that enters the jackpot phase (pending flag false by construction).
        _driveToTransitionCheckpoint();
        uint24 D = game.currentDayView();
        uint256 wordD = game.rngWordForDay(D);
        emit log_named_uint("[transition] entered jackpot on day", D);
        emit log_named_uint("[transition] rngWordForDay(D)", wordD);
        assertTrue(wordD != 0, "transition: day D word applied at jackpot entry");
        assertTrue(game.rngLocked(), "transition: not unlocked at jackpot entry");
        assertFalse(_pendingSet(), "transition: the pending flag is false at this break point");

        // STRADDLE across the wall-day WITHOUT completing/sealing the day.
        vm.warp(block.timestamp + 1 days + 1);
        uint24 D1 = game.currentDayView();
        assertGt(D1, D, "transition: warp advanced to a later day");
        // Advance + fulfill: the clamp processes day D's jackpot sequence on wordD, then
        // the wall-day requests its own fresh word.
        uint256 wordD1 = _advanceUntilWordRecorded(D1);
        assertTrue(game.jackpotPhase(), "transition: day D entered the jackpot phase on its own word");

        emit log_named_uint("[transition] rngWordForDay(D+1) after fix", wordD1);
        assertTrue(wordD1 != 0, "transition: no orphan - day D+1 word recorded");
        assertTrue(
            wordD1 != wordD,
            "FIXED (general): even pending=FALSE, day D+1 gets a fresh word not the reused day-D word (pre-fix: ==)"
        );
    }

    // ==================== Drive helpers ====================

    /// @dev slot 0 byte 22: dailyJackpotCoinTicketsPending (golden layout).
    uint256 private constant PENDING_BIT = 176;
    bytes4 private constant INSUFFICIENT_GAS = bytes4(keccak256("InsufficientExecutionGas()"));

    /// @dev One engine step at the smallest of three allowances that admits the next chunk. The
    ///      engine keeps admitting chunks while the allowance covers the next declared bound
    ///      (60d31f775), so an unbounded call would run a whole jackpot day; small allowances
    ///      stop between stages like the old one-stage-per-advance flow. Returns false when the
    ///      engine has nothing to do now (NoWork / RngNotReady).
    function _step() internal returns (bool) {
        uint256[3] memory allowances = [uint256(1_500_000), 4_500_000, 8_700_000];
        for (uint256 k; k < 3; ++k) {
            (bool ok, bytes memory err) =
                address(game).call{gas: allowances[k]}(abi.encodeWithSignature("mineFlip()"));
            if (ok) return true;
            if (err.length == 0 || (err.length == 4 && bytes4(err) == INSUFFICIENT_GAS)) continue;
            return false;
        }
        (bool okFull, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
        return okFull;
    }

    function _pendingSet() internal view returns (bool) {
        return (uint256(vm.load(address(game), bytes32(0))) >> PENDING_BIT) & 1 != 0;
    }

    /// @notice Drive the game from genesis into the jackpot phase, then advance
    ///         until the daily-jackpot pending is set (STAGE_JACKPOT_DAILY_STARTED)
    ///         — i.e. the deferred coin/ticket settlement is queued but NOT yet
    ///         completed and NOT unlocked. Returns that day's index.
    function _driveToJackpotPendingSet() internal returns (uint24) {
        _driveToJackpotPhase();

        for (uint256 i = 0; i < 400; i++) {
            require(!game.gameOver(), "gameOver before jackpot pending-set");
            require(game.jackpotPhase(), "left jackpot phase before pending-set");
            if (_pendingSet() && game.rngLocked()) return game.currentDayView();

            _fulfillVrf();
            if (!_step()) {
                // Day fully drained / no work yet: move to the next wall-day.
                vm.warp(block.timestamp + 1 days + 1);
            }
        }
        revert("did not reach jackpot pending-set");
    }

    /// @notice Drive to the transition day's checkpoint right before the jackpot entry: the
    ///         last-purchase transition word is applied under the lock and the next chunk is the
    ///         POOL_CONSOLIDATION stage (a 4.5M allowance cannot admit it).
    function _driveToTransitionCheckpoint() internal {
        for (uint256 i = 0; i < 4000; i++) {
            require(!game.gameOver(), "gameOver before jackpot phase");
            require(!game.jackpotPhase(), "passed the transition checkpoint");
            _fulfillVrf();
            (, , bool lpd, bool locked, ) = game.purchaseInfo();
            if (lpd && locked && game.rngWordForDay(game.currentDayView()) != 0) {
                (bool ok, bytes memory err) =
                    address(game).call{gas: 4_500_000}(abi.encodeWithSignature("mineFlip()"));
                if (!ok && err.length == 4 && bytes4(err) == INSUFFICIENT_GAS) return;
                if (ok) continue;
            }
            if (!_step()) {
                vm.warp(block.timestamp + 1 days + 1);
                _seedNextPrizePool(49.9 ether);
                _buyTickets(buyer, 4000);
            }
        }
        revert("did not reach the transition checkpoint");
    }

    /// @notice Drive purchase phase to target, transition, until jackpotPhase() == true.
    function _driveToJackpotPhase() internal {
        for (uint256 i = 0; i < 4000; i++) {
            require(!game.gameOver(), "gameOver before jackpot phase");
            if (game.jackpotPhase()) return;

            _fulfillVrf();
            if (!_step()) {
                // Next wall-day: seed the next pool over target + buy so the level
                // transition (→ jackpot phase) happens promptly.
                vm.warp(block.timestamp + 1 days + 1);
                _seedNextPrizePool(49.9 ether);
                _buyTickets(buyer, 4000);
            }
        }
        revert("did not reach jackpot phase");
    }

    /// @notice Advance + fulfill within the current day until RNG unlocks
    ///         (pending completed and any phase transition drained).
    function _drainUntilUnlocked() internal {
        for (uint256 i = 0; i < 120; i++) {
            if (!game.rngLocked()) return;
            _fulfillVrf();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) return;
        }
    }

    /// @notice Advance + fulfill until rngWordForDay(day) is recorded (control: D+1 wants a fresh word).
    function _advanceUntilWordRecorded(uint24 day) internal returns (uint256) {
        for (uint256 i = 0; i < 120; i++) {
            if (game.rngWordForDay(day) != 0) break;
            _fulfillVrf();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) break;
        }
        return game.rngWordForDay(day);
    }

    // ==================== Low-level helpers ====================

    /// @dev Fulfill the latest pending VRF request with a UNIQUE word per request
    ///      (so distinct days legitimately get distinct words — keyed on reqId+nonce).
    function _fulfillVrf() internal {
        if (game.rngLocked()) _assertPreferenceFrozen();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0 || reqId == lastFulfilledReqId) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) {
            lastFulfilledReqId = reqId;
            return;
        }
        vrfNonce++;
        uint256 w = uint256(keccak256(abi.encode("v60-rngreuse-vrf", reqId, vrfNonce)));
        if (w == 0) w = 1;
        mockVRF.fulfillRandomWords(reqId, w);
        if (game.rngLocked()) _assertPreferenceFrozen();
        lastFulfilledReqId = reqId;
    }

    /// @dev Return the stage of the LAST `Advance` event emitted by `game` in `logs`.
    function _lastAdvanceStage(Vm.Log[] memory logs)
        internal
        view
        returns (uint8 stage, bool found)
    {
        for (uint256 i = logs.length; i > 0; i--) {
            Vm.Log memory lg = logs[i - 1];
            if (
                lg.emitter == address(game) &&
                lg.topics.length > 0 &&
                lg.topics[0] == TOPIC_ADVANCE
            ) {
                (uint8 s, ) = abi.decode(lg.data, (uint8, uint24));
                return (s, true);
            }
        }
        return (0, false);
    }

    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);
        vm.prank(who);
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)),
            bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext)
        );
    }
}
