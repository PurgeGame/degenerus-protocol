// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {stdError} from "forge-std/StdError.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title AdvanceGapBackfillBrick — PoC for candidate C2 (AdvanceModule permanent brick).
///
/// @notice A purchase-phase VRF stall of a few days makes `advanceGame` revert with an
///         arithmetic underflow (Panic 0x11) on every subsequent call — a PERMANENT brick with
///         no liveness escape.
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
    // purchaseStartDay is a uint24 packed in slot 0; read it via the same view the game exposes.
    // (No public getter — derive state through currentDayView + behavior instead.)

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

    function test_C2_purchasePhaseStall_bricksAdvanceGame() public {
        // A buyer takes tickets in the opening purchase phase (sets the ticket queue + keeps us
        // firmly in the pre-target purchase phase, psd anchored at the deploy day).
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 0.05 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        // Seal the first post-deploy day normally so dailyIdx advances one step while psd stays put.
        _completeDay(0xDEAD0001);
        uint24 dayAfterFirst = game.currentDayView();

        // Now stall: fire the daily request, then let many days pass with NO fulfillment.
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "daily VRF request is in flight (window open)");
        uint256 stalledReqId = mockVRF.lastRequestId();

        // Let 8 calendar days elapse during the stall, then the SAME coordinator finally answers.
        vm.warp(block.timestamp + 8 days);
        mockVRF.fulfillRandomWords(stalledReqId, 0xCAFEBABE);

        // The next advance runs rngGate: it backfills the 8-day gap and bumps purchaseStartDay by
        // the full gap, then defers without sealing. Subsequent advances walk the backfilled days
        // one per call. Within a bounded number of calls, one seals + unlocks and the following
        // advance hits the turbo-gate underflow. Drive advanceGame and require that it bricks.
        bool bricked;
        for (uint256 i = 0; i < 20; i++) {
            try game.advanceGame() {
                // still progressing — keep going
            } catch (bytes memory reason) {
                // Arithmetic underflow surfaces as Panic(0x11): selector 0x4e487b71 + code 0x11.
                if (reason.length == 36) {
                    bytes4 sel;
                    uint256 code;
                    assembly {
                        sel := mload(add(reason, 0x20))
                        code := mload(add(reason, 0x24))
                    }
                    if (sel == 0x4e487b71 && code == 0x11) {
                        bricked = true;
                        break;
                    }
                }
                // Any other revert is not the brick we are proving — surface it.
                revert("advanceGame reverted with a non-underflow reason");
            }
        }

        assertTrue(bricked, "C2: advanceGame underflow-panics (permanent brick) after purchase-phase stall");

        // Permanence: it is not a one-off. The very next call reverts identically with Panic 0x11,
        // and the game-over/liveness path (which is gated AFTER the underflow site) can never run.
        vm.expectRevert(stdError.arithmeticError);
        game.advanceGame();

        vm.expectRevert(stdError.arithmeticError);
        game.advanceGame();

        // dailyIdx is frozen: currentDayView is a wall-clock view, but the game can never seal past
        // the point it wedged at (every seal path is downstream of the panic).
        assertLt(dayAfterFirst, game.currentDayView(), "wall clock advanced, but sealing is wedged");
    }
}
