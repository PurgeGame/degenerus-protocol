// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameFunding} from "../helpers/GameFunding.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MineFlipAdmission} from "../fuzz/helpers/MineFlipAdmission.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Storage-context reader. Etched over the Game for a view call, then the real code is restored.
contract ChainPinProbe is DegenerusGameStorage {
    struct Snap {
        uint24 level;
        bool locked;
        bool frozen;
        bool dead;
        bool ticketsDone;
        bool writeSlot;
        bool frozenPoolDue;
        uint24 ceiling;
        uint24 active;
        uint24 marker;
        uint24 requestDay;
        uint256 ffStale;
        uint256 decQueue;
        uint24 decEntries;
        uint8 decMode;
        uint8 decPhase;
        bool decGenerationDone;
        uint40 decGenerated;
        uint256 vaultPos;
        uint256 sdgnrsPos;
        bool complete;
        bool published;
        bool subsDone;
        uint256 pending;
        uint256 markers;
        bool dense;
    }

    function snap() external view returns (Snap memory s) {
        uint24 lvl = level;
        s.level = lvl;
        s.locked = rngLockedFlag;
        s.frozen = prizePoolFrozen;
        s.dead = gameOver || _livenessTriggered();
        s.ticketsDone = ticketsFullyProcessed;
        s.writeSlot = ticketWriteSlot;
        s.frozenPoolDue = _frozenPoolDue();
        s.ceiling = _mintCeiling();
        s.active = _activeTicketLevel();
        s.marker = ticketLevel;
        s.requestDay = rngRequestDay;
        uint24 lo = lvl + 1 > 99 ? lvl + 1 - 99 : 1;
        for (uint24 x = lo; x <= lvl + 1; ++x) {
            if (_ticketQueueLength(_tqFarFutureKey(x)) != 0) ++s.ffStale;
        }
        s.decQueue = decBattleQueue;
        s.decEntries = decEntriesLevel;
        uint24 head = uint24(decBattleQueue);
        if (head != 0) {
            DecJackpotPlan storage plan = decJackpotPlans[head];
            s.decMode = plan.mode;
            s.decPhase = decBattleRounds[head].phase;
            s.decGenerated = plan.generatedEntries;
            uint256 total = uint256(decBattleRounds[head].count) + plan.generatedEntries;
            uint256 survivors = (total + 1) / 2;
            if (survivors > 1000) survivors = 1000;
            s.decGenerationDone = plan.mode != 1
                && (plan.mode == 0 || plan.generatedEntries == 0 || plan.cursor == survivors);
        }
        s.vaultPos = _subPosition1(VAULT_WALLET_ID);
        s.sdgnrsPos = _subPosition1(SDGNRS_WALLET_ID);
        s.complete = _rngComplete();
        s.published = _rngSessionPublished();
        s.subsDone = subsFullyProcessed;
        s.pending = _pendingBoxCount;
        _book(s);
    }

    /// @dev AFKing set shape: both sections dense with a zero sentinel after each, and the box members
    ///      ahead of the opener that bought into the cohort (a protocol seat only once its BOUGHT bit,
    ///      1 Vault / 2 sDGNRS, is set).
    function _book(Snap memory s) private view {
        uint256 boxes = _subBoxCount;
        uint256 tickets = _subscribers.length - boxes;
        s.dense = true;
        for (uint256 i; i < boxes; ++i) if (_subscriberAt(i) == 0) s.dense = false;
        if (_subscriberAt(boxes) != 0) s.dense = false;
        for (uint256 i; i < tickets; ++i) if (_subscriberAt(2000 - i) == 0) s.dense = false;
        if (_subscriberAt(2000 - tickets) != 0) s.dense = false;
        uint8 flags = _afkingProtocolFlags;
        for (uint256 i = _subOpenCursor; i < boxes; ++i) {
            uint32 e = _subscriberAt(i);
            if (e == VAULT_WALLET_ID && flags & 1 == 0) continue;
            if (e == SDGNRS_WALLET_ID && flags & 2 == 0) continue;
            ++s.markers;
        }
    }

    function boxAt(uint48 buffer, uint32 position) external view returns (uint256) {
        return _boxEntryAt(buffer, position);
    }

    function setDeitySales(uint8 sales) external {
        deityPassSales = sales;
    }

    function queueLen(uint24 key) external view returns (uint256) {
        return _ticketQueueLength(key);
    }

    /// @dev Per level in [lo, hi]: read-key queue length, then far-future queue length.
    function windowLens(uint24 lo, uint24 hi) external view returns (uint256[] memory out) {
        out = new uint256[](2 * (uint256(hi) - lo + 1));
        for (uint24 x = lo; x <= hi; ++x) {
            uint256 i = 2 * (uint256(x) - lo);
            out[i] = _ticketQueueLength(_tqReadKey(x));
            out[i + 1] = _ticketQueueLength(_tqFarFutureKey(x));
        }
    }
}

/// @title ChainPinGameDrive
/// @notice A 100+ level drive of the real protocol through mineFlip, with ticket-mode and box-mode AFKing
///         subscribers, sDGNRS level-start whale buys, player tickets / boxes / passes / Degenerette bets /
///         Decimator burns, and a buyer poking the write side during every ticket window. Every engine
///         step is judged: the pins below are checked on the state before and after it. Violations are
///         counted per pin and reported together.
/// @dev Pins (audit couplings, S2 section 6):
///      F-T1/F-A1 an action selected as Tickets (and every other selected action) never reverts at 16M gas;
///      F-T2 no unminted-key queue at a level <= level + 1 outside a due frozen pool;
///      F-T3 read keys and the drained far-future keys never grow while the ticket window is open;
///      F-T5 a nonzero ticket marker always names a nonempty queue and survives its next Tickets step;
///      F-B1/F-D1 consumer stages run unlocked and unfrozen; the pool freeze never outlives the lock;
///      F-A7 Vault and sDGNRS stay at set positions 1 and 2; F-A8 AFKing ticket entries target the
///      active ticket level; F-C7/F-C6 the Decimator queue head owns the entry level and its
///      generation is complete before stage 5.
contract ChainPinGameDrive is DeployProtocol {
    uint256 private constant FULL = 16_000_000;
    uint24 private constant TARGET_LEVEL = 202;
    uint256 private constant MAX_DAYS = 2_200;
    uint256 private constant PLAYERS = 10;

    uint8 private constant A_TICKETS = 4;
    uint8 private constant A_AFKING = 8;
    uint8 private constant A_BOXES = 9;
    uint8 private constant A_DEGEN = 10;
    uint8 private constant A_DEC = 11;
    uint8 private constant A_PREPARE = 14;
    uint8 private constant A_DAILY_PHASE = 6;

    uint256 private constant V_T1 = 0;
    uint256 private constant V_T2 = 1;
    uint256 private constant V_T3 = 2;
    uint256 private constant V_T5 = 3;
    uint256 private constant V_B1 = 4;
    uint256 private constant V_D1 = 5;
    uint256 private constant V_A7 = 6;
    uint256 private constant V_A8 = 7;
    uint256 private constant V_C7 = 8;
    uint256 private constant V_C6 = 9;
    uint256 private constant V_ANY = 10;
    uint256 private constant V_A3 = 11;
    uint256 private constant V_BOX = 12;
    uint256 private constant V_N = 13;

    bytes32 private constant ENTRIES_SCALED = keccak256("EntriesQueuedScaled(uint32,uint24,uint32)");
    bytes32 private constant DEC_PLAN =
        keccak256("DecimatorJackpotPlan(uint24,uint256,uint96,uint64,uint40,uint128,uint96,uint128,uint32,uint40,uint64)");

    bytes private realCode;
    bytes private probeCode;
    address[] private actors;
    uint32[] private ticketSubIds;
    mapping(uint256 => bool) private subscribed;
    uint256 private simTime;
    uint256 private nonce;
    bool private halted;
    uint256 private haltCountdown;

    uint256[V_N] private viol;
    string[V_N] private firstWhere;

    // Coverage.
    uint256 private cDays;
    uint256 private cSteps;
    uint256 private cTicketsHard;
    uint256 private cTicketsMidQueue;
    uint256 private cWindowPokes;
    uint256 private cA8;
    uint256 private cFfSeen;
    uint256 private cDecPlans;
    uint256 private cDecGenPlans;
    uint256 private cDecFunded;
    uint256 private cDecGenerated;
    uint256 private cBets;
    uint256 private cDeityMax;
    uint256[2] private cDegenResolved; // [midday?]
    bytes32 private constant DEGEN_RESOLVED = keccak256("DegeneretteResolved(uint32,uint32,uint64,uint256,uint32,bytes)");
    bytes32 private constant LOOT_BOX_BUY = keccak256("LootBoxBuy(uint32,uint48,uint32,uint256)");
    uint256[22][2] private cStage; // [midday?][action]

    // T3 baseline.
    bool private baseValid;
    uint24 private baseLo;
    uint24 private baseHi;
    bool private baseSlot;
    uint256[] private baseLens;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        simTime = block.timestamp;
        mockVRF.fundSubscription(1, 1_000_000 ether);
        vm.deal(address(game), 200_000 ether);
        realCode = address(game).code;
        probeCode = type(ChainPinProbe).runtimeCode;
        for (uint256 i; i < PLAYERS; ++i) {
            address p = address(uint160(0xC4A10000 + i));
            actors.push(p);
            vm.deal(p, 5_000_000 ether);
        }
        _fundSdgnrs();
        vm.recordLogs();
    }

    function _fundSdgnrs() private {
        GameFunding.credit(2, 3_000 ether);
    }

    // =====================================================================
    // The drive
    // =====================================================================

    function testDriveHundredLevels() public {
        vm.pauseGasMetering();
        vm.recordLogs();
        uint256 d;
        for (; d < MAX_DAYS; ++d) {
            if (halted || game.gameOver()) break;
            if (game.currentLvl() >= TARGET_LEVEL && !game.jackpotPhase()) break;
            if (haltCountdown != 0 && --haltCountdown == 0) break;
            try this.playDay(d) {} catch (bytes memory why) {
                revert(string.concat("playDay ", vm.toString(d), " reverted: ", vm.toString(why), " at ", vm.envOr("PIN_WHERE", string(""))));
            }
        }
        cDays = d;
        _report();
        _finish();
    }

    /// @dev External so each day runs in its own call frame and frees its memory.
    function playDay(uint256 d) external {
        simTime += 1 days + 1;
        vm.warp(simTime);
        _seedNextPool();
        _degenerette(d + 1);
        _crank(d * 4);
        _morning(d);
        _crank(d * 4 + 1);
        vm.warp(simTime + 7 hours);
        _afternoon(d);
        _crank(d * 4 + 2);
        if (d % 25 == 24) _fundSdgnrs();
    }

    function _seedNextPool() private {
        if (game.jackpotPhase() || game.rngLocked()) return;
        uint256 target = game.prizePoolTargetView() + 0.01 ether;
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        if ((packed & ((uint256(1) << 128) - 1)) >= target) return;
        vm.store(
            address(game),
            bytes32(GameSlots.PRIZE_POOLS_PACKED),
            bytes32((packed & ~((uint256(1) << 128) - 1)) | target)
        );
    }

    // =====================================================================
    // Engine stepping
    // =====================================================================

    function _fulfill(uint256 salt) private returns (bool) {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return false;
        (, , bool done) = mockVRF.pendingRequests(req);
        if (done) return false;
        try mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("pin-drive", req, salt)))) {
            return true;
        } catch {
            return false;
        }
    }

    function _crank(uint256 tag) private {
        for (uint256 j; j < 700 && !halted; ++j) {
            _fulfill(tag * 1000 + j);
            uint8 a = game.nextMinerAction();
            if (a == 0) return;
            if (a == 2) {
                if (!_fulfill(tag * 1000 + j + 500)) return;
                continue;
            }
            _step(a);
            if (j % 2 == 0) _poke(j);
        }
    }

    function _rand() private returns (uint256) {
        return uint256(keccak256(abi.encode("pin-rand", ++nonce)));
    }

    function _snap() private returns (ChainPinProbe.Snap memory s) {
        vm.etch(address(game), probeCode);
        try ChainPinProbe(address(game)).snap() returns (ChainPinProbe.Snap memory got) {
            s = got;
        } catch (bytes memory why) {
            revert(string.concat("snap reverted: ", vm.toString(why)));
        }
        vm.etch(address(game), realCode);
    }

    function _lens(uint24 lo, uint24 hi) private returns (uint256[] memory out) {
        vm.etch(address(game), probeCode);
        out = ChainPinProbe(address(game)).windowLens(lo, hi);
        vm.etch(address(game), realCode);
    }

    function _qlen(uint24 key) private returns (uint256 n) {
        vm.etch(address(game), probeCode);
        n = ChainPinProbe(address(game)).queueLen(key);
        vm.etch(address(game), realCode);
    }

    function _mine(uint256 g) private returns (bool ok, bytes memory ret) {
        (ok, ret) = address(game).call{gas: g}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
    }

    /// @dev The smallest allowance (within 12%) that succeeds: a failed attempt leaves no state, so the
    ///      allowance is simply raised until the call makes progress.
    function _mineMinimal() private returns (bool ok, bytes memory ret) {
        uint256 g = 400_000;
        while (g < FULL) {
            (ok, ret) = _mine(g);
            if (ok) return (ok, ret);
            g = g * 9 / 8;
        }
        (ok, ret) = _mine(FULL);
    }

    function _violate(uint256 id, uint8 a, ChainPinProbe.Snap memory s) private {
        if (viol[id]++ == 0) {
            firstWhere[id] = string.concat(
                "level ", vm.toString(uint256(s.level)), " action ", vm.toString(uint256(a)), " day ", vm.toString(cDays)
            );
        }
        if (haltCountdown == 0) haltCountdown = 40;
    }

    function _at(string memory w) private {
        vm.setEnv("PIN_WHERE", w);
    }

    function _step(uint8 a) private {
        _at("step start");
        ++cSteps;
        vm.getRecordedLogs();
        ChainPinProbe.Snap memory pre = _snap();
        _checkState(a, pre);
        if (a == A_TICKETS && pre.marker != 0) ++cTicketsMidQueue;
        if (a == A_TICKETS) {
            // F-T5: a standing marker names a live queue before its Tickets step.
            if (pre.marker != 0 && _qlen(pre.marker) == 0) _violate(V_T5, a, pre);
        }
        if (a >= 8 && a <= 12 && (pre.locked || pre.frozen || pre.complete || !pre.published)) _violate(V_B1, a, pre);
        if (a == A_DEC && pre.decQueue == 0) _violate(V_C7, a, pre);
        if (a == A_PREPARE && pre.active != (pre.level + (_isJackpot() ? 0 : 1))) _violate(V_A8, a, pre);

        _at("pre checks done");
        uint256 min = MineFlipAdmission.minGas(a, false);
        uint256 r = _rand();
        uint256 g = r % 4 == 0 ? FULL : (r % 4 == 1 ? min : min + (r >> 8) % 1_500_000);
        bool ok;
        bytes memory ret;
        // Around the Decimator levels the daily phase runs on the smallest allowance that progresses, so the
        // generated-entry work is cut into the most calls the engine allows.
        bool minimal = a == A_DAILY_PHASE && (pre.level % 10 == 4 || pre.level % 10 == 5);
        if (minimal) {
            _at("minimal");
            (ok, ret) = _mineMinimal();
            _at("minimal done");
        } else if (g < FULL) {
            (ok, ret) = _mine(g);
        }
        if (!ok) {
            (ok, ret) = _mine(FULL);
            if (a == A_TICKETS) ++cTicketsHard;
            if (!ok) {
                // E() is what the Tickets stage reverts with when its ring preparation is refused; the call may
                // reach that stage after another action (Publish, DailyPhase) in the same mineFlip.
                bool isE = ret.length == 4 && bytes4(ret) == bytes4(keccak256("E()"));
                _violate(a == A_TICKETS || isE ? V_T1 : V_ANY, a, pre);
                emit log_named_bytes("mineFlip revert at 16M gas", ret);
                halted = true;
                return;
            }
        }
        // Stage coverage by request kind: a mid-day request carries day 0.
        ++cStage[pre.requestDay == 0 ? 1 : 0][a];

        _at("scan");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _scanLogs(a, pre, logs);
        _at("post snap");
        ChainPinProbe.Snap memory post = _snap();
        _at("post checks");
        _checkState(a, post);
        if (a == A_TICKETS && pre.marker != 0 && post.marker != pre.marker && _qlen(pre.marker) != 0) {
            _violate(V_T5, a, post);
        }
        _windowSample(post, a);
    }

    function _isJackpot() private view returns (bool) {
        return game.jackpotPhase();
    }

    /// @dev State pins that hold at every sample, before and after a step.
    function _checkState(uint8 a, ChainPinProbe.Snap memory s) private {
        if (s.ffStale != 0) {
            ++cFfSeen;
            if (!s.frozenPoolDue) _violate(V_T2, a, s);
        }
        if (s.marker != 0 && _qlen(s.marker) == 0) _violate(V_T5, a, s);
        if (s.frozen && !s.locked && !s.dead) _violate(V_D1, a, s);
        if (s.vaultPos != 1 || s.sdgnrsPos != 2) _violate(V_A7, a, s);
        if (!s.dense || (s.subsDone && s.pending != 0 && s.pending != s.markers)) _violate(V_A3, a, s);
        if (s.decQueue != 0 && s.decEntries != uint24(s.decQueue)) _violate(V_C7, a, s);
        if (s.decQueue != 0 && !s.locked && !s.decGenerationDone) _violate(V_C6, a, s);
    }

    /// @dev While the ticket window is open, no read key and no drained far-future key may grow.
    function _windowSample(ChainPinProbe.Snap memory s, uint8 a) private {
        if (s.ticketsDone || s.dead) {
            baseValid = false;
            return;
        }
        uint24 lo = s.level >= 2 ? s.level - 2 : 0;
        uint24 hi = s.ceiling;
        uint256[] memory now_ = _lens(lo, hi);
        if (baseValid && baseLo == lo && baseHi == hi && baseSlot == s.writeSlot) {
            for (uint256 i; i < now_.length; ++i) {
                if (now_[i] > baseLens[i]) {
                    _violate(V_T3, a, s);
                    break;
                }
            }
        }
        baseValid = true;
        baseLo = lo;
        baseHi = hi;
        baseSlot = s.writeSlot;
        baseLens = now_;
    }

    function _scanLogs(uint8 a, ChainPinProbe.Snap memory pre, Vm.Log[] memory logs) private {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 sig = logs[i].topics[0];
            if (a == A_PREPARE && sig == ENTRIES_SCALED && logs[i].topics.length > 1) {
                uint32 id = uint32(uint256(logs[i].topics[1]));
                for (uint256 k; k < ticketSubIds.length; ++k) {
                    if (ticketSubIds[k] != id) continue;
                    (uint24 target,) = abi.decode(logs[i].data, (uint24, uint32));
                    ++cA8;
                    if (target != pre.active) _violate(V_A8, a, pre);
                }
            }
            if (sig == DEC_PLAN) {
                (, , , , , uint96 funding, , , uint40 generated, ) =
                    abi.decode(logs[i].data, (uint256, uint96, uint64, uint40, uint128, uint96, uint128, uint32, uint40, uint64));
                ++cDecPlans;
                if (generated != 0) ++cDecGenPlans;
                if (funding != 0) ++cDecFunded;
            }
            if (sig == keccak256("DecimatorGenerated(uint24,uint64,uint32,uint8,uint32,uint256,uint256)")) {
                ++cDecGenerated;
            }
            if (sig == DEGEN_RESOLVED) ++cDegenResolved[pre.requestDay == 0 ? 1 : 0];
        }
    }

    // =====================================================================
    // Players
    // =====================================================================

    /// @dev A one-ticket buy between engine steps: while a ticket window is open this is the write-side
    ///      traffic that must not touch the sealed read side.
    function _poke(uint256 j) private {
        uint256 price = game.mintPrice();
        address who = actors[j % 4];
        vm.prank(who);
        try game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        ChainPinProbe.Snap memory s = _snap();
        if (!s.ticketsDone && !s.dead) {
            ++cWindowPokes;
            _windowSample(s, 0);
        }
    }

    function _buy(uint256 who, uint256 tickets, uint256 boxWei) private {
        uint256 price = game.mintPrice();
        uint256 cost = tickets * price + boxWei;
        if (cost == 0) return;
        vm.prank(actors[who]);
        try game.purchaseOrderFor{value: cost}(
            0, tickets * 400, boxWei == 0 ? 0 : BoxOrderLib.boCustomFloor(boxWei), bytes32(0), MintPaymentKind.DirectEth, false
        ) {} catch {}
    }

    function _morning(uint256 d) private {
        for (uint256 i; i < 4; ++i) {
            _buy(i, 1 + _rand() % 6, (i % 2 == 0) ? 0 : (0.1 ether + (_rand() % 10) * 0.1 ether));
        }
        _subscriptions(d);
        if (d % 7 == 3) _pass(1, 0);
        if (d % 31 == 5) _pass(2, 1);
        if (d == 40) _pass(2, 2);
        if (d == 70) _maxDeity();
        _decimator(d);
    }

    function _afternoon(uint256 d) private {
        for (uint256 i = 3; i < 7; ++i) {
            _buy(i, i == 3 ? 2 : 0, 0.2 ether + (_rand() % 20) * 0.1 ether);
        }
        _degenerette(d);
    }

    function _pass(uint256 who, uint256 kind) private {
        vm.prank(actors[who]);
        if (kind == 0) {
            try game.purchaseWhalePass{value: 40 ether}(0, 1 + _rand() % 4, bytes32(0)) {} catch {}
        } else if (kind == 1) {
            try game.purchaseLazyPass{value: 12 ether}(0, bytes32(0)) {} catch {}
        } else {
            try game.purchaseDeityPass{value: 80 ether}(0, 9, bytes32(0)) {} catch {}
        }
    }

    /// @dev The 30th paid deity sale (19,200 ETH) at a level past the early rate: its cover box is the largest
    ///      any producer sends and must fit the 21-bit units field and LB_UNITS_MAX.
    function _maxDeity() private {
        address buyer = actors[9];
        uint32 id = game.walletIdOf_g3120(buyer);
        vm.etch(address(game), probeCode);
        ChainPinProbe(address(game)).setDeitySales(29);
        vm.etch(address(game), realCode);
        vm.getRecordedLogs();
        vm.prank(buyer);
        try game.purchaseDeityPass{value: 19_200 ether}(0, 17, bytes32(0)) {} catch {
            return;
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != LOOT_BOX_BUY) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            (uint32 position,) = abi.decode(logs[i].data, (uint32, uint256));
            vm.etch(address(game), probeCode);
            uint256 entry = ChainPinProbe(address(game)).boxAt(uint48(uint256(logs[i].topics[2])), position);
            vm.etch(address(game), realCode);
            uint256 units = (entry >> 32) & 0x1FFFFF;
            ChainPinProbe.Snap memory s = _snap();
            if (units != 1_920_000 || units > 2_000_000 || ((entry >> 77) & 0x7F) != 1 || entry >> 85 != 0) {
                _violate(V_BOX, 0, s);
            }
            ++cDeityMax;
        }
    }

    function _degenerette(uint256 d) private {
        for (uint256 j; j < 3; ++j) {
            vm.prank(actors[(d + j) % PLAYERS]);
            try game.betDegenerette{value: 0.05 ether}(0, 0, uint128(0.01 ether), 5, uint8((d + j) % 24)) {
                ++cBets;
            } catch {}
        }
    }

    function _decimator(uint256 d) private {
        if (!game.decimatorActive()) return;
        for (uint256 j; j < 4; ++j) {
            address p = actors[(d + j) % PLAYERS];
            vm.prank(address(game));
            coin.mintForGame_g152734(p, 50_000);
            vm.prank(p);
            try coin.decimatorBurn(0, 5_000, 0) {} catch {}
        }
    }

    function _subscriptions(uint256 d) private {
        // 7, 8, 9: ticket-mode; 6: box-mode. Cancel and rejoin on a slow cycle to churn the set.
        for (uint256 i = 6; i < 10; ++i) {
            address p = actors[i];
            bool tickets = i != 6;
            if (subscribed[i] && (d + i) % 53 == 0) {
                vm.prank(p);
                try game.subscribe(0, tickets, 0, 0) {
                    subscribed[i] = false;
                } catch {}
                continue;
            }
            if (subscribed[i]) {
                if (game.afkingFundingOf(p) < 40 ether) {
                    uint32 pid = game.walletIdOf_g3120(p);
                    vm.prank(p);
                    try game.depositAfkingFunding{value: 400 ether}(pid) {} catch {}
                }
                continue;
            }
            uint256 seat = _grantSeat(p);
            vm.prank(p);
            try game.subscribe{value: 400 ether}(0, tickets, uint8(1 + (i + d) % 8), seat) {
                subscribed[i] = true;
                if (tickets) _trackTicketSub(game.walletIdOf_g3120(p));
            } catch {}
        }
    }

    function _trackTicketSub(uint32 id) private {
        for (uint256 k; k < ticketSubIds.length; ++k) if (ticketSubIds[k] == id) return;
        ticketSubIds.push(id);
    }

    // =====================================================================
    // Reporting
    // =====================================================================

    function _report() private {
        emit log_named_uint("days", cDays);
        emit log_named_uint("level", game.currentLvl());
        emit log_named_uint("engine steps", cSteps);
        emit log_named_uint("Tickets steps run at 16M", cTicketsHard);
        emit log_named_uint("Tickets steps starting mid-queue", cTicketsMidQueue);
        emit log_named_uint("pokes inside an open ticket window", cWindowPokes);
        emit log_named_uint("AFKing ticket entries checked (A8)", cA8);
        emit log_named_uint("samples with a stale far-future queue", cFfSeen);
        emit log_named_uint("Decimator plans", cDecPlans);
        emit log_named_uint("Decimator plans with generated entries", cDecGenPlans);
        emit log_named_uint("Decimator plans funded", cDecFunded);
        emit log_named_uint("Decimator generated entries", cDecGenerated);
        emit log_named_uint("Degenerette ETH bets placed", cBets);
        emit log_named_uint("Degenerette bets resolved after a daily cycle", cDegenResolved[0]);
        emit log_named_uint("Degenerette bets resolved after a mid-day cycle", cDegenResolved[1]);
        emit log_named_uint("max-price deity cover boxes checked", cDeityMax);
        for (uint256 a = 1; a < 22; ++a) {
            if (cStage[0][a] + cStage[1][a] != 0) {
                emit log_named_string(
                    string.concat("action ", vm.toString(a)),
                    string.concat("daily ", vm.toString(cStage[0][a]), " midday ", vm.toString(cStage[1][a]))
                );
            }
        }
    }

    function _finish() private view {
        string[V_N] memory names = [
            "F-T1 Tickets (or any E()) reverted at 16M", "F-T2 stale far-future queue", "F-T3 read key grew in window",
            "F-T5 ticket marker lost its queue", "F-B1 stage ran locked or frozen", "F-D1 freeze outlived lock",
            "F-A7 protocol seat moved", "F-A8 AFKing ticket target", "F-C7 decimator entry level",
            "F-C6 decimator generation", "any other action reverted at 16M", "F-A3 pending box count vs members", "F-B4 max deity cover box fields"
        ];
        string memory bad;
        for (uint256 i; i < V_N; ++i) {
            if (viol[i] != 0) {
                bad = string.concat(bad, names[i], " x", vm.toString(viol[i]), " (first: ", firstWhere[i], "); ");
            }
        }
        if (bytes(bad).length != 0) revert(string.concat("PIN VIOLATIONS: ", bad));
        // Non-vacuity of the drive itself.
        require(game.currentLvl() >= 201, "drive: never reached level 201");
        require(cTicketsHard >= 50, "drive: too few Tickets steps at 16M");
        require(cTicketsMidQueue >= 1, "drive: no Tickets step started mid-queue");
        require(cWindowPokes >= 20, "drive: no write-side traffic inside ticket windows");
        require(cA8 >= 20, "drive: no AFKing ticket delivery observed");
        require(cStage[0][A_BOXES] + cStage[1][A_BOXES] != 0, "drive: stage 3 never ran");
        require(cStage[1][A_BOXES] != 0, "drive: stage 3 never ran after a mid-day cycle");
        require(cDegenResolved[0] != 0, "drive: stage 4 never resolved a bet after a daily cycle");
        require(cDegenResolved[1] != 0, "drive: stage 4 never resolved a bet after a mid-day cycle");
        require(cDeityMax == 1, "drive: the max-price deity sale was not checked");
    }
}
