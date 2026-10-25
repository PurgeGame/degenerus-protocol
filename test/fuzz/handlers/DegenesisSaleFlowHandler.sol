// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";

/// @title DegenesisSaleFlowHandler -- random interleavings across the Degenesis sale and the launch
/// @notice Buys (well-formed and malformed), ordinary purchases, next-pool fills, mineFlip on bounded
///         gas, delayed or immediate VRF fulfilment, time warps and whole-day drives, from deploy day
///         1 through the sale into the main launch. After every action it scans the Game's logs in
///         emission order and reads the sale state from storage, counting every departure from the
///         sale's state machine:
///         - while the wall day is a Degenesis day the level is 0, with no latch, turbo or jackpot
///           phase;
///         - an accepted buy is on a sale day, live, at least 0.01 ETH in whole 0.0001 ETH units;
///         - a sealed cohort's count and volume never change; split flags never clear and only a
///           sealed cohort splits, with its header volume; degenesisClosed never decreases;
///         - cohorts price and close strictly in order, a cohort prices only at a request after its
///           day, each order resolves once inside the active cohort, and a nonempty cohort closes
///           only after all its orders resolved (outside game over);
///         - a bound word implies an active cohort until game over; seven closes leave nothing active,
///           no word and no inventory; game over leaves nothing active.
contract DegenesisSaleFlowHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    sDGNRS public sdgnrs;
    address[] public actors;

    uint256 internal constant UNIT = 0.0001 ether;
    uint8 internal constant ACTION_IDLE = 0;
    uint8 internal constant ACTION_WAIT = 2;
    uint24 internal constant START = GameTimeLib.DEGENESIS_START_DAY;
    uint24 internal constant LAUNCH = GameTimeLib.MAIN_LAUNCH_DAY;

    bytes32 internal constant SIG_RESOLVED =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");
    bytes32 internal constant SIG_SPLIT = keccak256("DegenesisCohortSplit(uint8,uint256)");
    bytes32 internal constant SIG_PRICED = keccak256("DegenesisCohortPriced(uint8,uint256,uint256,uint24)");
    bytes32 internal constant SIG_CLOSED = keccak256("DegenesisCohortClosed(uint8,uint256)");
    bytes32 internal constant SIG_BURNED = keccak256("DegenesisInventoryBurned(uint256)");

    // ---- departures (each must stay 0) ----
    uint256 public bad_levelDuringSale;
    uint256 public bad_buyAccepted;
    uint256 public bad_sealedCohortChanged;
    uint256 public bad_splitCleared;
    uint256 public bad_splitBeforeSeal;
    uint256 public bad_closedRegressed;
    uint256 public bad_pricedOutOfOrder;
    uint256 public bad_pricedBeforeSeal;
    uint256 public bad_resolvedTwice;
    uint256 public bad_resolvedOutsideActive;
    uint256 public bad_closedOutOfOrder;
    uint256 public bad_closedWithUnresolved;
    uint256 public bad_wordWithoutCohort;
    uint256 public bad_liveAfterSeventhClose;
    uint256 public bad_liveAfterGameOver;
    uint256 public bad_burnNotOnSeventh;

    // ---- coverage ----
    uint256 public ghost_buys;
    uint256 public ghost_rejectedBuys;
    uint256 public ghost_offSaleRejects;
    uint256 public ghost_ordinary;
    uint256 public ghost_mines;
    uint256 public ghost_vrf;
    uint256 public ghost_priced;
    uint256 public ghost_resolved;
    uint256 public ghost_closes;
    uint256 public ghost_burns;
    uint256 public ghost_launched;
    uint256 public ghost_turbo;
    uint256 public ghost_gameOver;

    // ---- mirrors ----
    uint8 internal closedC;
    uint8 internal activeC;
    uint256[8] internal resolvedN;
    uint256[8] internal sealedCount;
    uint256[8] internal sealedVolume;
    bool[8] internal sealedSeen;
    bool[8] internal splitSeen;
    mapping(uint256 => bool) internal resolvedKey;
    uint256 internal nextFilled;

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, sDGNRS sdgnrs_, uint256 n) {
        game = game_;
        vrf = vrf_;
        sdgnrs = sdgnrs_;
        for (uint256 i; i < n; ++i) {
            address a = address(uint160(0xDE6E0000 + i));
            actors.push(a);
            vm.deal(a, 1_000_000 ether);
        }
        vm.recordLogs();
    }

    // =====================================================================
    // Actions
    // =====================================================================

    /// @notice A Degenesis buy: credit earned first through a real lootbox buy when short. One call
    ///         in five sends a malformed amount (off the 0.0001 ETH grid or below 0.01 ETH).
    function buy(uint256 actorSeed, uint256 unitsSeed, uint256 mode) external {
        address p = actors[actorSeed % actors.length];
        uint256 amount = bound(unitsSeed, 100, 25_000) * UNIT;
        bool malformed = mode % 5 == 0;
        if (malformed) amount = mode % 2 == 0 ? amount + 1 : UNIT * (1 + (mode >> 8) % 99);
        uint24 today = game.currentDayView_g542950();
        bool saleDay = today >= START && today < LAUNCH;
        uint256 credit = game.degenesisCreditOf(p);
        if (credit < amount && saleDay && !game.gameOver()) {
            _observe();
            uint256 spend = ((amount - credit) * 4 + 0.001 ether - 1) / 0.001 ether * 0.001 ether;
            if (spend < 0.01 ether) spend = 0.01 ether;
            vm.prank(p);
            try game.purchaseOrderFor{value: spend}(0, 0, BoxOrderLib.boCustom(spend), bytes32(0), MintPaymentKind.DirectEth, false) {
                ++ghost_ordinary;
            } catch {
                _dropLogs();
            }
        }
        bool live = !game.gameOver() && !game.livenessTriggered();
        _observe();
        vm.prank(p);
        try game.purchaseDegenesisBox{value: amount}(0, amount) {
            ++ghost_buys;
            if (!saleDay || !live || malformed) ++bad_buyAccepted;
        } catch {
            _dropLogs();
            ++ghost_rejectedBuys;
            if (!saleDay) ++ghost_offSaleRejects;
        }
        _observe();
    }

    /// @notice An ordinary ticket + lootbox purchase.
    function ordinary(uint256 actorSeed, uint256 ticketsSeed, uint256 boxSeed) external {
        address p = actors[actorSeed % actors.length];
        uint256 price = game.mintPrice();
        uint256 tickets = bound(ticketsSeed, 0, 40);
        uint256 box = bound(boxSeed, 0, 300) * 0.01 ether;
        if (tickets == 0 && box == 0) tickets = 1;
        _observe();
        vm.prank(p);
        try game.purchaseOrderFor{value: tickets * price + box}(
            0, tickets * 400, box == 0 ? 0 : BoxOrderLib.boCustom(box), bytes32(0), MintPaymentKind.DirectEth, false
        ) {
            ++ghost_ordinary;
        } catch {
            _dropLogs();
        }
        _observe();
    }

    /// @notice A large ticket buy toward the level-1 target (at most 90 ETH in total), so some runs
    ///         launch with the turbo and some without.
    function fillNext(uint256 actorSeed, uint256 ethSeed) external {
        if (nextFilled >= 90 ether) return _observe();
        address p = actors[actorSeed % actors.length];
        uint256 price = game.mintPrice();
        uint256 tickets = bound(ethSeed, 5 ether, 30 ether) / price;
        _observe();
        vm.prank(p);
        try game.purchaseOrderFor{value: tickets * price}(0, tickets * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {
            nextFilled += tickets * price;
            ++ghost_ordinary;
        } catch {
            _dropLogs();
        }
        _observe();
    }

    /// @notice One mineFlip on a bounded allowance.
    function mine(uint256 actorSeed, uint256 gasSeed) external {
        uint256 g = bound(gasSeed, 250_000, 10_000_000);
        _observe();
        vm.prank(actors[actorSeed % actors.length]);
        (bool ok,) = address(game).call{gas: g}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
        if (ok) ++ghost_mines;
        else _dropLogs();
        _observe();
    }

    /// @notice Answer the open request, if any.
    function fulfil(uint256 word) external {
        _fulfil(word);
        _observe();
    }

    /// @notice Move the clock 10 minutes to 26 hours.
    function warp(uint256 delta) external {
        vm.warp(vm.getBlockTimestamp() + bound(delta, 10 minutes, 26 hours));
        _observe();
    }

    /// @notice Drive the engine to idle, answering every request.
    function driveDay(uint256 word) external {
        for (uint256 i; i < 400; ++i) {
            _fulfil(uint256(keccak256(abi.encode(word, i))));
            uint8 a = game.nextMinerAction();
            if (a == ACTION_IDLE) break;
            if (a == ACTION_WAIT) {
                if (!_fulfil(uint256(keccak256(abi.encode(word, i, "w"))))) break;
                continue;
            }
            _observe();
            (bool ok,) = address(game).call(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
            if (!ok) {
                _dropLogs();
                break;
            }
            ++ghost_mines;
        }
        _observe();
    }

    function _fulfil(uint256 word) internal returns (bool) {
        uint256 req = vrf.lastRequestId();
        if (req == 0) return false;
        (,, bool done) = vrf.pendingRequests(req);
        if (done) return false;
        if (word == 0) word = 1;
        _observe();
        try vrf.fulfillRandomWords(req, word) {
            ++ghost_vrf;
            return true;
        } catch {
            _dropLogs();
            return false;
        }
    }

    /// @dev Forge records the logs of a reverted call too; a reverted call's logs never happened.
    ///      Callers observe before the call, so only the reverted call's logs are dropped.
    function _dropLogs() internal {
        vm.getRecordedLogs();
    }

    // =====================================================================
    // Observation
    // =====================================================================

    function _observe() internal {
        _scan(vm.getRecordedLogs());
        _checkState();
    }

    function _scan(Vm.Log[] memory logs) internal {
        uint24 today = game.currentDayView_g542950();
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(game) || l.topics.length == 0) continue;
            bytes32 t = l.topics[0];
            if (!_committed(t, l)) continue;
            if (t == SIG_RESOLVED) {
                (uint8 day, uint32 index) = abi.decode(l.data, (uint8, uint32));
                uint256 key = (uint256(day) << 32) | index;
                if (resolvedKey[key]) ++bad_resolvedTwice;
                resolvedKey[key] = true;
                if (day != activeC || index >= _count(day)) ++bad_resolvedOutsideActive;
                ++resolvedN[day];
                ++ghost_resolved;
            } else if (t == SIG_SPLIT) {
                uint256 c = uint256(l.topics[1]);
                uint256 vol = abi.decode(l.data, (uint256));
                // Terminal setup splits every cohort, sealed or not.
                if (!game.livenessTriggered() && (START + c - 1 >= today || vol != _volume(c))) ++bad_splitBeforeSeal;
            } else if (t == SIG_PRICED) {
                uint256 c = uint256(l.topics[1]);
                (uint256 vol,, uint24 boundDay) = abi.decode(l.data, (uint256, uint256, uint24));
                if (c != uint256(closedC) + 1 || activeC != 0) ++bad_pricedOutOfOrder;
                if (boundDay <= START + c - 1 || vol != _volume(c)) ++bad_pricedBeforeSeal;
                activeC = uint8(c);
                ++ghost_priced;
            } else if (t == SIG_CLOSED) {
                uint256 c = uint256(l.topics[1]);
                if (c != uint256(closedC) + 1) ++bad_closedOutOfOrder;
                if (_count(c) != 0 && (activeC != c || resolvedN[c] != _count(c)) && !game.gameOver()) {
                    ++bad_closedWithUnresolved;
                }
                closedC = uint8(c);
                activeC = 0;
                ++ghost_closes;
            } else if (t == SIG_BURNED) {
                if (closedC != 7) ++bad_burnNotOnSeventh;
                ++ghost_burns;
            }
        }
    }

    /// @dev Forge keeps the logs of a call frame the Game later rolled back. The miner catches a refused
    ///      worker (the daily request refuses when the coordinator call cannot be made, after its Degenesis
    ///      split and pricing already emitted) and carries on, so a recorded log is real only if the state
    ///      it announces is visible now. Game over forfeits the active cohort, so after it every log is taken
    ///      as recorded.
    function _committed(bytes32 t, Vm.Log memory l) internal view returns (bool) {
        if (game.gameOver()) return true;
        uint256 closedNow = uint8(uint256(vm.load(address(game), bytes32(uint256(0)))) >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
        uint256 active = uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE)));
        if (t == SIG_SPLIT) return (_header(uint256(l.topics[1])) >> 80) & 1 == 1;
        if (t == SIG_PRICED) {
            uint256 c = uint256(l.topics[1]);
            return closedNow >= c || (active != 0 && closedNow + 1 == c);
        }
        if (t == SIG_CLOSED) return closedNow >= uint256(l.topics[1]);
        if (t == SIG_BURNED) return closedNow == 7;
        if (t == SIG_RESOLVED) {
            (uint8 day, uint32 index) = abi.decode(l.data, (uint8, uint32));
            return closedNow >= day || (active != 0 && closedNow + 1 == day && uint32(active >> 184) > index);
        }
        return true;
    }

    function _checkState() internal {
        uint24 today = game.currentDayView_g542950();
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint24 lvl = uint24(slot0 >> (GameSlots.LEVEL_OFFSET * 8));
        bool latch = uint8(slot0 >> (GameSlots.LAST_PURCHASE_DAY_OFFSET * 8)) != 0;
        bool jp = uint8(slot0 >> (GameSlots.JACKPOT_PHASE_FLAG_OFFSET * 8)) != 0;
        uint8 flags = uint8(slot0 >> (GameSlots.JACKPOT_FLAGS_OFFSET * 8));
        uint8 closed = uint8(slot0 >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
        uint24 dailyIdx = uint24(slot0 >> (GameSlots.DAILY_IDX_OFFSET * 8));
        bool over = game.gameOver();

        if (today < LAUNCH && (lvl != 0 || latch || jp || flags & 1 != 0)) ++bad_levelDuringSale;
        if (closed < closedC) ++bad_closedRegressed;
        if (dailyIdx >= LAUNCH) ghost_launched = 1;
        if (lvl >= 1 && dailyIdx <= LAUNCH) ghost_turbo = 1;
        if (over) ghost_gameOver = 1;

        for (uint256 c = 1; c <= 7; ++c) {
            uint256 header = _header(c);
            bool split = (header >> 80) & 1 == 1;
            if (splitSeen[c] && !split) ++bad_splitCleared;
            if (split) splitSeen[c] = true;
            if (START + c - 1 < today) {
                if (!sealedSeen[c]) {
                    sealedSeen[c] = true;
                    sealedCount[c] = uint32(header >> 48);
                    sealedVolume[c] = uint48(header);
                } else if (sealedCount[c] != uint32(header >> 48) || sealedVolume[c] != uint48(header)) {
                    ++bad_sealedCohortChanged;
                }
            }
        }
        uint256 active = uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE)));
        uint256 word = uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD)));
        // Game over forfeits the active cohort and leaves its word as dead storage behind the latch.
        if (word != 0 && active == 0 && !over) ++bad_wordWithoutCohort;
        if (closed == 7 && (active != 0 || word != 0 || sdgnrs.poolBalance(sDGNRS.Pool.Degenesis) != 0)) {
            ++bad_liveAfterSeventhClose;
        }
        if (over && active != 0) ++bad_liveAfterGameOver;
    }

    function _header(uint256 c) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
    }

    function _count(uint256 c) internal view returns (uint256) {
        return uint32(_header(c) >> 48);
    }

    function _volume(uint256 c) internal view returns (uint256) {
        return uint256(uint48(_header(c))) * UNIT;
    }

    /// @notice Sum of every departure counter.
    function departures() external view returns (uint256) {
        return bad_levelDuringSale + bad_buyAccepted + bad_sealedCohortChanged + bad_splitCleared
            + bad_splitBeforeSeal + bad_closedRegressed + bad_pricedOutOfOrder + bad_pricedBeforeSeal
            + bad_resolvedTwice + bad_resolvedOutsideActive + bad_closedOutOfOrder + bad_closedWithUnresolved
            + bad_wordWithoutCohort + bad_liveAfterSeventhClose + bad_liveAfterGameOver + bad_burnNotOnSeventh;
    }

    /// @notice The highest closed count this run reached.
    function closedCount() external view returns (uint8) {
        return closedC;
    }
}
