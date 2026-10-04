// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Read-only view overlay etched onto the live game to inspect internal box-queue state. A
///      DegenerusGame subclass: etching type().runtimeCode (no constructor) gives the reads access to
///      the live internal boxPlayers / retained orders / current word and the packed LR_INDEX
///      cursor without any storage change; the real code is restored after each read.
contract C1Viewer is DegenerusGame {
    function lrIndexView() external view returns (uint48) {
        return _rngWriteBuffer();
    }

    function boxPlayersContains(uint48 index, address who) external view returns (bool) {
        address[] storage q = boxPlayers[index & 1];
        for (uint256 i; i < q.length; ++i) {
            if (q[i] == who) return true;
        }
        return false;
    }

    /// @notice The raw packed lootboxOrder word for [index][who] — the live "box still owed" signal
    ///         that mineFlip's human-box stage gates on (it skips an entry whose box order AND
    ///         presale leg are both zero) and marks processed on a successful open. The decisive "opened vs not" signal: != 0 => the box is still
    ///         closed; 0 => it was opened/drained.
    function lootboxBaseFor(uint48 index, address who) external view returns (uint256) {
        return _boxOrder(index, who);
    }

    /// @notice _lootboxWord(index) — the per-index VRF word the open path gates on.
    function rngWordFor(uint48 index) external view returns (uint256) {
        return _lootboxWord(index);
    }
}

/// @title C1BoxAutoOpen — REGRESSION TEST for finding V62-01 (lootbox auto-open off-by-one).
///
/// @notice THE DEFECT CLASS (V62-01): a human lootbox is enqueued in boxPlayers[N & 1] while N is the
///         write buffer. The mid-day request (mineFlip's RequestMidday stage) or the daily request seals
///         N — the write side flips to N ^ 1 — BEFORE the word lands, and the word is published for the
///         read buffer N. The human-box stage and the boxesPending hint must read buffer N, not the
///         active write side; reading the write side would never open the just-finalized box.
///
///         These tests drive the REAL contract through both word-landing paths (mid-day and the daily
///         finalize) and assert STRICTLY that mineFlip's human-box stage opens the finalized box. If the
///         off-by-one is reintroduced, the box stays closed and these tests FAIL.
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

    // =========================================================================
    // Drive a genesis daily cycle so _recordedDailyWord(currentDay) != 0 and the lock clears
    // (a mid-day request requires today's daily word recorded and rngLocked == false).
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
            try game.mineFlip() {} catch {}
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
            try game.mineFlip() {} catch {}
        }
    }

    /// @dev Answer and drain the mid-day work the state engine requests on its own once a day
    ///      is sealed (a closed Craps window rides a mid-day request whenever the subscription
    ///      covers it, 6d0e64b09), until the engine is idle with nothing in flight.
    function _settleMidday() internal {
        for (uint256 i; i < 64; i++) {
            if (game.rngLocked()) return;
            uint8 action = game.nextMinerAction();
            if (action == 0 || action == 17) return; // Idle, or the next day's RequestDaily
            if (action == 2) {
                uint256 id = mockVRF.lastRequestId();
                (, , bool done) = mockVRF.pendingRequests(id);
                if (done) return;
                mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("c1_midday", id))) | 2);
            } else {
                vm.prank(actor);
                game.mineFlip();
            }
        }
        fail("harness: mid-day work did not settle");
    }

    function _enqueueHumanBoxAtCurrentIndex() internal returns (uint48 N, uint256 base) {
        N = _idx();
        uint256 lootboxDeposit = 1.2 ether;
        vm.prank(actor);
        game.purchase{value: lootboxDeposit + 1 ether}(
            actor, 400, BoxOrderLib.boCustom(lootboxDeposit), bytes32(0), MintPaymentKind.DirectEth, false
        );
        base = _base(N, actor);
        assertGt(base, 0, "fixture: a human lootbox box persisted at index N (base != 0)");
        assertTrue(_enqueued(N, actor), "fixture: the human box is enqueued in boxPlayers[N & 1]");
        assertEq(_idx(), N, "fixture: LR_INDEX is still N right after the box was enqueued");
    }

    // =========================================================================
    // V62-01 regression — MID-DAY (rawFulfillRandomWords) word-landing path.
    // mineFlip's human-box stage MUST open the just-finalized box at read buffer N.
    // =========================================================================

    function test_V62_01_autoOpen_opens_finalized_box_midday() public {
        _driveDailyCycleOnce();
        _settleMidday();
        _finishReadConsumers();
        assertFalse(game.rngLocked(), "stage0: not locked (mid-day path reachable)");

        (uint48 N, uint256 baseAtCreate) = _enqueueHumanBoxAtCurrentIndex();

        // The box's pending ETH clears the mid-day threshold: the engine's mid-day request fires the
        // VRF AND seals buffer N (the write side flips to N ^ 1) before the word lands.
        assertEq(game.nextMinerAction(), 18, "the mid-day request is the engine's next work"); // RequestMidday
        vm.prank(actor);
        game.mineFlip();
        assertEq(_idx(), N ^ 1, "the mid-day request sealed buffer N before the word lands");

        // Fulfill the mid-day VRF (not locked) => the word is written at _lootboxWord(N).
        uint256 reqId = mockVRF.lastRequestId();
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        assertFalse(fulfilled, "the mid-day lootbox VRF request is pending");
        mockVRF.fulfillRandomWords(reqId, uint256(keccak256("c1_midday_word")) | 1);

        assertFalse(game.rngLocked(), "post-fulfill: NOT locked (mid-day branch)");
        // Required keeper publication after the minimal callback, then the cohort's tickets:
        // the consumer order puts human boxes after ticket materialization (60d31f775). A 1.1M
        // allowance can never admit a human-box entry (HUMAN_ENTRY_GAS + tail), so these calls
        // stop with the box still closed, leaving its open to the human-box stage below.
        for (uint256 i; i < 20 && game.nextMinerAction() != 10; i++) game.mineFlip{gas: 1_100_000}();
        assertEq(game.nextMinerAction(), 10, "the human-box stage is next");
        assertGt(_word(N), 0, "the VRF word landed at _lootboxWord(N) (box at N IS ready)");
        assertEq(_idx(), N ^ 1, "LR_INDEX is N+1 while the ready word sits at N");
        assertEq(_base(N, actor), baseAtCreate, "pre-open: box at N still closed");

        // boxesPending() must now SEE the finalized box (it reads the read buffer N).
        assertTrue(game.boxesPending(), "boxesPending() reports the finalized box at N is openable");

        // The engine's human-box stage must open the box at N.
        vm.prank(actor);
        game.mineFlip();

        emit log_named_uint("lootboxOrder word[N][actor] AFTER the human-box stage", _base(N, actor));
        emit log_named_uint("N", N);

        assertEq(_base(N, actor), 0, "FIX: the human-box stage drained the finalized human box at N");
        // Consumer order (60d31f775): the cohort's tickets materialized BEFORE its boxes, so after
        // the open the human read of buffer N is complete rather than held open by tickets.
        assertTrue(game.boxIndexComplete(N), "the read cohort's human queue completed with its box open");
    }

    // =========================================================================
    // V62-01 regression — DAILY-FINALIZE (_finalizeLootboxRng) word-landing path.
    // Proves the fix covers the general LR_INDEX-cursor read, not only the mid-day branch.
    // =========================================================================

    function test_V62_01_autoOpen_opens_finalized_box_dailyFinalize() public {
        _driveDailyCycleOnce();
        _settleMidday();
        assertFalse(game.rngLocked(), "stage0: not locked");

        (uint48 N, uint256 baseAtCreate) = _enqueueHumanBoxAtCurrentIndex();

        // The daily request seals buffer N (the write side flips to N ^ 1) before its word lands.
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            game.mineFlip();
        }
        assertTrue(game.rngLocked(), "the daily request is in flight");
        uint48 nowIdx = _idx();
        assertEq(nowIdx, N ^ 1, "daily seal switches to the other write buffer");
        assertEq(_word(N), 0, "no word at N before the daily word lands");
        assertEq(_base(N, actor), baseAtCreate, "pre-open: box at N still closed");

        // The daily word finalizes buffer N, and the permissionless keeper's human-box stage
        // opens the box at N (the read buffer) before any later request can retire it. The
        // V62-01 off-by-one (opening the write side) would leave it closed. An open marks the raw
        // order word BOX_PROCESSED (bit 255; 6d0e64b09) and the logical view reads it as 0.
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, uint256(keccak256("c1_daily_word")) | 2);
        vm.recordLogs();
        for (uint256 i; i < 20 && game.rngLocked(); i++) {
            vm.prank(actor);
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "post daily cycle: not locked");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool landed;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0
                && logs[i].topics[0] == keccak256("LootboxRngApplied(uint48,uint256,uint256)")) {
                (uint48 index, uint256 word,) = abi.decode(logs[i].data, (uint48, uint256, uint256));
                if (index == N && word != 0) landed = true;
            }
        }
        assertTrue(landed, "the daily-finalized word landed at _lootboxWord(N)");

        // Mining on finds nothing left to open at N and stops without an unexpected revert.
        vm.startPrank(actor);
        _mineAll(16);
        vm.stopPrank();

        uint256 raw = uint256(vm.load(address(game),
            keccak256(abi.encode(actor, keccak256(abi.encode(uint256(N & 1), uint256(15)))))));
        emit log_named_uint("[daily] N", N);
        emit log_named_uint("[daily] LR_INDEX at request time", nowIdx);
        emit log_named_uint("[daily] base[N] after auto", _base(N, actor));

        assertTrue(raw >> 255 == 1, "FIX(daily): the permissionless keeper opened the finalized human box at N");
        assertEq(_base(N, actor), 0, "FIX(daily): the human-box stage drained the finalized human box at N");
    }
}
