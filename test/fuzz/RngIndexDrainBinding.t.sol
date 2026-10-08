// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RngIndexDrainOracle} from "./handlers/RngIndexDrainHandler.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @notice Public-path daily ticket entropy binding and post-request box binding.
/// The ordinary ticket oracle independently reconstructs generated traits and checks
/// their persisted bucket counts and owners; no event entropy field is assumed.
contract RngIndexDrainBindingTest is DeployProtocol, RngIndexDrainOracle {
    address internal buyer;
    uint256 internal lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("drainBindingBuyer");
        vm.deal(buyer, 100 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev Wallet ID recorded in queue entry 0 of physical buffer `index & 1` (the FIRST
    ///      purchase appended there); 0 when the buffer holds no entry.
    function _boxIdAt0(uint48 index) internal view returns (uint32) {
        if (RecyclingState.boxCount(address(game), index & 1) == 0) return 0;
        return BoxOrderLib.boId(RecyclingState.boxEntry(address(game), index & 1, 0));
    }

    /// @dev Nominal ordinary-leg ETH of every queued entry of `player` in buffer `index & 1`.
    ///      A box buy appends one entry at the LIVE buffer, so a nonzero total proves the box
    ///      bound to that exact buffer.
    function _presaleBoxEth(uint48 index, address player) internal view returns (uint256 total) {
        uint32 id = game.walletIdOf(player);
        uint256 n = RecyclingState.boxCount(address(game), index & 1);
        for (uint256 p; p < n; ++p) {
            uint256 word = RecyclingState.boxEntry(address(game), index & 1, p);
            if (BoxOrderLib.boId(word) != id) continue;
            total += BoxOrderLib.boNominal(word, PriceLookupLib.priceForLevel(BoxOrderLib.boLevel(word)));
        }
    }

    /// @dev Read _lootboxWord(index) directly from storage.
    function _lootboxWord(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev Read LR_INDEX from `lootboxRngPacked` (slot 33, low 48 bits).
    function _lrIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Purchase tickets for buyer at current level.
    function _purchase(uint256 qty, uint256 lootboxWei) internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * qty) / 400;
        uint256 total = ticketCost + lootboxWei;
        vm.prank(buyer);
        game.purchase{value: total}(
            0,
            qty,
            BoxOrderLib.boCustomFloor(lootboxWei),
            bytes32(0),
            MintPaymentKind.DirectEth, false
        );
    }

    /// @dev Advance + fulfill VRF + advance-until-unlock. Captures all logs
    ///      emitted during the entire advance sequence (including the drain).
    function _completeDayWithLogs(uint256 vrfWord)
        internal
        returns (Vm.Log[] memory logs)
    {
        _finishReadBoxes();
        vm.recordLogs();
        game.mineFlip(0);
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip(0);
        }
        logs = vm.getRecordedLogs();
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
                (,, bool done) = mockVRF.pendingRequests(id);
                if (done) return;
                mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("binding-midday", id))));
                lastFulfilledReqId = id;
            } else {
                game.mineFlip(0);
            }
        }
        fail("harness: mid-day work did not settle");
    }

    function _advanceAndCheck(bool checkWrongWord) internal returns (uint256 batches, uint256 entries, uint256 buyerEntries) {
        DrainSnapshot memory snap = _snapshotDrain(game);
        vm.recordLogs();
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Two physical buffers (6d0e64b09): the committed word is the read buffer's (write ^ 1).
        uint256 word = _wordAt(game, snap.index ^ 1);
        DrainResult memory result = _checkDrain(game, snap, logs, word, buyer);
        assertEq(result.unsupported, 0, "fixture crossed into a different trait consumer");
        assertEq(result.mismatches, 0, "persisted ticket traits differ from committed-word replay");
        if (result.batches != 0) {
            assertGt(word, 0, "a ticket drain consumed an unpopulated commitment");
            assertEq(_lrIndexOf(game), snap.index, "ticket drain must finish before the next index swap");
            if (checkWrongWord) {
                DrainResult memory mutant = _checkDrain(game, snap, logs, word ^ uint256(keccak256("wrong binding")), buyer);
                assertGt(mutant.mismatches, 0, "oracle failed to reject a different committed word");
            }
        }
        return (result.batches, result.entries, result.trackedEntries);
    }

    function _exerciseDailyDrain(bool checkWrongWord) internal returns (uint256 batches, uint256 entries) {
        // One user plus the protocol's initial recipients remains below the seated
        // round floor. This size requires repeated ordinary batches / budget resumes.
        _purchase(40_000, 0);
        uint256 buyerEntries;
        (batches, entries, buyerEntries) = _advanceAndCheck(checkWrongWord);
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0, "daily fixture did not request VRF");
        mockVRF.fulfillRandomWords(request, uint256(keccak256("binding-daily-drain-word")));
        for (uint256 i; i < 100 && game.rngLocked(); ++i) {
            (uint256 b, uint256 n, uint256 paid) = _advanceAndCheck(checkWrongWord);
            batches += b;
            entries += n;
            buyerEntries += paid;
        }
        assertFalse(game.rngLocked(), "daily drain did not finish");
        assertGt(batches, 1, "fixture must exercise multiple ordinary batches");
        assertGe(buyerEntries, 400, "paid buyer entries did not all pass the binding oracle");
    }

    function testBindingConsistencyDailyDrain() public {
        _exerciseDailyDrain(false);
    }

    /// @notice The same real persisted outputs must fail a deliberately wrong-word
    /// replay. The production-mutation campaign additionally changes its entropy read.
    function testBindingOracleRejectsWrongWord() public {
        _exerciseDailyDrain(true);
    }

    // =========================================================================
    // AC-3 / R2: Binding consistency on the mid-day -> cross-day edge
    // =========================================================================

    /// @notice A box purchased AFTER a mid-day VRF request binds to the LIVE LR_INDEX,
    ///         NOT to the in-flight LR_INDEX-1 word being delivered. The mid-day request
    ///         (mineFlip's RequestMidday stage) advances the lootbox index by exactly 1
    ///         (DegenerusGameAdvanceModule._lrAdvanceIndexClearPending at :1140) and reserves
    ///         the in-flight word at the just-vacated index (LR_INDEX-1). A subsequent box buy
    ///         records itself at the NEW LR_INDEX (DegenerusGameMintModule:1949/1960 — and the
    ///         :1951 `_lootboxWord(index) != 0` guard rejects binding to a worded
    ///         index), so when the in-flight word lands at LR_INDEX-1 the post-request box at
    ///         LR_INDEX is still un-worded and CANNOT be resolved by that word. This is the
    ///         load-bearing RNG-freeze property: a buyer cannot be resolved by a word already
    ///         requested at buy time.
    /// @dev Reads the committed word and box-binding storage directly. A post-request
    ///      purchase must remain unresolved when the earlier in-flight word arrives.
    function testBindingConsistencyMidDayCrossDay() public {
        // ── Mid-day prerequisite: today's daily RNG must already be consumed
        //    (the mid-day request is refused while _recordedDailyWord(today) == 0). Complete a
        //    day, then sit on the new day so today's word is committed.
        _completeDayWithLogs(uint256(keccak256("midday-binding-setup-word")));
        _settleMidday();
        vm.warp(block.timestamp + 1 days);
        _completeDayWithLogs(uint256(keccak256("midday-binding-setup-word-2")));
        _settleMidday();

        _finishReadBoxes();

        // ── Box A: a pre-request box buy creates pending lootbox ETH (clears the
        //    1-ether mid-day threshold) and keys itself at the LIVE index N.
        _purchase(400, 1 ether);
        uint48 idxN = _lrIndex();
        assertEq(_boxIdAt0(idxN), game.walletIdOf(buyer), "box A not keyed at live LR_INDEX");
        assertEq(_presaleBoxEth(idxN, buyer), 1 ether, "box A applied-ETH mis-keyed");
        assertEq(_lootboxWord(idxN), 0, "live index already worded before request");

        // ── Mid-day VRF request: bumps LR_INDEX N -> N+1 and reserves the in-flight
        //    word at index N (= the new LR_INDEX - 1). The word is NOT yet delivered. mineFlip
        //    is the only door to the request; with the read cohort finished it is the next action.
        uint256 priorReq = mockVRF.lastRequestId();
        game.mineFlip(0);
        assertGt(mockVRF.lastRequestId(), priorReq, "mineFlip issued the mid-day request");
        uint48 idxLive = _lrIndex();
        // Two physical buffers (6d0e64b09): the request seals N and the write side flips to N ^ 1.
        assertEq(idxLive, idxN ^ 1, "mid-day request did not advance LR_INDEX by exactly 1");
        assertEq(
            _lootboxWord(idxLive ^ 1),
            0,
            "in-flight LR_INDEX-1 word delivered before VRF fulfillment"
        );

        // ── Box B: a SECOND box bought AFTER the request must bind to the LIVE index
        //    (N+1), never to the in-flight index N being drained. The contract's
        //    :1951 worded-index guard would revert if it tried to key at a worded slot.
        address buyerB = makeAddr("drainBindingBuyerB");
        vm.deal(buyerB, 100 ether);
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * 400) / 400;
        vm.prank(buyerB);
        game.purchase{value: ticketCost + 1 ether}(
            0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
        assertEq(_boxIdAt0(idxLive), game.walletIdOf(buyerB), "box B not keyed at the LIVE post-request index");
        assertEq(_presaleBoxEth(idxLive, buyerB), 1 ether, "box B applied-ETH not at live index");
        assertEq(_presaleBoxEth(idxN, buyerB), 0, "box B leaked onto the in-flight index N");

        // ── Deliver the in-flight mid-day word. It lands ONLY at index N (LR_INDEX-1).
        uint256 midWord = uint256(keccak256("midday-binding-inflight-word"));
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, midWord);

        // Binding result: the callback stores the word and the next keeper call publishes it on
        // index N only; the post-request index N+1 is STILL un-worded — box B cannot be resolved
        // by the word requested before it was bought. The same call may drain the cohort and
        // seal box B's buffer for a further request, so the publications are read from events.
        vm.recordLogs();
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 landedN;
        uint256 landedLive;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0
                && logs[i].topics[0] == keccak256("LootboxRngApplied(uint48,uint256,uint256)")) {
                (uint48 index, uint256 word, uint256 requestId) = abi.decode(logs[i].data, (uint48, uint256, uint256));
                if (requestId != reqId) continue;
                if (index == idxN) landedN = word;
                if (index == idxLive) landedLive = word;
            }
        }
        assertTrue(landedN != 0, "in-flight word did not land at index N");
        assertEq(
            landedLive,
            0,
            "post-request live index N+1 became worded by the in-flight request"
        );
    }
}
