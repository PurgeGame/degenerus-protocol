// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

/// @dev Initial state only. All requests, callbacks, field chunks and settlement use the
///      production entry points after the Game's runtime is restored.
contract JackpotCommitmentSeeder is DegenerusGame {
    function seed(address attacker) external returns (uint256 salvagePosition) {
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
        rngWordByDay[day - 1] = 123456;
        salvagePosition = ticketQueue[_tqFarFutureKey(9)].length;
        for (uint24 target = 9; target <= 106; target += 97) {
            _queueEntries(attacker, target, 400, false);
            for (uint256 i; i < 180; ++i) {
                _queueEntries(address(uint160(0x100000 + i)), target, 4, false);
            }
        }
        // Real outstanding awards: either would add wallets to the drawn population if
        // its ordinary queue sink stopped enforcing the request lock.
        whalePassClaims[attacker] = 4;
        claimablePool = 12 ether;
        decBattleRounds[5].poolWei = 12 ether;
        decBattleRounds[5].phase = 2;
        decBattleRounds[5].winners = 1;
        decBattleRounds[5].champion = 1;
        decBattlePlayers[attacker] = (uint256(5) << 64) | 1;
        decBattleEntries[(uint256(5) << 64) | 1] = (uint256(1) << 190) | uint256(uint160(attacker));
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
    bytes32 private constant ENTRY = keccak256("JackpotBattleEntry(uint64,uint256,address,uint256,uint32)");
    bytes32 private constant SETTLED = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
    bytes32 private constant RESERVE = keccak256("HighRollerReserveDrawn(uint64,uint32,address,uint256,uint256)");
    bytes4 private constant RNG_LOCKED = bytes4(keccak256("RngLocked()"));
    IJackpotBattle private api;
    JackpotBattle private reader;
    uint64 private slot;
    uint256 private paidBet;
    uint256 private salvagePosition;
    uint24 private paidDay;

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
        vm.prank(address(game));
        crapsBattle.creditPasses(ATTACKER, 21, 1);
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
        crapsBattle.setPreferredBoard(2);
        vm.expectRevert(CrapsBattleStorage.BonusPeriodSpent.selector);
        crapsBattle.amendSlip(paidBet, 2);
        vm.expectRevert(RNG_LOCKED);
        game.purchaseWhalePass{value: 20 ether}(ATTACKER, 1, bytes32(0));
        vm.expectRevert(RNG_LOCKED);
        game.claimWhalePass(ATTACKER);
        uint32[] memory levels = new uint32[](1);
        levels[0] = 9;
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 4;
        uint256[] memory positions = new uint256[](1);
        positions[0] = salvagePosition;
        vm.expectRevert(RNG_LOCKED);
        game.sellFarFutureEntries(ATTACKER, levels, quantities, positions);
        // A no-op preference write is allowed; it must not unset the commitment.
        crapsBattle.setPreferredBoard(BOARD);
        vm.stopPrank();
        vm.prank(NEWCOMER);
        vm.expectRevert(CrapsBattleStorage.BonusPeriodSpent.selector);
        crapsBattle.upgradeDayWindows(paidDay, 1 << 5);
        vm.prank(address(0xF123));
        vm.expectRevert(CrapsBattleStorage.BonusPeriodSpent.selector);
        crapsBattle.enterBonusBattle(5, 0, 1);
        vm.expectRevert(CrapsBattleStorage.NoSuchBattle.selector);
        crapsBattle.resolveSlot(slot, 1);
        assertEq(crapsBattle.preferredBoardOf(ATTACKER), BOARD);
    }

    function _run(uint256 word, bool perturb) private returns (Result memory result) {
        // mineFlip is the scheduled keeper throughout; no direct privileged battle API is used.
        game.mineFlip();
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
            game.mineFlip();
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
                    if (address(uint160(uint256(logs[j].topics[3]))) == ATTACKER) {
                        (, uint32 chips) = abi.decode(logs[j].data, (uint256, uint32));
                        assertEq(chips, BOARD, "awarded seat lost its committed saved board");
                        ++result.attackerAwards;
                    }
                }
                if (topic == SETTLED) ++result.settlements;
                if (topic == RESERVE) ++result.reserveEvents;
            }
            (CrapsBattleStorage.JackpotRound memory afterRound,,) = reader.jackpotBattleOf(slot);
            if (afterRound.drawnCount > beforeRound.drawnCount) ++result.draws;
            if (afterRound.drawnCount != 0 && afterRound.word == 0) {
                assertEq(afterRound.drawnCount % 150, 0, "partial draw must retain its cursor");
                (,, uint64 settledCursor) = reader.jackpotBattleOf(slot);
                assertEq(settledCursor, 0, "paid seats settled before the field froze");
            }
        }
        (,,, bool complete) = api.jackpotProgress();
        assertTrue(complete, "battle stalled despite scheduled keeper and functional VRF");
        (CrapsBattleStorage.JackpotRound memory round, uint256 board, uint64 cursor) = reader.jackpotBattleOf(slot);
        CrapsBattleStorage.HighRollerDraw memory reserve = reader.highRollerDrawOf(slot);
        assertEq(result.entries, 500, "empty/short draws cannot prove the freeze");
        assertEq(result.draws, 4, "must probe three gaps between actual field chunks");
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
        uint256 word = 1;
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
