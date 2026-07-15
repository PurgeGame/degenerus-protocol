// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Read-only view overlay etched onto the live game to inspect internal box-queue state. A
///      DegenerusGame subclass: etching type().runtimeCode (no constructor) gives the reads access to
///      the live internal boxPlayers / lootboxEth / lootboxRngWordByIndex maps and the packed LR_INDEX
///      cursor without any storage change; the real code is restored after each read.
contract C1Viewer is DegenerusGame {
    function lrIndexView() external view returns (uint48) {
        return uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
    }

    function boxPlayersContains(uint48 index, address who) external view returns (bool) {
        address[] storage q = boxPlayers[index];
        for (uint256 i; i < q.length; ++i) {
            if (q[i] == who) return true;
        }
        return false;
    }

    /// @notice The packed lootboxEth amount sub-field (bits [0:128]) for [index][who] — the live
    ///         "box still owed" signal that the auto-open sweep gates on (openHumanBoxes skips an
    ///         entry whose lootbox amount AND presale leg are both zero) and that openLootBox zeroes
    ///         on a successful open. The decisive "opened vs not" signal: != 0 => the box is still
    ///         closed; 0 => it was opened/drained. (The post-repack lootboxEth word folds amount +
    ///         adj + score + distress; only the amount sub-field is the owed-ETH signal.)
    function lootboxBaseFor(uint48 index, address who) external view returns (uint256) {
        return lootboxEth[index][who] & LB_AMOUNT_MASK;
    }

    /// @notice lootboxRngWordByIndex[index] — the per-index VRF word the open path gates on.
    function rngWordFor(uint48 index) external view returns (uint256) {
        return lootboxRngWordByIndex[index];
    }
}

/// @title C1BoxAutoOpen — REGRESSION TEST for finding V62-01 (lootbox auto-open off-by-one).
///
/// @notice THE DEFECT (V62-01): a human lootbox is enqueued in boxPlayers[N] at LR_INDEX==N.
///         requestLootboxRng / the daily finalize advance LR_INDEX to N+1 BEFORE the word lands, and the
///         word is written to lootboxRngWordByIndex[LR_INDEX-1] == [N]. The permissionless
///         openBoxes()/_openHumanBoxes() previously read the ACTIVE LR_INDEX (= N+1) and so never opened
///         the just-finalized box at N — it degraded to manual-only openLootBox, returning open-timing
///         control to the owner. The fix points the open/boxesPending reads at LR_INDEX-1.
///
///         These tests drive the REAL contract through both word-landing paths (mid-day rawFulfill and the
///         daily finalize) and assert STRICTLY that the permissionless valve opens the finalized box.
///         If the off-by-one is reintroduced, openBoxes() opens 0 and these tests FAIL.
///
/// @dev Test-only. ZERO contracts/*.sol mutation by the test. The viewer is etched
///      (type().runtimeCode, no constructor); the real code is restored after every read.
contract C1BoxAutoOpen is DeployProtocol {
    address internal actor;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);

        actor = makeAddr("c1Actor");
        vm.deal(actor, 100 ether);
    }

    // =========================================================================
    // Viewer helpers (etch overlay; real code restored after each batch)
    // =========================================================================

    function _idx() internal returns (uint48 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lrIndexView();
        vm.etch(address(game), real);
    }

    function _base(uint48 index, address who) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lootboxBaseFor(index, who);
        vm.etch(address(game), real);
    }

    function _enqueued(uint48 index, address who) internal returns (bool v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).boxPlayersContains(index, who);
        vm.etch(address(game), real);
    }

    function _word(uint48 index) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).rngWordFor(index);
        vm.etch(address(game), real);
    }

    /// @dev Park the auto-open frontier (boxCursorIndex @ byte 13, boxCursor @ byte 7, both slot 58)
    ///      at `index` with a zero in-index cursor, so the O(1) boxesPending hint + the multi-index
    ///      sweep begin exactly at this finalized index (the realistic state where the empty lower
    ///      indices are already drained). No contract mutation — a field-isolated slot poke.
    function _parkBoxFrontier(uint48 index) internal {
        bytes32 slot = bytes32(uint256(58));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 m = (uint256(1) << 48) - 1;
        packed &= ~(m << (7 * 8));   // boxCursor = 0
        packed &= ~(m << (13 * 8));  // clear boxCursorIndex field
        packed |= (uint256(index) & m) << (13 * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    // =========================================================================
    // Drive a genesis daily cycle so rngWordByDay[currentDay] != 0 and the lock clears
    // (requestLootboxRng requires today's daily word recorded and rngLocked == false).
    // =========================================================================

    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(actor, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.advanceGame() {} catch {}
            if (game.rngLocked()) break;
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("daily", i))) | 1) {} catch {}
                }
            }
        }
        for (uint256 i; i < 10 && game.rngLocked(); i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("dailyword", i))) | 1) {} catch {}
                }
            }
            vm.prank(actor);
            try game.advanceGame() {} catch {}
        }
    }

    function _enqueueHumanBoxAtCurrentIndex() internal returns (uint48 N, uint256 base) {
        N = _idx();
        uint256 lootboxDeposit = 1.2 ether;
        vm.prank(actor);
        game.purchase{value: lootboxDeposit + 1 ether}(
            actor, 400, lootboxDeposit, bytes32(0), MintPaymentKind.DirectEth, false
        );
        base = _base(N, actor);
        assertGt(base, 0, "fixture: a human lootbox box persisted at index N (base != 0)");
        assertTrue(_enqueued(N, actor), "fixture: the human box is enqueued in boxPlayers[N]");
        assertEq(_idx(), N, "fixture: LR_INDEX is still N right after the box was enqueued");
    }

    // =========================================================================
    // V62-01 regression — MID-DAY (rawFulfillRandomWords) word-landing path.
    // The permissionless valve MUST open the just-finalized box at N (LR_INDEX-1).
    // =========================================================================

    function test_V62_01_autoOpen_opens_finalized_box_midday() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage0: not locked (mid-day path reachable)");

        (uint48 N, uint256 baseAtCreate) = _enqueueHumanBoxAtCurrentIndex();

        // requestLootboxRng fires the VRF AND advances LR_INDEX N -> N+1 before the word lands.
        vm.prank(actor);
        game.requestLootboxRng();
        assertEq(_idx(), N + 1, "requestLootboxRng advanced LR_INDEX N -> N+1 before the word lands");

        // Fulfill the mid-day VRF (not locked) => the word is written at lootboxRngWordByIndex[N].
        uint256 reqId = mockVRF.lastRequestId();
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        assertFalse(fulfilled, "the mid-day lootbox VRF request is pending");
        mockVRF.fulfillRandomWords(reqId, uint256(keccak256("c1_midday_word")) | 1);

        assertFalse(game.rngLocked(), "post-fulfill: NOT locked (mid-day branch)");
        assertGt(_word(N), 0, "the VRF word landed at lootboxRngWordByIndex[N] (box at N IS ready)");
        assertEq(_idx(), N + 1, "LR_INDEX is N+1 while the ready word sits at N");
        assertEq(_base(N, actor), baseAtCreate, "pre-open: box at N still closed");

        // The relocated sweep is a MULTI-INDEX frontier walk: boxesPending() is an O(1) hint that
        // reports the FRONTIER index (boxCursorIndex), not every higher finalized index. The genesis
        // indices below N carried no human box (their queues are empty = effectively drained), so park
        // the frontier at N — the realistic post-drain state — before the O(1) check. (The sweep would
        // advance the frontier through the empty lower indices on its first call anyway; this just
        // positions the O(1) hint to report the box that IS waiting at N.)
        _parkBoxFrontier(N);

        // boxesPending() must now SEE the finalized box (it reads LR_INDEX-1 == N at the frontier).
        assertTrue(game.boxesPending(), "boxesPending() reports the finalized box at N is openable");

        // The PERMISSIONLESS valve (not the manual openLootBox) must open the box at N.
        vm.prank(actor);
        uint256 openedAuto = game.openBoxes(50);

        emit log_named_uint("openBoxes() opened count", openedAuto);
        emit log_named_uint("lootboxEth amount[N][actor] AFTER auto-open", _base(N, actor));
        emit log_named_uint("N", N);

        assertGt(openedAuto, 0, "FIX: openBoxes() opened at least one box");
        assertEq(_base(N, actor), 0, "FIX: openBoxes() drained the finalized human box at N (auto valve works)");
        assertFalse(game.boxesPending(), "post-open: no box pending at the finalized index");
    }

    // =========================================================================
    // V62-01 regression — DAILY-FINALIZE (_finalizeLootboxRng) word-landing path.
    // Proves the fix covers the general LR_INDEX-cursor read, not only the mid-day branch.
    // =========================================================================

    function test_V62_01_autoOpen_opens_finalized_box_dailyFinalize() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage0: not locked");

        (uint48 N, uint256 baseAtCreate) = _enqueueHumanBoxAtCurrentIndex();

        // A full daily cycle: the daily request advances LR_INDEX past N; _finalizeLootboxRng
        // writes the word at LR_INDEX-1 == N.
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "post daily cycle: not locked");

        uint48 nowIdx = _idx();
        assertGt(nowIdx, N, "daily finalize advanced LR_INDEX past N");
        assertGt(_word(N), 0, "the daily-finalized word landed at lootboxRngWordByIndex[N]");
        assertEq(_base(N, actor), baseAtCreate, "pre-open: box at N still closed");

        // Permissionless valve must open the just-finalized box (LR_INDEX-1).
        vm.prank(actor);
        uint256 openedAuto = game.openBoxes(50);

        emit log_named_uint("[daily] openBoxes() opened count", openedAuto);
        emit log_named_uint("[daily] N", N);
        emit log_named_uint("[daily] LR_INDEX at open time", nowIdx);
        emit log_named_uint("[daily] base[N] after auto", _base(N, actor));

        assertGt(openedAuto, 0, "FIX(daily): openBoxes() opened at least one box");
        assertEq(_base(N, actor), 0, "FIX(daily): openBoxes() drained the finalized human box at N");
    }
}
