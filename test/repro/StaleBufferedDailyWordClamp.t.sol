// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title StaleBufferedDailyWordClamp — a daily VRF word delivered on its request day but left
///        unconsumed across the day boundary resolves ONLY its request day; the following day
///        is settled by a fresh VRF request.
///
/// @notice MECHANISM (AdvanceModule RNGREUSE guard, buffered arm):
///         A delivered daily word (rngWordCurrent) is public from its fulfillment tx, and flip
///         deposits stay open during the RNG lock targeting wallDay+1. Without the clamp, an
///         advance on day D+1 routes the day-D-requested word through rngGate's gap path: day D
///         is backfilled with a derived word and day D+1 consumes the RAW word — so a flip
///         deposited on day D after fulfillment (targeting D+1) would resolve against a word
///         already public at deposit time. The buffered clamp arm instead points the word at its
///         request day (whose deposit window closed before the request fired) and the next
///         advance issues a fresh VRF request for the wall day.
///
/// @dev TEST-ONLY. No contracts/*.sol are touched. Run:
///      forge test --match-path test/repro/StaleBufferedDailyWordClamp.t.sol -vvv
contract StaleBufferedDailyWordClamp is DeployProtocol {
    uint256 private constant HEADER_SLOT = 0;
    uint256 private constant OFF_DAILY_IDX = 3;

    // Opposite low bits so a word-reuse regression flips day D+1's coinflip outcome.
    uint256 private constant WORD_D = 0xC0FFEE01; // odd  -> win
    uint256 private constant WORD_E = 0xB16B00B0; // even -> loss

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _dailyIdx() internal view returns (uint24) {
        uint256 packed = uint256(vm.load(address(game), bytes32(HEADER_SLOT)));
        return uint24(packed >> (OFF_DAILY_IDX * 8));
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

    function test_bufferedDailyWord_resolvesRequestDayOnly() public {
        // Anchor the purchase phase with a small ticket buy (mirrors the gap-backfill fixture).
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 0.05 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        // Warp via vm.getBlockTimestamp(): the optimizer treats the TIMESTAMP opcode as
        // invariant within a transaction, so `block.timestamp` expressions are unreliable
        // across vm.warp calls in the same test frame.
        // Seal the first post-deploy day normally.
        _completeDay(0xDEAD0001);
        uint24 idxSealed = _dailyIdx();

        // Day D: fire the daily request, then the word arrives the SAME day — but no advance
        // consumes it before the boundary. From the fulfillment tx onward the word is public
        // while depositCoinflip is still open (those deposits target day D+1).
        vm.warp(vm.getBlockTimestamp() + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "daily VRF request in flight on day D");
        uint24 dayD = game.currentDayView();
        assertEq(dayD, idxSealed + 1, "day D is the in-progress day");
        uint256 staleReqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(staleReqId, WORD_D);
        assertTrue(game.isRngFulfilled(), "word buffered (public) before the boundary");

        // Day D+1: the clamp must route the buffered word to day D and stop there.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i = 0; i < 20; i++) {
            game.advanceGame();
            if (!game.rngLocked() && _dailyIdx() == dayD) break;
        }
        assertEq(_dailyIdx(), dayD, "clamped advance sealed the request day");
        assertEq(game.rngWordForDay(dayD), WORD_D, "request day resolved with its own raw word");
        assertEq(game.rngWordForDay(dayD + 1), 0, "buffered word NOT reused for day D+1");
        (uint16 rpD, bool winD) = coinflip.getCoinflipDayResult(dayD);
        assertTrue(rpD != 0, "day D coinflip settled");
        assertTrue(winD, "day D win bit matches WORD_D & 1");
        (uint16 rpE, ) = coinflip.getCoinflipDayResult(dayD + 1);
        assertEq(rpE, 0, "day D+1 coinflip untouched by the stale word");

        // Day D+1 gets its OWN request — entropy unknown to any deposit that targeted it.
        game.advanceGame();
        assertTrue(game.rngLocked(), "fresh daily VRF request in flight for day D+1");
        uint256 freshReqId = mockVRF.lastRequestId();
        assertTrue(freshReqId != staleReqId, "day D+1 word comes from a new request");
        mockVRF.fulfillRandomWords(freshReqId, WORD_E);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
        assertEq(_dailyIdx(), dayD + 1, "day D+1 sealed");
        assertEq(game.rngWordForDay(dayD + 1), WORD_E, "day D+1 resolved with the fresh word");
        (uint16 rpE2, bool winE) = coinflip.getCoinflipDayResult(dayD + 1);
        assertTrue(rpE2 != 0, "day D+1 coinflip settled");
        assertFalse(winE, "day D+1 win bit matches WORD_E & 1 (a reuse regression flips this)");
    }
}
