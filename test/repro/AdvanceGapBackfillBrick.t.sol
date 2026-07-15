// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

/// @dev Etch-only setter for the exact target-met replay boundary. Measured advances execute the
///      restored production runtime; this overlay only changes levelPrizePool in test storage.
contract PurchaseStartDaySeeder is DegenerusGame {
    function setLevelTarget(uint24 lvl, uint256 target) external {
        levelPrizePool[lvl] = target;
    }
}

/// @title AdvanceGapBackfillBrick — regression for finding C2 (AdvanceModule purchase-phase-stall brick).
///
/// @notice Before the fix, a purchase-phase VRF stall of a few days made `advanceGame` revert with
///         an arithmetic underflow (Panic 0x11) on every subsequent call — a PERMANENT brick with
///         no liveness escape. A bounds-only fix still let a target-met cached replay enter jackpot
///         without the request-time level promotion. The final fix gates both transition latches to
///         the real wall day, keeps `day >= psd` around the two subtractions, and requires an
///         unrequested word for turbo. This test proves the clock bump, replay, and promotion sequence.
///
///         MECHANISM (AdvanceModule @ HEAD):
///           - rngGate backfills a multi-day VRF gap and credits the FULL gap to storage
///             `purchaseStartDay` (`purchaseStartDay += gapCount`, ~L1263) while filling
///             `rngWordByDay` for every gap day, then defers (STAGE_GAP_BACKFILLED break ~L451)
///             WITHOUT sealing — so `dailyIdx` stays put but `purchaseStartDay` jumps ahead.
///           - The RNGREUSE clamp (L190: `day > dIdx+1 && rngWordByDay[dIdx+1] != 0 → day = dIdx+1`)
///             cannot tell a backfilled gap day from a live in-progress day, so it rewinds `day`
///             to `dailyIdx+1` and the walk seals one backfilled day per advance.
///           - As soon as a walk day seals and `_unlockRng` clears `rngLockedFlag`, the NEXT
///             advance reaches the turbo gate (L202, `!locked`) and computes
///             `uint32 purchaseDays = day - psd` (L203) with the clamped `day` still BELOW the
///             bumped `purchaseStartDay` → checked `uint24` subtraction underflow → Panic(0x11).
///           - The panic precedes the game-over/deadman gate (L216), so there is no escape;
///             `dailyIdx` and `purchaseStartDay` are frozen and every later call reverts identically.
///
/// @dev TEST-ONLY. No contracts/*.sol are touched. Run:
///      forge test --match-path test/repro/AdvanceGapBackfillBrick.t.sol -vvv
contract AdvanceGapBackfillBrick is DeployProtocol {
    uint256 private constant HEADER_SLOT = 0;
    uint256 private constant OFF_PURCHASE_START_DAY = 0;
    uint256 private constant OFF_DAILY_IDX = 3;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    /// @dev Complete a full day: advanceGame -> fulfill the pending daily word -> drain until unlocked.
    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    function _purchaseStartDay() internal view returns (uint24) {
        return _headerU24(OFF_PURCHASE_START_DAY);
    }

    function _dailyIdx() internal view returns (uint24) {
        return _headerU24(OFF_DAILY_IDX);
    }

    function _headerU24(uint256 byteOffset) private view returns (uint24) {
        uint256 packed = uint256(vm.load(address(game), bytes32(HEADER_SLOT)));
        return uint24(packed >> (byteOffset * 8));
    }

    function _isArithmeticPanic(bytes memory reason) private pure returns (bool) {
        if (reason.length != 36) return false;
        bytes4 selector;
        uint256 code;
        assembly {
            selector := mload(add(reason, 0x20))
            code := mload(add(reason, 0x24))
        }
        return selector == 0x4e487b71 && code == 0x11;
    }

    function _advanceAndFulfill(uint256 salt) private {
        try game.advanceGame() {
            if (!game.rngLocked()) return;
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId == 0) return;
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("walk", salt))) | 1);
            }
        } catch (bytes memory reason) {
            if (_isArithmeticPanic(reason)) {
                revert("C2 REGRESSION: advanceGame underflow-panicked (the brick is back)");
            }
            // NotTimeYet/RngNotReady are ordinary bounded-loop control flow; the state assertions
            // below make a permanently swallowed failure non-vacuous.
        }
    }

    function _setLevelTarget(uint24 lvl, uint256 target) private {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(PurchaseStartDaySeeder).runtimeCode);
        PurchaseStartDaySeeder(payable(address(game))).setLevelTarget(lvl, target);
        vm.etch(address(game), realCode);
    }

    function test_C2_purchasePhaseStall_advanceGameSurvives() public {
        // A buyer takes tickets in the opening purchase phase (sets the ticket queue + keeps us
        // firmly in the pre-target purchase phase, psd anchored at the deploy day).
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 0.05 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        // Seal the first post-deploy day normally so dailyIdx advances one step while psd stays put.
        _completeDay(0xDEAD0001);
        uint24 idxBeforeStall = _dailyIdx();
        uint24 psdBeforeStall = _purchaseStartDay();

        // Now stall: fire the daily request, then let many days pass with NO fulfillment.
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "daily VRF request is in flight (window open)");
        uint256 stalledReqId = mockVRF.lastRequestId();

        // Let 8 calendar days elapse during the stall, then the SAME coordinator finally answers.
        vm.warp(block.timestamp + 8 days);
        mockVRF.fulfillRandomWords(stalledReqId, 0xCAFEBABE);

        // Drive only until the gap backfill happens. The stalled word was requested on
        // reqDay (= idxBeforeStall + 1) and is public from its late fulfillment, so the
        // buffered RNGREUSE arm first seals reqDay with the raw word (a live day — no
        // purchase-clock credit); the following advance issues a fresh same-day request
        // whose word backfills the remaining [reqDay+1, resumeDay) as gap days. The
        // purchase clock must move by exactly that backfill count once, while dailyIdx
        // stays at reqDay because STAGE_GAP_BACKFILLED exits before _unlockRng.
        uint24 resumeDay = game.currentDayView();
        uint24 expectedGap = resumeDay - idxBeforeStall - 2;
        bool backfilled;
        for (uint256 i; i < 12; ++i) {
            _advanceAndFulfill(i);
            if (_purchaseStartDay() != psdBeforeStall) {
                backfilled = true;
                break;
            }
        }
        assertTrue(backfilled, "fixture reached the purchaseStartDay backfill bump");

        uint24 psdAfterBackfill = _purchaseStartDay();
        assertEq(psdAfterBackfill, psdBeforeStall + expectedGap, "purchaseStartDay bumped by exact gap once");
        assertEq(_dailyIdx(), idxBeforeStall + 1, "request day sealed before the backfill deferred");
        assertEq(game.rngWordForDay(idxBeforeStall + 1), 0xCAFEBABE, "request day kept its own raw word");
        assertTrue(game.rngWordForDay(idxBeforeStall + 2) != 0, "first replay day received a backfill word");

        // Make the target met only AFTER the backfill. Every replay day now sees targetMet=true,
        // so this catches the subtler failure: latching on a cached replay word would let the next
        // cached word bypass _finalizeRngRequest and enter jackpot without promoting level.
        _setLevelTarget(0, 0);

        bool sealedReplayBelowPsd;
        for (uint256 i; i < 80 && _dailyIdx() < resumeDay; ++i) {
            _advanceAndFulfill(100 + i);
            uint24 idx = _dailyIdx();
            if (idx > idxBeforeStall && idx < psdAfterBackfill) {
                sealedReplayBelowPsd = true;
            }
            if (idx < resumeDay) {
                (, bool inJackpot, bool lastPurchase, , ) = game.purchaseInfo();
                assertFalse(inJackpot, "cached replay must not enter jackpot");
                assertFalse(lastPurchase, "cached replay must not latch lastPurchaseDay");
                assertEq(game.level(), 0, "cached replay must not skip level promotion");
            }
        }

        assertTrue(sealedReplayBelowPsd, "dailyIdx sealed through the day<psd replay interval");
        assertEq(_dailyIdx(), resumeDay, "replay walk caught up to the real wall day");
        assertEq(_purchaseStartDay(), psdAfterBackfill, "purchaseStartDay bump remained exactly-once");
        assertFalse(game.gameOver(), "backfill recovery remains live");

        // Only the real wall-day completion may latch the target. Level stays 0 until the following
        // fresh calendar-day request, where _finalizeRngRequest is the sole writer that promotes it.
        (, bool inJackpotAtCatchup, bool lastPurchaseAtCatchup, , ) = game.purchaseInfo();
        assertFalse(inJackpotAtCatchup, "catch-up ends in purchase phase");
        assertTrue(lastPurchaseAtCatchup, "real wall day may latch the met target");
        assertEq(game.level(), 0, "level promotion waits for the fresh request");

        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 20 && !game.rngLocked(); ++i) {
            _advanceAndFulfill(1_000 + i);
        }
        assertTrue(game.rngLocked(), "fresh post-catchup day requested RNG");
        assertEq(game.level(), 1, "fresh request promoted level through _finalizeRngRequest");
    }
}
