// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

// MidDayStallCredit — the deadline credit for a VRF stall on a MID-DAY request (audit A-1),
// compared against the daily path, the coordinator-swap rescue, unattended gaps, the deadman,
// the vault owner's retry, the VRF-dead window, a same-day second request and the turbo
// activation. Written to compile and run unchanged against the frozen tree and both candidate
// fixes; the report lists which tests each tree fails.

/// @dev Level-1 purchase phase seeder plus read-backs (etched over the game, then etched back).
contract StallCreditSeeder is DegenerusGame {
    function seed(uint24 age) external {
        uint24 day = _simulatedDayIndex();
        level = 1;
        purchaseStartDay = day - age;
        dailyIdx = day - 1;
        levelPrizePool[1] = 10 ether;
        _setPrizePools(9 ether, 0);
        currentPrizePool = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
    }

    function setNextPool(uint128 next) external {
        _setPrizePools(next, 0);
    }

    function clock() external view returns (uint24 psd, uint24 idx) {
        return (purchaseStartDay, dailyIdx);
    }

    function vrfDeadView() external view returns (bool) {
        return _vrfDead();
    }

    function stamps() external view returns (uint48 requestTime, uint256 requestId) {
        // Logical authority: idle physical IDs are deliberately retained nonzero.
        return (rngRequestTime, _rngRequestActive() ? vrfRequestId : 0);
    }

    function latches() external view returns (bool goLvl, bool goDead) {
        return (_lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) != 0, _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0);
    }

    function earlyTicketLevelView() external view returns (uint24) {
        return earlyTicketLevel;
    }

    function dayOf(uint48 t) external pure returns (uint24) {
        return _simulatedDayIndexAt(t);
    }
}

abstract contract StallCreditBase is DeployProtocol {
    bytes internal realCode;
    MockVRFCoordinator internal vrf;
    address internal vaultOwner = makeAddr("vaultOwner");
    address internal stranger = makeAddr("stranger");

    function setUp() public virtual {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(vm.getBlockTimestamp() + 500 days);
        vm.deal(address(game), 20 ether);
        realCode = address(game).code;
        vrf = mockVRF;
        vm.mockCall(address(vault), abi.encodeWithSignature("isVaultOwner(address)", vaultOwner), abi.encode(true));
    }

    function _seeder() internal returns (StallCreditSeeder s) {
        vm.etch(address(game), type(StallCreditSeeder).runtimeCode);
        s = StallCreditSeeder(payable(address(game)));
    }

    function _restore() internal {
        vm.etch(address(game), realCode);
    }

    function _seed(uint24 age) internal {
        _seeder().seed(age);
        _restore();
    }

    function _clock() internal returns (uint24 psd, uint24 idx) {
        (psd, idx) = _seeder().clock();
        _restore();
    }

    function _vrfDead() internal returns (bool dead) {
        dead = _seeder().vrfDeadView();
        _restore();
    }

    function _stamps() internal returns (uint48 t, uint256 id) {
        (t, id) = _seeder().stamps();
        _restore();
    }

    function _dayOf(uint48 t) internal returns (uint24 d) {
        d = _seeder().dayOf(t);
        _restore();
    }

    /// @dev Advance as a caller who is not the vault owner (never fires the owner's retry).
    function _adv() internal {
        vm.prank(stranger);
        game.mineFlip();
    }

    /// @dev During a stall: advance as a stranger until the advance reverts (the day's afking
    ///      stage may run first), proving no new day can progress.
    function _advUntilBlocked() internal {
        for (uint256 i; i < 40; ++i) {
            vm.prank(stranger);
            try game.mineFlip() {} catch (bytes memory err) {
                assertEq(bytes4(err), bytes4(keccak256("RngNotReady()")), "blocked waiting for the word");
                assertFalse(game.rngLocked(), "blocked with no daily lock");
                return;
            }
        }
        revert("harness: the stalled day was never blocked");
    }

    function _latches() internal returns (bool goLvl, bool goDead) {
        (goLvl, goDead) = _seeder().latches();
        _restore();
    }

    /// @dev The first advance past the trigger latches the ending; the terminal word is always
    ///      the ending's own request, sent after the freeze (60d31f775), so game over follows
    ///      once that request is answered and the payout runs. Asserts both steps.
    function _endsOnTheGameOverPath(string memory label) internal {
        _adv();
        (bool goLvl,) = _latches();
        assertTrue(goLvl, label);
        for (uint256 i; i < 40 && !game.gameOver(); ++i) {
            _answer();
            _adv();
        }
        assertTrue(game.gameOver(), label);
    }

    function _answer() internal {
        uint256 id = vrf.lastRequestId();
        if (id == 0) return;
        (,, bool done) = vrf.pendingRequests(id);
        if (!done) vrf.fulfillRandomWords(id, uint256(keccak256(abi.encode(id, address(vrf), "stall-credit"))));
    }

    /// @dev Advance (answering every request at once) until `day` is sealed and unlocked.
    function _sealDay(uint24 day) internal {
        // setUp's synthetic 500-day jump leaves one expired scheduled Craps day
        // per maintenance checkpoint before the first daily request can be sent.
        for (uint256 i; i < 750; ++i) {
            _answer();
            (, uint24 idx) = _clock();
            if (!game.rngLocked() && idx == day && game.rngWordForDay(day) != 0) return;
            assertFalse(game.gameOver(), "harness: the level ended while sealing");
            _adv();
        }
        revert("harness: day never sealed");
    }

    /// @dev A mid-day request from a funded donor: the credit waives the pending-value gates, so
    ///      the request needs no lootbox queue and leaves no craps residue.
    function _middayRequest() internal returns (uint256 id) {
        _finishReadConsumers();
        _donorRequest();
        id = vrf.lastRequestId();
        (uint48 t, uint256 live) = _stamps();
        assertEq(live, id, "harness: mid-day request in flight");
        assertTrue(t != 0, "harness: stamped");
    }

    function _donorRequest() internal {
        address donor = makeAddr("midday-donor");
        mockFeed.setUpdatedAt(block.timestamp); // the credit charge prices off a fresh feed
        vm.prank(ContractAddresses.ADMIN);
        game.creditMiddayRng(donor, 1 ether);
        vm.prank(donor);
        game.requestLootboxRng();
    }

    function _warpDays(uint256 n) internal {
        vm.warp(vm.getBlockTimestamp() + n * 1 days);
    }

    /// @dev Warp to a time inside `day` well clear of the pre-reset minute.
    function _warpToDay(uint24 day) internal {
        uint24 today = game.currentDayView();
        if (day > today) _warpDays(day - today);
        assertEq(game.currentDayView(), day, "harness: warp");
    }

    function _rotate() internal {
        MockVRFCoordinator newVRF = new MockVRFCoordinator();
        uint256 subId = newVRF.createSubscription();
        newVRF.addConsumer(subId, address(game));
        newVRF.fundSubscription(subId, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), subId, bytes32(uint256(1)));
        vrf = newVRF;
    }

    /// @dev After a recovery: advance until `w` is sealed, never ending the level.
    function _catchUp(uint24 w) internal {
        for (uint256 i; i < 300; ++i) {
            assertFalse(game.gameOver(), "the level must not end");
            _answer();
            (, uint24 idx) = _clock();
            if (!game.rngLocked() && idx == w && game.rngWordForDay(w) != 0) return;
            // A read-drain step returns mult 0 too; the level state is the real check.
            _adv();
            assertFalse(game.gameOver() || game.livenessTriggered(), "no advance may take the game-over path");
        }
        revert("harness: never caught up");
    }
}

contract MidDayStallCreditTest is StallCreditBase {
    /// @notice Audit A-1. The day before the day before the deadline seals; that evening a mid-day
    ///         request stalls for five days and its word lands three days past the deadline.
    ///         The level must survive and the four stalled days must be credited once.
    function test_middayStallAcrossDeadlineKeepsTheLevel() public {
        _seed(28);
        uint24 x = game.currentDayView();
        _sealDay(x);
        (uint24 psd0,) = _clock();
        assertEq(x, psd0 + 28, "harness: X = deadline - 2");
        _middayRequest();

        for (uint256 d = 1; d <= 5; ++d) {
            _warpDays(1);
            assertFalse(game.livenessTriggered(), "a request in flight waits");
            _advUntilBlocked();
        }
        uint24 w = game.currentDayView();
        assertEq(w, psd0 + 33, "harness: W = deadline + 3");

        _answer();
        assertFalse(game.livenessTriggered(), "a recovered mid-day stall must not read as an unattended gap");
        vm.expectRevert();
        vm.prank(stranger);
        game.requestLootboxRng(); // today holds no word yet: no second mid-day request can replace the stamp

        _catchUp(w);
        (uint24 psd1, uint24 idx1) = _clock();
        assertEq(psd1, psd0 + (w - x - 1), "exactly the stalled days credited");
        assertEq(idx1, w, "caught up");
        assertFalse(game.livenessTriggered(), "alive");

        _warpDays(1);
        _sealDay(w + 1);
        (uint24 psd2,) = _clock();
        assertEq(psd2, psd1, "no second credit");
    }

    /// @notice The same timing on the daily request: unchanged behaviour.
    function test_dailyStallAcrossDeadlineKeepsTheLevel() public {
        _seed(28);
        uint24 x = game.currentDayView();
        (uint24 psd0,) = _clock();
        // setUp's synthetic 500-day jump leaves expired scheduled Craps days that the engine
        // maintains, one checkpoint per call, before the first daily request (see _sealDay).
        for (uint256 i; i < 750 && !game.rngLocked(); ++i) _adv();
        assertTrue(game.rngLocked(), "day X requested; VRF stalls");

        _warpDays(5);
        uint24 w = game.currentDayView();
        assertFalse(game.livenessTriggered(), "a request in flight waits");
        _answer();
        // The call that seals X goes straight on to the wall day's fresh request (the engine
        // selects it in the same flow, 60d31f775), so the drive stops on X's seal.
        for (uint256 i; i < 300; ++i) {
            (, uint24 sealedIdx) = _clock();
            if (sealedIdx >= x) break;
            _adv();
            _answer();
        }
        // rngWordForDay retains today and yesterday only (c729ecfc9); X is five days back, so
        // read its exact-tag ring entry before the wall day's word replaces that parity.
        assertEq(RecyclingState.dailyWord(address(game), x) != 0, true, "X finished on its late word");
        assertFalse(game.livenessTriggered(), "a recovered daily stall waits for its credit");

        _catchUp(w);
        (uint24 psd1, uint24 idx1) = _clock();
        assertEq(psd1, psd0 + (w - x - 1), "the stalled days credited");
        assertEq(idx1, w, "caught up");
    }

    /// @notice The mid-day stall is rescued by a coordinator swap, which re-sends it as a mid-day
    ///         request; its word lands three days past the deadline.
    function test_rotatedMiddayStallAcrossDeadlineKeepsTheLevel() public {
        _seed(28);
        uint24 x = game.currentDayView();
        _sealDay(x);
        (uint24 psd0,) = _clock();
        uint256 oldId = _middayRequest();

        _warpDays(2);
        _rotate();
        (, uint256 reissued) = _stamps();
        assertTrue(reissued != 0 && vrf.lastRequestId() == reissued, "re-sent on the new coordinator");
        assertFalse(game.rngLocked(), "still a mid-day request");
        oldId; // the old coordinator's answer would no longer match

        _warpDays(3);
        uint24 w = game.currentDayView();
        _answer();
        assertFalse(game.livenessTriggered(), "the swap's own answer must not fire the trigger");

        _catchUp(w);
        (uint24 psd1,) = _clock();
        assertEq(psd1, psd0 + (w - x - 1), "the stalled days credited");
    }

    /// @notice G rule: a gap behind dailyIdx past the deadline is a stall of that length, however it
    ///         arose (here nobody advanced for two days). It waits, the next advance credits it,
    ///         and the level ends at the next caught-up day.
    function test_idleGapAcrossDeadlineIsCreditedThenEndsWhenCaughtUp() public {
        _seed(29);
        uint24 x = game.currentDayView();
        _sealDay(x);
        (uint24 psd0,) = _clock();
        _warpToDay(x + 3);
        assertFalse(game.livenessTriggered(), "a gap waits for its credit");
        _catchUp(x + 3);
        (uint24 psd1,) = _clock();
        assertEq(psd1, psd0 + 2, "the gap is credited once");
        assertFalse(game.livenessTriggered(), "today holds its word");
        _warpToDay(x + 4);
        assertTrue(game.livenessTriggered(), "the next caught-up day past the deadline fires");
        _endsOnTheGameOverPath("and the advance takes the game-over path");
        (bool goLvl,) = _latches();
        assertTrue(goLvl, "the ending latched");
    }

    /// @notice The caught-up day after the deadline fires the trigger, and ANY keeper crank latches
    ///         the ending: mineFlip's advance leg runs whenever an advance is due and does not revert
    ///         when that advance pays nothing.
    function test_mineFlipOnTheCaughtUpDayLatchesTheEnding() public {
        _seed(30);
        uint24 s = game.currentDayView();
        _sealDay(s);
        _middayRequest();
        _answer();
        _warpToDay(s + 1);
        assertTrue(game.livenessTriggered(), "caught-up day past the deadline");
        vm.prank(stranger);
        game.mineFlip();
        (bool goLvl,) = _latches();
        assertTrue(goLvl, "a plain keeper crank latched the ending");
        _warpToDay(s + 2);
        assertTrue(game.livenessTriggered(), "latched: stays triggered");
    }

    /// @notice G rule, documented: a caught-up day nobody advances reads true, and once it has
    ///         passed the gap reads as a stall again and is credited (accepted: nobody advancing is
    ///         not a case the deadline has to handle; the deadman still bounds it).
    function test_skippedCaughtUpDayIsCreditedByDesign() public {
        _seed(30);
        uint24 s = game.currentDayView();
        _sealDay(s);
        (uint24 psd0,) = _clock();
        _warpToDay(s + 1);
        assertTrue(game.livenessTriggered(), "caught-up day past the deadline");
        _warpToDay(s + 2);
        assertFalse(game.livenessTriggered(), "skipped: the gap waits");
        _catchUp(s + 2);
        (uint24 psd1,) = _clock();
        assertEq(psd1, psd0 + 1, "the skipped day credited once");
    }

    /// @notice A gap past the deadline that nobody ever closes still ends at the deadman.
    function test_gapPastTheDeadlineEndsAtTheDeadman() public {
        _seed(29);
        uint24 x = game.currentDayView();
        _sealDay(x);
        _warpToDay(x + 30);
        assertFalse(game.livenessTriggered(), "a gap waits");
        _warpToDay(x + 31);
        assertTrue(game.livenessTriggered(), "deadman");
        _endsOnTheGameOverPath("the advance takes the game-over path");
    }

    /// @notice Whatever the last request, a game nobody seals for the deadman window ends.
    function test_answeredMiddayGameEndsAtTheDeadman() public {
        _seed(5);
        uint24 x = game.currentDayView();
        _sealDay(x);
        _middayRequest();
        _answer();
        _warpToDay(x + 31);
        assertTrue(game.livenessTriggered(), "deadman");
        _endsOnTheGameOverPath("the advance takes the game-over path");
    }

    /// @notice The Admin retry preserves a stalled mid-day request's mode and original timeout.
    function test_middayRetryTimerUnchanged() public {
        _seed(5);
        uint24 x = game.currentDayView();
        _sealDay(x);
        uint256 id = _middayRequest();
        (uint48 t0,) = _stamps();

        _warpDays(1);
        _advUntilBlocked(); // no retry for a non-owner

        vm.prank(vaultOwner);
        admin.retryGameRng();
        assertFalse(game.rngLocked(), "retry preserves the original midday mode");
        (uint48 t1, uint256 id1) = _stamps();
        assertTrue(id1 != id && id1 == vrf.lastRequestId(), "a fresh request ID");
        assertEq(t1, t0, "retry preserves the original timestamp");
        // rngFlagsAndNudges bit 10 (slot-0 bit 250) is the request's retry-spent flag.
        assertEq((uint256(vm.load(address(game), bytes32(0))) >> 250) & 1, 1, "retry spends its allowance");
        assertEq(_dayOf(t1), x, "retry remains attached to its original request day");
        _catchUp(x + 1);
    }

    /// @notice A mid-day request that was answered is not waited on: the next day any caller's
    ///         advance sends the fresh daily request, and no retry is needed or offered.
    function test_answeredMiddayIsNotWaitedOn() public {
        _seed(5);
        uint24 x = game.currentDayView();
        _sealDay(x);
        _middayRequest();
        _answer();
        _warpDays(1);
        for (uint256 i; i < 60 && !game.rngLocked(); ++i) _adv();
        assertTrue(game.rngLocked(), "the day's fresh daily request went out");
        (uint48 t,) = _stamps();
        assertEq(game.currentDayView(), _dayOf(t), "stamped today");
        assertEq(t & 1, 0, "its retry unspent");
        _catchUp(x + 1);
    }

    /// @notice A second mid-day request on the same day after the first was answered.
    function test_secondMiddayRequestSameDay() public {
        _seed(5);
        uint24 x = game.currentDayView();
        _sealDay(x);
        uint256 a = _middayRequest();
        _answer();
        uint256 b = _middayRequest();
        assertTrue(b != a, "a second request went out");
        _answer();
    }

    /// @notice An answered mid-day request never reads as a dead VRF, however long nobody advances.
    function test_answeredMiddayIsNeverVrfDead() public {
        _seed(5);
        uint24 x = game.currentDayView();
        _sealDay(x);
        _middayRequest();
        _answer();
        _warpToDay(x + 20);
        assertFalse(_vrfDead(), "VRF answered: not dead");
    }

    /// @notice The ending's terminal request is refused by the coordinator: the VRF-dead window
    ///         starts at that refusal even though the last request before it (a mid-day one) was
    ///         answered, and the deterministic ending takes over once it passes.
    function test_refusedTerminalRequestStartsTheDeadWindow() public {
        _seed(30);
        uint24 x = game.currentDayView();
        _sealDay(x);
        _middayRequest();
        _answer();
        _warpToDay(x + 1);
        assertTrue(game.livenessTriggered(), "caught-up day past the deadline");

        vm.mockCallRevert(address(vrf), abi.encodeWithSelector(MockVRFCoordinator.requestRandomWords.selector), "");
        for (uint256 i; i < 20; ++i) {
            // Each advance is on the game-over path: the first latches the ending (game over
            // itself waits for the ending's own terminal word, 60d31f775).
            _adv();
            (bool goLvl,) = _latches();
            assertTrue(goLvl, "game-over path");
            (uint48 t, uint256 id) = _stamps();
            if (id == 0 && t != 0 && _dayOf(t) == x + 1) break;
        }
        (uint48 ts, uint256 rid) = _stamps();
        assertEq(rid, 0, "the terminal request was refused");
        assertEq(_dayOf(ts), x + 1, "the refusal started the VRF-dead window");
        assertFalse(_vrfDead(), "not yet");

        _warpDays(15);
        assertTrue(_vrfDead(), "fourteen days after the refusal VRF is dead");
        _adv();
        (, bool goDead) = _latches();
        assertTrue(goDead, "the deterministic ending latched");
    }

    /// @notice A turbo transition on the day after an answered mid-day request activates the next
    ///         level's future pool exactly as it does with no earlier request.
    function test_turboAfterAnsweredMiddayActivatesNextTickets() public {
        _seed(0);
        uint24 x = game.currentDayView();
        _sealDay(x);
        _middayRequest();
        _answer();
        StallCreditSeeder s = _seeder();
        s.setNextPool(11 ether);
        uint24 before = s.earlyTicketLevelView();
        _restore();
        assertLt(before, 3, "harness: not yet active");

        _warpDays(1);
        for (uint256 i; i < 60 && !game.rngLocked(); ++i) _adv();
        assertTrue(game.rngLocked(), "the turbo transition request went out");
        s = _seeder();
        uint24 early = s.earlyTicketLevelView();
        _restore();
        assertEq(early, 3, "the turbo request activated level + 2");
    }

}

/// @notice Per-transaction gas of the paths the candidate rules touch. Run with `--isolate` so each
///         external call is its own transaction (cold accounts/slots, per-tx original values,
///         refunds reported separately); `used` is gas spent before the refund.
contract MidDayStallCreditGas is StallCreditBase {
    function _log(string memory label) private {
        Vm.Gas memory g = vm.lastCallGas();
        console.log(label);
        console.log("  used", uint256(g.gasTotalUsed), "refund", uint256(int256(g.gasRefunded)));
    }

    function _fulfil(uint256 id, string memory label) private {
        uint256[] memory words = new uint256[](1);
        words[0] = uint256(keccak256(abi.encode(id, "gas")));
        vm.prank(address(vrf));
        game.rawFulfillRandomWords(id, words);
        _log(label);
    }

    function test_gas_middayCallbackSameDay() public {
        _seed(5);
        _sealDay(game.currentDayView());
        _fulfil(_middayRequest(), "GAS middayCallbackSameDay used/refund");
    }

    function test_gas_middayCallbackLate() public {
        _seed(5);
        _sealDay(game.currentDayView());
        uint256 id = _middayRequest();
        _warpDays(3);
        _fulfil(id, "GAS middayCallbackLate used/refund");
    }

    function test_gas_dailyCallback() public {
        _seed(5);
        for (uint256 i; i < 60 && !game.rngLocked(); ++i) _adv();
        _fulfil(vrf.lastRequestId(), "GAS dailyCallback used/refund");
    }

    function test_gas_middayRequestFirst() public {
        _seed(5);
        _sealDay(game.currentDayView());
        _finishReadConsumers();
        _donorRequest();
        _log("GAS middayRequestFirst used/refund");
    }

    function test_gas_middayRequestAfterAnswer() public {
        _seed(5);
        _sealDay(game.currentDayView());
        _middayRequest();
        _answer();
        vm.warp(vm.getBlockTimestamp() + 1 hours); // a later request, not the same second's stamp
        _finishReadConsumers();
        _donorRequest();
        _log("GAS middayRequestAfterAnswer used/refund");
    }

    /// @dev The advance that sends the next day's daily request, after an answered mid-day request.
    function test_gas_dailyRequestAdvanceAfterAnsweredMidday() public {
        _seed(5);
        _sealDay(game.currentDayView());
        _middayRequest();
        _answer();
        _warpDays(1);
        _measureRequestAdvance("GAS dailyRequestAdvanceAfterAnsweredMidday used/refund");
    }

    /// @dev The same advance with no mid-day request the day before.
    function test_gas_dailyRequestAdvancePlain() public {
        _seed(5);
        _sealDay(game.currentDayView());
        _warpDays(1);
        _measureRequestAdvance("GAS dailyRequestAdvancePlain used/refund");
    }

    /// @dev The advance that sends the daily request after a mid-day stall recovered late.
    function test_gas_dailyRequestAdvanceAfterLateMidday() public {
        _seed(5);
        _sealDay(game.currentDayView());
        _middayRequest();
        _warpDays(3);
        _answer();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        _measureRequestAdvance("GAS dailyRequestAdvanceAfterLateMidday used/refund");
    }

    /// @dev The backfill advance that credits the stalled days after a late mid-day recovery.
    function test_gas_backfillAdvanceAfterLateMidday() public {
        _seed(5);
        _sealDay(game.currentDayView());
        _middayRequest();
        _warpDays(3);
        _answer();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        for (uint256 i; i < 60 && !game.rngLocked(); ++i) _adv();
        _answer();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(stranger);
        game.mineFlip();
        _log("GAS backfillAdvanceAfterLateMidday used/refund");
    }

    function _measureRequestAdvance(string memory label) private {
        for (uint256 i; i < 60; ++i) {
            vm.prank(stranger);
            game.mineFlip();
            Vm.Gas memory g = vm.lastCallGas(); // before the rngLocked() probe replaces it
            if (game.rngLocked()) {
                console.log(label);
                console.log("  used", uint256(g.gasTotalUsed), "refund", uint256(int256(g.gasRefunded)));
                return;
            }
        }
        revert("harness: no request");
    }
}
