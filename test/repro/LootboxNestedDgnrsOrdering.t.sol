// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {SigFigLib} from "../../contracts/libraries/SigFigLib.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title LootboxNestedDgnrsOrdering
/// @notice Regression for a parent box entry that wins DGNRS, recursively resolves an ETH-spin
///         lootbox that also wins DGNRS, then wins DGNRS again. The parent must settle before
///         recursion and reload the live Lootbox-pool balance afterward.
contract LootboxNestedDgnrsOrdering is DeployProtocol {
    address private constant PLAYER = address(0xBEEF);
    uint48 private constant PARENT_BUFFER = 1;
    uint256 private constant CUSTOM_SIZE = 10 ether;
    uint256 private constant BOX_ORDER = (uint256(3) << 24) | ((CUSTOM_SIZE / 1e12) << 32);
    // Verified against the single-symbol spin: parent DGNRS / score-6 ETH spin
    // with a DGNRS recirculation / parent DGNRS. The assertions below require all
    // three nonzero batches and distinguish live-pool pricing after the child.
    uint256 private constant RNG_WORD = 204344;

    bytes32 private constant DGNRS_BATCH_SIG = keccak256("LootBoxDgnrsBatch(address,uint256,uint256)");
    bytes32 private constant LOOTBOX_OPENED_SIG =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // The mid-day request that commits the entry needs the subscription's LINK floor.
        mockVRF.fundSubscription(1, 100e18);
        // Seal and finish the genesis read through the production lifecycle.
        // The golden nested-spin word is bound to physical write buffer 1.
        vm.warp(block.timestamp + 1 days);
        _settleGame(0xB00757);
        _settleClean(0xB00757);
        _settleIdle(0xB00757);
        // A trailing cohort (e.g. a shut craps window riding its own mid-day word) can leave the
        // other physical tag open for writes; one filler cohort restores tag 1. A mid-day request
        // needs pending work, so a filler buyer queues one box at the mid-day threshold and the
        // engine requests that cohort's word.
        if (RecyclingState.writeBuffer(address(game)) != PARENT_BUFFER) {
            address filler = makeAddr("nested-filler");
            vm.deal(filler, 1 ether);
            vm.prank(filler);
            game.purchase{value: 1 ether}(
                filler, 0, (uint256(1) << 24) | ((1 ether / 1e12) << 32), bytes32(0), MintPaymentKind.DirectEth, false
            );
            vm.prank(filler);
            game.mineFlip();
            _settleIdle(0xB00758);
        }
        assertEq(RecyclingState.writeBuffer(address(game)), PARENT_BUFFER);
    }

    /// @dev Answer every outstanding request and finish every delivered cohort until the engine
    ///      is idle and the read cohort is complete, so a fresh mid-day request is admissible.
    function _settleIdle(uint256 vrfWord) private {
        for (uint256 i; i < 20; ++i) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (,, bool done) = mockVRF.pendingRequests(reqId);
                if (!done) mockVRF.fulfillRandomWords(reqId, vrfWord + i);
            }
            _finishReadConsumers();
            if (!game.advanceDue() && game.rngComplete()) return;
            if (game.advanceDue()) game.mineFlip();
        }
        revert("harness: cohorts never settled");
    }

    /// @dev One mineFlip given the smallest allowance that succeeds (bisection over snapshots):
    ///      it runs exactly the next admitted chunk and cannot also admit the box entry.
    function _stepMinimal() private {
        uint256 lo = 200_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            vm.revertToStateAndDelete(snap);
            if (ok) hi = mid;
            else lo = mid;
        }
        game.mineFlip{gas: hi}();
    }

    /// @notice Accepted century behavior: any keeper can settle the known winner before the
    ///         refill; if it remains unresolved, its nested awards use the replenished live pool.
    function testPermissionlessKnownWinnerBeforeAndAfterCenturyRefill() public {
        vm.deal(PLAYER, 31 ether);
        vm.prank(PLAYER);
        game.purchase{value: 30 ether}(PLAYER, 0, BOX_ORDER, bytes32(0), MintPaymentKind.DirectEth, false);
        _landWord(RNG_WORD);
        vm.prank(address(game));
        IsDGNRS(address(sdgnrs)).transferFromPool(IsDGNRS.Pool.Whale, address(sdgnrs), 100_000_000_000 ether);

        uint256 snapshot = vm.snapshotState();
        uint256 balanceBefore = sdgnrs.balanceOf(PLAYER);
        // Any third party's mineFlip settles PLAYER's box: the engine's human-box stage credits the
        // box owner regardless of caller. PARENT_BUFFER holds PLAYER's only queued box (a real
        // purchase through the production path, so boxPlayers[PARENT_BUFFER] already holds it).
        vm.prank(address(0xCA11));
        game.mineFlip();
        uint256 beforeRefillAward = sdgnrs.balanceOf(PLAYER) - balanceBefore;
        assertGt(beforeRefillAward, 0, "known winner was actually settled by another address");

        assertTrue(vm.revertToState(snapshot));
        vm.prank(address(game));
        sdgnrs.recycleCentury(100, RNG_WORD);
        uint256 poolBefore = _lootboxPool();
        vm.prank(address(0xCA11));
        game.mineFlip();
        uint256 afterRefillAward = sdgnrs.balanceOf(PLAYER) - balanceBefore;
        assertGt(afterRefillAward, beforeRefillAward, "unresolved award retains live-pool pricing");
        assertEq(poolBefore - _lootboxPool(), afterRefillAward, "nested awards debit funded inventory");
        uint256 balanceAfter = sdgnrs.balanceOf(PLAYER);
        // Whatever the engine does next (or NoWork / a pending word) is acceptable; no second payout.
        try game.mineFlip() {} catch {}
        assertEq(sdgnrs.balanceOf(PLAYER), balanceAfter);
    }

    struct NestedOpen {
        uint256[3] requested;
        uint256[3] paid;
        uint256 batchCount;
        uint256 parentAmount;
        uint256 parentOpenCount;
        uint256 poolBefore;
        uint256 balanceBefore;
        uint256 gasUsed;
    }

    /// @dev Open the committed entry (the next read consumer) and decode its DGNRS batches.
    function _openAndParse() private returns (NestedOpen memory r) {
        r.poolBefore = _lootboxPool();
        r.balanceBefore = sdgnrs.balanceOf(PLAYER);
        vm.recordLogs();
        uint256 gasBefore = gasleft();
        game.mineFlip();
        r.gasUsed = gasBefore - gasleft();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            VmSafe.Log memory entry = logs[i];
            if (entry.emitter != address(game) || entry.topics.length < 2) continue;
            if (entry.topics[1] != bytes32(uint256(uint160(PLAYER)))) continue;

            if (entry.topics[0] == DGNRS_BATCH_SIG) {
                assertLt(r.batchCount, 3, "unexpected extra DGNRS settlement batch");
                (r.requested[r.batchCount], r.paid[r.batchCount]) = abi.decode(entry.data, (uint256, uint256));
                ++r.batchCount;
            } else if (
                entry.topics[0] == LOOTBOX_OPENED_SIG && entry.topics.length == 3
                    && uint48(uint256(entry.topics[2])) == PARENT_BUFFER
            ) {
                (uint256 amount,,,,) = abi.decode(entry.data, (uint256, uint24, uint32, uint256, bool));
                r.parentAmount = amount;
                ++r.parentOpenCount;
            }
        }
    }

    /// @dev Box three's DGNRS award priced from the live pool after the first two batches, and
    ///      from the entry's stale opening snapshot.
    function _thirdRoll(NestedOpen memory r) private pure returns (uint256 fresh, uint256 stale) {
        uint256 seed3 = EntropyLib.hash4(RNG_WORD, uint256(uint160(PLAYER)), 0x426f784f70656e, 3);
        uint256 boonBudget = r.parentAmount / 10;
        if (boonBudget > 1 ether) boonBudget = 1 ether;
        uint256 rollAmount = r.parentAmount - boonBudget;
        fresh = _dgnrsReward(rollAmount, seed3, r.poolBefore - r.paid[0] - r.paid[1]);
        stale = _dgnrsReward(rollAmount, seed3, r.poolBefore);
    }

    /// @dev Awards floor to three significant figures, so a fresh and a stale price for box three
    ///      differ only when the pool sits near a rounding step. The live Lootbox pool depends on
    ///      the setup's history, so trim it by the smallest multiple of 1/10,000 of itself that
    ///      makes the two prices differ (one step period is ~0.6% of the pool and the window
    ///      ~0.02%, so steps of 0.01% always land in it within the first period).
    function _distinguishingPoolTrim() private returns (uint256 trim) {
        uint256 pool = _lootboxPool();
        for (uint256 k; k < 100; ++k) {
            trim = pool * k / 10_000;
            uint256 snap = vm.snapshotState();
            if (trim != 0) {
                vm.prank(address(game));
                IsDGNRS(address(sdgnrs)).transferFromPool(IsDGNRS.Pool.Lootbox, address(0xdead), trim);
            }
            NestedOpen memory r = _openAndParse();
            (uint256 fresh, uint256 stale) = _thirdRoll(r);
            vm.revertToStateAndDelete(snap);
            if (fresh != stale) return trim;
        }
        revert("harness: no pool trim distinguishes fresh and stale pricing");
    }

    function testParentDgnrsIsSettledAndSnapshotReloadedAcrossNestedEthSpin() public {
        vm.deal(PLAYER, 31 ether);
        vm.prank(PLAYER);
        game.purchase{value: 30 ether}(PLAYER, 0, BOX_ORDER, bytes32(0), MintPaymentKind.DirectEth, false);

        _landWord(RNG_WORD);
        uint256 trim = _distinguishingPoolTrim();
        if (trim != 0) {
            vm.prank(address(game));
            IsDGNRS(address(sdgnrs)).transferFromPool(IsDGNRS.Pool.Lootbox, address(0xdead), trim);
        }
        emit log_named_uint("lootbox_pool_trim", trim);

        NestedOpen memory r = _openAndParse();

        // The middle ETH-spin uses BoxSpin instead of the all-zero LootBoxOpened schema.
        assertEq(r.parentOpenCount, 2, "fixture did not open both parent DGNRS boxes");
        assertEq(r.batchCount, 3, "parent/child/parent DGNRS must settle as three batches");
        for (uint256 i; i < r.batchCount; ++i) {
            assertGt(r.requested[i], 0, "fixture batch must request DGNRS");
            assertEq(r.paid[i], r.requested[i], "fixture pool must remain solvent");
        }

        // Box three is the later parent DGNRS roll. It must price from the balance after the
        // pre-recursion parent batch and the nested child batch, not the entry's old snapshot.
        (uint256 expectedFresh, uint256 expectedStale) = _thirdRoll(r);

        assertEq(r.requested[2], expectedFresh, "later parent roll did not reload live pool");
        assertNotEq(expectedFresh, expectedStale, "fixture must distinguish fresh and stale pool");

        uint256 totalPaid = r.paid[0] + r.paid[1] + r.paid[2];
        assertEq(r.poolBefore - _lootboxPool(), totalPaid, "pool debit mismatch");
        assertEq(sdgnrs.balanceOf(PLAYER) - r.balanceBefore, totalPaid, "player credit mismatch");

        emit log_named_uint("nested_dgnrs_open_gas", r.gasUsed);
        emit log_named_uint("stale_third_dgnrs", expectedStale);
        emit log_named_uint("fresh_third_dgnrs", expectedFresh);
    }

    function _dgnrsReward(uint256 amount, uint256 entropy, uint256 poolBalance) private pure returns (uint256 reward) {
        uint256 tierRoll = uint24(entropy >> 56) % 1000;
        uint256 ppm;
        if (tierRoll < 497) ppm = 10;
        else if (tierRoll < 864) ppm = 390;
        else if (tierRoll < 995) ppm = 800;
        else ppm = 8000;

        reward = SigFigLib.floorToThreeSigFigs((poolBalance * ppm * amount) / (1_000_000 * 1 ether));
        if (reward > poolBalance) reward = poolBalance;
    }

    function _lootboxPool() private view returns (uint256) {
        return IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool.Lootbox);
    }

    /// @dev Commit the purchased entry with a mid-day request (its 30 ETH clears the pending-value
    ///      gate), deliver `vrfWord`, and publish it in minimal checkpoints up to the cohort's
    ///      human-box stage. The entry is then mineFlip's next read consumer. (The engine opens a
    ///      published cohort's entries in the same call that finishes the earlier stages, so
    ///      publication is stepped rather than run with unbounded gas.)
    function _landWord(uint256 vrfWord) private {
        vm.prank(PLAYER);
        game.mineFlip();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), vrfWord);
        for (uint256 i; i < 50 && game.nextMinerAction() != 10; ++i) _stepMinimal(); // HumanBoxes
        assertEq(game.nextMinerAction(), 10, "the entry is the next read consumer");
        assertEq(RecyclingState.word(address(game), PARENT_BUFFER), vrfWord, "the word reached the entry's tag");
    }

    function _settleGame(uint256 vrfWord) private {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; ++d) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) private {
        for (uint256 d; d < 240; ++d) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineFlip();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == _lastFulfilledReqId || reqId == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (!fulfilled) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
    }
}
