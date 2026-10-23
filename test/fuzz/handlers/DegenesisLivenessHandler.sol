// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";
import {MineFlipAdmission} from "../helpers/MineFlipAdmission.sol";

interface IFlipMint {
    function mintForGame(address to, uint256 amount) external;
}

/// @title DegenesisLivenessHandler -- mineFlip liveness on the Degenesis timeline
/// @notice Drives a day-1 deploy through the seven-day sale and past it: ordinary ticket, lootbox
///         (presets, customs up to the 2,000 ETH box, 1 to 100 per order), foil and whale-pass
///         buys that earn credit; Degenesis buys at the order bounds (the 0.01 ETH minimum, one
///         unit above it, the whole credit) paid from fresh ETH, overpay or prepaid AFKing; the
///         Vault's budget spend; VRF delays, stalls (mid-day timeout, daily retry, a stall across
///         the close) and gap days; and mineFlip calls whose gas is drawn from the first action's
///         minimum admission upward.
///
///         Every mineFlip call is judged against the engine's own selector, read for the same
///         caller just before it: Idle must revert NoWork, Wait must revert RngNotReady, and any
///         other action must succeed (the engine only returns once something progressed) when
///         the caller supplies at least `minGas(action)`. Anything else is a violation.
///         Calls run on the fuzzer's per-transaction warm/cold state; no account is re-cooled:
///         re-cooling an account the same transaction already wrote, and not writing it again,
///         drops that write when the fuzzer commits the transaction (observed: a mock
///         coordinator request lost while the Game kept its request active). Cold first-touch
///         gas at each minimum is covered by DegenesisMineFlipWalk, which runs in one
///         transaction.
/// @dev `minGas` is MineFlipAdmission's first-unit bound for the selected action.
contract DegenesisLivenessHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    uint8 internal constant A_IDLE = 0;
    uint8 internal constant A_TERMINAL = 1;
    uint8 internal constant A_WAIT = 2;
    uint8 internal constant A_PUBLISH = 3;
    uint8 internal constant A_TICKETS = 4;
    uint8 internal constant A_DAILY_GAP = 5;
    uint8 internal constant A_DAILY_APPLY = 6;
    uint8 internal constant A_DAILY_PHASE = 7;
    uint8 internal constant A_REDEMPTION = 8;
    uint8 internal constant A_AFKING = 9;
    uint8 internal constant A_HUMAN_BOXES = 10;
    uint8 internal constant A_DEGENERETTE = 11;
    uint8 internal constant A_DECIMATOR = 12;
    uint8 internal constant A_CRAPS = 13;
    uint8 internal constant A_CERTIFY = 14;
    uint8 internal constant A_PREPARE_SUBS = 15;
    uint8 internal constant A_MAINTENANCE = 16;
    uint8 internal constant A_REQUEST_DAILY = 17;
    uint8 internal constant A_REQUEST_MIDDAY = 18;
    uint8 internal constant A_GROWTH = 19;
    uint8 internal constant A_SEIZE_LOANS = 20;
    uint8 internal constant A_DEGENESIS_SETTLE = 21;

    uint256 internal constant DAY_OFFSET = 82_620;
    uint256 internal constant MAX_GAS = 30_000_000;
    /// @dev Total simulated time cap, in days after deploy: far inside the 30-day deadman and
    ///      the 14-day VRF timeout (pending requests older than FORCE_FULFILL_AFTER are answered).
    uint256 internal constant MAX_SIM_DAYS = 22;
    uint256 internal constant FORCE_FULFILL_AFTER = 9 days;
    uint256 internal constant LEVEL_ONE_SEED = 60 ether;

    bytes4 internal constant E_NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant E_RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes4 internal constant E_INSUFFICIENT_GAS = bytes4(keccak256("InsufficientExecutionGas()"));
    bytes4 internal constant E_EMPTY_REVERT = bytes4(keccak256("EmptyRevert()"));


    struct Violation {
        uint8 action;
        bytes4 selector;
        uint256 gasGiven;
        uint256 minGas;
        uint24 day;
        uint24 level;
        uint8 degenesisClosed;
        uint256 actionNo;
        string where;
    }

    Violation internal _first;
    uint256 public ghost_violations;

    // ---- coverage ----
    uint256 public ghost_actions;
    uint256 public ghost_mineCalls;
    uint256 public ghost_mineProgress;
    uint256 public ghost_noWork;
    uint256 public ghost_rngNotReady;
    uint256 public ghost_minGasCalls; // calls given exactly the action's minimum
    uint256 public ghost_tightSteps; // cheapest-progressing calls
    uint256 public ghost_belowMinOtherReverts; // below-minimum reverts that are not gas refusals
    uint256 public ghost_ticketBuys;
    uint256 public ghost_boxBuys;
    uint256 public ghost_bigBoxBuys; // a 2,000 ETH box or a 100-box order
    uint256 public ghost_foilBuys;
    uint256 public ghost_flipBuys; // FLIP-paid ticket buys
    uint256 public ghost_whaleBuys;
    uint256 public ghost_degenesisBuys;
    uint256 public ghost_degenesisMinBuys;
    uint256 public ghost_degenesisAfkingBuys;
    uint256 public ghost_vaultSpends;
    uint256 public ghost_splits; // cohorts carrying the split flag (peak)
    uint256 public ghost_priced; // distinct pricing days observed
    uint256 public ghost_resolved; // orders settled (peak of closed cohorts' orders + active cursor)
    uint256 public ghost_burns; // the seventh close observed
    uint256 public ghost_settleCalls; // calls whose first action was the Degenesis settlement
    uint256 public ghost_saleRequests; // daily requests while degenesisClosed < 7
    uint256 public ghost_saleApplies; // gap/apply with the Degenesis word copy admitted
    uint256 public ghost_stalls;
    uint256 public ghost_stallOverClose;
    uint256 public ghost_gapDays;
    uint256 public ghost_forcedFulfils;
    uint256 public ghost_poolSeeds;
    uint256 public ghost_maxLevel;
    uint256 public ghost_maxClosed;
    mapping(uint8 => uint256) public ghost_actionCalls;

    // ---- completion (filled by finish) ----
    bool public finishRan;
    bool public finishLeftSale;
    bool public finishSettled;
    uint24 public finishLevel;
    uint256 public finishDays;
    /// @dev Diagnostics: the slot-0 word and wall day when liveness first fired during finish.
    uint256 public finishLivenessSlot0;
    uint24 public finishLivenessDay;

    address[] public actors;
    uint256 internal _deployTs;
    uint256 internal _lastReq;
    uint256 internal _lastReqAt;
    uint24 internal _lastPricedDay;
    uint256 internal _lowestOpen;
    string internal _where;

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;
        _deployTs = block.timestamp;
        for (uint256 i; i < numActors; ++i) {
            address a = address(uint160(0xDE6E0000 + i));
            actors.push(a);
            vm.deal(a, 10_000_000 ether);
        }
    }

    /// @notice The run's action names in order, for diagnosing a completion failure.
    string public trace;

    modifier action(string memory name) {
        _where = name;
        trace = string.concat(trace, name, "@", vm.toString(uint256(game.currentDayView())), " ");
        ++ghost_actions;
        _trackRequest();
        _;
        _observe();
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // =====================================================================
    // Purchases
    // =====================================================================

    function actBuyTickets(uint256 actorSeed, uint256 qtySeed) external action("buyTickets") {
        _buyTickets(_actor(actorSeed), bound(qtySeed, 1, 40));
    }

    /// @dev One type per order: small, medium, large presets or a custom, 1 to 100 boxes; the
    ///      custom reaches the 2,000 ETH per-box cap.
    function actBuyLootbox(uint256 actorSeed, uint256 kindSeed, uint256 qtySeed, uint256 sizeSeed)
        external
        action("buyLootbox")
    {
        if (game.gameOver()) return;
        address a = _actor(actorSeed);
        uint256 kind = kindSeed % 5;
        uint256 qty = kindSeed >> 8 & 3 == 0 ? 100 : bound(qtySeed, 1, 100);
        uint256 order;
        uint256 value;
        (,,,, uint256 price) = game.purchaseInfo();
        if (kind == 0) {
            order = BoxOrderLib.boSmalls(qty);
            value = price * qty;
        } else if (kind == 1) {
            order = BoxOrderLib.boMeds(qty);
            value = price * 5 * qty;
        } else if (kind == 2) {
            order = BoxOrderLib.boLarges(qty);
            value = price * 25 * qty;
        } else if (kind == 3) {
            uint256 per = bound(sizeSeed, 10, 20_000) * 0.001 ether;
            order = BoxOrderLib.boCustoms(qty, per);
            value = per * qty;
        } else {
            // The per-box cap: one 2,000 ETH custom box.
            qty = 1;
            order = BoxOrderLib.boCustoms(1, 2_000 ether);
            value = 2_000 ether;
        }
        vm.prank(a);
        try game.purchase{value: value}(0, 0, order, bytes32(0), MintPaymentKind.DirectEth, false) {
            ++ghost_boxBuys;
            if (qty == 100 || kind == 4) ++ghost_bigBoxBuys;
        } catch {}
    }

    function actFoil(uint256 actorSeed) external action("foil") {
        if (game.gameOver()) return;
        (,,,, uint256 price) = game.purchaseInfo();
        vm.prank(_actor(actorSeed));
        try game.purchase{value: price * 80}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true) {
            ++ghost_foilBuys;
        } catch {}
    }

    /// @dev 1 to 10 passes, or the 1,000-pass whale cap.
    function actWhalePass(uint256 actorSeed, uint256 qtySeed) external action("whalePass") {
        if (game.gameOver()) return;
        uint256 qty = qtySeed % 16 == 0 ? 1000 : bound(qtySeed, 1, 10);
        uint256 value = qty * (game.level() < 4 ? 2.4 ether : 4 ether);
        vm.prank(_actor(actorSeed));
        try game.purchaseWhalePass{value: value}(0, qty, bytes32(0)) {
            ++ghost_whaleBuys;
        } catch {}
    }

    /// @notice A Degenesis order at a bound: the 0.01 ETH minimum, one unit above it, a random
    ///         amount, or the whole credit. Credit is earned first through a real lootbox buy
    ///         when short. Payment from fresh ETH, with overpay, or from prepaid AFKing.
    function actBuyDegenesis(uint256 actorSeed, uint256 amountSeed, uint256 modeSeed)
        external
        action("buyDegenesis")
    {
        if (game.gameOver()) return;
        uint24 today = game.currentDayView();
        if (today < GameTimeLib.DEGENESIS_START_DAY || today >= GameTimeLib.MAIN_LAUNCH_DAY) return;
        address a = _actor(actorSeed);
        uint256 shape = amountSeed % 4;
        uint256 amount = shape == 0 ? 0.01 ether : shape == 1 ? 0.0101 ether
            : bound(amountSeed >> 8, 100, 3_000_000) * 0.0001 ether;
        uint256 credit = game.degenesisCreditOf(a);
        if (shape == 3 && credit >= 0.01 ether) amount = credit - credit % 0.0001 ether;
        if (credit < amount) {
            uint256 spend = (amount - credit) * 4 + 0.04 ether;
            vm.prank(a);
            try game.purchase{value: spend}(0, 0, BoxOrderLib.boCustoms(1, _floorUnit(spend)), bytes32(0),
                MintPaymentKind.DirectEth, false) {
                ++ghost_boxBuys;
            } catch {}
            credit = game.degenesisCreditOf(a);
            if (credit < amount) return;
        }
        uint256 mode = modeSeed % 3;
        uint256 value = mode == 0 ? amount : mode == 1 ? amount + bound(modeSeed >> 8, 1, 1 ether) : 0;
        if (mode == 2) {
            uint32 id = game.walletIdOf_g3120(a);
            vm.prank(a);
            try game.depositAfkingFunding{value: amount}(id) {} catch { return; }
        }
        vm.prank(a);
        try game.buyDegenesisBox{value: value}(0, amount) {
            ++ghost_degenesisBuys;
            if (amount == 0.01 ether) ++ghost_degenesisMinBuys;
            if (mode == 2) ++ghost_degenesisAfkingBuys;
        } catch {}
    }

    /// @notice FLIP-paid tickets: no Degenesis credit, so a day of only these is a zero-volume
    ///         cohort. The FLIP comes from the Game's mint (a fixture shortcut with no ETH effect);
    ///         redemption opens only past the next pool's target (actSeedPool reaches it).
    function actFlipPaidTickets(uint256 actorSeed, uint256 qtySeed) external action("flipTickets") {
        if (game.gameOver()) return;
        address a = _actor(actorSeed);
        vm.prank(address(game));
        IFlipMint(ContractAddresses.COIN).mintForGame(a, 1_000_000 ether);
        uint256 qty = bound(qtySeed, 1, 20) * 400;
        vm.prank(a);
        try game.redeemFlip(0, qty) {
            ++ghost_flipBuys;
        } catch {}
    }

    /// @notice The Vault's Degenesis budget buys tickets or a whale pass at the normal price.
    function actVaultSpend(uint256 qtySeed, uint256 whaleSeed) external action("vaultSpend") {
        if (game.gameOver()) return;
        (,,,, uint256 price) = game.purchaseInfo();
        bool whale = whaleSeed % 4 == 0;
        uint256 qty = whale ? 1 : bound(qtySeed, 400, 4000);
        uint256 cost = whale ? 2.4 ether : price * qty / 400;
        uint32 recipient = qtySeed % 3 == 0 ? 0 : game.walletIdOf_g3120(_actor(qtySeed));
        vm.prank(ContractAddresses.VAULT);
        try game.spendDegenesis(recipient, whale, qty, 0, cost + 0.5 ether) {
            ++ghost_vaultSpends;
        } catch {}
    }

    /// @notice Push the next pool over the level-1 target so the close runs the turbo jackpot.
    function actSeedPool(uint256 extra) external action("seedPool") {
        _seedNextPool(LEVEL_ONE_SEED + bound(extra, 0, 20 ether));
    }

    // =====================================================================
    // VRF and time
    // =====================================================================

    function actFulfill() external action("fulfill") {
        _fulfillPending();
    }

    /// @dev Answer late: warp inside the day first.
    function actDelayedFulfill(uint256 secs) external action("delayedFulfill") {
        _warp(block.timestamp + bound(secs, 1 minutes, 10 hours));
        _fulfillPending();
    }

    /// @notice Warp past a timeout without answering. Kind 3 stalls across the sale's close:
    ///         to the main launch day, with any request still open.
    function actStall(uint256 kind, uint256 offset) external action("stall") {
        kind = kind % 4;
        if (_pending()) ++ghost_stalls;
        if (kind == 3) {
            uint256 launch = GameTimeLib.DEGENESIS_END_TS + bound(offset, 0, 20 hours);
            if (block.timestamp >= launch) return;
            if (game.currentDayView() + 3 < GameTimeLib.MAIN_LAUNCH_DAY) return;
            ++ghost_stallOverClose;
            _warp(launch);
            return;
        }
        uint256 dt = kind == 0 ? 4 hours + 1 : kind == 1 ? 12 hours + 1 : 12 hours + 1 days;
        _warp(block.timestamp + dt);
    }

    function actNextDay(uint256 offset, uint256 mode) external action("nextDay") {
        uint256 start = _nextDayStart();
        mode = mode % 3;
        if (mode == 0) _warp(start + bound(offset, 0, 23 hours));
        else if (mode == 1) _warp(start + bound(offset, 0, 30 minutes));
        else {
            ++ghost_gapDays;
            _warp(start + 1 days + bound(offset, 0, 12 hours));
        }
    }

    // =====================================================================
    // mineFlip
    // =====================================================================

    /// @notice `n` mineFlip calls by one caller, each at a gas drawn from the action's minimum up.
    function actMine(uint256 actorSeed, uint256 n, uint256 gasSeed) external action("mine") {
        address a = _actor(actorSeed);
        n = bound(n, 1, 12);
        for (uint256 i; i < n; ++i) {
            if (!_mineJudged(a, uint256(keccak256(abi.encode(gasSeed, i))))) break;
        }
    }

    /// @notice `n` rounds of: the cheapest calls that progress (gas escalating by 25% from 200k,
    ///      so each ends after its first unit) until the Degenesis settlement is next, then one
    ///      judged call, whose first action is that stage (or whatever is next) at its minimum.
    ///      An attempt at or above the minimum that reverts (other than NoWork / RngNotReady)
    ///      is a violation; below it any revert is allowed and a non-gas one is counted.
    function actMineTight(uint256 actorSeed, uint256 n, uint256 gasSeed) external action("mineTight") {
        address a = _actor(actorSeed);
        n = bound(n, 1, 4);
        for (uint256 i; i < n; ++i) {
            // Tight steps until the settlement is next (or nothing is), so it starts a call.
            for (uint256 k; k < 60; ++k) {
                vm.prank(a);
                uint8 next = game.minerAction();
                if (next == A_DEGENESIS_SETTLE || next == A_IDLE || next == A_WAIT) break;
                if (!_tightStep(a)) break;
                ++ghost_tightSteps;
            }
            if (!_mineJudged(a, uint256(keccak256(abi.encode(gasSeed, i))))) break;
        }
    }

    function _tightStep(address caller) internal returns (bool) {
        for (uint256 g = 200_000; g < MAX_GAS; g = g * 5 / 4) {
            if (game.gameOver()) return false;
            vm.prank(caller);
            uint8 a = game.minerAction();
            vm.prank(caller);
            (bool ok, bytes memory ret) =
                address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            if (ok) {
                _observe();
                return true;
            }
            bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
            if (sel == E_NO_WORK || sel == E_RNG_NOT_READY) return false;
            if (g >= minGas(a)) {
                _violate(a, sel, g, minGas(a));
                return false;
            }
            // Below the minimum a revert is allowed (it changes nothing); one that is not a gas
            // refusal is counted. Known: the sDGNRS whale buy's nested recordCoverBox
            // delegatecall turns an out-of-gas into E() (WhaleModule._recordLootboxEntry).
            if (ret.length != 0 && sel != E_INSUFFICIENT_GAS && sel != E_EMPTY_REVERT) ++ghost_belowMinOtherReverts;
        }
        return false;
    }

    /// @notice With VRF answering, mine to quiescence at random gas.
    function actRunToIdle(uint256 gasSeed) external action("runToIdle") {
        _runToIdle(gasSeed, 200);
    }

    // =====================================================================
    // Completion
    // =====================================================================

    /// @notice VRF cooperating and the next pool funded, walk day by day until the sale is over,
    ///         every cohort is closed and the game stands at level 1 or beyond. Every call is
    ///         judged as in actMine.
    function finish(uint256 seed) external {
        finishRan = true;
        _where = "finish";
        for (uint256 d; d < 40; ++d) {
            if (finishLivenessDay == 0 && game.livenessTriggered()) {
                finishLivenessDay = game.currentDayView();
                finishLivenessSlot0 = uint256(vm.load(address(game), bytes32(0)));
            }
            if (game.gameOver()) break;
            _fulfillPending();
            _runToIdle(uint256(keccak256(abi.encode(seed, d))), 300);
            _observe();
            uint24 today = game.currentDayView();
            finishLeftSale = today >= GameTimeLib.MAIN_LAUNCH_DAY;
            finishSettled = _degenesisClosed() == 7;
            finishLevel = game.level();
            if (finishLeftSale && finishSettled && finishLevel >= 1) {
                finishDays = d;
                return;
            }
            if (game.level() == 0) _seedNextPool(LEVEL_ONE_SEED);
            vm.warp(_nextDayStart() + 1 hours);
        }
        finishDays = type(uint256).max;
    }

    // =====================================================================
    // The judged call
    // =====================================================================

    /// @dev One call. Returns false when the engine reports nothing to do or waits.
    function _mineJudged(address caller, uint256 gasSeed) internal returns (bool) {
        if (game.gameOver()) return false;
        vm.prank(caller);
        uint8 a = game.minerAction();
        uint256 minimum = minGas(a);
        uint256 g = _drawGas(minimum, gasSeed);
        if (g == minimum) ++ghost_minGasCalls;
        ++ghost_mineCalls;
        ++ghost_actionCalls[a];
        if (a == A_DEGENESIS_SETTLE) ++ghost_settleCalls;
        bool sale = _degenesisClosed() < 7;
        if (a == A_REQUEST_DAILY && sale) ++ghost_saleRequests;
        if ((a == A_DAILY_GAP || a == A_DAILY_APPLY) && sale) ++ghost_saleApplies;
        vm.prank(caller);
        (bool ok, bytes memory ret) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        _observe();
        bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
        if (a == A_IDLE) {
            if (ok || sel != E_NO_WORK) _violate(a, sel, g, minimum);
            else ++ghost_noWork;
            return false;
        }
        if (a == A_WAIT) {
            if (ok || sel != E_RNG_NOT_READY) _violate(a, sel, g, minimum);
            else ++ghost_rngNotReady;
            return false;
        }
        if (!ok) {
            _violate(a, sel, g, minimum);
            return false;
        }
        ++ghost_mineProgress;
        return true;
    }

    /// @dev A quarter of the calls at the minimum, a quarter within 300k above it, the rest
    ///      anywhere up to MAX_GAS.
    function _drawGas(uint256 minimum, uint256 seed) internal pure returns (uint256) {
        if (minimum >= MAX_GAS) return minimum;
        uint256 mode = seed % 4;
        if (mode == 0) return minimum;
        if (mode == 1) return minimum + (seed >> 8) % 300_000;
        return minimum + (seed >> 8) % (MAX_GAS - minimum + 1);
    }

    /// @notice Gas a caller must supply for the first unit of `a` in the current state.
    function minGas(uint8 a) public view returns (uint256) {
        return MineFlipAdmission.minGas(a, _degenesisClosed() < 7);
    }

    function _violate(uint8 a, bytes4 sel, uint256 g, uint256 minimum) internal {
        if (ghost_violations++ != 0) return;
        _first = Violation({
            action: a,
            selector: sel,
            gasGiven: g,
            minGas: minimum,
            day: game.currentDayView(),
            level: game.level(),
            degenesisClosed: _degenesisClosed(),
            actionNo: ghost_actions,
            where: _where
        });
    }

    function firstViolation() external view returns (Violation memory) {
        return _first;
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _runToIdle(uint256 seed, uint256 maxCalls) internal {
        address caller = _actor(seed);
        for (uint256 i; i < maxCalls; ++i) {
            if (game.gameOver()) return;
            _fulfillPending();
            if (!_mineJudged(caller, uint256(keccak256(abi.encode(seed, "idle", i))))) {
                if (!_fulfillPending()) return;
            }
        }
    }

    /// @dev Sale progress read from state (log capture would grow handler memory without bound):
    ///      split flags, the active cohort, the settled-order count (closed cohorts' orders plus
    ///      the active cursor) and the seventh close.
    function _observe() internal {
        uint24 lvl = game.level();
        if (lvl > ghost_maxLevel) ghost_maxLevel = lvl;
        uint8 closed = _degenesisClosed();
        if (closed > ghost_maxClosed) ghost_maxClosed = closed;
        uint256 split;
        uint256 settled;
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 header = _header(c);
            if (header & (uint256(1) << 80) != 0) ++split;
            if (c <= closed) settled += uint32(header >> 48);
        }
        uint256 active = uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE)));
        if (active != 0) {
            settled += uint32(active >> 184);
            if (uint24(active >> 160) != _lastPricedDay) {
                _lastPricedDay = uint24(active >> 160);
                ++ghost_priced;
            }
        }
        if (split > ghost_splits) ghost_splits = split;
        if (settled > ghost_resolved) ghost_resolved = settled;
        if (closed == 7 && ghost_burns == 0) ghost_burns = 1;
    }

    function _header(uint256 c) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
    }

    function _buyTickets(address a, uint256 tickets) internal {
        if (game.gameOver()) return;
        (,,,, uint256 price) = game.purchaseInfo();
        vm.prank(a);
        try game.purchase{value: price * tickets}(0, tickets * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {
            ++ghost_ticketBuys;
        } catch {}
    }

    function _seedNextPool(uint256 want) internal {
        if (game.gameOver()) return;
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        uint256 cur = packed & type(uint128).max;
        if (cur >= want) return;
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED),
            bytes32((packed & ~uint256(type(uint128).max)) | want));
        vm.deal(address(game), address(game).balance + (want - cur));
        ++ghost_poolSeeds;
    }

    function _floorUnit(uint256 w) internal pure returns (uint256) {
        uint256 v = w - w % 0.001 ether;
        if (v > 2_000 ether) v = 2_000 ether;
        return v;
    }

    /// @dev Records when each new request appeared; answers one left open longer than
    ///      FORCE_FULFILL_AFTER (VRF eventually delivers inside its 14-day timeout).
    function _trackRequest() internal {
        uint256 id = vrf.lastRequestId();
        if (id != _lastReq) {
            _lastReq = id;
            _lastReqAt = block.timestamp;
        }
        if (_pending() && block.timestamp > _lastReqAt + FORCE_FULFILL_AFTER) {
            ++ghost_forcedFulfils;
            _fulfillPending();
        }
    }

    function _pending() internal view returns (bool) {
        uint256 last = vrf.lastRequestId();
        for (uint256 id = _lowestOpen == 0 ? 1 : _lowestOpen; id <= last; ++id) {
            (,, bool fulfilled) = vrf.pendingRequests(id);
            if (!fulfilled) return true;
        }
        return false;
    }

    /// @dev Answers every open request, oldest first: the Game's request may sit below a later
    ///      request from another consumer of the same coordinator.
    function _fulfillPending() internal returns (bool any) {
        uint256 last = vrf.lastRequestId();
        for (uint256 id = _lowestOpen == 0 ? 1 : _lowestOpen; id <= last; ++id) {
            (,, bool fulfilled) = vrf.pendingRequests(id);
            if (fulfilled) continue;
            try vrf.fulfillRandomWords(id, uint256(keccak256(abi.encode(block.timestamp, id, "deg-liveness")))) {
                any = true;
            } catch {}
        }
        _lowestOpen = last + 1;
    }

    /// @dev Warps are clamped to the simulation horizon.
    function _warp(uint256 ts) internal {
        uint256 cap = _deployTs + MAX_SIM_DAYS * 1 days;
        if (ts > cap) ts = cap;
        if (ts > block.timestamp) vm.warp(ts);
    }

    function _nextDayStart() internal view returns (uint256) {
        uint256 ts = block.timestamp;
        return ts - ((ts - DAY_OFFSET) % 1 days) + 1 days;
    }

    function _degenesisClosed() internal view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_CLOSED)))
            >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
    }
}
