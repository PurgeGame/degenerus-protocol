// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {SolvencyObligations} from "./helpers/SolvencyObligations.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title DegenesisBusyWeekIntegration -- the game after a busy Degenesis week, end to end
/// @notice Many players earn credit through real ETH ticket and lootbox purchases and buy
///         Degenesis boxes on all seven days, inside and outside the early-bonus window. Days
///         are driven only through mineFlip with mock VRF fulfilment. From day index 6 the
///         miner runs on small bounded allowances, so cohort 6 is still settling when the
///         index-9 request lands and cohort 7 settles after the sale, across the level-1
///         jackpot and later ordinary play. Every log the Game emits is scanned in order:
///         each order resolves exactly once with its bought id and amount, cohorts split,
///         price and close strictly in order, the inventory burns once after the seventh
///         close, and every request that splits moves exactly V/2 to the future pool and V/4
///         each to the Vault budget and sDGNRS AFKing. ETH + stETH covers the obligation set
///         after every mineFlip call and every purchase.
contract DegenesisBusyWeekIntegration is DegenesisHarness {
    uint256 internal constant MAX_ALLOWANCE = 10_000_000;
    /// @dev A pre-request stage gets at most this much, so the daily request never shares its
    ///      call and every split is measured alone.
    uint256 internal constant PRE_REQUEST_CAP = 3_000_000;
    uint256 internal constant NO_CAP = type(uint256).max;
    uint256 internal constant TARGET_L1 = 50 ether;

    uint8 internal constant ACTION_IDLE = 0;
    uint8 internal constant ACTION_WAIT = 2;
    uint8 internal constant ACTION_PREPARE_SUBS = 14;
    uint8 internal constant ACTION_MAINTENANCE = 15;
    uint8 internal constant STAGE_PURCHASE_DAILY = 6;
    uint8 internal constant STAGE_ENTERED_JACKPOT = 7;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant STAGE_DEGENESIS_DAY = 21;
    uint8 internal constant JACKPOT_TURBO = 1;

    bytes32 internal constant SIG_ADVANCE = keccak256("Advance(uint8,uint24)");
    bytes32 internal constant SIG_AFKING_FUNDED = keccak256("AfkingFunded(uint32,uint256)");
    bytes32 internal constant SIG_VRF_FUNDED = keccak256("VrfFunded(uint24,uint256,uint256)");
    bytes4 internal constant ERR_GAS = bytes4(keccak256("InsufficientExecutionGas()"));
    bytes4 internal constant ERR_EMPTY = bytes4(keccak256("EmptyRevert()"));

    /// @dev Shape of one busy week.
    struct Plan {
        uint256 players; // pool size; each day's buyers are distinct members
        uint256 buyersMin; // buyers per Degenesis day
        uint256 buyersSpan; // extra buyers per day, drawn
        uint256 largeUnits; // largest order, in DEGENESIS_UNIT
        bool tickets; // credit may come from ticket purchases (else lootboxes only)
        uint256 settleAllowance; // allowance of a settlement call from day index 6
        uint256 dayAllowance; // allowance of any other call from day index 6
        uint256 cap8; // settlement calls on day index 8
    }

    /// @dev Books read around an isolated daily request.
    struct Books {
        uint256 claimablePool;
        uint256 future;
        uint256 insurance;
        uint256 vaultBudget;
        uint256 sdgnrsAfking;
    }

    address internal miner;
    /// @dev Calls other than settlement get the least allowance that funds their first
    ///      checkpoint (the backlog days).
    bool internal tight;
    address[] internal pool;
    uint256 internal seed;
    uint256 internal vrfSeed;

    // ---- bought orders: (day << 32 | index) => id | amount << 32 ----
    mapping(uint256 => uint256) internal lanes;
    mapping(uint256 => uint256) internal resolvedTimes;
    uint256[8] internal bought;
    uint256[8] internal boughtVol;
    uint256[8] internal earlyOrders;
    uint256[8] internal buyersOn;
    uint256[8] internal resolvedN;
    uint256[8] internal splitN;
    uint256[8] internal pricedN;
    uint256[8] internal closedN;
    uint256[8] internal cohortQ;
    uint256[8] internal cohortPaid;
    mapping(uint32 => uint256) internal degDgnrs;
    mapping(uint32 => uint256) internal degWwxrp;
    mapping(uint32 => bool) internal degFlip;
    uint24[8] internal pricedOn;
    uint24[8] internal closedOn;
    uint24[8] internal closedAtLevel;
    uint8 internal activeC;
    uint8 internal closedC;
    uint256 internal burns;
    uint256 internal splitsTotal;
    uint256 internal splitsMeasured;
    uint256 internal resolvedFromIndex9;
    uint24 internal lastResolveDay;

    // ---- daily engine observations ----
    mapping(uint24 => uint256) internal enteredJackpot; // by level
    mapping(uint24 => uint256) internal endedJackpot; // by level
    mapping(uint24 => uint256) internal degenesisDayStages; // by day index
    mapping(uint24 => uint256) internal purchaseDailyStages; // by day index
    bool internal l1JackpotEnded;
    uint256 internal resolvedAfterL1Jackpot;
    uint256 internal ordinaryEth;
    uint256 internal ticketEth;

    // ---- miner ----
    uint256 internal mineCalls;
    uint256 internal idleCalls;
    uint256 internal sizingRetries;
    uint256 internal tightRaises;
    uint256 internal settleCalls;
    uint256 internal peakGas;
    uint8 internal peakAction;
    uint256 internal peakSettleGas;

    function setUp() public override {
        super.setUp();
        miner = makeAddr("busy-miner");
        vm.recordLogs();
        _run(MAX_ALLOWANCE, MAX_ALLOWANCE, NO_CAP);
    }

    // =====================================================================
    // Plans
    // =====================================================================

    function _planAbove() internal pure returns (Plan memory p) {
        p.players = 44;
        p.buyersMin = 22;
        p.buyersSpan = 9;
        p.largeUnits = 60_000;
        p.tickets = true;
        p.settleAllowance = 700_000;
        p.dayAllowance = 3_000_000;
        p.cap8 = 2;
    }

    function _planAtOrBelow() internal pure returns (Plan memory p) {
        p.players = 36;
        p.buyersMin = 20;
        p.buyersSpan = 7;
        p.largeUnits = 12_000;
        p.tickets = false;
        p.settleAllowance = 700_000;
        p.dayAllowance = 3_000_000;
        p.cap8 = 2;
    }

    function _makePlayers(uint256 n) internal {
        for (uint256 i; i < n; ++i) pool.push(_player(string.concat("busy-", vm.toString(i))));
    }

    // =====================================================================
    // Tests
    // =====================================================================

    /// @notice A busy week far above 50 ETH: the index-9 request latches the turbo with level 1
    ///         while cohort 6 is still settling; level 1's jackpot phase enters and ends on day
    ///         9; cohort 6 finishes after it, cohort 7 is priced at the index-11 request and
    ///         settles across ordinary purchases into index 12. Then three more levels of
    ///         ordinary play, and players withdraw ETH, WWXRP and coinflip winnings.
    function test_BusyWeekAboveTarget_TurboWithBacklogPastTheSale() public {
        seed = 0xB05E;
        vrfSeed = 0x5EED1;
        Plan memory plan = _planAbove();
        _makePlayers(plan.players);
        _sale(plan);
        assertGt(_totalVolume(), 200 ether, "fixture: a busy week, well over 50 ETH");
        _assertBacklogAtSaleEnd();

        // ---- index 9: the first post-Degenesis request ----
        _warpTo(GameTimeLib.MAIN_LAUNCH_DAY, 1 hours);
        tight = true;
        _stepToRequestMetered(plan);
        assertEq(game.currentLvl(), 0, "level 0 up to the index-9 request");
        assertFalse(_lastPurchaseFlag(), "no latch before the index-9 request");
        assertEq(closedC, 5, "cohorts 1..5 closed");
        assertEq(activeC, 6, "cohort 6 active at the index-9 request");
        assertLt(_activeCursor(), _count(6), "cohort 6 orders still unresolved");
        assertEq(splitN[7], 0, "cohort 7 not split before its sealing request");
        assertGt(game.nextPrizePoolView(), TARGET_L1, "next pool above the level-1 target");
        console2.log("cohort 6 orders resolved at the index-9 request", _activeCursor());
        console2.log("next pool at the index-9 request (wei)", game.nextPrizePoolView());

        _mine(plan.dayAllowance); // the index-9 request
        assertEq(game.currentLvl(), 1, "the index-9 request made the level 1");
        assertTrue(_lastPurchaseFlag(), "lastPurchaseDay latched");
        assertEq(_flags() & JACKPOT_TURBO, JACKPOT_TURBO, "with JACKPOT_TURBO");
        assertEq(splitN[7], 1, "cohort 7 split at the index-9 request");
        assertEq(activeC, 6, "cohort 7 waits for cohort 6");
        assertEq(pricedN[7], 0, "cohort 7 not priced");

        _run(plan.dayAllowance, plan.settleAllowance, 2);
        assertEq(enteredJackpot[1], 1, "level 1's jackpot phase entered");
        assertEq(endedJackpot[1], 1, "level 1's jackpot phase ended");
        assertEq(degenesisDayStages[GameTimeLib.MAIN_LAUNCH_DAY], 0, "day 9 is not a Degenesis day");
        assertFalse(game.jackpotPhase(), "one-day jackpot phase complete");
        assertEq(_dailyIdxNow(), GameTimeLib.MAIN_LAUNCH_DAY, "day 9 sealed");
        assertGt(resolvedAfterL1Jackpot, 0, "Degenesis orders resolved after level 1's jackpot");
        assertEq(activeC, 6, "cohort 6 still settling after day 9");
        tight = false;

        // ---- index 10: cohort 6 finishes; cohort 7 waits for the next request ----
        _warpTo(10, 1 hours);
        _run(plan.dayAllowance, plan.settleAllowance, NO_CAP);
        assertEq(closedC, 6, "cohort 6 closed on index 10");
        assertEq(activeC, 0, "cohort 7 not priced at its close");

        // ---- index 11: cohort 7 priced; settlement interleaved with ordinary purchases ----
        _warpTo(11, 1 hours);
        tight = true;
        _run(plan.dayAllowance, plan.settleAllowance, 0);
        assertEq(activeC, 7, "cohort 7 priced at the index-11 request");
        assertEq(pricedOn[7], 11, "bound to day 11");
        _interleave(6, plan.settleAllowance);
        assertEq(closedC, 6, "cohort 7 still settling");
        tight = false;

        // ---- index 12: the backlog drains ----
        _warpTo(12, 1 hours);
        _run(MAX_ALLOWANCE, MAX_ALLOWANCE, NO_CAP);
        _assertSaleSettled();
        assertGe(lastResolveDay, 12, "settlement extended to index 12");

        // ---- ordinary play ----
        uint24 l0 = game.currentLvl();
        console2.log("level when the backlog drained", l0);
        _playLevels(l0 + 3, 13, 40);
        assertGe(game.currentLvl(), l0 + 3, "three more levels");
        _withdrawAll();
        _report("above-target");
    }

    /// @notice A busy week whose next pool stays at or below 50 ETH: no turbo at the index-9
    ///         request, day 9 runs the normal level-0 daily path, and the backlog still drains
    ///         with the same accounting.
    function test_BusyWeekAtOrBelowTarget_NoTurboBacklogDrains() public {
        seed = 0xA7B0;
        vrfSeed = 0x5EED2;
        Plan memory plan = _planAtOrBelow();
        _makePlayers(plan.players);
        _sale(plan);
        assertGt(_totalVolume(), 50 ether, "fixture: a busy week");
        _assertBacklogAtSaleEnd();

        _warpTo(GameTimeLib.MAIN_LAUNCH_DAY, 1 hours);
        tight = true;
        _stepToRequestMetered(plan);
        assertLe(game.nextPrizePoolView(), TARGET_L1, "fixture: next pool at or below the level-1 target");
        assertEq(activeC, 6, "cohort 6 active at the index-9 request");
        assertLt(_activeCursor(), _count(6), "cohort 6 orders still unresolved");
        console2.log("cohort 6 orders resolved at the index-9 request", _activeCursor());
        console2.log("next pool at the index-9 request (wei)", game.nextPrizePoolView());

        _mine(plan.dayAllowance); // the index-9 request
        assertEq(game.currentLvl(), 0, "level 0 continues");
        assertFalse(_lastPurchaseFlag(), "no latch at or below the target");
        assertEq(_flags() & JACKPOT_TURBO, 0, "no turbo");
        assertEq(splitN[7], 1, "cohort 7 split at the index-9 request");

        _run(plan.dayAllowance, plan.settleAllowance, 2);
        assertEq(purchaseDailyStages[GameTimeLib.MAIN_LAUNCH_DAY], 1, "the normal level-0 daily path ran on day 9");
        assertEq(degenesisDayStages[GameTimeLib.MAIN_LAUNCH_DAY], 0, "day 9 is not a Degenesis day");
        assertEq(enteredJackpot[1], 0, "no jackpot phase");
        assertEq(game.currentLvl(), 0, "level 0 after day 9");
        assertLt(closedC, 7, "backlog still open after day 9");
        tight = false;

        for (uint24 d = 10; d <= 20 && closedC < 7; ++d) {
            _warpTo(d, 1 hours);
            _run(plan.dayAllowance, plan.settleAllowance, NO_CAP);
            _checkClaimableIdentity();
        }
        _assertSaleSettled();
        assertGe(lastResolveDay, 10, "settlement extended past index 9");
        _report("at-or-below");
    }

    /// @notice Fuzzed VRF words and buy pattern: every order resolves exactly once, the sale
    ///         completes, and ETH + stETH covers the obligations throughout.
    /// forge-config: default.fuzz.runs = 8
    function testFuzz_BusyWeekExactlyOnceAndSolvent(uint256 vrfSeed_, uint256 pattern) public {
        seed = pattern;
        vrfSeed = vrfSeed_;
        Plan memory plan;
        plan.players = 14;
        plan.buyersMin = 3 + pattern % 4;
        plan.buyersSpan = 1 + (pattern >> 8) % 5;
        plan.largeUnits = 2000 + (pattern >> 16) % 30_000;
        plan.tickets = (pattern >> 32) & 1 == 1;
        plan.settleAllowance = 600_000 + (pattern >> 40) % 1_400_000;
        plan.dayAllowance = 2_500_000 + (pattern >> 64) % 2_000_000;
        plan.cap8 = (pattern >> 80) % 3;
        _makePlayers(plan.players);
        _sale(plan);

        uint256 cap9 = (pattern >> 96) % 3;
        for (uint24 d = GameTimeLib.MAIN_LAUNCH_DAY; d <= 22 && closedC < 7; ++d) {
            _warpTo(d, 1 hours);
            tight = d == GameTimeLib.MAIN_LAUNCH_DAY;
            _run(plan.dayAllowance, plan.settleAllowance, tight ? cap9 : NO_CAP);
        }
        tight = false;
        _flush();
        assertEq(closedC, 7, "sale completed");
        assertEq(burns, 1, "inventory burned once");
        for (uint256 c = 1; c <= 7; ++c) assertEq(resolvedN[c], bought[c], "every order resolved once");
        assertEq(_unsplitVolume(), 0, "nothing left unsplit");
        _checkSolvencyFull();
        _checkClaimableIdentity();
    }

    // =====================================================================
    // The sale
    // =====================================================================

    /// @dev Day index 1 left over, then Degenesis days 1..7 (indices 2..8). Each day's buyers act
    ///      at spread times; the engine runs at 1h and 12h into the day.
    function _sale(Plan memory plan) internal {
        for (uint256 c = 1; c <= 7; ++c) {
            _saleDay(c, plan);
            assertEq(game.currentLvl(), 0, "level 0 through index 8");
            assertFalse(_lastPurchaseFlag(), "no latch during Degenesis");
            assertFalse(game.jackpotPhase(), "no jackpot phase during Degenesis");
            assertGt(earlyOrders[c], 0, "orders inside the early-bonus window");
            assertGt(bought[c], earlyOrders[c], "orders after the early-bonus window");
            _checkClaimableIdentity();
            _checkSolvencyFull();
        }
    }

    /// @dev Cohorts 1..5 priced at the request after their day and closed; cohort 6 priced at
    ///      the index-8 request and still settling at the end of index 8.
    function _assertBacklogAtSaleEnd() internal view {
        for (uint256 c = 1; c <= 5; ++c) assertEq(pricedOn[c], c + 2, "cohort c priced at the request after its day");
        assertEq(closedC, 5, "cohorts 1..5 closed during the sale");
        assertEq(pricedOn[6], 8, "cohort 6 priced at the index-8 request");
        assertEq(activeC, 6, "cohort 6 still active at the end of index 8");
        assertLt(_activeCursor(), _count(6), "cohort 6 part-settled");
    }

    function _saleDay(uint256 c, Plan memory plan) internal {
        uint24 d = _dayOf(c);
        bool small = d >= 6;
        uint256 dayA = small ? plan.dayAllowance : MAX_ALLOWANCE;
        uint256 settleA = small ? plan.settleAllowance : MAX_ALLOWANCE;
        uint256 cap = d == 8 ? plan.cap8 : NO_CAP;
        tight = d == 8;
        uint256 n = plan.buyersMin + _rand(c, 0xB0) % (plan.buyersSpan + 1);
        if (n > plan.players) n = plan.players;
        buyersOn[c] = n;
        uint256 early = n / 3 + 1;
        vm.warp(_dayStart(d) + 1);
        _stepToRequestMetered(plan);
        _mine(dayA); // accepted logical request opens this cohort before its first purchase
        assertEq(game.currentDayView_g542950(), d);
        uint256 runs;
        uint256[2] memory runAt = [uint256(1 hours), 12 hours];
        for (uint256 k; k < n; ++k) {
            uint256 t = k < early ? 5 minutes + k * (6 hours - 10 minutes) / early
                : 6 hours + 1 + (k - early) * (18 hours - 15 minutes) / (n - early);
            while (runs < 2 && runAt[runs] <= t) {
                vm.warp(_dayStart(d) + runAt[runs++]);
                cap = _capLeft(cap, _run(dayA, settleA, cap));
            }
            vm.warp(_dayStart(d) + t);
            _buyerActs(c, k, plan);
        }
        while (runs < 2) {
            vm.warp(_dayStart(d) + runAt[runs++]);
            cap = _capLeft(cap, _run(dayA, settleA, cap));
        }
        tight = false;
        if (d < 6) assertEq(closedC, c > 1 ? c - 1 : 0, "prompt settlement before day index 6");
    }

    function _capLeft(uint256 cap, uint256 used) internal pure returns (uint256) {
        return cap == NO_CAP ? NO_CAP : cap - used;
    }

    /// @dev Buyer k of cohort c: earn credit with a real ETH purchase, then place one to three
    ///      Degenesis orders. Every fourth buyer also buys a plain lootbox.
    function _buyerActs(uint256 c, uint256 k, Plan memory plan) internal {
        address p = pool[(_rand(c, 0x0FF5) + k * 5) % plan.players];
        uint256 r = _rand(c, k);
        uint256 orders = 1 + (r % 3 == 0 ? 1 : 0) + (r % 7 == 0 ? 1 : 0);
        uint256[3] memory amounts;
        uint256 total;
        for (uint256 j; j < orders; ++j) {
            amounts[j] = _orderUnits(uint256(keccak256(abi.encode(r, j))), plan.largeUnits) * UNIT;
            total += amounts[j];
        }
        uint256 credit = game.degenesisCreditOf(p);
        if (credit < total) _earn(p, total - credit, r >> 128, plan.tickets);
        for (uint256 j; j < orders; ++j) _degenesisBuy(p, amounts[j]);
        if (k % 4 == 3) _ordinaryBox(p, 0.01 ether * (1 + (r >> 64) % 150));
        _checkSolvency();
    }

    /// @dev Order size in DEGENESIS_UNIT: 45% at 0.01..0.11 ETH, 40% up to 1.5 ETH, 15% large.
    function _orderUnits(uint256 r, uint256 largeUnits) internal pure returns (uint256) {
        uint256 band = r % 100;
        r >>= 8;
        if (band < 45) return 100 + r % 1000;
        if (band < 85) return 1100 + r % 13_900;
        return largeUnits / 2 + r % (largeUnits / 2 + 1);
    }

    /// @dev Earn at least `need` credit through ETH purchases: tickets for small needs (when the
    ///      plan allows), a custom lootbox, or both in one purchase.
    function _earn(address p, uint256 need, uint256 r, bool allowTickets) internal {
        uint256 spend = (need * 4 + 0.01 ether - 1) / 0.01 ether * 0.01 ether;
        uint256 credit0 = game.degenesisCreditOf(p);
        uint256 price = game.mintPrice();
        uint256 mode = allowTickets && spend <= 4 ether ? r % 3 : 1;
        uint256 ticketWei = mode == 0 ? spend : mode == 2 ? spend / 2 / price * price : 0;
        uint256 boxWei = spend - ticketWei;
        vm.deal(p, p.balance + spend);
        vm.prank(p);
        game.purchaseOrderFor{value: spend}(
            0, ticketWei / price * 400, boxWei == 0 ? 0 : BoxOrderLib.boCustom(boxWei), bytes32(0),
            MintPaymentKind.DirectEth, false
        );
        ordinaryEth += spend;
        ticketEth += ticketWei;
        assertEq(game.degenesisCreditOf(p), credit0 + spend / 4, "credit is a quarter of the ETH spend");
    }

    function _ordinaryBox(address p, uint256 amount) internal {
        vm.deal(p, p.balance + amount);
        vm.prank(p);
        game.purchaseOrderFor{value: amount}(0, 0, BoxOrderLib.boCustom(amount), bytes32(0), MintPaymentKind.DirectEth, false);
        ordinaryEth += amount;
    }

    function _ordinaryTickets(address p, uint256 tickets) internal {
        uint256 cost = game.mintPrice() * tickets;
        vm.deal(p, p.balance + cost);
        vm.prank(p);
        game.purchaseOrderFor{value: cost}(0, tickets * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        ordinaryEth += cost;
    }

    /// @dev One order, recorded for the exactly-once check: the buy holds the whole amount in
    ///      claimablePool and consumes the same credit.
    function _degenesisBuy(address p, uint256 amount) internal {
        uint256 c = uint256(game.currentDayView_g542950()) - GameTimeLib.DEGENESIS_START_DAY + 1;
        uint256 index = _count(c);
        uint256 credit0 = game.degenesisCreditOf(p);
        uint256 claimable0 = game.claimablePoolView();
        // _saleDay commits each cohort exactly one second after its reset.
        uint256 secs = block.timestamp - (_dayStart(_dayOf(c)) + 1);
        _buy(p, amount);
        assertEq(_count(c), index + 1, "order appended to today's cohort");
        assertEq(game.claimablePoolView(), claimable0 + amount, "the whole amount held in claimablePool");
        assertEq(game.degenesisCreditOf(p), credit0 - amount, "credit consumed 1:1");
        uint256 lane = _lane(c, index);
        assertEq(uint32(lane), game.walletIdOf_g3120(p), "lane id");
        assertEq(((lane >> 32) & MAX_UNITS) * UNIT, amount, "lane amount");
        assertEq(lane >> 70, secs > BONUS_WINDOW ? BONUS_WINDOW : secs, "lane seconds");
        lanes[(c << 32) | index] = uint256(game.walletIdOf_g3120(p)) | (amount << 32);
        ++bought[c];
        boughtVol[c] += amount;
        if (secs < BONUS_WINDOW) ++earlyOrders[c];
    }

    // =====================================================================
    // After the sale
    // =====================================================================

    /// @dev Pre-request stages on the plan's allowances until the daily request is next.
    function _stepToRequestMetered(Plan memory plan) internal {
        for (uint256 i; i < 500; ++i) {
            _answer();
            uint8 a = game.nextMinerAction();
            if (a == ACTION_REQUEST_DAILY) return;
            require(a != ACTION_IDLE && a != ACTION_WAIT, "fixture: no request came up");
            _mine(a == ACTION_DEGENESIS_SETTLE ? plan.settleAllowance : plan.dayAllowance);
        }
        fail("fixture: request never next");
    }

    /// @dev `rounds` of (an ordinary purchase, then one settlement call).
    function _interleave(uint256 rounds, uint256 settleAllowance) internal {
        for (uint256 i; i < rounds; ++i) {
            address p = pool[(i * 7 + 3) % pool.length];
            if (i % 2 == 0) _ordinaryTickets(p, 20 + i * 13);
            else _ordinaryBox(p, 0.05 ether * (i + 1));
            _checkSolvency();
            _answer();
            if (game.nextMinerAction() != ACTION_DEGENESIS_SETTLE) break;
            _mine(settleAllowance);
        }
    }

    /// @dev Ordinary play from day index `fromDay` until `level >= targetLevel`: each day some
    ///      players buy tickets (enough to pass the next level's target) and lootboxes, then
    ///      the day is driven to idle.
    function _playLevels(uint24 targetLevel, uint24 fromDay, uint24 maxDays) internal {
        for (uint24 d = fromDay; d < fromDay + maxDays && game.currentLvl() < targetLevel; ++d) {
            _warpTo(d, 30 minutes);
            uint256 next = game.nextPrizePoolView();
            uint256 target = game.prizePoolTargetView();
            uint256 need = next > target ? 1 ether : (target - next) * 10 / 9 + 2 ether;
            if (need > 60 ether) need = 60 ether;
            uint256 tickets = need / game.mintPrice();
            for (uint256 j; j < 4; ++j) {
                address p = pool[(uint256(d) * 5 + j * 11) % pool.length];
                _ordinaryTickets(p, tickets / 4 + 1);
                if (j % 2 == 0) _ordinaryBox(p, 0.25 ether * (j + 1));
                _checkSolvency();
            }
            _warpTo(d, 1 hours);
            _run(MAX_ALLOWANCE, MAX_ALLOWANCE, NO_CAP);
            _warpTo(d, 13 hours);
            _run(MAX_ALLOWANCE, MAX_ALLOWANCE, NO_CAP);
            if (game.currentLvl() < 5) _checkClaimableIdentity();
            _checkSolvencyFull();
        }
        _flush();
    }

    /// @dev Withdraw claimable ETH, WWXRP and coinflip winnings for every player.
    function _withdrawAll() internal {
        uint256 ethPaid;
        uint256 wwxrpPaid;
        uint256 flipPaid;
        uint256 degFlipClaimers;
        uint256 n = pool.length;
        for (uint256 i; i < n; ++i) {
            address p = pool[i];
            uint32 id = game.walletIdOf_g3120(p);
            assertGe(sdgnrs.balanceOf(p), degDgnrs[id], "Degenesis sDGNRS reached the buyer");
            uint256 claimable = game.claimableWinningsOf(p);
            if (claimable > 1) {
                uint256 bal0 = p.balance + mockStETH.balanceOf(p);
                uint256 pool0 = game.claimablePoolView();
                vm.prank(p);
                game.claimClaimable(0);
                assertEq(p.balance + mockStETH.balanceOf(p) - bal0, claimable - 1, "claim pays everything above the sentinel");
                assertEq(pool0 - game.claimablePoolView(), claimable - 1, "claimablePool debited by the payout");
                assertEq(game.claimableWinningsOf(p), 1, "sentinel kept");
                ethPaid += claimable - 1;
            }
            uint256 w = wwxrp.claimable(id);
            if (degWwxrp[id] != 0) assertGt(w, 0, "Degenesis WWXRP claimable");
            if (w != 0) {
                uint256 wb0 = wwxrp.balanceOf(p);
                vm.prank(p);
                wwxrp.withdraw(0, 0);
                assertEq(wwxrp.balanceOf(p) - wb0, w, "WWXRP withdrawn");
                wwxrpPaid += w;
            }
            uint256 f = coinflip.previewClaimCoinflips(p);
            if (f != 0) {
                uint256 fb0 = coin.balanceOf(p);
                vm.prank(p);
                uint256 got = coinflip.claimCoinflips(0, f);
                assertEq(got, f, "coinflip claim pays the preview");
                assertEq(coin.balanceOf(p) - fb0, f, "FLIP minted");
                flipPaid += f;
                if (degFlip[id]) ++degFlipClaimers;
            }
        }
        _flush();
        _checkSolvencyFull();
        assertGt(ethPaid, 0, "some players withdrew ETH winnings");
        assertGt(wwxrpPaid, 0, "some players withdrew WWXRP");
        assertGt(flipPaid, 0, "some players claimed coinflip winnings");
        assertGt(degFlipClaimers, 0, "Degenesis FLIP recipients claimed coinflip winnings");
        console2.log("players claiming coinflip after a Degenesis FLIP credit", degFlipClaimers);
        console2.log("withdrawn ETH (wei)", ethPaid);
        console2.log("withdrawn WWXRP", wwxrpPaid);
        console2.log("claimed FLIP", flipPaid);
    }

    // =====================================================================
    // Engine driving
    // =====================================================================

    /// @dev Answer the latest VRF request if it is open.
    function _answer() internal returns (bool) {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return false;
        (,, bool done) = mockVRF.pendingRequests(req);
        if (done) return false;
        mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode(vrfSeed, req))));
        return true;
    }

    /// @dev Mine until idle or until `settleCap` settlement calls ran in this run. Settlement
    ///      calls use `settleA`, every other call `dayA`.
    function _run(uint256 dayA, uint256 settleA, uint256 settleCap) internal returns (uint256 settles) {
        for (uint256 i; i < 6000; ++i) {
            _answer();
            uint8 a = game.nextMinerAction();
            if (a == ACTION_IDLE) {
                _flush();
                return settles;
            }
            if (a == ACTION_WAIT) {
                if (!_answer()) {
                    _flush();
                    return settles;
                }
                continue;
            }
            if (a == ACTION_DEGENESIS_SETTLE) {
                if (settles == settleCap) {
                    _flush();
                    return settles;
                }
                ++settles;
            }
            _mine(a == ACTION_DEGENESIS_SETTLE ? settleA : dayA);
        }
        fail("engine did not go idle");
    }

    /// @dev One mineFlip by the miner on at most 10M gas. A refusal because the first
    ///      checkpoint does not fit the allowance retries on twice the allowance, up to 10M;
    ///      NoWork / RngNotReady count as idle; any other revert fails the test. Returns
    ///      whether the call progressed.
    function _mine(uint256 allowance) internal returns (bool) {
        _flush();
        uint8 action = game.nextMinerAction();
        if (action == ACTION_PREPARE_SUBS || action == ACTION_MAINTENANCE) {
            if (allowance > PRE_REQUEST_CAP) allowance = PRE_REQUEST_CAP;
        }
        if (allowance > MAX_ALLOWANCE) allowance = MAX_ALLOWANCE;
        if (tight && action != ACTION_DEGENESIS_SETTLE) {
            allowance = _tightAllowance(allowance);
            vm.getRecordedLogs();
        }
        bool request = action == ACTION_REQUEST_DAILY;
        Books memory b0;
        if (request) b0 = _books();
        for (;;) {
            vm.prank(miner);
            uint256 g0 = gasleft();
            try game.mineRun{gas: allowance}(0) {
                uint256 used = g0 - gasleft();
                // `used` includes the call site's own few thousand gas.
                assertLe(used, allowance + 10_000, "mineFlip within its allowance");
                assertLe(used, MAX_ALLOWANCE, "mineFlip within 10M");
                ++mineCalls;
                if (used > peakGas) {
                    peakGas = used;
                    peakAction = action;
                }
                if (action == ACTION_DEGENESIS_SETTLE) {
                    ++settleCalls;
                    if (used > peakSettleGas) peakSettleGas = used;
                }
                break;
            } catch (bytes memory reason) {
                vm.getRecordedLogs();
                if (_isIdle(reason)) {
                    ++idleCalls;
                    return false;
                }
                bool sizing = reason.length == 0
                    || (reason.length == 4 && (bytes4(reason) == ERR_GAS || bytes4(reason) == ERR_EMPTY));
                if (!sizing || allowance >= MAX_ALLOWANCE) {
                    console2.log("mineFlip failed; first action", action);
                    console2.log("allowance", allowance);
                    assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
                }
                ++sizingRetries;
                allowance = allowance * 2 > MAX_ALLOWANCE ? MAX_ALLOWANCE : allowance * 2;
            }
        }
        _scan(vm.getRecordedLogs(), request, b0);
        _checkSolvency();
        return true;
    }

    /// @dev `base` when a trial call on it (under a state snapshot) succeeds without rolling on
    ///      into Degenesis settlement; otherwise the least allowance (to 100k, at most 10M) whose
    ///      call succeeds, which funds the first checkpoint and too little to start settlement.
    ///      Returns 10M when nothing up to 10M succeeds, so the real call surfaces the failure.
    function _tightAllowance(uint256 base) internal returns (uint256 hi) {
        (bool ok, bool rolled) = _trial(base);
        if (ok && !rolled) return base;
        if (!ok) ++tightRaises;
        uint256 lo = 30_000;
        hi = base;
        if (!ok) {
            lo = base;
            hi = MAX_ALLOWANCE;
            (ok,) = _trial(hi);
            if (!ok) return hi;
        }
        while (hi - lo > 100_000) {
            uint256 mid = (lo + hi) / 2;
            (ok,) = _trial(mid);
            if (ok) hi = mid;
            else lo = mid;
        }
    }

    /// @dev One mineFlip on `gas_` under a snapshot: whether it succeeded, and whether it
    ///      resolved Degenesis orders.
    function _trial(uint256 gas_) internal returns (bool ok, bool rolled) {
        uint256 snap = vm.snapshotState();
        uint256 marker = _settleMarker();
        vm.prank(miner);
        (ok,) = address(game).call{gas: gas_}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
        rolled = _settleMarker() != marker;
        vm.revertToStateAndDelete(snap);
    }

    /// @dev Settlement position: the active cursor and the closed count.
    function _settleMarker() internal view returns (uint256) {
        return (uint256(_activeCursor()) << 8) | _closed();
    }

    function _flush() internal {
        Books memory none;
        _scan(vm.getRecordedLogs(), false, none);
    }

    // =====================================================================
    // Log scan: exactly-once, ordering, split exactness
    // =====================================================================

    function _books() internal view returns (Books memory b) {
        b.claimablePool = game.claimablePoolView();
        b.future = _futureTotal();
        b.insurance = game.yieldAccumulatorView();
        b.vaultBudget = _vaultBudget();
        b.sdgnrsAfking = _sdgnrsAfking();
    }

    /// @dev Scan logs in emission order. `request` marks the logs of one isolated daily-request
    ///      call, whose books before the call are `b0`.
    function _scan(Vm.Log[] memory logs, bool request, Books memory b0) internal {
        uint256 splitVol;
        uint256 afkFunded;
        uint256 vrfFromSdgnrs;
        uint24 today = game.currentDayView_g542950();
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(game) || l.topics.length == 0) continue;
            bytes32 t = l.topics[0];
            if (t == SIG_SPLIT) {
                splitVol += _onSplit(l, today, request);
            } else if (t == SIG_AFKING_FUNDED) {
                if (uint256(l.topics[1]) == SDGNRS_ID && request) afkFunded += abi.decode(l.data, (uint256));
            } else if (t == SIG_VRF_FUNDED) {
                // The request tops up the VRF subscription natively, debiting the sDGNRS AFKing credit.
                (,, uint256 fromSdgnrs) = abi.decode(l.data, (uint24, uint256, uint256));
                if (request) vrfFromSdgnrs += fromSdgnrs;
            } else if (t == SIG_PRICED) {
                _onPriced(l, today);
            } else if (t == SIG_RESOLVED) {
                _onResolved(l, today);
            } else if (t == SIG_CLOSED) {
                _onClosed(l, today);
            } else if (t == SIG_BURNED) {
                assertEq(closedC, 7, "burn only after the seventh close");
                assertEq(burns, 0, "inventory burned once");
                ++burns;
                assertEq(_degPool(), 0, "burn empties the Degenesis pool");
            } else if (t == SIG_ADVANCE && l.topics.length == 1) {
                _onAdvance(l, today);
            }
        }
        if (splitVol != 0) {
            uint256 q = splitVol / 4;
            assertEq(q * 4, splitVol, "split volume divides into exact quarters");
            assertEq(afkFunded, q, "sDGNRS AFKing funded a quarter (event)");
            assertEq(b0.claimablePool - game.claimablePoolView(), 2 * q + vrfFromSdgnrs, "split: claimablePool -V/2 (plus the native VRF top-up)");
            assertEq(_futureTotal() - b0.future, q, "split: future pool +V/4");
            assertEq(game.yieldAccumulatorView() - b0.insurance, q, "split: insurance +V/4");
            assertEq(_vaultBudget() - b0.vaultBudget, q, "split: Vault budget +V/4");
            assertEq(_sdgnrsAfking() + vrfFromSdgnrs - b0.sdgnrsAfking, q, "split: sDGNRS AFKing +V/4 (before the native VRF top-up)");
            splitsMeasured += splitVol;
        }
    }

    function _onSplit(Vm.Log memory l, uint24 today, bool request) internal returns (uint256 vol) {
        uint256 c = uint256(l.topics[1]);
        vol = abi.decode(l.data, (uint256));
        assertTrue(request, "a split happens only in an isolated daily request");
        assertEq(splitN[c], 0, "each cohort splits once");
        assertGt(today, GameTimeLib.DEGENESIS_START_DAY + c - 1, "split only after the cohort sealed");
        assertEq(vol, boughtVol[c], "split volume equals the bought volume");
        assertGt(vol, 0, "only nonempty cohorts split");
        ++splitN[c];
        splitsTotal += vol;
    }

    function _onPriced(Vm.Log memory l, uint24 today) internal {
        uint256 c = uint256(l.topics[1]);
        (uint256 vol, uint256 q, uint24 boundDay) = abi.decode(l.data, (uint256, uint256, uint24));
        assertEq(c, uint256(closedC) + 1, "cohorts price strictly in order");
        assertEq(activeC, 0, "priced only after the previous cohort closed");
        assertEq(splitN[c], 1, "priced after its split");
        assertEq(vol, boughtVol[c], "priced volume");
        assertEq(boundDay, today, "bound to this request's day");
        assertGt(q, 0, "payout budget");
        assertEq(pricedN[c], 0, "each cohort priced once");
        ++pricedN[c];
        cohortQ[c] = q;
        pricedOn[c] = today;
        activeC = uint8(c);
    }

    function _onResolved(Vm.Log memory l, uint24 today) internal {
        uint32 id = uint32(uint256(l.topics[1]));
        Res memory r = _decodeResolved(l);
        uint8 day = r.day;
        uint32 index = r.index;
        uint256 amount = r.amount;
        bool flipSide = r.flip != 0 || r.normalPasses != 0 || r.highPasses != 0;
        assertFalse(flipSide && r.dgnrs != 0, "one category per order");
        if (r.dgnrs != 0) assertEq(r.wwxrp, 0, "an sDGNRS win carries no consolation");
        assertTrue(flipSide || r.dgnrs != 0 || r.wwxrp != 0, "every order pays something");
        cohortPaid[day] += r.dgnrs;
        degDgnrs[id] += r.dgnrs;
        if (r.wwxrp != 0) ++degWwxrp[id];
        if (r.flip != 0) degFlip[id] = true;
        assertEq(day, activeC, "orders resolve only in the active priced cohort");
        uint256 key = (uint256(day) << 32) | index;
        assertEq(resolvedTimes[key], 0, "each order resolves exactly once");
        resolvedTimes[key] = 1;
        uint256 want = lanes[key];
        assertGt(want, 0, "resolved order was bought");
        assertEq(id, uint32(want), "resolved id is the buyer's");
        assertEq(amount, want >> 32, "resolved amount is the bought amount");
        ++resolvedN[day];
        if (l1JackpotEnded) ++resolvedAfterL1Jackpot;
        if (today >= GameTimeLib.MAIN_LAUNCH_DAY) ++resolvedFromIndex9;
        lastResolveDay = today;
    }

    function _decodeResolved(Vm.Log memory l) internal pure returns (Res memory r) {
        (r.day, r.index, r.amount, r.flip, r.dgnrs, r.wwxrp, r.normalPasses, r.highPasses) =
            abi.decode(l.data, (uint8, uint32, uint256, uint256, uint256, uint256, uint32, uint32));
    }

    function _onClosed(Vm.Log memory l, uint24 today) internal {
        uint256 c = uint256(l.topics[1]);
        uint256 paid = abi.decode(l.data, (uint256));
        assertEq(c, uint256(closedC) + 1, "cohorts close strictly in order");
        assertEq(closedN[c], 0, "each cohort closes once");
        if (bought[c] != 0) {
            assertEq(activeC, c, "a nonempty cohort closes after its pricing");
            assertEq(resolvedN[c], bought[c], "a cohort closes only after all its orders resolved");
            assertEq(paid, cohortPaid[c], "closed cohort reports the sDGNRS its orders were paid");
            assertLe(paid, cohortQ[c] * 3 / 2, "sDGNRS paid within 1.5Q");
        } else {
            assertEq(activeC, 0, "an empty cohort closes unpriced");
            assertEq(paid, 0, "an empty cohort pays nothing");
        }
        ++closedN[c];
        closedOn[c] = today;
        closedAtLevel[c] = game.currentLvl();
        closedC = uint8(c);
        activeC = 0;
    }

    function _onAdvance(Vm.Log memory l, uint24 today) internal {
        (uint8 stage, uint24 lvl) = abi.decode(l.data, (uint8, uint24));
        if (stage == STAGE_ENTERED_JACKPOT) ++enteredJackpot[lvl];
        else if (stage == STAGE_JACKPOT_PHASE_ENDED) {
            ++endedJackpot[lvl];
            if (lvl == 1) l1JackpotEnded = true;
        } else if (stage == STAGE_DEGENESIS_DAY) {
            ++degenesisDayStages[today];
        } else if (stage == STAGE_PURCHASE_DAILY) {
            ++purchaseDailyStages[today];
        }
    }

    // =====================================================================
    // Accounting checks
    // =====================================================================

    /// @dev Per-call check: backing against the SolvencyObligations set (pools, claimablePool,
    ///      yield and the frozen pending buffer), without its queue walk.
    function _checkSolvency() internal view {
        (uint256 pendingNext, uint256 pendingFuture) = SolvencyObligations.pendingPools(game);
        uint256 owed = game.currentPrizePoolView() + game.nextPrizePoolView() + game.futurePrizePoolView()
            + game.claimablePoolView() + game.yieldAccumulatorView() + pendingNext + pendingFuture;
        uint256 backing = SolvencyObligations.backing(game);
        assertGe(backing, owed, "ETH + stETH covers the obligations");
    }

    /// @dev Checkpoint check: the full SolvencyObligations set, queue records attested.
    function _checkSolvencyFull() internal view {
        assertGe(SolvencyObligations.backing(game), SolvencyObligations.obligations(game), "ETH + stETH covers the obligations");
    }

    /// @dev claimablePool == Sigma over registered wallets (claimable above the sentinel +
    ///      AFKing) + the Vault's Degenesis budget + volume not yet split.
    function _checkClaimableIdentity() internal view {
        uint256 n = uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
        uint256 sum;
        for (uint256 id = 1; id < n; ++id) {
            uint256 packed = uint256(vm.load(address(game), keccak256(abi.encode(id, GameSlots.BALANCES_PACKED))));
            uint256 claimable = uint128(packed);
            assertGe(claimable, 1, "registered wallet keeps its sentinel");
            sum += claimable - 1 + (packed >> 128);
        }
        assertEq(
            game.claimablePoolView(), sum + _vaultBudget() + _unsplitVolume(),
            "claimablePool == wallet balances + Vault budget + unsplit volume"
        );
    }

    /// @dev The sale is over and settled: every order resolved once, every cohort split, priced
    ///      and closed in order, the inventory burned once, nothing Degenesis left reserved
    ///      except the Vault budget, whose quarters are exact.
    function _assertSaleSettled() internal {
        _flush();
        assertEq(closedC, 7, "seven cohorts closed");
        assertEq(burns, 1, "inventory burned exactly once");
        assertEq(_degPool(), 0, "Degenesis pool empty");
        assertEq(_active(), 0, "no reservation outstanding");
        assertEq(_word(), 0, "no bound word");
        uint256 quarters;
        for (uint256 c = 1; c <= 7; ++c) {
            assertGt(bought[c], 0, "every day sold");
            assertEq(resolvedN[c], bought[c], "every order of the cohort resolved exactly once");
            assertEq(splitN[c], 1, "each cohort split once");
            assertEq(pricedN[c], 1, "each cohort priced once");
            assertEq(closedN[c], 1, "each cohort closed once");
            assertEq(_volumeUnits(c) * UNIT, boughtVol[c], "cohort header volume");
            assertEq(_count(c), bought[c], "cohort header count");
            assertTrue(_split(c), "split flag");
            if (c > 1) assertGt(pricedOn[c], closedOn[c - 1], "priced at a request after the previous close");
            quarters += boughtVol[c] / 4;
        }
        assertEq(splitsMeasured, splitsTotal, "every split measured in an isolated request");
        assertEq(splitsTotal, _totalVolume(), "the whole volume split");
        assertEq(_unsplitVolume(), 0, "no unsplit Degenesis volume left in claimablePool");
        assertEq(_vaultBudget(), quarters, "Vault budget holds exactly the quarters");
        assertGt(resolvedFromIndex9, 0, "orders resolved after the sale ended");
        _checkClaimableIdentity();
        _checkSolvencyFull();
    }

    // =====================================================================
    // Readers and helpers
    // =====================================================================

    function _rand(uint256 a, uint256 b) internal view returns (uint256) {
        return uint256(keccak256(abi.encode(seed, a, b)));
    }

    function _totalVolume() internal view returns (uint256 v) {
        for (uint256 c = 1; c <= 7; ++c) v += boughtVol[c];
    }

    function _unsplitVolume() internal view returns (uint256 v) {
        for (uint256 c = 1; c <= 7; ++c) if (!_split(c)) v += _volumeUnits(c) * UNIT;
    }

    function _slot0() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(0))));
    }

    function _lastPurchaseFlag() internal view returns (bool) {
        return uint8(_slot0() >> (GameSlots.LAST_PURCHASE_DAY_OFFSET * 8)) != 0;
    }

    function _flags() internal view returns (uint8) {
        return uint8(_slot0() >> (GameSlots.JACKPOT_FLAGS_OFFSET * 8));
    }

    function _dailyIdxNow() internal view returns (uint24) {
        return uint24(_slot0() >> (GameSlots.DAILY_IDX_OFFSET * 8));
    }

    function _report(string memory tag) internal view {
        console2.log("=== scenario", tag);
        uint256 orders;
        for (uint256 c = 1; c <= 7; ++c) {
            console2.log("cohort", c);
            console2.log("  buyers", buyersOn[c]);
            console2.log("  orders", bought[c]);
            console2.log("  early-window orders", earlyOrders[c]);
            console2.log("  volume (wei)", boughtVol[c]);
            console2.log("  priced on day", pricedOn[c]);
            console2.log("  closed on day", closedOn[c]);
            console2.log("  level at close", closedAtLevel[c]);
            orders += bought[c];
        }
        console2.log("total orders", orders);
        console2.log("total Degenesis ETH (wei)", _totalVolume());
        console2.log("ordinary ETH spend (wei)", ordinaryEth);
        console2.log("  of which tickets (wei)", ticketEth);
        console2.log("last day index with a resolution", lastResolveDay);
        console2.log("orders resolved from index 9 on", resolvedFromIndex9);
        console2.log("orders resolved after level 1's jackpot ended", resolvedAfterL1Jackpot);
        console2.log("final level", game.currentLvl());
        console2.log("mineFlip calls (progressed)", mineCalls);
        console2.log("idle calls", idleCalls);
        console2.log("settlement calls", settleCalls);
        console2.log("allowance retries (first checkpoint above allowance)", sizingRetries);
        console2.log("tight calls sized above the base allowance", tightRaises);
        console2.log("peak mineFlip gas", peakGas);
        console2.log("  first action of the peak call", peakAction);
        console2.log("peak settlement-call gas", peakSettleGas);
    }
}
