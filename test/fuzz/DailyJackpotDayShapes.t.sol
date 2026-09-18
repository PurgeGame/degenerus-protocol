// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GoldenTicketHarness, CoinflipRecorder, WwxrpRecorder, ReturnZeroSink} from "./GoldenTicketArmResolve.t.sol";

/// @dev The golden-ticket harness plus a read of the packed daily ticket budgets Phase 1 leaves
///      for Phase 2.
contract DayShapeHarness is GoldenTicketHarness {
    function ticketBudgets() external view returns (uint8 step, uint256 dailyEntries, uint256 carryoverEntries, uint8 offset) {
        uint256 p = dailyTicketBudgetsPacked;
        step = uint8(p);
        dailyEntries = uint64(p >> 8);
        carryoverEntries = uint64(p >> 72);
        offset = uint8(p >> 136);
    }
    function setLocked(bool v) external { rngLockedFlag = v; }
    function setJackpotPhase(bool v) external { jackpotPhaseFlag = v; }
    function counter() external view returns (uint8) { return jackpotCounter; }
    function routedLevel() external view returns (uint24) { return _activeTicketLevel(); }
    function carryoverPending() external view returns (bool) { return _carryoverLegPending(); }
    function earlyBirdPending() external view returns (bool) { return _earlyBirdLegPending(); }
    function earlyBirdEntries() external view returns (uint256) { return uint64(dailyTicketBudgetsPacked >> 144); }
    function coinTicketsPending() external view returns (bool) { return dailyJackpotCoinTicketsPending; }
    function setCompressedFlag(uint8 v) external { compressedJackpotFlag = v; }
}

/// @title DailyJackpotDayShapes -- the early-bird day and the final physical day move the pools as documented
/// @notice A jackpot phase runs five daily draws. Day one (counter 0) is the EARLY-BIRD day: a
///         3% slice of the future pool is priced as a bonus-board ticket jackpot and moved to
///         next by the ETH stage, which latches the entries for the early-bird stage that runs
///         them on the next advance (payEarlyBirdTickets) ahead of the coin+tickets stage; the
///         day's own ticket budget is credited to next directly, and no carryover is priced.
///         The FINAL physical day (counter + step reaching the cap) pays 100% of the remaining
///         current pool: a fifth to tickets, the rest to ETH, the current pool ends at zero,
///         and the carryover is priced at the NEXT level. Mutation v78 found none of this
///         asserted in foundry (the early-bird gate, its next credit, the final-day gate and the
///         carryover's level all survived); this reads the pool moves back.
contract DailyJackpotDayShapes is Test {
    DayShapeHarness internal h;

    uint24 internal constant LVL = 4; // price(4) = 0.01, price(5) = 0.02: the carryover's level is observable
    uint256 internal constant CUR_POOL = 1000 ether;
    uint128 internal constant NEXT_POOL = 200 ether;
    uint128 internal constant FUT_POOL = 4000 ether;

    function setUp() public {
        h = new DayShapeHarness();
        vm.etch(ContractAddresses.COINFLIP, address(new CoinflipRecorder()).code);
        vm.etch(ContractAddresses.WWXRP, address(new WwxrpRecorder()).code);
        ReturnZeroSink sink = new ReturnZeroSink();
        vm.etch(ContractAddresses.STETH_TOKEN, address(sink).code);
        vm.etch(ContractAddresses.JACKPOTS, address(sink).code);
        h.setLevel(LVL);
        h.setDailyIdx(10);
        h.setCurrentPool(CUR_POOL);
        h.setPools(NEXT_POOL, FUT_POOL);
    }

    /// @dev The ETH the jackpot-phase solo bucket converted to half whale passes: it is booked
    ///      back into the future pool in the same call, so the future pool's net move includes it.
    function _whalePassEth(Vm.Log[] memory logs) internal pure returns (uint256 eth) {
        bytes32 topic = keccak256("JackpotWhalePassWin(address,uint256,uint8)");
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != topic) continue;
            (uint256 halves,) = abi.decode(logs[i].data, (uint256, uint8));
            eth += halves * 2.25 ether; // HALF_WHALE_PASS_PRICE
        }
    }

    /// @dev A mixed-colour board with deep buckets at both the purchase level and the next.
    function _board(uint256 salt) internal returns (uint256 word) {
        uint8[4] memory colors = [1, 2, 3, 4];
        uint8[4] memory syms = [3, 4, 5, 6];
        for (uint256 i; i < 4; ++i) {
            word |= (uint256(colors[i]) << 3 | uint256(syms[i])) << (i * 6);
        }
        word |= salt << 24;
        for (uint8 i; i < 4; ++i) {
            uint8 trait = uint8(uint256(i) * 64 + ((word >> (uint256(i) * 6)) & 0x3F));
            h.seedBucket(LVL, trait, 60, uint160(0x4000) + uint160(i) * 1000);
            h.seedBucket(LVL + 1, trait, 60, uint160(0x8000) + uint160(i) * 1000);
        }
        // The early-bird stage draws the BONUS board at LVL + 1 (no hero wager is set, so the
        // bonus traits are the salted word's raw roll); seed those buckets too.
        uint8[4] memory bonus = JackpotBucketLib.getRandomTraits(EntropyLib.hash2(word, uint256(keccak256("BONUS_TRAITS"))));
        for (uint8 i; i < 4; ++i) {
            h.seedBucket(LVL + 1, bonus[i], 60, uint160(0xC000) + uint160(i) * 1000);
        }
    }

    function test_earlyBirdDayMovesThreePercentOfFutureAndCreditsItsTicketBudgetToNext() public {
        h.setJackpotCounter(0);
        uint256 word = _board(0xEA51);
        (uint128 next0, uint128 fut0) = h.poolsView();
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        uint256 passEth = _whalePassEth(vm.getRecordedLogs());
        (uint128 next1, uint128 fut1) = h.poolsView();
        (uint8 step, uint256 dailyEntries, uint256 carryoverEntries, uint8 offset) = h.ticketBudgets();

        uint256 earlyBird = (uint256(fut0) * 300) / 10_000;
        assertEq(uint256(fut0) + passEth - uint256(fut1), earlyBird, "the early-bird day takes exactly 3% of the future pool, and no carryover reserve");
        assertEq(step, 1, "an uncompressed phase steps one day");
        assertEq(carryoverEntries, 0, "no carryover is priced on the early-bird day");
        assertEq(offset, 0, "and no carryover source is drawn");
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
        assertFalse(h.carryoverPending(), "the latch never reads as a carryover leg");
        assertEq(h.earlyBirdEntries(), (earlyBird << 2) / PriceLookupLib.priceForLevel(LVL + 1), "the latched entries are the 3% slice priced at the next level");
        assertTrue(h.coinTicketsPending(), "the coin+tickets stage still waits behind it");
        (uint128 next2, uint128 fut2) = h.poolsView();
        vm.recordLogs();
        h.payEarlyBirdTickets(word);
        uint256 ticketWins = _ticketWins(vm.getRecordedLogs(), LVL + 1);
        assertGt(ticketWins, 0, "the early-bird stage drew ticket winners at the next level");
        assertFalse(h.earlyBirdPending(), "the early-bird stage cleared its latch");
        (uint8 step2, uint256 daily2, uint256 carry2, uint8 offset2) = h.ticketBudgets();
        assertEq(step2, step, "the counter step survives the early-bird stage");
        assertEq(daily2, dailyEntries, "the day's own ticket budget survives for the coin+tickets stage");
        assertEq(carry2, 0);
        assertEq(offset2, 0);
        assertTrue(h.coinTicketsPending(), "the coin+tickets stage is still the next stage");
        (uint128 next3, uint128 fut3) = h.poolsView();
        assertEq(next3, next2, "the early-bird stage moves no pool: the ETH stage already did");
        assertEq(fut3, fut2, "the future pool is untouched by the distribution");
        assertEq(h.counter(), 0, "the counter waits for the day's seal");
    }

    /// @dev Turbo (flag 2, counter 0) collapses all five logical days into the one physical day-1
    ///      daily: the ETH stage is also the final physical day and steps the counter by the cap.
    ///      The early-bird leg still runs exactly once from its own stage, before the coin+tickets
    ///      stage that then reaches the cap and ends the level.
    function test_turboDayOneRunsTheEarlyBirdLegOnceFromItsOwnStageBeforeTheCounterReachesTheCap() public {
        h.setJackpotCounter(0);
        h.setCompressedFlag(2);
        h.setJackpotPhase(true);
        h.setLocked(true);
        uint256 word = _board(0x7B0);
        (, uint128 fut0) = h.poolsView();
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        Vm.Log[] memory logs1 = vm.getRecordedLogs();
        assertEq(_ticketWins(logs1, LVL + 1), 0, "the ETH stage drew no early-bird winner");
        assertEq(h.currentPoolView(), 0, "turbo day 1 is the final physical day: the whole current pool is spent");
        (uint8 step, , uint256 carryoverEntries,) = h.ticketBudgets();
        assertEq(step, 5, "turbo steps the counter by the cap");
        assertEq(carryoverEntries, 0, "no carryover on the early-bird day, turbo or not");
        assertTrue(h.earlyBirdPending());
        uint256 earlyBird = (uint256(fut0) * 300) / 10_000;
        assertEq(h.earlyBirdEntries(), (earlyBird << 2) / PriceLookupLib.priceForLevel(LVL + 1));
        assertEq(h.counter(), 0, "the counter has not moved before the leg stages");

        vm.recordLogs();
        h.payEarlyBirdTickets(word);
        assertGt(_ticketWins(vm.getRecordedLogs(), LVL + 1), 0, "the early-bird stage drew its winners");
        assertFalse(h.earlyBirdPending());
        assertEq(h.counter(), 0, "the early-bird stage never touches the counter");

        bool pending = h.payDailyJackpotCoinAndTickets(word);
        assertFalse(pending, "no carryover leg follows");
        assertEq(h.counter(), 5, "the coin+tickets stage steps to the cap; the advance then ends the level");
        assertFalse(h.earlyBirdPending());
        assertFalse(h.carryoverPending());
        assertFalse(h.coinTicketsPending());
    }

    /// @dev Count JackpotTicketWin logs queued at `queueLvl`.
    function _ticketWins(Vm.Log[] memory logs, uint24 queueLvl) internal pure returns (uint256 n) {
        bytes32 topic = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] != topic) continue;
            if (uint24(uint256(logs[i].topics[2])) == queueLvl) ++n;
        }
    }

    function test_finalPhysicalDayPaysTheWholeCurrentPoolAndPricesCarryoverAtTheNextLevel() public {
        h.setJackpotCounter(4); // 4 + 1 reaches the cap of five
        uint256 word = _board(0xF1A1);
        (uint128 next0, uint128 fut0) = h.poolsView();
        h.payDailyJackpot(true, LVL, word);
        (uint128 next1, uint128 fut1) = h.poolsView();
        (uint8 step, , uint256 carryoverEntries, uint8 offset) = h.ticketBudgets();

        assertEq(step, 1, "an uncompressed phase steps one day");
        assertEq(h.currentPoolView(), 0, "the final physical day spends the whole current pool");
        uint256 reserveSlice = uint256(fut0) / 200;
        assertEq(uint256(next1) - uint256(next0), CUR_POOL / 5 + reserveSlice, "next gains a fifth of the pool as tickets plus the carryover reserve");
        assertGe(uint256(fut1) + reserveSlice, uint256(fut0), "future gives up the reserve and takes back only the ETH no bucket could absorb");
        assertGt(offset, 0, "a carryover source is drawn");
        // The carryover is priced at lvl + 1 because this level ends tonight.
        assertEq(carryoverEntries, (reserveSlice << 2) / PriceLookupLib.priceForLevel(LVL + 1), "carryover entries are priced at the next level");
    }

    /// @dev Between the coin+tickets stage and the carryover stage the day is still locked; the
    ///      counter must not have advanced yet, or the routing predicate would read the next
    ///      daily as final and send buys to the next level for one advance.
    function test_carryoverDayAdvancesTheCounterOnlyAtItsSeal() public {
        h.setJackpotCounter(3);
        h.setJackpotPhase(true);
        h.setLocked(true);
        uint256 word = _board(0x0DD1);
        h.payDailyJackpot(true, LVL, word);
        assertEq(h.routedLevel(), LVL, "the day's ETH stage leaves buys at this level");
        bool pending = h.payDailyJackpotCoinAndTickets(word);
        assertTrue(pending, "an ordinary day priced a carryover");
        assertTrue(h.carryoverPending());
        assertEq(h.counter(), 3, "the counter waits for the seal");
        assertEq(h.routedLevel(), LVL, "buys still route to this level under the held lock");
        h.payCarryoverTickets(word);
        assertFalse(h.carryoverPending());
        assertEq(h.counter(), 4, "the carryover stage advanced it with the seal");
        h.setLocked(false);
        assertEq(h.routedLevel(), LVL);
        h.setLocked(true);
        assertEq(h.routedLevel(), LVL + 1, "the next request is the final daily's");
    }

    function test_ordinaryDayIsNeitherShape() public {
        h.setJackpotCounter(2);
        uint256 word = _board(0x0DD1);
        (, uint128 fut0) = h.poolsView();
        vm.recordLogs();
        h.payDailyJackpot(true, LVL, word);
        uint256 passEth = _whalePassEth(vm.getRecordedLogs());
        (, uint128 fut1) = h.poolsView();
        (, , uint256 carryoverEntries,) = h.ticketBudgets();
        assertGt(h.currentPoolView(), 0, "an ordinary day leaves current pool behind");
        assertEq(uint256(fut0) + passEth - uint256(fut1), uint256(fut0) / 200, "an ordinary day moves only the carryover reserve out of future");
        assertEq(carryoverEntries, ((uint256(fut0) / 200) << 2) / PriceLookupLib.priceForLevel(LVL), "and prices it at this level");
    }
}
