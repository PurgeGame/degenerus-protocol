// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {C1Viewer} from "../repro/C1BoxAutoOpen.t.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title LootboxBudgetResume -- a budget-bounded sweep resumes mid-index and maroons nothing
/// @notice The permissionless open walk charges each entry against its gas budget (the caller's
///         allowance; each entry is admitted only while the remaining allowance covers its declared
///         bound), BREAKS when the next entry would not fit, and leaves the cursor on it so the next
///         call resumes at the same index. Mutation v78 rewrote both halves of that — never breaking on the
///         budget, and never stopping the outer walk mid-index (which would carry the cursor to
///         the next index past unopened entries) — and no foundry oracle noticed. Five wallets
///         enqueue at one index; a two-step budget opens exactly one entry per call, and every
///         order is drained by the time the walk reports nothing pending.
contract LootboxBudgetResume is DeployProtocol {
    address internal actor;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("tierActor");
        vm.deal(actor, 100 ether);
    }

    function _idx() internal returns (uint48 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lrIndexView();
        vm.etch(address(game), real);
    }

    function _word(uint48 index) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).rngWordFor(index);
        vm.etch(address(game), real);
    }

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
        // A fresh request waits for every read consumer of the day's cohort to finish. A shut
        // craps window the day bound to the write buffer rides the next request, which the engine
        // makes as mid-day work; answer and drain it too, until the engine is idle.
        for (uint256 i; i < 20; i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("trailing", i))) | 1);
            }
            _finishReadConsumers();
            if (!game.advanceDue() && game.rngComplete()) break;
            if (!game.advanceDue()) continue; // a fresh request waits for its word
            vm.prank(actor);
            game.mineFlip();
        }
        assertTrue(game.rngComplete(), "harness: the day's cohorts all completed");
    }

    /// @dev Deliver and publish a word for the sealed cohort at `index`, as a fulfilled mid-day
    ///      request leaves it, on a sealed day (dailyIdx = today, tickets drained): the cohort's
    ///      human orders are then the next engine stage. Mirrors the request's seal: cursors restart
    ///      and the new write tag's queues are empty.
    function _deliverCohort(uint48 index) internal {
        RecyclingState.seedWord(address(game), index, keccak256("budget-resume-word"));
        uint256 s14 = uint256(vm.load(address(game), bytes32(uint256(14))));
        vm.store(address(game), bytes32(uint256(14)), bytes32(s14 & ~(uint256(type(uint48).max) << 160)));
        uint256 s56 = uint256(vm.load(address(game), bytes32(uint256(56))));
        vm.store(address(game), bytes32(uint256(56)), bytes32(s56 & ~(uint256(type(uint48).max) << 56)));
        vm.store(address(game), keccak256(abi.encode(uint256((index ^ 1) & 1), uint256(21))), bytes32(0));
        vm.store(address(game), keccak256(abi.encode(uint256((index ^ 1) & 1), uint256(57))), bytes32(0));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    function _drainedCount(uint48 index, address[5] memory who) internal returns (uint256 n) {
        for (uint256 k; k < 5; k++) if (_base(index, who[k]) == 0) n++;
    }

    /// @dev The smallest openBoxes allowance that opens any entry (bisection over snapshots).
    function _minimalOpenAllowance(uint48 index, address[5] memory who) internal returns (uint256) {
        uint256 before = _drainedCount(index, who);
        uint256 lo = 100_000;
        uint256 hi = 20_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            vm.prank(actor);
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("openBoxes(uint256)", uint256(2)));
            bool opened = ok && _drainedCount(index, who) > before;
            vm.revertToStateAndDelete(snap);
            if (opened) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    function _base(uint48 index, address who) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lootboxBaseFor(index, who);
        vm.etch(address(game), real);
    }

    function test_smallBudgetOpensOneEntryPerCallAndDrainsTheIndex() public {
        _driveDailyCycleOnce();
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();
        address[5] memory who;
        for (uint256 k; k < 5; k++) {
            who[k] = makeAddr(string.concat("budgetActor", vm.toString(k)));
            vm.deal(who[k], 10 ether);
            vm.prank(who[k]);
            game.purchase{value: 2 * priceWei + 1 ether}(who[k], 400, BoxOrderLib.boOrder(2, 0, 0, 0, 0), bytes32(0), MintPaymentKind.DirectEth, false);
            assertGt(_base(N, who[k]), 0, "fixture: the order persisted");
        }

        _deliverCohort(N);
        assertGt(_word(N), 0, "the daily word landed at the index");
        assertTrue(game.boxesPending(), "five entries wait at the index");

        // The smallest allowance that opens anything: the first entry runs, the second never fits.
        uint256 budget = _minimalOpenAllowance(N, who);
        emit log_named_uint("one-entry openBoxes allowance", budget);
        vm.prank(actor);
        uint256 first = game.openBoxes{gas: budget}(2);
        assertGt(first, 0, "a one-entry budget opens something");
        uint256 drained;
        for (uint256 k; k < 5; k++) if (_base(N, who[k]) == 0) drained++;
        assertEq(drained, 1, "one order drained, four still owed");
        assertTrue(game.boxesPending(), "the walk still reports the index pending");

        // Resume until the walk reports nothing pending: every order must be gone.
        uint256 calls = 1;
        while (game.boxesPending() && calls < 12) {
            vm.prank(actor);
            game.openBoxes{gas: budget}(2);
            calls++;
        }
        assertFalse(game.boxesPending(), "the index drains within a bounded number of calls");
        for (uint256 k; k < 5; k++) {
            assertEq(_base(N, who[k]), 0, "no order is marooned behind a budget break");
        }
        assertEq(calls, 5, "five entries, five one-entry calls");
    }

    /// @notice A budget that fits one two-box entry with room to spare but not a second: the
    ///         smallest one-entry allowance plus 30k gas. The inner loop is still running after the
    ///         first entry and only the budget BREAK (the next entry's declared bound no longer fits)
    ///         can refuse the second. Five such calls drain the five entries.
    function test_budgetThatFitsOneEntryRefusesTheSecond() public {
        _driveDailyCycleOnce();
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();
        address[5] memory who;
        for (uint256 k; k < 5; k++) {
            who[k] = makeAddr(string.concat("budgetActorB", vm.toString(k)));
            vm.deal(who[k], 10 ether);
            vm.prank(who[k]);
            game.purchase{value: 2 * priceWei + 1 ether}(who[k], 400, BoxOrderLib.boOrder(2, 0, 0, 0, 0), bytes32(0), MintPaymentKind.DirectEth, false);
        }
        _deliverCohort(N);
        assertGt(_word(N), 0, "the daily word landed at the index");
        uint256 budget = _minimalOpenAllowance(N, who) + 30_000;

        uint256 calls;
        while (game.boxesPending() && calls < 12) {
            uint256 before;
            for (uint256 k; k < 5; k++) if (_base(N, who[k]) == 0) before++;
            vm.prank(actor);
            game.openBoxes{gas: budget}(3);
            uint256 after_;
            for (uint256 k; k < 5; k++) if (_base(N, who[k]) == 0) after_++;
            assertEq(after_ - before, 1, "one entry per call: the second never fits the budget");
            calls++;
        }
        assertEq(calls, 5, "five entries, five calls");
        for (uint256 k; k < 5; k++) assertEq(_base(N, who[k]), 0, "every order drained");
    }
}
