// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title GapDayRewalkAfkingStage -- Regression for the re-walked gap day / afking STAGE freeze
///        (P1-fable H-1): a day whose rngWordByDay entry is already committed never runs the
///        STAGE, and a seal that does not release the VRF lock holds no seat drawing.
///
/// @notice Scenario: a daily VRF request fired on day R goes unanswered for three calendar days
///         (no keeper cranks). The word lands on day W = R+3. The advance:
///           #1  clamps to R (Buffered arm), resolves R with the late word, seals R.
///           #2  wall-day W: STAGE(W) runs on an uncommitted word, then a FRESH request fires.
///           #3  fresh word lands; rngGate backfills rngWordByDay[R+1], [R+2] = keccak(word, g)
///               and records W's word in the SAME tx, then breaks (STAGE_GAP_BACKFILLED).
///           #4  re-walks G1 = R+1 with the lock held (STAGE skipped), seals R+1 (lock off).
///           #5  re-walks G2 = R+2 with the lock DOWN and G2's word public: STAGE off, no drawing.
///           #6  wall-day W again with the lock down and W's word public: STAGE off, no drawing.
///         The next wall day (uncommitted word) runs the STAGE and its lock-releasing seal draws.
///
///         Observed through `lastAutoBoughtDay` / `_afkingResetDay` storage reads and the
///         AfkingDelivered / SubDrawWon logs of each crank.
contract GapDayRewalkAfkingStage is DeployProtocol {
    // forge inspect DegenerusGame storage: _subOf@52 (address => Sub, one packed slot); slot 0 packs
    // purchaseStartDay u24 @0 · dailyIdx u24 @3 · ...
    uint256 private constant SUBOF_SLOT = 52;
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity
    uint256 private constant OFF_AMOUNT = 4; // uint24 amount (milli-ETH)
    uint256 private constant OFF_LASTBOUGHT = 7; // uint24 lastAutoBoughtDay
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay
    uint256 private constant AFKING_RESET_SLOT = 56; // uint24 _afkingResetDay
    uint256 private constant AFKING_RESET_OFF = 4;

    bytes32 private constant AFKING_DELIVERED_SIG = keccak256("AfkingDelivered(address,uint256)");
    bytes32 private constant SUB_DRAW_WON_SIG = keccak256("SubDrawWon(address,uint24,uint24,uint256)");

    uint256 private constant WORD_NORMAL = 0xA11CE;
    uint256 private constant WORD_LATE = 0xBEEF_0001;
    uint256 private constant WORD_FRESH = 0xC0FFEE_0002;

    error RngLocked();

    uint256 private _t;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    function test_GapDayRewalkSkipsAfkingStageAndSeatDraw() public {
        address atk = makeAddr("gap_attacker");
        address bystander = makeAddr("gap_bystander");
        _setupSub(atk);
        _setupSub(bystander);

        // Two ordinary days so both subs carry a settled history (box stamped + opened each day).
        _runStageNewDay(WORD_NORMAL);
        _drainOpens();
        _runStageNewDay(WORD_NORMAL ^ 1);
        _drainOpens();

        // ---- Day R: STAGE(R) stamps, then the daily request fires and the lock engages. ----
        _t += 1 days;
        vm.warp(_t);
        game.advanceGame();
        uint24 R = game.currentDayView();
        assertEq(_lastBought(atk), R, "day R: STAGE stamped the attacker");
        assertEq(_afkingResetDay(), R, "day R: STAGE reset stamped R");
        assertTrue(game.rngLocked(), "day R: request outstanding");
        uint256 reqR = mockVRF.lastRequestId();

        // ---- VRF outage: three calendar days pass with no fulfilment and no crank. ----
        _t += 3 days;
        vm.warp(_t);
        uint24 W = game.currentDayView();
        assertEq(W, R + 3, "wall day is R+3");
        mockVRF.fulfillRandomWords(reqR, WORD_LATE);

        // ---- #1: Buffered clamp resolves R with the late word and seals it. ----
        _advanceUntilUnlocked();
        assertEq(_dailyIdx(), R, "#1 sealed R");
        assertTrue(game.rngWordForDay(R) != 0, "#1 recorded R's word");
        assertEq(game.rngWordForDay(R + 1), 0, "#1 did not touch R+1");
        assertTrue(_lastOpened(atk) < R, "R box pending");

        // ---- #2: the ONE wall-day STAGE(W), on a word not yet committed; fresh request. ----
        assertEq(game.rngWordForDay(W), 0, "#2 enters with W's word uncommitted");
        game.advanceGame();
        assertTrue(game.rngLocked(), "#2 fired the fresh request");
        assertEq(_afkingResetDay(), W, "#2 ran STAGE(W)");
        assertEq(_lastBought(atk), R, "#2 STAGE(W) skipped the attacker (pending R box)");
        assertEq(_lastBought(bystander), R, "#2 STAGE(W) skipped the bystander (pending R box)");
        uint256 reqW = mockVRF.lastRequestId();
        assertTrue(reqW != reqR, "fresh request id");
        mockVRF.fulfillRandomWords(reqW, WORD_FRESH);
        uint256 predictedG2 = uint256(keccak256(abi.encodePacked(WORD_FRESH, uint24(R + 2))));

        // ---- #3: backfill R+1, R+2 and record W in one tx; break with the lock held. ----
        game.advanceGame();
        assertTrue(game.rngLocked(), "#3 still locked");
        assertTrue(game.rngWordForDay(R + 1) != 0, "#3 backfilled R+1");
        assertEq(game.rngWordForDay(R + 2), predictedG2, "#3 backfilled R+2 = keccak(vrfWord, R+2)");
        assertTrue(game.rngWordForDay(W) != 0, "#3 recorded W's word");
        assertEq(_dailyIdx(), W - 1, "#3 skipped the gap days: index parked at W-1");

        // The gap words are public but the lock is up, so nothing player-side can move
        // against them: the subscription upsert is refused outright.
        vm.prank(atk);
        vm.expectRevert(RngLocked.selector);
        game.subscribe(address(0), false, false, 2, address(0));

        // The remaining advances pay W's jackpot under the lock and seal W. STAGE(W) ran
        // once, at #2, before the request; no gap day ever ran a STAGE or a seat draw.
        vm.recordLogs();
        _advanceUntilUnlocked();
        (uint256 delivW,) = _countAfkingLogs(vm.getRecordedLogs());
        assertEq(_dailyIdx(), W, "#4 sealed W");
        assertEq(_afkingResetDay(), W, "#4: STAGE(W) ran exactly once (at #2)");
        assertEq(_lastBought(atk), R, "#4: attacker not stamped on any gap day");
        assertEq(_lastBought(bystander), R, "#4: bystander not stamped on any gap day");
        assertEq(delivW, 0, "#4: no AfkingDelivered while sealing W");
        assertEq(game.rngWordForDay(W + 1), 0, "#4: unlocked with no word ahead");
        _drainOpens();
        assertEq(_lastOpened(atk), R, "R box opened through the valve");

        // ---- Positive control: the next day runs the STAGE (uncommitted word) and the drawing. ----
        _t += 1 days;
        vm.warp(_t);
        uint24 N = game.currentDayView();
        assertEq(N, W + 1, "next wall day");
        assertEq(game.rngWordForDay(N), 0, "N's word uncommitted before its STAGE");
        vm.recordLogs();
        game.advanceGame();
        (uint256 delivN,) = _countAfkingLogs(vm.getRecordedLogs());
        assertEq(_afkingResetDay(), N, "N: STAGE reset");
        assertEq(_lastBought(atk), N, "N: STAGE stamped the attacker (R box opened by the valve)");
        assertTrue(delivN != 0, "N: AfkingDelivered on the normal-day STAGE");
        assertTrue(game.rngLocked(), "N: request outstanding");
        // Pick a fulfil word whose seat draw lands on a player slot (ring: VAULT, sDGNRS, atk, bystander).
        uint256 wordN = WORD_FRESH ^ 0x5EA7;
        while (1 + (uint256(keccak256(abi.encodePacked("SEATDRAW", wordN))) % 3) == 1) wordN++;
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), wordN);
        vm.recordLogs();
        _advanceUntilUnlocked();
        (, uint256 drawsN) = _countAfkingLogs(vm.getRecordedLogs());
        assertEq(_dailyIdx(), N, "N sealed");
        assertEq(game.rngWordForDay(N), wordN, "N recorded the fulfil word unnudged");
        assertEq(drawsN, 1, "N: SubDrawWon at the lock-releasing seal");
    }

    /// @dev Counts game-emitted AfkingDelivered and SubDrawWon logs.
    function _countAfkingLogs(Vm.Log[] memory logs) internal view returns (uint256 deliveries, uint256 draws) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game)) continue;
            if (logs[i].topics[0] == AFKING_DELIVERED_SIG) deliveries++;
            else if (logs[i].topics[0] == SUB_DRAW_WON_SIG) draws++;
        }
    }

    // ---------------------------------------------------------------- helpers

    function _setupSub(address who) internal {
        _grantSeat(who);
        _fundPool(who, 200 ether);
        vm.prank(who);
        game.subscribe(address(0), false, false, 1, address(0));
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleClean(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleClean(vrfWord);
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _advanceUntilUnlocked() internal {
        for (uint256 i; i < 64; i++) {
            if (!game.rngLocked()) return;
            game.advanceGame();
        }
        revert("harness: lock never released");
    }

    function _drainOpens() internal {
        for (uint256 i; i < 16; i++) {
            if (game.openBoxes(64) == 0) return;
        }
    }

    function _afkingResetDay() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(AFKING_RESET_SLOT))) >> (AFKING_RESET_OFF * 8));
    }

    function _dailyIdx() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24);
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQty(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _lastBought(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpened(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }
}
