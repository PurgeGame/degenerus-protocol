// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {BafStageHost, BafBracketFixture} from "../helpers/BafStageHost.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

/// @title BafStagedResume — the BAF award stage draws and pays a real bracket in fixed groups.
/// @notice A real pre-stage bracket (scored trait buckets at the level and the next, scored
///         far-future queues, a full top-four board, an armed depositor draw) and the kind-7 record
///         consolidation leaves (cursor 0, 2R + 3 positions for the pool's round count, `paid` = the
///         schedule's reserved ETH term, counted in claimablePool) are paid through
///         `runDailyPhase`. Pinned: an allowance below one group plus tails changes nothing; every
///         admitted group moves the cursor by exactly eight (the head group by three) and `paid` by
///         exactly the ETH it credited; every award goes to the winner drawn when its pair starts:
///         `bafPairWinners` read at the group start for the group's first pair and for trait pairs,
///         read after replaying the first pair's queue writes for a far-future second pair, and
///         `bafHeadWinner` for the head awards. Completion deletes the record, runs `finalizeBaf`
///         (board cleared, epoch bumped) and returns the ETH term of unfilled slots to the pending
///         future pool (the stage runs inside the daily request's pool freeze); a resume from a
///         checkpoint under any allowance pays the identical remaining awards; another kind is left
///         untouched. A real consolidation (`runBafJackpot` -> `beginBaf`) arms the record with the
///         same reservation.
abstract contract BafStagedResumeFixture is BafBracketFixture {
    uint24 internal constant LVL = 20;
    uint256 internal constant WORD = uint256(keccak256("baf-staged-resume")) | 1;

    /// @dev runDailyPhase keeps DAILY_PHASE_TAIL for itself; the stage then needs one group plus
    ///      its tail. This allowance leaves strictly less than that for the stage.
    uint256 internal constant BELOW_ONE_GROUP =
        GasBounds.BAF_AWARD_GROUP + GasBounds.BAF_AWARD_TAIL + GasBounds.DAILY_PHASE_TAIL;
    /// @dev Admits one group (the stage's entry overhead is a few thousand gas); a second would
    ///      need the first eight awards to cost under 50k, which no group does.
    uint256 internal constant ONE_GROUP = BELOW_ONE_GROUP + 50_000;
    uint256 internal constant LARGE = 9_000_000;
    uint256 internal constant CALL_GAS = 30_000_000;

    uint256 internal pool;
    uint256 internal reserve;
    uint256 internal word;
    uint256 internal rollsSeen;
    uint256 internal secondPairsMoved;
    address[] internal digestAddrs;

    function _pool() internal pure virtual returns (uint128);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 40 days);
        _hostAt(LVL, WORD, true);
        host.seedPools(10 ether, 300 ether, 50 ether, LVL - 1, 40 ether);
        host.seedFrozen(true, 1 ether, 3 ether);
        _seedBracket(LVL);
        _armDepositDraw();
        vm.deal(address(game), address(game).balance + 2_000 ether);
        pool = _pool();
        reserve = _bafReserve(pool);
        word = host.dailyWord();
        assertEq(word, WORD, "the stage reads the recorded daily word");
        digestAddrs = _candidates(LVL);
    }

    // ---------------------------------------------------------------------
    // (a) below one group
    // ---------------------------------------------------------------------

    function test_AllowanceBelowOneGroupProgressesNothing() public {
        _arm(0);
        _assertNoProgress();
        host.daily{gas: CALL_GAS}(ONE_GROUP);
        assertEq(host.workView().winner, BAF_GROUP, "one group paid");
        _assertNoProgress();
    }

    // ---------------------------------------------------------------------
    // (b) one group per call
    // ---------------------------------------------------------------------

    function test_EachGroupAdvancesTheCursorByEightAndPaidByItsCredits() public {
        _arm(0);
        BafStageHost.PoolView memory p0 = host.poolView();
        uint256 n = _bafPositions(pool);
        uint256 cursor;
        uint256 credited;
        uint256 calls;
        while (cursor < n) {
            BafStageHost.WorkView memory before = host.workView();
            assertEq(before.kind, 7);
            assertEq(before.winner, cursor, "cursor sits on a group start");
            (MineFlipGas.Result memory r, uint256 groupCredit, uint256 end) = _payGroupAndCheck(cursor, LVL);
            ++calls;
            assertTrue(r.progressed, "an admitted group progresses");
            assertEq(r.rewardBasis, 1, "exactly one group per call");

            BafStageHost.WorkView memory afterW = host.workView();
            if (end < n) {
                assertFalse(r.done);
                assertEq(afterW.kind, 7);
                assertEq(afterW.winner - before.winner, BAF_GROUP, "cursor moves by exactly one group");
                assertEq(before.paid - afterW.paid, groupCredit, "paid falls by exactly the call's credit");
                assertEq(afterW.budget, pool);
                assertEq(afterW.traits, n);
            } else {
                assertTrue(r.done);
                assertEq(end - cursor, 3, "the head group pays the three head awards");
                assertEq(before.paid, groupCredit, "the head group credits the whole remaining reservation");
                _assertWorkDeleted();
            }
            BafStageHost.PoolView memory p = host.poolView();
            assertEq(p.claimable, p0.claimable, "credits come out of the reservation");
            assertEq(p.pendingFuture, p0.pendingFuture, "no residue while every slot is filled");
            assertEq(p.future, p0.future);
            credited += groupCredit;
            cursor = end;
        }
        assertEq(calls, _bafGroups(pool), "one call per group");
        assertEq(credited, reserve, "every reserved wei reaches a winner");
        emit log_named_uint("far_second_pairs_moved_by_their_first_pair", secondPairsMoved);
        assertGt(secondPairsMoved, 0, "a first pair's ticket legs move a far-future second pair's draw");
    }

    // ---------------------------------------------------------------------
    // (c) completion
    // ---------------------------------------------------------------------

    function test_CompletionFinalizesTheBracket() public {
        _arm(0);
        (uint64 epoch0, uint8 topLen0,, uint256 top0) = _bracketBoard(LVL);
        assertEq(topLen0, 4, "full board before the stage");
        assertTrue(top0 != 0);
        assertTrue(jackpots.bafHeadWinner(LVL, word, 0) == _idOf(_topBettor(3)), "the top bettor holds head slot 0");
        BafStageHost.PoolView memory p0 = host.poolView();

        MineFlipGas.Result memory r = _drainOnce(LARGE);
        assertTrue(r.done, "the stage completes");
        _assertWorkDeleted();

        // finalizeBaf: board cleared and epoch bumped, so every stored score reads stale.
        (uint64 epoch1, uint8 topLen1, bool skipped1, uint256 top1) = _bracketBoard(LVL);
        assertEq(epoch1, epoch0 + 1, "epoch bumped");
        assertEq(topLen1, 0, "board length cleared");
        assertEq(top1, 0, "board slots cleared");
        assertFalse(skipped1);
        assertEq(jackpots.bafHeadWinner(LVL, word, 0), 0, "no top bettor after finalizeBaf");
        assertEq(jackpots.bafHeadWinner(LVL, word, 2), 0, "no third or fourth place after finalizeBaf");
        uint256 rounds = _bafRounds(pool);
        for (uint256 pair; pair < rounds / 2; pair += 3) {
            uint32[4] memory drawn = jackpots.bafPairWinners(LVL, word, pair, rounds);
            for (uint256 k; k < 4; ++k) assertEq(drawn[k], 0, "closed epoch: no scatter winner");
        }

        BafStageHost.PoolView memory p1 = host.poolView();
        assertEq(p1.claimable, p0.claimable, "every slot filled: the stage leaves claimablePool as armed");
        assertEq(p1.pendingFuture, p0.pendingFuture, "no residue");
        assertEq(p1.future, p0.future);

        // The jackpot-phase daily follows.
        vm.recordLogs();
        r = host.daily{gas: CALL_GAS}(LARGE);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(r.progressed, "the next call does daily work");
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(game) || logs[j].topics.length == 0 || logs[j].topics[0] != ADVANCE_SIG) continue;
            (uint8 stage,) = abi.decode(logs[j].data, (uint8, uint24));
            assertEq(stage, 10, "the jackpot daily follows the award stage");
        }
    }

    /// @dev Head slot 1 empty (no direct deposits on the armed day): its ETH term stays in
    ///      `paid` and the head group returns it to the pending future pool, on top of the
    ///      pending balance the freeze already holds.
    function test_EmptyHeadSlotReturnsItsTermToThePendingFuturePool() public {
        _clearDepositDraw();
        assertEq(jackpots.bafHeadWinner(LVL, word, 1), 0, "head slot 1 is empty");
        _checkResidue(_bafEthTerm(pool, _bafPositions(pool) - 2));
    }

    /// @dev An empty head slot (wallet ID 0) forfeits its whole award: nothing is credited and exactly
    ///      what a filled slot would have been credited returns with the residue.
    function test_EmptyBafSlotForfeitsToResidue() public {
        address top = _topBettor(3);
        uint256 snap = vm.snapshotState();
        (uint256 creditedPaid, uint256 residuePaid) = _drainAll();
        assertGt(host.claimableOf(top), 0, "a filled head slot is paid");
        vm.revertToState(snap);
        vm.mockCall(
            address(jackpots),
            abi.encodeWithSelector(jackpots.bafHeadWinner.selector, LVL, word, uint8(0)),
            abi.encode(uint32(0))
        );
        (uint256 creditedSkipped, uint256 residueSkipped) = _drainAll();
        assertEq(host.claimableOf(top), 0, "the empty slot credits nobody");
        assertGt(creditedPaid, creditedSkipped, "the forfeited award is not credited");
        assertEq(residueSkipped - residuePaid, creditedPaid - creditedSkipped, "the forfeit joins the residue");
    }

    function _drainAll() private returns (uint256 credited, uint256 residue) {
        _arm(0);
        uint256 pending = host.poolView().pendingFuture;
        MineFlipGas.Result memory r;
        for (uint256 k; k < 32 && !r.done; ++k) {
            vm.recordLogs();
            r = host.daily{gas: CALL_GAS}(ONE_GROUP);
            credited += _creditedIn(vm.getRecordedLogs());
        }
        assertTrue(r.done);
        residue = host.poolView().pendingFuture - pending;
        assertEq(credited + residue, reserve, "credits plus residue equal the reservation");
    }

    /// @dev A bracket without a live score or board and no depositor draw: every slot is empty,
    ///      no group credits anything and the whole reservation returns.
    function test_EmptyBracketReturnsTheWholeReservation() public {
        _clearDepositDraw();
        // Every recorded score belongs to a closed epoch and the board is empty.
        vm.store(address(jackpots), keccak256(abi.encode(uint256(LVL), uint256(2))), bytes32(uint256(1)));
        assertEq(jackpots.bafHeadWinner(LVL, word, 0), 0);
        _checkResidue(reserve);
    }

    // ---------------------------------------------------------------------
    // (d) resume
    // ---------------------------------------------------------------------

    function test_MidwayResumeWithAnyAllowancePaysTheSameAwards() public {
        _arm(0);
        host.daily{gas: CALL_GAS}(ONE_GROUP);
        host.daily{gas: CALL_GAS}(ONE_GROUP);
        assertEq(host.workView().winner, 2 * BAF_GROUP);
        uint256 snap = vm.snapshotState();
        (bytes32 small, uint256 smallCalls) = _drain(ONE_GROUP, 0);
        assertTrue(vm.revertToState(snap));
        (bytes32 large, uint256 largeCalls) = _drain(LARGE, 0);
        assertTrue(vm.revertToState(snap));
        (bytes32 mixed,) = _drain(LARGE, 1);
        assertTrue(vm.revertToState(snap));
        (bytes32 medium,) = _drain(ONE_GROUP + 2_500_000, 0);
        assertEq(smallCalls, _bafGroups(pool) - 2, "one group per call");
        assertLt(largeCalls, smallCalls, "a large allowance runs several groups per call");
        assertEq(small, large, "group partition does not change any remaining award");
        assertEq(mixed, large, "interleaved no-progress calls change nothing");
        assertEq(medium, large, "a third partition pays the same awards");
    }

    function testFuzz_AllowanceLadderMatchesOneCall(uint256 seed) public {
        _arm(0);
        uint256 snap = vm.snapshotState();
        (bytes32 expected,) = _drain(LARGE, 0);
        assertTrue(vm.revertToState(snap));
        bytes32 digest;
        bool done;
        for (uint256 k; k < 96 && !done; ++k) {
            uint256 allowance = bound(uint256(keccak256(abi.encode(seed, k))), BELOW_ONE_GROUP - 200_000, LARGE);
            vm.recordLogs();
            MineFlipGas.Result memory r = host.daily{gas: CALL_GAS}(allowance);
            digest = _digestLogs(digest, vm.getRecordedLogs());
            done = r.done;
        }
        assertTrue(done, "the ladder completes the stage");
        assertEq(_digestState(digest), expected, "any allowance ladder pays the same transcript");
    }

    // ---------------------------------------------------------------------
    // Turbo floor and (e) guard
    // ---------------------------------------------------------------------

    function test_TurboFloorRollsFromOneLevelOut() public {
        _arm(1);
        uint256 cursor;
        while (cursor < _bafPositions(pool)) {
            (,, uint256 end) = _payGroupAndCheck(cursor, LVL + 1);
            cursor = end;
        }
        _assertWorkDeleted();
        assertGt(rollsSeen, 0, "ticket legs rolled from the turbo floor");
    }

    function test_OtherKindIsLeftUntouched() public {
        _arm(0);
        uint256 snap = vm.snapshotState();
        _assertWrongKindNoop(0);
        assertTrue(vm.revertToState(snap));
        _assertWrongKindNoop(2);
    }

    // ---------------------------------------------------------------------
    // Real consolidation
    // ---------------------------------------------------------------------

    /// @dev The x0 consolidation on a winning flip runs `runBafJackpot`: `beginBaf` records the
    ///      resolution day, the record is armed at cursor 0 with the schedule's ETH term reserved,
    ///      no award is paid in that transaction, and the stage then pays out every slot.
    function test_RealConsolidationArmsTheScheduleReserve() public {
        host.seedSession(LVL, WORD, false);
        host.seedPools(40 ether, 200 ether, 0, LVL - 1, 35 ether);
        uint256 claimable0 = host.liabilities();
        vm.recordLogs();
        MineFlipGas.Result memory r = host.daily{gas: CALL_GAS}(9_500_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(r.progressed && r.done, "consolidation completes");
        assertTrue(game.jackpotPhase(), "the jackpot phase opened");
        assertEq(_actualMarks(logs, LVL, LVL).length, 0, "no award is paid in the consolidation transaction");
        assertEq(jackpots.getLastBafResolvedDay(), game.currentDayView(), "beginBaf records the resolution day");

        BafStageHost.WorkView memory w = host.workView();
        assertEq(w.kind, 7, "the award stage is armed");
        assertEq(w.lvl, LVL);
        assertEq(w.traits, _bafPositions(w.budget), "2R + 3 positions for the pool's round count");
        assertEq(w.winner, 0);
        assertEq(w.quadrant, 0);
        assertGt(w.budget, 0);
        uint256 armedReserve = _bafReserve(w.budget);
        assertEq(w.paid, armedReserve, "paid is the schedule's ETH term");
        assertEq(_settledClaimableDelta(logs), armedReserve, "the reservation is the consolidation's claimable delta");
        assertGe(host.liabilities() - claimable0, armedReserve, "the reservation is counted in claimablePool");

        pool = w.budget;
        uint256 claimableArmed = host.liabilities();
        uint256 calls;
        uint256 credited;
        do {
            vm.recordLogs();
            r = host.daily{gas: CALL_GAS}(ONE_GROUP);
            logs = vm.getRecordedLogs();
            assertTrue(r.progressed);
            assertEq(_bafStageMarkers(logs, LVL), 1);
            credited += _creditedIn(logs);
            ++calls;
        } while (!r.done && calls < 32);
        assertTrue(r.done);
        assertEq(calls, _bafGroups(w.budget), "one call per award group");
        assertEq(credited, armedReserve, "every slot filled: credits equal the reservation");
        assertEq(host.liabilities(), claimableArmed, "the stage moves no pool when every slot is filled");
        _assertWorkDeleted();
        (uint64 epoch,,,) = _bracketBoard(LVL);
        assertEq(epoch, 1, "finalizeBaf closed the bracket");
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _arm(uint8 quadrant) internal {
        _armBaf(LVL, pool, quadrant);
    }

    function _clearDepositDraw() internal {
        vm.store(address(coinflip), keccak256(abi.encode(uint256(DRAW_DAY), uint256(5))), bytes32(0));
    }

    /// @dev Drains the stage one group per call and checks the residue path at completion: the
    ///      pools are frozen (as under every daily lock) with a nonzero pending future balance,
    ///      and the residue joins it.
    function _checkResidue(uint256 residue) internal {
        _arm(0);
        BafStageHost.PoolView memory p0 = host.poolView();
        assertTrue(p0.frozen, "the stage runs inside the daily freeze");
        assertEq(p0.pendingFuture, 3 ether, "the freeze already holds a pending future balance");
        uint256 credited;
        MineFlipGas.Result memory r;
        for (uint256 k; k < 32 && !r.done; ++k) {
            vm.recordLogs();
            r = host.daily{gas: CALL_GAS}(ONE_GROUP);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            credited += _creditedIn(logs);
            if (!r.done) assertEq(host.workView().paid + credited, reserve, "paid tracks the uncredited reservation");
        }
        assertTrue(r.done);
        _assertWorkDeleted();
        assertGt(residue, 0, "the case leaves a residue");
        assertEq(credited + residue, reserve, "credits plus residue equal the reservation");
        BafStageHost.PoolView memory p1 = host.poolView();
        assertEq(p1.claimable, p0.claimable - residue, "claimablePool releases exactly the residue");
        assertEq(p1.pendingFuture, p0.pendingFuture + residue, "residue joins the pending future pool");
        assertEq(p1.future, p0.future, "the frozen live future pool is untouched");
        assertTrue(p1.frozen, "the stage leaves the freeze in place");
        assertEq(p1.next, p0.next);
        assertEq(p1.pendingNext, p0.pendingNext);
        (uint64 epoch,,,) = _bracketBoard(LVL);
        assertGt(epoch, 0, "the bracket closes even with empty slots");
    }

    function _settledClaimableDelta(Vm.Log[] memory logs) internal view returns (uint256 delta) {
        bytes32 sig = keccak256("PoolsSettled(uint24,uint24,uint24,uint256,uint256,uint256,uint256,uint256,uint256)");
        bool found;
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(game) || logs[j].topics.length == 0 || logs[j].topics[0] != sig) continue;
            (,,,,,,, delta) =
                abi.decode(logs[j].data, (uint24, uint24, uint256, uint256, uint256, uint256, uint256, uint256));
            found = true;
        }
        assertTrue(found, "pools settled in the consolidation transaction");
    }

    /// @dev Pays the group at `cursor` with the one-group allowance and checks every award
    ///      exactly. The views read at the group start give the first pair, trait pairs and the
    ///      head awards. A far-future second pair is drawn after the first pair paid: its winners
    ///      are read after replaying the first pair's logged queue writes through the production
    ///      sink on the group-start state, and the group is then paid again from that state and
    ///      must log the same transcript. Every candidate's claimable and whale halves move by
    ///      exactly the awards it won in this call.
    function _payGroupAndCheck(uint256 cursor, uint24 floor)
        internal
        returns (MineFlipGas.Result memory r, uint256 groupCredit, uint256 end)
    {
        uint256 rounds = _bafRounds(pool);
        address[] memory exact = _groupWinners(LVL, word, cursor, pool);
        end = cursor + exact.length;
        (uint256[] memory c0, uint256[] memory h0) = _balances();
        uint256 snap = vm.snapshotState();
        Vm.Log[] memory logs;
        (r, logs) = _payOneGroup();
        uint256 second = (cursor >> 2) + 1;
        if (cursor + 4 < 2 * rounds && (second * 8) / rounds >= 2) {
            uint256 cut = _afterFirstPair(logs, exact, cursor, floor);
            assertTrue(vm.revertToState(snap));
            for (uint256 j; j < cut; ++j) _replayQueued(logs[j]);
            uint32[4] memory drawn = jackpots.bafPairWinners(LVL, word, second, rounds);
            bool moved;
            for (uint256 k; k < 4; ++k) {
                address winner = host.walletKeyOf(drawn[k]);
                if (winner != exact[4 + k]) moved = true;
                exact[4 + k] = winner;
            }
            assertTrue(vm.revertToStateAndDelete(snap));
            // Counted after the revert, which also restores this contract's storage.
            if (moved) ++secondPairsMoved;
            bytes32 firstRun = _digestLogs(bytes32(0), logs);
            (r, logs) = _payOneGroup();
            assertEq(_digestLogs(bytes32(0), logs), firstRun, "the group pays the same transcript from the same state");
        } else {
            vm.deleteStateSnapshot(snap);
        }
        Mark[] memory actual = _actualMarks(logs, LVL, floor);
        Mark[] memory expected = new Mark[](3 * exact.length);
        uint256 n;
        for (uint256 k; k < exact.length; ++k) {
            uint256 i = cursor + k;
            assertTrue(exact[k] != address(0), "the fixture fills every slot");
            if (i < 2 * rounds && i & 1 == 1) assertTrue(exact[k] != exact[k - 1], "a round's places are distinct");
            n = _expectMarks(expected, n, exact[k], pool, i, floor);
            groupCredit += _bafEthTerm(pool, i);
        }
        _assertMarks(actual, expected, n);
        for (uint256 m; m < actual.length; ++m) if (actual[m].sig == TICKET_SIG) ++rollsSeen;
        assertEq(_creditedIn(logs), groupCredit, "credits equal the paid awards' ETH terms");
        _assertBalanceDeltas(c0, h0, exact, cursor);
    }

    function _payOneGroup() internal returns (MineFlipGas.Result memory r, Vm.Log[] memory logs) {
        vm.recordLogs();
        r = host.daily{gas: CALL_GAS}(ONE_GROUP);
        logs = vm.getRecordedLogs();
        assertEq(_bafStageMarkers(logs, LVL), 1, "one Advance(19) per progressing call");
        assertEq(r.rewardBasis, 1, "the one-group allowance runs exactly one group");
    }

    /// @dev Index just past the first pair's last award event: its queue writes all precede it,
    ///      the second pair's all follow it.
    function _afterFirstPair(Vm.Log[] memory logs, address[] memory exact, uint256 cursor, uint24 floor)
        internal
        view
        returns (uint256 cut)
    {
        Mark[] memory scratch = new Mark[](12);
        uint256 marks;
        for (uint256 k; k < 4; ++k) marks = _expectMarks(scratch, marks, exact[k], pool, cursor + k, floor);
        uint256 seen;
        for (; cut < logs.length && seen < marks; ++cut) {
            if (logs[cut].emitter != address(game) || logs[cut].topics.length == 0) continue;
            bytes32 sig = logs[cut].topics[0];
            if (sig == ETH_SIG || sig == TICKET_SIG || sig == WHALE_SIG) ++seen;
        }
        assertEq(seen, marks, "the first pair's award events are logged");
    }

    function _replayQueued(Vm.Log memory l) internal {
        if (l.emitter != address(game) || l.topics.length < 2 || l.topics[0] != QUEUED_SIG) return;
        (uint24 target, uint32 entries) = abi.decode(l.data, (uint24, uint32));
        host.replayQueued(host.walletKeyOf(uint32(uint256(l.topics[1]))), target, entries);
    }

    function _balances() internal view returns (uint256[] memory c, uint256[] memory h) {
        c = new uint256[](digestAddrs.length);
        h = new uint256[](digestAddrs.length);
        for (uint256 j; j < digestAddrs.length; ++j) {
            c[j] = host.claimableOf(digestAddrs[j]);
            h[j] = host.whalePassesOf(digestAddrs[j]);
        }
    }

    function _assertBalanceDeltas(uint256[] memory c0, uint256[] memory h0, address[] memory paid, uint256 start)
        internal
        view
    {
        for (uint256 j; j < digestAddrs.length; ++j) {
            uint256 credit;
            uint256 halves;
            for (uint256 k; k < paid.length; ++k) {
                if (paid[k] != digestAddrs[j]) continue;
                credit += _bafEthTerm(pool, start + k);
                halves += _bafHalves(pool, start + k);
            }
            assertEq(host.claimableOf(digestAddrs[j]) - c0[j], credit, "winner credit");
            assertEq(host.whalePassesOf(digestAddrs[j]) - h0[j], halves, "winner whale halves");
        }
    }


    function _assertNoProgress() internal {
        BafStageHost.WorkView memory w0 = host.workView();
        BafStageHost.PoolView memory p0 = host.poolView();
        vm.record();
        vm.recordLogs();
        MineFlipGas.Result memory r = host.daily{gas: CALL_GAS}(BELOW_ONE_GROUP);
        assertEq(vm.getRecordedLogs().length, 0, "no event");
        (, bytes32[] memory writes) = vm.accesses(address(game));
        assertEq(writes.length, 0, "no game storage write");
        (, writes) = vm.accesses(address(jackpots));
        assertEq(writes.length, 0, "no bracket write");
        assertFalse(r.progressed, "below one group: no progress");
        assertFalse(r.done);
        assertEq(r.rewardBasis, 0);
        assertEq(abi.encode(host.workView()), abi.encode(w0), "record unchanged");
        assertEq(abi.encode(host.poolView()), abi.encode(p0), "pools unchanged");
    }

    function _assertWrongKindNoop(uint8 kind) internal {
        if (kind == 0) host.seedWork(0, 0, 0, 0, 0, 0);
        else host.seedWork(kind, LVL, 1 ether, 0.25 ether, 3, 1);
        BafStageHost.WorkView memory w0 = host.workView();
        BafStageHost.PoolView memory p0 = host.poolView();
        vm.record();
        vm.recordLogs();
        MineFlipGas.Result memory r = host.bafAwardsVia{gas: CALL_GAS}(word, LARGE);
        assertEq(vm.getRecordedLogs().length, 0, "no event");
        (, bytes32[] memory writes) = vm.accesses(address(game));
        assertEq(writes.length, 0, "no storage write");
        (, writes) = vm.accesses(address(jackpots));
        assertEq(writes.length, 0, "no bracket write");
        assertTrue(r.done, "another kind reads as done");
        assertFalse(r.progressed, "and does nothing");
        assertEq(r.rewardBasis, 0);
        assertEq(abi.encode(host.workView()), abi.encode(w0), "record unchanged");
        assertEq(abi.encode(host.poolView()), abi.encode(p0), "pools unchanged");
    }

    function _drainOnce(uint256 allowance) internal returns (MineFlipGas.Result memory r) {
        for (uint256 k; k < 32 && !r.done; ++k) r = host.daily{gas: CALL_GAS}(allowance);
    }

    /// @dev Drains the stage. `mode` 1 precedes every call with a no-progress call.
    function _drain(uint256 allowance, uint256 mode) internal returns (bytes32 digest, uint256 calls) {
        bool done;
        for (uint256 k; k < 64 && !done; ++k) {
            vm.recordLogs();
            if (mode == 1) {
                MineFlipGas.Result memory idle = host.daily{gas: CALL_GAS}(BELOW_ONE_GROUP);
                assertFalse(idle.progressed);
            }
            MineFlipGas.Result memory r = host.daily{gas: CALL_GAS}(allowance);
            assertTrue(r.progressed, "an admitting allowance progresses");
            digest = _digestLogs(digest, vm.getRecordedLogs());
            done = r.done;
            ++calls;
        }
        assertTrue(done);
        digest = _digestState(digest);
    }

    /// @dev Every award-stage log except the per-call Advance marker, in order.
    function _digestLogs(bytes32 digest, Vm.Log[] memory logs) internal view returns (bytes32) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE_SIG) continue;
            digest = keccak256(abi.encode(digest, logs[i].emitter, logs[i].topics, logs[i].data));
        }
        return digest;
    }

    function _digestState(bytes32 digest) internal view returns (bytes32) {
        for (uint256 i; i < digestAddrs.length; ++i) {
            digest = keccak256(abi.encode(
                digest, host.claimableOf(digestAddrs[i]), host.whalePassesOf(digestAddrs[i])
            ));
        }
        for (uint24 l = LVL; l <= LVL + 52; ++l) {
            digest = keccak256(abi.encode(digest, host.farQueueLength(l), host.nearQueueLength(l)));
        }
        (uint64 epoch, uint8 topLen, bool skipped, uint256 top) = _bracketBoard(LVL);
        return keccak256(abi.encode(
            digest, host.poolView(), host.workView(), epoch, topLen, skipped, top, host.liabilities()
        ));
    }

    function _assertWorkDeleted() internal view {
        BafStageHost.WorkView memory w = host.workView();
        assertEq(w.kind, 0, "record deleted");
        assertEq(w.budget, 0);
        assertEq(w.paid, 0);
        assertEq(w.traits, 0);
        assertEq(w.lvl, 0);
        assertEq(w.winner, 0);
        assertEq(w.quadrant, 0);
    }
}

/// @dev 1,200 ETH pool (96 rounds, 195 positions, 25 groups): small scatter awards above the
///      claim threshold (6.25 ETH firsts) defer to whale halves with a claimable remainder; 3.75 ETH
///      second places on the ticket leg take two rolls; head awards defer their lootbox halves.
contract BafStagedResumeTest is BafStagedResumeFixture {
    function _pool() internal pure override returns (uint128) {
        return 1_200 ether;
    }
}

/// @dev 60 ETH pool: every ticket leg rolls (single rolls for 0.375 ETH seconds, two rolls for
///      0.625 ETH firsts and the head awards' lootbox halves).
contract BafStagedResumeSmallPoolTest is BafStagedResumeFixture {
    function _pool() internal pure override returns (uint128) {
        return 60 ether;
    }
}
