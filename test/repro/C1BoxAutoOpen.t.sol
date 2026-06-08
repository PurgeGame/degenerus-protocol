// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Read-only view overlay etched onto the live game to inspect internal box-queue state. A
///      DegenerusGame subclass: etching type().runtimeCode (no constructor) gives the reads access to
///      the live internal boxPlayers / lootboxEth / lootboxEthBase / lootboxRngWordByIndex maps and the
///      packed LR_INDEX cursor without any storage change; the real code is restored after each read.
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

    /// @notice The persisted lootbox amount (the [232:amount] field). != 0 => persisted, not yet opened.
    function lootboxAmountFor(uint48 index, address who) external view returns (uint256) {
        return lootboxEth[index][who] & ((1 << 232) - 1);
    }

    /// @notice lootboxEthBase[index][who] — the EXACT slot the auto-open skip-gate reads
    ///         (_openHumanBoxes:1912) and that openLootBox zeroes on a successful open. The decisive
    ///         "opened vs not" signal: != 0 => the box is still closed; 0 => it was opened/drained.
    function lootboxBaseFor(uint48 index, address who) external view returns (uint256) {
        return lootboxEthBase[index][who];
    }

    /// @notice lootboxRngWordByIndex[index] — the per-index VRF word the open path gates on.
    function rngWordFor(uint48 index) external view returns (uint256) {
        return lootboxRngWordByIndex[index];
    }
}

/// @title C1BoxAutoOpen — empirical reproduction of council finding C1.
///
/// @notice THE CLAIM (C1): a human/presale lootbox is enqueued in boxPlayers[N] at LR_INDEX==N.
///         requestLootboxRng advances LR_INDEX to N+1 BEFORE the VRF word lands; rawFulfillRandomWords
///         (mid-day branch) writes the word to lootboxRngWordByIndex[LR_INDEX-1] == [N]. But the
///         permissionless openBoxes()/_openHumanBoxes() reads index = LR_INDEX = N+1 and gates on
///         lootboxRngWordByIndex[N+1] == 0, so it returns 0 and NEVER opens the box at N. The box is
///         only openable via the manual openLootBox(owner, N). The afking-cover leg keys off
///         rngWordByDay[stampDay] (not the index cursor) and is claimed to STILL WORK — the CONTROL.
///
///         This test drives the REAL contract through the mid-day lootbox-RNG lifecycle and reads the
///         hard outcome via an etched read-only viewer. It is purely empirical: whatever openBoxes()
///         actually does to lootboxEthBase[N][actor] decides CONFIRMED vs REFUTED.
///
/// @dev Test-only. ZERO contracts/*.sol mutation. The viewer is etched (type().runtimeCode, no
///      constructor); the real code is restored after every read.
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

    function _amount(uint48 index, address who) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lootboxAmountFor(index, who);
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
    // Drive a genesis daily cycle so rngWordByDay[currentDay] != 0 and the lock clears
    // (requestLootboxRng requires today's daily word to be recorded and rngLocked == false).
    // =========================================================================

    function _driveDailyCycleOnce() internal {
        // Small daily-gate buy so advanceGame has a reason to request the daily word.
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(actor, 400, 0, bytes32(0), MintPaymentKind.DirectEth) {} catch {}
        }
        // Cross day boundaries + advance until a daily request latches the lock, then fulfill it and
        // advance until the lock clears (the daily word gets recorded into rngWordByDay).
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.advanceGame() {} catch {}
            if (game.rngLocked()) break;
            // Clear any intermediate (mid-day lootbox) request so progression continues.
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("daily", i))) | 1) {} catch {}
                }
            }
        }
        // Fulfill the daily request and advance until the day processes (lock clears, word recorded).
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

    // =========================================================================
    // THE REPRODUCTION: mid-day lootbox-RNG human box vs the permissionless openBoxes() valve
    // =========================================================================

    function test_C1_humanBox_autoOpen_vs_manual() public {
        // --- Stage 0: get the game into a steady mid-day-capable state (daily word recorded). ---
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage0: not locked after a daily cycle (mid-day path reachable)");

        // --- Stage 1: create a HUMAN lootbox-bearing purchase. ---
        // A mint-with-lootbox purchase deposits a lootbox via MintModule, which enqueues into
        // boxPlayers[LR_INDEX]. Record the index N the box enqueues at. The lootbox deposit is sized
        // ABOVE the 1-ETH lootboxRngThreshold so the mid-day requestLootboxRng pending-ETH gate clears
        // through the REAL entrypoint (no threshold vm.store needed).
        uint48 N = _idx();
        uint256 lootboxDeposit = 1.2 ether;
        vm.prank(actor);
        game.purchase{value: lootboxDeposit + 1 ether}(
            actor,
            400, // one whole ticket
            lootboxDeposit,
            bytes32(0),
            MintPaymentKind.DirectEth
        );

        uint256 baseAtCreate = _base(N, actor);
        assertGt(baseAtCreate, 0, "fixture: a human lootbox box persisted at index N (base != 0)");
        assertTrue(_enqueued(N, actor), "fixture: the human box is enqueued in boxPlayers[N]");
        assertEq(_idx(), N, "fixture: LR_INDEX is still N right after the box was enqueued");

        // --- Stage 2: drive the REAL mid-day lootbox RNG lifecycle so the word for N lands. ---
        // requestLootboxRng fires the VRF AND advances LR_INDEX N -> N+1. It requires today's daily
        // word recorded, not locked, no in-flight request, and pending lootbox ETH above threshold
        // (the whale-bundle lootbox deposit supplies the pending ETH).
        vm.prank(actor);
        game.requestLootboxRng();

        uint48 afterRequest = _idx();
        assertEq(afterRequest, N + 1, "C1 step: requestLootboxRng advanced LR_INDEX N -> N+1 BEFORE the word lands");

        // Fulfill the mid-day VRF. NOT locked => rawFulfillRandomWords writes the word to
        // lootboxRngWordByIndex[LR_INDEX-1] == [N]. The lock stays clear (mid-day branch).
        uint256 reqId = mockVRF.lastRequestId();
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        assertFalse(fulfilled, "the mid-day lootbox VRF request is pending");
        mockVRF.fulfillRandomWords(reqId, uint256(keccak256("c1_midday_word")) | 1);

        assertFalse(game.rngLocked(), "post-fulfill: NOT locked (mid-day branch directly finalized)");
        assertGt(_word(N), 0, "the VRF word landed at lootboxRngWordByIndex[N] (box at N IS ready to open)");
        assertEq(_word(N + 1), 0, "no word at lootboxRngWordByIndex[N+1] (the index openBoxes will read)");
        assertEq(_idx(), N + 1, "LR_INDEX is N+1 while the ready word sits at N");

        // The box at N is genuinely ready & owed: base still non-zero, still enqueued, word present.
        assertEq(_base(N, actor), baseAtCreate, "pre-open: box at N still closed (base unchanged)");
        assertTrue(_enqueued(N, actor), "pre-open: box at N still enqueued for the auto valve");

        // --- Stage 3: call the PERMISSIONLESS auto valve (NOT the manual openLootBox). ---
        // _openHumanBoxes reads index = LR_INDEX = N+1, gates on lootboxRngWordByIndex[N+1] == 0.
        vm.prank(actor);
        uint256 openedAuto = game.openBoxes(50);

        uint256 baseAfterAuto = _base(N, actor);
        emit log_named_uint("openBoxes() opened count", openedAuto);
        emit log_named_uint("lootboxEthBase[N][actor] BEFORE auto-open", baseAtCreate);
        emit log_named_uint("lootboxEthBase[N][actor] AFTER  auto-open", baseAfterAuto);
        emit log_named_uint("N", N);
        emit log_named_uint("LR_INDEX at open time", _idx());

        bool autoOpenedTheBox = (baseAfterAuto == 0);

        // --- Stage 3b: the box at N is not merely "not-ready-yet" — it is STRUCTURALLY abandoned.
        // Run another full daily cycle (LR_INDEX moves further past N; the cursor resets to the new
        // index) and call the auto valve again: the box at N is never re-entered by the walk. ---
        if (!autoOpenedTheBox) {
            _driveDailyCycleOnce();
            vm.prank(actor);
            uint256 openedAgain = game.openBoxes(50);
            uint256 baseAfterSecond = _base(N, actor);
            emit log_named_uint("second openBoxes() opened count (after LR_INDEX moved further)", openedAgain);
            emit log_named_uint("lootboxEthBase[N][actor] AFTER second auto-open attempt", baseAfterSecond);
            emit log_named_uint("LR_INDEX after another daily cycle", _idx());
            assertEq(
                baseAfterSecond,
                baseAtCreate,
                "CONFIRMED: the box at N stays closed across further index advances (structurally abandoned, not just not-ready)"
            );
        }

        // --- Stage 4: CONTROL — the manual openLootBox(actor, N) MUST open the same box. ---
        // Proves the box is openable (word present, base present); the defect (if any) is specifically
        // the auto valve's index, not an un-fulfilled word.
        bool manualOpenedTheBox;
        if (!autoOpenedTheBox) {
            vm.prank(actor);
            game.openLootBox(actor, N);
            manualOpenedTheBox = (_base(N, actor) == 0);
            emit log_named_uint("lootboxEthBase[N][actor] AFTER manual openLootBox(N)", _base(N, actor));
        }

        // ---------------------------------------------------------------------
        // VERDICT
        // ---------------------------------------------------------------------
        if (autoOpenedTheBox) {
            // The permissionless valve drained the box at N. C1 is REFUTED.
            assertGt(openedAuto, 0, "REFUTED: openBoxes reported opening at least one box");
            assertEq(baseAfterAuto, 0, "REFUTED: openBoxes() DID open the human box at N (auto valve works)");
        } else {
            // The permissionless valve left the box at N closed. The control proves it WAS openable.
            assertEq(
                baseAfterAuto,
                baseAtCreate,
                "CONFIRMED: openBoxes() did NOT open the human box at N (base unchanged by the auto valve)"
            );
            assertTrue(
                manualOpenedTheBox,
                "CONTROL: manual openLootBox(actor, N) DID open the same box (so it was ready & owed; the auto valve is the defect)"
            );
        }
    }

    // =========================================================================
    // SECOND VARIANT: the DAILY-FINALIZE word-landing path (not the mid-day branch).
    // Proves C1 is the general LR_INDEX-cursor off-by-one, not specific to
    // rawFulfillRandomWords's mid-day branch. A human box is enqueued at N, then a full DAILY
    // advance cycle runs: the daily request advances LR_INDEX (N -> N+1) and _finalizeLootboxRng
    // writes the word at LR_INDEX-1 == N. openBoxes() then reads LR_INDEX == N+1 and misses N.
    // =========================================================================

    function test_C1_humanBox_dailyFinalizePath() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage0: not locked");

        // Enqueue a human box at index N (mint-with-lootbox).
        uint48 N = _idx();
        uint256 lootboxDeposit = 1.2 ether;
        vm.prank(actor);
        game.purchase{value: lootboxDeposit + 1 ether}(
            actor, 400, lootboxDeposit, bytes32(0), MintPaymentKind.DirectEth
        );
        uint256 baseAtCreate = _base(N, actor);
        assertGt(baseAtCreate, 0, "fixture: human box persisted at N");
        assertTrue(_enqueued(N, actor), "fixture: box enqueued in boxPlayers[N]");
        assertEq(_idx(), N, "fixture: LR_INDEX still N at enqueue");

        // Run a full DAILY cycle: a daily VRF request (advances LR_INDEX, latches the lock), fulfill
        // it, advance until processed (the lock clears; the day word + lootbox word are finalized).
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "post daily cycle: not locked");

        // The daily finalize advanced LR_INDEX past N and wrote the word at the prior index.
        uint48 nowIdx = _idx();
        assertGt(nowIdx, N, "daily finalize advanced LR_INDEX past N");
        assertGt(_word(N), 0, "the daily-finalized word landed at lootboxRngWordByIndex[N] (box at N IS ready)");
        assertEq(_base(N, actor), baseAtCreate, "pre-open: box at N still closed");

        // Permissionless auto valve: reads the LIVE LR_INDEX, not N.
        vm.prank(actor);
        uint256 openedAuto = game.openBoxes(50);
        uint256 baseAfterAuto = _base(N, actor);

        emit log_named_uint("[daily] openBoxes() opened count", openedAuto);
        emit log_named_uint("[daily] N", N);
        emit log_named_uint("[daily] LR_INDEX at open time", nowIdx);
        emit log_named_uint("[daily] base[N] before auto", baseAtCreate);
        emit log_named_uint("[daily] base[N] after  auto", baseAfterAuto);

        bool autoOpened = (baseAfterAuto == 0);
        if (autoOpened) {
            assertEq(baseAfterAuto, 0, "REFUTED(daily): openBoxes opened the box at N");
        } else {
            // Control: the box is openable via the explicit-index manual path.
            vm.prank(actor);
            game.openLootBox(actor, N);
            assertEq(
                _base(N, actor),
                0,
                "CONTROL(daily): manual openLootBox(actor, N) opened the box (ready & owed; auto valve is the defect)"
            );
            assertEq(
                baseAfterAuto,
                baseAtCreate,
                "CONFIRMED(daily): openBoxes() did NOT open the human box at N via the auto valve"
            );
        }
    }
}
