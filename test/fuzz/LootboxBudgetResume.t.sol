// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title LootboxBudgetResume -- a budget-bounded sweep resumes mid-cohort and maroons nothing
/// @notice mineFlip's human-box stage charges each entry against its gas budget (the caller's
///         allowance; each entry is admitted only while the remaining allowance covers its declared
///         bound), BREAKS when the next entry would not fit, and leaves `boxCursor` on it so the next
///         call resumes at the same position. Mutation v78 rewrote both halves of that — never breaking on
///         the budget, and never stopping the walk mid-cohort (which would carry the cursor past
///         unopened entries) — and no foundry oracle noticed. Five wallets append one entry each to
///         one buffer; a two-step budget settles exactly one entry per call, the cursor alone marks
///         them settled (the stored entries never change), and completion waits for the last one.
contract LootboxBudgetResume is DeployProtocol {
    address internal actor;

    bytes32 internal constant OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("tierActor");
        vm.deal(actor, 100 ether);
    }

    function _idx() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    function _word(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev Next unsettled position of the read buffer.
    function _cursor() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR))) >> (GameSlots.BOX_CURSOR_OFFSET * 8))
            & type(uint48).max;
    }

    function _readComplete() internal view returns (bool) {
        return (uint256(vm.load(address(game), bytes32(GameSlots.HUMAN_READ_COMPLETE)))
            >> (GameSlots.HUMAN_READ_COMPLETE_OFFSET * 8)) & 0xff != 0;
    }

    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.mineFlip(0) {} catch {}
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
            try game.mineFlip(0) {} catch {}
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
            game.mineFlip(0);
        }
        assertTrue(game.rngComplete(), "harness: the day's cohorts all completed");
    }

    /// @dev Deliver and publish a word for the sealed cohort at `index`, as a fulfilled mid-day
    ///      request leaves it, on a sealed day (dailyIdx = today, tickets drained): the cohort's
    ///      human entries are then the next engine stage. `seedWord` mirrors the request's seal: the
    ///      write counts latch into the read counts and both read cursors restart.
    function _deliverCohort(uint48 index) internal {
        RecyclingState.seedWord(address(game), index, keccak256("budget-resume-word"));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(GameSlots.DAILY_IDX)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << (GameSlots.DAILY_IDX_OFFSET * 8)))
            | (uint256(game.currentDayView()) << (GameSlots.DAILY_IDX_OFFSET * 8))
            | (uint256(1) << (GameSlots.TICKETS_FULLY_PROCESSED_OFFSET * 8));
        vm.store(address(game), bytes32(GameSlots.DAILY_IDX), bytes32(slot0));
    }

    /// @dev Five wallets each append one two-small-box entry to the write buffer `N`, at
    ///      consecutive positions; returns the stored entry words.
    function _buyFive(string memory label, uint48 N, uint256 priceWei) internal returns (uint256[5] memory entries) {
        for (uint256 k; k < 5; k++) {
            address who = makeAddr(string.concat(label, vm.toString(k)));
            vm.deal(who, 10 ether);
            vm.prank(who);
            game.purchase{value: 2 * priceWei + 1 ether}(0, 400, BoxOrderLib.boOrder(2, 0, 0, 0, 0), bytes32(0), MintPaymentKind.DirectEth, false);
            assertEq(RecyclingState.boxCount(address(game), N), k + 1, "fixture: one entry per purchase");
            entries[k] = RecyclingState.boxEntry(address(game), N, k);
            assertEq(BoxOrderLib.boId(entries[k]), game.walletIdOf(who), "fixture: the entry holds the buyer's ID");
            assertEq(BoxOrderLib.boSmall(entries[k]), 2, "fixture: two small boxes");
        }
    }

    /// @dev Settlement never rewrites an entry: only the cursor moves.
    function _assertEntriesUnchanged(uint48 N, uint256[5] memory entries) internal view {
        for (uint256 k; k < 5; k++) {
            assertEq(RecyclingState.boxEntry(address(game), N, k), entries[k], "a settled entry is never rewritten");
        }
    }

    /// @dev Completion can be its own mandatory checkpoint after the last funded open.
    function _finishTailWithoutReplay(uint256 budget) internal {
        if (_readComplete()) return;
        assertEq(_cursor(), 5, "completion waits until all entries settled");
        vm.recordLogs();
        vm.prank(actor);
        game.mineFlip{gas: budget}(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0) {
                assertTrue(logs[i].topics[0] != OPENED, "completion must not replay a box");
            }
        }
        assertTrue(_readComplete(), "the next mandatory checkpoint completes the cohort");
        assertEq(_cursor(), 5, "completion leaves the settled cursor untouched");
    }

    /// @dev The smallest mineFlip allowance that settles `entries` entries (bisection over snapshots).
    function _minimalOpenAllowance(uint256 entries) internal returns (uint256) {
        uint256 before = _cursor();
        uint256 lo = 100_000;
        uint256 hi = 20_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            vm.prank(actor);
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            bool opened = ok && _cursor() >= before + entries;
            vm.revertToStateAndDelete(snap);
            if (opened) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    function test_smallBudgetOpensOneEntryPerCallAndDrainsTheIndex() public {
        _driveDailyCycleOnce();
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();
        uint256[5] memory entries = _buyFive("budgetActor", N, priceWei);

        _deliverCohort(N);
        assertGt(_word(N), 0, "the daily word landed at the index");
        assertEq(RecyclingState.boxCount(address(game), N), 5, "the seal latched five entries");
        assertEq(_cursor(), 0, "nothing settled before the walk");
        assertTrue(game.boxesPending(), "five entries wait at the index");

        // The smallest allowance that opens anything: the first entry runs, the second never fits.
        uint256 budget = _minimalOpenAllowance(1);
        emit log_named_uint("one-entry mineFlip allowance", budget);
        vm.prank(actor);
        game.mineFlip{gas: budget}(0);
        assertEq(_cursor(), 1, "one entry settled, four still owed");
        assertFalse(_readComplete(), "no early completion while entries remain");
        assertTrue(game.boxesPending(), "the walk still reports the index pending");

        // Resume until the walk reports nothing pending: every entry settles exactly once, in order.
        uint256 calls = 1;
        while (_cursor() < 5 && calls < 12) {
            vm.prank(actor);
            game.mineFlip{gas: budget}(0);
            calls++;
            assertEq(_cursor(), calls, "each call settles exactly the next entry; none is replayed");
            if (calls < 5) assertFalse(_readComplete(), "no completion while entries remain");
        }
        _finishTailWithoutReplay(budget);
        assertFalse(game.boxesPending(), "the index drains within a bounded number of calls");
        assertEq(calls, 5, "five entries, five one-entry calls");
        assertEq(_cursor(), 5, "the cursor stays at the read count after completion");
        _assertEntriesUnchanged(N, entries);
    }

    /// @notice A budget that fits one two-box entry with room to spare but not a second: midway
    ///         between the smallest one-entry and the smallest two-entry allowance, re-measured for
    ///         each call (an entry's actual cost is far below its declared bound and shrinks as the
    ///         test's storage warms, so a fixed margin over the one-entry figure can reach the second
    ///         entry's admission). The walk is still running after the first entry and only the
    ///         budget BREAK (the next entry's declared bound no longer fits) can refuse the second.
    ///         Five such calls drain the five entries; the last one has no second to refuse.
    function test_budgetThatFitsOneEntryRefusesTheSecond() public {
        _driveDailyCycleOnce();
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();
        uint256[5] memory entries = _buyFive("budgetActorB", N, priceWei);
        _deliverCohort(N);
        assertGt(_word(N), 0, "the daily word landed at the index");

        uint256 calls;
        uint256 lastBudget;
        while (_cursor() < 5 && calls < 12) {
            uint256 before = _cursor();
            uint256 one = _minimalOpenAllowance(1);
            uint256 budget = before + 1 < 5 ? one + (_minimalOpenAllowance(2) - one) / 2 : one + 30_000;
            lastBudget = budget;
            vm.prank(actor);
            game.mineFlip{gas: budget}(0);
            assertEq(_cursor() - before, 1, "one entry per call: the second never fits the budget");
            calls++;
            if (calls < 5) assertFalse(_readComplete(), "no completion while entries remain");
        }
        _finishTailWithoutReplay(lastBudget);
        assertEq(calls, 5, "five entries, five calls");
        assertEq(_cursor(), 5, "every entry settled");
        _assertEntriesUnchanged(N, entries);
    }

    /// @notice Every entry settled but completion not yet run (the cursor already stands at the read
    ///         count, as a call that settled the last entry without the tail allowance leaves it):
    ///         the next call runs only the completion. It opens no box — the last entry is not
    ///         replayed — and leaves the cursor where it was.
    function test_settledTailCompletesWithoutReplay() public {
        _driveDailyCycleOnce();
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();
        _buyFive("budgetActorC", N, priceWei);
        _deliverCohort(N);
        uint256 slot = uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR)));
        slot = (slot & ~(uint256(type(uint48).max) << (GameSlots.BOX_CURSOR_OFFSET * 8)))
            | (uint256(5) << (GameSlots.BOX_CURSOR_OFFSET * 8));
        vm.store(address(game), bytes32(GameSlots.BOX_CURSOR), bytes32(slot));
        assertFalse(_readComplete(), "fixture: settled but not complete");
        assertTrue(game.boxesPending(), "fixture: the cohort still reports pending");

        vm.recordLogs();
        vm.prank(actor);
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0) {
                assertTrue(logs[i].topics[0] != OPENED, "the completion call replays no entry");
            }
        }
        assertTrue(_readComplete(), "the tail-only call completes the cohort");
        assertEq(_cursor(), 5, "the cursor is left at the read count");
    }
}
