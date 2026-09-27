// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @title JackpotBattleStageGas — STAGE_JACKPOT_BATTLE (16) and STAGE_JACKPOT_COIN_TICKETS (8) /
///        STAGE_JACKPOT_PHASE_ENDED (9) at their full worst cases, as two SEPARATE advance txs.
/// @notice A jackpot-phase daily whose FLIP budget is nonzero latches the jackpot battle
///         (`_JACKPOT_BATTLE_PENDING`) from its own ETH stage. The next advance runs it alone,
///         from its own stage:
///           - STAGE_JACKPOT_BATTLE (16): `payJackpotPhaseBattle` -> `_playJackpotBattle(lvl + 1, ...)`:
///             up to JACKPOT_BATTLE_ENTRANTS = 50 distinct wallets walked from the far-future queues
///             of levels lvl+2..lvl+100, played as one closed JackpotBattle and credited in one
///             creditFlipBatch. It touches no ticket-board state.
///         The advance after it runs the day's ticket leg alone, from the stage that seals the day:
///           - STAGE_JACKPOT_COIN_TICKETS (8) / STAGE_JACKPOT_PHASE_ENDED (9):
///             `payDailyJackpotCoinAndTickets` distributes the current level's main-trait ticket
///             winners (TICKET_JACKPOT_MAX_WINNERS = 96), each a fresh registry + queue + owed
///             write, runs no battle work, then on every non-final day `_unlockRng` seals the day
///             in this same stage; on the final day `_endPhase` runs instead
///             (STAGE_JACKPOT_PHASE_ENDED). No leg of the day is left for a later advance.
///         Every battle wallet and every ticket winner is a distinct never-touched wallet, through
///         the full DeployProtocol wiring (real Game, real JackpotBattle, real Coinflip). Each
///         call is capped at the EIP-7825 limit less intrinsic; the figure includes the 21,064
///         intrinsic.
/// @dev TEST-INFRA ONLY. No contracts/*.sol is mutated. Seeding in setUp() — a separate tx — so
///      the measured call starts cold. The day's word is applied by the ETH stage
///      (STAGE_JACKPOT_DAILY_STARTED) earlier; neither measured stage ever shares a tx with it.
contract JackpotBattleStageSeeder is DegenerusGame, BucketSeed {
    struct Shape {
        uint24 lvl;
        uint256 word;
        uint8 counter; // jackpotCounter on entry: JACKPOT_DAYS - 1 is the final (phase-ending) day
        uint256 prevPool; // levelPrizePool[lvl - 1]: the jackpot battle's coin budget
        uint256 ticketHolders; // distinct holders per main-trait bucket at lvl (ticket leg)
        uint256 ffHolders; // distinct holders per far-future queue at lvl+2..lvl+100 (jackpot battle)
        uint160 base;
    }

    /// @param battlePending Latches STAGE_JACKPOT_BATTLE (mirrors what Phase 1 leaves when the day's
    ///        FLIP budget is nonzero); false leaves the day to fall straight to the coin+tickets
    ///        stage, mirroring the state Phase 1 leaves when payJackpotPhaseBattle has already run (or
    ///        the day carries no FLIP budget at all).
    function seed(Shape calldata s, uint8[4] calldata mainTraits, bool battlePending) external {
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
        rngWordCurrent = s.word;
        rngWordByDay[day] = s.word;
        vrfRequestId = 1;
        dailyJackpotCoinTicketsPending = true;
        // dailyEntries = 4000 (bits 8..71): 1000 whole tickets, so the 96-winner cap saturates.
        // The battle-pending bit (72) is the only other live field: the coin+tickets stage zeroes
        // the whole word once it runs.
        dailyTicketBudgetsPacked = (uint256(4000) << 8) | (battlePending ? _JACKPOT_BATTLE_PENDING : 0);
        levelPrizePool[s.lvl] = 1000 ether;
        levelPrizePool[s.lvl - 1] = s.prevPool;
        _setPrizePools(uint128(50 ether), uint128(300 ether));
        currentPrizePool = uint128(200 ether);

        // Genesis deities add virtual entries naming VAULT / sDGNRS, whose seats are refused (a
        // cheaper path): exclude them so every ticket draw lands on a fresh wallet.
        deityBySymbol[VAULT_DEITY_SYMBOL] = address(0);
        deityBySymbol[SDGNRS_DEITY_SYMBOL] = address(0);

        if (lvlEntryOwner[s.lvl].length == 0) lvlEntryOwner[s.lvl].push(EntryOwner(address(1), 0));
        for (uint8 q; q < 4; ++q) {
            _seedBucketClear(s.lvl, mainTraits[q]);
            if (s.ticketHolders != 0) {
                _seedBucketDistinct(s.lvl, mainTraits[q], s.ticketHolders, s.base + uint160(q) * 0x100000);
            }
        }

        // The jackpot battle's far-future queues: levels lvl+2..lvl+100, distinct fresh wallets only.
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
    bytes32 internal constant BATTLE_RUN_SIG =
        keccak256("JackpotBattleRun(uint24,address,uint256,uint256,uint256,uint256,uint32)");
    bytes32 internal constant BATTLE_POT_SIG = keccak256("JackpotBattlePot(uint24,address,uint256)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant STAGE_JACKPOT_BATTLE = 16;
    uint256 internal constant TICKET_MAX = 96;
    uint256 internal constant JACKPOT_BATTLE_ENTRANTS = 50;

    struct Tally {
        uint8 stage;
        uint256 tickets;
        uint256 ticketDistinct;
        uint256 battleRuns;
        uint256 battleDistinct;
        uint256 battlePaidTotal;
        uint256 battlePot;
    }

    function _shape() internal pure virtual returns (JackpotBattleStageSeeder.Shape memory s);

    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp((uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + intoDay);
    }

    function _setUpWith(bool battlePending) internal {
        _deployProtocol();
        JackpotBattleStageSeeder.Shape memory s = _shape();
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(s.word);
        bytes memory realCode = address(game).code;
        _warpToDay(400, 3 hours);
        vm.etch(address(game), type(JackpotBattleStageSeeder).runtimeCode);
        JackpotBattleStageSeeder(payable(address(game))).seed(s, mainT, battlePending);
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
        address[] memory bw = new address[](JACKPOT_BATTLE_ENTRANTS + 8);
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = logs[i].topics[0];
            if (t0 == TICKET_WIN_SIG) {
                if (_pushDistinct(tk, t.tickets, address(uint160(uint256(logs[i].topics[1]))))) ++t.ticketDistinct;
                ++t.tickets;
            } else if (t0 == BATTLE_RUN_SIG) {
                address w = address(uint160(uint256(logs[i].topics[2])));
                if (_pushDistinct(bw, t.battleRuns, w)) ++t.battleDistinct;
                (, , , uint256 paid) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                t.battlePaidTotal += paid;
                ++t.battleRuns;
            } else if (t0 == BATTLE_POT_SIG) {
                t.battlePot = abi.decode(logs[i].data, (uint256));
            } else if (t0 == ADVANCE_SIG) {
                (t.stage,) = abi.decode(logs[i].data, (uint8, uint24));
            }
        }
        emit log_named_uint("  tx_gas_incl_intrinsic", used);
        emit log_named_uint("  stage", t.stage);
        emit log_named_uint("  ticket_wins", t.tickets);
        emit log_named_uint("  ticket_distinct", t.ticketDistinct);
        emit log_named_uint("  jackpot_battle_runs", t.battleRuns);
        emit log_named_uint("  fill_battle_distinct", t.battleDistinct);
        emit log_named_uint("  jackpot_battle_paid_total", t.battlePaidTotal);
        emit log_named_uint("  jackpot_battle_pot", t.battlePot);
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

    /// @dev Check the measured transaction directly. The maximum-work composition test
    ///      replaces its measured battle with an allowance; it never adds a second battle.
    function _assertBattleCaps(uint256 used) internal {
        assertLt(used, 10_500_000, "fill exceeds the 10.5M design limit");
    }

}

/// @notice STAGE_JACKPOT_BATTLE alone: the full 50-entrant jackpot battle, no ticket-board work.
contract JackpotBattleStageOnly is JackpotBattleStageFixture {
    function _shape() internal pure override returns (JackpotBattleStageSeeder.Shape memory s) {
        s.lvl = 110;
        s.word = uint256(keccak256("jackpot-battle-stage-only")) | 1;
        s.counter = 1;
        s.prevPool = 20_000 ether; // B = 1,250,000 FLIP at 0.04 ETH: stakes far above the 15,000
            // FLIP the battle needs to saturate all 50 units.
        s.ticketHolders = 0; // the ticket leg is not reached from this stage
        s.ffHolders = 8;
        s.base = uint160(0x1000000000);
    }

    function setUp() public {
        _setUpWith(true);
    }

    function test_JackpotBattleStage_50Runs_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_BATTLE_STAGE_GAS", used);
        assertEq(t.stage, STAGE_JACKPOT_BATTLE, "the battle stage ran");
        assertEq(t.battleRuns, JACKPOT_BATTLE_ENTRANTS, "the jackpot battle ran fewer than 50 entrants");
        assertEq(t.battleDistinct, JACKPOT_BATTLE_ENTRANTS, "every battle run is a distinct cold wallet");
        assertEq(t.tickets, 0, "the battle stage touches no ticket-board state");
        _assertBattleCaps(used);
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
        // Seeded even though unused: proves the ticket-only stage skips the battle because the
        // latch says so, not because there is nobody to play.
        s.ffHolders = 8;
        s.base = uint160(0x1000000000);
    }

    function setUp() public {
        _setUpWith(false);
    }

    function test_JackpotTicketOnlyStage_96Tickets_NoBattle_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_COIN_TICKETS_ORDINARY_DAY_GAS", used);
        assertEq(t.stage, STAGE_JACKPOT_COIN_TICKETS, "the coin+tickets stage ran");
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 96-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleRuns, 0, "the coin+tickets stage runs no battle work: the battle stage owns it");
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
        _setUpWith(false);
    }

    function test_JackpotTicketOnlyStage_96Tickets_NoBattle_EndPhase_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_COIN_TICKETS_PHASE_END_X0_GAS", used);
        assertEq(t.stage, STAGE_JACKPOT_PHASE_ENDED, "the phase-end stage ran");
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 96-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleRuns, 0, "the coin+tickets stage runs no battle work: the battle stage owns it");
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
        s.prevPool = 150_000 ether; // B = 1,562,500 FLIP at 0.24 ETH
        s.ticketHolders = 20_000;
        s.ffHolders = 8;
        s.base = uint160(0x1000000000);
    }

    function setUp() public {
        _setUpWith(false);
    }

    function test_JackpotTicketOnlyStage_96Tickets_NoBattle_EndPhaseX00_Measured() public {
        (uint256 used, Tally memory t) = _measure();
        emit log_named_uint("JACKPOT_COIN_TICKETS_PHASE_END_X00_GAS", used);
        assertEq(t.stage, STAGE_JACKPOT_PHASE_ENDED, "the phase-end stage ran");
        assertEq(t.tickets, TICKET_MAX, "the ticket leg paid the full 96-winner cap");
        assertEq(t.ticketDistinct, TICKET_MAX, "every ticket winner is a distinct cold wallet");
        assertEq(t.battleRuns, 0, "the coin+tickets stage runs no battle work: the battle stage owns it");
        assertLt(used, EIP7825_TX_GAS_CAP, "clears EIP-7825");
    }
}

/// @title JackpotPhaseStageSequence — proves the retired stage 13 never runs and that a jackpot
///        phase's per-day stage sequence is exactly ETH (10), early-bird (14, day 1), fill (16,
///        every day with a FLIP budget), then coin+tickets (8, or 9 on the final day).
/// @notice Drives a REAL protocol (DeployProtocol, real advanceGame, real mock VRF) through a
///         whole standard (3-day) jackpot phase and a turbo (1-day) one, recording every
///         Advance(uint8,uint24) log. Filtered to {10, 14, 16, 8, 9} (the jackpot-day stages), the
///         sequence must be exactly: day 1 -> 10, 14, 16, 8 (or 10, 14, 16, 9 on a turbo's one and
///         only, final day); a non-final standard day -> 10, 16, 8; the standard final day ->
///         10, 16, 9. Stage 13 must never appear anywhere in the unfiltered log, and stage 16 must
///         appear exactly once per jackpot day, always before that day's own 8/9.
contract JackpotPhaseStageSequence is DeployProtocol {
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");
    uint8 internal constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant STAGE_JACKPOT_DAILY_STARTED = 10;
    uint8 internal constant STAGE_JACKPOT_CARRYOVER_RETIRED = 13;
    uint8 internal constant STAGE_JACKPOT_EARLY_BIRD_TICKETS = 14;
    uint8 internal constant STAGE_JACKPOT_BATTLE = 16;

    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp((uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + intoDay);
    }

    /// @dev Fresh jackpot-phase entry at day 400, counter 0, no request outstanding yet: the
    ///      loop below fires the day's own real VRF request on its first advanceGame() call.
    ///      `prevPool` seeds levelPrizePool[lvl - 1]: nonzero latches the battle stage on every day
    ///      (the shape most of this suite pins); zero reproduces a level whose FLIP budget is
    ///      empty, where the battle stage must never latch at all.
    function _seedFreshPhase(uint24 lvl, uint8 flags, uint256 prevPool) internal {
        _deployProtocol();
        _warpToDay(400, 3 hours);
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(JackpotPhaseSeeder).runtimeCode);
        JackpotPhaseSeeder(payable(address(game))).seedFreshPhase(lvl, flags, prevPool);
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
    ///      Also tracks, per physical day, how many times stage 16 fires before that day's own
    ///      8/9 seals it: exactly one when `expectBattle` is true, exactly zero when it is false —
    ///      either way the test fails at the seal if the count is wrong.
    function _driveJackpotPhase(uint256 daysToRun, bool expectBattle) internal returns (uint8[] memory stages) {
        uint8[] memory buf = new uint8[](128);
        uint256 n;
        uint256 daysSealed;
        uint256 guard;
        uint256 battleCountThisDay;
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
            if (st == STAGE_JACKPOT_BATTLE) {
                unchecked { ++battleCountThisDay; }
            }
            if (st == STAGE_JACKPOT_COIN_TICKETS) {
                // A non-final day's own stage unlocks the day it just sealed (the final day's
                // STAGE_JACKPOT_PHASE_ENDED instead keeps the lock held through the phase
                // transition, so this check is specific to the non-final branch).
                assertFalse(game.rngLocked(), "the coin+tickets stage must unlock a non-final day");
            }
            if (st == STAGE_JACKPOT_COIN_TICKETS || st == STAGE_JACKPOT_PHASE_ENDED) {
                _assertBattleCountAtSeal(battleCountThisDay, expectBattle);
                battleCountThisDay = 0;
                unchecked { ++daysSealed; }
                if (daysSealed < daysToRun) vm.warp(block.timestamp + 1 days);
            }
        }
        assertEq(daysSealed, daysToRun, "the jackpot phase must fully seal every requested day");
        stages = new uint8[](n);
        for (uint256 k; k < n; ++k) stages[k] = buf[k];
    }

    /// @dev Split out of `_driveJackpotPhase` to keep its stack shallow enough to compile.
    function _assertBattleCountAtSeal(uint256 count, bool expectBattle) internal {
        if (expectBattle) {
            assertEq(count, 1, "the battle stage must run exactly once per jackpot day, before its seal");
        } else {
            assertEq(count, 0, "a zero coin budget must never latch the battle stage");
        }
    }

    /// @dev Keeps only the jackpot-day stages {10, 14, 16, 8, 9}, in order.
    function _filterJackpotStages(uint8[] memory stages) internal pure returns (uint8[] memory filtered) {
        uint8[] memory buf = new uint8[](stages.length);
        uint256 n;
        for (uint256 i; i < stages.length; ++i) {
            uint8 s = stages[i];
            if (s == STAGE_JACKPOT_DAILY_STARTED || s == STAGE_JACKPOT_EARLY_BIRD_TICKETS
                || s == STAGE_JACKPOT_BATTLE || s == STAGE_JACKPOT_COIN_TICKETS || s == STAGE_JACKPOT_PHASE_ENDED) {
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
        _seedFreshPhase(110, 0, 1000 ether);
        uint8[] memory stages = _driveJackpotPhase(3, true);
        uint8[] memory filtered = _filterJackpotStages(stages);
        uint8[] memory want = new uint8[](10);
        want[0] = STAGE_JACKPOT_DAILY_STARTED;
        want[1] = STAGE_JACKPOT_EARLY_BIRD_TICKETS;
        want[2] = STAGE_JACKPOT_BATTLE;
        want[3] = STAGE_JACKPOT_COIN_TICKETS;
        want[4] = STAGE_JACKPOT_DAILY_STARTED;
        want[5] = STAGE_JACKPOT_BATTLE;
        want[6] = STAGE_JACKPOT_COIN_TICKETS;
        want[7] = STAGE_JACKPOT_DAILY_STARTED;
        want[8] = STAGE_JACKPOT_BATTLE;
        want[9] = STAGE_JACKPOT_PHASE_ENDED;
        _assertSequence(filtered, want);
    }

    function test_TurboOneDayPhase_ExactStageSequence() public {
        _seedFreshPhase(110, JACKPOT_TURBO_FLAG, 1000 ether);
        uint8[] memory stages = _driveJackpotPhase(1, true);
        uint8[] memory filtered = _filterJackpotStages(stages);
        uint8[] memory want = new uint8[](4);
        want[0] = STAGE_JACKPOT_DAILY_STARTED;
        want[1] = STAGE_JACKPOT_EARLY_BIRD_TICKETS;
        want[2] = STAGE_JACKPOT_BATTLE;
        want[3] = STAGE_JACKPOT_PHASE_ENDED;
        _assertSequence(filtered, want);
    }

    /// @notice A level whose FLIP budget is empty (levelPrizePool[lvl - 1] == 0, e.g. a fresh
    ///         level 1 reading levelPrizePool[0]) must never latch the battle stage: the jackpot
    ///         day's sequence collapses to ETH (10), early-bird (14), then coin+tickets (8) with
    ///         no 16 in between — the shape the old fused-stage fixture exercised, kept as a
    ///         standing regression now that most of this suite seeds a nonzero budget instead.
    function test_ZeroCoinBudget_BattleStageNeverLatches() public {
        _seedFreshPhase(110, 0, 0);
        uint8[] memory stages = _driveJackpotPhase(1, false);
        uint8[] memory filtered = _filterJackpotStages(stages);
        uint8[] memory want = new uint8[](3);
        want[0] = STAGE_JACKPOT_DAILY_STARTED;
        want[1] = STAGE_JACKPOT_EARLY_BIRD_TICKETS;
        want[2] = STAGE_JACKPOT_COIN_TICKETS;
        _assertSequence(filtered, want);
    }

    uint8 internal constant JACKPOT_TURBO_FLAG = 1;
}

contract JackpotPhaseSeeder is DegenerusGame {
    /// @notice Fresh jackpot-phase entry: day 400, counter 0, no VRF request outstanding.
    function seedFreshPhase(uint24 lvl, uint8 flags, uint256 prevPool) external {
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
        rngWordCurrent = 0;
        vrfRequestId = 0;
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        dailyJackpotCoinTicketsPending = false;
        dailyTicketBudgetsPacked = 0;
        _afkingResetDay = day;
        levelPrizePool[lvl] = 1000 ether;
        // `prevPool` (levelPrizePool[lvl - 1]) sizes the day's FLIP budget (_calcDailyCoinBudget):
        // nonzero latches the battle stage (16) on every jackpot day; zero mirrors a level whose
        // budget is empty, where the battle stage must never latch. No far-future wallets are
        // seeded, so the jackpot battle itself finds nobody to play — the sequence and stage-13/16
        // checks depend only on the latch, not on winner counts.
        levelPrizePool[lvl - 1] = prevPool;
        // Small pools: each day's own ticket leg then queues only a handful of mint entries
        // at lvl+1, so the write-budgeted STAGE_TICKETS_WORKING drain the next day's request
        // triggers for them finishes in one chunk instead of stretching this sequence check
        // over dozens of advances. The sequence and stage-13 checks do not depend on winner
        // counts.
        _setPrizePools(uint128(5 ether), uint128(10 ether));
        currentPrizePool = uint128(15 ether);
    }
}
