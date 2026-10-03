// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test, Vm} from "forge-std/Test.sol";
import {JackpotCheckpointHarness} from "./JackpotCheckpoints.t.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {PackedTicketSampleLib} from "../../contracts/libraries/PackedTicketSampleLib.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";

contract TicketChunkHarness is JackpotCheckpointHarness {
    function bucketData(uint24 lvl, uint8 trait) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(_traitBufferBase(lvl) + trait)));
    }
    function owed(uint24 lvl, address player) external view returns (uint80) {
        return _entriesOwed(lvl > _mintCeiling() ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl), player);
    }
}

/// @dev One 128-winner early-bird quadrant (the largest ticket cap) is one fixed award chunk.
///      Caller gas only decides whether the chunk runs: the quadrant is drawn once, a stopped
///      call reads none of the bucket, and every partition reproduces the single-call
///      winners, order, events and queued entries.
contract JackpotTicketAwardChunksTest is Test {
    TicketChunkHarness private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    uint256 private constant MAX_WINNERS = 128;
    uint256 private constant CHUNK = GasBounds.JACKPOT_TICKET_AWARD_CHUNK;
    uint256 private constant MINER_MINIMUM = 1_000_000;
    bytes32 private constant TICKET_WIN = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");

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
        uint256 drawCalls;
        uint256 bucketReads;
        uint256 basis;
    }

    function setUp() public {
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

    /// @dev Drives to completion; `small` interleaves a miner-minimum call before each sized call.
    function _run(uint256 allowance, bool small) private returns (Run memory run) {
        while (run.calls < 12) {
            if (small) {
                (, , uint16 before,) = h.progress();
                Call memory s = _call(MINER_MINIMUM);
                (, , uint16 afterSmall,) = h.progress();
                assertEq(s.wins, 0, "minimum call awarded nothing");
                assertEq(s.bucketReads, 0, "minimum call stopped before drawing");
                assertEq(afterSmall, before, "minimum call kept the chunk checkpoint");
                if (s.done) return run;
            }
            Call memory c = _call(allowance);
            ++run.calls;
            run.bucketReads += c.bucketReads;
            run.basis += c.basis;
            assertEq(c.basis, c.wins, "reward basis counts awards");
            assertEq(c.wins % CHUNK, 0, "awards land in whole fixed chunks");
            (, , uint16 winner,) = h.progress();
            assertEq(winner, 0, "checkpoint sits on a quadrant boundary");
            if (c.wins != 0) {
                ++run.drawCalls;
                assertGt(c.bucketReads, 0);
            } else {
                assertEq(c.bucketReads, 0, "a call without awards never draws");
            }
            if (c.done) return run;
        }
        revert("ticket leg did not finish");
    }

    function _owedDigest() private view returns (bytes32 digest) {
        for (uint256 i; i < 600; ++i) {
            digest = keccak256(abi.encode(digest, h.owed(LVL, address(uint160(0x10000 + i)))));
        }
    }

    /// @dev Smallest allowance whose post-setup call runs a chunk (cold, one chunk only).
    function _minimumChunkAllowance() private returns (uint256 lo) {
        uint256 snap = vm.snapshotState();
        lo = 1_000_000;
        uint256 hi = 16_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            if (_call(mid).wins != 0) hi = mid;
            else lo = mid;
            assertTrue(vm.revertToState(snap));
        }
        lo = hi;
        snap = vm.snapshotState();
        assertEq(_call(lo).wins, CHUNK, "the minimum admitted call runs exactly one chunk");
        assertTrue(vm.revertToState(snap));
    }

    function test_DeclaredChunkBoundStaysBelowTenMillion() public pure {
        uint256 bound = 50_000 + MAX_WINNERS * GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX
            + CHUNK * GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX + GasBounds.JACKPOT_TAIL_GAS;
        assertEq(CHUNK, 128);
        assertGe(CHUNK, MAX_WINNERS, "no ticket quadrant splits across chunks");
        assertEq(bound, 6_527_600);
        assertLe(bound + MineFlipGas.CHECK_RESERVE, 10_000_000);
    }

    function test_QuadrantDrawnPerChunkAndTranscriptIndependentOfCallSize() public {
        uint256 snap = vm.snapshotState();
        stream = 0;
        Run memory one = _run(30_000_000, false);
        bytes32 oneStream = stream;
        assertEq(one.calls, 1, "one large call finishes the leg");
        assertEq(one.drawCalls, 1);
        assertEq(one.basis, MAX_WINNERS, "the concentrated quadrant holds the full 128-winner cap");
        uint256 readsPerDraw = one.bucketReads;
        assertGt(readsPerDraw, 0);
        bytes32 owedOne = _owedDigest();
        assertEq(h.pending(), 0);
        assertTrue(vm.revertToState(snap));

        // Setup first, at the miner minimum: the chunk is never admitted.
        Call memory setupCall = _call(MINER_MINIMUM);
        assertTrue(setupCall.progressed && setupCall.wins == 0 && setupCall.bucketReads == 0);
        uint256 minimum = _minimumChunkAllowance() + 5_000;
        emit log_named_uint("minimum allowance admitting one 128-award chunk", minimum);
        emit log_named_uint("bucket word reads per 128-winner draw", readsPerDraw);
        assertLt(minimum, 7_000_000, "a whole quadrant is admitted well below 10M");
        uint256 probe = vm.snapshotState();
        uint256[5] memory below = [uint256(MINER_MINIMUM), 2_000_000, 4_000_000, 6_000_000, minimum - 10_000];
        for (uint256 i; i < below.length; ++i) {
            Call memory b = _call(below[i]);
            assertTrue(b.wins == 0 && b.bucketReads == 0, "below the chunk bound nothing is drawn");
            assertTrue(vm.revertToState(probe));
        }
        uint256[5] memory sizes = [minimum, minimum + 3_000_000, 12_000_000, 17_000_000, 30_000_000];
        uint256 afterSetup = vm.snapshotState();
        bytes32 setupStream = stream;
        for (uint256 s; s < sizes.length * 2; ++s) {
            bool small = s % 2 == 1;
            stream = setupStream;
            Run memory run = _run(sizes[s / 2], small);
            assertEq(run.drawCalls, 1, "the whole quadrant is drawn exactly once");
            assertEq(run.bucketReads, run.drawCalls * readsPerDraw, "bucket read only by whole draws");
            assertEq(run.basis, MAX_WINNERS);
            assertEq(_owedDigest(), owedOne, "queued entries match the single call");
            assertEq(h.pending(), 0);
            assertEq(stream, oneStream, "ordered events match the single call");
            assertTrue(vm.revertToState(afterSetup));
        }
    }

    function test_MinimumCallsReproduceSingleCallWinnerTranscript() public {
        uint256 snap = vm.snapshotState();
        address[] memory expected = _winners(30_000_000);
        assertEq(expected.length, MAX_WINNERS);
        assertTrue(vm.revertToState(snap));
        _call(MINER_MINIMUM);
        uint256 minimum = _minimumChunkAllowance() + 5_000;
        address[] memory split = _winners(minimum);
        assertEq(keccak256(abi.encode(split)), keccak256(abi.encode(expected)), "ordered winners match");
    }

    function _winners(uint256 allowance) private returns (address[] memory winners) {
        winners = new address[](MAX_WINNERS);
        uint256 n;
        for (uint256 calls; calls < 12; ++calls) {
            vm.cool(address(h));
            vm.recordLogs();
            MineFlipGas.Result memory r = h.runEarlyBirdTickets{gas: allowance + 1_000_000}(WORD, allowance);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != TICKET_WIN) continue;
                (uint32 entries, uint24 source,, bool rounded) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
                assertEq(entries, 180);
                assertEq(source, LVL);
                assertFalse(rounded);
                winners[n++] = address(uint160(uint256(logs[i].topics[1])));
            }
            if (r.done) {
                assertEq(n, MAX_WINNERS);
                return winners;
            }
        }
        revert("ticket leg did not finish");
    }
}

contract TicketGasHarness is TicketChunkHarness {
    /// @dev Replays one quadrant draw as `_randTraitTicket` runs it; returns internal gas.
    function drawGas(uint24 lvl, uint256 entropy, uint8 trait, uint8 count, uint8 salt)
        external view returns (uint256 used, address[] memory winners)
    {
        uint256 g = gasleft();
        uint256 len = _bucketLength(lvl, trait);
        address deity = _traitDeity(trait);
        _assertReadableTicketLevel(lvl);
        uint256 effectiveLen = len + _deityVirtualCount(trait, len, deity);
        winners = new address[](count);
        uint256[] memory indexes = new uint256[](count);
        PackedTicketSampleLib.Cursor memory cursor;
        for (uint256 i; i < count; ++i) {
            (winners[i], indexes[i]) = _drawBucketEntry(lvl, trait, len, effectiveLen, deity, entropy, salt, i, cursor);
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
                _queueEntries(winner, queueLvl, entries, true);
                emit JackpotTicketWin(winner, queueLvl, traitId, entries, sourceLvl, i, false);
            }
        }
        used = g - gasleft();
    }

    /// @dev `live` leaves an owed lane at the write key (a top-up); otherwise only the pending
    ///      word exists, as it does for a holder whose earlier entries at this level were drained.
    function touchLanes(uint24 lvl, address[] calldata players, bool live) external {
        uint24 wk = _tqWriteKey(lvl);
        for (uint256 i; i < players.length; ++i) {
            if (live) _queueEntries(players[i], lvl, 4, true);
            else _setEntryOwed(wk, ticketOwnerId[players[i]], 0);
        }
    }

    function touchClaimable(uint160 base, uint256 count) external {
        for (uint256 i; i < count; ++i) balancesPacked[address(base + uint160(i + 1))] += 1;
    }

    function setDeity(uint8 trait, address deity) external {
        deityBySymbol[(trait >> 6) * 8 + (trait & 7)] = deity;
    }

    function seedMany(uint24 lvl, uint8 trait, uint256 count, uint160 base) external {
        _seedBucketClear(lvl, trait);
        _seedBucketDistinct(lvl, trait, count, base);
    }
}

/// @dev Cold measurements behind the ticket draw/award bounds. Realistic heavy: every winner's
///      pending word at the queue level is fresh (zero to nonzero) and the queue grows by fresh
///      words. Theoretical: additionally a deep distinct bucket, an unregistered deity winner,
///      and a padding redraw (one more cold word) for every winner.
contract JackpotTicketChunkGasTest is Test {
    TicketGasHarness private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    uint256 private constant N = 128;
    uint256 private constant INTRINSIC = 21_000;
    // One extra cold bucket word plus its redraw hash, per winner.
    uint256 private constant REDRAW_GAS = 2_500;
    // Registering an unregistered winner (a deity's virtual entry): 47.1k measured.
    uint256 private constant NEW_OWNER_GAS = 50_000;
    address private constant DEITY = address(0xDE17);
    uint8 private trait;

    function setUp() public {
        h = new TicketGasHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        h.seed(LVL, WORD, true);
        trait = JackpotBucketLib.getRandomTraits(WORD)[0];
    }

    function _declaredChunk() private pure returns (uint256) {
        return 50_000 + N * GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX
            + GasBounds.JACKPOT_TICKET_AWARD_CHUNK * GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX + GasBounds.JACKPOT_TAIL_GAS;
    }

    function _holders(uint256 count) private pure returns (address[] memory list) {
        list = new address[](count);
        for (uint256 i; i < count; ++i) list[i] = address(uint160(0x10000 + i + 1));
    }

    function _maxDraw() private returns (uint256 maxDraw) {
        for (uint256 s; s < 8; ++s) {
            vm.cool(address(h));
            (uint256 used,) = h.drawGas(LVL, uint256(keccak256(abi.encode(WORD, s))), trait, uint8(N), 239);
            if (used > maxDraw) maxDraw = used;
        }
    }

    function _award(address[] memory winners) private returns (uint256) {
        vm.cool(address(h));
        return h.awardGas(winners, LVL, 180, trait, LVL);
    }

    /// @return setupGas Cold setup call, including the transaction intrinsic.
    /// @return chunkGas Cold whole-quadrant call (plan, draw, 128 awards, final), including intrinsic.
    function _leg() private returns (uint256 setupGas, uint256 chunkGas) {
        vm.cool(address(h));
        uint256 g = gasleft();
        MineFlipGas.Result memory r = h.runEarlyBirdTickets{gas: 2_000_000}(WORD, 1_000_000);
        setupGas = g - gasleft() + INTRINSIC;
        assertTrue(r.progressed && r.rewardBasis == 0, "setup checkpoint awards nothing");
        vm.cool(address(h));
        g = gasleft();
        r = h.runEarlyBirdTickets{gas: 31_000_000}(WORD, 30_000_000);
        chunkGas = g - gasleft() + INTRINSIC;
        assertEq(r.rewardBasis, N, "one call pays the whole quadrant");
        assertTrue(r.done);
    }

    function test_MeasuredDrawAndAwardCostsFitTheirBounds() public {
        uint256 snap = vm.snapshotState();
        uint256 draw = _maxDraw();
        emit log_named_uint("draw per winner, 512-holder bucket", draw / N);
        assertLe(draw, N * GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX);

        address[] memory list = _holders(N);
        uint256 fresh = _award(list);
        emit log_named_uint("award per winner, fresh pending word (realistic heavy)", fresh / N);
        assertLe(fresh, N * GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX);
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

        h.seedMany(LVL, trait, 4096, 0x5000000);
        h.setDeity(trait, DEITY);
        uint256 deep = _maxDraw();
        emit log_named_uint("draw per winner, 4096-holder bucket with deity", deep / N);
        assertLe(deep, N * GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX);
        assertLe(deep + N * REDRAW_GAS + worst,
            N * (GasBounds.JACKPOT_TICKET_DRAW_GAS_MAX + GasBounds.JACKPOT_TICKET_AWARD_GAS_MAX),
            "theoretical draw and award stay inside the declared admission");
    }

    function test_RealisticChunkWithinTenMillionAndWorstBelowThirteenMillion() public {
        uint256 declared = _declaredChunk();
        emit log_named_uint("declared whole-quadrant chunk", declared);
        assertLe(declared + MineFlipGas.CHECK_RESERVE, 10_000_000);

        uint256 snap = vm.snapshotState();
        (uint256 setupGas, uint256 heavy) = _leg();
        emit log_named_uint("realistic heavy chunk tx, 128 fresh pending words", heavy);
        assertLe(heavy, 10_000_000, "realistic heavy chunk stays within 10M");
        assertTrue(vm.revertToState(snap));

        h.seedMany(LVL, trait, 4096, 0x5000000);
        h.setDeity(trait, DEITY);
        (uint256 deepSetup, uint256 deep) = _leg();
        if (deepSetup > setupGas) setupGas = deepSetup;
        uint256 worst = deep + N * REDRAW_GAS + NEW_OWNER_GAS;
        emit log_named_uint("deep distinct bucket with deity chunk tx", deep);
        emit log_named_uint("theoretical worst chunk tx (+ redraw per winner, + new owner)", worst);
        emit log_named_uint("theoretical worst with setup in the same tx", worst + setupGas - INTRINSIC);
        assertLt(worst + setupGas - INTRINSIC, 13_000_000, "theoretical worst stays below 13M");
        assertLe(worst - INTRINSIC, declared + GasBounds.JACKPOT_PLAN_GAS + GasBounds.JACKPOT_FINAL_GAS,
            "admission covers the theoretical worst chunk");
    }
}

/// @dev Cold measurements behind the ETH winner bound: four 512-holder quadrants at the daily
///      max scale (152/104/48/1 winners), every winner's claimable fresh, with pass conversions.
contract JackpotEthQuadrantGasTest is Test {
    TicketGasHarness private h;
    uint24 private constant LVL = 110;
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    uint256 private constant INTRINSIC = 21_000;
    uint256 private constant REDRAW_GAS = 2_500;
    uint256 private constant MAX_QUADRANT = 152;
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");

    function setUp() public {
        h = new TicketGasHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
        h.seed(LVL, WORD, false);
        h.seedDaily(LVL);
    }

    function _quadrantBound(uint256 count) private pure returns (uint256) {
        return 160_000 + count * GasBounds.JACKPOT_ETH_WINNER_GAS_MAX;
    }

    function _call(uint256 allowance) private returns (uint256 used, uint256 wins, bool done) {
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.recordLogs();
        uint256 g = gasleft();
        MineFlipGas.Result memory r = h.runDailyJackpot{gas: allowance + 1_000_000}(true, LVL, WORD, allowance);
        used = g - gasleft() + INTRINSIC;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == ETH_WIN) ++wins;
        done = r.done;
    }

    function test_EthQuadrantsFitBoundAndStayBelowLimits() public {
        (uint256 setupGas, uint256 none,) = _call(700_000);
        assertEq(none, 0, "setup checkpoint pays nothing");
        uint256[3] memory allowances = [uint256(6_500_000), 4_700_000, 2_400_000];
        uint256[3] memory expected = [uint256(152), 104, 49];
        uint256 perWinner;
        bool done;
        for (uint256 c; c < 3; ++c) {
            (uint256 used, uint256 wins, bool fin) = _call(allowances[c]);
            assertEq(wins, expected[c]);
            assertLe(used, 10_000_000);
            uint256 quadrants = c == 2 ? 2 : 1;
            assertLe(used - INTRINSIC, quadrants * 160_000 + wins * GasBounds.JACKPOT_ETH_WINNER_GAS_MAX
                + GasBounds.JACKPOT_PLAN_GAS + GasBounds.JACKPOT_TAIL_GAS, "admission covers the measured quadrant");
            if (c < 2 && used / wins > perWinner) perWinner = used / wins;
            emit log_named_uint("ETH quadrant call tx gas", used);
            emit log_named_uint("  winners", wins);
            done = fin;
        }
        assertTrue(done);
        emit log_named_uint("ETH per winner incl. quadrant fixed cost (realistic heavy)", perWinner);
        assertLe(perWinner, GasBounds.JACKPOT_ETH_WINNER_GAS_MAX);
        uint256 declared = _quadrantBound(MAX_QUADRANT) + GasBounds.JACKPOT_TAIL_GAS;
        emit log_named_uint("declared largest ETH quadrant", declared);
        assertLe(declared + MineFlipGas.CHECK_RESERVE, 10_000_000);
        uint256 worst = setupGas + MAX_QUADRANT * (perWinner + REDRAW_GAS) + 160_000;
        emit log_named_uint("theoretical worst ETH quadrant tx with setup", worst);
        assertLt(worst, 13_000_000);
    }
}
