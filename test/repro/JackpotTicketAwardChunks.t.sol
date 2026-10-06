// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {JackpotCheckpointHarness} from "./JackpotCheckpoints.t.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {PackedTicketSampleLib} from "../../contracts/libraries/PackedTicketSampleLib.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract TicketChunkHarness is JackpotCheckpointHarness {
    function bucketData(uint24 lvl, uint8 trait) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(_traitBufferBase(lvl) + trait)));
    }
    function owed(uint24 lvl, address player) external view returns (uint80) {
        return _owedOf(lvl > _mintCeiling() ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl), player);
    }
}

/// @dev One 192-winner early-bird quadrant, awarded in fixed groups of
///      eight. Caller gas only decides how many groups run: every partition reproduces the
///      single-call winners, order, events and queued entries, each group's bucket word is read
///      once across all calls, and a call that awards nothing reads none of the bucket.
contract JackpotTicketAwardChunksTest is Test {
    TicketChunkHarness private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    uint256 private constant MAX_WINNERS = 192;
    uint256 private constant CHUNK = GasBounds.JACKPOT_TICKET_AWARD_CHUNK;
    // Admits the plan (120k + tail) but never a group (393.6k + tail).
    uint256 private constant BELOW_GROUP = 400_000;
    // Admits setup (500k + tail); whether a group follows depends on setup's actual cost.
    uint256 private constant SETUP_CALL = 700_000;
    bytes32 private constant TICKET_WIN = keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)");

    uint256 private dataStart;
    bytes32 private stream;

    struct Call {
        bool progressed;
        bool done;
        uint256 basis;
        uint256 wins;
        uint256 bucketReads;
    }

    struct Run {
        uint256 calls;
        uint256 bucketReads;
        uint256 basis;
        bool midQuadrant;
    }

    function setUp() public {
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        h = new TicketChunkHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        h.seed(LVL, WORD, true);
        dataStart = h.bucketData(LVL, JackpotBucketLib.getRandomTraits(WORD)[0]);
    }

    function _call(uint256 allowance) private returns (Call memory c) {
        vm.cool(address(h));
        vm.record();
        vm.recordLogs();
        MineFlipGas.Result memory r = h.runEarlyBirdTickets{gas: allowance + 1_000_000}(WORD, allowance);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (bytes32[] memory reads,) = vm.accesses(address(h));
        (c.progressed, c.done, c.basis) = (r.progressed, r.done, r.rewardBasis);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == TICKET_WIN) ++c.wins;
            stream = keccak256(abi.encode(stream, logs[i].emitter, logs[i].topics, logs[i].data));
        }
        for (uint256 i; i < reads.length; ++i) {
            uint256 slot = uint256(reads[i]);
            if (slot >= dataStart && slot < dataStart + 64) ++c.bucketReads;
        }
    }

    /// @dev Drives to completion; `interleave` runs a below-group call before each sized call.
    function _run(uint256 allowance, bool interleave) private returns (Run memory run) {
        while (run.calls < 64) {
            if (interleave) {
                (, , uint16 before,) = h.progress();
                Call memory s = _call(BELOW_GROUP);
                (, , uint16 afterSmall,) = h.progress();
                assertEq(s.wins, 0, "below-group call awards nothing");
                assertEq(s.bucketReads, 0, "below-group call draws nothing");
                assertEq(afterSmall, before, "below-group call keeps the checkpoint");
                if (s.done) return run;
            }
            Call memory c = _call(allowance);
            ++run.calls;
            run.bucketReads += c.bucketReads;
            run.basis += c.basis;
            assertEq(c.basis, c.wins, "reward basis counts awards");
            assertEq(c.wins % CHUNK, 0, "awards land in whole groups");
            (, , uint16 winner,) = h.progress();
            assertEq(winner % CHUNK, 0, "checkpoint sits on a group start");
            if (winner != 0) run.midQuadrant = true;
            if (c.wins == 0) assertEq(c.bucketReads, 0, "a call without awards never draws");
            if (c.done) return run;
        }
        revert("ticket leg did not finish");
    }

    function _owedDigest() private view returns (bytes32 digest) {
        for (uint256 i; i < 600; ++i) {
            digest = keccak256(abi.encode(digest, h.owed(LVL, address(uint160(0x10000 + i)))));
        }
    }

    /// @dev Smallest allowance whose call runs a group (cold), from the current checkpoint.
    function _minimumGroupAllowance() private returns (uint256 lo) {
        uint256 snap = vm.snapshotState();
        lo = BELOW_GROUP;
        uint256 hi = 16_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            if (_call(mid).wins != 0) hi = mid;
            else lo = mid;
            assertTrue(vm.revertToState(snap));
        }
        lo = hi;
        snap = vm.snapshotState();
        assertEq(_call(lo).wins, CHUNK, "the minimum admitted call runs exactly one group");
        assertTrue(vm.revertToState(snap));
    }

    function test_DeclaredGroupBoundStaysBelowTenMillion() public pure {
        uint256 bound = CHUNK * (GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX + GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX)
            + GasBounds.JACKPOT_TAIL_GAS;
        assertEq(CHUNK, 8, "one sampler group per chunk");
        assertEq(MAX_WINNERS % CHUNK, 0);
        assertEq(bound, 573_600);
        assertLe(bound + MineFlipGas.CHECK_RESERVE, 10_000_000);
    }

    function test_GroupsDrawnOnceAndTranscriptIndependentOfCallSize() public {
        uint256 snap = vm.snapshotState();
        stream = 0;
        Run memory one = _run(30_000_000, false);
        bytes32 oneStream = stream;
        assertEq(one.calls, 1, "one large call finishes the leg");
        assertEq(one.basis, MAX_WINNERS, "the concentrated quadrant holds all 192 winners");
        uint256 readsOnce = one.bucketReads;
        assertGt(readsOnce, 0);
        bytes32 owedOne = _owedDigest();
        assertEq(h.pending(), 0);
        assertTrue(vm.revertToState(snap));

        // Setup checkpoint first (it may already pay a group), then the smallest group call.
        Call memory setup = _call(SETUP_CALL);
        assertTrue(setup.progressed);
        uint256 afterSetup = vm.snapshotState();
        bytes32 setupStream = stream;
        uint256 minimum = _minimumGroupAllowance();
        emit log_named_uint("minimum allowance admitting one 8-winner group", minimum);
        emit log_named_uint("bucket word reads for the whole 192-winner quadrant", readsOnce);
        assertLt(minimum, 1_000_000, "one group is admitted well below 1M");
        uint256[7] memory sizes = [minimum, minimum + 200_000, 1_500_000, 3_000_000, 5_000_000, 12_000_000, 30_000_000];
        for (uint256 s; s < sizes.length * 2; ++s) {
            stream = setupStream;
            Run memory run = _run(sizes[s / 2], s % 2 == 1);
            assertEq(setup.bucketReads + run.bucketReads, readsOnce, "every group's bucket word is read exactly once");
            assertEq(setup.basis + run.basis, MAX_WINNERS);
            if (sizes[s / 2] < 3_000_000) assertTrue(run.midQuadrant, "mid-quadrant checkpoints exercised");
            assertEq(_owedDigest(), owedOne, "queued entries match the single call");
            assertEq(h.pending(), 0);
            assertEq(stream, oneStream, "ordered events match the single call");
            assertTrue(vm.revertToState(afterSetup));
        }
    }

    function test_MinimumCallsReproduceSingleCallWinnerTranscript() public {
        uint256 snap = vm.snapshotState();
        address[] memory expected = new address[](MAX_WINNERS);
        (uint256 n, bool done) = _collect(30_000_000, expected, 0);
        assertTrue(done, "one large call finishes the leg");
        assertEq(n, MAX_WINNERS);
        assertTrue(vm.revertToState(snap));

        address[] memory split = new address[](MAX_WINNERS);
        (n, done) = _collect(SETUP_CALL, split, 0);
        uint256 groupsLeft = (MAX_WINNERS - n) / CHUNK;
        uint256 minimum = _minimumGroupAllowance();
        uint256 calls;
        while (!done) {
            assertLt(++calls, 64, "ticket leg did not finish");
            uint256 before = n;
            (n, done) = _collect(minimum, split, n);
            assertLe(n - before, CHUNK, "the minimum call pays at most one group");
        }
        assertEq(n, MAX_WINNERS);
        assertEq(keccak256(abi.encode(split)), keccak256(abi.encode(expected)), "ordered winners match");
        assertGe(calls, groupsLeft, "one group per minimum call");
        assertLe(calls, groupsLeft + 1, "at most one trailing completion call");
    }

    function _collect(uint256 allowance, address[] memory winners, uint256 n) private returns (uint256, bool) {
        vm.cool(address(h));
        vm.recordLogs();
        MineFlipGas.Result memory r = h.runEarlyBirdTickets{gas: allowance + 1_000_000}(WORD, allowance);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != TICKET_WIN) continue;
            (uint32 entries, uint24 source,, bool rounded) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
            assertEq(entries, 20);
            assertEq(source, LVL);
            assertFalse(rounded);
            winners[n++] = address(uint160(uint256(logs[i].topics[1])));
        }
        return (n, r.done);
    }
}

contract TicketGasHarness is TicketChunkHarness {
    event JackpotTicketWin(
        uint32 indexed walletId, uint24 indexed lvl, uint16 indexed trait,
        uint32 tickets, uint24 sourceLvl, uint256 entryIndex, bool roundedUp
    );

    /// @dev Replays positions [0, count) as `_resumeTicketWork` draws them; returns internal gas.
    function drawGas(uint24 lvl, uint256 entropy, uint8 trait, uint8 count, uint8 salt)
        external view returns (uint256 used, address[] memory winners)
    {
        uint256 g = gasleft();
        uint256 len = _bucketLength(lvl, trait);
        uint32 deity = _traitDeity(trait);
        _assertReadableTicketLevel(lvl);
        uint256 effectiveLen = len + _deityVirtualCount(trait, len, deity);
        winners = new address[](count);
        uint256[] memory indexes = new uint256[](count);
        PackedTicketSampleLib.Cursor memory cursor;
        for (uint256 i; i < count; ++i) {
            (uint32 winnerId, uint256 index) = _drawBucketEntry(lvl, trait, len, effectiveLen, deity, entropy, salt, i, cursor);
            (winners[i], indexes[i]) = (_walletKey(winnerId), index);
        }
        used = g - gasleft();
    }

    /// @dev Replays the award loop body of `_resumeTicketWork`; returns internal gas.
    function awardGas(address[] calldata winners, uint24 queueLvl, uint32 entries, uint16 traitId, uint24 sourceLvl)
        external returns (uint256 used)
    {
        uint256 g = gasleft();
        for (uint256 i; i < winners.length; ++i) {
            address winner = winners[i];
            if (winner != address(0)) {
                uint32 id = _seedWallet(winner);
                _queueEntries(id, queueLvl, entries, true);
                emit JackpotTicketWin(id, queueLvl, traitId, entries, sourceLvl, i, false);
            }
        }
        used = g - gasleft();
    }

    /// @dev `live` leaves an owed lane at the write key (a top-up); otherwise only the pending
    ///      word exists, as it does for a holder whose earlier entries at this level were drained.
    function touchLanes(uint24 lvl, address[] calldata players, bool live) external {
        uint24 wk = _tqWriteKey(lvl);
        for (uint256 i; i < players.length; ++i) {
            if (live) _queueEntries(_seedWallet(players[i]), lvl, 4, true);
            else _setEntryOwed(wk, _walletIdOf(players[i]), 0);
        }
    }

    function touchClaimable(uint160 base, uint256 count) external {
        for (uint256 i; i < count; ++i) balancesPacked[_seedWallet(address(base + uint160(i + 1)))] += 1;
    }

    function setDeity(uint8 trait, address deity) external {
        deityBySymbol[(trait >> 6) * 8 + (trait & 7)] = _seedWallet(deity);
    }

    function seedMany(uint24 lvl, uint8 trait, uint256 count, uint160 base) external {
        _seedBucketClear(lvl, trait);
        _seedBucketDistinct(lvl, trait, count, base);
    }
}

/// @dev Cold measurements behind the ticket draw/award bounds. Realistic heavy: every winner's
///      pending word at the queue level is fresh (zero to nonzero) and the queue grows by fresh
///      words. Theoretical: additionally a deep distinct bucket, an unregistered deity winner,
///      and a padding redraw (one more cold word) for every draw but a group's first.
contract JackpotTicketChunkGasTest is Test {
    TicketGasHarness private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    uint256 private constant N = 192;
    uint256 private constant CHUNK = GasBounds.JACKPOT_TICKET_AWARD_CHUNK;
    uint256 private constant INTRINSIC = 21_000;
    // One extra cold bucket word plus its redraw hash, per winner.
    uint256 private constant REDRAW_GAS = 2_500;
    // Registering an unregistered winner (a deity's virtual entry): 47.1k measured.
    uint256 private constant NEW_OWNER_GAS = 50_000;
    address private constant DEITY = address(0xDE17);
    uint256 private constant SETUP_CALL = 700_000;
    uint8 private trait;

    function setUp() public {
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        h = new TicketGasHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        h.seed(LVL, WORD, true);
        trait = JackpotBucketLib.getRandomTraits(WORD)[0];
    }

    function _groupBound() private pure returns (uint256) {
        return CHUNK * (GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX + GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX);
    }

    function _holders(uint256 count) private pure returns (address[] memory list) {
        list = new address[](count);
        for (uint256 i; i < count; ++i) list[i] = address(uint160(0x10000 + i + 1));
    }

    function _maxDraw(uint8 count) private returns (uint256 maxDraw) {
        for (uint256 s; s < 8; ++s) {
            vm.cool(address(h));
            (uint256 used,) = h.drawGas(LVL, uint256(keccak256(abi.encode(WORD, s))), trait, count, 239);
            if (used > maxDraw) maxDraw = used;
        }
    }

    function _award(address[] memory winners) private returns (uint256) {
        vm.cool(address(h));
        return h.awardGas(winners, LVL, 180, trait, LVL);
    }

    /// @return used Cold call gas including the transaction intrinsic.
    function _tx(uint256 allowance) private returns (uint256 used, MineFlipGas.Result memory r) {
        vm.cool(address(h));
        uint256 g = gasleft();
        r = h.runEarlyBirdTickets{gas: allowance + 1_000_000}(WORD, allowance);
        used = g - gasleft() + INTRINSIC;
    }

    /// @dev Smallest allowance that pays one group from the current checkpoint.
    function _minimumGroupAllowance() private returns (uint256 lo) {
        uint256 snap = vm.snapshotState();
        lo = 400_000;
        uint256 hi = 4_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            (, MineFlipGas.Result memory r) = _tx(mid);
            if (r.rewardBasis != 0) hi = mid;
            else lo = mid;
            assertTrue(vm.revertToState(snap));
        }
        lo = hi;
    }

    /// @dev Moves the leg to a mid-quadrant checkpoint, then measures one cold resumed group.
    /// @return used Cold resumed-group tx gas, including the intrinsic.
    /// @return allowance The smallest allowance admitting that group.
    function _resumedGroup() private returns (uint256 used, uint256 allowance) {
        _tx(SETUP_CALL);
        _tx(1_200_000);
        (, , uint16 winner,) = h.progress();
        assertGt(winner, 0, "checkpoint sits inside the quadrant");
        allowance = _minimumGroupAllowance();
        MineFlipGas.Result memory r;
        (used, r) = _tx(allowance);
        assertEq(r.rewardBasis, CHUNK, "the measured call pays exactly one group");
    }

    function test_MeasuredDrawAndAwardCostsFitTheirBounds() public {
        uint256 snap = vm.snapshotState();
        uint256 draw = _maxDraw(uint8(N));
        emit log_named_uint("draw per winner, 512-holder bucket", draw / N);
        assertLe(draw, N * GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX);
        uint256 groupDraw = _maxDraw(uint8(CHUNK));
        emit log_named_uint("draw of one cold group, 512-holder bucket", groupDraw);

        address[] memory list = _holders(N);
        uint256 fresh = _award(list);
        emit log_named_uint("award per winner, fresh pending word (realistic heavy)", fresh / N);
        assertLe(fresh, N * GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX);
        assertTrue(vm.revertToState(snap));
        address[] memory group = _holders(CHUNK);
        uint256 groupAward = _award(group);
        emit log_named_uint("award of one cold group, fresh pending words", groupAward);
        assertLe(groupDraw + groupAward, _groupBound(), "a cold realistic group fits its admission");
        assertTrue(vm.revertToState(snap));
        h.touchLanes(LVL, list, false);
        emit log_named_uint("award per winner, existing pending word", _award(list) / N);
        assertTrue(vm.revertToState(snap));
        h.touchLanes(LVL, list, true);
        emit log_named_uint("award per winner, live lane top-up", _award(list) / N);
        assertTrue(vm.revertToState(snap));
        list[N - 1] = DEITY;
        uint256 worst = _award(list);
        emit log_named_uint("award per winner, fresh plus one new owner", worst / N);
        assertLe(worst, N * GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX);
        assertLe(worst - fresh, NEW_OWNER_GAS);
        assertTrue(vm.revertToState(snap));
        group[CHUNK - 1] = DEITY;
        uint256 worstGroupAward = _award(group);
        assertTrue(vm.revertToState(snap));

        h.seedMany(LVL, trait, 4096, 0x5000000);
        h.setDeity(trait, DEITY);
        uint256 deep = _maxDraw(uint8(N));
        emit log_named_uint("draw per winner, 4096-holder bucket with deity", deep / N);
        assertLe(deep, N * GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX);
        uint256 deepGroup = _maxDraw(uint8(CHUNK));
        uint256 worstGroup = deepGroup + (CHUNK - 1) * REDRAW_GAS + worstGroupAward;
        emit log_named_uint("theoretical worst cold group (deep, deity, 7 redraws, new owner)", worstGroup);
        assertLe(worstGroup, _groupBound() + GasBounds.JACKPOT_TAIL_GAS,
            "the theoretical worst group stays inside its admission and tail");
    }

    function test_RealisticLegAndResumedGroupStayWithinBounds() public {
        uint256 snap = vm.snapshotState();
        (uint256 whole, MineFlipGas.Result memory r) = _tx(30_000_000);
        assertTrue(r.done && r.rewardBasis == N, "one call pays the whole leg");
        emit log_named_uint("realistic heavy whole leg in one tx (setup, 192 winners, final)", whole);
        assertLe(whole, 10_000_000, "the whole realistic leg fits one 10M tx");
        assertTrue(vm.revertToState(snap));

        (uint256 resumed, uint256 allowance) = _resumedGroup();
        emit log_named_uint("cold resumed one-group tx", resumed);
        emit log_named_uint("  smallest admitting allowance", allowance);
        assertLe(resumed - INTRINSIC, allowance, "the realistic resumed group spends inside its admission");
        assertTrue(vm.revertToState(snap));

        h.seedMany(LVL, trait, 4096, 0x5000000);
        h.setDeity(trait, DEITY);
        uint256 deepAllowance;
        (resumed, deepAllowance) = _resumedGroup();
        uint256 worst = resumed + (CHUNK - 1) * REDRAW_GAS + NEW_OWNER_GAS;
        emit log_named_uint("deep distinct bucket with deity, resumed one-group tx", resumed);
        emit log_named_uint("theoretical worst resumed group tx (+ 7 redraws, + new owner)", worst);
        assertLe(worst - INTRINSIC, deepAllowance + MineFlipGas.CHECK_RESERVE,
            "admission covers the theoretical worst resumed group");
        assertLt(worst, 13_000_000);
    }
}

/// @dev Cold measurements behind the ETH winner bound: four 512-holder quadrants on a large
///      jackpot day (hundreds of winners), every winner's claimable fresh, with pass conversions.
///      Quadrants pay in fixed eight-winner groups; a quadrant's first group carries its pass
///      conversion. Every partition reproduces the single-call transcript.
contract JackpotEthQuadrantGasTest is Test {
    TicketGasHarness private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    uint256 private constant INTRINSIC = 21_000;
    uint256 private constant REDRAW_GAS = 2_500;
    uint256 private constant CHUNK = GasBounds.JACKPOT_ETH_AWARD_CHUNK;
    uint256 private constant SETUP_CALL = 700_000;
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");

    bytes32 private stream;

    function setUp() public {
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        h = new TicketGasHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
        h.seed(LVL, WORD, false);
        h.seedDaily(LVL);
    }

    function _call(uint256 allowance) private returns (uint256 used, uint256 wins, bool done, bool progressed) {
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.recordLogs();
        uint256 g = gasleft();
        MineFlipGas.Result memory r = h.runDailyJackpot{gas: allowance + 1_000_000}(true, LVL, WORD, allowance);
        used = g - gasleft() + INTRINSIC;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == ETH_WIN) ++wins;
            stream = keccak256(abi.encode(stream, logs[i].topics, logs[i].data));
        }
        (done, progressed) = (r.done, r.progressed);
    }

    /// @dev Smallest allowance that pays a group from the current checkpoint.
    function _minimumGroupAllowance() private returns (uint256 lo) {
        uint256 snap = vm.snapshotState();
        lo = 300_000;
        uint256 hi = 6_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            (, uint256 wins,,) = _call(mid);
            if (wins != 0) hi = mid;
            else lo = mid;
            assertTrue(vm.revertToState(snap));
        }
        lo = hi;
    }

    function _accounts() private view returns (bytes32) {
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f) = h.accounting();
        return keccak256(abi.encode(a, b, c, d, e, f));
    }

    function test_DeclaredGroupBoundsStayBelowTenMillion() public pure {
        uint256 first = 160_000 + CHUNK * GasBounds.JACKPOT_ETH_WINNER_GAS_MAX + GasBounds.JACKPOT_TAIL_GAS;
        assertEq(CHUNK, 8, "one sampler group per chunk");
        assertEq(first, 636_000);
        assertLe(first + MineFlipGas.CHECK_RESERVE, 10_000_000);
    }

    function test_EthGroupsFitBoundsAndStayBelowLimits() public {
        (uint256 setupGas, uint256 none,,) = _call(SETUP_CALL);
        assertEq(none, 0, "setup checkpoint pays nothing");
        uint256 afterSetup = vm.snapshotState();

        (uint256 whole, uint256 all, bool done,) = _call(60_000_000);
        assertTrue(done);
        assertGt(all, 305, "more winners than the old 305 ceiling");
        emit log_named_uint("ETH winners on this day", all);
        emit log_named_uint("whole ETH leg in one tx after setup", whole);
        emit log_named_uint("ETH per winner incl. quadrant fixed costs (realistic heavy)", (whole - INTRINSIC) / all);
        assertLe((whole - INTRINSIC) / all, GasBounds.JACKPOT_ETH_WINNER_GAS_MAX);
        assertTrue(vm.revertToState(afterSetup));

        // First group of the largest quadrant, including its pass conversion.
        uint256 firstAllowance = _minimumGroupAllowance();
        (uint256 firstGas, uint256 firstWins,,) = _call(firstAllowance);
        assertEq(firstWins, CHUNK, "the minimum call pays exactly one group");
        (, , uint16 winner,) = h.progress();
        assertEq(winner, CHUNK, "checkpoint inside the quadrant");
        emit log_named_uint("cold first group tx (with pass conversion)", firstGas);
        emit log_named_uint("  smallest admitting allowance", firstAllowance);
        assertLe(firstGas - INTRINSIC, firstAllowance, "first group spends inside its admission");

        uint256 nextAllowance = _minimumGroupAllowance();
        (uint256 nextGas, uint256 nextWins,,) = _call(nextAllowance);
        assertEq(nextWins, CHUNK);
        emit log_named_uint("cold continuation group tx", nextGas);
        emit log_named_uint("  smallest admitting allowance", nextAllowance);
        uint256 worst = nextGas + CHUNK * REDRAW_GAS;
        emit log_named_uint("theoretical worst continuation group tx (+ 8 redraws)", worst);
        assertLe(worst - INTRINSIC, nextAllowance, "admission covers the theoretical worst group");
        assertLt(setupGas + firstGas + CHUNK * REDRAW_GAS, 13_000_000);
    }

    function test_EveryPartitionMatchesTheSingleCall() public {
        uint256 snap = vm.snapshotState();
        stream = 0;
        _call(SETUP_CALL);
        (, uint256 winners, bool done,) = _call(60_000_000);
        assertTrue(done);
        bytes32 expected = stream;
        bytes32 accounts = _accounts();
        assertTrue(vm.revertToState(snap));

        uint256[4] memory sizes = [uint256(0), 1_200_000, 2_500_000, 6_000_000];
        bool midQuadrant;
        for (uint256 s; s < sizes.length; ++s) {
            stream = 0;
            _call(SETUP_CALL);
            uint256 allowance = sizes[s] == 0 ? _minimumGroupAllowance() : sizes[s];
            uint256 paid;
            done = false;
            for (uint256 calls; !done; ++calls) {
                assertLt(calls, 256, "ETH leg did not finish");
                uint256 wins;
                bool progressed;
                (, wins, done, progressed) = _call(allowance);
                assertTrue(progressed, "every sized call makes progress");
                paid += wins;
                (, , uint16 winner,) = h.progress();
                assertEq(winner % CHUNK, 0, "checkpoint sits on a group start");
                if (winner != 0) midQuadrant = true;
            }
            assertEq(paid, winners);
            assertEq(stream, expected, "ordered winners, amounts and pass awards match");
            assertEq(_accounts(), accounts, "pools and liabilities match");
            assertTrue(vm.revertToState(snap));
        }
        assertTrue(midQuadrant, "mid-quadrant checkpoints exercised");
    }
}
