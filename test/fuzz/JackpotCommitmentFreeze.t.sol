// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Initial state only. All requests, callbacks, field chunks and settlement use the
///      production entry points after the Game's runtime is restored.
contract JackpotCommitmentSeeder is DegenerusGame, WalletSeed {
    function seed(address attacker) external returns (uint256 salvagePosition) {
        TQ.retireCompleted(address(this), 7);
        uint24 day = _simulatedDayIndex();
        level = 6;
        purchaseStartDay = day - 2;
        dailyIdx = day - 1;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        gameOver = false;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngLockedFlag = false;
        rngRequestTime = 0;
        rngWordCurrent = RNG_WORD_WAITING;
        vrfRequestId = 0;
        dailyTicketBudgetsPacked = 0;
        levelPrizePool[6] = 30_000 ether; // 500 awards, requiring four real draw calls.
        _setPrizePools(uint128(50 ether), uint128(300 ether));
        currentPrizePool = 200 ether;
        _recordDailyRng(day - 1, 123456);
        salvagePosition = _ticketQueueLength(_tqFarFutureKey(9));
        for (uint24 target = 9; target <= 106; target += 97) {
            _queueEntries(_seedWallet(attacker), target, 400, false);
            for (uint256 i; i < 180; ++i) {
                _queueEntries(_seedWallet(address(uint160(0x100000 + i))), target, 4, false);
            }
        }
        // Real outstanding awards: either would add wallets to the drawn population if
        // its ordinary queue sink stopped enforcing the request lock.
        _seedHalfPasses(attacker, 4);
        claimablePool = 12 ether;
        decBattleRounds[5].poolWei = 12 ether;
        decBattleRounds[5].phase = 2;
        decBattleRounds[5].count = 1;
        decBattleRounds[5].capacity = 1;
        decBattleRounds[5].winners = 1;
        decBattleRounds[5].champion = 1;
        decBattlePlayers[_seedWallet(attacker)] = (uint256(5) << 64) | 1;
        _storeDecEntry(5, uint64(1),
            (uint256(1) << 62) | uint256(_seedWallet(attacker)));
        decBattleHeap[0] = 1;
        decBattleQueue = 5 | (uint256(5) << 24);

    }
}

/// @notice A request-to-settlement freeze proof over the real Game, table, engine and Coinflip.
///         The attacker acts before fulfillment and between every pair of 150-seat draw chunks.
contract JackpotCommitmentFreezeTest is DeployProtocol {
    address private constant ATTACKER = address(0xA11CE);
    address private constant NEWCOMER = address(0xBADB0B);
    uint32 private constant BOARD = 1 | (1 << 9) | (1 << 12);
    bytes32 private constant ENTRY = keccak256("JackpotBattleEntry(uint64,uint256,uint32,uint256,uint32)");
    bytes32 private constant SETTLED = keccak256("CrapsBetSettled(uint256,uint32,uint256,uint256)");
    bytes32 private constant RESERVE = keccak256("HighRollerReserveDrawn(uint64,uint32,uint32,uint256,uint256)");
    bytes32 private constant FINALIZED = keccak256("CrapsBattleFinalized(bytes32,uint8,uint64,uint256,uint256,uint256,uint256)");
    bytes4 private constant RNG_LOCKED = bytes4(keccak256("RngLocked()"));
    IJackpotBattle private api;
    JackpotBattle private reader;
    uint64 private slot;
    uint256 private paidBet;
    uint256 private salvagePosition;
    uint24 private paidDay;
    /// @dev Admits one 50-entry field group (JACKPOT_BATTLE_DRAW 3.3M + tails) but not a second.
    uint256 private constant ONE_GROUP_GAS = 4_600_000;

    struct Result {
        bytes32 transcript;
        bytes32 finalState;
        uint256 entries;
        uint256 settlements;
        uint256 draws;
        uint256 reserveEvents;
        uint256 attackerAwards;
    }

    function setUp() public {
        _deployProtocol();
        api = IJackpotBattle(address(crapsBattle));
        reader = JackpotBattle(address(crapsBattle));
        uint256 start = (399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620;
        vm.warp(start);
        vm.deal(address(game), 50_000 ether);
        vm.deal(ATTACKER, 100 ether);
        bytes memory runtime = address(game).code;
        vm.etch(address(game), type(JackpotCommitmentSeeder).runtimeCode);
        salvagePosition = JackpotCommitmentSeeder(payable(address(game))).seed(ATTACKER);
        vm.etch(address(game), runtime);

        vm.warp(start - 1 days);
        vm.prank(address(game));
        crapsBattle.openBonusDay();
        paidDay = crapsBattle.currentDayIndex();
        slot = uint64(uint256(paidDay) * 8 + 6);
        vm.prank(address(game));
        coin.mintForGame(ATTACKER, 10_000_000 ether);
        uint16 highMultiple = uint16(crapsBattle.highMultForDay(paidDay));
        vm.prank(ATTACKER);
        paidBet = crapsBattle.enterBonusBattle(5, BOARD, highMultiple);
        uint32 attackerId = game.walletIdOf(ATTACKER);
        vm.prank(address(game));
        crapsBattle.creditPasses(attackerId, 21, 1);
        // A day seat exercises the distinct paid-day-header path and its upgrade gate.
        vm.prank(address(game));
        coin.mintForGame(NEWCOMER, 10_000_000 ether);
        vm.prank(NEWCOMER);
        crapsBattle.enterBonusDay(0, 1);
        vm.warp(start);
        assertEq(game.gameOverTimestamp(), 0, "healthy live fixture");
        assertFalse(game.rngLocked());
    }

    function _perturb() private {
        assertTrue(game.rngLocked(), "mutation probe must be inside the real request lock");
        vm.startPrank(ATTACKER);
        vm.expectRevert(CrapsBattleStorage.BetLocked.selector);
        crapsBattle.setPreferredBoard(0, 2);
        vm.expectRevert(CrapsBattleStorage.BonusPeriodSpent.selector);
        crapsBattle.amendSlip(paidBet, 2);
        vm.expectRevert(RNG_LOCKED);
        game.purchaseWhalePass{value: 20 ether}(0, 1, bytes32(0));
        vm.expectRevert(RNG_LOCKED);
        game.claimWhalePass(0);
        uint32[] memory levels = new uint32[](1);
        levels[0] = 9;
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 4;
        uint256[] memory positions = new uint256[](1);
        positions[0] = salvagePosition;
        vm.expectRevert(RNG_LOCKED);
        game.sellFarFutureEntries(0, levels, quantities, positions);
        // A no-op preference write is allowed; it must not unset the commitment.
        crapsBattle.setPreferredBoard(0, BOARD);
        vm.stopPrank();
        vm.prank(NEWCOMER);
        vm.expectRevert(CrapsBattleStorage.BonusPeriodSpent.selector);
        crapsBattle.upgradeDayWindows(0, paidDay, 1 << 5);
        vm.prank(address(0xF123));
        vm.expectRevert(CrapsBattleStorage.BonusPeriodSpent.selector);
        crapsBattle.enterBonusBattle(5, 0, 1);
        // The locked field settles only inside the Game's own jackpot-battle stage.
        vm.prank(ATTACKER);
        vm.expectRevert(CrapsBattleStorage.OnlyGame.selector);
        crapsBattle.runDailyBattleWork(10_000_000);
        assertEq(crapsBattle.preferredBoardOf(game.walletIdOf(ATTACKER)), BOARD);
    }

    function _run(uint256 word, bool perturb) private returns (Result memory result) {
        bool battleFinalized;
        // mineFlip is the scheduled keeper throughout; no direct privileged battle API is used.
        // The synthetic day-400 jump leaves expired Craps maintenance ahead of the daily request
        // (one checkpoint per call); the first call that sends a request must engage the lock.
        uint256 before = mockVRF.lastRequestId();
        for (uint256 i; i < 1000 && mockVRF.lastRequestId() == before; ++i) {
            assertFalse(game.rngLocked(), "no lock before the daily request");
            game.mineFlip();
        }
        assertTrue(game.rngLocked(), "request did not engage the lock");
        (uint64 locked,, bool started,) = api.jackpotProgress();
        assertEq(locked, slot);
        assertFalse(started);
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0);
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        assertFalse(fulfilled, "word must be unknown at commitment");
        if (perturb) _perturb();
        mockVRF.fulfillRandomWords(request, word);
        (,, fulfilled) = mockVRF.pendingRequests(request);
        assertTrue(fulfilled, "functional VRF fixture");

        for (uint256 i; i < 100; ++i) {
            (,,, bool done) = api.jackpotProgress();
            if (done) break;
            assertTrue(game.rngLocked(), "battle work escaped the request lock");
            assertTrue(game.advanceDue(), "scheduled keeper cannot reach pending battle");
            if (perturb) _perturb();
            (CrapsBattleStorage.JackpotRound memory beforeRound,,) = reader.jackpotBattleOf(slot);
            vm.recordLogs();
            // A call keeps drawing 50-entry field groups while another 3.3M group bound fits.
            // Packed appends made the old 5M allowance fit two; keep this probe at one so it runs
            // between every pair of actual field chunks.
            game.mineFlip{gas: ONE_GROUP_GAS}();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                // Include every table event (exact field/boards, seat outcomes and bounty
                // payouts), and Coinflip's recipient/credit events, in their original order.
                if (logs[j].emitter != address(crapsBattle) && logs[j].emitter != address(coinflip)) continue;
                result.transcript = keccak256(abi.encode(result.transcript, logs[j].emitter, logs[j].topics, logs[j].data));
                if (logs[j].emitter != address(crapsBattle) || logs[j].topics.length == 0) continue;
                bytes32 topic = logs[j].topics[0];
                if (topic == ENTRY) {
                    ++result.entries;
                    if (uint32(uint256(logs[j].topics[3])) == game.walletIdOf(ATTACKER)) {
                        (, uint32 chips) = abi.decode(logs[j].data, (uint256, uint32));
                        assertEq(chips, BOARD, "awarded seat lost its committed saved board");
                        ++result.attackerAwards;
                    }
                }
                // The battle settles its own seats under its slot and its day seats under the
                // day slot, then finalizes. A completing call may run later read consumers in the
                // same transaction (the engine composes admitted work), whose day-window
                // settlements are not this battle's.
                if (topic == FINALIZED && logs[j].topics[1] == bytes32(uint256(slot))) battleFinalized = true;
                if (topic == SETTLED) {
                    uint256 betSlot = uint256(logs[j].topics[1]) >> 64;
                    if (betSlot == slot || (betSlot == uint256(slot) - uint256(slot) % 8 && !battleFinalized)) {
                        ++result.settlements;
                    }
                }
                if (topic == RESERVE) ++result.reserveEvents;
            }
            (CrapsBattleStorage.JackpotRound memory afterRound,,) = reader.jackpotBattleOf(slot);
            if (afterRound.drawnCount > beforeRound.drawnCount) ++result.draws;
            if (afterRound.drawnCount != 0 && afterRound.word == 0) {
                // Field groups are 50 entries (984b8e7d8; was 150).
                assertEq(afterRound.drawnCount % 50, 0, "partial draw must retain its cursor");
                (,, uint64 settledCursor) = reader.jackpotBattleOf(slot);
                assertEq(settledCursor, 0, "paid seats settled before the field froze");
            }
        }
        (,,, bool complete) = api.jackpotProgress();
        assertTrue(complete, "battle stalled despite scheduled keeper and functional VRF");
        (CrapsBattleStorage.JackpotRound memory round, uint256 board, uint64 cursor) = reader.jackpotBattleOf(slot);
        CrapsBattleStorage.HighRollerDraw memory reserve = reader.highRollerDrawOf(slot);
        assertEq(result.entries, 500, "empty/short draws cannot prove the freeze");
        // 500 entries in 50-entry groups (984b8e7d8; was four 150-entry chunks): nine probed gaps.
        assertEq(result.draws, 10, "must probe nine gaps between actual field chunks");
        assertGt(result.attackerAwards, 0, "preferred-board probe must affect a selected wallet");
        assertEq(result.settlements, uint256(round.paidCount) + 500);
        assertEq(result.reserveEvents, 1);
        assertTrue(reserve.resolved);
        assertGt(reserve.eligible, 0, "reserve draw must have a real high entrant");
        result.finalState = keccak256(abi.encode(round, board, cursor, reserve, reader.highRollerReserve()));
        for (uint256 i; i < 40 && game.rngLocked(); ++i) game.mineFlip();
        assertFalse(game.rngLocked(), "completed daily chain did not unlock");
    }

    function _compare(bool reserveWin) private {
        // Zero and one are reserved callback values, so use a publishable VRF word.
        uint256 word = 2;
        while (true) {
            uint256 battleWord = uint256(keccak256(abi.encode(word, uint24(7), keccak256("far-future-coin"))));
            bool wins = uint256(keccak256(abi.encode(battleWord, keccak256("CrapsHighReserveDraw"), uint256(slot)))) % 10 == 0;
            if (wins == reserveWin) break;
            ++word;
        }
        uint256 snap = vm.snapshotState();
        Result memory baseline = _run(word, false);
        assertTrue(vm.revertToState(snap));
        Result memory attacked = _run(word, true);
        assertEq(attacked.transcript, baseline.transcript, "public mutation changed exact field/boards or payouts");
        assertEq(attacked.finalState, baseline.finalState, "public mutation changed battle or reserve state");
        assertEq(reader.highRollerDrawOf(slot).won, reserveWin);
    }

    function test_RequestThroughFourChunksFreezesFieldAndReserveWin() public { _compare(true); }
    function test_RequestThroughFourChunksFreezesFieldAndReserveMiss() public { _compare(false); }
}
