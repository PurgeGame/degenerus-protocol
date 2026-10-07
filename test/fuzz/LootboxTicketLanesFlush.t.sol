// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title LootboxTicketLanesFlush -- every box's announced future level receives exactly its entries
/// @notice A box open announces each box's target level and whole-ticket roll in `LootBoxOpened`
///         and accumulates the tickets per level offset; the entry's flush then walks the
///         populated offsets with a six-step lowest-set-bit search and queues each level once.
///         Mutation v78 broke one step of that walk (`scan & 0xF` to `scan * 0xF`) and survived:
///         nothing had checked that the queued levels are the announced ones. Twenty boxes spread
///         over the target band pin the walk lane by lane.
contract LootboxTicketLanesFlush is DeployProtocol {
    address internal actor;

    bytes32 internal constant OPENED =
        keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 internal constant QUEUED = keccak256("EntriesQueued(uint32,uint24,uint32)");
    /// @dev Event-tag bit of a queued entry: QUEUED_ENTRY_TAG | position << 1 | buffer.
    uint48 internal constant QUEUED_ENTRY_TAG = uint48(1) << 46;

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

    /// @dev The mid-day request, issued by `caller`'s mineFlip as the engine's next action (the
    ///      only door to a mid-day word). Returns the fresh request's ID.
    function _mineMiddayRequest(address caller) internal returns (uint256 reqId) {
        uint256 prior = mockVRF.lastRequestId();
        vm.prank(caller);
        game.mineFlip();
        reqId = mockVRF.lastRequestId();
        assertGt(reqId, prior, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "a mid-day request, not the daily one");
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

    /// @dev Tally one open's announcements (tagged with the entry's `ref`) and the actor's queue
    ///      writes (keyed by wallet ID) per level offset from `base`.
    function _tally(Vm.Log[] memory logs, uint48 ref, uint256 base)
        internal
        returns (uint256[64] memory announced, uint256[64] memory queued, uint256 boxes)
    {
        uint32 actorId = game.walletIdOf(actor);
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] == OPENED && uint32(uint256(logs[i].topics[1])) == game.walletIdOf(actor)
                && uint48(uint256(logs[i].topics[2])) == ref) {
                (, uint24 lvl, uint32 scaled,, bool up) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                uint256 whole = scaled / 100 + (up ? 1 : 0);
                assertGe(lvl, base, "a box targets the live level or later");
                assertLt(lvl - base, 64, "and within the band");
                announced[lvl - base] += whole * 4;
                boxes++;
            } else if (logs[i].topics[0] == QUEUED && uint32(uint256(logs[i].topics[1])) == actorId) {
                (uint24 lvl, uint32 entries) = abi.decode(logs[i].data, (uint24, uint32));
                assertGe(lvl, base, "queued at the live level or later");
                assertLt(lvl - base, 64, "and within the band");
                assertEq(queued[lvl - base], 0, "each level is queued exactly once per entry");
                queued[lvl - base] += entries;
            }
        }
    }

    /// @dev The lane shape the six-step walk is most easily wrong about: a populated offset in
    ///      the high nibble of a byte whose low nibble is empty (the `& 0xF` step must fire).
    function _hasIsolatedHighNibbleLane(uint256[64] memory announced) internal pure returns (bool) {
        for (uint256 k = 4; k < 64; k++) {
            if (announced[k] == 0 || (k & 7) < 4) continue;
            uint256 b = k & ~uint256(7);
            if (announced[b] == 0 && announced[b + 1] == 0 && announced[b + 2] == 0 && announced[b + 3] == 0) return true;
        }
        return false;
    }

    function test_flushQueuesEachAnnouncedLevelExactlyOnce() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();
        uint256 position = RecyclingState.boxCount(address(game), N);
        uint48 ref = QUEUED_ENTRY_TAG | (uint48(position) << 1) | N;
        // Thirty smalls spread over the target band, plus a one-ETH custom so the pending ETH
        // clears the mid-day request threshold.
        vm.prank(actor);
        game.purchase{value: 30 * priceWei + 2 ether}(0, 400, BoxOrderLib.boOrder(30, 0, 0, 1, 1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 reqId = _mineMiddayRequest(actor);
        uint256 base = game.level();

        // Search the word for a draw whose lanes include an isolated high-nibble offset, so every
        // step of the walk is exercised; the word only moves the boxes' targets.
        uint256[64] memory announced;
        uint256[64] memory queued;
        uint256 boxes;
        bool found;
        for (uint256 w = 1; w <= 96 && !found; w++) {
            uint256 snap = vm.snapshotState();
            mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("lane_word", w))) | 1);
            // The engine publishes the word and opens the read cohort's order as a read consumer.
            vm.recordLogs();
            vm.prank(actor);
            game.mineFlip();
            (announced, queued, boxes) = _tally(vm.getRecordedLogs(), ref, base);
            assertGt(_word(N), 0, "the word landed at the order's index");
            assertTrue(game.boxIndexComplete(N), "the walk opened the order");
            if (_hasIsolatedHighNibbleLane(announced)) found = true;
            else vm.revertToState(snap);
        }
        assertTrue(found, "some word populates an isolated high-nibble lane");
        assertGe(boxes, 15, "most of the boxes opened plainly");

        // A box that drew a spin announces nothing here but may still queue tickets, so a level
        // may hold MORE than its plain boxes announced; it can never hold less, and a mis-walked
        // lane would leave an announced level short.
        uint256 lanes;
        for (uint256 k; k < 64; k++) {
            assertGe(queued[k], announced[k], "a level receives at least the entries its boxes announced");
            if (announced[k] != 0) {
                lanes++;
                emit log_named_uint("populated lane offset", k);
            }
        }
        assertGe(lanes, 3, "the boxes spread over several lanes");
    }
}
