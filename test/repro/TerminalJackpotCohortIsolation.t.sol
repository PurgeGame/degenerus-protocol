// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @dev Etch-only storage overlay used to construct and inspect exact terminal states while every
///      measured advance still executes the production DegenerusGame runtime.
contract TerminalCohortSeeder is DegenerusGame, BucketSeed {
    function exposedVrfDead() external view returns (bool) { return _vrfDead(); }

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
        uint256 preFreezeWord,
        uint24 queueLevel,
        address readPlayer,
        address writePlayer,
        uint32 entriesEach
    ) external {
        uint24 day = _simulatedDayIndex();

        purchaseStartDay = day - 121;
        dailyIdx = day - 121;
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

        // Only one word exists. A held daily request may have delivered its final
        // word; an unanswered request has the nonzero waiting payload and no ready bit.
        lootboxRngPacked = 2;
        if (locked && preFreezeWord > 1) {
            uint256 finalWord = preFreezeWord;
            rngWordCurrent = finalWord; _setRngSessionPublished(true); _setRngComplete(false);
        } else {
            rngWordCurrent = RNG_WORD_WAITING;
        }
        _setRngRequestActive(locked);
        _setRngSessionPublished(!locked);
        vrfRequestId = locked ? 777 : 1;
        rngRequestTime = locked ? uint48(block.timestamp - 120 days) & ~uint48(1) : 1;

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

        // Trigger game-over through a daily request with nothing delivered for 14 days (VRF
        // dead). dailyIdx stays at `day`, keeping the deadman false and the day caught up and
        // sealed, so the purchase deadline stays off: the dead request is the only trigger.
        purchaseStartDay = day - 121;
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

        rngWordCurrent = RNG_WORD_WAITING;
        rngWordByDay[day] = 0;
        vrfRequestId = 777;
        _setRngRequestActive(true);
        _setRngSessionPublished(false);
        rngRequestTime = uint48(block.timestamp - 14 days);

        lootboxRngPacked = 1;
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(0) + 1) & 1) << 12);
        // The outstanding request has no delivered payload; its paid cohort remains queued.
        _setRngSessionPublished(false);
        ticketCursor = 0;
        ticketLevel = 0;
        _seedQueue(_tqReadKey(lvl + 1), readPlayer, entries);
    }

    function seedEveryTrait(uint24 lvl, address player) external {
        for (uint16 trait; trait < 256; ++trait) {
            _seedBucket(lvl, uint8(trait), player, 1);
        }
    }

    function seedWriteQueue(uint24 lvl, address player, uint32 entries) external {
        _seedQueue(_tqWriteKey(lvl), player, entries);
    }

    function holderEntryCount(uint24 lvl, address player) external view returns (uint256 count) {
        for (uint16 trait; trait < 256; ++trait) {
            uint256 len = _bucketLength(lvl, uint8(trait));
            for (uint256 i; i < len; ++i) {
                if (_bucketOwnerAtUnchecked(lvl, uint8(trait), i) == player) ++count;
            }
        }
    }

    function totalQueuedOwed(uint24 lvl, address player) external view returns (uint256) {
        return uint256(uint32(_entriesOwed(lvl, player) >> 8)) +
            uint256(uint32(_entriesOwed(lvl | TICKET_SLOT_BIT, player) >> 8));
    }

    function ticketBufferState() external view returns (bool writeSlot, bool readDrained) {
        return (ticketWriteSlot, ticketsFullyProcessed);
    }

    function _seedQueue(uint24 key, address player, uint32 entries) private {
        uint80 ownerBits = _registerEntryOwner(player, uint24(key & ((uint24(1) << 22) - 1)));
        _tqAppend(key, uint32(ownerBits >> OWNER_IDX_SHIFT));
        _seedOwedAt(key, player, ownerBits | (uint80(entries) << 8));
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
    uint256 private constant PRE_FREEZE_WORD = uint256(keccak256("pre-freeze-word")) | 1;

    address private committedBuyer;
    address private frozenBuyer;
    address private lateBuyer;
    address private currentLevelWinner;
    address private nextLevelWinner;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 200 days);
        realGameCode = address(game).code;

        committedBuyer = makeAddr("committedBuyer");
        frozenBuyer = makeAddr("frozenBuyer");
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
            PRE_FREEZE_WORD,
            LEVEL,
            committedBuyer,
            frozenBuyer,
            ENTRIES
        );
        // Seed deterministic payout sentinels at both candidate levels. Only the current-level
        // sentinel may receive terminal ETH when jackpotPhaseFlag is true.
        seeder.seedEveryTrait(LEVEL, currentLevelWinner);
        seeder.seedEveryTrait(LEVEL + 1, nextLevelWinner);
        _restoreGame();
        vm.deal(address(game), 100 ether);

        // The pre-freeze daily request's word only finalizes the lootbox index it reserved.
        game.advanceGame();
        assertFalse(game.rngLocked(), "pre-freeze request dropped");
        assertEq(_holderEntryCount(LEVEL, committedBuyer), 0, "finalizing the index runs no drain batch");

        // The read cohort that request committed drains on its word, before the terminal swap.
        game.advanceGame();
        assertGt(_holderEntryCount(LEVEL, committedBuyer), 0, "pre-request read cohort materialized");
        assertEq(_holderEntryCount(LEVEL, frozenBuyer), 0, "write cohort waits for the terminal word");

        // The one terminal swap takes the write cohort bought before the freeze, then the terminal
        // request goes out: from here the terminal draw's cohort is fixed.
        uint256 before = mockVRF.lastRequestId();
        game.advanceGame();
        uint256 requestId = mockVRF.lastRequestId();
        assertGt(requestId, before, "terminal request sent after the swap");

        // A write-buffer entry at the terminal level after that commitment.
        seeder = _installSeeder();
        seeder.seedWriteQueue(LEVEL, lateBuyer, ENTRIES);
        _restoreGame();
        mockVRF.fulfillRandomWords(requestId, TERMINAL_WORD);

        // Apply the terminal word, then drain the swapped cohort on it.
        game.advanceGame();
        assertEq(_holderEntryCount(LEVEL, frozenBuyer), 0, "the application runs no drain batch");
        game.advanceGame();
        assertGt(_holderEntryCount(LEVEL, frozenBuyer), 0, "pre-request write cohort drawn on the terminal word");
        assertFalse(game.gameOver(), "terminal jackpot remains isolated in its own tx");
        assertEq(_holderEntryCount(LEVEL, lateBuyer), 0, "post-request write cohort not materialized");
        assertEq(_totalQueuedOwed(LEVEL, lateBuyer), ENTRIES, "late write cohort remains queued");

        // The payout must not promote the write buffer; it pays the current-level jackpot and latches.
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

        // The terminal word is applied in its own transaction.
        game.advanceGame();
        assertTrue(game.rngWordForDay(game.currentDayView()) != 0, "terminal word applied");
        assertEq(_holderEntryCount(LEVEL + 1, committedBuyer), 0, "the application runs no drain batch");

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
            PRE_FREEZE_WORD,
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

        // The first entry latches the promoted level while the last-purchase request still holds
        // the lock; that request's word then only finalizes its lootbox index and it is dropped.
        game.advanceGame();
        assertFalse(game.rngLocked(), "pre-freeze request dropped");

        // The promoted read cohort drains on that word.
        game.advanceGame();
        assertGt(_holderEntryCount(LEVEL, committedBuyer), 0, "sealed purchase cohort drains at promoted level");
        assertEq(_holderEntryCount(LEVEL + 1, lateBuyer), 0, "later level+1 write cohort remains excluded");
        assertEq(_totalQueuedOwed(LEVEL + 1, lateBuyer), ENTRIES, "later write cohort remains queued");

        // Terminal request, word application and payout, one transaction each.
        uint256 before = mockVRF.lastRequestId();
        game.advanceGame();
        uint256 requestId = mockVRF.lastRequestId();
        assertGt(requestId, before, "terminal request sent");
        mockVRF.fulfillRandomWords(requestId, TERMINAL_WORD);
        game.advanceGame();
        assertFalse(game.gameOver(), "payout runs apart from the word's application");
        game.advanceGame();
        assertTrue(game.gameOver(), "locked-transition terminal settlement completes");
        assertEq(_holderEntryCount(LEVEL + 1, lateBuyer), 0, "later level+1 write cohort never drawn");
        assertEq(_totalQueuedOwed(LEVEL + 1, lateBuyer), ENTRIES, "later write cohort remains queued at latch");
    }

    function testRefusedTerminalRequestsKeepOneTimerAndNoCallbackAuthority() public {
        TerminalCohortSeeder seeder = _installSeeder();
        seeder.seedTerminalState(LEVEL, false, false, false, true, 0, LEVEL + 1, address(0), address(0), 0);
        _restoreGame();
        vm.deal(address(game), 100 ether);
        vm.mockCallRevert(address(mockVRF), bytes4(keccak256("requestRandomWords((bytes32,uint256,uint16,uint32,uint32,bytes))")), abi.encodeWithSignature("Error(string)", "refused"));
        game.advanceGame();
        uint256 state = uint256(game.extsload(bytes32(0)));
        uint256 stamp = (state >> 48) & type(uint48).max;
        assertGt(stamp, 1, "first attempt arms a real refusal timer");
        assertEq((state >> 254) & 1, 0, "failed request has no callback authority");
        assertEq((state >> 255) & 1, 0, "terminal session remains unpublished");
        assertEq(uint256(game.extsload(bytes32(uint256(4)))), 1, "nonzero idle ID is retained");
        mockVRF.fulfillRandomWordsRaw(1, address(game), 42);
        assertEq(RecyclingState.currentWord(address(game)), 0, "idle ID cannot authorize a terminal callback");
        for (uint256 i; i < 3; ++i) {
            vm.warp(vm.getBlockTimestamp() + 1 hours);
            game.advanceGame();
            assertEq((uint256(game.extsload(bytes32(0))) >> 48) & type(uint48).max, stamp, "refusal cannot reset the timeout");
        }
        vm.warp(stamp + 14 days);
        seeder = _installSeeder();
        assertTrue(seeder.exposedVrfDead(), "unanswered terminal attempt expires without a live ID");
        _restoreGame();
        vm.clearMockedCalls();
        for (uint256 i; i < 5 && !game.gameOver(); ++i) game.advanceGame();
        assertTrue(game.gameOver(), "refused terminal RNG cannot strand the ending");
    }

    function testExpiredStallEndsDeterministicallyWithoutDrawing() public {
        TerminalCohortSeeder seeder = _installSeeder();
        seeder.seedGraceOnlyTerminalState(LEVEL, committedBuyer, ENTRIES);
        _restoreGame();
        vm.deal(address(game), 100 ether);

        // The request has had nothing delivered for 14 days: VRF is dead, and the ending uses no
        // entropy at all. The committed cohort is counted, never drawn or drained.
        assertTrue(game.livenessTriggered(), "the dead request is the only trigger in this fixture");
        for (uint256 i; i < 5 && !game.gameOver(); ++i) game.advanceGame();
        assertTrue(game.gameOver(), "the deterministic ending completes");
        assertEq(_holderEntryCount(LEVEL + 1, committedBuyer), 0, "no ticket was materialized");
        assertEq(_totalQueuedOwed(LEVEL + 1, committedBuyer), ENTRIES, "the cohort stays queued for its claim");
        assertTrue(game.livenessTriggered(), "the trigger stays on after game over");
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
