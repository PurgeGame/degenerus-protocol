// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DecimatorBattleHarness} from "./helpers/DecimatorBattleHarness.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {Craps} from "../../contracts/Craps.sol";

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
        address,
        uint256 boost,
        uint256 bounds
    ) external pure returns (Craps.SlipResult memory r) {
        uint256 named;
        for (uint256 i; i < 30; i += 3) named += (chips >> i) & 7;
        require(chip == 60 && count == 10 - named && bankroll == 3000 ether && bounds == (511 << 16 | 48));
        // The normal battles' shooter-boost row (Craps._shooterBoostTerms).
        require(boost == (0x1205170618081D091D0B1D0C1D0E200F >> (named << 4)) & 0xFFFF);
        r.peakBankroll = bankroll + board % (1_000_000 ether);
        r.totalRolls = 30;
    }
}

/// @dev Every run peaks exactly at the starting bankroll, so equal stacks tie and ranking falls
///      through to the random tiebreak.
contract DecimatorFlatProbe {
    function settleSlipBounded(uint256 chips, uint256 chip, uint256, uint256 count, bytes32, uint256 bankroll, address, uint256, uint256)
        external
        pure
        returns (Craps.SlipResult memory r)
    {
        require(chips == 0 && chip == 60 && count == 10 && bankroll == 3000 ether);
        r.peakBankroll = bankroll;
        r.totalRolls = 30;
    }
}

/// @dev Peaks far past anything the engine's bounds admit, so every score hits its cap.
contract DecimatorHugePeakProbe {
    function settleSlipBounded(uint256, uint256, uint256 board, uint256, bytes32, uint256, address, uint256, uint256)
        external
        pure
        returns (Craps.SlipResult memory r)
    {
        r.peakBankroll = (uint256(1) << 200) + board % (1_000_000 ether);
        r.totalRolls = 30;
    }
}

contract DecimatorBattleTest is Test {
    DecimatorBattleHarness internal h;
    uint24 internal constant LVL = 5;
    bytes32 internal constant DICE = keccak256("decimator.battle.dice.v1");
    bytes32 internal constant BOARD = keccak256("decimator.battle.board.v1");
    bytes32 internal constant COIN = keccak256("decimator.battle.final-coin.v1");
    bytes32 internal constant TIE = keccak256("decimator.battle.tie.v1");

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
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

    function _heads(uint256 word, uint24 lvl, uint64 id) internal pure returns (bool) {
        return uint256(keccak256(abi.encode(COIN, word, lvl, id))) & 1 != 0;
    }

    function _drain(DecimatorBattleHarness target, uint256 budget) internal {
        for (uint256 i; uint24(target.queue()) != 0 && i < 4000; ++i) {
            target.settleDecimatorWinners(budget);
        }
        assertEq(uint24(target.queue()), 0, "settlement terminated");
    }

    function _populate(DecimatorBattleHarness target, uint24 lvl, uint64 n) internal {
        for (uint64 i = 1; i <= n; ++i) {
            _burn(target, address(uint160(i)), lvl, (uint256(i) + 1) * 1000 ether, 10_000);
        }
    }

    function _probe() internal {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorEngineProbe).runtimeCode);
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
        assertEq(_burn(h, address(1), LVL, 1_000_000 ether, 19_000), 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertEq(_burn(h, address(1), LVL, 1_000_000 ether, 20_000), 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _burn(h, address(1), LVL, 1_000_000 ether, 10_000);
        DecimatorBattleHarness.Entry memory e = h.entryOf(LVL, 1);
        assertEq(e.stack, 4_510_000 ether);
        assertEq(h.roundOf(LVL).count, 1);
    }

    function test_FirstBurnDoesNotStartClockAndNoOld500kCap() public {
        vm.warp(vm.getBlockTimestamp() + 3 days);
        _burn(h, address(1), LVL, 10_000_000 ether, 20_000);
        assertEq(h.entryOf(LVL, 1).stack, 14_580_000 ether);
    }

    function test_ResetBoundary() public {
        vm.warp(vm.getBlockTimestamp() + 1 days - 2);
        _burn(h, address(1), LVL, 1000 ether, 10_000);
        vm.warp(vm.getBlockTimestamp() + 1);
        _burn(h, address(2), LVL, 1000 ether, 10_000);
        assertEq(h.entryOf(LVL, 1).stack, 1000 ether);
        assertEq(h.entryOf(LVL, 2).stack, 900 ether);
    }

    function test_RecordAccessAndSealGuards() public {
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL, 1000 ether, 10_000, 0);
        vm.startPrank(ContractAddresses.COIN);
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL + 1, 1000 ether, 10_000, 0);
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL, 1000 ether, 20_001, 0);
        vm.expectRevert();
        h.recordDecBurn(address(0), LVL, 1000 ether, 10_000, 0);
        vm.stopPrank();
        _burn(h, address(1), LVL, 1000 ether, 10_000);
        vm.expectRevert();
        h.runDecimatorJackpot(1 ether, LVL, 123);
        h.seal(LVL, 1 ether, 123);
        vm.prank(ContractAddresses.COIN);
        vm.expectRevert();
        h.recordDecBurn(address(1), LVL, 1000 ether, 10_000, 0);
        assertEq(h.seal(LVL, 1 ether, 456), 1 ether);
        assertEq(h.roundOf(LVL).rngWord, 123);
        assertEq(h.reserved(), 1 ether);
    }

    function test_EmptyRoundReturnsPool() public {
        assertEq(h.seal(LVL, 100 ether, 123), 100 ether);
        assertEq(h.reserved(), 0);
        assertEq(uint24(h.queue()), 0);
    }

    function test_SingleHeadsGetsEverythingAndNoDoublePay() public {
        _burn(h, address(1), LVL, 1000 ether, 10_000);
        uint256 word;
        while (!_heads(word, LVL, 1)) ++word;
        h.seal(LVL, 13 ether + 17, word);
        h.freeze(true);
        _drain(h, 21);
        // The champion: half in whole half passes (6.5 ETH buys two), the rest ETH.
        assertEq(h.passesOf(address(1)), 2);
        assertEq(h.balanceOf(address(1)), 13 ether + 17 - 2 * 2.25 ether);
        assertEq(h.reserved(), 13 ether + 17 - 2 * 2.25 ether);
        assertEq(h.pendingFuture(), 2 * 2.25 ether, "pass money recycles, pending while frozen");
        (uint256 worked,, bool moved) = h.settleDecimatorWinners(1500);
        assertEq(worked, 0);
        assertFalse(moved);
    }

    function test_AllTailsReturnsReserveToFrozenFuture() public {
        _burn(h, address(1), LVL, 1000 ether, 10_000);
        uint256 word;
        while (_heads(word, LVL, 1)) ++word;
        h.seal(LVL, 7 ether, word);
        h.freeze(true);
        _drain(h, 1500);
        assertEq(h.balanceOf(address(1)), 0);
        assertEq(h.roundOf(LVL).winners, 0);
        assertEq(h.reserved(), 0);
        assertEq(h.pendingFuture(), 7 ether);
        assertEq(h.future(), 0);
    }

    /// @dev A tails run never reaches the engine: an engine that always reverts cannot stop it.
    function test_TailsSkipsTheEngine() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, hex"fe");
        _burn(h, address(1), LVL, 1000 ether, 10_000);
        uint256 word;
        while (_heads(word, LVL, 1)) ++word;
        h.seal(LVL, 5 ether, word);
        (uint256 worked, uint256 units,) = h.settleDecimatorWinners(1500);
        assertEq(worked, 1);
        assertEq(units, 10, "call base plus the flat tails charge");
        _drain(h, 1500);
        assertEq(h.roundOf(LVL).winners, 0);
        assertEq(h.future(), 5 ether, "all-tails pool returns to future");
    }

    /// @dev Game over stops settlement: the queued round keeps its reservation for the final sweep.
    function test_SettlementIdlesAfterGameOver() public {
        _probe();
        _populate(h, LVL, 4);
        h.seal(LVL, 3 ether, 1);
        h.terminal();
        (uint256 worked, uint256 units, bool moved) = h.settleDecimatorWinners(1500);
        assertEq(worked, 0);
        assertEq(units, 0);
        assertFalse(moved);
        assertEq(uint24(h.queue()), LVL);
        assertEq(h.roundOf(LVL).cursor, 0);
        assertEq(h.reserved(), 3 ether);
    }

    function test_MultipleRoundsQueuedAndHistoricalEntriesRemain() public {
        _probe();
        _populate(h, LVL, 4);
        h.seal(LVL, 3 ether, 1);
        h.open(15);
        _populate(h, 15, 3);
        h.seal(15, 4 ether, 2);
        assertEq(uint24(h.queue()), LVL);
        assertEq(uint24(h.queue() >> 24), 15);
        assertEq(h.roundOf(LVL).next, 15);
        _drain(h, 21);
        assertEq(h.roundOf(LVL).phase, 3);
        assertEq(h.roundOf(15).phase, 3);
        assertEq(h.entryOf(LVL, 1).stack, 2000 ether);
        assertEq(h.entryOf(15, 1).stack, 2000 ether);
    }

    function test_BatchesHaveIdenticalRealDiceAndPayouts() public {
        DecimatorBattleHarness other = new DecimatorBattleHarness();
        other.open(LVL);
        _populate(h, LVL, 31);
        _populate(other, LVL, 31);
        uint256 word = type(uint256).max - 77;
        h.seal(LVL, 13 ether + 77, word);
        other.seal(LVL, 13 ether + 77, word);
        _drain(h, 21);
        _drain(other, type(uint256).max);
        assertEq(abi.encode(h.roundOf(LVL)), abi.encode(other.roundOf(LVL)));
        for (uint8 i; i < h.roundOf(LVL).winners; ++i) {
            assertEq(abi.encode(h.nodeOf(LVL, i)), abi.encode(other.nodeOf(LVL, i)));
        }
        for (uint160 i = 1; i <= 31; ++i) {
            assertEq(h.balanceOf(address(i)), other.balanceOf(address(i)));
        }
    }

    function test_RealEngineReplayUsesSharedDiceAndAbsolutePeak() public {
        _populate(h, LVL, 16);
        uint256 word = uint256(keccak256("decimator replay"));
        h.seal(LVL, 10 ether, word);
        _drain(h, 1500);
        DegenerusGameStorage.DecBattleRound memory round = h.roundOf(LVL);
        bytes32 seed = keccak256(abi.encode(DICE, word, LVL));
        for (uint8 i; i < round.winners; ++i) {
            DecimatorBattleHarness.Node memory node = h.nodeOf(LVL, i);
            uint64 id = uint64(node.key);
            assertTrue(_heads(word, LVL, id));
            Craps.SlipResult memory run = CrapsEngine(ContractAddresses.CRAPS_ENGINE)
                .settleSlipBounded(
                    0,
                    60,
                    uint256(keccak256(abi.encode(BOARD, word, LVL, id))),
                    10,
                    seed,
                    3000 ether,
                    address(uint160(id)),
                    (32 << 8) | 15,
                    (511 << 16) | 48
                );
            assertEq(node.score, h.entryOf(LVL, id).stack / 1 ether * run.peakBankroll);
            assertGe(run.peakBankroll, 3000 ether);
        }
    }

    function test_100WinnerCapExactPayoutAndNoTailsOnBoard() public {
        _probe();
        _populate(h, LVL, 1001);
        h.seal(LVL, 100 ether + 3, 777);
        _drain(h, 1500);
        DegenerusGameStorage.DecBattleRound memory round = h.roundOf(LVL);
        assertEq(round.capacity, 100);
        assertEq(round.winners, 100);
        uint256 pool = 100 ether + 3;
        uint256 base = (pool - pool / 20) / 100;
        uint256 champ = pool - base * 99; // 5.95 ETH: half buys one half pass, 3.7 ETH stays ETH
        uint256 perEth = 0; // shares of 0.95 ETH buy no pass, so nobody else takes passes
        assertEq(uint64(h.nodeOf(LVL, 0).key), round.champion, "champion paid from position 0");
        assertEq(h.passesOf(address(uint160(round.champion))), 1);
        assertEq(h.balanceOf(address(uint160(round.champion))), champ - 2.25 ether);
        uint256 sum = champ - 2.25 ether;
        for (uint8 i = 1; i < 100; ++i) {
            uint64 id = uint64(h.nodeOf(LVL, i).key);
            assertTrue(_heads(777, LVL, id));
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
        for (uint8 i = 1; i < 100; ++i) {
            DecimatorBattleHarness.Node memory node = h.nodeOf(LVL, i);
            if (node.score < root.score) root = node;
        }
        for (uint64 id = 1; id <= 1001; ++id) {
            if (!_heads(777, LVL, id) || h.balanceOf(address(uint160(id))) != 0 || id == round.champion) continue;
            uint256 peak = 3000 ether + uint256(keccak256(abi.encode(BOARD, uint256(777), LVL, id))) % (1_000_000 ether);
            assertLe(h.entryOf(LVL, id).stack / 1 ether * peak, root.score);
        }
    }

    function test_TailsChampionNeverOccupiesPlace() public {
        _probe();
        uint256 word;
        while (_heads(word, LVL, 1) || !_heads(word, LVL, 2)) ++word;
        _burn(h, address(1), LVL, type(uint160).max, 10_000);
        _burn(h, address(2), LVL, 1000 ether, 10_000);
        h.seal(LVL, 1 ether, word);
        _drain(h, 1500);
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
            h.recordDecBurn(address(1), LVL, 1000 ether, 10_000, bad[i]);
        }
        uint32 seven = 3 | 3 << 3 | 1 << 6;
        h.recordDecBurn(address(1), LVL, 1000 ether, 10_000, seven);
        assertEq(h.entryOf(LVL, 1).chips, seven);
        // A later burn sets the board; the stack keeps accumulating.
        h.recordDecBurn(address(1), LVL, 1000 ether, 10_000, 1 << 27);
        vm.stopPrank();
        assertEq(h.entryOf(LVL, 1).chips, 1 << 27);
        assertEq(h.entryOf(LVL, 1).stack, 2000 ether);
    }

    /// @dev A chosen board reaches the engine with the scatter count and boost row for its size.
    function test_ChosenBoardDrivesTheRun() public {
        _probe();
        uint256 word;
        while (!_heads(word, LVL, 1)) ++word;
        vm.prank(ContractAddresses.COIN);
        h.recordDecBurn(address(1), LVL, 1000 ether, 10_000, 2 | 3 << 12 | 1 << 21);
        h.seal(LVL, 1 ether, word);
        _drain(h, 1500); // the probe reverts unless chips, scatter count and boost all match
        assertEq(h.balanceOf(address(1)), 1 ether);
    }

    function _tieKey(uint256 word, uint24 lvl, uint64 id) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encode(TIE, word, lvl, id))) & ~uint256(type(uint64).max)) | id;
    }

    /// @dev Equal scores: two higher stacks and a 33-entry equal-stack group share four places.
    ///      The cutoff and first place both resolve by the tiebreak, identically at any batch size,
    ///      and every retained node reports the key the Lens derives.
    function test_EqualScoresRankByTiebreakAtCutoffAndFirst() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorFlatProbe).runtimeCode);
        DecimatorBattleHarness other = new DecimatorBattleHarness();
        other.open(LVL);
        uint256 word;
        while (!_heads(word, LVL, 1) || !_heads(word, LVL, 2)) ++word;
        for (uint160 i = 1; i <= 35; ++i) {
            uint256 amount = i <= 2 ? 2000 ether : 1000 ether;
            _burn(h, address(i), LVL, amount, 10_000);
            _burn(other, address(i), LVL, amount, 10_000);
        }
        h.seal(LVL, 4 ether, word);
        other.seal(LVL, 4 ether, word);
        _drain(h, 21);
        _drain(other, type(uint256).max);
        assertEq(h.roundOf(LVL).capacity, 4);
        assertEq(h.roundOf(LVL).winners, 4);
        // First place: the two top stacks tie, so the larger tiebreak key wins.
        uint64 first = _tieKey(word, LVL, 1) > _tieKey(word, LVL, 2) ? 1 : 2;
        assertEq(h.roundOf(LVL).champion, first);
        // Cutoff: the two best-keyed heads entries of the equal group take the last two places.
        uint64 best;
        uint64 second;
        for (uint64 id = 3; id <= 35; ++id) {
            if (!_heads(word, LVL, id)) continue;
            if (best == 0 || _tieKey(word, LVL, id) > _tieKey(word, LVL, best)) {
                second = best;
                best = id;
            } else if (second == 0 || _tieKey(word, LVL, id) > _tieKey(word, LVL, second)) {
                second = id;
            }
        }
        bool[36] memory placed;
        for (uint8 i; i < 4; ++i) {
            DecimatorBattleHarness.Node memory node = h.nodeOf(LVL, i);
            uint64 id = uint64(node.key);
            assertEq(node.key, _tieKey(word, LVL, id), "node key matches the Lens derivation");
            assertEq(abi.encode(node), abi.encode(other.nodeOf(LVL, i)), "batch size never moves the heap");
            placed[id] = true;
        }
        assertTrue(placed[1] && placed[2] && placed[best] && placed[second], "exact winner set");
        uint256 base = (4 ether - 4 ether / 20) / 4; // champion 1.15 ETH: under a half pass, all ETH
        assertEq(h.balanceOf(address(uint160(first))), 4 ether - base * 3);
        assertEq(h.balanceOf(address(uint160(best))), base);
    }

    function _runPhaseUnits(DecimatorBattleHarness target, uint24 lvl) internal returns (uint256 units) {
        while (target.roundOf(lvl).phase == 1 && target.roundOf(lvl).cursor < target.roundOf(lvl).count) {
            (, uint256 used,) = target.settleDecimatorWinners(1500);
            units += used;
        }
    }

    /// @dev A later round reuses the leaderboard slots an earlier round filled: stale nodes never
    ///      reach its results, and its filling inserts are charged the reused price.
    function test_LaterRoundReusesLeaderboardSlots() public {
        _probe();
        _populate(h, LVL, 40); // four places
        h.seal(LVL, 4 ether, 11);
        _drain(h, 1500);
        DecimatorBattleHarness fresh = new DecimatorBattleHarness();
        h.open(15);
        fresh.open(15);
        for (uint160 i = 1; i <= 25; ++i) { // three places
            _burn(h, address(i + 1000), 15, (uint256(i) + 1) * 1000 ether, 10_000);
            _burn(fresh, address(i + 1000), 15, (uint256(i) + 1) * 1000 ether, 10_000);
        }
        h.seal(15, 3 ether + 1, 22);
        fresh.seal(15, 3 ether + 1, 22);
        uint256 reusedUnits = _runPhaseUnits(h, 15);
        uint256 freshUnits = _runPhaseUnits(fresh, 15);
        _drain(h, 1500);
        _drain(fresh, 1500);
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

    /// @dev The longest run of the 200,000-run simulation: entry 200 of round 404 (a fully random
    ///      board) ran 430 rolls and 35 shooters unbounded, inside the Decimator's own bounds. Any
    ///      roll bound under 512 cuts exactly, as the Decimator's 511 does: 400 stops this run at
    ///      exactly 400 rolls; a smaller shooter cap stops it at that shooter; oversized bounds
    ///      clamp to the engine's.
    function test_RunBoundsCapRollsAndShooters() public {
        CrapsEngine engine = CrapsEngine(ContractAddresses.CRAPS_ENGINE);
        uint256 word = uint256(keccak256(abi.encode("round200k", uint256(404))));
        bytes32 seed = keccak256(abi.encode(DICE, word, LVL));
        uint256 board = uint256(keccak256(abi.encode(BOARD, word, LVL, uint64(200))));
        address owner = address(uint160(200) + 0x1000);
        uint256 boost = 0x1205170618081D091D0B1D0C1D0E200F & 0xFFFF;
        Craps.SlipResult memory free = engine.settleSlip(0, 60, board, 10, seed, 3000 ether, 0, owner, boost);
        assertEq(free.totalRolls, 430);
        assertEq(free.handsPlayed, 35);
        Craps.SlipResult memory run = engine.settleSlipBounded(0, 60, board, 10, seed, 3000 ether, owner, boost, (400 << 16) | 40);
        assertEq(run.totalRolls, 400, "exact roll cap");
        assertLe(run.handsPlayed, 40);
        assertGe(run.peakBankroll, 3000 ether);
        Craps.SlipResult memory short = engine.settleSlipBounded(0, 60, board, 10, seed, 3000 ether, owner, boost, (400 << 16) | 20);
        assertEq(short.handsPlayed, 20, "shooter cap");
        Craps.SlipResult memory clamped =
            engine.settleSlipBounded(0, 60, board, 10, seed, 3000 ether, owner, boost, type(uint256).max);
        assertEq(abi.encode(clamped), abi.encode(free), "oversized bounds clamp to the engine limits");
    }

    /// @dev Big shares: the champion (position 0) takes half its amount in whole half passes and the
    ///      rest in ETH; the other places alternate ETH (odd) and whole half passes (even). Only pass
    ///      money leaves for the future pool (pending while frozen); the other pass winners'
    ///      leftovers top up the other ETH winners, and that split's dust follows the passes.
    function test_BigSharesAlternateEthAndHalfPasses() public {
        for (uint256 frozen; frozen < 2; ++frozen) {
            DecimatorBattleHarness t = new DecimatorBattleHarness();
            t.open(LVL);
            _probe();
            _populate(t, LVL, 60); // up to six places
            uint256 pool = 60 ether + 7;
            t.seal(LVL, uint128(pool), 5);
            if (frozen == 1) t.freeze(true);
            _drain(t, 1500);
            DegenerusGameStorage.DecBattleRound memory round = t.roundOf(LVL);
            uint256 w = round.winners;
            assertGt(w, 1, "fixture has several winners");
            uint256 base = (pool - pool / 20) / w;
            uint256 champ = pool - base * (w - 1);
            uint256 passWinners = (w - 1) / 2;
            uint256 ethWinners = w - 1 - passWinners;
            uint256 champPasses = champ / 2 / 2.25 ether;
            uint256 leftover = passWinners * (base % 2.25 ether);
            uint256 perEth = leftover / ethWinners;
            uint256 passMoney = champPasses * 2.25 ether + passWinners * (base / 2.25 ether) * 2.25 ether;
            assertEq(uint64(t.nodeOf(LVL, 0).key), round.champion);
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
            assertEq(frozen == 1 ? t.pendingFuture() : t.future(), recycled, "only pass money (and dust) recycles");
        }
    }

    function test_SmallSharesAreAllEth() public {
        _probe();
        _populate(h, LVL, 60);
        h.seal(LVL, 4 ether, 5); // two or more places share < 2.25 ether; a lone winner takes ETH
        _drain(h, 1500);
        for (uint160 i = 1; i <= 60; ++i) assertEq(h.passesOf(address(i)), 0);
        assertEq(h.reserved(), 4 ether);
    }

    /// @dev Whole FLIP of chips: a burn's credit rounds down to a whole FLIP, and one that rounds
    ///      to zero reverts.
    function test_StackCountsWholeFlip() public {
        _burn(h, address(1), LVL, 1000 ether + 0.9 ether, 10_000);
        assertEq(h.entryOf(LVL, 1).stack, 1000 ether);
        vm.prank(ContractAddresses.COIN);
        vm.expectRevert();
        h.recordDecBurn(address(2), LVL, 0.9 ether, 10_000, 0);
    }

    /// @dev Past 2^66 FLIP the stack saturates: later burns still record, and the owner and board
    ///      beside it are untouched.
    function test_StackSaturatesInsteadOfWrapping() public {
        uint256 cap = ((uint256(1) << 66) - 1) * 1 ether;
        _burn(h, address(1), LVL, type(uint160).max, 10_000);
        assertEq(h.entryOf(LVL, 1).stack, cap);
        vm.prank(ContractAddresses.COIN);
        assertEq(h.recordDecBurn(address(1), LVL, type(uint160).max, 20_000, 3), 1);
        DecimatorBattleHarness.Entry memory e = h.entryOf(LVL, 1);
        assertEq(e.stack, cap);
        assertEq(e.owner, address(1));
        assertEq(e.chips, 3);
        assertEq(h.roundOf(LVL).count, 1);
    }

    /// @dev A peak past the engine's bounds saturates the score: equal capped scores fall to the
    ///      tiebreak, and settlement completes.
    function test_ScoreSaturatesInsteadOfWrapping() public {
        vm.etch(ContractAddresses.CRAPS_ENGINE, type(DecimatorHugePeakProbe).runtimeCode);
        uint256 word;
        while (!_heads(word, LVL, 1) || !_heads(word, LVL, 2)) ++word;
        _burn(h, address(1), LVL, type(uint160).max, 10_000);
        _burn(h, address(2), LVL, 1000 ether, 10_000);
        h.seal(LVL, 1 ether, word);
        _drain(h, 1500);
        assertEq(h.roundOf(LVL).winners, 1);
        uint64 champion = _tieKey(word, LVL, 1) > _tieKey(word, LVL, 2) ? 1 : 2;
        assertEq(h.roundOf(LVL).champion, champion);
        assertEq(h.nodeOf(LVL, 0).score, (uint256(1) << 192) - 1);
        assertEq(h.balanceOf(address(uint160(champion))), 1 ether);
    }

    function testFuzz_WinnerQuotaAndConservation(uint8 population, uint256 word, uint96 pool) public {
        _probe();
        uint64 n = uint64(bound(population, 1, 35));
        _populate(h, LVL, n);
        h.seal(LVL, pool, word);
        _drain(h, 1500);
        uint8 cap = uint8((n + 9) / 10);
        uint8 heads;
        uint256 sum;
        for (uint64 id = 1; id <= n; ++id) {
            if (_heads(word, LVL, id)) ++heads;
            sum += h.balanceOf(address(uint160(id)));
        }
        assertEq(h.roundOf(LVL).winners, heads < cap ? heads : cap);
        assertEq(sum + h.future(), pool);
        assertEq(h.reserved(), sum);
    }
}
