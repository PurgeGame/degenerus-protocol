// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";

/// @title AdvanceLivenessHandler — drives the advance chain and checks a LIVENESS post-condition.
///
/// @notice The bug class: a latch/flag that only a worker's `finished` signal clears, where
///         either a return path discards `finished`, or the caller only invokes the worker
///         while it can still FIND work — leaving "flag set, no work, every entry point
///         reverts" reachable. The handler drives random sequences (ticket/lootbox/foil/whale
///         buys, mid-day lootbox requests as a player or as the CRAPS table, VRF fulfilment
///         with delays and stalls, advanceGame / mineFlip cranks, intra-day and cross-day
///         warps including the pre-reset minute, prize-pool seeding to force turbo and normal
///         last-purchase-day seals) and after EVERY action runs an isolated liveness check.
///
///         THE CHECK (inside vm.snapshotState / revertToState, so it never perturbs the run):
///           1. With VRF cooperating and WITHOUT moving time, fulfil any pending request and
///              crank advanceGame until it reverts (quiescence) or N cranks pass.
///           2. At quiescence the game must be sealed and idle: terminal revert is
///              NotTimeYet, today's word exists, rngLocked is false, LR_MID_DAY == 0,
///              ticketsFullyProcessed is true (nothing staged without a worker), and
///              advanceDue() agrees (false) with the reverting advance.
///           3. requestLootboxRng from a fresh account must not revert MidDayActive /
///              RngNotReady / RngLocked (only the legitimate economic/timing refusals).
///           4. PROBE: requestLootboxRng as the CRAPS table (exempt from the pending-value
///              gates, so it issues whenever the timing gates allow). On success, fulfil and
///              crank to quiescence again and re-run step 2 — every mid-day cycle must
///              return to idle.
///           Every Kth action additionally runs the same check after warping into the next
///           day: the next day must seal within N cranks.
///         A violation stores a decoded state snapshot; the invariant asserts none occurred.
contract AdvanceLivenessHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // ---- storage layout (forge inspect DegenerusGame storageLayout) ----
    uint256 private constant SLOT0 = 0;
    uint256 private constant PRIZE_POOLS_SLOT = 2;
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant TICKET_QUEUE_SLOT = 12;
    uint256 private constant LEVEL_PRIZE_POOL_SLOT = 23;
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;
    uint256 private constant FOIL_CURSOR_SLOT = 62; // foilDrainDay @4 (3B), foilLastResolveDay @7 (3B)
    uint256 private constant LR_MID_DAY_SHIFT = 224;
    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;
    uint24 private constant TICKET_FAR_FUTURE_BIT = uint24(1) << 22;
    uint8 private constant JACKPOT_TURBO = 1;

    uint256 private constant DAY_OFFSET = 82_620;
    uint256 private constant MIDDAY_RNG_STALL_TIMEOUT = 4 hours;
    uint256 private constant DAILY_RNG_RETRY_TIMEOUT = 12 hours;

    uint256 public constant MAX_CRANKS = 250;
    uint256 public constant NEXT_DAY_CHECK_EVERY = 4;

    // ---- error selectors (AdvanceModule / Storage) ----
    bytes4 private constant E_MID_DAY_ACTIVE = bytes4(keccak256("MidDayActive()"));
    bytes4 private constant E_PRE_RESET = bytes4(keccak256("PreResetWindow()"));
    bytes4 private constant E_INSUFFICIENT_LINK = bytes4(keccak256("InsufficientLink()"));
    bytes4 private constant E_NO_PENDING = bytes4(keccak256("NoPendingLootbox()"));
    bytes4 private constant E_BELOW_THRESHOLD = bytes4(keccak256("BelowThreshold()"));
    bytes4 private constant E_RNG_IN_FLIGHT = bytes4(keccak256("RngInFlight()"));
    bytes4 private constant E_GAS_TOO_HIGH = bytes4(keccak256("GasTooHigh()"));
    bytes4 private constant E_NOT_TIME_YET = bytes4(keccak256("NotTimeYet()"));
    bytes4 private constant E_RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes4 private constant E_RNG_LOCKED = bytes4(keccak256("RngLocked()"));

    // ---- violation codes ----
    uint8 public constant V_NONE = 0;
    uint8 public constant V_NO_QUIESCENCE = 1; // N cranks all succeeded
    uint8 public constant V_TERMINAL_REVERT = 2; // quiesced on something other than NotTimeYet
    uint8 public constant V_LATCH_STUCK = 3; // LR_MID_DAY set at quiescence
    uint8 public constant V_NOT_SEALED = 4; // today's word missing / rng still locked at quiescence
    uint8 public constant V_STAGED_NO_WORKER = 5; // !ticketsFullyProcessed while idle and sealed
    uint8 public constant V_ADVANCE_DUE_LIES = 6; // advanceDue() true but advanceGame reverts
    uint8 public constant V_REQUEST_BLOCKED = 7; // requestLootboxRng blocked by a liveness gate

    struct Violation {
        uint8 code;
        bytes4 selector; // terminal advance revert, or the request revert for V_REQUEST_BLOCKED
        uint8 phase; // 0 same-day, 1 after CRAPS probe, 2 next-day, 3 next-day after probe
        uint256 cranks;
        uint24 level;
        uint24 wallDay;
        uint24 dailyIdx;
        bool jackpotPhase;
        bool lastPurchaseDay;
        bool turbo;
        bool rngLocked;
        bool ticketsFullyProcessed;
        uint256 midDayLatch;
        uint256 rngRequestTime;
        uint256 wordToday;
        bool advanceDue;
        uint256 readLenL;
        uint256 readLenL1;
        uint256 readLenL2;
        uint256 ffLenL1;
        uint256 ffLenL2;
        bool foilPending;
        uint256 timestamp;
        uint256 actionNo;
        string lastAction;
    }

    Violation internal _firstViolation;
    uint256 public ghost_violations;

    // ---- coverage ghosts ----
    uint256 public ghost_actions;
    uint256 public ghost_checks;
    uint256 public ghost_nextDayChecks;
    uint256 public ghost_probeRequests; // CRAPS probe issued a mid-day request inside a check
    uint256 public ghost_probeOnLpd; // ... while lastPurchaseDay latched (non-turbo)
    uint256 public ghost_probeOnLpdFrozenPool; // ... with the frozen next-level pool non-empty
    uint256 public ghost_skippedGameOver;
    uint256 public ghost_maxCranks;
    uint256 public ghost_lpdSeals; // lastPurchaseDay false -> true
    uint256 public ghost_turboSeals; // ... with JACKPOT_TURBO
    uint256 public ghost_normalSeals;
    uint256 public ghost_levelTransitions;
    uint256 public ghost_x9Levels;
    uint256 public ghost_x0Levels;
    uint256 public ghost_maxLevel;
    uint256 public ghost_middayRequests; // real-run requestLootboxRng successes
    uint256 public ghost_middayLatchSet; // ... that set the latch
    uint256 public ghost_middayLatchOnLpd; // ... on a (non-turbo) last purchase day
    uint256 public ghost_middayLatchOnLpdFrozenPool; // ... with a non-empty frozen pool
    uint256 public ghost_middayAsCraps;
    uint256 public ghost_vrfStalls; // warped past a stall timeout with a request outstanding
    uint256 public ghost_vrfStallsDaily;
    uint256 public ghost_vrfStallsMidday;
    uint256 public ghost_foilBuys;
    uint256 public ghost_foilPendingMidday; // foil drain pending while the mid-day latch is set
    uint256 public ghost_whalePasses;
    uint256 public ghost_ticketBuys;
    uint256 public ghost_lootboxBuys;
    uint256 public ghost_poolSeeds;
    uint256 public ghost_dayCrossings;
    uint256 public ghost_preResetWarps;
    uint256 public ghost_biasedRuns;
    uint256 public ghost_biasedReachedLpd;
    uint256 public ghost_gameOver;

    // real-run observation memory
    uint24 private _prevLevel;
    bool private _prevLpd;

    address[] public actors;
    string private _lastAction;

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;
        for (uint256 i = 0; i < numActors; i++) {
            address a = address(uint160(0x7A0000 + i));
            actors.push(a);
            vm.deal(a, 1_000_000 ether);
        }
    }

    // =====================================================================
    // Modifier: every action is followed by the observation + liveness check
    // =====================================================================

    modifier action(string memory name) {
        _lastAction = name;
        ghost_actions++;
        _;
        _observe();
        _check(false);
        if (ghost_actions % NEXT_DAY_CHECK_EVERY == 0) {
            _check(true);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // =====================================================================
    // Actions
    // =====================================================================

    function actBuyTickets(uint256 actorSeed, uint256 qtySeed) external action("buyTickets") {
        _buyTickets(_actor(actorSeed), bound(qtySeed, 1, 40));
    }

    function actBuyLootbox(uint256 actorSeed, uint256 ethSeed) external action("buyLootbox") {
        _buyLootbox(_actor(actorSeed), bound(ethSeed, 0.5 ether, 4 ether));
    }

    function actFoil(uint256 actorSeed) external action("foil") {
        _buyFoil(_actor(actorSeed));
    }

    function actWhalePass(uint256 actorSeed) external action("whalePass") {
        _buyWhalePass(_actor(actorSeed));
    }

    function actOpenBoxes(uint256 n) external action("openBoxes") {
        if (game.gameOver()) return;
        try game.openBoxes(bound(n, 1, 20)) {} catch {}
    }

    /// Mid-day lootbox request from a random player (after optionally topping up the pending
    /// lootbox value) or as the CRAPS table.
    function actMiddayRequest(uint256 actorSeed, uint256 mode) external action("middayRequest") {
        mode = mode % 3;
        address a = _actor(actorSeed);
        if (mode == 1) _buyLootbox(a, 2 ether);
        _request(mode == 2 ? ContractAddresses.CRAPS : a);
    }

    function actFulfill() external action("fulfill") {
        _fulfillPending();
    }

    /// Crank n times. Bit i of `bits`: fulfil before crank i; bit (i+32): mineFlip instead of advanceGame.
    function actCrank(uint256 n, uint256 bits) external action("crank") {
        n = bound(n, 1, 40);
        for (uint256 i = 0; i < n; i++) {
            if ((bits >> (i % 32)) & 1 != 0) _fulfillPending();
            bool ok;
            if ((bits >> (32 + (i % 32))) & 1 != 0) {
                vm.prank(_actor(bits >> 64));
                (ok,) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            } else {
                (ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            }
            if (!ok && (bits >> 100) & 1 == 0) break;
        }
    }

    /// Crank to quiescence with VRF cooperating (the "honest keeper" day runner).
    function actRunToIdle(uint256 useMineFlip) external action("runToIdle") {
        _runToIdle(useMineFlip & 1 == 1);
    }

    function actWarpWithinDay(uint256 secs) external action("warpWithinDay") {
        vm.warp(block.timestamp + bound(secs, 1 minutes, 8 hours));
    }

    /// Warp into the next day at an offset; mode selects a near-boundary / pre-reset shape.
    function actNextDay(uint256 offset, uint256 mode) external action("nextDay") {
        uint256 start = _nextDayStart();
        mode = mode % 4;
        if (mode == 0) {
            vm.warp(start + bound(offset, 0, 23 hours));
        } else if (mode == 1) {
            vm.warp(start + bound(offset, 0, 30 minutes));
        } else if (mode == 2) {
            // into the pre-reset minute of the CURRENT day (not across it)
            vm.warp(start - bound(offset, 1, 60));
            ghost_preResetWarps++;
            return;
        } else {
            // skip a whole day (gap day)
            vm.warp(start + 1 days + bound(offset, 0, 12 hours));
        }
        ghost_dayCrossings++;
    }

    /// VRF stall: warp past a stall timeout WITHOUT fulfilling.
    function actStall(uint256 kind) external action("stall") {
        bool pending = _pendingUnfulfilled();
        kind = kind % 3;
        uint256 dt = kind == 0
            ? MIDDAY_RNG_STALL_TIMEOUT + 1
            : (kind == 1 ? DAILY_RNG_RETRY_TIMEOUT + 1 : DAILY_RNG_RETRY_TIMEOUT + 1 days);
        if (pending) {
            ghost_vrfStalls++;
            if (game.rngLocked()) ghost_vrfStallsDaily++;
            else ghost_vrfStallsMidday++;
        }
        vm.warp(block.timestamp + dt);
    }

    /// Push the next prize pool over the level target (turbo if on purchase day <=1,
    /// normal evening latch otherwise).
    function actSeedPool(uint256 extra) external action("seedPool") {
        _seedNextPool(bound(extra, 0, 5 ether));
    }

    /// Biased compound: reach a sealed NORMAL last purchase day with the frozen next-level
    /// pool non-empty and tickets on the write side, then fire a mid-day request, fulfil and
    /// drain it through mineFlip/advanceGame. The liveness post-condition then judges it.
    function actLastPurchaseDayMidday(uint256 seed) external action("lastPurchaseDayMidday") {
        ghost_biasedRuns++;
        if (game.gameOver()) return;
        address a = _actor(seed);
        // finish whatever is outstanding today
        _runToIdle(false);
        (uint24 lvl, bool inJp, bool lpd, bool locked,) = game.purchaseInfo();
        if (inJp || locked) {
            // walk out of the jackpot phase (bounded)
            for (uint256 d = 0; d < 8; d++) {
                (, inJp,, locked,) = game.purchaseInfo();
                if (!inJp && !locked) break;
                vm.warp(_nextDayStart() + 1 hours);
                _runToIdle(false);
            }
            (lvl, inJp, lpd, locked,) = game.purchaseInfo();
            if (inJp || locked || game.gameOver()) return;
        }
        if (!lpd) {
            // populate far-future keys (frozen pool for level+2) before the seal
            _buyWhalePass(a);
            _buyTickets(a, 8);
            // ensure the seal is a NORMAL (evening) one when seed bit 0 is clear: move past
            // purchase day 1 before seeding.
            if (seed & 1 == 0) {
                vm.warp(_nextDayStart() + 1 hours);
                _runToIdle(false);
                vm.warp(_nextDayStart() + 1 hours);
                _runToIdle(false);
            }
            _seedNextPool(1 ether);
            for (uint256 d = 0; d < 4; d++) {
                vm.warp(_nextDayStart() + 1 hours);
                _runToIdle(false);
                (, inJp, lpd, locked,) = game.purchaseInfo();
                if (lpd || inJp || game.gameOver()) break;
                _seedNextPool(1 ether);
            }
        }
        (lvl, inJp, lpd, locked,) = game.purchaseInfo();
        if (!lpd || inJp || locked || game.gameOver()) return;
        ghost_biasedReachedLpd++;
        // write-side work + pending lootbox value, then the mid-day request
        _buyTickets(a, bound(seed >> 8, 1, 20));
        _buyLootbox(a, 2 ether);
        if ((seed >> 40) & 1 == 1) _buyFoil(_actor(seed >> 16));
        _request((seed >> 32) & 1 == 1 ? ContractAddresses.CRAPS : _actor(seed >> 24));
        _fulfillPending();
        uint256 n = bound(seed >> 48, 1, 30);
        for (uint256 i = 0; i < n; i++) {
            vm.prank(a);
            (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip()"));
            if (!ok) break;
        }
        lvl;
    }

    // =====================================================================
    // The liveness check
    // =====================================================================

    function _check(bool nextDay) internal {
        if (ghost_violations != 0) return; // keep the first counterexample
        if (game.gameOver()) {
            ghost_skippedGameOver++;
            return;
        }
        ghost_checks++;
        if (nextDay) ghost_nextDayChecks++;

        uint256 snap = vm.snapshotState();
        if (nextDay) vm.warp(_nextDayStart() + 1 hours);

        Violation memory v;
        uint256 probeFlags; // bit0 probe issued, bit1 on lpd non-turbo, bit2 frozen pool non-empty
        uint256 maxCr;
        {
            (bool quiet, bytes4 sel, uint256 cranks) = _crankToQuiescence();
            maxCr = cranks;
            if (!game.gameOver()) v = _judge(quiet, sel, cranks, nextDay ? 2 : 0);
        }
        if (v.code == V_NONE && !game.gameOver()) {
            // (3) a fresh player's mid-day request must not hit a liveness gate
            address fresh = address(uint160(0xF4E5400));
            vm.prank(fresh);
            (bool ok, bytes memory ret) = address(game).call(abi.encodeWithSignature("requestLootboxRng()"));
            if (ok) {
                // a fresh account with no boxes can only pass via the pending/credit gates; fine.
            } else if (!_requestRevertAllowed(_sel(ret))) {
                v = _snapshot(V_REQUEST_BLOCKED, _sel(ret), 0, nextDay ? 2 : 0);
            }
        }
        if (v.code == V_NONE && !game.gameOver()) {
            // (4) CRAPS probe: a full mid-day cycle must return to idle
            (, bool inJp, bool lpd,,) = game.purchaseInfo();
            bool turbo = (uint8(uint256(vm.load(address(game), bytes32(SLOT0))) >> 184) & JACKPOT_TURBO) != 0;
            uint24 lvl = _level();
            bool ffNonEmpty = _queueLen(lvl + 2 | TICKET_FAR_FUTURE_BIT) != 0;
            vm.prank(ContractAddresses.CRAPS);
            (bool ok,) = address(game).call(abi.encodeWithSignature("requestLootboxRng()"));
            if (ok) {
                probeFlags = 1;
                if (lpd && !inJp && !turbo && _midDayLatch() != 0) {
                    probeFlags |= 2;
                    if (ffNonEmpty) probeFlags |= 4;
                }
                (bool quiet, bytes4 sel, uint256 cranks) = _crankToQuiescence();
                if (cranks > maxCr) maxCr = cranks;
                if (!game.gameOver()) v = _judge(quiet, sel, cranks, nextDay ? 3 : 1);
            }
        }

        vm.revertToStateAndDelete(snap);

        if (maxCr > ghost_maxCranks) ghost_maxCranks = maxCr;
        if (probeFlags & 1 != 0) ghost_probeRequests++;
        if (probeFlags & 2 != 0) ghost_probeOnLpd++;
        if (probeFlags & 4 != 0) ghost_probeOnLpdFrozenPool++;
        if (v.code != V_NONE) {
            v.actionNo = ghost_actions;
            v.lastAction = _lastAction;
            _firstViolation = v;
            ghost_violations++;
        }
    }

    /// Fulfil + advanceGame until it reverts or MAX_CRANKS successes.
    function _crankToQuiescence() internal returns (bool quiet, bytes4 sel, uint256 cranks) {
        for (cranks = 0; cranks < MAX_CRANKS; cranks++) {
            if (game.gameOver()) return (true, bytes4(0), cranks);
            _fulfillPending();
            (bool ok, bytes memory ret) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) return (true, _sel(ret), cranks);
        }
        return (false, bytes4(0), cranks);
    }

    function _judge(bool quiet, bytes4 sel, uint256 cranks, uint8 phase) internal view returns (Violation memory v) {
        if (!quiet) return _snapshot(V_NO_QUIESCENCE, sel, cranks, phase);
        if (_midDayLatch() != 0) return _snapshot(V_LATCH_STUCK, sel, cranks, phase);
        if (sel != E_NOT_TIME_YET) return _snapshot(V_TERMINAL_REVERT, sel, cranks, phase);
        uint24 wallDay = game.currentDayView();
        if (_wordByDay(wallDay) == 0 || game.rngLocked()) return _snapshot(V_NOT_SEALED, sel, cranks, phase);
        if (!_ticketsFullyProcessed() && _rngRequestTime() == 0) {
            return _snapshot(V_STAGED_NO_WORKER, sel, cranks, phase);
        }
        if (game.advanceDue()) return _snapshot(V_ADVANCE_DUE_LIES, sel, cranks, phase);
    }

    function _requestRevertAllowed(bytes4 s) internal pure returns (bool) {
        return s == E_NO_PENDING || s == E_BELOW_THRESHOLD || s == E_RNG_IN_FLIGHT || s == E_PRE_RESET
            || s == E_INSUFFICIENT_LINK || s == E_GAS_TOO_HIGH;
    }

    function _snapshot(uint8 code, bytes4 sel, uint256 cranks, uint8 phase) internal view returns (Violation memory v) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(SLOT0)));
        uint24 lvl = uint24(s0 >> 96);
        v.code = code;
        v.selector = sel;
        v.phase = phase;
        v.cranks = cranks;
        v.level = lvl;
        v.wallDay = game.currentDayView();
        v.dailyIdx = uint24(s0 >> 24);
        v.jackpotPhase = uint8(s0 >> 120) != 0;
        v.lastPurchaseDay = uint8(s0 >> 136) != 0;
        v.turbo = (uint8(s0 >> 184) & JACKPOT_TURBO) != 0;
        v.rngLocked = uint8(s0 >> 152) != 0;
        v.ticketsFullyProcessed = uint8(s0 >> 192) != 0;
        v.midDayLatch = _midDayLatch();
        v.rngRequestTime = uint48(s0 >> 48);
        v.wordToday = _wordByDay(v.wallDay);
        v.advanceDue = game.advanceDue();
        v.readLenL = _queueLen(_readKey(lvl));
        v.readLenL1 = _queueLen(_readKey(lvl + 1));
        v.readLenL2 = _queueLen(_readKey(lvl + 2));
        v.ffLenL1 = _queueLen((lvl + 1) | TICKET_FAR_FUTURE_BIT);
        v.ffLenL2 = _queueLen((lvl + 2) | TICKET_FAR_FUTURE_BIT);
        v.foilPending = _foilPending();
        v.timestamp = block.timestamp;
    }

    function firstViolation() external view returns (Violation memory) {
        return _firstViolation;
    }

    // =====================================================================
    // Real-run observation (coverage ghosts)
    // =====================================================================

    function _observe() internal {
        if (game.gameOver()) {
            ghost_gameOver++;
            return;
        }
        uint256 s0 = uint256(vm.load(address(game), bytes32(SLOT0)));
        uint24 lvl = uint24(s0 >> 96);
        bool inJp = uint8(s0 >> 120) != 0;
        bool lpd = uint8(s0 >> 136) != 0 && !inJp;
        bool turbo = (uint8(s0 >> 184) & JACKPOT_TURBO) != 0;
        if (lvl > _prevLevel) {
            ghost_levelTransitions += lvl - _prevLevel;
            if (lvl % 10 == 9) ghost_x9Levels++;
            if (lvl % 10 == 0) ghost_x0Levels++;
            if (lvl > ghost_maxLevel) ghost_maxLevel = lvl;
        }
        if (lpd && !_prevLpd) {
            ghost_lpdSeals++;
            if (turbo) ghost_turboSeals++;
            else ghost_normalSeals++;
        }
        if (_midDayLatch() != 0 && _foilPending()) ghost_foilPendingMidday++;
        _prevLevel = lvl;
        _prevLpd = lpd;
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _request(address who) internal {
        bool latchBefore = _midDayLatch() != 0;
        (uint24 lvl, bool inJp, bool lpd,,) = game.purchaseInfo();
        bool ffNonEmpty = _queueLen(lvl + 2 | TICKET_FAR_FUTURE_BIT) != 0;
        vm.prank(who);
        (bool ok,) = address(game).call(abi.encodeWithSignature("requestLootboxRng()"));
        if (!ok) return;
        ghost_middayRequests++;
        if (who == ContractAddresses.CRAPS) ghost_middayAsCraps++;
        if (!latchBefore && _midDayLatch() != 0) {
            ghost_middayLatchSet++;
            if (lpd && !inJp) {
                ghost_middayLatchOnLpd++;
                if (ffNonEmpty) ghost_middayLatchOnLpdFrozenPool++;
            }
        }
    }

    function _runToIdle(bool useMineFlip) internal {
        for (uint256 i = 0; i < MAX_CRANKS; i++) {
            if (game.gameOver()) return;
            _fulfillPending();
            bool ok;
            if (useMineFlip) {
                vm.prank(actors[0]);
                (ok,) = address(game).call(abi.encodeWithSignature("mineFlip()"));
                if (ok && !game.advanceDue()) {
                    (ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                }
            } else {
                (ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            }
            if (!ok) return;
        }
    }

    function _buyTickets(address a, uint256 tickets) internal {
        if (game.gameOver()) return;
        (,,,, uint256 priceWei) = game.purchaseInfo();
        vm.prank(a);
        try game.purchase{value: priceWei * tickets}(a, tickets * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {
            ghost_ticketBuys++;
        } catch {}
    }

    function _buyLootbox(address a, uint256 amount) internal {
        if (game.gameOver()) return;
        vm.prank(a);
        try game.purchase{value: amount}(a, 0, BoxOrderLib.boCustom(amount), bytes32(0), MintPaymentKind.DirectEth, false) {
            ghost_lootboxBuys++;
        } catch {}
    }

    function _buyFoil(address a) internal {
        if (game.gameOver()) return;
        (,,,, uint256 priceWei) = game.purchaseInfo();
        vm.prank(a);
        // overpay is credited to the payer's afking balance, never reverts
        try game.purchase{value: priceWei * 80}(a, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true) {
            ghost_foilBuys++;
        } catch {}
    }

    function _buyWhalePass(address a) internal {
        if (game.gameOver()) return;
        vm.prank(a);
        try game.purchaseWhalePass{value: 10 ether}(a, 1, bytes32(0)) {
            ghost_whalePasses++;
        } catch {}
    }

    function _seedNextPool(uint256 extra) internal {
        if (game.gameOver()) return;
        uint24 lvl = _level();
        uint256 target = uint256(vm.load(address(game), keccak256(abi.encode(uint256(lvl), LEVEL_PRIZE_POOL_SLOT))));
        uint256 want = target + 1 ether + extra;
        uint256 packed = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_SLOT)));
        uint256 cur = packed & type(uint128).max;
        if (cur >= want) return;
        vm.store(address(game), bytes32(PRIZE_POOLS_SLOT), bytes32((packed & ~uint256(type(uint128).max)) | want));
        vm.deal(address(game), address(game).balance + (want - cur));
        ghost_poolSeeds++;
    }

    function _pendingUnfulfilled() internal view returns (bool) {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return false;
        (,, bool fulfilled) = vrf.pendingRequests(reqId);
        return !fulfilled;
    }

    function _fulfillPending() internal {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;
        (,, bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode(block.timestamp, reqId, "liveness")));
        try vrf.fulfillRandomWords(reqId, word) {} catch {}
    }

    function _nextDayStart() internal view returns (uint256) {
        uint256 ts = block.timestamp;
        return ts - ((ts - DAY_OFFSET) % 1 days) + 1 days;
    }

    function _sel(bytes memory ret) internal pure returns (bytes4 s) {
        if (ret.length < 4) return bytes4(0);
        assembly {
            s := mload(add(ret, 32))
        }
    }

    function _level() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(SLOT0))) >> 96);
    }

    function _ticketsFullyProcessed() internal view returns (bool) {
        return (uint256(vm.load(address(game), bytes32(SLOT0))) >> 192) & 1 != 0;
    }

    function _rngRequestTime() internal view returns (uint256) {
        return uint48(uint256(vm.load(address(game), bytes32(SLOT0))) >> 48);
    }

    function _midDayLatch() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(LOOTBOX_RNG_PACKED_SLOT))) >> LR_MID_DAY_SHIFT) & 0xFF;
    }

    function _wordByDay(uint24 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), RNG_WORD_BY_DAY_SLOT))));
    }

    function _queueLen(uint24 key) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(key), TICKET_QUEUE_SLOT))));
    }

    function _readKey(uint24 lvl) internal view returns (uint24) {
        bool writeSlot = (uint256(vm.load(address(game), bytes32(SLOT0))) >> 200) & 1 != 0;
        return writeSlot ? lvl : lvl | TICKET_SLOT_BIT;
    }

    function _foilPending() internal view returns (bool) {
        uint256 s = uint256(vm.load(address(game), bytes32(FOIL_CURSOR_SLOT)));
        uint24 dd = uint24(s >> 32);
        uint24 last = uint24(s >> 56);
        if (last == 0 || dd > last) return false;
        return _wordByDay(dd) != 0;
    }
}
