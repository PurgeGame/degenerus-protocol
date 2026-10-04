// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {GoldenTicketHarness, CoinflipRecorder, WwxrpRecorder, ReturnZeroSink} from "./GoldenTicketArmResolve.t.sol";

/// @dev The golden-ticket harness plus a read of the packed daily ticket budgets Phase 1 leaves
///      for Phase 2.
contract DayShapeHarness is GoldenTicketHarness {
    function ticketBudgets() external view returns (uint256 dailyEntries) {
        return uint64(dailyTicketBudgetsPacked >> 8);
    }
    function setLocked(bool v) external { rngLockedFlag = v; }
    function setJackpotPhase(bool v) external { jackpotPhaseFlag = v; }
    function counter() external view returns (uint8) { return jackpotCounter; }
    function routedLevel() external view returns (uint24) { return _activeTicketLevel(); }
    function isFinalJackpotDay(uint8 counterVal) external view returns (bool) {
        return _isFinalJackpotDay(counterVal, jackpotFlags);
    }
    function earlyBirdPending() external view returns (bool) { return _earlyBirdLegPending(); }
    function earlyBirdEntries() external view returns (uint256) { return uint64(dailyTicketBudgetsPacked >> 144); }
    function coinTicketsPending() external view returns (bool) { return dailyJackpotCoinTicketsPending; }
    function setJackpotFlags(uint8 v) external { jackpotFlags = v; }
    function battlePending() external view returns (bool) { return _jackpotBattlePending(); }
    function setLevelPrizePool(uint24 lvl, uint256 v) external { levelPrizePool[lvl] = v; }
}

/// @dev Adds the far-future entry registration the daily jackpot battle draws from, so the day's
///      daily runs against populated far-future queues. Deployed by `runtimeCode` directly onto
///      ContractAddresses.GAME.
contract JackpotBattleHarness is DayShapeHarness {
    /// @dev Registers `who` at `targetLevel` and appends it to that level's far-future
    ///      queue lane, exactly as a far-future purchase does (owed balance is irrelevant
    ///      to the jackpot battle, which only reads the registry's owner address).
    function seedFarFutureWallet(uint24 targetLevel, address who) external {
        uint80 packed = _registerEntryOwner(who, targetLevel);
        _tqAppend(_tqFarFutureKey(targetLevel), uint32(packed >> OWNER_IDX_SHIFT));
    }
}

/// @title DailyJackpotDayShapes -- the early-bird day and the final physical day move the pools as documented
/// @notice A jackpot phase runs one or three physical daily draws. Day one (counter 0) is the EARLY-BIRD day: a
///         3% slice of the future pool is priced as a ticket jackpot on the day's main board and moved to
///         next by the ETH stage, which latches the entries for the early-bird stage that runs
///         them on the next advance (runEarlyBirdTickets) ahead of the coin+tickets stage; the
///         day's own ticket budget is credited to next directly. Every OTHER jackpot day (ordinary
///         or final) credits only its own ticket budget to next, current -> next, with nothing
///         reserved and no move on the future pool beyond any whale-pass conversion booked back.
///         The FINAL physical day (counter + step reaching the cap) pays 100% of the remaining
///         current pool: a fifth to tickets, the rest to ETH, and the current pool ends at zero.
///         Mutation v78 found none of this asserted in foundry (the early-bird gate, its next
///         credit and the final-day gate all survived); this reads the pool moves back.
contract DailyJackpotDayShapes is Test {
    DayShapeHarness internal h;

    uint24 internal constant LVL = 4; // price(4) = 0.01, price(5) = 0.02
    uint256 internal constant CUR_POOL = 1000 ether;
    uint128 internal constant NEXT_POOL = 200 ether;
    uint128 internal constant FUT_POOL = 4000 ether;

    // Mirrors the jackpot module's private `_dailyCurrentPoolBps` + the fixed 1/5 ticket carve
    // (DAILY_CURRENT_BPS_MIN/MAX and the "daily-current-bps" tag), so the day's ticket budget can
    // be reconstructed exactly from the same inputs Phase 1 sees.
    uint16 private constant _BPS_MIN = 600;
    uint16 private constant _BPS_MAX = 1400;
    bytes32 private constant _BPS_TAG = keccak256("daily-current-bps");

    function setUp() public {
        h = new DayShapeHarness();
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
        vm.etch(ContractAddresses.COINFLIP, address(new CoinflipRecorder()).code);
        vm.etch(ContractAddresses.WWXRP, address(new WwxrpRecorder()).code);
        ReturnZeroSink sink = new ReturnZeroSink();
        vm.etch(ContractAddresses.STETH_TOKEN, address(sink).code);
        vm.etch(ContractAddresses.JACKPOTS, address(sink).code);
        h.setLevel(LVL);
        h.setDailyIdx(10);
        h.setJackpotFlags(0);
        h.setCurrentPool(CUR_POOL);
        h.setPools(NEXT_POOL, FUT_POOL);
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
    }

    /// @dev The ETH the jackpot-phase quadrants converted to full whale passes: it is booked
    ///      back into the future pool in the same call, so the future pool's net move includes it.
    function _whalePassEth(Vm.Log[] memory logs) internal pure returns (uint256 eth) {
        bytes32 topic = keccak256("JackpotWhalePassWin(address,uint256,uint8)");
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != topic) continue;
            (uint256 halves,) = abi.decode(logs[i].data, (uint256, uint8));
            eth += halves * 2.25 ether; // HALF_WHALE_PASS_PRICE
        }
    }

    /// @dev A mixed-colour board with deep buckets at both the purchase level and the next: the
    ///      early-bird and coin+tickets stages both read this same recorded main board.
    function _board(uint256 salt) internal returns (uint256 word) {
        word = salt;
        uint8[4] memory traits;
        while (true) {
            traits = JackpotBucketLib.getRandomTraits(word);
            bool hasGold;
            for (uint8 q; q < 4; ++q) if (((traits[q] >> 3) & 7) == 7) hasGold = true;
            if (!hasGold) break;
            ++word;
        }
        for (uint8 i; i < 4; ++i) {
            uint8 trait = traits[i];
            h.seedBucket(LVL, trait, 60, uint160(0x4000) + uint160(i) * 1000);
            h.seedBucket(LVL + 1, trait, 60, uint160(0x8000) + uint160(i) * 1000);
        }
    }

    /// @dev Reproduces Phase 1's daily-ticket-budget arithmetic exactly, given the same
    ///      (curPool, counter, word) inputs and whether the day is the level's final.
    function _expectedDailyTicketBudget(
        uint256 curPool,
        uint8 counterVal,
        uint256 word,
        bool isFinal
    ) internal pure returns (uint256 dailyTicketBudget) {
        uint16 bps;
        if (isFinal) {
            bps = 10_000;
        } else {
            uint16 range = _BPS_MAX - _BPS_MIN + 1;
            uint256 seed = uint256(keccak256(abi.encodePacked(word, _BPS_TAG, counterVal)));
            bps = uint16(_BPS_MIN + (seed % range));
            if (counterVal != 0) bps *= 2;
        }
        uint256 budget = (curPool * bps) / 10_000;
        dailyTicketBudget = budget / 5;
    }

    /// @dev Count queued individual awards and direct packed awards at `queueLvl`.
    function _ticketWins(Vm.Log[] memory logs, uint24 queueLvl) internal pure returns (uint256 n) {
        bytes32 topic = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length < 3 || uint24(uint256(logs[i].topics[2])) != queueLvl) continue;
            if (logs[i].topics[0] == topic) ++n;
            else if (logs[i].topics[0] == keccak256("JackpotTicketBatchWin(uint24,uint24,uint16,uint16,uint8,uint32,uint256[4],uint256[4])")) {
                (,uint8 count,,,) = abi.decode(logs[i].data, (uint16,uint8,uint32,uint256[4],uint256[4]));
                n += count;
            }
        }
    }

    function test_earlyBirdDayMovesThreePercentOfFutureAndCreditsItsTicketBudgetToNext() public {
        h.setJackpotCounter(0);
        uint256 word = _board(0xEA51);
        (uint128 next0, uint128 fut0) = h.poolsView();
        vm.recordLogs();
        h.runDailyJackpot(true, LVL, word, gasleft());
        uint256 passEth = _whalePassEth(vm.getRecordedLogs());
        (uint128 next1, uint128 fut1) = h.poolsView();
        uint256 dailyEntries = h.ticketBudgets();

        uint256 earlyBird = (uint256(fut0) * 300) / 10_000;
        assertEq(uint256(fut0) + passEth - uint256(fut1), earlyBird, "the early-bird day takes exactly 3% of the future pool");
        assertGt(dailyEntries, 0, "the day's own ticket budget was priced");
        // next gains the early-bird slice plus the day's ticket budget, which Phase 1 priced into
        // `dailyEntries` at the next level (four entries per ticket price; one sub-ticket of slack).
        uint256 unit = PriceLookupLib.priceForLevel(LVL + 1) >> 2;
        uint256 gained = uint256(next1) - uint256(next0) - earlyBird;
        assertGe(gained, dailyEntries * unit, "next was credited the day's ticket budget");
        assertLt(gained, (dailyEntries + 1) * unit, "and nothing beyond it");

        // The ETH stage priced the leg but drew no ticket winner: the entries wait in the latch
        // for the early-bird stage, which distributes them at LVL + 1 and clears only its field.
        assertTrue(h.earlyBirdPending(), "the early-bird leg is latched for its own stage");
        assertEq(h.earlyBirdEntries(), earlyBird * 4 / PriceLookupLib.priceForLevel(LVL + 1),
            "the latch holds the whole early-bird budget; its plan sizes any pass surplus");
        assertTrue(h.coinTicketsPending(), "the coin+tickets stage still waits behind it");
        (uint128 next2, uint128 fut2) = h.poolsView();
        vm.recordLogs();
        h.runEarlyBirdTickets(word, gasleft());
        uint256 ticketWins = _ticketWins(vm.getRecordedLogs(), LVL + 1);
        assertGt(ticketWins, 0, "the early-bird stage drew ticket winners at the next level");
        assertFalse(h.earlyBirdPending(), "the early-bird stage cleared its latch");
        uint256 daily2 = h.ticketBudgets();
        assertEq(daily2, dailyEntries, "the day's own ticket budget survives for the coin+tickets stage");
        assertTrue(h.coinTicketsPending(), "the coin+tickets stage is still the next stage");
        (uint128 next3, uint128 fut3) = h.poolsView();
        assertEq(next3, next2, "the early-bird stage moves no pool: the ETH stage already did");
        assertEq(fut3, fut2, "the future pool is untouched by the distribution");
        assertEq(h.counter(), 0, "the counter waits for the day's seal");
    }

    /// @dev Turbo (flag bit 0, counter 0) has one draw: its ETH stage pays the final
    ///      physical day, and completion increments the counter once.
    ///      The early-bird leg still runs exactly once from its own stage, before the coin+tickets
    ///      stage that then reaches the cap and ends the level.
    function test_turboDayOneRunsTheEarlyBirdLegOnceFromItsOwnStageBeforeTheCounterReachesTheCap() public {
        h.setJackpotCounter(0);
        h.setJackpotFlags(1);
        h.setJackpotPhase(true);
        h.setLocked(true);
        uint256 word = _board(0x7B0);
        vm.recordLogs();
        h.runDailyJackpot(true, LVL, word, gasleft());
        Vm.Log[] memory logs1 = vm.getRecordedLogs();
        assertEq(_ticketWins(logs1, LVL + 1), 0, "the ETH stage drew no early-bird winner");
        assertEq(h.currentPoolView(), 0, "turbo day 1 is the final physical day: the whole current pool is spent");
        assertTrue(h.earlyBirdPending());
        assertGt(h.earlyBirdEntries(), 0);
        assertEq(h.counter(), 0, "the counter has not moved before the leg stages");

        vm.recordLogs();
        h.runEarlyBirdTickets(word, gasleft());
        assertGt(_ticketWins(vm.getRecordedLogs(), LVL + 1), 0, "the early-bird stage drew its winners");
        assertFalse(h.earlyBirdPending());
        assertEq(h.counter(), 0, "the early-bird stage never touches the counter");

        h.runDailyJackpotTickets(word, gasleft());
        assertEq(h.counter(), 1, "the coin+tickets stage completes the single turbo day");
        assertFalse(h.earlyBirdPending());
        assertFalse(h.coinTicketsPending());
    }

    /// @dev The coin+tickets stage is the day's only remaining stage after the ETH leg: it
    ///      always advances the counter by one and zeroes the packed ticket budgets, whether
    ///      the day is ordinary or the level's final.
    function _checkCoinTicketsStageSealsCounterAndBudgets(uint8 counterVal) internal {
        h.setJackpotCounter(counterVal);
        h.setJackpotPhase(true);
        h.setLocked(true);
        uint256 word = _board(uint256(0x0DD1) + counterVal);
        h.runDailyJackpot(true, LVL, word, gasleft());
        h.runDailyJackpotTickets(word, gasleft());
        assertEq(h.counter(), counterVal + 1, "the coin+tickets stage advances the counter with its own seal");
        assertEq(h.ticketBudgets(), 0, "the packed budgets are zeroed after the stage runs");
        assertFalse(h.coinTicketsPending());
    }

    function test_coinTicketsStageAdvancesTheCounterAndZeroesBudgets_ordinaryDay() public {
        _checkCoinTicketsStageSealsCounterAndBudgets(1);
    }

    function test_coinTicketsStageAdvancesTheCounterAndZeroesBudgets_finalDay() public {
        _checkCoinTicketsStageSealsCounterAndBudgets(2);
    }

    /// @dev The coin+tickets stage advances the counter in the same transaction the advance
    ///      seals the day, so no later transaction sees an advanced counter under the day's lock:
    ///      buys stay at this level through the ETH stage, the unlocked day routes them here too,
    ///      and only the next request (the final daily's) routes them to the next level.
    function test_ordinaryDayRoutedLevelTracksTheCounterTheMomentItAdvances() public {
        h.setJackpotCounter(1);
        h.setJackpotPhase(true);
        h.setLocked(true);
        uint256 word = _board(0x0DD1);
        h.runDailyJackpot(true, LVL, word, gasleft());
        assertEq(h.routedLevel(), LVL, "the day's ETH stage leaves buys at this level");
        h.runDailyJackpotTickets(word, gasleft());
        assertEq(h.counter(), 2, "the coin+tickets stage advanced it with the seal");
        assertEq(h.routedLevel(), LVL + 1, "the counter's advance immediately marks the next request as the final daily's");
        h.setLocked(false);
        assertEq(h.routedLevel(), LVL, "the sealed day routes buys to this level");
        h.setLocked(true);
        assertEq(h.routedLevel(), LVL + 1, "the next request is the final daily's");
    }

    /// @dev Every jackpot-day shape (the early-bird day, an ordinary day, the final day and
    ///      turbo) moves next by exactly the day's own ticket budget, plus the early-bird 3% on
    ///      day 1, and moves future by nothing else beyond a whale-pass conversion booked back.
    /// @param curPool The current pool to price the day off. The final-day and turbo shapes use
    ///        a small pool so no bucket's ETH share reaches the 18-ether whale-pass-conversion
    ///        floor: a final day sweeps its own unpaid ETH into the future pool, and a
    ///        conversion's division dust would ride along with it, which a small pool avoids so
    ///        the reconciliation stays an exact equality.
    function _checkDailyTicketBudgetReconciliation(uint8 counterVal, uint8 flags, uint256 curPool) internal {
        h.setJackpotCounter(counterVal);
        h.setJackpotFlags(flags);
        h.setCurrentPool(curPool);
        if (flags != 0) {
            h.setJackpotPhase(true);
            h.setLocked(true);
        }
        uint256 word = _board(uint256(0xB0D9) + counterVal + flags);
        (uint128 next0, uint128 fut0) = h.poolsView();
        uint256 curBefore = h.currentPoolView();
        bool isFinal = h.isFinalJackpotDay(counterVal);
        uint256 expectedTicketBudget = _expectedDailyTicketBudget(curBefore, counterVal, word, isFinal);
        uint256 expectedEarlyBird = counterVal == 0 ? (uint256(fut0) * 300) / 10_000 : 0;

        vm.recordLogs();
        h.runDailyJackpot(true, LVL, word, gasleft());
        uint256 passEth = _whalePassEth(vm.getRecordedLogs());
        (uint128 next1, uint128 fut1) = h.poolsView();

        assertEq(
            uint256(next1) - uint256(next0),
            expectedTicketBudget + expectedEarlyBird,
            "next gains exactly the day's ticket budget plus the early-bird 3% on day 1"
        );
        if (counterVal == 0) {
            assertEq(
                uint256(fut0) - uint256(fut1) + passEth,
                expectedEarlyBird,
                "future moves only by the early-bird 3%, offset by whale-pass conversions booked back"
            );
        } else {
            assertEq(
                uint256(fut1),
                uint256(fut0) + passEth,
                "future moves only by whale-pass conversions booked back"
            );
        }
        if (isFinal) {
            assertEq(h.currentPoolView(), 0, "the final physical day spends the whole current pool");
        }
        assertGt(h.ticketBudgets(), 0, "the day's ticket budget was priced into entries");
    }

    function test_dailyTicketBudgetReconciliation_earlyBirdDay() public {
        _checkDailyTicketBudgetReconciliation(0, 0, CUR_POOL);
    }

    function test_dailyTicketBudgetReconciliation_ordinaryDay() public {
        _checkDailyTicketBudgetReconciliation(1, 0, CUR_POOL);
    }

    function test_dailyTicketBudgetReconciliation_finalDay() public {
        _checkDailyTicketBudgetReconciliation(2, 0, 20 ether);
    }

    function test_dailyTicketBudgetReconciliation_turboDay() public {
        _checkDailyTicketBudgetReconciliation(0, 1, 20 ether);
    }

    // -- jackpot-day daily: tickets only, no trait-matched FLIP draw, and the battle is not its business ---

    bytes32 private constant FLIP_WIN = keccak256("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");

    /// @dev Runs a jackpot-phase daily (the ETH stage, then the coin+tickets stage, as mineFlip
    ///      sequences them) with the jackpot module's code hosted on the harness. The jackpot battle
    ///      is latched by the daily RNG request and finished before either stage runs, so neither
    ///      stage may touch its latch, even with a funded prize pool.
    function _runJackpotDayDaily() internal returns (uint256 flipWins, uint256 ticketWins) {
        vm.etch(ContractAddresses.GAME, type(JackpotBattleHarness).runtimeCode);
        JackpotBattleHarness g = JackpotBattleHarness(payable(ContractAddresses.GAME));

        g.setLevel(LVL);
        g.setDailyIdx(10);
        g.setJackpotCounter(1); // an ordinary jackpot day: no early-bird leg to run first
        g.setJackpotFlags(0);
        g.setLevelPrizePool(LVL - 1, 1000 ether);
        g.setCurrentPool(CUR_POOL);
        g.setPools(NEXT_POOL, FUT_POOL);

        uint256 word = 0xF11D;
        uint8[4] memory traits;
        while (true) {
            traits = JackpotBucketLib.getRandomTraits(word);
            bool hasGold;
            for (uint8 q; q < 4; ++q) if (((traits[q] >> 3) & 7) == 7) hasGold = true;
            if (!hasGold) break;
            ++word;
        }
        for (uint8 i; i < 4; ++i) {
            g.seedBucket(LVL, traits[i], 60, uint160(0x4000) + uint160(i) * 1000);
            g.seedBucket(LVL + 1, traits[i], 60, uint160(0x8000) + uint160(i) * 1000);
        }
        for (uint24 lv = LVL + 2; lv <= LVL + 100; ++lv) {
            g.seedFarFutureWallet(lv, address(uint160(0xF00000 + lv)));
        }

        g.runDailyJackpot(true, LVL, word, gasleft());
        assertTrue(g.coinTicketsPending(), "fixture: the coin+tickets stage is queued");
        assertFalse(g.battlePending(), "the daily latched the jackpot battle");

        vm.recordLogs();
        g.runDailyJackpotTickets(word, gasleft());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == FLIP_WIN) ++flipWins;
        }
        assertFalse(g.battlePending(), "the coin+tickets stage latched the jackpot battle");
        ticketWins = _ticketWins(logs, LVL + 1);
    }

    function test_jackpotDayDailyPaysTicketsAndNoTraitMatchedFlipDraw() public {
        (uint256 flipWins, uint256 ticketWins) = _runJackpotDayDaily();
        assertEq(flipWins, 0, "a jackpot day never runs the trait-matched FLIP draw");
        assertGt(ticketWins, 0, "the day's own ticket leg still pays");
    }

    /// @dev Without a coin budget (levelPrizePool[LVL - 1] left at setUp's default zero) the ETH
    ///      stage queues the coin+tickets stage and leaves the battle latch alone, as it always does.
    function test_phase1DoesNotLatchBattleWhenCoinBudgetIsZero() public {
        uint256 word = _board(0xB0D9E7);
        h.runDailyJackpot(true, LVL, word, gasleft());
        assertFalse(h.battlePending(), "the daily latched the jackpot battle");
        assertTrue(h.coinTicketsPending(), "the coin+tickets stage is still queued");
    }
}
