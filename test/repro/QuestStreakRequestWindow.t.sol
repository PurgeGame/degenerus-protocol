// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {QaSlots} from "../helpers/QaSlots.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DegeneretteQueue} from "../helpers/DegeneretteQueue.sol";

/// @notice Regression (O1): between the daily request (dailyIdx := D) and the applyDailyWord that
///         rolls quest day D, the active quest record still carries D-1. The effective streak used
///         to read the raw stored streak there (no decay against quest day 0), so a lapsed player
///         (misses > shields) scored the full stale streak in that window. Decay now bills against
///         the Game day, so the window reads the same decayed streak as the settled day before it
///         and the day after its word. Full protocol: the streak is built by real daily purchases
///         (MINT_ETH primary completions), the lapse is real logical days with no action, and the
///         window is a real VRF request awaiting its word. No state is written with vm.store.
contract QuestStreakRequestWindow is DeployProtocol {
    uint256 private constant QSTATE = QaSlots.STATE;
    uint256 private _t;
    uint256 private _nonce;

    address private p;
    uint32 private id;
    uint256 private builtStreak;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _finishSubscriptionWindow();
        p = makeAddr("o1_lapsed_player");
        vm.deal(p, 1_000 ether);
    }

    // ---- quest-state reads ----
    function _q() internal view returns (uint256) {
        return uint256(vm.load(ContractAddresses.QUESTS, keccak256(abi.encode(uint256(id), QSTATE))));
    }
    function _rawStreak() internal view returns (uint256) { return (_q() >> 72) & 0xffff; }
    function _shields() internal view returns (uint256) { return (_q() >> 200) & 0xff; }
    function _lastActive() internal view returns (uint256) { return (_q() >> 24) & 0xffffff; }
    function _activeQuestDay() internal view returns (uint24) {
        return uint24(uint256(vm.load(ContractAddresses.QUESTS, bytes32(QaSlots.ACTIVE))));
    }

    // ---- drive helpers ----
    function _fulfilLatest(uint256 w) internal {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return;
        (,, bool done) = mockVRF.pendingRequests(req);
        if (!done) mockVRF.fulfillRandomWords(req, w);
    }

    /// @dev Finish everything owed for the current logical day (word applied, daily complete).
    function _settle() internal {
        for (uint256 i; i < 400; ++i) {
            _fulfilLatest(uint256(keccak256(abi.encode("o1-reg", _nonce++))) | 1);
            if (!game.advanceDue() && !game.rngLocked()) break;
            try game.mineRun(0) {} catch {}
        }
        _mineAll(64);
    }

    /// @dev Cross the next reset and run the chain only until the fresh daily request is in
    ///      flight (rngLocked, dailyIdx advanced, word not yet delivered).
    function _toRequestWindow() internal returns (uint24 day) {
        uint24 before = game.currentDayView_g542950();
        _t += 1 days;
        vm.warp(_t);
        for (uint256 i; i < 400 && game.currentDayView_g542950() == before; ++i) {
            // Deliver only words for requests issued before this day's request (mid-day leftovers).
            _fulfilLatest(uint256(keccak256(abi.encode("o1-reg-pre", _nonce++))) | 1);
            if (game.currentDayView_g542950() != before) break;
            try game.mineRun(0) {} catch {}
        }
        day = game.currentDayView_g542950();
        assertEq(day, before + 1, "one fresh daily request");
        assertTrue(game.rngLocked(), "window: daily request in flight");
    }

    function _nextDay() internal {
        _toRequestWindow();
        _settle();
    }

    function _buy() internal {
        (,,,, uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 box = 0.5 ether;
        vm.prank(p);
        game.purchaseOrderFor{value: priceWei + box}(
            0, 400, BoxOrderLib.boCustomFloor(box), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    /// @dev Last box entry on the current write buffer, its frozen score.
    function _lastBoxScore() internal view returns (uint256 score, uint32 owner) {
        uint48 b = RecyclingState.writeBuffer(address(game));
        uint256 n = RecyclingState.boxCount(address(game), b);
        require(n != 0, "no box entry");
        uint256 e = RecyclingState.boxEntry(address(game), b, n - 1);
        return (BoxOrderLib.boScore(e), BoxOrderLib.boId(e));
    }

    /// @dev Place one ETH Degenerette spin and return the activity score frozen into the bet.
    function _betScore() internal returns (uint256) {
        vm.prank(p);
        game.betDegenerette{value: 0.01 ether}(0, 0, 0.01 ether, 1, 3);
        uint48 b = RecyclingState.writeBuffer(address(game));
        uint64 betId = DegeneretteQueue.lastBetId(vm, address(game), b);
        uint256 bet = DegeneretteQueue.betAt(vm, address(game), b, betId);
        require(uint32(bet) == id, "bet owner");
        return DegeneretteQueue.activity(bet);
    }

    /// @dev Build a real streak of `days_` primary completions, then lapse `lapse` logical days.
    function _buildAndLapse(uint256 days_, uint256 lapse) internal {
        _settle();
        for (uint256 i; i < days_; ++i) {
            _buy();
            if (id == 0) id = game.walletIdOf_g3120(p);
            _nextDay();
        }
        emit log_named_uint("raw streak after build", _rawStreak());
        emit log_named_uint("shields", _shields());
        // Each day completes the MINT_ETH primary (+1); the opened boxes and secondaries may add more.
        assertGe(_rawStreak(), days_, "at least one primary completion per real day");
        builtStreak = _rawStreak();
        uint256 built = _lastActive();
        for (uint256 i; i < lapse; ++i) _nextDay();
        assertEq(_lastActive(), built, "lapse: no quest action");
        assertGt(uint256(game.currentDayView_g542950()), built + 1 + _shields(), "misses exceed shields");
    }

    function test_LapsedStreakStaysDecayedInRequestWindow() public {
        _buildAndLapse(12, 4);
        uint24 dPrev = game.currentDayView_g542950();

        // Settled day (word applied): decay applies, the lapsed streak reads 0.
        assertEq(_activeQuestDay(), dPrev, "settled: quest day == Game day");
        uint256 settledStreak = quests.effectiveBaseStreak(id);
        (uint256 settledScore,) = game.playerActivityScore(p);
        assertEq(settledStreak, 0, "settled: lapsed streak decays to 0");

        // Request window: dailyIdx = D, quests still on D-1.
        uint24 d = _toRequestWindow();
        assertEq(_activeQuestDay(), dPrev, "window: quest record still carries D-1");
        assertEq(d, dPrev + 1);
        uint256 windowStreak = quests.effectiveBaseStreak(id);
        (uint256 windowScore,) = game.playerActivityScore(p);
        uint256 windowScoreById = game.playerActivityScoreById(id);
        (uint32 s2, bool afk) = quests.effectiveBaseStreakAndAfking_g1521(id, d);
        assertFalse(afk);

        // A real lootbox purchase inside the window freezes its score into its box entry.
        uint256 snap = vm.snapshotState();
        _buy();
        (uint256 windowBoxScore, uint32 owner) = _lastBoxScore();
        assertEq(owner, id, "window box is the player's");
        uint256 streakAfterWindowBuy = _rawStreak();
        assertTrue(vm.revertToState(snap));
        uint256 windowBetScore = _betScore();
        assertTrue(vm.revertToState(snap));

        // Same day after its word lands: decay applies again.
        _settle();
        assertEq(game.currentDayView_g542950(), d, "same logical day");
        assertEq(_activeQuestDay(), d, "word applied: quest day rolled to D");
        uint256 afterStreak = quests.effectiveBaseStreak(id);
        (uint256 afterScore,) = game.playerActivityScore(p);
        uint256 snap2 = vm.snapshotState();
        uint256 afterBetScore = _betScore();
        assertTrue(vm.revertToState(snap2));
        _buy();
        (uint256 afterBoxScore, uint32 owner2) = _lastBoxScore();
        assertEq(owner2, id);

        // Control: the settled day before and the same day after its word.
        assertEq(settledStreak, 0, "settled: decayed");
        assertEq(afterStreak, 0, "after word: decayed");
        assertEq(afterScore, settledScore, "after word: same score as the settled day");
        // The window reads exactly what the days around it read.
        assertEq(windowStreak, 0, "window: decayed against the Game day");
        assertEq(s2, 0, "window: Game-side streak read decayed");
        assertEq(windowScore, settledScore, "window score = settled score");
        assertEq(windowScoreById, windowScore);
        assertEq(windowBetScore, afterBetScore, "bet in the window freezes the same score as after the word");
        assertLe(windowBoxScore, afterBoxScore, "box in the window freezes no higher score than after the word");
        assertEq(streakAfterWindowBuy, builtStreak, "window buy neither syncs nor completes the quest");
        assertGt(builtStreak, 0, "fixture: a real streak was built");
    }
}
