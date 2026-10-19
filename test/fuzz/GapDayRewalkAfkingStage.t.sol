// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title GapDayRewalkAfkingStage — skipped days never stage subscriptions or draw seats.
/// @notice A request committed on R is fulfilled on W = R+3. The engine completes R's
///         consumers before staging W and requesting its fresh word. The fresh word credits
///         the intervening gap without purchases or seat draws on either skipped day.
///         Only the last gap word and W are retained in the tagged two-day word ring.
contract GapDayRewalkAfkingStage is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    // slot 0 packs purchaseStartDay u24 @0 · dailyIdx u24 @3 · ...
    uint256 private constant AFKING_RESET_SLOT = GameSlots.AFKING_RESET_DAY; // uint24 _afkingResetDay
    uint256 private constant AFKING_RESET_OFF = 4;

    bytes32 private constant AFKING_DELIVERED_SIG = keccak256("AfkingDelivered(uint32,uint256)");
    bytes32 private constant DAILY_RNG_APPLIED_SIG = keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)");
    bytes32 private constant SUB_DRAW_WON_SIG = keccak256("SubDrawWon(uint32,uint24,uint24,uint256)");

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
        _finishSubscriptionWindow();
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

        // Day R stamps subscriptions before committing the daily request. Scheduled
        // maintenance may require an earlier checkpoint, so await the actual request.
        _t += 1 days;
        vm.warp(_t);
        _requestDaily();
        uint24 R = game.currentDayView();
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), _aid(atk)), "day R: STAGE stamped the attacker");
        assertEq(_afkingResetDay(), R, "day R: STAGE reset stamped R");
        assertTrue(game.rngLocked(), "day R: request outstanding");
        uint256 reqR = mockVRF.lastRequestId();

        _t += 3 days;
        vm.warp(_t);
        uint24 W = game.currentDayView();
        assertEq(W, R + 3, "wall day is R+3");
        mockVRF.fulfillRandomWords(reqR, WORD_LATE);

        // A crank may both finish R and request W. Observe the request boundary, not
        // a historical intermediate unlock that the serialized engine can cross atomically.
        vm.recordLogs();
        for (uint256 i; i < 128 && mockVRF.lastRequestId() == reqR; ++i) {
            game.mineFlip{gas: 15_000_000}(0);
        }
        Vm.Log[] memory recoveryLogs = vm.getRecordedLogs();
        _assertNoGapLogs(recoveryLogs, R, W);
        assertEq(_dailyIdx(), R, "late word sealed the committed day R");
        _assertAppliedWord(recoveryLogs, R, WORD_LATE);
        assertEq(game.rngWordForDay(R), 0, "public word view expires history older than yesterday");
        assertEq(game.rngWordForDay(R + 1), 0, "R completion did not invent a gap word");
        // The record carries no open marker. R's boxes opened during this recovery: the W stage
        // could only prepare after the cohort count reached zero, so the live count is exactly W's
        // stamps and both subs' W boxes are pending.
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), _aid(atk)), "W box pending");
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), _aid(bystander)), "W box pending (bystander)");
        assertEq(_pendingCount(), 2, "R box completes before the next request: only W's stamps remain");
        assertEq(game.rngWordForDay(W), 0, "W was staged before its word was known");
        assertTrue(game.rngLocked(), "fresh W request is outstanding");
        assertEq(_afkingResetDay(), W, "one wall-day STAGE ran for W");
        assertEq(_endpoint(), W, "the W pass completed after R's box has completed");
        uint256 reqW = mockVRF.lastRequestId();
        assertTrue(reqW != reqR, "fresh request id");
        mockVRF.fulfillRandomWords(reqW, WORD_FRESH);
        uint256 predictedG2 = uint256(keccak256(abi.encodePacked(WORD_FRESH, uint24(R + 2))));

        // Smaller calls expose the post-gap, pre-jackpot checkpoint without changing
        // the logical word or permitting a subscription change while W remains locked.
        vm.recordLogs();
        for (uint256 i; i < 64 && game.rngWordForDay(W) == 0; ++i) {
            game.mineFlip{gas: 5_000_000}(0);
        }
        assertTrue(game.rngLocked(), "W remains locked before its daily battle finishes");
        assertEq(game.rngWordForDay(R + 1), 0, "older gap word retired from the two-day ring");
        assertEq(game.rngWordForDay(R + 2), predictedG2, "last gap word derives from W's fresh word");
        assertEq(game.rngWordForDay(W), WORD_FRESH, "W records its fresh word");
        assertEq(_dailyIdx(), W - 1, "gap credited without running either skipped day");
        uint256 seat = _grantSeat(atk);
        vm.prank(atk);
        vm.expectRevert(RngLocked.selector);
        game.subscribe(0, false, 2, seat);

        _advanceUntilUnlocked();
        Vm.Log[] memory sealLogs = vm.getRecordedLogs();
        _assertNoGapLogs(sealLogs, R, W);
        (uint256 delivW,) = _countAfkingLogs(sealLogs);
        assertEq(_dailyIdx(), W, "W sealed");
        assertEq(_afkingResetDay(), W, "W's stage was not repeated after publication");
        assertEq(_endpoint(), W, "the pass endpoint skipped the gap days");
        assertEq(delivW, 0, "no subscription purchases while sealing known words");
        assertEq(game.rngWordForDay(W + 1), 0, "no future daily word");
        _settleClean(WORD_FRESH);
        assertFalse(GameSlotKeys.afkingBoxPending(address(game), _aid(atk)), "W box completes through the ordered engine");

        // ---- Positive control: the next day runs the STAGE (uncommitted word) and the drawing. ----
        _t += 1 days;
        vm.warp(_t);
        uint24 N = game.currentDayView();
        assertEq(N, W + 1, "next wall day");
        assertEq(game.rngWordForDay(N), 0, "N's word uncommitted before its STAGE");
        vm.recordLogs();
        _requestDaily();
        (uint256 delivN,) = _countAfkingLogs(vm.getRecordedLogs());
        assertEq(_afkingResetDay(), N, "N: STAGE reset");
        assertTrue(GameSlotKeys.afkingBoxPending(address(game), _aid(atk)), "N: STAGE stamped the attacker after W completed");
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

    function _pendingCount() internal view returns (uint256) {
        return uint16(uint256(vm.load(address(game), bytes32(GameSlots.PENDING_BOX_COUNT))) >> (GameSlots.PENDING_BOX_COUNT_OFFSET * 8));
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
        uint256 seat = _grantSeat(who);
        _fundPool(who, 200 ether);
        vm.prank(who);
        game.subscribe(0, false, 1, seat);
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleClean(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleClean(vrfWord);
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            _fulfillPending(vrfWord);
            if (game.rngComplete() && !game.advanceDue() && !game.rngLocked() && !game.boxesPending()) return;
            game.mineFlip{gas: 15_000_000}(0);
        }
        revert("harness: current cohort never completed");
    }

    function _requestDaily() internal {
        for (uint256 i; i < 128; ++i) {
            if (game.rngLocked()) return;
            game.mineFlip{gas: 15_000_000}(0);
        }
        revert("harness: daily request never committed");
    }

    function _assertAppliedWord(Vm.Log[] memory logs, uint24 day, uint256 word) internal view {
        uint256 matches;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0
                || logs[i].topics[0] != DAILY_RNG_APPLIED_SIG) continue;
            (uint24 appliedDay, uint256 rawWord,, uint256 finalWord) =
                abi.decode(logs[i].data, (uint24, uint256, uint256, uint256));
            if (appliedDay != day) continue;
            assertEq(rawWord, word, "committed day receives its own raw word");
            assertEq(finalWord, word, "committed day receives its own unnudged word");
            ++matches;
        }
        assertEq(matches, 1, "committed day's word applied exactly once");
    }

    function _assertNoGapLogs(Vm.Log[] memory logs, uint24 R, uint24 W) internal view {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            uint24 day;
            if (logs[i].topics[0] == AFKING_DELIVERED_SIG) {
                day = uint24(abi.decode(logs[i].data, (uint256)) >> 128);
            } else if (logs[i].topics[0] == SUB_DRAW_WON_SIG) {
                (day,,) = abi.decode(logs[i].data, (uint24, uint24, uint256));
            } else continue;
            assertTrue(day <= R || day >= W, "no subscription charge or seat draw on a gap day");
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
            game.mineFlip{gas: 15_000_000}(0);
        }
        revert("harness: lock never released");
    }

    /// @dev Mine until the engine reports no work, so every stamped box has been opened in order.
    function _drainOpens() internal {
        _mineAll(16);
    }

    function _afkingResetDay() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(AFKING_RESET_SLOT))) >> (AFKING_RESET_OFF * 8));
    }

    function _dailyIdx() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24);
    }

    function _endpoint() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_ENDPOINT_DAY))) >> (GameSlots.AFKING_ENDPOINT_DAY_OFFSET * 8));
    }
}
