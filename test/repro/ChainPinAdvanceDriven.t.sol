// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {GamePoolSlots} from "../helpers/GamePoolSlots.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGame, MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IDegenerusGameFoilWorkerModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Forwards every call to a relocated copy of the real module through delegatecall, so it runs in the
///      Game's storage. `_enter` observes the state just before the call, `_leave` just after a successful one.
abstract contract ModuleSpy is DegenerusGameStorage {
    function _real() internal pure virtual returns (address);
    function _enter() internal virtual;
    function _leave(bytes memory ret) internal virtual;

    fallback() external payable {
        _enter();
        (bool ok, bytes memory data) = _real().delegatecall(msg.data);
        if (ok) _leave(data);
        assembly ("memory-safe") {
            switch ok
            case 0 { revert(add(data, 32), mload(data)) }
            default { return(add(data, 32), mload(data)) }
        }
    }
}

/// @dev Observes the x0 consolidation's buffer and queue state at the entry of `runBafJackpot`, then runs
///      the two preparations the real call performs (the same state change it makes next).
contract BafProbe is ModuleSpy {
    event BafPre(
        uint24 lvl, uint24 stampL, uint24 stampN, uint256 prevQueues, uint256 staleL, uint256 staleN,
        uint24 early, uint8 flags, bool idle
    );
    event BafPrep(bool okL, bool okN, uint24 stampL, uint24 stampN);

    function _real() internal pure override returns (address) {
        return address(uint160(uint256(keccak256("chainpin.draw.real"))));
    }

    function _lengths(uint24 lvl) private view returns (uint256) {
        return _ticketQueueLength(lvl) + _ticketQueueLength(lvl | TICKET_SLOT_BIT)
            + _ticketQueueLength(_tqFarFutureKey(lvl));
    }

    function _stale(uint24 stamp, uint24 want) private view returns (uint256) {
        return stamp == 0 || stamp == want ? 0 : _lengths(stamp);
    }

    function _enter() internal override {
        if (msg.sig != IDegenerusGame.runBafJackpot.selector) return;
        (, uint24 lvl,) = abi.decode(msg.data[4:], (uint256, uint24, uint256));
        uint24 stampL = _ticketBufferLevel(lvl);
        uint24 stampN = _ticketBufferLevel(lvl + 1);
        emit BafPre(
            lvl, stampL, stampN, _lengths(lvl - 1), _stale(stampL, lvl), _stale(stampN, lvl + 1),
            earlyTicketLevel, jackpotFlags, ticketsFullyProcessed && ticketSeats == 0
        );
        bool okL = _prepareTicketLevelAfterFoil(lvl);
        bool okN = _prepareTicketLevelAfterFoil(lvl + 1);
        emit BafPrep(okL, okN, _ticketBufferLevel(lvl), _ticketBufferLevel(lvl + 1));
    }

    function _leave(bytes memory) internal override {}
}

/// @dev Observes the far-future roots at the transition close that appends the deities' perpetual tickets.
contract PerpetualProbe is ModuleSpy {
    event PerpPre(
        uint24 lvl, uint24 target, uint256 ffLevel, uint256 ffTarget, uint256 deities, bool inJackpot,
        bool transition
    );
    event PerpPost(uint256 ffTarget);

    function _real() internal pure override returns (address) {
        return address(uint160(uint256(keccak256("chainpin.foil.real"))));
    }

    function _enter() internal override {
        if (msg.sig != IDegenerusGameFoilWorkerModule.queuePerpetualTickets.selector) return;
        uint24 target = abi.decode(msg.data[4:], (uint24));
        emit PerpPre(
            level, target, _ticketQueueLength(_tqFarFutureKey(level)), _ticketQueueLength(_tqFarFutureKey(target)),
            _deityCount(), jackpotPhaseFlag, phaseTransitionActive
        );
    }

    function _leave(bytes memory) internal override {
        if (msg.sig != IDegenerusGameFoilWorkerModule.queuePerpetualTickets.selector) return;
        uint24 target = abi.decode(msg.data[4:], (uint24));
        emit PerpPost(_ticketQueueLength(_tqFarFutureKey(target)));
    }
}

/// @dev Storage-side deity registration for the 32-owner transition close.
contract DeityFill is WalletSeed {
    function fill(uint256 n) external {
        for (uint160 i; i < n; ++i) _seedDeity(address(uint160(0xD1000 + i)));
    }
}

/// @notice Pins for the advance-module couplings that only hold through the real level lifecycle:
///         F1 (charity level pairing), F2 (far-future root sharing at the transition close), F3 (opening-day
///         decimator burn), F4 (x0 consolidation buffer preparation), F10 (affiliate pool decrement).
abstract contract ChainPinBase is DeployProtocol {
    address internal buyer = address(0xB4A1);
    address internal whale = address(0x7A1E);
    address internal foiler = address(0xF011);
    address internal boxer = address(0xB0C5);
    address internal crank = address(0xC4A9);

    uint256 internal simTime;
    uint256 internal constant MAX_MINE_CALLS = 20_000;
    uint256 internal maxDayCalls;
    /// @dev Nudges the initial simulated time; fulfillment witnesses keep both
    ///      the daily coinflip and the independently tagged BAF gate winning.
    uint256 internal constant WORD_NUDGE = 1;

    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 private constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    bytes32 private constant BAF_PRE = BafProbe.BafPre.selector;
    bytes32 private constant BAF_PREP = BafProbe.BafPrep.selector;
    bytes32 private constant PERP_PRE = PerpetualProbe.PerpPre.selector;
    bytes32 private constant PERP_POST = PerpetualProbe.PerpPost.selector;
    bytes32 private constant REC_SIG = keccak256("DecBurnRecorded(uint32,uint24,uint64,uint256,uint256,uint256,uint32)");
    bytes32 private constant BURN_SIG = keccak256("DecimatorBurn(uint32,uint256,uint64)");
    bytes32 private constant TOP_SIG = keccak256("AffiliateDgnrsReward(address,uint24,uint256)");
    bytes32 private constant ALLOC_SIG = keccak256("LevelDgnrsAllocated(uint24,uint256)");

    struct BafObs {
        uint24 lvl;
        uint24 stampL;
        uint24 stampN;
        uint256 prevQueues;
        uint256 staleL;
        uint256 staleN;
        uint24 early;
        uint8 flags;
        bool idle;
        bool okL;
        bool okN;
        uint24 postL;
        uint24 postN;
    }

    struct PerpObs {
        uint24 lvl;
        uint24 target;
        uint256 ffLevel;
        uint256 ffTargetBefore;
        uint256 deities;
        bool inJackpot;
        bool transition;
        uint256 ffTargetAfter;
        bool closed;
    }

    BafObs[] internal bafObs;
    PerpObs[] internal perpObs;
    mapping(uint24 => uint256) internal sdgnrsRecorded;
    uint256 internal sdgnrsBurns;
    mapping(uint24 => uint256) internal rewardPaid;
    mapping(uint24 => bool) internal rewardSeen;
    mapping(uint24 => uint256) internal allocation;
    mapping(uint24 => bool) internal allocationSeen;
    uint256 internal ticketBuys;
    uint256 internal whaleBuys;
    uint256 internal foilBuys;
    uint256 internal boxBuys;
    bool internal checkCharityLevel;
    uint32 internal sdgnrsId;
    bool internal crossedMidnight;

    function _setUpWorld() internal {
        _setUpWorld(true);
    }

    function _setUpWorld(bool spies) internal {
        _deployProtocol();
        // One pre-warp timestamp read: a second read after vm.warp can be folded to the old value.
        simTime = block.timestamp + 1 days + WORD_NUDGE;
        vm.warp(simTime);
        vm.deal(address(game), 20_000 ether);
        vm.deal(buyer, 500_000 ether);
        vm.deal(whale, 500_000 ether);
        vm.deal(foiler, 500_000 ether);
        vm.deal(boxer, 500_000 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
        deal(address(coin), buyer, 5_000_000 ether, true);
        sdgnrsId = game.walletIdOf_g3120(address(sdgnrs));
        if (spies) _installSpies();
        vm.recordLogs();
    }

    function _installSpies() internal {
        address drawReal = address(uint160(uint256(keccak256("chainpin.draw.real"))));
        address foilReal = address(uint160(uint256(keccak256("chainpin.foil.real"))));
        vm.etch(drawReal, ContractAddresses.GAME_JACKPOT_DRAW_MODULE.code);
        vm.etch(foilReal, ContractAddresses.GAME_TICKET_MODULE.code);
        vm.etch(ContractAddresses.GAME_JACKPOT_DRAW_MODULE, type(BafProbe).runtimeCode);
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, type(PerpetualProbe).runtimeCode);
    }

    // ---------------------------------------------------------------------
    // Mining driver
    // ---------------------------------------------------------------------

    /// @dev One engine call at the smallest admitting allowance. False when the engine is idle or waiting;
    ///      any other revert fails the test with its selector.
    function _mine() internal returns (bool) {
        if (game.nextMinerAction() == uint8(DegenerusGameStorage.MinerAction.RequestMidday)) return false;
        uint256[6] memory ladder = [uint256(1_500_000), 2_500_000, 3_500_000, 5_000_000, 9_000_000, 16_777_216];
        for (uint256 r; r < ladder.length; ++r) {
            (bool ok, bytes4 sel) = this.mineOnce(ladder[r]);
            if (ok) {
                if (checkCharityLevel) {
                    assertEq(uint256(gnrus.currentLevel()), uint256(game.level()), "F1: GNRUS level != game level");
                }
                return true;
            }
            if (sel == MineFlipGas.InsufficientExecutionGas.selector) continue;
            if (sel == NO_WORK || sel == RNG_NOT_READY) return false;
            revert(string.concat("harness: mineFlip reverted with ", vm.toString(sel)));
        }
        return false;
    }

    /// @dev One engine call in its own frame, so the driver's memory does not grow with the call count.
    function mineOnce(uint256 gasLimit) external returns (bool ok, bytes4 sel) {
        bytes memory err;
        (ok, err) = address(game).call{gas: gasLimit}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        sel = bytes4(err);
    }

    function _fulfillPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode(simTime, reqId))) | 1;
        while (uint256(keccak256(abi.encode(uint256(61), word))) & 1 == 0) {
            unchecked { word += 2; }
        }
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    function _requestInFlight() internal view returns (bool) {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return false;
        (,, bool fulfilled) = mockVRF.pendingRequests(id);
        return !fulfilled;
    }

    function _settle() internal {
        for (uint256 i;; ++i) {
            require(i < MAX_MINE_CALLS, "harness: every driven day drains before its cap");
            _fulfillPending();
            if (!_mine()) break;
        }
    }

    /// @dev Settle the deploy-warp day first: warping over an un-advanced day gap-backfills the purchase start
    ///      day and structurally disarms turbo.
    function _settleToday() internal {
        vm.pauseGasMetering();
        vm.recordLogs();
        _settle();
        this.scanRecordedLogs();
    }

    /// @dev Cross the day boundary and run the whole advance chain. With `crossAt` set, the clock moves past
    ///      the next midnight the moment the request that promotes the game to level `crossAt` is in flight.
    function _runDay(uint24 crossAt) internal {
        this.runDayFrame(crossAt);
    }

    /// @dev Release the driver's temporary ABI arrays between simulated days.
    function runDayFrame(uint24 crossAt) external {
        require(msg.sender == address(this), "driver self-call");
        simTime += 1 days + 1;
        vm.warp(simTime);
        for (uint256 i;; ++i) {
            require(i < MAX_MINE_CALLS, "harness: every driven day drains before its cap");
            if (crossAt != 0 && !crossedMidnight && game.level() == crossAt && _requestInFlight()) {
                crossedMidnight = true;
                simTime += 1 days;
                vm.warp(simTime);
            }
            _fulfillPending();
            if (i % 1000 == 999) this.scanRecordedLogs();
            if (!_mine()) {
                if (i > maxDayCalls) maxDayCalls = i;
                break;
            }
        }
        this.scanRecordedLogs();
    }

    function _runFullDay() internal {
        _runDay(0);
    }

    // ---------------------------------------------------------------------
    // Buys and pool helpers
    // ---------------------------------------------------------------------

    function _levelPrizePool(uint24 lvl) internal view returns (uint256) {
        uint256 v = GamePoolSlots.read(address(game), lvl);
        return v < 50 ether ? 50 ether : v;
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        uint256 mask = (uint256(1) << 128) - 1;
        if ((packed & mask) >= targetNext) return;
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32((packed & ~mask) | targetNext));
    }

    function _setNextPrizePool(uint256 value) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        uint256 mask = (uint256(1) << 128) - 1;
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32((packed & ~mask) | value));
    }

    function _buyTickets() internal {
        (,,, bool locked, uint256 priceWei) = game.purchaseInfo_g1027();
        if (locked) return;
        vm.prank(buyer);
        try game.purchase{value: (priceWei * 4000) / 400}(
            0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false
        ) { ++ticketBuys; } catch {}
    }

    function _tryCoinflipDeposit() internal {
        vm.prank(buyer);
        try coinflip.depositCoinflip(0, 500) {} catch {}
    }

    /// @dev A whale pass (far-future tickets), a foil pack and a lootbox, each by its own buyer.
    function _extraBuys() internal {
        (,,, bool locked, uint256 priceWei) = game.purchaseInfo_g1027();
        if (locked) return;
        vm.prank(whale);
        try game.purchaseWhalePass{value: 10 ether}(0, 1, bytes32(0)) { ++whaleBuys; } catch {}
        vm.prank(foiler);
        try game.purchase{value: 10 * priceWei}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true) {
            ++foilBuys;
        } catch {}
        vm.prank(boxer);
        try game.purchase{value: 1 ether}(
            0, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false
        ) { ++boxBuys; } catch {}
    }

    function _fundSdgnrsFlip() internal {
        vm.prank(address(game));
        coinflip.creditFlip_g317(sdgnrsId, 100_000);
    }

    /// @dev Register thirty more deities (32 in all) through the production allocator, without paying: a paid
    ///      pass past the 23rd costs thousands of ETH and confers a lootbox of that size, which swamps the drive.
    function _seedDeities() internal {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(DeityFill).runtimeCode);
        DeityFill(address(game)).fill(30);
        vm.etch(address(game), original);
    }

    // ---------------------------------------------------------------------
    // Log scan
    // ---------------------------------------------------------------------

    /// @dev Release decoded log memory between driven days while retaining every observation.
    function scanRecordedLogs() external {
        require(msg.sender == address(this), "log scan self-call");
        _scan(vm.getRecordedLogs());
    }

    function _scan(Vm.Log[] memory logs) internal {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length == 0) continue;
            bytes32 t = l.topics[0];
            if (l.emitter == address(game)) {
                if (t == BAF_PRE) {
                    BafObs memory o;
                    (o.lvl, o.stampL, o.stampN, o.prevQueues, o.staleL, o.staleN, o.early, o.flags, o.idle) =
                        abi.decode(l.data, (uint24, uint24, uint24, uint256, uint256, uint256, uint24, uint8, bool));
                    bafObs.push(o);
                } else if (t == BAF_PREP) {
                    BafObs storage o = bafObs[bafObs.length - 1];
                    (o.okL, o.okN, o.postL, o.postN) = abi.decode(l.data, (bool, bool, uint24, uint24));
                } else if (t == PERP_PRE) {
                    PerpObs memory p;
                    (p.lvl, p.target, p.ffLevel, p.ffTargetBefore, p.deities, p.inJackpot, p.transition) =
                        abi.decode(l.data, (uint24, uint24, uint256, uint256, uint256, bool, bool));
                    perpObs.push(p);
                } else if (t == PERP_POST) {
                    PerpObs storage p = perpObs[perpObs.length - 1];
                    p.ffTargetAfter = abi.decode(l.data, (uint256));
                    p.closed = true;
                } else if (t == REC_SIG && uint32(uint256(l.topics[1])) == sdgnrsId) {
                    ++sdgnrsRecorded[uint24(uint256(l.topics[2]))];
                } else if (t == TOP_SIG) {
                    uint24 lvl = uint24(uint256(l.topics[2]));
                    rewardPaid[lvl] = abi.decode(l.data, (uint256));
                    rewardSeen[lvl] = true;
                } else if (t == ALLOC_SIG) {
                    uint24 lvl = uint24(uint256(l.topics[1]));
                    allocation[lvl] = abi.decode(l.data, (uint256));
                    allocationSeen[lvl] = true;
                }
            } else if (l.emitter == address(coin) && t == BURN_SIG && uint32(uint256(l.topics[1])) == sdgnrsId) {
                ++sdgnrsBurns;
            }
        }
    }

    // ---------------------------------------------------------------------
    // Drivers
    // ---------------------------------------------------------------------

    /// @dev Turbo-chain levels from genesis (the next pool is seeded over target every purchase day, so each level
    ///      collapses in one locked chain) until the game reaches `targetLevel`.
    function _driveTurbo(uint24 targetLevel, uint24 crossAt) internal {
        _settleToday();
        for (uint256 i; i < 200; ++i) {
            require(!game.gameOver(), "harness: gameOver");
            if (game.level() >= targetLevel) return;
            if (!game.jackpotPhase()) {
                _fundSdgnrsFlip();
                _seedNextPrizePool(_levelPrizePool(game.level()) + 25 ether);
                _buyTickets();
                _tryCoinflipDeposit();
            }
            _runDay(crossAt);
        }
        revert("harness: never reached the target level");
    }

    enum Mode {
        Turbo,
        Normal,
        NormalEarly
    }

    /// @dev Drive through level 10's x0 consolidation and its jackpot phase. Turbo: every level, level 10
    ///      included, collapses in one chain. Normal: level 10's purchase phase runs three days (the first
    ///      with the next pool held under target), so its latch is the ordinary one. NormalEarly additionally
    ///      sends a mid-day request after the latch, activating the next level's pool early.
    function _driveX0(Mode mode, bool extras) internal {
        _settleToday();
        uint256 x0PurchaseDays;
        for (uint256 i; i < 300; ++i) {
            require(!game.gameOver(), "harness: gameOver before level 10");
            uint24 lvl = game.level();
            bool jp = game.jackpotPhase();
            if (lvl >= 10 && !jp && bafObs.length != 0) return;
            bool normalX0 = mode != Mode.Turbo && lvl == 9 && !jp;
            if (!jp) _buyTickets();
            if (extras) _extraBuys();
            if (!jp) {
                if (normalX0 && x0PurchaseDays == 0) _setNextPrizePool(1 ether);
                else _seedNextPrizePool(_levelPrizePool(lvl) + 25 ether);
                _tryCoinflipDeposit();
            }
            if (normalX0) ++x0PurchaseDays;
            _runFullDay();
            if (normalX0 && mode == Mode.NormalEarly && x0PurchaseDays == 2) {
                (,, bool latched,,) = game.purchaseInfo_g1027();
                require(latched, "harness: the x0 latch must be set");
                _middayRequest();
                _settle();
                this.scanRecordedLogs();
            }
        }
        revert("harness: never completed level 10");
    }

    /// @dev Buy a lootbox and fire a mid-day request, or finish the read session until the miner sends its own.
    function _middayRequest() internal {
        if (_requestInFlight()) return;
        if (_settleReadsUntilRequest()) return;
        vm.prank(buyer);
        game.purchase{value: 2 ether}(
            0, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
        uint256 priorReq = mockVRF.lastRequestId();
        vm.prank(crank);
        (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        require(ok && mockVRF.lastRequestId() > priorReq, "harness: mineFlip must issue the mid-day request");
    }

    function _settleReadsUntilRequest() internal returns (bool minerRequested) {
        for (uint256 i; i < MAX_MINE_CALLS; ++i) {
            _fulfillPending();
            uint256 id = mockVRF.lastRequestId();
            (,, bool fulfilled) = mockVRF.pendingRequests(id);
            if (game.rngComplete() && (id == 0 || fulfilled)) return false;
            uint256[6] memory ladder = [uint256(2_700_000), 3_500_000, 4_500_000, 6_000_000, 9_000_000, 16_777_216];
            bool progressed;
            for (uint256 r; r < ladder.length && !progressed; ++r) {
                (bool ok, bytes memory err) =
                    address(game).call{gas: ladder[r]}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
                if (ok) progressed = true;
                else if (bytes4(err) == NO_WORK) return false;
                else require(bytes4(err) == MineFlipGas.InsufficientExecutionGas.selector, "harness: reads settle");
            }
            require(progressed, "harness: reads settle within a realistic allowance");
            if (mockVRF.lastRequestId() != id) return true;
        }
        revert("harness: reads never settled");
    }

    // ---------------------------------------------------------------------
    // Assertions shared by the level-10 drives
    // ---------------------------------------------------------------------

    function _assertBaf(bool turbo, bool earlyActivated) internal {
        assertEq(bafObs.length, 1, "F4: exactly one x0 consolidation observed");
        BafObs memory o = bafObs[0];
        emit log_named_uint("baf stampL", o.stampL);
        emit log_named_uint("baf stampN", o.stampN);
        emit log_named_uint("baf earlyTicketLevel", o.early);
        emit log_named_uint("baf jackpotFlags", o.flags);
        emit log_named_uint("most mining calls in a day", maxDayCalls);
        emit log_named_uint("whale buys", whaleBuys);
        emit log_named_uint("foil buys", foilBuys);
        emit log_named_uint("box buys", boxBuys);
        emit log_named_uint("ticket buys", ticketBuys);
        assertEq(o.lvl, 10, "F4: the consolidation is level 10's");
        assertTrue(o.okL && o.okN, "F4: both buffers prepare");
        assertEq(o.postL, 10, "F4: parity(L) stamped L after the call");
        assertEq(o.postN, 11, "F4: parity(L+1) stamped L+1 after the call");
        assertEq(o.prevQueues, 0, "F4: the L-1 queues are empty before the call");
        assertEq(o.staleL, 0, "F4: a stale parity(L) buffer holds no queue");
        assertEq(o.staleN, 0, "F4: a stale parity(L+1) buffer holds no queue");
        assertTrue(o.stampL == 10 || o.stampL == 8, "F4: parity(L) holds L or L-2");
        assertTrue(o.stampN == 11 || o.stampN == 9, "F4: parity(L+1) holds L+1 or L-1");
        assertTrue(o.idle, "F4: the ticket cursor is idle");
        assertEq(o.flags & 1, turbo ? 1 : 0, "scenario: turbo latch");
        if (earlyActivated) assertEq(o.early, 11, "scenario: next level activated early");
        else assertLt(o.early, 11, "scenario: no early activation of level 11");
    }

    function _assertPerp(uint256 deities, uint256 minClosings) internal {
        assertGe(perpObs.length, minClosings, "F2: transition closes observed");
        emit log_named_uint("perpetual closes observed", perpObs.length);
        for (uint256 i; i < perpObs.length; ++i) {
            PerpObs memory p = perpObs[i];
            assertTrue(p.closed, "F2: the close completes");
            assertTrue(p.inJackpot && p.transition, "F2: observed at the transition close");
            assertEq(p.target, p.lvl + 100, "F2: the target is level + 100");
            assertEq(p.ffLevel, 0, "F2: FF(level) is empty before the close");
            assertEq(p.deities, deities, "F2: deity count");
            assertGe(p.ffTargetAfter, p.deities, "F2: every deity holds a lane at the target");
            assertGe(p.ffTargetAfter, p.ffTargetBefore, "F2: the close only appends");
        }
    }
}

contract ChainPinAdvanceDriven is ChainPinBase {
    function setUp() public {
        _setUpWorld();
        vm.pauseGasMetering();
    }

    /// F1: after every request, including each last-purchase request, GNRUS and the game agree on the level.
    function test_F1_charityLevelTracksGameLevel() public {
        checkCharityLevel = true;
        _driveTurbo(3, 0);
        assertEq(uint256(gnrus.currentLevel()), 3, "GNRUS advanced with the game");
        assertEq(uint256(game.level()), 3);
    }

    /// F3: the real arming block at level 4 (window open, decDayOne, entries level) lets applyDailyWord_g1652 burn
    /// sDGNRS's backing into level 5's decimator round.
    function test_F3_openingBurnAfterRealArming() public {
        _driveTurbo(4, 0);
        assertTrue(game.decWindow(), "the level-4 arming opened the window");
        assertEq(sdgnrsBurns, 1, "sDGNRS burned once on the opening day");
        assertEq(sdgnrsRecorded[5], 1, "and the entry landed in level 5's round");
    }

    /// F3: the opening day is a logical day, not a wall day: a word whose request was pinned before midnight
    /// and applied after it still performs the opening-day burn and enters level 5's round.
    function test_F3_requestPinnedBeforeMidnightStillBurns() public {
        _driveTurbo(5, 4);
        assertTrue(crossedMidnight, "harness: the clock crossed midnight with the arming request in flight");
        assertEq(uint256(game.level()), 5, "the game carried on");
        assertGe(sdgnrsBurns, 1, "the opening-day burn ran after midnight");
        assertEq(sdgnrsRecorded[5], 1, "and the entry landed in level 5's round");
    }

    // ---- F10 ----

    function _f10(uint256 poolWei) internal {
        uint256 cur = sdgnrs.poolBalance(sDGNRS.Pool.Affiliate);
        if (poolWei < cur) {
            vm.prank(address(game));
            sdgnrs.transferFromPool(sDGNRS.Pool.Affiliate, address(0xdead), cur - poolWei);
        } else {
            poolWei = cur;
        }
        uint256 start = sdgnrs.poolBalance(sDGNRS.Pool.Affiliate);
        assertEq(start, poolWei, "fixture: pool set");
        _driveTurbo(1, 0);
        assertTrue(allocationSeen[1], "the bump recorded the level pot");
        emit log_named_uint("affiliate pool before", start);
        emit log_named_uint("top reward paid", rewardSeen[1] ? rewardPaid[1] : 0);
        emit log_named_uint("level pot", allocation[1]);
        uint256 paid = rewardSeen[1] ? rewardPaid[1] : 0;
        uint256 after_ = sdgnrs.poolBalance(sDGNRS.Pool.Affiliate);
        assertEq(after_, start - paid, "F10: the pool fell by exactly the reported amount");
        assertEq(allocation[1], (start - paid) * 250 / 10_000, "F10: the pot is sized off the real remainder");
        if (rewardSeen[1]) assertEq(paid, start * 50 / 10_000, "top affiliate reward");
    }

    function test_F10_emptyAffiliatePool() public {
        _f10(0);
    }

    function test_F10_dustAffiliatePool() public {
        _f10(199);
    }

    function test_F10_oneWeiReward() public {
        _f10(200);
    }

    /// A pool where an off-by-one in the remainder moves the pot by a whole unit.
    function test_F10_roundingEdgePool() public {
        uint256 p = 100_000;
        while ((p - p * 50 / 10_000) % 40 != 0) ++p;
        _f10(p);
    }

    function test_F10_partialAffiliatePool() public {
        _f10(sdgnrs.poolBalance(sDGNRS.Pool.Affiliate) / 3 + 7);
    }

    // ---- F2 / F4 ----

    /// Turbo x0 with 32 deities, whale passes, foil packs and boxes every day.
    function test_F2_F4_turboX0With32Deities() public {
        for (uint24 lvl = 2; lvl <= 10; ++lvl) {
            assertGt(
                TicketQueueStorage.length(address(game), lvl | (uint24(1) << 22)), 0,
                "fixture: FF(level) holds the genesis deities' tickets before it is minted"
            );
        }
        _seedDeities();
        _driveX0(Mode.Turbo, true);
        assertGt(whaleBuys, 0, "harness: whale passes bought");
        assertGt(foilBuys, 0, "harness: foil packs bought");
        assertGt(boxBuys, 0, "harness: boxes bought");
        _assertBaf(true, true);
        _assertPerp(32, 10);
    }

    function test_F4_normalX0() public {
        _driveX0(Mode.Normal, true);
        assertGt(whaleBuys, 0, "harness: whale passes bought");
        assertGt(foilBuys, 0, "harness: foil packs bought");
        _assertBaf(false, false);
        _assertPerp(2, 10);
    }

    function test_F4_normalX0EarlyActivation() public {
        _driveX0(Mode.NormalEarly, true);
        assertGt(whaleBuys, 0, "harness: whale passes bought");
        _assertBaf(false, true);
        _assertPerp(2, 10);
    }
}
