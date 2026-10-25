// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {MineFlipAdmission} from "./helpers/MineFlipAdmission.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title DegenesisMineFlipWalk -- the Degenesis timeline mined at each action's minimum admission
/// @notice Whole scenarios driven only through mineFlip, every call given exactly the gas its
///         first action's declared bound needs (MineFlipAdmission.minGas), or a random amount
///         above it. A call must progress, or revert NoWork when the engine's selector said Idle,
///         or RngNotReady when it said Wait; any other outcome fails the test with the action,
///         the gas and the selector. Contracts are re-cooled before each call.
///         - a stall across the whole sale: orders over seven calendar days in the same cohort, nobody mines until after
///           the close, then the first request splits that cohort;
///         - a busy week mined daily, the next pool over the level-1 target, through the turbo
///           level-1 jackpot at the close;
///         - a deadman game over during the sale with every cohort unsplit;
///         - the same timelines at random gas from the minimum up.
contract DegenesisMineFlipWalk is DegenesisHarness {
    bytes4 internal constant E_NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant E_RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes32 internal constant SIG_FUNDS_RELEASED = keccak256("DegenesisFundsReleased(uint256,uint256)");
    bytes32 internal constant SIG_ADVANCE = keccak256("Advance(uint8,uint24)");
    uint256 internal constant MAX_GAS = 30_000_000;

    address internal miner;
    address[] internal buyers;
    /// @dev 0 = every call at the minimum; otherwise calls draw gas from this seed.
    uint256 internal gasSeed;
    uint256 internal calls;
    uint256 internal minCalls;
    uint256 internal splits;
    uint256 internal resolved;
    uint256 internal burns;
    uint256 internal fundsReleased;
    uint256 internal settleCalls;
    mapping(uint8 => uint256) internal peakUsed;
    mapping(uint8 => uint256) internal actionCalls;
    bool internal sawJackpotPhase;
    /// @dev First day the walk funds the next pool past the level-1 target.
    uint24 internal seedFrom;
    bool internal busySeed = true;

    function setUp() public override {
        super.setUp();
        miner = makeAddr("walk-miner");
        _giveWalletId(miner);
        vm.deal(address(game), 100_000 ether);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        for (uint256 i; i < 16; ++i) buyers.push(_player(string(abi.encode("walk-buyer", i))));
    }

    // =====================================================================
    // Scenarios
    // =====================================================================

    /// @notice Orders on all seven sale days, nobody mines until after the close: the first
    ///         request splits and prices cohort 1, then settlement runs one
    ///         cohort per day. Every call at the minimum.
    function test_StallAcrossWholeSale_MinimumGas() public {
        _saleWithoutMining(3);
        _walkDays(GameTimeLib.MAIN_LAUNCH_DAY + 1, 24, true);
        _assertSettledAtLevelOne();
        assertEq(splits, 1, "only the occupied logical cohort split");
    }

    /// @notice A busy week mined daily, the next pool above the level-1 target: the close runs
    ///         the turbo level-1 jackpot. Every call at the minimum.
    function test_BusyWeekTurboLevelOne_MinimumGas() public {
        _busyWeek(5);
        _walkDays(GameTimeLib.MAIN_LAUNCH_DAY, 18, true);
        _assertSettledAtLevelOne();
        assertTrue(sawJackpotPhase, "the level-1 jackpot phase ran");
    }

    /// @notice The same busy week with the next pool below the level-1 target at the close: level 0
    ///         continues with its ordinary level-one draws for three days, then the pool is funded
    ///         and the game reaches level 1. Every call at the minimum.
    function test_BusyWeekNoTurbo_MinimumGas() public {
        busySeed = false;
        seedFrom = GameTimeLib.MAIN_LAUNCH_DAY + 3;
        _busyWeek(5);
        _walkDays(GameTimeLib.MAIN_LAUNCH_DAY, 18, true);
        _assertSettledAtLevelOne();
    }

    /// @notice A deadman game over during the sale: orders on every sale day, no request ever
    ///         made, so all seven cohorts are unsplit at terminal setup, which splits them and
    ///         releases the Vault budget and sDGNRS AFKing. Every call at the minimum.
    function test_TerminalDuringSale_MinimumGas() public {
        _saleWithoutMining(2);
        vm.warp(block.timestamp + 32 days);
        assertTrue(game.livenessTriggered(), "deadman fires");
        _walkTerminal();
        assertEq(splits, 1, "terminal setup split the single occupied cohort");
        assertEq(fundsReleased, 1, "Degenesis funds released once");
    }

    /// @notice A deadman game over with a cohort priced and its bound word delivered but never
    ///         applied: the sale is mined through Degenesis day 4, the day-index-6 request prices a
    ///         cohort and its word lands, then nobody mines for 31 days. The ending draws its own
    ///         terminal word instead of applying the stale one, so the bound day is never recorded
    ///         and nothing is copied into degenesisWord: the terminal apply's DAILY_APPLY admission needs no DEGENESIS_WORD_COPY_GAS. The setup forfeits the
    ///         unsettled cohort and releases the Degenesis funds. Every call at the minimum.
    function test_TerminalAppliesBoundCohortWord_MinimumGas() public {
        for (uint256 c = 1; c <= 4; ++c) {
            _warpTo(_dayOf(c), 30 minutes);
            _walkToIdle(true);
            for (uint256 k; k < 3; ++k) _orderAtBound(buyers[(c * 3 + k) % buyers.length], c * 5 + k);
            _walkToIdle(true);
        }
        _warpTo(_dayOf(5), 30 minutes);
        _requestOnly(0);
        assertTrue(_active() != 0, "a cohort is priced and bound");
        uint24 bound = _activeDay();
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD))), 0, "its word not yet copied");
        vm.warp(block.timestamp + 31 days);
        assertTrue(game.livenessTriggered(), "deadman fires");
        bool copied;
        for (uint256 i; i < 120; ++i) {
            if (game.gameOver() && _jackpotPaid()) break;
            _fulfillPending(0);
            _judged(true);
            if (uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD))) != 0) copied = true;
        }
        assertTrue(game.gameOver() && _jackpotPaid(), "the ending finished");
        assertFalse(copied, "the stale bound-day word is never applied, so never copied");
        assertEq(_active(), 0, "the unsettled cohort is forfeited at game over");
        assertEq(fundsReleased, 1, "the Degenesis funds released once");
        emit log_named_uint("bound day", bound);
    }

    /// forge-config: default.fuzz.runs = 6
    function testFuzz_StallAcrossWholeSale_RandomGas(uint256 seed) public {
        gasSeed = seed | 1;
        _saleWithoutMining(2);
        _walkDays(GameTimeLib.MAIN_LAUNCH_DAY + 1 + uint24(seed % 4), 24, false);
        _assertSettledAtLevelOne();
    }

    /// forge-config: default.fuzz.runs = 6
    function testFuzz_BusyWeek_RandomGas(uint256 seed) public {
        gasSeed = seed | 1;
        _busyWeek(4);
        _walkDays(GameTimeLib.MAIN_LAUNCH_DAY, 18, false);
        _assertSettledAtLevelOne();
    }

    /// forge-config: default.fuzz.runs = 6
    function testFuzz_TerminalDuringSale_RandomGas(uint256 seed) public {
        gasSeed = seed | 1;
        _saleWithoutMining(2);
        vm.warp(block.timestamp + 32 days);
        _walkTerminal();
        assertEq(splits, 1, "terminal setup split the single occupied cohort");
    }

    // =====================================================================
    // Timelines
    // =====================================================================

    /// @dev `perDay` buyers a day on all seven sale days, each earning credit through an
    ///      ordinary lootbox and buying orders at the bounds; no mineFlip at all.
    function _saleWithoutMining(uint256 perDay) internal {
        _warpTo(2, 0);
        _walkToIdle(gasSeed == 0); // open the first logical sale cohort
        for (uint256 c = 1; c <= 7; ++c) {
            _warpTo(_dayOf(c), c * 1 hours);
            for (uint256 k; k < perDay; ++k) _orderAtBound(buyers[(c * perDay + k) % buyers.length], c * 7 + k);
        }
    }

    /// @dev A busy week mined daily at the minimum: buyers on every sale day, orders at the
    ///      bounds, ordinary ticket and lootbox volume, the next pool above the level-1 target.
    function _busyWeek(uint256 perDay) internal {
        for (uint256 c = 1; c <= 7; ++c) {
            uint24 d = _dayOf(c);
            _warpTo(d, 30 minutes);
            _walkToIdle(gasSeed == 0);
            for (uint256 k; k < perDay; ++k) _orderAtBound(buyers[(c * perDay + k) % buyers.length], c * 11 + k);
            (,,,, uint256 price) = game.purchaseInfo_g1027();
            vm.prank(buyers[c % buyers.length]);
            game.purchase{value: price * 40}(0, 40 * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
            _walkToIdle(gasSeed == 0);
        }
        if (busySeed) _seedNextPool(80 ether);
    }

    /// @dev One order at a bound: the minimum, one unit above it, a large order, or the whole
    ///      credit; credit from a real lootbox purchase.
    function _orderAtBound(address p, uint256 r) internal {
        uint256 shape = r % 4;
        uint256 amount = shape == 0 ? MIN_ORDER : shape == 1 ? MIN_ORDER + UNIT : (r % 20 + 1) * 0.1 ether;
        _earn(p, amount + 0.02 ether);
        if (shape == 3) {
            uint256 credit = game.degenesisCreditOf(p);
            amount = credit - credit % UNIT;
        }
        _buy(p, amount);
    }

    /// @dev Credit through one real custom lootbox of four times `credit`, rounded up to whole
    ///      0.001 ETH box units.
    function _earn(address p, uint256 credit) internal {
        uint256 spend = credit * 4;
        spend += (0.001 ether - spend % 0.001 ether) % 0.001 ether;
        if (p.balance < spend) vm.deal(p, spend + 1 ether);
        vm.prank(p);
        game.purchase{value: spend}(0, 0, BoxOrderLib.boCustoms(1, spend), bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @dev Day by day from `fromDay`, VRF answering, until the sale is settled at level 1.
    function _walkDays(uint24 fromDay, uint24 maxDays, bool minimum) internal {
        for (uint24 d = fromDay; d < fromDay + maxDays; ++d) {
            _warpTo(d, 1 hours);
            if (game.level() == 0 && d >= seedFrom) _seedNextPool(80 ether);
            _walkToIdle(minimum);
            if (_closed() == 7 && game.level() >= 1 && !_jackpotPhase()) return;
        }
    }

    /// @dev Terminal calls, VRF answering, until the terminal jackpot is paid.
    function _walkTerminal() internal {
        for (uint256 i; i < 120; ++i) {
            if (game.gameOver() && _jackpotPaid()) return;
            _fulfillPending(0);
            _judged(gasSeed == 0);
        }
        fail("terminal path did not finish");
    }

    /// @dev Step on small budgets until settlement is the next action, then mine it as the first
    ///      action of each call at its own minimum (or random gas) until it is no longer next.
    function _settleFirst(bool minimum) internal {
        for (uint256 i; i < 400; ++i) {
            _fulfillPending(0);
            uint8 next = game.nextMinerAction();
            if (next == MineFlipAdmission.DEGENESIS_SETTLE) break;
            if (next == MineFlipAdmission.IDLE || next == MineFlipAdmission.WAIT) return;
            if (!_tightStep()) return;
        }
        for (uint256 i; i < 400; ++i) {
            if (game.nextMinerAction() != MineFlipAdmission.DEGENESIS_SETTLE) return;
            _judged(minimum);
        }
    }

    /// @dev On settlement-focus days, whenever a cohort is priced, the stages before settlement run
    ///      on small unjudged budgets so settlement starts calls at its own minimum.
    /// @dev The cheapest call (within 25%) that progresses: its continuation estimates fail, so
    ///      the call ends after its first unit. Returns false on NoWork / RngNotReady.
    function _tightStep() internal returns (bool) {
        for (uint256 g = 200_000; g < MAX_GAS; g = g * 5 / 4) {
            vm.recordLogs();
            vm.prank(miner);
            (bool ok, bytes memory ret) =
                address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            if (ok) { _scan(vm.getRecordedLogs()); return true; }
            bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
            if (sel == E_NO_WORK || sel == E_RNG_NOT_READY) return false;
        }
        fail("tightStep: no gas level progressed");
    }

    function _walkToIdle(bool minimum) internal {
        bool focus = game.currentDayView_g542950() % 2 == 0;
        for (uint256 i; i < 1500; ++i) {
            if (focus && _closed() < 7 && _active() != 0) _settleFirst(minimum);
            _fulfillPending(0);
            if (!_judged(minimum)) {
                if (!_fulfillPending(0)) return;
            }
        }
        _report();
        fail("walk: engine never idled");
    }

    // =====================================================================
    // The judged call
    // =====================================================================

    /// @dev One mineFlip by `miner`. Returns false on the expected NoWork / RngNotReady.
    function _judged(bool minimum) internal returns (bool) {
        if (game.gameOver() && _jackpotPaid()) return false;
        vm.prank(miner);
        uint8 a = game.minerAction();
        uint256 floor_ = MineFlipAdmission.minGas(a, _closed() < 7);
        uint256 g = floor_;
        if (!minimum) {
            uint256 r = uint256(keccak256(abi.encode(gasSeed, calls)));
            if (r % 3 != 0 && floor_ < MAX_GAS) g = floor_ + (r >> 8) % (MAX_GAS - floor_ + 1);
        }
        if (g == floor_) ++minCalls;
        ++calls;
        ++actionCalls[a];
        if (a == MineFlipAdmission.DEGENESIS_SETTLE) ++settleCalls;
        if (a == MineFlipAdmission.DAILY_PHASE && _jackpotPhase()) sawJackpotPhase = true;
        _cool();
        vm.recordLogs();
        uint256 before = gasleft();
        vm.prank(miner);
        (bool ok, bytes memory ret) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        uint256 used = before - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // A reverted call has no effect; forge still records the logs it emitted.
        if (ok) _scan(logs);
        bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
        if (a == MineFlipAdmission.IDLE) {
            if (ok || sel != E_NO_WORK) _fail(a, sel, g, floor_, "idle must revert NoWork");
            return false;
        }
        if (a == MineFlipAdmission.WAIT) {
            if (ok || sel != E_RNG_NOT_READY) _fail(a, sel, g, floor_, "wait must revert RngNotReady");
            return false;
        }
        if (!ok) _fail(a, sel, g, floor_, "an action at or above its minimum admission must progress");
        if (used > peakUsed[a]) peakUsed[a] = used;
        return true;
    }

    function _fail(uint8 a, bytes4 sel, uint256 g, uint256 floor_, string memory why) internal {
        console2.log("action", uint256(a));
        console2.logBytes4(sel);
        console2.log("gas given", g);
        console2.log("minimum", floor_);
        console2.log("day", uint256(game.currentDayView_g542950()));
        console2.log("level", uint256(game.level()));
        console2.log("degenesisClosed", uint256(_closed()));
        fail(why);
    }

    function _scan(Vm.Log[] memory logs) internal {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 t = logs[i].topics[0];
            if (t == SIG_SPLIT) ++splits;
            else if (t == SIG_RESOLVED) ++resolved;
            else if (t == SIG_BURNED) ++burns;
            else if (t == SIG_FUNDS_RELEASED) ++fundsReleased;
            else if (t == SIG_ADVANCE) {
                (uint8 stage, uint24 lvl) = abi.decode(logs[i].data, (uint8, uint24));
                if (lvl == 1 && stage == 7) sawJackpotPhase = true;
            }
        }
    }

    function _assertSettledAtLevelOne() internal {
        _report();
        assertEq(_closed(), 7, "all seven cohorts closed");
        assertEq(burns, 1, "leftover inventory burned once");
        assertGe(uint256(game.level()), 1, "level 1 reached");
        assertGt(settleCalls, 0, "settlement ran as a first action at its minimum");
        assertGt(resolved, 0, "orders resolved");
        assertGt(minCalls, 0, "calls at the minimum");
    }

    function _report() internal {
        console2.log("calls", calls);
        console2.log("calls at the minimum", minCalls);
        console2.log("settlement calls", settleCalls);
        console2.log("orders resolved", resolved);
        for (uint8 a = 1; a <= 21; ++a) {
            if (actionCalls[a] == 0) continue;
            console2.log(string.concat("action ", vm.toString(uint256(a)), " calls ", vm.toString(actionCalls[a]),
                " peak gas used ", vm.toString(peakUsed[a]), " minimum ", vm.toString(MineFlipAdmission.minGas(a, true))));
        }
    }

    // =====================================================================
    // Readers
    // =====================================================================

    function _cool() internal {
        vm.cool(address(game));
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENESIS_MODULE);
        vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_GAMEOVER_MODULE);
        vm.cool(ContractAddresses.GAME_RNG_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE);
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.SDGNRS);
        vm.cool(ContractAddresses.COINFLIP);
        vm.cool(ContractAddresses.CRAPS);
        vm.cool(ContractAddresses.WWXRP);
        vm.cool(ContractAddresses.COIN);
        vm.cool(address(mockVRF));
    }

    function _seedNextPool(uint256 want) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        uint256 cur = packed & type(uint128).max;
        if (cur >= want) return;
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32((packed & ~uint256(type(uint128).max)) | want));
        vm.deal(address(game), address(game).balance + (want - cur));
    }

    function _jackpotPhase() internal view returns (bool) {
        return uint8(uint256(vm.load(address(game), bytes32(0))) >> (GameSlots.JACKPOT_PHASE_FLAG_OFFSET * 8)) != 0;
    }

    function _jackpotPaid() internal view returns (bool) {
        return uint8(uint256(vm.load(address(game), bytes32(uint256(GameSlots.GAME_OVER_STATE_PACKED)))) >> 48) != 0;
    }
}
