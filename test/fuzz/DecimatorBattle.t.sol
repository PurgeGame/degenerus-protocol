// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecimatorBattleHarness} from "./helpers/DecimatorBattleHarness.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";
import {DecimatorSampleReference as Sample} from "../helpers/DecimatorSamplingReference.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Makes ranking tests cheap while asserting the exact engine inputs. The real engine
///      is separately exercised by shared-dice replay, batching and gas tests.
contract DecimatorEngineProbe {
    function settleSlipBounded(
        uint256 chips,
        uint256 chip,
        uint256 board,
        uint256 count,
        bytes32,
        uint256 bankroll,
        uint256,
        uint256 boost,
        uint256 bounds
    ) external pure returns (Craps.SlipResult memory r) {
        uint256 named;
        for (uint256 i; i < 30; i += 3) named += (chips >> i) & 7;
        require(chip == 60 && count == 10 - named && bankroll == 3000e18 && bounds == (511 << 16 | 48));
        // The normal battles' shooter-boost row (Craps._shooterBoostTerms).
        require(boost == (0x050c070c0a0c0e0c120c140c190c1e0c >> (named << 4)) & 0xFFFF);
        r.peakBankroll = bankroll + board % (1_000_000e18);
        r.totalRolls = 30;
    }
}

/// @dev Every run peaks exactly at the starting bankroll, so equal stacks tie and ranking falls
///      through to the random tiebreak.
contract DecimatorFlatProbe {
    function settleSlipBounded(uint256 chips, uint256 chip, uint256, uint256 count, bytes32, uint256 bankroll, uint256, uint256, uint256)
        external
        pure
        returns (Craps.SlipResult memory r)
    {
        require(chips == 0 && chip == 60 && count == 10 && bankroll == 3000e18);
        r.peakBankroll = bankroll;
        r.totalRolls = 30;
    }
}

contract DecimatorBattleTest is Test {
    DecimatorBattleHarness internal h;
    uint24 internal constant LVL = 5;
    bytes32 internal constant DICE = keccak256("decimator.battle.dice.v1");
    bytes32 internal constant BOARD = keccak256("decimator.battle.board.v1");
    bytes32 internal constant TIE = keccak256("decimator.battle.tie.v1");

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        h = new DecimatorBattleHarness();
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(CrapsEngine).runtimeCode);
        h.open(LVL);
    }

    function _burn(DecimatorBattleHarness target, address p, uint24 lvl, uint256 amount, uint256 mult)
        internal
        returns (uint64)
    {
        vm.prank(ContractAddresses.COIN);
        return target.recordDecBurn(p, lvl, amount, mult, 0);
    }

    function _sampled(uint256 word, uint24 lvl, uint64 id, uint256 total) internal pure returns (bool) {
        return Sample.contains(word, lvl, total, id);
    }

    /// @dev Drive the live decimator worker (mineFlip's Decimator stage) with all remaining gas
    ///      per call until the queue empties.
    function _drain(DecimatorBattleHarness target) internal {
        for (uint256 i; uint24(target.queue()) != 0 && i < 4000; ++i) {
            target.runDecimatorWork(gasleft());
        }
        assertEq(uint24(target.queue()), 0, "settlement terminated");
    }

    function _populate(DecimatorBattleHarness target, uint24 lvl, uint64 n) internal {
        for (uint64 i = 1; i <= n; ++i) {
            _burn(target, address(uint160(i)), lvl, (uint256(i) + 1) * 1000, 10_000);
        }
    }

    function _probe() internal {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorEngineProbe).runtimeCode);
    }

    function _assertLockedSettlementIsIdle(DecimatorBattleHarness target) internal {
        DegenerusGameStorage.DecBattleRound memory beforeRound = target.roundOf(LVL);
        MineFlipGas.Result memory r = target.runDecimatorWork(gasleft());
        assertEq(r.rewardBasis, 0);
        assertFalse(r.progressed);
        DegenerusGameStorage.DecBattleRound memory afterRound = target.roundOf(LVL);
        assertEq(afterRound.cursor, beforeRound.cursor, "daily lock preserves the run cursor");
        assertEq(afterRound.phase, beforeRound.phase, "daily lock preserves the phase");
        assertEq(afterRound.paid, beforeRound.paid, "daily lock preserves the payment cursor");
    }

    function test_DegenAnchorsAndCap() public pure {
        assertEq(ActivityCurveLib.decBattleMultBps(0), 10_000);
        assertEq(ActivityCurveLib.decBattleMultBps(235), 17_049);
        assertEq(ActivityCurveLib.decBattleMultBps(500), 19_000);
        assertEq(ActivityCurveLib.decBattleMultBps(30_000), 20_000);
        assertEq(ActivityCurveLib.decBattleMultBps(type(uint256).max), 20_000);
    }

    function testFuzz_DegenMonotonic(uint16 score) public pure {
        assertGe(ActivityCurveLib.decBattleMultBps(uint256(score) + 1), ActivityCurveLib.decBattleMultBps(score));
    }

    function test_TopupsPreserveEarlyCreditAndUseCurrentMultiplier() public {
        assertEq(_burn(h, address(1), LVL, 1_000_000, 19_000), 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertEq(_burn(h, address(1), LVL, 1_000_000, 20_000), 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _burn(h, address(1), LVL, 1_000_000, 10_000);
        DecimatorBattleHarness.Entry memory e = h.entryOf(LVL, 1);
        assertEq(e.stack, 4_510_000);
        assertEq(h.roundOf(LVL).count, 1);
    }

    function test_FirstBurnDoesNotStartClockAndNoOld500kCap() public {
        vm.warp(vm.getBlockTimestamp() + 3 days);
        _burn(h, address(1), LVL, 10_000_000, 20_000);
        assertEq(h.entryOf(LVL, 1).stack, 14_580_000);
    }

    function test_ResetBoundary() public {
        vm.warp(vm.getBlockTimestamp() + 1 days - 2);
        _burn(h, address(1), LVL, 1000, 10_000);
        vm.warp(vm.getBlockTimestamp() + 1);
        _burn(h, address(2), LVL, 1000, 10_000);
        assertEq(h.entryOf(LVL, 1).stack, 1000);
        assertEq(h.entryOf(LVL, 2).stack, 900);
    }

    function test_RecordAccessAndSealGuards() public {
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL, 1000, 10_000, 0);
        vm.startPrank(ContractAddresses.COIN);
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL + 1, 1000, 10_000, 0);
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL, 1000, 20_001, 0);
        vm.expectRevert();
        h.recordDecBurn(address(0), LVL, 1000, 10_000, 0);
        vm.stopPrank();
        _burn(h, address(1), LVL, 1000, 10_000);
        vm.expectRevert();
        h.runDecimatorJackpot(1 ether, LVL, 123);
        h.seal(LVL, 1 ether, 123);
        vm.prank(ContractAddresses.COIN);
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL, 1000, 10_000, 0);
        assertEq(h.seal(LVL, 1 ether, 456), 1 ether);
        assertEq(h.activeWord(), 123);
        assertEq(h.reserved(), 1 ether);
    }

    function test_EmptyRoundReturnsPool() public {
        assertEq(h.seal(LVL, 100 ether, 123), 100 ether);
        assertEq(h.reserved(), 0);
        assertEq(uint24(h.queue()), 0);
    }

    function test_SingleSurvivorGetsEverythingAndNoDoublePay() public {
        _burn(h, address(1), LVL, 1000, 10_000);
        _burn(h, address(2), LVL, 1000, 10_000);
        uint256 word = 2;
        while (!_sampled(word, LVL, 1, h.roundOf(LVL).count) || _sampled(word, LVL, 2, h.roundOf(LVL).count)) ++word;
        h.seal(LVL, 13 ether + 17, word);
        h.freeze(true);
        _assertLockedSettlementIsIdle(h);
        assertEq(h.reserved(), 13 ether + 17, "daily lock retains the full reservation");
        h.freeze(false);
        _drain(h);
        // The champion: half in whole half passes (6.5 ETH buys two), the rest ETH.
        assertEq(h.passesOf(address(1)), 2);
        assertEq(h.balanceOf(address(1)), 13 ether + 17 - 2 * 2.25 ether);
        assertEq(h.reserved(), 13 ether + 17 - 2 * 2.25 ether);
        assertEq(h.future(), 2 * 2.25 ether, "pass money recycles after daily work unlocks");
        assertEq(h.pendingFuture(), 0);
        MineFlipGas.Result memory r = h.runDecimatorWork(gasleft());
        assertEq(r.rewardBasis, 0);
        assertFalse(r.progressed);
    }

    function test_SmallSampledRoundSimulatesRanksAndPaysInOneCall() public {
        _burn(h, address(1), LVL, 1000, 10_000);
        _burn(h, address(2), LVL, 1000, 10_000);
        uint256 word = 2;
        while (!_sampled(word, LVL, 1, h.roundOf(LVL).count) || _sampled(word, LVL, 2, h.roundOf(LVL).count)) ++word;
        h.seal(LVL, 13 ether + 17, word);

        MineFlipGas.Result memory result = h.runDecimatorWork{gas: 2_000_000}(1_900_000);

        assertTrue(result.progressed);
        assertTrue(result.done, "one worker call drains the small round");
        assertEq(result.rewardBasis, 3, "one sampled run, one ranking and one payment");
        DegenerusGameStorage.DecBattleRound memory round = h.roundOf(LVL);
        assertEq(round.cursor, 1);
        assertEq(round.phase, 3);
        assertEq(round.champion, 1);
        assertEq(round.paid, 1);
        assertEq(h.queue(), 0, "the read cohort no longer waits on decimator");
        assertEq(h.passesOf(address(1)), 2);
        assertEq(h.balanceOf(address(1)), 13 ether + 17 - 2 * 2.25 ether);
        assertEq(h.reserved() + h.future(), 13 ether + 17);
    }

    function test_InsufficientRunGasCheckpointsWithoutChangingTranscript() public {
        _burn(h, address(1), LVL, 1000, 10_000);
        h.seal(LVL, 7 ether, 777);
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs();
        _drain(h);
        bytes32 fullTranscript = _transcript(h, vm.getRecordedLogs());
        bytes32 fullState = _settledState(h);
        assertTrue(vm.revertToState(snapshot));
        vm.recordLogs();
        MineFlipGas.Result memory refused = h.runDecimatorWork{gas: 200_000}(200_000);
        assertFalse(refused.progressed);
        assertEq(h.roundOf(LVL).cursor, 0);
        assertEq(h.reserved(), 7 ether);
        _drain(h);
        assertEq(_transcript(h, vm.getRecordedLogs()), fullTranscript);
        assertEq(_settledState(h), fullState);
    }

    function test_DailyLockDefersZeroQuotaReserveRelease() public {
        _burn(h, address(1), LVL, 1000, 10_000);
        uint256 word = 2;
        h.seal(LVL, 7 ether, word);
        h.freeze(true);
        _assertLockedSettlementIsIdle(h);
        assertEq(h.reserved(), 7 ether, "locked stage retains the reservation");
        h.freeze(false);
        _drain(h);
        assertEq(h.balanceOf(address(1)), 0);
        assertEq(h.roundOf(LVL).winners, 0);
        assertEq(h.reserved(), 0);
        assertEq(h.pendingFuture(), 0);
        assertEq(h.future(), 7 ether);
    }

    /// @dev Only the sampled slot is visited, even when the unsampled entry was recorded first.
    function test_UnsampledEntriesNeverRun() public {
        _probe();
        _populate(h, LVL, 2);
        uint256 word = 2;
        while (Sample.contains(word, LVL, 2, 1)) ++word;
        h.seal(LVL, 5 ether, word);
        vm.recordLogs();
        _drain(h);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 runs;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("DecimatorRun(uint24,uint64,uint256)")) continue;
            ++runs;
            assertEq(uint64(uint256(logs[i].topics[2])), 2);
        }
        assertEq(runs, 1);
        assertEq(h.roundOf(LVL).cursor, 1);
        assertEq(h.roundOf(LVL).champion, 2);
        assertEq(h.balanceOf(address(1)), 0);
    }

    /// @dev Game over stops settlement: the queued round keeps its reservation for the final sweep.
    function test_SettlementIdlesAfterGameOver() public {
        _probe();
        _populate(h, LVL, 4);
        h.seal(LVL, 3 ether, 11);
        h.terminal();
        MineFlipGas.Result memory r = h.runDecimatorWork(gasleft());
        assertEq(r.rewardBasis, 0);
        assertFalse(r.progressed);
        assertEq(uint24(h.queue()), LVL);
        assertEq(h.roundOf(LVL).cursor, 0);
        assertEq(h.reserved(), 3 ether);
    }

    function test_RoundsCannotOverlapAndHistoricalEntriesRemain() public {
        _probe();
        _populate(h, LVL, 4);
        h.seal(LVL, 3 ether, 11);
        h.open(15);
        _populate(h, 15, 3);
        vm.expectRevert();
        h.seal(15, 4 ether, 22);
        assertEq(uint24(h.queue()), LVL);
        assertEq(uint24(h.queue() >> 24), LVL);
        assertEq(h.roundOf(LVL).next, 0);
        assertEq(h.activeWord(), 11);
        _drain(h);
        assertEq(h.roundOf(LVL).phase, 3);
        h.seal(15, 4 ether, 22);
        _drain(h);
        assertEq(h.roundOf(15).phase, 3);
        assertEq(h.entryOf(LVL, 1).stack, 2000);
        assertEq(h.entryOf(15, 1).stack, 2000);
    }

    function test_BatchesHaveIdenticalRealDiceAndPayouts() public {
        DecimatorBattleHarness other = new DecimatorBattleHarness();
        other.open(LVL);
        _populate(h, LVL, 31);
        _populate(other, LVL, 31);
        uint256 word = type(uint256).max - 77;
        h.seal(LVL, 13 ether + 77, word);
        other.seal(LVL, 13 ether + 77, word);
        // Bounded-gas chunks against one all-gas pass: the supplied gas never moves the outcome.
        _drainWithGas(h, 1_000_000);
        _drain(other);
        assertEq(abi.encode(h.roundOf(LVL)), abi.encode(other.roundOf(LVL)));
        for (uint8 i; i < h.roundOf(LVL).winners; ++i) {
            assertEq(abi.encode(h.nodeOf(LVL, i)), abi.encode(other.nodeOf(LVL, i)));
        }
        for (uint160 i = 1; i <= 31; ++i) {
            assertEq(h.balanceOf(address(i)), other.balanceOf(address(i)));
        }
    }

    function _drainWithGas(DecimatorBattleHarness target, uint256 callGas)
        internal returns (uint256 calls, bytes32 transcript)
    {
        vm.recordLogs();
        while (target.queue() != 0 && calls < 200) {
            vm.cool(address(target));
            vm.cool(ContractAddresses.CRAPS_ENGINE);
            MineFlipGas.Result memory result = target.runDecimatorWork{gas: callGas}(callGas);
            assertTrue(result.progressed, "funded call advances an atomic obligation");
            ++calls;
        }
        assertEq(target.queue(), 0, "native worker completes");
        transcript = _transcript(target, vm.getRecordedLogs());
    }

    function _transcript(DecimatorBattleHarness target, Vm.Log[] memory logs)
        internal pure returns (bytes32 transcript)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(target)) {
                transcript = keccak256(abi.encode(transcript, logs[i].topics, logs[i].data));
            }
        }
    }

    function test_SuppliedGasPartitionsPreserveRealDiceTranscriptAndPayouts() public {
        _populate(h, LVL, 31);
        h.seal(LVL, 13 ether + 77, type(uint256).max - 77);
        uint256 snapshot = vm.snapshotState();
        (uint256 fullCalls, bytes32 fullTranscript) = _drainWithGas(h, 15_000_000);
        bytes32 fullState = _settledState(h);
        assertTrue(vm.revertToState(snapshot));
        (uint256 splitCalls, bytes32 splitTranscript) = _drainWithGas(h, 1_000_000);
        assertGt(splitCalls, fullCalls, "actual supplied gas creates additional checkpoints");
        assertEq(splitTranscript, fullTranscript, "ordered runs, ranking and payouts are unchanged");
        assertEq(_settledState(h), fullState, "all winners, balances and reservations are unchanged");
    }

    function _settledState(DecimatorBattleHarness target) internal view returns (bytes32 digest) {
        DegenerusGameStorage.DecBattleRound memory round = target.roundOf(LVL);
        digest = keccak256(abi.encode(round, target.future(), target.reserved()));
        for (uint8 i; i < round.winners; ++i) digest = keccak256(abi.encode(digest, target.nodeOf(LVL, i)));
        for (uint160 i = 1; i <= 31; ++i) {
            digest = keccak256(abi.encode(digest, target.balanceOf(address(i)), target.passesOf(address(i))));
        }
    }

    function test_RealEngineReplayUsesSharedDiceAndAbsolutePeak() public {
        _populate(h, LVL, 16);
        uint256 word = uint256(keccak256("decimator replay"));
        h.seal(LVL, 10 ether, word);
        _drain(h);
        DegenerusGameStorage.DecBattleRound memory round = h.roundOf(LVL);
        bytes32 seed = keccak256(abi.encode(DICE, word, LVL));
        for (uint8 i; i < round.winners; ++i) {
            DecimatorBattleHarness.Node memory node = h.nodeOf(LVL, i);
            uint64 id = uint64(node.key);
            assertTrue(_sampled(word, LVL, id, h.roundOf(LVL).count));
            Craps.SlipResult memory run = CrapsEngine(ContractAddresses.CRAPS_ENGINE)
                .settleSlipBounded(
                    0,
                    60,
                    uint256(keccak256(abi.encode(BOARD, word, LVL, id))),
                    10,
                    seed,
                    3000e18,
                    // The production salt: the entry's committed wallet ID (low 32 bits).
                    uint256(uint32(uint160(h.entryOf(LVL, id).owner))),
                    (30 << 8) | 12,
                    (511 << 16) | 48
                );
            assertEq(node.score, h.entryOf(LVL, id).stack / 1 * run.peakBankroll);
            assertGe(run.peakBankroll, 3000e18);
        }
    }

    function test_200WinnerCapExactPayoutAndOnlySampledIdsOnBoard() public {
        _probe();
        _populate(h, LVL, 2000);
        h.seal(LVL, 100 ether + 3, 777);
        _drain(h);
        DegenerusGameStorage.DecBattleRound memory round = h.roundOf(LVL);
        assertEq(round.capacity, 200);
        assertEq(round.winners, 200);
        uint256 pool = 100 ether + 3;
        uint256 base = (pool - pool / 20) / 200;
        uint256 champ = pool - base * 199; // 5.475 ETH: half buys one half pass
        uint256 perEth = 0; // shares of 0.475 ETH buy no pass, so nobody else takes passes
        assertEq(uint64(h.nodeOf(LVL, 0).key), round.champion, "champion paid from position 0");
        assertEq(h.passesOf(address(uint160(round.champion))), 1);
        assertEq(h.balanceOf(address(uint160(round.champion))), champ - 2.25 ether);
        uint256 sum = champ - 2.25 ether;
        for (uint8 i = 1; i < 200; ++i) {
            uint64 id = uint64(h.nodeOf(LVL, i).key);
            assertTrue(_sampled(777, LVL, id, h.roundOf(LVL).count));
            uint256 amount = h.balanceOf(address(uint160(id)));
            assertEq(amount, base + perEth, "equal ETH share plus the champion's leftover split");
            sum += amount;
        }
        assertEq(sum + h.future(), pool, "only the pass money recycles to future");
        sum += 2.25 ether; // for the checks below
        assertEq(sum, 100 ether + 3);
        // Every excluded eligible entry is weaker than the weakest retained one (ranking moved the
        // champion to position 0, so the minimum is found by scan).
        DecimatorBattleHarness.Node memory root = h.nodeOf(LVL, 0);
        for (uint8 i = 1; i < 200; ++i) {
            DecimatorBattleHarness.Node memory node = h.nodeOf(LVL, i);
            if (node.score < root.score) root = node;
        }
        for (uint64 id = 1; id <= 2000; ++id) {
            if (!_sampled(777, LVL, id, h.roundOf(LVL).count) || h.balanceOf(address(uint160(id))) != 0 || id == round.champion) continue;
            uint256 peak = 3000 + uint256(keccak256(abi.encode(BOARD, uint256(777), LVL, id))) % (1_000_000);
            assertLe(h.entryOf(LVL, id).stack / 1 * peak, root.score);
        }
    }

    function test_UnsampledHighStackNeverOccupiesPlace() public {
        _probe();
        uint256 word = 2;
        while (_sampled(word, LVL, 1, 2) || !_sampled(word, LVL, 2, 2)) ++word;
        _burn(h, address(1), LVL, uint256(type(uint64).max) - 1000, 10_000);
        _burn(h, address(2), LVL, 1000, 10_000);
        h.seal(LVL, 1 ether, word);
        _drain(h);
        assertEq(h.roundOf(LVL).champion, 2);
        assertEq(h.balanceOf(address(1)), 0);
        assertEq(h.balanceOf(address(2)), 1 ether);
    }

    /// @dev The battle board rules: three per leg, seven named, one side of the line, thirty bits.
    function test_BoardRulesMatchNormalBattles() public {
        uint32[5] memory bad = [
            uint32(4),                  // four chips on the pass line
            uint32(3 | 3 << 3 | 2 << 6), // eight named chips
            uint32(1 | 1 << 27),        // pass and don't pass together
            uint32(1 << 30),            // outside the thirty chip bits
            uint32(3 << 3 | 3 << 6 | 3 << 9) // nine named chips
        ];
        vm.startPrank(ContractAddresses.COIN);
        for (uint256 i; i < bad.length; ++i) {
            vm.expectRevert();
            h.recordDecBurn(address(1), LVL, 1000, 10_000, bad[i]);
        }
        uint32 seven = 3 | 3 << 3 | 1 << 6;
        h.recordDecBurn(address(1), LVL, 1000, 10_000, seven);
        assertEq(h.entryOf(LVL, 1).chips, seven);
        // A later burn sets the board; the stack keeps accumulating.
        h.recordDecBurn(address(1), LVL, 1000, 10_000, 1 << 27);
        vm.stopPrank();
        assertEq(h.entryOf(LVL, 1).chips, 1 << 27);
        assertEq(h.entryOf(LVL, 1).stack, 2000);
    }

    /// @dev A chosen board reaches the engine with the scatter count and boost row for its size.
    function test_ChosenBoardDrivesTheRun() public {
        _probe();
        uint256 word = 2;
        while (!_sampled(word, LVL, 1, 2) || _sampled(word, LVL, 2, 2)) ++word;
        vm.prank(ContractAddresses.COIN);
        h.recordDecBurn(address(1), LVL, 1000, 10_000, 2 | 3 << 12 | 1 << 21);
        _burn(h, address(2), LVL, 1000, 10_000);
        h.seal(LVL, 1 ether, word);
        _drain(h); // the probe reverts unless chips, scatter count and boost all match
        assertEq(h.balanceOf(address(1)), 1 ether);
    }

    function _tieKey(uint256 word, uint24 lvl, uint64 id) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encode(TIE, word, lvl, id))) & ~uint256(type(uint64).max)) | id;
    }

    /// @dev Equal scores: two higher stacks and 38 sampled equal-stack entries contest 20 places.
    ///      The cutoff and first place both resolve by the tiebreak, identically at any batch size,
    ///      and every retained node reports the key the Lens derives.
    function test_EqualScoresRankByTiebreakAtCutoffAndFirst() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorFlatProbe).runtimeCode);
        DecimatorBattleHarness other = new DecimatorBattleHarness();
        other.open(LVL);
        uint256 word = 2;
        while (!Sample.contains(word, LVL, 80, 1) || !Sample.contains(word, LVL, 80, 2)) ++word;
        for (uint160 i = 1; i <= 80; ++i) {
            uint256 amount = i <= 2 ? 2000 : 1000;
            _burn(h, address(i), LVL, amount, 10_000);
            _burn(other, address(i), LVL, amount, 10_000);
        }
        h.seal(LVL, 4 ether, word);
        other.seal(LVL, 4 ether, word);
        _drainWithGas(h, 1_000_000);
        _drain(other);
        assertEq(h.roundOf(LVL).capacity, 20);
        assertEq(h.roundOf(LVL).winners, 20);
        uint64 first = _tieKey(word, LVL, 1) > _tieKey(word, LVL, 2) ? 1 : 2;
        assertEq(h.roundOf(LVL).champion, first);
        uint256[38] memory keys;
        uint256 used;
        for (uint64 id = 3; id <= 80; ++id) if (Sample.contains(word, LVL, 80, id)) {
            uint256 key = _tieKey(word, LVL, id);
            uint256 at = used++;
            while (at != 0 && keys[at - 1] < key) { keys[at] = keys[at - 1]; --at; }
            keys[at] = key;
        }
        assertEq(used, 38);
        bool[81] memory placed;
        for (uint8 i; i < 20; ++i) {
            DecimatorBattleHarness.Node memory node = h.nodeOf(LVL, i);
            uint64 id = uint64(node.key);
            assertEq(node.key, _tieKey(word, LVL, id));
            assertEq(abi.encode(node), abi.encode(other.nodeOf(LVL, i)), "partition invariant heap");
            placed[id] = true;
        }
        assertTrue(placed[1] && placed[2]);
        for (uint256 i; i < 38; ++i) assertEq(placed[uint64(keys[i])], i < 18);
        uint256 base = (4 ether - 4 ether / 20) / 20;
        assertEq(h.balanceOf(address(uint160(first))), 4 ether - base * 19);
        assertEq(h.balanceOf(address(uint160(uint64(keys[0])))), base);
    }

    function _runPhaseUnits(DecimatorBattleHarness target, uint24 lvl) internal returns (uint256 units) {
        while (target.roundOf(lvl).phase == 1 && target.roundOf(lvl).cursor < Sample.count(target.roundOf(lvl).count)) {
            uint256 g0 = gasleft();
            target.runDecimatorWork(gasleft());
            units += g0 - gasleft();
        }
    }

    /// @dev A later round reuses the leaderboard slots an earlier round filled: stale nodes never
    ///      reach its results, and its filling inserts are charged the reused price.
    function test_LaterRoundReusesLeaderboardSlots() public {
        _probe();
        _populate(h, LVL, 40); // up to twenty places
        h.seal(LVL, 4 ether, 11);
        _drain(h);
        DecimatorBattleHarness fresh = new DecimatorBattleHarness();
        h.open(15);
        fresh.open(15);
        for (uint160 i = 1; i <= 25; ++i) { // three places
            _burn(h, address(i + 1000), 15, (uint256(i) + 1) * 1000, 10_000);
            _burn(fresh, address(i + 1000), 15, (uint256(i) + 1) * 1000, 10_000);
        }
        h.seal(15, 3 ether + 1, 22);
        fresh.seal(15, 3 ether + 1, 22);
        uint256 reusedUnits = _runPhaseUnits(h, 15);
        uint256 freshUnits = _runPhaseUnits(fresh, 15);
        _drain(h);
        _drain(fresh);
        uint8 winners = h.roundOf(15).winners;
        assertGt(winners, 0);
        assertEq(winners, fresh.roundOf(15).winners);
        assertEq(h.roundOf(15).champion, fresh.roundOf(15).champion);
        for (uint8 i; i < winners; ++i) {
            assertEq(abi.encode(h.nodeOf(15, i)), abi.encode(fresh.nodeOf(15, i)));
        }
        for (uint160 i = 1001; i <= 1025; ++i) {
            assertEq(h.balanceOf(address(i)), fresh.balanceOf(address(i)));
        }
        assertLt(reusedUnits, freshUnits, "reused slots are charged less than fresh ones");
    }

    /// @dev Fund the fixture beyond affordability so the bounds themselves decide the stop.
    ///      The old 3000-FLIP fixture's duration depended on the replaced random bonus.
    function test_RunBoundsCapRollsAndShooters() public {
        CrapsEngine engine = CrapsEngine(ContractAddresses.CRAPS_ENGINE);
        uint256 word = uint256(keccak256(abi.encode("round200k", uint256(404))));
        bytes32 seed = keccak256(abi.encode(DICE, word, LVL));
        uint256 board = uint256(keccak256(abi.encode(BOARD, word, LVL, uint64(200))));
        uint256 owner = 200 + 0x1000;
        uint256 boost = 0x050c070c0a0c0e0c120c140c190c1e0c & 0xFFFF;
        Craps.SlipResult memory free = engine.settleSlip(0, 60, board, 10, seed, 1e40, 0, owner, boost);
        assertGe(free.totalRolls, 600, "funded fixture must reach the roll budget");
        Craps.SlipResult memory run = engine.settleSlipBounded(0, 60, board, 10, seed, 1e40, owner, boost, (400 << 16) | 512);
        assertEq(run.totalRolls, 400, "exact roll cap");
        assertLe(run.handsPlayed, 512);
        assertGe(run.peakBankroll, 1e40);
        Craps.SlipResult memory exact = engine.settleSlipBounded(0, 60, board, 10, seed, 1e40, owner, boost, (511 << 16) | 512);
        assertEq(exact.totalRolls, 511, "exact 511-roll cut");
        Craps.SlipResult memory short = engine.settleSlipBounded(0, 60, board, 10, seed, 1e40, owner, boost, (400 << 16) | 20);
        assertEq(short.handsPlayed, 20, "shooter cap");
        Craps.SlipResult memory clamped =
            engine.settleSlipBounded(0, 60, board, 10, seed, 1e40, owner, boost, type(uint256).max);
        assertEq(abi.encode(clamped), abi.encode(free), "oversized bounds clamp to the engine limits");
    }

    /// @dev Big shares: the champion (position 0) takes half its amount in whole half passes and the
    ///      rest in ETH; the other places alternate ETH (odd) and whole half passes (even). Only pass
    ///      money leaves for the future pool after the daily lock clears; the other pass winners'
    ///      leftovers top up the other ETH winners, and that split's dust follows the passes.
    function test_BigSharesAlternateEthAndHalfPasses() public {
        for (uint256 frozen; frozen < 2; ++frozen) {
            DecimatorBattleHarness t = new DecimatorBattleHarness();
            t.open(LVL);
            _probe();
            _populate(t, LVL, 60); // up to twenty places
            uint256 pool = 60 ether + 7;
            t.seal(LVL, uint128(pool), 5);
            if (frozen == 1) {
                t.freeze(true);
                _assertLockedSettlementIsIdle(t);
                assertEq(t.reserved(), pool, "locked round keeps its full reservation");
                t.freeze(false);
            }
            _drain(t);
            this.assertBigSharePayouts(t, pool);
        }
    }

    // Separate test call frame keeps the via-IR fixture within its stack limit.
    function assertBigSharePayouts(DecimatorBattleHarness t, uint256 pool) external {
        DegenerusGameStorage.DecBattleRound memory round = t.roundOf(LVL);
        uint256 w = round.winners;
        assertGt(w, 1, "fixture has several winners");
        assertEq(uint64(t.nodeOf(LVL, 0).key), round.champion);
        uint256 base = (pool - pool / 20) / w;
        uint256 champ = pool - base * (w - 1);
        uint256 passWinners = (w - 1) / 2;
        uint256 ethWinners = w - 1 - passWinners;
        uint256 champPasses = champ / 2 / 2.25 ether;
        uint256 leftover = passWinners * (base % 2.25 ether);
        uint256 perEth = leftover / ethWinners;
        uint256 passMoney = champPasses * 2.25 ether + passWinners * (base / 2.25 ether) * 2.25 ether;
        address champion = address(uint160(round.champion));
        assertEq(t.passesOf(champion), champPasses, "champion: half in whole half passes");
        assertEq(t.balanceOf(champion), champ - champPasses * 2.25 ether, "champion: the rest ETH");
        uint256 eth = champ - champPasses * 2.25 ether;
        for (uint8 i = 1; i < w; ++i) {
            address owner = address(uint160(uint64(t.nodeOf(LVL, i).key)));
            if (i % 2 == 0) {
                assertEq(t.passesOf(owner), base / 2.25 ether, "whole half passes");
                assertEq(t.balanceOf(owner), 0);
            } else {
                assertEq(t.balanceOf(owner), base + perEth, "ETH share plus the leftovers");
                assertEq(t.passesOf(owner), 0);
                eth += base + perEth;
            }
        }
        uint256 recycled = passMoney + (leftover - perEth * ethWinners);
        assertEq(eth + recycled, pool, "every wei accounted");
        assertEq(t.reserved(), eth, "the reservation keeps exactly the ETH credits");
        assertEq(t.future(), recycled, "only pass money (and dust) recycles");
        assertEq(t.pendingFuture(), 0, "settlement runs only after the daily lock clears");
    }

    function test_SmallSharesAreAllEth() public {
        _probe();
        _populate(h, LVL, 60);
        h.seal(LVL, 4 ether, 5); // two or more places share < 2.25 ether; a lone winner takes ETH
        _drain(h);
        for (uint160 i = 1; i <= 60; ++i) assertEq(h.passesOf(address(i)), 0);
        assertEq(h.reserved(), 4 ether);
    }

    /// @dev Whole FLIP of chips: a burn's credit rounds down to a whole FLIP, and one that rounds
    ///      to zero reverts.
    function test_StackCountsWholeFlip() public {
        _burn(h, address(1), LVL, 1001, 10_000);
        assertEq(h.entryOf(LVL, 1).stack, 1001);
        vm.prank(ContractAddresses.COIN);
        vm.expectRevert();
        h.recordDecBurn(address(2), LVL, 0, 10_000, 0);
    }

    /// @dev Past 2^66 FLIP the stack saturates: later burns still record, and the owner and board
    ///      beside it are untouched.
    function test_StackCannotOverflowCreditedAggregate() public {
        _burn(h, address(1), LVL, type(uint64).max, 10_000);
        vm.prank(ContractAddresses.COIN);
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL, 2000, 20_000, 3);
        DecimatorBattleHarness.Entry memory e = h.entryOf(LVL, 1);
        assertEq(e.stack, type(uint64).max);
        assertEq(e.owner, address(1));
        assertEq(e.chips, 0);
        assertEq(h.roundOf(LVL).count, 1);
    }

    /// @dev A loose envelope from the actual bounded engine inputs still leaves 18 score bits.
    function test_EnginePayoutEnvelopeFitsScoreLane() public pure {
        uint256 stake = 600e18;
        uint256 escalation = uint256(1) << 27; // last permitted shooter (47)
        // Nine-to-one is the largest profit multiple; include all stakes/refunds and
        // one survival doubling per shooter, even though these maxima cannot coincide.
        uint256 peakBound = 3000e18 + 511 * 9 * stake * 130 / 100 * escalation
            + 48 * 2 * stake * escalation;
        assertLt(peakBound, uint256(1) << 110);
        assertLt(((uint256(1) << 66) - 1) * peakBound, uint256(1) << 192);
    }

    function testFuzz_WinnerQuotaAndConservation(uint8 population, uint256 word, uint96 pool) public {
        _probe();
        word = bound(word, 2, type(uint256).max);
        uint64 n = uint64(bound(population, 1, 35));
        _populate(h, LVL, n);
        h.seal(LVL, pool, word);
        _drain(h);
        uint8 cap = uint8(n / 2); // this property covers 1–35 entrants, below the 20-place plateau
        uint256 sum;
        for (uint64 id = 1; id <= n; ++id) {
            sum += h.balanceOf(address(uint160(id)));
        }
        assertEq(h.roundOf(LVL).winners, cap);
        assertEq(sum + h.future(), pool);
        assertEq(h.reserved(), sum);
    }

    function test_QuotaBoundariesAndCenturyUseSameRule() public {
        uint40[18] memory counts = [uint40(1),2,19,20,39,40,41,190,191,199,200,201,999,1000,1001,1999,2000,2001];
        uint8[18] memory quotas = [uint8(0),1,9,10,19,20,20,20,20,20,20,21,100,100,101,200,200,200];
        uint256 clean = vm.snapshotState();
        for (uint256 i; i < counts.length; ++i) {
            assertTrue(vm.revertToState(clean));
            clean = vm.snapshotState();
            h.open(100);
            h.forceCount(100, counts[i]);
            h.seal(100, 0, 777);
            assertEq(h.roundOf(100).capacity, quotas[i]);
        }
    }

    function test_RoundedUpSurvivorsRespectFloorHalfQuota() public {
        _probe();
        _populate(h, LVL, 19);
        h.seal(LVL, 60 ether, 777);
        _drain(h);
        assertEq(h.roundOf(LVL).cursor, 10);
        assertEq(h.roundOf(LVL).winners, 9);
        assertEq(h.roundOf(LVL).paid, 9);
        uint256 sum;
        for (uint160 i = 1; i <= 19; ++i) sum += h.balanceOf(address(i));
        assertEq(sum + h.future(), 60 ether);
    }

    function test_LargeFieldVisitsExactlyOneThousandSurvivors() public {
        _probe();
        _populate(h, LVL, 2001);
        h.seal(LVL, 100 ether, 777);
        vm.recordLogs();
        _drain(h);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool[2002] memory ran;
        uint256 runs;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == keccak256("DecimatorRun(uint24,uint64,uint256)")) {
            uint64 id = uint64(uint256(logs[i].topics[2]));
            assertFalse(ran[id]);
            ran[id] = true;
            ++runs;
        }
        for (uint64 id = 1; id <= 2001; ++id) assertEq(ran[id], Sample.contains(777, LVL, 2001, id));
        assertEq(runs, 1000);
        assertEq(h.roundOf(LVL).cursor, 1000);
        assertEq(h.roundOf(LVL).winners, 200);
    }
}
