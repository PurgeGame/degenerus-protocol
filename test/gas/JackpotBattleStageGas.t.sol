// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @title JackpotBattleStageGas — STAGE_JACKPOT_COIN_TICKETS (8) / STAGE_JACKPOT_PHASE_ENDED (9) at
///        their full worst case, and the exact per-day stage order of a jackpot phase.
/// @notice Every jackpot-phase day's request locks its jackpot battle; the battle's own stage (16)
///         runs after the word applies (18) and before any of the day's legs. The day's ticket leg
///         then runs alone, from the stage that seals the day:
///           - STAGE_JACKPOT_COIN_TICKETS (8) / STAGE_JACKPOT_PHASE_ENDED (9):
///             `payDailyJackpotCoinAndTickets` distributes the current level's main-trait ticket
///             winners (TICKET_JACKPOT_MAX_WINNERS = 96), each a fresh registry + queue + owed
///             write, runs no battle work, then on every non-final day `_unlockRng` seals the day
///             in this same stage; on the final day `_endPhase` runs instead
///             (STAGE_JACKPOT_PHASE_ENDED). No leg of the day is left for a later advance.
///         Every ticket winner is a distinct never-touched wallet, through the full DeployProtocol
///         wiring. Each call is capped at the EIP-7825 limit less intrinsic; the figure includes
///         the 21,064 intrinsic. The battle's own transactions are pinned by JackpotMergeAdvance.
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
        vrfRequestId = 1;
        dailyJackpotCoinTicketsPending = true;
        // dailyEntries = 4000 (bits 8..71): 1000 whole tickets, so the 96-winner cap saturates.
        dailyTicketBudgetsPacked = uint256(4000) << 8;
        levelPrizePool[s.lvl] = 1000 ether;
        levelPrizePool[s.lvl - 1] = s.prevPool;
        _setPrizePools(uint128(50 ether), uint128(300 ether));
        currentPrizePool = uint128(200 ether);

        // Genesis deities add virtual entries naming VAULT / sDGNRS, whose seats are refused (a
        // cheaper path): exclude them so every ticket draw lands on a fresh wallet.
        deityBySymbol[VAULT_DEITY_SYMBOL] = address(0);
        deityBySymbol[SDGNRS_DEITY_SYMBOL] = address(0);

        if (ticketOwners.length == 0) _registerEntryOwner(address(1), s.lvl);
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
                    _tqAppend(_tqFarFutureKey(c), uint32(_registerEntryOwner(address(b + uint160(i + 1)), c) >> OWNER_IDX_SHIFT));
                }
            }
        }
    }
}

abstract contract JackpotBattleStageFixture is DeployProtocol {
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    uint256 internal constant GAS_TARGET = 10_000_000;
    uint256 internal constant INTRINSIC = 21_064;

    bytes32 internal constant TICKET_WIN_SIG =
        keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant BATTLE_ENTRY_SIG = keccak256("JackpotBattleEntry(uint64,uint256,address,uint256,uint32)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint256 internal constant TICKET_MAX = 96;

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
        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(JackpotBattleStageSeeder).runtimeCode);
        JackpotBattleStageSeeder(payable(address(game))).seed(s, mainT);
        vm.etch(address(game), realCode);
        vm.deal(address(game), 10_000 ether);
    }

    function _measure() internal returns (uint256 used, Tally memory t) {
        vm.recordLogs();
        uint256 g0 = gasleft();
        game.advanceGame{gas: EIP7825_TX_GAS_CAP - INTRINSIC}();
        used = g0 - gasleft() + INTRINSIC;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address[] memory tk = new address[](TICKET_MAX + 8);
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = logs[i].topics[0];
            if (t0 == TICKET_WIN_SIG) {
                if (_pushDistinct(tk, t.tickets, address(uint160(uint256(logs[i].topics[1]))))) ++t.ticketDistinct;
                ++t.tickets;
            } else if (t0 == BATTLE_ENTRY_SIG) {
                ++t.battleEntries;
            } else if (t0 == ADVANCE_SIG) {
                (t.stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
        emit log_named_uint("  tx_gas_incl_intrinsic", used);
        emit log_named_uint("  stage", t.stage);
        emit log_named_uint("  ticket_wins", t.tickets);
        emit log_named_uint("  ticket_distinct", t.ticketDistinct);
        emit log_named_uint("  jackpot_battle_entries", t.battleEntries);
        emit log_named_uint("  headroom_to_16p7M", used < EIP7825_TX_GAS_CAP ? EIP7825_TX_GAS_CAP - used : 0);
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

/// @notice Non-final jackpot day at L=110 (0.04 ETH): the coin+tickets stage alone pays 96 cold
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
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 96-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleEntries, 0, "the coin+tickets stage runs no battle work");
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
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
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 96-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleEntries, 0, "the coin+tickets stage runs no battle work");
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
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
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 96-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleEntries, 0, "the coin+tickets stage runs no battle work");
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }
}

/// @title JackpotPhaseStageSequence — proves the retired stage 13 never runs and that a jackpot
///        phase's per-day stage sequence is exactly word apply (18), battle (16), ETH (10),
///        early-bird (14, day 1), then coin+tickets (8, or 9 on the final day).
/// @notice Drives a REAL protocol (DeployProtocol, real advanceGame, real mock VRF) through a
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
    ///      loop below fires the day's own real VRF request on its first advanceGame() call.
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
    ///      request, advances, records the stage, and warps one wall day forward once a day
    ///      seals (stage 8 or 9) so the next physical day gets its own fresh request — a
    ///      calendar-day boundary a real deployment gets for free from wall-clock time. A fresh
    ///      day's own request may first drain a STAGE_TICKETS_WORKING (5) chunk minting the
    ///      previous day's ticket-leg winners into their queued trait entries; the raw stage list
    ///      carries it, but it is not one of the jackpot-day stages `_filterJackpotStages` checks.
    function _driveJackpotPhase(uint256 daysToRun) internal returns (uint8[] memory stages) {
        uint8[] memory buf = new uint8[](128);
        uint256 n;
        uint256 daysSealed;
        uint256 guard;
        while (daysSealed < daysToRun && guard < 100) {
            unchecked { ++guard; }
            uint256 id = mockVRF.lastRequestId();
            if (id != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(id);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("phase-sequence", guard))) | 1);
                }
            }
            vm.recordLogs();
            game.advanceGame();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint8 st = 255;
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].topics[0] == ADVANCE_SIG) (st,) = abi.decode(logs[j].data, (uint8, uint24));
            }
            require(n < buf.length, "sequence: guard buffer too small");
            buf[n++] = st;
            assertTrue(st != STAGE_JACKPOT_CARRYOVER_RETIRED, "stage 13 (the retired carryover leg) must never run");
            if (st == STAGE_JACKPOT_COIN_TICKETS) {
                // A non-final day's own stage unlocks the day it just sealed (the final day's
                // STAGE_JACKPOT_PHASE_ENDED instead keeps the lock held through the phase
                // transition, so this check is specific to the non-final branch).
                assertFalse(game.rngLocked(), "the coin+tickets stage must unlock a non-final day");
            }
            if (st == STAGE_JACKPOT_COIN_TICKETS || st == STAGE_JACKPOT_PHASE_ENDED) {
                unchecked { ++daysSealed; }
                if (daysSealed < daysToRun) vm.warp(block.timestamp + 1 days);
            }
        }
        assertEq(daysSealed, daysToRun, "the jackpot phase must fully seal every requested day");
        stages = new uint8[](n);
        for (uint256 k; k < n; ++k) stages[k] = buf[k];
    }

    /// @dev Keeps only the jackpot-day stages {18, 16, 10, 14, 8, 9}, in order.
    function _filterJackpotStages(uint8[] memory stages) internal pure returns (uint8[] memory filtered) {
        uint8[] memory buf = new uint8[](stages.length);
        uint256 n;
        for (uint256 i; i < stages.length; ++i) {
            uint8 s = stages[i];
            if (s == STAGE_RNG_APPLIED || s == STAGE_JACKPOT_BATTLE || s == STAGE_JACKPOT_DAILY_STARTED
                || s == STAGE_JACKPOT_EARLY_BIRD_TICKETS || s == STAGE_JACKPOT_COIN_TICKETS
                || s == STAGE_JACKPOT_PHASE_ENDED) {
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
