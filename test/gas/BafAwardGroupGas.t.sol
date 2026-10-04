// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {
    BafPairDraw,
    BafSchedule,
    CenturyBafScores,
    CenturyConsolidationSeeder
} from "./AdvanceCenturyConsolidationGas.t.sol";

/// @dev Production game facade plus a native runDailyPhase seam. `seedBafStage` writes the state
///      the x00 consolidation leaves behind, positioned at a group boundary: a kind-7 work record
///      (pool, positions, cursor) whose `paid` is the reserved ETH still owed (also held in
///      claimablePool), the daily lock of a published session with the day's word recorded, and the
///      prize pools frozen as the daily lock leaves them (one hundredth of futurePool opening the
///      pending buffer).
contract BafGroupGasHost is DegenerusGame {
    function seedBafStage(uint256 word, uint128 pool, uint32 positions, uint16 cursor, uint128 reserved) external {
        uint24 day = _simulatedDayIndex();
        level = 100;
        jackpotPhaseFlag = true;
        lastPurchaseDay = false;
        jackpotFlags = 0;
        phaseTransitionActive = false;
        dailyIdx = day - 1;
        ticketsFullyProcessed = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = word;
        rngRequestDay = day;
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        _recordDailyRng(day, word);
        dailyTicketBudgetsPacked = 0;
        uint256 future = _getFuturePrizePool();
        _setFuturePrizePool(future - future / 100);
        _setPendingPools(0, uint128(future / 100));
        prizePoolFrozen = true;

        JackpotWork storage work = jackpotWork;
        work.budget = pool;
        work.paid = reserved;
        work.traits = positions;
        work.lvl = 100;
        work.winner = cursor;
        work.kind = 7;
        work.quadrant = 0;
        claimablePool += reserved;
    }

    function dailyWith(uint256 allowance) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runDailyPhase(uint256)", allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }

    /// @dev Reference seam: the production queue sink with one logged ticket roll's arguments.
    function replayQueued(address buyer, uint24 targetLevel, uint32 entries) external {
        _queueEntries(buyer, targetLevel, entries, true);
    }

    /// @dev Re-points the armed stage at `cursor` under `word`; the reservation is left as seeded.
    function repointBafStage(uint256 word, uint16 cursor) external {
        rngWordCurrent = word;
        _recordDailyRng(rngRequestDay, word);
        jackpotWork.winner = cursor;
    }

    function bafWork() external view returns (uint8 kind, uint16 cursor, uint32 count, uint128 reserved) {
        JackpotWork storage work = jackpotWork;
        return (work.kind, work.winner, work.traits, work.paid);
    }

    function claimableOfProbe(address player) external view returns (uint256) {
        return uint128(balancesPacked[player]);
    }

    /// @dev claimablePool and futurePool plus the pending future share a frozen pool accumulates.
    function poolsProbe() external view returns (uint256 claimable, uint256 future) {
        (, uint128 pending) = _getPendingPools();
        return (claimablePool, _getFuturePrizePool() + pending);
    }
}

/// @title BafAwardGroupGas — one BAF award group of the level-100 bracket, cold, at its worst mix.
/// @notice The bracket is the century fixture's: every trait bucket the minted-level rounds select
///         holds 2048 distinct wallets, every level 102..199 holds a far-future queue (2048 deep at
///         102..105, 128 at 106..199, lengths multiples of eight), every one of those wallets has a
///         qualifying BAF score, the head board holds four bettors and the depositor draw walks a
///         4096-interval book. The stage is seeded at the measured group's boundary and one call
///         pays exactly that group. The word is the one, of 2048 candidates, whose ticket legs in
///         the group reach the most distinct target levels (each first touch appends a new lane
///         and starts a fresh queue word), tie-broken by rolls onto far-future levels.
/// @dev Before the measured call a reference run of the same group and the bracket views draw each
///      round pair on the state it starts from (`BafPairDraw`); the state is restored and the engine
///      accounts cooled, so the measured call starts on a cold access list. The call is checked
///      position by position against that draw (BafSchedule.checkGroupR).
abstract contract BafAwardGroupFixture is DeployProtocol {
    uint256 internal constant CAP = 10_000_000;
    uint8 internal constant STAGE_JACKPOT_BAF_AWARDS = 19;
    uint256 internal constant BAF_TICKET_TAG = 0x4261665469636b6574;
    uint256 internal constant GROUP = BafSchedule.GROUP;
    uint256 internal constant SEARCH = 2048;
    uint24 internal constant DAY = 400;
    /// @dev Admits exactly one group: the group bound, its tail, the phase tail and check reserve,
    ///      plus the runDailyPhase preamble and module hops before the group check.
    uint256 internal constant ONE_GROUP_ALLOWANCE = GasBounds.BAF_AWARD_GROUP + GasBounds.BAF_AWARD_TAIL
        + GasBounds.DAILY_PHASE_TAIL + MineFlipGas.CHECK_RESERVE + 100_000;
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    BafGroupGasHost internal host;
    uint256 internal word;
    uint256 internal spreadLevels;
    uint256 internal start;
    uint256 internal end;
    uint256 internal positions;

    /// @dev Group index: 0..R/4-1 scatter groups (two round pairs each), R/4 the three head awards.
    function _group() internal pure virtual returns (uint256);

    function _pool() internal pure virtual returns (uint128);

    /// @dev Scatter rounds of the pool's schedule (the draw module's `_bafRounds`).
    function _rounds() internal pure virtual returns (uint256) {
        return BafSchedule.ROUNDS;
    }

    /// @dev Reserved ETH of earlier unfilled positions, returned to the pending pool by the last group.
    function _residue() internal pure virtual returns (uint256) {
        return 0;
    }

    /// @dev The head board and the depositor draw book the head awards read.
    function _seedHead() internal virtual {
        CenturyBafScores.seedHead(address(jackpots), address(coinflip), address(game), DAY);
    }

    function setUp() public {
        _deployProtocol();
        vm.warp((uint256(399) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
        assertEq(_rounds(), _bafRounds(_pool()), "the schedule's round count is the pool's");
        positions = 2 * _rounds() + 3;
        start = _group() * GROUP;
        end = start + GROUP < positions ? start + GROUP : positions;
        (word, spreadLevels) = _pickWord();

        vm.etch(address(game), type(CenturyConsolidationSeeder).runtimeCode);
        CenturyConsolidationSeeder(payable(address(game))).seed(word, 100 ether, 100 ether);
        // Every queue through level 100 has drained at a level-100 BAF; the recycled roots for
        // levels 101..200 are free to bind.
        TQ.retireCompleted(address(game), 100);
        CenturyBafScores.seedCandidates(address(jackpots));
        _seedHead();
        vm.etch(address(game), type(BafGroupGasHost).runtimeCode);
        host = BafGroupGasHost(payable(address(game)));
        uint256 reserved = BafSchedule.ethTermsR(_pool(), start, positions, _rounds()) + _residue();
        host.seedBafStage(word, _pool(), uint32(positions), uint16(start), uint128(reserved));
    }

    /// @dev The draw module's round count: 48 below 500 ETH, doubled at each fourfold step from
    ///      there, at most 1,536.
    function _bafRounds(uint256 pool) internal pure returns (uint256 rounds) {
        rounds = 48;
        for (uint256 step = 500 ether; rounds < 1536 && pool >= step; step *= 4) rounds *= 2;
    }

    /// @dev Target level of one roll, as `_jackpotTicketRoll` derives it at floor level 100.
    function _target(uint256 e) private pure returns (uint24) {
        uint256 d = e / 100;
        uint256 r = e - d * 100;
        if (r < 30) return 100;
        if (r < 95) return uint24(101 + d % 4);
        return uint24(105 + d % 46);
    }

    /// @dev The ticket part of position `i`'s award when it rolls tickets (zero for an ETH leg or
    ///      a whale-pass deferral).
    function _rolledLootbox(uint256 pool, uint256 i) private pure returns (uint256 lootbox) {
        uint256 a = BafSchedule.amountR(pool, i, _rounds());
        if (a >= pool / 20) lootbox = a - a / 2;
        else if (!BafSchedule.ethLeg(i)) lootbox = a;
        if (lootbox > 5 ether) lootbox = 0;
    }

    function _pickWord() private view returns (uint256 best, uint256 bestLevels) {
        uint256[] memory words = _topWords(start, end, 1);
        best = words[0];
        (bestLevels,) = _spread(best, start, end);
    }

    /// @dev Distinct target levels and far-future rolls of the ticket legs of positions `from`..`to` - 1
    ///      under word `w`.
    function _spread(uint256 w, uint256 from, uint256 to) private pure returns (uint256 levels, uint256 far) {
        uint256 pool = _pool();
        uint256 seen;
        for (uint256 i = from; i < to; ++i) {
            uint256 lootbox = _rolledLootbox(pool, i);
            if (lootbox == 0) continue;
            uint256 e = EntropyLib.hash4(w, 100, BAF_TICKET_TAG, i);
            uint256 rolls = lootbox <= 0.5 ether ? 1 : 2;
            for (uint256 r; r < rolls; ++r) {
                e = EntropyLib.hash2(e, e);
                uint24 t = _target(e);
                uint256 bit = uint256(1) << (t - 100);
                if (seen & bit == 0) {
                    seen |= bit;
                    ++levels;
                }
                if (t >= 102) ++far;
            }
        }
    }

    /// @dev The `k` words of `SEARCH` candidates whose ticket legs over positions `from`..`to` - 1
    ///      reach the most distinct target levels, tie-broken by far-future rolls, best first.
    function _topWords(uint256 from, uint256 to, uint256 k) internal pure returns (uint256[] memory words) {
        words = new uint256[](k);
        uint256[] memory scores = new uint256[](k);
        for (uint256 c; c < SEARCH; ++c) {
            uint256 w = uint256(keccak256(abi.encode("baf-award-group-worst", c))) | 1;
            (uint256 levels, uint256 far) = _spread(w, from, to);
            uint256 score = levels * 16 + far + 1;
            for (uint256 j; j < k; ++j) {
                if (score <= scores[j]) continue;
                for (uint256 m = k - 1; m > j; --m) {
                    scores[m] = scores[m - 1];
                    words[m] = words[m - 1];
                }
                scores[j] = score;
                words[j] = w;
                break;
            }
        }
    }

    /// @dev Measures every scatter group `gFrom`..`gTo` - 1 cold under each of its `perGroup`
    ///      widest-spread words (the stage re-pointed from a snapshot each time) and logs the largest.
    function _sweep(uint256 gFrom, uint256 gTo, uint256 perGroup, string memory label) internal returns (uint256 worst) {
        uint256 worstGroup;
        string memory worstMix;
        uint256 runs;
        for (uint256 g = gFrom; g < gTo; ++g) {
            uint256[] memory words = _topWords(g * GROUP, g * GROUP + GROUP, perGroup);
            for (uint256 k; k < words.length; ++k) {
                uint256 snap = vm.snapshotState();
                host.repointBafStage(words[k], uint16(g * GROUP));
                (uint256 used, MineFlipGas.Result memory result, Vm.Log[] memory logs) = _measure(ONE_GROUP_ALLOWANCE);
                assertTrue(result.progressed && !result.done, "one scatter group is admitted");
                assertEq(_lastStage(logs), STAGE_JACKPOT_BAF_AWARDS, "the BAF award stage ran");
                (, uint16 cursor,,) = host.bafWork();
                assertEq(cursor, g * GROUP + GROUP, "exactly one group per admitted allowance");
                assertLe(used, GasBounds.BAF_AWARD_GROUP, "cold BAF group exceeds its saved bound");
                if (used > worst) {
                    worst = used;
                    worstGroup = g;
                    worstMix = _composition(logs);
                }
                ++runs;
                vm.revertToState(snap);
                vm.deleteStateSnapshot(snap);
            }
        }
        emit log_named_uint(label, worst);
        emit log_named_uint(string.concat(label, "_group"), worstGroup);
        emit log_named_string(string.concat(label, "_composition"), worstMix);
        emit log_named_uint(string.concat(label, "_measured_calls"), runs);
    }

    function _coldCallGas() internal view returns (uint256 used) {
        used = vm.lastCallGas().gasTotalUsed;
        if (!vm.envOr("FOUNDRY_ISOLATE", false)) used += 21_064;
    }

    /// @dev Engine accounts the award stage touches start every measured call cold.
    function _coolEngine() internal {
        vm.cool(address(game));
        vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_DRAW_MODULE);
        vm.cool(address(jackpots));
        vm.cool(address(coinflip));
    }

    function _measure(uint256 allowance)
        internal
        returns (uint256 used, MineFlipGas.Result memory result, Vm.Log[] memory logs)
    {
        _coolEngine();
        vm.recordLogs();
        result = host.dailyWith{gas: 12_000_000}(allowance);
        used = _coldCallGas();
        logs = vm.getRecordedLogs();
    }

    function _lastStage(Vm.Log[] memory logs) internal pure returns (uint8 stage) {
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE_SIG) {
                (stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
    }

    /// @dev "e ETH, r rolls on l levels (f far-future), w whale" for the group's award logs.
    function _composition(Vm.Log[] memory logs) internal pure returns (string memory) {
        uint256 eth;
        uint256 rolls;
        uint256 far;
        uint256 whales;
        uint256 seen;
        uint256 levels;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (t0 == BafSchedule.ETH_SIG) ++eth;
            else if (t0 == BafSchedule.WHALE_SIG) ++whales;
            else if (t0 == BafSchedule.TICKET_SIG) {
                ++rolls;
                uint256 t = uint256(logs[i].topics[2]);
                if (t >= 102) ++far;
                if (seen & (uint256(1) << (t - 100)) == 0) {
                    seen |= uint256(1) << (t - 100);
                    ++levels;
                }
            }
        }
        return string.concat(
            vm.toString(eth), " ETH, ", vm.toString(rolls), " rolls on ", vm.toString(levels), " levels (",
            vm.toString(far), " far-future), ", vm.toString(whales), " whale"
        );
    }

    function _assertDeclaredFits() internal pure {
        assertLe(
            GasBounds.BAF_AWARD_GROUP + GasBounds.BAF_AWARD_TAIL + GasBounds.DAILY_PHASE_TAIL
                + MineFlipGas.CHECK_RESERVE,
            CAP,
            "declared BAF group plus tails exceeds the 10M chunk limit"
        );
    }

    /// @dev A reference run of the group from the seeded state, then the views' draw of each pair on
    ///      the state it starts from; the state is back at the seeded one afterwards.
    function _referenceDraw() internal returns (address[] memory atStart, address[] memory expected, bytes32 digest) {
        uint256 pre = vm.snapshotState();
        vm.recordLogs();
        host.dailyWith{gas: 12_000_000}(ONE_GROUP_ALLOWANCE);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.revertToState(pre);
        digest = BafSchedule.chain(bytes32(0), logs);
        (BafSchedule.Award[] memory got,) = BafSchedule.awardsOf(logs);
        (atStart, expected) =
            BafPairDraw.draw(address(jackpots), address(host), pre, got, _pool(), word, start, end, _rounds());
        vm.getRecordedLogs();
        vm.deleteStateSnapshot(pre);
    }

    /// @dev One measured call pays exactly the group: the reference draw's winners with the
    ///      schedule's amounts and legs, the reservation reduced by the ETH credited; a last group
    ///      also returns the residue to the pending pool, closes the bracket and deletes the work
    ///      record.
    function _checkGroup(string memory label) internal {
        uint256 pool = _pool();
        uint256 rounds = _rounds();
        (,,, uint128 reservedBefore) = host.bafWork();
        (uint256 claimableBefore, uint256 futureBefore) = host.poolsProbe();
        uint256 levelBefore = CenturyBafScores.levelWord(address(jackpots));
        (address[] memory atStart, address[] memory expected, bytes32 refDigest) = _referenceDraw();

        (uint256 used, MineFlipGas.Result memory result, Vm.Log[] memory logs) = _measure(ONE_GROUP_ALLOWANCE);
        emit log_named_uint(label, used);
        emit log_named_string("group_composition", _composition(logs));
        emit log_named_uint("searched_distinct_roll_levels", spreadLevels);

        assertTrue(result.progressed, "one group is admitted");
        assertEq(_lastStage(logs), STAGE_JACKPOT_BAF_AWARDS, "the BAF award stage ran");
        assertEq(BafSchedule.chain(bytes32(0), logs), refDigest, "the measured call repeats the reference run");
        (BafSchedule.Award[] memory got, bool tagged) = BafSchedule.awardsOf(logs);
        assertTrue(tagged, "BAF award events carry level 100 and the BAF sentinel");
        address[] memory paid = new address[](end - start);
        uint256 credited = BafSchedule.checkGroupR(got, pool, start, end, expected, paid, rounds);
        uint256 moved;
        for (uint256 i = start; i < end; ++i) {
            if (expected[i - start] != atStart[i - start]) {
                assertTrue(i & 7 >= 4 && i >= rounds && i < 2 * rounds, "only a far-future second pair moves");
                ++moved;
            }
            if (BafSchedule.ethTermR(pool, i, rounds) != 0) {
                assertGt(host.claimableOfProbe(paid[i - start]), 0, "the ETH leg reaches a cold wallet");
            }
        }
        emit log_named_uint("positions_moved_by_own_group_rolls", moved);

        (uint8 kind, uint16 cursor,, uint128 reservedAfter) = host.bafWork();
        (uint256 claimableAfter, uint256 futureAfter) = host.poolsProbe();
        if (end < positions) {
            assertFalse(result.done, "the stage continues");
            assertEq(kind, 7, "work continues");
            assertEq(cursor, end, "exactly one group per admitted allowance");
            assertEq(reservedBefore - reservedAfter, credited, "reservation tracks the credited ETH");
            assertEq(claimableAfter, claimableBefore, "a group moves no pool");
            assertEq(futureAfter, futureBefore, "a group moves no pool");
            assertEq(CenturyBafScores.levelWord(address(jackpots)), levelBefore, "the bracket stays frozen");
        } else {
            uint256 residue = reservedBefore - credited;
            assertEq(residue, _residue(), "the residue is the unfilled earlier positions' reservation");
            assertTrue(result.done, "the last group completes the stage");
            assertEq(kind, 0, "the last group deletes the work record");
            assertEq(claimableBefore - claimableAfter, residue, "the residue leaves claimablePool");
            assertEq(futureAfter - futureBefore, residue, "and returns to the pending future pool");
            uint256 levelAfter = CenturyBafScores.levelWord(address(jackpots));
            assertEq(uint64(levelAfter), uint64(levelBefore) + 1, "the bracket epoch is bumped");
            assertEq(uint8(levelAfter >> 64), 0, "the board is emptied");
        }
        assertLe(used, GasBounds.BAF_AWARD_GROUP, "cold BAF group exceeds its saved bound");
        _assertDeclaredFits();
    }
}

/// @notice Worst scatter group: two lvl+6..lvl+99 round pairs (each pair samples four far-future
///         packs once for its two rounds), four ETH credits to cold wallets and four 2-roll ticket
///         legs (P = 100 ETH: 1.04 / 0.625 ETH awards) on the searched widest level spread.
contract BafAwardGroupGas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 9;
    }

    function _pool() internal pure override returns (uint128) {
        return 100 ether;
    }

    function test_WorstRoundGroupCold() public {
        _checkGroup("baf_band3_round_group_cold_including_intrinsic");
    }

    /// @dev An allowance below one group plus its tails progresses nothing and changes nothing.
    function test_BelowOneGroupCold() public {
        (uint256 claimableBefore,) = host.poolsProbe();
        (uint256 used, MineFlipGas.Result memory result, Vm.Log[] memory logs) = _measure(400_000);
        emit log_named_uint("baf_no_group_call_cold_including_intrinsic", used);
        assertFalse(result.progressed, "no group admitted");
        assertEq(logs.length, 0, "no award and no Advance");
        (uint8 kind, uint16 cursor,, uint128 reserved) = host.bafWork();
        assertEq(kind, 7);
        assertEq(cursor, start, "no position consumed");
        assertEq(reserved, BafSchedule.ethTerms(_pool(), start, positions), "reservation untouched");
        (uint256 claimableAfter,) = host.poolsProbe();
        assertEq(claimableAfter, claimableBefore);
    }
}

/// @notice The same mix on two lvl+2..lvl+5 round pairs (four 2048-deep levels).
contract BafAwardGroupBandTwoGas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 6;
    }

    function _pool() internal pure override returns (uint128) {
        return 100 ether;
    }

    function test_BandTwoRoundGroupCold() public {
        _checkGroup("baf_band2_round_group_cold_including_intrinsic");
    }
}

/// @notice The same mix on two level-100 trait-bucket round pairs (one packed word per round).
contract BafAwardGroupTraitGas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 0;
    }

    function _pool() internal pure override returns (uint128) {
        return 100 ether;
    }

    function test_TraitRoundGroupCold() public {
        _checkGroup("baf_trait_round_group_cold_including_intrinsic");
    }
}

/// @notice Head group with 2-roll halves (P = 100 ETH: 5 / 2.5 / 2.5 ETH lootbox halves): three
///         cold ETH credits, six rolls on the searched widest spread, the depositor draw's binary
///         search, a residue returned to the pending pool (one unfilled earlier ETH-leg award), the
///         bracket close and the work-record delete.
contract BafAwardHeadGroupGas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 12;
    }

    function _pool() internal pure override returns (uint128) {
        return 100 ether;
    }

    function _residue() internal pure override returns (uint256) {
        return BafSchedule.amount(100 ether, 0);
    }

    function test_HeadGroupCold() public {
        _checkGroup("baf_head_group_rolls_cold_including_intrinsic");
    }
}

/// @notice Head group with whale-pass halves (P = 1100 ETH: 55 / 27.5 / 27.5 ETH halves): three
///         cold ETH credits and three whale-pass queues with their claimable remainders, every
///         position filled (no residue). 1,100 ETH schedules 96 rounds: the head group is group 24.
contract BafAwardHeadWhaleGas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 96 / 4;
    }

    function _pool() internal pure override returns (uint128) {
        return 1100 ether;
    }

    function _rounds() internal pure override returns (uint256) {
        return 96;
    }

    function test_HeadWhaleGroupCold() public {
        _checkGroup("baf_head_group_whale_cold_including_intrinsic");
    }
}

/// @notice Tail probe: a last group whose three head slots are empty (a four-entry board of empty
///         players, no draw book) pays nothing, so the call is the preamble, three empty draws and
///         the completion: the residue release into the frozen pending pool, the four-entry board
///         close with the epoch bump and the work-record delete. Against
///         BafAwardGroupGas.test_BelowOneGroupCold (the preamble alone), the difference bounds the
///         completion tail BAF_AWARD_TAIL reserves.
contract BafAwardTailProbeGas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 12;
    }

    function _pool() internal pure override returns (uint128) {
        return 100 ether;
    }

    function _seedHead() internal override {
        bytes32 board = keccak256(abi.encode(uint256(100), uint256(1)));
        for (uint256 i; i < 4; ++i) {
            vm.store(address(jackpots), bytes32(uint256(board) + i), bytes32(uint256(1_000_000 + i) << 160));
        }
        bytes32 levelSlot = keccak256(abi.encode(uint256(100), uint256(2)));
        vm.store(address(jackpots), levelSlot, bytes32(uint256(vm.load(address(jackpots), levelSlot)) | (uint256(4) << 64)));
    }

    function test_TailProbeCold() public {
        uint256 headReserve = BafSchedule.ethTerms(_pool(), start, positions);
        (uint256 claimableBefore, uint256 futureBefore) = host.poolsProbe();
        uint256 levelBefore = CenturyBafScores.levelWord(address(jackpots));
        assertEq(uint8(levelBefore >> 64), 4, "a four-entry board");
        (uint256 used, MineFlipGas.Result memory result, Vm.Log[] memory logs) = _measure(ONE_GROUP_ALLOWANCE);
        emit log_named_uint("baf_tail_probe_cold_including_intrinsic", used);
        assertTrue(result.progressed && result.done, "the empty last group completes the stage");
        assertEq(_lastStage(logs), STAGE_JACKPOT_BAF_AWARDS, "the BAF award stage ran");
        (BafSchedule.Award[] memory got,) = BafSchedule.awardsOf(logs);
        assertEq(got.length, 0, "an empty slot pays nothing");
        (uint8 kind,,,) = host.bafWork();
        assertEq(kind, 0, "the work record is deleted");
        (uint256 claimableAfter, uint256 futureAfter) = host.poolsProbe();
        assertEq(claimableBefore - claimableAfter, headReserve, "unfilled slots' reservation leaves claimablePool");
        assertEq(futureAfter - futureBefore, headReserve, "and returns to the pending future pool");
        uint256 levelAfter = CenturyBafScores.levelWord(address(jackpots));
        assertEq(uint64(levelAfter), uint64(levelBefore) + 1, "the bracket epoch is bumped");
        assertEq(uint8(levelAfter >> 64), 0, "the board is emptied");
        for (uint256 i; i < 4; ++i) assertEq(CenturyBafScores.topEntry(address(jackpots), i), 0, "board entry cleared");
        assertLe(used, GasBounds.BAF_AWARD_GROUP, "the tail probe exceeds the group bound");
        _assertDeclaredFits();
    }
}

// -------------------------------------------------------------------------------------------------
// Scaled schedules: the group is a fixed eight positions whatever the round count, so the worst group
// is set by its leg mix and band, not by R. Each case is the last scatter group (band 3,
// lvl+6..lvl+99) unless noted.
// -------------------------------------------------------------------------------------------------

/// @notice 96 rounds at P = 900 ETH (4.69 / 2.81 ETH scatter awards): the same all-roll mix as the
///         48-round worst, four ETH credits and four 2-roll ticket legs.
contract BafAwardScaled96Gas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 96 / 4 - 1;
    }

    function _pool() internal pure override returns (uint128) {
        return 900 ether;
    }

    function _rounds() internal pure override returns (uint256) {
        return 96;
    }

    function test_Scaled96BandThreeGroupCold() public {
        _checkGroup("baf_r96_band3_group_cold_including_intrinsic");
    }
}

/// @notice 96 rounds at P = 900 ETH on a band-2 group (lvl+2..lvl+5).
contract BafAwardScaled96BandTwoGas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 96 / 8;
    }

    function _pool() internal pure override returns (uint128) {
        return 900 ether;
    }

    function _rounds() internal pure override returns (uint256) {
        return 96;
    }

    function test_Scaled96BandTwoGroupCold() public {
        _checkGroup("baf_r96_band2_group_cold_including_intrinsic");
    }
}

/// @notice 192 rounds at P = 2,000 ETH (5.21 / 3.125 ETH scatter awards): the best's ticket leg
///         defers to whale passes, the second's rolls twice: four ETH credits, two 2-roll legs and
///         two whale-pass legs.
contract BafAwardScaled192Gas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 192 / 4 - 1;
    }

    function _pool() internal pure override returns (uint128) {
        return 2000 ether;
    }

    function _rounds() internal pure override returns (uint256) {
        return 192;
    }

    function test_Scaled192BandThreeGroupCold() public {
        _checkGroup("baf_r192_band3_group_cold_including_intrinsic");
    }
}

/// @notice 1,536 rounds at P = 128,000 ETH (41.7 / 25 ETH scatter awards): four ETH credits and
///         four whale-pass legs.
contract BafAwardScaled1536Gas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 1536 / 4 - 1;
    }

    function _pool() internal pure override returns (uint128) {
        return 128_000 ether;
    }

    function _rounds() internal pure override returns (uint256) {
        return 1536;
    }

    function test_Scaled1536BandThreeGroupCold() public {
        _checkGroup("baf_r1536_band3_group_cold_including_intrinsic");
    }
}

/// @notice 1,536 rounds at P = 128,000 ETH: the head group (12,800 / 6,400 / 6,400 ETH awards, ETH
///         halves and whale-pass halves) with the bracket close.
contract BafAwardScaled1536HeadGas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 1536 / 4;
    }

    function _pool() internal pure override returns (uint128) {
        return 128_000 ether;
    }

    function _rounds() internal pure override returns (uint256) {
        return 1536;
    }

    function test_Scaled1536HeadGroupCold() public {
        _checkGroup("baf_r1536_head_group_cold_including_intrinsic");
    }
}

/// @notice Every far-future group of the 48-round schedule (P = 100 ETH: four ETH credits and four
///         2-roll ticket legs per group), each under its three widest-spread words.
contract BafAwardSweep48Gas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 6;
    }

    function _pool() internal pure override returns (uint128) {
        return 100 ether;
    }

    function test_SweepFarBandGroupsCold() public {
        _sweep(6, 9, 3, "baf_r48_band2_sweep_worst_cold_including_intrinsic");
        _sweep(9, 12, 3, "baf_r48_band3_sweep_worst_cold_including_intrinsic");
        _assertDeclaredFits();
    }
}

/// @notice Every far-future group of the 96-round schedule at P = 900 ETH (the same leg mix), each
///         under its two widest-spread words.
contract BafAwardSweep96Gas is BafAwardGroupFixture {
    function _group() internal pure override returns (uint256) {
        return 12;
    }

    function _pool() internal pure override returns (uint128) {
        return 900 ether;
    }

    function _rounds() internal pure override returns (uint256) {
        return 96;
    }

    function test_SweepFarBandGroupsCold() public {
        _sweep(12, 18, 2, "baf_r96_band2_sweep_worst_cold_including_intrinsic");
        _sweep(18, 24, 2, "baf_r96_band3_sweep_worst_cold_including_intrinsic");
        _assertDeclaredFits();
    }
}
