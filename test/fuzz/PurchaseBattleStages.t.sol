// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PurchaseDailyFixture, PurchaseDailySeeder, FreshWordLeg} from "../gas/PurchaseDailyWorstCase.t.sol";

/// @notice The purchase day on a real request: the request locks the jackpot battle, the word applies
///         alone (18), the battle's steps (17) run under the held lock, then the ETH leg (6) and the
///         ticket leg (15), which seals and unlocks. Stages are read from the ordered log stream:
///         the engine composes admitted checkpoints into a call.
abstract contract PurchaseBattleStagesBase is PurchaseDailyFixture, FreshWordLeg {
    IJackpotBattle internal battle;

    function _start(PurchaseDailySeeder.Shape memory s) internal {
        _seedFresh(s);
        _armFreshWord(s.word, 400);
        battle = IJackpotBattle(address(crapsBattle));
        (, uint256 added, bool started,) = battle.jackpotProgress();
        assertGt(added, 0, "the request locked the battle");
        assertFalse(started, "the field waits for the word");
    }

    /// @dev The word applies alone and draws nothing: its call ends on the application marker
    ///      (the engine composes admitted checkpoints, so each call takes the smallest admitting
    ///      realistic allowance, which leaves no room for the next battle group).
    function _apply() internal {
        (uint256 from, uint256 to,) = _runThroughMarker(STAGE_RNG_APPLIED_, 50);
        delete lastLogs;
        for (uint256 i = from; i <= to; ++i) lastLogs.push(streamLogs[i]);
        assertFalse(_markerAfter(to), "the word applies alone");
        for (uint256 i = from; i < to; ++i) assertFalse(_isMarker(i), "no stage precedes the application");
        assertEq(
            _countTopic(lastLogs, ETH_WIN_SIG) + _countTopic(lastLogs, TICKET_WIN_SIG)
                + _countTopic(lastLogs, FLIP_WIN_SIG) + _countTopic(lastLogs, BATTLE_ENTRY_SIG),
            0
        );
        assertTrue(game.rngLocked());
        assertTrue(game.advanceDue());
    }

    /// @dev Runs the battle's steps to completion (one stage run of battle markers); returns its
    ///      awarded entries and a digest of its draw logs and final round.
    function _battle() internal returns (bytes32 digest, uint256 entries) {
        (uint64 slot,,,) = battle.jackpotProgress();
        (Tally memory t) = _battleRun();
        entries = t.battleEntries;
        digest = keccak256(abi.encode(digest, _drawDigest()));
        (,,, bool complete) = battle.jackpotProgress();
        assertTrue(complete, "the battle completed");
        (CrapsBattleStorage.JackpotRound memory round, uint256 board, uint64 cursor) =
            JackpotBattle(address(crapsBattle)).jackpotBattleOf(slot);
        digest = keccak256(abi.encode(digest, round, board, cursor));
    }

    function _battleRun() private returns (Tally memory t) {
        uint256 before = streamCursor;
        (, t) = _measure();
        assertEq(t.stage, STAGE_PURCHASE_BATTLE, "a battle step has its own stage");
        assertEq(t.ethWins + t.ticketWins + t.flipWins, 0, "a battle step shares no daily leg");
        _assertNoFreshRng();
        // Every battle call but the completing one (which may compose the day's next stages)
        // returned with the daily lock still held.
        uint256 firstCall = streamLogCall[before];
        uint256 lastCall = streamLogCall[streamCursor - 1];
        for (uint256 c = firstCall; c < lastCall; ++c) assertTrue(streamLockedAfter[c], "the lock holds across battle steps");
    }

    function _drawDigest() private view returns (bytes32 digest) {
        bytes32 started = keccak256("JackpotBattleStarted(uint64,uint24,uint256,uint256,uint256)");
        for (uint256 i; i < lastLogs.length; ++i) {
            Vm.Log storage l = lastLogs[i];
            if (l.topics.length == 0) continue;
            if (l.topics[0] == BATTLE_ENTRY_SIG || l.topics[0] == started) {
                digest = keccak256(abi.encode(digest, l.topics, l.data));
            }
        }
    }

    function _assertNoFreshRng() internal view {
        for (uint256 i; i < lastLogs.length; ++i) {
            if (lastLogs[i].topics.length == 0) continue;
            bytes32 sig = lastLogs[i].topics[0];
            assertTrue(sig != keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)"));
            assertTrue(sig != keccak256("DailyWinningTraits(uint24,uint32)"));
        }
    }
}

contract PurchaseBattleStagesTest is PurchaseBattleStagesBase {
    function setUp() public {
        _start(_shape(128, 0, FF_HOLDERS, NEXT_POOL_QUIET, PREV_POOL_OPEN25));
        _giveWalletId(address(0xBEEF));
    }

    function test_SeparateStagesHoldLockAndDoNotReplayBattle() public {
        _apply();
        (, uint256 entries) = _battle();
        assertGt(entries, 0, "the award draw found the unminted queues");
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY, "the ETH leg follows the battle");
        assertEq(daily.ethWins, PURCHASE_ETH_WINNERS);
        assertEq(daily.ticketWins + daily.battleEntries, 0);
        assertTrue(game.rngLocked(), "tickets still pending");
        (, Tally memory tickets) = _measure();
        assertEq(tickets.stage, STAGE_PURCHASE_DAILY_TICKETS);
        assertGt(tickets.ticketWins, 0);
        assertEq(tickets.ethWins + tickets.battleEntries + tickets.flipWins, 0);
        assertFalse(game.rngLocked());
        vm.recordLogs();
        (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        // A same-day no-work call may revert; either outcome must not replay the draw.
        ok;
        assertEq(_countTopic(vm.getRecordedLogs(), BATTLE_ENTRY_SIG), 0, "the battle replayed");
    }

    function test_MidnightUsesSameFieldBoardsAndWord() public {
        _apply();
        uint24 day = game.currentDayView();
        uint256 word = game.rngWordForDay(day);
        uint256 snap = vm.snapshotState();
        (bytes32 sameDay,) = _battle();
        vm.revertToState(snap);
        vm.warp(block.timestamp + 2 days);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CrapsBattleStorage.BetLocked.selector);
        crapsBattle.setPreferredBoard(0, 3);
        (bytes32 deferred,) = _battle();
        assertEq(deferred, sameDay, "a deferred battle changed its result");
        // Daily words are retained for today and yesterday only (tagged two-slot storage,
        // c729ecfc9), so `day`'s record is not readable two days later; the deferred digest
        // (field, boards and round word) carries the same-word property.
        word;
        assertEq(game.rngWordForDay(day + 1), 0, "revealed word must not resolve a later day");
        assertTrue(game.rngLocked());
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY);
        (, Tally memory tickets) = _measure();
        assertEq(tickets.stage, STAGE_PURCHASE_DAILY_TICKETS);
        assertFalse(game.rngLocked());
        vm.prank(address(0xBEEF)); crapsBattle.setPreferredBoard(0, 3);
        assertEq(crapsBattle.preferredBoardOf(game.walletIdOf(address(0xBEEF))), 3);
    }

    function test_FailedBattleStepRetainsLockAndRetries() public {
        _apply();
        vm.mockCallRevert(
            ContractAddresses.CRAPS, abi.encodeWithSelector(IJackpotBattle.prepareJackpotBattle.selector), hex"deadbeef"
        );
        vm.expectRevert(bytes4(0xdeadbeef));
        game.mineFlip(0);
        assertTrue(game.rngLocked());
        vm.clearMockedCalls();
        _battle();
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY, "the ETH leg waited for the battle");
        (, Tally memory tickets) = _measure();
        assertEq(tickets.stage, STAGE_PURCHASE_DAILY_TICKETS);
    }
}

/// @notice Level one has no ticket leg: once the battle completes, the trait-draw stage seals the day.
contract PurchaseBattleWithoutTicketsTest is PurchaseBattleStagesBase {
    function setUp() public {
        PurchaseDailySeeder.Shape memory s = _shapeLevelOne(PREV_POOL_L1_MAX, false);
        s.traitHolders = 4;
        _start(s);
    }

    function test_TraitDrawSealsDayWhenThereIsNoTicketLeg() public {
        _apply();
        uint256 word = game.rngWordForDay(game.currentDayView());
        // The engine reaches the battle through the metered entry (level, word, allowance); a
        // prefix match pins the level and the day's word.
        vm.expectCall(
            ContractAddresses.GAME_JACKPOT_MODULE,
            abi.encodeWithSignature("runPurchaseJackpotBattle(uint24,uint256,uint256)", uint24(1), word)
        );
        _battle();
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY);
        assertGt(daily.flipWins, 0);
        assertEq(daily.battleEntries, 0);
        assertFalse(game.rngLocked(), "the trait-draw stage seals and unlocks");
    }
}

/// @notice A zero recorded pool still locks a battle, at level one's 150,000-FLIP floor.
contract PurchaseZeroPoolBattleFloorTest is PurchaseBattleStagesBase {
    function setUp() public {
        PurchaseDailySeeder.Shape memory s = _shapeLevelOne(0, false);
        s.traitHolders = 4;
        _start(s);
    }

    function test_ZeroPoolLocksTheFloorBattleThenSeals() public {
        (uint64 slot, uint256 added,,) = battle.jackpotProgress();
        assertEq(added, 150_000 * battle.jackpotEntryPriceOf(slot) / 8_000, "scaled level-one floor");
        _apply();
        (, uint256 entries) = _battle();
        assertEq(entries, 15, "one award per 10,000 of Added");
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY);
        assertEq(daily.flipWins, 0, "a zero pool pays no trait shares");
        assertFalse(game.rngLocked());
    }
}

/// @notice A zero recorded pool still pays the ticket leg before the seal. The seeded day records its
///         word without a request, so it locks no battle.
contract PurchaseZeroPoolWithTicketsTest is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(128, 0, FF_HOLDERS, NEXT_POOL_QUIET, 0));
    }

    function test_ZeroPoolStillPaysTicketsBeforeSeal() public {
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY);
        assertTrue(game.rngLocked());
        (, Tally memory tickets) = _measure();
        assertEq(tickets.stage, STAGE_PURCHASE_DAILY_TICKETS);
        assertGt(tickets.ticketWins, 0);
        assertEq(tickets.battleEntries, 0);
        assertFalse(game.rngLocked());
    }
}
