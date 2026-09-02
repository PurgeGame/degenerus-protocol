// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {C1Viewer} from "../repro/C1BoxAutoOpen.t.sol";

/// @title LootboxBudgetResume -- a budget-bounded sweep resumes mid-index and maroons nothing
/// @notice The permissionless open walk charges each entry against a step budget, BREAKS when
///         the next entry would not fit, and leaves the cursor on it so the next call resumes at
///         the same index. Mutation v78 rewrote both halves of that — never breaking on the
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

    /// @dev Point the permissionless open walk at `index` (cursor 0), as the auto-open repro does.
    function _parkBoxFrontier(uint48 index) internal {
        bytes32 slot = bytes32(uint256(56));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 m = (uint256(1) << 48) - 1;
        packed &= ~(m << (7 * 8));
        packed &= ~(m << (13 * 8));
        packed |= (uint256(index) & m) << (13 * 8);
        vm.store(address(game), slot, bytes32(packed));
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

        _driveDailyCycleOnce();
        assertGt(_word(N), 0, "the daily word landed at the index");
        _parkBoxFrontier(N);
        assertTrue(game.boxesPending(), "five entries wait at the index");

        // A two-step budget: one step for the index header, then the first entry of a call always runs and the second never fits.
        vm.prank(actor);
        uint256 first = game.openBoxes(2);
        assertGt(first, 0, "a two-step budget opens something");
        uint256 drained;
        for (uint256 k; k < 5; k++) if (_base(N, who[k]) == 0) drained++;
        assertEq(drained, 1, "one order drained, four still owed");
        assertTrue(game.boxesPending(), "the walk still reports the index pending");

        // Resume until the walk reports nothing pending: every order must be gone.
        uint256 calls = 1;
        while (game.boxesPending() && calls < 12) {
            vm.prank(actor);
            game.openBoxes(2);
            calls++;
        }
        assertFalse(game.boxesPending(), "the index drains within a bounded number of calls");
        for (uint256 k; k < 5; k++) {
            assertEq(_base(N, who[k]), 0, "no order is marooned behind a budget break");
        }
        assertEq(calls, 5, "five entries, five two-step calls");
    }

    /// @notice A budget that fits one two-box entry with room to spare but not a second. `openBoxes`
    ///         hands the human walk `(maxCount - afkingSteps) * OPEN_HUMAN_ENTRY_WEIGHT` steps; with a
    ///         count of three that is 30 or 45. The index header costs one step and a two-box entry
    ///         `15 + 2 * 6 = 27`, so the inner loop is still running after the first entry and only
    ///         the budget BREAK can refuse the second. Five such calls drain the five entries.
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
        _driveDailyCycleOnce();
        assertGt(_word(N), 0, "the daily word landed at the index");
        _parkBoxFrontier(N);

        uint256 calls;
        while (game.boxesPending() && calls < 12) {
            uint256 before;
            for (uint256 k; k < 5; k++) if (_base(N, who[k]) == 0) before++;
            vm.prank(actor);
            game.openBoxes(3);
            uint256 after_;
            for (uint256 k; k < 5; k++) if (_base(N, who[k]) == 0) after_++;
            assertEq(after_ - before, 1, "one entry per call: the second never fits the budget");
            calls++;
        }
        assertEq(calls, 5, "five entries, five calls");
        for (uint256 k; k < 5; k++) assertEq(_base(N, who[k]), 0, "every order drained");
    }
}
