// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test, Vm} from "forge-std/Test.sol";
import {JackpotCheckpointHarness} from "./JackpotCheckpoints.t.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract TicketChunkHarness is JackpotCheckpointHarness {
    function bucketData(uint24 lvl, uint8 trait) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(_traitBufferBase(lvl) + trait)));
    }
    function owed(uint24 lvl, address player) external view returns (uint80) {
        return _entriesOwed(lvl > _mintCeiling() ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl), player);
    }
}

/// @dev One 128-winner early-bird quadrant (the largest ticket cap) splits into two fixed
///      64-award chunks. Caller gas only decides whether a chunk runs: the quadrant is drawn
///      at most twice, a stopped call reads none of the bucket, and every partition
///      reproduces the single-call winners, order, events and queued entries.
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
            assertTrue(winner == 0 || winner == CHUNK, "checkpoint sits on a chunk boundary");
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
        assertEq(CHUNK, 64);
        assertEq(bound, 9_830_000);
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
        emit log_named_uint("minimum allowance admitting one 64-award chunk", minimum);
        emit log_named_uint("bucket word reads per 128-winner draw", readsPerDraw);
        uint256 probe = vm.snapshotState();
        uint256[5] memory below = [uint256(MINER_MINIMUM), 2_000_000, 5_000_000, 9_000_000, minimum - 10_000];
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
            assertLe(run.drawCalls, (MAX_WINNERS + CHUNK - 1) / CHUNK, "drawn at most ceil(count / 64) times");
            assertEq(run.bucketReads, run.drawCalls * readsPerDraw, "bucket read only by whole draws");
            assertEq(run.basis, MAX_WINNERS);
            assertEq(_owedDigest(), owedOne, "queued entries match the single call");
            assertEq(h.pending(), 0);
            assertEq(stream, oneStream, "ordered events match the single call");
            if (sizes[s / 2] == minimum) assertEq(run.drawCalls, 2, "minimum calls split at the chunk boundary");
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
