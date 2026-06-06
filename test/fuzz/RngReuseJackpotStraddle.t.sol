// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

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
///         backfill is skipped (`rngWordByDay[dailyIdx+1] != 0`), and
///         `_applyDailyRng(D+1, currentWord)` writes
///             rngWordByDay[D+1] = rngWordByDay[D]
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
    /// @dev prizePoolsPacked slot (confirmed via the BAF/RngRetry tests): [hi128 future][lo128 next].
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
        _driveToJackpotPhase();
        uint24 D = game.currentDayView();
        uint256 wordD = game.rngWordForDay(D);
        emit log_named_uint("[transition] entered jackpot on day", D);
        emit log_named_uint("[transition] rngWordForDay(D)", wordD);
        assertTrue(wordD != 0, "transition: day D word applied at jackpot entry");
        assertTrue(game.rngLocked(), "transition: not unlocked at jackpot entry");

        // STRADDLE across the wall-day WITHOUT completing/sealing the day.
        vm.warp(block.timestamp + 1 days + 1);
        uint24 D1 = game.currentDayView();
        assertGt(D1, D, "transition: warp advanced to a later day");
        // Advance + fulfill: the clamp processes day D's jackpot sequence on wordD, then
        // the wall-day requests its own fresh word.
        uint256 wordD1 = _advanceUntilWordRecorded(D1);

        emit log_named_uint("[transition] rngWordForDay(D+1) after fix", wordD1);
        assertTrue(wordD1 != 0, "transition: no orphan - day D+1 word recorded");
        assertTrue(
            wordD1 != wordD,
            "FIXED (general): even pending=FALSE, day D+1 gets a fresh word not the reused day-D word (pre-fix: ==)"
        );
    }

    // ==================== Drive helpers ====================

    /// @notice Drive the game from genesis into the jackpot phase, then advance
    ///         until the daily-jackpot pending is set (STAGE_JACKPOT_DAILY_STARTED)
    ///         — i.e. the deferred coin/ticket settlement is queued but NOT yet
    ///         completed and NOT unlocked. Returns that day's index.
    function _driveToJackpotPendingSet() internal returns (uint24) {
        _driveToJackpotPhase();

        for (uint256 i = 0; i < 400; i++) {
            require(!game.gameOver(), "gameOver before jackpot pending-set");
            require(game.jackpotPhase(), "left jackpot phase before pending-set");

            _fulfillVrf();
            vm.recordLogs();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (ok) {
                (uint8 stage, bool found) = _lastAdvanceStage(vm.getRecordedLogs());
                if (found && stage == STAGE_JACKPOT_DAILY_STARTED) {
                    return game.currentDayView();
                }
            } else {
                // Day fully drained / not-time-yet: move to the next wall-day.
                vm.warp(block.timestamp + 1 days + 1);
            }
        }
        revert("did not reach jackpot pending-set");
    }

    /// @notice Drive purchase phase to target, transition, until jackpotPhase() == true.
    function _driveToJackpotPhase() internal {
        for (uint256 i = 0; i < 4000; i++) {
            require(!game.gameOver(), "gameOver before jackpot phase");
            if (game.jackpotPhase()) return;

            _fulfillVrf();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) {
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
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) return;
        }
    }

    /// @notice Advance + fulfill until rngWordForDay(day) is recorded (control: D+1 wants a fresh word).
    function _advanceUntilWordRecorded(uint24 day) internal returns (uint256) {
        for (uint256 i = 0; i < 120; i++) {
            if (game.rngWordForDay(day) != 0) break;
            _fulfillVrf();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) break;
        }
        return game.rngWordForDay(day);
    }

    // ==================== Low-level helpers ====================

    /// @dev Fulfill the latest pending VRF request with a UNIQUE word per request
    ///      (so distinct days legitimately get distinct words — keyed on reqId+nonce).
    function _fulfillVrf() internal {
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
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth) {} catch {}
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(packed);
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(packed >> 128);
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)),
            bytes32((uint256(currentFuture) << 128) | targetNext)
        );
    }
}
