// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./DeployProtocol.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";

/// @title DegenesisWeekOpening -- a real Degenesis week as the opening of a stateful suite
/// @notice Deploys on day index 1 and plays the production timeline: on each Degenesis day
///         (indices 2..8) a rotating set of players earn credit through real ETH lootbox
///         purchases and place Degenesis orders inside and after the early-bonus window, with
///         the miner driven at several points of the day (mock VRF fulfilment only, no forged
///         stage). The opening then drives the first post-sale days until the seventh cohort
///         closes. With `turbo`, a real 67 ETH ticket buy on the deploy day puts the next pool
///         past the 50 ETH level-1 target, so the index-9 request latches the turbo and level 1
///         plays its one-day jackpot phase; without it the next pool stays below the target and
///         level 0 continues. Every Game log of the opening is scanned: each order resolves once,
///         cohorts split, price and close once each, the inventory burns once.
/// @dev Inheriting suites call `_degenesisWeek(turbo)` right after `_deployProtocol()` and
///      `_assertDegenesisWeekHappened()` wherever a non-vacuity gate belongs. The opening leaves
///      the engine idle on `dgwEndDay`.
abstract contract DegenesisWeekOpening is DeployProtocol {
    uint256 internal constant DGW_UNIT = 0.0001 ether;
    uint256 internal constant DGW_TARGET_L1 = 50 ether;
    uint256 internal constant DGW_PLAYERS = 18;
    uint8 internal constant DGW_ACTION_IDLE = 0;
    uint8 internal constant DGW_ACTION_WAIT = 2;
    uint8 internal constant DGW_ACTION_SETTLE = 21;
    uint8 internal constant DGW_STAGE_ENTERED_JACKPOT = 7;
    uint8 internal constant DGW_STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant DGW_STAGE_DEGENESIS_DAY = 21;
    uint8 internal constant DGW_JACKPOT_TURBO = 1;

    bytes32 internal constant DGW_SIG_RESOLVED =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");
    bytes32 internal constant DGW_SIG_SPLIT = keccak256("DegenesisCohortSplit(uint8,uint256)");
    bytes32 internal constant DGW_SIG_PRICED = keccak256("DegenesisCohortPriced(uint8,uint256,uint256,uint24)");
    bytes32 internal constant DGW_SIG_CLOSED = keccak256("DegenesisCohortClosed(uint8,uint256)");
    bytes32 internal constant DGW_SIG_BURNED = keccak256("DegenesisInventoryBurned(uint256)");
    bytes32 internal constant DGW_SIG_ADVANCE = keccak256("Advance(uint8,uint24)");

    /// @dev What the opening did.
    struct DegenesisWeekStats {
        bool turbo;
        uint24 endDay;
        uint256 orders;
        uint256 volume;
        uint256 resolved;
        uint256 splits;
        uint256 priced;
        uint256 closed;
        uint256 burns;
        uint256 degenesisDayStages;
        uint256 l1JackpotEntered;
        uint256 l1JackpotEnded;
        uint256 nextAtLaunch;
        uint256 lootboxEth;
    }

    DegenesisWeekStats internal dgw;
    uint256[8] internal dgwOrders;
    uint256[8] internal dgwVolume;
    mapping(uint256 => bool) internal dgwResolvedKey;
    address[] internal dgwPlayers;
    uint256 internal dgwWordSalt;
    uint8 internal dgwHandoffClosed;
    bool internal dgwOpening;

    function _deployTimestamp() internal pure virtual override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    /// @dev True for a suite that records every log from deploy on and ingests them itself: the
    ///      opening then neither restarts nor consumes the recording, and its log-derived checks
    ///      give way to the state-derived ones.
    function _dgwKeepLogs() internal pure virtual returns (bool) {
        return false;
    }

    /// @dev True for a hand-off with the settlement backlog still open: from day index 7 the miner
    ///      runs on small allowances and stops whenever Degenesis settlement is next, so cohort 6 is
    ///      still settling and cohort 7 split but unpriced when the suite's campaign starts.
    function _dgwBacklog() internal pure virtual returns (bool) {
        return false;
    }

    // ------------------------------------------------------------------ the opening

    function _degenesisWeek(bool turbo) internal {
        require(game.currentDayView() == 1, "DegenesisWeekOpening: deploy on day index 1");
        dgw.turbo = turbo;
        dgwOpening = true;
        dgwWordSalt = turbo ? 0xD6E7 : 0xD6E8;
        if (!_dgwKeepLogs()) vm.recordLogs();
        for (uint256 i; i < DGW_PLAYERS; ++i) {
            address p = makeAddr(string.concat("dgw-player-", vm.toString(i)));
            vm.deal(p, 100_000 ether);
            dgwPlayers.push(p);
        }

        // Deploy day: optional real next-pool fill, then the day is processed.
        if (turbo) {
            address whale = makeAddr("dgw-ticket-whale");
            uint256 cost = game.mintPrice() * 6700;
            vm.deal(whale, cost);
            vm.prank(whale);
            game.purchase{value: cost}(0, 6700 * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }
        _dgwDrive();

        for (uint256 c = 1; c <= 7; ++c) _dgwSaleDay(c);

        // The main launch: the first post-Degenesis request decides the turbo.
        uint24 launch = GameTimeLib.MAIN_LAUNCH_DAY;
        _dgwWarp(launch, 20 minutes);
        dgw.nextAtLaunch = game.nextPrizePoolView();
        if (turbo) require(dgw.nextAtLaunch > DGW_TARGET_L1 + 5 ether, "DegenesisWeekOpening: next pool not past the target");
        else require(dgw.nextAtLaunch + 5 ether < DGW_TARGET_L1, "DegenesisWeekOpening: next pool not below the target");
        _dgwDrive();
        require(!game.jackpotPhase(), "DegenesisWeekOpening: a jackpot phase outlived the launch day");
        if (turbo) {
            require(game.level() == 1, "DegenesisWeekOpening: index-9 request did not reach level 1");
            require(_dgwKeepLogs() || (dgw.l1JackpotEntered == 1 && dgw.l1JackpotEnded == 1), "DegenesisWeekOpening: level-1 jackpot not one day");
        } else {
            require(game.level() == 0, "DegenesisWeekOpening: level moved without the target");
            require(dgw.l1JackpotEntered == 0, "DegenesisWeekOpening: jackpot phase without the target");
        }

        uint24 d = launch;
        while (!_dgwBacklog() && _dgwClosed() < 7) {
            ++d;
            require(d <= launch + 6, "DegenesisWeekOpening: the sale never closed");
            _dgwWarp(d, 1 hours);
            _dgwDrive();
        }
        dgw.endDay = d;
        _dgwScan();
        dgwHandoffClosed = _dgwClosed();
        dgwOpening = false;
        _assertDegenesisWeekHappened();
    }

    /// @dev Degenesis day `c` (index c + 1): buyers spread over the day, the miner driven before
    ///      the first buy, at 1h, 7h and 13h, and after every fourth buyer.
    function _dgwSaleDay(uint256 c) internal {
        uint24 d = uint24(GameTimeLib.DEGENESIS_START_DAY + c - 1);
        _dgwWarp(d, 5 minutes);
        _dgwDrive();
        uint256 buyers = 7 + uint256(keccak256(abi.encode(dgwWordSalt, c))) % 5;
        uint256[3] memory driveAt = [uint256(1 hours), 7 hours, 13 hours];
        uint256 drives;
        for (uint256 k; k < buyers; ++k) {
            uint256 t = k < buyers / 3 + 1 ? 10 minutes + k * 1 hours : 6 hours + 5 minutes + k * 1 hours;
            while (drives < 3 && driveAt[drives] <= t) {
                _dgwWarp(d, driveAt[drives++]);
                _dgwDrive();
            }
            _dgwWarp(d, t);
            _dgwBuyer(c, k);
            if (k % 4 == 3) _dgwDrive();
        }
        while (drives < 3) {
            _dgwWarp(d, driveAt[drives++]);
            _dgwDrive();
        }
        require(game.level() == 0, "DegenesisWeekOpening: level moved during the sale");
        require(!game.jackpotPhase(), "DegenesisWeekOpening: jackpot phase during the sale");
        require(!_dgwLastPurchaseDay(), "DegenesisWeekOpening: last-purchase latch during the sale");
    }

    /// @dev Buyer k of cohort c: earn the credit with one real lootbox purchase (4x the orders),
    ///      then place one or two orders.
    function _dgwBuyer(uint256 c, uint256 k) internal {
        uint256 r = uint256(keccak256(abi.encode(dgwWordSalt, c, k)));
        address p = dgwPlayers[(c * 5 + k) % DGW_PLAYERS];
        uint256 n = r % 3 == 0 ? 2 : 1;
        uint256[2] memory amounts;
        uint256 total;
        for (uint256 j; j < n; ++j) {
            uint256 x = uint256(keccak256(abi.encode(r, j)));
            // 0.01 .. 0.5 ETH most of the time, up to 2.5 ETH one time in five.
            uint256 units = x % 5 == 0 ? 5000 + (x >> 8) % 20_001 : 100 + (x >> 8) % 4901;
            amounts[j] = units * DGW_UNIT;
            total += amounts[j];
        }
        uint256 credit = game.degenesisCreditOf(p);
        if (credit < total) {
            uint256 spend = ((total - credit) * 4 + 0.001 ether - 1) / 0.001 ether * 0.001 ether;
            if (spend < 0.01 ether) spend = 0.01 ether;
            vm.prank(p);
            game.purchase{value: spend}(0, 0, BoxOrderLib.boCustom(spend), bytes32(0), MintPaymentKind.DirectEth, false);
            dgw.lootboxEth += spend;
        }
        for (uint256 j; j < n; ++j) {
            vm.prank(p);
            game.buyDegenesisBox{value: amounts[j]}(0, amounts[j]);
            ++dgwOrders[c];
            dgwVolume[c] += amounts[j];
            ++dgw.orders;
            dgw.volume += amounts[j];
        }
    }

    // ------------------------------------------------------------------ engine

    /// @dev Run mineFlip until idle, answering every request with a derived word.
    function _dgwDrive() internal {
        bool lag = _dgwBacklog() && dgwOpening && game.currentDayView() >= 7;
        for (uint256 i; i < 2000; ++i) {
            _dgwFulfil();
            uint8 a = game.nextMinerAction();
            if (a == DGW_ACTION_IDLE || (lag && a == DGW_ACTION_SETTLE)) break;
            if (a == DGW_ACTION_WAIT) {
                if (!_dgwFulfil()) break;
                continue;
            }
            if (lag) _dgwMineSmall();
            else game.mineFlip(0);
            if (i == 1999) revert("DegenesisWeekOpening: engine never idle");
        }
        _dgwScan();
    }

    /// @dev One mineFlip on the least of 0.8M, 1.6M, ... 12.8M gas that runs, so little carries over
    ///      into settlement after the first action.
    function _dgwMineSmall() internal {
        for (uint256 g = 800_000; g <= 12_800_000; g *= 2) {
            (bool ok,) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            if (ok) return;
        }
        game.mineFlip(0);
    }

    function _dgwFulfil() internal returns (bool) {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return false;
        (,, bool done) = mockVRF.pendingRequests(req);
        if (done) return false;
        mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode(dgwWordSalt, req))));
        return true;
    }

    function _dgwWarp(uint24 d, uint256 secs) internal {
        vm.warp(uint256(d - 1) * 1 days + GameTimeLib.JACKPOT_RESET_TIME + secs);
        require(game.currentDayView() == d, "DegenesisWeekOpening: day mapping");
    }

    // ------------------------------------------------------------------ log scan

    function _dgwScan() internal {
        if (_dgwKeepLogs()) return;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(game) || l.topics.length == 0) continue;
            bytes32 t = l.topics[0];
            if (t == DGW_SIG_RESOLVED) {
                (uint8 day, uint32 index, uint256 amount) = abi.decode(l.data, (uint8, uint32, uint256));
                uint256 key = (uint256(day) << 32) | index;
                require(!dgwResolvedKey[key], "DegenesisWeekOpening: an order resolved twice");
                require(index < dgwOrders[day] && amount >= 0.01 ether, "DegenesisWeekOpening: unknown order resolved");
                dgwResolvedKey[key] = true;
                ++dgw.resolved;
            } else if (t == DGW_SIG_SPLIT) {
                ++dgw.splits;
            } else if (t == DGW_SIG_PRICED) {
                ++dgw.priced;
            } else if (t == DGW_SIG_CLOSED) {
                ++dgw.closed;
            } else if (t == DGW_SIG_BURNED) {
                ++dgw.burns;
            } else if (t == DGW_SIG_ADVANCE && l.topics.length == 1) {
                (uint8 stage, uint24 lvl) = abi.decode(l.data, (uint8, uint24));
                if (stage == DGW_STAGE_DEGENESIS_DAY) ++dgw.degenesisDayStages;
                else if (stage == DGW_STAGE_ENTERED_JACKPOT && lvl == 1) ++dgw.l1JackpotEntered;
                else if (stage == DGW_STAGE_JACKPOT_PHASE_ENDED && lvl == 1) ++dgw.l1JackpotEnded;
            }
        }
    }

    // ------------------------------------------------------------------ non-vacuity

    /// @notice The opening sold, sealed, split, priced, settled and closed all seven cohorts and
    ///         burned the leftover inventory once, through the production timeline; the turbo
    ///         decision matches the variant. State-based checks hold for the rest of a campaign.
    function _assertDegenesisWeekHappened() internal view {
        if (_dgwBacklog()) {
            assertLt(_dgwClosed(), 7, "NON-VACUITY: the backlog is open at the hand-off");
            assertGe(_dgwClosed(), 4, "NON-VACUITY: the early cohorts closed during the sale");
            assertTrue(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE))) != 0, "NON-VACUITY: a cohort is mid-settlement");
            assertGt(sdgnrs.poolBalance(sDGNRS.Pool.Degenesis), 0, "NON-VACUITY: inventory not yet burned");
        } else {
            assertEq(_dgwClosed(), 7, "NON-VACUITY: seven cohorts closed");
            assertEq(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE))), 0, "NON-VACUITY: no active cohort");
            assertEq(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD))), 0, "NON-VACUITY: no bound word");
            assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Degenesis), 0, "NON-VACUITY: inventory burned");
        }
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 header = uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
            assertGt(dgwOrders[c], 0, "NON-VACUITY: every Degenesis day sold");
            assertEq(uint32(header >> 48), dgwOrders[c], "NON-VACUITY: cohort order count");
            assertEq(uint256(uint48(header)) * DGW_UNIT, dgwVolume[c], "NON-VACUITY: cohort volume");
            assertTrue((header >> 80) & 1 == 1, "NON-VACUITY: cohort split");
        }
        if (dgw.turbo) {
            assertGe(game.level(), 1, "NON-VACUITY: level 1 reached");
            assertGt(dgw.nextAtLaunch, DGW_TARGET_L1, "NON-VACUITY: next pool above 50 ETH at the launch");
        } else {
            assertLe(dgw.nextAtLaunch, DGW_TARGET_L1, "NON-VACUITY: next pool at or below 50 ETH at the launch");
        }
        if (_dgwKeepLogs()) return;
        assertEq(dgw.splits, 7, "NON-VACUITY: seven splits");
        assertEq(dgw.degenesisDayStages, 7, "NON-VACUITY: seven Degenesis daily branches");
        if (dgw.turbo) assertEq(dgw.l1JackpotEnded, 1, "NON-VACUITY: the level-1 turbo jackpot ran");
        else assertEq(dgw.l1JackpotEntered, 0, "NON-VACUITY: no level-1 jackpot at the launch");
        if (_dgwBacklog()) {
            assertEq(dgw.closed, _dgwClosed(), "NON-VACUITY: closes match the closed count");
            assertEq(dgw.priced, dgw.closed + 1, "NON-VACUITY: one cohort priced past the closed ones");
            assertLt(dgw.resolved, dgw.orders, "NON-VACUITY: orders still owed at the hand-off");
            return;
        }
        assertEq(dgw.resolved, dgw.orders, "NON-VACUITY: every order resolved exactly once");
        assertEq(dgw.priced, 7, "NON-VACUITY: seven cohorts priced");
        assertEq(dgw.closed, 7, "NON-VACUITY: seven closes");
        assertEq(dgw.burns, 1, "NON-VACUITY: one inventory burn");
    }

    /// @notice After the period nothing reopens the sale: the closed count stays 7, no cohort is
    ///         active or bound, the inventory stays burned and every cohort header (count, volume,
    ///         split flag) is exactly what the week left. A buy, an append or a re-split after the
    ///         sale would break it.
    function _assertSaleStaysClosed() internal view {
        assertEq(_dgwClosed(), 7, "Degenesis: closed count moved after the sale");
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE))), 0, "Degenesis: a cohort reactivated");
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD))), 0, "Degenesis: a word was bound after the sale");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Degenesis), 0, "Degenesis: inventory refilled");
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 header = uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
            assertEq(uint32(header >> 48), dgwOrders[c], "Degenesis: an order joined a closed cohort");
            assertEq(uint256(uint48(header)) * DGW_UNIT, dgwVolume[c], "Degenesis: closed cohort volume changed");
            assertTrue((header >> 80) & 1 == 1, "Degenesis: split flag cleared");
        }
        assertEq(uint256(vm.load(address(game), keccak256(abi.encode(uint256(8), GameSlots.DEGENESIS_DAYS)))), 0, "Degenesis: an eighth cohort");
    }

    /// @notice With the backlog open at the hand-off, settlement only moves forward under the
    ///         campaign: the closed count never drops below the hand-off's, no cohort header changes
    ///         (no order joins after the sale), a bound word has its cohort until game over, and the seventh
    ///         close leaves nothing active, no word and no inventory.
    function _assertBacklogSettlesForward() internal view {
        uint8 closed = _dgwClosed();
        assertGe(closed, dgwHandoffClosed, "Degenesis: closed count fell below the hand-off");
        assertLe(closed, 7, "Degenesis: closed count above seven");
        uint256 active = uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE)));
        uint256 word = uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD)));
        // Game over forfeits the active cohort and leaves its word behind as dead storage: the
        // gameOver latch routes the miner before settlement is ever considered.
        if (word != 0 && !game.gameOver()) assertTrue(active != 0, "Degenesis: a bound word without its cohort");
        if (closed == 7) {
            assertEq(active, 0, "Degenesis: active after the seventh close");
            assertEq(word, 0, "Degenesis: word after the seventh close");
            assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Degenesis), 0, "Degenesis: inventory after the seventh close");
        }
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 header = uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
            assertEq(uint32(header >> 48), dgwOrders[c], "Degenesis: an order joined after the sale");
            assertEq(uint256(uint48(header)) * DGW_UNIT, dgwVolume[c], "Degenesis: cohort volume changed after the sale");
            assertTrue((header >> 80) & 1 == 1, "Degenesis: split flag cleared");
        }
    }

    // ------------------------------------------------------------------ readers

    function _dgwClosed() internal view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_CLOSED))) >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
    }

    function _dgwLastPurchaseDay() internal view returns (bool) {
        return uint8(uint256(vm.load(address(game), bytes32(uint256(0)))) >> (GameSlots.LAST_PURCHASE_DAY_OFFSET * 8)) != 0;
    }
}
