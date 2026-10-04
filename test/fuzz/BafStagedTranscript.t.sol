// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {CenturyConsolidationSeeder} from "../gas/AdvanceCenturyConsolidationGas.t.sol";

/// @dev Production facade plus native worker seams and read-only storage digests. The seams
///      run the production modules by delegatecall; nothing here replaces production logic.
contract BafTranscriptHost is DegenerusGame {
    function btPublish() external {
        _btNative(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("publishRng()"));
    }

    function btPrepareTickets() external returns (bool done) {
        MineFlipGas.Result memory result = abi.decode(_btNative(ContractAddresses.GAME_TICKET_MODULE,
            abi.encodeWithSignature("runTicketWork(uint24,uint256)", level, uint256(9_000_000))),
            (MineFlipGas.Result));
        done = result.done;
        if (done) {
            // Identical normalization to Miner after a completed native read.
            ticketsFullyProcessed = true;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        }
    }

    function btApply() external {
        _btNative(ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("applyDailyWord()"));
    }

    /// @dev One `runDailyPhase` call under a caller-chosen allowance.
    function btDaily(uint256 allowance) external returns (MineFlipGas.Result memory) {
        return abi.decode(_btNative(ContractAddresses.GAME_ADVANCE_MODULE,
            abi.encodeWithSignature("runDailyPhase(uint256)", allowance)), (MineFlipGas.Result));
    }

    function btDailyWord() external view returns (uint256) {
        return _recordedDailyWord(rngRequestDay);
    }

    function btBattlePending() external view returns (bool) {
        return _jackpotBattlePending();
    }

    function btWork()
        external
        view
        returns (uint128 budget, uint128 paid, uint32 n, uint24 lvl, uint16 cursor, uint8 kind, uint8 quadrant)
    {
        JackpotWork storage w = jackpotWork;
        return (w.budget, w.paid, w.traits, w.lvl, w.winner, w.kind, w.quadrant);
    }

    function btWorkRaw() external view returns (uint256 w0, uint256 w1) {
        JackpotWork storage w = jackpotWork;
        assembly ("memory-safe") {
            w0 := sload(w.slot)
            w1 := sload(add(w.slot, 1))
        }
    }

    function btPools()
        external
        view
        returns (uint256 next, uint256 future, uint256 current, uint256 yieldAcc, uint256 claimable)
    {
        (uint128 n, uint128 f) = _getPrizePools();
        return (n, f, currentPrizePool, yieldAccumulator, claimablePool);
    }

    function btPending() external view returns (uint256 pendingNext, uint256 pendingFuture, bool frozen) {
        (uint128 n, uint128 f) = _getPendingPools();
        return (n, f, prizePoolFrozen);
    }

    function btPlayer(address w) external view returns (uint256 claimable, uint256 halfPasses) {
        return (uint128(balancesPacked[w]), whalePassClaims[w]);
    }

    /// @dev Every lane owner of a far-future level's queue, in queue order.
    function btFarOwners(uint24 l) external view returns (address[] memory owners) {
        uint24 key = _tqFarFutureKey(l);
        uint256 len = _ticketQueueLength(key);
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        owners = new address[](len);
        for (uint256 i; i < len; ++i) owners[i] = _tqOwnerAt(q, l, i);
    }

    /// @dev Total far-future lanes over levels from..to.
    function btFarLanes(uint24 from, uint24 to) external view returns (uint256 lanes) {
        for (uint24 l = from; l <= to; ++l) lanes += _ticketQueueLength(_tqFarFutureKey(l));
    }

    /// @dev Reference seam: the production queue sink with the arguments one logged
    ///      `EntriesQueued` reports, so a reference walk rebuilds the queue state an award
    ///      stage left behind award by award.
    function btReplayQueued(address buyer, uint24 targetLevel, uint32 entries) external {
        _queueEntries(buyer, targetLevel, entries, true);
    }

    /// @dev Pools, Decimator seal round, level pools and phase flags.
    function btPoolDigest(uint24 lvl) external view returns (bytes32 h) {
        (uint128 next, uint128 future) = _getPrizePools();
        (uint128 pendingNext, uint128 pendingFuture) = _getPendingPools();
        DecBattleRound storage r = decBattleRounds[lvl];
        uint256 r0;
        uint256 r1;
        assembly ("memory-safe") {
            r0 := sload(r.slot)
            r1 := sload(add(r.slot, 1))
        }
        h = keccak256(abi.encode(next, future, pendingNext, pendingFuture, prizePoolFrozen, currentPrizePool,
            yieldAccumulator, claimablePool));
        h = keccak256(abi.encode(h, levelPrizePool[lvl], levelPrizePool[lvl - 1], r0, r1, centuryPrizePools.length));
        h = keccak256(abi.encode(h, level, jackpotPhaseFlag, lastPurchaseDay, jackpotCounter, jackpotFlags,
            dailyTicketBudgetsPacked, rngLockedFlag));
    }

    /// @dev Claimable, whale-pass claims, owner id, both normal cohorts and the far-future lanes
    ///      of `w`, plus its owed total at every level lvl..lvl+99.
    function btPlayerDigest(address w, uint24 lvl) external view returns (bytes32 h) {
        uint32 id = ticketOwnerId[w];
        h = keccak256(abi.encode(w, balancesPacked[w], whalePassClaims[w], id));
        if (id != 0) {
            uint256[13] memory lanes = farFutureOwed[id];
            h = keccak256(abi.encode(h, ticketPending[id], lanes));
        }
        for (uint24 l = lvl; l < lvl + 100; ++l) {
            h = keccak256(abi.encode(h, _entriesOwedTotal(l, w)));
        }
    }

    /// @dev Every queue word of the write, read and far-future keys of levels lvl..lvl+99.
    function btQueueDigest(uint24 lvl) external view returns (bytes32 h) {
        for (uint24 l = lvl; l < lvl + 100; ++l) {
            h = keccak256(abi.encode(h, _btQueueHash(l), _btQueueHash(l | TICKET_SLOT_BIT),
                _btQueueHash(l | TICKET_FAR_FUTURE_BIT)));
        }
        h = keccak256(abi.encode(h, ticketOwners.length, ticketWriteSlot));
    }

    function _btQueueHash(uint24 key) private view returns (bytes32 h) {
        uint256 len = _ticketQueueLength(key);
        h = bytes32(len);
        if (len == 0) return h;
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        uint256 words = (len + 7) >> 3;
        for (uint256 i; i < words; ++i) {
            h = keccak256(abi.encode(h, _tqWordAt(q, i << 3)));
        }
    }

    function _btNative(address target, bytes memory data) private returns (bytes memory result) {
        (bool ok, bytes memory reason) = target.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        return reason;
    }
}

/// @dev Last-purchase-day state for a plain x0 level: every trait bucket of lvl and lvl+1 holds
///      four scored players, and every far-future level lvl+2..lvl+99 queues two of them, so
///      each scatter round fills both places. Players repeat across rounds, so one wallet can
///      hold several awards.
contract PlainBafSeeder is DegenerusGame, BucketSeed {
    function seed(uint24 lvl, uint128 nextPool, uint128 futurePool, uint256 count, uint160 base) external {
        uint24 day = _simulatedDayIndex();
        level = lvl - 1;
        purchaseStartDay = day - 8;
        dailyIdx = day - 1;
        lastPurchaseDay = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        currentPrizePool = 0;
        _setPrizePools(nextPool, futurePool);
        levelPrizePool[lvl - 2] = (uint256(nextPool) * 8) / 10;
        levelPrizePool[lvl - 1] = (uint256(nextPool) * 9) / 10;
        yieldAccumulator = 10 ether;
        // The synthetic jump skips the bootstrap far-future cohorts; retire their physical
        // headers before binding the seeded population, as the century seeder does.
        for (uint24 oldLevel = 1; oldLevel <= 100; ++oldLevel) {
            uint256[] storage oldQueue = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(oldLevel))];
            assembly ("memory-safe") { sstore(oldQueue.slot, 0) }
        }
        for (uint256 t; t < 256; ++t) {
            for (uint256 k; k < 4; ++k) {
                _seedBucket(lvl, uint8(t), address(base + uint160((t * 4 + k) % count)), 1);
                _seedBucket(lvl + 1, uint8(t), address(base + uint160((t * 4 + k + 3) % count)), 1);
            }
        }
        for (uint24 target = lvl + 2; target <= lvl + 99; ++target) {
            for (uint256 k; k < 2; ++k) {
                _seedQueued(_tqFarFutureKey(target), target,
                    address(base + uint160((uint256(target) * 2 + k) % count)), uint80(4 << 8));
            }
        }
    }
}

/// @dev The century seeder fills the trait buckets the 48-round schedule samples. A larger round
///      count samples a quarter of its rounds at each of levels 100 and 101; this fills every
///      bucket those rounds select with 2048 distinct wallets.
contract CenturyTraitRoundSeeder is DegenerusGame, BucketSeed {
    function seed(uint256 word, uint256 rounds) external {
        uint256 base = EntropyLib.hash2(word, uint256(keccak256("degenerus.baf.winners")));
        for (uint256 round; round < rounds / 2; ++round) {
            uint24 target = round < rounds / 4 ? 100 : 101;
            uint8 trait = uint8(EntropyLib.hash2(base, round) >> 24);
            if (_seedBucketLen(target, trait) < 2048) {
                _seedBucketDistinct(target, trait, 2048, uint160(0xC3800000 + round * 4096));
            }
        }
    }
}

/// @title BafStagedTranscript -- the staged BAF payout is a pure function of state.
/// @notice From one last-purchase-day snapshot (daily lock held, word recorded) the consolidation
///         call (`runBafJackpot`: `beginBaf` plus the kind-7 record reserving the schedule's ETH
///         term), every BAF award call (stage 19) and the first jackpot-phase call run under three
///         allowance partitions: one call for every award, the minimal allowance admitting one
///         eight-award group per call, and a fuzzed ladder that includes calls below one group.
///         The award-stage log transcript (Advance markers excluded, their count is the
///         partition), the residue and the storage digests at completion and after the next leg
///         must be equal. The bracket stays frozen through the stage and `finalizeBaf` closes it
///         only with the last group. A reference walk rebuilds every award exactly: each scatter
///         pair is drawn at its first position, after every earlier award's logged ticket queues
///         are replayed through the production sink, by ranking the pair's own sample here (two
///         trait-bucket samples, or one eight-lane far-future sample serving both rounds) and
///         requiring `DegenerusJackpots.bafPairWinners` to agree; head awards come from
///         `bafHeadWinner` on the frozen board. Every award's logs must name that winner with the
///         schedule's amount and leg.
abstract contract BafTranscriptFixture is DeployProtocol {
    uint8 internal constant MODE_ONE_CALL = 0;
    uint8 internal constant MODE_ONE_GROUP = 1;
    uint8 internal constant MODE_LADDER = 2;

    uint8 internal constant STAGE_PURCHASE_BATTLE = 17;
    uint8 internal constant STAGE_ENTERED_JACKPOT = 7;
    uint8 internal constant STAGE_JACKPOT_DAILY_STARTED = 10;
    uint8 internal constant STAGE_JACKPOT_EARLY_BIRD_TICKETS = 14;
    uint8 internal constant STAGE_JACKPOT_BAF_AWARDS = 19;

    uint256 internal constant CALL_GAS = 90_000_000;
    uint256 internal constant WIDE_ALLOWANCE = 60_000_000;
    uint256 internal constant LADDER_MAX = 30_000_000;
    uint256 internal constant CRAPS_DAY_STAKED_SLOT = 10; // CrapsBattle `_dayStaked`
    uint24 internal constant DAY = 400;

    // Scatter draw keys of DegenerusJackpots: the winners stream tag and the far-future pair key.
    bytes32 internal constant BAF_WINNERS_TAG = keccak256("degenerus.baf.winners");
    uint256 internal constant BAF_FAR_PAIR_KEY = 1 << 16;

    // Mirrors of the production payout constants (storage and draw module).
    uint256 internal constant LOOTBOX_CLAIM_THRESHOLD = 5 ether;
    uint256 internal constant SMALL_LOOTBOX_THRESHOLD = 0.5 ether;
    uint256 internal constant HALF_WHALE_PASS_PRICE = 2.25 ether;
    uint256 internal constant QTY_SCALE = 100;
    uint16 internal constant BAF_TRAIT_SENTINEL = 420;
    uint256 internal constant BAF_TICKET_TAG = 0x4261665469636b6574;
    uint8 internal constant WHALE_PASS_SRC_BAF_DIRECT = 2;
    uint8 internal constant WHALE_PASS_SRC_AWARD_TICKETS = 3;

    // DegenerusJackpots storage: bafPlayer slot 0, bafTop slot 1, bafLevel slot 2.
    uint256 internal constant BAF_PLAYER_SLOT = 0;
    uint256 internal constant BAF_TOP_SLOT = 1;
    uint256 internal constant BAF_LEVEL_SLOT = 2;

    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");
    bytes32 internal constant ETH_SIG = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 internal constant TICKET_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant WHALE_SIG = keccak256("JackpotWhalePassWin(address,uint256,uint8)");
    bytes32 internal constant CREDIT_SIG = keccak256("PlayerCredited(address,uint256)");
    bytes32 internal constant QUEUED_SIG = keccak256("EntriesQueued(address,uint24,uint32)");
    bytes32 internal constant REGISTERED_SIG = keccak256("EntryOwnerRegistered(uint24,uint32,address)");
    bytes32 internal constant SKIPPED_SIG = keccak256("BafSkipped(uint24,uint24)");

    struct Run {
        bytes32 armed;
        bytes32 consLogs;
        bytes32 bafLogs;
        bytes32 doneState;
        bytes32 nextLogs;
        bytes32 nextState;
        uint256 residue;
        uint256 bafCalls;
        uint256 idleCalls;
        uint8 nextStage;
    }

    /// @dev The armed stage and what it moved, carried into the completion and reference checks.
    struct Stage {
        uint256 pool;
        uint256 paid0;
        uint24 floorLvl;
        uint24 consDay;
        uint256 snap;
        uint256 credited;
        uint256 residue;
        uint64 epoch;
        address[] winners;
        uint256[] claimAfter;
        uint256[] passesAfter;
    }

    /// @dev Bracket storage of DegenerusJackpots for `lvl`: the BafLevel word (epoch | topLen |
    ///      skipped), the four board slots and the global resolution day.
    struct Bracket {
        uint256 levelWord;
        bytes32[4] top;
        uint24 resolvedDay;
    }

    struct Totals {
        uint256 ethWins;
        uint256 credits;
        uint256 remainders;
        uint256 halfPasses;
    }

    /// @dev Reference-walk counters. `farPairsMoved`: far-future pairs whose pair-start draw
    ///      differs from the stage-start view (earlier awards' lanes reached the sample).
    ///      `evenAddedLane`: far-future pairs whose even round queued a new lane in the pair's band.
    ///      `oddHeld`: far-future pairs whose odd round, re-sampled after the even round, would
    ///      name other winners than the pair-start sample the stage paid.
    struct Draws {
        uint256 farPairsMoved;
        uint256 evenAddedLane;
        uint256 oddHeld;
        uint256 empty;
        uint256 emptyTerm;
    }

    BafTranscriptHost internal host;
    uint24 internal lvl;
    uint256 internal word;
    Run internal base;

    /// @dev Seed the level, restore production bytecode, drive the real request and VRF answer.
    function _seedAndArm() internal virtual;

    function _expectBaf() internal pure virtual returns (bool);

    /// @dev Scatter rounds the fixture's BAF pool selects (48 below 500 ETH).
    function _rounds() internal pure virtual returns (uint256) {
        return 48;
    }

    function _positions() internal pure returns (uint256) {
        return 2 * _rounds() + 3;
    }

    /// @dev True when every award slot has a candidate.
    function _expectFilled() internal pure virtual returns (bool) {
        return true;
    }

    /// @dev True when the fixture must show a far-future pair whose pair-start draw differs from
    ///      the stage-start view and an odd round held to its pair-start sample against a lane its
    ///      even round added (the replay and the pair-start rule are load-bearing).
    function _expectFarDrift() internal pure virtual returns (bool) {
        return false;
    }

    /// @dev Scores recorded after the host is installed and the day's prerequisites ran,
    ///      before the consolidation call.
    function _score() internal virtual {}

    function setUp() public {
        _deployProtocol();
        vm.warp((399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        _seedAndArm();

        vm.etch(address(game), type(BafTranscriptHost).runtimeCode);
        host = BafTranscriptHost(payable(address(game)));
        host.btPublish();
        for (uint256 reads; !host.btPrepareTickets{gas: 30_000_000}(); ++reads) {
            assertLt(reads, 32, "ticket prerequisites stalled");
        }
        host.btApply{gas: 30_000_000}();
        for (uint256 steps; host.btBattlePending(); ++steps) {
            assertLt(steps, 64, "the jackpot battle stalled");
            vm.recordLogs();
            MineFlipGas.Result memory res = host.btDaily{gas: 30_000_000}(9_000_000);
            assertTrue(res.progressed, "battle step progresses");
            assertEq(_lastStage(vm.getRecordedLogs()), STAGE_PURCHASE_BATTLE, "the battle precedes consolidation");
        }
        assertTrue(game.rngLocked(), "the daily lock is held before consolidation");
        word = host.btDailyWord();
        lvl = game.level();
        assertTrue(word != 0, "the day's word is recorded");
        assertEq(word & 1, _expectBaf() ? 1 : 0, "the flip bit selects the fixture's branch");
        _score();

        // The bracket slots read here are the ones the digests and closure checks use.
        Bracket memory b = _bracket();
        assertEq(uint8(b.levelWord >> 64), 4, "the fixture fills the four-place board");
        assertTrue(b.top[0] != bytes32(0), "board slot 0 holds the top bettor");

        uint256 s1 = vm.snapshotState();
        Run memory a = _run(MODE_ONE_CALL, 0, false);
        vm.revertToState(s1);
        base = a;
        emit log_named_uint("baf_level", lvl);
        emit log_named_uint("baf_residue_wei", a.residue);
        emit log_named_uint("one_call_award_calls", a.bafCalls);
    }

    /// @notice One call per award stage versus the minimal one-group allowance per call, with the
    ///         award-by-award reference walk over the one-group run.
    function test_OneGroupPerCallMatchesOneCall() public {
        Run memory b = _run(MODE_ONE_GROUP, 0, true);
        emit log_named_uint("one_group_award_calls", b.bafCalls);
        if (_expectBaf()) {
            assertEq(b.bafCalls, (_positions() + 7) / 8, "one eight-award group per call");
        }
        _assertSame(base, b);
    }

    /// @notice The single-call partition against the reference walk.
    function test_OneCallMatchesViewReference() public {
        Run memory c = _run(MODE_ONE_CALL, 0, true);
        _assertSame(base, c);
    }

    /// @notice A random allowance per call, including calls below one group, versus one call.
    function testFuzz_AllowanceLadderMatchesOneCall(uint256 seed) public {
        Run memory c = _run(MODE_LADDER, seed, false);
        emit log_named_uint("ladder_award_calls", c.bafCalls);
        emit log_named_uint("ladder_idle_calls", c.idleCalls);
        _assertSame(base, c);
    }

    // ---------------------------------------------------------------------
    // Partition runner
    // ---------------------------------------------------------------------

    function _run(uint8 mode, uint256 seed, bool checkRef) internal returns (Run memory r) {
        uint256 k;
        Vm.Log[] memory logs;
        Bracket memory b0 = _bracket();
        // Consolidation: one atomic call; an allowance below its bound progresses nothing.
        for (;;) {
            assertLt(k, 256, "consolidation never admitted");
            uint256 a = mode == MODE_LADDER ? _ladder(seed, k) : WIDE_ALLOWANCE;
            ++k;
            bool progressed;
            (progressed, logs) = _call(a);
            if (!progressed) {
                assertEq(logs.length, 0, "an idle consolidation call emits nothing");
                ++r.idleCalls;
                continue;
            }
            assertGt(a, GasBounds.POOL_CONSOLIDATION + GasBounds.DAILY_PHASE_TAIL + MineFlipGas.CHECK_RESERVE,
                "consolidation runs only above its declared bound");
            break;
        }
        assertEq(_lastStage(logs), STAGE_ENTERED_JACKPOT, "the consolidation call enters the jackpot phase");
        assertEq(_awardLogs(logs), 0, "the consolidation call pays no BAF award");
        r.consLogs = _hashLogs(bytes32(0), logs, false);

        Stage memory st;
        r.armed = _checkArmed(logs, b0, st);
        st.snap = vm.snapshotState();

        (uint256 next0, uint256 future0, uint256 current0, uint256 yield0, uint256 claimable0) = host.btPools();
        (uint256 pendNext0, uint256 pendFuture0, bool frozen0) = host.btPending();
        uint256 lanes0 = host.btFarLanes(lvl + 2, lvl + 99);

        // Award stage.
        uint256 groupAllowance;
        if (mode == MODE_ONE_GROUP && _expectBaf()) groupAllowance = _calibrateOneGroup();
        Vm.Log[] memory stageLogs = new Vm.Log[](0);
        bytes32 h;
        for (;;) {
            (,,,, uint16 cursor, uint8 kind,) = host.btWork();
            if (kind != 7) break;
            assertLt(k, 512, "award stage stalled");
            uint256 a = mode == MODE_ONE_CALL ? WIDE_ALLOWANCE : mode == MODE_ONE_GROUP ? groupAllowance : _ladder(seed, k);
            ++k;
            bool progressed;
            (progressed, logs) = _call(a);
            (, uint128 paidAfter,,, uint16 cursorAfter, uint8 kindAfter,) = host.btWork();
            if (!progressed) {
                assertEq(logs.length, 0, "an idle award call emits nothing");
                assertEq(cursorAfter, cursor, "an idle award call keeps the cursor");
                assertEq(kindAfter, 7, "an idle award call keeps the stage");
                assertTrue(mode == MODE_LADDER, "fixed partitions always progress");
                ++r.idleCalls;
                continue;
            }
            assertGt(a, _oneGroupFloor(), "no group runs below one group's admission");
            ++r.bafCalls;
            assertEq(_countAdvance(logs), 1, "one stage marker per award call");
            assertEq(_lastStage(logs), STAGE_JACKPOT_BAF_AWARDS, "award calls run stage 19");
            uint256 advanced = (kindAfter == 7 ? cursorAfter : _positions()) - cursor;
            uint256 remaining = _positions() - cursor;
            if (mode == MODE_ONE_GROUP) {
                assertEq(advanced, remaining < 8 ? remaining : 8, "exactly one group per call");
            } else {
                assertTrue(advanced % 8 == 0 || advanced == remaining, "whole groups only");
            }
            st.credited += _credits(logs);
            if (kindAfter == 7) {
                assertEq(paidAfter, st.paid0 - st.credited, "the open reservation is the reserve less the credits");
                _assertBracketOpen(b0, st.consDay);
            }
            h = _hashLogs(h, logs, true);
            stageLogs = _concat(stageLogs, logs);
        }
        r.bafLogs = h;
        if (mode == MODE_ONE_CALL && _expectBaf()) assertEq(r.bafCalls, 1, "a wide allowance pays every award in one call");

        // Completion: the record is cleared, the bracket closed, and only the residue moved pools.
        {
            (uint256 w0, uint256 w1) = host.btWorkRaw();
            assertEq(w0, 0, "jackpotWork word 0 cleared");
            assertEq(w1, 0, "jackpotWork word 1 cleared");
        }
        if (_expectBaf()) {
            _assertBracketClosed(b0, st.consDay);
            st.residue = st.paid0 - st.credited;
            (uint256 next1, uint256 future1, uint256 current1, uint256 yield1, uint256 claimable1) = host.btPools();
            (uint256 pendNext1, uint256 pendFuture1, bool frozen1) = host.btPending();
            assertEq(next1, next0, "award stage moves no next pool");
            assertEq(current1, current0, "award stage moves no current pool");
            assertEq(yield1, yield0, "award stage moves no yield accumulator");
            assertEq(pendNext1, pendNext0, "award stage moves no pending next pool");
            assertTrue(frozen0 && frozen1, "the stage runs inside the daily request's pool freeze");
            assertEq(claimable0 - claimable1, st.residue, "the residue leaves claimablePool");
            assertEq(pendFuture1 - pendFuture0, st.residue, "the residue joins the pending future pool");
            assertEq(future1, future0, "the frozen live future pool is untouched");
            if (_expectFilled()) {
                assertEq(st.residue, 0, "every slot filled: the stage credits the whole reserve");
                assertEq(claimable1, claimable0, "every slot filled: claimablePool untouched by the stage");
            } else {
                assertGt(st.residue, 0, "an unfilled slot leaves a residue");
            }
            st.winners = _awardRecipients(stageLogs);
            st.claimAfter = new uint256[](st.winners.length);
            st.passesAfter = new uint256[](st.winners.length);
            for (uint256 j; j < st.winners.length; ++j) {
                (st.claimAfter[j], st.passesAfter[j]) = host.btPlayer(st.winners[j]);
            }
            emit log_named_uint("baf_far_lanes_added", host.btFarLanes(lvl + 2, lvl + 99) - lanes0);
        } else {
            assertEq(stageLogs.length, 0, "a skipped BAF has no award stage");
        }
        r.residue = st.residue;
        address[] memory addrs = _digestAddrs(st.winners);
        r.doneState = _stateDigest(addrs);

        // The next leg is the jackpot-phase daily, run at one fixed allowance in every partition.
        bool nextProgressed;
        (nextProgressed, logs) = _call(WIDE_ALLOWANCE);
        assertTrue(nextProgressed, "the first jackpot-phase leg progresses");
        r.nextStage = _lastStage(logs);
        assertTrue(r.nextStage == STAGE_JACKPOT_DAILY_STARTED || r.nextStage == STAGE_JACKPOT_EARLY_BIRD_TICKETS,
            "the jackpot-phase daily follows the BAF stage");
        r.nextLogs = _hashLogs(bytes32(0), logs, false);
        r.nextState = _stateDigest(addrs);

        // The reference walk rebuilds the stage from its start state; nothing after it reads state.
        if (checkRef && _expectBaf()) {
            vm.revertToState(st.snap);
            _checkReference(stageLogs, st);
        }
    }

    /// @dev Consolidation effects. A winning flip runs `beginBaf` (resolution day = today) and
    ///      arms kind 7 with the schedule's reserved ETH term, leaving the board and epoch as they
    ///      were; a losing flip arms nothing and marks the bracket skipped.
    function _checkArmed(Vm.Log[] memory consLogs, Bracket memory b0, Stage memory st)
        internal
        returns (bytes32 h)
    {
        (uint128 budget, uint128 paid, uint32 n, uint24 wl, uint16 cursor, uint8 kind, uint8 quadrant) = host.btWork();
        h = keccak256(abi.encode(budget, paid, n, wl, cursor, kind, quadrant));
        Bracket memory b = _bracket();
        st.consDay = game.currentDayView();
        assertEq(b.resolvedDay, st.consDay, "the consolidation records today's resolution day");
        assertEq(keccak256(abi.encode(b.top)), keccak256(abi.encode(b0.top)), "consolidation leaves the board");
        if (!_expectBaf()) {
            assertEq(kind, 0, "a losing flip arms no award stage");
            uint256 skipped;
            for (uint256 i; i < consLogs.length; ++i) {
                if (consLogs[i].emitter == address(jackpots) && consLogs[i].topics.length != 0
                    && consLogs[i].topics[0] == SKIPPED_SIG) ++skipped;
            }
            assertEq(skipped, 1, "the consolidation call marks the bracket skipped");
            assertEq(uint64(b.levelWord), uint64(b0.levelWord), "a skip keeps the epoch");
            assertTrue((b.levelWord >> 72) & 0xff == 1, "the bracket reads skipped");
            return h;
        }
        assertEq(b.levelWord, b0.levelWord, "beginBaf leaves the epoch and board length");
        assertEq(kind, 7, "BAF award stage armed");
        assertEq(n, _positions(), "two places per scatter round plus three head slots");
        assertGt(budget, 0, "the BAF pool is positive");
        assertEq(wl, lvl, "bracket level");
        assertEq(cursor, 0, "cursor starts at the first award");
        assertEq(quadrant, 0, "a non-turbo level floors ticket rolls at the level");
        assertEq(paid, _reserve(budget), "the reservation is the schedule's ETH term");
        st.pool = budget;
        st.paid0 = paid;
        st.floorLvl = lvl + quadrant;
        st.epoch = uint64(b.levelWord);
        emit log_named_uint("baf_pool_wei", budget);
    }

    // ---------------------------------------------------------------------
    // Schedule and reference walk
    // ---------------------------------------------------------------------

    function _amountAt(uint256 pool, uint256 i) internal pure returns (uint256) {
        uint256 rounds = _rounds();
        if (i < 2 * rounds) return i & 1 == 0 ? (pool / 2) / rounds : ((pool * 30) / 100) / rounds;
        return i == 2 * rounds ? pool / 10 : pool / 20;
    }

    /// @dev Small awards pay ETH for the best of an even round and the second of an odd round.
    function _ethLeg(uint256 i) internal pure returns (bool) {
        return ((i >> 1) ^ i) & 1 == 0;
    }

    function _ethTerm(uint256 amount, uint256 threshold, bool ethLeg) internal pure returns (uint256) {
        if (amount >= threshold) {
            uint256 lootbox = amount - amount / 2;
            return amount / 2 + (lootbox > LOOTBOX_CLAIM_THRESHOLD ? lootbox % HALF_WHALE_PASS_PRICE : 0);
        }
        if (ethLeg) return amount;
        return amount > LOOTBOX_CLAIM_THRESHOLD ? amount % HALF_WHALE_PASS_PRICE : 0;
    }

    /// @dev The ETH term summed over the whole schedule, every slot counted.
    function _reserve(uint256 pool) internal pure returns (uint256 reserve) {
        for (uint256 i; i < _positions(); ++i) reserve += _ethTerm(_amountAt(pool, i), pool / 20, _ethLeg(i));
    }

    /// @dev Award-by-award reference from the stage's start state. Scatter pair q (positions
    ///      4q..4q+3: the even round's best and second, then the odd round's) is drawn at 4q, after
    ///      every earlier award's logged ticket queues were replayed through the production sink:
    ///      `_drawPair` ranks the pair's sample on that state and `bafPairWinners` must agree. All
    ///      four awards of the pair pay that draw, so a far-future pair's odd round ranks lanes
    ///      4..7 of the same eight-lane sample as its even round even when the even round's ticket
    ///      legs queued a new lane in the band before the odd round pays. Trait pairs and head
    ///      awards read frozen state and must equal the stage-start views.
    function _checkReference(Vm.Log[] memory logs, Stage memory st) internal {
        uint256 rounds = _rounds();
        uint256 pool = st.pool;
        uint256 threshold = pool / 20;
        bytes32[] memory atStageStart = new bytes32[](rounds / 2);
        for (uint256 q; q < rounds / 2; ++q) {
            atStageStart[q] = keccak256(abi.encode(jackpots.bafPairWinners(lvl, word, q, rounds)));
        }
        address[3] memory heads;
        for (uint256 s; s < 3; ++s) heads[s] = jackpots.bafHeadWinner(lvl, word, uint8(s));

        Totals memory t;
        Draws memory d;
        address[4] memory drawn;
        uint256 lanesAtPairStart;
        uint256 p;
        for (uint256 i; i < _positions(); ++i) {
            address w;
            if (i < 2 * rounds) {
                uint256 q = i >> 2;
                uint256 band = (q * 8) / rounds;
                if (i & 3 == 0) {
                    drawn = _drawPair(q, rounds, st.epoch);
                    bytes32 h = keccak256(abi.encode(drawn));
                    assertEq(keccak256(abi.encode(jackpots.bafPairWinners(lvl, word, q, rounds))), h,
                        "bafPairWinners ranks the pair's sample on the pair-start state");
                    if (h != atStageStart[q]) {
                        assertGe(band, 2, "trait pairs read frozen buckets");
                        ++d.farPairsMoved;
                    }
                    if (band >= 2) lanesAtPairStart = _bandLanes(band);
                } else if (i & 3 == 2 && band >= 2) {
                    // The even round is paid and its queues replayed: the odd round still pays
                    // lanes 4..7 of the pair-start sample (`drawn`), whatever a re-sample says.
                    if (_bandLanes(band) != lanesAtPairStart) ++d.evenAddedLane;
                    address[4] memory resampled = _drawPair(q, rounds, st.epoch);
                    if (resampled[2] != drawn[2] || resampled[3] != drawn[3]) ++d.oddHeld;
                }
                w = drawn[i & 3];
                if (i & 1 == 1 && w != address(0)) assertTrue(w != drawn[(i & 3) - 1], "a round's places are distinct");
            } else {
                w = jackpots.bafHeadWinner(lvl, word, uint8(i - 2 * rounds));
                assertEq(w, heads[i - 2 * rounds], "head slot is fixed by the frozen board");
            }
            uint256 amount = _amountAt(pool, i);
            bool ethLeg = _ethLeg(i);
            if (w == address(0) || amount == 0) {
                ++d.empty;
                d.emptyTerm += _ethTerm(amount, threshold, ethLeg);
                continue;
            }
            p = _expectAward(logs, p, w, amount, threshold, ethLeg,
                EntropyLib.hash4(word, lvl, BAF_TICKET_TAG, i), st.floorLvl, t);
        }
        assertEq(_nextKey(logs, p), logs.length, "the award stage emits nothing beyond the award set");
        assertEq(st.residue, d.emptyTerm, "the residue is the ETH term of the unfilled slots");
        assertEq(t.credits, st.credited, "the reference credits equal the logged credits");
        assertEq(t.ethWins + t.remainders + st.residue, st.paid0,
            "ETH wins plus whale remainders plus the residue equal the reserve");
        if (_expectFilled()) assertEq(d.empty, 0, "every award slot is filled");
        else assertGt(d.empty, 0, "the fixture leaves a slot unfilled");
        if (_expectFarDrift()) {
            assertGt(d.farPairsMoved, 0, "an earlier award's lane moves a later far-future pair's draw");
            assertGt(d.oddHeld, 0, "an even round's new lane would move its odd round on a re-sample");
        }

        // Credits and whale-pass claims landed on the winners exactly as the logs report.
        uint256 claimDelta;
        uint256 passDelta;
        for (uint256 j; j < st.winners.length; ++j) {
            (uint256 c, uint256 hp) = host.btPlayer(st.winners[j]);
            claimDelta += st.claimAfter[j] - c;
            passDelta += st.passesAfter[j] - hp;
        }
        assertEq(claimDelta, st.credited, "winner claimable grows by the credited ETH");
        assertEq(passDelta, t.halfPasses, "winner whale-pass claims grow by the logged half passes");
        emit log_named_uint("baf_far_pairs_moved_by_earlier_awards", d.farPairsMoved);
        emit log_named_uint("baf_far_pairs_even_round_added_a_lane", d.evenAddedLane);
        emit log_named_uint("baf_far_pairs_odd_round_held_to_pair_start", d.oddHeld);
        emit log_named_uint("baf_empty_slots", d.empty);
    }

    /// @dev Pair q of `rounds` ranked here on the current state: a trait pair ranks two four-entry
    ///      bucket samples (one per round); a far-future pair ranks lanes 0..3 (even round) and
    ///      4..7 (odd round) of one eight-lane sample.
    function _drawPair(uint256 q, uint256 rounds, uint64 epoch) internal view returns (address[4] memory d) {
        uint256 base = EntropyLib.hash2(word, uint256(BAF_WINNERS_TAG));
        uint256 band = (q * 8) / rounds;
        if (band < 2) {
            (, address[] memory a) = game.sampleTraitEntries(band == 1, EntropyLib.hash2(base, 2 * q));
            (d[0], d[1]) = _rankRef(a, 0, epoch);
            (, a) = game.sampleTraitEntries(band == 1, EntropyLib.hash2(base, 2 * q + 1));
            (d[2], d[3]) = _rankRef(a, 0, epoch);
        } else {
            (uint24 from, uint24 to) = _bandLevels(band);
            address[] memory lanes = game.sampleFarFutureTickets(EntropyLib.hash2(base, BAF_FAR_PAIR_KEY | q), from, to);
            (d[0], d[1]) = _rankRef(lanes, 0, epoch);
            (d[2], d[3]) = _rankRef(lanes, 4, epoch);
        }
    }

    function _bandLevels(uint256 band) internal view returns (uint24 from, uint24 to) {
        return band == 2 ? (lvl + 2, lvl + 5) : (lvl + 6, lvl + 99);
    }

    function _bandLanes(uint256 band) internal view returns (uint256) {
        (uint24 from, uint24 to) = _bandLevels(band);
        return host.btFarLanes(from, to);
    }

    /// @dev Best and second-best bracket score among the four candidates from `off`; a later
    ///      candidate takes a place only with a strictly higher score, and the second place never
    ///      repeats the best.
    function _rankRef(address[] memory c, uint256 off, uint64 epoch)
        internal
        view
        returns (address best, address second)
    {
        uint256 end = off + 4 < c.length ? off + 4 : c.length;
        uint256 bestScore;
        uint256 secondScore;
        for (uint256 k = off; k < end; ++k) {
            uint256 score = _scoreOf(c[k], epoch);
            if (score > bestScore) {
                (second, secondScore) = (best, bestScore);
                (best, bestScore) = (c[k], score);
            } else if (score > secondScore && c[k] != best) {
                (second, secondScore) = (c[k], score);
            }
        }
    }

    /// @dev `bafPlayer[lvl][a]` total when it belongs to the bracket's live epoch, else zero.
    function _scoreOf(address a, uint64 epoch) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(lvl), BAF_PLAYER_SLOT));
        uint256 v = uint256(vm.load(address(jackpots), keccak256(abi.encode(a, inner))));
        return uint64(v >> 192) == epoch ? uint192(v) : 0;
    }

    /// @dev One award's logs: a large award (at least a twentieth of the pool) half ETH and half
    ///      tickets or, above the claim threshold, whale-pass halves; a small ETH-leg award all ETH;
    ///      a small ticket-leg award all tickets or, above the claim threshold, whale-pass halves.
    function _expectAward(
        Vm.Log[] memory logs,
        uint256 p,
        address w,
        uint256 a,
        uint256 threshold,
        bool ethLeg,
        uint256 entropy,
        uint24 floorLvl,
        Totals memory t
    ) internal returns (uint256) {
        if (a >= threshold) {
            uint256 eth = a / 2;
            uint256 lootbox = a - eth;
            p = _expectCredit(logs, p, w, eth, t);
            p = _expectEthWin(logs, p, w, eth, t);
            if (lootbox <= LOOTBOX_CLAIM_THRESHOLD) return _expectRolls(logs, p, w, lootbox, entropy, floorLvl);
            p = _expectCredit(logs, p, w, lootbox % HALF_WHALE_PASS_PRICE, t);
            t.remainders += lootbox % HALF_WHALE_PASS_PRICE;
            return _expectWhale(logs, p, w, lootbox / HALF_WHALE_PASS_PRICE, WHALE_PASS_SRC_BAF_DIRECT, t);
        }
        if (ethLeg) {
            p = _expectCredit(logs, p, w, a, t);
            return _expectEthWin(logs, p, w, a, t);
        }
        if (a > LOOTBOX_CLAIM_THRESHOLD) {
            p = _expectCredit(logs, p, w, a % HALF_WHALE_PASS_PRICE, t);
            t.remainders += a % HALF_WHALE_PASS_PRICE;
            return _expectWhale(logs, p, w, a / HALF_WHALE_PASS_PRICE, WHALE_PASS_SRC_AWARD_TICKETS, t);
        }
        return _expectRolls(logs, p, w, a, entropy, floorLvl);
    }

    function _nextKey(Vm.Log[] memory logs, uint256 p) internal view returns (uint256) {
        while (p < logs.length && logs[p].emitter == address(game) && logs[p].topics.length != 0
            && (logs[p].topics[0] == REGISTERED_SIG || logs[p].topics[0] == ADVANCE_SIG)) {
            ++p;
        }
        return p;
    }

    function _expectCredit(Vm.Log[] memory logs, uint256 p, address w, uint256 amount, Totals memory t)
        internal
        view
        returns (uint256)
    {
        if (amount == 0) return p;
        p = _nextKey(logs, p);
        assertLt(p, logs.length, "credit log present");
        assertEq(logs[p].topics[0], CREDIT_SIG, "claimable credit");
        assertEq(logs[p].topics[1], bytes32(uint256(uint160(w))), "credit winner");
        assertEq(keccak256(logs[p].data), keccak256(abi.encode(amount)), "credit amount");
        t.credits += amount;
        return p + 1;
    }

    function _expectEthWin(Vm.Log[] memory logs, uint256 p, address w, uint256 amount, Totals memory t)
        internal
        view
        returns (uint256)
    {
        p = _nextKey(logs, p);
        assertLt(p, logs.length, "ETH win log present");
        assertEq(logs[p].topics[0], ETH_SIG, "ETH win");
        assertEq(logs[p].topics[1], bytes32(uint256(uint160(w))), "ETH winner");
        assertEq(logs[p].topics[2], bytes32(uint256(lvl)), "ETH win level");
        assertEq(logs[p].topics[3], bytes32(uint256(BAF_TRAIT_SENTINEL)), "BAF sentinel");
        assertEq(keccak256(logs[p].data), keccak256(abi.encode(amount, uint256(0))), "ETH win amount");
        t.ethWins += amount;
        return p + 1;
    }

    function _expectWhale(Vm.Log[] memory logs, uint256 p, address w, uint256 halves, uint8 source, Totals memory t)
        internal
        view
        returns (uint256)
    {
        p = _nextKey(logs, p);
        assertLt(p, logs.length, "whale-pass log present");
        assertEq(logs[p].topics[0], WHALE_SIG, "whale-pass deferral");
        assertEq(logs[p].topics[1], bytes32(uint256(uint160(w))), "whale-pass winner");
        assertEq(keccak256(logs[p].data), keccak256(abi.encode(halves, source)), "half passes and source");
        t.halfPasses += halves;
        return p + 1;
    }

    /// @dev One roll at or below the small threshold, two half rolls above it.
    function _expectRolls(Vm.Log[] memory logs, uint256 p, address w, uint256 amount, uint256 entropy, uint24 floorLvl)
        internal
        returns (uint256)
    {
        if (amount <= SMALL_LOOTBOX_THRESHOLD) {
            (p,) = _expectRoll(logs, p, w, amount, entropy, floorLvl);
            return p;
        }
        uint256 half = amount / 2;
        (p, entropy) = _expectRoll(logs, p, w, half, entropy, floorLvl);
        (p,) = _expectRoll(logs, p, w, amount - half, entropy, floorLvl);
        return p;
    }

    /// @dev Independent ticket roll: 30% the floor, 65% one to four levels above, 5% five to fifty
    ///      above; the scaled count collapses to whole tickets by a Bernoulli round-up. The queue
    ///      it logs is replayed so the next pair's draw sees the state the stage drew it on.
    function _expectRoll(Vm.Log[] memory logs, uint256 p, address w, uint256 amount, uint256 entropy, uint24 floorLvl)
        internal
        returns (uint256, uint256)
    {
        entropy = EntropyLib.hash2(entropy, entropy);
        uint256 roll = entropy % 100;
        uint256 div = entropy / 100;
        uint24 target;
        if (roll < 30) target = floorLvl;
        else if (roll < 95) target = floorLvl + uint24(1 + div % 4);
        else target = floorLvl + uint24(5 + div % 46);
        uint256 scaled = (amount * QTY_SCALE) / PriceLookupLib.priceForLevel(target);
        if (scaled > type(uint32).max) scaled = type(uint32).max;
        uint32 whole = uint32(scaled / QTY_SCALE);
        uint32 frac = uint32(scaled % QTY_SCALE);
        bool up = frac != 0 && (uint32(entropy >> 96) % uint32(QTY_SCALE)) < frac;
        if (up) ++whole;
        uint32 entries = whole << 2;
        if (entries != 0) {
            p = _nextKey(logs, p);
            assertLt(p, logs.length, "queue log present");
            assertEq(logs[p].topics[0], QUEUED_SIG, "entries queued");
            assertEq(logs[p].topics[1], bytes32(uint256(uint160(w))), "queued winner");
            assertEq(keccak256(logs[p].data), keccak256(abi.encode(target, entries)), "queued level and entries");
            host.btReplayQueued(w, target, entries);
            ++p;
        }
        p = _nextKey(logs, p);
        assertLt(p, logs.length, "ticket win log present");
        assertEq(logs[p].topics[0], TICKET_SIG, "ticket win");
        assertEq(logs[p].topics[1], bytes32(uint256(uint160(w))), "ticket winner");
        assertEq(logs[p].topics[2], bytes32(uint256(target)), "ticket target level");
        assertEq(logs[p].topics[3], bytes32(uint256(BAF_TRAIT_SENTINEL)), "BAF sentinel");
        assertEq(keccak256(logs[p].data), keccak256(abi.encode(entries, floorLvl, uint256(0), up)),
            "ticket count, floor and round-up");
        return (p + 1, entropy);
    }

    // ---------------------------------------------------------------------
    // Bracket state
    // ---------------------------------------------------------------------

    function _bracket() internal view returns (Bracket memory b) {
        b.levelWord = uint256(vm.load(address(jackpots), keccak256(abi.encode(uint256(lvl), BAF_LEVEL_SLOT))));
        uint256 topBase = uint256(keccak256(abi.encode(uint256(lvl), BAF_TOP_SLOT)));
        for (uint256 i; i < 4; ++i) b.top[i] = vm.load(address(jackpots), bytes32(topBase + i));
        b.resolvedDay = jackpots.getLastBafResolvedDay();
    }

    /// @dev Mid-stage: board, epoch and resolution day exactly as consolidation left them.
    function _assertBracketOpen(Bracket memory b0, uint24 consDay) internal view {
        Bracket memory b = _bracket();
        assertEq(b.levelWord, b0.levelWord, "the bracket epoch and board length stay frozen mid-stage");
        assertEq(keccak256(abi.encode(b.top)), keccak256(abi.encode(b0.top)), "the board stays frozen mid-stage");
        assertEq(b.resolvedDay, consDay, "the resolution day stays at the consolidation day");
    }

    /// @dev After the last group: `finalizeBaf` cleared the board and bumped the epoch.
    function _assertBracketClosed(Bracket memory b0, uint24 consDay) internal view {
        Bracket memory b = _bracket();
        assertEq(b.levelWord, uint256(uint64(b0.levelWord)) + 1, "finalizeBaf bumps the epoch, empties the board");
        for (uint256 i; i < 4; ++i) assertEq(b.top[i], bytes32(0), "finalizeBaf clears every board slot");
        assertEq(b.resolvedDay, consDay, "the resolution day stays at the consolidation day");
    }

    // ---------------------------------------------------------------------
    // Allowances
    // ---------------------------------------------------------------------

    /// @dev The largest allowance that cannot admit one group: the Draw module's group
    ///      admission plus the Advance tail retained ahead of it.
    function _oneGroupFloor() internal pure returns (uint256) {
        return GasBounds.BAF_AWARD_GROUP + GasBounds.BAF_AWARD_TAIL + MineFlipGas.CHECK_RESERVE
            + GasBounds.DAILY_PHASE_TAIL;
    }

    /// @dev Allowances in [just below one group, 30M]: a quarter just below one group, a quarter
    ///      within 1M above it and a quarter within 4M (a few groups each), a quarter up to 30M.
    function _ladder(uint256 seed, uint256 k) internal pure returns (uint256) {
        uint256 r = uint256(keccak256(abi.encode(seed, k)));
        uint256 floor_ = _oneGroupFloor();
        uint256 band = r % 4;
        r >>= 8;
        if (band == 0) return floor_ - 250_000 + r % 250_001;
        if (band == 1) return floor_ + 1 + r % 1_000_000;
        if (band == 2) return floor_ + 1 + r % 4_000_000;
        return floor_ + 1 + r % (LADDER_MAX - floor_);
    }

    /// @dev Smallest allowance whose first award call progresses (to 1k), plus a 10k margin;
    ///      every call at it must still run exactly one group.
    function _calibrateOneGroup() internal returns (uint256) {
        uint256 snap = vm.snapshotState();
        uint256 lo = _oneGroupFloor();
        uint256 hi = lo + 400_000;
        MineFlipGas.Result memory res = host.btDaily{gas: CALL_GAS}(hi);
        vm.revertToState(snap);
        assertTrue(res.progressed, "calibration ceiling admits a group");
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            res = host.btDaily{gas: CALL_GAS}(mid);
            vm.revertToState(snap);
            if (res.progressed) hi = mid;
            else lo = mid;
        }
        emit log_named_uint("one_group_allowance", hi + 10_000);
        return hi + 10_000;
    }

    // ---------------------------------------------------------------------
    // Digests and log helpers
    // ---------------------------------------------------------------------

    function _call(uint256 allowance) internal returns (bool progressed, Vm.Log[] memory logs) {
        vm.recordLogs();
        MineFlipGas.Result memory res = host.btDaily{gas: CALL_GAS}(allowance);
        logs = vm.getRecordedLogs();
        progressed = res.progressed;
        assertEq(_countAdvance(logs) != 0, progressed, "a stage marker exactly when the call progresses");
    }

    /// @dev Pools, Decimator seal, level pools, quest state, every queue of lvl..lvl+99, each
    ///      digest address's balances and lanes, the work record and the bracket state.
    function _stateDigest(address[] memory addrs) internal view returns (bytes32 h) {
        h = host.btPoolDigest(lvl);
        h = keccak256(abi.encode(h, host.btQueueDigest(lvl)));
        for (uint256 j; j < addrs.length; ++j) {
            h = keccak256(abi.encode(h, host.btPlayerDigest(addrs[j], lvl)));
        }
        (uint256 w0, uint256 w1) = host.btWorkRaw();
        h = keccak256(abi.encode(h, w0, w1));
        Bracket memory b = _bracket();
        h = keccak256(abi.encode(h, b.levelWord, b.top, b.resolvedDay));
        // Level type/version share the active daily-quest word at bits 128..143.
        h = keccak256(abi.encode(h, bytes32(uint256(uint16(uint256(vm.load(address(quests), bytes32(0))) >> 128))), address(game).balance));
    }

    /// @dev Every address an award log names, in first-seen order.
    function _awardRecipients(Vm.Log[] memory logs) internal view returns (address[] memory out) {
        address[] memory buf = new address[](logs.length);
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic != ETH_SIG && topic != TICKET_SIG && topic != WHALE_SIG && topic != CREDIT_SIG) continue;
            address a = address(uint160(uint256(logs[i].topics[1])));
            bool seen;
            for (uint256 j; j < n; ++j) {
                if (buf[j] == a) {
                    seen = true;
                    break;
                }
            }
            if (!seen) buf[n++] = a;
        }
        out = new address[](n);
        for (uint256 i; i < n; ++i) out[i] = buf[i];
    }

    function _digestAddrs(address[] memory winners) internal view returns (address[] memory out) {
        address[] memory extra = _extraDigestAddrs();
        out = new address[](winners.length + extra.length);
        uint256 n;
        for (uint256 i; i < winners.length; ++i) out[n++] = winners[i];
        for (uint256 i; i < extra.length; ++i) {
            bool seen;
            for (uint256 j; j < winners.length; ++j) {
                if (winners[j] == extra[i]) {
                    seen = true;
                    break;
                }
            }
            if (!seen) out[n++] = extra[i];
        }
        assembly ("memory-safe") { mstore(out, n) }
    }

    function _extraDigestAddrs() internal view virtual returns (address[] memory) {
        return new address[](0);
    }

    function _credits(Vm.Log[] memory logs) internal view returns (uint256 sum) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == CREDIT_SIG) {
                sum += abi.decode(logs[i].data, (uint256));
            }
        }
    }

    function _hashLogs(bytes32 h, Vm.Log[] memory logs, bool skipAdvance) internal view returns (bytes32) {
        for (uint256 i; i < logs.length; ++i) {
            if (skipAdvance && logs[i].emitter == address(game) && logs[i].topics.length != 0
                && logs[i].topics[0] == ADVANCE_SIG) continue;
            h = keccak256(abi.encode(h, logs[i].emitter, logs[i].topics, logs[i].data));
        }
        return h;
    }

    function _concat(Vm.Log[] memory a, Vm.Log[] memory b) internal pure returns (Vm.Log[] memory c) {
        c = new Vm.Log[](a.length + b.length);
        for (uint256 i; i < a.length; ++i) c[i] = a[i];
        for (uint256 i; i < b.length; ++i) c[a.length + i] = b[i];
    }

    function _countAdvance(Vm.Log[] memory logs) internal view returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE_SIG) {
                ++count;
            }
        }
    }

    function _lastStage(Vm.Log[] memory logs) internal view returns (uint8 stage) {
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE_SIG) {
                (stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
    }

    function _awardLogs(Vm.Log[] memory logs) internal pure returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == ETH_SIG || topic == TICKET_SIG || topic == WHALE_SIG) ++count;
        }
    }

    function _assertSame(Run memory x, Run memory y) internal pure {
        assertEq(x.consLogs, y.consLogs, "consolidation transcript");
        assertEq(x.armed, y.armed, "armed record");
        assertEq(x.bafLogs, y.bafLogs, "award-stage transcript");
        assertEq(x.residue, y.residue, "residue");
        assertEq(x.doneState, y.doneState, "storage at award completion");
        assertEq(x.nextStage, y.nextStage, "next leg stage");
        assertEq(x.nextLogs, y.nextLogs, "next leg transcript");
        assertEq(x.nextState, y.nextState, "storage after the next leg");
    }

    // ---------------------------------------------------------------------
    // Arming
    // ---------------------------------------------------------------------

    /// @dev Booked craps days, yesterday's flip resolved, then the real miner up to the daily
    ///      request and its VRF answer (the century fixture's arming without its gas seeding).
    function _armWord(uint256 w) internal {
        for (uint24 i = 1; i <= 7; ++i) {
            vm.store(address(crapsBattle), keccak256(abi.encode(uint256(DAY - i), CRAPS_DAY_STAKED_SLOT)),
                bytes32((uint256(500_000 ether) << 128) | uint256(1_000_000 ether)));
        }
        vm.prank(address(game));
        coinflip.processCoinflipPayouts(0, uint256(keccak256("yesterday")) | 1, DAY - 1);
        uint256 beforeRequest = mockVRF.lastRequestId();
        for (uint256 calls; mockVRF.lastRequestId() == beforeRequest; ++calls) {
            assertLt(calls, 512, "request preparation stalled");
            game.mineFlip{gas: 12_000_000}();
        }
        assertEq(mockVRF.lastRequestId(), beforeRequest + 1, "one real daily request");
        mockVRF.fulfillRandomWords(beforeRequest + 1, w);
    }

    /// @dev Arm the final-day weighted depositor draw over `count` packed intervals.
    function _armDepositDraw(address[] memory depositors) internal {
        uint256 count = depositors.length;
        for (uint256 i; i < count; ++i) {
            vm.store(address(coinflip), keccak256(abi.encode((uint256(DAY) << 32) | i, uint256(8))),
                bytes32((uint256(uint160(depositors[i])) << 96) | ((i + 1) * 100)));
        }
        vm.store(address(coinflip), keccak256(abi.encode(uint256(DAY), uint256(5))),
            bytes32((count << 96) | (count * 100)));
        vm.prank(address(game));
        coinflip.armBafDraw(DAY);
        (, uint96 weight, uint32 drawn) = coinflip.bafDrawInfo();
        assertEq(drawn, count, "draw layout");
        assertEq(weight, count * 100, "draw weight");
    }
}

/// @dev Level 100 seeded by the century consolidation fixture's seeder and word (the trait
///      buckets each round's draw reads hold 2048 distinct wallets), with every far-future lane
///      owner scored, so every award slot fills whatever lanes earlier awards add.
abstract contract CenturyBafTranscript is BafTranscriptFixture {
    /// @dev The century fixture's word (bit 0 set: winning flip).
    uint256 internal constant WORD = 0x0ee7fcb287531227df7efcfddb3f0151121ee9e59765e743a190d8e26ee417fd;

    function _pools() internal pure virtual returns (uint128 nextPool, uint128 futurePool);

    function _expectBaf() internal pure override returns (bool) {
        return true;
    }

    function _expectFarDrift() internal pure override returns (bool) {
        return true;
    }

    function _seedAndArm() internal override {
        (uint128 nextPool, uint128 futurePool) = _pools();
        bytes memory original = address(game).code;
        vm.etch(address(game), type(CenturyConsolidationSeeder).runtimeCode);
        CenturyConsolidationSeeder(payable(address(game))).seed(WORD, nextPool, futurePool);
        vm.etch(address(game), type(CenturyTraitRoundSeeder).runtimeCode);
        CenturyTraitRoundSeeder(payable(address(game))).seed(WORD, _rounds());
        vm.etch(address(game), original);
        vm.deal(address(game), uint256(nextPool) + futurePool + 68.25 ether + uint256(nextPool) / 400);
        mockStETH.mint(address(game), 50 ether);
        _armWord(WORD);
        assertEq(game.level(), 100, "the request pre-increments the level");
        address[] memory depositors = new address[](64);
        for (uint256 i; i < 64; ++i) depositors[i] = address(0xD3F0517);
        _armDepositDraw(depositors);
    }

    function _score() internal override {
        // A full board of four bettors above every scatter candidate.
        for (uint256 i; i < 4; ++i) {
            vm.prank(ContractAddresses.COINFLIP);
            jackpots.recordBafFlip(address(uint160(0xBAF000 + i)), 100, (i + 1) * 1_000_000 ether);
        }
        // Trait rounds (the first half, a quarter per level) read frozen buckets: score the four
        // entries each round samples.
        uint256 entropyBase = EntropyLib.hash2(WORD, uint256(BAF_WINNERS_TAG));
        for (uint256 r; r < _rounds() / 2; ++r) {
            (, address[] memory candidates) =
                game.sampleTraitEntries(r >= _rounds() / 4, EntropyLib.hash2(entropyBase, r));
            assertEq(candidates.length, 4, "each trait round samples four entries");
            for (uint256 i; i < candidates.length; ++i) {
                vm.prank(ContractAddresses.COINFLIP);
                jackpots.recordBafFlip(candidates[i], 100, (i + 1) * 100 ether);
            }
        }
        // Far-future rounds sample lanes whose positions move when earlier awards add lanes:
        // score every lane owner of 102..199 (below the board, so the board is unchanged).
        uint256 epoch = uint64(uint256(vm.load(address(jackpots), keccak256(abi.encode(uint256(100), BAF_LEVEL_SLOT)))));
        bytes32 inner = keccak256(abi.encode(uint256(100), BAF_PLAYER_SLOT));
        address probe = address(0xBAF5C0E);
        vm.prank(ContractAddresses.COINFLIP);
        jackpots.recordBafFlip(probe, 100, 7 ether);
        assertEq(uint256(vm.load(address(jackpots), keccak256(abi.encode(probe, inner)))), 7 ether | (epoch << 192),
            "bafPlayer slot layout");
        for (uint24 l = 102; l <= 199; ++l) {
            address[] memory owners = host.btFarOwners(l);
            for (uint256 i; i < owners.length; ++i) {
                uint256 score = (1 + uint256(uint160(owners[i])) % 997) * 1 ether;
                vm.store(address(jackpots), keccak256(abi.encode(owners[i], inner)), bytes32(score | (epoch << 192)));
            }
        }
    }
}

/// @notice x00 fixture shape: large winners split ETH with ticket rolls and one whale deferral.
/// forge-config: default.fuzz.runs = 32
contract BafStagedTranscriptCentury is CenturyBafTranscript {
    function _pools() internal pure override returns (uint128, uint128) {
        return (3500 ether, 100 ether);
    }
}

/// @notice x00 at a 1,100 ETH pool: 96 scatter rounds (195 positions, 25 groups). First places
///         (5.73 ETH) on the ticket leg and the head awards' lootbox halves defer to whale-pass
///         halves; ticket-leg second places (3.44 ETH) take two rolls.
/// forge-config: default.fuzz.runs = 32
contract BafStagedTranscriptCenturyAllDeferred is CenturyBafTranscript {
    function _pools() internal pure override returns (uint128, uint128) {
        return (100 ether, 5_527_303_235_348_616_599_105);
    }

    function _rounds() internal pure override returns (uint256) {
        return 96;
    }
}

/// @dev Plain x0 level with 40 scored players filling every scatter round.
abstract contract PlainBafTranscript is BafTranscriptFixture {
    uint256 internal constant PLAYERS = 40;
    uint160 internal constant PLAYER_BASE = 0xBA5E0000;
    uint256 internal constant PLAIN_WORD = uint256(keccak256("baf-staged-transcript")) | 1;

    function _level() internal pure virtual returns (uint24);

    function _word() internal pure virtual returns (uint256) {
        return PLAIN_WORD;
    }

    function _expectBaf() internal pure virtual override returns (bool) {
        return true;
    }

    /// @dev False leaves the final-day depositor draw empty (head slot 1 unfilled).
    function _armDraw() internal pure virtual returns (bool) {
        return true;
    }

    function _extraDigestAddrs() internal pure override returns (address[] memory players) {
        players = new address[](PLAYERS);
        for (uint256 i; i < PLAYERS; ++i) players[i] = address(PLAYER_BASE + uint160(i));
    }

    function _seedAndArm() internal override {
        uint24 target = _level();
        uint128 nextPool = 500 ether;
        uint128 futurePool = 550 ether;
        bytes memory original = address(game).code;
        vm.etch(address(game), type(PlainBafSeeder).runtimeCode);
        PlainBafSeeder(payable(address(game))).seed(target, nextPool, futurePool, PLAYERS, PLAYER_BASE);
        vm.etch(address(game), original);
        vm.deal(address(game), uint256(nextPool) + futurePool + 110 ether);
        mockStETH.mint(address(game), 50 ether);
        _armWord(_word());
        assertEq(game.level(), target, "the request pre-increments the level");
        for (uint256 i; i < PLAYERS; ++i) {
            vm.prank(ContractAddresses.COINFLIP);
            jackpots.recordBafFlip(address(PLAYER_BASE + uint160(i)), target, (i + 1) * 100 ether);
        }
        if (_armDraw()) {
            address[] memory depositors = new address[](16);
            for (uint256 i; i < 16; ++i) depositors[i] = address(PLAYER_BASE + uint160(i * 2));
            _armDepositDraw(depositors);
        }
    }
}

/// @notice Level 20 (10% pool): large winners take two-roll ticket halves, second places take
///         single rolls.
/// forge-config: default.fuzz.runs = 32
contract BafStagedTranscriptLevel20 is PlainBafTranscript {
    function _level() internal pure override returns (uint24) {
        return 20;
    }

    function _expectFarDrift() internal pure override returns (bool) {
        return true;
    }
}

/// @notice Level 50 (20% pool): the top winner's lootbox half defers to whale-pass halves.
/// forge-config: default.fuzz.runs = 32
contract BafStagedTranscriptLevel50 is PlainBafTranscript {
    function _level() internal pure override returns (uint24) {
        return 50;
    }
}

/// @notice Level 30 with nobody in the final-day depositor draw: head slot 1 (`bafHeadWinner`
///         slot 1) is empty, so its ETH term stays reserved through the stage and returns to the
///         pending future pool with the last group, identically under every partition.
/// forge-config: default.fuzz.runs = 32
contract BafStagedTranscriptEmptySlot is PlainBafTranscript {
    function _level() internal pure override returns (uint24) {
        return 30;
    }

    function _armDraw() internal pure override returns (bool) {
        return false;
    }

    function _expectFilled() internal pure override returns (bool) {
        return false;
    }

    function _score() internal override {
        assertEq(jackpots.bafHeadWinner(lvl, word, 1), address(0), "the empty depositor draw names nobody");
    }
}

/// @notice Level 20 with a losing flip: no award stage is armed, the bracket is marked skipped in
///         the consolidation call and the next call is the jackpot-phase daily.
/// forge-config: default.fuzz.runs = 32
contract BafStagedTranscriptSkip is PlainBafTranscript {
    function _level() internal pure override returns (uint24) {
        return 20;
    }

    function _word() internal pure override returns (uint256) {
        return PLAIN_WORD & ~uint256(1);
    }

    function _expectBaf() internal pure override returns (bool) {
        return false;
    }
}
