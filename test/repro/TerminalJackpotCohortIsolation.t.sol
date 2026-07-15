// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

/// @dev Etch-only storage overlay used to construct and inspect exact terminal states while every
///      measured advance still executes the production DegenerusGame runtime.
contract TerminalCohortSeeder is DegenerusGame {
    function seedPhase(bool inJackpot, bool isLastPurchase, bool locked) external {
        jackpotPhaseFlag = inJackpot;
        lastPurchaseDay = isLastPurchase;
        rngLockedFlag = locked;
    }

    function exposedGameOverTicketLevel(uint24 lvl) external view returns (uint24) {
        return _gameOverTicketLevel(lvl);
    }

    function seedTerminalState(
        uint24 lvl,
        bool inJackpot,
        bool isLastPurchase,
        bool locked,
        bool readDrained,
        uint256 terminalWord,
        uint24 queueLevel,
        address readPlayer,
        address writePlayer,
        uint32 entriesEach
    ) external {
        uint24 day = _simulatedDayIndex();

        purchaseStartDay = day - 121;
        dailyIdx = day - 121;
        rngRequestTime = 0;
        level = lvl;
        jackpotPhaseFlag = inJackpot;
        jackpotCounter = 0;
        lastPurchaseDay = isLastPurchase;
        rngLockedFlag = locked;
        phaseTransitionActive = false;
        gameOver = false;
        dailyJackpotCoinTicketsPending = false;
        ticketsFullyProcessed = readDrained;
        ticketWriteSlot = false;
        prizePoolFrozen = false;

        rngWordCurrent = 0;
        vrfRequestId = 0;
        rngWordByDay[day] = terminalWord;

        // processTicketBatch reads lootboxRngWordByIndex[LR_INDEX-1]. Keep index 1 populated for
        // pre-seeded words; a fresh terminal request advances it to 2 and fills index 1 itself.
        lootboxRngPacked = 1;
        lootboxRngWordByIndex[0] = uint256(keccak256("terminal-ticket-traits")) | 1;

        ticketCursor = 0;
        ticketLevel = 0;
        foilDrainDay = 0;
        foilLastResolveDay = 0;
        foilCursor = 0;

        if (readPlayer != address(0) && entriesEach != 0) {
            _seedQueue(_tqReadKey(queueLevel), readPlayer, entriesEach);
        }
        if (writePlayer != address(0) && entriesEach != 0) {
            _seedQueue(_tqWriteKey(queueLevel), writePlayer, entriesEach);
        }
    }

    function seedGraceOnlyTerminalState(
        uint24 lvl,
        address readPlayer,
        uint32 entries
    ) external {
        uint24 day = _simulatedDayIndex();

        // Trigger game-over solely through the expired VRF-grace timer. Day-based liveness and the
        // >120-day deadman remain false, so clearing this timer before gameOver latches would make
        // the terminal path unreachable on the next transaction.
        purchaseStartDay = day;
        dailyIdx = day;
        level = lvl;
        levelPrizePool[lvl] = type(uint256).max;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        rngLockedFlag = true;
        gameOver = false;
        ticketsFullyProcessed = false;
        ticketWriteSlot = false;
        prizePoolFrozen = true;

        rngWordCurrent = 0;
        rngWordByDay[day] = 0;
        vrfRequestId = 777;
        rngRequestTime = uint48(block.timestamp - 14 days);

        lootboxRngPacked = 1;
        lootboxRngWordByIndex[0] = uint256(keccak256("grace-terminal-ticket-traits")) | 1;
        ticketCursor = 0;
        ticketLevel = 0;
        _seedQueue(_tqReadKey(lvl + 1), readPlayer, entries);
    }

    function seedEveryTrait(uint24 lvl, address player) external {
        for (uint16 trait; trait < 256; ++trait) {
            lvlTraitEntry[lvl][uint8(trait)].push(player);
        }
    }

    function seedWriteQueue(uint24 lvl, address player, uint32 entries) external {
        _seedQueue(_tqWriteKey(lvl), player, entries);
    }

    function holderEntryCount(uint24 lvl, address player) external view returns (uint256 count) {
        for (uint16 trait; trait < 256; ++trait) {
            address[] storage bucket = lvlTraitEntry[lvl][uint8(trait)];
            for (uint256 i; i < bucket.length; ++i) {
                if (bucket[i] == player) ++count;
            }
        }
    }

    function totalQueuedOwed(uint24 lvl, address player) external view returns (uint256) {
        return uint256(uint32(entriesOwedPacked[lvl][player] >> 8)) +
            uint256(uint32(entriesOwedPacked[lvl | TICKET_SLOT_BIT][player] >> 8));
    }

    function ticketBufferState() external view returns (bool writeSlot, bool readDrained) {
        return (ticketWriteSlot, ticketsFullyProcessed);
    }

    function _seedQueue(uint24 key, address player, uint32 entries) private {
        ticketQueue[key].push(player);
        entriesOwedPacked[key][player] = uint40(entries) << 8;
    }
}

/// @title TerminalJackpotCohortIsolation
/// @notice Proves the terminal level policy and, critically, that a jackpot ticket bought after
///         the RNG commitment cannot be promoted from the write buffer into the terminal draw.
contract TerminalJackpotCohortIsolation is DeployProtocol {
    bytes private realGameCode;

    uint24 private constant LEVEL = 777;
    uint32 private constant ENTRIES = 8;
    uint256 private constant TERMINAL_WORD = uint256(keccak256("terminal-word")) | 1;

    address private committedBuyer;
    address private lateBuyer;
    address private currentLevelWinner;
    address private nextLevelWinner;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 200 days);
        realGameCode = address(game).code;

        committedBuyer = makeAddr("committedBuyer");
        lateBuyer = makeAddr("lateBuyer");
        currentLevelWinner = makeAddr("currentLevelWinner");
        nextLevelWinner = makeAddr("nextLevelWinner");
    }

    function testTerminalLevelMatrixUsesLogicalCommittedCohort() public {
        TerminalCohortSeeder seeder = _installSeeder();

        seeder.seedPhase(false, false, false);
        assertEq(seeder.exposedGameOverTicketLevel(LEVEL), LEVEL + 1, "ordinary purchase -> next level");

        seeder.seedPhase(false, true, false);
        assertEq(seeder.exposedGameOverTicketLevel(LEVEL), LEVEL + 1, "unrequested last-purchase -> next level");

        seeder.seedPhase(false, true, true);
        assertEq(seeder.exposedGameOverTicketLevel(LEVEL), LEVEL, "locked transition -> promoted level");

        seeder.seedPhase(true, false, false);
        assertEq(seeder.exposedGameOverTicketLevel(LEVEL), LEVEL, "jackpot -> current level");

        _restoreGame();
    }

    function testJackpotTerminalExcludesPostCommitWriteBuffer() public {
        TerminalCohortSeeder seeder = _installSeeder();
        seeder.seedTerminalState(
            LEVEL,
            true,
            false,
            true,
            false,
            TERMINAL_WORD,
            LEVEL,
            committedBuyer,
            lateBuyer,
            ENTRIES
        );
        // Seed deterministic payout sentinels at both candidate levels. Only the current-level
        // sentinel may receive terminal ETH when jackpotPhaseFlag is true.
        seeder.seedEveryTrait(LEVEL, currentLevelWinner);
        seeder.seedEveryTrait(LEVEL + 1, nextLevelWinner);
        _restoreGame();
        vm.deal(address(game), 100 ether);

        // Tx 1 drains exactly the committed read snapshot and deliberately stops before payout.
        game.advanceGame();
        assertFalse(game.gameOver(), "terminal jackpot remains isolated in its own tx");
        assertGt(_holderEntryCount(LEVEL, committedBuyer), 0, "pre-request read cohort materialized");
        assertEq(_holderEntryCount(LEVEL, lateBuyer), 0, "post-request write cohort not materialized");
        assertEq(_totalQueuedOwed(LEVEL, lateBuyer), ENTRIES, "late write cohort remains queued");

        // Tx 2 must not promote the write buffer; it pays the current-level jackpot and latches.
        game.advanceGame();
        assertTrue(game.gameOver(), "game-over latches after committed snapshot drains");
        assertEq(_holderEntryCount(LEVEL, lateBuyer), 0, "late cohort never enters terminal traits");
        assertEq(_totalQueuedOwed(LEVEL, lateBuyer), ENTRIES, "late cohort remains excluded at latch");
        assertGt(game.claimableWinningsOf(currentLevelWinner), 0, "jackpot pays current-level cohort");
        assertEq(game.claimableWinningsOf(nextLevelWinner), 0, "jackpot does not pay level+1 cohort");
    }

    function testPurchaseTerminalFreezesUnsnappedNextLevelBeforeRequest() public {
        TerminalCohortSeeder seeder = _installSeeder();
        seeder.seedTerminalState(
            LEVEL,
            false,
            false,
            false,
            true,
            0,
            LEVEL + 1,
            address(0),
            committedBuyer,
            ENTRIES
        );
        _restoreGame();
        vm.deal(address(game), 100 ether);

        // No RNG boundary existed, so terminal entry must first swap write->read, then request VRF.
        game.advanceGame();
        assertTrue(game.rngLocked(), "terminal VRF request opened after cohort snapshot");
        assertFalse(game.gameOver(), "waiting for terminal word");
        (bool writeSlot, bool readDrained) = _ticketBufferState();
        assertTrue(writeSlot, "unsnapped purchase cohort was frozen into read slot");
        assertFalse(readDrained, "frozen cohort still awaits processing");

        uint256 requestId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(requestId, TERMINAL_WORD);

        // Drain the frozen cohort, then settle in a separate transaction.
        game.advanceGame();
        assertGt(_holderEntryCount(LEVEL + 1, committedBuyer), 0, "purchase cohort materialized at level+1");
        assertFalse(game.gameOver(), "payout remains isolated after the finishing batch");

        game.advanceGame();
        assertTrue(game.gameOver(), "purchase-phase terminal settlement completes");
        assertEq(_totalQueuedOwed(LEVEL + 1, committedBuyer), 0, "committed purchase queue drained");
    }

    function testLockedLastPurchaseUsesPromotedReadCohort() public {
        TerminalCohortSeeder seeder = _installSeeder();
        seeder.seedTerminalState(
            LEVEL,
            false,
            true,
            true,
            false,
            TERMINAL_WORD,
            LEVEL,
            committedBuyer,
            address(0),
            ENTRIES
        );
        // A later purchase in this raw phase is already routed to promoted LEVEL+1 and must remain
        // outside the terminal draw selected from the pre-request purchase cohort at LEVEL.
        seeder.seedWriteQueue(LEVEL + 1, lateBuyer, ENTRIES);
        _restoreGame();
        vm.deal(address(game), 100 ether);

        game.advanceGame();
        assertGt(_holderEntryCount(LEVEL, committedBuyer), 0, "sealed purchase cohort drains at promoted level");
        assertEq(_holderEntryCount(LEVEL + 1, lateBuyer), 0, "later level+1 write cohort remains excluded");
        assertEq(_totalQueuedOwed(LEVEL + 1, lateBuyer), ENTRIES, "later write cohort remains queued");

        game.advanceGame();
        assertTrue(game.gameOver(), "locked-transition terminal settlement completes");
    }

    function testGraceTimerTerminalStaysLatchedAcrossDrainTransactions() public {
        TerminalCohortSeeder seeder = _installSeeder();
        seeder.seedGraceOnlyTerminalState(LEVEL, committedBuyer, ENTRIES);
        _restoreGame();
        vm.deal(address(game), 100 ether);

        // The first transaction commits historical fallback entropy and finishes the selected
        // read batch, but deliberately isolates the terminal jackpot in the following transaction.
        game.advanceGame();
        assertFalse(game.gameOver(), "finishing ticket batch remains isolated from terminal payout");
        assertGt(_holderEntryCount(LEVEL + 1, committedBuyer), 0, "grace-only cohort materialized");

        // The expired grace timer is the only liveness predicate in this fixture. It must remain a
        // terminal-intent latch until handleGameOverDrain sets gameOver and _unlockRng clears it.
        game.advanceGame();
        assertTrue(game.gameOver(), "grace-only terminal intent survived the transaction boundary");
    }

    function _installSeeder() private returns (TerminalCohortSeeder seeder) {
        vm.etch(address(game), type(TerminalCohortSeeder).runtimeCode);
        seeder = TerminalCohortSeeder(payable(address(game)));
    }

    function _restoreGame() private {
        vm.etch(address(game), realGameCode);
    }

    function _holderEntryCount(uint24 lvl, address player) private returns (uint256 count) {
        TerminalCohortSeeder seeder = _installSeeder();
        count = seeder.holderEntryCount(lvl, player);
        _restoreGame();
    }

    function _totalQueuedOwed(uint24 lvl, address player) private returns (uint256 owed) {
        TerminalCohortSeeder seeder = _installSeeder();
        owed = seeder.totalQueuedOwed(lvl, player);
        _restoreGame();
    }

    function _ticketBufferState() private returns (bool writeSlot, bool readDrained) {
        TerminalCohortSeeder seeder = _installSeeder();
        (writeSlot, readDrained) = seeder.ticketBufferState();
        _restoreGame();
    }
}
