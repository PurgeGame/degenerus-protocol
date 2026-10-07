// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {AdvanceStageStream} from "../helpers/AdvanceStageStream.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title JackpotBattleStageGas — STAGE_JACKPOT_COIN_TICKETS (8) / STAGE_JACKPOT_PHASE_ENDED (9) at
///        their full winner cap, and the exact per-day stage order of a jackpot phase.
/// @notice Every jackpot-phase day's request locks its jackpot battle; the battle's own stage (16)
///         runs after the word applies (18) and before any of the day's legs. The day's ticket leg
///         then runs alone, from the stage that seals the day:
///           - STAGE_JACKPOT_COIN_TICKETS (8) / STAGE_JACKPOT_PHASE_ENDED (9):
///             the main-trait ticket leg pays its winner cap (96, doubled to 192 at 40 ETH of
///             value, 5b25fded0), each winner a fresh wallet, runs no battle work, then on every
///             non-final day `_unlockRng` seals the day in this same stage; on the final day
///             `_endPhase` runs instead (STAGE_JACKPOT_PHASE_ENDED). No leg of the day is left for
///             a later advance.
///         Every ticket winner is a distinct never-touched wallet, through the full DeployProtocol
///         wiring. The engine composes admitted checkpoints, so the leg is read from the ordered
///         log stream (AdvanceStageStream), each call at the smallest admitting realistic
///         allowance; the largest call is logged, never bounded (one ticket group is bounded per
///         chunk by JackpotTicketAwardChunks / DirectJackpotAdvanceGas). The battle's own
///         transactions are pinned by JackpotMergeAdvance.
/// @dev TEST-INFRA ONLY. No contracts/*.sol is mutated. Seeding in setUp() — a separate tx — so
///      the measured call starts cold. The seeded day records its word directly, so no battle is
///      locked ahead of the measured stage.
contract JackpotBattleStageSeeder is DegenerusGame, BucketSeed {
    struct Shape {
        uint24 lvl;
        uint256 word;
        uint8 counter; // jackpotCounter on entry: JACKPOT_DAYS - 1 is the final (phase-ending) day
        uint256 prevPool; // levelPrizePool[lvl - 1]
        uint256 ticketHolders; // distinct holders per main-trait bucket at lvl (ticket leg)
        uint256 ffHolders; // distinct holders per far-future queue at lvl+2..lvl+100
        uint160 base;
    }

    function seed(Shape calldata s, uint8[4] calldata mainTraits) external {
        // The synthetic jump models every earlier level as drained: free their recycled roots.
        TQ.retireCompleted(address(this), s.lvl);
        uint24 day = _simulatedDayIndex();
        level = s.lvl;
        purchaseStartDay = day - 10;
        dailyIdx = day - 1;
        jackpotPhaseFlag = true;
        lastPurchaseDay = false;
        jackpotFlags = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);
        jackpotCounter = s.counter;
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = s.word < 2 ? RNG_WORD_WAITING : s.word;
        _recordDailyRng(day, s.word);
        dailyFoilDraw[day & 1] = _packFoilDraw(JackpotBucketLib.packWinningTraits(mainTraits), s.lvl, day, s.word);
        vrfRequestId = 1;
        // The daily phase of a delivered, published request.
        rngRequestDay = day;
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        dailyJackpotCoinTicketsPending = true;
        // dailyEntries = 4000 (bits 8..71): 1000 whole tickets worth 40 ETH, so the cap doubles
        // to 192 winners and saturates.
        dailyTicketBudgetsPacked = uint256(4000) << 8;
        levelPrizePool[s.lvl] = 1000 ether;
        levelPrizePool[s.lvl - 1] = s.prevPool;
        _setPrizePools(uint128(50 ether), uint128(300 ether));
        currentPrizePool = uint128(200 ether);

        // Genesis deities add virtual entries naming VAULT / sDGNRS, whose seats are refused (a
        // cheaper path): exclude them so every ticket draw lands on a fresh wallet.
        deityBySymbol[VAULT_DEITY_SYMBOL] = 0;
        deityBySymbol[SDGNRS_DEITY_SYMBOL] = 0;

        for (uint8 q; q < 4; ++q) {
            _seedBucketClear(s.lvl, mainTraits[q]);
            if (s.ticketHolders != 0) {
                _seedBucketDistinct(s.lvl, mainTraits[q], s.ticketHolders, s.base + uint160(q) * 0x100000);
            }
        }

        // Populated far-future queues, levels lvl+2..lvl+100, distinct fresh wallets only.
        if (s.ffHolders != 0) {
            for (uint24 c = s.lvl + 2; c <= s.lvl + 100; ++c) {
                uint160 b = s.base + 0x2000000 + uint160(c - s.lvl - 2) * 0x1000;
                for (uint256 i; i < s.ffHolders; ++i) {
                    _tqAppend(_tqFarFutureKey(c), _seedWallet(address(b + uint160(i + 1))));
                }
            }
        }
    }
}

abstract contract JackpotBattleStageFixture is AdvanceStageStream {
    uint256 internal constant GAS_TARGET = 10_000_000;

    bytes32 internal constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant TICKET_BATCH_SIG =
        keccak256("JackpotTicketBatchWin(uint24,uint24,uint16,uint16,uint8,uint32,uint256[4],uint256[4])");
    bytes32 internal constant BATTLE_ENTRY_SIG = keccak256("JackpotBattleEntry(uint64,uint256,uint32,uint256,uint32)");

    uint8 internal constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    // 1000 whole tickets worth 40 ETH: the 96-winner cap doubles (5b25fded0).
    uint256 internal constant TICKET_MAX = 192;

    struct Tally {
        uint8 stage;
        uint256 tickets;
        uint256 ticketDistinct;
        uint256 battleEntries;
    }

    function _shape() internal pure virtual returns (JackpotBattleStageSeeder.Shape memory s);

    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp((uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + intoDay);
    }

    function _setUpSeeded() internal {
        _deployProtocol();
        JackpotBattleStageSeeder.Shape memory s = _shape();
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(s.word);
        mainT[3] = GoldSixLib.daily(mainT[3], s.word);
        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(JackpotBattleStageSeeder).runtimeCode);
        JackpotBattleStageSeeder(payable(address(game))).seed(s, mainT);
        vm.etch(address(game), realCode);
        vm.deal(address(game), 10_000 ether);
    }

    /// @dev Registry owner of zero-based index `idx` (ticketOwners, slot 67).
    function _ownerAt(uint256 idx) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(game), bytes32(uint256(keccak256(abi.encode(GameSlots.WALLETS))) + idx)))));
    }

    /// @dev The coin+tickets leg from the stream: its partial calls mark stage 8; a final day's
    ///      completing call marks stage 9, so a run of 8s followed by 9 is one leg. Ticket winners
    ///      are queued (JackpotTicketWin) or, while the next-level buffer is live, materialized
    ///      directly (JackpotTicketBatchWin with registry owner IDs, 95d88f68b).
    function _measure() internal returns (uint256 used, Tally memory t) {
        (uint8 stage, uint256 from, uint256 to, uint256 maxGas) = _nextStageRun(200);
        if (stage == STAGE_JACKPOT_COIN_TICKETS && game.rngLocked()) {
            uint256 g;
            (stage,, to, g) = _nextStageRun(200);
            if (g > maxGas) maxGas = g;
        }
        used = maxGas;
        t.stage = stage;
        address[] memory tk = new address[](TICKET_MAX + 8);
        for (uint256 i = from; i <= to; ++i) {
            Vm.Log storage l = streamLogs[i];
            if (l.topics.length == 0) continue;
            bytes32 t0 = l.topics[0];
            if (t0 == TICKET_WIN_SIG) {
                if (_pushDistinct(tk, t.tickets, address(uint160(uint256(l.topics[1]))))) ++t.ticketDistinct;
                ++t.tickets;
            } else if (t0 == TICKET_BATCH_SIG) {
                (, uint8 count,, uint256[4] memory owners,) = abi.decode(l.data, (uint16, uint8, uint32, uint256[4], uint256[4]));
                for (uint256 j; j < count; ++j) {
                    address player = _ownerAt(uint32(owners[j >> 3] >> (32 * (j & 7))));
                    if (_pushDistinct(tk, t.tickets, player)) ++t.ticketDistinct;
                    ++t.tickets;
                }
            } else if (t0 == BATTLE_ENTRY_SIG) {
                ++t.battleEntries;
            }
        }
        emit log_named_uint("  largest_call_gas_incl_intrinsic", used);
        emit log_named_uint("  stage", t.stage);
        emit log_named_uint("  ticket_wins", t.tickets);
        emit log_named_uint("  ticket_distinct", t.ticketDistinct);
        emit log_named_uint("  jackpot_battle_entries", t.battleEntries);
        emit log_named_uint("  over_10M_target_by", used > GAS_TARGET ? used - GAS_TARGET : 0);
    }

    function _pushDistinct(address[] memory arr, uint256 n, address w) private pure returns (bool fresh) {
        fresh = true;
        for (uint256 j; j < n && j < arr.length; ++j) {
            if (arr[j] == w) {
                fresh = false;
                break;
            }
        }
        if (n < arr.length) arr[n] = w;
    }
}

/// @notice Non-final jackpot day at L=110 (0.04 ETH): the coin+tickets stage alone pays 192 cold
///         ticket winners and runs no battle work; the day seals in this stage.
contract JackpotTicketOnlyOrdinaryDay is JackpotBattleStageFixture {
    function _shape() internal pure override returns (JackpotBattleStageSeeder.Shape memory s) {
        s.lvl = 110;
        s.word = uint256(keccak256("jackpot-battle-stage-day")) | 1;
        s.counter = 1;
        s.prevPool = 20_000 ether;
        s.ticketHolders = 20_000;
        // Seeded even though unused: the ticket stage runs no battle work while unminted queues
        // are populated.
        s.ffHolders = 8;
        s.base = uint160(0x1000000000);
    }

    function setUp() public {
        _setUpSeeded();
    }

    function test_JackpotTicketOnlyStage_96Tickets_NoBattle_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_COIN_TICKETS_ORDINARY_DAY_GAS", used);
        assertEq(t.stage, STAGE_JACKPOT_COIN_TICKETS, "the coin+tickets stage ran");
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 192-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleEntries, 0, "the coin+tickets stage runs no battle work");
    }
}

/// @notice FINAL jackpot day at an x0 level L=110: the same ticket-only cap plus `_endPhase`.
contract JackpotTicketOnlyPhaseEndX0 is JackpotBattleStageFixture {
    function _shape() internal pure override returns (JackpotBattleStageSeeder.Shape memory s) {
        s.lvl = 110;
        s.word = uint256(keccak256("jackpot-battle-stage-phase-end-x0")) | 1;
        s.counter = 2;
        s.prevPool = 20_000 ether;
        s.ticketHolders = 20_000;
        s.ffHolders = 8;
        s.base = uint160(0x1000000000);
    }

    function setUp() public {
        _setUpSeeded();
    }

    function test_JackpotTicketOnlyStage_96Tickets_NoBattle_EndPhase_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_COIN_TICKETS_PHASE_END_X0_GAS", used);
        assertEq(t.stage, STAGE_JACKPOT_PHASE_ENDED, "the phase-end stage ran");
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 192-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleEntries, 0, "the coin+tickets stage runs no battle work");
    }
}

/// @notice FINAL jackpot day at the x00 level L=100 (0.24 ETH): the same ticket-only cap plus
///         `_endPhase`.
contract JackpotTicketOnlyPhaseEndX00 is JackpotBattleStageFixture {
    function _shape() internal pure override returns (JackpotBattleStageSeeder.Shape memory s) {
        s.lvl = 100;
        s.word = uint256(keccak256("jackpot-battle-stage-phase-end-x00")) | 1;
        s.counter = 2;
        s.prevPool = 150_000 ether;
        s.ticketHolders = 20_000;
        s.ffHolders = 8;
        s.base = uint160(0x1000000000);
    }

    function setUp() public {
        _setUpSeeded();
    }

    function test_JackpotTicketOnlyStage_96Tickets_NoBattle_EndPhaseX00_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_COIN_TICKETS_PHASE_END_X00_GAS", used);
        assertEq(t.stage, STAGE_JACKPOT_PHASE_ENDED, "the phase-end stage ran");
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 192-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleEntries, 0, "the coin+tickets stage runs no battle work");
    }
}

/// @title JackpotPhaseStageSequence — proves the retired stage 13 never runs and that a jackpot
///        phase's per-day stage sequence is exactly word apply (18), battle (16), ETH (10),
///        early-bird (14, day 1), then coin+tickets (8, or 9 on the final day).
/// @notice Drives a REAL protocol (DeployProtocol, real mineFlip, real mock VRF) through a
///         whole standard (3-day) jackpot phase and a turbo (1-day) one, recording every
///         Advance(uint8,uint24) log. Filtered to {18, 16, 10, 14, 8, 9}, the sequence must be
///         exactly: day 1 -> 18, 16, 10, 14, 8 (or 18, 16, 10, 14, 9 on a turbo's one and only,
///         final day); a non-final standard day -> 18, 16, 10, 8; the standard final day ->
///         18, 16, 10, 9. Stage 13 must never appear anywhere in the unfiltered log. No far-future
///         wallets are seeded, so each day's battle seals its empty field and completes in one step.
contract JackpotPhaseStageSequence is DeployProtocol {
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");
    uint8 internal constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant STAGE_JACKPOT_DAILY_STARTED = 10;
    uint8 internal constant STAGE_JACKPOT_CARRYOVER_RETIRED = 13;
    uint8 internal constant STAGE_JACKPOT_EARLY_BIRD_TICKETS = 14;
    uint8 internal constant STAGE_JACKPOT_BATTLE = 16;
    uint8 internal constant STAGE_RNG_APPLIED = 18;

    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp((uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + intoDay);
    }

    /// @dev Fresh jackpot-phase entry at day 400, counter 0, no request outstanding yet: the
    ///      loop below fires the day's own real VRF request on its first mineFlip() call.
    function _seedFreshPhase(uint24 lvl, uint8 flags) internal {
        _deployProtocol();
        _warpToDay(400, 3 hours);
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(JackpotPhaseSeeder).runtimeCode);
        JackpotPhaseSeeder(payable(address(game))).seedFreshPhase(lvl, flags);
        vm.etch(address(game), realCode);
        vm.deal(address(game), 10_000 ether);
    }

    /// @dev Drives `daysToRun` full jackpot physical days for real: fulfils any pending VRF
    ///      request, advances, records EVERY stage marker of each call in order (the engine
    ///      composes admitted checkpoints, so one call can carry several stages), and warps one wall
    ///      day forward once a day seals (stage 8 or 9) so the next physical day gets its own fresh
    ///      request. The synthetic day-400 jump first retires expired Craps maintenance (one
    ///      checkpoint per call, no marker). Partial checkpoints repeat their stage's marker; the
    ///      filter below collapses a stage's repeats.
    function _driveJackpotPhase(uint256 daysToRun) internal returns (uint8[] memory stages) {
        uint8[] memory buf = new uint8[](256);
        uint256 n;
        uint256 daysSealed;
        uint256 guard;
        while (daysSealed < daysToRun && guard < 2000) {
            unchecked { ++guard; }
            uint256 id = mockVRF.lastRequestId();
            if (id != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(id);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("phase-sequence", guard))) | 2);
                }
            }
            vm.recordLogs();
            game.mineFlip();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool sealedNow;
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].topics.length == 0 || logs[j].topics[0] != ADVANCE_SIG) continue;
                (uint8 st,) = abi.decode(logs[j].data, (uint8, uint24));
                require(n < buf.length, "sequence: guard buffer too small");
                buf[n++] = st;
                assertTrue(st != STAGE_JACKPOT_CARRYOVER_RETIRED, "stage 13 (the retired carryover leg) must never run");
                if (st == STAGE_JACKPOT_COIN_TICKETS || st == STAGE_JACKPOT_PHASE_ENDED) sealedNow = true;
            }
            if (sealedNow) {
                (, bool inJackpot,,,) = game.purchaseInfo();
                if (inJackpot) {
                    // A non-final day's own stage unlocks the day it just sealed (the final day's
                    // STAGE_JACKPOT_PHASE_ENDED instead keeps the lock through the transition).
                    assertFalse(game.rngLocked(), "the coin+tickets stage must unlock a non-final day");
                }
                unchecked { ++daysSealed; }
                if (daysSealed < daysToRun) vm.warp(block.timestamp + 1 days);
            }
        }
        assertEq(daysSealed, daysToRun, "the jackpot phase must fully seal every requested day");
        stages = new uint8[](n);
        for (uint256 k; k < n; ++k) stages[k] = buf[k];
    }

    /// @dev Keeps only the jackpot-day stages {18, 16, 10, 14, 8, 9}, in order, collapsing a stage's
    ///      repeated partial-checkpoint markers; a final day's partial coin+tickets markers (8)
    ///      belong to the leg its completing call marks 9.
    function _filterJackpotStages(uint8[] memory stages) internal pure returns (uint8[] memory filtered) {
        uint8[] memory buf = new uint8[](stages.length);
        uint256 n;
        for (uint256 i; i < stages.length; ++i) {
            uint8 s = stages[i];
            if (s == STAGE_RNG_APPLIED || s == STAGE_JACKPOT_BATTLE || s == STAGE_JACKPOT_DAILY_STARTED
                || s == STAGE_JACKPOT_EARLY_BIRD_TICKETS || s == STAGE_JACKPOT_COIN_TICKETS
                || s == STAGE_JACKPOT_PHASE_ENDED) {
                if (n != 0 && buf[n - 1] == s) continue;
                if (s == STAGE_JACKPOT_PHASE_ENDED && n != 0 && buf[n - 1] == STAGE_JACKPOT_COIN_TICKETS) {
                    buf[n - 1] = s;
                    continue;
                }
                buf[n++] = s;
            }
        }
        filtered = new uint8[](n);
        for (uint256 k; k < n; ++k) filtered[k] = buf[k];
    }

    function _assertSequence(uint8[] memory got, uint8[] memory want) internal {
        assertEq(got.length, want.length, "jackpot-day stage sequence has the wrong length");
        for (uint256 i; i < want.length; ++i) {
            assertEq(got[i], want[i], "jackpot-day stage sequence diverged");
        }
    }

    function test_StandardThreeDayPhase_ExactStageSequence() public {
        _seedFreshPhase(110, 0);
        uint8[] memory filtered = _filterJackpotStages(_driveJackpotPhase(3));
        uint8[] memory want = new uint8[](13);
        want[0] = STAGE_RNG_APPLIED;
        want[1] = STAGE_JACKPOT_BATTLE;
        want[2] = STAGE_JACKPOT_DAILY_STARTED;
        want[3] = STAGE_JACKPOT_EARLY_BIRD_TICKETS;
        want[4] = STAGE_JACKPOT_COIN_TICKETS;
        want[5] = STAGE_RNG_APPLIED;
        want[6] = STAGE_JACKPOT_BATTLE;
        want[7] = STAGE_JACKPOT_DAILY_STARTED;
        want[8] = STAGE_JACKPOT_COIN_TICKETS;
        want[9] = STAGE_RNG_APPLIED;
        want[10] = STAGE_JACKPOT_BATTLE;
        want[11] = STAGE_JACKPOT_DAILY_STARTED;
        want[12] = STAGE_JACKPOT_PHASE_ENDED;
        _assertSequence(filtered, want);
    }

    function test_TurboOneDayPhase_ExactStageSequence() public {
        _seedFreshPhase(110, JACKPOT_TURBO_FLAG);
        uint8[] memory filtered = _filterJackpotStages(_driveJackpotPhase(1));
        uint8[] memory want = new uint8[](5);
        want[0] = STAGE_RNG_APPLIED;
        want[1] = STAGE_JACKPOT_BATTLE;
        want[2] = STAGE_JACKPOT_DAILY_STARTED;
        want[3] = STAGE_JACKPOT_EARLY_BIRD_TICKETS;
        want[4] = STAGE_JACKPOT_PHASE_ENDED;
        _assertSequence(filtered, want);
    }

    uint8 internal constant JACKPOT_TURBO_FLAG = 1;
}

contract JackpotPhaseSeeder is DegenerusGame {
    /// @notice Fresh jackpot-phase entry: day 400, counter 0, no VRF request outstanding.
    function seedFreshPhase(uint24 lvl, uint8 flags) external {
        // The synthetic jump models every earlier level as drained: free their recycled roots.
        TQ.retireCompleted(address(this), lvl);
        uint24 day = _simulatedDayIndex();
        level = lvl;
        purchaseStartDay = day - 10;
        dailyIdx = day - 1;
        jackpotPhaseFlag = true;
        lastPurchaseDay = false;
        jackpotFlags = flags;
        jackpotCounter = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
        rngLockedFlag = false;
        rngRequestTime = 0;
        rngWordCurrent = RNG_WORD_WAITING;
        vrfRequestId = 0;
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
        _afkingResetDay = day;
        levelPrizePool[lvl] = 1000 ether;
        levelPrizePool[lvl - 1] = 1000 ether;
        // Small pools: each day's own ticket leg then queues only a handful of mint entries
        // at lvl+1, so the write-budgeted STAGE_TICKETS_WORKING drain the next day's request
        // triggers for them finishes in one chunk instead of stretching this sequence check
        // over dozens of advances. The sequence and stage-13 checks do not depend on winner
        // counts.
        _setPrizePools(uint128(5 ether), uint128(10 ether));
        currentPrizePool = uint128(15 ether);
    }
}
